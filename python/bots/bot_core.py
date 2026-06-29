#!/data/data/com.termux/files/usr/bin/python3
# ============================================================
#  termux-ai-stack · bot_core.py
#  Bot Telegram avanzado — memoria individual + cola FIFO
#
#  RUTAS:
#    Script : ~/bots/scripts/bot_core.py
#    BD     : ~/bots/db/bot_memoria.db
#
#  USO DESDE n8n (Execute Command):
#    python3 ~/bots/scripts/bot_core.py enqueue \
#      --user_id 123456789 \
#      --chat_id 123456789 \
#      --mensaje "Hola bot"
#
#    python3 ~/bots/scripts/bot_core.py stats
#    python3 ~/bots/scripts/bot_core.py clear --user_id 123456789
#
#  REGLAS ARM64:
#    - Sin DEFAULT (datetime('now')) en SQLite → datetime.now() explícito
#    - Sin import requests → urllib.request builtin
#    - Sin /tmp → $HOME/
#
#  VERSIÓN: 1.0.0 | Junio 2026
# ============================================================

import os
import sys
import json
import sqlite3
import argparse
from datetime import datetime
from urllib import request as ureq
from urllib.error import URLError

# ── Rutas base ────────────────────────────────────────────────
HOME      = os.path.expanduser("~")
DB_PATH   = os.path.join(HOME, "bots", "db", "bot_memoria.db")
OLLAMA_URL = "http://127.0.0.1:11434/api/generate"

# ── Config fija del bot ────────────────────────────────────────
# Para cambiarla en el futuro: mover a tabla config en BD
BOT_CONFIG = {
    "modelo":      "gemma3:4b",
    "system":      (
        "Eres un asistente de IA directo, técnico y conciso. "
        "Responde siempre en español. "
        "No repitas el historial, solo responde al último mensaje del usuario. "
        "Si no sabes algo, dilo claramente sin inventar."
    ),
    "temperatura": 0.7,
    "top_p":       0.9,
    "top_k":       40,
    "num_predict": 400,
    "num_ctx":     4096,
    "ram_msgs":    4,    # mensajes activos en contexto por usuario
    "disk_msgs":   50,   # máximo histórico en disco por usuario
}

# ── Output helpers ─────────────────────────────────────────────
def ok(data: dict):
    print(json.dumps({"status": "ok", **data}, ensure_ascii=False))
    sys.exit(0)

def fail(msg: str, code: int = 1):
    print(json.dumps({"status": "error", "message": msg}, ensure_ascii=False))
    sys.exit(code)

# ── SQLite — init BD ───────────────────────────────────────────
def get_conn() -> sqlite3.Connection:
    """Abre conexión y garantiza que todas las tablas existen."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    # Tabla usuarios — uno por user_id de Telegram
    conn.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id         TEXT    NOT NULL UNIQUE,
            nombre          TEXT,
            fecha_registro  TEXT    NOT NULL
        )
    """)

    # Tabla historial — memoria individual por user_id
    # chat_id guardado para soporte futuro de grupos
    conn.execute("""
        CREATE TABLE IF NOT EXISTS historial (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id  TEXT    NOT NULL,
            chat_id  TEXT    NOT NULL,
            rol      TEXT    NOT NULL,
            content  TEXT    NOT NULL,
            modelo   TEXT,
            fecha    TEXT    NOT NULL
        )
    """)
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_hist_user ON historial(user_id)"
    )

    # Tabla jobs — cola FIFO multiusuario
    # status: pending → processing → done | error
    conn.execute("""
        CREATE TABLE IF NOT EXISTS jobs (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id       TEXT    NOT NULL,
            chat_id       TEXT    NOT NULL,
            mensaje       TEXT    NOT NULL,
            status        TEXT    NOT NULL DEFAULT 'pending',
            respuesta     TEXT,
            creado_en     TEXT    NOT NULL,
            procesado_en  TEXT
        )
    """)
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_jobs_user ON jobs(user_id)"
    )

    conn.commit()
    return conn

# ── Usuarios ───────────────────────────────────────────────────
def registrar_usuario(conn, user_id: str, nombre: str = None):
    """Registra usuario si no existe. Idempotente."""
    existe = conn.execute(
        "SELECT id FROM users WHERE user_id=?", (user_id,)
    ).fetchone()
    if not existe:
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        conn.execute(
            "INSERT INTO users (user_id, nombre, fecha_registro) VALUES (?,?,?)",
            (user_id, nombre or user_id, now)
        )
        conn.commit()

# ── Historial ──────────────────────────────────────────────────
def get_historial(conn, user_id: str, limit: int) -> list:
    """Retorna los últimos N mensajes del usuario como lista de dicts."""
    rows = conn.execute(
        """SELECT rol, content FROM historial
           WHERE user_id=? ORDER BY id DESC LIMIT ?""",
        (user_id, limit)
    ).fetchall()
    return list(reversed(rows))

def guardar_turno(conn, user_id: str, chat_id: str,
                  user_msg: str, bot_msg: str, modelo: str):
    """Guarda un turno completo (user + assistant). Trimea si supera disk_msgs."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn.execute(
        """INSERT INTO historial (user_id, chat_id, rol, content, modelo, fecha)
           VALUES (?,?,?,?,?,?)""",
        (user_id, chat_id, "user", user_msg, None, now)
    )
    conn.execute(
        """INSERT INTO historial (user_id, chat_id, rol, content, modelo, fecha)
           VALUES (?,?,?,?,?,?)""",
        (user_id, chat_id, "assistant", bot_msg, modelo, now)
    )
    conn.commit()

    # Trim: si hay más de disk_msgs para este usuario, eliminar los más viejos
    total = conn.execute(
        "SELECT COUNT(*) FROM historial WHERE user_id=?", (user_id,)
    ).fetchone()[0]
    limite = BOT_CONFIG["disk_msgs"]
    if total > limite:
        exceso = total - limite
        ids = [
            str(r[0]) for r in conn.execute(
                """SELECT id FROM historial WHERE user_id=?
                   ORDER BY id ASC LIMIT ?""",
                (user_id, exceso)
            ).fetchall()
        ]
        conn.execute(
            "DELETE FROM historial WHERE id IN ({})".format(",".join(ids))
        )
        conn.commit()

# ── Cola FIFO ──────────────────────────────────────────────────
def encolar_mensaje(conn, user_id: str, chat_id: str, mensaje: str) -> int:
    """Inserta job en la cola. Retorna el job_id."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cur = conn.execute(
        """INSERT INTO jobs (user_id, chat_id, mensaje, status, creado_en)
           VALUES (?,?,?,?,?)""",
        (user_id, chat_id, mensaje, "pending", now)
    )
    conn.commit()
    return cur.lastrowid

def tomar_job_pendiente(conn, job_id: int) -> sqlite3.Row:
    """Marca job como 'processing' y lo retorna."""
    conn.execute(
        "UPDATE jobs SET status='processing' WHERE id=?", (job_id,)
    )
    conn.commit()
    return conn.execute(
        "SELECT * FROM jobs WHERE id=?", (job_id,)
    ).fetchone()

def completar_job(conn, job_id: int, respuesta: str, error: bool = False):
    """Marca job como 'done' o 'error' y guarda la respuesta."""
    now    = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    status = "error" if error else "done"
    conn.execute(
        """UPDATE jobs SET status=?, respuesta=?, procesado_en=?
           WHERE id=?""",
        (status, respuesta, now, job_id)
    )
    conn.commit()

# ── Ollama ─────────────────────────────────────────────────────
def construir_prompt(historial: list, mensaje_actual: str) -> str:
    """
    Construye el prompt con contexto de historial.
    Formato: 'Usuario: ...\nBot: ...\nUsuario: actual\nBot:'
    """
    lineas = []
    for row in historial:
        prefijo = "Usuario" if row["rol"] == "user" else "Bot"
        lineas.append(f"{prefijo}: {row['content']}")
    lineas.append(f"Usuario: {mensaje_actual}")
    lineas.append("Bot:")
    return "\n".join(lineas)

def llamar_ollama(prompt: str) -> str:
    """
    Llama a Ollama local via urllib (sin requests).
    Retorna la respuesta en texto plano.
    """
    cfg = BOT_CONFIG
    payload = json.dumps({
        "model":  cfg["modelo"],
        "system": cfg["system"],
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": cfg["temperatura"],
            "top_p":       cfg["top_p"],
            "top_k":       cfg["top_k"],
            "num_predict": cfg["num_predict"],
            "num_ctx":     cfg["num_ctx"],
        }
    }).encode("utf-8")

    req = ureq.Request(
        OLLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    try:
        with ureq.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            respuesta = str(data.get("response", "")).strip()
            # Limpiar prefijos que algunos modelos agregan
            for prefijo in ("Bot:", "Assistant:", "Asistente:"):
                if respuesta.lower().startswith(prefijo.lower()):
                    respuesta = respuesta[len(prefijo):].strip()
            return respuesta if respuesta else "No pude generar respuesta. Intenta de nuevo."
    except URLError as e:
        return f"[ERROR Ollama] No se pudo conectar: {e.reason}"
    except Exception as e:
        return f"[ERROR Ollama] {str(e)}"

# ════════════════════════════════════════════════════════════════
#  COMANDOS CLI
# ════════════════════════════════════════════════════════════════

def cmd_enqueue(args):
    """
    Flujo completo: registrar → encolar → procesar → guardar → responder.
    n8n llama este comando y captura el JSON de stdout.
    """
    user_id = str(args.user_id)
    chat_id = str(args.chat_id)
    mensaje = str(args.mensaje).strip()

    if not mensaje:
        fail("Mensaje vacío")

    conn = get_conn()

    # 1. Registrar usuario si es nuevo
    registrar_usuario(conn, user_id, args.nombre)

    # 2. Encolar mensaje
    job_id = encolar_mensaje(conn, user_id, chat_id, mensaje)

    # 3. Marcar como processing
    tomar_job_pendiente(conn, job_id)

    # 4. Leer historial reciente del usuario (ram_msgs)
    historial = get_historial(conn, user_id, BOT_CONFIG["ram_msgs"])

    # 5. Construir prompt con contexto
    prompt = construir_prompt(historial, mensaje)

    # 6. Llamar a Ollama
    respuesta = llamar_ollama(prompt)

    # 7. Guardar turno en historial
    guardar_turno(conn, user_id, chat_id, mensaje, respuesta, BOT_CONFIG["modelo"])

    # 8. Completar job
    completar_job(conn, job_id, respuesta)

    conn.close()

    # 9. Retornar JSON para n8n
    ok({
        "user_id":   user_id,
        "chat_id":   chat_id,
        "job_id":    job_id,
        "respuesta": respuesta,
    })


def cmd_stats(args):
    """Estadísticas de la BD — útil para debug desde menú."""
    conn = get_conn()

    total_users = conn.execute(
        "SELECT COUNT(*) FROM users"
    ).fetchone()[0]

    total_msgs = conn.execute(
        "SELECT COUNT(*) FROM historial"
    ).fetchone()[0]

    total_jobs = conn.execute(
        "SELECT COUNT(*) FROM jobs"
    ).fetchone()[0]

    pending = conn.execute(
        "SELECT COUNT(*) FROM jobs WHERE status='pending'"
    ).fetchone()[0]

    top_users = conn.execute(
        """SELECT user_id, COUNT(*) as c FROM historial
           WHERE rol='user' GROUP BY user_id ORDER BY c DESC LIMIT 5"""
    ).fetchall()

    db_size = os.path.getsize(DB_PATH) if os.path.exists(DB_PATH) else 0

    conn.close()
    ok({
        "usuarios":    total_users,
        "mensajes_bd": total_msgs,
        "jobs_total":  total_jobs,
        "jobs_pending": pending,
        "top_usuarios": [{"user_id": r["user_id"], "mensajes": r["c"]} for r in top_users],
        "bd_bytes":    db_size,
        "bd_kb":       round(db_size / 1024, 1),
    })


def cmd_clear(args):
    """Borra historial de un usuario específico."""
    user_id = str(args.user_id)
    conn = get_conn()
    deleted = conn.execute(
        "DELETE FROM historial WHERE user_id=?", (user_id,)
    ).rowcount
    conn.commit()
    conn.close()
    ok({"user_id": user_id, "mensajes_borrados": deleted})


def cmd_history(args):
    """Muestra historial reciente de un usuario — debug."""
    user_id = str(args.user_id)
    limit   = int(args.limit) if args.limit else 10
    conn    = get_conn()
    rows    = conn.execute(
        """SELECT rol, content, fecha FROM historial
           WHERE user_id=? ORDER BY id DESC LIMIT ?""",
        (user_id, limit)
    ).fetchall()
    conn.close()
    ok({
        "user_id": user_id,
        "mensajes": [
            {"rol": r["rol"], "content": r["content"], "fecha": r["fecha"]}
            for r in reversed(rows)
        ]
    })


# ════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="bot_core.py — Bot Telegram con memoria individual"
    )
    sub = parser.add_subparsers(dest="cmd")

    # enqueue — comando principal llamado por n8n
    p_enq = sub.add_parser("enqueue", help="Procesar mensaje de usuario")
    p_enq.add_argument("--user_id", required=True, help="ID numérico Telegram del usuario")
    p_enq.add_argument("--chat_id", required=True, help="ID del chat Telegram")
    p_enq.add_argument("--mensaje", required=True, help="Texto del mensaje")
    p_enq.add_argument("--nombre",  default=None,  help="Nombre del usuario (opcional)")

    # stats — estadísticas de la BD
    sub.add_parser("stats", help="Estadísticas de uso")

    # clear — borrar historial de un usuario
    p_clr = sub.add_parser("clear", help="Borrar historial de un usuario")
    p_clr.add_argument("--user_id", required=True)

    # history — ver historial de un usuario
    p_hist = sub.add_parser("history", help="Ver historial de un usuario")
    p_hist.add_argument("--user_id", required=True)
    p_hist.add_argument("--limit",   default=10, type=int)

    args = parser.parse_args()

    if not args.cmd:
        parser.print_help()
        sys.exit(1)

    dispatch = {
        "enqueue": cmd_enqueue,
        "stats":   cmd_stats,
        "clear":   cmd_clear,
        "history": cmd_history,
    }
    dispatch[args.cmd](args)


if __name__ == "__main__":
    main()

#!/data/data/com.termux/files/usr/bin/python3
"""
vision_bot.py — Bot de visión para termux-ai-stack
Sesión 8 — BUG 4 FIX + SQLite ARM64 FIX + urllib (sin requests)

Uso directo: python3 vision_bot.py <ruta_imagen> [chat_id] [pregunta]
Desde n8n:   python3 /data/data/com.termux/files/home/vision_bot.py <img> <chat_id>

FIXES aplicados vs versión anterior:
  [BUG 4] redimensionado automático a 512px para imágenes >500KB
  [SQLite] eliminado DEFAULT (datetime('now')) — incompatible con ARM64
  [urllib] reemplazado requests por urllib.request — sin deps externas
"""

import sys
import os
import base64
import sqlite3
import json
import argparse
from urllib import request as ureq
from datetime import datetime

# ── Pillow opcional — requerido para redimensionado (BUG 4) ───
try:
    from PIL import Image
    PILLOW_OK = True
except ImportError:
    PILLOW_OK = False

# ── Config ─────────────────────────────────────────────────────
OLLAMA_URL    = "http://localhost:11434"
VISION_MODEL  = "moondream:1.8b"
TEXT_MODEL    = "qwen2.5:0.5b"
DB_PATH       = os.path.expanduser("~/bot_history.db")
IMG_CACHE_DIR = os.path.expanduser("~/img_cache")

os.makedirs(IMG_CACHE_DIR, exist_ok=True)


def init_db():
    conn = sqlite3.connect(DB_PATH)
    # FIX: sin DEFAULT (datetime('now')) — falla en SQLite ARM64 < 3.38
    conn.execute("""CREATE TABLE IF NOT EXISTS historial (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id      TEXT,
        rol          TEXT,
        content      TEXT,
        tiene_imagen INTEGER DEFAULT 0,
        modelo       TEXT,
        fecha        TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS imagenes_analizadas (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id     TEXT,
        ruta        TEXT,
        descripcion TEXT,
        pregunta    TEXT,
        modelo      TEXT,
        fecha       TEXT
    )""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_chat ON historial(chat_id)")
    conn.commit()
    return conn


def redimensionar(ruta):
    """BUG 4 FIX: redimensiona imágenes >500KB a max 512px antes de enviar a Ollama.
    Sin esto, una imagen de 2.8MB hace timeout garantizado en ARM64."""
    if not PILLOW_OK:
        return ruta  # sin Pillow, usar original (advertencia: puede hacer timeout)
    if os.path.getsize(ruta) <= 500_000:
        return ruta  # ya es pequeña, no necesita resize
    img = Image.open(ruta)
    w, h = img.size
    r = min(512 / w, 512 / h)
    img = img.resize((int(w * r), int(h * r)), Image.LANCZOS)
    tmp = os.path.expanduser("~/vision_tmp.jpg")
    img.save(tmp, "JPEG", quality=80)
    return tmp


def _post_ollama(payload_dict, timeout=300):
    """HTTP POST a Ollama usando urllib — sin dependencia de requests."""
    data = json.dumps(payload_dict).encode("utf-8")
    req = ureq.Request(
        f"{OLLAMA_URL}/api/generate",
        data=data,
        headers={"Content-Type": "application/json"}
    )
    with ureq.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def analizar_imagen(ruta, pregunta, chat_id):
    conn = init_db()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # BUG 4 FIX: redimensionar ANTES de codificar en base64
    ruta_proc = redimensionar(ruta)
    with open(ruta_proc, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()

    # Limpiar archivo temporal si se generó
    tmp = os.path.expanduser("~/vision_tmp.jpg")
    if ruta_proc != ruta and os.path.exists(tmp):
        os.remove(tmp)

    try:
        result = _post_ollama({
            "model": VISION_MODEL,
            "prompt": f"You must respond ONLY in Spanish. {pregunta} Responde en español.",
            "images": [b64],
            "stream": False,
            "options": {"num_predict": 150, "temperature": 0.1}
        })
        descripcion = result.get("response", "").strip()
    except Exception as e:
        descripcion = f"[ERROR Ollama] {e}"

    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,tiene_imagen,modelo,fecha) VALUES (?,?,?,1,?,?)",
        (chat_id, "user", f"[IMAGEN] {pregunta}", None, now)
    )
    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,tiene_imagen,modelo,fecha) VALUES (?,?,?,1,?,?)",
        (chat_id, "assistant", descripcion, VISION_MODEL, now)
    )
    conn.execute(
        "INSERT INTO imagenes_analizadas (chat_id,ruta,descripcion,pregunta,modelo,fecha) VALUES (?,?,?,?,?,?)",
        (chat_id, ruta, descripcion, pregunta, VISION_MODEL, now)
    )
    conn.commit()
    conn.close()
    return descripcion


def chat_texto(chat_id, mensaje):
    conn = init_db()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    hist = conn.execute(
        "SELECT rol, content FROM historial WHERE chat_id=? ORDER BY id DESC LIMIT 4",
        (chat_id,)
    ).fetchall()
    hist = list(reversed(hist))
    context = "\n".join([
        f"{'Usuario' if r == 'user' else 'Bot'}: {c}"
        for r, c in hist[:-1]
    ])
    prompt = f"{context}\nUsuario: {mensaje}\nBot:" if context else mensaje

    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,fecha) VALUES (?,?,?,?)",
        (chat_id, "user", mensaje, now)
    )
    conn.commit()

    try:
        result = _post_ollama({
            "model": TEXT_MODEL,
            "prompt": prompt,
            "stream": False,
            "options": {"num_predict": 100}
        }, timeout=60)
        respuesta = result.get("response", "").strip()
    except Exception as e:
        respuesta = f"[ERROR Ollama] {e}"

    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,modelo,fecha) VALUES (?,?,?,?,?)",
        (chat_id, "assistant", respuesta, TEXT_MODEL, now)
    )
    conn.commit()
    conn.close()
    return respuesta


def get_stats(chat_id=None):
    conn = init_db()
    if chat_id:
        msgs = conn.execute(
            "SELECT COUNT(*) FROM historial WHERE chat_id=?", (chat_id,)
        ).fetchone()[0]
        imgs = conn.execute(
            "SELECT COUNT(*) FROM imagenes_analizadas WHERE chat_id=?", (chat_id,)
        ).fetchone()[0]
        result = {"chat_id": chat_id, "mensajes": msgs, "imagenes": imgs}
    else:
        total = conn.execute("SELECT COUNT(*) FROM historial").fetchone()[0]
        imgs  = conn.execute("SELECT COUNT(*) FROM imagenes_analizadas").fetchone()[0]
        users = conn.execute("SELECT COUNT(DISTINCT chat_id) FROM historial").fetchone()[0]
        result = {"total_mensajes": total, "imagenes_analizadas": imgs, "usuarios": users}
    conn.close()
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Bot de visión para termux-ai-stack"
    )
    parser.add_argument("imagen",   nargs="?", help="Ruta de imagen")
    parser.add_argument("chat_id",  nargs="?", default="test_chat", help="ID del chat")
    parser.add_argument("pregunta", nargs="?",
                        default="¿Qué ves en esta imagen? Responde en español.",
                        help="Pregunta sobre la imagen")
    parser.add_argument("--texto",  help="Mensaje de texto (sin imagen)")
    parser.add_argument("--stats",  action="store_true", help="Ver estadísticas BD")
    args = parser.parse_args()

    if args.stats:
        print(json.dumps(get_stats(), ensure_ascii=False, indent=2))
    elif args.texto:
        print(chat_texto(args.chat_id, args.texto))
    elif args.imagen:
        if not os.path.exists(args.imagen):
            print(f"ERROR: imagen no encontrada: {args.imagen}", file=sys.stderr)
            sys.exit(1)
        print(analizar_imagen(args.imagen, args.pregunta, args.chat_id))
    else:
        parser.print_help()

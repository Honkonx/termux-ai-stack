#!/data/data/com.termux/files/usr/bin/python3
"""
bot_utils.py — Helpers para termux-ai-stack
Uso: from bot_utils import save_message, get_history, img_to_b64

NOTA ARM64: sin DEFAULT (datetime('now')) — fecha se pasa explícita desde Python.
HTTP: urllib builtin en lugar de requests.
"""
import sqlite3, base64, os
from datetime import datetime
from urllib import request as ureq
import json

DB_PATH = os.path.expanduser("~/bot_history.db")

def init_db(db_path=DB_PATH):
    """Inicializa la BD si no existe."""
    conn = sqlite3.connect(db_path)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS history (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id  TEXT NOT NULL,
            rol      TEXT NOT NULL,
            content  TEXT NOT NULL,
            modelo   TEXT,
            fecha    TEXT
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_chat ON history(chat_id)")
    conn.commit()
    conn.close()

def save_message(chat_id, rol, content, modelo=None, db_path=DB_PATH):
    """Guarda un mensaje en el historial."""
    init_db(db_path)
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(db_path)
    conn.execute(
        "INSERT INTO history (chat_id, rol, content, modelo, fecha) VALUES (?,?,?,?,?)",
        (chat_id, rol, content, modelo, now)
    )
    conn.commit()
    conn.close()

def get_history(chat_id, limit=10, db_path=DB_PATH):
    """Devuelve el historial de un chat como lista de dicts."""
    init_db(db_path)
    conn = sqlite3.connect(db_path)
    rows = conn.execute(
        "SELECT rol, content, fecha FROM history WHERE chat_id=? ORDER BY id DESC LIMIT ?",
        (chat_id, limit)
    ).fetchall()
    conn.close()
    return [{"rol": r[0], "content": r[1], "fecha": r[2]} for r in reversed(rows)]

def get_stats(db_path=DB_PATH):
    """Estadísticas generales de la BD."""
    init_db(db_path)
    conn = sqlite3.connect(db_path)
    total   = conn.execute("SELECT COUNT(*) FROM history").fetchone()[0]
    chats   = conn.execute("SELECT COUNT(DISTINCT chat_id) FROM history").fetchone()[0]
    modelos = conn.execute(
        "SELECT modelo, COUNT(*) FROM history WHERE modelo IS NOT NULL GROUP BY modelo"
    ).fetchall()
    conn.close()
    return {"total_mensajes": total, "chats_unicos": chats, "por_modelo": dict(modelos)}

def img_to_b64(path):
    """Convierte imagen a base64 para Ollama API."""
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()

def clear_history(chat_id, db_path=DB_PATH):
    """Borra el historial de un chat específico."""
    conn = sqlite3.connect(db_path)
    conn.execute("DELETE FROM history WHERE chat_id=?", (chat_id,))
    conn.commit()
    conn.close()

def ollama_generate(prompt, model, url="http://localhost:11434", timeout=60):
    """Llama a Ollama /api/generate usando urllib (sin requests)."""
    data = json.dumps({
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_predict": 100}
    }).encode("utf-8")
    req = ureq.Request(
        f"{url}/api/generate",
        data=data,
        headers={"Content-Type": "application/json"}
    )
    with ureq.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read()).get("response", "").strip()

if __name__ == "__main__":
    # Test rápido
    init_db()
    save_message("test_chat", "user", "Hola")
    save_message("test_chat", "assistant", "Hola! ¿En qué te ayudo?", "qwen2.5:0.5b")
    hist = get_history("test_chat")
    print(f"Historial ({len(hist)} mensajes):")
    for m in hist:
        print(f"  [{m['rol']}] {m['content']} — {m['fecha']}")
    stats = get_stats()
    print(f"Stats: {stats}")
    clear_history("test_chat")
    print("Test bot_utils.py: OK")

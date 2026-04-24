#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · TEST 2 — Python solo
#  Valida: versión, pip, librerías clave, SQLite desde Python,
#          lectura de archivos de /sdcard, HTTP con urllib
#
#  NOTA ARM64: DEFAULT (datetime('now')) falla en Python/SQLite
#  en Termux. Usar: fecha TEXT sin DEFAULT + datetime.now() en Python.
#  HTTP: se usa urllib (builtin) en lugar de requests.
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

OK()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
FAIL() { echo -e "  ${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS+1)); }
INFO() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
SKIP() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }
ERRORS=0

clear; echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  TEST 2 — Python solo                   ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""

# ── 1. Versión Python ────────────────────────────────────────
INFO "Verificando Python..."
PY_VER=$(python3 --version 2>/dev/null)
[ -n "$PY_VER" ] && OK "$PY_VER" || { FAIL "python3 no disponible"; exit 1; }

PIP_VER=$(pip --version 2>/dev/null | cut -d' ' -f2)
[ -n "$PIP_VER" ] && OK "pip $PIP_VER" || FAIL "pip no disponible"

# ── 2. Módulos builtin ───────────────────────────────────────
INFO "Verificando módulos builtin..."
python3 -c "import sqlite3; print('sqlite3:', sqlite3.sqlite_version)" 2>/dev/null \
  && OK "sqlite3 builtin: $(python3 -c 'import sqlite3; print(sqlite3.sqlite_version)')" \
  || FAIL "sqlite3 builtin no disponible"

python3 -c "import json, os, sys, pathlib, base64, hashlib, datetime; print('ok')" 2>/dev/null \
  && OK "json, os, sys, pathlib, base64, hashlib, datetime — todos presentes" \
  || FAIL "Módulos builtin faltantes"

python3 -c "import http.server, urllib.request, urllib.parse; print('ok')" 2>/dev/null \
  && OK "http.server, urllib — presentes" \
  || FAIL "urllib no disponible"

# ── 3. Instalar librerías externas ───────────────────────────
echo ""
INFO "Instalando/verificando librerías externas..."

install_pkg() {
  local pkg="$1"
  local import="$2"
  python3 -c "import $import" 2>/dev/null && OK "$pkg ya instalado" && return
  INFO "Instalando $pkg..."
  pip install "$pkg" --break-system-packages -q 2>/dev/null \
    && OK "$pkg instalado" \
    || FAIL "$pkg no se pudo instalar"
}

install_pkg "requests"  "requests"

# ── Pillow: requiere deps nativas en ARM64 ───────────────────
echo -n "  Verificando Pillow..."
python3 -c "import PIL" 2>/dev/null && echo "" && OK "Pillow ya instalado" || {
  echo ""
  INFO "Instalando dependencias nativas para Pillow en ARM64..."
  pkg install -y libjpeg-turbo libpng zlib 2>/dev/null \
    && OK "Dependencias nativas instaladas (libjpeg-turbo, libpng, zlib)" \
    || FAIL "Advertencia en dependencias nativas (puede continuar)"

  INFO "Instalando Pillow..."
  # Intentar con pip normal primero
  pip install Pillow --break-system-packages -q 2>/dev/null \
    && OK "Pillow instalado via pip" \
    || {
      # Fallback: compilar desde fuente con flags ARM64
      INFO "Fallback: compilando Pillow desde fuente..."
      LDFLAGS="-L${PREFIX}/lib" \
      CFLAGS="-I${PREFIX}/include" \
      pip install Pillow --break-system-packages --no-binary Pillow -q 2>/dev/null \
        && OK "Pillow compilado desde fuente" \
        || {
          # Último fallback: pillow-simd (fork optimizado para ARM)
          INFO "Último fallback: pillow-simd..."
          pip install pillow-simd --break-system-packages -q 2>/dev/null \
            && OK "pillow-simd instalado" \
            || FAIL "Pillow no se pudo instalar — los tests de visión usarán base64 directo"
        }
    }
}

# numpy y pandas son opcionales (pesados en ARM64)
python3 -c "import numpy" 2>/dev/null \
  && OK "numpy ya instalado" \
  || SKIP "numpy no instalado (opcional — pip install numpy --break-system-packages)"

python3 -c "import pandas" 2>/dev/null \
  && OK "pandas ya instalado" \
  || SKIP "pandas no instalado (opcional)"

# ── 4. Test SQLite desde Python ──────────────────────────────
echo ""
INFO "Test SQLite desde Python..."
python3 << 'PYEOF'
import sqlite3, os, sys
from datetime import datetime

DB = os.path.expanduser("~/test_python.db")
try:
    conn = sqlite3.connect(DB)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS bot_logs (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            nivel   TEXT,
            mensaje TEXT,
            fecha   TEXT
        )
    """)
    # Insertar con fecha explícita desde Python
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    datos = [
        ("INFO",  "Bot iniciado",              now),
        ("DEBUG", "Conexión a Ollama OK",       now),
        ("INFO",  "Mensaje recibido: hola",     now),
        ("DEBUG", "Respuesta generada en 1.2s", now),
        ("ERROR", "Timeout en query 3",         now),
    ]
    conn.executemany("INSERT INTO bot_logs (nivel, mensaje, fecha) VALUES (?,?,?)", datos)
    conn.commit()

    # Leer
    rows = conn.execute("SELECT nivel, mensaje FROM bot_logs ORDER BY id").fetchall()
    print(f"  Filas insertadas: {len(rows)}")
    for nivel, msg in rows:
        print(f"    [{nivel:5}] {msg}")

    # Filtrar por nivel
    errores = conn.execute("SELECT COUNT(*) FROM bot_logs WHERE nivel='ERROR'").fetchone()[0]
    print(f"  Errores en log: {errores}")

    conn.close()
    os.remove(DB)
    print("  RESULTADO: OK")
except Exception as e:
    print(f"  RESULTADO: FAIL — {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
[ $? -eq 0 ] && OK "SQLite desde Python funciona" || FAIL "SQLite desde Python falló"

# ── 5. Test leer archivo de /sdcard ──────────────────────────
echo ""
INFO "Test acceso a /sdcard..."
if [ -d "/sdcard/Download" ]; then
  python3 << 'PYEOF'
import os, pathlib

sdcard = pathlib.Path("/sdcard/Download")
files = list(sdcard.iterdir())[:5]
print(f"  Archivos en /sdcard/Download (primeros 5):")
for f in files:
    size = f.stat().st_size if f.is_file() else 0
    print(f"    {'📁' if f.is_dir() else '📄'} {f.name} {'(' + str(size) + ' bytes)' if f.is_file() else ''}")
print("  RESULTADO: OK")
PYEOF
  [ $? -eq 0 ] && OK "Acceso a /sdcard funciona" || FAIL "No se pudo leer /sdcard"
else
  SKIP "/sdcard/Download no accesible (ejecuta: termux-setup-storage)"
fi

# ── 6. Test imagen con Pillow ────────────────────────────────
echo ""
INFO "Test Pillow — crear imagen de prueba..."
python3 << 'PYEOF'
import sys
try:
    from PIL import Image, ImageDraw
    import os, base64, io

    # Crear imagen de prueba 100x100
    img = Image.new("RGB", (100, 100), color=(73, 109, 137))
    draw = ImageDraw.Draw(img)
    draw.rectangle([10,10,90,90], outline=(255,255,255), width=3)
    draw.text((20,40), "TEST", fill=(255,255,0))

    # Guardar
    path = os.path.expanduser("~/test_image.jpg")
    img.save(path, "JPEG")
    size = os.path.getsize(path)
    print(f"  Imagen creada: {path} ({size} bytes)")

    # Convertir a base64 (lo que usaría el bot para enviar a Ollama)
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    print(f"  Base64 length: {len(b64)} chars")
    print(f"  Primeros 40 chars: {b64[:40]}...")

    os.remove(path)
    print("  RESULTADO: OK")
except ImportError:
    print("  RESULTADO: SKIP — Pillow no instalado")
except Exception as e:
    print(f"  RESULTADO: FAIL — {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
[ $? -eq 0 ] && OK "Pillow funciona" || FAIL "Pillow falló"

# ── 7. Test HTTP con urllib ──────────────────────────────────
echo ""
INFO "Test HTTP con urllib (builtin)..."
python3 << 'PYEOF'
from urllib import request as ureq
import sys

targets = [
    ("Ollama",    "http://localhost:11434"),
    ("n8n",       "http://localhost:5678/healthz"),
    ("Dashboard", "http://localhost:8080/api/status"),
]
for name, url in targets:
    try:
        with ureq.urlopen(url, timeout=2) as r:
            print(f"  {name:12} → HTTP {r.status} ✓")
    except Exception as e:
        msg = str(e)
        if "Connection refused" in msg or "actively refused" in msg:
            print(f"  {name:12} → no responde (normal si no está corriendo)")
        else:
            print(f"  {name:12} → {msg[:60]}")
print("  RESULTADO: OK")
PYEOF
OK "Test HTTP completado"

# ── 8. Script de utilidad — bot_utils.py ─────────────────────
echo ""
INFO "Creando ~/bot_utils.py (helpers reutilizables)..."
cat > "$HOME/bot_utils.py" << 'PYEOF'
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
PYEOF
python3 "$HOME/bot_utils.py" && OK "bot_utils.py creado y funcional" || FAIL "bot_utils.py falló"

# ── Resumen ──────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}✓ TEST 2 PASADO — Python funciona correctamente${NC}"
else
  echo -e "  ${RED}${BOLD}✗ TEST 2: $ERRORS error(s) — revisar arriba${NC}"
fi
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
echo ""
echo -e "  Helper disponible: ${CYAN}~/bot_utils.py${NC}"
echo -e "  Uso: ${BOLD}from bot_utils import save_message, get_history${NC}"
echo ""

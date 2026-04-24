#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · TEST 7 — n8n + Ollama visión + Python + SQLite
#  Bot Telegram que acepta fotos, las analiza y guarda historial
#
#  NOTA ARM64: sin DEFAULT (datetime('now')) en SQLite Python.
#  HTTP: urllib builtin en lugar de requests.
#  BUG 4 FIX: redimensionado automático a 512px para img >500KB.
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

OK()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
FAIL() { echo -e "  ${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS+1)); }
INFO() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
SKIP() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }
NOTE() { echo -e "  ${BOLD}[NOTA]${NC} $1"; }
ERRORS=0

OLLAMA_URL="http://localhost:11434"
N8N_URL="http://localhost:5678"
BOT_DB="$HOME/bot_history.db"
VISION_SCRIPT="$HOME/vision_bot.py"

clear; echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  TEST 7 — Bot Telegram con visión       ║"
echo    "  ║  n8n + Ollama visión + Python + SQLite  ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""

# ── 1. Pre-checks ────────────────────────────────────────────
INFO "Verificando servicios y modelos..."
curl -sf "$OLLAMA_URL" &>/dev/null && OK "Ollama activo" || { FAIL "Ollama no responde"; exit 1; }
curl -sf "$N8N_URL/healthz" &>/dev/null && OK "n8n activo" || { FAIL "n8n no responde"; exit 1; }

VISION_MODEL=$(curl -sf "$OLLAMA_URL/api/tags" | python3 -c "
import json,sys
models=[m['name'] for m in json.load(sys.stdin).get('models',[])]
for p in ['moondream:1.8b','llava-phi3:3.8b','llava:7b']:
    if p in models: print(p); break
" 2>/dev/null)
[ -n "$VISION_MODEL" ] && OK "Modelo visión: $VISION_MODEL" || { FAIL "No hay modelo de visión — ejecuta TEST 4"; exit 1; }

TEXT_MODEL=$(curl -sf "$OLLAMA_URL/api/tags" | python3 -c "
import json,sys
models=[m['name'] for m in json.load(sys.stdin).get('models',[])]
for p in ['qwen2.5:0.5b','qwen2.5:1.5b','qwen:1.8b']:
    if p in models: print(p); break
" 2>/dev/null)
[ -n "$TEXT_MODEL" ] && OK "Modelo texto: $TEXT_MODEL" || TEXT_MODEL="$VISION_MODEL"

# ── 2. Crear vision_bot.py ───────────────────────────────────
echo ""
INFO "Creando $VISION_SCRIPT..."
cat > "$VISION_SCRIPT" << PYEOF
#!/data/data/com.termux/files/usr/bin/python3
"""
vision_bot.py — Bot de visión para termux-ai-stack
Uso directo: python3 vision_bot.py <ruta_imagen> [chat_id] [pregunta]
Desde n8n:   python3 /data/data/com.termux/files/home/vision_bot.py <img> <chat_id>

FIXES:
  [BUG 4]  Redimensionado automático a 512px para imágenes >500KB
  [SQLite] Sin DEFAULT (datetime('now')) — incompatible con ARM64
  [HTTP]   urllib builtin en lugar de requests
"""
import sys, os, base64, sqlite3, json, argparse
from urllib import request as ureq
from datetime import datetime

try:
    from PIL import Image
    PILLOW_OK = True
except ImportError:
    PILLOW_OK = False

OLLAMA_URL    = "http://localhost:11434"
VISION_MODEL  = "$VISION_MODEL"
TEXT_MODEL    = "$TEXT_MODEL"
DB_PATH       = os.path.expanduser("~/bot_history.db")
IMG_CACHE_DIR = os.path.expanduser("~/img_cache")
os.makedirs(IMG_CACHE_DIR, exist_ok=True)

def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""CREATE TABLE IF NOT EXISTS historial (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT, rol TEXT, content TEXT,
        tiene_imagen INTEGER DEFAULT 0, modelo TEXT, fecha TEXT)""")
    conn.execute("""CREATE TABLE IF NOT EXISTS imagenes_analizadas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT, ruta TEXT, descripcion TEXT,
        pregunta TEXT, modelo TEXT, fecha TEXT)""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_chat ON historial(chat_id)")
    conn.commit()
    return conn

def redimensionar(ruta):
    """BUG 4 FIX: redimensiona imágenes >500KB a max 512px."""
    if not PILLOW_OK: return ruta
    if os.path.getsize(ruta) <= 500_000: return ruta
    img = Image.open(ruta)
    w, h = img.size
    r = min(512/w, 512/h)
    img = img.resize((int(w*r), int(h*r)), Image.LANCZOS)
    tmp = os.path.expanduser("~/vision_tmp.jpg")
    img.save(tmp, "JPEG", quality=80)
    return tmp

def _post_ollama(payload, timeout=300):
    data = json.dumps(payload).encode("utf-8")
    req = ureq.Request(f"{OLLAMA_URL}/api/generate", data=data,
                       headers={"Content-Type": "application/json"})
    with ureq.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())

def analizar_imagen(ruta, pregunta, chat_id):
    conn = init_db()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    ruta_proc = redimensionar(ruta)
    with open(ruta_proc, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    tmp = os.path.expanduser("~/vision_tmp.jpg")
    if ruta_proc != ruta and os.path.exists(tmp): os.remove(tmp)
    try:
        result = _post_ollama({"model": VISION_MODEL,
            "prompt": f"You must respond ONLY in Spanish. {pregunta} Responde en español.",
            "images": [b64], "stream": False,
            "options": {"num_predict": 150, "temperature": 0.1}})
        descripcion = result.get("response", "").strip()
    except Exception as e:
        descripcion = f"[ERROR Ollama] {e}"
    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,tiene_imagen,modelo,fecha) VALUES (?,?,?,1,?,?)",
        (chat_id, "user", f"[IMAGEN] {pregunta}", None, now))
    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,tiene_imagen,modelo,fecha) VALUES (?,?,?,1,?,?)",
        (chat_id, "assistant", descripcion, VISION_MODEL, now))
    conn.execute(
        "INSERT INTO imagenes_analizadas (chat_id,ruta,descripcion,pregunta,modelo,fecha) VALUES (?,?,?,?,?,?)",
        (chat_id, ruta, descripcion, pregunta, VISION_MODEL, now))
    conn.commit(); conn.close()
    return descripcion

def chat_texto(chat_id, mensaje):
    conn = init_db()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    hist = list(reversed(conn.execute(
        "SELECT rol, content FROM historial WHERE chat_id=? ORDER BY id DESC LIMIT 4",
        (chat_id,)).fetchall()))
    context = "\n".join([f"{'Usuario' if r=='user' else 'Bot'}: {c}" for r,c in hist[:-1]])
    prompt = f"{context}\nUsuario: {mensaje}\nBot:" if context else mensaje
    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,fecha) VALUES (?,?,?,?)",
        (chat_id, "user", mensaje, now))
    conn.commit()
    try:
        result = _post_ollama({"model": TEXT_MODEL, "prompt": prompt,
            "stream": False, "options": {"num_predict": 100}}, timeout=60)
        respuesta = result.get("response", "").strip()
    except Exception as e:
        respuesta = f"[ERROR Ollama] {e}"
    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,modelo,fecha) VALUES (?,?,?,?,?)",
        (chat_id, "assistant", respuesta, TEXT_MODEL, now))
    conn.commit(); conn.close()
    return respuesta

def get_stats(chat_id=None):
    conn = init_db()
    if chat_id:
        result = {"chat_id": chat_id,
            "mensajes": conn.execute("SELECT COUNT(*) FROM historial WHERE chat_id=?", (chat_id,)).fetchone()[0],
            "imagenes": conn.execute("SELECT COUNT(*) FROM imagenes_analizadas WHERE chat_id=?", (chat_id,)).fetchone()[0]}
    else:
        result = {
            "total_mensajes": conn.execute("SELECT COUNT(*) FROM historial").fetchone()[0],
            "imagenes_analizadas": conn.execute("SELECT COUNT(*) FROM imagenes_analizadas").fetchone()[0],
            "usuarios": conn.execute("SELECT COUNT(DISTINCT chat_id) FROM historial").fetchone()[0]}
    conn.close()
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("imagen",   nargs="?")
    parser.add_argument("chat_id",  nargs="?", default="test_chat")
    parser.add_argument("pregunta", nargs="?", default="¿Qué ves en esta imagen? Responde en español.")
    parser.add_argument("--texto",  help="Mensaje de texto sin imagen")
    parser.add_argument("--stats",  action="store_true")
    args = parser.parse_args()
    if args.stats:
        print(json.dumps(get_stats(), ensure_ascii=False, indent=2))
    elif args.texto:
        print(chat_texto(args.chat_id, args.texto))
    elif args.imagen:
        if not os.path.exists(args.imagen):
            print(f"ERROR: imagen no encontrada: {args.imagen}", file=sys.stderr); sys.exit(1)
        print(analizar_imagen(args.imagen, args.pregunta, args.chat_id))
    else:
        parser.print_help()
PYEOF
chmod +x "$VISION_SCRIPT"
OK "vision_bot.py creado: $VISION_SCRIPT"

# ── 3. Test del script ───────────────────────────────────────
echo ""
INFO "Probando vision_bot.py con imagen de prueba..."

# Crear imagen de prueba
python3 -c "
from PIL import Image, ImageDraw
import os
img = Image.new('RGB',(300,200),(20,100,160))
d = ImageDraw.Draw(img)
d.ellipse([40,40,140,140], fill=(255,200,0))
d.rectangle([160,60,260,160], fill=(40,180,80))
d.text((10,170),'vision_bot test', fill=(255,255,255))
img.save(os.path.expanduser('~/vbot_test.jpg'))
" 2>/dev/null

if [ -f "$HOME/vbot_test.jpg" ]; then
  INFO "(Esto puede tardar 30-120s en ARM64...)"
  RESP=$(python3 "$VISION_SCRIPT" "$HOME/vbot_test.jpg" "chat_test_777" "¿Qué formas geométricas hay?" 2>/dev/null)
  if [ -n "$RESP" ]; then
    OK "Respuesta recibida:"
    echo "$RESP" | fold -s -w 60 | while read line; do echo "    $line"; done
  else
    FAIL "No se recibió respuesta"
  fi

  # Test texto
  echo ""
  INFO "Probando modo texto..."
  RESP2=$(python3 "$VISION_SCRIPT" --texto "¿Recuerdas la imagen que te envié?" "chat_test_777" 2>/dev/null)
  [ -n "$RESP2" ] && OK "Modo texto OK: ${RESP2:0:80}..." || FAIL "Modo texto falló"

  # Stats
  echo ""
  INFO "Stats de la BD:"
  python3 "$VISION_SCRIPT" --stats 2>/dev/null | while read line; do echo "  $line"; done

  rm -f "$HOME/vbot_test.jpg"
else
  SKIP "Pillow no disponible — imagen de prueba no generada"
fi

# ── 4. Instrucciones workflow n8n ────────────────────────────
echo ""
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Workflow n8n para fotos — estructura:${NC}"
echo ""
echo -e "  ${BOLD}[Telegram Trigger]${NC} → recibe mensaje con foto"
echo -e "    ↓"
echo -e "  ${BOLD}[IF]${NC} → \$json.message.photo existe?"
echo -e "    ↓ SI"
echo -e "  ${BOLD}[HTTP GET]${NC} → descargar foto de Telegram API"
echo -e "    URL: https://api.telegram.org/bot{TOKEN}/getFile"
echo -e "    → obtener file_path"
echo -e "    ↓"
echo -e "  ${BOLD}[HTTP GET]${NC} → https://api.telegram.org/file/bot{TOKEN}/{file_path}"
echo -e "    → guardar como /tmp/foto_\$chatid.jpg"
echo -e "    ↓"
echo -e "  ${BOLD}[Execute Command]${NC}:"
echo -e "    ${CYAN}/data/data/com.termux/files/usr/bin/python3${NC}"
echo -e "    ${CYAN}/data/data/com.termux/files/home/vision_bot.py${NC}"
echo -e "    ${CYAN}/tmp/foto_{{chat_id}}.jpg {{chat_id}} '¿Qué ves?'${NC}"
echo -e "    ↓"
echo -e "  ${BOLD}[Telegram Send]${NC} → responder con output del script"
echo ""
echo -e "  ${BOLD}[IF]${NC} → NO (mensaje de texto normal)"
echo -e "    ↓"
echo -e "  ${BOLD}[Execute Command]${NC}:"
echo -e "    ${CYAN}python3 .../vision_bot.py --texto '{{mensaje}}' {{chat_id}}${NC}"
echo -e "    ↓"
echo -e "  ${BOLD}[Telegram Send]${NC}"
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"

# ── Resumen ──────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}✓ TEST 7 PASADO — Bot visión completo OK${NC}"
else
  echo -e "  ${RED}${BOLD}✗ TEST 7: $ERRORS error(s) — revisar arriba${NC}"
fi
echo ""
echo -e "  Script: ${CYAN}$VISION_SCRIPT${NC}"
echo -e "  Uso imagen: ${CYAN}python3 vision_bot.py foto.jpg CHAT_ID${NC}"
echo -e "  Uso texto:  ${CYAN}python3 vision_bot.py --texto 'msg' CHAT_ID${NC}"
echo -e "  Stats:      ${CYAN}python3 vision_bot.py --stats${NC}"
echo ""

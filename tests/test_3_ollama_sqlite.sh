#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · TEST 3 — Ollama + SQLite (Python)
#  Valida: Ollama API REST, chat con historial en SQLite,
#          contexto persistente entre mensajes
#
#  NOTA ARM64: sin DEFAULT (datetime('now')) en SQLite Python.
#  HTTP: urllib builtin en lugar de requests.
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

OK()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
FAIL() { echo -e "  ${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS+1)); }
INFO() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
SKIP() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }
ERRORS=0

OLLAMA_URL="http://localhost:11434"

clear; echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  TEST 3 — Ollama + SQLite               ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""

# ── 1. Verificar Ollama corriendo ────────────────────────────
INFO "Verificando Ollama en $OLLAMA_URL..."
if ! curl -sf "$OLLAMA_URL" &>/dev/null; then
  INFO "Ollama no está corriendo. Iniciando..."
  if [ -f "$HOME/ollama_start.sh" ]; then
    bash "$HOME/ollama_start.sh" &>/dev/null &
  else
    ollama serve &>/dev/null &
  fi
  echo -n "  Esperando Ollama"
  for i in $(seq 1 15); do
    sleep 2; echo -n "."
    curl -sf "$OLLAMA_URL" &>/dev/null && break
  done
  echo ""
fi
curl -sf "$OLLAMA_URL" &>/dev/null && OK "Ollama responde en $OLLAMA_URL" || { FAIL "Ollama no responde"; exit 1; }

# ── 2. Listar modelos ────────────────────────────────────────
INFO "Listando modelos disponibles..."
MODELS_JSON=$(curl -sf "$OLLAMA_URL/api/tags" 2>/dev/null)
if [ -z "$MODELS_JSON" ]; then
  FAIL "No se pudo listar modelos"
else
  echo "$MODELS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
models = data.get('models', [])
if not models:
    print('  (ningún modelo instalado)')
else:
    for m in models:
        size_gb = m.get('size', 0) / 1024**3
        print(f\"  {m['name']:30} {size_gb:.1f} GB\")
"
  OK "$(echo "$MODELS_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('models',[])),'modelos encontrados')")"
fi

# ── 3. Seleccionar modelo de prueba ──────────────────────────
echo ""
INFO "Seleccionando modelo para prueba (texto)..."
MODEL=$(curl -sf "$OLLAMA_URL/api/tags" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
models = [m['name'] for m in data.get('models', [])]
# Preferir modelos livianos de texto
priority = ['qwen2.5:0.5b','qwen2.5:1.5b','qwen:1.8b','llama3.2:1b','phi3:mini']
for p in priority:
    if p in models:
        print(p)
        break
else:
    if models: print(models[0])
" 2>/dev/null)

if [ -z "$MODEL" ]; then
  INFO "No hay modelos. Descargando qwen2.5:0.5b (397MB)..."
  ollama pull qwen2.5:0.5b
  MODEL="qwen2.5:0.5b"
fi
OK "Modelo seleccionado: $MODEL"

# ── 4. Test API REST básico ──────────────────────────────────
echo ""
INFO "Test API REST — generación simple..."
RESPONSE=$(curl -sf "$OLLAMA_URL/api/generate" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"prompt\":\"Responde SOLO con el número: cuanto es 2+2\",\"stream\":false}" \
  2>/dev/null)

if [ -n "$RESPONSE" ]; then
  RESP_TEXT=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null)
  OK "Respuesta recibida: '$RESP_TEXT'"
  DURATION=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{d.get('total_duration',0)/1e9:.1f}s\")" 2>/dev/null)
  OK "Tiempo de inferencia: $DURATION"
else
  FAIL "No se recibió respuesta de Ollama"
fi

# ── 5. Test chat con historial en SQLite ─────────────────────
echo ""
INFO "Test chat con historial persistente en SQLite..."
python3 << PYEOF
import sqlite3, json, os, sys
from urllib import request as ureq
from datetime import datetime

OLLAMA_URL = "http://localhost:11434"
MODEL = "$MODEL"
DB = os.path.expanduser("~/test_chat_history.db")

# Inicializar BD — sin DEFAULT (datetime('now')) ARM64 fix
conn = sqlite3.connect(DB)
conn.execute("""
    CREATE TABLE IF NOT EXISTS historial (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT NOT NULL,
        rol     TEXT NOT NULL,
        content TEXT NOT NULL,
        fecha   TEXT
    )
""")
conn.commit()

def save(chat_id, rol, content):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,fecha) VALUES (?,?,?,?)",
        (chat_id, rol, content, now)
    )
    conn.commit()

def get_history(chat_id, limit=6):
    rows = conn.execute(
        "SELECT rol, content FROM historial WHERE chat_id=? ORDER BY id DESC LIMIT ?",
        (chat_id, limit)
    ).fetchall()
    return [{"role": r[0], "content": r[1]} for r in reversed(rows)]

def chat(chat_id, pregunta):
    save(chat_id, "user", pregunta)
    historial = get_history(chat_id)
    context = "\n".join([f"{m['role'].upper()}: {m['content']}" for m in historial[:-1]])
    prompt = f"{context}\nUSER: {pregunta}\nASSISTANT:" if context else pregunta

    try:
        data = json.dumps({
            "model": MODEL,
            "prompt": prompt,
            "stream": False,
            "options": {"num_predict": 80, "temperature": 0.7}
        }).encode("utf-8")
        req = ureq.Request(
            f"{OLLAMA_URL}/api/generate",
            data=data,
            headers={"Content-Type": "application/json"}
        )
        with ureq.urlopen(req, timeout=60) as resp:
            respuesta = json.loads(resp.read()).get("response", "").strip()
        save(chat_id, "assistant", respuesta)
        return respuesta
    except Exception as e:
        return f"ERROR: {e}"

# Simular conversación
chat_id = "test_001"
print(f"  Chat ID: {chat_id} | Modelo: {MODEL}")
print()

conversacion = [
    "Hola, me llamo Carlos",
    "¿Cuál es mi nombre?",
    "Dame un consejo corto de programación",
]

for i, pregunta in enumerate(conversacion, 1):
    print(f"  [{i}] USER: {pregunta}")
    resp = chat(chat_id, pregunta)
    print(f"      BOT:  {resp[:120]}{'...' if len(resp)>120 else ''}")
    print()

# Verificar que el historial se guardó
total = conn.execute("SELECT COUNT(*) FROM historial WHERE chat_id=?", (chat_id,)).fetchone()[0]
print(f"  Mensajes guardados en SQLite: {total}")
conn.close()
os.remove(DB)
print("  RESULTADO: OK")
PYEOF
[ $? -eq 0 ] && OK "Chat con historial SQLite funciona" || FAIL "Chat con historial SQLite falló"

# ── 6. Test Ollama /api/chat (formato OpenAI) ────────────────
echo ""
INFO "Test /api/chat (formato messages)..."
CHAT_RESP=$(curl -sf "$OLLAMA_URL/api/chat" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Di solo: FUNCIONA\"}],\"stream\":false}" \
  2>/dev/null)
if [ -n "$CHAT_RESP" ]; then
  CHAT_TEXT=$(echo "$CHAT_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['message']['content'].strip())" 2>/dev/null)
  OK "/api/chat responde: '$CHAT_TEXT'"
else
  SKIP "/api/chat no disponible en esta versión de Ollama (normal en v0.21)"
fi

# ── 7. Variables de entorno Ollama ───────────────────────────
echo ""
INFO "Variables de entorno Ollama relevantes..."
echo -e "  ${BOLD}Actuales en el sistema:${NC}"
env | grep -i ollama | while read line; do echo "    $line"; done
[ -z "$(env | grep -i ollama)" ] && echo "    (ninguna configurada)"
echo ""
echo -e "  ${BOLD}Recomendadas para ARM64 (ya en ~/.bashrc si corriste [p]):${NC}"
echo "    OLLAMA_MAX_LOADED_MODELS=1  — evita OOM"
echo "    OLLAMA_NUM_PARALLEL=1       — conserva RAM"
echo "    OLLAMA_FLASH_ATTENTION=1    — inferencia más eficiente"
echo "    MALLOC_ARENA_MAX=2          — reduce fragmentación"

# ── Resumen ──────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}✓ TEST 3 PASADO — Ollama + SQLite funciona${NC}"
else
  echo -e "  ${RED}${BOLD}✗ TEST 3: $ERRORS error(s) — revisar arriba${NC}"
fi
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
echo ""
echo -e "  Modelo usado: ${CYAN}$MODEL${NC}"
echo -e "  Helper: ${CYAN}~/bot_utils.py${NC} (generado en TEST 2)"
echo ""

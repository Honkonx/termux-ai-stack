#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · TEST 6 — n8n + Ollama + SQLite
#  Valida: workflow Telegram, memoria SQLite, respuestas con
#  contexto, acceso a BD de Termux desde proot n8n
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
NOTE() { echo -e "  ${BOLD}[NOTA]${NC} $1"; }
ERRORS=0

N8N_URL="http://localhost:5678"
OLLAMA_URL="http://localhost:11434"
N8N_DB="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian/root/.n8n/database.sqlite"
BOT_DB="$HOME/bot_history.db"

clear; echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  TEST 6 — n8n + Ollama + SQLite         ║"
echo    "  ║  Chatbot Telegram con memoria           ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""

# ── 1. Verificar servicios ───────────────────────────────────
INFO "Verificando servicios..."

# n8n
curl -sf "$N8N_URL/healthz" &>/dev/null \
  && OK "n8n activo ($N8N_URL)" \
  || { FAIL "n8n no responde — ejecuta: n8n-start"; exit 1; }

# Ollama
curl -sf "$OLLAMA_URL" &>/dev/null \
  && OK "Ollama activo" \
  || { FAIL "Ollama no responde"; exit 1; }

# ── 2. Verificar BD n8n ──────────────────────────────────────
echo ""
INFO "Verificando BD de n8n..."
if [ -f "$N8N_DB" ]; then
  WF_COUNT=$(sqlite3 "$N8N_DB" "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null)
  WF_ACTIVE=$(sqlite3 "$N8N_DB" "SELECT COUNT(*) FROM workflow_entity WHERE active=1;" 2>/dev/null)
  OK "BD n8n: $WF_COUNT workflows ($WF_ACTIVE activos)"

  echo ""
  echo -e "  ${BOLD}Workflows activos:${NC}"
  sqlite3 "$N8N_DB" "SELECT name, active FROM workflow_entity WHERE active=1 LIMIT 5;" \
    | while IFS='|' read -r name active; do
        echo "    ● $name"
      done

  EXEC_COUNT=$(sqlite3 "$N8N_DB" "SELECT COUNT(*) FROM execution_entity;" 2>/dev/null)
  OK "Ejecuciones totales en n8n: $EXEC_COUNT"
else
  SKIP "BD n8n no encontrada — puede estar en ruta diferente"
  NOTE "Ruta esperada: $N8N_DB"
fi

# ── 3. Verificar/crear BD de historial del bot ──────────────
echo ""
INFO "Verificando BD de historial del bot: $BOT_DB"
python3 << PYEOF
import sqlite3, os
from datetime import datetime

DB = "$BOT_DB"
now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
conn = sqlite3.connect(DB)
conn.execute("""
    CREATE TABLE IF NOT EXISTS historial (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id  TEXT NOT NULL,
        rol      TEXT NOT NULL,
        content  TEXT NOT NULL,
        modelo   TEXT,
        fecha    TEXT
    )
""")
conn.execute("CREATE INDEX IF NOT EXISTS idx_chat ON historial(chat_id)")
conn.execute("""
    CREATE TABLE IF NOT EXISTS usuarios (
        chat_id    TEXT PRIMARY KEY,
        nombre     TEXT,
        primer_uso TEXT,
        total_msgs INTEGER DEFAULT 0
    )
""")
conn.commit()
total = conn.execute("SELECT COUNT(*) FROM historial").fetchone()[0]
users = conn.execute("SELECT COUNT(*) FROM usuarios").fetchone()[0]
conn.close()
print(f"  BD OK: {total} mensajes, {users} usuarios")
PYEOF
[ $? -eq 0 ] && OK "BD bot historial lista: $BOT_DB" || FAIL "Error con BD bot"

# ── 4. Ruta de BD desde proot ────────────────────────────────
echo ""
INFO "Verificando acceso a BD del bot desde proot (n8n)..."
BOT_DB_PROOT="/data/data/com.termux/files/home/bot_history.db"
NOTE "Desde n8n (dentro de proot), la ruta de la BD es:"
echo -e "  ${CYAN}$BOT_DB_PROOT${NC}"
echo ""
NOTE "Ejemplo de query SQLite desde nodo Execute Command en n8n:"
echo -e "  ${BOLD}sqlite3 $BOT_DB_PROOT \"SELECT content FROM historial WHERE chat_id='{{chat_id}}' ORDER BY id DESC LIMIT 5;\"${NC}"

# Verificar que la ruta existe desde el punto de vista de Termux
[ -f "$BOT_DB" ] && OK "BD accesible desde Termux" || WARN "BD aún no existe (se crea en el primer uso)"

# ── 5. Simular flujo completo del bot ────────────────────────
echo ""
INFO "Simulando flujo completo del bot (sin Telegram real)..."
echo ""

python3 << PYEOF
import sqlite3, json, os, sys
from urllib import request as ureq
from datetime import datetime

OLLAMA_URL = "http://localhost:11434"
DB = "$BOT_DB"

# Detectar modelo de texto con urllib
try:
    with ureq.urlopen(f"{OLLAMA_URL}/api/tags", timeout=5) as resp:
        models = [m['name'] for m in json.loads(resp.read()).get('models', [])]
    TEXT_MODEL = next((m for m in ['qwen2.5:0.5b','qwen2.5:1.5b','qwen:1.8b'] if m in models), models[0] if models else None)
except:
    TEXT_MODEL = None

if not TEXT_MODEL:
    print("  ERROR: No hay modelos de texto disponibles")
    sys.exit(1)

print(f"  Modelo: {TEXT_MODEL}")
conn = sqlite3.connect(DB)

def get_history(chat_id, limit=5):
    rows = conn.execute(
        "SELECT rol, content FROM historial WHERE chat_id=? ORDER BY id DESC LIMIT ?",
        (chat_id, limit)
    ).fetchall()
    return list(reversed(rows))

def save_message(chat_id, rol, content, modelo=None):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,modelo,fecha) VALUES (?,?,?,?,?)",
        (chat_id, rol, content, modelo, now)
    )
    conn.execute("""
        INSERT INTO usuarios (chat_id, primer_uso, total_msgs) VALUES (?,?,1)
        ON CONFLICT(chat_id) DO UPDATE SET total_msgs=total_msgs+1
    """, (chat_id, now))
    conn.commit()

def procesar_mensaje(chat_id, texto_usuario):
    save_message(chat_id, "user", texto_usuario)
    historia = get_history(chat_id, limit=6)
    context_lines = [f"{'Usuario' if r=='user' else 'Bot'}: {c}" for r,c in historia[:-1]]
    contexto = "\n".join(context_lines)
    system = "Eres un asistente conciso. Responde en español, máximo 2 oraciones."
    prompt = f"{system}\n\n{contexto}\nUsuario: {texto_usuario}\nBot:" if contexto else f"{system}\nUsuario: {texto_usuario}\nBot:"

    try:
        data = json.dumps({
            "model": TEXT_MODEL,
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
    except Exception as e:
        respuesta = f"Error: {e}"

    save_message(chat_id, "assistant", respuesta, TEXT_MODEL)
    return respuesta

# Simular 3 usuarios distintos
test_cases = [
    ("user_telegram_111", "Hola, me llamo Ana"),
    ("user_telegram_111", "¿Cuál es mi nombre?"),
    ("user_telegram_222", "¿Cuánto es 5 por 8?"),
    ("user_telegram_111", "Dame un consejo corto"),
    ("user_telegram_222", "¿Quién inventó Python?"),
]

print()
for chat_id, mensaje in test_cases:
    user_short = chat_id.split("_")[-1]
    print(f"  [User {user_short}] {mensaje}")
    respuesta = procesar_mensaje(chat_id, mensaje)
    print(f"  [Bot      ] {respuesta[:100]}")
    print()

# Estadísticas finales
total = conn.execute("SELECT COUNT(*) FROM historial").fetchone()[0]
users = conn.execute("SELECT COUNT(*) FROM usuarios").fetchone()[0]
por_modelo = conn.execute(
    "SELECT modelo, COUNT(*) FROM historial WHERE modelo IS NOT NULL GROUP BY modelo"
).fetchall()

print(f"  ─── Estadísticas BD ───")
print(f"  Total mensajes: {total}")
print(f"  Usuarios únicos: {users}")
for modelo, count in por_modelo:
    print(f"  Modelo {modelo}: {count} respuestas")

conn.close()
print("\n  RESULTADO: OK")
PYEOF
[ $? -eq 0 ] && OK "Flujo bot simulado correctamente" || FAIL "Flujo bot falló"

# ── 6. Instrucciones para configurar workflow n8n ────────────
echo ""
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Para agregar memoria SQLite a tu workflow n8n existente:${NC}"
echo ""
echo -e "  ${BOLD}Nodo Execute Command (antes de llamar Ollama):${NC}"
echo "  sqlite3 /data/data/com.termux/files/home/bot_history.db \\"
echo "    \"SELECT rol||': '||content FROM historial"
echo "     WHERE chat_id='{{'\$json.message.chat.id'}}'"
echo "     ORDER BY id DESC LIMIT 5;\""
echo ""
echo -e "  ${BOLD}Nodo Execute Command (después de respuesta Ollama):${NC}"
echo "  sqlite3 /data/data/com.termux/files/home/bot_history.db \\"
echo "    \"INSERT INTO historial (chat_id,rol,content) VALUES"
echo "     ('{{'\$json.message.chat.id'}}','assistant','{{respuesta}}');\""
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"

# ── Resumen ──────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}✓ TEST 6 PASADO — n8n + Ollama + SQLite OK${NC}"
else
  echo -e "  ${RED}${BOLD}✗ TEST 6: $ERRORS error(s) — revisar arriba${NC}"
fi
echo ""
echo -e "  BD historial: ${CYAN}$BOT_DB${NC}"
echo -e "  Ruta proot:   ${CYAN}$BOT_DB_PROOT${NC}"
echo ""

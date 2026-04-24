#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · TEST 1 — SQLite solo
#  Valida: instalación, CRUD, integridad, schema bot
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

OK()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
FAIL() { echo -e "  ${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS+1)); }
INFO() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
ERRORS=0

DB="$HOME/test_stack.db"

clear; echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  TEST 1 — SQLite solo                   ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""

# ── 1. Verificar binario ─────────────────────────────────────
INFO "Verificando sqlite3..."
if ! command -v sqlite3 &>/dev/null; then
  INFO "sqlite3 no encontrado — instalando..."
  pkg install -y sqlite 2>/dev/null
fi
command -v sqlite3 &>/dev/null && OK "sqlite3 $(sqlite3 --version | cut -d' ' -f1)" || { FAIL "sqlite3 no disponible"; exit 1; }

# ── 2. Crear BD y schema ─────────────────────────────────────
INFO "Creando BD de prueba: $DB"
rm -f "$DB"
sqlite3 "$DB" << 'SQL'
CREATE TABLE mensajes (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario   TEXT NOT NULL,
  texto     TEXT NOT NULL,
  respuesta TEXT,
  fecha     TEXT DEFAULT (datetime('now')),
  procesado INTEGER DEFAULT 0
);
CREATE TABLE contexto (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_id   TEXT NOT NULL,
  rol       TEXT NOT NULL,
  contenido TEXT NOT NULL,
  fecha     TEXT DEFAULT (datetime('now'))
);
CREATE INDEX idx_chat ON contexto(chat_id);
CREATE INDEX idx_fecha ON mensajes(fecha);
SQL
[ $? -eq 0 ] && OK "Schema creado (mensajes + contexto + índices)" || FAIL "Error creando schema"

# ── 3. INSERT ────────────────────────────────────────────────
INFO "Insertando datos de prueba..."
sqlite3 "$DB" << 'SQL'
INSERT INTO mensajes (usuario, texto, respuesta, procesado) VALUES
  ('user_123', 'Hola bot', 'Hola! ¿En qué te ayudo?', 1),
  ('user_456', '¿Cuánto es 2+2?', 'Son 4.', 1),
  ('user_123', 'Gracias', 'De nada!', 1),
  ('user_789', 'Test mensaje', NULL, 0),
  ('user_123', 'Otro mensaje', NULL, 0);
INSERT INTO contexto (chat_id, rol, contenido) VALUES
  ('chat_001', 'user',      'Necesito ayuda con Python'),
  ('chat_001', 'assistant', 'Claro, ¿qué necesitas?'),
  ('chat_001', 'user',      'Cómo hago un for loop'),
  ('chat_002', 'user',      'Hola'),
  ('chat_002', 'assistant', 'Hola! ¿Qué necesitas?');
SQL
[ $? -eq 0 ] && OK "5 mensajes + 5 contextos insertados" || FAIL "Error en INSERT"

# ── 4. SELECT ────────────────────────────────────────────────
INFO "Verificando SELECTs..."
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM mensajes;")
[ "$COUNT" = "5" ] && OK "COUNT mensajes = $COUNT" || FAIL "COUNT esperado 5, obtenido $COUNT"

COUNT_CTX=$(sqlite3 "$DB" "SELECT COUNT(*) FROM contexto;")
[ "$COUNT_CTX" = "5" ] && OK "COUNT contexto = $COUNT_CTX" || FAIL "COUNT esperado 5, obtenido $COUNT_CTX"

# ── 5. Queries de uso real (bot) ─────────────────────────────
INFO "Simulando queries reales del bot..."

# Historial de un chat (lo que usaría n8n para contexto)
echo ""
echo -e "  ${BOLD}Historial chat_001:${NC}"
sqlite3 "$DB" "SELECT rol, contenido FROM contexto WHERE chat_id='chat_001' ORDER BY fecha;" \
  | while IFS='|' read -r rol cont; do
      printf "    %-12s → %s\n" "$rol" "$cont"
    done

# Mensajes sin procesar
PENDIENTES=$(sqlite3 "$DB" "SELECT COUNT(*) FROM mensajes WHERE procesado=0;")
OK "Mensajes pendientes: $PENDIENTES"

# UPDATE — marcar como procesado
sqlite3 "$DB" "UPDATE mensajes SET procesado=1, respuesta='Procesado automaticamente' WHERE procesado=0;"
PENDIENTES2=$(sqlite3 "$DB" "SELECT COUNT(*) FROM mensajes WHERE procesado=0;")
[ "$PENDIENTES2" = "0" ] && OK "UPDATE: todos marcados como procesados" || FAIL "UPDATE no funcionó"

# ── 6. Queries analíticas ────────────────────────────────────
INFO "Verificando queries analíticas..."
echo ""
echo -e "  ${BOLD}Mensajes por usuario:${NC}"
sqlite3 "$DB" "SELECT usuario, COUNT(*) as total FROM mensajes GROUP BY usuario ORDER BY total DESC;" \
  | while IFS='|' read -r usr total; do
      printf "    %-15s %s mensajes\n" "$usr" "$total"
    done

# ── 7. Ruta n8n SQLite (dentro de proot) ─────────────────────
echo ""
INFO "Verificando SQLite de n8n en proot..."
N8N_DB="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian/root/.n8n/database.sqlite"
if [ -f "$N8N_DB" ]; then
  TABLES=$(sqlite3 "$N8N_DB" ".tables" 2>/dev/null | tr ' ' '\n' | grep -c ".")
  OK "BD n8n encontrada — $TABLES tablas"
  WF=$(sqlite3 "$N8N_DB" "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null)
  OK "Workflows en n8n: $WF"
  EXEC=$(sqlite3 "$N8N_DB" "SELECT COUNT(*) FROM execution_entity;" 2>/dev/null)
  OK "Ejecuciones en n8n: $EXEC"
else
  echo -e "  ${YELLOW}[SKIP]${NC} BD n8n no encontrada en ruta proot (normal si n8n no corrió aún)"
fi

# ── 8. DELETE y cleanup ──────────────────────────────────────
INFO "Probando DELETE..."
sqlite3 "$DB" "DELETE FROM mensajes WHERE usuario='user_789';"
COUNT_DEL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM mensajes;")
[ "$COUNT_DEL" = "4" ] && OK "DELETE: 1 fila eliminada, quedan $COUNT_DEL" || FAIL "DELETE no funcionó"

# ── Resumen ──────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}✓ TEST 1 PASADO — SQLite funciona correctamente${NC}"
else
  echo -e "  ${RED}${BOLD}✗ TEST 1: $ERRORS error(s) — revisar arriba${NC}"
fi
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
echo ""
echo -e "  BD de prueba guardada en: ${BOLD}$DB${NC}"
echo -e "  Puedes explorarla con: ${CYAN}sqlite3 $DB${NC}"
echo ""

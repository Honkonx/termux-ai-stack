#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · menu_nativo.sh
#  Módulos NATIVOS Termux (sin proot):
#    check_claude, check_ollama, check_expo,
#    check_python, check_remote
#    submenu_ollama, submenu_claude, submenu_code_tools,
#    submenu_expo, submenu_python, submenu_sqlite,
#    submenu_trading, submenu_activos, submenu_remote,
#    submenu_backup, submenu_desinstalar, uninstall_module
#
#  Cargado via 'source' por menu.sh — no ejecutar directamente.
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 5.0.0 | Mayo 2026
# ============================================================

# ════════════════════════════════════════════
#  CHECKS DE ESTADO — MÓDULOS NATIVOS
# ════════════════════════════════════════════

check_claude() {
  local cli_path wrapper_path
  cli_path=$(find_claude_cli)
  wrapper_path="$TERMUX_PREFIX/bin/claude"
  local wrapper_ok=false cli_ok=false
  [ -f "$wrapper_path" ] && [ -s "$wrapper_path" ] && wrapper_ok=true
  [ -f "$cli_path" ]     && [ -s "$cli_path" ]     && cli_ok=true

  if [ "$wrapper_ok" = "false" ] && [ "$cli_ok" = "false" ]; then
    echo "not_installed||"; return
  fi

  # Reparar registry silenciosamente si wrapper existe pero registry no
  if [ "$(get_reg claude_code installed)" != "true" ] && \
     { [ "$wrapper_ok" = "true" ] || [ "$cli_ok" = "true" ]; }; then
    local ver_repair
    ver_repair=$(node "$cli_path" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver_repair" ] && ver_repair="2.1.111"
    grep -v "^claude_code\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null || touch "$REGISTRY.tmp"
    cat >> "$REGISTRY.tmp" << EOF
claude_code.installed=true
claude_code.version=$ver_repair
claude_code.install_date=$(date +%Y-%m-%d)
claude_code.location=termux_native
EOF
    mv "$REGISTRY.tmp" "$REGISTRY"
  fi

  [ "$cli_ok" = "false" ] && [ "$wrapper_ok" = "true" ] && {
    echo "ready|err:reinstalar|"; return
  }

  local ver; ver=$(get_reg claude_code version)
  if [ -z "$ver" ] || [ "$ver" = "unknown" ]; then
    ver=$(node "$cli_path" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  fi
  [ -z "$ver" ] && ver="err:reinstalar"
  echo "ready|${ver}|"
}

check_ollama() {
  [ "$(get_reg ollama installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver
  ver=$(pkg show ollama 2>/dev/null | grep "^Version:" | awk '{print $2}')
  [ -z "$ver" ] && ver=$(get_reg ollama version)
  [ -z "$ver" ] && ver="?"
  tmux has-session -t "ollama-server" 2>/dev/null \
    && echo "running|${ver}|" || echo "stopped|${ver}|"
}

check_expo() {
  [ "$(get_reg expo installed)" = "true" ] || { echo "not_installed||"; return; }
  echo "ready|$(get_reg expo version)|"
}

check_python() {
  [ "$(get_reg python installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver; ver=$(get_reg python version)
  [ -z "$ver" ] && ver="?"
  echo "ready|${ver}|"
}

check_remote() {
  local ssh_installed dashboard_installed
  ssh_installed=$(get_reg ssh installed)
  dashboard_installed=$(get_reg dashboard installed)

  local has_remote=false
  [ "$ssh_installed" = "true" ] || [ "$dashboard_installed" = "true" ] && has_remote=true
  [ -f "$REMOTE_SCRIPTS/dashboard_server.py" ] && has_remote=true

  if [ "$has_remote" = "false" ]; then
    echo "not_installed||"; return
  fi

  local ssh_ver; ssh_ver=$(get_reg ssh version)
  ssh_ver="${ssh_ver#v}"
  [ -z "$ssh_ver" ] && ssh_ver="?"

  local ssh_active=false db_active=false
  pgrep -x sshd &>/dev/null              && ssh_active=true
  pgrep -f "dashboard_server.py" &>/dev/null && db_active=true

  local status_detail=""
  $ssh_active && status_detail="SSH●"
  $db_active  && status_detail="${status_detail}${status_detail:+ }DB●"
  [ -z "$status_detail" ] && status_detail="listo"

  if $ssh_active || $db_active; then
    echo "running|${ssh_ver}|${status_detail}"
  else
    echo "stopped|${ssh_ver}|"
  fi
}

# ════════════════════════════════════════════
#  VARIABLES GLOBALES OLLAMA
# ════════════════════════════════════════════
OLLAMA_CFG="$HOME/.ollama_chat_config"
OLLAMA_DB="$HOME/ollama_chat.db"
OLLAMA_URL_LOCAL="http://localhost:11434"
OLLAMA_USER_CFG="$HOME/.ollama_user_config"

# ── Carga parámetros de inferencia y system prompt ───────────
_ollama_load_params() {
  OLLAMA_TEMP=0.7
  OLLAMA_TOP_P=0.9
  OLLAMA_TOP_K=40
  OLLAMA_REP_PENALTY=1.1
  OLLAMA_NUM_CTX=2048
  OLLAMA_NUM_PREDICT=2048
  OLLAMA_SYSTEM_PROMPT=""
  OLLAMA_ROLE="Asistente técnico especializado"
  OLLAMA_GOAL="Ayudar al usuario con sus tareas"
  OLLAMA_TONE="profesional, amigable"
  OLLAMA_DELIVERABLE="Respuesta clara y útil"
  [ -f "$OLLAMA_USER_CFG" ] && source "$OLLAMA_USER_CFG" 2>/dev/null
}

# ── Guarda parámetros en ~/.ollama_user_config ───────────────
_ollama_save_params() {
  local _SP="${OLLAMA_SYSTEM_PROMPT//\"/\\\"}"
  local _RO="${OLLAMA_ROLE//\"/\\\"}"
  local _GO="${OLLAMA_GOAL//\"/\\\"}"
  local _TO="${OLLAMA_TONE//\"/\\\"}"
  local _DE="${OLLAMA_DELIVERABLE//\"/\\\"}"
  cat > "$OLLAMA_USER_CFG" << EOF
# termux-ai-stack · ~/.ollama_user_config
# Generado automáticamente por el menú — editar con cuidado

OLLAMA_TEMP=$OLLAMA_TEMP
OLLAMA_TOP_P=$OLLAMA_TOP_P
OLLAMA_TOP_K=$OLLAMA_TOP_K
OLLAMA_REP_PENALTY=$OLLAMA_REP_PENALTY
OLLAMA_NUM_CTX=$OLLAMA_NUM_CTX
OLLAMA_NUM_PREDICT=$OLLAMA_NUM_PREDICT
OLLAMA_SYSTEM_PROMPT="$_SP"
OLLAMA_ROLE="$_RO"
OLLAMA_GOAL="$_GO"
OLLAMA_TONE="$_TO"
OLLAMA_DELIVERABLE="$_DE"
EOF
}

# ── Retorna el system prompt efectivo ────────────────────────
# Si OLLAMA_SYSTEM_PROMPT tiene contenido lo usa directo.
# Si está vacío construye desde ROLE + GOAL + TONE + DELIVERABLE.
_ollama_get_prompt_effective() {
  if [ -n "$OLLAMA_SYSTEM_PROMPT" ]; then
    echo "$OLLAMA_SYSTEM_PROMPT"
  else
    echo "${OLLAMA_ROLE}. ${OLLAMA_GOAL}. Tono: ${OLLAMA_TONE}. Entrega: ${OLLAMA_DELIVERABLE}."
  fi
}

# ── Valida número decimal con bc. Retorna 0 si válido. ───────
_ollama_validate_float() {
  local val="$1" min="$2" max="$3"
  [[ "$val" =~ ^[0-9]*\.?[0-9]+$ ]] || return 1
  command -v bc &>/dev/null || return 0
  local ok
  ok=$(echo "$val >= $min && $val <= $max" | bc -l 2>/dev/null)
  [ "$ok" = "1" ]
}

_ollama_get_db() {
  local model_safe
  model_safe=$(echo "$1" | tr ':' '_' | tr '/' '_')
  echo "$HOME/ollama_${model_safe}.db"
}

_ollama_ensure_server() {
  curl -sf "$OLLAMA_URL_LOCAL" &>/dev/null && return 0
  echo -e "  ${YELLOW}[AVISO]${NC} Ollama no está corriendo."
  echo -n "  ¿Iniciarlo ahora? (s/n): "
  read -r _ANS < /dev/tty
  [ "$_ANS" = "s" ] || [ "$_ANS" = "S" ] || return 1
  [ -f "$OLLAMA_SCRIPTS/ollama_start.sh" ] && bash "$OLLAMA_SCRIPTS/ollama_start.sh" &>/dev/null \
    || { ollama serve &>/dev/null & sleep 4; }
  sleep 2
  curl -sf "$OLLAMA_URL_LOCAL" &>/dev/null \
    && echo -e "  ${GREEN}[OK]${NC} Servidor iniciado" \
    || echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar"
}

_ollama_list_models() {
  ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^$"
}

_ollama_list_vision_models() {
  ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | \
    grep -E "moondream|llava|bakllava|llama3.2-vision|minicpm-v|qwen.*vl|gemma.*vision" | \
    grep -v "^$"
}

_ollama_pick_model() {
  local filter="$1"
  if [ "$filter" = "vision" ]; then
    mapfile -t MODELS < <(_ollama_list_vision_models)
  else
    mapfile -t MODELS < <(_ollama_list_models)
  fi
  if [ ${#MODELS[@]} -eq 0 ]; then
    if [ "$filter" = "vision" ]; then
      echo -e "  ${YELLOW}[AVISO]${NC} No hay modelos de visión."
      echo -e "  ${DIM}Recomendados: llava-phi3:3.8b (~2.5GB) o moondream:1.8b (~1.1GB)${NC}"
    else
      echo -e "  ${YELLOW}[AVISO]${NC} No hay modelos instalados. Ve a [5] Modelos."
    fi
    PICKED_MODEL=""; return 1
  fi
  echo ""; echo -e "  ${CYAN}Modelos disponibles:${NC}"; echo ""
  for i in "${!MODELS[@]}"; do
    printf "    ${BOLD}[%d]${NC} %s\n" "$((i+1))" "${MODELS[$i]}"
  done
  echo ""; printf "  Elige (1-%d): " "${#MODELS[@]}"
  local CHOICE
  read -r CHOICE < /dev/tty
  [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && \
  [ "$CHOICE" -le "${#MODELS[@]}" ] && {
    PICKED_MODEL="${MODELS[$((CHOICE-1))]}"; return 0
  }
  echo -e "  ${RED}[ERROR]${NC} Número inválido."
  PICKED_MODEL=""; return 1
}

_ollama_load_cfg() {
  OL_RAM_MSGS=4; OL_DISK_MSGS=50; OL_USER_ID=""
  [ -f "$OLLAMA_CFG" ] && source "$OLLAMA_CFG" 2>/dev/null
}

_ollama_save_cfg() {
  local tmp="$OLLAMA_CFG.tmp"
  grep -v "^OL_RAM_MSGS=\|^OL_DISK_MSGS=" "$OLLAMA_CFG" > "$tmp" 2>/dev/null || touch "$tmp"
  echo "OL_RAM_MSGS=$OL_RAM_MSGS"   >> "$tmp"
  echo "OL_DISK_MSGS=$OL_DISK_MSGS" >> "$tmp"
  mv "$tmp" "$OLLAMA_CFG"
}

_ollama_ensure_user_id() {
  if [ -z "$OL_USER_ID" ]; then
    echo ""; echo -e "  ${CYAN}Primera vez en este equipo.${NC}"
    echo -n "  Tu nombre (para identificar tus chats): "
    read -r OL_USER_ID < /dev/tty
    OL_USER_ID=$(echo "$OL_USER_ID" | tr ' ' '_' | tr -cd '[:alnum:]_-')
    [ -z "$OL_USER_ID" ] && OL_USER_ID="usuario"
    grep -v "^OL_USER_ID=" "$OLLAMA_CFG" > "$OLLAMA_CFG.tmp" 2>/dev/null || touch "$OLLAMA_CFG.tmp"
    echo "OL_USER_ID=$OL_USER_ID" >> "$OLLAMA_CFG.tmp"
    mv "$OLLAMA_CFG.tmp" "$OLLAMA_CFG"
    echo -e "  ${GREEN}[OK]${NC} Bienvenido/a ${BOLD}$OL_USER_ID${NC}"
    echo ""
  fi
}

_ollama_init_db() {
  python3 -c "
import sqlite3, os
db = os.path.expanduser('$OLLAMA_DB')
conn = sqlite3.connect(db)
conn.execute('''CREATE TABLE IF NOT EXISTS historial (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_id   TEXT NOT NULL,
  rol       TEXT NOT NULL,
  content   TEXT NOT NULL,
  modelo    TEXT,
  tiene_img INTEGER DEFAULT 0,
  fecha     TEXT
)''')
conn.execute('CREATE INDEX IF NOT EXISTS idx_c ON historial(chat_id)')
conn.commit(); conn.close()
"
}

# ── Chat completo con historial SQLite ────────────────────────
_ollama_chat_full() {
  local MODEL="$1"
  _ollama_load_cfg
  _ollama_ensure_user_id
  local model_safe
  model_safe=$(echo "$MODEL" | tr ':' '_' | tr '/' '_')
  local CHAT_ID="${OL_USER_ID}_${model_safe}"
  OLLAMA_DB=$(_ollama_get_db "$MODEL")
  _ollama_init_db

  # Helper Python escrito en HOME (no /tmp — noexec Android 15)
  local _CHATPY="$HOME/.ollama_chat_helper.py"
  _ollama_load_params
  local _SYS; _SYS=$(_ollama_get_prompt_effective)
  cat > "$_CHATPY" << 'PYEOF'
import sys, sqlite3, os, json
from urllib import request as ureq
from datetime import datetime

db_path     = os.path.expanduser(sys.argv[1])
chat_id     = sys.argv[2]
model       = sys.argv[3]
ram_msgs    = int(sys.argv[4])
disk_msgs   = int(sys.argv[5])
url         = sys.argv[6]
user_msg    = sys.argv[7]
system_p    = sys.argv[8]  if len(sys.argv) > 8  else ""
temperature = float(sys.argv[9])  if len(sys.argv) > 9  else 0.7
top_p       = float(sys.argv[10]) if len(sys.argv) > 10 else 0.9
top_k       = int(sys.argv[11])   if len(sys.argv) > 11 else 40
rep_penalty = float(sys.argv[12]) if len(sys.argv) > 12 else 1.1
num_ctx     = int(sys.argv[13])   if len(sys.argv) > 13 else 2048
num_predict = int(sys.argv[14])   if len(sys.argv) > 14 else 2048

conn = sqlite3.connect(db_path)
conn.execute("""CREATE TABLE IF NOT EXISTS historial (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_id TEXT NOT NULL, rol TEXT NOT NULL,
  content TEXT NOT NULL, modelo TEXT,
  tiene_img INTEGER DEFAULT 0, fecha TEXT)""")
conn.execute("CREATE INDEX IF NOT EXISTS idx_c ON historial(chat_id)")
conn.commit()

rows = conn.execute(
    "SELECT rol, content FROM historial WHERE chat_id=? ORDER BY id DESC LIMIT ?",
    (chat_id, ram_msgs)).fetchall()
lines = [("Usuario" if r[0]=="user" else "Asistente")+": "+r[1] for r in reversed(rows)]
lines.append("Usuario: " + user_msg)
lines.append("Asistente:")
prompt = "\n".join(lines)

payload = json.dumps({
    "model": model,
    "prompt": prompt,
    "system": system_p,
    "stream": False,
    "options": {
        "temperature": temperature,
        "top_p": top_p,
        "top_k": top_k,
        "repeat_penalty": rep_penalty,
        "num_ctx": num_ctx,
        "num_predict": num_predict
    }
}).encode("utf-8")

try:
    req = ureq.Request(url+"/api/generate", data=payload,
                       headers={"Content-Type": "application/json"})
    with ureq.urlopen(req, timeout=600) as resp:
        response = json.loads(resp.read()).get("response","").strip()
except Exception as e:
    response = "[ERROR] " + str(e)

print(response)

now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
conn.execute("INSERT INTO historial (chat_id,rol,content,modelo,fecha) VALUES (?,?,?,?,?)",
    (chat_id,"user",user_msg,None,now))
conn.execute("INSERT INTO historial (chat_id,rol,content,modelo,fecha) VALUES (?,?,?,?,?)",
    (chat_id,"assistant",response,model,now))
total = conn.execute("SELECT COUNT(*) FROM historial WHERE chat_id=?",(chat_id,)).fetchone()[0]
if total > disk_msgs:
    ids=[str(r[0]) for r in conn.execute(
        "SELECT id FROM historial WHERE chat_id=? ORDER BY id ASC LIMIT ?",
        (chat_id,total-disk_msgs)).fetchall()]
    conn.execute("DELETE FROM historial WHERE id IN ({})".format(",".join(ids)))
conn.commit(); conn.close()
PYEOF

  clear; echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo -e "  ║  💬 Chat completo — $MODEL"
  echo -e "  ╠══════════════════════════════════════════╣${NC}"
  echo -e "  Contexto activo: ${GREEN}$OL_RAM_MSGS mensajes${NC} en RAM"
  echo -e "  Historial total: ${CYAN}$OL_DISK_MSGS mensajes${NC} en disco"
  echo -e "  Chat ID: ${DIM}$CHAT_ID${NC}"
  echo -e "  ${DIM}'salir'/'/bye' → salir · '/limpiar' → borrar contexto · '/stats' → info${NC}"
  echo ""

  while true; do
    echo -en "  ${GREEN}Tú:${NC} "
    read -r USER_INPUT < /dev/tty
    [ "$USER_INPUT" = "salir" ] || [ "$USER_INPUT" = "/bye" ] && break
    [ -z "$USER_INPUT" ] && continue

    if [ "$USER_INPUT" = "/limpiar" ]; then
      python3 -c "
import sqlite3, os
conn = sqlite3.connect(os.path.expanduser('$OLLAMA_DB'))
conn.execute('DELETE FROM historial WHERE chat_id=?', ('$CHAT_ID',))
conn.commit(); conn.close()
print('  [OK] Contexto limpiado')
" 2>/dev/null; continue
    fi

    if [ "$USER_INPUT" = "/stats" ]; then
      python3 -c "
import sqlite3, os
conn = sqlite3.connect(os.path.expanduser('$OLLAMA_DB'))
total    = conn.execute('SELECT COUNT(*) FROM historial WHERE chat_id=?',('$CHAT_ID',)).fetchone()[0]
all_c    = conn.execute('SELECT COUNT(DISTINCT chat_id) FROM historial').fetchone()[0]
all_msgs = conn.execute('SELECT COUNT(*) FROM historial').fetchone()[0]
conn.close()
print(f'  Chat actual : {total} mensajes')
print(f'  Total en BD : {all_msgs} mensajes en {all_c} chats')
" 2>/dev/null; continue
    fi

    # Spinner
    local _SC="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏" _SI=0
    ( while true; do
        printf "\r  ${CYAN}Bot:${NC} ${DIM}%s pensando...${NC}" "${_SC:$((_SI%${#_SC})):1}"
        _SI=$((_SI+1)); sleep 0.12
      done ) &
    local _SP=$!

    RESPONSE=$(python3 "$_CHATPY" \
      "$OLLAMA_DB" "$CHAT_ID" "$MODEL" \
      "$OL_RAM_MSGS" "$OL_DISK_MSGS" \
      "$OLLAMA_URL_LOCAL" "$USER_INPUT" \
      "$_SYS" "$OLLAMA_TEMP" "$OLLAMA_TOP_P" \
      "$OLLAMA_TOP_K" "$OLLAMA_REP_PENALTY" \
      "$OLLAMA_NUM_CTX" "$OLLAMA_NUM_PREDICT")

    kill $_SP 2>/dev/null; wait $_SP 2>/dev/null
    printf "\r\033[2K"
    echo -e "  ${CYAN}Bot:${NC} $RESPONSE"; echo ""
  done

  rm -f "$_CHATPY"
  echo ""; echo -e "  ${DIM}Chat guardado. ID: $CHAT_ID${NC}"
  echo ""; read -r _ < /dev/tty
}

# ── Chat con imágenes ─────────────────────────────────────────
_ollama_chat_vision() {
  local MODEL="$1"
  _ollama_load_cfg
  _ollama_ensure_user_id
  local model_safe
  model_safe=$(echo "$MODEL" | tr ':' '_' | tr '/' '_')
  local CHAT_ID="${OL_USER_ID}_${model_safe}_vision"
  OLLAMA_DB=$(_ollama_get_db "$MODEL")
  _ollama_init_db

  # Helper Python para rama texto (sin imagen)
  local _VISIONPY="$HOME/.ollama_vision_helper.py"
  cat > "$_VISIONPY" << 'PYEOF'
import sys, sqlite3, os, json
from urllib import request as ureq
from datetime import datetime

db_path   = os.path.expanduser(sys.argv[1])
chat_id   = sys.argv[2]
model     = sys.argv[3]
ram_msgs  = int(sys.argv[4])
disk_msgs = int(sys.argv[5])
url       = sys.argv[6]
user_msg  = sys.argv[7]

conn = sqlite3.connect(db_path)
conn.execute("""CREATE TABLE IF NOT EXISTS historial (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_id TEXT NOT NULL, rol TEXT NOT NULL,
  content TEXT NOT NULL, modelo TEXT,
  tiene_img INTEGER DEFAULT 0, fecha TEXT)""")
conn.execute("CREATE INDEX IF NOT EXISTS idx_c ON historial(chat_id)")
conn.commit()

rows = conn.execute(
    "SELECT rol, content FROM historial WHERE chat_id=? ORDER BY id DESC LIMIT ?",
    (chat_id, ram_msgs)).fetchall()
lines = [("Usuario" if r[0]=="user" else "Asistente")+": "+r[1] for r in reversed(rows)]
lines.append("Usuario: " + user_msg)
lines.append("Asistente:")
prompt = "\n".join(lines)

payload = json.dumps({
    "model": model, "prompt": prompt, "stream": False,
    "options": {"num_predict": 300, "temperature": 0.7}
}).encode("utf-8")

try:
    req = ureq.Request(url+"/api/generate", data=payload,
                       headers={"Content-Type": "application/json"})
    with ureq.urlopen(req, timeout=600) as resp:
        response = json.loads(resp.read()).get("response","").strip()
except Exception as e:
    response = "[ERROR] " + str(e)

print(response)

now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
conn.execute("INSERT INTO historial (chat_id,rol,content,modelo,tiene_img,fecha) VALUES (?,?,?,?,?,?)",
    (chat_id,"user",user_msg,None,0,now))
conn.execute("INSERT INTO historial (chat_id,rol,content,modelo,tiene_img,fecha) VALUES (?,?,?,?,?,?)",
    (chat_id,"assistant",response,model,0,now))
total = conn.execute("SELECT COUNT(*) FROM historial WHERE chat_id=?",(chat_id,)).fetchone()[0]
if total > disk_msgs:
    ids=[str(r[0]) for r in conn.execute(
        "SELECT id FROM historial WHERE chat_id=? ORDER BY id ASC LIMIT ?",
        (chat_id,total-disk_msgs)).fetchall()]
    conn.execute("DELETE FROM historial WHERE id IN ({})".format(",".join(ids)))
conn.commit(); conn.close()
PYEOF

  clear; echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo -e "  ║  🖼  Chat imágenes — $MODEL"
  echo -e "  ╠══════════════════════════════════════════╣${NC}"
  echo -e "  Contexto: ${GREEN}$OL_RAM_MSGS mensajes${NC} en RAM"
  echo -e "  ${DIM}'salir' · '/imagen RUTA' · '/camara' · '/stats'${NC}"
  echo ""

  local LAST_IMG_B64="" LAST_IMG_PATH=""

  while true; do
    echo -en "  ${GREEN}Tú:${NC} "
    read -r USER_INPUT < /dev/tty
    [ "$USER_INPUT" = "salir" ] || [ "$USER_INPUT" = "/bye" ] && break
    [ -z "$USER_INPUT" ] && continue

    # /imagen
    if [[ "$USER_INPUT" == /imagen* ]]; then
      local IMG_PATH="${USER_INPUT#/imagen }"
      IMG_PATH="${IMG_PATH//\'/}"
      IMG_PATH=$(eval echo "$IMG_PATH" 2>/dev/null || echo "$IMG_PATH")
      if [ ! -f "$IMG_PATH" ]; then
        echo -e "  ${RED}[ERROR]${NC} No encontrado: $IMG_PATH"; continue
      fi
      local IMG_BYTES WORK_IMG
      IMG_BYTES=$(stat -c%s "$IMG_PATH" 2>/dev/null || echo 0)
      WORK_IMG="$IMG_PATH"
      if [ "$IMG_BYTES" -gt 500000 ]; then
        echo -en "  Redimensionando..."
        python3 -c "
from PIL import Image; import os
img=Image.open('$IMG_PATH'); w,h=img.size; r=min(512/w,512/h)
img=img.resize((int(w*r),int(h*r)),Image.LANCZOS)
out=os.path.expanduser('~/vision_tmp.jpg')
img.save(out,'JPEG',quality=80)
print(f' {w}x{h}→{img.size[0]}x{img.size[1]}')
" 2>/dev/null && WORK_IMG="$HOME/vision_tmp.jpg" || echo " (sin Pillow)"
      fi
      LAST_IMG_B64=$(base64 -w 0 "$WORK_IMG" 2>/dev/null)
      LAST_IMG_PATH="$IMG_PATH"
      [ -n "$LAST_IMG_B64" ] \
        && echo -e "  ${GREEN}[OK]${NC} Imagen cargada: $(basename "$IMG_PATH")" \
        || { echo -e "  ${RED}[ERROR]${NC} No se pudo leer"; LAST_IMG_B64=""; }
      continue
    fi

    # /camara
    if [ "$USER_INPUT" = "/camara" ]; then
      local LAST_CAM
      LAST_CAM=$(find /sdcard/DCIM/Camera -name "*.jpg" 2>/dev/null | sort | tail -1)
      if [ -n "$LAST_CAM" ]; then
        echo -e "  ${CYAN}Última foto: $LAST_CAM${NC}"
        echo -n "  ¿Usar esta imagen? (s/n): "
        read -r _UC < /dev/tty
        if [ "$_UC" = "s" ] || [ "$_UC" = "S" ]; then
          local IMG_BYTES WORK_IMG
          IMG_BYTES=$(stat -c%s "$LAST_CAM" 2>/dev/null || echo 0)
          WORK_IMG="$LAST_CAM"
          if [ "$IMG_BYTES" -gt 500000 ]; then
            python3 -c "
from PIL import Image; import os
img=Image.open('$LAST_CAM'); w,h=img.size; r=min(512/w,512/h)
img=img.resize((int(w*r),int(h*r)),Image.LANCZOS)
out=os.path.expanduser('~/vision_tmp.jpg'); img.save(out,'JPEG',quality=80)
" 2>/dev/null && WORK_IMG="$HOME/vision_tmp.jpg"
          fi
          LAST_IMG_B64=$(base64 -w 0 "$WORK_IMG" 2>/dev/null)
          LAST_IMG_PATH="$LAST_CAM"
          echo -e "  ${GREEN}[OK]${NC} Imagen cargada. ¿Qué quieres saber?"
        fi
      else
        echo -e "  ${YELLOW}[AVISO]${NC} No hay fotos en /sdcard/DCIM/Camera"
      fi
      continue
    fi

    # /stats
    if [ "$USER_INPUT" = "/stats" ]; then
      python3 -c "
import sqlite3, os
conn = sqlite3.connect(os.path.expanduser('$OLLAMA_DB'))
t = conn.execute('SELECT COUNT(*) FROM historial WHERE chat_id=?',('$CHAT_ID',)).fetchone()[0]
i = conn.execute('SELECT COUNT(*) FROM historial WHERE chat_id=? AND tiene_img=1',('$CHAT_ID',)).fetchone()[0]
conn.close()
print(f'  Chat actual: {t} mensajes ({i} con imagen)')
" 2>/dev/null
      [ -n "$LAST_IMG_PATH" ] && echo -e "  Imagen activa: ${DIM}$LAST_IMG_PATH${NC}"
      continue
    fi

    # Enviar a Ollama
    if [ -n "$LAST_IMG_B64" ]; then
      # Rama imagen — urllib (no requests — regla del proyecto)
      local PROMPT_VISION="You must respond ONLY in Spanish. $USER_INPUT Responde en español."
      local _SC3="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏" _SI3=0
      ( while true; do
          printf "\r  ${CYAN}Bot:${NC} ${DIM}%s analizando imagen...${NC}" "${_SC3:$((_SI3%${#_SC3})):1}"
          _SI3=$((_SI3+1)); sleep 0.12
        done ) &
      local _SP3=$!
      RESPONSE=$(python3 -c "
import json, sys
from urllib import request as ureq
from datetime import datetime
import os, sqlite3

url      = sys.argv[1]; model    = sys.argv[2]
prompt   = sys.argv[3]; img_b64  = sys.argv[4]
db_path  = os.path.expanduser(sys.argv[5])
chat_id  = sys.argv[6]; user_msg = sys.argv[7]
disk_msgs = int(sys.argv[8])

payload = json.dumps({
    'model': model, 'prompt': prompt,
    'images': [img_b64], 'stream': False,
    'options': {'num_predict': 300, 'temperature': 0.1}
}).encode('utf-8')

try:
    req = ureq.Request(url+'/api/generate', data=payload,
                       headers={'Content-Type': 'application/json'})
    with ureq.urlopen(req, timeout=600) as resp:
        response = json.loads(resp.read()).get('response','').strip()
except Exception as e:
    response = '[ERROR] ' + str(e)

print(response)

conn = sqlite3.connect(db_path)
now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
conn.execute('INSERT INTO historial (chat_id,rol,content,modelo,tiene_img,fecha) VALUES (?,?,?,?,?,?)',
    (chat_id,'user',user_msg,None,1,now))
conn.execute('INSERT INTO historial (chat_id,rol,content,modelo,tiene_img,fecha) VALUES (?,?,?,?,?,?)',
    (chat_id,'assistant',response,model,1,now))
total = conn.execute('SELECT COUNT(*) FROM historial WHERE chat_id=?',(chat_id,)).fetchone()[0]
if total > disk_msgs:
    ids=[str(r[0]) for r in conn.execute(
        'SELECT id FROM historial WHERE chat_id=? ORDER BY id ASC LIMIT ?',
        (chat_id,total-disk_msgs)).fetchall()]
    conn.execute('DELETE FROM historial WHERE id IN ({})'.format(','.join(ids)))
conn.commit(); conn.close()
" "$OLLAMA_URL_LOCAL" "$MODEL" "$PROMPT_VISION" "$LAST_IMG_B64" \
  "$OLLAMA_DB" "$CHAT_ID" "$USER_INPUT" "$OL_DISK_MSGS")
      kill $_SP3 2>/dev/null; wait $_SP3 2>/dev/null
      printf "\r\033[2K"
      LAST_IMG_B64=""
    else
      # Rama texto
      local _SC2="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏" _SI2=0
      ( while true; do
          printf "\r  ${CYAN}Bot:${NC} ${DIM}%s pensando...${NC}" "${_SC2:$((_SI2%${#_SC2})):1}"
          _SI2=$((_SI2+1)); sleep 0.12
        done ) &
      local _SP2=$!
      RESPONSE=$(python3 "$_VISIONPY" \
        "$OLLAMA_DB" "$CHAT_ID" "$MODEL" \
        "$OL_RAM_MSGS" "$OL_DISK_MSGS" \
        "$OLLAMA_URL_LOCAL" "$USER_INPUT")
      kill $_SP2 2>/dev/null; wait $_SP2 2>/dev/null
      printf "\r\033[2K"
    fi

    echo -e "  ${CYAN}Bot:${NC} $RESPONSE"; echo ""
  done

  rm -f "$_VISIONPY" "$HOME/vision_tmp.jpg" 2>/dev/null
  echo ""; read -r _ < /dev/tty
}

# ── Config historial SQL ──────────────────────────────────────
_ollama_config_sql() {
  _ollama_load_cfg
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⚙  Config historial SQLite              ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}Mensajes en RAM — Actual: ${GREEN}${OL_RAM_MSGS}${NC}            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}  [1] 2 msg ~50MB   [2] 4 msg ~100MB ←  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}  [3] 6 msg ~150MB  [4] 8 msg ~200MB    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}  [5] Personalizado (1-20)               ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}Mensajes en disco — Actual: ${CYAN}${OL_DISK_MSGS}${NC}          ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}  [6] 20   [7] 50 ←   [8] 100  [9] ∞    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}  [0] Personalizado                      ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[i] Estadísticas BD  [j] Borrar BD       ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver                               ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r COPT < /dev/tty
    case "$COPT" in
      1) OL_RAM_MSGS=2;    _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} RAM: 2 msg" ;;
      2) OL_RAM_MSGS=4;    _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} RAM: 4 msg" ;;
      3) OL_RAM_MSGS=6;    _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} RAM: 6 msg" ;;
      4) OL_RAM_MSGS=8;    _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} RAM: 8 msg" ;;
      5)
        echo -n "  Mensajes en contexto (1-20): "
        read -r VAL < /dev/tty
        [[ "$VAL" =~ ^[0-9]+$ ]] && [ "$VAL" -ge 1 ] && [ "$VAL" -le 20 ] \
          && { OL_RAM_MSGS=$VAL; _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} RAM: $VAL msg"; } \
          || echo -e "  ${RED}[ERROR]${NC} Valor inválido (1-20)" ;;
      6) OL_DISK_MSGS=20;   _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} Disco: 20" ;;
      7) OL_DISK_MSGS=50;   _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} Disco: 50" ;;
      8) OL_DISK_MSGS=100;  _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} Disco: 100" ;;
      9) OL_DISK_MSGS=9999; _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} Disco: sin límite" ;;
      0)
        echo -n "  Mensajes en disco (10-9999): "
        read -r VAL < /dev/tty
        [[ "$VAL" =~ ^[0-9]+$ ]] && [ "$VAL" -ge 10 ] \
          && { OL_DISK_MSGS=$VAL; _ollama_save_cfg; echo -e "  ${GREEN}[OK]${NC} Disco: $VAL"; } \
          || echo -e "  ${RED}[ERROR]${NC} Valor inválido" ;;
      i|I)
        _ollama_init_db; echo ""
        python3 -c "
import sqlite3, os
db = os.path.expanduser('$OLLAMA_DB')
if not os.path.exists(db): print('  BD vacía'); exit()
conn = sqlite3.connect(db)
total   = conn.execute('SELECT COUNT(*) FROM historial').fetchone()[0]
chats   = conn.execute('SELECT COUNT(DISTINCT chat_id) FROM historial').fetchone()[0]
imgs    = conn.execute('SELECT COUNT(*) FROM historial WHERE tiene_img=1').fetchone()[0]
size    = os.path.getsize(db)
modelos = conn.execute('SELECT modelo,COUNT(*) FROM historial WHERE modelo IS NOT NULL GROUP BY modelo').fetchall()
conn.close()
print(f'  Mensajes  : {total}')
print(f'  Chats     : {chats}')
print(f'  Imágenes  : {imgs}')
print(f'  Tamaño BD : {size} bytes')
if modelos:
    print('  Por modelo:')
    for m,c in modelos: print(f'    {m}: {c} resp')
" 2>/dev/null || echo "  BD no existe aún"
        echo ""; read -r _ < /dev/tty ;;
      j|J)
        echo -n "  ¿Borrar TODA la BD de chat? (s/n): "
        read -r _DEL < /dev/tty
        [ "$_DEL" = "s" ] || [ "$_DEL" = "S" ] && {
          rm -f "$OLLAMA_DB" \
            && echo -e "  ${GREEN}[OK]${NC} BD eliminada" \
            || echo -e "  ${RED}[ERROR]${NC}"
        } ;;
      b|B|"") break ;;
    esac
    sleep 1
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ PERSONALIZACIÓN OLLAMA
# ════════════════════════════════════════════
submenu_ollama_personalizacion() {
  _ollama_load_params
  while true; do
    clear; echo ""
    local _PE; _PE=$(_ollama_get_prompt_effective)
    local _PE_SHORT="${_PE:0:35}"
    [ ${#_PE} -gt 35 ] && _PE_SHORT="${_PE_SHORT}..."

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⚙  PERSONALIZACIÓN OLLAMA               ║"
    echo    "  ╠══════════════════════════════════════════╣"
    printf  "  ║  ${NC}[1] Temperatura      actual: %-12s${CYAN}${BOLD}║\n" "$OLLAMA_TEMP"
    printf  "  ║  ${NC}[2] Repeat penalty   actual: %-12s${CYAN}${BOLD}║\n" "$OLLAMA_REP_PENALTY"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[3] System prompt / personalidad        ${CYAN}${BOLD}║"
    printf  "  ║      ${DIM}%-38s${CYAN}${BOLD}║\n" "$_PE_SHORT"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[4] Ver configuración actual            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5] Configuración avanzada              ${CYAN}${BOLD}║"
    echo -e "  ║  ${DIM}    Top P · Top K · Contexto · Tokens   ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[6] Guardar como Modelfile              ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[0] Crear modelo personalizado          ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[r] Restaurar defaults                  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver al menú Ollama               ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r POPT < /dev/tty

    case "$POPT" in

      1)
        echo -n "  Temperatura (0.0-2.0, actual ${OLLAMA_TEMP}): "
        read -r VAL < /dev/tty
        if _ollama_validate_float "$VAL" 0 2; then
          OLLAMA_TEMP="$VAL"; _ollama_save_params
          echo -e "  ${GREEN}[OK]${NC} Temperatura → $OLLAMA_TEMP"
        else
          echo -e "  ${RED}[ERROR]${NC} Valor inválido. Rango: 0.0 – 2.0"
        fi; sleep 1 ;;

      2)
        echo -n "  Repeat penalty (1.0-2.0, actual ${OLLAMA_REP_PENALTY}): "
        read -r VAL < /dev/tty
        if _ollama_validate_float "$VAL" 1 2; then
          OLLAMA_REP_PENALTY="$VAL"; _ollama_save_params
          echo -e "  ${GREEN}[OK]${NC} Repeat penalty → $OLLAMA_REP_PENALTY"
        else
          echo -e "  ${RED}[ERROR]${NC} Valor inválido. Rango: 1.0 – 2.0"
        fi; sleep 1 ;;

      3)
        # ── Editor de system prompt / personalidad ────────────
        while true; do
          clear; echo ""
          echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
          echo    "  ║  ✏  SYSTEM PROMPT / PERSONALIDAD        ║"
          echo    "  ╠══════════════════════════════════════════╣"
          printf  "  ║  ${NC}ROLE:   %-34s${CYAN}${BOLD}║\n" "${OLLAMA_ROLE:0:34}"
          printf  "  ║  ${NC}GOAL:   %-34s${CYAN}${BOLD}║\n" "${OLLAMA_GOAL:0:34}"
          printf  "  ║  ${NC}TONE:   %-34s${CYAN}${BOLD}║\n" "${OLLAMA_TONE:0:34}"
          printf  "  ║  ${NC}ENTREGA:%-34s${CYAN}${BOLD}║\n" "${OLLAMA_DELIVERABLE:0:34}"
          echo    "  ╠══════════════════════════════════════════╣"
          echo -e "  ║  ${NC}[1] Editar ROLE (quién es)              ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[2] Editar GOAL (objetivo)              ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[3] Editar TONE (tono/estilo)           ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[4] Editar DELIVERABLE (entregable)     ${CYAN}${BOLD}║"
          echo    "  ╠══════════════════════════════════════════╣"
          echo -e "  ║  ${NC}[v] Ver prompt efectivo                 ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[c] Limpiar prompt (usar campos meta)   ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[b] Volver                              ${CYAN}${BOLD}║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"
          echo ""; echo -n "  Opción: "
          read -r SPOPT < /dev/tty
          case "$SPOPT" in
            1) echo -n "  ROLE: "; read -r VAL < /dev/tty
               [ -n "$VAL" ] && OLLAMA_ROLE="$VAL"
               _ollama_save_params; echo -e "  ${GREEN}[OK]${NC} ROLE guardado"; sleep 1 ;;
            2) echo -n "  GOAL: "; read -r VAL < /dev/tty
               [ -n "$VAL" ] && OLLAMA_GOAL="$VAL"
               _ollama_save_params; echo -e "  ${GREEN}[OK]${NC} GOAL guardado"; sleep 1 ;;
            3) echo -n "  TONE: "; read -r VAL < /dev/tty
               [ -n "$VAL" ] && OLLAMA_TONE="$VAL"
               _ollama_save_params; echo -e "  ${GREEN}[OK]${NC} TONE guardado"; sleep 1 ;;
            4) echo -n "  DELIVERABLE: "; read -r VAL < /dev/tty
               [ -n "$VAL" ] && OLLAMA_DELIVERABLE="$VAL"
               _ollama_save_params; echo -e "  ${GREEN}[OK]${NC} DELIVERABLE guardado"; sleep 1 ;;
            v|V)
               clear; echo ""
               echo -e "  ${CYAN}${BOLD}PROMPT EFECTIVO:${NC}"; echo ""
               echo -e "  ${DIM}$(_ollama_get_prompt_effective)${NC}"
               echo ""; read -r _ < /dev/tty ;;
            c|C)
               OLLAMA_SYSTEM_PROMPT=""
               _ollama_save_params
               echo -e "  ${GREEN}[OK]${NC} Prompt limpiado — se usarán los campos meta"
               sleep 1 ;;
            b|B|"") break ;;
          esac
        done ;;

      4)
        # ── Ver configuración completa ────────────────────────
        clear; echo ""
        echo -e "  ${CYAN}${BOLD}CONFIGURACIÓN ACTUAL OLLAMA${NC}"; echo ""
        echo -e "  Temperatura       : ${GREEN}$OLLAMA_TEMP${NC}"
        echo -e "  Repeat penalty    : ${GREEN}$OLLAMA_REP_PENALTY${NC}"
        echo -e "  Top P             : ${GREEN}$OLLAMA_TOP_P${NC}"
        echo -e "  Top K             : ${GREEN}$OLLAMA_TOP_K${NC}"
        echo -e "  Contexto (tokens) : ${GREEN}$OLLAMA_NUM_CTX${NC}"
        echo -e "  Max tokens resp   : ${GREEN}$OLLAMA_NUM_PREDICT${NC}"
        echo ""
        echo -e "  ${CYAN}SYSTEM PROMPT EFECTIVO:${NC}"
        echo -e "  ${DIM}$(_ollama_get_prompt_effective)${NC}"
        echo ""
        echo -e "  ${DIM}Archivo: $OLLAMA_USER_CFG${NC}"
        echo ""; read -r _ < /dev/tty ;;

      5)
        # ── Configuración avanzada ────────────────────────────
        while true; do
          clear; echo ""
          echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
          echo    "  ║  ⚙  CONFIGURACIÓN AVANZADA               ║"
          echo    "  ╠══════════════════════════════════════════╣"
          printf  "  ║  ${NC}[1] Top P           actual: %-12s${CYAN}${BOLD}║\n" "$OLLAMA_TOP_P"
          printf  "  ║  ${NC}[2] Top K           actual: %-12s${CYAN}${BOLD}║\n" "$OLLAMA_TOP_K"
          printf  "  ║  ${NC}[3] Contexto tokens actual: %-12s${CYAN}${BOLD}║\n" "$OLLAMA_NUM_CTX"
          printf  "  ║  ${NC}[4] Max tokens resp actual: %-12s${CYAN}${BOLD}║\n" "$OLLAMA_NUM_PREDICT"
          echo    "  ╠══════════════════════════════════════════╣"
          echo -e "  ║  ${NC}[b] Volver                              ${CYAN}${BOLD}║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"
          echo ""; echo -n "  Opción: "
          read -r AOPT < /dev/tty
          case "$AOPT" in
            1) echo -n "  Top P (0.0-1.0, actual ${OLLAMA_TOP_P}): "
               read -r VAL < /dev/tty
               if _ollama_validate_float "$VAL" 0 1; then
                 OLLAMA_TOP_P="$VAL"; _ollama_save_params
                 echo -e "  ${GREEN}[OK]${NC} Top P → $OLLAMA_TOP_P"
               else
                 echo -e "  ${RED}[ERROR]${NC} Valor inválido. Rango: 0.0 – 1.0"
               fi; sleep 1 ;;
            2) echo -n "  Top K (1-100, actual ${OLLAMA_TOP_K}): "
               read -r VAL < /dev/tty
               if [[ "$VAL" =~ ^[0-9]+$ ]] && [ "$VAL" -ge 1 ] && [ "$VAL" -le 100 ]; then
                 OLLAMA_TOP_K="$VAL"; _ollama_save_params
                 echo -e "  ${GREEN}[OK]${NC} Top K → $OLLAMA_TOP_K"
               else
                 echo -e "  ${RED}[ERROR]${NC} Valor inválido. Rango: 1 – 100"
               fi; sleep 1 ;;
            3) echo -n "  Contexto tokens (512-8192, actual ${OLLAMA_NUM_CTX}): "
               read -r VAL < /dev/tty
               if [[ "$VAL" =~ ^[0-9]+$ ]] && [ "$VAL" -ge 512 ] && [ "$VAL" -le 8192 ]; then
                 OLLAMA_NUM_CTX="$VAL"; _ollama_save_params
                 echo -e "  ${GREEN}[OK]${NC} Contexto → $OLLAMA_NUM_CTX tokens"
               else
                 echo -e "  ${RED}[ERROR]${NC} Valor inválido. Rango: 512 – 8192"
               fi; sleep 1 ;;
            4) echo -n "  Max tokens respuesta (128-4096, actual ${OLLAMA_NUM_PREDICT}): "
               read -r VAL < /dev/tty
               if [[ "$VAL" =~ ^[0-9]+$ ]] && [ "$VAL" -ge 128 ] && [ "$VAL" -le 4096 ]; then
                 OLLAMA_NUM_PREDICT="$VAL"; _ollama_save_params
                 echo -e "  ${GREEN}[OK]${NC} Max tokens → $OLLAMA_NUM_PREDICT"
               else
                 echo -e "  ${RED}[ERROR]${NC} Valor inválido. Rango: 128 – 4096"
               fi; sleep 1 ;;
            b|B|"") break ;;
          esac
        done ;;

      6)
        # ── Guardar como Modelfile ────────────────────────────
        clear; echo ""
        echo -e "  ${CYAN}Modelo base para el Modelfile:${NC}"; echo ""
        mapfile -t _MF_MODELS < <(_ollama_list_models)
        if [ ${#_MF_MODELS[@]} -eq 0 ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} No hay modelos instalados. Descarga uno primero."
          echo ""; read -r _ < /dev/tty; continue
        fi
        for i in "${!_MF_MODELS[@]}"; do
          printf "    ${BOLD}[%d]${NC} %s\n" "$((i+1))" "${_MF_MODELS[$i]}"
        done
        echo ""; echo -n "  Elige (número): "
        read -r _MFC < /dev/tty
        local _BASE_MODEL=""
        if [[ "$_MFC" =~ ^[0-9]+$ ]] && [ "$_MFC" -ge 1 ] && \
           [ "$_MFC" -le "${#_MF_MODELS[@]}" ]; then
          _BASE_MODEL="${_MF_MODELS[$((_MFC-1))]}"
        else
          echo -e "  ${RED}[ERROR]${NC} Selección inválida"; sleep 1; continue
        fi
        local _EPROMPT; _EPROMPT=$(_ollama_get_prompt_effective)
        local _EPROMPT_ESC="${_EPROMPT//\"/\\\"}"
        cat > "$HOME/Modelfile" << MFEOF
FROM ${_BASE_MODEL}
SYSTEM """${_EPROMPT_ESC}"""
PARAMETER temperature ${OLLAMA_TEMP}
PARAMETER top_p ${OLLAMA_TOP_P}
PARAMETER top_k ${OLLAMA_TOP_K}
PARAMETER repeat_penalty ${OLLAMA_REP_PENALTY}
PARAMETER num_ctx ${OLLAMA_NUM_CTX}
PARAMETER num_predict ${OLLAMA_NUM_PREDICT}
MFEOF
        echo -e "  ${GREEN}[OK]${NC} Modelfile creado: ~/Modelfile"
        echo -e "  ${DIM}Modelo base: $_BASE_MODEL${NC}"
        echo ""; read -r _ < /dev/tty ;;

      0)
        # ── Crear modelo personalizado ────────────────────────
        clear; echo ""
        if [ ! -f "$HOME/Modelfile" ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} Primero usa [6] para generar el Modelfile."
          echo ""; read -r _ < /dev/tty; continue
        fi
        local _MODEL_NAME
        _MODEL_NAME="mi-asistente-$(date +%Y%m%d-%H%M)"
        echo -e "  ${CYAN}Creando modelo: ${BOLD}$_MODEL_NAME${NC}"; echo ""
        ollama create "$_MODEL_NAME" -f "$HOME/Modelfile"
        if [ $? -eq 0 ]; then
          echo ""
          echo -e "  ${GREEN}[OK]${NC} Modelo creado exitosamente"
          echo -e "  ${DIM}Usar con: ollama run $_MODEL_NAME${NC}"
        else
          echo -e "  ${RED}[ERROR]${NC} Falló la creación del modelo"
        fi
        echo ""; read -r _ < /dev/tty ;;

      r|R)
        echo -n "  ¿Restaurar valores por defecto? (s/n): "
        read -r _CONF < /dev/tty
        if [ "$_CONF" = "s" ] || [ "$_CONF" = "S" ]; then
          OLLAMA_TEMP=0.7; OLLAMA_TOP_P=0.9; OLLAMA_TOP_K=40
          OLLAMA_REP_PENALTY=1.1; OLLAMA_NUM_CTX=2048; OLLAMA_NUM_PREDICT=2048
          OLLAMA_SYSTEM_PROMPT="Eres un asistente técnico especializado en programación y trading. Responde siempre en español. Sé directo y conciso. Si no sabes algo, dilo sin inventar."
          OLLAMA_ROLE="Asistente técnico especializado"
          OLLAMA_GOAL="Ayudar al usuario con programación, trading y automatización"
          OLLAMA_TONE="profesional, directo, amigable"
          OLLAMA_DELIVERABLE="Código funcional o respuesta clara y útil"
          _ollama_save_params
          echo -e "  ${GREEN}[OK]${NC} Valores restaurados"
        fi; sleep 1 ;;

      b|B|"") break ;;
    esac
  done
}


# ════════════════════════════════════════════
#  SUBMENÚ OLLAMA
# ════════════════════════════════════════════
submenu_ollama() {
  local state="$1"
  _ollama_load_cfg
  while true; do
    clear; echo ""
    curl -sf "$OLLAMA_URL_LOCAL" &>/dev/null && state="running"
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    if [ "$state" = "running" ]; then
      echo -e "  ║  ◎ OLLAMA  ${GREEN}● activo${CYAN}${BOLD}    :11434          ║"
    else
      echo    "  ║  ◎ OLLAMA  ○ detenido                   ║"
    fi
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar / detener servidor          ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[2] Chat rápido                         ${CYAN}${BOLD}║"
    echo -e "  ║  ${DIM}    Sin historial · respuesta directa    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Chat completo                       ${CYAN}${BOLD}║"
    echo -e "  ║  ${DIM}    SQLite · RAM:${OL_RAM_MSGS}msg · disco:${OL_DISK_MSGS}msg       ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Chat con imágenes                   ${CYAN}${BOLD}║"
    echo -e "  ║  ${DIM}    Visión · /imagen RUTA · /camara     ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[5] Modelos (ver / descargar / eliminar)${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6] Configurar historial SQLite         ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[7] Personalización (temp/prompt/rol)   ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver al menú principal            ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        if [ "$state" = "running" ]; then
          echo -n "  Ollama activo. ¿Detener? (s/n): "
          read -r _ST < /dev/tty
          [ "$_ST" = "s" ] || [ "$_ST" = "S" ] && {
            tmux kill-session -t "ollama-server" 2>/dev/null
            pkill -f "ollama serve" 2>/dev/null
            sleep 1; echo -e "  ${GREEN}[OK]${NC} Servidor detenido"; state="stopped"
          }
        else
          [ -f "$OLLAMA_SCRIPTS/ollama_start.sh" ] && bash "$OLLAMA_SCRIPTS/ollama_start.sh" \
            || { ollama serve &>/dev/null & sleep 4; }
          curl -sf "$OLLAMA_URL_LOCAL" &>/dev/null \
            && { echo -e "  ${GREEN}[OK]${NC} Servidor iniciado"; state="running"; } \
            || echo -e "  ${RED}[ERROR]${NC} No responde"
        fi
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        _ollama_ensure_server || { read -r _ < /dev/tty; continue; }
        _ollama_pick_model || { sleep 1; continue; }
        echo -e "\n  ${GREEN}[OK]${NC} Chat rápido — ${CYAN}$PICKED_MODEL${NC}"
        echo -e "  ${DIM}Sin historial — /bye para salir${NC}"; echo ""
        ollama run "$PICKED_MODEL" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        _ollama_ensure_server || { read -r _ < /dev/tty; continue; }
        _ollama_pick_model || { sleep 1; continue; }
        _ollama_chat_full "$PICKED_MODEL" ;;
      4)
        clear; echo ""
        _ollama_ensure_server || { read -r _ < /dev/tty; continue; }
        echo -e "  ${CYAN}Modelos de visión disponibles:${NC}"
        _ollama_pick_model "vision"
        if [ -z "$PICKED_MODEL" ]; then
          echo ""
          echo -e "  ${BOLD}¿Descargar modelo de visión ahora?${NC}"; echo ""
          echo "    [1] llava-phi3:3.8b  ~2.5GB  ← recomendado"
          echo "    [2] moondream:1.8b   ~1.1GB  más rápido"
          echo "    [b] Cancelar"
          echo ""; echo -n "  Elige: "
          read -r _DV < /dev/tty
          case "$_DV" in
            1) ollama pull "llava-phi3:3.8b" && PICKED_MODEL="llava-phi3:3.8b" ;;
            2) ollama pull "moondream:1.8b"  && PICKED_MODEL="moondream:1.8b" ;;
            *) continue ;;
          esac
        fi
        [ -n "$PICKED_MODEL" ] && _ollama_chat_vision "$PICKED_MODEL" ;;
      5)
        while true; do
          clear; echo ""
          echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
          echo    "  ║  ◎ Modelos instalados                    ║"
          echo -e "  ╠══════════════════════════════════════════╣${NC}"
          ollama list 2>/dev/null | tail -n +2 | \
            awk '{printf "  ║  %-26s  %s %s\n", $1, $3, $4}' | head -12
          echo ""
          echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
          echo -e "  ║  ${NC}[d] Descargar  [r] Eliminar  [b] Volver  ${CYAN}${BOLD}║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"
          echo ""; echo -n "  Opción: "
          read -r MOPT < /dev/tty
          case "$MOPT" in
            d|D)
              clear; echo ""
              echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
              echo    "  ║  ◎ Descargar modelo                      ║"
              echo    "  ╠══════════════════════════════════════════╣"
              echo -e "  ║  ${NC}TEXTO${CYAN}${BOLD}                                    ║"
              echo -e "  ║  ${NC}  [1] qwen2.5:0.5b  ~397MB  liviano      ${CYAN}${BOLD}║"
              echo -e "  ║  ${NC}  [2] qwen2.5:1.5b  ~986MB  balance      ${CYAN}${BOLD}║"
              echo -e "  ║  ${NC}  [3] qwen2.5:3b    ~1.9GB  buena cal.   ${CYAN}${BOLD}║"
              echo -e "  ║  ${NC}  [4] gemma3:4b     ~2.5GB  excelente    ${CYAN}${BOLD}║"
              echo -e "  ║  ${NC}  [5] llama3.2:3b   ~2.0GB  multilingüe  ${CYAN}${BOLD}║"
              echo    "  ╠══════════════════════════════════════════╣"
              echo -e "  ║  ${NC}IMAGEN${CYAN}${BOLD}                                   ║"
              echo -e "  ║  ${NC}  [6] moondream:1.8b  ~1.1GB  rápido     ${CYAN}${BOLD}║"
              echo -e "  ║  ${NC}  [7] llava-phi3:3.8b ~2.5GB  ← recomend ${CYAN}${BOLD}║"
              echo -e "  ║  ${NC}  [8] llava:7b         ~4.7GB  alta cal.  ${CYAN}${BOLD}║"
              echo    "  ╠══════════════════════════════════════════╣"
              echo -e "  ║  ${NC}  [9] Nombre manual   [b] Cancelar       ${CYAN}${BOLD}║"
              echo -e "  ╚══════════════════════════════════════════╝${NC}"
              echo ""; echo -n "  Elige: "
              read -r DC < /dev/tty
              case "$DC" in
                1) DL="qwen2.5:0.5b"    ;; 2) DL="qwen2.5:1.5b"    ;;
                3) DL="qwen2.5:3b"      ;; 4) DL="gemma3:4b"        ;;
                5) DL="llama3.2:3b"     ;; 6) DL="moondream:1.8b"   ;;
                7) DL="llava-phi3:3.8b" ;; 8) DL="llava:7b"         ;;
                9) echo -n "  Nombre: "; read -r DL < /dev/tty ;;
                *) DL="" ;;
              esac
              [ -n "$DL" ] && { echo ""; ollama pull "$DL"; echo ""; read -r _ < /dev/tty; } ;;
            r|R)
              echo ""; _ollama_pick_model
              [ -n "$PICKED_MODEL" ] && {
                echo -n "  ¿Eliminar $PICKED_MODEL? (s/n): "
                read -r _DEL < /dev/tty
                [ "$_DEL" = "s" ] || [ "$_DEL" = "S" ] && {
                  ollama rm "$PICKED_MODEL" \
                    && echo -e "  ${GREEN}[OK]${NC} Eliminado" \
                    || echo -e "  ${RED}[ERROR]${NC}"
                  sleep 1
                }
              } ;;
            b|B|"") break ;;
          esac
        done ;;
      6) _ollama_config_sql ;;
      7) submenu_ollama_personalizacion ;;
      b|B|"") break ;;
    esac
    _ollama_load_cfg
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ CLAUDE CODE
# ════════════════════════════════════════════
submenu_claude() {
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◆ CLAUDE CODE  ● listo                 ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Abrir en directorio actual          ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Abrir en proyecto                   ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Gestionar proyectos                 ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Actualizar Claude Code              ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver                              ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        local CLI_PATH; CLI_PATH=$(find_claude_cli)
        if [ ! -f "$CLI_PATH" ]; then
          echo -e "\n  ${RED}[ERROR]${NC} cli.js no encontrado."
          echo "  Reinstala desde [0] → Restore → GitHub → claude"
          echo ""; read -r _ < /dev/tty; continue
        fi
        echo -e "\n  ${CYAN}Abriendo Claude Code en $(pwd)...${NC}\n"
        DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 node "$CLI_PATH" ;;
      2)
        clear; echo ""
        local CLI_PATH; CLI_PATH=$(find_claude_cli)
        [ ! -f "$CLI_PATH" ] && {
          echo -e "  ${RED}[ERROR]${NC} cli.js no encontrado."
          read -r _ < /dev/tty; continue
        }
        mkdir -p "$HOME/proyectos"
        mapfile -t PROJS < <(ls -1 "$HOME/proyectos/" 2>/dev/null)
        echo -e "  ${CYAN}Proyectos en ~/proyectos/:${NC}"; echo ""
        local IDX=1
        [ ${#PROJS[@]} -gt 0 ] \
          && for p in "${PROJS[@]}"; do printf "    [%d] %s\n" "$IDX" "$p"; IDX=$((IDX+1)); done \
          || echo "    (ninguno)"
        echo ""; echo "    [m] Ruta manual  [d] Download  [b] Volver"
        echo ""; echo -n "  Elige: "
        read -r PCHOICE < /dev/tty
        local TARGET_DIR=""
        case "$PCHOICE" in
          m|M) echo -n "  Ruta: "; read -r TARGET_DIR < /dev/tty ;;
          d|D)
            mapfile -t DL_DIRS < <(find /storage/emulated/0/Download \
              -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -I{} basename {})
            [ ${#DL_DIRS[@]} -eq 0 ] && { echo "    (ninguna)"; read -r _ < /dev/tty; continue; }
            for i in "${!DL_DIRS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DL_DIRS[$i]}"; done
            echo ""; echo -n "  Número: "; read -r DCHOICE < /dev/tty
            if [[ "$DCHOICE" =~ ^[0-9]+$ ]] && [ "$DCHOICE" -ge 1 ] && \
               [ "$DCHOICE" -le "${#DL_DIRS[@]}" ]; then
              local DNAME="${DL_DIRS[$((DCHOICE-1))]}"
              local LINK_DST="$HOME/proyectos/${DNAME}"
              [ ! -e "$LINK_DST" ] && \
                ln -s "/storage/emulated/0/Download/${DNAME}" "$LINK_DST" 2>/dev/null && \
                echo -e "  ${GREEN}[OK]${NC} Symlink creado"
              TARGET_DIR="$LINK_DST"
            fi ;;
          b|B|"") continue ;;
          *)
            [[ "$PCHOICE" =~ ^[0-9]+$ ]] && [ "$PCHOICE" -ge 1 ] && \
            [ "$PCHOICE" -le "${#PROJS[@]}" ] && \
              TARGET_DIR="$HOME/proyectos/${PROJS[$((PCHOICE-1))]}" ;;
        esac
        if [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ]; then
          echo -e "\n  ${CYAN}Abriendo Claude Code en $TARGET_DIR...${NC}\n"
          cd "$TARGET_DIR" && DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 node "$CLI_PATH"
        elif [ -n "$TARGET_DIR" ]; then
          echo -e "  ${RED}[ERROR]${NC} No existe: $TARGET_DIR"
          read -r _ < /dev/tty
        fi ;;
      3)
        while true; do
          clear; echo ""
          echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
          echo    "  ║  ◆ CLAUDE CODE — Proyectos              ║"
          echo    "  ╠══════════════════════════════════════════╣"
          echo -e "  ║  ${NC}[1] Listar  [2] Nuevo symlink  [3] Borrar${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[b] Volver${CYAN}${BOLD}                             ║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"
          echo ""; echo -n "  Opción: "; read -r GOPT < /dev/tty
          case "$GOPT" in
            1)
              clear; echo ""
              echo -e "  ${BOLD}Proyectos en ~/proyectos/:${NC}"; echo ""
              mkdir -p "$HOME/proyectos"
              ls "$HOME/proyectos/" 2>/dev/null | grep -q . \
                && ls -la "$HOME/proyectos/" \
                || echo -e "  ${DIM}(vacío)${NC}"
              echo ""; read -r _ < /dev/tty ;;
            2)
              clear; echo ""
              mapfile -t DL_DIRS < <(find /storage/emulated/0/Download \
                -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -I{} basename {})
              [ ${#DL_DIRS[@]} -eq 0 ] && {
                echo -e "  ${YELLOW}No hay carpetas en Download${NC}"
                read -r _ < /dev/tty; continue
              }
              for i in "${!DL_DIRS[@]}"; do
                local LDST="$HOME/proyectos/${DL_DIRS[$i]}"
                [ -L "$LDST" ] \
                  && printf "    [%d] %s ${DIM}(ya existe)${NC}\n" "$((i+1))" "${DL_DIRS[$i]}" \
                  || printf "    [%d] %s\n" "$((i+1))" "${DL_DIRS[$i]}"
              done
              echo ""; echo -n "  Número: "; read -r DCHOICE < /dev/tty
              if [[ "$DCHOICE" =~ ^[0-9]+$ ]] && [ "$DCHOICE" -ge 1 ] && \
                 [ "$DCHOICE" -le "${#DL_DIRS[@]}" ]; then
                local DNAME="${DL_DIRS[$((DCHOICE-1))]}"
                local LSRC="/storage/emulated/0/Download/${DNAME}"
                local LDST="$HOME/proyectos/${DNAME}"
                mkdir -p "$HOME/proyectos"
                [ -L "$LDST" ] \
                  && echo -e "  ${YELLOW}[AVISO]${NC} Ya existe: ~/proyectos/${DNAME}" \
                  || { ln -s "$LSRC" "$LDST" 2>/dev/null \
                    && echo -e "  ${GREEN}[OK]${NC} Symlink creado" \
                    || echo -e "  ${RED}[ERROR]${NC}"; }
              fi
              echo ""; read -r _ < /dev/tty ;;
            3)
              clear; echo ""
              mkdir -p "$HOME/proyectos"
              mapfile -t LINKS < <(find "$HOME/proyectos" -maxdepth 1 -type l 2>/dev/null \
                | xargs -I{} basename {})
              [ ${#LINKS[@]} -eq 0 ] && {
                echo -e "  ${DIM}Sin symlinks${NC}"; read -r _ < /dev/tty; continue
              }
              for i in "${!LINKS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${LINKS[$i]}"; done
              echo ""; echo -n "  Número: "; read -r LCHOICE < /dev/tty
              if [[ "$LCHOICE" =~ ^[0-9]+$ ]] && [ "$LCHOICE" -ge 1 ] && \
                 [ "$LCHOICE" -le "${#LINKS[@]}" ]; then
                local LNAME="${LINKS[$((LCHOICE-1))]}"
                echo -n "  ¿Eliminar ~/proyectos/${LNAME}? (s/n): "
                read -r LCONFIRM < /dev/tty
                [ "$LCONFIRM" = "s" ] || [ "$LCONFIRM" = "S" ] && {
                  rm "$HOME/proyectos/$LNAME" \
                    && echo -e "  ${GREEN}[OK]${NC} Eliminado" \
                    || echo -e "  ${RED}[ERROR]${NC}"
                }
              fi
              echo ""; read -r _ < /dev/tty ;;
            b|B|"") break ;;
          esac
        done ;;
      4)
        clear; echo ""
        echo -e "  ${CYAN}Actualizando Claude Code...${NC}"; echo ""
        _ensure_install_script "install_claude.sh" || { read -r _ < /dev/tty; continue; }
        bash "$HOME/install_claude.sh" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ CODE TOOLS (Claude + OpenCode)
#  $1 = CC_STATE precalculado desde el loop principal (opcional)
#  $2 = OC_STATE precalculado desde el loop principal (opcional)
# ════════════════════════════════════════════
submenu_code_tools() {
  local _CC_INIT="${1:-}"
  local _OC_INIT="${2:-}"
  local _FIRST_RENDER=1

  while true; do
    clear; echo ""
    local CC_S CC_V CC_E OC_S OC_V OC_E

    if [ "$_FIRST_RENDER" = "1" ] && [ -n "$_CC_INIT" ] && [ -n "$_OC_INIT" ]; then
      # Primer render: usar estados ya calculados — sin check adicional
      CC_S="$_CC_INIT"
      CC_V=$(get_reg claude_code version); [ -z "$CC_V" ] && CC_V="?"
      CC_E=""
      OC_S="$_OC_INIT"
      OC_V=$(echo "$_OC_CACHE" | cut -d'|' -f2); [ -z "$OC_V" ] && OC_V="?"
      OC_E=""
      _FIRST_RENDER=0
    else
      # Renders siguientes: chequeo real
      IFS='|' read -r CC_S CC_V CC_E <<< "$(check_claude)"
      IFS='|' read -r OC_S OC_V OC_E <<< "$(check_opencode_cached)"
    fi

    local CC_PILL OC_PILL
    case "$CC_S" in
      ready)         CC_PILL="${GREEN}● listo   ${NC}" ;;
      not_installed) CC_PILL="${YELLOW}○ no instal${NC}"; CC_V="──────────" ;;
      *)             CC_PILL="${YELLOW}● ${CC_S}${NC}" ;;
    esac
    case "$OC_S" in
      running)       OC_PILL="${GREEN}● activo  ${NC}" ;;
      stopped)       OC_PILL="${GREEN}● listo   ${NC}" ;;
      not_installed) OC_PILL="${YELLOW}○ no instal${NC}"; OC_V="──────────" ;;
      *)             OC_PILL="${YELLOW}● ${OC_S}${NC}" ;;
    esac

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◆ CODE TOOLS                           ║"
    echo    "  ╠══════════════════════════════════════════╣"
    printf  "  ║  ${NC}[1] Claude Code  %b  %b${CYAN}${BOLD}║\n" "$CC_PILL" "${NC}→ submenú${CYAN}${BOLD}"
    printf  "  ║      ${NC}${DIM}%s${NC}${CYAN}${BOLD}%-$((28-${#CC_V}))s║\n" "$CC_V" ""
    printf  "  ║  ${NC}[2] OpenCode     %b  %b${CYAN}${BOLD}║\n" "$OC_PILL" "${NC}→ submenú${CYAN}${BOLD}"
    printf  "  ║      ${NC}${DIM}%s${NC}${CYAN}${BOLD}%-$((28-${#OC_V}))s║\n" "$OC_V" ""
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        if [ "$CC_S" = "not_installed" ]; then
          install_module "Claude Code" "claude"
        elif [ "$CC_V" = "err:reinstalar" ]; then
          clear; echo ""
          echo -e "${YELLOW}${BOLD}  ╔══════════════════════════════════════════╗"
          echo    "  ║  ⚠  Claude Code — cli.js corrompido    ║"
          echo    "  ╠══════════════════════════════════════════╣"
          echo -e "  ║  ${NC}Usa [0] → Restore → GitHub → claude     ${YELLOW}${BOLD}║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""
          echo -n "  ¿Reinstalar ahora? (s/n): "
          read -r RI < /dev/tty
          [ "$RI" = "s" ] || [ "$RI" = "S" ] && install_module "Claude Code" "claude"
        else
          submenu_claude
        fi ;;
      2)
        if [ "$OC_S" = "not_installed" ]; then
          install_module "OpenCode" "opencode"
        else
          submenu_opencode
        fi ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ EXPO / EAS / GIT
# ════════════════════════════════════════════
submenu_expo() {
  while true; do
    clear; echo ""
    local ACTIVE_PROJ; ACTIVE_PROJ=$(_eas_get_project)
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◈ EXPO / EAS / GIT  ● listo            ║"
    echo    "  ╠══════════════════════════════════════════╣"
    [ -n "$ACTIVE_PROJ" ] \
      && printf "  ║  ${NC}Proyecto: %-30s${CYAN}${BOLD}║\n" "$(basename "$ACTIVE_PROJ")" \
      || printf "  ║  ${NC}%-40s${CYAN}${BOLD}║\n" "Proyecto: <ninguno>"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Build APK preview${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[2] Build producción (AAB)${CYAN}${BOLD}             ║"
    echo -e "  ║  ${NC}[3] Ver builds activos${CYAN}${BOLD}                 ║"
    echo -e "  ║  ${NC}[4] Login en expo.dev${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[5] Info / estado general${CYAN}${BOLD}              ║"
    echo -e "  ║  ${NC}[6] Configurar proyecto activo${CYAN}${BOLD}         ║"
    echo -e "  ║  ${NC}[7] Git push (proyecto activo)${CYAN}${BOLD}         ║"
    echo -e "  ║  ${NC}[b] Volver${CYAN}${BOLD}                             ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1|2)
        clear; echo ""
        local PROJ; PROJ=$(_eas_get_project)
        [ -z "$PROJ" ] && {
          echo -e "  ${YELLOW}[AVISO]${NC} No hay proyecto activo. Configúralo con [6]."
          echo ""; read -r _ < /dev/tty; continue
        }
        local REAL_PATH; REAL_PATH=$(readlink -f "$PROJ" 2>/dev/null || echo "$PROJ")
        [ ! -d "$REAL_PATH" ] && {
          echo -e "  ${RED}[ERROR]${NC} No existe: $PROJ"
          echo ""; read -r _ < /dev/tty; continue
        }
        local PROFILE; [ "$OPT" = "1" ] && PROFILE="preview" || PROFILE="production"
        echo -e "  ${CYAN}Build $PROFILE → $PROJ${NC}"; echo ""
        cd "$REAL_PATH" && EAS_SKIP_AUTO_FINGERPRINT=1 eas build \
          --platform android --profile "$PROFILE" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        echo -e "  ${CYAN}Builds activos en expo.dev:${NC}"; echo ""
        eas build:list 2>/dev/null || echo -e "  ${YELLOW}Error al consultar${NC}"
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        eas whoami 2>/dev/null \
          && echo -e "\n  ${GREEN}[OK]${NC} Ya estás logueado." \
          || EAS_SKIP_AUTO_FINGERPRINT=1 eas login < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        echo -e "  ${BOLD}Info Expo / EAS:${NC}"; echo ""
        echo -e "  eas:      $(eas --version 2>/dev/null | head -1)"
        echo -e "  node:     $(node --version 2>/dev/null)"
        echo -e "  whoami:   $(eas whoami 2>/dev/null | head -1)"
        local PROJ; PROJ=$(_eas_get_project)
        echo -e "  proyecto: ${PROJ:-<ninguno>}"
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        echo -e "  ${BOLD}Configurar proyecto activo${NC}"; echo ""
        mkdir -p "$HOME/proyectos"
        mapfile -t PROJS < <(ls -1 "$HOME/proyectos/" 2>/dev/null)
        [ ${#PROJS[@]} -gt 0 ] && {
          echo -e "  ${CYAN}Proyectos en ~/proyectos/:${NC}"; echo ""
          for i in "${!PROJS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${PROJS[$i]}"; done
          echo ""
        }
        echo "    [m] Ruta manual  [d] Download"
        [ -n "$(_eas_get_project)" ] && echo "    [x] Quitar proyecto activo"
        echo "    [b] Volver"
        echo ""; echo -n "  Opción: "; read -r PCHOICE < /dev/tty
        local NEW_PROJ=""
        case "$PCHOICE" in
          m|M) echo -n "  Ruta: "; read -r NEW_PROJ < /dev/tty ;;
          d|D)
            mapfile -t DL_DIRS < <(find /storage/emulated/0/Download \
              -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -I{} basename {})
            [ ${#DL_DIRS[@]} -eq 0 ] && { echo "    (ninguna)"; read -r _ < /dev/tty; continue; }
            for i in "${!DL_DIRS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DL_DIRS[$i]}"; done
            echo ""; echo -n "  Número: "; read -r DCHOICE < /dev/tty
            if [[ "$DCHOICE" =~ ^[0-9]+$ ]] && [ "$DCHOICE" -ge 1 ] && \
               [ "$DCHOICE" -le "${#DL_DIRS[@]}" ]; then
              local DNAME="${DL_DIRS[$((DCHOICE-1))]}"
              local LINK_DST="$HOME/proyectos/${DNAME}"
              [ ! -e "$LINK_DST" ] && \
                ln -s "/storage/emulated/0/Download/${DNAME}" "$LINK_DST" 2>/dev/null
              NEW_PROJ="$LINK_DST"
            fi ;;
          x|X)
            rm -f "$EAS_PROJECT_FILE"
            echo -e "  ${GREEN}[OK]${NC} Proyecto activo eliminado."
            read -r _ < /dev/tty; continue ;;
          b|B|"") continue ;;
          *)
            [[ "$PCHOICE" =~ ^[0-9]+$ ]] && [ "$PCHOICE" -ge 1 ] && \
            [ "$PCHOICE" -le "${#PROJS[@]}" ] && \
              NEW_PROJ="$HOME/proyectos/${PROJS[$((PCHOICE-1))]}" ;;
        esac
        if [ -n "$NEW_PROJ" ]; then
          local REAL_PATH; REAL_PATH=$(readlink -f "$NEW_PROJ" 2>/dev/null || echo "$NEW_PROJ")
          if [ ! -d "$REAL_PATH" ]; then
            echo -e "  ${RED}[ERROR]${NC} No existe: $NEW_PROJ"
          elif [ ! -f "$REAL_PATH/package.json" ]; then
            echo -e "  ${YELLOW}[AVISO]${NC} Sin package.json."
            echo -n "  ¿Guardar de todas formas? (s/n): "; read -r FC < /dev/tty
            [ "$FC" = "s" ] || [ "$FC" = "S" ] && {
              _eas_set_project "$NEW_PROJ"
              echo -e "  ${GREEN}[OK]${NC} Guardado."
            }
          else
            _eas_set_project "$NEW_PROJ"
            echo -e "  ${GREEN}[OK]${NC} Proyecto activo: $NEW_PROJ"
          fi
        fi
        echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        local PROJ; PROJ=$(_eas_get_project)
        [ -z "$PROJ" ] && {
          echo -e "  ${YELLOW}[AVISO]${NC} No hay proyecto activo."
          echo ""; read -r _ < /dev/tty; continue
        }
        local REAL_PATH; REAL_PATH=$(readlink -f "$PROJ" 2>/dev/null || echo "$PROJ")
        [ ! -d "$REAL_PATH" ] && {
          echo -e "  ${RED}[ERROR]${NC} No existe: $PROJ"
          echo ""; read -r _ < /dev/tty; continue
        }
        [ ! -d "$REAL_PATH/.git" ] && {
          echo -e "  ${RED}[ERROR]${NC} No es repositorio git."
          echo -n "  ¿Inicializar git? (s/n): "; read -r INITGIT < /dev/tty
          [ "$INITGIT" = "s" ] || [ "$INITGIT" = "S" ] && cd "$REAL_PATH" && git init
          echo ""; read -r _ < /dev/tty; continue
        }
        cd "$REAL_PATH" || { read -r _ < /dev/tty; continue; }
        echo -e "  ${CYAN}Proyecto:${NC} $PROJ"; echo ""
        git status --short; echo ""
        echo -n "  Commit (ENTER = 'update desde Android'): "
        read -r COMMIT_MSG < /dev/tty
        [ -z "$COMMIT_MSG" ] && COMMIT_MSG="update desde Android"
        git add . && git commit -m "$COMMIT_MSG" && {
          echo ""; echo -e "  ${CYAN}Push...${NC}"
          git push \
            && echo -e "  ${GREEN}[OK]${NC} Push completado." \
            || echo -e "  ${RED}[ERROR]${NC} Push falló."
        } || echo -e "  ${YELLOW}[AVISO]${NC} Nada nuevo para commitear."
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  RUTAS TRADING
# ════════════════════════════════════════════
TRADING_DIR="$HOME/python/trading"
SIGNAL_BOT="$TRADING_DIR/signal_bot.py"
TRADE_TRACKER="$TRADING_DIR/trade_tracker.py"
TRADING_DB="$HOME/trading/senales.db"

_py_ok() {
  command -v python3 &>/dev/null && return 0
  echo -e "  ${RED}[ERROR]${NC} Python3 no encontrado. Instala desde [5]."; return 1
}

_check_script() {
  local path="$1" name="$2"
  if [ ! -f "$path" ]; then
    echo -e "  ${YELLOW}[AVISO]${NC} $name no encontrado en $path"
    echo -e "  ${DIM}Descarga desde: github.com/Honkonx/termux-ai-stack${NC}"
    echo ""; read -r _ < /dev/tty; return 1
  fi
  return 0
}

# ════════════════════════════════════════════
#  SUBMENÚ ACTIVOS
# ════════════════════════════════════════════
submenu_activos() {
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    printf  "  ║  %-40s║\n" "◈ ACTIVOS — Configuración"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Listar activos por categoría         ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Agregar activo custom                ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Ver categorías disponibles           ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver                               ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "; read -r AOPT < /dev/tty

    case "$AOPT" in
      1)
        _py_ok || continue; clear; echo ""
        python3 - << 'PYLIST'
import sqlite3, os
db = os.path.join(os.environ.get("HOME",""), "trading", "senales.db")
try:
    conn = sqlite3.connect(db); c = conn.cursor()
    c.execute("SELECT categoria,simbolo,broker,pip_mult FROM activos WHERE activo=1 ORDER BY categoria,simbolo")
    rows = c.fetchall(); conn.close()
    cat_actual = ""
    for cat,sim,broker,pip in rows:
        if cat != cat_actual:
            print(f"\n  [{cat}]"); cat_actual = cat
        print(f"    {sim:<18} broker={broker:<12} pip_mult={pip}")
    if not rows: print("  Sin activos.")
except Exception as e:
    print(f"  Error: {e}")
PYLIST
        echo ""; read -r _ < /dev/tty ;;
      2)
        _py_ok || continue; clear; echo ""
        echo -n "  Símbolo (ej: BTCUSD): "; read -r ACT_SIM < /dev/tty
        [ -z "$ACT_SIM" ] && { echo -e "  ${YELLOW}Cancelado${NC}"; echo ""; read -r _ < /dev/tty; continue; }
        echo -n "  Nombre (ej: Bitcoin/USD): "; read -r ACT_NOM < /dev/tty
        echo -e "  Cat: [1]forex [2]crypto [3]indice [4]metal [5]sintetico_deriv [6]custom"
        echo -n "  Opción: "; read -r ACT_CAT_OPT < /dev/tty
        case "$ACT_CAT_OPT" in
          1) ACT_CAT="forex" ;; 2) ACT_CAT="crypto" ;;
          3) ACT_CAT="indice";; 4) ACT_CAT="metal"  ;;
          5) ACT_CAT="sintetico_deriv" ;; *) ACT_CAT="custom" ;;
        esac
        echo -n "  Broker: "; read -r ACT_BROKER < /dev/tty
        echo -n "  pip_mult (ej: 10000 FX, 1 sintéticos): "; read -r ACT_PIP < /dev/tty
        ACT_PIP="${ACT_PIP:-1}"
        python3 - << PYINSERT
import sqlite3, os
db = os.path.join(os.environ.get("HOME",""), "trading", "senales.db")
try:
    conn = sqlite3.connect(db); c = conn.cursor()
    c.execute("""INSERT INTO activos (simbolo,nombre,categoria,broker,pip_mult)
                 VALUES (?,?,?,?,?)
                 ON CONFLICT(simbolo) DO UPDATE SET
                 nombre=excluded.nombre,categoria=excluded.categoria,
                 broker=excluded.broker,pip_mult=excluded.pip_mult,activo=1""",
              ("$ACT_SIM","$ACT_NOM","$ACT_CAT","$ACT_BROKER",float("$ACT_PIP")))
    conn.commit(); conn.close()
    print("  [OK] Activo guardado")
except Exception as e:
    print(f"  [ERROR] {e}")
PYINSERT
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        echo -e "  ${CYAN}Categorías disponibles:${NC}"; echo ""
        echo "    sintetico_deriv    → Boom, Crash, GainX, PainX (Deriv)"
        echo "    sintetico_weltrade → Boom, Crash, GainX, PainX (Weltrade)"
        echo "    forex              → EURUSD, GBPUSD, USDJPY..."
        echo "    metal              → XAUUSD, XAGUSD"
        echo "    indice             → US30, NAS100, GER40..."
        echo "    crypto             → BTCUSD, ETHUSD..."
        echo "    custom             → cualquier otro"
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
      *) echo -e "  ${YELLOW}[?]${NC} Inválido"; sleep 1 ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ TRADING
# ════════════════════════════════════════════
submenu_trading() {
  while true; do
    clear; echo ""
    local DB_STATUS SENALES_TOTAL WIN LOSS PENDIENTES
    if [ -f "$TRADING_DB" ]; then
      SENALES_TOTAL=$(python3 -c "import sqlite3; c=sqlite3.connect('$TRADING_DB').cursor(); c.execute('SELECT COUNT(*) FROM senales'); print(c.fetchone()[0])" 2>/dev/null || echo "?")
      WIN=$(python3 -c "import sqlite3; c=sqlite3.connect('$TRADING_DB').cursor(); c.execute(\"SELECT COUNT(*) FROM senales WHERE resultado='WIN'\"); print(c.fetchone()[0])" 2>/dev/null || echo "?")
      LOSS=$(python3 -c "import sqlite3; c=sqlite3.connect('$TRADING_DB').cursor(); c.execute(\"SELECT COUNT(*) FROM senales WHERE resultado='LOSS'\"); print(c.fetchone()[0])" 2>/dev/null || echo "?")
      PENDIENTES=$(python3 -c "import sqlite3; c=sqlite3.connect('$TRADING_DB').cursor(); c.execute(\"SELECT COUNT(*) FROM senales WHERE resultado='PENDIENTE'\"); print(c.fetchone()[0])" 2>/dev/null || echo "?")
      DB_STATUS="${GREEN}● activa${NC}"
    else
      DB_STATUS="${YELLOW}○ sin BD${NC}"
      SENALES_TOTAL="─"; WIN="─"; LOSS="─"; PENDIENTES="─"
    fi

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◈ TRADING — Sistema de señales         ║"
    echo    "  ╠══════════════════════════════════════════╣"
    printf  "  ║  ${NC}BD: %b  S:%-5s W:%-5s L:%-5s P:%-5s${CYAN}${BOLD}║\n" \
      "$DB_STATUS" "$SENALES_TOTAL" "$WIN" "$LOSS" "$PENDIENTES"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1]  Nueva señal                        ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2]  Actualizar señal (resultado/BE)    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3]  Ver señales abiertas               ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4]  Ver historial (últimas 20)         ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5]  Estadísticas rápidas               ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6]  Inicializar BD                     ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[7]  Ver historial (tracker)            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[8]  Webhook receptor (MT5)             ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[9]  Reporte semanal                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[10] Backtest CSV                       ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[11] Ejecutar bot Python                ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[c]  Configurar activos →               ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b]  Volver                             ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "; read -r OPT < /dev/tty

    case "$OPT" in
      1) _py_ok || continue; _check_script "$SIGNAL_BOT" "signal_bot.py" || continue
         clear; echo ""; python3 "$SIGNAL_BOT" nueva; echo ""; read -r _ < /dev/tty ;;
      2) _py_ok || continue; _check_script "$SIGNAL_BOT" "signal_bot.py" || continue
         clear; echo ""; python3 "$SIGNAL_BOT" actualizar; echo ""; read -r _ < /dev/tty ;;
      3) _py_ok || continue; _check_script "$SIGNAL_BOT" "signal_bot.py" || continue
         clear; echo ""; python3 "$SIGNAL_BOT" abiertas; echo ""; read -r _ < /dev/tty ;;
      4) _py_ok || continue; _check_script "$SIGNAL_BOT" "signal_bot.py" || continue
         clear; echo ""; python3 "$SIGNAL_BOT" historial 20; echo ""; read -r _ < /dev/tty ;;
      5) _py_ok || continue; _check_script "$SIGNAL_BOT" "signal_bot.py" || continue
         clear; echo ""; python3 "$SIGNAL_BOT" stats; echo ""; read -r _ < /dev/tty ;;
      6) _py_ok || continue; _check_script "$SIGNAL_BOT" "signal_bot.py" || continue
         clear; echo ""; python3 "$SIGNAL_BOT" init
         echo -e "  ${DIM}Ruta: $TRADING_DB${NC}"; echo ""; read -r _ < /dev/tty ;;
      7) _py_ok || continue; _check_script "$TRADE_TRACKER" "trade_tracker.py" || continue
         clear; echo ""; python3 "$TRADE_TRACKER" historial 50; echo ""; read -r _ < /dev/tty ;;
      8)
        local WEBHOOK_SCRIPT="$TRADING_DIR/webhook_receiver.py"
        _py_ok || continue; _check_script "$WEBHOOK_SCRIPT" "webhook_receiver.py" || continue
        clear; echo ""
        echo -e "  ${CYAN}${BOLD}WEBHOOK RECEPTOR — Señales MT5${NC}"
        echo -e "  ${DIM}Puerto: 9000  |  BD: $TRADING_DB${NC}"; echo ""
        echo -e "  [1] Background (tmux)  [2] Primer plano  [3] Detener  [4] Estado  [b] Volver"
        echo ""; echo -n "  Opción: "; read -r WHOPT < /dev/tty
        case "$WHOPT" in
          1) tmux kill-session -t "trading-wh" 2>/dev/null || true
             tmux new-session -d -s "trading-wh" "python3 $WEBHOOK_SCRIPT" 2>/dev/null \
               && echo -e "  ${GREEN}[OK]${NC} Corriendo (tmux: trading-wh)" \
               || echo -e "  ${RED}[ERROR]${NC}" ;;
          2) echo -e "  ${CYAN}Ctrl+C para salir${NC}"; echo ""
             python3 "$WEBHOOK_SCRIPT" < /dev/tty ;;
          3) tmux kill-session -t "trading-wh" 2>/dev/null \
               && echo -e "  ${GREEN}[OK]${NC} Detenido" \
               || echo -e "  ${YELLOW}[INFO]${NC} No estaba corriendo" ;;
          4) tmux has-session -t "trading-wh" 2>/dev/null \
               && echo -e "  ${GREEN}● activo${NC}" \
               || echo -e "  ${YELLOW}○ detenido${NC}" ;;
        esac
        echo ""; read -r _ < /dev/tty ;;
      9)
        _py_ok || continue
        [ ! -f "$TRADING_DB" ] && {
          echo -e "\n  ${YELLOW}[AVISO]${NC} BD no encontrada — inicializa con [6]"
          echo ""; read -r _ < /dev/tty; continue
        }
        clear; echo ""
        echo -e "  ${CYAN}${BOLD}REPORTE SEMANAL — TRADING${NC}"; echo ""
        python3 - << 'PYREPORT'
import sqlite3, os
from datetime import datetime, timedelta
db = os.path.join(os.environ.get("HOME",""), "trading", "senales.db")
conn = sqlite3.connect(db); c = conn.cursor()
desde = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d 00:00:00")
c.execute("SELECT COUNT(*) FROM senales WHERE fecha >= ?", (desde,))
total = c.fetchone()[0]
c.execute("SELECT COUNT(*) FROM senales WHERE resultado='WIN' AND fecha >= ?", (desde,))
wins = c.fetchone()[0]
c.execute("SELECT COUNT(*) FROM senales WHERE resultado='LOSS' AND fecha >= ?", (desde,))
losses = c.fetchone()[0]
c.execute("SELECT COUNT(*) FROM senales WHERE resultado='PENDIENTE' AND fecha >= ?", (desde,))
pend = c.fetchone()[0]
c.execute("SELECT SUM(pips) FROM senales WHERE resultado='WIN' AND fecha >= ? AND pips IS NOT NULL", (desde,))
pips_win = c.fetchone()[0] or 0
c.execute("SELECT SUM(pips) FROM senales WHERE resultado='LOSS' AND fecha >= ? AND pips IS NOT NULL", (desde,))
pips_loss = c.fetchone()[0] or 0
c.execute("SELECT AVG(duracion_min) FROM senales WHERE resultado!='PENDIENTE' AND fecha>=? AND duracion_min IS NOT NULL",(desde,))
dur_avg = c.fetchone()[0]
c.execute("SELECT activo,COUNT(*),SUM(CASE WHEN resultado='WIN' THEN 1 ELSE 0 END) FROM senales WHERE fecha>=? GROUP BY activo ORDER BY COUNT(*) DESC",(desde,))
por_activo = c.fetchall(); conn.close()
wr = round(wins/(wins+losses)*100,1) if (wins+losses)>0 else 0.0
print(f"  Periodo    : últimos 7 días")
print(f"  Total      : {total}  W:{wins}  L:{losses}  P:{pend}")
print(f"  Winrate    : {wr}%")
print(f"  Pips neto  : {round(pips_win+pips_loss,1)}")
if dur_avg: print(f"  Duración   : {int(dur_avg)} min prom.")
if por_activo:
    print("\n  Por activo:")
    for a,tot,w in por_activo: print(f"    {a:<18} {tot} ops  W:{w} L:{tot-w}")
PYREPORT
        echo ""; read -r _ < /dev/tty ;;
      10)
        local BACKTEST_SCRIPT="$TRADING_DIR/backtest_runner.py"
        _py_ok || continue; _check_script "$BACKTEST_SCRIPT" "backtest_runner.py" || continue
        clear; echo ""
        echo -e "  ${CYAN}${BOLD}BACKTESTING — CSV MT5${NC}"
        echo -e "  ${DIM}Coloca el CSV en ~/trading/${NC}"; echo ""
        python3 "$BACKTEST_SCRIPT" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      11)
        _py_ok || continue; clear; echo ""
        mapfile -t BOTS < <(find "$TRADING_DIR" -maxdepth 1 -name "*.py" 2>/dev/null | sort)
        if [ ${#BOTS[@]} -eq 0 ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} Sin scripts en $TRADING_DIR"
          echo ""; read -r _ < /dev/tty; continue
        fi
        echo -e "  Scripts en $TRADING_DIR:\n"
        for i in "${!BOTS[@]}"; do
          printf "    [%d] %s\n" "$((i+1))" "$(basename "${BOTS[$i]}")"
        done
        echo ""; echo "    [m] Ruta manual"; echo -n "  Elige: "; read -r BOT_OPT < /dev/tty
        local BOT_PATH=""
        if [ "$BOT_OPT" = "m" ] || [ "$BOT_OPT" = "M" ]; then
          echo -n "  Ruta: "; read -r BOT_PATH < /dev/tty
          BOT_PATH="${BOT_PATH/#\~/$HOME}"
        elif [[ "$BOT_OPT" =~ ^[0-9]+$ ]] && [ "$BOT_OPT" -ge 1 ] && \
             [ "$BOT_OPT" -le "${#BOTS[@]}" ]; then
          BOT_PATH="${BOTS[$((BOT_OPT-1))]}"
        fi
        [ -z "$BOT_PATH" ] || [ ! -f "$BOT_PATH" ] && {
          echo -e "  ${RED}[ERROR]${NC} No encontrado"; echo ""; read -r _ < /dev/tty; continue
        }
        echo -n "  args (ENTER=ninguno): "; read -r BOT_ARGS < /dev/tty
        echo ""
        cd "$(dirname "$BOT_PATH")" && python3 "$BOT_PATH" $BOT_ARGS < /dev/tty
        BOT_EXIT=$?
        echo ""
        [ $BOT_EXIT -eq 0 ] \
          && echo -e "  ${GREEN}[OK]${NC} Terminó (código 0)" \
          || echo -e "  ${YELLOW}[AVISO]${NC} Terminó con código $BOT_EXIT"
        echo ""; read -r _ < /dev/tty ;;
      c|C) submenu_activos ;;
      b|B|"") break ;;
      *) echo -e "  ${YELLOW}[?]${NC} Inválido"; sleep 1 ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ SQLITE
# ════════════════════════════════════════════
submenu_sqlite() {
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⬡ SQLITE                                ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Listar BDs en ~/                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Abrir BD (modo interactivo)         ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Ver tablas de una BD                ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] BD de n8n (acceso rápido)           ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5] Exportar BD a CSV                   ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6] Crear nueva BD vacía                ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver a Python                     ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "; read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        echo -e "  ${BOLD}Bases de datos SQLite en ~/:${NC}"; echo ""
        find "$HOME" -maxdepth 3 \( -name "*.db" -o -name "*.sqlite" \) 2>/dev/null | \
          while read -r f; do echo "  $f ($(du -h "$f" | cut -f1))"; done
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        mapfile -t DBS < <(find "$HOME" -maxdepth 3 \( -name "*.db" -o -name "*.sqlite" \) 2>/dev/null)
        [ ${#DBS[@]} -eq 0 ] && {
          echo -e "  ${YELLOW}No hay bases de datos.${NC}"; echo ""; read -r _ < /dev/tty; continue
        }
        echo -e "  ${CYAN}BDs disponibles:${NC}"; echo ""
        for i in "${!DBS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DBS[$i]}"; done
        echo ""; echo -n "  Número: "; read -r CHOICE < /dev/tty
        [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && \
        [ "$CHOICE" -le "${#DBS[@]}" ] && sqlite3 "${DBS[$((CHOICE-1))]}" ;;
      3)
        clear; echo ""
        mapfile -t DBS < <(find "$HOME" -maxdepth 3 \( -name "*.db" -o -name "*.sqlite" \) 2>/dev/null)
        [ ${#DBS[@]} -eq 0 ] && {
          echo -e "  ${YELLOW}No hay bases de datos.${NC}"; echo ""; read -r _ < /dev/tty; continue
        }
        for i in "${!DBS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DBS[$i]}"; done
        echo ""; echo -n "  Número: "; read -r CHOICE < /dev/tty
        [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && \
        [ "$CHOICE" -le "${#DBS[@]}" ] && {
          echo ""; echo -e "  ${CYAN}Tablas:${NC}"; echo ""
          sqlite3 "${DBS[$((CHOICE-1))]}" ".tables"
        }
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        N8N_DB="$TERMUX_PREFIX/var/lib/proot-distro/installed-rootfs/debian/root/.n8n/database.sqlite"
        [ ! -f "$N8N_DB" ] && N8N_DB=$(find "$TERMUX_PREFIX" -name "database.sqlite" 2>/dev/null | head -1)
        if [ -z "$N8N_DB" ] || [ ! -f "$N8N_DB" ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} BD n8n no encontrada (n8n debe haber corrido al menos una vez)."
        else
          echo -e "  ${CYAN}BD n8n: $N8N_DB${NC}"; echo ""
          sqlite3 "$N8N_DB" ".tables"
          echo ""; echo -e "  ${DIM}Tip: sqlite3 directamente para queries${NC}"
        fi
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        mapfile -t DBS < <(find "$HOME" -maxdepth 3 \( -name "*.db" -o -name "*.sqlite" \) 2>/dev/null)
        [ ${#DBS[@]} -eq 0 ] && {
          echo -e "  ${YELLOW}No hay bases de datos.${NC}"; echo ""; read -r _ < /dev/tty; continue
        }
        for i in "${!DBS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DBS[$i]}"; done
        echo ""; echo -n "  Número: "; read -r CHOICE < /dev/tty
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && \
           [ "$CHOICE" -le "${#DBS[@]}" ]; then
          local DB_PATH="${DBS[$((CHOICE-1))]}"
          local CSV_DIR; CSV_DIR="$(dirname "$DB_PATH")"
          echo ""; echo -e "  ${CYAN}Tablas en $DB_PATH:${NC}"; echo ""
          mapfile -t TABLES < <(sqlite3 "$DB_PATH" ".tables" 2>/dev/null | tr ' ' '\n' | grep -v "^$")
          [ ${#TABLES[@]} -eq 0 ] && { echo -e "  ${YELLOW}Sin tablas.${NC}"; read -r _ < /dev/tty; continue; }
          for i in "${!TABLES[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${TABLES[$i]}"; done
          echo "    [a] Todas"
          echo ""; echo -n "  Tabla: "; read -r TCHOICE < /dev/tty
          _export_table() {
            local tbl="$1" out="$CSV_DIR/${1}.csv"
            sqlite3 -csv "$DB_PATH" "SELECT * FROM ${tbl};" > "$out" 2>/dev/null \
              && echo -e "  ${GREEN}[OK]${NC} $tbl → $out" \
              || echo -e "  ${RED}[ERROR]${NC} No se pudo exportar $tbl"
          }
          if [ "$TCHOICE" = "a" ] || [ "$TCHOICE" = "A" ]; then
            for tbl in "${TABLES[@]}"; do _export_table "$tbl"; done
          elif [[ "$TCHOICE" =~ ^[0-9]+$ ]] && [ "$TCHOICE" -ge 1 ] && \
               [ "$TCHOICE" -le "${#TABLES[@]}" ]; then
            _export_table "${TABLES[$((TCHOICE-1))]}"
          fi
        fi
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        echo -e "  ${BOLD}Crear nueva BD SQLite vacía${NC}"; echo ""
        echo -n "  Nombre (sin extensión): "; read -r DB_NAME < /dev/tty
        if [ -z "$DB_NAME" ]; then
          echo -e "  ${YELLOW}Cancelado.${NC}"
        else
          local DB_FILE="$HOME/${DB_NAME}.db"
          sqlite3 "$DB_FILE" "" 2>/dev/null \
            && echo -e "  ${GREEN}[OK]${NC} BD creada: $DB_FILE" \
            || echo -e "  ${RED}[ERROR]${NC}"
        fi
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ PYTHON
# ════════════════════════════════════════════
submenu_python() {
  local py_ver="$1"
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    printf  "  ║  ◉ PYTHON  ● listo · v%-18s${CYAN}${BOLD}║\n" "${py_ver}"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Ver versión e info                  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Abrir REPL (python3)                ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Instalar paquete (pip)              ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Listar paquetes instalados          ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5] SQLite → submenú                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6] Ejecutar script .py                 ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[7] ◈ Trading →                         ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[8] ◉ Bot deportivo → ${DIM}(próximamente)${CYAN}${BOLD}   ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal            ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "; read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        echo -e "  ${BOLD}Python info:${NC}"; echo ""
        echo -e "  python3: $(python3 --version 2>/dev/null)"
        echo -e "  pip:     $(pip --version 2>/dev/null | awk '{print $1,$2}')"
        echo -e "  sqlite3: $(python3 -c 'import sqlite3; print(sqlite3.sqlite_version)' 2>/dev/null)"
        echo -e "  Ruta:    $(command -v python3 2>/dev/null)"
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        echo -e "  ${CYAN}REPL Python — exit() para volver${NC}"; echo ""
        python3 ;;
      3)
        clear; echo ""
        echo -n "  Nombre del paquete: "; read -r PKG_NAME < /dev/tty
        [ -z "$PKG_NAME" ] && { echo -e "  ${YELLOW}Cancelado.${NC}"; echo ""; read -r _ < /dev/tty; continue; }
        echo ""; echo -e "  ${CYAN}Instalando ${PKG_NAME}...${NC}"; echo ""
        # --break-system-packages requerido en Termux Python 3.12+
        pip install "$PKG_NAME" --break-system-packages 2>&1
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        echo -e "  ${BOLD}Paquetes instalados:${NC}"; echo ""
        pip list 2>/dev/null | head -40
        echo ""; read -r _ < /dev/tty ;;
      5) submenu_sqlite ;;
      6)
        clear; echo ""
        mapfile -t PY_SCRIPTS < <(
          { find "$HOME/proyectos" -maxdepth 2 -name "*.py" 2>/dev/null
            find "$HOME" -maxdepth 1 -name "*.py" 2>/dev/null
            find /storage/emulated/0/Download -maxdepth 2 -name "*.py" 2>/dev/null
          } | sort -u
        )
        if [ ${#PY_SCRIPTS[@]} -eq 0 ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} Sin scripts .py encontrados."
          echo -n "  Escribe la ruta completa: "; read -r MANUAL_PY < /dev/tty
          [ -n "$MANUAL_PY" ] && [ -f "$MANUAL_PY" ] \
            && PY_SCRIPTS=("$MANUAL_PY") \
            || { read -r _ < /dev/tty; continue; }
        else
          echo -e "  ${CYAN}Scripts encontrados:${NC}"; echo ""
          for i in "${!PY_SCRIPTS[@]}"; do
            local DISPLAY="${PY_SCRIPTS[$i]}"; DISPLAY="${DISPLAY/#$HOME/~}"
            printf "    [%d] %s\n" "$((i+1))" "$DISPLAY"
          done
          echo ""; echo "    [m] Ruta manual"; echo ""
          echo -n "  Elige número: "; read -r SCHOICE < /dev/tty
          [ "$SCHOICE" = "m" ] || [ "$SCHOICE" = "M" ] && {
            echo -n "  Ruta: "; read -r MANUAL_PY < /dev/tty
            PY_SCRIPTS=("$MANUAL_PY"); SCHOICE=1
          }
          if ! [[ "$SCHOICE" =~ ^[0-9]+$ ]] || [ "$SCHOICE" -lt 1 ] || \
             [ "$SCHOICE" -gt "${#PY_SCRIPTS[@]}" ]; then
            echo -e "  ${RED}[ERROR]${NC} Número inválido."; read -r _ < /dev/tty; continue
          fi
        fi
        local SELECTED_PY="${PY_SCRIPTS[$((SCHOICE-1))]:-${PY_SCRIPTS[0]}}"
        [ ! -f "$SELECTED_PY" ] && {
          echo -e "  ${RED}[ERROR]${NC} Archivo no existe."; read -r _ < /dev/tty; continue
        }
        echo ""; echo -e "  ${CYAN}▶ Ejecutando:${NC} $SELECTED_PY"; echo ""
        cd "$(dirname "$SELECTED_PY")" && python3 "$SELECTED_PY" < /dev/tty
        local PY_EXIT=$?
        echo ""
        [ $PY_EXIT -eq 0 ] \
          && echo -e "  ${GREEN}[OK]${NC} Terminó (código 0)" \
          || echo -e "  ${YELLOW}[AVISO]${NC} Terminó con código $PY_EXIT"
        echo ""; read -r _ < /dev/tty ;;
      7) submenu_trading ;;
      8)
        echo -e "\n  ${DIM}Bot deportivo SQLite — en desarrollo (ver #17)${NC}"
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ REMOTE (SSH + Dashboard + CF-SSH)
# ════════════════════════════════════════════
submenu_remote() {
  while true; do
    clear; echo ""
    local SSH_ACTIVE=false DB_ACTIVE=false CF_ACTIVE=false
    pgrep -x sshd &>/dev/null && SSH_ACTIVE=true
    pgrep -f "dashboard_server.py" &>/dev/null && DB_ACTIVE=true
    pgrep -f "cloudflared.*ssh\|cloudflared.*access" &>/dev/null && CF_ACTIVE=true
    local IP; IP=$(_get_ip)

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════╗"
    echo    "  ║  ◎ REMOTE / SSH / DASHBOARD              ║"
    echo    "  ╠══════════════════════════════════════════════╣"
    $SSH_ACTIVE \
      && printf "  ║  SSH    ${GREEN}● activo${NC}${CYAN}${BOLD}  :8022  %-16s║\n" "${IP}" \
      || printf "  ║  SSH    ${YELLOW}○ listo ${NC}${CYAN}${BOLD}  :8022  %-16s║\n" ""
    $DB_ACTIVE \
      && printf "  ║  Dash   ${GREEN}● activo${NC}${CYAN}${BOLD}  :8080  %-16s║\n" "http://${IP}:8080" \
      || printf "  ║  Dash   ${YELLOW}○ listo ${NC}${CYAN}${BOLD}  :8080                  ║\n"
    $CF_ACTIVE \
      && printf "  ║  CF-SSH ${GREEN}● activo${NC}${CYAN}${BOLD}  tunnel              ║\n" \
      || printf "  ║  CF-SSH ${YELLOW}○ listo ${NC}${CYAN}${BOLD}  tunnel              ║\n"
    echo    "  ╠══════════════════════════════════════════════╣"
    echo -e "  ║  ${BOLD}── SSH ──${CYAN}${BOLD}                                 ║"
    echo -e "  ║  ${NC}[1] Iniciar  [2] Detener  [3] Info       ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Agregar clave pública (PC)           ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5] Conexiones activas  [6] Contraseña   ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════════╣"
    echo -e "  ║  ${BOLD}── Dashboard ──${CYAN}${BOLD}                          ║"
    echo -e "  ║  ${NC}[7] Iniciar  [8] Detener  [9] URL        ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════════╣"
    echo -e "  ║  ${BOLD}── Cloudflared SSH ──${CYAN}${BOLD}                    ║"
    echo -e "  ║  ${NC}[c] Iniciar  [x] Detener  [t] Token      ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[i] Cómo conectarse via CF-SSH           ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[b] Volver al menú principal             ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "; read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        if pgrep -x sshd &>/dev/null; then
          echo -e "  ${YELLOW}[AVISO]${NC} SSH ya está corriendo."
        else
          bash "$REMOTE_SCRIPTS/ssh_start.sh" 2>/dev/null || sshd 2>/dev/null; sleep 1
        fi
        if pgrep -x sshd &>/dev/null; then
          IP=$(_get_ip)
          echo -e "  ${GREEN}[OK]${NC} SSH activo :8022"
          echo -e "  ${GREEN}  ssh -p 8022 $(whoami)@${IP:-<IP>}${NC}"
        else
          echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar. Prueba: sshd -d"
        fi
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        bash "$REMOTE_SCRIPTS/ssh_stop.sh" 2>/dev/null || pkill sshd 2>/dev/null
        sleep 1; pgrep -x sshd &>/dev/null || echo -e "  ${GREEN}[OK]${NC} SSH detenido"
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        IP=$(_get_ip); local USER_N; USER_N=$(whoami)
        echo -e "  ${BOLD}Información de conexión SSH${NC}"; echo ""
        echo -e "  Estado:  $(pgrep -x sshd &>/dev/null && echo "${GREEN}● ACTIVO${NC}" || echo "${YELLOW}○ DETENIDO${NC}")"
        echo -e "  Puerto:  8022  |  Usuario: ${USER_N}  |  IP: ${IP:-no detectada}"; echo ""
        echo -e "  ${CYAN}WiFi:${NC}   ssh -p 8022 ${USER_N}@${IP:-<IP>}"
        echo -e "  ${CYAN}SCP:${NC}    scp -P 8022 archivo.txt ${USER_N}@${IP:-<IP>}:~/"
        echo -e "  ${CYAN}VS Code:${NC} Remote-SSH → ${USER_N}@${IP:-<IP>}:8022"
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        echo -e "  ${BOLD}Agregar clave pública SSH${NC}"; echo ""
        echo "  En tu PC: cat ~/.ssh/id_ed25519.pub"
        echo "  (Si no tienes: ssh-keygen -t ed25519)"; echo ""
        echo -n "  Pega la clave (vacío = cancelar): "; read -r PUB_KEY < /dev/tty
        if [ -z "$PUB_KEY" ]; then
          echo -e "  ${YELLOW}Cancelado.${NC}"
        elif echo "$PUB_KEY" | grep -qE "^ssh-(rsa|ed25519|ecdsa|dss) "; then
          mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
          echo "$PUB_KEY" >> "$HOME/.ssh/authorized_keys"
          chmod 600 "$HOME/.ssh/authorized_keys"
          echo -e "  ${GREEN}[OK]${NC} Clave agregada."
        else
          echo -e "  ${RED}[ERROR]${NC} Formato inválido (debe empezar con ssh-ed25519, ssh-rsa...)"
        fi
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        echo -e "  ${BOLD}Conexiones SSH activas${NC}"; echo ""
        local CONNS; CONNS=$(ps aux 2>/dev/null | grep "sshd:" | grep -v grep | grep -v "sshd -D")
        [ -z "$CONNS" ] && echo -e "  ${DIM}Sin conexiones activas.${NC}" || \
          echo "$CONNS" | while IFS= read -r line; do echo "  $line"; done
        echo ""
        pgrep -x sshd &>/dev/null \
          && echo -e "  Daemon: ${GREEN}● corriendo${NC} (PID: $(pgrep -x sshd | head -1))" \
          || echo -e "  Daemon: ${YELLOW}○ detenido${NC}"
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        echo -e "  ${BOLD}Contraseña Termux (para SSH sin clave)${NC}"; echo ""
        passwd; echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        if pgrep -f "dashboard_server.py" &>/dev/null; then
          IP=$(_get_ip)
          echo -e "  ${YELLOW}[AVISO]${NC} Dashboard ya corriendo."
          echo -e "  URL: ${GREEN}http://${IP}:8080${NC}"
        else
          # Auto-crear dashboard_start.sh si no existe
          if [ ! -f "$REMOTE_SCRIPTS/dashboard_start.sh" ] || \
             ! grep -q "dashboard_server.py" "$REMOTE_SCRIPTS/dashboard_start.sh" 2>/dev/null; then
            cat > "$REMOTE_SCRIPTS/dashboard_start.sh" << 'DBSTART'
#!/data/data/com.termux/files/usr/bin/bash
DB_SCRIPT="$HOME/scripts/remote/dashboard_server.py"
_get_ip() {
  local ip
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  echo "${ip:-localhost}"
}
[ ! -f "$DB_SCRIPT" ] && { echo "[ERROR] dashboard_server.py no encontrado"; exit 1; }
pgrep -f "dashboard_server.py" &>/dev/null && { echo "[INFO] Ya corriendo en http://$(_get_ip):8080"; exit 0; }
cd "$(dirname "$DB_SCRIPT")"
nohup python3 "$DB_SCRIPT" > "$HOME/.dashboard.log" 2>&1 &
sleep 2
pgrep -f "dashboard_server.py" &>/dev/null \
  && echo "[OK] Dashboard → http://$(_get_ip):8080" \
  || { echo "[ERROR] No se pudo iniciar. Log: cat ~/.dashboard.log"; exit 1; }
DBSTART
            chmod +x "$REMOTE_SCRIPTS/dashboard_start.sh"
          fi
          if [ ! -f "$REMOTE_SCRIPTS/dashboard_server.py" ]; then
            echo -e "  ${RED}[ERROR]${NC} dashboard_server.py no encontrado"
            echo "  Instala Remote: menú → [6] → Instalar"
            echo ""; read -r _ < /dev/tty; continue
          fi
          bash "$REMOTE_SCRIPTS/dashboard_start.sh" < /dev/null
          sleep 2
          if pgrep -f "dashboard_server.py" &>/dev/null; then
            IP=$(_get_ip)
            echo -e "  ${GREEN}[OK]${NC} Dashboard iniciado"
            echo -e "  URL: ${GREEN}http://${IP}:8080${NC}"
          else
            echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar"
            echo "  Log: cat ~/.dashboard.log"
          fi
        fi
        echo ""; read -r _ < /dev/tty ;;
      8)
        clear; echo ""
        if pgrep -f "dashboard_server.py" &>/dev/null; then
          pkill -f "dashboard_server.py" 2>/dev/null; sleep 1
          pgrep -f "dashboard_server.py" &>/dev/null && pkill -9 -f "dashboard_server.py" 2>/dev/null
          sleep 1
          pgrep -f "dashboard_server.py" &>/dev/null \
            && echo -e "  ${RED}[ERROR]${NC} No se pudo detener" \
            || echo -e "  ${GREEN}[OK]${NC} Dashboard detenido"
        else
          echo -e "  ${GREEN}[OK]${NC} Dashboard detenido"
        fi
        echo ""; read -r _ < /dev/tty ;;
      9)
        clear; echo ""
        IP=$(_get_ip)
        echo -e "  ${BOLD}URLs Dashboard${NC}"; echo ""
        echo -e "  WiFi:    ${GREEN}http://${IP}:8080${NC}"
        echo -e "  Local:   ${GREEN}http://localhost:8080${NC}"; echo ""
        pgrep -f "dashboard_server.py" &>/dev/null \
          && echo -e "  Estado: ${GREEN}● activo${NC}" \
          || echo -e "  Estado: ${YELLOW}○ detenido${NC} — usa [7] para iniciar"
        echo ""; read -r _ < /dev/tty ;;
      c|C)
        clear; echo ""
        local CF_SSH_TOKEN="$HOME/.cf_ssh_token"
        if [ ! -f "$CF_SSH_TOKEN" ] || [ ! -s "$CF_SSH_TOKEN" ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} Sin token CF-SSH. Configúralo con [t] primero."
          echo ""; read -r _ < /dev/tty; continue
        fi
        if ! pgrep -x sshd &>/dev/null; then
          echo -e "  ${YELLOW}[AVISO]${NC} SSH no está corriendo. Iniciando..."
          bash "$REMOTE_SCRIPTS/ssh_start.sh" 2>/dev/null || sshd 2>/dev/null; sleep 1
          pgrep -x sshd &>/dev/null || {
            echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar SSH."
            read -r _ < /dev/tty; continue
          }
          echo -e "  ${GREEN}[OK]${NC} SSH iniciado"; echo ""
        fi
        local CF_TOK; CF_TOK=$(cat "$CF_SSH_TOKEN")
        echo -e "  ${CYAN}Iniciando tunnel Cloudflared SSH...${NC}"; echo ""
        tmux new-session -d -s "cf-ssh-tunnel" \
          "cloudflared tunnel run --token ${CF_TOK} 2>&1 | tee $HOME/.cf_ssh.log" 2>/dev/null
        sleep 3
        tmux has-session -t "cf-ssh-tunnel" 2>/dev/null \
          && { echo -e "  ${GREEN}[OK]${NC} Tunnel activo"
               echo -e "  ${DIM}Ver logs: tmux attach -t cf-ssh-tunnel${NC}"; } \
          || { echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar. Verifica token con [t]"; }
        echo ""; read -r _ < /dev/tty ;;
      x|X)
        clear; echo ""
        tmux kill-session -t "cf-ssh-tunnel" 2>/dev/null
        pkill -f "cloudflared.*tunnel\|cloudflared.*ssh" 2>/dev/null
        sleep 1; echo -e "  ${GREEN}[OK]${NC} Tunnel CF-SSH detenido"
        echo ""; read -r _ < /dev/tty ;;
      t|T)
        clear; echo ""
        echo -e "  ${BOLD}Configurar token Cloudflared SSH${NC}"; echo ""
        local CF_SSH_TOKEN="$HOME/.cf_ssh_token"
        [ -f "$CF_SSH_TOKEN" ] \
          && echo -e "  Token actual: ${GREEN}configurado${NC}" \
          || echo -e "  Token actual: ${YELLOW}no configurado${NC}"
        echo ""
        echo "  cloudflare.com → Zero Trust → Access → Tunnels → Create → SSH"
        echo ""; echo -n "  Nuevo token (ENTER = cancelar): "; read -r NEW_CF_SSH < /dev/tty
        if [ -n "$NEW_CF_SSH" ]; then
          echo "$NEW_CF_SSH" > "$CF_SSH_TOKEN"
          echo -e "  ${GREEN}[OK]${NC} Token guardado."
        else
          echo -e "  ${YELLOW}Cancelado.${NC}"
        fi
        echo ""; read -r _ < /dev/tty ;;
      i|I)
        clear; echo ""
        echo -e "  ${BOLD}Cómo conectarse via Cloudflared SSH${NC}"; echo ""
        echo -e "  ${CYAN}TELÉFONO:${NC}"
        echo "  1. Configura token: [t]"
        echo "  2. Inicia SSH: [1]"
        echo "  3. Inicia tunnel: [c]"; echo ""
        echo -e "  ${CYAN}PC (primera vez):${NC}"
        echo "  1. Instala cloudflared en el PC"
        echo "  2. ~/.ssh/config:"
        echo -e "  ${DIM}  Host termux-remoto"
        echo "    HostName tu-dominio-ssh.com"
        echo "    User $(whoami)"
        echo "    ProxyCommand cloudflared access ssh --hostname %h"
        echo -e "  ${NC}"
        echo "  3. ssh termux-remoto"
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  HELPERS BACKUP / RESTORE
# ════════════════════════════════════════════
_ensure_backup() {
  if [ ! -f "$HOME/backup.sh" ] || [ ! -s "$HOME/backup.sh" ]; then
    curl -fsSL "$REPO_RAW/backup.sh" -o "$HOME/backup.sh" 2>/dev/null || \
      wget -q "$REPO_RAW/backup.sh" -O "$HOME/backup.sh" 2>/dev/null
    [ ! -f "$HOME/backup.sh" ] || [ ! -s "$HOME/backup.sh" ] && return 1
    chmod +x "$HOME/backup.sh"
  fi
  return 0
}

_ensure_restore() {
  if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
    curl -fsSL "$REPO_RAW/restore.sh" -o "$HOME/restore.sh" 2>/dev/null || \
      wget -q "$REPO_RAW/restore.sh" -O "$HOME/restore.sh" 2>/dev/null
    [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ] && return 1
    chmod +x "$HOME/restore.sh"
  fi
  return 0
}

# ════════════════════════════════════════════
#  SUBMENÚ BACKUP / RESTORE
# ════════════════════════════════════════════
submenu_backup() {
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◉ BACKUP / RESTORE                     ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Backup completo                      ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Backup por módulo                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Restore completo (GitHub)            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Restore por módulo (interactivo)     ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver al menú principal             ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "; read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        _ensure_backup || { echo -e "  ${RED}[ERROR]${NC} backup.sh no disponible"; read -r _ < /dev/tty; continue; }
        bash "$HOME/backup.sh" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        echo -e "  ${CYAN}Módulo a respaldar:${NC}"; echo ""
        echo "  [0] base      [2] claude   [3] expo"
        echo "  [4] ollama    [5] n8n      [6] proot"
        echo "  [7] remote    [8] opencode [9] openclaw"
        echo "  [b] Cancelar"
        echo ""; echo -n "  Módulo: "; read -r MOD_OPT < /dev/tty
        local BAK_MOD=""
        case "$MOD_OPT" in
          0)  BAK_MOD="base"     ;; 2) BAK_MOD="claude"   ;;
          3)  BAK_MOD="expo"     ;; 4) BAK_MOD="ollama"   ;;
          5)  BAK_MOD="n8n"      ;; 6) BAK_MOD="proot"    ;;
          7)  BAK_MOD="remote"   ;; 8) BAK_MOD="opencode" ;;
          9)  BAK_MOD="openclaw" ;;
          b|B|"") continue ;;
          *) echo -e "  ${RED}[ERROR]${NC} Inválido"; read -r _ < /dev/tty; continue ;;
        esac
        _ensure_backup || { echo -e "  ${RED}[ERROR]${NC} backup.sh no disponible"; read -r _ < /dev/tty; continue; }
        bash "$HOME/backup.sh" --module "$BAK_MOD" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear
        _ensure_restore || { echo -e "  ${RED}[ERROR]${NC} restore.sh no disponible"; read -r _ < /dev/tty; continue; }
        bash "$HOME/restore.sh" --module all --source github < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear
        _ensure_restore || { echo -e "  ${RED}[ERROR]${NC} restore.sh no disponible"; read -r _ < /dev/tty; continue; }
        bash "$HOME/restore.sh" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  DESINSTALAR
# ════════════════════════════════════════════
uninstall_module() {
  local module_key="$1" module_name="$2"
  clear; echo ""
  echo -e "${RED}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "⚠  Desinstalar ${module_name}"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}Esta acción NO se puede deshacer.${RED}${BOLD}       ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""
  echo -n "  ¿Confirmar? (escribe SI): "; read -r CONFIRM_DEL < /dev/tty
  [ "$CONFIRM_DEL" != "SI" ] && {
    echo -e "  ${YELLOW}Cancelado.${NC}"; echo ""; read -r _ < /dev/tty; return 0
  }
  echo ""

  case "$module_key" in
    claude)
      npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
      npm cache clean --force 2>/dev/null || true
      local NPM_ROOT_U; NPM_ROOT_U=$(npm root -g 2>/dev/null)
      rm -rf "${NPM_ROOT_U}/@anthropic-ai" 2>/dev/null || true
      rm -f "${TERMUX_PREFIX}/bin/claude" "$HOME/.install_claude_checkpoint" 2>/dev/null
      grep -v "alias claude=" "$HOME/.bashrc" > "$HOME/.bashrc.tmp" 2>/dev/null && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
      grep -v "^claude_code\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Claude Code desinstalado" ;;
    ollama)
      tmux kill-session -t "ollama-server" 2>/dev/null || true
      pkg uninstall ollama -y 2>/dev/null || true
      rm -f "$OLLAMA_SCRIPTS/ollama_start.sh" "$OLLAMA_SCRIPTS/ollama_stop.sh" 2>/dev/null
      grep -v "^ollama\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Ollama desinstalado"
      echo -e "  ${YELLOW}⚠${NC}  ~/.ollama no eliminado — bórralo para liberar espacio" ;;
    n8n)
      tmux kill-session -t "n8n-server" 2>/dev/null || true
      if proot-distro login debian -- bash -c 'true' &>/dev/null 2>&1; then
        proot-distro login debian -- bash -c '
          rm -rf /usr/lib/node_modules/n8n /usr/lib/node_modules/corepack 2>/dev/null
          rm -f /usr/bin/n8n /usr/local/bin/cloudflared /usr/bin/node 2>/dev/null
          rm -rf /root/.n8n /root/.cache/node-gyp /root/.cf_token 2>/dev/null
          echo "[OK] Archivos n8n eliminados"
        ' 2>/dev/null
      fi
      rm -f "$N8N_SCRIPTS/start_servidor.sh" "$N8N_SCRIPTS/stop_servidor.sh" "$N8N_SCRIPTS/ver_url.sh" 2>/dev/null
      rm -f "$N8N_SCRIPTS/n8n_status.sh" "$N8N_SCRIPTS/n8n_log.sh" "$N8N_SCRIPTS/n8n_update.sh" "$N8N_SCRIPTS/n8n_backup.sh" 2>/dev/null
      rm -f "$N8N_SCRIPTS/cf_token.sh" "$HOME/.cf_token" "$HOME/.last_cf_url" 2>/dev/null
      grep -v "^n8n\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} n8n desinstalado (proot Debian conservado)" ;;
    expo)
      npm uninstall -g eas-cli 2>/dev/null || true
      rm -f "${TERMUX_PREFIX}/bin/eas" 2>/dev/null
      grep -v "^expo\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Expo / EAS CLI desinstalado" ;;
    python)
      pkg uninstall python sqlite -y 2>/dev/null || true
      rm -f "$HOME/.install_python_checkpoint" 2>/dev/null
      grep -v "^python\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Python + SQLite desinstalados" ;;
    remote)
      pkill sshd 2>/dev/null || true
      tmux kill-session -t "cf-ssh-tunnel" 2>/dev/null || true
      pkill -f "dashboard_server.py" 2>/dev/null || true
      pkg uninstall openssh -y 2>/dev/null || true
      rm -f "$REMOTE_SCRIPTS/ssh_start.sh" "$REMOTE_SCRIPTS/ssh_stop.sh" 2>/dev/null
      rm -f "$REMOTE_SCRIPTS/dashboard_start.sh" "$REMOTE_SCRIPTS/dashboard_stop.sh" "$REMOTE_SCRIPTS/dashboard_server.py" 2>/dev/null
      rm -f "$HOME/.cf_ssh_token" "$HOME/.install_ssh_checkpoint" 2>/dev/null
      grep -v "^ssh\.\|^dashboard\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Remote desinstalado"
      echo -e "  ${DIM}(~/.ssh/authorized_keys conservado)${NC}" ;;
    opencode)
      [ -f "$HOME/.opencode_web.pid" ] && {
        kill "$(cat "$HOME/.opencode_web.pid")" 2>/dev/null || true
        rm -f "$HOME/.opencode_web.pid"
      }
      pkill -f "opencode web" 2>/dev/null || true
      if proot-distro login debian -- bash -c 'true' &>/dev/null 2>&1; then
        proot-distro login debian -- bash -c '
          rm -rf /root/.opencode /root/.config/opencode /root/.local/share/opencode /root/.cache/opencode 2>/dev/null
          echo "[OK] Archivos OpenCode eliminados"
        ' 2>/dev/null
      fi
      grep -v "^opencode\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} OpenCode desinstalado" ;;
    openclaw)
      pkill -f "openclaw\|node.*openclaw" 2>/dev/null || true
      [ -f "$HOME/.openclaw_gateway.pid" ] && {
        kill "$(cat "$HOME/.openclaw_gateway.pid")" 2>/dev/null || true
        rm -f "$HOME/.openclaw_gateway.pid"
      }
      if proot-distro login debian -- bash -c 'true' &>/dev/null 2>&1; then
        proot-distro login debian -- bash -c '
          rm -rf /root/.nvm /root/.openclaw /root/openclaw-shim.cjs /root/.npm 2>/dev/null
          echo "[OK] Archivos OpenClaw eliminados"
        ' 2>/dev/null
      fi
      rm -f "$OPENCLAW_SCRIPTS/openclaw_start.sh" "$OPENCLAW_SCRIPTS/openclaw_stop.sh" "$OPENCLAW_SCRIPTS/openclaw_token.sh" 2>/dev/null
      rm -f "$HOME/.openclaw_gateway.log" 2>/dev/null
      grep -v "^openclaw\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} OpenClaw desinstalado" ;;
  esac
  echo ""; read -r _ < /dev/tty
}

submenu_desinstalar() {
  while true; do
    clear; echo ""
    echo -e "${RED}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⚠  Desinstalar módulo                  ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] n8n + proot  [2] Claude Code${RED}${BOLD}        ║"
    echo -e "  ║  ${NC}[3] Ollama       [4] Expo / EAS${RED}${BOLD}         ║"
    echo -e "  ║  ${NC}[5] Python       [6] Remote${RED}${BOLD}             ║"
    echo -e "  ║  ${NC}[7] OpenCode     [8] OpenClaw${RED}${BOLD}           ║"
    echo -e "  ║  ${NC}[b] Cancelar${RED}${BOLD}                            ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Módulo: "; read -r OPT < /dev/tty

    case "$OPT" in
      1) uninstall_module "n8n"      "n8n + proot Debian"      ; break ;;
      2) uninstall_module "claude"   "Claude Code"              ; break ;;
      3) uninstall_module "ollama"   "Ollama"                   ; break ;;
      4) uninstall_module "expo"     "Expo / EAS CLI"           ; break ;;
      5) uninstall_module "python"   "Python + SQLite"          ; break ;;
      6) uninstall_module "remote"   "Remote (SSH + Dashboard)" ; break ;;
      7) uninstall_module "opencode" "OpenCode"                 ; break ;;
      8) uninstall_module "openclaw" "OpenClaw"                 ; break ;;
      b|B|"") break ;;
    esac
  done
}

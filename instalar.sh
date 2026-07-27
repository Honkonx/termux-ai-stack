#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · instalar.sh
#  Script maestro — setup inicial completo
#
#  USO (primera vez):
#    bash <(curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/instalar.sh)
#
#  O descargarlo primero:
#    curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/instalar.sh -o instalar.sh
#    bash instalar.sh
#
#  QUÉ HACE:
#    ✅ PASO 0 — Permisos de almacenamiento
#    ✅ PASO 1 — pkg update + dependencias base (silencioso)
#    ✅ PASO 2 — Tema GitHub Dark + JetBrains Mono + extra-keys
#    ✅ PASO 3 — Descarga scripts individuales desde el repo (silencioso)
#    ✅ PASO 4 — Configura .bashrc auto-launch
#    ✅ PASO 5 — Menú interactivo para instalar módulos
#    ✅ PASO 6 — Termux:API opcional (necesario para app Android)
#
#  Toda la lógica de pkg/npm/descarga corre en background con spinner
#  y log completo en ~/.termux-ai-stack/logs/ — nunca en pantalla.
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 4.0.0 | Julio 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"
export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib"

# Fix stdin cuando se ejecuta via curl | bash
exec < /dev/tty

# ── URLs ──────────────────────────────────────────────────────
REPO_RAW_SCRIPT="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts"
REPO_URL="https://github.com/Honkonx/termux-ai-stack"

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }

# ── Estado ────────────────────────────────────────────────────
CHECKPOINT="$HOME/.instalar_checkpoint"
REGISTRY="$HOME/.android_server_registry"
LOG_DIR="$HOME/.termux-ai-stack/logs"
mkdir -p "$LOG_DIR"

check_done()   { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()    { echo "$1" >> "$CHECKPOINT"; }
get_reg()      { grep "^${1}\.${2}=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2; }
check_module() { [ "$(get_reg "$1" installed)" = "true" ]; }

# ── Ejecutar un paso pesado (pkg/npm/descargas) en background con
#    spinner + log completo — nunca imprime el output crudo en pantalla.
#    Uso: _run_silent "Etiqueta" comando arg1 arg2...
_LAST_SILENT_LOG=""
_run_silent() {
  local _label="$1"; shift
  local _log="$LOG_DIR/instalar_$(date +%Y%m%d_%H%M%S)_$$.log"
  _LAST_SILENT_LOG="$_log"
  ( "$@" ) > "$_log" 2>&1 &
  local _pid=$!
  local _SC="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏" _SI=0
  while kill -0 "$_pid" 2>/dev/null; do
    printf "\r  ${CYAN}%s${NC} ${DIM}%s...${NC}" "${_SC:$((_SI % ${#_SC})):1}" "$_label"
    _SI=$((_SI + 1)); sleep 0.12
  done
  wait "$_pid"
  local _exit=$?
  printf "\r\033[2K"
  if [ "$_exit" -eq 0 ]; then
    log "$_label completado"
  else
    echo -e "  ${RED}[ERROR]${NC} $_label falló (código $_exit)"
    echo -e "  ${DIM}Log completo: $_log${NC}"
    echo -e "  ${YELLOW}Últimas líneas:${NC}"
    tail -15 "$_log" 2>/dev/null | sed 's/^/  /'
  fi
  return "$_exit"
}

# ════════════════════════════════════════════════════════════
# CABECERA
# ════════════════════════════════════════════════════════════
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════════╗
  ║                                                  ║
  ║      ████████╗███████╗██████╗ ███╗   ███╗██╗   ║
  ║         ██╔══╝██╔════╝██╔══██╗████╗ ████║╚██╗  ║
  ║         ██║   █████╗  ██████╔╝██╔████╔██║ ╚██╗ ║
  ║         ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║ ██╔╝ ║
  ║         ██║   ███████╗██║  ██║██║ ╚═╝ ██║██╔╝  ║
  ║         ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝   ║
  ║                                                  ║
  ║        termux-ai-stack · Setup Inicial           ║
  ║        v4.0.0 · Android ARM64 · sin root         ║
  ╚══════════════════════════════════════════════════╝
HEADER
echo -e "${NC}"
echo "  Repo: $REPO_URL"
echo ""

# ── Checkpoints previos ───────────────────────────────────────
if [ -f "$CHECKPOINT" ] && [ -s "$CHECKPOINT" ]; then
  echo -e "${YELLOW}  Setup previo detectado — se omitirán:${NC}"
  while IFS= read -r line; do
    echo -e "  ${GREEN}✓${NC} $line"
  done < "$CHECKPOINT"
  echo ""
  read -r -p "  ¿Continuar desde donde quedó? (s/n): " CONT
  [ "$CONT" != "s" ] && [ "$CONT" != "S" ] && {
    read -r -p "  ¿Reiniciar desde cero? (s/n): " RESET
    [ "$RESET" = "s" ] || [ "$RESET" = "S" ] && rm -f "$CHECKPOINT"
  }
fi

# ============================================================
# PASO 0 — Permisos de almacenamiento
# ============================================================
titulo "PASO 0 — Permisos de almacenamiento"

if check_done "storage_perms"; then
  log "Permisos ya verificados [checkpoint]"
else
  if ! touch /sdcard/Download/.termux_test 2>/dev/null; then
    info "Solicitando permisos de almacenamiento..."
    termux-setup-storage
    sleep 3
    if ! touch /sdcard/Download/.termux_test 2>/dev/null; then
      warn "Sin permisos de almacenamiento"
      warn "Ve a: Ajustes → Apps → Termux → Permisos → Almacenamiento"
      warn "Continuando sin acceso a /sdcard..."
    else
      rm -f /sdcard/Download/.termux_test
      log "Permisos de almacenamiento OK"
    fi
  else
    rm -f /sdcard/Download/.termux_test
    log "Permisos de almacenamiento OK"
  fi
  mark_done "storage_perms"
fi

# ============================================================
# PASO 1 — pkg update + dependencias base (silencioso)
# ============================================================
titulo "PASO 1 — Actualizando Termux"

_paso1_worker() {
  MIRRORS=(
    "https://packages.termux.dev/apt/termux-main"
    "https://mirror.accum.se/mirror/termux.dev/apt/termux-main"
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
  )

  try_update() {
    pkg update -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>&1
  }

  set_mirror() {
    echo "deb $1 stable main" > "$TERMUX_PREFIX/etc/apt/sources.list"
    echo "Mirror: $1"
  }

  OUT=$(try_update)
  echo "$OUT"
  if echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
    echo "Mirror roto — probando alternativas..."
    OK=0
    for m in "${MIRRORS[@]}"; do
      set_mirror "$m"
      OUT=$(try_update)
      echo "$OUT"
      if ! echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
        echo "Mirror OK: $m"; OK=1; break
      fi
    done
    [ "$OK" = "0" ] && { echo "Todos los mirrors fallaron."; exit 1; }
  fi

  pkg upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>&1

  pkg install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    curl wget tar xz-utils tmux \
    proot proot-distro busybox iproute2 \
    git unzip 2>&1

  for p in curl wget tmux proot-distro git; do
    command -v "$p" &>/dev/null && echo "$p OK" || echo "AVISO: $p no instaló"
  done
}

if check_done "pkg_update"; then
  log "Termux ya actualizado [checkpoint]"
else
  if _run_silent "Actualizando Termux" _paso1_worker; then
    export ANDROID_SERVER_READY=1
    mark_done "pkg_update"
  else
    error "PASO 1 falló — revisa el log de arriba"
  fi
fi

# ============================================================
# PASO 2 — Tema GitHub Dark + fuente + extra-keys
# ============================================================
titulo "PASO 2 — Tema visual"

_paso2_worker() {
  TERMUX_CONFIG="$HOME/.termux"
  mkdir -p "$TERMUX_CONFIG"

  cat > "$TERMUX_CONFIG/colors.properties" << 'COLORS'
background=#0d1117
foreground=#c9d1d9
color0=#484f58
color1=#ff7b72
color2=#3fb950
color3=#d29922
color4=#58a6ff
color5=#bc8cff
color6=#39c5cf
color7=#b1bac4
color8=#6e7681
color9=#ffa198
color10=#56d364
color11=#e3b341
color12=#79c0ff
color13=#d2a8ff
color14=#56d4dd
color15=#f0f6fc
COLORS

  cat > "$TERMUX_CONFIG/termux.properties" << 'PROPS'
# termux-ai-stack — Configuración Termux
extra-keys = [['ESC','TAB','CTRL','ALT','|','/','UP','DOWN'],['n8n-start','n8n-url','claude','ollama-start','menu','help','LEFT','RIGHT']]
bell-character=ignore
PROPS

  FONT_FILE="$TERMUX_CONFIG/font.ttf"
  if [ ! -f "$FONT_FILE" ]; then
    echo "Descargando JetBrains Mono..."
    FONT_URL="https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
    FONT_TMP="$HOME/jbmono.zip"
    curl -fL "$FONT_URL" -o "$FONT_TMP" 2>&1 || wget -q "$FONT_URL" -O "$FONT_TMP" 2>&1
    if [ -f "$FONT_TMP" ] && [ -s "$FONT_TMP" ]; then
      unzip -q "$FONT_TMP" "fonts/ttf/JetBrainsMono-Regular.ttf" -d "$HOME/jbmono_tmp" 2>&1
      mv "$HOME/jbmono_tmp/fonts/ttf/JetBrainsMono-Regular.ttf" "$FONT_FILE" 2>&1 || true
      rm -rf "$HOME/jbmono.zip" "$HOME/jbmono_tmp" 2>/dev/null
      [ -f "$FONT_FILE" ] && echo "JetBrains Mono instalada" || echo "AVISO: no se pudo instalar la fuente"
    fi
  else
    echo "JetBrains Mono ya instalada [skip]"
  fi

  command -v termux-reload-settings &>/dev/null && termux-reload-settings 2>&1
}

if check_done "tema_visual"; then
  log "Tema visual ya aplicado [checkpoint]"
else
  _run_silent "Aplicando tema GitHub Dark + JetBrains Mono" _paso2_worker
  mark_done "tema_visual"
fi

# ============================================================
# PASO 3 — Instalar scripts base (silencioso)
# ============================================================
titulo "PASO 3 — Instalando scripts base"

# Lista de scripts descargados desde scripts/ del repo — install_ssh.sh
# ya no existe (fusionado en install_remote.sh). Corregido 2026-07-27:
# faltaban hermes/codex/antigravity/entorno — nunca se descargaban en
# la instalación inicial, solo si el usuario los pedía manualmente
# después desde el menú (y ahí dependían del fallback de menu.sh, que
# también tenía la URL rota — ver docs/BUGS_PERSISTENTES_2026-07-26.md)
BASE_SCRIPTS=(
  install_n8n.sh install_claude.sh install_ollama.sh
  install_expo.sh install_python.sh
  install_remote.sh install_opencode.sh install_openclaw.sh
  install_hermes.sh install_codex.sh install_antigravity.sh
  install_entorno.sh
)

download_file() {
  local url="$1"
  local dest="$2"
  local label="$3"
  rm -f "$dest"
  curl -fsSL "$url" -o "$dest" 2>&1 || wget -q "$url" -O "$dest" 2>&1
  if [ -f "$dest" ] && [ -s "$dest" ]; then
    chmod +x "$dest"
    echo "$label OK"
    return 0
  else
    rm -f "$dest"
    echo "AVISO: $label — fallo al descargar"
    return 1
  fi
}

_paso3_worker() {
  local ok=0 fail=0

  # menu.sh vive en scripts/ del repo (2026-07-23: ya no en raíz)
  download_file "$REPO_RAW_SCRIPT/menu.sh" "$HOME/menu.sh" "menu.sh" \
    && ok=$((ok + 1)) || fail=$((fail + 1))

  download_file "$REPO_RAW_SCRIPT/backup.sh" "$HOME/backup.sh" "backup.sh" \
    && ok=$((ok + 1)) || fail=$((fail + 1))
  download_file "$REPO_RAW_SCRIPT/restore.sh" "$HOME/restore.sh" "restore.sh" \
    && ok=$((ok + 1)) || fail=$((fail + 1))

  for script in "${BASE_SCRIPTS[@]}"; do
    if download_file "$REPO_RAW_SCRIPT/$script" "$HOME/$script" "$script"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done

  mkdir -p "$HOME/scripts"
  for script in menu_nativo.sh menu_proot.sh menu_entorno.sh; do
    if download_file "$REPO_RAW_SCRIPT/$script" "$HOME/scripts/$script" "$script"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done

  echo "$ok scripts descargados, $fail fallaron"
  [ "$fail" -eq 0 ]
}

if check_done "base_scripts"; then
  log "Scripts base ya instalados [checkpoint]"
else
  _run_silent "Descargando scripts desde el repo" _paso3_worker
  mark_done "base_scripts"
fi

# Verificar qué scripts hay disponibles
echo ""
info "Scripts disponibles en ~/:"
for script in menu.sh backup.sh restore.sh "${BASE_SCRIPTS[@]}"; do
  if [ -f "$HOME/$script" ] && [ -s "$HOME/$script" ]; then
    SIZE=$(wc -c < "$HOME/$script" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} ~/$script  (${SIZE} bytes)"
  else
    echo -e "  ${YELLOW}?${NC} ~/$script  (no disponible)"
  fi
done
info "Scripts en ~/scripts/:"
for script in menu_nativo.sh menu_proot.sh menu_entorno.sh; do
  if [ -f "$HOME/scripts/$script" ] && [ -s "$HOME/scripts/$script" ]; then
    SIZE=$(wc -c < "$HOME/scripts/$script" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} ~/scripts/$script  (${SIZE} bytes)"
  else
    echo -e "  ${YELLOW}?${NC} ~/scripts/$script  (no disponible)"
  fi
done

# ============================================================
# PASO 4 — Configurar .bashrc
# ============================================================
titulo "PASO 4 — Configurando .bashrc"

if check_done "bashrc_config"; then
  log ".bashrc ya configurado [checkpoint]"
else
  BASHRC="$HOME/.bashrc"

  if grep -q "termux-ai-stack" "$BASHRC" 2>/dev/null; then
    info "Eliminando configuración anterior..."
    sed -i '/# ════.*termux-ai-stack/,/# FIN ANDROID SERVER STACK/d' "$BASHRC" 2>/dev/null || \
      grep -v "termux-ai-stack\|alias menu\|alias help\|menu\.sh\|ANDROID_SERVER_READY\|FIN ANDROID" \
        "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
  fi

  cat >> "$BASHRC" << 'BASHRC_BLOCK'

# ════════════════════════════════════════
#  termux-ai-stack · configuración base
# ════════════════════════════════════════
alias menu='bash ~/menu.sh'
alias remote='bash ~/scripts/remote/ssh_start.sh'

# Auto-ejecutar menu al abrir Termux
if [ -z "$TMUX" ] && [ -z "$ANDROID_SERVER_READY" ]; then
  bash ~/menu.sh
fi
# FIN ANDROID SERVER STACK
BASHRC_BLOCK

  mark_done "bashrc_config"
  log ".bashrc configurado"
fi

# ============================================================
# PASO 5 — Selección de módulos (silencioso)
# ============================================================
titulo "PASO 5 — Módulos disponibles"

echo "  Instala módulos ahora o después desde el menú."
echo ""

run_module() {
  local name="$1"
  local key="$2"
  local script="install_${key}.sh"
  local dest="$HOME/$script"

  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    warn "~/$script no encontrado — re-descargando..."
    download_file "$REPO_RAW_SCRIPT/$script" "$dest" "$script"
  fi
  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    echo -e "  ${RED}[ERROR]${NC} No se pudo obtener $script"
    return 1
  fi

  # Módulos con selector de variante propio: se pre-elige un default
  # razonable acá porque instalar.sh no tiene el menú de variante visible
  # que sí existe en menu.sh — el usuario puede cambiarla después desde ahí
  case "$key" in
    ollama) export OLLAMA_INSTALL_MODE="${OLLAMA_INSTALL_MODE:-standard}" ;;
    claude) export CLAUDE_METHOD="${CLAUDE_METHOD:-native}" ;;
    n8n)    export N8N_INSTALL_MODE="${N8N_INSTALL_MODE:-1}" ;;
  esac

  _run_silent "Instalando $name" bash "$dest" --silent
  local _rc=$?

  case "$key" in
    ollama) unset OLLAMA_INSTALL_MODE ;;
    claude) unset CLAUDE_METHOD ;;
    n8n)    unset N8N_INSTALL_MODE ;;
  esac

  return "$_rc"
}

# Estado de módulos
echo -e "  Módulo                Estado"
echo -e "  ──────────────────────────────────────────────"

check_module "n8n"         && N8N_V=$(get_reg n8n version)         && echo -e "  [1] n8n               ${GREEN}✓ v${N8N_V}${NC}  (reinstalar: 1)"  || echo -e "  [1] n8n               ${YELLOW}○ no instalado${NC}"
check_module "claude_code" && CC_V=$(get_reg claude_code version)  && echo -e "  [2] Claude Code       ${GREEN}✓ v${CC_V}${NC}  (reinstalar: 2)"   || echo -e "  [2] Claude Code       ${YELLOW}○ no instalado${NC}"
check_module "ollama"      && OL_V=$(get_reg ollama version)       && echo -e "  [3] Ollama            ${GREEN}✓ v${OL_V}${NC}  (reinstalar: 3)"   || echo -e "  [3] Ollama            ${YELLOW}○ no instalado${NC}"
check_module "expo"        && EX_V=$(get_reg expo version)         && echo -e "  [4] Expo / EAS        ${GREEN}✓ v${EX_V}${NC}  (reinstalar: 4)"   || echo -e "  [4] Expo / EAS        ${YELLOW}○ no instalado${NC}"
check_module "python"      && PY_V=$(get_reg python version)       && echo -e "  [5] Python            ${GREEN}✓ v${PY_V}${NC}  (reinstalar: 5)"   || echo -e "  [5] Python            ${YELLOW}○ no instalado${NC}"
check_module "ssh"                                                 && echo -e "  [6] Remote (SSH)      ${GREEN}✓ instalado${NC}  (reinstalar: 6)"  || echo -e "  [6] Remote (SSH)      ${YELLOW}○ no instalado${NC}"
check_module "opencode"    && OC_V=$(get_reg opencode version)     && echo -e "  [7] OpenCode          ${GREEN}✓ v${OC_V}${NC}  (reinstalar: 7)"   || echo -e "  [7] OpenCode          ${YELLOW}○ no instalado${NC}"
check_module "openclaw"    && CL_V=$(get_reg openclaw version)     && echo -e "  [8] OpenClaw          ${GREEN}✓ v${CL_V}${NC}  (reinstalar: 8)"   || echo -e "  [8] OpenClaw          ${YELLOW}○ no instalado${NC}"
check_module "hermes"      && HM_V=$(get_reg hermes version)       && echo -e "  [9] Hermes Agent      ${GREEN}✓ v${HM_V}${NC}  (reinstalar: 9)"   || echo -e "  [9] Hermes Agent      ${YELLOW}○ no instalado${NC}"
check_module "codex"       && CX_V=$(get_reg codex version)        && echo -e "  [10] Codex CLI        ${GREEN}✓ v${CX_V}${NC}  (reinstalar: 10)"  || echo -e "  [10] Codex CLI        ${YELLOW}○ no instalado${NC}"
check_module "antigravity" && AG_V=$(get_reg antigravity version)  && echo -e "  [11] Antigravity CLI  ${GREEN}✓ v${AG_V}${NC}  (reinstalar: 11)"  || echo -e "  [11] Antigravity CLI  ${YELLOW}○ no instalado${NC}"
check_module "entorno"     && EN_V=$(get_reg entorno version)      && echo -e "  [12] Entorno          ${GREEN}✓ v${EN_V}${NC}  (reinstalar: 12)"  || echo -e "  [12] Entorno          ${YELLOW}○ no instalado${NC}"

echo ""
echo "  [a] Instalar todos"
echo "  [s] Saltar — instalaré después desde el menú"
echo ""
read -r -p "  Elige [1-12/a/s]: " MODULE_CHOICE < /dev/tty

case "$MODULE_CHOICE" in
  1) run_module "n8n"         "n8n"    ;;
  2) run_module "Claude Code" "claude" ;;
  3) run_module "Ollama"      "ollama" ;;
  4) run_module "Expo/EAS"    "expo"   ;;
  5) run_module "Python"      "python" ;;
  6) run_module "Remote (SSH)" "remote" ;;
  7) run_module "OpenCode"        "opencode"    ;;
  8) run_module "OpenClaw"        "openclaw"    ;;
  9) run_module "Hermes Agent"    "hermes"      ;;
  10) run_module "Codex CLI"      "codex"       ;;
  11) run_module "Antigravity CLI" "antigravity" ;;
  12) run_module "Entorno"        "entorno"     ;;
  a|A)
    run_module "n8n"           "n8n"
    run_module "Claude Code"   "claude"
    run_module "Ollama"        "ollama"
    run_module "Expo/EAS"      "expo"
    run_module "Python"        "python"
    run_module "Remote (SSH)"  "remote"
    run_module "OpenCode"      "opencode"
    run_module "OpenClaw"      "openclaw"
    run_module "Hermes Agent"  "hermes"
    run_module "Codex CLI"     "codex"
    run_module "Antigravity CLI" "antigravity"
    run_module "Entorno"       "entorno"
    ;;
  s|S|"") info "Módulos omitidos — instálalos después con: menu" ;;
  *)      warn "Opción no reconocida — instala módulos después con: menu" ;;
esac

# ============================================================
# PASO 6 — Termux:API (opcional)
# ============================================================
titulo "PASO 6 — Termux:API (opcional)"

if check_done "termuxapi_install"; then
  log "Termux:API ya instalado [checkpoint]"
else
  echo "  Termux:API permite que la app Android controle"
  echo "  los servicios del stack (iniciar/detener n8n, Ollama, etc.)"
  echo ""
  echo "  IMPORTANTE: También debes instalar la app Termux:API"
  echo "  desde F-Droid (no desde Google Play — la versión de"
  echo "  Play Store está desactualizada y puede no funcionar)."
  echo ""
  echo -n "  ¿Instalar pkg termux-api? (s/n): "
  read -r INST_API < /dev/tty
  if [ "$INST_API" = "s" ] || [ "$INST_API" = "S" ]; then
    _run_silent "Instalando termux-api" pkg install termux-api -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"
    sed -i '/^termuxapi\.installed=/d' "$REGISTRY" 2>/dev/null
    echo "termuxapi.installed=true" >> "$REGISTRY"
  else
    info "Termux:API omitido — instala después con: pkg install termux-api"
    echo "termuxapi.installed=false" >> "$REGISTRY"
  fi
  mark_done "termuxapi_install"
fi

# ── Info dependencias del stack IA ───────────────────────────
echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}  ║  💡 ¿Qué necesita qué?                          ║${NC}"
echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Para usar bots de IA con Telegram (workflows WF1-WF4):"
echo ""
echo "  n8n           → automatización y webhooks Telegram"
echo "    requiere → Python 3 (para scripts de visión)"
echo "    requiere → Ollama   (para respuestas de IA)"
echo ""
echo "  Ollama        → modelos de IA local (qwen2.5, gemma3, moondream)"
echo "    requiere → Python 3 + Pillow (para visión con imágenes)"
echo ""
echo "  Stack mínimo para bot de texto:  n8n + Ollama"
echo "  Stack completo para bot de fotos: n8n + Ollama + Python + Pillow"
echo ""

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "SETUP COMPLETADO"

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════════╗
  ║     termux-ai-stack v4.0.0 configurado ✓        ║
  ╚══════════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  SCRIPTS EN ~/:"
for f in menu.sh backup.sh restore.sh "${BASE_SCRIPTS[@]}"; do
  [ -f "$HOME/$f" ] && \
    echo -e "  ${GREEN}✓${NC} ~/$f" || \
    echo -e "  ${YELLOW}?${NC} ~/$f (no disponible)"
done

echo ""
echo "  SCRIPTS EN ~/scripts/:"
for f in menu_nativo.sh menu_proot.sh menu_entorno.sh; do
  [ -f "$HOME/scripts/$f" ] && \
    echo -e "  ${GREEN}✓${NC} ~/scripts/$f" || \
    echo -e "  ${YELLOW}?${NC} ~/scripts/$f (no disponible)"
done

echo ""
echo "  COMANDOS:"
echo "  menu        → abrir dashboard TUI"
echo "  claude      → Claude Code"
echo "  n8n-start   → iniciar n8n"
echo "  ollama-start → iniciar Ollama"
echo "  remote      → iniciar SSH"
echo ""

rm -f "$CHECKPOINT"

echo -e "${CYAN}${BOLD}  → Cargando dashboard...${NC}"
echo ""
exec bash "$HOME/menu.sh"

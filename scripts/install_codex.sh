#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_codex.sh  v1.0.0
#  Instala OpenAI Codex CLI para Termux ARM64 (vía npm)
#
#  CANALES DISPONIBLES:
#    termux   → @mmmbuto/codex-cli-termux@next  (Termux fork)
#    vl       → @mmmbuto/codex-vl@latest         (Codex VL fork)
#    official → npm install -g codex@latest       (futuro)
#    native   → binario ARM64 prebuilt, SIN Node.js (ver docs/REFERENCIA_TERMUX_AI_MASTER.md)
#               github.com/WangChengYeh/codex_android — versión pinneada v0.25.0,
#               NO "latest" (repo de un solo mantenedor, no oficial de OpenAI —
#               riesgo asumido a propósito, ver esa doc para el detalle completo)
#
#  USO:
#    bash install_codex.sh                       → instalar / reinstall
#    CODEX_CHANNEL=vl bash install_codex.sh      → instalar canal específico
#    CODEX_CHANNEL=native bash install_codex.sh  → binario nativo, sin Node.js
#    CODEX_MODE=update bash install_codex.sh     → actualizar
#    CODEX_MODE=uninstall bash install_codex.sh  → desinstalar
# ============================================================

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Modo silencioso (invocado desde menu.sh, confirmación ya hecha ahí) ──
SILENT_MODE=false
FORCE_MODE=false
for _arg in "$@"; do
  [ "$_arg" = "--silent" ] && SILENT_MODE=true
  [ "$_arg" = "--force" ] && FORCE_MODE=true
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log()    { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "  ${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "  ${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "  ${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }

REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_codex_checkpoint"

mark_done()  { grep -q "^codex_${1}=done" "$CHECKPOINT" 2>/dev/null || echo "codex_${1}=done" >> "$CHECKPOINT"; }
check_done() { grep -q "^codex_${1}=done" "$CHECKPOINT" 2>/dev/null; }

_read_reg()  { grep "^codex\.${1}=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2; }
_update_reg() {
  local _tmp="$REGISTRY.tmp"
  grep -v "^codex\." "$REGISTRY" > "$_tmp" 2>/dev/null || touch "$_tmp"
  for kv in "$@"; do echo "codex.$kv" >> "$_tmp"; done
  mv "$_tmp" "$REGISTRY"
}

get_installed_ver() {
  command -v codex &>/dev/null && codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
}

declare -A CODEX_CHANNELS
CODEX_CHANNELS[termux]="@mmmbuto/codex-cli-termux@next"
CODEX_CHANNELS[vl]="@mmmbuto/codex-vl@latest"
CODEX_CHANNELS[official]="codex@latest"

CODEX_NATIVE_VERSION="0.25.0"
CODEX_NATIVE_URL="https://github.com/WangChengYeh/codex_android/releases/download/v${CODEX_NATIVE_VERSION}/android-codex-cli-binaries-${CODEX_NATIVE_VERSION}-aarch64.tar.gz"

# 2026-07-28: canal "native" — binario ARM64 prebuilt, no pasa por npm/Node.js en
# absoluto (ver docs/REFERENCIA_TERMUX_AI_MASTER.md). No hay checksum SHA256
# publicado que se haya podido verificar al escribir esto — la mitigación real
# es la misma que ya se usa en ssh.sh/n8n.sh/cloudflared: no confiar en que el
# archivo se descargó bien solo porque curl devolvió 0, VERIFICAR que el binario
# efectivamente corre sobre Bionic antes de darlo por instalado.
_install_codex_native() {
  titulo "Codex CLI — canal native (binario prebuilt, sin Node.js)"
  if command -v codex &>/dev/null && [ "$(_read_reg channel)" = "native" ] && ! $FORCE_MODE; then
    log "Codex CLI (native) ya instalado — $(codex --version 2>/dev/null | head -1)"
    return 0
  fi
  info "Descargando binario v${CODEX_NATIVE_VERSION} de codex_android..."
  local tmp="$HOME/tmp/codex_native_dl"
  mkdir -p "$tmp"
  local tarball="$tmp/codex-native.tar.gz"
  if command -v curl &>/dev/null; then
    curl -fsSL --max-time 60 "$CODEX_NATIVE_URL" -o "$tarball" || error "Descarga falló (curl)"
  elif command -v wget &>/dev/null; then
    wget -q --timeout=60 "$CODEX_NATIVE_URL" -O "$tarball" || error "Descarga falló (wget)"
  else
    error "Ni curl ni wget disponibles"
  fi
  [ -s "$tarball" ] || error "Descarga vacía o incompleta"

  tar -xzf "$tarball" -C "$tmp" || error "No se pudo extraer el tarball"
  local bin_src exec_src
  bin_src=$(find "$tmp" -type f -name "codex-aarch64-linux-android" | head -1)
  exec_src=$(find "$tmp" -type f -name "codex-exec-aarch64-linux-android" | head -1)
  [ -z "$bin_src" ] && error "No se encontró el binario codex-aarch64-linux-android en el tarball"

  mkdir -p "$TERMUX_PREFIX/opt/codex-native"
  cp "$bin_src" "$TERMUX_PREFIX/opt/codex-native/codex"
  chmod +x "$TERMUX_PREFIX/opt/codex-native/codex"
  if [ -n "$exec_src" ]; then
    cp "$exec_src" "$TERMUX_PREFIX/opt/codex-native/codex-exec"
    chmod +x "$TERMUX_PREFIX/opt/codex-native/codex-exec"
  fi
  ln -sf "$TERMUX_PREFIX/opt/codex-native/codex" "$TERMUX_PREFIX/bin/codex"

  # Verificación real de ejecución — no solo que el archivo exista (mismo patrón
  # que cloudflared/ssh.sh: un binario ARM64 no siempre corre sobre Bionic).
  if ! codex --version &>/dev/null; then
    rm -f "$TERMUX_PREFIX/bin/codex"
    rm -rf "$TERMUX_PREFIX/opt/codex-native"
    error "Binario descargado pero no ejecuta (incompatible con Bionic) — probar otro canal (CODEX_CHANNEL=termux)"
  fi
  rm -rf "$tmp"

  mkdir -p "$HOME/.config/codex"
  _update_reg "installed=true" "version=${CODEX_NATIVE_VERSION}" "channel=native" "install_date=$(date +%Y-%m-%d)"
  log "Codex CLI (native) instalado: $(codex --version 2>/dev/null | head -1)"
  return 0
}

CODEX_CHANNEL="${CODEX_CHANNEL:-termux}"
CODEX_PKG="${CODEX_CHANNELS[$CODEX_CHANNEL]}"

if [ "$CODEX_CHANNEL" = "native" ]; then
  _install_codex_native
  exit $?
fi

detect_active_channel() {
  local _pkg
  _pkg=$(npm ls -g --depth=0 2>/dev/null | grep -o "@mmmbuto/codex-cli-termux\|@mmmbuto/codex-vl\|codex[^@]*" | head -1)
  case "$_pkg" in
    @mmmbuto/codex-cli-termux) echo "termux" ;;
    @mmmbuto/codex-vl)         echo "vl" ;;
    codex*)                     echo "official" ;;
    *)                          echo "" ;;
  esac
}

# ── Dispatch: update ─────────────────────────────────────────
if [ "${CODEX_MODE:-}" = "update" ]; then
  titulo "ACTUALIZANDO Codex CLI"
  _VER_BEFORE=$(get_installed_ver)
  if npm update -g "$CODEX_PKG" 2>/dev/null; then
    _VER_AFTER=$(get_installed_ver)
    log "Codex CLI actualizado"
    _DATE=$(python3 -c "from datetime import datetime; print(datetime.now().strftime('%Y-%m-%d'))" 2>/dev/null || date +%Y-%m-%d)
    _update_reg "version=$_VER_AFTER" "install_date=$_DATE" "channel=$CODEX_CHANNEL"
    echo -e "  Antes: ${_VER_BEFORE:-?}  →  Ahora: ${_VER_AFTER:-?}"
  else
    warn "No se pudo actualizar — reinstala con CODEX_MODE=reinstall"
  fi
  exit 0
fi

# ── Dispatch: uninstall ──────────────────────────────────────
if [ "${CODEX_MODE:-}" = "uninstall" ]; then
  titulo "DESINSTALANDO Codex CLI"
  _CH=$(detect_active_channel)
  [ -z "$_CH" ] && _CH="$CODEX_CHANNEL"
  _PKG="${CODEX_CHANNELS[$_CH]:-$CODEX_PKG}"
  npm uninstall -g "$_PKG" 2>/dev/null || true
  rm -f "$CHECKPOINT"
  _tmp="$REGISTRY.tmp"
  grep -v "^codex\." "$REGISTRY" > "$_tmp" 2>/dev/null || touch "$_tmp"
  mv "$_tmp" "$REGISTRY"
  log "Codex CLI desinstalado"
  exit 0
fi

# ════════════════════════════════════════════
#  BANNER
# ════════════════════════════════════════════
clear; echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║  ◆ CODEX CLI — Instalador               ║"
echo "  ║  OpenAI · Termux ARM64                  ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ════════════════════════════════════════════
#  DETECCIÓN DE INSTALACIÓN
# ════════════════════════════════════════════
_INSTALLED_VER=$(get_installed_ver)
_ACTIVE_CH=$(detect_active_channel)

# _SKIP_FINAL_CONFIRM: elegir reinstalar/cambiar canal aquí YA es la confirmación —
# no hace falta preguntar "¿instalar?" de nuevo después (bug reportado: doble diálogo)
_SKIP_FINAL_CONFIRM=false

if [ -n "$_INSTALLED_VER" ]; then
  if $SILENT_MODE; then
    # Invocado con --silent y ya instalado: reinstalar sin preguntar
    rm -f "$CHECKPOINT"
    _SKIP_FINAL_CONFIRM=true
  else
    echo -e "  ${GREEN}✓ Codex CLI ya instalado${NC} (v${_INSTALLED_VER})"
    [ -n "$_ACTIVE_CH" ] && echo -e "  ${DIM}Canal: ${_ACTIVE_CH}${NC}"
    echo ""
    echo -e "  ${BOLD}[1]${NC} Reinstalar (mantener configuración)"
    echo -e "  ${BOLD}[2]${NC} Cambiar canal (termux / vl / official)"
    echo -e "  ${BOLD}[b]${NC} Cancelar"
    echo ""; echo -n "  Opción: "
    read -r _RI < /dev/tty
    case "$_RI" in
      1) rm -f "$CHECKPOINT"; _SKIP_FINAL_CONFIRM=true ;;
      2)
        echo ""
        echo -e "  ${BOLD}Canales disponibles:${NC}"
        echo -e "  [1] termux   ${DIM}@mmmbuto/codex-cli-termux@next${NC}"
        echo -e "  [2] vl       ${DIM}@mmmbuto/codex-vl@latest${NC}"
        echo -e "  [3] official ${DIM}codex@latest (futuro)${NC}"
        echo -e "  [4] native   ${DIM}binario prebuilt v${CODEX_NATIVE_VERSION}, sin Node.js${NC}"
        echo ""; echo -n "  Canal: "
        read -r _CH_OPT < /dev/tty
        case "$_CH_OPT" in
          1) CODEX_CHANNEL="termux"; CODEX_PKG="${CODEX_CHANNELS[termux]}" ;;
          2) CODEX_CHANNEL="vl";     CODEX_PKG="${CODEX_CHANNELS[vl]}" ;;
          3) warn "Canal official no disponible aún"; exit 0 ;;
          4) _install_codex_native; exit $? ;;
          *) info "Sin cambios"; exit 0 ;;
        esac
        rm -f "$CHECKPOINT"; _SKIP_FINAL_CONFIRM=true ;;
      b|B|"") info "Nada que hacer"; exit 0 ;;
    esac
  fi
fi

# ── Confirmación (una sola vez — se salta si ya se confirmó arriba o es --silent) ──
if ! $SILENT_MODE && ! $_SKIP_FINAL_CONFIRM; then
  echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║  Vas a instalar:                        ║"
  echo    "  ║  OpenAI Codex CLI para Termux            ║"
  echo    "  ╠══════════════════════════════════════════╣"
  printf  "  ║  ${NC}Canal: %-33s${CYAN}${BOLD}║\n" "${CODEX_CHANNEL}"
  echo -e "  ║  ${NC}~50MB · npm install · requiere Node${CYAN}${BOLD}  ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  [1] Sí, instalar"
  echo -e "  [2] No, cancelar"
  echo ""; echo -n "  Opción: "
  read -r _CONFIRM < /dev/tty
  [ "$_CONFIRM" != "1" ] && { echo "Cancelado."; exit 0; }
fi

# ════════════════════════════════════════════
#  INSTALACIÓN
# ════════════════════════════════════════════

# ── PASO 1 — Node.js ─────────────────────────────────────────
titulo "PASO 1 — Verificando Node.js"
if check_done "node"; then
  log "Node.js ya verificado [checkpoint]"
else
  if command -v node &>/dev/null && command -v npm &>/dev/null; then
    _NODE_VER=$(node --version 2>/dev/null)
    log "Node.js detectado: ${_NODE_VER}"
    mark_done "node"
  else
    info "Instalando nodejs-lts..."
    pkg install nodejs-lts -y 2>/dev/null || error "No se pudo instalar Node.js"
    command -v node &>/dev/null || error "Node.js no disponible tras instalación"
    npm install -g npm 2>&1 | tail -2
    log "Node.js instalado: $(node --version)"
    mark_done "node"
  fi
fi

# ── PASO 2 — npm install ─────────────────────────────────────
titulo "PASO 2 — Instalando Codex CLI vía npm"
if check_done "npm_install"; then
  log "Codex CLI ya instalado [checkpoint]"
else
  info "Ejecutando: npm install -g ${CODEX_PKG}"
  echo ""
  npm install -g "$CODEX_PKG" 2>&1 | tail -5; [ ${PIPESTATUS[0]} -eq 0 ] || error "npm install falló"
  echo ""
  command -v codex &>/dev/null || error "codex no disponible tras instalación"
  log "Codex CLI instalado"
  mark_done "npm_install"
fi

# ── PASO 3 — Login ───────────────────────────────────────────
titulo "PASO 3 — Autenticación"
if check_done "login"; then
  log "Login ya completado [checkpoint]"
elif $SILENT_MODE; then
  warn "Modo silencioso — login omitido, ejecuta 'codex login' manualmente después"
  mark_done "login"
else
  echo -e "  ${DIM}Codex necesita login para funcionar.${NC}"
  echo -e "  ${DIM}Se abrirá el navegador para autenticarte.${NC}"
  echo ""
  echo -n "  ¿Iniciar login ahora? (s/n): "
  read -r _DO_LOGIN < /dev/tty
  if [ "$_DO_LOGIN" = "s" ] || [ "$_DO_LOGIN" = "S" ]; then
    echo ""
    codex login < /dev/tty
    echo ""
    log "Login completado"
    mark_done "login"
  else
    warn "Login omitido — ejecuta 'codex login' manualmente"
    mark_done "login"
  fi
fi

# ── Registry ─────────────────────────────────────────────────
titulo "FINALIZANDO"
_VER_FINAL=$(get_installed_ver)
_DATE=$(python3 -c "from datetime import datetime; print(datetime.now().strftime('%Y-%m-%d'))" 2>/dev/null || date +%Y-%m-%d)
_update_reg \
  "installed=true" \
  "version=${_VER_FINAL:-?}" \
  "channel=${CODEX_CHANNEL}" \
  "install_date=${_DATE}"

echo -e "  ${GREEN}${BOLD}✓ Codex CLI instalado correctamente${NC}"
echo -e "  ${DIM}Versión: ${_VER_FINAL:-?}  |  Canal: ${CODEX_CHANNEL}${NC}"
echo ""
echo -e "  ${DIM}Usa 'codex' para iniciar o el menú Code Tools${NC}"
echo ""

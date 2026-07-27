#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_claude.sh
#  Instala Claude Code en Termux ARM64 (sin root)
#
#  MÉTODOS:
#    native  — binario ELF + glibc-runner  (v2.1.152+, recomendado)
#    legacy  — npm @2.1.111 + Node.js      (garantizado, sin deps extra)
#
#  FLUJO:
#    1. Detecta si hay versión instalada y de qué tipo
#    2. Menú nivel 1: elegir método (native / legacy)
#    3. Bloqueo si el método elegido es distinto al instalado
#    4. Menú nivel 2: instalación limpia o desde GitHub Releases
#    5. Instala, crea wrapper, settings.json, registry
#
#  RUTAS:
#    native : ~/.local/share/claude-code/claude  (binario ELF)
#             ~/.local/bin/claude                (wrapper)
#    legacy : $PREFIX/lib/node_modules/@anthropic-ai/claude-code/cli.js
#             $PREFIX/bin/claude                 (wrapper node)
#
#  VERSIÓN: 3.0.0 | Mayo 2026
# ============================================================

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$HOME/.local/bin:$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Modo silencioso (invocado desde menu.sh, confirmación ya hecha ahí) ──
SILENT_MODE=false
for _arg in "$@"; do [ "$_arg" = "--silent" ] && SILENT_MODE=true; done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }

# ── Constantes ────────────────────────────────────────────────
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_claude_checkpoint"
CLAUDE_VERSION_LEGACY="2.1.111"
CLAUDE_VERSION_NATIVE="2.1.152"
NATIVE_BINARY="$HOME/.local/share/claude-code/claude"
NATIVE_WRAPPER="$HOME/.local/bin/claude"
LEGACY_WRAPPER="$TERMUX_PREFIX/bin/claude"
GLIBC_LD="$TERMUX_PREFIX/glibc/lib/ld-linux-aarch64.so.1"
PATCHELF="$TERMUX_PREFIX/glibc/bin/patchelf"
RELEASE_API="https://api.github.com/repos/Honkonx/termux-ai-stack/releases/latest"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ════════════════════════════════════════════════════════════
# DETECCIÓN — qué método está instalado actualmente
# ════════════════════════════════════════════════════════════
_detect_method() {
  # native: binario ELF ejecutable en ruta nativa
  if [ -f "$NATIVE_BINARY" ] && [ -x "$NATIVE_BINARY" ]; then
    echo "native"; return
  fi
  # legacy: cli.js via npm
  local npm_root; npm_root=$(npm root -g 2>/dev/null)
  if [ -f "${npm_root}/@anthropic-ai/claude-code/cli.js" ]; then
    echo "legacy"; return
  fi
  # wrapper legacy en PREFIX/bin pero sin cli.js → roto
  if [ -f "$LEGACY_WRAPPER" ]; then
    echo "broken"; return
  fi
  echo "none"
}

_detect_version() {
  local method="$1"
  case "$method" in
    native)
      "$NATIVE_WRAPPER" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    legacy)
      local npm_root; npm_root=$(npm root -g 2>/dev/null)
      local cli="${npm_root}/@anthropic-ai/claude-code/cli.js"
      node "$cli" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
  esac
}

# ════════════════════════════════════════════════════════════
# DESINSTALACIÓN LIMPIA POR MÉTODO
# ════════════════════════════════════════════════════════════
_uninstall_native() {
  info "Desinstalando Claude native..."
  rm -rf "$HOME/.local/share/claude-code" 2>/dev/null || true
  rm -f  "$NATIVE_WRAPPER" 2>/dev/null || true
  # NO desinstalar glibc-runner — puede usarlo OpenCode u otros
  grep -v "^claude_code\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && \
    mv "$REGISTRY.tmp" "$REGISTRY" || true
  rm -f "$CHECKPOINT" 2>/dev/null || true
  log "Claude native desinstalado"
}

_uninstall_legacy() {
  info "Desinstalando Claude legacy..."
  npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
  npm cache clean --force 2>/dev/null || true
  local npm_root; npm_root=$(npm root -g 2>/dev/null)
  rm -rf "${npm_root}/@anthropic-ai/claude-code" 2>/dev/null || true
  rm -f "$LEGACY_WRAPPER" 2>/dev/null || true
  grep -v "^claude_code\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && \
    mv "$REGISTRY.tmp" "$REGISTRY" || true
  rm -f "$CHECKPOINT" 2>/dev/null || true
  log "Claude legacy desinstalado"
}

# ════════════════════════════════════════════════════════════
# REGISTRY
# ════════════════════════════════════════════════════════════
_update_registry() {
  local version="$1" method="$2"
  local date_now; date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^claude_code\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
claude_code.installed=true
claude_code.version=${version}
claude_code.method=${method}
claude_code.install_date=${date_now}
claude_code.location=termux_native
EOF
  mv "$tmp" "$REGISTRY"
}

# ════════════════════════════════════════════════════════════
# CABECERA
# ════════════════════════════════════════════════════════════
_show_header() {
  clear; echo ""
  local CURRENT_METHOD; CURRENT_METHOD=$(_detect_method)
  local CURRENT_VER=""
  [ "$CURRENT_METHOD" != "none" ] && [ "$CURRENT_METHOD" != "broken" ] && \
    CURRENT_VER=$(_detect_version "$CURRENT_METHOD")

  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║  ⬡ Claude Code · Instalador             ║"
  echo    "  ╠══════════════════════════════════════════╣"
  case "$CURRENT_METHOD" in
    native)
      printf  "  ║  ${NC}Estado: ${GREEN}native v%-24s${CYAN}${BOLD}║\n" "${CURRENT_VER}  ✓"
      echo -e "  ║  ${NC}${DIM}glibc-runner · ~/.local/bin/claude${NC}${CYAN}${BOLD}     ║" ;;
    legacy)
      printf  "  ║  ${NC}Estado: ${GREEN}legacy v%-24s${CYAN}${BOLD}║\n" "${CURRENT_VER}  ✓"
      echo -e "  ║  ${NC}${DIM}npm · \$PREFIX/bin/claude${NC}${CYAN}${BOLD}              ║" ;;
    broken)
      echo -e "  ║  ${NC}Estado: ${RED}instalación rota${NC}${CYAN}${BOLD}               ║" ;;
    none)
      echo -e "  ║  ${NC}Estado: ${YELLOW}no instalado${NC}${CYAN}${BOLD}                   ║" ;;
  esac
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  # Exportar para uso en el resto del script
  INSTALLED_METHOD="$CURRENT_METHOD"
  INSTALLED_VER="$CURRENT_VER"
}

# ════════════════════════════════════════════════════════════
# MENÚ NIVEL 1 — Elegir método
# ════════════════════════════════════════════════════════════
_menu_metodo() {
  clear; echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║  Selecciona el método de instalación    ║"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}[1] Native  v${CLAUDE_VERSION_NATIVE}+  ${DIM}(recomendado)${NC}${CYAN}${BOLD}    ║"
  echo -e "  ║  ${NC}    ${DIM}binario ELF · glibc-runner${NC}${CYAN}${BOLD}           ║"
  echo -e "  ║  ${NC}    ${DIM}versiones más recientes de Claude${NC}${CYAN}${BOLD}     ║"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}[2] Legacy  v${CLAUDE_VERSION_LEGACY}  ${DIM}(garantizado)${NC}${CYAN}${BOLD}   ║"
  echo -e "  ║  ${NC}    ${DIM}npm · Node.js · sin deps extra${NC}${CYAN}${BOLD}       ║"
  echo -e "  ║  ${NC}    ${DIM}funciona en cualquier Termux${NC}${CYAN}${BOLD}         ║"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}[b] Volver / Cancelar${CYAN}${BOLD}                   ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""; echo -n "  Opción: "
  read -r OPT_METHOD < /dev/tty

  case "$OPT_METHOD" in
    1) CHOSEN_METHOD="native"  ;;
    2) CHOSEN_METHOD="legacy"  ;;
    b|B|q|Q|"") echo "Cancelado."; exit 0 ;;
    *) error "Opción inválida" ;;
  esac
}

# ════════════════════════════════════════════════════════════
# BLOQUEO — versión diferente ya instalada
# ════════════════════════════════════════════════════════════
_check_conflict() {
  # Sin conflicto si no hay nada instalado o si es el mismo método
  [ "$INSTALLED_METHOD" = "none" ]   && return 0
  [ "$INSTALLED_METHOD" = "broken" ] && return 0
  [ "$INSTALLED_METHOD" = "$CHOSEN_METHOD" ] && return 0

  # Conflicto: método distinto instalado
  local other_label
  [ "$INSTALLED_METHOD" = "native" ] && other_label="Native v${INSTALLED_VER}" \
                                     || other_label="Legacy v${INSTALLED_VER}"
  echo ""
  echo -e "${YELLOW}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  ⚠  %-38s║\n" "Conflicto de versiones"
  echo    "  ╠══════════════════════════════════════════╣"
  printf  "  ║  ${NC}Instalado: %-31s${YELLOW}${BOLD}║\n" "$other_label"
  printf  "  ║  ${NC}Elegido:   %-31s${YELLOW}${BOLD}║\n" "$CHOSEN_METHOD"
  echo -e "  ║  ${NC}No se pueden tener ambos a la vez.${YELLOW}${BOLD}      ║"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}¿Desinstalar ${other_label} ahora?${YELLOW}${BOLD}       ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  $SILENT_MODE && error "Conflicto de versión detectado — no se puede resolver en modo silencioso, ejecuta sin --silent para decidir manualmente"
  echo -n "  Escribe SI para desinstalar y continuar: "
  read -r CONFIRM_UNINSTALL < /dev/tty
  if [ "$CONFIRM_UNINSTALL" = "SI" ]; then
    [ "$INSTALLED_METHOD" = "native" ] && _uninstall_native || _uninstall_legacy
    INSTALLED_METHOD="none"
    INSTALLED_VER=""
  else
    warn "Instalación cancelada — desinstala primero desde: menú → Claude Code → Desinstalar"
    exit 0
  fi
}

# ════════════════════════════════════════════════════════════
# MENÚ NIVEL 2 — Fuente de instalación
# ════════════════════════════════════════════════════════════
_menu_fuente() {
  # Siempre instalación limpia — el usuario no necesita elegir fuente
  CHOSEN_SOURCE="clean"
}

# ════════════════════════════════════════════════════════════
# PASO COMÚN — Actualizar Termux + Node (solo legacy)
# ════════════════════════════════════════════════════════════
_ensure_termux() {
  if check_done "termux_update" || [ -n "$ANDROID_SERVER_READY" ]; then
    log "Termux ya preparado [skip]"
    return
  fi
  info "Actualizando Termux..."
  pkg update -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>&1 | tail -3
  mark_done "termux_update"
}

_ensure_nodejs() {
  check_done "nodejs" && { log "Node.js ya verificado [checkpoint]"; return; }
  if command -v node &>/dev/null; then
    local ver; ver=$(node --version 2>/dev/null | sed 's/v//' | cut -d'.' -f1)
    if [ "${ver:-0}" -ge 18 ] 2>/dev/null; then
      log "Node.js $(node --version) ✓"; mark_done "nodejs"; return
    fi
    warn "Node.js $(node --version) < 18 — actualizando..."
  else
    info "Node.js no encontrado — instalando..."
  fi
  pkg install nodejs-lts -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || error "Error instalando nodejs-lts"
  log "Node.js $(node --version) instalado"
  mark_done "nodejs"
}

_ensure_glibc() {
  check_done "glibc_deps" && { log "glibc-runner ya instalado [checkpoint]"; return; }
  info "Verificando glibc-runner..."

  local NEED_INSTALL=false
  [ ! -f "$GLIBC_LD" ]  && NEED_INSTALL=true
  [ ! -f "$PATCHELF" ]  && NEED_INSTALL=true

  if $NEED_INSTALL; then
    info "Instalando glibc-runner + patchelf-glibc + jq..."
    pkg install -y glibc-repo 2>/dev/null || true
    pkg update -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>&1 | tail -2
    pkg install -y glibc-runner patchelf-glibc jq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || error "No se pudo instalar glibc-runner"
  fi

  [ -f "$GLIBC_LD" ]  || error "ld.so no encontrado en $GLIBC_LD — reinstala glibc-runner"
  [ -f "$PATCHELF" ]  || error "patchelf no encontrado en $PATCHELF — reinstala patchelf-glibc"

  # Agregar ~/.local/bin al PATH si no está
  if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    export PATH="$HOME/.local/bin:$PATH"
    log "~/.local/bin agregado a PATH"
  fi
  log "glibc-runner listo: $GLIBC_LD"
  log "patchelf listo:     $PATCHELF"
  mark_done "glibc_deps"
}

# ════════════════════════════════════════════════════════════
# INSTALACIÓN NATIVE — limpia (descarga + patchelf)
# ════════════════════════════════════════════════════════════
_install_native_clean() {
  titulo "Instalando Claude Native (glibc-runner)"

  local VERSION="$CLAUDE_VERSION_NATIVE"
  local DL="https://downloads.claude.ai/claude-code-releases/${VERSION}"

  # Preguntar si usar versión fija o latest
  local OPT_VER
  if $SILENT_MODE; then
    info "Modo silencioso — usando versión estable v${CLAUDE_VERSION_NATIVE}"
    OPT_VER="1"
  else
    echo -e "  ${CYAN}Versión a instalar:${NC}"
    echo -e "  [1] v${CLAUDE_VERSION_NATIVE}  ${DIM}(estable, probada en POCO F5)${NC}"
    echo -e "  [2] latest          ${DIM}(más reciente, puede ser inestable)${NC}"
    echo ""; echo -n "  Opción [1/2]: "
    read -r OPT_VER < /dev/tty
  fi
  if [ "$OPT_VER" = "2" ]; then
    info "Consultando versión latest..."
    VERSION=$(curl -fsSL \
      "https://downloads.claude.ai/claude-code-releases/latest/manifest.json" \
      2>/dev/null | grep -o '"version":"[^"]*"' | grep -o '[0-9][^"]*' | head -1)
    [ -z "$VERSION" ] && {
      warn "No se pudo obtener latest — usando v${CLAUDE_VERSION_NATIVE}"
      VERSION="$CLAUDE_VERSION_NATIVE"
    }
    DL="https://downloads.claude.ai/claude-code-releases/${VERSION}"
    info "Versión latest: v${VERSION}"
  fi

  mkdir -p "$(dirname "$NATIVE_BINARY")" "$(dirname "$NATIVE_WRAPPER")"

  info "Descargando binario v${VERSION}..."
  curl -fL --progress-bar "${DL}/linux-arm64/claude" -o "$NATIVE_BINARY" || \
    error "Descarga fallida — verifica tu conexión"
  [ -s "$NATIVE_BINARY" ] || error "Binario descargado vacío"

  # Verificar checksum
  info "Verificando SHA256..."
  local expected actual
  expected=$(curl -fsSL "${DL}/manifest.json" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d['platforms']['linux-arm64']['checksum'])" \
    2>/dev/null)
  if [ -n "$expected" ]; then
    actual=$(sha256sum "$NATIVE_BINARY" | cut -d' ' -f1)
    if [ "$actual" = "$expected" ]; then
      log "SHA256 verificado ✓"
    else
      rm -f "$NATIVE_BINARY"
      error "SHA256 no coincide — binario corrupto\n  Esperado: ${expected:0:20}...\n  Actual:   ${actual:0:20}..."
    fi
  else
    warn "No se pudo verificar checksum — continuando"
  fi

  # Patchear intérprete ELF
  chmod +x "$NATIVE_BINARY"
  info "Parcheando intérprete ELF..."
  # Usar ruta absoluta: patchelf-glibc instala en $TERMUX_PREFIX/glibc/bin/patchelf
  # NO en $PREFIX/bin — no está en PATH por defecto
  # LD_PRELOAD= evita que termux-exec crashee patchelf (libc.so incompatible con glibc)
  LD_PRELOAD= "$PATCHELF" --set-interpreter "$GLIBC_LD" "$NATIVE_BINARY" || \
    error "patchelf falló — ruta: $PATCHELF"
  log "Intérprete ELF parcheado ✓"

  _create_native_wrapper "$VERSION"
}

_create_native_wrapper() {
  local version="$1"
  # Wrapper: unset LD_PRELOAD para que el binario glibc no crashee
  # con el preloader de termux-exec (que busca libc.so incompatible)
  cat > "$NATIVE_WRAPPER" << WRAPPER
#!/data/data/com.termux/files/usr/bin/bash
# termux-ai-stack · Claude native wrapper
# unset LD_PRELOAD: evita crash de termux-exec con glibc
unset LD_PRELOAD
exec "$NATIVE_BINARY" "\$@"
WRAPPER
  chmod +x "$NATIVE_WRAPPER"
  log "Wrapper creado: $NATIVE_WRAPPER"

  _create_settings_native
  _update_registry "$version" "native"
  mark_done "claude_install"

  # Verificar
  local ver_check
  ver_check=$("$NATIVE_WRAPPER" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$ver_check" ] \
    && log "Claude native v${ver_check} funcionando ✓" \
    || warn "Wrapper creado pero --version no respondió — verifica con: claude --version"
}

# ════════════════════════════════════════════════════════════
# ACTUALIZACIÓN NATIVE — solo binario + patchelf + registry
# No toca: glibc, wrapper, settings, aliases
# ════════════════════════════════════════════════════════════
_update_native() {
  titulo "Actualización — Claude Code native"

  local _VER_ANTES
  _VER_ANTES=$(_detect_version "native")
  [ -z "$_VER_ANTES" ] && \
    _VER_ANTES=$(grep "^claude_code\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  echo -e "  Versión actual: ${CYAN}${_VER_ANTES:-desconocida}${NC}"; echo ""

  # ── Elegir versión ────────────────────────────────────────
  local _OPT_VER
  if $SILENT_MODE; then
    info "Modo silencioso — usando versión estable v${CLAUDE_VERSION_NATIVE}"
    _OPT_VER="1"
  else
    echo -e "  ${BOLD}Versión a instalar:${NC}"
    echo -e "  [1] v${CLAUDE_VERSION_NATIVE}  ${DIM}(estable, probada en POCO F5)${NC}"
    echo -e "  [2] latest          ${DIM}(más reciente, puede ser inestable)${NC}"
    echo -e "  [q] Cancelar"
    echo ""; echo -n "  Opción [1]: "
    read -r _OPT_VER < /dev/tty
  fi

  local _VERSION="$CLAUDE_VERSION_NATIVE"
  case "${_OPT_VER:-1}" in
    1) _VERSION="$CLAUDE_VERSION_NATIVE" ;;
    2)
      info "Consultando versión latest..."
      _VERSION=$(curl -fsSL \
        "https://downloads.claude.ai/claude-code-releases/latest/manifest.json" \
        2>/dev/null | grep -o '"version":"[^"]*"' | grep -o '[0-9][^"]*' | head -1)
      [ -z "$_VERSION" ] && {
        warn "No se pudo obtener latest — usando v${CLAUDE_VERSION_NATIVE}"
        _VERSION="$CLAUDE_VERSION_NATIVE"
      }
      info "Versión latest: v${_VERSION}" ;;
    q|Q|"") echo "Cancelado."; return 0 ;;
    *) _VERSION="$CLAUDE_VERSION_NATIVE" ;;
  esac

  # Si la versión es la misma, preguntar antes de continuar
  if [ "$_VERSION" = "$_VER_ANTES" ]; then
    echo -e "  ${YELLOW}[AVISO]${NC} Ya tienes v${_VERSION} instalada."
    if $SILENT_MODE; then
      info "Modo silencioso — misma versión ya instalada, no se reinstala"
      return 0
    fi
    echo -n "  ¿Reinstalar el binario de todas formas? (s/n): "
    read -r _FORCE < /dev/tty
    [ "$_FORCE" != "s" ] && [ "$_FORCE" != "S" ] && { echo "Cancelado."; return 0; }
  fi

  local _DL="https://downloads.claude.ai/claude-code-releases/${_VERSION}"

  # ── Descargar binario ─────────────────────────────────────
  info "Descargando binario v${_VERSION}..."
  mkdir -p "$(dirname "$NATIVE_BINARY")"
  curl -fL --progress-bar "${_DL}/linux-arm64/claude" -o "$NATIVE_BINARY" || \
    error "Descarga fallida — verifica tu conexión"
  [ -s "$NATIVE_BINARY" ] || error "Binario descargado vacío"

  # ── Verificar checksum ────────────────────────────────────
  info "Verificando SHA256..."
  local expected actual
  expected=$(curl -fsSL "${_DL}/manifest.json" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); \
    print(d['platforms']['linux-arm64']['checksum'])" 2>/dev/null)
  if [ -n "$expected" ]; then
    actual=$(sha256sum "$NATIVE_BINARY" | cut -d' ' -f1)
    if [ "$actual" = "$expected" ]; then
      log "SHA256 verificado ✓"
    else
      rm -f "$NATIVE_BINARY"
      error "SHA256 no coincide — binario corrupto\n  Esperado: ${expected:0:20}...\n  Actual:   ${actual:0:20}..."
    fi
  else
    warn "No se pudo verificar checksum — continuando"
  fi

  # ── Patchear ELF ──────────────────────────────────────────
  chmod +x "$NATIVE_BINARY"
  info "Parcheando intérprete ELF..."
  [ -f "$PATCHELF" ] || error "patchelf no encontrado: $PATCHELF — ejecuta: pkg install patchelf-glibc"
  [ -f "$GLIBC_LD" ] || error "ld.so no encontrado: $GLIBC_LD — ejecuta: pkg install glibc-runner"
  LD_PRELOAD= "$PATCHELF" --set-interpreter "$GLIBC_LD" "$NATIVE_BINARY" || \
    error "patchelf falló"
  log "Intérprete ELF parcheado ✓"

  # ── Verificar + registry ──────────────────────────────────
  local _VER_NUEVA
  # Wrapper puede no existir si es la primera instalación native desde legacy
  # → recrear wrapper antes de verificar versión
  if [ ! -x "$NATIVE_WRAPPER" ]; then
    mkdir -p "$(dirname "$NATIVE_WRAPPER")"
    cat > "$NATIVE_WRAPPER" << _WRAP
#!/data/data/com.termux/files/usr/bin/bash
unset LD_PRELOAD
exec "$NATIVE_BINARY" "\$@"
_WRAP
    chmod +x "$NATIVE_WRAPPER"
    log "Wrapper recreado: $NATIVE_WRAPPER"
  fi
  _VER_NUEVA=$("$NATIVE_WRAPPER" --version 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$_VER_NUEVA" ] && _VER_NUEVA="$_VERSION"

  _update_registry "$_VER_NUEVA" "native"

  echo ""
  echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║  [OK] Claude Code native actualizado   ║"
  echo    "  ╠══════════════════════════════════════════╣"
  printf  "  ║  ${NC}Antes:  %-34s${GREEN}${BOLD}║\n" "${_VER_ANTES:-?}"
  printf  "  ║  ${NC}Ahora:  %-34s${GREEN}${BOLD}║\n" "${_VER_NUEVA:-?}"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
}

# ════════════════════════════════════════════════════════════
# INSTALACIÓN NATIVE — desde GitHub Releases (part2b)
# ════════════════════════════════════════════════════════════
_install_native_github() {
  titulo "Restaurando Claude Native desde GitHub Releases"

  if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
    info "Descargando restore.sh..."
    curl -fsSL "https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/restore.sh" \
      -o "$HOME/restore.sh" && chmod +x "$HOME/restore.sh" || \
      error "No se pudo obtener restore.sh"
  fi

  bash "$HOME/restore.sh" --module claude-native --source github || \
    error "Restore de Claude native falló"

  # El restore.sh ya crea el wrapper y actualiza el registry
  # Solo verificar el resultado
  local ver_check
  ver_check=$("$NATIVE_WRAPPER" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$ver_check" ] \
    && log "Claude native v${ver_check} restaurado ✓" \
    || warn "Restaurado pero --version no respondió — verifica con: claude --version"
}

# ════════════════════════════════════════════════════════════
# INSTALACIÓN LEGACY — limpia (npm)
# ════════════════════════════════════════════════════════════
_find_legacy_cli() {
  # 1. Desde wrapper existente
  local wrapper="$LEGACY_WRAPPER"
  if [ -f "$wrapper" ]; then
    local p; p=$(grep "node " "$wrapper" 2>/dev/null | grep "cli\.js" | \
      grep -oE '/[^ "]+cli\.js' | head -1)
    [ -n "$p" ] && [ -f "$p" ] && { echo "$p"; return; }
  fi
  # 2. Rutas conocidas
  local npm_root; npm_root=$(npm root -g 2>/dev/null)
  local known=(
    "$npm_root/@anthropic-ai/claude-code/cli.js"
    "$TERMUX_PREFIX/lib/node_modules/@anthropic-ai/claude-code/cli.js"
    "$HOME/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js"
  )
  for p in "${known[@]}"; do
    [ -f "$p" ] && { echo "$p"; return; }
  done
  echo "${npm_root}/@anthropic-ai/claude-code/cli.js"
}

_validate_legacy_cli() {
  local p="$1"
  [ -f "$p" ] && [ -s "$p" ] || return 1
  node "$p" --version 2>&1 | grep -qv "SyntaxError\|not found\|No such" || return 1
  local first; first=$(head -1 "$p" 2>/dev/null)
  echo "$first" | grep -q "^#!/.*bash" && return 1
  return 0
}

_install_legacy_clean() {
  titulo "Instalando Claude Legacy v${CLAUDE_VERSION_LEGACY} (npm)"

  local NPM_ROOT; NPM_ROOT=$(npm root -g 2>/dev/null)
  local CLAUDE_DIR="$NPM_ROOT/@anthropic-ai/claude-code"
  local CLAUDE_OK=false
  local CLI_PATH

  info "Limpiando instalación anterior..."
  npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
  npm cache clean --force 2>/dev/null || true
  rm -rf "$CLAUDE_DIR" 2>/dev/null || true

  # ── Estrategia 1: npm directo ──────────────────────────────
  info "npm install @${CLAUDE_VERSION_LEGACY} (sin --ignore-scripts)..."
  npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION_LEGACY} --save-exact \
    2>&1 | tail -5
  CLI_PATH=$(_find_legacy_cli)
  if _validate_legacy_cli "$CLI_PATH"; then
    CLAUDE_OK=true; log "Estrategia 1 exitosa ✓"
  fi

  # ── Estrategia 2: npm --ignore-scripts ─────────────────────
  if [ "$CLAUDE_OK" = "false" ]; then
    warn "Estrategia 2: npm --ignore-scripts..."
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
    npm cache clean --force 2>/dev/null || true
    npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION_LEGACY} \
      --ignore-scripts --save-exact 2>&1 | tail -5
    CLI_PATH=$(_find_legacy_cli)
    _validate_legacy_cli "$CLI_PATH" && { CLAUDE_OK=true; log "Estrategia 2 exitosa ✓"; }
  fi

  # ── Estrategia 3: tarball directo npmjs.com ─────────────────
  if [ "$CLAUDE_OK" = "false" ]; then
    warn "Estrategia 3: tarball desde registry.npmjs.org..."
    local URL="https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${CLAUDE_VERSION_LEGACY}.tgz"
    local TMP_TGZ="$HOME/claude_npm_direct.tgz"
    local TMP_EXT="$HOME/claude_extract_direct"
    curl -fL --progress-bar "$URL" -o "$TMP_TGZ" 2>/dev/null
    if [ -s "$TMP_TGZ" ]; then
      mkdir -p "$TMP_EXT"
      tar -xzf "$TMP_TGZ" -C "$TMP_EXT" 2>/dev/null
      if [ -f "$TMP_EXT/package/cli.js" ]; then
        mkdir -p "$CLAUDE_DIR"
        cp -r "$TMP_EXT/package/." "$CLAUDE_DIR/"
        CLI_PATH=$(_find_legacy_cli)
        _validate_legacy_cli "$CLI_PATH" && { CLAUDE_OK=true; log "Estrategia 3 exitosa ✓"; }
      fi
    fi
    rm -rf "$TMP_EXT" "$TMP_TGZ" 2>/dev/null || true
  fi

  # ── Estrategia 4: reparar cli.js desde GitHub Releases ──────
  if [ "$CLAUDE_OK" = "false" ] && [ -d "$CLAUDE_DIR" ]; then
    warn "Estrategia 4: reparar cli.js desde GitHub Releases..."
    local CLI_URL
    CLI_URL=$(curl -fsSL "$RELEASE_API" 2>/dev/null | \
      grep -o '"browser_download_url": *"[^"]*part2-claude[^"]*"' | \
      grep -o 'https://[^"]*' | head -1)
    if [ -n "$CLI_URL" ]; then
      local TMP_TAR="$HOME/claude_gh_release.tar.xz"
      local TMP_EXT2="$HOME/claude_extract_gh"
      curl -fL --progress-bar "$CLI_URL" -o "$TMP_TAR" 2>/dev/null
      if [ -s "$TMP_TAR" ]; then
        mkdir -p "$TMP_EXT2"
        tar -xJf "$TMP_TAR" -C "$TMP_EXT2" 2>/dev/null
        local CLI_GH="$TMP_EXT2/npm_modules/@anthropic-ai/claude-code/cli.js"
        if [ -f "$CLI_GH" ]; then
          cp "$CLI_GH" "$CLAUDE_DIR/cli.js" && chmod +x "$CLAUDE_DIR/cli.js"
          CLI_PATH=$(_find_legacy_cli)
          _validate_legacy_cli "$CLI_PATH" && { CLAUDE_OK=true; log "Estrategia 4 exitosa ✓"; }
        fi
      fi
      rm -rf "$TMP_EXT2" "$TMP_TAR" 2>/dev/null || true
    fi
  fi

  if [ "$CLAUDE_OK" = "false" ]; then
    error "Ninguna estrategia funcionó.\n  Prueba manual: npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION_LEGACY}"
  fi

  _create_legacy_wrapper "$CLI_PATH"
}

_create_legacy_wrapper() {
  local cli_path="$1"
  local version
  version=$(node "$cli_path" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$version" ] && version="$CLAUDE_VERSION_LEGACY"

  cat > "$LEGACY_WRAPPER" << WRAPPER
#!/data/data/com.termux/files/usr/bin/bash
# termux-ai-stack · Claude legacy wrapper (ARM64 Bionic)
export DISABLE_AUTOUPDATER=1
export DISABLE_UPDATES=1
exec node "${cli_path}" "\$@"
WRAPPER
  chmod +x "$LEGACY_WRAPPER"
  log "Wrapper creado: $LEGACY_WRAPPER"

  _create_settings_legacy "$cli_path"
  _update_registry "$version" "legacy"
  mark_done "claude_install"
  log "Claude legacy v${version} instalado ✓"
}

# ════════════════════════════════════════════════════════════
# INSTALACIÓN LEGACY — desde GitHub Releases (part2)
# ════════════════════════════════════════════════════════════
_install_legacy_github() {
  titulo "Restaurando Claude Legacy desde GitHub Releases"

  if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
    info "Descargando restore.sh..."
    curl -fsSL "https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/restore.sh" \
      -o "$HOME/restore.sh" && chmod +x "$HOME/restore.sh" || \
      error "No se pudo obtener restore.sh"
  fi

  bash "$HOME/restore.sh" --module claude --source github || \
    error "Restore de Claude legacy falló"

  local cli_path; cli_path=$(_find_legacy_cli)
  _validate_legacy_cli "$cli_path" || error "cli.js del backup no es válido"
  _create_legacy_wrapper "$cli_path"
}

# ════════════════════════════════════════════════════════════
# SETTINGS.JSON
# ════════════════════════════════════════════════════════════
_create_settings_native() {
  mkdir -p "$HOME/.claude"
  # LD_PRELOAD en env: Claude lo hereda al lanzar subprocesos internos
  # sin esto, ugrep y otros binarios internos crashean con termux-exec
  cat > "$HOME/.claude/settings.json" << 'SETTINGS'
{
  "autoUpdates": false,
  "env": {
    "LD_PRELOAD": "/data/data/com.termux/files/usr/lib/libtermux-exec-ld-preload.so"
  }
}
SETTINGS
  log "~/.claude/settings.json configurado (native)"
}

_create_settings_legacy() {
  local cli_path="$1"
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" << 'SETTINGS'
{
  "autoUpdates": false,
  "env": {
    "DISABLE_AUTOUPDATER": "1",
    "DISABLE_UPDATES": "1"
  }
}
SETTINGS
  log "~/.claude/settings.json configurado (legacy)"

  # Aliases en .bashrc
  local BASHRC="$HOME/.bashrc"
  grep -v "alias claude=\|alias claude-update=\|alias claude-check=" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
  cat >> "$BASHRC" << ALIASES

# ════════════════════════════════
#  Claude Code legacy · aliases
# ════════════════════════════════
alias claude='DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 node ${cli_path}'
alias claude-check='node ${cli_path} --version 2>/dev/null && echo "OK" || echo "ERROR"'
ALIASES
  log "Aliases legacy agregados a ~/.bashrc"
}

# ════════════════════════════════════════════════════════════
# RESUMEN FINAL
# ════════════════════════════════════════════════════════════
_show_result() {
  clear; echo ""
  local method="$1" version="$2"
  echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║  ⬡ Claude Code instalado ✓              ║"
  echo    "  ╠══════════════════════════════════════════╣"
  printf  "  ║  ${NC}Versión: %-33s${GREEN}${BOLD}║\n" "v${version}"
  printf  "  ║  ${NC}Método:  %-33s${GREEN}${BOLD}║\n" "${method}"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}claude                → agente interactivo${GREEN}${BOLD}║"
  echo -e "  ║  ${NC}claude --version      → ver versión     ${GREEN}${BOLD}║"
  echo -e "  ║  ${NC}claude -p \"texto\"      → modo headless  ${GREEN}${BOLD}║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  [ "$method" = "legacy" ] && \
    echo -e "  ${CYAN}→ Ejecuta: source ~/.bashrc  para activar aliases${NC}\n"
  rm -f "$CHECKPOINT"
}

# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════
INSTALLED_METHOD=""
INSTALLED_VER=""
CHOSEN_METHOD=""
CHOSEN_SOURCE=""

_show_header
if [ "$CLAUDE_METHOD" = "native" ] || [ "$CLAUDE_METHOD" = "legacy" ]; then
  CHOSEN_METHOD="$CLAUDE_METHOD"
  info "Método preseleccionado: $CHOSEN_METHOD"
else
  _menu_metodo
fi
_check_conflict

# Si ya está instalado el mismo método: ofrecer update vs reinstalación
if [ "$INSTALLED_METHOD" = "$CHOSEN_METHOD" ] && \
   [ "$INSTALLED_METHOD" != "none" ] && [ "$INSTALLED_METHOD" != "broken" ]; then
  echo ""
  echo -e "  ${GREEN}Claude ${CHOSEN_METHOD} v${INSTALLED_VER} ya instalado.${NC}"
  echo ""

  if [ "$CHOSEN_METHOD" = "native" ]; then
    $SILENT_MODE && error "Claude ${CHOSEN_METHOD} ya instalado — no se puede decidir actualizar/reinstalar en modo silencioso, ejecuta sin --silent para decidir manualmente"
    # Native: ofrecer update rápido o reinstalación completa
    echo -e "  ${BOLD}¿Qué deseas hacer?${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} Actualizar          ${DIM}(solo nuevo binario + patchelf)${NC}"
    echo -e "  [2] Reinstalar  ${DIM}(descarga completa desde cero)${NC}"
    echo -e "  [q] Cancelar"
    echo ""; echo -n "  Opción: "
    read -r _OPT_ACTION < /dev/tty
    case "$_OPT_ACTION" in
      1)
        _update_native; exit 0 ;;
      2)
        rm -f "$CHECKPOINT"
        CHOSEN_SOURCE="clean"
        _ensure_termux
        _ensure_glibc
        _install_native_clean
        FINAL_VER=$(_detect_version "native")
        [ -z "$FINAL_VER" ] && FINAL_VER="instalado"
        _show_result "native" "$FINAL_VER"
        exit 0 ;;
      q|Q|"") info "Nada que hacer. Saliendo."; exit 0 ;;
      *) info "Nada que hacer. Saliendo."; exit 0 ;;
    esac

  else
    # Legacy: no hay update — versión fijada en 2.1.111
    $SILENT_MODE && error "Claude legacy ya instalado — no se puede decidir reinstalar en modo silencioso, ejecuta sin --silent para decidir manualmente"
    echo -e "  ${YELLOW}[INFO]${NC} Claude legacy está fijado en v${CLAUDE_VERSION_LEGACY}"
    echo -e "  ${DIM}No se actualiza — esta versión garantiza compatibilidad con Bionic libc.${NC}"
    echo ""
    echo -n "  ¿Reinstalar v${CLAUDE_VERSION_LEGACY} desde cero? (s/n): "
    read -r CONFIRM_REINSTALL < /dev/tty
    [ "$CONFIRM_REINSTALL" != "s" ] && [ "$CONFIRM_REINSTALL" != "S" ] && {
      info "Nada que hacer. Saliendo."; exit 0
    }
    rm -f "$CHECKPOINT"
  fi
fi

_menu_fuente

# Preparar dependencias según método
case "$CHOSEN_METHOD" in
  native)
    _ensure_termux
    _ensure_glibc ;;
  legacy)
    _ensure_termux
    _ensure_nodejs ;;
esac

# Instalar
case "${CHOSEN_METHOD}_${CHOSEN_SOURCE}" in
  native_clean)  _install_native_clean  ;;
  native_github) _install_native_github ;;
  legacy_clean)  _install_legacy_clean  ;;
  legacy_github) _install_legacy_github ;;
esac

# Resultado
FINAL_VER=$(_detect_version "$CHOSEN_METHOD")
[ -z "$FINAL_VER" ] && FINAL_VER="instalado"
_show_result "$CHOSEN_METHOD" "$FINAL_VER"

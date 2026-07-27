#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_openclaw.sh  v4.1.0
#  Instala OpenClaw en Termux ARM64 (sin root)
#
#  MODO ÚNICO: nativo — glibc + npm (Node v22-24, ver PASO 0)
#
#  QUÉ HACE:
#    ✅ PASO 0 — instala glibc-runner + Node v22-24 si no existen
#    ✅ Instala openclaw vía npm --ignore-scripts
#    ✅ koffi stub, clipboard stub, patch /tmp, patch /bin/npm
#    ✅ glibc-compat.js (os.networkInterfaces + homedir)
#    ✅ Wrapper node dist/entry.js
#    ✅ Aliases ocr/oclog/ockill en .bashrc
#    ⛔ NO lanza el gateway (2026-07-26) — 100% manual desde el menú,
#       ver PASO 9. Auto-lanzarlo durante la instalación exponía al
#       proceso (backgroundeado vía menu.sh) al OOM/Doze killer de
#       Android (SIGKILL/137), sin relación con si el paquete quedó bien
#
#  MODO PROOT: archivado en termux-ai-stack-dev/proot-legacy/ (2026-07-27)
#  — no se mantiene activamente, sin vía de instalación desde ningún menú,
#  disponible solo por si algún día hace falta correrlo a mano. Ver
#  proot-legacy/README.md y docs/OPENCLAW.md
#
#  REGLAS TÉCNICAS (NO VIOLAR):
#    - NUNCA /tmp/ → siempre $HOME/tmp  (noexec Android 15)
#    - NUNCA read sin < /dev/tty         (Termux pipe mode)
#    - NUNCA import requests             (usar urllib builtin)
#    - NUNCA datetime('now') en SQLite   (usar datetime.now())
#
#  VERSIÓN: 4.0.0 | Julio 2026
# ============================================================

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/.local/bin:$HOME/.openclaw-android/bin:$HOME/.npm-global/bin:$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Constantes glibc ──────────────────────────────────────────
GLIBC_LD="$TERMUX_PREFIX/glibc/lib/ld-linux-aarch64.so.1"
GLIBC_NODE_DIR="$HOME/.openclaw-android/node"
GLIBC_BIN_DIR="$HOME/.openclaw-android/bin"
NODE_VERSION_TARGET="24.15.0"

# ── Constantes generales ──────────────────────────────────────
NPM_GLOBAL="$HOME/.npm-global"
NPM_BIN="$NPM_GLOBAL/bin"
LOG_DIR="$HOME/openclaw-logs"
TMP_DIR="$HOME/tmp"
COMPAT_JS="$HOME/.openclaw/glibc-compat.js"
REGISTRY="$HOME/.android_server_registry"
PORT=18789
BASHRC="$HOME/.bashrc"

# ── Sanitizar NODE_OPTIONS heredado (bug confirmado en dispositivo real,
# 2026-07-26) ──────────────────────────────────────────────────
# PASO 3 exporta "--require $COMPAT_JS" a NODE_OPTIONS y lo persiste en
# ~/.bashrc. Si una sesión interactiva ya tiene ese .bashrc sourceado
# (Termux abierto antes de esta corrida) y $COMPAT_JS ya no existe en
# disco (reinstalación, checkpoint autoreparado, ~/.openclaw/ limpiado),
# CUALQUIER invocación de node/npm en este script — incluyendo el propio
# "npm install -g openclaw@latest" de PASO 2 — muere de inmediato con
# "MODULE_NOT_FOUND" en internal/preload, antes de instalar nada. El
# wrapper de node en $GLIBC_BIN_DIR ya tiene esta misma protección
# (verifica el archivo antes de agregarlo), pero si _ensure_glibc_node()
# usa un `node` del sistema en vez del wrapper (ver más abajo), esa
# protección nunca se ejecuta. Limpiar acá cubre ambos casos.
if [ -n "${NODE_OPTIONS:-}" ] && [ ! -f "$COMPAT_JS" ]; then
  case "$NODE_OPTIONS" in
    *"$COMPAT_JS"*)
      NODE_OPTIONS=$(echo "$NODE_OPTIONS" | sed -E "s#(--require|-r) *${COMPAT_JS//\//\\/}##")
      export NODE_OPTIONS
      ;;
  esac
fi

# ── Modo silencioso (invocado desde menu.sh, confirmación ya hecha ahí) ──
SILENT_MODE=false
for _arg in "$@"; do [ "$_arg" = "--silent" ] && SILENT_MODE=true; done

# ── Colores ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "${CYAN}[INFO]${NC}  $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }

# ── Checkpoint ─────────────────────────────────────────────────
CHECKPOINT="$HOME/.install_openclaw_native_checkpoint"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Registry ─────────────────────────────────────────────────
update_registry() {
  local version="$1" location="$2"
  local date_now
  date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^openclaw\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
openclaw.installed=true
openclaw.version=$version
openclaw.install_date=$date_now
openclaw.location=$location
openclaw.port=$PORT
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado (location=$location)"
}

# ============================================================
#  ACTUALIZACIÓN NATIVA — npm update + reaplicar todos los parches
# ============================================================
_update_native_openclaw() {
  titulo "ACTUALIZACIÓN — OpenClaw nativo"

  local _VER_ANTES
  _VER_ANTES=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  [ -z "$_VER_ANTES" ] && \
    _VER_ANTES=$(command -v openclaw &>/dev/null && openclaw --version 2>/dev/null | \
      grep -oE '[0-9]+\.[0-9.]+' | head -1)
  echo -e "  Versión actual: ${CYAN}${_VER_ANTES:-desconocida}${NC}"; echo ""

  export PATH="$GLIBC_BIN_DIR:$NPM_BIN:$PATH"
  export TMPDIR="$TMP_DIR"
  mkdir -p "$LOG_DIR" "$TMP_DIR" "$HOME/.openclaw"

  info "Actualizando openclaw vía npm (--ignore-scripts)..."
  env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true \
    TMPDIR="$TMP_DIR" \
    npm install -g openclaw@latest --ignore-scripts 2>&1 | tail -10 || \
    error "npm install openclaw@latest falló — verifica conexión y espacio en disco"

  local _OC_BASE
  _OC_BASE=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE "/.+/openclaw" | head -1)
  [ -z "$_OC_BASE" ] && _OC_BASE="$NPM_GLOBAL/lib/node_modules/openclaw"
  [ ! -d "$_OC_BASE" ] && { error "Directorio openclaw no encontrado tras update: $_OC_BASE"; }
  log "Paquete actualizado en: $_OC_BASE"

  # ── Reaplicar koffi stub ──────────────────────────────────
  titulo "Re-parche 1/4 — koffi stub"
  local _KOFFI_DIR="$_OC_BASE/node_modules/koffi"
  if [ -d "$_KOFFI_DIR" ]; then
    cat > "$_KOFFI_DIR/index.js" << 'EOF'
// koffi stub — android-arm64 (termux-ai-stack)
const handler = {
  get(_, prop) {
    if (prop === '__esModule') return false;
    if (prop === 'default') return proxy;
    if (prop === 'then') return undefined;
    return function () { throw new Error('koffi stub: no disponible en android-arm64'); };
  }
};
const proxy = new Proxy({}, handler);
module.exports = proxy;
module.exports.default = proxy;
EOF
    log "koffi stub reaplicado"
  else
    info "koffi no encontrado en nueva versión — omitiendo"
  fi

  # ── Reaplicar clipboard stub ──────────────────────────────
  titulo "Re-parche 2/4 — clipboard stub"
  local _CLIP="$_OC_BASE/node_modules/@mariozechner/clipboard/index.js"
  if [ -f "$_CLIP" ]; then
    node -e "
const fs = require('fs');
const mock = \`module.exports = {
  availableFormats:()=>[],getText:()=>'',setText:()=>false,hasText:()=>false,
  getImageBinary:()=>null,getImageBase64:()=>null,setImageBinary:()=>false,
  setImageBase64:()=>false,hasImage:()=>false,getHtml:()=>'',setHtml:()=>false,
  hasHtml:()=>false,getRtf:()=>'',setRtf:()=>false,hasRtf:()=>false,
  clear:()=>{},watch:()=>({stop:()=>{}}),callThreadsafeFunction:()=>{}
};\`;
fs.writeFileSync('$_CLIP', mock);
" && log "clipboard stub reaplicado" || warn "clipboard stub falló — no crítico"
  else
    info "clipboard no encontrado en nueva versión — omitiendo"
  fi

  # ── Reaplicar patches /tmp y /bin/npm ─────────────────────
  titulo "Re-parche 3/4 — /tmp y /bin/npm"
  local _DIST="$_OC_BASE/dist"
  if [ -d "$_DIST" ]; then
    local _FILES_TMP
    _FILES_TMP=$(grep -rl "/tmp/openclaw" "$_DIST" 2>/dev/null || true)
    if [ -n "$_FILES_TMP" ]; then
      while IFS= read -r _f; do
        node -e "
const fs=require('fs');
const c=fs.readFileSync('$_f','utf8');
fs.writeFileSync('$_f',c.replace(/\\/tmp\\/openclaw/g,process.env.HOME+'/openclaw-logs'));
"
        info "  /tmp parcheado: $(basename "$_f")"
      done <<< "$_FILES_TMP"
      log "/tmp/openclaw → \$HOME/openclaw-logs"
    else
      log "Sin referencias /tmp/openclaw — OK"
    fi

    local _REAL_NPM
    _REAL_NPM=$(command -v npm 2>/dev/null || true)
    if [ -n "$_REAL_NPM" ] && [ "$_REAL_NPM" != "/bin/npm" ]; then
      local _FILES_NPM
      _FILES_NPM=$(grep -rl '"/bin/npm"\|'"'"'/bin/npm'"'" "$_DIST" 2>/dev/null || true)
      if [ -n "$_FILES_NPM" ]; then
        while IFS= read -r _f; do
          sed -i "s|/bin/npm|${_REAL_NPM}|g" "$_f"
        done <<< "$_FILES_NPM"
        log "/bin/npm → $_REAL_NPM"
      fi
    fi
  else
    warn "dist/ no encontrado — saltando patches /tmp y /bin/npm"
  fi

  # ── Recrear wrapper openclaw ──────────────────────────────
  titulo "Re-parche 4/4 — wrapper openclaw"
  local _ENTRY="$_OC_BASE/dist/entry.js"
  if [ -f "$_ENTRY" ]; then
    cat > "$NPM_BIN/openclaw" << WRAPPER
#!/data/data/com.termux/files/usr/bin/sh
# Sanea NODE_OPTIONS heredado antes de exec — si trae --require/-r a un
# glibc-compat.js que ya no existe, node muere con MODULE_NOT_FOUND en
# internal/preload antes de correr nada. Por acá pasan gateway, onboard
# y tui — un solo punto de saneo cubre los tres (bug confirmado 2026-07-26,
# el saneo anterior solo cubría la instalación, no el uso posterior)
_OC_COMPAT="\$HOME/.openclaw/glibc-compat.js"
if [ -n "\$NODE_OPTIONS" ] && [ ! -f "\$_OC_COMPAT" ]; then
  case "\$NODE_OPTIONS" in
    *"\$_OC_COMPAT"*)
      NODE_OPTIONS=\$(echo "\$NODE_OPTIONS" | sed "s#--require \$_OC_COMPAT##;s#-r \$_OC_COMPAT##")
      export NODE_OPTIONS
      ;;
  esac
fi
exec node "$_ENTRY" "\$@"
WRAPPER
    chmod +x "$NPM_BIN/openclaw"
    log "Wrapper recreado: $NPM_BIN/openclaw → node $_ENTRY"
  else
    warn "entry.js no encontrado — wrapper no recreado"
    local _OC_BIN_FILE="$NPM_BIN/openclaw"
    if [ -f "$_OC_BIN_FILE" ] && head -n1 "$_OC_BIN_FILE" | grep -q "^#!/usr/bin/env"; then
      local _TENV="$TERMUX_PREFIX/bin/env"
      [ -x "$_TENV" ] && {
        sed -i "1s|#!/usr/bin/env|#!${_TENV}|" "$_OC_BIN_FILE"
        log "Shebang parcheado → $_TENV"
      }
    fi
  fi

  # ── Versión nueva + registry ──────────────────────────────
  local _VER_NUEVA
  _VER_NUEVA=$(openclaw --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9.]+' | head -1)
  [ -z "$_VER_NUEVA" ] && _VER_NUEVA="unknown"
  update_registry "$_VER_NUEVA" "nativo_termux"

  echo ""
  echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║  [OK] OpenClaw nativo actualizado      ║"
  echo    "  ╠══════════════════════════════════════════╣"
  printf  "  ║  ${NC}Antes:  %-33s${GREEN}${BOLD}║\n" "${_VER_ANTES:-?}"
  printf  "  ║  ${NC}Ahora:  %-33s${GREEN}${BOLD}║\n" "${_VER_NUEVA:-?}"
  echo -e "  ║  ${NC}Parches reaplicados: 4/4           ${GREEN}${BOLD} ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${CYAN}→ Ejecuta: ocr  para reiniciar el gateway${NC}"
  echo ""
}

# ============================================================
#  CABECERA
# ============================================================
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · OpenClaw Installer v4  ║
  ║   Nativo · glibc + npm · ARM64             ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Detectar instalación nativa previa ───────────────────────
_NATIVE_INSTALLED=false

if [ -f "$NPM_BIN/openclaw" ] || command -v openclaw &>/dev/null 2>&1; then
  _LOC=$(grep "^openclaw\.location=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  [ "$_LOC" = "nativo_termux" ] && _NATIVE_INSTALLED=true
fi

echo -e "  Estado actual:"
$_NATIVE_INSTALLED \
  && echo -e "  ${GREEN}●${NC} Nativo  — instalado" \
  || echo -e "  ${YELLOW}○${NC} Nativo  — no instalado"
echo ""

# ── Dispatch rápido desde menú externo (OCL_MODE=update) ─────
if [ "${OCL_MODE:-}" = "update" ]; then
  if $_NATIVE_INSTALLED; then
    _update_native_openclaw; exit 0
  else
    echo -e "  ${YELLOW}[AVISO]${NC} OpenClaw nativo no detectado — instala primero"
    exit 1
  fi
fi

# ── Check reinstalar / actualizar nativo ─────────────────────
if $_NATIVE_INSTALLED; then
  _CL_VER=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  echo -e "  ${GREEN}✓ OpenClaw nativo ya instalado${NC} (v${_CL_VER:-?})"
  echo ""
  echo -e "  ${BOLD}¿Qué deseas hacer?${NC}"; echo ""
  echo -e "  [1] Actualizar   ${DIM}(npm update + reaplicar todos los parches)${NC}"
  echo -e "  [2] Reinstalar   ${DIM}(instalación completa desde cero)${NC}"
  echo -e "  [q] Cancelar"
  echo ""; echo -n "  Opción: "
  read -r _RI < /dev/tty
  case "$_RI" in
    1) _update_native_openclaw; exit 0 ;;
    2) rm -f "$CHECKPOINT" ;;
    q|Q|"") info "Nada que hacer."; exit 0 ;;
    *) info "Nada que hacer."; exit 0 ;;
  esac
fi

# ── Confirmación de instalación ──────────────────────────────
# En modo silencioso la confirmación ya la hizo menu.sh antes de invocar
# este script con --silent — no volver a preguntar.
if ! $SILENT_MODE; then
  echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║  Vas a instalar:                        ║"
  echo    "  ║  OpenClaw glibc nativo (npm + parches)  ║"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}~300MB · 10-20 min · requiere glibc     ${CYAN}${BOLD}║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  [1] Sí, instalar"
  echo -e "  [2] No, cancelar"
  echo ""; echo -n "  Opción: "
  read -r _CONFIRM_INSTALL < /dev/tty
  case "$_CONFIRM_INSTALL" in
    1) ;;
    *) echo "Cancelado."; exit 0 ;;
  esac
fi

# ── Checkpoint resume ────────────────────────────────────────
if [ -f "$CHECKPOINT" ] && [ -s "$CHECKPOINT" ]; then
  echo -e "${YELLOW}  Instalación previa detectada — se omitirán:${NC}"
  while IFS= read -r line; do
    echo -e "  ${GREEN}✓${NC} $line"
  done < "$CHECKPOINT"
  if $SILENT_MODE; then
    echo -e "  ${DIM}(modo silencioso — continuando desde checkpoint)${NC}"
  else
    echo ""; echo -n "  ¿Continuar desde donde quedó? (s/n): "
    read -r CONT < /dev/tty
    if [ "$CONT" != "s" ] && [ "$CONT" != "S" ]; then
      echo -n "  ¿Reiniciar desde cero? (s/n): "
      read -r RESET < /dev/tty
      [ "$RESET" = "s" ] || [ "$RESET" = "S" ] && rm -f "$CHECKPOINT"
    fi
  fi
  echo ""
fi

echo ""
echo "  Instalación NATIVA:"
echo "  ▸  glibc-runner + Node v${NODE_VERSION_TARGET} (si no existen)"
echo "  ▸  openclaw@latest vía npm --ignore-scripts"
echo "  ▸  koffi stub + clipboard stub + patches Android"
echo "  ▸  glibc-compat.js (os.networkInterfaces + homedir)"
echo "  ▸  Scripts de control (ocr/oclog/ockill) — el gateway se inicia manualmente después"
echo ""
if ! $SILENT_MODE; then
  echo -n "  ¿Continuar? (s/n): "
  read -r _CONF < /dev/tty
  [ "$_CONF" != "s" ] && [ "$_CONF" != "S" ] && { echo "Cancelado."; exit 0; }
fi

# ============================================================
#  PASO 0 — glibc-runner + Node
# ============================================================
titulo "PASO 0 — Infraestructura glibc + Node v${NODE_VERSION_TARGET}"

_ensure_glibc_node() {
  # ¿Ya hay Node en el rango probado (22-24) accesible?
  # NO aceptar cualquier ≥22 — Node 26 (visto en dispositivo real,
  # 2026-07-26) sube la versión ABI de módulos nativos y openclaw trae
  # varios (koffi, etc.) que ya necesitan stubs específicos para
  # android-arm64; una versión sin probar es un riesgo real, no solo
  # teórico. El propio proyecto de referencia AidanPark/openclaw-android
  # (glibc-runner nativo en Termux, mismo enfoque) fija Node 22 LTS
  # explícitamente en vez de "latest" por este motivo.
  local _NODE_OK=false
  if command -v node &>/dev/null; then
    local _NM; _NM=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [ -n "$_NM" ] && [ "$_NM" -ge 22 ] && [ "$_NM" -le 24 ] 2>/dev/null && _NODE_OK=true
  fi
  if ! $_NODE_OK && [ -x "$GLIBC_BIN_DIR/node" ]; then
    local _NM2; _NM2=$("$GLIBC_BIN_DIR/node" --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [ -n "$_NM2" ] && [ "$_NM2" -ge 22 ] && [ "$_NM2" -le 24 ] 2>/dev/null && {
      export PATH="$GLIBC_BIN_DIR:$PATH"; _NODE_OK=true
    }
  fi
  $_NODE_OK && { log "Node.js $(node --version 2>/dev/null) ya disponible — skip"; return 0; }

  info "Node.js ≥22 no detectado — instalando glibc-runner + Node v${NODE_VERSION_TARGET}..."
  echo ""

  # Paso 0a: glibc-runner
  if [ ! -f "$GLIBC_LD" ]; then
    info "Instalando glibc-runner..."
    pkg install -y glibc-repo 2>/dev/null || true
    pkg update -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>&1 | tail -2
    pkg install -y glibc-runner patchelf-glibc \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      error "No se pudo instalar glibc-runner"
    [ -f "$GLIBC_LD" ] || error "ld.so no encontrado tras instalar glibc-runner"
    log "glibc-runner instalado"
  else
    log "glibc-runner ya presente"
  fi

  # glibc /etc/hosts para dns.lookup localhost
  local _GLIBC_ETC="$TERMUX_PREFIX/glibc/etc"
  if [ -d "$_GLIBC_ETC" ] && [ ! -f "$_GLIBC_ETC/hosts" ]; then
    printf '127.0.0.1 localhost localhost.localdomain\n::1 localhost\n' > "$_GLIBC_ETC/hosts"
    log "glibc /etc/hosts creado"
  fi

  # Paso 0b: Node.js linux-arm64
  titulo "PASO 0b — Node.js v${NODE_VERSION_TARGET} linux-arm64"
  local _NODE_URL="https://nodejs.org/dist/v${NODE_VERSION_TARGET}/node-v${NODE_VERSION_TARGET}-linux-arm64.tar.xz"
  local _NODE_TMP="$TMP_DIR/node-openclaw-$$.tar.xz"
  mkdir -p "$TMP_DIR" "$GLIBC_NODE_DIR" "$GLIBC_BIN_DIR"

  info "Descargando Node.js v${NODE_VERSION_TARGET} (~30MB)..."
  curl -fL --progress-bar "$_NODE_URL" -o "$_NODE_TMP" 2>/dev/null || \
    wget --progress=bar:force -O "$_NODE_TMP" "$_NODE_URL" 2>/dev/null || \
    error "Descarga fallida — verifica conexión"
  [ -s "$_NODE_TMP" ] || error "Archivo Node.js descargado vacío"

  info "Extrayendo..."
  tar -xJf "$_NODE_TMP" -C "$GLIBC_NODE_DIR" --strip-components=1 || \
    error "Error extrayendo Node.js"
  rm -f "$_NODE_TMP"

  # Mover binario real y crear wrapper grun-style
  [ -f "$GLIBC_NODE_DIR/bin/node" ] && [ ! -L "$GLIBC_NODE_DIR/bin/node" ] && \
    mv "$GLIBC_NODE_DIR/bin/node" "$GLIBC_NODE_DIR/bin/node.real"

  cat > "$GLIBC_BIN_DIR/node" << NODEWRAP
#!/data/data/com.termux/files/usr/bin/bash
[ -n "\$LD_PRELOAD" ] && export _OA_ORIG_LD_PRELOAD="\$LD_PRELOAD"
unset LD_PRELOAD
_OA_COMPAT="\$HOME/.openclaw/glibc-compat.js"
# Si NODE_OPTIONS ya trae una referencia rota a compat.js (archivo
# borrado/reinstalado), limpiarla antes de decidir si agregar una nueva —
# si no, node muere con MODULE_NOT_FOUND en internal/preload (2026-07-26)
if [ -n "\${NODE_OPTIONS:-}" ] && [ ! -f "\$_OA_COMPAT" ]; then
  case "\$NODE_OPTIONS" in
    *"\$_OA_COMPAT"*)
      NODE_OPTIONS=\$(echo "\$NODE_OPTIONS" | sed "s#--require \$_OA_COMPAT##;s#-r \$_OA_COMPAT##")
      export NODE_OPTIONS
      ;;
  esac
fi
if [ -f "\$_OA_COMPAT" ]; then
  case "\${NODE_OPTIONS:-}" in
    *"\$_OA_COMPAT"*) ;;
    *) export NODE_OPTIONS="\${NODE_OPTIONS:+\$NODE_OPTIONS }-r \$_OA_COMPAT" ;;
  esac
fi
exec "$GLIBC_LD" --library-path "$TERMUX_PREFIX/glibc/lib" "$GLIBC_NODE_DIR/bin/node.real" "\$@"
NODEWRAP
  chmod +x "$GLIBC_BIN_DIR/node"

  if [ -f "$GLIBC_NODE_DIR/lib/node_modules/npm/bin/npm-cli.js" ]; then
    cat > "$GLIBC_BIN_DIR/npm" << NPMWRAP
#!/data/data/com.termux/files/usr/bin/bash
exec "$GLIBC_BIN_DIR/node" "$GLIBC_NODE_DIR/lib/node_modules/npm/bin/npm-cli.js" "\$@"
NPMWRAP
    chmod +x "$GLIBC_BIN_DIR/npm"
  fi
  if [ -f "$GLIBC_NODE_DIR/lib/node_modules/npm/bin/npx-cli.js" ]; then
    cat > "$GLIBC_BIN_DIR/npx" << NPXWRAP
#!/data/data/com.termux/files/usr/bin/bash
exec "$GLIBC_BIN_DIR/node" "$GLIBC_NODE_DIR/lib/node_modules/npm/bin/npx-cli.js" "\$@"
NPXWRAP
    chmod +x "$GLIBC_BIN_DIR/npx"
  fi

  ! grep -q "openclaw-android/bin" "$BASHRC" 2>/dev/null && \
    echo 'export PATH="$HOME/.openclaw-android/bin:$PATH"' >> "$BASHRC"
  export PATH="$GLIBC_BIN_DIR:$PATH"

  local _VCK; _VCK=$("$GLIBC_BIN_DIR/node" --version 2>/dev/null)
  [ -z "$_VCK" ] && error "Wrapper de Node falló — revisa $GLIBC_BIN_DIR/node"
  log "Node.js $_VCK listo (glibc, grun wrapper)"
}

_ensure_glibc_node

# ── PASO 1 — Verificar Node ──────────────────────────────────
titulo "PASO 1 — Verificando Node.js y npm"

if ! command -v node &>/dev/null; then
  error "Node.js no encontrado tras Paso 0 — reinicia Termux y vuelve a intentar"
fi
NODE_MAJOR=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
[ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 22 ] && \
  error "Node.js $(node --version) insuficiente — se requiere v22+"
log "Node.js $(node --version) — OK"

! command -v npm &>/dev/null && error "npm no encontrado"
log "npm $(npm --version) — OK"

mkdir -p "$LOG_DIR" "$TMP_DIR" "$HOME/.openclaw"
export TMPDIR="$TMP_DIR"

npm config set prefix "$NPM_GLOBAL" 2>/dev/null || true
! grep -q "export PATH=$NPM_BIN" "$BASHRC" 2>/dev/null && \
  echo "export PATH=$NPM_BIN:\$PATH" >> "$BASHRC"
export PATH="$NPM_BIN:$PATH"

! grep -q 'max-old-space-size=5632' "$BASHRC" 2>/dev/null && \
  echo 'export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size=5632"' >> "$BASHRC"
export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size=5632"
log "npm global en $NPM_GLOBAL · heap 5632MB"

# ── PASO 2 — Instalar openclaw ───────────────────────────────
titulo "PASO 2 — Instalando OpenClaw"

# El checkpoint es solo una bandera — si el paquete real desapareció desde
# la última corrida exitosa (ej. tras un SIGKILL de Android en otro paso),
# confiar ciegamente en él deja el script fallando para siempre en el mismo
# error. Verificar el artefacto real antes de saltar la instalación.
if check_done "n_openclaw_install" && [ ! -d "$NPM_GLOBAL/lib/node_modules/openclaw" ]; then
  warn "Checkpoint 'n_openclaw_install' activo pero el paquete no está en disco — reinstalando"
  grep -v "^n_openclaw_install$" "$CHECKPOINT" > "$CHECKPOINT.tmp" 2>/dev/null && mv "$CHECKPOINT.tmp" "$CHECKPOINT"
fi

if check_done "n_openclaw_install"; then
  log "OpenClaw ya instalado [checkpoint]"
else
  info "npm install -g openclaw@latest --ignore-scripts"
  env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true \
    TMPDIR="$TMP_DIR" \
    npm install -g openclaw@latest --ignore-scripts 2>&1 | tail -10

  _OC_BIN=$(command -v openclaw 2>/dev/null || find "$NPM_BIN" -name "openclaw" 2>/dev/null | head -1)
  [ -z "$_OC_BIN" ] && error "openclaw no encontrado tras instalación"
  log "openclaw instalado: $_OC_BIN"
  mark_done "n_openclaw_install"
fi

OC_BASE=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE "/.+/openclaw" | head -1)
[ -z "$OC_BASE" ] && OC_BASE="$NPM_GLOBAL/lib/node_modules/openclaw"
[ ! -d "$OC_BASE" ] && error "Directorio openclaw no encontrado: $OC_BASE"
log "Paquete en: $OC_BASE"

# ── PASO 3 — glibc-compat.js ────────────────────────────────
titulo "PASO 3 — glibc-compat.js"

if check_done "n_openclaw_compat"; then
  log "glibc-compat.js ya creado [checkpoint]"
else
  cat > "$COMPAT_JS" << 'EOF'
// glibc-compat.js — termux-ai-stack
// Fix Android/Bionic: os.networkInterfaces() y os.homedir()
const os = require('os');
const _ni = os.networkInterfaces.bind(os);
os.networkInterfaces = function () {
  try { const r = _ni(); if (r && Object.keys(r).length > 0) return r; } catch (_) {}
  return { lo: [{ address: '127.0.0.1', netmask: '255.0.0.0', family: 'IPv4',
    mac: '00:00:00:00:00:00', internal: true, cidr: '127.0.0.1/8' }] };
};
const _hd = os.homedir.bind(os);
os.homedir = function () { return process.env.HOME || _hd(); };
EOF
  ! grep -q "glibc-compat.js" "$BASHRC" 2>/dev/null && {
    sed -i '/max-old-space-size=5632/d' "$BASHRC"
    echo "export NODE_OPTIONS=\"\${NODE_OPTIONS:+\$NODE_OPTIONS }--require $COMPAT_JS --max-old-space-size=5632\"" >> "$BASHRC"
  }
  export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require $COMPAT_JS"
  log "glibc-compat.js creado y configurado"
  mark_done "n_openclaw_compat"
fi

# ── PASO 4 — koffi stub ──────────────────────────────────────
titulo "PASO 4 — koffi stub (android-arm64)"

if check_done "n_openclaw_koffi"; then
  log "koffi stub ya aplicado [checkpoint]"
else
  _KOFFI_DIR="$OC_BASE/node_modules/koffi"
  if [ -d "$_KOFFI_DIR" ]; then
    cat > "$_KOFFI_DIR/index.js" << 'EOF'
// koffi stub — android-arm64 (termux-ai-stack)
// Solo usado por pi-tui para Windows VT input — nunca ejecuta en Android
const handler = {
  get(_, prop) {
    if (prop === '__esModule') return false;
    if (prop === 'default') return proxy;
    if (prop === 'then') return undefined;
    return function () { throw new Error('koffi stub: no disponible en android-arm64'); };
  }
};
const proxy = new Proxy({}, handler);
module.exports = proxy;
module.exports.default = proxy;
EOF
    log "koffi stub aplicado"
  else
    info "koffi no encontrado — omitiendo"
  fi
  mark_done "n_openclaw_koffi"
fi

# ── PASO 5 — clipboard stub ──────────────────────────────────
titulo "PASO 5 — clipboard stub"

if check_done "n_openclaw_clipboard"; then
  log "clipboard stub ya aplicado [checkpoint]"
else
  _CLIP="$OC_BASE/node_modules/@mariozechner/clipboard/index.js"
  if [ -f "$_CLIP" ]; then
    node -e "
const fs = require('fs');
const mock = \`module.exports = {
  availableFormats:()=>[],getText:()=>'',setText:()=>false,hasText:()=>false,
  getImageBinary:()=>null,getImageBase64:()=>null,setImageBinary:()=>false,
  setImageBase64:()=>false,hasImage:()=>false,getHtml:()=>'',setHtml:()=>false,
  hasHtml:()=>false,getRtf:()=>'',setRtf:()=>false,hasRtf:()=>false,
  clear:()=>{},watch:()=>({stop:()=>{}}),callThreadsafeFunction:()=>{}
};\`;
fs.writeFileSync('$_CLIP', mock);
" && log "clipboard stub aplicado" || warn "clipboard stub falló — no crítico"
  else
    info "clipboard no encontrado — omitiendo"
  fi
  mark_done "n_openclaw_clipboard"
fi

# ── PASO 6 — Patches /tmp y /bin/npm ────────────────────────
titulo "PASO 6 — Patches Android"

if check_done "n_openclaw_patches"; then
  log "Patches ya aplicados [checkpoint]"
else
  _DIST="$OC_BASE/dist"
  if [ -d "$_DIST" ]; then
    _FILES_TMP=$(grep -rl "/tmp/openclaw" "$_DIST" 2>/dev/null || true)
    if [ -n "$_FILES_TMP" ]; then
      while IFS= read -r _f; do
        node -e "
const fs=require('fs');
const c=fs.readFileSync('$_f','utf8');
fs.writeFileSync('$_f',c.replace(/\\/tmp\\/openclaw/g,process.env.HOME+'/openclaw-logs'));
"
        info "  /tmp parcheado: $(basename "$_f")"
      done <<< "$_FILES_TMP"
      log "/tmp/openclaw → \$HOME/openclaw-logs"
    else
      log "Sin referencias /tmp/openclaw — OK"
    fi

    _REAL_NPM=$(command -v npm 2>/dev/null || true)
    if [ -n "$_REAL_NPM" ] && [ "$_REAL_NPM" != "/bin/npm" ]; then
      _FILES_NPM=$(grep -rl '"/bin/npm"\|'"'"'/bin/npm'"'" "$_DIST" 2>/dev/null || true)
      if [ -n "$_FILES_NPM" ]; then
        while IFS= read -r _f; do
          sed -i "s|/bin/npm|${_REAL_NPM}|g" "$_f"
        done <<< "$_FILES_NPM"
        log "/bin/npm → $_REAL_NPM"
      fi
    fi
  else
    warn "dist/ no encontrado — saltando patches"
  fi
  mark_done "n_openclaw_patches"
fi

# ── PASO 7 — Wrapper openclaw ────────────────────────────────
titulo "PASO 7 — Wrapper openclaw"

if check_done "n_openclaw_wrapper"; then
  log "Wrapper ya creado [checkpoint]"
else
  _ENTRY="$OC_BASE/dist/entry.js"
  if [ -f "$_ENTRY" ]; then
    cat > "$NPM_BIN/openclaw" << WRAPPER
#!/data/data/com.termux/files/usr/bin/sh
# Sanea NODE_OPTIONS heredado antes de exec — si trae --require/-r a un
# glibc-compat.js que ya no existe, node muere con MODULE_NOT_FOUND en
# internal/preload antes de correr nada. Por acá pasan gateway, onboard
# y tui — un solo punto de saneo cubre los tres (bug confirmado 2026-07-26,
# el saneo anterior solo cubría la instalación, no el uso posterior)
_OC_COMPAT="\$HOME/.openclaw/glibc-compat.js"
if [ -n "\$NODE_OPTIONS" ] && [ ! -f "\$_OC_COMPAT" ]; then
  case "\$NODE_OPTIONS" in
    *"\$_OC_COMPAT"*)
      NODE_OPTIONS=\$(echo "\$NODE_OPTIONS" | sed "s#--require \$_OC_COMPAT##;s#-r \$_OC_COMPAT##")
      export NODE_OPTIONS
      ;;
  esac
fi
exec node "$_ENTRY" "\$@"
WRAPPER
    chmod +x "$NPM_BIN/openclaw"
    log "Wrapper creado: $NPM_BIN/openclaw → node $_ENTRY"
  else
    warn "entry.js no encontrado — usando bin de npm directamente"
    _OC_BIN_FILE="$NPM_BIN/openclaw"
    if [ -f "$_OC_BIN_FILE" ] && head -n1 "$_OC_BIN_FILE" | grep -q "^#!/usr/bin/env"; then
      _TENV="$TERMUX_PREFIX/bin/env"
      [ -x "$_TENV" ] && {
        sed -i "1s|#!/usr/bin/env|#!${_TENV}|" "$_OC_BIN_FILE"
        log "Shebang parcheado → $_TENV"
      }
    fi
  fi
  mark_done "n_openclaw_wrapper"
fi

# ── PASO 8 — Scripts de control + aliases .bashrc ────────────
titulo "PASO 8 — Scripts de control y aliases"

OPENCLAW_SCRIPTS="$HOME/scripts/openclaw"

if check_done "n_openclaw_aliases"; then
  log "Scripts y aliases ya configurados [checkpoint]"
else
  mkdir -p "$OPENCLAW_SCRIPTS"

  # Heap del primer arranque: escalado a RAM disponible, no el 5.6GB fijo
  # que usan las shells normales — evita que Android mate el proceso por
  # OOM justo cuando Node carga el bundle completo por primera vez.
  _MEM_AVAIL_KB=$(grep -m1 MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
  if [ -n "$_MEM_AVAIL_KB" ]; then
    _HEAP_MB=$(( _MEM_AVAIL_KB * 60 / 100 / 1024 ))
    [ "$_HEAP_MB" -lt 1024 ] && _HEAP_MB=1024
    [ "$_HEAP_MB" -gt 5632 ] && _HEAP_MB=5632
  else
    _HEAP_MB=2048
  fi

  # openclaw_start.sh — (antes función ocr() en .bashrc)
  cat > "$OPENCLAW_SCRIPTS/openclaw_start.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
# Lanzador/reinicio OpenClaw gateway — nativo Termux — termux-ai-stack
# --no-wait: dispara tmux y termina de inmediato, sin esperar el health-check.
#            La instalación (install_openclaw.sh) ya NO llama a este script
#            en absoluto (el primer arranque quedó 100% manual, ver PASO 9
#            de install_openclaw.sh) — este flag queda disponible para quien
#            quiera invocar un arranque no bloqueante manualmente.
NOWAIT=0
for arg in "\$@"; do [ "\$arg" = "--no-wait" ] && NOWAIT=1; done
export TMPDIR="$TMP_DIR"
echo -e "\033[1;33m[+] Reiniciando OpenClaw...\033[0m"
pkill -9 -f 'openclaw' 2>/dev/null || true
tmux kill-session -t openclaw 2>/dev/null || true
sleep 1
tmux new -d -s openclaw
sleep 1
tmux send-keys -t openclaw \
  "export TMPDIR=$TMP_DIR; export NODE_OPTIONS=\"--max-old-space-size=$_HEAP_MB\"; openclaw gateway --bind loopback --port $PORT 2>&1 | tee $LOG_DIR/runtime.log" Enter
if [ "\$NOWAIT" = "1" ]; then
  echo -e "\033[0;32m[OK]\033[0m OpenClaw lanzado en background (tmux 'openclaw') — verifica el estado desde el menú en unos segundos"
  exit 0
fi
HEALTH_OK=false
# Ventana acotada a ~12s (6x2s) — solo se ejecuta en uso interactivo
# (menú), donde no hay riesgo de que Android mate un proceso backgroundeado
for i in \$(seq 1 6); do
  sleep 2
  curl -sf --max-time 2 http://127.0.0.1:$PORT &>/dev/null && { HEALTH_OK=true; break; }
  tmux has-session -t openclaw 2>/dev/null || break
done
if \$HEALTH_OK; then
  echo -e "\033[0;32m[OK]\033[0m OpenClaw iniciado :$PORT"
  exit 0
else
  echo -e "\033[0;31m[ERROR]\033[0m Gateway no respondió en 12s — revisa: cat $LOG_DIR/runtime.log"
  exit 1
fi
SCRIPT
  chmod +x "$OPENCLAW_SCRIPTS/openclaw_start.sh"
  log "openclaw_start.sh"

  # openclaw_stop.sh — (antes función ockill() en .bashrc)
  cat > "$OPENCLAW_SCRIPTS/openclaw_stop.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
pkill -9 -f "openclaw" 2>/dev/null || true
tmux kill-session -t openclaw 2>/dev/null || true
echo -e "\033[0;32m[OK]\033[0m OpenClaw detenido"
SCRIPT
  chmod +x "$OPENCLAW_SCRIPTS/openclaw_stop.sh"
  log "openclaw_stop.sh"

  # openclaw_log.sh — (antes función oclog() en .bashrc)
  cat > "$OPENCLAW_SCRIPTS/openclaw_log.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
tmux has-session -t openclaw 2>/dev/null && tmux attach -t openclaw \\
  || echo -e "\033[1;33m[AVISO]\033[0m No corre. Usa: openclaw-start"
SCRIPT
  chmod +x "$OPENCLAW_SCRIPTS/openclaw_log.sh"
  log "openclaw_log.sh"

  sed -i '/# --- OpenClaw Start ---/,/# --- OpenClaw End ---/d' "$BASHRC" 2>/dev/null || true
  grep -v "openclaw-start\|openclaw-stop\|openclaw-status\|openclaw-token\|openclaw-tui\|ocr()\|oclog()\|ockill()\|# OpenClaw" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << ALIASES

# --- OpenClaw Start ---
# termux-ai-stack · OpenClaw nativo ARM64
export TMPDIR="$TMP_DIR"
alias openclaw-start='bash ~/scripts/openclaw/openclaw_start.sh'
alias openclaw-stop='bash ~/scripts/openclaw/openclaw_stop.sh'
alias openclaw-log='bash ~/scripts/openclaw/openclaw_log.sh'
alias openclaw-status='curl -sf --max-time 2 http://127.0.0.1:$PORT &>/dev/null && echo "OpenClaw activo :$PORT" || echo "OpenClaw detenido"'
alias openclaw-tui='openclaw tui'
# Alias cortos (compatibilidad con versiones anteriores)
alias ocr='bash ~/scripts/openclaw/openclaw_start.sh'
alias oclog='bash ~/scripts/openclaw/openclaw_log.sh'
alias ockill='bash ~/scripts/openclaw/openclaw_stop.sh'
# --- OpenClaw End ---
ALIASES

  log "Scripts creados en ~/scripts/openclaw/ y aliases agregados a ~/.bashrc"
  mark_done "n_openclaw_aliases"
fi

# ── PASO 9 — Onboard ────────────────────────────────────────
# El arranque del gateway durante la instalación se eliminó (2026-07-26,
# pedido explícito) — install_openclaw.sh corre en background vía
# menu.sh, y lanzar+esperar el gateway ahí lo exponía a que Android lo
# matara (SIGKILL/137) en medio de la instalación, sin relación con si
# el paquete en sí quedó bien instalado. El primer arranque real ahora
# es 100% manual, desde el menú ([1] Iniciar/reiniciar gateway) — igual
# de simple, sin el riesgo de matar la instalación a mitad de camino.
titulo "PASO 9 — Configuración inicial (onboard)"

if $SILENT_MODE; then
  warn "Modo silencioso — onboard omitido, ejecutalo después desde el menú [1] OpenClaw → [6]"
else
  echo -n "  ¿Ejecutar openclaw onboard ahora? (s/n): "
  read -r _DO_OB < /dev/tty
  if [ "$_DO_OB" = "s" ] || [ "$_DO_OB" = "S" ]; then
    _OLD_LD="${LD_PRELOAD:-}"; unset LD_PRELOAD
    openclaw onboard < /dev/tty || warn "onboard terminó con error — re-ejecuta desde el menú"
    [ -n "$_OLD_LD" ] && export LD_PRELOAD="$_OLD_LD"
  else
    warn "onboard omitido — ejecuta después desde el menú [1] OpenClaw → [6]"
  fi
fi

# ── PASO 10 — Registry ───────────────────────────────────────
titulo "PASO 10 — Registry"
_CL_VER_F=$(openclaw --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9.]+' | head -1)
[ -z "$_CL_VER_F" ] && _CL_VER_F="unknown"
update_registry "$_CL_VER_F" "nativo_termux"

titulo "INSTALACIÓN NATIVA COMPLETADA"
echo "  Versión:  ${_CL_VER_F}"
echo "  Puerto:   $PORT"
echo "  Node:     $(node --version 2>/dev/null)"
echo "  Logs:     $LOG_DIR/runtime.log"
echo ""
echo "  El gateway NO se inicia automáticamente — arráncalo cuando quieras:"
echo "  ocr              → iniciar/reiniciar gateway"
echo "  oclog            → ver logs en vivo"
echo "  ockill           → detener gateway"
echo "  openclaw tui     → interfaz TUI"
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para activar aliases${NC}"
echo ""
rm -f "$CHECKPOINT"

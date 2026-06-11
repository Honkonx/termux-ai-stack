#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_openclaw.sh  v3.0.0
#  Instala OpenClaw en Termux ARM64 (sin root)
#
#  MODOS:
#    native — glibc + npm nativo  (Node v24, recomendado)
#    proot  — NVM + Node 22 en Debian proot
#
#  QUÉ HACE (nativo):
#    ✅ PASO 0 — instala glibc-runner + Node v24 si no existen
#    ✅ Instala openclaw vía npm --ignore-scripts
#    ✅ koffi stub, clipboard stub, patch /tmp, patch /bin/npm
#    ✅ glibc-compat.js (os.networkInterfaces + homedir)
#    ✅ Wrapper node dist/entry.js
#    ✅ Aliases ocr/oclog/ockill en .bashrc
#    ✅ Lanza gateway via tmux
#
#  QUÉ HACE (proot):
#    ✅ Verifica/instala rootfs Debian
#    ✅ NVM + Node 22 en proot
#    ✅ Shim de red Android (os.networkInterfaces fix)
#    ✅ openclaw via npm en proot
#    ✅ Setup wizard
#    ✅ Scripts de control desde Termux nativo
#    ✅ Aliases en .bashrc
#
#  REGLAS TÉCNICAS (NO VIOLAR):
#    - NUNCA /tmp/ → siempre $HOME/tmp  (noexec Android 15)
#    - NUNCA read sin < /dev/tty         (Termux pipe mode)
#    - NUNCA import requests             (usar urllib builtin)
#    - NUNCA datetime('now') en SQLite   (usar datetime.now())
#
#  VERSIÓN: 3.0.0 | Junio 2026
# ============================================================

set -euo pipefail

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$HOME/.local/bin:$HOME/.openclaw-android/bin:$HOME/.npm-global/bin:$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Constantes glibc ──────────────────────────────────────────
GLIBC_LD="$TERMUX_PREFIX/glibc/lib/ld-linux-aarch64.so.1"
GLIBC_NODE_DIR="$HOME/.openclaw-android/node"
GLIBC_BIN_DIR="$HOME/.openclaw-android/bin"
NODE_VERSION_TARGET="22.22.0"

# ── Constantes generales ──────────────────────────────────────
NPM_GLOBAL="$HOME/.npm-global"
NPM_BIN="$NPM_GLOBAL/bin"
LOG_DIR="$HOME/openclaw-logs"
TMP_DIR="$HOME/tmp"
COMPAT_JS="$HOME/.openclaw/glibc-compat.js"
REGISTRY="$HOME/.android_server_registry"
PORT=18789
BASHRC="$HOME/.bashrc"

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

# ── Checkpoint por modo ───────────────────────────────────────
CHECKPOINT_NATIVE="$HOME/.install_openclaw_native_checkpoint"
CHECKPOINT_PROOT="$HOME/.install_openclaw_proot_checkpoint"
CHECKPOINT=""   # se asigna según modo elegido

check_done() { [ -n "$CHECKPOINT" ] && grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { [ -n "$CHECKPOINT" ] && echo "$1" >> "$CHECKPOINT"; }

# ── Registry ─────────────────────────────────────────────────
update_registry() {
  local version="$1" location="$2"
  local date_now
  date_now=$(python3 -c "from datetime import datetime; print(datetime.now().strftime('%Y-%m-%d'))")
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
#  CABECERA
# ============================================================
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · OpenClaw Installer v3  ║
  ║   ARM64 · sin root                         ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ============================================================
#  MENÚ DE MODO — Nativo o Proot
# ============================================================

# Detectar qué está ya instalado
_NATIVE_INSTALLED=false
_PROOT_INSTALLED=false

if [ -f "$NPM_BIN/openclaw" ] || command -v openclaw &>/dev/null 2>&1; then
  _LOC=$(grep "^openclaw\.location=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  [ "$_LOC" = "nativo_termux" ] && _NATIVE_INSTALLED=true
fi

ROOTFS_BASE="$TERMUX_PREFIX/var/lib/proot-distro/installed-rootfs"
DISTRO_NAME=""
ROOTFS_PATH=""
_detect_rootfs() {
  DISTRO_NAME=""; ROOTFS_PATH=""
  if command -v proot-distro &>/dev/null; then
    local _pd _d
    _pd=$(proot-distro list 2>/dev/null)
    for _d in debian ubuntu fedora archlinux; do
      if echo "$_pd" | grep -qE "^\s*\*?\s*${_d}\b" && [ -d "$ROOTFS_BASE/$_d" ]; then
        DISTRO_NAME="$_d"; ROOTFS_PATH="$ROOTFS_BASE/$_d"; return 0
      fi
    done
  fi
  if [ -d "$ROOTFS_BASE" ]; then
    local _rd
    for _rd in "$ROOTFS_BASE"/*/; do
      _rd="${_rd%/}"
      if [ -d "$_rd" ]; then
        DISTRO_NAME=$(basename "$_rd"); ROOTFS_PATH="$_rd"; return 0
      fi
    done
  fi
  return 1
}
_detect_rootfs

if [ -n "$DISTRO_NAME" ]; then
  if proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; export NVM_DIR="/root/.nvm"
     [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
     command -v openclaw' &>/dev/null 2>&1; then
    _PROOT_INSTALLED=true
  fi
fi

# Mostrar estado actual
echo -e "  Estado actual:"
$_NATIVE_INSTALLED \
  && echo -e "  ${GREEN}●${NC} Nativo  — instalado" \
  || echo -e "  ${YELLOW}○${NC} Nativo  — no instalado"
$_PROOT_INSTALLED \
  && echo -e "  ${GREEN}●${NC} Proot   — instalado (${DISTRO_NAME:-?})" \
  || echo -e "  ${YELLOW}○${NC} Proot   — no instalado"
echo ""

echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  ¿Qué instalar?                         ║"
echo    "  ╠══════════════════════════════════════════╣"
echo -e "  ║  ${NC}[1] Nativo  — glibc + npm  ${DIM}(recomendado)${NC}${CYAN}${BOLD}║"
echo -e "  ║  ${NC}[2] Proot   — NVM + Debian ${DIM}(alternativo)${NC}${CYAN}${BOLD} ║"
echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                             ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -n "  Opción: "
read -r MODE_CHOICE < /dev/tty

case "$MODE_CHOICE" in
  1) INSTALL_MODE="native" ;;
  2) INSTALL_MODE="proot"  ;;
  b|B|"") echo "Cancelado."; exit 0 ;;
  *) echo "Opción inválida."; exit 1 ;;
esac

# ============================================================
# ════════════════════════════════════════════════════════════
#  RAMA NATIVA
# ════════════════════════════════════════════════════════════
# ============================================================
if [ "$INSTALL_MODE" = "native" ]; then

CHECKPOINT="$CHECKPOINT_NATIVE"

# Check reinstalar
if $_NATIVE_INSTALLED; then
  _CL_VER=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  echo ""
  echo -e "  ${GREEN}✓ OpenClaw nativo ya está instalado${NC} (v${_CL_VER:-?})"
  echo -n "  ¿Reinstalar/actualizar? (s/n): "
  read -r _RI < /dev/tty
  [ "$_RI" != "s" ] && [ "$_RI" != "S" ] && { info "Nada que hacer."; exit 0; }
  rm -f "$CHECKPOINT_NATIVE"
fi

echo ""
echo "  Instalación NATIVA:"
echo "  ▸ glibc-runner + Node v${NODE_VERSION_TARGET} (si no existen)"
echo "  ▸ openclaw@latest vía npm --ignore-scripts"
echo "  ▸ koffi stub + clipboard stub + patches Android"
echo "  ▸ glibc-compat.js (os.networkInterfaces + homedir)"
echo "  ▸ Gateway via tmux (ocr/oclog/ockill)"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r _CONF < /dev/tty
[ "$_CONF" != "s" ] && [ "$_CONF" != "S" ] && { echo "Cancelado."; exit 0; }

# ── PASO 0 — glibc-runner + Node ────────────────────────────
titulo "PASO 0 — Infraestructura glibc + Node"

_ensure_glibc_node() {
  # ¿Ya hay Node ≥22 accesible?
  local _NODE_OK=false
  if command -v node &>/dev/null; then
    local _NM; _NM=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [ -n "$_NM" ] && [ "$_NM" -ge 22 ] 2>/dev/null && _NODE_OK=true
  fi
  if ! $_NODE_OK && [ -x "$GLIBC_BIN_DIR/node" ]; then
    local _NM2; _NM2=$("$GLIBC_BIN_DIR/node" --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [ -n "$_NM2" ] && [ "$_NM2" -ge 22 ] 2>/dev/null && {
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
  local _NODE_TMP="$TERMUX_PREFIX/tmp/node-openclaw-$$.tar.xz"
  mkdir -p "$TERMUX_PREFIX/tmp" "$GLIBC_NODE_DIR" "$GLIBC_BIN_DIR"

  info "Descargando Node.js v${NODE_VERSION_TARGET} (~25MB)..."
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

# ── PASO 8 — Aliases .bashrc ─────────────────────────────────
titulo "PASO 8 — Aliases en .bashrc"

if check_done "n_openclaw_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  sed -i '/# --- OpenClaw Start ---/,/# --- OpenClaw End ---/d' "$BASHRC" 2>/dev/null || true
  grep -v "openclaw-start\|openclaw-stop\|openclaw-status\|openclaw-token\|openclaw-tui\|# OpenClaw" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << ALIASES

# --- OpenClaw Start ---
# termux-ai-stack · OpenClaw nativo ARM64
export TMPDIR="$TMP_DIR"

ocr() {
  echo -e "\033[1;33m[+] Reiniciando OpenClaw...\033[0m"
  pkill -9 -f 'openclaw' 2>/dev/null || true
  tmux kill-session -t openclaw 2>/dev/null || true
  sleep 1
  tmux new -d -s openclaw
  sleep 1
  tmux send-keys -t openclaw \
    "export TMPDIR=$TMP_DIR; openclaw gateway --bind loopback --port $PORT 2>&1 | tee $LOG_DIR/runtime.log" C-m
  sleep 2
  tmux has-session -t openclaw 2>/dev/null \
    && echo -e "\033[0;32m[OK]\033[0m OpenClaw iniciado :$PORT" \
    || echo -e "\033[0;31m[ERROR]\033[0m tmux terminó — cat $LOG_DIR/runtime.log"
}
oclog()  { tmux has-session -t openclaw 2>/dev/null && tmux attach -t openclaw \
             || echo -e "\033[1;33m[AVISO]\033[0m No corre. Usa: ocr"; }
ockill() { pkill -9 -f "openclaw" 2>/dev/null || true
           tmux kill-session -t openclaw 2>/dev/null || true
           echo -e "\033[0;32m[OK]\033[0m OpenClaw detenido"; }
alias openclaw-start='ocr'
alias openclaw-stop='ockill'
alias openclaw-status='curl -sf --max-time 1 http://127.0.0.1:$PORT &>/dev/null && echo "OpenClaw activo :$PORT" || echo "OpenClaw detenido"'
alias openclaw-tui='openclaw tui'
# --- OpenClaw End ---
ALIASES

  log "Aliases agregados a ~/.bashrc"
  mark_done "n_openclaw_aliases"
fi

# ── PASO 9 — Primer arranque ─────────────────────────────────
titulo "PASO 9 — Primer arranque del gateway"

if check_done "n_openclaw_first_start"; then
  log "Gateway ya iniciado antes [checkpoint]"
else
  if ! command -v tmux &>/dev/null; then
    pkg install -y tmux 2>/dev/null || warn "tmux no disponible — inicia con: ocr"
  fi
  if command -v tmux &>/dev/null; then
    pkill -9 -f 'openclaw' 2>/dev/null || true
    tmux kill-session -t openclaw 2>/dev/null || true
    sleep 1
    tmux new -d -s openclaw
    sleep 1
    tmux send-keys -t openclaw \
      "export TMPDIR=$TMP_DIR; openclaw gateway --bind loopback --port $PORT 2>&1 | tee $LOG_DIR/runtime.log" C-m
    sleep 3
    tmux has-session -t openclaw 2>/dev/null \
      && log "Gateway iniciado en sesión tmux 'openclaw'" \
      || warn "tmux terminó — puede ser normal si openclaw pide configuración"
    mark_done "n_openclaw_first_start"
  fi
fi

# ── PASO 10 — Onboard ────────────────────────────────────────
titulo "PASO 10 — Configuración inicial (onboard)"

echo -n "  ¿Ejecutar openclaw onboard ahora? (s/n): "
read -r _DO_OB < /dev/tty
if [ "$_DO_OB" = "s" ] || [ "$_DO_OB" = "S" ]; then
  _OLD_LD="${LD_PRELOAD:-}"; unset LD_PRELOAD
  openclaw onboard < /dev/tty || warn "onboard terminó con error — re-ejecuta desde el menú"
  [ -n "$_OLD_LD" ] && export LD_PRELOAD="$_OLD_LD"
else
  warn "onboard omitido — ejecuta después desde el menú [1] OpenClaw → [6]"
fi

# ── PASO 11 — Registry ───────────────────────────────────────
titulo "PASO 11 — Registry"
_CL_VER_F=$(openclaw --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9.]+' | head -1)
[ -z "$_CL_VER_F" ] && _CL_VER_F="unknown"
update_registry "$_CL_VER_F" "nativo_termux"

titulo "INSTALACIÓN NATIVA COMPLETADA ✓"
echo "  Versión:  ${_CL_VER_F}"
echo "  Puerto:   $PORT"
echo "  Node:     $(node --version 2>/dev/null)"
echo "  Logs:     $LOG_DIR/runtime.log"
echo ""
echo "  COMANDOS (activos tras reabrir Termux):"
echo "  ocr              → iniciar/reiniciar gateway"
echo "  oclog            → ver logs en vivo"
echo "  ockill           → detener gateway"
echo "  openclaw tui     → interfaz TUI"
echo "  http://localhost:$PORT"
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para activar aliases${NC}"
echo ""
rm -f "$CHECKPOINT_NATIVE"
exit 0

fi  # end INSTALL_MODE=native

# ============================================================
# ════════════════════════════════════════════════════════════
#  RAMA PROOT
# ════════════════════════════════════════════════════════════
# ============================================================

CHECKPOINT="$CHECKPOINT_PROOT"

# Check reinstalar proot
if $_PROOT_INSTALLED; then
  _CL_VER_P=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; export NVM_DIR="/root/.nvm"
     [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
     openclaw --version 2>/dev/null | head -1' 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9.]+' | head -1)
  echo ""
  echo -e "  ${GREEN}✓ OpenClaw proot ya instalado${NC} (v${_CL_VER_P:-?})"
  echo -n "  ¿Reinstalar/actualizar? (s/n): "
  read -r _RI2 < /dev/tty
  [ "$_RI2" != "s" ] && [ "$_RI2" != "S" ] && { info "Nada que hacer."; exit 0; }
  rm -f "$CHECKPOINT_PROOT"
fi

echo ""
echo "  Instalación PROOT:"
echo "  ▸ proot Debian + NVM + Node 22"
echo "  ▸ shim de red Android (os.networkInterfaces)"
echo "  ▸ openclaw@latest via npm en proot"
echo "  ▸ Setup wizard (optional)"
echo "  ▸ Scripts de control desde Termux nativo"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r _CONF2 < /dev/tty
[ "$_CONF2" != "s" ] && [ "$_CONF2" != "S" ] && { echo "Cancelado."; exit 0; }

# ── PASO P1 — Verificar proot-distro y rootfs ────────────────
titulo "PASO P1 — Verificando entorno proot"

if ! command -v proot-distro &>/dev/null; then
  info "Instalando proot-distro..."
  pkg install proot-distro proot tmux curl wget tar xz-utils git -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    error "No se pudo instalar proot-distro"
fi

if [ -z "$DISTRO_NAME" ]; then
  warn "Rootfs Debian no encontrado"
  echo ""
  echo -e "  ${GREEN}[1]${NC} Desde GitHub Releases  (~5-10 min)"
  echo -e "  ${GREEN}[2]${NC} Instalación limpia      (~15-25 min)"
  echo -e "  ${GREEN}[b]${NC} Cancelar"
  echo ""; echo -n "  Opción: "
  read -r _ROOTFS_OPT < /dev/tty

  case "$_ROOTFS_OPT" in
    1)
      [ ! -f "$HOME/restore.sh" ] && \
        curl -fsSL "https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/restore.sh" \
          -o "$HOME/restore.sh" && chmod +x "$HOME/restore.sh"
      bash "$HOME/restore.sh" --module proot-base --source github || \
        error "Falló la restauración del rootfs"
      ;;
    2)
      proot-distro list 2>/dev/null | grep -qE "^\s*\*?\s*debian\b" || {
        _OUT=$(proot-distro install debian 2>&1); _RC=$?
        echo "$_OUT" | grep -q "already exists" || \
          { [ $_RC -ne 0 ] && { echo "$_OUT"; error "No se pudo instalar Debian"; }; }
      }
      ;;
    b|B|"") error "Cancelado" ;;
    *) error "Opción inválida" ;;
  esac
  sleep 2; _detect_rootfs
  [ -z "$DISTRO_NAME" ] && error "Rootfs no disponible tras instalación"
  log "Rootfs listo: $DISTRO_NAME"
else
  log "Rootfs encontrado: $DISTRO_NAME"
fi

# ── PASO P2 — NVM + Node 22 ──────────────────────────────────
titulo "PASO P2 — NVM + Node 22 en proot"

if check_done "p_openclaw_nvm"; then
  log "NVM + Node 22 ya configurados [checkpoint]"
else
  _NVM_EXISTS=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; [ -s "/root/.nvm/nvm.sh" ] && echo "yes" || echo "no"' 2>/dev/null)

  if [ "$_NVM_EXISTS" != "yes" ]; then
    info "Instalando NVM en proot..."
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'export HOME=/root
       curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' || \
      error "No se pudo instalar NVM"
    log "NVM instalado"
  else
    log "NVM ya existe en proot"
  fi

  _N22=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; export NVM_DIR="/root/.nvm"
     [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     node --version 2>/dev/null | grep -c "^v22"' 2>/dev/null)

  if [ "$_N22" != "1" ]; then
    info "Instalando Node 22 via NVM..."
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'export HOME=/root; export NVM_DIR="/root/.nvm"
       [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" || exit 1
       nvm install 22 && nvm use 22 && nvm alias default 22' || \
      error "No se pudo instalar Node 22"
    log "Node 22 instalado"
  else
    log "Node 22 ya activo"
  fi
  mark_done "p_openclaw_nvm"
fi

# ── PASO P3 — Shim de red ────────────────────────────────────
titulo "PASO P3 — Shim de red Android"

if check_done "p_openclaw_shim"; then
  log "Shim ya creado [checkpoint]"
else
  proot-distro login "$DISTRO_NAME" -- bash -c \
'cat > /root/openclaw-shim.cjs << '"'"'EOF'"'"'
const os = require('"'"'os'"'"');
os.networkInterfaces = () => ({
  lo: [{ address: '"'"'127.0.0.1'"'"', netmask: '"'"'255.0.0.0'"'"', family: '"'"'IPv4'"'"',
    mac: '"'"'00:00:00:00:00:00'"'"', internal: true, cidr: '"'"'127.0.0.1/8'"'"' }]
});
EOF' || error "No se pudo crear el shim"
  log "Shim creado: /root/openclaw-shim.cjs"
  mark_done "p_openclaw_shim"
fi

# ── PASO P4 — Instalar openclaw en proot ─────────────────────
titulo "PASO P4 — Instalando OpenClaw en proot"

if check_done "p_openclaw_install"; then
  log "OpenClaw ya instalado [checkpoint]"
else
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; export NVM_DIR="/root/.nvm"
     [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
     npm install -g openclaw@latest 2>&1 | tail -5' || \
    error "No se pudo instalar OpenClaw en proot"

  _CL_OK=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; export NVM_DIR="/root/.nvm"
     [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     command -v openclaw && echo "ok" || echo "fail"' 2>/dev/null | tail -1)
  [ "$_CL_OK" != "ok" ] && error "OpenClaw no quedó accesible en proot"

  _CL_VER_P2=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; export NVM_DIR="/root/.nvm"
     [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     openclaw --version 2>/dev/null | head -1' 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9.]+' | head -1)
  log "OpenClaw ${_CL_VER_P2:-?} instalado en proot"
  mark_done "p_openclaw_install"
fi

# ── PASO P5 — Setup wizard ───────────────────────────────────
titulo "PASO P5 — Setup inicial"

if check_done "p_openclaw_setup"; then
  log "Setup ya ejecutado [checkpoint]"
else
  echo ""
  echo -e "  ${YELLOW}IMPORTANTE:${NC}"
  echo -e "  ▸ Ollama debe estar corriendo en Termux (otra sesión)"
  echo -e "  ▸ El wizard tarda 1-3 min en ARM64 — es normal"
  echo -e "  ▸ Selecciona: Ollama → http://127.0.0.1:11434"
  echo ""
  echo -n "  ¿Ejecutar wizard ahora? (s/n): "
  read -r _WIZ < /dev/tty
  if [ "$_WIZ" = "s" ] || [ "$_WIZ" = "S" ]; then
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'export HOME=/root; export NVM_DIR="/root/.nvm"
       [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
       export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
       openclaw setup --wizard' < /dev/tty
    _TK=$(proot-distro login "$DISTRO_NAME" -- bash -c \
      "python3 -c \"import json; d=json.load(open('/root/.openclaw/openclaw.json')); print(d['gateway']['auth']['token'])\"" \
      2>/dev/null)
    [ -n "$_TK" ] && log "Setup completado — token generado" || \
      warn "Token no detectado — re-ejecuta desde el menú [1] OpenClaw → [6]"
  else
    warn "Wizard omitido — ejecuta después desde el menú"
  fi
  mark_done "p_openclaw_setup"
fi

# ── PASO P6 — .bashrc en proot ───────────────────────────────
titulo "PASO P6 — Entorno proot (.bashrc)"

if check_done "p_openclaw_proot_bashrc"; then
  log "Entorno proot ya configurado [checkpoint]"
else
  proot-distro login "$DISTRO_NAME" -- bash -c \
'grep -v "NVM_DIR\|openclaw-shim\|openclaw aliases\|openclaw-start\|claw-status\|claw-logs" \
  /root/.bashrc > /root/.bashrc.tmp 2>/dev/null && mv /root/.bashrc.tmp /root/.bashrc
cat >> /root/.bashrc << '"'"'BASHRC'"'"'

# ════════════════════════════════
#  OpenClaw · NVM + shim
# ════════════════════════════════
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
alias openclaw-start='"'"'openclaw gateway --bind loopback'"'"'
alias claw-status='"'"'ps aux | grep openclaw'"'"'
BASHRC'
  log ".bashrc del proot configurado"
  mark_done "p_openclaw_proot_bashrc"
fi

# ── PASO P7 — Scripts de control desde Termux ────────────────
titulo "PASO P7 — Scripts de control Termux"

if check_done "p_openclaw_scripts"; then
  log "Scripts ya creados [checkpoint]"
else
  mkdir -p "$HOME/scripts/openclaw"
  _DN="$DISTRO_NAME"

  cat > "$HOME/scripts/openclaw/openclaw_start.sh" << PSCRIPT
#!/data/data/com.termux/files/usr/bin/bash
PORT=18789
DISTRO_NAME="${_DN}"
curl -sf http://127.0.0.1:\$PORT &>/dev/null && {
  echo -e "\033[0;32m[OK]\033[0m Gateway ya corriendo :\${PORT}"; exit 0; }
echo -e "\033[0;36m[+] Iniciando OpenClaw proot...\033[0m"
proot-distro login "\$DISTRO_NAME" -- bash -c \
  'export HOME=/root; export NVM_DIR="/root/.nvm"
   [ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
   export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
   openclaw gateway --bind loopback' > "\$HOME/.openclaw_gateway.log" 2>&1 &
echo \$! > "\$HOME/.openclaw_gateway.pid"
TRIES=0
while [ \$TRIES -lt 30 ]; do
  sleep 2; curl -sf http://127.0.0.1:\$PORT &>/dev/null && break
  TRIES=\$((TRIES+1)); echo -n "."
done; echo ""
curl -sf http://127.0.0.1:\$PORT &>/dev/null \
  && echo -e "\033[0;32m[OK]\033[0m Gateway activo :\${PORT}" \
  || echo -e "\033[0;31m[ERROR]\033[0m No respondió — cat ~/.openclaw_gateway.log"
PSCRIPT
  chmod +x "$HOME/scripts/openclaw/openclaw_start.sh"

  cat > "$HOME/scripts/openclaw/openclaw_stop.sh" << PSCRIPT
#!/data/data/com.termux/files/usr/bin/bash
DISTRO_NAME="${_DN}"
[ -f "\$HOME/.openclaw_gateway.pid" ] && {
  kill "\$(cat \$HOME/.openclaw_gateway.pid)" 2>/dev/null; rm -f "\$HOME/.openclaw_gateway.pid"; }
pkill -f "openclaw gateway" 2>/dev/null || true
proot-distro login "\$DISTRO_NAME" -- bash -c \
  'pkill -f "openclaw gateway" 2>/dev/null || true' 2>/dev/null || true
sleep 1
curl -sf http://127.0.0.1:18789 &>/dev/null \
  && echo -e "\033[1;33m[AVISO]\033[0m Aún responde — espera" \
  || echo -e "\033[0;32m[OK]\033[0m Gateway detenido"
PSCRIPT
  chmod +x "$HOME/scripts/openclaw/openclaw_stop.sh"
  log "Scripts de control creados"
  mark_done "p_openclaw_scripts"
fi

# ── PASO P8 — Aliases Termux ─────────────────────────────────
titulo "PASO P8 — Aliases en Termux"

if check_done "p_openclaw_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  grep -v "openclaw-start\|openclaw-stop\|openclaw-status\|openclaw-token\|openclaw-tui" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << ALIASES

# ════════════════════════════════
#  OpenClaw proot · aliases Termux
# ════════════════════════════════
alias openclaw-start='bash ~/scripts/openclaw/openclaw_start.sh'
alias openclaw-stop='bash ~/scripts/openclaw/openclaw_stop.sh'
alias openclaw-status='curl -sf http://127.0.0.1:18789 &>/dev/null && echo "activo :18789" || echo "detenido"'
alias openclaw-tui='proot-distro login ${DISTRO_NAME} -- bash -c "source ~/.bashrc 2>/dev/null; openclaw tui"'
ALIASES

  log "Aliases agregados"
  mark_done "p_openclaw_aliases"
fi

# ── PASO P9 — Registry ───────────────────────────────────────
titulo "PASO P9 — Registry"

_CL_VER_PF=$(proot-distro login "$DISTRO_NAME" -- bash -c \
  'export HOME=/root; export NVM_DIR="/root/.nvm"
   [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
   openclaw --version 2>/dev/null | head -1' 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9.]+' | head -1)
[ -z "$_CL_VER_PF" ] && _CL_VER_PF="unknown"
update_registry "$_CL_VER_PF" "proot_debian"

titulo "INSTALACIÓN PROOT COMPLETADA ✓"
echo "  Versión:  ${_CL_VER_PF}"
echo "  Puerto:   $PORT"
echo "  Entorno:  proot Debian (Node 22 via NVM)"
echo "  Distro:   ${DISTRO_NAME}"
echo ""
echo "  COMANDOS:"
echo "  openclaw-start  → iniciar gateway"
echo "  openclaw-stop   → detener gateway"
echo "  openclaw-status → verificar estado"
echo "  openclaw-tui    → interfaz TUI"
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para activar aliases${NC}"
echo ""
rm -f "$CHECKPOINT_PROOT"

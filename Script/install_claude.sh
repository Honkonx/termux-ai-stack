#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  android-server · install_claude.sh
#  Instala Claude Code en Termux nativo (ARM64, sin root)
#
#  USO STANDALONE:
#    bash install_claude.sh
#
#  QUÉ HACE:
#    ✅ Actualiza Termux (solo si no lo hizo el maestro)
#    ✅ Verifica/instala Node.js >= 18
#    ✅ Limpia caché npm antes de instalar (evita instalación vacía)
#    ✅ Instala @anthropic-ai/claude-code vía npm
#    ✅ Crea alias funcional (workaround ARM64 — sin binario nativo)
#    ✅ Escribe estado al registry ~/.android_server_registry
#    ✅ Agrega aliases a .bashrc
#
#  NOTA TÉCNICA ARM64:
#    Claude Code incluye binarios x86/x64 incompatibles con ARM64.
#    Solución: alias que invoca cli.js directamente con node.
#    Probado en POCO F5 · Android 15 · ARM64.
#
#  VERSIÓN: 2.7.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }

# ── Archivos de estado ────────────────────────────────────────
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_claude_checkpoint"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Helper: encontrar cli.js ──────────────────────────────────
find_cli() {
  local npm_root
  npm_root=$(npm root -g 2>/dev/null)
  echo "${npm_root}/@anthropic-ai/claude-code/cli.js"
}

# ── Función: actualizar registry ─────────────────────────────
update_registry() {
  local version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)

  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"

  local tmp="$REGISTRY.tmp"
  grep -v "^claude_code\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"

  cat >> "$tmp" << EOF
claude_code.installed=true
claude_code.version=$version
claude_code.install_date=$date_now
claude_code.commands=claude,claude -p,claude --continue,claude --version
claude_code.port=none
claude_code.location=termux_native
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → $REGISTRY"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   android-server · Claude Code Installer   ║
  ║   Termux ARM64 · sin root                  ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado ───────────────────────────
CLI_PATH=$(find_cli)

if [ -f "$CLI_PATH" ] && [ -s "$CLI_PATH" ]; then
  CURRENT_VERSION=$(node "$CLI_PATH" --version 2>/dev/null | head -1)
  echo -e "${GREEN}  ✓ Claude Code ya está instalado${NC}"
  echo -e "  Versión actual: ${CYAN}${CURRENT_VERSION}${NC}"
  echo ""
  read -r -p "  ¿Reinstalar/actualizar? (s/n): " REINSTALL
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
fi

echo ""
echo "  Este script instalará:"
echo "  ▸ Node.js (si no está o versión < 18)"
echo "  ▸ @anthropic-ai/claude-code vía npm"
echo "  ▸ Alias 'claude' con workaround ARM64"
echo "  ▸ Registro en ~/.android_server_registry"
echo ""
read -r -p "  ¿Continuar? (s/n): " CONFIRM
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 1 — Actualizar Termux (condicional)
# ============================================================
titulo "PASO 1 — Verificando Termux"

if [ -n "$ANDROID_SERVER_READY" ]; then
  log "Termux ya preparado por el maestro [skip]"
elif check_done "termux_update"; then
  log "Termux ya verificado [checkpoint]"
else
  info "Modo standalone — actualizando Termux..."

  MIRRORS=(
    "https://packages.termux.dev/apt/termux-main"
    "https://mirror.accum.se/mirror/termux.dev/apt/termux-main"
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
  )

  try_update() {
    pkg update -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      2>&1
  }

  set_mirror() {
    echo "deb $1 stable main" > "$TERMUX_PREFIX/etc/apt/sources.list"
    info "Mirror: $1"
  }

  OUT=$(try_update)
  if echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
    warn "Mirror roto — probando alternativas..."
    OK=0
    for m in "${MIRRORS[@]}"; do
      set_mirror "$m"
      OUT=$(try_update)
      if ! echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
        log "Mirror OK: $m"; OK=1; break
      fi
    done
    [ "$OK" = "0" ] && error "Todos los mirrors fallaron. Verifica tu conexión."
  fi

  for dep in curl wget git; do
    if ! command -v "$dep" &>/dev/null; then
      info "Instalando $dep..."
      pkg install "$dep" -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>/dev/null
    fi
  done

  log "Termux actualizado"
  mark_done "termux_update"
fi

# ============================================================
# PASO 2 — Verificar / Instalar Node.js
# ============================================================
titulo "PASO 2 — Node.js"

if check_done "nodejs"; then
  log "Node.js ya verificado [checkpoint]"
else
  if command -v node &>/dev/null; then
    NODE_VER=$(node --version 2>/dev/null | sed 's/v//' | cut -d'.' -f1)
    if [ "$NODE_VER" -ge 18 ] 2>/dev/null; then
      # Node v18+ es compatible con @anthropic-ai/claude-code@2.1.111
      # Confirmado: v24 funciona correctamente con cli.js de esa versión
      log "Node.js $(node --version) ✓ (compatible con Claude Code)"
    else
      warn "Node.js $(node --version) — versión < 18, actualizando..."
      pkg install nodejs-lts -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || \
        error "Error instalando nodejs-lts. Verifica conexión."
      log "Node.js actualizado: $(node --version)"
    fi
  else
    info "Node.js no encontrado — instalando nodejs-lts..."
    pkg install nodejs-lts -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      error "Error instalando nodejs-lts. Verifica conexión."
    log "Node.js instalado: $(node --version)"
  fi

  command -v npm &>/dev/null || error "npm no encontrado. Reinstala con: pkg install nodejs"
  log "npm $(npm --version) ✓"
  mark_done "nodejs"
fi

# ============================================================
# PASO 3 — Instalar Claude Code
# ============================================================
titulo "PASO 3 — Instalando Claude Code"

# Validar checkpoint: aunque diga "hecho", verificar que cli.js existe y es JS válido
# Si el checkpoint está sucio (instalación fallida anterior), lo limpiamos
_CLI_CHECK=$(find_cli)
if check_done "claude_npm" && [ -f "$_CLI_CHECK" ] && [ -s "$_CLI_CHECK" ] &&    node "$_CLI_CHECK" --version 2>&1 | grep -qv "SyntaxError"; then
  log "Claude Code ya instalado [checkpoint]"
else
  # Checkpoint inválido — limpiar y reinstalar
  if check_done "claude_npm"; then
    warn "Checkpoint claude_npm inválido (cli.js ausente o corrompido) — reinstalando..."
    sed -i '/^claude_npm$/d' "$CHECKPOINT" 2>/dev/null || true
  fi
  NPM_ROOT=$(npm root -g 2>/dev/null)
  CLAUDE_DIR="$NPM_ROOT/@anthropic-ai/claude-code"

  # Versión confirmada funcional en Termux ARM64 (Bionic libc) con Node v18+
  # Las versiones latest (v2.2+) usan binario nativo glibc — no corren en Bionic
  # v2.1.111 incluye cli.js puro JS — compatible con cualquier Node >= 18
  CLAUDE_VERSION_FALLBACK="2.1.111"

  # Limpiar instalación anterior
  if [ -d "$CLAUDE_DIR" ]; then
    warn "Limpiando instalación anterior..."
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
  fi

  npm cache clean --force 2>/dev/null || true
  echo ""

  # ── Estrategia para Termux ARM64 (Bionic libc) ───────────────
  # Las versiones latest de claude-code usan un binario nativo
  # compilado con glibc que no existe en Termux (usa Bionic).
  # Usamos directamente la versión fallback que incluye cli.js.
  # ─────────────────────────────────────────────────────────────

  CLAUDE_OK=false

  # Intento 1: latest — verifica si incluye cli.js (puede funcionar en futuras versiones)
  info "Intento 1/2: probando versión latest..."
  npm install -g @anthropic-ai/claude-code 2>&1 | tail -3
  echo ""

  CLI_PATH_NEW=$(find_cli)
  if [ -f "$CLI_PATH_NEW" ] && [ -s "$CLI_PATH_NEW" ]; then
    CLAUDE_OK=true
    log "Versión latest instalada con cli.js ✓"
  fi

  # Intento 2: fallback a v2.1.111 (última con cli.js funcional en Termux)
  if [ "$CLAUDE_OK" = "false" ]; then
    warn "Latest no incluye cli.js — usando v${CLAUDE_VERSION_FALLBACK} (confirmada en Termux ARM64 + Node v24)..."
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
    npm cache clean --force 2>/dev/null || true
    echo ""

    info "Intento 2/2: instalando v${CLAUDE_VERSION_FALLBACK}..."
    npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION_FALLBACK} 2>&1 | tail -3
    echo ""

    CLI_PATH_NEW=$(find_cli)
    if [ -f "$CLI_PATH_NEW" ] && [ -s "$CLI_PATH_NEW" ]; then
      CLAUDE_OK=true
      log "v${CLAUDE_VERSION_FALLBACK} instalada con cli.js ✓"
    fi
  fi

  if [ "$CLAUDE_OK" = "false" ]; then
    echo ""
    echo -e "${RED}[ERROR]${NC} Claude Code no instaló correctamente en ambos intentos"
    echo ""
    echo "  Diagnóstico:"
    echo "  npm root -g  → $NPM_ROOT"
    echo "  Espacio      → $(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
    echo "  Node         → $(node --version 2>/dev/null)"
    echo ""
    echo "  Prueba manualmente:"
    echo "  npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION_FALLBACK}"
    exit 1
  fi

  mark_done "claude_npm"
fi

# ============================================================
# PASO 4 — Crear wrapper ejecutable + alias (workaround ARM64)
# ============================================================
titulo "PASO 4 — Configurando comando claude"

if check_done "claude_alias"; then
  log "Comando claude ya configurado [checkpoint]"
else
  CLI_FINAL=$(find_cli)

  if [ ! -f "$CLI_FINAL" ]; then
    error "cli.js no existe en $CLI_FINAL — reinstala desde el paso 3"
  fi

  # ── Wrapper ejecutable en PREFIX/bin (activo SIN reabrir Termux) ─
  # $TERMUX_PREFIX/bin ya está en PATH permanentemente — no requiere
  # source ni reabrir sesión. Funciona inmediatamente tras instalar.
  WRAPPER="$TERMUX_PREFIX/bin/claude"
  cat > "$WRAPPER" << WRAPPER_SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
exec node "${CLI_FINAL}" "\$@"
WRAPPER_SCRIPT
  chmod +x "$WRAPPER"
  log "Wrapper ejecutable → $WRAPPER"

  # ── Alias en .bashrc (respaldo para sesiones interactivas) ───────
  BASHRC="$HOME/.bashrc"
  if [ -f "$BASHRC" ]; then
    grep -v "alias claude=" "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
  fi

  cat >> "$BASHRC" << ALIASES

# ════════════════════════════════
#  Claude Code · alias ARM64
# ════════════════════════════════
alias claude='node ${CLI_FINAL}'
alias claude-update='npm cache clean --force && npm install -g @anthropic-ai/claude-code && echo "Claude Code actualizado"'
ALIASES

  log "Alias respaldo en .bashrc configurado"
  source "$BASHRC" 2>/dev/null || true

  mark_done "claude_alias"
fi

# ============================================================
# PASO 5 — Actualizar registry
# ============================================================
titulo "PASO 5 — Actualizando registry"

CLI_REG=$(find_cli)
VERSION_REG=$(node "$CLI_REG" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$VERSION_REG" ] && VERSION_REG="unknown"

update_registry "$VERSION_REG"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

CLI_SHOW=$(find_cli)
VERSION_SHOW=$(node "$CLI_SHOW" --version 2>/dev/null | head -1)

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║     Claude Code instalado con éxito ✓       ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  Versión:   ${VERSION_SHOW}"
echo "  Node.js:   $(node --version)"
echo ""
echo "  COMANDOS:"
echo "  claude                  → agente interactivo"
echo "  claude --version        → ver versión"
echo "  claude -p \"instrucción\" → modo directo"
echo "  claude --continue       → continuar sesión"
echo "  claude-update           → actualizar"
echo ""
echo -e "${YELLOW}  IMPORTANTE:${NC}"
echo "  1. Cierra y reabre Termux para activar el alias"
echo "  2. En primer uso, acepta la autenticación OAuth"
echo "  3. Requiere cuenta Claude Pro o superior"
echo ""
if [ -z "$ANDROID_SERVER_READY" ]; then
  echo -e "${CYAN}  TIP: ejecuta instalar.sh para aplicar tema visual${NC}"
  echo -e "${CYAN}       y configurar las teclas rápidas de Termux${NC}"
  echo ""
fi
echo -e "${CYAN}  → Cierra y reabre Termux, luego escribe: claude${NC}"
echo ""

rm -f "$CHECKPOINT"

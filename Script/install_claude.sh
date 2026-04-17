#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  android-server · install_claude.sh
#  Instala Claude Code en Termux nativo (ARM64, sin root)
#
#  USO STANDALONE:
#    bash install_claude.sh
#
#  USO VÍA MAESTRO (cuando repo sea público):
#    bash <(curl -fsSL https://raw.githubusercontent.com/TU_USUARIO/android-server/main/modules/install_claude.sh)
#
#  QUÉ HACE:
#    ✅ Actualiza Termux (solo si no lo hizo el maestro)
#    ✅ Verifica/instala Node.js >= 18
#    ✅ Instala @anthropic-ai/claude-code vía npm
#    ✅ Crea alias funcional (workaround ARM64)
#    ✅ Escribe estado al registry ~/.android_server_registry
#    ✅ Agrega aliases a .bashrc
#
#  RESPONSABILIDAD DEL MAESTRO (instalar.sh):
#    ⏭  Tema visual (GitHub Dark + JetBrains Mono)
#    ⏭  termux.properties + extra-keys
#    ⏭  pkg update base → exporta ANDROID_SERVER_READY=1
#
#  NOTAS TÉCNICAS:
#    - Claude Code trae binarios x86/x64 incompatibles con ARM64
#    - Solución: alias apuntando directamente a cli.js con Node.js
#    - Funciona 100% — probado en POCO F5, Android 15, Node.js 25.x
#
#  VERSIÓN: 1.2.0 | Abril 2026
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

# ── Función: actualizar registry ─────────────────────────────
update_registry() {
  local version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)

  # Crear registry si no existe
  if [ ! -f "$REGISTRY" ]; then
    echo '{}' > "$REGISTRY"
  fi

  # Entrada para claude_code (formato simple key=value por línea)
  # Usamos formato propio — no depende de jq (no siempre está en Termux)
  local tmp="$REGISTRY.tmp"
  
  # Eliminar entrada anterior si existe
  grep -v "^claude_code\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  
  # Agregar entrada actualizada
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
  ║   android-server · Claude Code Installer    ║
  ║   Termux ARM64 · sin root                   ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado ───────────────────────────
CLI_PATH="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/cli.js"

if [ -f "$CLI_PATH" ]; then
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

  OUT=$(pkg update -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>&1)

  if echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
    warn "Mirror roto — probando alternativas..."
    OK=0
    for m in "${MIRRORS[@]}"; do
      echo "deb $m stable main" > "$TERMUX_PREFIX/etc/apt/sources.list"
      OUT=$(pkg update -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>&1)
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
      log "Node.js $(node --version) ya instalado ✓"
    else
      warn "Node.js $(node --version) — versión < 18, actualizando..."
      pkg install nodejs -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
      log "Node.js actualizado: $(node --version)"
    fi
  else
    info "Node.js no encontrado — instalando..."
    pkg install nodejs -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      error "Error instalando Node.js. Verifica conexión."
    log "Node.js instalado: $(node --version)"
  fi

  # Verificar npm
  if ! command -v npm &>/dev/null; then
    error "npm no encontrado tras instalar nodejs. Reinstala con: pkg install nodejs"
  fi
  log "npm $(npm --version) disponible"
  mark_done "nodejs"
fi

# ============================================================
# PASO 3 — Instalar Claude Code
# ============================================================
titulo "PASO 3 — Instalando Claude Code"

if check_done "claude_npm"; then
  log "Claude Code ya instalado vía npm [checkpoint]"
else
  info "Ejecutando: npm install -g @anthropic-ai/claude-code"
  info "Los warnings sobre binarios incompatibles son normales en ARM64..."
  info "Esto puede tardar 1-3 minutos — espera hasta ver [OK]..."
  echo ""

  # Fix v1.2.0: NO filtrar con pipe — rompe el exit code de npm
  npm install -g @anthropic-ai/claude-code
  NPM_EXIT=$?

  CLI_PATH_NEW="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/cli.js"

  if [ ! -f "$CLI_PATH_NEW" ]; then
    warn "cli.js no encontrado tras primera instalación — reintentando..."
    echo ""
    npm install -g @anthropic-ai/claude-code --prefer-online
    CLI_PATH_NEW="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/cli.js"
  fi

  if [ ! -f "$CLI_PATH_NEW" ]; then
    echo ""
    echo -e "${RED}[ERROR]${NC} cli.js no encontrado tras 2 intentos."
    echo ""
    echo "  Posibles causas:"
    echo "  1. Error de red — verifica conexión y reintenta"
    echo "  2. npm global sin espacio en disco"
    echo "  3. Instalación parcial — limpia con:"
    echo "     npm uninstall -g @anthropic-ai/claude-code"
    echo "     npm install -g @anthropic-ai/claude-code"
    echo ""
    df -h "$HOME" 2>/dev/null | tail -1
    echo ""
    exit 1
  fi

  log "cli.js encontrado: $CLI_PATH_NEW"

  TEST_OUT=$(node "$CLI_PATH_NEW" --version 2>/dev/null | head -1)
  if [ -z "$TEST_OUT" ]; then
    warn "No se pudo obtener versión — puede funcionar igual"
  else
    log "Prueba OK: $TEST_OUT"
  fi

  mark_done "claude_npm"
fi

# ============================================================
# PASO 4 — Crear alias funcional (workaround ARM64)
# ============================================================
titulo "PASO 4 — Configurando alias"

if check_done "claude_alias"; then
  log "Alias ya configurado [checkpoint]"
else
  CLI_FINAL="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/cli.js"
  
  if [ ! -f "$CLI_FINAL" ]; then
    error "cli.js no existe en $CLI_FINAL — instala primero con npm (paso 3)"
  fi

  BASHRC="$HOME/.bashrc"
  
  # Eliminar aliases anteriores de claude para evitar duplicados
  if [ -f "$BASHRC" ]; then
    grep -v "alias claude=" "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
  fi

  # Agregar alias permanente
  cat >> "$BASHRC" << ALIASES

# ════════════════════════════════
#  Claude Code · alias ARM64
# ════════════════════════════════
alias claude='node ${CLI_FINAL}'
alias claude-update='npm install -g @anthropic-ai/claude-code && echo "Claude Code actualizado"'
ALIASES

  log "Alias 'claude' agregado a ~/.bashrc"
  log "Alias 'claude-update' agregado a ~/.bashrc"
  
  # Activar en sesión actual
  # shellcheck disable=SC1090
  source "$BASHRC" 2>/dev/null || true
  
  mark_done "claude_alias"
fi

# ============================================================
# PASO 5 — Actualizar registry
# ============================================================
titulo "PASO 5 — Actualizando registry"

CLI_REGISTRY="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/cli.js"
VERSION_REGISTRY=$(node "$CLI_REGISTRY" --version 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1)
[ -z "$VERSION_REGISTRY" ] && VERSION_REGISTRY="unknown"

update_registry "$VERSION_REGISTRY"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

CLI_SHOW="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code/cli.js"
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

# Limpiar checkpoint (instalación exitosa)
rm -f "$CHECKPOINT"

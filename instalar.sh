#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · instalar.sh
#  Script maestro — setup inicial completo
#
#  USO:
#    bash <(curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/instalar.sh)
#
#  O descargarlo primero:
#    curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/instalar.sh -o instalar.sh
#    bash instalar.sh
#
#  QUÉ HACE:
#    ✅ Permisos de almacenamiento
#    ✅ pkg update + dependencias base (una sola vez para todos los módulos)
#    ✅ Tema visual GitHub Dark + JetBrains Mono
#    ✅ termux.properties + extra-keys del stack completo
#    ✅ Descarga menu.sh desde el repo
#    ✅ Configura .bashrc para auto-ejecutar menu.sh
#    ✅ Exporta ANDROID_SERVER_READY=1 (los módulos saltan pkg update)
#    ✅ Menú interactivo para instalar módulos
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 1.0.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"
export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib"

# ── URLs del repo ─────────────────────────────────────────────
REPO_RAW="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script"
REPO_URL="https://github.com/Honkonx/termux-ai-stack"

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
CHECKPOINT="$HOME/.instalar_checkpoint"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Cabecera ─────────────────────────────────────────────────
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
  ║        Android ARM64 · sin root                  ║
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
  echo ""
fi

echo "  Este script configura:"
echo "  ▸ Dependencias base de Termux"
echo "  ▸ Tema visual (GitHub Dark + JetBrains Mono)"
echo "  ▸ Teclas rápidas del stack completo"
echo "  ▸ Dashboard menu.sh (se abre al iniciar Termux)"
echo "  ▸ Módulos opcionales: n8n · Claude Code · Ollama · Expo"
echo ""
read -r -p "  ¿Continuar? (s/n): " CONFIRMAR
[ "$CONFIRMAR" != "s" ] && [ "$CONFIRMAR" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 0 — Permiso de almacenamiento
# ============================================================
titulo "PASO 0 — Permiso de almacenamiento"

if check_done "storage"; then
  log "Permiso de almacenamiento ya configurado [checkpoint]"
else
  if [ -d "/sdcard/Download" ]; then
    log "Acceso a /sdcard ya disponible"
    mark_done "storage"
  else
    info "Solicitando permiso de almacenamiento..."
    info "→ Acepta el diálogo que aparecerá en pantalla"
    termux-setup-storage
    sleep 4
    if [ -d "/sdcard/Download" ]; then
      log "Acceso a /sdcard confirmado"
      mark_done "storage"
    else
      warn "Acepta el permiso y re-ejecuta el script"
      exit 1
    fi
  fi
fi

# ============================================================
# PASO 1 — Actualizar Termux + dependencias base
# ============================================================
titulo "PASO 1 — Actualizando Termux"

if check_done "termux_base"; then
  log "Termux ya actualizado [checkpoint]"
else
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

  pkg upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    2>/dev/null || warn "pkg upgrade tuvo advertencias (no fatal)"

  # Dependencias base necesarias para todos los módulos
  info "Instalando dependencias base..."
  pkg install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    curl wget git tmux nano unzip \
    proot proot-distro busybox iproute2 \
    2>/dev/null || warn "Algunos paquetes tuvieron advertencias"

  for p in curl wget git tmux; do
    command -v "$p" &>/dev/null && log "$p ✓" || warn "$p no instaló"
  done

  mark_done "termux_base"
  log "Termux actualizado"
fi

# ── Exportar señal para módulos ───────────────────────────────
# Los módulos que se llamen desde este script saltarán pkg update
export ANDROID_SERVER_READY=1

# ============================================================
# PASO 2 — Tema visual (GitHub Dark + JetBrains Mono)
# ============================================================
titulo "PASO 2 — Aplicando tema visual"

if check_done "tema"; then
  log "Tema ya aplicado [checkpoint]"
else
  TERMUX_CONFIG="$HOME/.termux"
  mkdir -p "$TERMUX_CONFIG"

  cat > "$TERMUX_CONFIG/colors.properties" << 'COLORS'
# termux-ai-stack — Tema GitHub Dark
background=#0d1117
foreground=#e6edf3
cursor=#58a6ff
color0=#161b22
color8=#484f58
color1=#f85149
color9=#ff7b72
color2=#3fb950
color10=#56d364
color3=#e3b341
color11=#f0c94d
color4=#388bfd
color12=#79c0ff
color5=#bc8cff
color13=#d2a8ff
color6=#79c0ff
color14=#a5d6ff
color7=#b1bac4
color15=#e6edf3
COLORS
  log "colors.properties aplicado (GitHub Dark)"

  # Fuente JetBrains Mono
  FONT_FILE="$TERMUX_CONFIG/font.ttf"
  if [ -f "$FONT_FILE" ]; then
    log "Fuente ya existe — omitiendo descarga"
  else
    info "Descargando JetBrains Mono..."
    FONT_URL="https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
    FONT_TMP="$HOME/jbmono.zip"
    wget -q --show-progress "$FONT_URL" -O "$FONT_TMP" 2>/dev/null || \
      curl -L --progress-bar "$FONT_URL" -o "$FONT_TMP" 2>/dev/null
    if [ -f "$FONT_TMP" ] && [ -s "$FONT_TMP" ]; then
      unzip -q "$FONT_TMP" "fonts/ttf/JetBrainsMono-Regular.ttf" \
        -d "$HOME/jbmono_tmp" 2>/dev/null
      mv "$HOME/jbmono_tmp/fonts/ttf/JetBrainsMono-Regular.ttf" "$FONT_FILE" 2>/dev/null || true
      rm -rf "$HOME/jbmono.zip" "$HOME/jbmono_tmp" 2>/dev/null
    fi
    [ -f "$FONT_FILE" ] && log "JetBrains Mono instalada" || \
      warn "No se pudo descargar la fuente — se usará la fuente por defecto"
  fi

  # termux.properties — extra-keys del stack completo
  cat > "$TERMUX_CONFIG/termux.properties" << 'PROPS'
# termux-ai-stack — Configuración Termux
extra-keys = [['ESC','TAB','CTRL','ALT','|','/','UP','DOWN'],['n8n-start','n8n-url','claude','ollama-start','menu','help','LEFT','RIGHT']]
bell-character=ignore
PROPS
  log "termux.properties configurado (extra-keys del stack)"

  command -v termux-reload-settings &>/dev/null && \
    termux-reload-settings 2>/dev/null && \
    log "Tema aplicado — reinicia Termux para verlo" || \
    log "Tema listo — reinicia Termux para verlo"

  mark_done "tema"
fi

# ============================================================
# PASO 3 — Descargar menu.sh
# ============================================================
titulo "PASO 3 — Descargando dashboard (menu.sh)"

if check_done "menu_download"; then
  log "menu.sh ya descargado [checkpoint]"
else
  info "Descargando menu.sh desde el repo..."
  curl -fsSL "$REPO_RAW/menu.sh" -o "$HOME/menu.sh" 2>/dev/null || \
    wget -q "$REPO_RAW/menu.sh" -O "$HOME/menu.sh" 2>/dev/null

  if [ -f "$HOME/menu.sh" ] && [ -s "$HOME/menu.sh" ]; then
    chmod +x "$HOME/menu.sh"
    log "menu.sh descargado y listo"
    mark_done "menu_download"
  else
    warn "No se pudo descargar menu.sh — se creará una versión básica"
    # Versión mínima de fallback
    cat > "$HOME/menu.sh" << 'MENU'
#!/data/data/com.termux/files/usr/bin/bash
echo ""
echo "╔══════════════════════════════════════╗"
echo "║     termux-ai-stack · menu          ║"
echo "╠══════════════════════════════════════╣"
echo "║  [1] n8n-start                      ║"
echo "║  [2] claude                         ║"
echo "║  [3] ollama-start                   ║"
echo "║  [h] help                           ║"
echo "║  [q] salir al shell                 ║"
echo "╚══════════════════════════════════════╝"
echo ""
read -r -p "  Opción: " OPT
case "$OPT" in
  1) n8n-start ;;
  2) claude ;;
  3) ollama-start ;;
  h) help ;;
  q) exit 0 ;;
esac
MENU
    chmod +x "$HOME/menu.sh"
    warn "menu.sh básico creado — actualiza desde el repo cuando tengas conexión"
    mark_done "menu_download"
  fi
fi

# ============================================================
# PASO 4 — Configurar .bashrc
# ============================================================
titulo "PASO 4 — Configurando .bashrc"

if check_done "bashrc_config"; then
  log ".bashrc ya configurado [checkpoint]"
else
  BASHRC="$HOME/.bashrc"

  # Eliminar configuración anterior de este proyecto
  grep -v "termux-ai-stack\|alias menu\|menu.sh" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << 'BASHRC_CONTENT'

# ════════════════════════════════════════
#  termux-ai-stack · configuración base
# ════════════════════════════════════════
alias menu='bash ~/menu.sh'

# Auto-ejecutar menu al abrir Termux
# (solo si no hay sesión tmux activa ya corriendo)
if [ -z "$TMUX" ] && [ -z "$ANDROID_SERVER_READY" ]; then
  bash ~/menu.sh
fi
BASHRC_CONTENT

  mark_done "bashrc_config"
  log ".bashrc configurado — menu.sh se abrirá automáticamente"
fi

# ============================================================
# PASO 5 — Selección de módulos a instalar
# ============================================================
titulo "PASO 5 — Módulos disponibles"

echo "  Elige qué instalar ahora."
echo "  Puedes saltar todo y hacerlo después desde el menú."
echo ""

# Función para verificar si un módulo ya está instalado
check_module() {
  local module="$1"
  local registry="$HOME/.android_server_registry"
  [ -f "$registry" ] && grep -q "^${module}.installed=true" "$registry" 2>/dev/null
}

# Mostrar estado de cada módulo
echo -e "  Módulo          Estado"
echo -e "  ──────────────────────────────────────"

if check_module "n8n"; then
  N8N_VER=$(grep "^n8n.version=" "$HOME/.android_server_registry" 2>/dev/null | cut -d'=' -f2)
  echo -e "  [1] n8n          ${GREEN}✓ instalado${NC} v$N8N_VER"
else
  echo -e "  [1] n8n          ${YELLOW}○ no instalado${NC}"
fi

if check_module "claude_code"; then
  CC_VER=$(grep "^claude_code.version=" "$HOME/.android_server_registry" 2>/dev/null | cut -d'=' -f2)
  echo -e "  [2] Claude Code  ${GREEN}✓ instalado${NC} v$CC_VER"
else
  echo -e "  [2] Claude Code  ${YELLOW}○ no instalado${NC}"
fi

if check_module "ollama"; then
  OL_VER=$(grep "^ollama.version=" "$HOME/.android_server_registry" 2>/dev/null | cut -d'=' -f2)
  echo -e "  [3] Ollama       ${GREEN}✓ instalado${NC} v$OL_VER"
else
  echo -e "  [3] Ollama       ${YELLOW}○ no instalado${NC}"
fi

if check_module "expo"; then
  EX_VER=$(grep "^expo.version=" "$HOME/.android_server_registry" 2>/dev/null | cut -d'=' -f2)
  echo -e "  [4] Expo / EAS   ${GREEN}✓ instalado${NC} v$EX_VER"
else
  echo -e "  [4] Expo / EAS   ${YELLOW}○ no instalado${NC}"
fi

echo ""
echo "  [a] Instalar todos"
echo "  [s] Saltar — instalaré después desde el menú"
echo ""
read -r -p "  Elige [1/2/3/4/a/s]: " MODULE_CHOICE

# Función: descargar y ejecutar módulo
run_module() {
  local name="$1"
  local script="$2"
  local tmp="$HOME/.tmp_${name}_install.sh"

  titulo "Instalando $name"
  info "Descargando $script desde el repo..."

  curl -fsSL "$REPO_RAW/$script" -o "$tmp" 2>/dev/null || \
    wget -q "$REPO_RAW/$script" -O "$tmp" 2>/dev/null

  if [ ! -f "$tmp" ] || [ ! -s "$tmp" ]; then
    error "No se pudo descargar $script. Verifica conexión y que el repo sea público."
  fi

  chmod +x "$tmp"
  # ANDROID_SERVER_READY ya está exportado — el módulo saltará pkg update
  bash "$tmp"
  local status=$?
  rm -f "$tmp"
  return $status
}

case "$MODULE_CHOICE" in
  1) run_module "n8n" "install_n8n.sh" ;;
  2) run_module "Claude Code" "install_claude.sh" ;;
  3) run_module "Ollama" "install_ollama.sh" ;;
  4) run_module "Expo/EAS" "install_expo.sh" ;;
  a|A)
    run_module "n8n" "install_n8n.sh"
    run_module "Claude Code" "install_claude.sh"
    run_module "Ollama" "install_ollama.sh"
    run_module "Expo/EAS" "install_expo.sh"
    ;;
  s|S|"")
    info "Módulos omitidos — instálalos después con: menu"
    ;;
  *)
    warn "Opción no reconocida — instala módulos después con: menu"
    ;;
esac

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "SETUP COMPLETADO"

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════════╗
  ║     termux-ai-stack configurado con éxito ✓     ║
  ╚══════════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  PRÓXIMOS PASOS:"
echo "  1. Cierra y reabre Termux"
echo "     → aparecerá el dashboard automáticamente"
echo "  2. Desde el dashboard puedes instalar"
echo "     módulos que hayas saltado"
echo ""
echo "  COMANDOS DIRECTOS:"
echo "  menu          → abrir dashboard"
echo "  n8n-start     → iniciar n8n"
echo "  claude        → Claude Code"
echo "  ollama-start  → iniciar Ollama"
echo "  help          → todos los comandos"
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para ver el dashboard${NC}"
echo ""

rm -f "$CHECKPOINT"

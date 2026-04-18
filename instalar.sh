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
#    ✅ PASO 0 — Permisos de almacenamiento (verificación real con escritura)
#    ✅ PASO 1 — pkg update + dependencias base (una sola vez para todos los módulos)
#    ✅ PASO 2 — Tema visual GitHub Dark + JetBrains Mono (siempre re-aplica)
#    ✅ PASO 3 — termux.properties + extra-keys del stack completo
#    ✅ PASO 4 — Descarga menu.sh a ~/
#    ✅ PASO 5 — Descarga los 4 scripts de módulo a ~/
#    ✅ PASO 6 — Configura .bashrc para auto-ejecutar menu.sh
#    ✅ PASO 7 — Menú interactivo para instalar módulos (llama bash ~/install_X.sh)
#
#  ARQUITECTURA v2:
#    - Scripts descargados a ~/ una sola vez
#    - menu.sh llama bash ~/install_X.sh (sin red)
#    - Verificación de permisos con escritura real
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 2.0.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"
export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib"

# ── Fix: stdin desde terminal (necesario para curl | bash) ────
# Sin esto, todos los `read` leen del pipe en lugar del teclado
exec < /dev/tty

# ── URLs del repo ─────────────────────────────────────────────
REPO_RAW_SCRIPT="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script"
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
REGISTRY="$HOME/.android_server_registry"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Leer registry ─────────────────────────────────────────────
get_reg() { grep "^${1}\.${2}=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2; }
check_module() { [ "$(get_reg "$1" installed)" = "true" ]; }

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
  ║        v2.0.0 · Android ARM64 · sin root         ║
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
echo "  ▸ Scripts de módulo descargados a ~/"
echo "  ▸ Dashboard menu.sh (se abre al iniciar Termux)"
echo "  ▸ Módulos opcionales: n8n · Claude Code · Ollama · Expo"
echo ""
read -r -p "  ¿Continuar? (s/n): " CONFIRMAR
[ "$CONFIRMAR" != "s" ] && [ "$CONFIRMAR" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 0 — Permiso de almacenamiento (verificación real)
# ============================================================
titulo "PASO 0 — Permiso de almacenamiento"

# Verificación real: intenta escribir un archivo de prueba
# [ -d /sdcard/Download ] es falso positivo — el dir existe aunque no haya permiso
check_storage_real() {
  touch /sdcard/Download/.termux_test 2>/dev/null && \
    rm -f /sdcard/Download/.termux_test 2>/dev/null
}

if check_done "storage"; then
  log "Permiso de almacenamiento ya configurado [checkpoint]"
else
  STORAGE_OK=0
  STORAGE_ATTEMPTS=0

  while [ "$STORAGE_OK" = "0" ] && [ "$STORAGE_ATTEMPTS" -lt 3 ]; do
    STORAGE_ATTEMPTS=$((STORAGE_ATTEMPTS + 1))

    if check_storage_real; then
      log "Acceso a /sdcard confirmado (escritura verificada)"
      STORAGE_OK=1
    else
      if [ "$STORAGE_ATTEMPTS" = "1" ]; then
        info "Solicitando permiso de almacenamiento..."
        info "→ Acepta el diálogo que aparecerá en pantalla"
        termux-setup-storage 2>/dev/null
        sleep 4
      else
        echo ""
        echo -e "  ${YELLOW}  No se detectó permiso de escritura en /sdcard${NC}"
        echo ""
        echo "  Si el diálogo no apareció, actívalo manualmente:"
        echo "  → Ajustes → Apps → Termux → Permisos → Almacenamiento → Permitir"
        echo ""
        echo "  En MIUI / HyperOS también necesitas:"
        echo "  → Ajustes → Privacidad → Permisos especiales"
        echo "     → Acceso a todos los archivos → Termux → Activar"
        echo ""
        read -r -p "  ¿Ya activaste el permiso? Presiona ENTER para verificar..." _
      fi
    fi
  done

  if [ "$STORAGE_OK" = "1" ]; then
    mark_done "storage"
  else
    warn "No se pudo verificar permiso de escritura en /sdcard"
    warn "Los backups no funcionarán. Puedes continuar igual."
    echo ""
    read -r -p "  ¿Continuar sin permiso de almacenamiento? (s/n): " CONT_NO_STORAGE
    [ "$CONT_NO_STORAGE" != "s" ] && [ "$CONT_NO_STORAGE" != "S" ] && {
      echo "Cancelado. Activa el permiso y vuelve a ejecutar el script."
      exit 1
    }
    mark_done "storage"
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
# Siempre re-aplica — garantiza tema correcto en cualquier re-ejecución
# ============================================================
titulo "PASO 2 — Aplicando tema visual"

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
if [ -f "$FONT_FILE" ] && [ -s "$FONT_FILE" ]; then
  log "JetBrains Mono ya instalada — omitiendo descarga"
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
  [ -f "$FONT_FILE" ] && [ -s "$FONT_FILE" ] && \
    log "JetBrains Mono instalada" || \
    warn "No se pudo descargar la fuente — se usará la fuente por defecto"
fi

command -v termux-reload-settings &>/dev/null && \
  termux-reload-settings 2>/dev/null
log "Tema GitHub Dark aplicado — reinicia Termux para verlo"

# ============================================================
# PASO 3 — termux.properties (extra-keys del stack)
# ============================================================
titulo "PASO 3 — Configurando extra-keys"

cat > "$TERMUX_CONFIG/termux.properties" << 'PROPS'
# termux-ai-stack — Configuración Termux
extra-keys = [['ESC','TAB','CTRL','ALT','|','/','UP','DOWN'],['n8n-start','n8n-url','claude','ollama-start','menu','help','LEFT','RIGHT']]
bell-character=ignore
PROPS

command -v termux-reload-settings &>/dev/null && \
  termux-reload-settings 2>/dev/null
log "termux.properties configurado (extra-keys del stack)"

# ============================================================
# PASO 4 — Descargar menu.sh a ~/
# ============================================================
titulo "PASO 4 — Descargando menu.sh"

download_file() {
  local url="$1"
  local dest="$2"
  local label="$3"

  rm -f "$dest"
  curl -fsSL "$url" -o "$dest" 2>/dev/null || \
    wget -q "$url" -O "$dest" 2>/dev/null

  if [ -f "$dest" ] && [ -s "$dest" ]; then
    chmod +x "$dest"
    log "$label descargado ✓"
    return 0
  else
    rm -f "$dest"
    warn "$label no se pudo descargar"
    return 1
  fi
}

download_file \
  "$REPO_RAW_SCRIPT/menu.sh" \
  "$HOME/menu.sh" \
  "menu.sh"

# Fallback: menú básico si no se pudo descargar
if [ ! -f "$HOME/menu.sh" ] || [ ! -s "$HOME/menu.sh" ]; then
  warn "Creando menu.sh básico de emergencia..."
  cat > "$HOME/menu.sh" << 'MENU_FALLBACK'
#!/data/data/com.termux/files/usr/bin/bash
echo ""
echo "╔══════════════════════════════════════╗"
echo "║   termux-ai-stack · menu (básico)   ║"
echo "╠══════════════════════════════════════╣"
echo "║  [1] n8n-start                      ║"
echo "║  [2] claude                         ║"
echo "║  [3] ollama-start                   ║"
echo "║  [4] expo-info                      ║"
echo "║  [q] salir al shell                 ║"
echo "╚══════════════════════════════════════╝"
echo ""
read -r -p "  Opción: " OPT
case "$OPT" in
  1) n8n-start ;;
  2) claude ;;
  3) ollama-start ;;
  4) expo-info ;;
  q) exit 0 ;;
esac
MENU_FALLBACK
  chmod +x "$HOME/menu.sh"
  warn "menu.sh básico creado — actualiza desde el repo cuando tengas conexión"
fi

# ============================================================
# PASO 5 — Descargar scripts de módulo a ~/
# ============================================================
titulo "PASO 5 — Descargando scripts de módulo"

info "Descargando los 4 scripts de módulo + backup/restore desde $REPO_RAW_SCRIPT/..."
echo ""

SCRIPTS_OK=0
SCRIPTS_FAIL=0

for script in install_n8n.sh install_claude.sh install_ollama.sh install_expo.sh backup.sh restore.sh; do
  if download_file \
      "$REPO_RAW_SCRIPT/$script" \
      "$HOME/$script" \
      "$script"; then
    SCRIPTS_OK=$((SCRIPTS_OK + 1))
  else
    SCRIPTS_FAIL=$((SCRIPTS_FAIL + 1))
  fi
done

echo ""
log "$SCRIPTS_OK/6 scripts descargados correctamente"
[ "$SCRIPTS_FAIL" -gt 0 ] && \
  warn "$SCRIPTS_FAIL script(s) fallaron — se re-intentará al usar ese módulo"

# Verificación final: listar qué hay en ~/
echo ""
info "Scripts disponibles en ~/ :"
for script in menu.sh install_n8n.sh install_claude.sh install_ollama.sh install_expo.sh backup.sh restore.sh; do
  if [ -f "$HOME/$script" ] && [ -s "$HOME/$script" ]; then
    SIZE=$(wc -c < "$HOME/$script" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} ~/$script  (${SIZE} bytes)"
  else
    echo -e "  ${RED}✗${NC} ~/$script  (no disponible)"
  fi
done

# ============================================================
# PASO 6 — Configurar .bashrc
# ============================================================
titulo "PASO 6 — Configurando .bashrc"

if check_done "bashrc_config"; then
  log ".bashrc ya configurado [checkpoint]"
else
  BASHRC="$HOME/.bashrc"

  # Eliminar bloque anterior de este proyecto (idempotente)
  if grep -q "termux-ai-stack" "$BASHRC" 2>/dev/null; then
    info "Eliminando configuración anterior de termux-ai-stack..."
    # Eliminar entre los marcadores del bloque
    sed -i '/# ════.*termux-ai-stack/,/# FIN ANDROID SERVER STACK/d' "$BASHRC" 2>/dev/null || \
      grep -v "termux-ai-stack\|alias menu\|alias help\|menu\.sh\|ANDROID_SERVER_READY\|FIN ANDROID" \
        "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
  fi

  cat >> "$BASHRC" << 'BASHRC_BLOCK'

# ════════════════════════════════════════
#  termux-ai-stack · configuración base
# ════════════════════════════════════════
alias menu='bash ~/menu.sh'

# Auto-ejecutar menu al abrir Termux
# Solo si: no estamos dentro de tmux, y no somos llamados por instalar.sh
if [ -z "$TMUX" ] && [ -z "$ANDROID_SERVER_READY" ]; then
  bash ~/menu.sh
fi
# FIN ANDROID SERVER STACK
BASHRC_BLOCK

  mark_done "bashrc_config"
  log ".bashrc configurado — menu.sh se abrirá automáticamente"
fi

# ============================================================
# PASO 7 — Selección de módulos a instalar
# ============================================================
titulo "PASO 7 — Módulos disponibles"

echo "  Elige qué instalar ahora."
echo "  Puedes saltar todo y hacerlo después desde el menú."
echo ""

# ── Función: ejecutar módulo con re-descarga si falta ────────
run_module() {
  local name="$1"
  local script="install_${2}.sh"
  local dest="$HOME/$script"

  titulo "Instalando $name"

  # Verificar que el script existe y tiene contenido real
  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    warn "~/$script no encontrado — re-descargando..."
    download_file "$REPO_RAW_SCRIPT/$script" "$dest" "$script"
  fi

  # Segunda verificación tras re-descarga
  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    echo -e "  ${RED}[ERROR]${NC} No se pudo obtener $script"
    echo "  Verifica tu conexión y vuelve a intentarlo desde el menú."
    echo ""
    read -r -p "  Presiona ENTER para continuar..." _
    return 1
  fi

  # ANDROID_SERVER_READY ya está exportado — el módulo saltará pkg update
  # < /dev/tty garantiza que los read del módulo hijo lean del teclado
  bash "$dest" < /dev/tty
}

# ── Mostrar estado de cada módulo ────────────────────────────
echo -e "  Módulo            Estado"
echo -e "  ────────────────────────────────────────────"

# n8n
if check_module "n8n"; then
  N8N_VER=$(get_reg n8n version)
  echo -e "  [1] n8n           ${GREEN}✓ instalado${NC} v${N8N_VER}  ${YELLOW}(reinstalar: 1)${NC}"
else
  echo -e "  [1] n8n           ${YELLOW}○ no instalado${NC}"
fi

# Claude Code
if check_module "claude_code"; then
  CC_VER=$(get_reg claude_code version)
  echo -e "  [2] Claude Code   ${GREEN}✓ instalado${NC} v${CC_VER}  ${YELLOW}(reinstalar: 2)${NC}"
else
  echo -e "  [2] Claude Code   ${YELLOW}○ no instalado${NC}"
fi

# Ollama
if check_module "ollama"; then
  OL_VER=$(get_reg ollama version)
  echo -e "  [3] Ollama        ${GREEN}✓ instalado${NC} v${OL_VER}  ${YELLOW}(reinstalar: 3)${NC}"
else
  echo -e "  [3] Ollama        ${YELLOW}○ no instalado${NC}"
fi

# Expo / EAS
if check_module "expo"; then
  EX_VER=$(get_reg expo version)
  echo -e "  [4] Expo / EAS    ${GREEN}✓ instalado${NC} v${EX_VER}  ${YELLOW}(reinstalar: 4)${NC}"
else
  echo -e "  [4] Expo / EAS    ${YELLOW}○ no instalado${NC}"
fi

echo ""
echo "  [a] Instalar todos"
echo "  [s] Saltar — instalaré después desde el menú"
echo ""
read -r -p "  Elige [1/2/3/4/a/s]: " MODULE_CHOICE

case "$MODULE_CHOICE" in
  1) run_module "n8n"        "n8n"    ;;
  2) run_module "Claude Code" "claude" ;;
  3) run_module "Ollama"     "ollama" ;;
  4) run_module "Expo/EAS"   "expo"   ;;
  a|A)
    run_module "n8n"        "n8n"
    run_module "Claude Code" "claude"
    run_module "Ollama"     "ollama"
    run_module "Expo/EAS"   "expo"
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
  ║     termux-ai-stack v2 configurado con éxito ✓  ║
  ╚══════════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  SCRIPTS EN ~/:"
for f in menu.sh install_n8n.sh install_claude.sh install_ollama.sh install_expo.sh; do
  [ -f "$HOME/$f" ] && \
    echo -e "  ${GREEN}✓${NC} ~/$f" || \
    echo -e "  ${YELLOW}?${NC} ~/$f (no disponible)"
done

echo ""
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
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para ver el dashboard${NC}"
echo ""

rm -f "$CHECKPOINT"

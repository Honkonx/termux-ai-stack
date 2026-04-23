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
#    ✅ PASO 1 — pkg update + dependencias base
#    ✅ PASO 2 — Tema GitHub Dark + JetBrains Mono + extra-keys
#    ✅ PASO 3 — ELECCIÓN: instalar base desde GitHub Release (rápido)
#                          O descargar scripts individuales desde repo (lento)
#    ✅ PASO 4 — Configura .bashrc auto-launch
#    ✅ PASO 5 — Menú interactivo para instalar módulos
#
#  MODOS DE SETUP BASE:
#    Modo A (Release) → descarga part0-termux-base del último release
#                       Más rápido, 1 archivo, incluye todo configurado
#    Modo B (Scripts) → descarga scripts individuales desde repo raw
#                       Más lento, siempre la versión más reciente del repo
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 2.3.1 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"
export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib"

# Fix stdin cuando se ejecuta via curl | bash
exec < /dev/tty

# ── URLs ──────────────────────────────────────────────────────
REPO_RAW_SCRIPT="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script"
REPO_URL="https://github.com/Honkonx/termux-ai-stack"
GITHUB_API="https://api.github.com/repos/Honkonx/termux-ai-stack/releases/latest"

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

# ── Estado ────────────────────────────────────────────────────
CHECKPOINT="$HOME/.instalar_checkpoint"
REGISTRY="$HOME/.android_server_registry"

check_done()   { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()    { echo "$1" >> "$CHECKPOINT"; }
get_reg()      { grep "^${1}\.${2}=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2; }
check_module() { [ "$(get_reg "$1" installed)" = "true" ]; }

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
  ║        v2.3.1 · Android ARM64 · sin root         ║
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
# PRE-PASO — Elegir modo de instalación base
# Se hace ANTES del pkg update para poder saltarlo si el
# usuario elige Modo Release (el part0-base ya trae pkg_update
# marcado como hecho, así que no necesita actualizar Termux)
# ============================================================
if ! check_done "base_scripts" && ! check_done "base_mode_chosen"; then
  echo ""
  echo -e "  ${BOLD}¿Cómo instalar los scripts base?${NC}"
  echo ""
  echo -e "  ${GREEN}[1] GitHub Release${NC} (RECOMENDADO)"
  echo "      Descarga part0-termux-base del último release"
  echo "      ✓ Un solo archivo · Incluye tema y configs"
  echo -e "      ✓ ${BOLD}Salta pkg update${NC} — mucho más rápido"
  echo ""
  echo -e "  ${CYAN}[2] Scripts individuales${NC} (desde el repo)"
  echo "      Descarga cada script por separado"
  echo "      ✓ Siempre la versión más reciente del repo"
  echo ""
  echo -n "  Elige [1/2]: "
  read -r _PRE_BASE_MODE < /dev/tty
  echo "$_PRE_BASE_MODE" > "$HOME/.instalar_base_mode"
  mark_done "base_mode_chosen"
fi

# Leer modo elegido (puede venir de una sesión previa via checkpoint)
_BASE_MODE_SAVED=$(cat "$HOME/.instalar_base_mode" 2>/dev/null)

# ============================================================
# PASO 1 — pkg update + dependencias base
# Se salta si el usuario eligió Modo Release [1] y el release
# está disponible — el part0-base ya incluye el entorno listo
# ============================================================
titulo "PASO 1 — Actualizando Termux"

if check_done "pkg_update"; then
  log "Termux ya actualizado [checkpoint]"
elif [ "$_BASE_MODE_SAVED" = "1" ]; then
  # Modo Release: intentar sin pkg update primero
  # Si el release descarga bien, marcamos pkg_update como hecho
  # Si falla la descarga, volvemos al flujo normal
  info "Modo Release elegido — verificando si pkg update es necesario..."
  TEST_CURL=$(curl -fsSL --max-time 5 "https://api.github.com/repos/Honkonx/termux-ai-stack/releases/latest" 2>/dev/null | grep -c "tag_name")
  if [ "$TEST_CURL" -gt 0 ] 2>/dev/null; then
    info "GitHub accesible — pkg update se omite hasta verificar el release"
    # NO marcamos pkg_update aquí — se marca en el Paso 3 si la descarga funciona
  else
    warn "GitHub no accesible — ejecutando pkg update como fallback..."
    pkg update -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>/dev/null || \
      warn "pkg update tuvo advertencias"
    pkg install -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      curl wget tar xz-utils tmux proot proot-distro busybox iproute2 git unzip 2>/dev/null || \
      warn "Algunos paquetes tuvieron advertencias"
    export ANDROID_SERVER_READY=1
    mark_done "pkg_update"
    log "Termux actualizado"
  fi
else
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
    [ "$OK" = "0" ] && error "Todos los mirrors fallaron."
  fi

  pkg upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>/dev/null || \
    warn "pkg upgrade tuvo advertencias"

  pkg install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    curl wget tar xz-utils tmux \
    proot proot-distro busybox iproute2 \
    git unzip 2>/dev/null || \
    warn "Algunos paquetes tuvieron advertencias"

  for p in curl wget tmux proot-distro git; do
    command -v "$p" &>/dev/null && log "$p ✓" || warn "$p no instaló"
  done

  export ANDROID_SERVER_READY=1
  mark_done "pkg_update"
  log "Termux actualizado"
fi

# ============================================================
# PASO 2 — Tema GitHub Dark + fuente + extra-keys
# ============================================================
titulo "PASO 2 — Tema visual"

TERMUX_CONFIG="$HOME/.termux"
mkdir -p "$TERMUX_CONFIG"

# Colores GitHub Dark
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

# Extra-keys del stack (incluye remote/ssh y dashboard)
cat > "$TERMUX_CONFIG/termux.properties" << 'PROPS'
# termux-ai-stack — Configuración Termux
extra-keys = [['ESC','TAB','CTRL','ALT','|','/','UP','DOWN'],['n8n-start','n8n-url','claude','ollama-start','menu','help','LEFT','RIGHT']]
bell-character=ignore
PROPS

# Fuente JetBrains Mono
FONT_FILE="$TERMUX_CONFIG/font.ttf"
if [ ! -f "$FONT_FILE" ]; then
  info "Descargando JetBrains Mono..."
  FONT_URL="https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
  FONT_TMP="$HOME/jbmono.zip"
  wget -q --show-progress "$FONT_URL" -O "$FONT_TMP" 2>/dev/null || \
    curl -L --progress-bar "$FONT_URL" -o "$FONT_TMP" 2>/dev/null
  if [ -f "$FONT_TMP" ] && [ -s "$FONT_TMP" ]; then
    unzip -q "$FONT_TMP" "fonts/ttf/JetBrainsMono-Regular.ttf" -d "$HOME/jbmono_tmp" 2>/dev/null
    mv "$HOME/jbmono_tmp/fonts/ttf/JetBrainsMono-Regular.ttf" "$FONT_FILE" 2>/dev/null || true
    rm -rf "$HOME/jbmono.zip" "$HOME/jbmono_tmp" 2>/dev/null
    [ -f "$FONT_FILE" ] && log "JetBrains Mono instalada" || warn "No se pudo instalar la fuente"
  fi
else
  log "JetBrains Mono ya instalada [skip]"
fi

command -v termux-reload-settings &>/dev/null && termux-reload-settings 2>/dev/null
log "Tema GitHub Dark aplicado"

# ============================================================
# PASO 3 — Instalar scripts base
# ============================================================
titulo "PASO 3 — Instalando scripts base"

download_file() {
  local url="$1"
  local dest="$2"
  local label="$3"
  rm -f "$dest"
  curl -fsSL "$url" -o "$dest" 2>/dev/null || wget -q "$url" -O "$dest" 2>/dev/null
  if [ -f "$dest" ] && [ -s "$dest" ]; then
    chmod +x "$dest"
    log "$label ✓"
    return 0
  else
    rm -f "$dest"
    warn "$label — fallo al descargar"
    return 1
  fi
}

if check_done "base_scripts"; then
  log "Scripts base ya instalados [checkpoint]"
else
  # Modo elegido en el PRE-PASO (antes del pkg update)
  BASE_MODE="${_BASE_MODE_SAVED:-2}"
  [ -z "$BASE_MODE" ] && BASE_MODE="2"
  info "Modo: $([ "$BASE_MODE" = "1" ] && echo 'GitHub Release' || echo 'Scripts individuales')"
  echo ""

  case "$BASE_MODE" in
    2)
      # ── Modo B: scripts individuales desde repo raw ──────────
      info "Descargando scripts desde el repo..."
      echo ""

      SCRIPTS_OK=0
      SCRIPTS_FAIL=0

      for script in \
        menu.sh backup.sh restore.sh \
        install_n8n.sh install_claude.sh install_ollama.sh \
        install_expo.sh install_python.sh install_ssh.sh \
        install_remote.sh
      do
        if download_file "$REPO_RAW_SCRIPT/$script" "$HOME/$script" "$script"; then
          SCRIPTS_OK=$((SCRIPTS_OK + 1))
        else
          SCRIPTS_FAIL=$((SCRIPTS_FAIL + 1))
        fi
      done

      echo ""
      log "$SCRIPTS_OK scripts descargados"
      [ "$SCRIPTS_FAIL" -gt 0 ] && warn "$SCRIPTS_FAIL scripts fallaron"
      mark_done "base_scripts"
      ;;

    1|"")
      # ── Modo A: desde GitHub Release (paquete base) ──────────
      info "Consultando GitHub para obtener el último release..."

      RELEASE_JSON=$(curl -fsSL "$GITHUB_API" 2>/dev/null)
      BASE_URL=""

      if [ -n "$RELEASE_JSON" ]; then
        BASE_URL=$(echo "$RELEASE_JSON" | \
          grep -o '"browser_download_url": *"[^"]*part0-termux-base[^"]*"' | \
          grep -o 'https://[^"]*' | head -1)
      fi

      if [ -n "$BASE_URL" ]; then
        RELEASE_TAG=$(echo "$RELEASE_JSON" | grep '"tag_name"' | grep -o '"v[^"]*"' | tr -d '"' | head -1)
        info "Release encontrado: ${RELEASE_TAG:-latest}"
        info "Descargando paquete base..."

        BASE_TMP="$HOME/base_tmp.tar.xz"
        curl -fL --progress-bar "$BASE_URL" -o "$BASE_TMP" 2>/dev/null

        if [ -f "$BASE_TMP" ] && [ -s "$BASE_TMP" ]; then
          BASE_SIZE=$(du -h "$BASE_TMP" | cut -f1)
          log "Descarga completa: $BASE_SIZE"

          BASE_EXTRACT="$HOME/base_extract_tmp"
          mkdir -p "$BASE_EXTRACT"
          info "Extrayendo..."
          tar -xJf "$BASE_TMP" -C "$BASE_EXTRACT" 2>/dev/null

          # Copiar scripts al home
          if [ -d "$BASE_EXTRACT/home" ]; then
            for f in "$BASE_EXTRACT/home/"*.sh; do
              [ -f "$f" ] && cp "$f" "$HOME/" && chmod +x "$HOME/$(basename "$f")"
            done
            for f in "$BASE_EXTRACT/home/"*.py; do
              [ -f "$f" ] && cp "$f" "$HOME/"
            done
            COPIED=$(ls "$BASE_EXTRACT/home/"*.sh 2>/dev/null | wc -l)
            log "$COPIED scripts instalados desde release"
          fi

          # Tema si no se aplicó antes (o actualizarlo)
          if [ -d "$BASE_EXTRACT/termux_config/.termux" ]; then
            cp -r "$BASE_EXTRACT/termux_config/.termux/." "$HOME/.termux/"
            command -v termux-reload-settings &>/dev/null && termux-reload-settings 2>/dev/null
            log "Tema desde release aplicado"
          fi

          # Registry si existe
          [ -f "$BASE_EXTRACT/home/.android_server_registry" ] && \
            cp "$BASE_EXTRACT/home/.android_server_registry" "$REGISTRY"

          rm -rf "$BASE_EXTRACT" "$BASE_TMP"
          log "Paquete base instalado desde GitHub Release ✓"
          mark_done "pkg_update"  # Release incluye Termux ya configurado
          export ANDROID_SERVER_READY=1
          mark_done "base_scripts"
        else
          warn "Descarga fallida — usando Modo B como fallback..."
          rm -f "$BASE_TMP"
          # Fallback automático a scripts individuales
          for script in \
            menu.sh backup.sh restore.sh \
            install_n8n.sh install_claude.sh install_ollama.sh \
            install_expo.sh install_python.sh install_ssh.sh \
            install_remote.sh
          do
            download_file "$REPO_RAW_SCRIPT/$script" "$HOME/$script" "$script"
          done
          mark_done "base_scripts"
        fi
      else
        warn "No se encontró part0-termux-base en el release — usando Modo B..."
        for script in \
          menu.sh backup.sh restore.sh \
          install_n8n.sh install_claude.sh install_ollama.sh \
          install_expo.sh install_python.sh install_ssh.sh \
          install_remote.sh
        do
          download_file "$REPO_RAW_SCRIPT/$script" "$HOME/$script" "$script"
        done
        mark_done "base_scripts"
      fi
      ;;
  esac
fi

# Verificar qué scripts hay disponibles
echo ""
info "Scripts disponibles en ~/:"
for script in \
  menu.sh backup.sh restore.sh \
  install_n8n.sh install_claude.sh install_ollama.sh \
  install_expo.sh install_python.sh install_ssh.sh \
  install_remote.sh
do
  if [ -f "$HOME/$script" ] && [ -s "$HOME/$script" ]; then
    SIZE=$(wc -c < "$HOME/$script" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} ~/$script  (${SIZE} bytes)"
  else
    echo -e "  ${YELLOW}?${NC} ~/$script  (no disponible)"
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
alias remote='bash ~/ssh_start.sh'
alias dashboard='bash ~/dashboard_start.sh'

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
# PASO 5 — Selección de módulos
# ============================================================
titulo "PASO 5 — Módulos disponibles"

echo "  Instala módulos ahora o después desde el menú."
echo ""

run_module() {
  local name="$1"
  local script="install_${2}.sh"
  local dest="$HOME/$script"

  titulo "Instalando $name"

  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    warn "~/$script no encontrado — re-descargando..."
    download_file "$REPO_RAW_SCRIPT/$script" "$dest" "$script"
  fi

  [ ! -f "$dest" ] || [ ! -s "$dest" ] && {
    echo -e "  ${RED}[ERROR]${NC} No se pudo obtener $script"
    read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
    return 1
  }

  bash "$dest" < /dev/tty
}

# Estado de módulos
echo -e "  Módulo                Estado"
echo -e "  ──────────────────────────────────────────────"

check_module "n8n"        && N8N_V=$(get_reg n8n version)      && echo -e "  [1] n8n               ${GREEN}✓ v${N8N_V}${NC}  (reinstalar: 1)"    || echo -e "  [1] n8n               ${YELLOW}○ no instalado${NC}"
check_module "claude_code" && CC_V=$(get_reg claude_code version) && echo -e "  [2] Claude Code       ${GREEN}✓ v${CC_V}${NC}  (reinstalar: 2)"    || echo -e "  [2] Claude Code       ${YELLOW}○ no instalado${NC}"
check_module "ollama"     && OL_V=$(get_reg ollama version)    && echo -e "  [3] Ollama            ${GREEN}✓ v${OL_V}${NC}  (reinstalar: 3)"    || echo -e "  [3] Ollama            ${YELLOW}○ no instalado${NC}"
check_module "expo"       && EX_V=$(get_reg expo version)      && echo -e "  [4] Expo / EAS        ${GREEN}✓ v${EX_V}${NC}  (reinstalar: 4)"    || echo -e "  [4] Expo / EAS        ${YELLOW}○ no instalado${NC}"
check_module "python"     && PY_V=$(get_reg python version)    && echo -e "  [5] Python            ${GREEN}✓ v${PY_V}${NC}  (reinstalar: 5)"    || echo -e "  [5] Python            ${YELLOW}○ no instalado${NC}"
check_module "ssh"                                              && echo -e "  [6] SSH               ${GREEN}✓ instalado${NC}  (reinstalar: 6)"   || echo -e "  [6] SSH               ${YELLOW}○ no instalado${NC}"
check_module "dashboard"                                        && echo -e "  [7] Remote/Dashboard  ${GREEN}✓ instalado${NC}  (reinstalar: 7)"   || echo -e "  [7] Remote/Dashboard  ${YELLOW}○ no instalado${NC}"

echo ""
echo "  [a] Instalar todos"
echo "  [s] Saltar — instalaré después desde el menú"
echo ""
read -r -p "  Elige [1/2/3/4/5/6/7/a/s]: " MODULE_CHOICE < /dev/tty

case "$MODULE_CHOICE" in
  1) run_module "n8n"           "n8n"     ;;
  2) run_module "Claude Code"   "claude"  ;;
  3) run_module "Ollama"        "ollama"  ;;
  4) run_module "Expo/EAS"      "expo"    ;;
  5) run_module "Python"        "python"  ;;
  6) run_module "SSH"           "ssh"     ;;
  7) run_module "Remote/Dashboard" "remote" ;;
  a|A)
    run_module "n8n"           "n8n"
    run_module "Claude Code"   "claude"
    run_module "Ollama"        "ollama"
    run_module "Expo/EAS"      "expo"
    run_module "Python"        "python"
    run_module "SSH"           "ssh"
    run_module "Remote/Dashboard" "remote"
    ;;
  s|S|"") info "Módulos omitidos — instálalos después con: menu" ;;
  *)      warn "Opción no reconocida — instala módulos después con: menu" ;;
esac

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "SETUP COMPLETADO"

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════════╗
  ║     termux-ai-stack v2.3.1 configurado ✓        ║
  ╚══════════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  SCRIPTS EN ~/:"
for f in menu.sh install_n8n.sh install_claude.sh install_ollama.sh \
          install_expo.sh install_python.sh install_ssh.sh install_remote.sh \
          backup.sh restore.sh; do
  [ -f "$HOME/$f" ] && \
    echo -e "  ${GREEN}✓${NC} ~/$f" || \
    echo -e "  ${YELLOW}?${NC} ~/$f (no disponible)"
done

echo ""
echo "  COMANDOS:"
echo "  menu        → abrir dashboard TUI"
echo "  claude      → Claude Code"
echo "  n8n-start   → iniciar n8n"
echo "  ollama-start → iniciar Ollama"
echo "  dashboard   → iniciar servidor web"
echo "  remote      → iniciar SSH"
echo ""

rm -f "$CHECKPOINT"
rm -f "$HOME/.instalar_base_mode" 2>/dev/null

echo -e "${CYAN}${BOLD}  → Cargando dashboard...${NC}"
echo ""
exec bash "$HOME/menu.sh"

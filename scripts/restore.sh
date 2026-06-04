#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · restore.sh
#  Restaura módulos desde GitHub Releases o backup local
#
#  USO:
#    bash ~/restore.sh                           → menú interactivo
#    bash ~/restore.sh --module base             → base (scripts + tema + configs)
#    bash ~/restore.sh --module claude           → Claude Code
#    bash ~/restore.sh --module expo             → EAS CLI
#    bash ~/restore.sh --module ollama           → Ollama binario
#    bash ~/restore.sh --module n8n              → n8n + cloudflared
#    bash ~/restore.sh --module proot            → Rootfs Debian
#    bash ~/restore.sh --module remote           → SSH + Dashboard configs
#    bash ~/restore.sh --module all              → todos
#    bash ~/restore.sh --module all --source github  → todos desde GitHub
#    bash ~/restore.sh --module base --source local  → base desde backup local
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 2.6.0 | Mayo 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

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

# ── Rutas ─────────────────────────────────────────────────────
TMP_DIR="$HOME/restore_tmp"
LOCAL_DIR="/sdcard/Download/termux-ai-stack-releases"
REGISTRY="$HOME/.android_server_registry"
NPM_GLOBAL="${TERMUX_PREFIX}/lib/node_modules"
ROOTFS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/installed-rootfs"
GITHUB_API="https://api.github.com/repos/Honkonx/termux-ai-stack/releases/latest"
SSHD_CONFIG="${TERMUX_PREFIX}/etc/ssh/sshd_config"

TARGET_MODULE=""
SOURCE=""

# ── Detectar proot ────────────────────────────────────────────
DISTRO_NAME=""
ROOTFS_PATH=""
detect_distro() {
  DISTRO_NAME=""
  ROOTFS_PATH=""
  if [ -d "$ROOTFS_BASE" ]; then
    for d in "$ROOTFS_BASE"/*/; do
      d="${d%/}"   # quitar trailing slash
      if [ -f "${d}/bin/bash" ] || [ -f "${d}/usr/bin/bash" ] || [ -f "${d}/etc/os-release" ]; then
        DISTRO_NAME=$(basename "$d")
        ROOTFS_PATH="$d"
        return 0
      fi
    done
  fi
  return 1
}
detect_distro

# ════════════════════════════════════════════════════════════
# DEPENDENCIAS BASE — proot-distro + paquetes necesarios
# Se llama antes de cualquier parte que use proot.
# Idempotente — si ya está instalado no hace nada.
# ════════════════════════════════════════════════════════════
_ensure_proot_pkg() {
  command -v proot-distro &>/dev/null && return 0
  warn "proot-distro no instalado — instalando dependencias base..."
  echo -e "  ${CYAN}[INFO]${NC} Esto requiere conexión a internet..."
  pkg install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    proot-distro proot tmux curl wget tar xz-utils git busybox 2>/dev/null \
    && log "proot-distro instalado correctamente" \
    || error "No se pudo instalar proot-distro — verifica tu conexión y ejecuta: pkg install proot-distro"
}

cleanup() {
  [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
  echo -e "\n  ${YELLOW}[AVISO]${NC} Restore interrumpido — archivos temporales eliminados"
}
trap cleanup INT TERM

# ════════════════════════════════════════════════════════════
# PARSE ARGUMENTOS
# ════════════════════════════════════════════════════════════
parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --module) shift; TARGET_MODULE="$1" ;;
      --source) shift; SOURCE="$1" ;;
      *) error "Argumento desconocido: $1" ;;
    esac
    shift
  done

  if [ -n "$TARGET_MODULE" ]; then
    case "$TARGET_MODULE" in
      base|claude|claude-native|expo|ollama|n8n|proot-base|proot-completo|remote|opencode|openclaw|all) ;;
      *) error "Módulo inválido: '$TARGET_MODULE'\n  Válidos: base | claude | expo | ollama | n8n | proot-base | proot-completo | remote | opencode | openclaw | all" ;;
    esac
  fi

  if [ -n "$SOURCE" ]; then
    case "$SOURCE" in
      github|local) ;;
      *) error "Fuente inválida: '$SOURCE'\n  Válidas: github | local" ;;
    esac
  fi
}

# ════════════════════════════════════════════════════════════
# HELPERS DE DISPONIBILIDAD
# Construye el indicador ✓/○ para cada módulo.
# _avail <PREFIX> → "1" si está en el release, "0" si no.
# Solo válido cuando SOURCE=github y RELEASE_JSON cargado.
# ════════════════════════════════════════════════════════════
declare -A _AVAIL_CACHE=()

_avail() {
  local key="$1"
  [ -n "${_AVAIL_CACHE[$key]+x}" ] && { echo "${_AVAIL_CACHE[$key]}"; return; }
  local url; url=$(get_part_url "$key")
  local val; [ -n "$url" ] && val="1" || val="0"
  _AVAIL_CACHE[$key]="$val"
  echo "$val"
}

_pill() {
  # $1 = PREFIX  →  imprime "✓" verde o "○" amarillo
  if [ "$SOURCE" = "github" ]; then
    [ "$(_avail "$1")" = "1" ] \
      && printf "${GREEN}✓${NC}" \
      || printf "${YELLOW}○${NC}"
  else
    # Fuente local — verificar archivo
    ls "$LOCAL_DIR"/*${1}*.tar.xz &>/dev/null 2>&1 \
      && printf "${GREEN}✓${NC}" \
      || printf "${YELLOW}○${NC}"
  fi
}

# ════════════════════════════════════════════════════════════
# SELECCIÓN DE FUENTE  (silenciosa — sin pantalla propia)
# ════════════════════════════════════════════════════════════
select_source() {
  local HAS_LOCAL=false
  [ -d "$LOCAL_DIR" ] && ls "$LOCAL_DIR"/*.tar.xz &>/dev/null 2>&1 && HAS_LOCAL=true

  if $HAS_LOCAL; then
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⬡ RESTORE · Fuente                    ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] GitHub Releases  (último release)  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Backup local     (/sdcard/Download)${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción (1/2): "
    read -r OPT_SRC < /dev/tty
    case "$OPT_SRC" in
      2) SOURCE="local" ;;
      *) SOURCE="github" ;;
    esac
  else
    SOURCE="github"
  fi
}

# ════════════════════════════════════════════════════════════
# MENÚ INTERACTIVO
# Consulta el release UNA sola vez, luego renderiza con ✓/○.
# ════════════════════════════════════════════════════════════
menu_interactivo() {
  select_source

  # Pre-cargar release JSON una sola vez antes de renderizar
  if [ "$SOURCE" = "github" ]; then
    clear; echo ""
    echo -e "  ${CYAN}Consultando GitHub...${NC}"
    fetch_release_json
  fi

  clear; echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  if [ "$SOURCE" = "github" ] && [ -n "$RELEASE_TAG" ]; then
    printf  "  ║  ⬡ RESTORE · %-28s║\n" "${RELEASE_TAG}"
  else
    echo    "  ║  ⬡ RESTORE · Backup local               ║"
  fi
  echo    "  ╠══════════════════════════════════════════╣"

  # ── Grupo BASE ────────────────────────────────────────────
  echo -e "  ║  ${NC}${DIM}── BASE ──────────────────────────────${NC}${CYAN}${BOLD}  ║"
  printf  "  ║  ${NC}[0] Scripts + tema + configs  $(_pill "part0-termux-base") ${CYAN}${BOLD}     ║\n"
  printf  "  ║  ${NC}[2] Claude legacy v2.1.111    $(_pill "part2-claude-code") ${CYAN}${BOLD}    ║\n"
  printf  "  ║  ${NC}[2b] Claude native v2.1.152+  $(_pill "part2b-claude-native") ${CYAN}${BOLD}   ║\n"
  printf  "  ║  ${NC}[3] Expo / EAS CLI            $(_pill "part3-eas-expo") ${CYAN}${BOLD}     ║\n"
  printf  "  ║  ${NC}[4] Ollama                    $(_pill "part4-ollama-standard") ${CYAN}${BOLD}     ║\n"
  printf  "  ║  ${NC}[7] Remote (SSH + Dashboard)  $(_pill "part7-remote") ${CYAN}${BOLD}     ║\n"

  # ── Grupo PROOT ───────────────────────────────────────────
  echo -e "  ║  ${NC}${DIM}── PROOT DEBIAN ──────────────────────${NC}${CYAN}${BOLD}  ║"
  printf  "  ║  ${NC}[5] n8n + cloudflared         $(_pill "part5-n8n-data") ${CYAN}${BOLD}     ║\n"
  printf  "  ║  ${NC}[8] OpenCode                  $(_pill "part8-opencode") ${CYAN}${BOLD}     ║\n"
  printf  "  ║  ${NC}[9] OpenClaw                  $(_pill "part9-openclaw") ${CYAN}${BOLD}     ║\n"

  # ── Grupo ROOTFS ──────────────────────────────────────────
  echo -e "  ║  ${NC}${DIM}── ROOTFS ────────────────────────────${NC}${CYAN}${BOLD}  ║"
  printf  "  ║  ${NC}[6b] Debian limpio            $(_pill "part6-proot-base") ${CYAN}${BOLD}     ║\n"
  printf  "  ║  ${NC}[6c] Debian completo          $(_pill "part6-proot-completo") ${CYAN}${BOLD}     ║\n"

  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}[a] Todo   [q] Salir${CYAN}${BOLD}                    ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  [ "$SOURCE" = "github" ] && \
    echo -e "  ${DIM}✓ disponible  ○ no en este release${NC}" || \
    echo -e "  ${DIM}✓ en backup local  ○ no encontrado${NC}"
  echo ""
  echo -n "  Opción: "
  read -r OPT_MOD < /dev/tty

  case "$OPT_MOD" in
    0)    TARGET_MODULE="base"           ;;
    2)    TARGET_MODULE="claude"         ;;
    2b)   TARGET_MODULE="claude-native"  ;;
    3)    TARGET_MODULE="expo"           ;;
    4)    TARGET_MODULE="ollama"         ;;
    5)    TARGET_MODULE="n8n"            ;;
    6b)   TARGET_MODULE="proot-base"     ;;
    6c)   TARGET_MODULE="proot-completo" ;;
    7)    TARGET_MODULE="remote"         ;;
    8)    TARGET_MODULE="opencode"       ;;
    9)    TARGET_MODULE="openclaw"       ;;
    a|A)  TARGET_MODULE="all"            ;;
    q|Q)  echo "Cancelado."; exit 0      ;;
    *)    error "Opción inválida"        ;;
  esac
}

# ════════════════════════════════════════════════════════════
# GitHub API
# ════════════════════════════════════════════════════════════
RELEASE_JSON=""
RELEASE_TAG=""

# ── Tabla fija de partes (número → identificador en nombre de archivo) ────
# El número es permanente — el nombre del archivo puede tener fecha/versión
# pero SIEMPRE empieza con partN- donde N es el número de parte
declare -A PART_NAMES=(
  [0]="part0-termux-base"
  [2]="part2-claude-code"
  [2b]="part2b-claude-native"
  [3]="part3-eas-expo"
  [4s]="part4-ollama-standard"
  [4o]="part4-ollama-optimized"
  [4v]="part4-ollama-vulkan"
  [5]="part5-n8n-data"
  [6b]="part6-proot-base"
  [6c]="part6-proot-completo"
  [7]="part7-remote"
  [8]="part8-opencode"
  [9]="part9-openclaw"
)
declare -A PART_LABELS=(
  [0]="Termux base (scripts + tema + configs)"
  [2]="Claude Code legacy (npm · v2.1.111)"
  [2b]="Claude Code native (glibc-runner · v2.1.152+)"
  [3]="Expo / EAS CLI"
  [4s]="Ollama estándar"
  [4o]="Ollama optimizado (i8mm+dotprod)"
  [4v]="Ollama Vulkan GPU"
  [5]="n8n + cloudflared"
  [6b]="Proot Debian limpio"
  [6c]="Proot Debian completo (n8n + OpenCode + OpenClaw)"
  [7]="Remote (SSH + Dashboard)"
  [8]="OpenCode"
  [9]="OpenClaw (NVM + Node22)"
)

fetch_release_json() {
  RELEASE_JSON=$(curl -fsSL "$GITHUB_API" 2>/dev/null)
  [ -z "$RELEASE_JSON" ] && error "No se pudo obtener el release de GitHub\n  Verifica tu conexión"
  RELEASE_TAG=$(echo "$RELEASE_JSON" | grep '"tag_name"' | grep -o '"v[^"]*"' | tr -d '"' | head -1)
}

# Busca por prefijo de parte: part2-* encontrará part2-claude-code-20260418_1714.tar.xz
get_part_url() {
  local PART_PREFIX="$1"
  echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*'"${PART_PREFIX}"'[^"]*"' \
    | grep -o 'https://[^"]*' | head -1
}

get_checksums_url() {
  echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*checksums[^"]*"' \
    | grep -o 'https://[^"]*' | head -1
}

# ════════════════════════════════════════════════════════════
# DESCARGAR Y VERIFICAR
# ════════════════════════════════════════════════════════════
DOWNLOADED_FILE=""

download_and_verify() {
  local PART_NAME="$1"
  local FILE_URL=""
  local FILENAME=""

  mkdir -p "$TMP_DIR"

  if [ "$SOURCE" = "github" ]; then
    [ -z "$RELEASE_JSON" ] && fetch_release_json
    FILE_URL=$(get_part_url "$PART_NAME")
    [ -z "$FILE_URL" ] && error "No se encontró '$PART_NAME' en el último release de GitHub"
    FILENAME=$(basename "$FILE_URL")
    info "Descargando $FILENAME..."
    DOWNLOADED_FILE="$TMP_DIR/$FILENAME"
    # Progress bar: curl escribe el progreso a stderr — NO redirigir stderr a /dev/null
    # En Termux el --progress-bar funciona correctamente cuando stderr está libre
    if command -v curl &>/dev/null; then
      curl -fL --progress-bar "$FILE_URL" -o "$DOWNLOADED_FILE"
    else
      wget --progress=bar:force -O "$DOWNLOADED_FILE" "$FILE_URL" 2>&1
    fi
    [ ! -s "$DOWNLOADED_FILE" ] && error "Descarga fallida o archivo vacío: $FILENAME"

    # Verificar checksum si hay checksums.txt
    CHECKSUMS_URL=$(get_checksums_url)
    if [ -n "$CHECKSUMS_URL" ]; then
      CHECKSUMS_FILE="$TMP_DIR/checksums.txt"
      curl -fsSL "$CHECKSUMS_URL" -o "$CHECKSUMS_FILE" 2>/dev/null
      if [ -f "$CHECKSUMS_FILE" ]; then
        EXPECTED=$(grep "$FILENAME" "$CHECKSUMS_FILE" 2>/dev/null | cut -d' ' -f1)
        if [ -n "$EXPECTED" ]; then
          ACTUAL=$(sha256sum "$DOWNLOADED_FILE" 2>/dev/null | cut -d' ' -f1)
          if [ "$EXPECTED" = "$ACTUAL" ]; then
            log "SHA256 verificado ✓"
          else
            warn "SHA256 no coincide — el archivo puede estar corrupto"
            warn "  Esperado: ${EXPECTED:0:20}..."
            warn "  Actual:   ${ACTUAL:0:20}..."
          fi
        fi
      fi
    fi
  else
    # Fuente local
    LOCAL_FILE=$(ls "$LOCAL_DIR"/*${PART_NAME}*.tar.xz 2>/dev/null | sort -r | head -1)
    [ -z "$LOCAL_FILE" ] && error "No se encontró '$PART_NAME' en $LOCAL_DIR"
    FILENAME=$(basename "$LOCAL_FILE")
    info "Usando backup local: $FILENAME"
    DOWNLOADED_FILE="$LOCAL_FILE"
  fi

  log "Archivo listo: $FILENAME ($(du -h "$DOWNLOADED_FILE" | cut -f1))"
}

# ════════════════════════════════════════════════════════════
# Helper: actualizar registry
# ════════════════════════════════════════════════════════════
update_registry() {
  local module="$1"
  local version="$2"
  local date_now
  date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^${module}\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
${module}.installed=true
${module}.version=${version}
${module}.install_date=${date_now}
${module}.location=restored
EOF
  mv "$tmp" "$REGISTRY"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 0 — Termux base
# ════════════════════════════════════════════════════════════
restore_part0() {
  titulo "PARTE 0 — Termux base (scripts + tema + configs)"

  download_and_verify "part0-termux-base"

  EXTRACT_TMP="$TMP_DIR/base_extract"
  mkdir -p "$EXTRACT_TMP"
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null

  # Scripts al home
  if [ -d "$EXTRACT_TMP/home" ]; then
    # Copiar scripts de raíz (~/)
    for f in "$EXTRACT_TMP/home/"*.sh; do
      [ -f "$f" ] && cp "$f" "$HOME/" && chmod +x "$HOME/$(basename "$f")"
    done
    # Copiar Python scripts de raíz
    for f in "$EXTRACT_TMP/home/"*.py; do
      [ -f "$f" ] && cp "$f" "$HOME/"
    done
    # Copiar subcarpetas ~/scripts/* (módulos de menú + scripts generados)
    for subdir in scripts scripts/n8n scripts/ollama scripts/remote \
                  scripts/openclaw scripts/opencode scripts/expo; do
      src="$EXTRACT_TMP/home/$subdir"
      [ -d "$src" ] || continue
      mkdir -p "$HOME/$subdir"
      for f in "$src/"*; do
        [ -f "$f" ] || continue
        cp "$f" "$HOME/$subdir/"
        [[ "$f" == *.sh ]] && chmod +x "$HOME/$subdir/$(basename "$f")"
      done
    done
    log "Scripts copiados a ~/ y ~/scripts/"
  fi

  # Registry — restaurar solo claves base, preservar estado de módulos existentes
  if [ -f "$EXTRACT_TMP/home/.android_server_registry" ]; then
    if [ -f "$REGISTRY" ]; then
      # Combinar: claves base del backup + claves de módulos del actual
      # El backup de part0 NO tiene claves de módulos (por diseño)
      # pero por si acaso, filtramos para no sobreescribir estado de módulos instalados
      local TMP_REG="$REGISTRY.merge"
      # Claves base del backup (sin módulos)
      grep -v "^ssh\.\|^dashboard\.\|^claude_code\.\|^ollama\.\|^n8n\.\|^expo\.\|^python\."         "$EXTRACT_TMP/home/.android_server_registry" > "$TMP_REG" 2>/dev/null || touch "$TMP_REG"
      # Preservar claves de módulos del registry actual
      grep "^ssh\.\|^dashboard\.\|^claude_code\.\|^ollama\.\|^n8n\.\|^expo\.\|^python\."         "$REGISTRY" >> "$TMP_REG" 2>/dev/null || true
      mv "$TMP_REG" "$REGISTRY"
    else
      cp "$EXTRACT_TMP/home/.android_server_registry" "$REGISTRY"
    fi
    log "Registry restaurado (claves base + módulos existentes preservados)"
  fi

  # Tema Termux (.termux — colores, fuente, extra-keys)
  if [ -d "$EXTRACT_TMP/termux_config/.termux" ]; then
    mkdir -p "$HOME/.termux"
    cp -r "$EXTRACT_TMP/termux_config/.termux/." "$HOME/.termux/"
    command -v termux-reload-settings &>/dev/null && termux-reload-settings 2>/dev/null
    log "Tema Termux restaurado (.termux)"
  fi

  # .bashrc
  if [ -f "$EXTRACT_TMP/home/.bashrc" ]; then
    cp "$EXTRACT_TMP/home/.bashrc" "$HOME/.bashrc"
    log ".bashrc restaurado"
  fi

  # .env_n8n si existe
  [ -f "$EXTRACT_TMP/home/.env_n8n" ] && cp "$EXTRACT_TMP/home/.env_n8n" "$HOME/.env_n8n"

  update_registry "termux_base" "restored"
  log "Termux base restaurado ✓"
  echo -e "  ${CYAN}Siguiente:${NC} source ~/.bashrc  (o reinicia Termux)"
  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 2 — Claude Code
# ════════════════════════════════════════════════════════════
restore_part2() {
  titulo "PARTE 2 — Claude Code"

  download_and_verify "part2-claude-code"

  EXTRACT_TMP="$TMP_DIR/claude_extract"
  mkdir -p "$EXTRACT_TMP"
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null

  if [ -d "$EXTRACT_TMP/npm_modules/@anthropic-ai" ]; then
    mkdir -p "$NPM_GLOBAL"
    rm -rf "$NPM_GLOBAL/@anthropic-ai" 2>/dev/null
    cp -r "$EXTRACT_TMP/npm_modules/@anthropic-ai" "$NPM_GLOBAL/"
    log "npm @anthropic-ai restaurado desde release"
  else
    error "No se encontró npm_modules/@anthropic-ai en el archivo"
  fi

  CLI_PATH="$NPM_GLOBAL/@anthropic-ai/claude-code/cli.js"

  # ── VALIDACIÓN CRÍTICA: verificar que cli.js es JS válido ────────
  # El backup puede haber sido hecho con cli.js corrompido (wrapper bash).
  # Si está corrompido, hacemos fallback automático a npm install.
  CLI_VALID=false
  if [ -f "$CLI_PATH" ] && [ -s "$CLI_PATH" ]; then
    FIRST_LINE=$(head -1 "$CLI_PATH" 2>/dev/null)
    if echo "$FIRST_LINE" | grep -q "^#!/.*bash"; then
      warn "cli.js en el backup es un wrapper bash (backup hecho antes del fix)"
      warn "Haciendo fallback a npm install..."
      CLI_VALID=false
    elif node "$CLI_PATH" --version 2>&1 | grep -qv "SyntaxError\|not found"; then
      CLI_VALID=true
      log "cli.js validado como JavaScript correcto ✓"
    else
      warn "cli.js existe pero node no puede ejecutarlo"
      CLI_VALID=false
    fi
  fi

  if [ "$CLI_VALID" = "false" ]; then
    warn "Instalando via npm como fallback (más confiable)..."
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
    npm cache clean --force 2>/dev/null || true
    npm install -g @anthropic-ai/claude-code@2.1.111 2>&1 | tail -5
    CLI_PATH="$NPM_GLOBAL/@anthropic-ai/claude-code/cli.js"
    if [ -f "$CLI_PATH" ] && node "$CLI_PATH" --version 2>&1 | grep -qv "SyntaxError"; then
      log "Claude Code instalado via npm fallback ✓"
    else
      error "Ni el backup ni npm funcionaron. Intenta instalar limpio desde el menú."
    fi
  fi

  # Crear/actualizar wrapper ejecutable
  WRAPPER="${TERMUX_PREFIX}/bin/claude"
  cat > "$WRAPPER" << WRAPPER_SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
exec node "${CLI_PATH}" "\$@"
WRAPPER_SCRIPT
  chmod +x "$WRAPPER"
  log "Wrapper /usr/bin/claude creado ✓"

  # Validar
  if [ -f "$CLI_PATH" ] && node "$CLI_PATH" --version 2>&1 | grep -qv "SyntaxError"; then
    VERSION_CC=$(node "$CLI_PATH" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    update_registry "claude_code" "${VERSION_CC:-restored}"
    log "Claude Code restaurado y validado ✓ (v${VERSION_CC})"
  else
    warn "cli.js restaurado pero no validó — puede requerir reinstalación"
  fi

  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 2b — Claude Code Native (glibc-runner)
# ════════════════════════════════════════════════════════════
restore_part2b() {
  titulo "PARTE 2b — Claude Code Native (glibc-runner)"

  # Verificar/instalar glibc-runner antes de extraer
  local GLIBC_LD="${TERMUX_PREFIX}/glibc/lib/ld-linux-aarch64.so.1"
  if [ ! -f "$GLIBC_LD" ]; then
    info "Instalando glibc-runner (requerido por Claude native)..."
    pkg install -y glibc-repo 2>/dev/null || true
    pkg update -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>&1 | tail -2
    pkg install -y glibc-runner patchelf-glibc \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      error "No se pudo instalar glibc-runner"
  fi
  [ -f "$GLIBC_LD" ] || error "glibc ld.so no encontrado en $GLIBC_LD"
  log "glibc-runner disponible ✓"

  download_and_verify "part2b-claude-native"

  local EXTRACT_TMP="$TMP_DIR/claude_native_extract"
  mkdir -p "$EXTRACT_TMP"
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null

  # Instalar binario — ya viene parcheado, NO re-patchear
  local NATIVE_BIN="$EXTRACT_TMP/bin/claude"
  [ -f "$NATIVE_BIN" ] || error "binario claude no encontrado en el backup"

  mkdir -p "$HOME/.local/share/claude-code" "$HOME/.local/bin"
  cp "$NATIVE_BIN" "$HOME/.local/share/claude-code/claude"
  chmod +x "$HOME/.local/share/claude-code/claude"
  log "Binario instalado en ~/.local/share/claude-code/claude ✓"

  # Restaurar o recrear wrapper
  if [ -f "$EXTRACT_TMP/wrapper/claude" ]; then
    cp "$EXTRACT_TMP/wrapper/claude" "$HOME/.local/bin/claude"
    chmod +x "$HOME/.local/bin/claude"
    log "Wrapper restaurado ✓"
  else
    # Recrear wrapper si no está en el backup
    cat > "$HOME/.local/bin/claude" << 'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
unset LD_PRELOAD
exec "$HOME/.local/share/claude-code/claude" "$@"
WRAPPER
    chmod +x "$HOME/.local/bin/claude"
    log "Wrapper recreado ✓"
  fi

  # Restaurar settings.json
  if [ -f "$EXTRACT_TMP/settings/settings.json" ]; then
    mkdir -p "$HOME/.claude"
    cp "$EXTRACT_TMP/settings/settings.json" "$HOME/.claude/settings.json"
    log "settings.json restaurado ✓"
  else
    mkdir -p "$HOME/.claude"
    cat > "$HOME/.claude/settings.json" << 'SETTINGS'
{
  "autoUpdates": false,
  "env": {
    "LD_PRELOAD": "/data/data/com.termux/files/usr/lib/libtermux-exec-ld-preload.so"
  }
}
SETTINGS
    log "settings.json recreado ✓"
  fi

  # Agregar ~/.local/bin al PATH si no está
  if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    export PATH="$HOME/.local/bin:$PATH"
    log "~/.local/bin agregado a PATH"
  fi

  # Verificar
  local VER_CHECK
  VER_CHECK=$("$HOME/.local/bin/claude" --version 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$VER_CHECK" ] \
    && log "Claude native v${VER_CHECK} funcionando ✓" \
    || warn "Restaurado pero --version no respondió — verifica con: claude --version"

  # Registry — usar función helper existente con campos extra
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^claude_code\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
claude_code.installed=true
claude_code.version=${VER_CHECK:-restored}
claude_code.method=native
claude_code.install_date=$(date +%Y-%m-%d)
claude_code.location=termux_native
EOF
  mv "$tmp" "$REGISTRY"

  rm -rf "$EXTRACT_TMP"
}
restore_part3() {
  titulo "PARTE 3 — Expo / EAS CLI"

  download_and_verify "part3-eas-expo"

  EXTRACT_TMP="$TMP_DIR/expo_extract"
  mkdir -p "$EXTRACT_TMP"
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null

  if [ -d "$EXTRACT_TMP/npm_modules/eas-cli" ]; then
    mkdir -p "$NPM_GLOBAL"
    rm -rf "$NPM_GLOBAL/eas-cli" 2>/dev/null
    cp -r "$EXTRACT_TMP/npm_modules/eas-cli" "$NPM_GLOBAL/"
    ln -sf "$NPM_GLOBAL/eas-cli/bin/eas" "${TERMUX_PREFIX}/bin/eas" 2>/dev/null
    chmod +x "${TERMUX_PREFIX}/bin/eas" 2>/dev/null
    log "eas-cli restaurado"
  fi

  [ -d "$EXTRACT_TMP/home/.expo" ] && {
    cp -r "$EXTRACT_TMP/home/.expo" "$HOME/"
    log "~/.expo restaurado"
  }

  EAS_VER=$(node "$NPM_GLOBAL/eas-cli/bin/eas" --version 2>/dev/null | head -1)
  [ -z "$EAS_VER" ] && EAS_VER="restored"
  update_registry "expo" "$EAS_VER"
  log "Expo / EAS restaurado ✓"
  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 4 — Ollama
# ════════════════════════════════════════════════════════════
restore_part4() {
  titulo "PARTE 4 — Ollama (sin modelos)"

  # Detectar hardware para recomendar variante
  local HW_CPU_FEAT
  HW_CPU_FEAT=$(grep -m1 -i "^Features" /proc/cpuinfo 2>/dev/null)
  local HW_REC="standard"
  echo "$HW_CPU_FEAT" | grep -qE "i8mm|dotprod|asimddp" && HW_REC="optimized"

  # Ver qué variantes hay disponibles en el release
  if [ "$SOURCE" = "github" ]; then
    [ -z "$RELEASE_JSON" ] && fetch_release_json
    local URL_STD URL_OPT URL_VLK
    URL_STD=$(get_part_url "part4-ollama-standard")
    URL_OPT=$(get_part_url "part4-ollama-optimized")
    URL_VLK=$(get_part_url "part4-ollama-vulkan")

    echo ""
    echo -e "  ${CYAN}Variantes disponibles:${NC}"
    [ -n "$URL_STD" ] && echo -e "  ${GREEN}[1]${NC} Estándar   — part4-ollama-standard" \
                      || echo -e "  ${YELLOW}[1]${NC} Estándar   — no disponible en este release"
    [ -n "$URL_OPT" ] && echo -e "  ${GREEN}[2]${NC} Optimizada — part4-ollama-optimized$([ "$HW_REC" = "optimized" ] && echo " ★ recomendado")" \
                      || echo -e "  ${YELLOW}[2]${NC} Optimizada — no disponible en este release"
    [ -n "$URL_VLK" ] && echo -e "  ${GREEN}[3]${NC} Vulkan     — part4-ollama-vulkan" \
                      || echo -e "  ${YELLOW}[3]${NC} Vulkan     — no disponible en este release"
    echo ""
    echo -n "  Variante [1/2/3]: "
    read -r OL_V < /dev/tty

    local OL_PART_KEY
    case "$OL_V" in
      2) OL_PART_KEY="part4-ollama-optimized" ;;
      3) OL_PART_KEY="part4-ollama-vulkan"    ;;
      *) OL_PART_KEY="part4-ollama-standard"  ;;
    esac

    # Verificar que la variante elegida existe
    local CHOSEN_URL
    CHOSEN_URL=$(get_part_url "$OL_PART_KEY")
    if [ -z "$CHOSEN_URL" ]; then
      warn "La variante '${OL_PART_KEY}' no está en el release actual"
      warn "Instala Ollama limpio desde el menú: bash ~/install_ollama.sh"
      return 0
    fi
  else
    # Fuente local: preguntar variante
    echo -n "  Variante [1=standard/2=optimized/3=vulkan]: "
    read -r OL_V < /dev/tty
    case "$OL_V" in
      2) OL_PART_KEY="part4-ollama-optimized" ;;
      3) OL_PART_KEY="part4-ollama-vulkan"    ;;
      *) OL_PART_KEY="part4-ollama-standard"  ;;
    esac
  fi

  download_and_verify "$OL_PART_KEY"

  EXTRACT_TMP="$TMP_DIR/ollama_extract"
  mkdir -p "$EXTRACT_TMP"
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null

  [ -f "$EXTRACT_TMP/bin/ollama" ] && {
    cp "$EXTRACT_TMP/bin/ollama" "${TERMUX_PREFIX}/bin/ollama"
    chmod +x "${TERMUX_PREFIX}/bin/ollama"
    log "Binario ollama restaurado"
  }

  # llama-server y llama-cli para versiones compiladas
  [ -f "$EXTRACT_TMP/bin/llama-server" ] && {
    cp "$EXTRACT_TMP/bin/llama-server" "${TERMUX_PREFIX}/bin/llama-server"
    chmod +x "${TERMUX_PREFIX}/bin/llama-server"
    log "llama-server restaurado"
  }
  [ -f "$EXTRACT_TMP/bin/llama-cli" ] && {
    cp "$EXTRACT_TMP/bin/llama-cli" "${TERMUX_PREFIX}/bin/llama-cli"
    chmod +x "${TERMUX_PREFIX}/bin/llama-cli"
    log "llama-cli restaurado"
  }

  [ -d "$EXTRACT_TMP/lib_ollama" ] && {
    cp -r "$EXTRACT_TMP/lib_ollama" "${TERMUX_PREFIX}/lib/ollama"
    log "Librerías ollama restauradas"
  }

  [ -d "$EXTRACT_TMP/home" ] && {
    mkdir -p "$HOME/scripts/ollama"
    for f in "$EXTRACT_TMP/home/"*.sh; do
      [ -f "$f" ] && cp "$f" "$HOME/scripts/ollama/"
    done
    chmod +x "$HOME/scripts/ollama/ollama_start.sh" \
             "$HOME/scripts/ollama/ollama_stop.sh" 2>/dev/null
    log "Scripts ollama restaurados en ~/scripts/ollama/"
  }

  update_registry "ollama" "${OL_PART_KEY##*-}"
  log "Ollama restaurado ✓ (${OL_PART_KEY})"
  echo -e "  ${YELLOW}⚠${NC}  Modelos NO incluidos — descarga con: ollama pull qwen2.5:0.5b"
  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 5 — n8n + cloudflared
# ════════════════════════════════════════════════════════════
restore_part5() {
  titulo "PARTE 5 — n8n + cloudflared"
  _ensure_proot_pkg

  if [ -z "$DISTRO_NAME" ]; then
    echo -e "  ${YELLOW}${BOLD}⚠  Proot Debian no encontrado${NC}"
    echo -e "  n8n requiere el contenedor Debian (part6)."
    echo ""
    echo -n "  ¿Instalar rootfs Debian ahora? (s/n): "
    read -r DO_PROOT < /dev/tty
    if [ "$DO_PROOT" = "s" ] || [ "$DO_PROOT" = "S" ]; then
      restore_part6
      detect_distro
      [ -z "$DISTRO_NAME" ] && error "El proot no quedó disponible — abortando"
      log "Proot listo — continuando con n8n..."
    else
      warn "Restauración de n8n cancelada"
      return 0
    fi
  fi

  download_and_verify "part5-n8n-data"

  local FILE_SIZE
  FILE_SIZE=$(wc -c < "$DOWNLOADED_FILE" 2>/dev/null)
  [ -z "$FILE_SIZE" ] || [ "$FILE_SIZE" -lt 1024 ] && \
    error "Archivo descargado corrupto (${FILE_SIZE:-0} bytes)"

  # Copiar archivo al rootfs host — accesible como /root/n8n_restore_tmp.tar.xz dentro del proot
  # NO usamos stdin: proot-distro login consume el stdin antes de que bash -c lo lea
  # NO usamos /tmp del proot: Android 15 tmpfs independiente (ver ARCHITECTURE §3.11)
  local N8N_TMP="${ROOTFS_PATH}/root/n8n_restore_tmp.tar.xz"
  info "Copiando archivo al rootfs para extracción interna..."
  cp "$DOWNLOADED_FILE" "$N8N_TMP" || error "No se pudo copiar archivo al rootfs"

  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
     mkdir -p /usr/local/lib/node_modules /usr/local/bin /usr/lib/node_modules /usr/bin /root/.n8n
     echo "[INFO] Extrayendo n8n desde /root/n8n_restore_tmp.tar.xz..."
     tar -xJf /root/n8n_restore_tmp.tar.xz -C / 2>/dev/null || \
       tar -xJf /root/n8n_restore_tmp.tar.xz -C / --ignore-failed-read 2>/dev/null || \
       { echo "[ERROR] Extraccion fallida"; rm -f /root/n8n_restore_tmp.tar.xz; exit 1; }
     rm -f /root/n8n_restore_tmp.tar.xz
     [ -f /usr/local/bin/n8n ]         && chmod +x /usr/local/bin/n8n
     [ -f /usr/bin/n8n ]               && chmod +x /usr/bin/n8n
     [ -f /usr/local/bin/cloudflared ] && chmod +x /usr/local/bin/cloudflared
     [ -f /usr/local/bin/node ]        && chmod +x /usr/local/bin/node
     [ -f /usr/bin/node ]              && chmod +x /usr/bin/node
     { [ -f /usr/local/bin/n8n ] || [ -f /usr/bin/n8n ]; } && \
       echo "[OK] n8n verificado" || echo "[AVISO] n8n no encontrado en PATH"
     echo "[DONE]"'

  local N8N_EXIT=$?
  rm -f "$N8N_TMP" 2>/dev/null
  [ $N8N_EXIT -ne 0 ] && error "Fallo la restauración de n8n"

  N8N_VER=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    "cat /usr/local/lib/node_modules/n8n/package.json 2>/dev/null" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" 2>/dev/null)
  [ -z "$N8N_VER" ] && N8N_VER="restored"
  update_registry "n8n" "$N8N_VER"
  log "n8n + cloudflared restaurado ✓"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 6 — Proot Debian
# ════════════════════════════════════════════════════════════
restore_part6() {
  local PROOT_VARIANT="${1:-proot-base}"  # default: base limpio
  titulo "PARTE 6 — Proot Debian (${PROOT_VARIANT})"
  _ensure_proot_pkg

  if [ -n "$DISTRO_NAME" ]; then
    echo -e "  ${YELLOW}${BOLD}⚠  Se sobreescribirá el rootfs: $DISTRO_NAME${NC}"
    echo -e "  ${YELLOW}Todos los datos del proot actual se perderán.${NC}"
    echo ""
    echo -n "  ¿Continuar? (s/n): "
    read -r CONFIRM_P6 < /dev/tty
    [ "$CONFIRM_P6" != "s" ] && [ "$CONFIRM_P6" != "S" ] && { warn "Cancelado."; return 0; }
  fi

  download_and_verify "$PROOT_VARIANT"
  mkdir -p "$ROOTFS_BASE"

  info "Detectando nombre del distro en el archivo..."
  DISTRO_IN_TAR=$(tar -tJf "$DOWNLOADED_FILE" 2>/dev/null | head -1 | cut -d'/' -f1)
  [ -z "$DISTRO_IN_TAR" ] && error "No se pudo leer el contenido del archive ${PROOT_VARIANT}"
  info "Distro detectada: $DISTRO_IN_TAR"

  [ -d "$ROOTFS_BASE/$DISTRO_IN_TAR" ] && {
    warn "Eliminando rootfs anterior..."
    rm -rf "$ROOTFS_BASE/$DISTRO_IN_TAR"
  }

  echo -e "  ${YELLOW}Extrayendo rootfs — puede tardar 10-20 min...${NC}"
  tar -xJf "$DOWNLOADED_FILE" -C "$ROOTFS_BASE" 2>/dev/null || \
    error "Error al extraer ${PROOT_VARIANT}"

  detect_distro
  PROOT_VER=$(proot-distro login "$DISTRO_IN_TAR" -- bash -c \
    "cat /etc/debian_version 2>/dev/null" 2>/dev/null | tr -d '\n')
  [ -z "$PROOT_VER" ] && PROOT_VER=$(pkg show proot-distro 2>/dev/null | grep "^Version:" | awk '{print $2}')
  [ -z "$PROOT_VER" ] && PROOT_VER="restored"
  update_registry "proot" "$PROOT_VER"
  log "Proot Debian restaurado ✓ ($DISTRO_IN_TAR / ${PROOT_VARIANT})"

  # Si restauramos el rootfs base y n8n está en otro backup, avisar
  if [ "$PROOT_VARIANT" = "part6-proot-base" ]; then
    echo ""
    echo -e "  ${CYAN}Rootfs base restaurado.${NC}"
    echo -e "  Para instalar n8n: restore módulo 'n8n' o usar el menú."
  fi
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 7 — Remote (SSH + Dashboard)
# NUEVO en v2.5.0
# ════════════════════════════════════════════════════════════
restore_part7() {
  titulo "PARTE 7 — Remote (SSH + Dashboard configs)"

  download_and_verify "part7-remote"

  EXTRACT_TMP="$TMP_DIR/remote_extract"
  mkdir -p "$EXTRACT_TMP"
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null

  # ── SSH: configuración ────────────────────────────────────
  if [ -f "$EXTRACT_TMP/ssh_config/sshd_config" ]; then
    mkdir -p "${TERMUX_PREFIX}/etc/ssh"
    cp "$EXTRACT_TMP/ssh_config/sshd_config" "$SSHD_CONFIG"
    log "sshd_config restaurado (puerto 8022)"
  fi

  # ── SSH: Cloudflared token ────────────────────────────────
  if [ -f "$EXTRACT_TMP/ssh_config/.cf_ssh_token" ]; then
    cp "$EXTRACT_TMP/ssh_config/.cf_ssh_token" "$HOME/.cf_ssh_token"
    log "Token cloudflared SSH restaurado"
  fi

  # ── SSH: authorized_keys ──────────────────────────────────
  if [ -f "$EXTRACT_TMP/ssh_keys/authorized_keys" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    cp "$EXTRACT_TMP/ssh_keys/authorized_keys" "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    KEYS_COUNT=$(wc -l < "$HOME/.ssh/authorized_keys" 2>/dev/null)
    log "authorized_keys restaurado ($KEYS_COUNT claves)"
  fi

  # ── SSH: scripts de control ───────────────────────────────
  mkdir -p "$HOME/scripts/remote"
  for f in "$EXTRACT_TMP/home/"*.sh; do
    [ -f "$f" ] && cp "$f" "$HOME/scripts/remote/" && \
      chmod +x "$HOME/scripts/remote/$(basename "$f")"
  done

  # ── Dashboard ────────────────────────────────────────────
  for f in dashboard_server.py dashboard_start.sh dashboard_stop.sh index.html; do
    [ -f "$EXTRACT_TMP/dashboard/$f" ] && {
      cp "$EXTRACT_TMP/dashboard/$f" "$HOME/scripts/remote/$f"
      [[ "$f" == *.sh ]] && chmod +x "$HOME/scripts/remote/$f"
      log "$f restaurado en ~/scripts/remote/"
    }
  done

  # ── Instalar openssh si no está ───────────────────────────
  if ! command -v sshd &>/dev/null; then
    warn "openssh no encontrado — instalando..."
    pkg install openssh -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>/dev/null
    log "openssh instalado"
  fi

  # ── Generar claves del servidor si no existen ─────────────
  if ! ls "${TERMUX_PREFIX}/etc/ssh/ssh_host_"*"_key" &>/dev/null 2>&1; then
    ssh-keygen -A 2>/dev/null
    log "Claves del servidor generadas"
  fi

  update_registry "ssh" "$(ssh -V 2>&1 | awk '{print $1}' | tr -d 'OpenSSH_' | head -1)"
  update_registry "dashboard" "restored"
  log "Remote (SSH + Dashboard) restaurado ✓"
  echo -e "  ${CYAN}Para SSH:${NC}       bash ~/scripts/remote/ssh_start.sh"
  echo -e "  ${CYAN}Para Dashboard:${NC}  bash ~/scripts/remote/dashboard_start.sh"
  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 8 — OpenCode
# ════════════════════════════════════════════════════════════
restore_part8() {
  titulo "PARTE 8 — OpenCode (en proot)"
  _ensure_proot_pkg

  if [ -z "$DISTRO_NAME" ]; then
    echo -e "  ${YELLOW}${BOLD}⚠  Proot Debian no encontrado${NC}"
    echo -e "  OpenCode requiere el contenedor Debian (part6)."
    echo ""
    echo -n "  ¿Instalar rootfs Debian ahora? (s/n): "
    read -r DO_PROOT < /dev/tty
    if [ "$DO_PROOT" = "s" ] || [ "$DO_PROOT" = "S" ]; then
      restore_part6 "part6-proot-base"
      detect_distro
      [ -z "$DISTRO_NAME" ] && error "El proot no quedó disponible — abortando"
      log "Proot listo — continuando con OpenCode..."
    else
      warn "Restauración de OpenCode cancelada"
      return 0
    fi
  fi

  download_and_verify "part8-opencode"
  
  # Copiar archivo al rootfs host — accesible como /root/oc_restore_tmp.tar.xz dentro del proot
  # NO usamos stdin: proot-distro login consume el stdin antes de que bash -c lo lea
  # NO usamos /tmp del proot: Android 15 tmpfs independiente (ver ARCHITECTURE §3.11)
  local OC_TMP="${ROOTFS_PATH}/root/oc_restore_tmp.tar.xz"
  info "Copiando archivo al rootfs para extracción interna..."
  cp "$DOWNLOADED_FILE" "$OC_TMP" || { warn "No se pudo copiar archivo al rootfs"; return 1; }

  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
     echo "[INFO] Extrayendo OpenCode desde /root/oc_restore_tmp.tar.xz..."
     tar -xJf /root/oc_restore_tmp.tar.xz -C / 2>/dev/null || \
       tar -xJf /root/oc_restore_tmp.tar.xz -C / --ignore-failed-read 2>/dev/null || {
         echo "[ERROR] Extracción fallida"
         rm -f /root/oc_restore_tmp.tar.xz
         exit 1
       }
     rm -f /root/oc_restore_tmp.tar.xz
     command -v opencode >/dev/null 2>&1 && echo "[OK] opencode verificado" || echo "[AVISO] opencode no encontrado en PATH"
     echo "[DONE]"'

  local OC_EXIT=$?
  rm -f "$OC_TMP" 2>/dev/null
  [ $OC_EXIT -ne 0 ] && { warn "Fallo restaurando OpenCode"; return 1; }

  OC_VER=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'source ~/.bashrc 2>/dev/null; opencode --version 2>/dev/null | head -1' 2>/dev/null | \
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$OC_VER" ] && OC_VER="restored"
  update_registry "opencode" "$OC_VER"
  log "OpenCode restaurado ✓"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 9 — OpenClaw
# ════════════════════════════════════════════════════════════
restore_part9() {
  titulo "PARTE 9 — OpenClaw (NVM + Node22 + OpenClaw en proot)"
  _ensure_proot_pkg

  if [ -z "$DISTRO_NAME" ]; then
    echo -e "  ${YELLOW}${BOLD}⚠  Proot Debian no encontrado${NC}"
    echo -e "  OpenClaw requiere el contenedor Debian (part6)."
    echo ""
    echo -n "  ¿Instalar rootfs Debian ahora? (s/n): "
    read -r DO_PROOT < /dev/tty
    if [ "$DO_PROOT" = "s" ] || [ "$DO_PROOT" = "S" ]; then
      restore_part6 "part6-proot-base"
      detect_distro
      [ -z "$DISTRO_NAME" ] && error "El proot no quedó disponible — abortando"
      log "Proot listo — continuando con OpenClaw..."
    else
      warn "Restauración de OpenClaw cancelada"
      return 0
    fi
  fi

  download_and_verify "part9-openclaw"
  
  # Copiar archivo al rootfs host — accesible como /root/ocl_restore_tmp.tar.xz dentro del proot
  # NO usamos stdin: proot-distro login consume el stdin antes de que bash -c lo lea
  # NO usamos /tmp del proot: Android 15 tmpfs independiente (ver ARCHITECTURE §3.11)
  local OCL_TMP="${ROOTFS_PATH}/root/ocl_restore_tmp.tar.xz"
  info "Copiando archivo al rootfs para extracción interna..."
  cp "$DOWNLOADED_FILE" "$OCL_TMP" || { warn "No se pudo copiar archivo al rootfs"; return 1; }

  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
     echo "[INFO] Extrayendo OpenClaw desde /root/ocl_restore_tmp.tar.xz..."
     tar -xJf /root/ocl_restore_tmp.tar.xz -C / 2>/dev/null || \
       tar -xJf /root/ocl_restore_tmp.tar.xz -C / --ignore-failed-read 2>/dev/null || \
       { echo "[ERROR] Extracción fallida"; rm -f /root/ocl_restore_tmp.tar.xz; exit 1; }
     rm -f /root/ocl_restore_tmp.tar.xz
     export NVM_DIR="$HOME/.nvm"
     [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
     if ! grep -q "NVM_DIR" /root/.bashrc 2>/dev/null; then
       echo "" >> /root/.bashrc
       echo "export NVM_DIR=\"\$HOME/.nvm\"" >> /root/.bashrc
       echo "[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"" >> /root/.bashrc
       echo "[INFO] NVM agregado a .bashrc"
     fi
     command -v openclaw &>/dev/null && echo "[OK] openclaw verificado" || echo "[AVISO] openclaw no en PATH — puede necesitar reiniciar sesión proot"
     echo "[DONE]"'

  local OCL_EXIT=$?
  rm -f "$OCL_TMP" 2>/dev/null
  [ $OCL_EXIT -ne 0 ] && { warn "Fallo restaurando OpenClaw"; return 1; }

  OCL_VER=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  [ -z "$OCL_VER" ] && OCL_VER="restored"
  update_registry "openclaw" "$OCL_VER"
  log "OpenClaw restaurado ✓"
  echo -e "  ${YELLOW}⚠${NC}  Token de auth vacío — configura con: menu → Servicios → OpenClaw → Configurar"
}

# ════════════════════════════════════════════════════════════
# DISPATCHER
# ════════════════════════════════════════════════════════════
run_restore() {
  mkdir -p "$TMP_DIR"

  case "$TARGET_MODULE" in
    base)            restore_part0  ;;
    claude)          restore_part2  ;;
    claude-native)   restore_part2b ;;
    expo)            restore_part3  ;;
    ollama)          restore_part4 ;;
    n8n)             restore_part5 ;;
    proot-base)      restore_part6 "part6-proot-base"      ;;
    proot-completo)  restore_part6 "part6-proot-completo"  ;;
    remote)          restore_part7 ;;
    opencode)        restore_part8 ;;
    openclaw)        restore_part9 ;;
    all)
      restore_part0
      restore_part2
      restore_part3
      restore_part4
      restore_part5
      restore_part6 "part6-proot-completo"
      restore_part7
      restore_part8
      restore_part9
      ;;
  esac

  rm -rf "$TMP_DIR"
  trap - INT TERM

  clear; echo ""
  echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║  ⬡ RESTORE COMPLETADO ✓                 ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  Módulo: ${BOLD}${TARGET_MODULE}${NC}"
  echo -e "  ${CYAN}→ source ~/.bashrc  (o reinicia Termux)${NC}"
  echo ""
}

# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════
parse_args "$@"

if [ -z "$TARGET_MODULE" ]; then
  menu_interactivo
else
  # Modo --module directo: elegir fuente si no se especificó
  [ -z "$SOURCE" ] && select_source
fi

run_restore

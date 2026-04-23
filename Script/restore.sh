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
#  VERSIÓN: 2.5.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

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
  if [ -d "$ROOTFS_BASE" ]; then
    for d in "$ROOTFS_BASE"/*/; do
      if [ -f "${d}bin/bash" ]; then
        DISTRO_NAME=$(basename "$d")
        ROOTFS_PATH="$d"
        return 0
      fi
    done
  fi
  return 1
}
detect_distro

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
      base|claude|expo|ollama|n8n|proot|remote|all) ;;
      *) error "Módulo inválido: '$TARGET_MODULE'\n  Válidos: base | claude | expo | ollama | n8n | proot | remote | all" ;;
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
# CABECERA
# ════════════════════════════════════════════════════════════
show_header() {
  clear
  echo -e "${CYAN}${BOLD}"
  cat << 'HEADER'
  ╔══════════════════════════════════════════════════╗
  ║   termux-ai-stack · Restore v2.5.0              ║
  ║   Restaura módulos desde backup                 ║
  ╚══════════════════════════════════════════════════╝
HEADER
  echo -e "${NC}"
}

# ════════════════════════════════════════════════════════════
# SELECCIÓN DE FUENTE
# ════════════════════════════════════════════════════════════
select_source() {
  echo -e "  ${BOLD}¿Desde dónde restaurar?${NC}"
  echo ""
  echo "  [1] GitHub Releases  — descarga el último release automáticamente"

  if [ -d "$LOCAL_DIR" ] && ls "$LOCAL_DIR"/*.tar.xz &>/dev/null 2>&1; then
    echo "  [2] Backup local     — generado con backup.sh en este dispositivo"
    echo ""
    echo -n "  Opción (1/2): "
    read -r OPT_SRC < /dev/tty
    case "$OPT_SRC" in
      1) SOURCE="github" ;;
      2) SOURCE="local"  ;;
      *) warn "Opción inválida — usando GitHub"; SOURCE="github" ;;
    esac
  else
    echo -e "  ${YELLOW}○${NC} Backup local no disponible"
    echo ""
    echo -n "  Presiona Enter para continuar con GitHub Releases..."
    read -r _ < /dev/tty
    SOURCE="github"
  fi
}

# ════════════════════════════════════════════════════════════
# MENÚ INTERACTIVO
# ════════════════════════════════════════════════════════════
menu_interactivo() {
  show_header
  select_source
  echo ""
  echo -e "  ${BOLD}¿Qué módulo restaurar?${NC}"
  echo ""
  echo "  [0] base   — scripts + tema + configs + registry (instalación rápida)"
  echo "  [2] claude — Claude Code"
  echo "  [3] expo   — EAS CLI + credenciales"
  echo "  [4] ollama — Ollama binario + libs"
  echo "  [5] n8n    — n8n + cloudflared (dentro del proot)"
  echo "  [6] proot  — Rootfs Debian completo (~834MB)"
  echo "  [7] remote — SSH + Dashboard configs + claves"
  echo "  [a] all    — Todos los módulos"
  echo "  [q] Salir"
  echo ""
  echo -n "  Opción: "
  read -r OPT_MOD < /dev/tty

  case "$OPT_MOD" in
    0|b) TARGET_MODULE="base"   ;;
    2)   TARGET_MODULE="claude" ;;
    3)   TARGET_MODULE="expo"   ;;
    4)   TARGET_MODULE="ollama" ;;
    5)   TARGET_MODULE="n8n"    ;;
    6)   TARGET_MODULE="proot"  ;;
    7)   TARGET_MODULE="remote" ;;
    a|A) TARGET_MODULE="all"    ;;
    q|Q) echo "Cancelado."; exit 0 ;;
    *)   error "Opción inválida" ;;
  esac
}

# ════════════════════════════════════════════════════════════
# GitHub API
# ════════════════════════════════════════════════════════════
RELEASE_JSON=""

fetch_release_json() {
  info "Consultando GitHub API..."
  RELEASE_JSON=$(curl -fsSL "$GITHUB_API" 2>/dev/null)
  [ -z "$RELEASE_JSON" ] && error "No se pudo obtener el release de GitHub\n  Verifica tu conexión"
}

get_part_url() {
  local PART_NAME="$1"
  echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*'"$PART_NAME"'[^"]*"' \
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
    curl -fL --progress-bar "$FILE_URL" -o "$DOWNLOADED_FILE" 2>/dev/null
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
    # Copiar scripts
    for f in "$EXTRACT_TMP/home/"*.sh; do
      [ -f "$f" ] && cp "$f" "$HOME/" && chmod +x "$HOME/$(basename "$f")"
    done
    # Copiar Python scripts
    for f in "$EXTRACT_TMP/home/"*.py; do
      [ -f "$f" ] && cp "$f" "$HOME/"
    done
    log "Scripts copiados a ~/"
  fi

  # Registry
  if [ -f "$EXTRACT_TMP/home/.android_server_registry" ]; then
    cp "$EXTRACT_TMP/home/.android_server_registry" "$REGISTRY"
    log "Registry restaurado"
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
    log "npm @anthropic-ai restaurado"
  else
    error "No se encontró npm_modules/@anthropic-ai en el archivo"
  fi

  # Restaurar wrapper
  CLI_PATH="$NPM_GLOBAL/@anthropic-ai/claude-code/cli.js"
  if [ -f "$CLI_PATH" ]; then
    WRAPPER="${TERMUX_PREFIX}/bin/claude"
    cat > "$WRAPPER" << WRAPPER_SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
exec node "${CLI_PATH}" "\$@"
WRAPPER_SCRIPT
    chmod +x "$WRAPPER"
    log "Wrapper /usr/bin/claude restaurado"
  fi

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
# RESTORE PARTE 3 — Expo / EAS CLI
# ════════════════════════════════════════════════════════════
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

  download_and_verify "part4-ollama"

  EXTRACT_TMP="$TMP_DIR/ollama_extract"
  mkdir -p "$EXTRACT_TMP"
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null

  [ -f "$EXTRACT_TMP/bin/ollama" ] && {
    cp "$EXTRACT_TMP/bin/ollama" "${TERMUX_PREFIX}/bin/ollama"
    chmod +x "${TERMUX_PREFIX}/bin/ollama"
    log "Binario ollama restaurado"
  }

  [ -d "$EXTRACT_TMP/lib_ollama" ] && {
    cp -r "$EXTRACT_TMP/lib_ollama" "${TERMUX_PREFIX}/lib/ollama"
    log "Librerías ollama restauradas"
  }

  [ -d "$EXTRACT_TMP/home" ] && {
    cp "$EXTRACT_TMP/home/"*.sh "$HOME/" 2>/dev/null
    chmod +x "$HOME/ollama_start.sh" "$HOME/ollama_stop.sh" 2>/dev/null
    log "Scripts ollama restaurados"
  }

  OLLAMA_VER=$(pkg show ollama 2>/dev/null | grep "^Version:" | awk '{print $2}')
  [ -z "$OLLAMA_VER" ] && OLLAMA_VER="restored"
  update_registry "ollama" "$OLLAMA_VER"
  log "Ollama restaurado ✓"
  echo -e "  ${YELLOW}⚠${NC}  Modelos NO incluidos — descarga con: ollama pull qwen2.5:0.5b"
  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 5 — n8n + cloudflared
# ════════════════════════════════════════════════════════════
restore_part5() {
  titulo "PARTE 5 — n8n + cloudflared"

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

  local ROOTFS_TMP="${ROOTFS_PATH}tmp"
  mkdir -p "$ROOTFS_TMP"
  cp "$DOWNLOADED_FILE" "$ROOTFS_TMP/n8n_restore.tar.xz"
  [ ! -s "$ROOTFS_TMP/n8n_restore.tar.xz" ] && error "No se pudo copiar al proot"

  info "Extrayendo n8n dentro del proot ($DISTRO_NAME)..."
  proot-distro login "$DISTRO_NAME" -- bash << 'PROOT_INNER'
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ARCHIVE="/tmp/n8n_restore.tar.xz"
[ ! -f "$ARCHIVE" ] && { echo "[ERROR] No se encontró el archivo en el proot"; exit 1; }

mkdir -p /usr/local/lib/node_modules /usr/local/bin /root/.n8n

echo "[INFO] Extrayendo en /..."
tar -xJf "$ARCHIVE" -C / 2>/dev/null || \
  tar -xJf "$ARCHIVE" -C / --ignore-failed-read 2>/dev/null || \
  { echo "[ERROR] Extracción fallida"; exit 1; }

[ -f /usr/local/bin/n8n ]         && chmod +x /usr/local/bin/n8n
[ -f /usr/local/bin/cloudflared ] && chmod +x /usr/local/bin/cloudflared
[ -f /usr/local/bin/node ]        && chmod +x /usr/local/bin/node

[ -f /usr/local/bin/n8n ] && echo "[OK] n8n verificado" || echo "[AVISO] n8n no encontrado"
rm -f "$ARCHIVE"
echo "[DONE]"
PROOT_INNER

  [ $? -ne 0 ] && error "Fallo la restauración de n8n"

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
  titulo "PARTE 6 — Proot Debian (rootfs completo)"

  if [ -n "$DISTRO_NAME" ]; then
    echo -e "  ${YELLOW}${BOLD}⚠  Se sobreescribirá el rootfs: $DISTRO_NAME${NC}"
    echo -e "  ${YELLOW}Todos los datos del proot actual se perderán.${NC}"
    echo ""
    echo -n "  ¿Continuar? (s/n): "
    read -r CONFIRM_P6 < /dev/tty
    [ "$CONFIRM_P6" != "s" ] && [ "$CONFIRM_P6" != "S" ] && { warn "Cancelado."; return 0; }
  fi

  download_and_verify "part6-proot-debian"
  mkdir -p "$ROOTFS_BASE"

  info "Detectando nombre del distro en el archivo..."
  DISTRO_IN_TAR=$(tar -tJf "$DOWNLOADED_FILE" 2>/dev/null | head -1 | cut -d'/' -f1)
  [ -z "$DISTRO_IN_TAR" ] && error "No se pudo leer el contenido del archive part6"
  info "Distro detectada: $DISTRO_IN_TAR"

  [ -d "$ROOTFS_BASE/$DISTRO_IN_TAR" ] && {
    warn "Eliminando rootfs anterior..."
    rm -rf "$ROOTFS_BASE/$DISTRO_IN_TAR"
  }

  echo -e "  ${YELLOW}Extrayendo rootfs (~834MB) — puede tardar 10-20 min...${NC}"
  tar -xJf "$DOWNLOADED_FILE" -C "$ROOTFS_BASE" 2>/dev/null || \
    error "Error al extraer part6"

  detect_distro
  PROOT_VER=$(proot-distro login "$DISTRO_IN_TAR" -- bash -c \
    "cat /etc/debian_version 2>/dev/null" 2>/dev/null | tr -d '\n')
  [ -z "$PROOT_VER" ] && PROOT_VER=$(pkg show proot-distro 2>/dev/null | grep "^Version:" | awk '{print $2}')
  [ -z "$PROOT_VER" ] && PROOT_VER="restored"
  update_registry "proot" "$PROOT_VER"
  log "Proot Debian restaurado ✓ ($DISTRO_IN_TAR)"
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
  for f in "$EXTRACT_TMP/home/"*.sh; do
    [ -f "$f" ] && cp "$f" "$HOME/" && chmod +x "$HOME/$(basename "$f")"
  done

  # ── Dashboard ────────────────────────────────────────────
  for f in dashboard_server.py dashboard_start.sh dashboard_stop.sh index.html; do
    [ -f "$EXTRACT_TMP/dashboard/$f" ] && {
      cp "$EXTRACT_TMP/dashboard/$f" "$HOME/$f"
      [[ "$f" == *.sh ]] && chmod +x "$HOME/$f"
      log "$f restaurado"
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
  echo -e "  ${CYAN}Para SSH:${NC}       bash ~/ssh_start.sh"
  echo -e "  ${CYAN}Para Dashboard:${NC}  bash ~/dashboard_start.sh"
  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# DISPATCHER
# ════════════════════════════════════════════════════════════
run_restore() {
  mkdir -p "$TMP_DIR"

  case "$TARGET_MODULE" in
    base)   restore_part0 ;;
    claude) restore_part2 ;;
    expo)   restore_part3 ;;
    ollama) restore_part4 ;;
    n8n)    restore_part5 ;;
    proot)  restore_part6 ;;
    remote) restore_part7 ;;
    all)
      restore_part0
      restore_part2
      restore_part3
      restore_part4
      restore_part5
      restore_part6
      restore_part7
      ;;
  esac

  rm -rf "$TMP_DIR"
  trap - INT TERM

  titulo "RESTORE COMPLETADO"
  echo -e "${GREEN}${BOLD}"
  cat << 'RESUMEN'
  ╔══════════════════════════════════════════════════╗
  ║     termux-ai-stack · Restore completado ✓      ║
  ╚══════════════════════════════════════════════════╝
RESUMEN
  echo -e "${NC}"
  echo -e "  Módulo restaurado: ${BOLD}$TARGET_MODULE${NC}"
  echo ""
  echo -e "  ${CYAN}Siguiente paso:${NC} source ~/.bashrc   (o reinicia Termux)"
  echo ""
}

# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════
parse_args "$@"
show_header

if [ -z "$TARGET_MODULE" ]; then
  [ -z "$SOURCE" ] && select_source
  menu_interactivo
else
  [ -z "$SOURCE" ] && select_source
fi

run_restore

#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · restore.sh
#  Restaura módulos desde GitHub Releases o backup local
#
#  USO:
#    bash ~/restore.sh                           → menú interactivo
#    bash ~/restore.sh --module ollama           → módulo específico (pregunta fuente)
#    bash ~/restore.sh --module all              → todos los módulos (pregunta fuente)
#    bash ~/restore.sh --module all --source github  → directo a GitHub sin preguntar
#    bash ~/restore.sh --module n8n --source local   → directo a backup local
#
#  MÓDULOS DISPONIBLES:
#    base | claude | expo | ollama | n8n | proot | all
#
#  FUENTES:
#    github — último release automático (GitHub API)
#    local  — backup generado con backup.sh en este dispositivo
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 2.2.0 | Abril 2026
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

# ── Rutas ─────────────────────────────────────────────────────
TMP_DIR="$HOME/restore_tmp"
LOCAL_DIR="/sdcard/Download/termux-ai-stack-releases"
REGISTRY="$HOME/.android_server_registry"
NPM_GLOBAL="${TERMUX_PREFIX}/lib/node_modules"
ROOTFS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/installed-rootfs"
GITHUB_API="https://api.github.com/repos/Honkonx/termux-ai-stack/releases/latest"

# Módulo a restaurar (se setea por args o menú)
TARGET_MODULE=""
# Fuente elegida: "github" o "local"
SOURCE=""

# ── Detectar proot instalado ──────────────────────────────────
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

# ── Cleanup si se interrumpe ──────────────────────────────────
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
      --module)
        shift
        TARGET_MODULE="$1"
        ;;
      --source)
        shift
        SOURCE="$1"
        ;;
      *)
        error "Argumento desconocido: $1\n  USO: bash ~/restore.sh [--module <módulo>] [--source github|local]"
        ;;
    esac
    shift
  done

  # Validar módulo si se pasó por arg
  if [ -n "$TARGET_MODULE" ]; then
    case "$TARGET_MODULE" in
      base|claude|expo|ollama|n8n|proot|all) ;;
      *)
        error "Módulo inválido: '$TARGET_MODULE'\n  Válidos: base | claude | expo | ollama | n8n | proot | all"
        ;;
    esac
  fi

  # Validar fuente si se pasó por arg
  if [ -n "$SOURCE" ]; then
    case "$SOURCE" in
      github|local) ;;
      *)
        error "Fuente inválida: '$SOURCE'\n  Válidas: github | local"
        ;;
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
  ║   termux-ai-stack · Restore v2.2.0              ║
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
    echo "  [2] Desde mi backup  — backup generado con backup.sh en este dispositivo"
    echo ""
    echo -n "  Opción (1/2): "
    read -r OPT_SRC
    case "$OPT_SRC" in
      1) SOURCE="github" ;;
      2) SOURCE="local"  ;;
      *) warn "Opción inválida — usando GitHub"; SOURCE="github" ;;
    esac
  else
    echo -e "  ${YELLOW}○${NC} Backup local no disponible (no hay archivos en $LOCAL_DIR)"
    echo ""
    echo -n "  Presiona Enter para continuar con GitHub Releases..."
    read -r
    SOURCE="github"
  fi
}

# ════════════════════════════════════════════════════════════
# MENÚ INTERACTIVO (sin args)
# ════════════════════════════════════════════════════════════
menu_interactivo() {
  show_header
  select_source

  echo ""
  echo -e "  ${BOLD}¿Qué módulo restaurar?${NC}"
  echo ""
  echo "  [1] base   — .bashrc + scripts + .termux"
  echo "  [2] claude — Claude Code"
  echo "  [3] expo   — EAS CLI + credenciales"
  echo "  [4] ollama — Ollama binario + libs"
  echo "  [5] n8n    — n8n + cloudflared (dentro del proot)"
  echo "  [6] proot  — Rootfs Debian completo"
  echo "  [7] all    — Todos los módulos"
  echo "  [q] Salir"
  echo ""
  echo -n "  Opción: "
  read -r OPT_MOD

  case "$OPT_MOD" in
    1) TARGET_MODULE="base"   ;;
    2) TARGET_MODULE="claude" ;;
    3) TARGET_MODULE="expo"   ;;
    4) TARGET_MODULE="ollama" ;;
    5) TARGET_MODULE="n8n"    ;;
    6) TARGET_MODULE="proot"  ;;
    7) TARGET_MODULE="all"    ;;
    q|Q) echo "Cancelado."; exit 0 ;;
    *) error "Opción inválida" ;;
  esac
}

# ════════════════════════════════════════════════════════════
# OBTENER URL DEL ÚLTIMO RELEASE (GitHub API)
# ════════════════════════════════════════════════════════════

# Guarda la respuesta JSON del release en variable global
RELEASE_JSON=""

fetch_release_json() {
  info "Consultando GitHub API..."
  RELEASE_JSON=$(curl -fsSL "$GITHUB_API" 2>/dev/null)
  if [ -z "$RELEASE_JSON" ]; then
    error "No se pudo obtener el release de GitHub\n  Verifica tu conexión a internet"
  fi
}

# Devuelve la URL de descarga para una parte específica
# $1 = nombre de la parte (ej: part4-ollama)
get_part_url() {
  local PART_NAME="$1"
  echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*'"$PART_NAME"'[^"]*"' \
    | grep -o 'https://[^"]*' | head -1
}

# Devuelve la URL de checksums.txt del release
get_checksums_url() {
  echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*checksums[^"]*"' \
    | grep -o 'https://[^"]*' | head -1
}

# ════════════════════════════════════════════════════════════
# DESCARGAR Y VERIFICAR SHA256
# ════════════════════════════════════════════════════════════
# $1 = nombre de parte (ej: part4-ollama)
# Deja el archivo extraído listo en $TMP_DIR
# Retorna ruta del .tar.xz descargado en $DOWNLOADED_FILE
DOWNLOADED_FILE=""

download_and_verify() {
  local PART_NAME="$1"
  local FILE_URL=""
  local CHECKSUMS_URL=""
  local FILENAME=""

  if [ "$SOURCE" = "github" ]; then
    # Obtener JSON si aún no se hizo
    [ -z "$RELEASE_JSON" ] && fetch_release_json

    FILE_URL=$(get_part_url "$PART_NAME")
    [ -z "$FILE_URL" ] && error "No se encontró '$PART_NAME' en el último release de GitHub"

    FILENAME=$(basename "$FILE_URL")
    info "Descargando $FILENAME..."
    curl -fL --progress-bar "$FILE_URL" -o "$TMP_DIR/$FILENAME" || \
      error "Error al descargar $FILENAME"

    # Descargar checksums si aún no existe
    if [ ! -f "$TMP_DIR/checksums.txt" ]; then
      CHECKSUMS_URL=$(get_checksums_url)
      if [ -n "$CHECKSUMS_URL" ]; then
        info "Descargando checksums.txt..."
        curl -fsSL "$CHECKSUMS_URL" -o "$TMP_DIR/checksums.txt" || \
          warn "No se pudo descargar checksums.txt — verificación SHA256 omitida"
      fi
    fi

  else
    # Fuente local — buscar con glob (ignora timestamp)
    FILENAME=$(ls "$LOCAL_DIR"/${PART_NAME}-*.tar.xz 2>/dev/null | tail -1)
    [ -z "$FILENAME" ] && error "No se encontró '$PART_NAME' en $LOCAL_DIR"

    info "Usando backup local: $(basename "$FILENAME")"
    cp "$FILENAME" "$TMP_DIR/"
    FILENAME=$(basename "$FILENAME")

    # Copiar checksums local si existe
    if [ ! -f "$TMP_DIR/checksums.txt" ]; then
      local LOCAL_CHK
      LOCAL_CHK=$(ls "$LOCAL_DIR"/checksums-*.txt 2>/dev/null | tail -1)
      [ -n "$LOCAL_CHK" ] && cp "$LOCAL_CHK" "$TMP_DIR/checksums.txt"
    fi
  fi

  # ── Verificar SHA256 ─────────────────────────────────────
  if [ -f "$TMP_DIR/checksums.txt" ]; then
    info "Verificando SHA256..."
    EXPECTED=$(grep "$FILENAME" "$TMP_DIR/checksums.txt" | cut -d' ' -f1)
    if [ -n "$EXPECTED" ]; then
      ACTUAL=$(sha256sum "$TMP_DIR/$FILENAME" | cut -d' ' -f1)
      if [ "$EXPECTED" = "$ACTUAL" ]; then
        log "SHA256 OK"
      else
        error "SHA256 no coincide para $FILENAME\n  Esperado: $EXPECTED\n  Obtenido: $ACTUAL"
      fi
    else
      warn "No se encontró checksum para $FILENAME — verificación omitida"
    fi
  else
    warn "checksums.txt no disponible — verificación SHA256 omitida"
  fi

  DOWNLOADED_FILE="$TMP_DIR/$FILENAME"
}

# ════════════════════════════════════════════════════════════
# UPDATE REGISTRY
# ════════════════════════════════════════════════════════════
# $1 = módulo  $2 = versión (opcional)
update_registry() {
  local MOD="$1"
  local VER="${2:-restored}"
  local DATE
  DATE=$(date +%Y-%m-%d)

  touch "$REGISTRY"

  # Eliminar entradas previas del módulo
  sed -i "/^${MOD}\./d" "$REGISTRY" 2>/dev/null

  {
    echo "${MOD}.installed=true"
    echo "${MOD}.version=${VER}"
    echo "${MOD}.install_date=${DATE}"
    echo "${MOD}.source=restore"
  } >> "$REGISTRY"

  log "Registry actualizado → $MOD v${VER}"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 1 — Termux base
# ════════════════════════════════════════════════════════════
restore_part1() {
  titulo "PARTE 1 — Termux base"
  download_and_verify "part1-termux-base"

  info "Extrayendo en $HOME..."
  tar -xJf "$DOWNLOADED_FILE" -C "$HOME" 2>/dev/null || \
    error "Error al extraer part1-termux-base"

  # Asegurar permisos de ejecución en scripts
  chmod +x "$HOME"/*.sh 2>/dev/null

  update_registry "base"
  log "Termux base restaurado ✓"
  echo -e "  ${YELLOW}⚠${NC}  Reinicia Termux o ejecuta: source ~/.bashrc"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 2 — Claude Code
# ════════════════════════════════════════════════════════════
restore_part2() {
  titulo "PARTE 2 — Claude Code"
  download_and_verify "part2-claude-code"

  local EXTRACT_TMP="$TMP_DIR/claude_extract"
  mkdir -p "$EXTRACT_TMP"
  info "Extrayendo..."
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null || \
    error "Error al extraer part2-claude-code"

  # Copiar @anthropic-ai al directorio npm global
  if [ -d "$EXTRACT_TMP/npm_modules/@anthropic-ai" ]; then
    mkdir -p "$NPM_GLOBAL"
    rm -rf "$NPM_GLOBAL/@anthropic-ai" 2>/dev/null
    cp -r "$EXTRACT_TMP/npm_modules/@anthropic-ai" "$NPM_GLOBAL/"
    log "@anthropic-ai copiado a $NPM_GLOBAL"
  else
    error "Estructura inesperada en part2 — no se encontró npm_modules/@anthropic-ai"
  fi

  # Asegurar alias en .bashrc
  local CLI_PATH
  CLI_PATH="${NPM_GLOBAL}/@anthropic-ai/claude-code/cli.js"
  if [ -f "$CLI_PATH" ]; then
    if ! grep -q "alias claude=" "$HOME/.bashrc" 2>/dev/null; then
      echo "alias claude='node ${CLI_PATH}'" >> "$HOME/.bashrc"
      log "Alias claude agregado a .bashrc"
    else
      info "Alias claude ya existe en .bashrc — no modificado"
    fi
  fi

  update_registry "claude" "2.1.111"
  log "Claude Code restaurado ✓"
  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 3 — Expo / EAS CLI
# ════════════════════════════════════════════════════════════
restore_part3() {
  titulo "PARTE 3 — Expo / EAS CLI"
  download_and_verify "part3-eas-expo"

  local EXTRACT_TMP="$TMP_DIR/expo_extract"
  mkdir -p "$EXTRACT_TMP"
  info "Extrayendo..."
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null || \
    error "Error al extraer part3-eas-expo"

  # Copiar eas-cli
  if [ -d "$EXTRACT_TMP/npm_modules/eas-cli" ]; then
    rm -rf "$NPM_GLOBAL/eas-cli" 2>/dev/null
    cp -r "$EXTRACT_TMP/npm_modules/eas-cli" "$NPM_GLOBAL/"
    log "eas-cli copiado a $NPM_GLOBAL"
  else
    error "Estructura inesperada en part3 — no se encontró npm_modules/eas-cli"
  fi

  # Restaurar credenciales expo
  if [ -d "$EXTRACT_TMP/home/.expo" ]; then
    cp -r "$EXTRACT_TMP/home/.expo" "$HOME/"
    log "Credenciales ~/.expo restauradas"
  fi

  # Crear symlink
  local EAS_BIN="${TERMUX_PREFIX}/bin/eas"
  ln -sf "${NPM_GLOBAL}/eas-cli/bin/eas" "$EAS_BIN" 2>/dev/null
  chmod +x "$EAS_BIN" 2>/dev/null
  log "Symlink $EAS_BIN → eas-cli creado"

  update_registry "expo"
  log "Expo / EAS CLI restaurado ✓"
  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 4 — Ollama
# ════════════════════════════════════════════════════════════
restore_part4() {
  titulo "PARTE 4 — Ollama"
  download_and_verify "part4-ollama"

  local EXTRACT_TMP="$TMP_DIR/ollama_extract"
  mkdir -p "$EXTRACT_TMP"
  info "Extrayendo..."
  tar -xJf "$DOWNLOADED_FILE" -C "$EXTRACT_TMP" 2>/dev/null || \
    error "Error al extraer part4-ollama"

  # Binario
  if [ -f "$EXTRACT_TMP/bin/ollama" ]; then
    cp "$EXTRACT_TMP/bin/ollama" "${TERMUX_PREFIX}/bin/ollama"
    chmod +x "${TERMUX_PREFIX}/bin/ollama"
    log "Binario ollama instalado"
  else
    error "Estructura inesperada en part4 — no se encontró bin/ollama"
  fi

  # Librerías
  if [ -d "$EXTRACT_TMP/lib_ollama" ]; then
    rm -rf "${TERMUX_PREFIX}/lib/ollama" 2>/dev/null
    cp -r "$EXTRACT_TMP/lib_ollama" "${TERMUX_PREFIX}/lib/ollama"
    log "Librerías ollama restauradas"
  fi

  # Scripts de control
  if [ -d "$EXTRACT_TMP/home" ]; then
    cp "$EXTRACT_TMP/home/"*.sh "$HOME/" 2>/dev/null
    chmod +x "$HOME/ollama_start.sh" "$HOME/ollama_stop.sh" 2>/dev/null
    log "Scripts ollama_start.sh / ollama_stop.sh restaurados"
  fi

  # Leer versión desde pkg
  local OLLAMA_VER
  OLLAMA_VER=$(pkg show ollama 2>/dev/null | grep "^Version:" | awk '{print $2}')
  [ -z "$OLLAMA_VER" ] && OLLAMA_VER="restored"

  update_registry "ollama" "$OLLAMA_VER"
  log "Ollama restaurado ✓"
  echo -e "  ${YELLOW}⚠${NC}  Modelos NO incluidos — descarga con: ollama pull qwen2.5:0.5b"
  rm -rf "$EXTRACT_TMP"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 5 — n8n + cloudflared (dentro del proot)
# ════════════════════════════════════════════════════════════
restore_part5() {
  titulo "PARTE 5 — n8n + cloudflared"

  # ── Si no hay proot, ofrecer instalar part6 primero ──────────
  if [ -z "$DISTRO_NAME" ]; then
    echo -e "  ${YELLOW}${BOLD}⚠  ADVERTENCIA — Proot Debian no encontrado${NC}"
    echo ""
    echo -e "  n8n vive dentro del contenedor Debian (part6 — rootfs completo)."
    echo -e "  Sin él, n8n no puede instalarse ni ejecutarse."
    echo ""
    echo -e "  ${YELLOW}Instalar part6 ahora descargará ~834MB y puede tardar 10-20 min."
    echo -e "  Si ya tienes un rootfs instalado, SERÁ SOBREESCRITO y perderás"
    echo -e "  todos sus datos actuales.${NC}"
    echo ""
    read -r -p "  ¿Descargar e instalar el rootfs Debian (part6) ahora? (s/n): " DO_PROOT
    echo ""

    if [ "$DO_PROOT" = "s" ] || [ "$DO_PROOT" = "S" ]; then
      restore_part6
      detect_distro
      if [ -z "$DISTRO_NAME" ]; then
        error "El proot no quedó disponible tras restaurar part6 — abortando"
      fi
      log "Proot listo — continuando con n8n..."
      echo ""
    else
      warn "Restauración de n8n cancelada — se requiere el contenedor Debian"
      return 0
    fi
  fi

  download_and_verify "part5-n8n-data"

  # Copiar el .tar.xz al /tmp del rootfs para extraerlo desde adentro
  local ROOTFS_TMP="${ROOTFS_PATH}tmp"
  mkdir -p "$ROOTFS_TMP"
  cp "$DOWNLOADED_FILE" "$ROOTFS_TMP/n8n_restore.tar.xz"

  info "Extrayendo n8n dentro del proot ($DISTRO_NAME)..."

  proot-distro login "$DISTRO_NAME" -- bash << 'PROOT_INNER'
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ARCHIVE="/tmp/n8n_restore.tar.xz"

if [ ! -f "$ARCHIVE" ]; then
  echo "[ERROR] No se encontró /tmp/n8n_restore.tar.xz dentro del proot"
  exit 1
fi

echo "[INFO] Extrayendo en /..."
tar -xJf "$ARCHIVE" -C / 2>/dev/null && echo "[OK] Extracción completada" || {
  echo "[ERROR] Fallo al extraer dentro del proot"
  exit 1
}

# Restaurar permisos
[ -f /usr/local/bin/n8n ]         && chmod +x /usr/local/bin/n8n
[ -f /usr/local/bin/cloudflared ] && chmod +x /usr/local/bin/cloudflared
[ -f /usr/local/bin/node ]        && chmod +x /usr/local/bin/node

rm -f "$ARCHIVE"
echo "[DONE]"
PROOT_INNER

  if [ $? -ne 0 ]; then
    error "Falló la restauración de n8n dentro del proot"
  fi

  update_registry "n8n"
  log "n8n + cloudflared restaurado ✓"
}

# ════════════════════════════════════════════════════════════
# RESTORE PARTE 6 — Proot Debian rootfs completo
# ════════════════════════════════════════════════════════════
restore_part6() {
  titulo "PARTE 6 — Proot Debian (rootfs completo)"

  # Advertencia si ya existe un rootfs
  if [ -n "$DISTRO_NAME" ]; then
    echo -e "  ${YELLOW}${BOLD}⚠  ADVERTENCIA${NC}"
    echo -e "  Se sobreescribirá el rootfs existente: ${BOLD}$ROOTFS_NAME${NC}"
    echo -e "  ${YELLOW}Todos los datos del proot actual se perderán.${NC}"
    echo ""
  fi

  download_and_verify "part6-proot-debian"

  mkdir -p "$ROOTFS_BASE"

  # Detectar nombre del directorio dentro del tar
  info "Detectando nombre del distro en el archivo..."
  local DISTRO_IN_TAR
  DISTRO_IN_TAR=$(tar -tJf "$DOWNLOADED_FILE" 2>/dev/null | head -1 | cut -d'/' -f1)

  if [ -z "$DISTRO_IN_TAR" ]; then
    error "No se pudo leer el contenido del archive part6"
  fi

  info "Distro detectada: $DISTRO_IN_TAR"

  # Eliminar rootfs anterior si existe con el mismo nombre
  if [ -d "$ROOTFS_BASE/$DISTRO_IN_TAR" ]; then
    warn "Eliminando rootfs anterior: $ROOTFS_BASE/$DISTRO_IN_TAR"
    rm -rf "$ROOTFS_BASE/$DISTRO_IN_TAR"
  fi

  echo -e "  ${YELLOW}Extrayendo rootfs (~834MB) — puede tardar 10-20 min...${NC}"
  echo -e "  ${YELLOW}Mantén la pantalla encendida.${NC}"
  echo ""

  tar -xJf "$DOWNLOADED_FILE" -C "$ROOTFS_BASE" 2>/dev/null || \
    error "Error al extraer part6-proot-debian"

  # Actualizar variables globales
  detect_distro

  update_registry "proot"
  log "Proot Debian restaurado ✓ ($DISTRO_IN_TAR)"
  echo -e "  ${CYAN}Prueba con:${NC} proot-distro login $DISTRO_IN_TAR"
}

# ════════════════════════════════════════════════════════════
# DISPATCHER — ejecutar módulo(s)
# ════════════════════════════════════════════════════════════
run_restore() {
  mkdir -p "$TMP_DIR"

  case "$TARGET_MODULE" in
    base)   restore_part1 ;;
    claude) restore_part2 ;;
    expo)   restore_part3 ;;
    ollama) restore_part4 ;;
    n8n)    restore_part5 ;;
    proot)  restore_part6 ;;
    all)
      restore_part1
      restore_part2
      restore_part3
      restore_part4
      restore_part5
      restore_part6
      ;;
  esac

  # Limpiar tmp
  rm -rf "$TMP_DIR"
  trap - INT TERM

  # ── Resumen final ───────────────────────────────────────
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
  # Sin args → menú interactivo: elige fuente y módulo
  [ -z "$SOURCE" ] && select_source
  menu_interactivo
else
  # Con --module → solo preguntar fuente si no viene por arg
  [ -z "$SOURCE" ] && select_source
fi

run_restore

#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_opencode.sh
#  Instala OpenCode en Termux ARM64
#
#  ESTRATEGIA (en orden de prioridad):
#    1. Nativo Termux  — descarga .pkg.tar.xz desde
#       github.com/Honkonx/opencode-termux releases
#       Requiere: glibc + openssl-glibc (se instalan si faltan)
#    2. Fallback proot — instalador oficial en Debian proot
#       (igual que versión anterior — si nativo no disponible)
#
#  REGLAS TÉCNICAS:
#    - HTTP: urllib / curl / wget (NUNCA import requests)
#    - Fechas: date +%Y-%m-%d (NUNCA datetime.now() en Python)
#    - Rutas temp: $HOME/ (NUNCA /tmp/ — noexec en Android 15)
#    - read: siempre < /dev/tty
#
#  VERSIÓN: 2.0.0 | Junio 2026
# ============================================================

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Colores ──────────────────────────────────────────────────
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

# ── Constantes ────────────────────────────────────────────────
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_opencode_checkpoint"
OPENCODE_SCRIPTS="$HOME/scripts/opencode"
FORK_OWNER="Honkonx"
FORK_REPO="opencode-termux"
GITHUB_API="https://api.github.com/repos/${FORK_OWNER}/${FORK_REPO}/releases/latest"
# Directorio de descarga temporal — $HOME/ (no /tmp/, noexec Android 15)
DL_DIR="$HOME/.opencode_install_tmp"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

update_registry() {
  local version="$1" location="$2"
  local date_now; date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^opencode\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
opencode.installed=true
opencode.version=$version
opencode.install_date=$date_now
opencode.location=$location
opencode.port=3000
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado (location=$location)"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · OpenCode Installer     ║
  ║   Native ARM64 · Termux · sin root         ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ============================================================
# PASO 0 — Detectar instalación existente
# ============================================================
titulo "PASO 0 — Detección de estado actual"

_OC_NATIVE=false
_OC_PROOT=false
_OC_VER_EXISTING=""

# ── Nativo: opencode en PATH de Termux ───────────────────────
if command -v opencode &>/dev/null; then
  _OC_NATIVE=true
  _OC_VER_EXISTING=$(opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  echo -e "${GREEN}  ✓ OpenCode nativo detectado${NC}"
  echo -e "  Versión: ${CYAN}${_OC_VER_EXISTING:-?}${NC}  |  Ruta: $(command -v opencode)"
fi

# ── Proot: opencode en Debian ────────────────────────────────
ROOTFS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/installed-rootfs"
DISTRO_NAME=""
ROOTFS_PATH=""
_detect_rootfs() {
  DISTRO_NAME=""; ROOTFS_PATH=""
  [ -d "$ROOTFS_BASE" ] || return 1
  for _d in "$ROOTFS_BASE"/*/; do
    _d="${_d%/}"
    if [ -f "${_d}/bin/bash" ] || [ -f "${_d}/usr/bin/bash" ] || [ -f "${_d}/etc/os-release" ]; then
      DISTRO_NAME=$(basename "$_d"); ROOTFS_PATH="$_d"; return 0
    fi
  done
  return 1
}
_detect_rootfs

if [ -n "$DISTRO_NAME" ] && \
   proot-distro login "$DISTRO_NAME" -- bash -c \
     'source ~/.bashrc 2>/dev/null; command -v opencode' &>/dev/null 2>&1; then
  _OC_PROOT=true
  if [ -z "$_OC_VER_EXISTING" ]; then
    _OC_VER_EXISTING=$(proot-distro login "$DISTRO_NAME" -- bash -c \
      'source ~/.bashrc 2>/dev/null; opencode --version 2>/dev/null | head -1' 2>/dev/null \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  fi
  echo -e "${GREEN}  ✓ OpenCode proot detectado${NC} (en $DISTRO_NAME)"
fi

# ── Si ya está instalado: preguntar modo ─────────────────────
if $_OC_NATIVE || $_OC_PROOT; then
  echo ""
  echo -e "  Versión actual: ${CYAN}${_OC_VER_EXISTING:-?}${NC}"
  echo ""
  echo -e "  ${BOLD}¿Qué deseas hacer?${NC}"
  echo "  [1] Actualizar/reinstalar nativo (recomendado)"
  echo "  [2] Reinstalar proot Debian"
  echo "  [3] Cancelar"
  echo ""; echo -n "  Opción: "
  read -r REINSTALL_OPT < /dev/tty
  case "$REINSTALL_OPT" in
    1) rm -f "$CHECKPOINT"; FORCE_MODE="native" ;;
    2) rm -f "$CHECKPOINT"; FORCE_MODE="proot"  ;;
    3|"") info "Nada que hacer. Saliendo."; exit 0 ;;
    *) error "Opción inválida" ;;
  esac
else
  FORCE_MODE=""
  echo -e "  ${DIM}No se detectó instalación previa.${NC}"
fi

# ============================================================
# PASO 1 — Selección de modo de instalación
# ============================================================
titulo "PASO 1 — Modo de instalación"

# Si ya se forzó modo en reinstalación, saltar menú
if [ -z "$FORCE_MODE" ]; then
  echo "  ${BOLD}Selecciona modo:${NC}"
  echo ""
  echo -e "  ${GREEN}[1]${NC} Nativo Termux ${CYAN}(recomendado)${NC}"
  echo -e "      ▸ Descarga binario desde github.com/${FORK_OWNER}/${FORK_REPO}"
  echo -e "      ▸ Instala glibc + openssl-glibc si faltan"
  echo -e "      ▸ Más rápido, accede a carpetas Termux directamente"
  echo ""
  echo -e "  ${GREEN}[2]${NC} proot Debian ${DIM}(fallback)${NC}"
  echo -e "      ▸ Instalador oficial en Debian proot"
  echo -e "      ▸ Requiere proot-distro instalado"
  echo ""
  echo -n "  Opción [1]: "
  read -r MODE_OPT < /dev/tty
  case "${MODE_OPT:-1}" in
    1) FORCE_MODE="native" ;;
    2) FORCE_MODE="proot"  ;;
    *) error "Opción inválida" ;;
  esac
fi

echo ""
echo -e "  Modo seleccionado: ${CYAN}${BOLD}${FORCE_MODE}${NC}"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRM < /dev/tty
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ════════════════════════════════════════════════════════════
#  RAMA A — INSTALACIÓN NATIVA
# ════════════════════════════════════════════════════════════
if [ "$FORCE_MODE" = "native" ]; then

  # ── PASO N1 — Dependencias glibc ─────────────────────────
  titulo "PASO N1 — Dependencias glibc Termux"

  if check_done "native_glibc_deps"; then
    log "Dependencias glibc ya instaladas [checkpoint]"
  else
    info "Instalando glibc-repo, glibc y openssl-glibc..."
    info "(Termux omite los paquetes ya instalados automáticamente)"
    echo ""

    pkg install -y glibc-repo \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      warn "glibc-repo: posible advertencia — continuando"

    pkg update -y 2>/dev/null || true

    pkg install -y glibc openssl-glibc \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      warn "glibc/openssl-glibc: posible advertencia — continuando"

    # Verificar que glibc quedó disponible
    if [ -f "${TERMUX_PREFIX}/glibc/lib/ld-linux-aarch64.so.1" ] || \
       command -v glibc-runner &>/dev/null || \
       pkg list-installed 2>/dev/null | grep -q "^glibc/"; then
      log "glibc disponible"
    else
      warn "glibc no detectado — OpenCode puede fallar si no está instalado"
    fi

    mark_done "native_glibc_deps"
  fi

  # ── PASO N2 — Detectar última release del fork ───────────
  titulo "PASO N2 — Detectando última versión disponible"

  if check_done "native_version_resolved"; then
    OC_RELEASE_URL=$(grep "^_oc_pkg_url=" "$CHECKPOINT.data" 2>/dev/null | cut -d'=' -f2-)
    OC_RELEASE_VER=$(grep "^_oc_ver=" "$CHECKPOINT.data" 2>/dev/null | cut -d'=' -f2-)
    log "Versión ya resuelta [checkpoint]: v${OC_RELEASE_VER}"
  else
    info "Consultando GitHub API: ${FORK_OWNER}/${FORK_REPO}..."
    echo ""

    # Descargar JSON de la API — sin jq, sin requests
    RELEASE_JSON_PATH="$DL_DIR/release.json"
    mkdir -p "$DL_DIR"

    _download_ok=false
    if command -v curl &>/dev/null; then
      curl -fsSL --max-time 15 "$GITHUB_API" -o "$RELEASE_JSON_PATH" 2>/dev/null && _download_ok=true
    fi
    if ! $_download_ok && command -v wget &>/dev/null; then
      wget -q --timeout=15 "$GITHUB_API" -O "$RELEASE_JSON_PATH" 2>/dev/null && _download_ok=true
    fi

    if ! $_download_ok || [ ! -s "$RELEASE_JSON_PATH" ]; then
      warn "No se pudo consultar la API de GitHub"
      warn "Verifica que github.com/Honkonx/opencode-termux tenga releases publicados"
      echo ""
      echo -n "  Ingresa la URL directa del .pkg.tar.xz (o ENTER para cancelar): "
      read -r MANUAL_URL < /dev/tty
      [ -z "$MANUAL_URL" ] && error "Sin URL — cancelado"
      OC_RELEASE_URL="$MANUAL_URL"
      OC_RELEASE_VER="manual"
    else
      # Parsear JSON con grep/sed — sin jq
      OC_RELEASE_TAG=$(grep -o '"tag_name":"[^"]*"' "$RELEASE_JSON_PATH" | head -1 | cut -d'"' -f4)
      OC_RELEASE_VER=$(echo "$OC_RELEASE_TAG" | sed 's/^v//')

      # Buscar URL del .pkg.tar.xz aarch64
      OC_RELEASE_URL=$(grep -o '"browser_download_url":"[^"]*"' "$RELEASE_JSON_PATH" \
        | grep "aarch64.*\.pkg\.tar\.xz" | head -1 | cut -d'"' -f4)

      # Fallback: .deb aarch64
      if [ -z "$OC_RELEASE_URL" ]; then
        OC_RELEASE_URL=$(grep -o '"browser_download_url":"[^"]*"' "$RELEASE_JSON_PATH" \
          | grep "aarch64.*\.deb" | head -1 | cut -d'"' -f4)
        [ -n "$OC_RELEASE_URL" ] && _PKG_FORMAT="deb" || _PKG_FORMAT=""
      else
        _PKG_FORMAT="pkg.tar.xz"
      fi

      if [ -z "$OC_RELEASE_URL" ]; then
        warn "No se encontró binario aarch64 en la release ${OC_RELEASE_TAG}"
        warn "Activa el workflow en github.com/${FORK_OWNER}/${FORK_REPO}/actions"
        error "Sin paquete disponible"
      fi

      log "Release encontrada: ${OC_RELEASE_TAG} (${_PKG_FORMAT})"
      echo -e "  URL: ${DIM}${OC_RELEASE_URL}${NC}"
    fi

    rm -f "$RELEASE_JSON_PATH"

    # Persistir en checkpoint.data para resume
    cat > "$CHECKPOINT.data" << EOF
_oc_pkg_url=${OC_RELEASE_URL}
_oc_ver=${OC_RELEASE_VER}
_oc_fmt=${_PKG_FORMAT:-pkg.tar.xz}
EOF
    mark_done "native_version_resolved"
  fi

  # Restaurar formato si venimos de checkpoint
  _PKG_FORMAT=$(grep "^_oc_fmt=" "$CHECKPOINT.data" 2>/dev/null | cut -d'=' -f2-)
  [ -z "$_PKG_FORMAT" ] && _PKG_FORMAT="pkg.tar.xz"

  # ── PASO N3 — Descargar paquete ───────────────────────────
  titulo "PASO N3 — Descargando paquete (v${OC_RELEASE_VER})"

  if check_done "native_download"; then
    log "Descarga ya completada [checkpoint]"
    OC_PKG_FILE=$(ls "$DL_DIR"/opencode*.${_PKG_FORMAT##*.} 2>/dev/null \
      | grep -E "aarch64\.(pkg\.tar\.xz|deb)$" | head -1)
    # Si el archivo no existe ya (sesión anterior), marcar para re-descarga
    [ -z "$OC_PKG_FILE" ] || [ ! -f "$OC_PKG_FILE" ] && {
      warn "Archivo de descarga no encontrado — re-descargando"
      grep -v "^native_download$" "$CHECKPOINT" > "$CHECKPOINT.tmp" && mv "$CHECKPOINT.tmp" "$CHECKPOINT"
    }
  fi

  if ! check_done "native_download"; then
    mkdir -p "$DL_DIR"
    _ext="${OC_RELEASE_URL##*.}"
    [ "$_ext" = "xz" ] && _ext="pkg.tar.xz"   # nombre correcto para tar.xz
    OC_PKG_FILE="$DL_DIR/opencode-${OC_RELEASE_VER}-aarch64.${_PKG_FORMAT##*.}"
    # Para pkg.tar.xz conservar extensión completa
    [[ "$_PKG_FORMAT" == "pkg.tar.xz" ]] && OC_PKG_FILE="$DL_DIR/opencode-${OC_RELEASE_VER}-1-aarch64.pkg.tar.xz"
    [[ "$_PKG_FORMAT" == "deb" ]]        && OC_PKG_FILE="$DL_DIR/opencode_${OC_RELEASE_VER}_aarch64.deb"

    info "Descargando desde GitHub Releases..."
    _dl_ok=false
    if command -v curl &>/dev/null; then
      curl -fL --progress-bar --max-time 120 "$OC_RELEASE_URL" -o "$OC_PKG_FILE" 2>/dev/null && _dl_ok=true
    fi
    if ! $_dl_ok && command -v wget &>/dev/null; then
      wget --show-progress -q --timeout=120 "$OC_RELEASE_URL" -O "$OC_PKG_FILE" 2>/dev/null && _dl_ok=true
    fi

    if ! $_dl_ok || [ ! -s "$OC_PKG_FILE" ]; then
      rm -f "$OC_PKG_FILE"
      error "Descarga fallida. Verifica tu conexión e intenta de nuevo."
    fi

    log "Descargado: $(du -sh "$OC_PKG_FILE" | cut -f1)"
    mark_done "native_download"
  fi

  # ── PASO N4 — Instalar binario en $PREFIX ─────────────────
  titulo "PASO N4 — Instalando en Termux ($TERMUX_PREFIX)"

  if check_done "native_install"; then
    log "Instalación ya completada [checkpoint]"
  else
    echo -e "  Formato detectado: ${CYAN}${_PKG_FORMAT}${NC}"; echo ""

    case "$_PKG_FORMAT" in
      pkg.tar.xz)
        info "Extrayendo .pkg.tar.xz en $TERMUX_PREFIX ..."
        # Extraer en $HOME primero, luego copiar — evitar permisos
        _EXTRACT_TMP="$DL_DIR/extract"
        mkdir -p "$_EXTRACT_TMP"
        if tar -xJf "$OC_PKG_FILE" -C "$_EXTRACT_TMP" 2>/dev/null; then
          # Copiar estructura usr/ → $PREFIX/
          if [ -d "$_EXTRACT_TMP/usr" ]; then
            cp -r "$_EXTRACT_TMP/usr/"* "$TERMUX_PREFIX/" 2>/dev/null || true
            chmod 755 "$TERMUX_PREFIX/bin/opencode" 2>/dev/null || true
            [ -f "$TERMUX_PREFIX/lib/opencode/runtime/opencode" ] && \
              chmod 755 "$TERMUX_PREFIX/lib/opencode/runtime/opencode" 2>/dev/null || true
            log "Extraído correctamente"
          else
            warn "Estructura inesperada en .pkg.tar.xz — intentando extracción directa"
            tar -xJf "$OC_PKG_FILE" -C "$TERMUX_PREFIX/" --strip-components=1 2>/dev/null || \
              error "No se pudo extraer el paquete"
          fi
        else
          error "Fallo al extraer el .pkg.tar.xz"
        fi
        rm -rf "$_EXTRACT_TMP"
        ;;
      deb)
        info "Instalando .deb con dpkg..."
        if command -v dpkg &>/dev/null; then
          dpkg -i "$OC_PKG_FILE" 2>/dev/null || \
            warn "dpkg tuvo advertencias — verificando binario..."
        else
          # Extraer manualmente si dpkg no disponible en Termux
          info "dpkg no disponible — extrayendo manualmente..."
          _DEB_TMP="$DL_DIR/deb_extract"
          mkdir -p "$_DEB_TMP"
          # .deb es un ar archive — usar binutils o extracción manual
          if command -v ar &>/dev/null; then
            ar x "$OC_PKG_FILE" --output="$_DEB_TMP" 2>/dev/null || true
            if [ -f "$_DEB_TMP/data.tar.xz" ]; then
              tar -xJf "$_DEB_TMP/data.tar.xz" -C "$_DEB_TMP/" 2>/dev/null || true
            elif [ -f "$_DEB_TMP/data.tar.gz" ]; then
              tar -xzf "$_DEB_TMP/data.tar.gz" -C "$_DEB_TMP/" 2>/dev/null || true
            fi
            [ -d "$_DEB_TMP/usr" ] && cp -r "$_DEB_TMP/usr/"* "$TERMUX_PREFIX/" 2>/dev/null || true
          else
            error "No se puede extraer .deb sin ar o dpkg. Usa pkg install binutils primero."
          fi
          rm -rf "$_DEB_TMP"
        fi
        chmod 755 "$TERMUX_PREFIX/bin/opencode" 2>/dev/null || true
        ;;
    esac

    # Verificar que el binario funciona
    echo ""
    info "Verificando binario..."
    if command -v opencode &>/dev/null; then
      OC_VER=$(opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      log "opencode v${OC_VER:-?} funcional en $(command -v opencode)"
    else
      # PATH puede necesitar refresh en la misma sesión
      if [ -f "$TERMUX_PREFIX/bin/opencode" ]; then
        OC_VER=$("$TERMUX_PREFIX/bin/opencode" --version 2>/dev/null \
          | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log "Binario presente: v${OC_VER:-?} — recarga el shell para que funcione 'opencode'"
      else
        error "Binario no encontrado tras la instalación"
      fi
    fi

    mark_done "native_install"
  fi

  # ── PASO N5 — Scripts de control ─────────────────────────
  titulo "PASO N5 — Scripts de control"

  if check_done "native_scripts"; then
    log "Scripts ya creados [checkpoint]"
  else
    mkdir -p "$OPENCODE_SCRIPTS"

    # opencode_start.sh — nativo, sin proot
    cat > "$OPENCODE_SCRIPTS/opencode_start.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# Lanzador OpenCode Web — nativo Termux — termux-ai-stack
SESSION="opencode"
PORT=3000
CWD="${1:-$HOME}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo -e "\033[0;32m[OK]\033[0m OpenCode ya corriendo — http://127.0.0.1:${PORT}"
  exit 0
fi

echo -e "\033[0;36m[+] Iniciando OpenCode Web (nativo)...\033[0m"
tmux new-session -d -s "$SESSION" \
  "BROWSER= opencode web --port $PORT --hostname 127.0.0.1 --cwd '$CWD' 2>&1"

sleep 2
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo -e "\033[0;32m[OK]\033[0m Servidor iniciado"
  echo -e "     URL: http://127.0.0.1:${PORT}"
  echo -e "     \033[2mAbre en Brave, Chrome u otro navegador\033[0m"
else
  echo -e "\033[0;31m[ERROR]\033[0m No se pudo iniciar. Verifica: opencode --version"
fi
SCRIPT
    chmod +x "$OPENCODE_SCRIPTS/opencode_start.sh"
    log "opencode_start.sh (nativo)"

    # opencode_stop.sh
    cat > "$OPENCODE_SCRIPTS/opencode_stop.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
SESSION="opencode"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  echo "✓ OpenCode detenido"
else
  echo "OpenCode no estaba corriendo"
fi
SCRIPT
    chmod +x "$OPENCODE_SCRIPTS/opencode_stop.sh"
    log "opencode_stop.sh"

    mark_done "native_scripts"
  fi

  # ── PASO N6 — Aliases ─────────────────────────────────────
  titulo "PASO N6 — Aliases en ~/.bashrc"

  if check_done "native_aliases"; then
    log "Aliases ya configurados [checkpoint]"
  else
    BASHRC="$HOME/.bashrc"
    grep -v "opencode-web\|opencode-stop\|opencode-status\|opencode-tui\|# OpenCode · aliases" \
      "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

    cat >> "$BASHRC" << 'ALIASES'

# ════════════════════════════════
#  OpenCode · aliases (nativo)
# ════════════════════════════════
alias opencode-web='bash ~/scripts/opencode/opencode_start.sh'
alias opencode-stop='bash ~/scripts/opencode/opencode_stop.sh'
alias opencode-status='tmux has-session -t opencode 2>/dev/null && echo "OpenCode corriendo en :3000" || echo "OpenCode detenido"'
alias opencode-tui='opencode'
ALIASES

    log "Aliases agregados a ~/.bashrc"
    mark_done "native_aliases"
  fi

  # ── PASO N7 — Registry ────────────────────────────────────
  titulo "PASO N7 — Actualizando registry"

  OC_VER_FINAL=$("$TERMUX_PREFIX/bin/opencode" --version 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$OC_VER_FINAL" ] && OC_VER_FINAL="${OC_RELEASE_VER:-unknown}"
  update_registry "$OC_VER_FINAL" "termux_native"

  # ── Limpiar temporales ────────────────────────────────────
  rm -rf "$DL_DIR" "$CHECKPOINT.data"
  rm -f "$CHECKPOINT"

  # ── Resumen ───────────────────────────────────────────────
  titulo "INSTALACIÓN NATIVA COMPLETADA"
  echo -e "${GREEN}${BOLD}"
  cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║  OpenCode nativo instalado con éxito ✓     ║
  ╚══════════════════════════════════════════════╝
RESUMEN
  echo -e "${NC}"
  echo "  Versión:  v${OC_VER_FINAL}"
  echo "  Modo:     nativo Termux (ARM64, glibc)"
  echo "  Binario:  $TERMUX_PREFIX/bin/opencode"
  echo ""
  echo "  COMANDOS:"
  echo "  opencode              → TUI (interfaz terminal)"
  echo "  opencode-web          → servidor web en :3000"
  echo "  opencode-stop         → detener servidor"
  echo "  opencode-status       → verificar estado"
  echo ""
  echo "  DESDE EL MENÚ:"
  echo "  menu → [2] Code Tools → [2] OpenCode"
  echo ""
  echo -e "${CYAN}  → Cierra y reabre Termux (o: source ~/.bashrc) para activar aliases${NC}"
  echo ""
  exit 0
fi   # fin rama native

# ════════════════════════════════════════════════════════════
#  RAMA B — FALLBACK PROOT DEBIAN
#  Código equivalente a versión 1.x — sin cambios funcionales
# ════════════════════════════════════════════════════════════
titulo "INSTALACIÓN VÍA PROOT DEBIAN"
info "Modo proot seleccionado — usando Debian proot como entorno glibc"
echo ""

# ── Verificar / instalar proot-distro ────────────────────────
if ! command -v proot-distro &>/dev/null; then
  info "Instalando proot-distro..."
  pkg install proot-distro proot tmux curl wget tar xz-utils git busybox -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    error "No se pudo instalar proot-distro."
fi

# ── Detectar rootfs ──────────────────────────────────────────
_detect_rootfs
if [ -z "$DISTRO_NAME" ]; then
  warn "Rootfs Debian no encontrado en $ROOTFS_BASE"
  echo ""
  echo -e "  ${CYAN}¿Cómo instalar Debian?${NC}"; echo ""
  echo -e "  ${GREEN}[1]${NC} Desde GitHub Releases  (~5-10 min)"
  echo -e "  ${GREEN}[2]${NC} Instalación limpia      (~15-25 min)"
  echo -e "  ${GREEN}[b]${NC} Cancelar"
  echo ""; echo -n "  Opción: "
  read -r ROOTFS_OPT < /dev/tty
  case "$ROOTFS_OPT" in
    1)
      [ ! -f "$HOME/restore.sh" ] && \
        curl -fsSL "https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/restore.sh" \
          -o "$HOME/restore.sh" && chmod +x "$HOME/restore.sh"
      bash "$HOME/restore.sh" --module proot-base --source github || \
        error "Fallo la restauración del rootfs"
      ;;
    2)
      if [ -d "$ROOTFS_BASE/debian" ] && \
         { [ -f "$ROOTFS_BASE/debian/bin/bash" ] || [ -f "$ROOTFS_BASE/debian/usr/bin/bash" ]; }; then
        log "Rootfs debian ya existe — saltando"
      else
        OUT=$(proot-distro install debian 2>&1); RC=$?
        echo "$OUT" | grep -q "already exists" && log "Debian ya registrado" || \
          { [ $RC -ne 0 ] && echo "$OUT" && error "No se pudo instalar Debian"; }
      fi
      ;;
    b|B|"") error "Cancelado" ;;
    *) error "Opción inválida" ;;
  esac
  sleep 2; _detect_rootfs
  [ -z "$DISTRO_NAME" ] && error "Rootfs no disponible tras instalación"
  log "Rootfs listo: $DISTRO_NAME"
fi

log "Rootfs: $DISTRO_NAME ($ROOTFS_PATH)"

# ── PASO P1 — Dependencias Debian ────────────────────────────
titulo "PASO P1 — Dependencias en Debian"

if check_done "proot_deps"; then
  log "Dependencias ya instaladas [checkpoint]"
else
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     apt-get update -qq -o Acquire::Check-Valid-Until=false 2>/dev/null || true
     apt-get install -y --no-install-recommends curl ripgrep tmux nodejs npm 2>&1 | tail -5' || \
    warn "Algunas dependencias no instaladas — continuando"
  mark_done "proot_deps"
fi

# ── PASO P2 — Instalar OpenCode ───────────────────────────────
titulo "PASO P2 — Instalando OpenCode en Debian"

if check_done "proot_opencode_install"; then
  log "OpenCode ya instalado [checkpoint]"
else
  OC_OK=false
  info "Intentando instalador oficial..."
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     curl -fsSL https://opencode.ai/install | bash 2>&1' && OC_OK=true || OC_OK=false

  if $OC_OK; then
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'export HOME=/root; export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
       command -v opencode' &>/dev/null 2>&1 || OC_OK=false
  fi

  if ! $OC_OK; then
    warn "Instalador oficial falló — intentando npm..."
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'export HOME=/root; npm install -g opencode-ai 2>&1 | tail -5' && \
      OC_OK=true || OC_OK=false
  fi

  $OC_OK || error "No se pudo instalar OpenCode. Verifica tu conexión."

  # Asegurar PATH
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     grep -q "\.local/bin" /root/.bashrc 2>/dev/null || \
       echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> /root/.bashrc' 2>/dev/null || true

  OC_VER=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
     opencode --version 2>/dev/null | head -1' 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$OC_VER" ] && OC_VER="unknown"
  log "OpenCode instalado: v${OC_VER}"
  mark_done "proot_opencode_install"
fi

# ── PASO P3 — Scripts proot ───────────────────────────────────
titulo "PASO P3 — Scripts de control"

if check_done "proot_scripts"; then
  log "Scripts ya creados [checkpoint]"
else
  mkdir -p "$OPENCODE_SCRIPTS"

  cat > "$OPENCODE_SCRIPTS/opencode_start.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
# Lanzador OpenCode Web — proot — termux-ai-stack
DISTRO="${DISTRO_NAME}"
SESSION="opencode"
PORT=3000
CWD="\${1:-/root}"

if tmux has-session -t "\$SESSION" 2>/dev/null; then
  echo -e "\033[0;32m[OK]\033[0m OpenCode ya corriendo — http://127.0.0.1:\${PORT}"
  exit 0
fi

echo -e "\033[0;36m[+] Iniciando OpenCode Web en Debian proot...\033[0m"
proot-distro login "\$DISTRO" -- bash -c \
  "source ~/.bashrc 2>/dev/null; BROWSER= opencode web --port \$PORT --hostname 127.0.0.1 --cwd '\$CWD'" &
echo \$! > "\$HOME/.opencode_web.pid"

sleep 3
echo -e "\033[0;32m[OK]\033[0m Servidor iniciado — http://127.0.0.1:\${PORT}"
echo -e "     \033[2mAbre en Brave, Chrome u otro navegador\033[0m"
SCRIPT
  chmod +x "$OPENCODE_SCRIPTS/opencode_start.sh"
  log "opencode_start.sh (proot)"

  cat > "$OPENCODE_SCRIPTS/opencode_stop.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
SESSION="opencode"
pkill -f "opencode web" 2>/dev/null || true
[ -f "$HOME/.opencode_web.pid" ] && {
  kill "$(cat "$HOME/.opencode_web.pid")" 2>/dev/null || true
  rm -f "$HOME/.opencode_web.pid"
}
tmux kill-session -t "$SESSION" 2>/dev/null && echo "✓ OpenCode detenido" || echo "OpenCode no estaba corriendo"
SCRIPT
  chmod +x "$OPENCODE_SCRIPTS/opencode_stop.sh"
  log "opencode_stop.sh"

  mark_done "proot_scripts"
fi

# ── PASO P4 — Aliases proot ───────────────────────────────────
titulo "PASO P4 — Aliases en ~/.bashrc"

if check_done "proot_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"
  grep -v "opencode-web\|opencode-stop\|opencode-status\|opencode-tui\|# OpenCode · aliases" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << ALIASES

# ════════════════════════════════
#  OpenCode · aliases (proot)
# ════════════════════════════════
alias opencode-web='bash ~/scripts/opencode/opencode_start.sh'
alias opencode-stop='bash ~/scripts/opencode/opencode_stop.sh'
alias opencode-status='tmux has-session -t opencode 2>/dev/null && echo "OpenCode corriendo en :3000" || echo "OpenCode detenido"'
alias opencode-tui='proot-distro login ${DISTRO_NAME} -- bash -c "source ~/.bashrc 2>/dev/null; opencode"'
alias debian='proot-distro login ${DISTRO_NAME}'
ALIASES

  log "Aliases agregados"
  mark_done "proot_aliases"
fi

# ── PASO P5 — Registry proot ──────────────────────────────────
titulo "PASO P5 — Actualizando registry"

OC_VER_FINAL=$(proot-distro login "$DISTRO_NAME" -- bash -c \
  'source ~/.bashrc 2>/dev/null; opencode --version 2>/dev/null | head -1' 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$OC_VER_FINAL" ] && OC_VER_FINAL="unknown"
update_registry "$OC_VER_FINAL" "proot_debian"

rm -f "$CHECKPOINT"

titulo "INSTALACIÓN PROOT COMPLETADA"
echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║   OpenCode (proot) instalado con éxito ✓   ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"
echo "  Versión:  v${OC_VER_FINAL}"
echo "  Modo:     proot Debian"
echo "  Puerto:   3000"
echo ""
echo "  COMANDOS:"
echo "  opencode-web              → servidor web en :3000"
echo "  opencode-stop             → detener servidor"
echo "  opencode-status           → verificar estado"
echo "  opencode-tui              → TUI en Debian proot"
echo "  debian                    → entrar a Debian proot"
echo ""
echo "  DESDE EL MENÚ:"
echo "  menu → [2] Code Tools → [2] OpenCode"
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para activar aliases${NC}"
echo ""

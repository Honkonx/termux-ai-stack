#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_antigravity.sh
#  Instala Antigravity CLI (agy) en Termux nativo ARM64
#
#  USO:
#    bash install_antigravity.sh          → instalar / menú
#    AGY_MODE=update bash install_antigravity.sh → actualizar
#
#  QUÉ HACE:
#    ✅ Descarga antigravity-termux-standalone.tar.gz del fork
#    ✅ Instala binarios agy + agy.va39 en $PREFIX/bin/
#    ✅ Verifica dependencias: glibc, curl, tar, ca-certificates
#    ✅ Detecta LSE atomics (POCO F5 ✓) — fallback QEMU si falta
#    ✅ Escribe estado al registry ~/.android_server_registry
#    ✅ NO usa /tmp/ (noexec Android 15) — rutas en $HOME/
#
#  NOTA TÉCNICA:
#    El instalador oficial usa /tmp/ — violación en Android 15.
#    Este wrapper sobrescribe TMP y EXTRACT_DIR a $HOME/.agy_install/
#    y pasa AGY_INSTALL_SKIP_LAUNCH=1 para no lanzar el CLI
#    al final de la instalación.
#
#  VERSIÓN: 1.1.0 | Julio 2026
# ============================================================

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Modo silencioso (invocado desde menu.sh, confirmación ya hecha ahí) ──
SILENT_MODE=false
for _arg in "$@"; do [ "$_arg" = "--silent" ] && SILENT_MODE=true; done

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()    { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "  ${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "  ${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "  ${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }

# ── Archivos de estado ────────────────────────────────────────
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_antigravity_checkpoint"
# REGLA TÉCNICA: NUNCA /tmp/ en Android 15 (noexec)
AGY_WORKDIR="$HOME/.agy_install"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Cleanup on interrupt ─────────────────────────────────────
AGY_INSTALL_OK=0
_agy_cleanup() {
  if [ "$AGY_INSTALL_OK" -eq 0 ] && [ -d "$AGY_WORKDIR" ]; then
    rm -rf "$AGY_WORKDIR"
  fi
}
trap '_agy_cleanup' EXIT
trap 'echo ""; warn "Instalación cancelada."; _agy_cleanup; exit 130' INT TERM

# ── Registry ─────────────────────────────────────────────────
update_registry() {
  local version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^antigravity\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
antigravity.installed=true
antigravity.version=$version
antigravity.install_date=$date_now
antigravity.location=termux_native
antigravity.binary=$TERMUX_PREFIX/bin/agy
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → antigravity v${version}"
}

# ── Detectar instalación previa ───────────────────────────────
_check_installed() {
  command -v agy &>/dev/null && \
  [ -f "$TERMUX_PREFIX/bin/agy" ] && \
  [ -f "$TERMUX_PREFIX/bin/agy.va39" ]
}

# ── Función: actualizar (agy update) ─────────────────────────
_update_antigravity() {
  titulo "ACTUALIZACIÓN — Antigravity CLI"

  local _VER_ANTES
  _VER_ANTES=$(agy --version 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1)
  [ -z "$_VER_ANTES" ] && \
    _VER_ANTES=$(grep "^antigravity\.version=" "$REGISTRY" 2>/dev/null | cut -d= -f2)
  echo -e "  Versión actual: ${CYAN}${_VER_ANTES:-desconocida}${NC}"; echo ""

  info "Ejecutando: agy update"
  # agy update es self-updating nativo — maneja descarga y parches VA39
  if agy update 2>&1; then
    local _VER_NUEVA
    _VER_NUEVA=$(agy --version 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1)
    [ -n "$_VER_NUEVA" ] && update_registry "$_VER_NUEVA"
    echo ""
    echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════════╗"
    echo    "  ║  [OK] Antigravity CLI actualizado      ║"
    echo    "  ╠══════════════════════════════════════════╣"
    printf  "  ║  ${NC}Antes:  %-34s${GREEN}${BOLD}║\n" "${_VER_ANTES:-?}"
    printf  "  ║  ${NC}Ahora:  %-34s${GREEN}${BOLD}║\n" "${_VER_NUEVA:-?}"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    AGY_INSTALL_OK=1
  else
    echo -e "  ${RED}[ERROR]${NC} agy update falló"
    echo -e "  ${DIM}Intenta reinstalar con: bash install_antigravity.sh${NC}"
    exit 1
  fi
  echo ""
}

# ── Dispatch rápido desde menú externo ───────────────────────
if [ "${AGY_MODE:-}" = "update" ]; then
  if _check_installed; then
    _update_antigravity
    AGY_INSTALL_OK=1; exit 0
  else
    error "Antigravity no instalado — instala primero"
  fi
fi

# ── Si ya está instalado: preguntar ──────────────────────────
if _check_installed; then
  _VER_ACTUAL=$(agy --version 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1)
  [ -z "$_VER_ACTUAL" ] && \
    _VER_ACTUAL=$(grep "^antigravity\.version=" "$REGISTRY" 2>/dev/null | cut -d= -f2)
  if $SILENT_MODE; then
    # Invocado con --silent y ya instalado: la elección real (actualizar
    # vs reinstalar) ya se hizo en el menú que llamó a este script —
    # aquí solo se procede a reinstalar desde cero sin volver a preguntar
    rm -f "$CHECKPOINT"
  else
    echo ""
    echo -e "  ${GREEN}✓ Antigravity CLI ya instalado${NC} (v${_VER_ACTUAL:-?})"
    echo ""
    echo -e "  ${BOLD}¿Qué deseas hacer?${NC}"; echo ""
    echo -e "  ${GREEN}[1]${NC} Actualizar  ${DIM}(agy update — self-updating)${NC}"
    echo -e "  [2] Reinstalar  ${DIM}(descarga completa desde cero)${NC}"
    echo -e "  [q] Cancelar"
    echo ""; echo -n "  Opción: "
    read -r _AGY_OPT < /dev/tty
    case "$_AGY_OPT" in
      1) _update_antigravity; exit 0 ;;
      2) rm -f "$CHECKPOINT" ;;
      q|Q|"") info "Nada que hacer."; exit 0 ;;
      *) info "Nada que hacer."; exit 0 ;;
    esac
  fi
fi

# ════════════════════════════════════════════════════════════
#  INSTALACIÓN
# ════════════════════════════════════════════════════════════
clear; echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  ✦ ANTIGRAVITY CLI — Instalador         ║"
echo    "  ║  termux-ai-stack · ARM64 · sin root     ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Confirmación (solo si se corre standalone — menu.sh ya confirma antes) ──
if ! $SILENT_MODE; then
  echo -e "  Vas a instalar Antigravity CLI (~46MB, binario nativo ARM64)."
  echo -n "  ¿Continuar? (s/n): "
  read -r _CONFIRM < /dev/tty
  [ "$_CONFIRM" != "s" ] && [ "$_CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }
  echo ""
fi

# ── PASO 1 — Dependencias ─────────────────────────────────────
titulo "PASO 1 — Dependencias del sistema"
if check_done "deps"; then
  log "Dependencias ya instaladas [checkpoint]"
else
  info "Verificando: glibc, curl, ca-certificates, resolv-conf..."
  _GLIBC_MISSING=false
  [ ! -f "$TERMUX_PREFIX/glibc/lib/ld-linux-aarch64.so.1" ] && _GLIBC_MISSING=true

  if $_GLIBC_MISSING; then
    info "glibc no detectado — instalando glibc-repo..."
    pkg install -y glibc-repo \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>/dev/null || \
      error "No se pudo instalar glibc-repo"
    info "Actualizando índices de paquetes (repo glibc recién agregado)..."
    pkg update -y 2>/dev/null || error "pkg update falló tras agregar glibc-repo"
  fi

  _MISSING_DEPS=()
  $_GLIBC_MISSING && _MISSING_DEPS+=("glibc-runner")
  command -v curl &>/dev/null || _MISSING_DEPS+=("curl")
  [ ! -s "$TERMUX_PREFIX/etc/tls/cert.pem" ] && \
    _MISSING_DEPS+=("ca-certificates")
  [ ! -r "$TERMUX_PREFIX/etc/resolv.conf" ] && \
    _MISSING_DEPS+=("resolv-conf")

  if [ ${#_MISSING_DEPS[@]} -gt 0 ]; then
    info "Instalando: ${_MISSING_DEPS[*]}"
    pkg install -y "${_MISSING_DEPS[@]}" \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>/dev/null || \
      error "No se pudieron instalar dependencias: ${_MISSING_DEPS[*]}"
  fi

  # Verificar LSE atomics (POCO F5 tiene Snapdragon 7+ Gen 2 — soporta LSE)
  if grep -q "atomics" /proc/cpuinfo 2>/dev/null; then
    log "LSE atomics: soportado (nativo)"
  elif command -v qemu-aarch64 &>/dev/null; then
    warn "LSE no soportado — usando QEMU (puede ser lento)"
  else
    error "CPU sin LSE y sin qemu-aarch64\n  Instala: pkg install qemu-user-aarch64"
  fi

  mark_done "deps"
  log "Dependencias verificadas"
fi

# ── PASO 2 — Descargar e instalar binarios ────────────────────
titulo "PASO 2 — Descargando Antigravity CLI"
if check_done "binaries"; then
  log "Binarios ya instalados [checkpoint]"
else
  # REGLA TÉCNICA: NUNCA /tmp/ → usar $HOME/.agy_install/
  rm -rf "$AGY_WORKDIR"
  mkdir -p "$AGY_WORKDIR"

  _FORK="Honkonx/antigravity-cli-termux"
  _TAR="$AGY_WORKDIR/antigravity-termux-standalone.tar.gz"
  _EXTRACT="$AGY_WORKDIR/extract"
  mkdir -p "$_EXTRACT"

  info "Descargando desde github.com/${_FORK}..."
  info "Tamaño: ~46MB — puede tardar 1-3 min"

  # Descargar usando curl (no requests — regla técnica)
  if ! curl -fL --progress-bar \
    "https://github.com/${_FORK}/releases/latest/download/antigravity-termux-standalone.tar.gz" \
    -o "$_TAR" 2>/dev/null; then
    rm -rf "$AGY_WORKDIR"
    error "Descarga fallida — verifica conexión\n  URL: github.com/${_FORK}/releases/latest"
  fi

  [ -s "$_TAR" ] || error "Archivo descargado vacío"
  log "Descargado: $(du -sh "$_TAR" | cut -f1)"

  # Extraer
  info "Extrayendo binarios..."
  tar -xzf "$_TAR" -C "$_EXTRACT" agy agy.va39 2>/dev/null || \
    error "Fallo al extraer — archivo corrupto"

  [ -f "$_EXTRACT/agy" ] && [ -f "$_EXTRACT/agy.va39" ] || \
    error "Binarios no encontrados en el archivo"

  # Instalar
  info "Instalando en $TERMUX_PREFIX/bin/..."
  # Backup si existe versión anterior
  [ -f "$TERMUX_PREFIX/bin/agy" ] && \
    cp "$TERMUX_PREFIX/bin/agy" "$AGY_WORKDIR/agy.bak" 2>/dev/null || true
  [ -f "$TERMUX_PREFIX/bin/agy.va39" ] && \
    cp "$TERMUX_PREFIX/bin/agy.va39" "$AGY_WORKDIR/agy.va39.bak" 2>/dev/null || true

  install -m 0755 "$_EXTRACT/agy"      "$TERMUX_PREFIX/bin/agy"      || \
    error "No se pudo instalar agy"
  install -m 0755 "$_EXTRACT/agy.va39" "$TERMUX_PREFIX/bin/agy.va39" || \
    error "No se pudo instalar agy.va39"

  # Verificar
  [ -f "$TERMUX_PREFIX/bin/agy" ] && [ -f "$TERMUX_PREFIX/bin/agy.va39" ] || \
    error "Verificación fallida — binarios no encontrados"

  rm -rf "$AGY_WORKDIR"
  mark_done "binaries"
  log "Binarios instalados: agy + agy.va39"
fi

# ── PASO 3 — Verificar versión ────────────────────────────────
titulo "PASO 3 — Verificación"
_AGY_VER=$(agy --version 2>/dev/null | grep -oE '[0-9]+\.[0-9.]+' | head -1)
if [ -n "$_AGY_VER" ]; then
  log "Antigravity CLI v${_AGY_VER} ejecutándose correctamente"
else
  warn "No se pudo verificar la versión — puede requerir autenticación al ejecutar"
  _AGY_VER="installed"
fi

# ── PASO 4 — Registry ────────────────────────────────────────
titulo "PASO 4 — Registro"
update_registry "${_AGY_VER}"
rm -f "$CHECKPOINT"
AGY_INSTALL_OK=1

# ── Resultado ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  [OK] Antigravity CLI instalado        ║"
echo    "  ╠══════════════════════════════════════════╣"
printf  "  ║  ${NC}Versión: %-33s${GREEN}${BOLD}║\n" "v${_AGY_VER}"
printf  "  ║  ${NC}Binario: %-33s${GREEN}${BOLD}║\n" "$TERMUX_PREFIX/bin/agy"
echo    "  ╠══════════════════════════════════════════╣"
echo -e "  ║  ${NC}Uso: agy                              ${GREEN}${BOLD}║"
echo -e "  ║  ${NC}     agy update  (actualizar)         ${GREEN}${BOLD}║"
echo -e "  ║  ${NC}     agy --help  (ayuda)              ${GREEN}${BOLD}║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${DIM}Autenticación: la primera vez que ejecutes 'agy'${NC}"
echo -e "  ${DIM}se abrirá Google Sign-In en el navegador.${NC}"
echo ""

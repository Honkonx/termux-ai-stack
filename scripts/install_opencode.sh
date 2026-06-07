#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_opencode.sh
#  Instala OpenCode en proot Debian (ARM64, sin root)
#
#  USO STANDALONE:
#    bash install_opencode.sh
#
#  QUÉ HACE:
#    ✅ Verifica que proot-distro y Debian estén instalados
#    ✅ Instala dependencias en Debian (curl, ripgrep, tmux)
#    ✅ Instala OpenCode vía instalador oficial (curl | bash)
#    ✅ Fallback: npm install -g opencode-ai
#    ✅ Crea lanzador ~/opencode_start.sh en Termux
#    ✅ Agrega aliases a .bashrc
#    ✅ Escribe estado al registry ~/.android_server_registry
#
#  NOTA TÉCNICA:
#    OpenCode usa binarios compilados con glibc.
#    NO funciona en Termux nativo (Bionic libc).
#    Solución: proot-distro con Debian Bookworm (glibc puro).
#    La interfaz TUI puede tener problemas de PTY — usar modo web.
#    Modo web validado: opencode web --port 3000 --hostname 127.0.0.1
#
#  VERSIÓN: 1.2.0 | Mayo 2026
# ============================================================

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
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
CHECKPOINT="$HOME/.install_opencode_checkpoint"

# ── Rutas de scripts ──────────────────────────────────────────
OPENCODE_SCRIPTS="$HOME/scripts/opencode"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

update_registry() {
  local version="$1"
  local date_now; date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^opencode\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
opencode.installed=true
opencode.version=$version
opencode.install_date=$date_now
opencode.location=proot_debian
opencode.port=3000
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · OpenCode Installer     ║
  ║   proot Debian ARM64 · sin root            ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ============================================================
# PASO 1 — Verificar proot-distro y rootfs Debian
# FUENTE PRIMARIA: proot-distro list (fiable con permisos 700 del rootfs)
# FALLBACK: enumeración de directorios en installed-rootfs/
# Fix S22: permisos 0700 en debian/ bloqueaban [ -f dir/bin/bash ]
# ============================================================
titulo "PASO 1 — Verificando entorno proot"

# Instalar proot-distro si no está disponible
if ! command -v proot-distro &>/dev/null; then
  info "Instalando proot-distro..."
  pkg install proot-distro proot tmux curl wget tar xz-utils git busybox -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    error "No se pudo instalar proot-distro."
fi

ROOTFS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/installed-rootfs"
DISTRO_NAME=""
ROOTFS_PATH=""
_detect_rootfs() {
  DISTRO_NAME=""
  ROOTFS_PATH=""
  # Método 1: proot-distro list (no requiere entrar al directorio)
  if command -v proot-distro &>/dev/null; then
    local _pd_out
    _pd_out=$(proot-distro list 2>/dev/null)
    local _d
    for _d in debian ubuntu fedora archlinux; do
      if echo "$_pd_out" | grep -qE "^\s*\*?\s*${_d}\b"; then
        if [ -d "$ROOTFS_BASE/$_d" ]; then
          DISTRO_NAME="$_d"
          ROOTFS_PATH="$ROOTFS_BASE/$_d"
          return 0
        fi
      fi
    done
  fi
  # Método 2: fallback por directorio (solo verificar que el dir existe)
  if [ -d "$ROOTFS_BASE" ]; then
    local _rd
    for _rd in "$ROOTFS_BASE"/*/; do
      _rd="${_rd%/}"
      if [ -d "$_rd" ]; then
        DISTRO_NAME=$(basename "$_rd")
        ROOTFS_PATH="$ROOTFS_BASE/$DISTRO_NAME"
        return 0
      fi
    done
  fi
  return 1
}
_detect_rootfs

if [ -n "$DISTRO_NAME" ]; then
  log "Rootfs encontrado: $DISTRO_NAME ($ROOTFS_PATH)"
else
  warn "Rootfs Debian no encontrado en $ROOTFS_BASE"
  echo ""
  echo -e "  ${CYAN}¿Cómo instalar Debian?${NC}"
  echo ""
  echo -e "  ${GREEN}[1]${NC} Desde GitHub Releases  (rápido ~5-10 min, proot-base)"
  echo -e "  ${GREEN}[2]${NC} Instalación limpia     (proot-distro install, ~15-25 min)"
  echo -e "  ${GREEN}[b]${NC} Cancelar"
  echo ""
  echo -n "  Opción: "
  read -r INSTALL_ROOTFS_OPT < /dev/tty

  case "$INSTALL_ROOTFS_OPT" in
    1)
      info "Descargando rootfs desde GitHub Releases..."
      if [ ! -f "$HOME/restore.sh" ]; then
        curl -fsSL "https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/restore.sh" \
          -o "$HOME/restore.sh" && chmod +x "$HOME/restore.sh"
      fi
      bash "$HOME/restore.sh" --module proot-base --source github || \
        error "Fallo la restauración del rootfs Debian"
      ;;
    2)
      info "Instalando Debian con proot-distro..."
      if proot-distro list 2>/dev/null | grep -qE "^\s*\*?\s*debian\b"; then
        log "Rootfs debian ya registrado en proot-distro — saltando instalación"
      else
        _INSTALL_OUT=$(proot-distro install debian 2>&1)
        _INSTALL_RC=$?
        if echo "$_INSTALL_OUT" | grep -q "already exists"; then
          log "Debian ya registrado en proot-distro — continuando"
        elif [ $_INSTALL_RC -ne 0 ]; then
          echo "$_INSTALL_OUT"
          error "No se pudo instalar Debian en proot."
        fi
      fi
      ;;
    b|B|"")
      error "Cancelado por el usuario"
      ;;
    *)
      error "Opción inválida"
      ;;
  esac

  sleep 2
  _detect_rootfs
  [ -z "$DISTRO_NAME" ] && \
    error "Rootfs Debian no disponible tras la instalación — verifica: ls $ROOTFS_BASE"
  log "Rootfs listo: $DISTRO_NAME"
fi

# ── Verificar si OpenCode ya está instalado ──────────────────
# Ahora que tenemos DISTRO_NAME correcto, podemos hacer el check
if proot-distro login "$DISTRO_NAME" -- bash -c \
  'source ~/.bashrc 2>/dev/null; command -v opencode' &>/dev/null 2>&1; then
  OC_VER=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'opencode --version 2>/dev/null | head -1' 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  echo ""
  echo -e "${GREEN}  ✓ OpenCode ya está instalado${NC}"
  echo -e "  Versión actual: ${CYAN}${OC_VER:-?}${NC}"
  echo ""
  echo -n "  ¿Reinstalar/actualizar? (s/n): "
  read -r REINSTALL < /dev/tty
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
fi

echo ""
echo "  Este script instalará OpenCode en Debian proot:"
echo "  ▸ Distro detectada: $DISTRO_NAME"
echo "  ▸ Dependencias: curl ripgrep tmux"
echo "  ▸ OpenCode vía instalador oficial"
echo "  ▸ Fallback: npm install -g opencode-ai"
echo "  ▸ Scripts en: ~/scripts/opencode/"
echo "  ▸ Aliases: opencode-web, opencode-stop, opencode-status"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRM < /dev/tty
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 2 — Dependencias en Debian
# ============================================================
titulo "PASO 2 — Dependencias en Debian"

if check_done "debian_deps"; then
  log "Dependencias ya instaladas [checkpoint]"
else
  info "Actualizando apt e instalando dependencias..."
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     apt-get update -qq -o Acquire::Check-Valid-Until=false 2>/dev/null || true
     apt-get install -y --no-install-recommends curl ripgrep tmux nodejs npm 2>&1 | tail -5' || \
    warn "Algunas dependencias pueden no haberse instalado — continuando..."

  log "Dependencias instaladas"
  mark_done "debian_deps"
fi

# ============================================================
# PASO 3 — Instalar OpenCode
# ============================================================
titulo "PASO 3 — Instalando OpenCode"

if check_done "opencode_install"; then
  log "OpenCode ya instalado [checkpoint]"
else
  # Estrategia 1: instalador oficial
  info "Intentando instalador oficial (curl | bash)..."
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     curl -fsSL https://opencode.ai/install | bash 2>&1' && \
    OC_OK=true || OC_OK=false

  # Verificar que realmente funciona — PATH explícito, sin source bashrc
  if $OC_OK; then
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'export HOME=/root
       export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
       command -v opencode' &>/dev/null 2>&1 || OC_OK=false
  fi

  # Estrategia 2: npm
  if ! $OC_OK; then
    warn "Instalador oficial falló — intentando vía npm..."
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'export HOME=/root
       npm install -g opencode-ai 2>&1 | tail -5' && \
      OC_OK=true || OC_OK=false
  fi

  if ! $OC_OK; then
    error "No se pudo instalar OpenCode. Verifica tu conexión e intenta de nuevo."
  fi

  # Obtener versión — PATH explícito, sin source bashrc
  OC_VER=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
     opencode --version 2>/dev/null | head -1' 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$OC_VER" ] && OC_VER="unknown"

  # Asegurar que ~/.local/bin esté en PATH del proot para futuras sesiones
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root
     grep -q "\.local/bin" /root/.bashrc 2>/dev/null || \
       echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> /root/.bashrc' 2>/dev/null || true

  log "OpenCode instalado: v${OC_VER}"
  mark_done "opencode_install"
fi

# ============================================================
# PASO 4 — Crear lanzador en Termux
# ============================================================
titulo "PASO 4 — Lanzador y scripts de control"

if check_done "opencode_scripts"; then
  log "Scripts ya creados [checkpoint]"
else
  mkdir -p "$OPENCODE_SCRIPTS"

  # Script de inicio del servidor web
  cat > "$OPENCODE_SCRIPTS/opencode_start.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
# Lanzador OpenCode Web — termux-ai-stack
DISTRO="${DISTRO_NAME}"
SESSION="opencode"
PORT=3000
CWD="\${1:-/root}"  # Acepta --cwd como argumento opcional

if tmux has-session -t "\$SESSION" 2>/dev/null; then
  echo -e "${GREEN}[OK]${NC} OpenCode ya corriendo en tmux sesión: \$SESSION"
  echo -e "     URL: http://127.0.0.1:\${PORT}"
  exit 0
fi

echo -e "${CYAN}[+] Iniciando OpenCode Web en Debian proot...${NC}"
proot-distro login "\$DISTRO" -- bash -c \
  "tmux kill-session -t \$SESSION 2>/dev/null; \
   tmux new-session -d -s \$SESSION \
   'source ~/.bashrc 2>/dev/null; \
    opencode web --port \$PORT --hostname 127.0.0.1 --cwd \"\$CWD\"'"

sleep 2
if tmux has-session -t "\$SESSION" 2>/dev/null; then
  echo -e "${GREEN}[OK]${NC} Servidor iniciado"
  echo -e "     URL: http://127.0.0.1:\${PORT}"
  echo -e "     ${DIM}Abre en Brave, Chrome u otro navegador${NC}"
else
  echo -e "${RED}[ERROR]${NC} No se pudo iniciar. Verifica con: proot-distro login debian"
fi
SCRIPT
  chmod +x "$OPENCODE_SCRIPTS/opencode_start.sh"
  log "opencode_start.sh creado"

  # Script de parada
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
  log "opencode_stop.sh creado"

  mark_done "opencode_scripts"
fi

# ============================================================
# PASO 5 — Aliases en .bashrc
# ============================================================
titulo "PASO 5 — Configurando aliases"

if check_done "opencode_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"
  grep -v "opencode-web\|opencode-stop\|opencode-status\|opencode-tui" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << ALIASES

# ════════════════════════════════
#  OpenCode · aliases
# ════════════════════════════════
alias opencode-web='bash ~/scripts/opencode/opencode_start.sh'
alias opencode-stop='bash ~/scripts/opencode/opencode_stop.sh'
alias opencode-status='tmux has-session -t opencode 2>/dev/null && echo "OpenCode corriendo en :3000" || echo "OpenCode detenido"'
alias opencode-tui='proot-distro login ${DISTRO_NAME} -- bash -c "source ~/.bashrc 2>/dev/null; opencode"'
alias debian='proot-distro login ${DISTRO_NAME}'
ALIASES

  log "Aliases agregados a ~/.bashrc"
  mark_done "opencode_aliases"
fi

# ============================================================
# PASO 6 — Registry
# ============================================================
titulo "PASO 6 — Actualizando registry"

OC_VER_FINAL=$(proot-distro login "$DISTRO_NAME" -- bash -c \
  'source ~/.bashrc 2>/dev/null; opencode --version 2>/dev/null | head -1' 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$OC_VER_FINAL" ] && OC_VER_FINAL="unknown"

update_registry "$OC_VER_FINAL"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║     OpenCode instalado con éxito ✓         ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  Versión:  v${OC_VER_FINAL}"
echo "  Puerto:   3000"
echo "  Entorno:  proot Debian"
echo ""
echo "  COMANDOS:"
echo "  opencode-web              → servidor web en :3000"
echo "  opencode-stop             → detener servidor"
echo "  opencode-status           → verificar estado"
echo "  opencode-tui              → interfaz TUI en terminal"
echo "  debian                    → entrar a Debian proot"
echo ""
echo "  DESDE EL MENÚ:"
echo "  menu → [7] OpenCode → [2] Servidor web"
echo "  menu → [7] OpenCode → [1] TUI"
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para activar aliases${NC}"
echo -e "${CYAN}  → Luego: opencode-web y abre http://127.0.0.1:3000${NC}"
echo ""

# Limpiar checkpoint
rm -f "$CHECKPOINT"

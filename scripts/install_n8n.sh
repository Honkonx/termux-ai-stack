#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_n8n.sh
#  Instala n8n en Termux (proot Debian o udocker)
#
#  MODOS:
#    [1] proot Debian — Node.js 20 LTS + n8n + cloudflared
#    [2] udocker      — imagen oficial n8nio/n8n (sin proot)
#
#  REGLAS TÉCNICAS (NO VIOLAR):
#    - NUNCA /tmp/ → siempre $HOME/ (noexec Android 15)
#    - NUNCA read sin < /dev/tty en Termux
#    - HTTP: NUNCA requests → urllib o curl builtin
#
#  VERSIÓN: 3.0.0 | Julio 2026
# ============================================================

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"
export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib"
export DEBIAN_FRONTEND=noninteractive

# ── Modo silencioso (invocado desde menu.sh, confirmación ya hecha ahí) ──
SILENT_MODE=false
for _arg in "$@"; do [ "$_arg" = "--silent" ] && SILENT_MODE=true; done

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
GRAY='\033[0;90m'
NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }

# ── Archivos de estado ────────────────────────────────────────
REGISTRY="$TERMUX_HOME/.android_server_registry"
CHECKPOINT_PROOT="$TERMUX_HOME/.install_n8n_proot_checkpoint"
CHECKPOINT_UDOCKER="$TERMUX_HOME/.install_n8n_udocker_checkpoint"

# ── Rutas de scripts ──────────────────────────────────────────
N8N_SCRIPTS_PROOT="$TERMUX_HOME/scripts/n8n"
N8N_SCRIPTS_UDOCKER="$TERMUX_HOME/scripts/n8n-udocker"

check_done() { grep -q "^$1$" "$2" 2>/dev/null; }
mark_done()  { echo "$1" >> "$2"; }

# ── Función: actualizar registry ─────────────────────────────
update_registry() {
  local mode="$1"
  local version="$2"
  local date_now
  date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^n8n\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
n8n.installed=true
n8n.version=$version
n8n.install_date=$date_now
n8n.mode=$mode
n8n.port=5678
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → $REGISTRY"
}

# ── Detección de rootfs proot ────────────────────────────────
# ROOTFS_BASE = layout LEGACY de proot-distro ("installed-rootfs/<nombre>").
# proot-distro fue reescrito de bash a Python y las versiones modernas
# instalan en "containers/<nombre>/rootfs/" — la ruta legacy solo existe
# para migrar instalaciones viejas (confirmado en el código fuente de
# proot-distro). Confiar solo en la ruta legacy hace que _detect_rootfs
# nunca encuentre un rootfs real e instalado, causando el bug persistente
# "container already exists" (ver docs/N8N.md sección 14, 2026-07-26).
ROOTFS_BASE="$TERMUX_PREFIX/var/lib/proot-distro/installed-rootfs"
CONTAINERS_BASE="$TERMUX_PREFIX/var/lib/proot-distro/containers"
DISTRO_NAME=""
ROOTFS_PATH=""

_proot_rootfs_path() {
  local _name="$1"
  [ -d "$CONTAINERS_BASE/$_name/rootfs" ] && { echo "$CONTAINERS_BASE/$_name/rootfs"; return 0; }
  [ -d "$ROOTFS_BASE/$_name" ] && { echo "$ROOTFS_BASE/$_name"; return 0; }
  return 1
}

_detect_rootfs() {
  DISTRO_NAME=""
  ROOTFS_PATH=""
  if command -v proot-distro &>/dev/null; then
    local _pd_out
    _pd_out=$(proot-distro list 2>/dev/null)
    local _d _path
    for _d in debian ubuntu fedora archlinux; do
      if echo "$_pd_out" | grep -qE "^\s*\*?\s*${_d}\b"; then
        _path=$(_proot_rootfs_path "$_d") && {
          DISTRO_NAME="$_d"
          ROOTFS_PATH="$_path"
          return 0
        }
      fi
    done
  fi
  # Fallback: escanear ambos layouts directamente (proot-distro list pudo
  # no reportar nada coincidente — versión desconocida, output inesperado)
  local _rd
  if [ -d "$CONTAINERS_BASE" ]; then
    for _rd in "$CONTAINERS_BASE"/*/; do
      _rd="${_rd%/}"
      [ -d "$_rd/rootfs" ] && { DISTRO_NAME=$(basename "$_rd"); ROOTFS_PATH="$_rd/rootfs"; return 0; }
    done
  fi
  if [ -d "$ROOTFS_BASE" ]; then
    for _rd in "$ROOTFS_BASE"/*/; do
      _rd="${_rd%/}"
      if [ -d "$_rd" ]; then
        DISTRO_NAME=$(basename "$_rd")
        ROOTFS_PATH="$_rd"
        return 0
      fi
    done
  fi
  return 1
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · n8n Installer v3.0      ║
  ║   proot Debian  ·  udocker  ·  ARM64        ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Función: detectar modo instalado ────────────────────────
_detect_n8n_mode() {
  local _mode=""
  if [ -f "$REGISTRY" ]; then
    _mode=$(grep "^n8n\.mode=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  fi
  echo "$_mode"
}

# ── Función: actualizar n8n ──────────────────────────────────
update_n8n() {
  local _installed_mode
  _installed_mode=$(_detect_n8n_mode)

  local _has_proot=false
  local _has_udocker=false

  # Detectar qué variantes están instaladas
  [ "$_installed_mode" = "proot" ] && _has_proot=true
  [ "$_installed_mode" = "udocker" ] && _has_udocker=true

  # Fallback: verificar en disco si el registry no es concluyente
  if [ "$_installed_mode" != "proot" ] && [ "$_installed_mode" != "udocker" ]; then
    [ -f "$N8N_SCRIPTS_PROOT/n8n_update.sh" ]   && _has_proot=true
    command -v udocker &>/dev/null && \
      udocker inspect n8n &>/dev/null && _has_udocker=true
  fi

  if ! $_has_proot && ! $_has_udocker; then
    echo -e "${YELLOW}[AVISO]${NC} No se detectó n8n instalado."
    echo "  Instala primero con opción [1] o [2]."
    echo ""; exit 1
  fi

  # Si solo hay una variante, actualizar directamente
  if $_has_proot && ! $_has_udocker; then
    UPDATE_TARGET="proot"
  elif $_has_udocker && ! $_has_proot; then
    UPDATE_TARGET="udocker"
  else
    # Ambas instaladas — preguntar
    echo -e "  ${BOLD}¿Qué variante de n8n actualizar?${NC}"
    echo ""
    echo -e "  [1] proot Debian  (n8n-update)"
    echo -e "  [2] udocker       (n8n-ud-update)"
    echo -e "  [q] Cancelar"
    echo ""; echo -n "  Opción: "
    read -r _UPD_OPT < /dev/tty
    case "$_UPD_OPT" in
      1) UPDATE_TARGET="proot"   ;;
      2) UPDATE_TARGET="udocker" ;;
      q|Q|"") echo "Cancelado."; exit 0 ;;
      *) echo "Cancelado."; exit 0 ;;
    esac
  fi

  case "$UPDATE_TARGET" in
    proot)
      if [ -f "$N8N_SCRIPTS_PROOT/n8n_update.sh" ]; then
        bash "$N8N_SCRIPTS_PROOT/n8n_update.sh"
      else
        error "Script no encontrado: $N8N_SCRIPTS_PROOT/n8n_update.sh"
      fi ;;
    udocker)
      if [ -f "$N8N_SCRIPTS_UDOCKER/update.sh" ]; then
        bash "$N8N_SCRIPTS_UDOCKER/update.sh"
      else
        error "Script no encontrado: $N8N_SCRIPTS_UDOCKER/update.sh"
      fi ;;
  esac
}

# ── Menú principal de modo ────────────────────────────────────
if [ -n "$N8N_INSTALL_MODE" ]; then
  INSTALL_MODE="$N8N_INSTALL_MODE"
else
  # Detectar si ya hay algo instalado para mostrar opción update
  _CURRENT_MODE=$(_detect_n8n_mode)
  _UPDATE_HINT=""
  if [ -n "$_CURRENT_MODE" ]; then
    _UPDATE_HINT=" ${GRAY}(instalado: ${_CURRENT_MODE})${NC}"
  fi

  echo -e "  ${BOLD}¿Qué quieres hacer con n8n?${NC}"
  echo ""
  echo -e "  [1] n8n en proot Debian"
  echo -e "      ${GRAY}Node.js 20 LTS + n8n + cloudflared · ARM64 nativo${NC}"
  echo -e "      ${GRAY}~300MB · 20-40 min${NC}"
  echo ""
  echo -e "  [2] n8n en udocker"
  echo -e "      ${GRAY}Imagen oficial n8nio/n8n · sin proot, datos en ~/n8n-udocker${NC}"
  echo -e "      ${GRAY}~800MB · 5-15 min${NC}"
  echo ""
  echo -e "  [u] Actualizar n8n${_UPDATE_HINT}"
  echo ""
  echo "  [q] Cancelar"
  echo ""
  echo -n "  Opción (1/2/u/q): "
  read -r INSTALL_MODE < /dev/tty
  echo ""
fi

case "$INSTALL_MODE" in
  q|Q) echo "Cancelado."; exit 0 ;;
  u|U) update_n8n; exit 0 ;;
  1|2) ;;
  *) warn "Opción inválida — usando [2] udocker"; INSTALL_MODE=2 ;;
esac

# ============================================================
# ██████████████████████████████████████████████████████████
#  MODO 1 — proot Debian
# ██████████████████████████████████████████████████████████
# ============================================================
install_proot() {
  local CHECKPOINT="$CHECKPOINT_PROOT"
  info "Modo: proot Debian"

  # ── Verificar si ya está instalado ───────────────────────
  _detect_rootfs
  N8N_INSTALLED=false
  if [ -n "$DISTRO_NAME" ]; then
    if proot-distro login "$DISTRO_NAME" -- bash -c 'command -v n8n' &>/dev/null 2>&1; then
      N8N_INSTALLED=true
    fi
  fi

  if [ "$N8N_INSTALLED" = true ]; then
    # Si N8N_INSTALL_MODE=1 viene del menú → reinstalar sin preguntar
    if [ "${N8N_INSTALL_MODE:-}" = "1" ]; then
      rm -f "$CHECKPOINT"
    else
      N8N_VER=$(proot-distro login "$DISTRO_NAME" -- bash -c \
        'n8n --version 2>/dev/null' 2>/dev/null | head -1)
      echo -e "${GREEN}  ✓ n8n ya instalado en proot${NC} — versión: ${CYAN}${N8N_VER}${NC}"
      echo -n "  ¿Reinstalar/actualizar? (s/n): "
      read -r REINSTALL < /dev/tty
      [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
        info "Nada que hacer."; exit 0
      }
      rm -f "$CHECKPOINT"
    fi
  fi

  # ── Checkpoints previos ───────────────────────────────────
  if [ -f "$CHECKPOINT" ] && [ -s "$CHECKPOINT" ]; then
    # Si viene del menú (N8N_INSTALL_MODE=1) → continuar sin preguntar
    if [ "${N8N_INSTALL_MODE:-}" = "1" ]; then
      echo -e "${YELLOW}  Continuando desde checkpoint anterior...${NC}"
      while IFS= read -r line; do
        echo -e "  ${GREEN}✓${NC} $line [omitido]"
      done < "$CHECKPOINT"
      echo ""
    else
      echo -e "${YELLOW}  Instalación previa detectada — se omitirán:${NC}"
      while IFS= read -r line; do
        echo -e "  ${GREEN}✓${NC} $line"
      done < "$CHECKPOINT"
      echo ""
      echo -n "  ¿Continuar desde donde quedó? (s/n): "
      read -r CONT < /dev/tty
      if [ "$CONT" != "s" ] && [ "$CONT" != "S" ]; then
        echo -n "  ¿Reiniciar desde cero? (s/n): "
        read -r RESET < /dev/tty
        [ "$RESET" = "s" ] || [ "$RESET" = "S" ] && rm -f "$CHECKPOINT"
      fi
      echo ""
    fi
  fi

  # ── PASO 0 — Almacenamiento ───────────────────────────────
  titulo "PASO 0 — Permiso de almacenamiento"
  if check_done "storage" "$CHECKPOINT"; then
    log "Permiso de almacenamiento ya configurado [checkpoint]"
  else
    if [ -d "/sdcard/Download" ]; then
      log "Acceso a /sdcard disponible"
      mark_done "storage" "$CHECKPOINT"
    else
      info "Solicitando permiso de almacenamiento..."
      termux-setup-storage
      sleep 4
      if [ -d "/sdcard/Download" ]; then
        log "Acceso a /sdcard confirmado"
        mark_done "storage" "$CHECKPOINT"
      else
        warn "Acepta el permiso y re-ejecuta el script"
        exit 1
      fi
    fi
  fi

  # ── PASO 1 — Actualizar Termux ────────────────────────────
  titulo "PASO 1 — Verificando Termux"
  if [ -n "$ANDROID_SERVER_READY" ]; then
    log "Termux ya preparado por el maestro [skip]"
  elif check_done "termux_update" "$CHECKPOINT"; then
    log "Termux ya actualizado [checkpoint]"
  else
    info "Actualizando Termux..."
    pkg update -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>/dev/null || warn "pkg update con advertencias"
    pkg install -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      curl wget tar xz-utils tmux \
      proot proot-distro busybox iproute2 git 2>/dev/null || \
      warn "Algunos paquetes tuvieron advertencias"
    mark_done "termux_update" "$CHECKPOINT"
    log "Termux actualizado"
  fi

  # ── PASO 2 — Token cloudflared ────────────────────────────
  titulo "PASO 2 — Configuración cloudflared"
  if check_done "cf_token" "$CHECKPOINT"; then
    log "Cloudflared ya configurado [checkpoint]"
    [ -f "$TERMUX_HOME/.cf_token" ] && \
      info "Modo: URL FIJA (token guardado)" || \
      info "Modo: URL temporal (sin token)"
  elif $SILENT_MODE; then
    rm -f "$TERMUX_HOME/.cf_token"
    info "Modo silencioso — omitiendo token de Cloudflare, se usará túnel rápido (URL temporal). Agrégalo después desde el menú de n8n si quieres una URL fija."
    mark_done "cf_token" "$CHECKPOINT"
  else
    echo ""
    echo "  TÚNEL CLOUDFLARED:"
    echo "  A) Sin cuenta → URL cambia en cada reinicio (ENTER)"
    echo "  B) Con cuenta Cloudflare → URL fija permanente (gratis)"
    echo "     cloudflare.com → Zero Trust → Networks → Tunnels → Create tunnel"
    echo ""
    echo -n "  Token cloudflared (ENTER para URL temporal): "
    read -r CF_TOKEN < /dev/tty
    echo ""
    if [ -n "$CF_TOKEN" ]; then
      echo "$CF_TOKEN" > "$TERMUX_HOME/.cf_token"
      log "Token guardado — URL fija permanente"
    else
      rm -f "$TERMUX_HOME/.cf_token"
      info "Sin token — URL temporal"
    fi
    mark_done "cf_token" "$CHECKPOINT"
  fi

  # ── PASO 3 — Instalar Debian ──────────────────────────────
  titulo "PASO 3 — Instalando Debian Bookworm"
  _detect_rootfs
  if check_done "debian_install" "$CHECKPOINT"; then
    log "Debian ya instalado [checkpoint]"
    [ -z "$DISTRO_NAME" ] && \
      error "Checkpoint activo pero rootfs no encontrado en $ROOTFS_BASE"
  else
    if [ -n "$DISTRO_NAME" ]; then
      log "Rootfs ya existe — saltando instalación"
      log "Distro: $DISTRO_NAME  Ruta: $ROOTFS_PATH"
    else
      echo ""
      echo -e "  ${YELLOW}Instalando rootfs Debian Bookworm ARM64...${NC}"
      echo -e "  ${YELLOW}~200MB comprimido / ~500MB expandido · 5-15 min${NC}"
      echo ""
      # Verificar espacio libre antes de extraer (~500MB necesarios) —
      # una extracción con poco espacio puede quedar silenciosamente
      # incompleta (exit 0 de proot-distro, pero rootfs a medias)
      _FREE_KB=$(df -Pk "$TERMUX_PREFIX" 2>/dev/null | awk 'NR==2{print $4}')
      if [ -n "$_FREE_KB" ] && [ "$_FREE_KB" -lt 1048576 ]; then
        warn "Poco espacio libre ($((_FREE_KB / 1024))MB) — se necesitan ~500MB, la extracción puede quedar incompleta"
      fi
      _INSTALL_OUT=$(proot-distro install debian 2>&1)
      _INSTALL_RC=$?
      if echo "$_INSTALL_OUT" | grep -q "already exists"; then
        log "Debian ya registrado en proot-distro"
      elif [ $_INSTALL_RC -ne 0 ]; then
        echo "$_INSTALL_OUT"
        error "Falló instalación de Debian"
      fi
      # Reintentar detección: en dispositivo real el FS puede tardar
      # más de 2s en reflejar los ~500MB recién extraídos (condición
      # de carrera confirmada — proot-distro login funciona bien
      # manualmente segundos después de un falso "no encontrado")
      for _i in $(seq 1 10); do
        _detect_rootfs
        [ -n "$DISTRO_NAME" ] && break
        sleep 2
      done
      if [ -z "$DISTRO_NAME" ]; then
        # proot-distro reportó éxito (exit 0) pero el rootfs nunca
        # aparece — no es (solo) timing, volcar el output real que
        # antes se descartaba en silencio para poder diagnosticar
        warn "Output real de 'proot-distro install debian' (para diagnóstico):"
        echo "$_INSTALL_OUT"
        error "Rootfs no encontrado tras instalación — revisa: ls $ROOTFS_BASE"
      fi
      log "Debian instalado: $DISTRO_NAME ($ROOTFS_PATH)"
    fi
    mark_done "debian_install" "$CHECKPOINT"
  fi
  info "Usando distro: ${DISTRO_NAME}"

  # ── PASO 4 — Instalar n8n + cloudflared ──────────────────
  titulo "PASO 4 — Instalando n8n + cloudflared en Debian"
  if check_done "n8n_install" "$CHECKPOINT"; then
    log "n8n ya instalado [checkpoint]"
  else
    info "Instalando software en Debian (15-25 min)..."
    info "No cierres Termux durante este paso..."

    # Escribir script al rootfs — evitar heredoc + proot stdin bug
    _N8N_SETUP_SCRIPT="${ROOTFS_PATH}/root/n8n_setup_inner.sh"
    cat > "$_N8N_SETUP_SCRIPT" << 'INNERSCRIPT'
#!/bin/bash
set -e
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

echo "[1/6] Actualizando sistema Debian..."
apt-get update -qq -o Acquire::Check-Valid-Until=false 2>/dev/null || \
  apt-get update -qq --allow-insecure-repositories 2>/dev/null || \
  echo "[AVISO] apt update tuvo errores — continuando"
apt-get upgrade -y -qq $DPKG_OPTS 2>/dev/null || true
apt-get install -y -qq $DPKG_OPTS \
  curl wget git nano build-essential \
  python3 python3-pip python3-setuptools python3-dev \
  ca-certificates gnupg lsb-release \
  procps apt-transport-https iproute2
echo "[OK] Sistema Debian actualizado"

echo "[2/6] Instalando Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
apt-get install -y $DPKG_OPTS nodejs
echo "[OK] Node.js $(node --version)"

NODE_MAJOR=$(node --version | sed 's/v//' | cut -d'.' -f1)
[ "$NODE_MAJOR" -lt 18 ] && echo "[ERROR] Node < 18" && exit 1

echo "[3/6] Configurando variables de entorno..."
export npm_config_python=$(which python3)
export PYTHON=$(which python3)
grep -q "npm_config_python" /root/.bashrc 2>/dev/null || cat >> /root/.bashrc << 'PROFILE'
export npm_config_python=$(which python3)
export PYTHON=$(which python3)
export N8N_HOST=0.0.0.0
export N8N_PORT=5678
export N8N_SECURE_COOKIE=false
PROFILE
echo "[OK] Variables configuradas"

echo "[4/6] Instalando n8n (10-20 min)..."
npm install -g n8n --unsafe-perm 2>&1 | tail -3
N8N_VER=$(n8n --version 2>/dev/null || echo "error")
[ "$N8N_VER" = "error" ] && echo "[ERROR] n8n no instaló" && exit 1
echo "[OK] n8n $N8N_VER"

echo "[5/6] Instalando cloudflared..."
wget -q \
  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" \
  -O /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
echo "[OK] $(cloudflared --version 2>/dev/null | head -1)"

echo "[6/6] Verificación final..."
echo "  Node.js:     $(node --version)"
echo "  n8n:         $(n8n --version 2>/dev/null)"
echo "  cloudflared: $(cloudflared --version 2>/dev/null | head -1)"
echo "[COMPLETADO] Debian setup listo"
INNERSCRIPT
    chmod +x "$_N8N_SETUP_SCRIPT"
    proot-distro login "$DISTRO_NAME" -- bash /root/n8n_setup_inner.sh
    _N8N_RC=$?
    rm -f "$_N8N_SETUP_SCRIPT" 2>/dev/null
    [ $_N8N_RC -eq 0 ] || \
      error "El setup de Debian falló. Re-ejecuta el script para reintentar."
    mark_done "n8n_install" "$CHECKPOINT"
    log "n8n + cloudflared instalados"
  fi

  # ── PASO 5 — Scripts de control ───────────────────────────
  titulo "PASO 5 — Creando scripts de control"
  if check_done "scripts" "$CHECKPOINT"; then
    log "Scripts ya creados [checkpoint]"
  else
    mkdir -p "$N8N_SCRIPTS_PROOT"

    # start_servidor.sh
    cat > "$N8N_SCRIPTS_PROOT/start_servidor.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock 2>/dev/null &
LAST_URL="\$HOME/.last_cf_url"
SESSION="n8n-server"
WEBHOOK_URL_CFG=\$(grep "^N8N_WEBHOOK_URL=" "\$HOME/.env_n8n" 2>/dev/null | cut -d'=' -f2)

echo "[*] Iniciando n8n + cloudflared en sesión tmux..."
tmux kill-session -t "\$SESSION" 2>/dev/null || true
sleep 1

tmux new-session -d -s "\$SESSION" -n "n8n"
N8N_CMD="export HOME=/root"
N8N_CMD="\${N8N_CMD} && export NODE_FUNCTION_ALLOW_BUILTIN=child_process,fs,path,os"
N8N_CMD="\${N8N_CMD} && export NODE_FUNCTION_ALLOW_EXTERNAL=*"
N8N_CMD="\${N8N_CMD} && export N8N_HOST=0.0.0.0"
N8N_CMD="\${N8N_CMD} && export N8N_PORT=5678"
N8N_CMD="\${N8N_CMD} && export N8N_PROXY_HOPS=1"
N8N_CMD="\${N8N_CMD} && export N8N_SECURE_COOKIE=false"
N8N_CMD="\${N8N_CMD} && export N8N_RUNNERS_ENABLED=true"
N8N_CMD="\${N8N_CMD} && export N8N_RUNNERS_HEARTBEAT_INTERVAL=300"
[ -n "\$WEBHOOK_URL_CFG" ] && N8N_CMD="\${N8N_CMD} && export WEBHOOK_URL=\${WEBHOOK_URL_CFG}"
N8N_CMD="\${N8N_CMD} && n8n start"

DISTRO_NAME=\$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print \$NF}' | head -1)
[ -z "\$DISTRO_NAME" ] && DISTRO_NAME="debian"

tmux send-keys -t "\$SESSION:n8n" \
  "proot-distro login \"\$DISTRO_NAME\" -- bash -c '\${N8N_CMD}'" Enter

echo "[*] Esperando que n8n inicie (35 seg)..."
sleep 35

tmux new-window -t "\$SESSION" -n "tunnel"
if [ -f "\$HOME/.cf_token" ]; then
  CF_TOK=\$(cat "\$HOME/.cf_token")
  tmux send-keys -t "\$SESSION:tunnel" \
    "proot-distro login \"\$DISTRO_NAME\" -- bash -c 'cloudflared tunnel --no-autoupdate run --token \${CF_TOK} 2>&1 | tee /root/cf_url.log'" Enter
else
  tmux send-keys -t "\$SESSION:tunnel" \
    "proot-distro login \"\$DISTRO_NAME\" -- bash -c 'cloudflared tunnel --no-autoupdate --url http://localhost:5678 2>&1 | tee /root/cf_url.log'" Enter
fi

echo "[*] Obteniendo URL pública (40 seg)..."
sleep 40

if [ -n "\$WEBHOOK_URL_CFG" ]; then
  CF_URL="\$WEBHOOK_URL_CFG"
else
  CF_URL=\$(proot-distro login "\$DISTRO_NAME" -- bash -c \
    "grep -o 'https://[a-zA-Z0-9.-]*\\.trycloudflare\\.com' /root/cf_url.log 2>/dev/null | head -1" 2>/dev/null)
fi

IP=\$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print \$2}' | cut -d'/' -f1)
[ -n "\$CF_URL" ] && echo "\$CF_URL" > "\$HOME/.last_cf_url"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   n8n ACTIVO · proot Debian            ║"
echo "╠════════════════════════════════════════╣"
echo "║  Local:    http://localhost:5678       ║"
[ -n "\$IP" ]     && echo "║  WiFi PC:  http://\$IP:5678"
[ -n "\$CF_URL" ] && echo "║  Internet: \$CF_URL" || echo "║  Internet: usa n8n-url en ~20s"
[ -f "\$HOME/.cf_token" ] && echo "║  Modo:     URL FIJA ✓" || echo "║  Modo:     URL temporal"
echo "╠════════════════════════════════════════╣"
echo "║  n8n-log → logs en vivo               ║"
echo "║  Ctrl+B D → salir sin detener         ║"
echo "╚════════════════════════════════════════╝"
SCRIPT
    chmod +x "$N8N_SCRIPTS_PROOT/start_servidor.sh"
    log "start_servidor.sh creado"

    # stop_servidor.sh
    cat > "$N8N_SCRIPTS_PROOT/stop_servidor.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Deteniendo n8n y cloudflared..."
DISTRO_NAME=$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print $NF}' | head -1)
[ -z "$DISTRO_NAME" ] && DISTRO_NAME="debian"
proot-distro login "$DISTRO_NAME" -- bash -c \
  'pkill -f n8n 2>/dev/null; pkill -f cloudflared 2>/dev/null; rm -f /root/cf_url.log' 2>/dev/null || true
tmux kill-session -t "n8n-server" 2>/dev/null || true
rm -f "$HOME/.last_cf_url" 2>/dev/null
echo "[OK] Todo detenido."
SCRIPT
    chmod +x "$N8N_SCRIPTS_PROOT/stop_servidor.sh"
    log "stop_servidor.sh creado"

    # ver_url.sh
    cat > "$N8N_SCRIPTS_PROOT/ver_url.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
URL=""
[ -f "$HOME/.last_cf_url" ] && URL=$(cat "$HOME/.last_cf_url")
if [ -z "$URL" ]; then
  DISTRO_NAME=$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print $NF}' | head -1)
  [ -z "$DISTRO_NAME" ] && DISTRO_NAME="debian"
  URL=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    "grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' /root/cf_url.log 2>/dev/null | head -1" 2>/dev/null)
fi
[ -n "$URL" ] && echo "" && echo "  ▸ $URL" && echo "" || \
  echo "[!] URL no disponible — ejecuta n8n-start primero"
SCRIPT
    chmod +x "$N8N_SCRIPTS_PROOT/ver_url.sh"
    log "ver_url.sh creado"

    # n8n_status.sh
    cat > "$N8N_SCRIPTS_PROOT/n8n_status.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo ""
echo "╔══════════════════════════════════════╗"
echo "║   termux-ai-stack · n8n (proot)     ║"
echo "╠══════════════════════════════════════╣"
tmux has-session -t "n8n-server" 2>/dev/null && \
  echo "║  n8n:     ● ACTIVO                   ║" || \
  echo "║  n8n:     ○ DETENIDO                 ║"
URL=""
[ -f "$HOME/.last_cf_url" ] && URL=$(cat "$HOME/.last_cf_url")
[ -n "$URL" ] && echo "║  URL:  $URL" || \
  echo "║  URL:     no disponible              ║"
IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
[ -n "$IP" ] && echo "║  WiFi: http://$IP:5678"
echo "╚══════════════════════════════════════╝"
echo ""
SCRIPT
    chmod +x "$N8N_SCRIPTS_PROOT/n8n_status.sh"
    log "n8n_status.sh creado"

    # n8n_log.sh
    cat > "$N8N_SCRIPTS_PROOT/n8n_log.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
tmux has-session -t "n8n-server" 2>/dev/null && \
  tmux attach-session -t "n8n-server" || \
  echo "[!] n8n no está corriendo — ejecuta: n8n-start"
SCRIPT
    chmod +x "$N8N_SCRIPTS_PROOT/n8n_log.sh"
    log "n8n_log.sh creado"

    # n8n_update.sh
    cat > "$N8N_SCRIPTS_PROOT/n8n_update.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
REGISTRY="$HOME/.android_server_registry"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   n8n · Actualización (proot Debian)    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

DISTRO_NAME=$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print $NF}' | head -1)
[ -z "$DISTRO_NAME" ] && DISTRO_NAME="debian"

# Versión actual
VER_ANTES=$(proot-distro login "$DISTRO_NAME" -- bash -c \
  'export HOME=/root && n8n --version 2>/dev/null' 2>/dev/null | head -1)
echo "[INFO] Versión actual: ${VER_ANTES:-desconocida}"
echo ""

# Detener n8n si está corriendo
if tmux has-session -t "n8n-server" 2>/dev/null; then
  echo "[1/3] Deteniendo n8n..."
  tmux kill-session -t "n8n-server" 2>/dev/null || true
  sleep 2
else
  echo "[1/3] n8n no estaba corriendo — OK"
fi

# Actualizar
echo "[2/3] Actualizando n8n (puede tardar 5-15 min)..."
proot-distro login "$DISTRO_NAME" -- bash -c \
  'export HOME=/root
   export DEBIAN_FRONTEND=noninteractive
   npm update -g n8n --unsafe-perm 2>&1 | tail -5' || {
  echo "[ERROR] Falló la actualización"; exit 1
}

# Versión nueva
VER_NUEVA=$(proot-distro login "$DISTRO_NAME" -- bash -c \
  'export HOME=/root && n8n --version 2>/dev/null' 2>/dev/null | head -1)
echo "[3/3] Versión nueva: ${VER_NUEVA:-desconocida}"

# Actualizar registry
if [ -f "$REGISTRY" ] && [ -n "$VER_NUEVA" ]; then
  DATE_NOW=$(date +%Y-%m-%d)
  TMP="$REGISTRY.tmp"
  grep -v "^n8n\.version=\|^n8n\.install_date=" "$REGISTRY" > "$TMP" 2>/dev/null || true
  echo "n8n.version=$VER_NUEVA" >> "$TMP"
  echo "n8n.install_date=$DATE_NOW" >> "$TMP"
  mv "$TMP" "$REGISTRY"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  [OK] n8n actualizado                   ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Antes:  ${VER_ANTES:-?}"
echo "║  Ahora:  ${VER_NUEVA:-?}"
echo "╠══════════════════════════════════════════╣"
echo "║  Ejecuta: n8n-start para reiniciar      ║"
echo "╚══════════════════════════════════════════╝"
echo ""
SCRIPT
    chmod +x "$N8N_SCRIPTS_PROOT/n8n_update.sh"
    log "n8n_update.sh creado"

    # n8n_backup.sh
    cat > "$N8N_SCRIPTS_PROOT/n8n_backup.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
FECHA=\$(date +%Y%m%d_%H%M)
DESTINO="/sdcard/Download/n8n_proot_\$FECHA.tar.gz"
echo "[*] Backup de workflows n8n (proot)..."
DISTRO_NAME=\$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print \$NF}' | head -1)
[ -z "\$DISTRO_NAME" ] && DISTRO_NAME="debian"
proot-distro login "\${DISTRO_NAME}" -- bash -c \
  'tar -czf - -C /root/.n8n . 2>/dev/null' > "\$DESTINO"
SIZE=\$(du -h "\$DESTINO" 2>/dev/null | cut -f1)
echo "[OK] Backup: \$DESTINO (\$SIZE)"
SCRIPT
    chmod +x "$N8N_SCRIPTS_PROOT/n8n_backup.sh"
    log "n8n_backup.sh creado"

    # debian.sh
    cat > "$TERMUX_HOME/debian.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
DISTRO_NAME=\$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print \$NF}' | head -1)
[ -z "\$DISTRO_NAME" ] && DISTRO_NAME="debian"
proot-distro login "\$DISTRO_NAME"
SCRIPT
    chmod +x "$TERMUX_HOME/debian.sh"
    log "debian.sh creado"

    mark_done "scripts" "$CHECKPOINT"
    log "Todos los scripts de control creados"
  fi

  # ── PASO 6 — Aliases ──────────────────────────────────────
  titulo "PASO 6 — Configurando aliases"
  if check_done "aliases" "$CHECKPOINT"; then
    log "Aliases ya configurados [checkpoint]"
  else
    BASHRC="$TERMUX_HOME/.bashrc"
    grep -v "n8n-start\|n8n-stop\|n8n-url\|n8n-status\|n8n-log\|n8n-update\|n8n-backup\|alias debian\b" \
      "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
    cat >> "$BASHRC" << 'ALIASES'

# ════ n8n proot · aliases ════
alias n8n-start='bash ~/scripts/n8n/start_servidor.sh'
alias n8n-stop='bash ~/scripts/n8n/stop_servidor.sh'
alias n8n-url='bash ~/scripts/n8n/ver_url.sh'
alias n8n-status='bash ~/scripts/n8n/n8n_status.sh'
alias n8n-log='bash ~/scripts/n8n/n8n_log.sh'
alias n8n-update='bash ~/scripts/n8n/n8n_update.sh'
alias n8n-backup='bash ~/scripts/n8n/n8n_backup.sh'
alias debian='bash ~/debian.sh'
ALIASES
    mark_done "aliases" "$CHECKPOINT"
    log "Aliases configurados"
  fi

  # ── PASO 7 — Arranque automático ─────────────────────────
  titulo "PASO 7 — Arranque automático"
  if check_done "boot" "$CHECKPOINT"; then
    log "Arranque automático ya configurado [checkpoint]"
  else
    BOOT_DIR="$TERMUX_HOME/.termux/boot"
    mkdir -p "$BOOT_DIR"
    cat > "$BOOT_DIR/start_n8n.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/sbin:\$PATH
sleep 25
termux-wake-lock
bash ~/scripts/n8n/start_servidor.sh
SCRIPT
    chmod +x "$BOOT_DIR/start_n8n.sh"
    mark_done "boot" "$CHECKPOINT"
    warn "Para arranque automático: instala Termux:Boot desde F-Droid y ábrelo UNA VEZ"
  fi

  # ── PASO 8 — Registry ─────────────────────────────────────
  titulo "PASO 8 — Actualizando registry"
  N8N_VER_REG=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'n8n --version 2>/dev/null' 2>/dev/null | head -1)
  [ -z "$N8N_VER_REG" ] && N8N_VER_REG="unknown"
  update_registry "proot" "$N8N_VER_REG"

  # ── Resumen ───────────────────────────────────────────────
  titulo "INSTALACIÓN PROOT COMPLETADA"
  IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
  echo -e "${GREEN}${BOLD}"
  cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║      n8n (proot Debian) instalado ✓         ║
  ╚══════════════════════════════════════════════╝
RESUMEN
  echo -e "${NC}"
  echo "  n8n:      $N8N_VER_REG"
  echo "  Puerto:   5678"
  [ -n "$IP" ] && echo "  IP WiFi:  $IP"
  echo ""
  echo "  COMANDOS:"
  echo "  n8n-start    → inicia n8n + cloudflared"
  echo "  n8n-stop     → detiene todo"
  echo "  n8n-url      → muestra URL pública"
  echo "  n8n-status   → estado del sistema"
  echo "  n8n-log      → logs en vivo"
  echo "  n8n-update   → actualizar n8n"
  echo "  n8n-backup   → backup de workflows"
  echo "  debian       → consola Debian proot"
  echo ""
  echo -e "${YELLOW}  IMPORTANTE:${NC}"
  echo "  1. Cierra y reabre Termux para activar aliases"
  echo "  2. Luego escribe: n8n-start"
  echo "  3. Primera vez en :5678 → crea cuenta de administrador"
  echo ""
  rm -f "$CHECKPOINT"
}

# ============================================================
# ██████████████████████████████████████████████████████████
#  MODO 2 — udocker
# ██████████████████████████████████████████████████████████
# ============================================================
install_udocker() {
  local CHECKPOINT="$CHECKPOINT_UDOCKER"
  info "Modo: udocker"

  # Rutas — NUNCA /tmp/ en Android 15
  N8N_DATA="$TERMUX_HOME/n8n-udocker"
  N8N_DATA_ABS="/data/data/com.termux/files/home/n8n-udocker"

  # ── Verificar instalación previa (inspect: no depende del formato
  #    de columnas de `ps`, que lista el UUID antes que el nombre) ──
  if udocker inspect n8n &>/dev/null; then
    # Si N8N_INSTALL_MODE=2 viene del menú → reinstalar sin preguntar
    if [ "${N8N_INSTALL_MODE:-}" = "2" ]; then
      udocker rm n8n 2>/dev/null || true
      rm -f "$CHECKPOINT"
    else
      echo -e "${GREEN}  ✓ Contenedor n8n ya existe en udocker${NC}"
      echo -n "  ¿Recrear contenedor? (s/n): "
      read -r RECREAR < /dev/tty
      if [ "$RECREAR" = "s" ] || [ "$RECREAR" = "S" ]; then
        udocker rm n8n 2>/dev/null || true
        rm -f "$CHECKPOINT"
      else
        info "Nada que hacer."
        _show_udocker_commands
        exit 0
      fi
    fi
  fi

  # ── Checkpoints previos ───────────────────────────────────
  if [ -f "$CHECKPOINT" ] && [ -s "$CHECKPOINT" ]; then
    # Si viene del menú (N8N_INSTALL_MODE=2) → continuar desde checkpoint sin preguntar
    if [ "${N8N_INSTALL_MODE:-}" = "2" ]; then
      echo -e "${YELLOW}  Continuando desde checkpoint anterior...${NC}"
      while IFS= read -r line; do
        echo -e "  ${GREEN}✓${NC} $line [omitido]"
      done < "$CHECKPOINT"
      echo ""
    else
      echo -e "${YELLOW}  Instalación previa detectada — se omitirán:${NC}"
      while IFS= read -r line; do
        echo -e "  ${GREEN}✓${NC} $line"
      done < "$CHECKPOINT"
      echo ""
      echo -n "  ¿Continuar desde donde quedó? (s/n): "
      read -r CONT < /dev/tty
      if [ "$CONT" != "s" ] && [ "$CONT" != "S" ]; then
        echo -n "  ¿Reiniciar desde cero? (s/n): "
        read -r RESET < /dev/tty
        [ "$RESET" = "s" ] || [ "$RESET" = "S" ] && rm -f "$CHECKPOINT"
      fi
      echo ""
    fi
  fi

  # ── PASO 0 — Instalar udocker ─────────────────────────────
  titulo "PASO 0 — Instalando udocker"
  if check_done "udocker_install" "$CHECKPOINT"; then
    log "udocker ya instalado [checkpoint]"
  else
    # Variable crítica para Android — udocker necesita saber dónde está proot
    export UDOCKER_USE_PROOT_EXECUTABLE=$(which proot 2>/dev/null || echo "$TERMUX_PREFIX/bin/proot")
    info "UDOCKER_USE_PROOT_EXECUTABLE=${UDOCKER_USE_PROOT_EXECUTABLE}"

    if command -v udocker &>/dev/null; then
      log "udocker ya disponible: $(udocker version 2>/dev/null | head -1)"
    else
      info "Instalando udocker desde pkg..."
      pkg install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        udocker 2>/dev/null || error "No se pudo instalar udocker"
      log "udocker instalado"
    fi

    info "Inicializando udocker (primera vez puede tardar 1-2 min)..."
    _UDOCKER_INSTALL_OUT=$(udocker install 2>&1)
    _UDOCKER_INSTALL_RC=$?
    echo "$_UDOCKER_INSTALL_OUT" | grep -v "^$"
    if [ "$_UDOCKER_INSTALL_RC" -ne 0 ]; then
      warn "udocker install falló (código $_UDOCKER_INSTALL_RC) — se forzará modo P2 de todas formas"
    fi

    # P2 se fuerza siempre (no solo cuando "udocker install" falla): P1 (default)
    # no monta --volume de forma confiable en Android — confirmado con el usuario,
    # que solo logró persistencia real de datos forzando P2 manualmente.
    touch "$TERMUX_HOME/.udocker_force_p2"

    mark_done "udocker_install" "$CHECKPOINT"
    log "udocker inicializado"
  fi

  # ── PASO 1 — Crear directorio de datos ───────────────────
  titulo "PASO 1 — Directorio de datos"
  if check_done "datadir" "$CHECKPOINT"; then
    log "Directorio de datos ya creado [checkpoint]"
  else
    mkdir -p "$N8N_DATA"
    # Permisos correctos para n8n (uid 1000 dentro del contenedor)
    chmod 777 "$N8N_DATA"
    log "Directorio creado: $N8N_DATA"
    mark_done "datadir" "$CHECKPOINT"
  fi

  # ── PASO 1.5 — Instalar cloudflared nativo ───────────────
  titulo "PASO 1.5 — Instalando cloudflared (Termux nativo)"
  if check_done "cloudflared" "$CHECKPOINT"; then
    log "cloudflared ya instalado [checkpoint]"
  else
    if command -v cloudflared &>/dev/null; then
      log "cloudflared ya disponible: $(cloudflared --version 2>/dev/null | head -1)"
    else
      info "Instalando cloudflared en Termux (para tunnel con udocker)..."
      if pkg install -y cloudflared 2>/dev/null; then
        log "cloudflared instalado via pkg"
      else
        info "Descargando cloudflared ARM64 manualmente..."
        wget -q \
          "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" \
          -O "$TERMUX_PREFIX/bin/cloudflared" 2>/dev/null
        chmod +x "$TERMUX_PREFIX/bin/cloudflared"
        command -v cloudflared &>/dev/null \
          && log "cloudflared descargado" \
          || error "No se pudo instalar cloudflared"
      fi
    fi
    mark_done "cloudflared" "$CHECKPOINT"
  fi

  # ── PASO 2 — Descargar imagen n8n ────────────────────────
  titulo "PASO 2 — Descargando imagen n8nio/n8n"
  if check_done "image_pull" "$CHECKPOINT"; then
    log "Imagen ya descargada [checkpoint]"
  else
    info "Descargando imagen oficial n8nio/n8n (~800MB)..."
    info "Puede tardar 5-15 min según tu conexión..."
    udocker pull n8nio/n8n || error "Falló la descarga de la imagen n8n"
    mark_done "image_pull" "$CHECKPOINT"
    log "Imagen descargada"
  fi

  # ── PASO 3 — Crear contenedor ────────────────────────────
  titulo "PASO 3 — Creando contenedor n8n"
  if check_done "container_create" "$CHECKPOINT"; then
    log "Contenedor ya creado [checkpoint]"
  else
    # Eliminar contenedor previo si existe
    udocker rm n8n 2>/dev/null || true
    udocker create --name=n8n n8nio/n8n || \
      error "Falló la creación del contenedor n8n"

    # Forzar execmode P2 para compatibilidad Android
    if [ -f "$TERMUX_HOME/.udocker_force_p2" ]; then
      info "Configurando execmode=P2 en contenedor n8n..."
      udocker setup --execmode=P2 n8n 2>/dev/null && \
        log "Contenedor n8n configurado en modo P2 (compatible Android)" || \
        warn "No se pudo cambiar execmode — usando default"
    fi

    mark_done "container_create" "$CHECKPOINT"
    log "Contenedor n8n creado"
  fi

  # ── PASO 4 — Scripts de control ──────────────────────────
  titulo "PASO 4 — Creando scripts de control"
  if check_done "scripts" "$CHECKPOINT"; then
    log "Scripts ya creados [checkpoint]"
  else
    mkdir -p "$N8N_SCRIPTS_UDOCKER"

    # start_n8n_udocker.sh
    cat > "$N8N_SCRIPTS_UDOCKER/start.sh" << 'STARTSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  n8n udocker · start.sh
#  Inicia n8n en contenedor udocker + cloudflared nativo
# ============================================================
TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
N8N_DATA_ABS="${TERMUX_HOME}/n8n-udocker"
SESSION="n8n-udocker"
CF_LOG="$TERMUX_HOME/.cf_ud_url.log"

# Variable crítica Android — udocker necesita proot de Termux
export UDOCKER_USE_PROOT_EXECUTABLE="${TERMUX_PREFIX}/bin/proot"

echo "[*] Iniciando n8n (udocker) en sesión tmux..."
echo "    HOME:   $TERMUX_HOME"
echo "    Datos:  $N8N_DATA_ABS"
echo "    Puerto: 5678"
echo ""

# ── Asegurar datos ──────────────────────────────────────────
[ ! -d "$N8N_DATA_ABS" ] && mkdir -p "$N8N_DATA_ABS" && chmod 777 "$N8N_DATA_ABS"
[ ! -w "$N8N_DATA_ABS" ] && {
  echo "[ERROR] No se puede escribir en $N8N_DATA_ABS"
  echo "        Ejecuta: chmod 777 $N8N_DATA_ABS"
  exit 1
}

# ── Verificar udocker ───────────────────────────────────────
if ! command -v udocker &>/dev/null; then
  echo "[ERROR] udocker no instalado. Ejecuta el instalador primero."
  exit 1
fi

# ── Verificar contenedor (inspect: no depende del formato de columnas
#    de `ps`, que lista el UUID antes que el nombre) ──
if ! udocker inspect n8n &>/dev/null; then
  echo "[AVISO] Contenedor 'n8n' no existe — creando..."
  if udocker images 2>/dev/null | grep -q "n8nio/n8n"; then
    udocker create --name=n8n n8nio/n8n || {
      echo "[ERROR] No se pudo crear contenedor n8n"; exit 1
    }
  else
    echo "[ERROR] Imagen n8nio/n8n no encontrada. Reinstala n8n."
    exit 1
  fi
fi

# ── Asegurar execmode P2 (compatible Android) ───────────────
if [ -f "$TERMUX_HOME/.udocker_force_p2" ]; then
  udocker setup --execmode=P2 n8n 2>/dev/null || true
fi

# ── Matar sesión previa ─────────────────────────────────────
tmux kill-session -t "$SESSION" 2>/dev/null || true
sleep 1
tmux new-session -d -s "$SESSION" -n "n8n"

# ── Iniciar n8n en udocker ──────────────────────────────────
tmux send-keys -t "$SESSION:n8n" \
  "udocker run --publish=5678:5678 --volume=${N8N_DATA_ABS}:/home/node/.n8n --env=N8N_HOST=0.0.0.0 --env=N8N_PORT=5678 --env=N8N_SECURE_COOKIE=false --env=N8N_RUNNERS_ENABLED=true --env=NODE_FUNCTION_ALLOW_BUILTIN=child_process,fs,path,os --env=NODE_FUNCTION_ALLOW_EXTERNAL=* n8n" Enter

echo "[*] Esperando que n8n arranque..."
# ── Health check: esperar hasta 60s a que n8n responda ──────
HEALTH_OK=false
for i in $(seq 1 30); do
  sleep 2
  if curl -sf --max-time 2 http://localhost:5678/healthz >/dev/null 2>&1; then
    HEALTH_OK=true
    echo "[OK] n8n respondió en ${i} intentos (~$((i*2))s)"
    break
  fi
  printf "  [%2d/30] Esperando n8n...\r" "$i"
done

if [ "$HEALTH_OK" = false ]; then
  echo ""
  echo "[AVISO] n8n no respondió en 60s. Puede seguir iniciando."
  echo "        Revisa logs: tmux attach -t $SESSION"
fi

# ── Cloudflared tunnel (nativo Termux, no dentro de udocker) ─
echo "[*] Iniciando cloudflared nativo (Termux)..."
if ! command -v cloudflared &>/dev/null; then
  echo "[AVISO] cloudflared no instalado. Instálalo con: pkg install cloudflared"
  echo "        n8n solo accesible en localhost:5678"
else
  tmux new-window -t "$SESSION" -n "tunnel"
  if [ -f "$TERMUX_HOME/.cf_token" ] && [ -s "$TERMUX_HOME/.cf_token" ]; then
    CF_TOK=$(cat "$TERMUX_HOME/.cf_token")
    tmux send-keys -t "$SESSION:tunnel" \
      "cloudflared tunnel --no-autoupdate run --token ${CF_TOK} 2>&1 | tee ${CF_LOG}" Enter
    echo "    Modo: URL FIJA (token cloudflare)"
  else
    tmux send-keys -t "$SESSION:tunnel" \
      "cloudflared tunnel --no-autoupdate --url http://localhost:5678 2>&1 | tee ${CF_LOG}" Enter
    echo "    Modo: URL temporal"
  fi

  echo "[*] Obteniendo URL cloudflared (20 seg)..."
  sleep 20
fi

# ── Mostrar resultado ───────────────────────────────────────
IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
CF_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$CF_LOG" 2>/dev/null | head -1)
[ -n "$CF_URL" ] && echo "$CF_URL" > "$TERMUX_HOME/.last_cf_url"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   n8n ACTIVO · udocker                 ║"
echo "╠════════════════════════════════════════╣"
echo "║  Local:    http://localhost:5678       ║"
[ -n "$IP" ]     && echo "║  WiFi PC:  http://$IP:5678"
[ -n "$CF_URL" ] && echo "║  Internet: $CF_URL" || echo "║  Internet: (tunnel iniciando...)"
[ -f "$TERMUX_HOME/.cf_token" ] && echo "║  Modo:     URL FIJA ✓"
echo "╠════════════════════════════════════════╣"
echo "║  n8n-ud-log → logs en vivo            ║"
echo "║  Ctrl+B D  → salir sin detener        ║"
echo "╚════════════════════════════════════════╝"
STARTSCRIPT
    chmod +x "$N8N_SCRIPTS_UDOCKER/start.sh"
    log "start.sh creado"

    # stop.sh
    cat > "$N8N_SCRIPTS_UDOCKER/stop.sh" << 'STOPSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Deteniendo n8n (udocker) + cloudflared..."
# Detener cloudflared nativo
pkill -f "cloudflared tunnel" 2>/dev/null || true
# Detener sesión tmux
tmux kill-session -t "n8n-udocker" 2>/dev/null || true
tmux kill-session -t "n8n-cf-tunnel" 2>/dev/null || true
sleep 2
# Limpiar logs de tunnel
rm -f "$HOME/.cf_ud_url.log" 2>/dev/null
rm -f "$HOME/.last_cf_url" 2>/dev/null
echo "[OK] n8n udocker detenido."
STOPSCRIPT
    chmod +x "$N8N_SCRIPTS_UDOCKER/stop.sh"
    log "stop.sh creado"

    # status.sh
    cat > "$N8N_SCRIPTS_UDOCKER/status.sh" << 'STATUSSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
echo ""
echo "╔══════════════════════════════════════╗"
echo "║   termux-ai-stack · n8n (udocker)   ║"
echo "╠══════════════════════════════════════╣"
tmux has-session -t "n8n-udocker" 2>/dev/null \
  && echo "║  n8n:    ● ACTIVO                    ║" \
  || echo "║  n8n:    ○ DETENIDO                  ║"
echo "║  Puerto: 5678                        ║"
echo "║  Datos:  $TERMUX_HOME/n8n-udocker"
_CF_URL=$(cat "$TERMUX_HOME/.last_cf_url" 2>/dev/null)
[ -z "$_CF_URL" ] && _CF_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TERMUX_HOME/.cf_ud_url.log" 2>/dev/null | head -1)
[ -n "$_CF_URL" ] && echo "║  URL:    $_CF_URL"
[ -f "$TERMUX_HOME/.cf_token" ] && echo "║  Tunnel: URL FIJA (token ✓)          ║"
_IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
[ -n "$_IP" ] && echo "║  WiFi:   http://$_IP:5678"
echo "╚══════════════════════════════════════╝"
echo ""
STATUSSCRIPT
    chmod +x "$N8N_SCRIPTS_UDOCKER/status.sh"
    log "status.sh creado"

    # log.sh
    cat > "$N8N_SCRIPTS_UDOCKER/log.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
tmux has-session -t "n8n-udocker" 2>/dev/null && \
  tmux attach-session -t "n8n-udocker" || \
  echo "[!] n8n udocker no está corriendo — ejecuta: n8n-ud-start"
SCRIPT
    chmod +x "$N8N_SCRIPTS_UDOCKER/log.sh"
    log "log.sh creado"

    # update.sh — pull nueva imagen + recrear contenedor
    cat > "$N8N_SCRIPTS_UDOCKER/update.sh" << 'UPDATESCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
REGISTRY="$HOME/.android_server_registry"
TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   n8n · Actualización (udocker)         ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Versión actual desde registry
VER_ANTES=$(grep "^n8n\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
echo "[INFO] Versión actual en registry: ${VER_ANTES:-desconocida}"
echo ""

# Detener contenedor
echo "[1/4] Deteniendo n8n..."
tmux kill-session -t "n8n-udocker" 2>/dev/null || true
sleep 2

# Descargar nueva imagen
echo "[2/4] Descargando nueva imagen n8nio/n8n (puede tardar ~15 min)..."
udocker pull n8nio/n8n || { echo "[ERROR] Falló la descarga de imagen"; exit 1; }

# Recrear contenedor (los datos persisten en ~/n8n-udocker)
echo "[3/4] Recreando contenedor con nueva imagen..."
udocker rm n8n 2>/dev/null || true
udocker create --name=n8n n8nio/n8n || { echo "[ERROR] Falló la creación del contenedor"; exit 1; }

# Re-aplicar execmode P2 si estaba forzado
if [ -f "$TERMUX_HOME/.udocker_force_p2" ]; then
  echo "[INFO] Re-aplicando execmode=P2 (compatibilidad Android)..."
  udocker setup --execmode=P2 n8n 2>/dev/null || true
fi

# Obtener nueva versión
echo "[4/4] Verificando versión..."
VER_NUEVA=$(udocker run n8n n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$VER_NUEVA" ] && VER_NUEVA=$(udocker images 2>/dev/null | grep "n8nio/n8n" | awk '{print $2}' | head -1)
[ -z "$VER_NUEVA" ] && VER_NUEVA="latest-$(date +%Y%m%d)"

# Actualizar registry
if [ -f "$REGISTRY" ]; then
  DATE_NOW=$(date +%Y-%m-%d)
  TMP="$REGISTRY.tmp"
  grep -v "^n8n\.version=\|^n8n\.install_date=" "$REGISTRY" > "$TMP" 2>/dev/null || true
  echo "n8n.version=$VER_NUEVA" >> "$TMP"
  echo "n8n.install_date=$DATE_NOW" >> "$TMP"
  mv "$TMP" "$REGISTRY"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  [OK] n8n (udocker) actualizado         ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Antes:  ${VER_ANTES:-?}"
echo "║  Ahora:  ${VER_NUEVA:-?}"
echo "║  Datos:  ~/n8n-udocker (intactos)       ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Ejecuta: n8n-ud-start para reiniciar   ║"
echo "╚══════════════════════════════════════════╝"
echo ""
UPDATESCRIPT
    chmod +x "$N8N_SCRIPTS_UDOCKER/update.sh"
    log "update.sh creado"

    # backup.sh
    cat > "$N8N_SCRIPTS_UDOCKER/backup.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
N8N_DATA_ABS="/data/data/com.termux/files/home/n8n-udocker"
FECHA=\$(date +%Y%m%d_%H%M)
DESTINO="/sdcard/Download/n8n_udocker_\$FECHA.tar.gz"
echo "[*] Backup de datos n8n (udocker)..."
tar -czf "\$DESTINO" -C "\$N8N_DATA_ABS" . 2>/dev/null
SIZE=\$(du -h "\$DESTINO" 2>/dev/null | cut -f1)
echo "[OK] Backup: \$DESTINO (\$SIZE)"
SCRIPT
    chmod +x "$N8N_SCRIPTS_UDOCKER/backup.sh"
    log "backup.sh creado"

    mark_done "scripts" "$CHECKPOINT"
    log "Todos los scripts de control creados"
  fi

  # ── PASO 5 — Aliases ──────────────────────────────────────
  titulo "PASO 5 — Configurando aliases"
  if check_done "aliases" "$CHECKPOINT"; then
    log "Aliases ya configurados [checkpoint]"
  else
    BASHRC="$TERMUX_HOME/.bashrc"
    grep -v "n8n-ud-start\|n8n-ud-stop\|n8n-ud-status\|n8n-ud-log\|n8n-ud-update\|n8n-ud-backup" \
      "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
    cat >> "$BASHRC" << 'ALIASES'

# ════ n8n udocker · aliases ════
alias n8n-ud-start='bash ~/scripts/n8n-udocker/start.sh'
alias n8n-ud-stop='bash ~/scripts/n8n-udocker/stop.sh'
alias n8n-ud-status='bash ~/scripts/n8n-udocker/status.sh'
alias n8n-ud-log='bash ~/scripts/n8n-udocker/log.sh'
alias n8n-ud-update='bash ~/scripts/n8n-udocker/update.sh'
alias n8n-ud-backup='bash ~/scripts/n8n-udocker/backup.sh'
ALIASES
    mark_done "aliases" "$CHECKPOINT"
    log "Aliases configurados"
  fi

  # ── PASO 6 — Arranque automático ─────────────────────────
  titulo "PASO 6 — Arranque automático"
  if check_done "boot" "$CHECKPOINT"; then
    log "Arranque automático ya configurado [checkpoint]"
  else
    BOOT_DIR="$TERMUX_HOME/.termux/boot"
    mkdir -p "$BOOT_DIR"
    # Nombre distinto para no solapar con proot boot
    cat > "$BOOT_DIR/start_n8n_udocker.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/sbin:\$PATH
sleep 30
termux-wake-lock
bash ~/scripts/n8n-udocker/start.sh
SCRIPT
    chmod +x "$BOOT_DIR/start_n8n_udocker.sh"
    mark_done "boot" "$CHECKPOINT"
    warn "Para arranque automático: instala Termux:Boot desde F-Droid y ábrelo UNA VEZ"
  fi

  # ── PASO 7 — Registry ─────────────────────────────────────
  titulo "PASO 7 — Actualizando registry"
  N8N_IMG_VER=$(udocker images 2>/dev/null | grep "n8nio/n8n" | awk '{print $2}' | head -1)
  [ -z "$N8N_IMG_VER" ] && N8N_IMG_VER="latest"
  update_registry "udocker" "$N8N_IMG_VER"

  # ── Test inicial ──────────────────────────────────────────
  titulo "PASO 8 — Verificación inicial"
  info "Lanzando n8n para verificar que arranca correctamente..."
  bash "$N8N_SCRIPTS_UDOCKER/start.sh"

  # ── Resumen ───────────────────────────────────────────────
  titulo "INSTALACIÓN UDOCKER COMPLETADA"
  IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
  echo -e "${GREEN}${BOLD}"
  cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║      n8n (udocker) instalado ✓              ║
  ╚══════════════════════════════════════════════╝
RESUMEN
  echo -e "${NC}"
  echo "  Puerto:   5678"
  echo "  Datos:    $N8N_DATA"
  [ -n "$IP" ] && echo "  IP WiFi:  $IP"
  echo ""
  echo "  COMANDOS:"
  echo "  n8n-ud-start    → inicia n8n"
  echo "  n8n-ud-stop     → detiene n8n"
  echo "  n8n-ud-status   → estado del contenedor"
  echo "  n8n-ud-log      → logs en vivo"
  echo "  n8n-ud-update   → actualizar a nueva versión"
  echo "  n8n-ud-backup   → backup de workflows"
  echo ""
  echo -e "${YELLOW}  IMPORTANTE:${NC}"
  echo "  1. Cierra y reabre Termux para activar aliases"
  echo "  2. Abre http://localhost:5678 en el browser"
  echo "  3. Primera vez → crea cuenta de administrador"
  echo ""
  echo -e "${CYAN}  NOTA:${NC} cloudflared se ejecuta nativo en Termux (no en udocker)."
  echo "  Si no está instalado: pkg install cloudflared"
  echo "  El tunnel se inicia automáticamente con n8n-ud-start."
  echo ""
  rm -f "$CHECKPOINT"
}

# ── Función helper para mostrar comandos udocker ─────────────
_show_udocker_commands() {
  echo ""
  echo "  COMANDOS DISPONIBLES:"
  echo "  n8n-ud-start  / n8n-ud-stop / n8n-ud-status"
  echo "  n8n-ud-log    / n8n-ud-update / n8n-ud-backup"
  echo ""
}

# ════════════════════════════════════════════
#  MENÚ DE CONTROL UNIFICADO n8n
#  Post-instalación — detecta modo proot/udocker
#  Mismas opciones 1-9 para ambos modos
#  Llamado con: bash install_n8n.sh --menu
# ════════════════════════════════════════════
n8n_control_menu() {
  if [ "$(grep "^n8n\.installed=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)" != "true" ]; then
    clear; echo ""
    echo -e "  ${YELLOW}[AVISO]${NC} n8n no está instalado."
    echo ""
    echo -n "  ¿Instalar ahora? (s/n): "
    read -r _INST < /dev/tty
    if [ "$_INST" = "s" ] || [ "$_INST" = "S" ]; then
      exec bash "$0"
    fi
    return 0
  fi

  local _MODE _VER _SESSION
  _MODE=$(grep "^n8n\.mode=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  _VER=$(grep "^n8n\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
  [ -z "$_MODE" ] && _MODE="proot"
  [ -z "$_VER" ] && _VER="?"
  [ "$_MODE" = "udocker" ] && _SESSION="n8n-udocker" || _SESSION="n8n-server"

  while true; do
    clear; echo ""
    local _RUNNING=false _CF_TOKEN=false
    tmux has-session -t "$_SESSION" 2>/dev/null && _RUNNING=true
    [ -f "$HOME/.cf_token" ] && [ -s "$HOME/.cf_token" ] && _CF_TOKEN=true

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    if $_RUNNING; then
      printf "  ║  ⬡ N8N · %-8s ${GREEN}● activo${CYAN}${BOLD}        :5678  ║\n" "$_MODE"
    else
      printf "  ║  ⬡ N8N · %-8s ${YELLOW}○ detenido${CYAN}${BOLD}      :5678  ║\n" "$_MODE"
    fi
    printf "  ║  ${NC}v%-38s${CYAN}${BOLD}║\n" "$_VER"
    if $_CF_TOKEN; then
      echo -e "  ║  ${NC}Tunnel: URL fija ${GREEN}●${NC}${CYAN}${BOLD}                   ║"
    else
      echo -e "  ║  ${NC}Tunnel: URL temporal ${YELLOW}○${NC}${CYAN}${BOLD}                 ║"
    fi
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1]  Iniciar n8n + tunnel              ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2]  Detener n8n + tunnel              ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3]  Abrir localhost :5678             ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4]  Ver URL pública (cloudflare)      ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5]  Logs en vivo                      ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6]  Ver estado del sistema            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[7]  Actualizar n8n                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[8]  Backup workflows                  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[9]  Token CF + Dominio webhook        ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[u]  Reinstalar / cambiar modo         ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b]  Volver                             ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        if [ "$_MODE" = "udocker" ]; then
          if [ ! -f "$N8N_SCRIPTS_UDOCKER/start.sh" ]; then
            echo -e "  ${RED}[ERROR]${NC} Script no encontrado — reinstala n8n"
          elif ! bash "$N8N_SCRIPTS_UDOCKER/start.sh"; then
            echo -e "  ${RED}[ERROR]${NC} start.sh falló durante la ejecución — revisa el log arriba"
          fi
        else
          if [ ! -f "$N8N_SCRIPTS_PROOT/start_servidor.sh" ]; then
            echo -e "  ${RED}[ERROR]${NC} Script no encontrado — usa [9] Reparar scripts"
          elif ! bash "$N8N_SCRIPTS_PROOT/start_servidor.sh"; then
            echo -e "  ${RED}[ERROR]${NC} start_servidor.sh falló durante la ejecución — revisa el log arriba"
          fi
        fi
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        if [ "$_MODE" = "udocker" ]; then
          bash "$N8N_SCRIPTS_UDOCKER/stop.sh" 2>/dev/null || \
            tmux kill-session -t "n8n-udocker" 2>/dev/null
        else
          bash "$N8N_SCRIPTS_PROOT/stop_servidor.sh" 2>/dev/null || \
            tmux kill-session -t "n8n-server" 2>/dev/null
        fi
        echo -e "  ${GREEN}[OK]${NC} n8n detenido"
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        local _IP; _IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        echo -e "  ${BOLD}n8n — Acceso local (sin cloudflare):${NC}"; echo ""
        echo -e "  ${GREEN}Teléfono:${NC} http://localhost:5678"
        [ -n "$_IP" ] && echo -e "  ${GREEN}WiFi PC: ${NC} http://${_IP}:5678"
        echo ""
        termux-open-url "http://localhost:5678" 2>/dev/null || true
        echo -e "  ${DIM}Ctrl+C para copiar la URL${NC}"
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        local _CF_URL
        _CF_URL=$(cat "$HOME/.last_cf_url" 2>/dev/null)
        if [ -n "$_CF_URL" ]; then
          echo -e "  ${GREEN}URL pública:${NC} ${_CF_URL}"
          echo ""
          echo -e "  ${DIM}Ctrl+C para copiar${NC}"
        elif [ "$_MODE" = "udocker" ]; then
          _CF_URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' "$HOME/cf_url.log" 2>/dev/null | head -1)
          _CF_URL="${_CF_URL:-$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$HOME/.cf_ud_url.log" 2>/dev/null | head -1)}"
          if [ -n "$_CF_URL" ]; then
            echo -e "  ${GREEN}URL pública:${NC} ${_CF_URL}"
          else
            echo -e "  ${YELLOW}[AVISO]${NC} Tunnel no activo — inicia con [1] primero"
          fi
        else
          bash "$N8N_SCRIPTS_PROOT/ver_url.sh" 2>/dev/null || \
            echo -e "  ${YELLOW}[AVISO]${NC} URL no disponible — inicia con [1] primero"
        fi
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        echo -e "  ${CYAN}Logs n8n — Ctrl+B D para salir sin detener${NC}"; echo ""
        tmux has-session -t "$_SESSION" 2>/dev/null \
          && tmux attach-session -t "$_SESSION" \
          || echo -e "  ${YELLOW}[AVISO]${NC} n8n no está corriendo"
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        if [ "$_MODE" = "udocker" ]; then
          bash "$N8N_SCRIPTS_UDOCKER/status.sh" 2>/dev/null || {
            echo -e "  ${BOLD}Estado n8n (udocker):${NC}"; echo ""
            $_RUNNING \
              && echo -e "  ${GREEN}● Corriendo${NC} — tmux: n8n-udocker" \
              || echo -e "  ${YELLOW}○ Detenido${NC}"
            local _SIP; _SIP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
            echo -e "  Puerto: 5678"
            [ -n "$_SIP" ] && echo -e "  WiFi:   http://${_SIP}:5678"
          }
        else
          bash "$N8N_SCRIPTS_PROOT/n8n_status.sh" 2>/dev/null || {
            echo -e "  ${BOLD}Estado n8n (proot):${NC}"; echo ""
            $_RUNNING \
              && echo -e "  ${GREEN}● Corriendo${NC} — tmux: n8n-server" \
              || echo -e "  ${YELLOW}○ Detenido${NC}"
          }
        fi
        echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        if [ "$_MODE" = "udocker" ]; then
          bash "$N8N_SCRIPTS_UDOCKER/update.sh" 2>/dev/null || {
            echo -e "  ${CYAN}Actualizando n8n (udocker)...${NC}"; echo ""
            tmux kill-session -t "n8n-udocker" 2>/dev/null || true
            udocker pull n8nio/n8n && {
              udocker rm n8n 2>/dev/null || true
              udocker create --name=n8n n8nio/n8n
              echo -e "  ${GREEN}[OK]${NC} n8n actualizado — usa [1] para iniciar"
            }
          }
        else
          bash "$N8N_SCRIPTS_PROOT/n8n_update.sh" 2>/dev/null || {
            echo -e "  ${CYAN}Actualizando n8n (proot)...${NC}"; echo ""
            local _DN; _DN=$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print $NF}' | head -1)
            [ -z "$_DN" ] && _DN="debian"
            proot-distro login "$_DN" -- bash -c \
              'export HOME=/root && npm update -g n8n && echo "n8n: $(n8n --version)"'
          }
        fi
        echo ""; read -r _ < /dev/tty ;;
      8)
        clear; echo ""
        echo -e "  ${CYAN}Backup workflows y credenciales${NC}"; echo ""
        if [ "$_MODE" = "udocker" ]; then
          bash "$N8N_SCRIPTS_UDOCKER/backup.sh" 2>/dev/null || \
            echo -e "  ${YELLOW}[AVISO]${NC} Script backup no encontrado"
        else
          bash "$N8N_SCRIPTS_PROOT/n8n_backup.sh" 2>/dev/null || \
            echo -e "  ${YELLOW}[AVISO]${NC} Script backup no encontrado"
        fi
        echo ""; read -r _ < /dev/tty ;;
      9)
        while true; do
          clear; echo ""
          echo -e "  ${CYAN}${BOLD}╔══════════════════════════════════════════╗"
          echo    "  ║  Token CF + Dominio webhook            ║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"
          echo ""

          local _CF_CUR _DOM_CUR
          _CF_CUR=$(cat "$HOME/.cf_token" 2>/dev/null)
          _DOM_CUR=$(grep "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" 2>/dev/null | cut -d'=' -f2)

          [ -n "$_CF_CUR" ] \
            && echo -e "  Token CF:   ${GREEN}configurado ✓${NC}" \
            || echo -e "  Token CF:   ${YELLOW}no configurado (URL temporal)${NC}"

          [ -n "$_DOM_CUR" ] \
            && echo -e "  Dominio:    ${GREEN}${_DOM_CUR}${NC}" \
            || echo -e "  Dominio:    ${YELLOW}no configurado${NC}"

          echo ""
          echo -e "  [t]  Cambiar token cloudflared"
          echo -e "  [d]  Configurar dominio webhook"
          echo -e "  [b]  Volver"
          echo ""; echo -n "  Opción: "
          read -r _C9OPT < /dev/tty

          case "$_C9OPT" in
            t|T)
              echo ""
              echo -e "  ${DIM}Obtén token en: dash.cloudflare.com → Zero Trust → Tunnels${NC}"
              echo -n "  Nuevo token (ENTER = borrar): "
              read -r _NEW_CF < /dev/tty
              if [ -n "$_NEW_CF" ]; then
                echo "$_NEW_CF" > "$HOME/.cf_token"
                chmod 600 "$HOME/.cf_token"
                echo -e "  ${GREEN}[OK]${NC} Token guardado — URL fija activada"
              else
                rm -f "$HOME/.cf_token"
                echo -e "  ${YELLOW}[OK]${NC} Token eliminado — modo URL temporal"
              fi
              read -r _ < /dev/tty ;;
            d|D)
              echo ""
              echo -e "  ${DIM}Ej: https://n8n.tudominio.com${NC}"
              echo -n "  URL del dominio webhook (ENTER = cancelar): "
              read -r _NEW_DOM < /dev/tty
              if [ -n "$_NEW_DOM" ]; then
                grep -v "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" > "$HOME/.env_n8n.tmp" 2>/dev/null || \
                  touch "$HOME/.env_n8n.tmp"
                echo "N8N_WEBHOOK_URL=${_NEW_DOM}" >> "$HOME/.env_n8n.tmp"
                mv "$HOME/.env_n8n.tmp" "$HOME/.env_n8n"
                echo "$_NEW_DOM" > "$HOME/.last_cf_url"
                echo -e "  ${GREEN}[OK]${NC} Dominio guardado: ${_NEW_DOM}"
                echo -e "  ${DIM}Reinicia n8n para aplicar.${NC}"
              fi
              read -r _ < /dev/tty ;;
            b|B|"") break ;;
          esac
        done ;;
      u|U)
        clear; echo ""
        echo -e "  ${CYAN}Reinstalar / cambiar modo n8n${NC}"; echo ""
        echo -e "  Modo actual: ${GREEN}$_MODE${NC}"; echo""
        echo -e "  Esto ejecutará el instalador completo."
        echo -n "  ¿Continuar? (s/n): "
        read -r _RI < /dev/tty
        if [ "$_RI" = "s" ] || [ "$_RI" = "S" ]; then
          exec bash "$0"
        fi
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ── Dispatch ─────────────────────────────────────────────────
if [ "$1" = "--menu" ]; then
  n8n_control_menu
  exit $?
fi

case "$INSTALL_MODE" in
  1) install_proot   ;;
  2) install_udocker ;;
esac

# ── Menú de control post-instalación ─────────────────────────
echo ""
echo -n "  ¿Abrir menú de control n8n? (s/n): "
read -r _SM < /dev/tty
if [ "$_SM" = "s" ] || [ "$_SM" = "S" ]; then
  n8n_control_menu
fi

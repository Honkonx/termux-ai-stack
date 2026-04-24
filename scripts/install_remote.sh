#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_remote.sh
#  Módulo Remote completo: SSH + Dashboard + Cloudflared SSH
#
#  USO:
#    bash install_remote.sh
#
#  QUÉ INSTALA:
#    ✅ OpenSSH (puerto 8022) — configurado, no solo el binario
#    ✅ dashboard_server.py + scripts de control
#    ✅ python3 (si no está)
#    ✅ tmux (si no está)
#    ✅ cloudflared ARM64 nativo (tunnel SSH desde cualquier red)
#    ✅ Scripts: ssh_start.sh, ssh_stop.sh,
#               dashboard_start.sh, dashboard_stop.sh
#    ✅ Registry actualizado para SSH y Dashboard
#    ✅ Aliases en .bashrc
#
#  CLOUDFLARED: nativo en Termux (ARM64) — NO requiere proot
#  Binario oficial de Cloudflare para linux/arm64
#
#  ACCESO SSH:     ssh -p 8022 usuario@IP_WiFi
#  ACCESO DASHBOARD: http://IP_WiFi:8080
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 1.1.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

REPO_RAW_DASHBOARD="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/python/dashboard"
# URL oficial cloudflared ARM64 — sin proot, binario nativo
CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"

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

get_local_ip() {
  local ip
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | \
       grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep "inet " | \
       grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ip addr show 2>/dev/null | grep "inet " | \
       grep -v "127\." | awk '{print $2}' | cut -d'/' -f1 | head -1)
  echo "${ip:-<tu_IP_WiFi>}"
}

REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_remote_checkpoint"
SSHD_CONFIG="$TERMUX_PREFIX/etc/ssh/sshd_config"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

update_registry_ssh() {
  local version="$1"; local date_now; date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^ssh\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
ssh.installed=true
ssh.version=${version}
ssh.install_date=${date_now}
ssh.port=8022
ssh.location=termux_native
ssh.auth=password+pubkey
EOF
  mv "$tmp" "$REGISTRY"
}

update_registry_dashboard() {
  local version="$1"; local date_now; date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^dashboard\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
dashboard.installed=true
dashboard.version=${version}
dashboard.install_date=${date_now}
dashboard.port=8080
dashboard.location=termux_native
EOF
  mv "$tmp" "$REGISTRY"
}

# ════════════════════════════════════════════════════════════
# CABECERA
# ════════════════════════════════════════════════════════════
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · Remote Installer        ║
  ║   SSH + Dashboard + Cloudflared · v1.1.0   ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# Estado actual
SSH_CONFIGURED=false
DB_CONFIGURED=false
CF_INSTALLED=false

# SSH configurado = sshd_config con "Port 8022" (el nuestro) o registry
{ [ "$(grep -c 'Port 8022' "$SSHD_CONFIG" 2>/dev/null)" -gt 0 ] || \
  [ "$(grep '^ssh.installed' "$REGISTRY" 2>/dev/null | cut -d= -f2)" = "true" ]; } && \
  SSH_CONFIGURED=true

{ [ -f "$HOME/dashboard_server.py" ] || \
  [ "$(grep '^dashboard.installed' "$REGISTRY" 2>/dev/null | cut -d= -f2)" = "true" ]; } && \
  DB_CONFIGURED=true

command -v cloudflared &>/dev/null && CF_INSTALLED=true

if $SSH_CONFIGURED && $DB_CONFIGURED && $CF_INSTALLED; then
  echo -e "${GREEN}  ✓ Remote completamente instalado${NC}"
  echo -e "  SSH, Dashboard y Cloudflared están configurados"
  echo ""
  echo -n "  ¿Reinstalar/reconfigurar? (s/n): "
  read -r REINSTALL < /dev/tty
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && { info "Nada que hacer."; exit 0; }
  rm -f "$CHECKPOINT"
fi

echo ""
echo "  Este script instalará:"
echo "  ▸ OpenSSH configurado en puerto 8022"
echo "  ▸ Dashboard web Python en puerto 8080"
echo "  ▸ Cloudflared ARM64 nativo (tunnel SSH remoto)"
echo "  ▸ Scripts de control para los 3 servicios"
echo ""
echo -e "  ${CYAN}Cloudflared:${NC} binario nativo ARM64 — NO requiere proot"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRM < /dev/tty
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 1 — Termux (solo standalone)
# ============================================================
titulo "PASO 1 — Verificando Termux"

if [ -n "$ANDROID_SERVER_READY" ]; then
  log "Termux preparado por instalar.sh [skip]"
elif check_done "termux_update"; then
  log "Termux ya actualizado [checkpoint]"
else
  info "Modo standalone — actualizando Termux..."
  MIRRORS=(
    "https://packages.termux.dev/apt/termux-main"
    "https://mirror.accum.se/mirror/termux.dev/apt/termux-main"
  )
  OUT=$(pkg update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>&1)
  if echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
    for m in "${MIRRORS[@]}"; do
      echo "deb $m stable main" > "$TERMUX_PREFIX/etc/apt/sources.list"
      OUT=$(pkg update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>&1)
      echo "$OUT" | grep -q "unexpected size\|Mirror sync" || { log "Mirror OK"; break; }
    done
  fi
  log "Termux actualizado"
  mark_done "termux_update"
fi

# ============================================================
# PASO 2 — Dependencias
# ============================================================
titulo "PASO 2 — Instalando dependencias"

if check_done "remote_deps"; then
  log "Dependencias ya instaladas [checkpoint]"
else
  DEPS_TO_INSTALL=()
  command -v sshd    &>/dev/null || DEPS_TO_INSTALL+=("openssh")
  command -v python3 &>/dev/null || DEPS_TO_INSTALL+=("python")
  command -v tmux    &>/dev/null || DEPS_TO_INSTALL+=("tmux")

  if [ ${#DEPS_TO_INSTALL[@]} -gt 0 ]; then
    info "Instalando: ${DEPS_TO_INSTALL[*]}..."
    pkg install -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      "${DEPS_TO_INSTALL[@]}" || \
      warn "Algunos paquetes tuvieron advertencias"
  fi

  command -v sshd    &>/dev/null && log "OpenSSH ✓" || error "openssh no instaló"
  command -v python3 &>/dev/null && log "Python3 ✓ $(python3 --version 2>/dev/null)" || \
    warn "python3 no disponible"
  command -v tmux    &>/dev/null && log "tmux ✓" || warn "tmux no instaló"

  mark_done "remote_deps"
fi

# ============================================================
# PASO 3 — Configurar SSH
# ============================================================
titulo "PASO 3 — Configurando SSH"

if check_done "ssh_config"; then
  log "SSH ya configurado [checkpoint]"
else
  # Backup del config original si existe
  [ -f "$SSHD_CONFIG" ] && cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak" 2>/dev/null

  cat > "$SSHD_CONFIG" << 'SSHCONF'
# termux-ai-stack · sshd_config v1.1.0
# Puerto 8022 — sin root no se puede usar < 1024

Port 8022
ListenAddress 0.0.0.0

# Autenticación
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Seguridad
PermitRootLogin no
MaxAuthTries 6
MaxSessions 5

# Keepalive — evita que Android corte conexiones inactivas
ClientAliveInterval 60
ClientAliveCountMax 3

# Sin X11
X11Forwarding no

# SFTP — transferencia de archivos
Subsystem sftp /data/data/com.termux/files/usr/libexec/sftp-server
SSHCONF

  log "sshd_config configurado (Puerto 8022)"

  # Generar claves del servidor
  info "Generando claves del servidor SSH..."
  ssh-keygen -A 2>/dev/null || warn "ssh-keygen -A: puede ser normal si ya existen"
  ls "$TERMUX_PREFIX/etc/ssh/ssh_host_"*"_key" &>/dev/null && \
    log "Claves del servidor generadas" || \
    warn "Claves no encontradas — se generarán al primer inicio de sshd"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
  log "~/.ssh/authorized_keys listo"

  mark_done "ssh_config"
fi

# ============================================================
# PASO 4 — Instalar Dashboard
# ============================================================
titulo "PASO 4 — Instalando Dashboard web"

if check_done "dashboard_install"; then
  log "Dashboard ya instalado [checkpoint]"
else
  info "Descargando dashboard_server.py desde GitHub..."

  DB_OK=true
  for F in dashboard_server.py; do
    echo -n "  Descargando $F... "
    curl -fL --progress-bar "$REPO_RAW_DASHBOARD/$F" -o "$HOME/$F" 2>&1 | grep -v "^$" || \
      wget --progress=bar:force -O "$HOME/$F" "$REPO_RAW_DASHBOARD/$F" 2>&1
    if [ -f "$HOME/$F" ] && [ -s "$HOME/$F" ]; then
      echo -e "${GREEN}✓${NC}"
    else
      echo -e "${RED}✗${NC}"
      DB_OK=false
    fi
  done

  if ! $DB_OK; then
    warn "Descarga falló — el dashboard requiere dashboard_server.py del repo"
    warn "Puedes descargarlo luego con: [u] Actualizar en el menú"
  else
    log "dashboard_server.py descargado"
  fi

  # SIEMPRE crear dashboard_start.sh robusto (sin tmux, con nohup)
  # No depende del repo — funciona desde el primer arranque
  cat > "$HOME/dashboard_start.sh" << 'DBSTART'
#!/data/data/com.termux/files/usr/bin/bash
# dashboard_start.sh — robusto, sin tmux
DB_SCRIPT="$HOME/dashboard_server.py"
[ ! -f "$DB_SCRIPT" ] && DB_SCRIPT="/data/data/com.termux/files/home/dashboard_server.py"

_get_ip() {
  local ip
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  echo "${ip:-localhost}"
}

if [ ! -f "$DB_SCRIPT" ]; then
  echo "[ERROR] dashboard_server.py no encontrado"
  echo "  Instala desde menú: [6] Remote → [7] Iniciar Dashboard"
  exit 1
fi

if pgrep -f "dashboard_server.py" &>/dev/null; then
  echo "[INFO] Dashboard ya corriendo → http://$(_get_ip):8080"
  exit 0
fi

cd "$(dirname "$DB_SCRIPT")"
nohup python3 "$DB_SCRIPT" > "$HOME/.dashboard.log" 2>&1 &
DASH_PID=$!
sleep 2

if kill -0 "$DASH_PID" 2>/dev/null || pgrep -f "dashboard_server.py" &>/dev/null; then
  echo "[OK] Dashboard → http://$(_get_ip):8080"
  echo "     App Android: http://localhost:8080"
else
  echo "[ERROR] No se pudo iniciar"
  echo "  Log: cat ~/.dashboard.log"
  exit 1
fi
DBSTART
  chmod +x "$HOME/dashboard_start.sh"
  log "dashboard_start.sh creado (robusto, sin tmux)"

  # dashboard_stop.sh con espera real
  cat > "$HOME/dashboard_stop.sh" << 'DBSTOP'
#!/data/data/com.termux/files/usr/bin/bash
if pgrep -f "dashboard_server.py" &>/dev/null; then
  pkill -f "dashboard_server.py" 2>/dev/null
  sleep 1
  pgrep -f "dashboard_server.py" &>/dev/null && \
    pkill -9 -f "dashboard_server.py" 2>/dev/null && sleep 1
  pgrep -f "dashboard_server.py" &>/dev/null && \
    echo "[ERROR] No se pudo detener" || echo "[OK] Dashboard detenido"
else
  echo "[OK] Dashboard detenido"
fi
DBSTOP
  chmod +x "$HOME/dashboard_stop.sh"
  log "dashboard_stop.sh creado"

  mark_done "dashboard_install"
fi

# ============================================================
# PASO 5 — Scripts de control SSH
# ============================================================
titulo "PASO 5 — Scripts SSH"

if check_done "ssh_scripts"; then
  log "Scripts SSH ya creados [checkpoint]"
else
  cat > "$HOME/ssh_start.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
_get_ip() {
  local ip
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  echo "${ip:-<tu_IP_WiFi>}"
}
if pgrep -x sshd &>/dev/null; then
  echo "  SSH ya corriendo → ssh -p 8022 $(whoami)@$(_get_ip)"
  exit 0
fi
sshd 2>/dev/null
sleep 1
if pgrep -x sshd &>/dev/null; then
  echo "  ✓ SSH iniciado → ssh -p 8022 $(whoami)@$(_get_ip)"
else
  echo "  ✗ Error iniciando SSH — prueba: sshd -d"
  exit 1
fi
SCRIPT
  chmod +x "$HOME/ssh_start.sh"

  cat > "$HOME/ssh_stop.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
if pgrep -x sshd &>/dev/null; then
  pkill sshd 2>/dev/null; sleep 1
  pgrep -x sshd &>/dev/null && echo "  ✗ No se pudo detener" || echo "  ✓ SSH detenido"
else
  echo "  SSH no estaba corriendo"
fi
SCRIPT
  chmod +x "$HOME/ssh_stop.sh"

  log "ssh_start.sh y ssh_stop.sh creados"
  mark_done "ssh_scripts"
fi

# ============================================================
# PASO 6 — Cloudflared ARM64 nativo
# ============================================================
titulo "PASO 6 — Cloudflared (tunnel SSH remoto)"

if check_done "cloudflared_install"; then
  log "Cloudflared ya instalado [checkpoint]"
else
  echo "  Cloudflared permite conectarte via SSH desde CUALQUIER red"
  echo "  (no solo WiFi local). Binario nativo ARM64 — sin proot."
  echo ""
  echo -n "  ¿Instalar cloudflared? (s/n): "
  read -r INSTALL_CF < /dev/tty

  if [ "$INSTALL_CF" = "s" ] || [ "$INSTALL_CF" = "S" ]; then
    CF_DEST="$TERMUX_PREFIX/bin/cloudflared"

    info "Descargando cloudflared linux/arm64..."
    curl -fL --progress-bar "$CLOUDFLARED_URL" -o "$CF_DEST"

    if [ -f "$CF_DEST" ] && [ -s "$CF_DEST" ]; then
      chmod +x "$CF_DEST"
      # Verificar que es ejecutable en Termux/Bionic
      CF_VER=$(cloudflared --version 2>/dev/null | head -1)
      if [ -n "$CF_VER" ]; then
        log "Cloudflared instalado ✓ — $CF_VER"
        log "Ubicación: $CF_DEST"
        echo ""
        echo -e "  ${CYAN}Para usarlo:${NC}"
        echo "  1. Ve a cloudflare.com → Zero Trust → Access → Tunnels"
        echo "  2. Crea un tunnel tipo SSH"
        echo "  3. Copia el token y úsalo en el menú [6] → [t]"
      else
        warn "cloudflared descargado pero no ejecuta (puede ser incompatible con Bionic)"
        warn "Alternativa: usar SSH solo en red local (sin cloudflared)"
        rm -f "$CF_DEST"
      fi
    else
      warn "Descarga de cloudflared falló — puedes instalarlo luego"
      warn "URL: $CLOUDFLARED_URL"
    fi
  else
    info "Cloudflared omitido — puedes instalarlo luego desde el menú [6] → [c]"
  fi

  mark_done "cloudflared_install"
fi

# ============================================================
# PASO 7 — Aliases en .bashrc
# ============================================================
titulo "PASO 7 — Aliases"

if check_done "remote_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"
  grep -v "ssh-start\|ssh-stop\|ssh-status\|dashboard-start\|dashboard-stop\|# Remote · aliases" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << 'ALIASES'

# ════════════════════════════════
#  Remote (SSH + Dashboard) · aliases
# ════════════════════════════════
alias ssh-start='bash ~/ssh_start.sh'
alias ssh-stop='bash ~/ssh_stop.sh'
alias ssh-status='pgrep -x sshd &>/dev/null && echo "SSH: ● :8022" || echo "SSH: ○ detenido"'
alias dashboard-start='bash ~/dashboard_start.sh'
alias dashboard-stop='bash ~/dashboard_stop.sh'
alias dashboard-status='pgrep -f "dashboard_server.py" &>/dev/null && echo "Dashboard: ● :8080" || echo "Dashboard: ○ detenido"'
ALIASES

  log "Aliases agregados a ~/.bashrc"
  mark_done "remote_aliases"
fi

# ============================================================
# PASO 8 — Actualizar registry
# ============================================================
titulo "PASO 8 — Actualizando registry"

SSH_VER=$(ssh -V 2>&1 | grep -oE 'OpenSSH_[0-9]+\.[0-9p]+' | head -1)
[ -z "$SSH_VER" ] && SSH_VER="unknown"
DB_VER="1.1"
[ -f "$HOME/dashboard_server.py" ] && \
  DB_VER=$(grep -oE "v[0-9]+\.[0-9]+" "$HOME/dashboard_server.py" 2>/dev/null | head -1 | tr -d 'v')
[ -z "$DB_VER" ] && DB_VER="1.1"

update_registry_ssh "$SSH_VER"
update_registry_dashboard "$DB_VER"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

IP=$(get_local_ip)
USER_NAME=$(whoami)

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║   Remote (SSH + Dashboard) instalado ✓      ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo -e "  ${CYAN}SSH${NC} — OpenSSH configurado en puerto 8022"
echo -e "  Conectar: ${GREEN}ssh -p 8022 ${USER_NAME}@${IP}${NC}"
echo ""
echo -e "  ${CYAN}Dashboard${NC} — servidor web Python en puerto 8080"
echo -e "  URL WiFi: ${GREEN}http://${IP}:8080${NC}"
echo -e "  URL App:  ${GREEN}http://localhost:8080${NC}"
echo ""
command -v cloudflared &>/dev/null && \
  echo -e "  ${CYAN}Cloudflared${NC} ✓ — configura el token en menú [6] → [t]" || \
  echo -e "  ${YELLOW}Cloudflared${NC} — no instalado (opcional, para acceso remoto)"
echo ""
echo "  ALIASES:"
echo "  ssh-start / ssh-stop / ssh-status"
echo "  dashboard-start / dashboard-stop / dashboard-status"
echo ""
echo -e "  ${YELLOW}NOTAS:${NC}"
echo "  · Para SSH sin contraseña: menú [6] → [4] Agregar clave pública"
echo "  · Para acceso remoto sin WiFi: menú [6] → [t] Configurar token CF-SSH"
echo ""

echo -n "  ¿Iniciar SSH y Dashboard ahora? (s/n): "
read -r START_NOW < /dev/tty
if [ "$START_NOW" = "s" ] || [ "$START_NOW" = "S" ]; then
  echo ""
  info "Iniciando SSH..."
  bash "$HOME/ssh_start.sh"
  echo ""
  info "Iniciando Dashboard..."
  bash "$HOME/dashboard_start.sh"
fi

echo ""
rm -f "$CHECKPOINT"

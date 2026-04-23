#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_remote.sh
#  Instala SSH + Dashboard en Termux (módulo Remote unificado)
#
#  USO STANDALONE:
#    bash install_remote.sh
#
#  QUÉ HACE:
#    ✅ Instala OpenSSH (puerto 8022, contraseña + clave pública)
#    ✅ Configura sshd_config optimizado para Android
#    ✅ Genera claves del servidor SSH
#    ✅ Instala dashboard_server.py + scripts de control
#    ✅ Instala python3 si falta (requerido por dashboard)
#    ✅ Instala termux-api (requerido por app Android)
#    ✅ Crea scripts: ssh_start.sh, ssh_stop.sh,
#                    dashboard_start.sh, dashboard_stop.sh
#    ✅ Escribe estado al registry
#    ✅ Agrega aliases a .bashrc
#
#  ACCESO SSH:
#    ssh -p 8022 <usuario>@<IP_WiFi>
#
#  ACCESO DASHBOARD:
#    http://<IP_WiFi>:8080   (desde PC en la misma red)
#    http://localhost:8080   (desde la app Android)
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 1.0.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

REPO_RAW="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script"
REPO_RAW_DASHBOARD="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/dashboard"

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

# ── IP local ─────────────────────────────────────────────────
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

# ── Estado ────────────────────────────────────────────────────
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
  ║   SSH + Dashboard · v1.0.0 · sin root       ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Estado actual ─────────────────────────────────────────────
SSH_INSTALLED=false
DB_INSTALLED=false
command -v sshd &>/dev/null && SSH_INSTALLED=true
{ [ -f "$HOME/dashboard_server.py" ] || \
  [ -f "$HOME/dashboard/dashboard_server.py" ]; } && DB_INSTALLED=true

if $SSH_INSTALLED && $DB_INSTALLED; then
  SSH_VER=$(ssh -V 2>&1 | awk '{print $1}')
  echo -e "${GREEN}  ✓ SSH instalado${NC} (${SSH_VER})"
  echo -e "${GREEN}  ✓ Dashboard instalado${NC}"
  echo ""
  read -r -p "  ¿Reinstalar/reconfigurar? (s/n): " REINSTALL < /dev/tty
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
elif $SSH_INSTALLED; then
  echo -e "${GREEN}  ✓ SSH ya instalado${NC}"
  echo -e "${YELLOW}  ○ Dashboard no instalado${NC}"
  echo ""
  read -r -p "  ¿Instalar Dashboard + reconfigurar SSH? (s/n): " REINSTALL < /dev/tty
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && { info "Cancelado."; exit 0; }
  rm -f "$CHECKPOINT"
fi

echo ""
echo "  Este script instalará:"
echo "  ▸ OpenSSH server (sshd) — puerto 8022"
echo "  ▸ Dashboard web (Python) — puerto 8080"
echo "  ▸ python3 (si no está instalado)"
echo "  ▸ termux-api (requerido por la app Android)"
echo "  ▸ Scripts de control para ambos servicios"
echo ""
read -r -p "  ¿Continuar? (s/n): " CONFIRM < /dev/tty
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 1 — Actualizar Termux (solo si es standalone)
# ============================================================
titulo "PASO 1 — Verificando Termux"

if [ -n "$ANDROID_SERVER_READY" ]; then
  log "Termux ya preparado por instalar.sh [skip]"
elif check_done "termux_update"; then
  log "Termux ya actualizado [checkpoint]"
else
  info "Modo standalone — actualizando Termux..."
  MIRRORS=(
    "https://packages.termux.dev/apt/termux-main"
    "https://mirror.accum.se/mirror/termux.dev/apt/termux-main"
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
  )
  OUT=$(pkg update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>&1)
  if echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
    warn "Mirror roto — probando alternativas..."
    OK=0
    for m in "${MIRRORS[@]}"; do
      echo "deb $m stable main" > "$TERMUX_PREFIX/etc/apt/sources.list"
      OUT=$(pkg update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>&1)
      if ! echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
        log "Mirror OK: $m"; OK=1; break
      fi
    done
    [ "$OK" = "0" ] && error "Todos los mirrors fallaron."
  fi
  log "Termux actualizado"
  mark_done "termux_update"
fi

# ============================================================
# PASO 2 — Instalar dependencias (openssh + python3)
# ============================================================
titulo "PASO 2 — Instalando dependencias"

if check_done "remote_deps"; then
  log "Dependencias ya instaladas [checkpoint]"
else
  DEPS_TO_INSTALL=()
  command -v sshd    &>/dev/null || DEPS_TO_INSTALL+=("openssh")
  command -v python3 &>/dev/null || DEPS_TO_INSTALL+=("python")

  if [ ${#DEPS_TO_INSTALL[@]} -gt 0 ]; then
    info "Instalando: ${DEPS_TO_INSTALL[*]}..."
    pkg install -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      "${DEPS_TO_INSTALL[@]}" || \
      warn "Algunos paquetes tuvieron advertencias (puede ser normal)"
  fi

  # Verificar SSH
  command -v sshd &>/dev/null && \
    log "OpenSSH ✓ $(ssh -V 2>&1 | awk '{print $1}')" || \
    error "openssh no instaló correctamente"

  # Verificar Python
  command -v python3 &>/dev/null && \
    log "Python3 ✓ $(python3 --version 2>/dev/null)" || \
    warn "python3 no está disponible — dashboard puede no funcionar"

  # termux-api (para app Android — no es crítico si falla)
  info "Instalando termux-api..."
  pkg install termux-api -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>/dev/null && \
    log "termux-api ✓" || \
    warn "termux-api: no instaló (no crítico para SSH/Dashboard)"

  mark_done "remote_deps"
fi

# ============================================================
# PASO 3 — Configurar SSH
# ============================================================
titulo "PASO 3 — Configurando SSH"

if check_done "ssh_config"; then
  log "SSH ya configurado [checkpoint]"
else
  # Backup del config original
  [ -f "$SSHD_CONFIG" ] && cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak" 2>/dev/null

  cat > "$SSHD_CONFIG" << 'SSHCONF'
# termux-ai-stack · sshd_config
# Puerto 8022 — sin root no se puede usar puerto < 1024

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

  log "sshd_config configurado (puerto 8022)"

  # Generar claves del servidor
  info "Generando claves del servidor..."
  ssh-keygen -A 2>/dev/null || warn "ssh-keygen -A: advertencias (normal si ya existen)"

  ls "$TERMUX_PREFIX/etc/ssh/ssh_host_"*"_key" &>/dev/null && \
    log "Claves del servidor generadas" || \
    warn "Claves no encontradas — se generarán al primer inicio de sshd"

  # Crear ~/.ssh
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
  info "Descargando archivos del dashboard..."

  DB_OK=true

  # dashboard_server.py va directo en HOME (no en subdirectorio)
  # Así dashboard_start.sh puede arrancarlo con ruta simple
  for F in dashboard_server.py dashboard_start.sh dashboard_stop.sh; do
    echo -n "  Descargando $F... "
    curl -fsSL "$REPO_RAW_DASHBOARD/$F" -o "$HOME/$F" 2>/dev/null || \
      wget -q "$REPO_RAW_DASHBOARD/$F" -O "$HOME/$F" 2>/dev/null

    if [ -f "$HOME/$F" ] && [ -s "$HOME/$F" ]; then
      [[ "$F" == *.sh ]] && chmod +x "$HOME/$F"
      echo -e "${GREEN}✓${NC}"
    else
      echo -e "${RED}✗${NC}"
      DB_OK=false
    fi
  done

  # Si la descarga falló, crear scripts mínimos funcionales
  if ! $DB_OK || [ ! -f "$HOME/dashboard_server.py" ]; then
    warn "Descarga parcial — creando scripts de control mínimos..."

    # dashboard_start.sh mínimo — inicia el server si existe
    cat > "$HOME/dashboard_start.sh" << 'DBSTART'
#!/data/data/com.termux/files/usr/bin/bash
# dashboard_start.sh — arranca dashboard_server.py en background
DB_SCRIPT="$HOME/dashboard_server.py"
[ ! -f "$DB_SCRIPT" ] && {
  echo "[ERROR] dashboard_server.py no encontrado en $HOME"
  echo "  Instala desde el menú: [6] Remote → Instalar"
  exit 1
}
pgrep -f "dashboard_server.py" &>/dev/null && {
  IP=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  echo "[INFO] Dashboard ya corriendo en http://${IP:-localhost}:8080"
  exit 0
}
cd "$HOME"
nohup python3 dashboard_server.py > "$HOME/.dashboard.log" 2>&1 &
sleep 2
if pgrep -f "dashboard_server.py" &>/dev/null; then
  IP=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  echo "[OK] Dashboard iniciado — http://${IP:-localhost}:8080"
else
  echo "[ERROR] No se pudo iniciar el dashboard"
  echo "  Revisa el log: cat ~/.dashboard.log"
  exit 1
fi
DBSTART
    chmod +x "$HOME/dashboard_start.sh"

    cat > "$HOME/dashboard_stop.sh" << 'DBSTOP'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f "dashboard_server.py" 2>/dev/null && \
  echo "[OK] Dashboard detenido" || \
  echo "[INFO] Dashboard no estaba corriendo"
DBSTOP
    chmod +x "$HOME/dashboard_stop.sh"
    log "Scripts de control creados (mínimos)"
  else
    log "Dashboard descargado correctamente"
  fi

  # index.html (dashboard web) — no crítico
  curl -fsSL "$REPO_RAW_DASHBOARD/index.html" -o "$HOME/index.html" 2>/dev/null || true
  [ -f "$HOME/index.html" ] && [ -s "$HOME/index.html" ] && \
    log "index.html descargado" || \
    info "index.html no disponible (el servidor lo genera dinámicamente)"

  mark_done "dashboard_install"
fi

# ============================================================
# PASO 5 — Crear scripts de control SSH
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
  echo "  SSH ya corriendo en :8022"
  echo "  Conectar: ssh -p 8022 $(whoami)@$(_get_ip)"
  exit 0
fi
sshd 2>/dev/null
sleep 1
if pgrep -x sshd &>/dev/null; then
  echo "  ✓ SSH iniciado en :8022"
  echo "  Conectar: ssh -p 8022 $(whoami)@$(_get_ip)"
else
  echo "  ✗ Error iniciando SSH"
  exit 1
fi
SCRIPT
  chmod +x "$HOME/ssh_start.sh"

  cat > "$HOME/ssh_stop.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
if pgrep -x sshd &>/dev/null; then
  pkill sshd 2>/dev/null; sleep 1
  pgrep -x sshd &>/dev/null && echo "  ✗ No se pudo detener sshd" || echo "  ✓ SSH detenido"
else
  echo "  SSH no estaba corriendo"
fi
SCRIPT
  chmod +x "$HOME/ssh_stop.sh"

  log "ssh_start.sh creado"
  log "ssh_stop.sh creado"
  mark_done "ssh_scripts"
fi

# ============================================================
# PASO 6 — Aliases en .bashrc
# ============================================================
titulo "PASO 6 — Aliases"

if check_done "remote_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"
  # Limpiar aliases anteriores (SSH legacy + nuevos Remote)
  grep -v "ssh-start\|ssh-stop\|ssh-status\|ssh-info\|ssh-addkey\|dashboard-start\|dashboard-stop\|# SSH · aliases\|# Remote · aliases" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << 'ALIASES'

# ════════════════════════════════
#  Remote (SSH + Dashboard) · aliases
# ════════════════════════════════
alias ssh-start='bash ~/ssh_start.sh'
alias ssh-stop='bash ~/ssh_stop.sh'
alias ssh-status='pgrep -x sshd &>/dev/null && echo "SSH: ● corriendo (:8022)" || echo "SSH: ○ detenido"'
alias dashboard-start='bash ~/dashboard_start.sh'
alias dashboard-stop='bash ~/dashboard_stop.sh'
alias dashboard-status='pgrep -f "dashboard_server.py" &>/dev/null && echo "Dashboard: ● corriendo (:8080)" || echo "Dashboard: ○ detenido"'
ALIASES

  log "Aliases agregados a ~/.bashrc"
  mark_done "remote_aliases"
fi

# ============================================================
# PASO 7 — Actualizar registry
# ============================================================
titulo "PASO 7 — Actualizando registry"

SSH_VER=$(ssh -V 2>&1 | grep -oE 'OpenSSH_[0-9]+\.[0-9p]+' | head -1)
[ -z "$SSH_VER" ] && SSH_VER="$(ssh -V 2>&1 | awk '{print $1}')"
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

echo -e "  ${CYAN}SSH${NC}"
echo "  Versión: $(ssh -V 2>&1 | awk '{print $1}')"
echo "  Puerto:  8022"
echo -e "  Comando: ${GREEN}ssh -p 8022 ${USER_NAME}@${IP}${NC}"
echo ""
echo -e "  ${CYAN}Dashboard${NC}"
echo "  Puerto:  8080"
echo -e "  URL WiFi: ${GREEN}http://${IP}:8080${NC}"
echo -e "  URL App:  ${GREEN}http://localhost:8080${NC}"
echo ""
echo "  ALIASES:"
echo "  ssh-start         → inicia SSH"
echo "  ssh-stop          → detiene SSH"
echo "  ssh-status        → verifica SSH"
echo "  dashboard-start   → inicia Dashboard"
echo "  dashboard-stop    → detiene Dashboard"
echo ""
echo -e "  ${YELLOW}NOTAS:${NC}"
echo "  · Para SSH sin contraseña: agrega tu clave pública"
echo "    desde el menú → [6] Remote → [4] Agregar clave"
echo "  · VS Code Remote SSH: extensión Remote - SSH"
echo "    Host: ${USER_NAME}@${IP}:8022"
echo "  · Termux:API app (F-Droid) necesaria para app Android"
echo "    https://f-droid.org/packages/com.termux.api/"
echo ""

# Ofrecer arrancar ambos servicios
read -r -p "  ¿Iniciar SSH y Dashboard ahora? (s/n): " START_NOW < /dev/tty
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

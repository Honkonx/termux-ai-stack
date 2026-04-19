#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_ssh.sh
#  Instala y configura OpenSSH en Termux nativo (ARM64, sin root)
#
#  USO STANDALONE:
#    bash install_ssh.sh
#
#  QUÉ HACE:
#    ✅ Instala openssh vía pkg
#    ✅ Configura sshd_config (puerto 8022, contraseña habilitada)
#    ✅ Genera claves del servidor (ssh-keygen -A)
#    ✅ Crea ~/ssh_start.sh y ~/ssh_stop.sh
#    ✅ Escribe estado al registry ~/.android_server_registry
#    ✅ Agrega aliases a .bashrc
#    ✅ Muestra IP + comando de conexión exacto al finalizar
#
#  CONEXIÓN DESDE PC:
#    ssh -p 8022 <usuario>@<IP_del_telefono>
#    Misma red WiFi — sin configuración adicional
#
#  VERSIÓN: 1.0.2 | Abril 2026
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

# ── Detectar IP local (funciona con cualquier nombre de interfaz) ──
# Prefiere máscara 255.255.x.x (WiFi real) sobre /8 (VPN/tunnel)
get_local_ip() {
  local ip
  # Método 1: ifconfig — máscara 255.255.x.x = red local real
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | \
       grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  # Método 2: ifconfig — cualquier inet no-loopback
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep "inet " | \
       grep -v "127\." | awk '{print $2}' | head -1)
  # Método 3: ip addr — último recurso
  [ -z "$ip" ] && ip=$(ip addr show 2>/dev/null | grep "inet " | \
       grep -v "127\." | awk '{print $2}' | cut -d'/' -f1 | head -1)
  echo "${ip:-<tu_IP_WiFi>}"
}

# ── Archivos de estado ────────────────────────────────────────
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_ssh_checkpoint"
SSHD_CONFIG="$TERMUX_PREFIX/etc/ssh/sshd_config"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Función: actualizar registry ─────────────────────────────
update_registry() {
  local version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)

  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"

  local tmp="$REGISTRY.tmp"
  grep -v "^ssh\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"

  cat >> "$tmp" << EOF
ssh.installed=true
ssh.version=$version
ssh.install_date=$date_now
ssh.port=8022
ssh.location=termux_native
ssh.auth=password
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → $REGISTRY"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · SSH Installer           ║
  ║   Termux ARM64 · sin root · puerto 8022     ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado ───────────────────────────
if command -v sshd &>/dev/null; then
  CURRENT_VER=$(ssh -V 2>&1 | awk '{print $1}')
  echo -e "${GREEN}  ✓ OpenSSH ya está instalado${NC}"
  echo -e "  Versión: ${CYAN}${CURRENT_VER}${NC}"
  echo ""
  echo -n "  ¿Reinstalar/reconfigurar? (s/n): "
  read -r REINSTALL < /dev/tty
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
fi

echo ""
echo "  Este script instalará:"
echo "  ▸ OpenSSH server (sshd) en puerto 8022"
echo "  ▸ Autenticación por contraseña habilitada"
echo "  ▸ Scripts ssh_start.sh y ssh_stop.sh"
echo "  ▸ Aliases: ssh-start, ssh-stop, ssh-status, ssh-info"
echo ""
echo -e "  ${YELLOW}NOTA:${NC} Termux usa puerto 8022 (no 22)"
echo "  Conexión: ssh -p 8022 usuario@IP"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRM < /dev/tty
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 1 — Actualizar Termux (condicional)
# ============================================================
titulo "PASO 1 — Verificando Termux"

if [ -n "$ANDROID_SERVER_READY" ]; then
  log "Termux ya preparado por el maestro [skip]"
elif check_done "termux_update"; then
  log "Termux ya verificado [checkpoint]"
else
  info "Modo standalone — actualizando Termux..."

  MIRRORS=(
    "https://packages.termux.dev/apt/termux-main"
    "https://mirror.accum.se/mirror/termux.dev/apt/termux-main"
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
  )

  OUT=$(pkg update -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>&1)

  if echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
    warn "Mirror roto — probando alternativas..."
    OK=0
    for m in "${MIRRORS[@]}"; do
      echo "deb $m stable main" > "$TERMUX_PREFIX/etc/apt/sources.list"
      OUT=$(pkg update -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>&1)
      if ! echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
        log "Mirror OK: $m"; OK=1; break
      fi
    done
    [ "$OK" = "0" ] && error "Todos los mirrors fallaron. Verifica tu conexión."
  fi

  log "Termux actualizado"
  mark_done "termux_update"
fi

# ============================================================
# PASO 2 — Instalar OpenSSH
# ============================================================
titulo "PASO 2 — Instalando OpenSSH"

if check_done "ssh_install"; then
  log "OpenSSH ya instalado [checkpoint]"
else
  info "Instalando openssh vía pkg..."
  pkg install openssh -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    error "Error instalando openssh. Verifica conexión."

  command -v sshd &>/dev/null || \
    error "sshd no disponible después de instalar."

  log "OpenSSH instalado: $(ssh -V 2>&1 | awk '{print $1}')"
  mark_done "ssh_install"
fi

# ============================================================
# PASO 3 — Configurar sshd_config
# ============================================================
titulo "PASO 3 — Configurando sshd"

if check_done "ssh_config"; then
  log "sshd_config ya configurado [checkpoint]"
else
  info "Escribiendo configuración..."

  # Hacer backup de config original si existe
  if [ -f "$SSHD_CONFIG" ]; then
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak" 2>/dev/null
    log "Backup de config original → ${SSHD_CONFIG}.bak"
  fi

  cat > "$SSHD_CONFIG" << 'SSHCONF'
# termux-ai-stack · sshd_config
# Puerto 8022 — Termux no puede usar puertos < 1024 sin root

Port 8022
ListenAddress 0.0.0.0

# Autenticación
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Seguridad básica
PermitRootLogin no
MaxAuthTries 6
MaxSessions 5

# Keepalive — evita que Android corte conexiones inactivas
ClientAliveInterval 60
ClientAliveCountMax 3

# Sin X11 en Termux
X11Forwarding no

# Subsistema SFTP — permite transferir archivos con scp/sftp
Subsystem sftp /data/data/com.termux/files/usr/libexec/sftp-server
SSHCONF

  log "sshd_config configurado (puerto 8022)"
  mark_done "ssh_config"
fi

# ============================================================
# PASO 4 — Generar claves del servidor
# ============================================================
titulo "PASO 4 — Generando claves del servidor"

if check_done "ssh_keys"; then
  log "Claves del servidor ya generadas [checkpoint]"
else
  info "Generando claves del servidor..."
  ssh-keygen -A 2>/dev/null || \
    warn "ssh-keygen -A tuvo advertencias (puede ser normal si las claves ya existen)"

  # Verificar que al menos una clave existe
  if ls "$TERMUX_PREFIX/etc/ssh/ssh_host_"*"_key" &>/dev/null; then
    log "Claves del servidor generadas"
  else
    warn "No se encontraron claves — el primer inicio de sshd las generará automáticamente"
  fi

  # Crear ~/.ssh si no existe
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
  log "~/.ssh/authorized_keys listo para claves públicas"

  mark_done "ssh_keys"
fi

# ============================================================
# PASO 5 — Crear scripts de control
# ============================================================
titulo "PASO 5 — Scripts de control"

if check_done "ssh_scripts"; then
  log "Scripts ya creados [checkpoint]"
else
  # ── ssh_start.sh ─────────────────────────────────────────
  cat > "$HOME/ssh_start.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
TERMUX_PREFIX="/data/data/com.termux/files/usr"

# Detectar IP local (prefiere máscara /24 sobre VPN /8)
_get_ip() {
  local ip
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | \
       grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep "inet " | \
       grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ip addr show 2>/dev/null | grep "inet " | \
       grep -v "127\." | awk '{print $2}' | cut -d'/' -f1 | head -1)
  echo "${ip:-<tu_IP_WiFi>}"
}

# Verificar si ya está corriendo
if pgrep -x sshd &>/dev/null; then
  echo "  SSH ya está corriendo en puerto 8022"
  echo "  Conectar: ssh -p 8022 $(whoami)@$(_get_ip)"
  exit 0
fi

sshd 2>/dev/null

sleep 1

if pgrep -x sshd &>/dev/null; then
  echo "  ✓ SSH iniciado en puerto 8022"
  echo "  Conectar: ssh -p 8022 $(whoami)@$(_get_ip)"
else
  echo "  ✗ Error iniciando SSH — revisa: logcat | grep sshd"
  exit 1
fi
SCRIPT
  chmod +x "$HOME/ssh_start.sh"

  # ── ssh_stop.sh ──────────────────────────────────────────
  cat > "$HOME/ssh_stop.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
if pgrep -x sshd &>/dev/null; then
  pkill sshd 2>/dev/null
  sleep 1
  pgrep -x sshd &>/dev/null && \
    echo "  ✗ No se pudo detener sshd" || \
    echo "  ✓ SSH detenido"
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
titulo "PASO 6 — Configurando aliases"

if check_done "ssh_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"

  # Limpiar aliases anteriores
  if [ -f "$BASHRC" ]; then
    grep -v "ssh-start\|ssh-stop\|ssh-status\|ssh-info\|ssh-addkey\|# SSH · aliases" \
      "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
  fi

  cat >> "$BASHRC" << 'ALIASES'

# ════════════════════════════════
#  SSH · aliases
# ════════════════════════════════
alias ssh-start='bash ~/ssh_start.sh'
alias ssh-stop='bash ~/ssh_stop.sh'
alias ssh-status='pgrep -x sshd &>/dev/null && echo "SSH: ● corriendo (:8022)" || echo "SSH: ○ detenido"'
alias ssh-info='IP=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk "{print \$2}" | head -1); [ -z "$IP" ] && IP=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127\." | awk "{print \$2}" | head -1); echo "Conectar: ssh -p 8022 $(whoami)@${IP:-<tu_IP_WiFi>}"'
alias ssh-addkey='echo "Pega la clave pública (ssh-rsa ...): " && read KEY && echo "$KEY" >> ~/.ssh/authorized_keys && echo "Clave agregada."'
ALIASES

  log "Aliases agregados a ~/.bashrc"
  mark_done "ssh_aliases"
fi

# ============================================================
# PASO 7 — Actualizar registry
# ============================================================
titulo "PASO 7 — Actualizando registry"

SSH_VER=$(ssh -V 2>&1 | grep -oE 'OpenSSH_[0-9]+\.[0-9]+' | head -1)
[ -z "$SSH_VER" ] && SSH_VER="unknown"
update_registry "$SSH_VER"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

# Obtener IP usando método robusto
IP=$(get_local_ip)

USER_NAME=$(whoami)

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║       OpenSSH instalado con éxito ✓         ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  Versión: $(ssh -V 2>&1 | awk '{print $1}')"
echo "  Puerto:  8022"
echo "  Auth:    contraseña + clave pública"
echo ""
echo -e "  ${CYAN}${BOLD}COMANDO DE CONEXIÓN DESDE PC:${NC}"
echo ""
echo -e "  ${GREEN}  ssh -p 8022 ${USER_NAME}@${IP}${NC}"
echo ""
echo "  ─────────────────────────────────────────────"
echo "  PASOS PARA CONECTAR:"
echo "  1. PC y teléfono en la misma red WiFi"
echo "  2. Inicia SSH: ssh-start"
echo "  3. En la PC: ssh -p 8022 ${USER_NAME}@${IP}"
echo "  4. Ingresa la contraseña de Termux cuando pida"
echo ""
echo -e "  ${YELLOW}NOTA — contraseña de Termux:${NC}"
echo "  Si no tienes contraseña configurada, establécela con:"
echo "  passwd"
echo ""
echo "  ALIASES DISPONIBLES (tras reabrir Termux):"
echo "  ssh-start   → inicia el servidor"
echo "  ssh-stop    → detiene el servidor"
echo "  ssh-status  → verifica si está corriendo"
echo "  ssh-info    → muestra IP + comando exacto"
echo "  ssh-addkey  → agrega clave pública desde PC"
echo ""
echo -e "  ${CYAN}PARA VS CODE REMOTE SSH:${NC}"
echo "  Instala extensión: Remote - SSH"
echo "  Agrega host: ssh -p 8022 ${USER_NAME}@${IP}"
echo ""
echo -e "  ${CYAN}→ Inicia ahora con: ssh-start${NC}"
echo -e "  ${CYAN}   (o presiona [6] en el menú)${NC}"
echo ""

# ── Ofrecer iniciar SSH ahora mismo ──────────────────────────
echo -n "  ¿Iniciar SSH ahora? (s/n): "
read -r START_NOW < /dev/tty
if [ "$START_NOW" = "s" ] || [ "$START_NOW" = "S" ]; then
  echo ""
  bash "$HOME/ssh_start.sh"
fi

echo ""

# Limpiar checkpoint
rm -f "$CHECKPOINT"

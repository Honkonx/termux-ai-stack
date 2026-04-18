#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  android-server · install_n8n.sh
#  Instala n8n + cloudflared en Termux (proot Debian, sin root)
#
#  USO STANDALONE:
#    bash install_n8n.sh
#
#  USO VÍA MAESTRO (cuando repo sea público):
#    bash <(curl -fsSL https://raw.githubusercontent.com/TU_USUARIO/android-server/main/modules/install_n8n.sh)
#
#  QUÉ HACE:
#    ✅ Actualiza Termux (solo si no lo hizo el maestro)
#    ✅ Instala proot-distro + Debian Bookworm ARM64
#    ✅ Instala Node.js 20 LTS + n8n + cloudflared (dentro del proot)
#    ✅ Crea todos los scripts de control (start/stop/url/status/backup)
#    ✅ Configura aliases en .bashrc
#    ✅ Configura arranque automático (Termux:Boot)
#    ✅ Escribe estado al registry ~/.android_server_registry
#
#  RESPONSABILIDAD DEL MAESTRO (instalar.sh):
#    ⏭  Tema visual (GitHub Dark + JetBrains Mono)
#    ⏭  termux.properties + extra-keys
#    ⏭  pkg update base → exporta ANDROID_SERVER_READY=1
#
#  NO INSTALA:
#    ❌ EAS CLI / Expo → usar install_expo.sh
#    ❌ Claude Code    → usar install_claude.sh
#    ❌ Ollama         → usar install_ollama.sh
#
#  VERSIÓN: 2.1.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"
export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib"
export DEBIAN_FRONTEND=noninteractive

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
CHECKPOINT="$HOME/.install_n8n_checkpoint"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Función: actualizar registry ─────────────────────────────
update_registry() {
  local version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)

  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"

  local tmp="$REGISTRY.tmp"
  grep -v "^n8n\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"

  cat >> "$tmp" << EOF
n8n.installed=true
n8n.version=$version
n8n.install_date=$date_now
n8n.commands=n8n-start,n8n-stop,n8n-url,n8n-status,n8n-log,n8n-update,n8n-backup
n8n.port=5678
n8n.location=proot_debian
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → $REGISTRY"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   android-server · n8n Installer            ║
  ║   proot Debian · cloudflared · ARM64        ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado ───────────────────────────
N8N_INSTALLED=false
if proot-distro list 2>/dev/null | grep -q "debian.*installed"; then
  if proot-distro login debian -- bash -c 'command -v n8n' &>/dev/null 2>&1; then
    N8N_INSTALLED=true
  fi
fi

if [ "$N8N_INSTALLED" = true ]; then
  N8N_VER=$(proot-distro login debian -- bash -c 'n8n --version 2>/dev/null' 2>/dev/null | head -1)
  echo -e "${GREEN}  ✓ n8n ya está instalado${NC}"
  echo -e "  Versión actual: ${CYAN}${N8N_VER}${NC}"
  echo ""
  echo -n "  ¿Reinstalar/actualizar? (s/n): "
  read -r REINSTALL
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
fi

# ── Mostrar checkpoints previos si existen ───────────────────
if [ -f "$CHECKPOINT" ] && [ -s "$CHECKPOINT" ]; then
  echo -e "${YELLOW}  Instalación previa detectada — se omitirán:${NC}"
  while IFS= read -r line; do
    echo -e "  ${GREEN}✓${NC} $line"
  done < "$CHECKPOINT"
  echo ""
  echo -n "  ¿Continuar desde donde quedó? (s/n): "
  read -r CONT
  [ "$CONT" != "s" ] && [ "$CONT" != "S" ] && {
    echo -n "  ¿Reiniciar desde cero? (s/n): "
    read -r RESET
    [ "$RESET" = "s" ] || [ "$RESET" = "S" ] && rm -f "$CHECKPOINT"
  }
  echo ""
fi

echo "  Este script instala:"
echo "  ▸ proot Debian Bookworm ARM64"
echo "  ▸ Node.js 20 LTS + n8n + cloudflared (dentro del proot)"
echo "  ▸ Scripts de control y aliases"
echo ""
[ -z "$ANDROID_SERVER_READY" ] && \
  echo "  Tema y termux.properties → ejecuta instalar.sh para eso"
echo "  EAS CLI, Claude Code, Ollama → cada uno tiene su propio script"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRMAR
[ "$CONFIRMAR" != "s" ] && [ "$CONFIRMAR" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 0 — Permiso de almacenamiento
# ============================================================
titulo "PASO 0 — Permiso de almacenamiento"

if check_done "storage"; then
  log "Permiso de almacenamiento ya configurado [checkpoint]"
else
  if [ -d "/sdcard/Download" ]; then
    log "Acceso a /sdcard ya disponible"
    mark_done "storage"
  else
    info "Solicitando permiso de almacenamiento..."
    info "→ Acepta el diálogo que aparecerá en pantalla"
    termux-setup-storage
    sleep 4
    if [ -d "/sdcard/Download" ]; then
      log "Acceso a /sdcard confirmado"
      mark_done "storage"
    else
      warn "Acepta el permiso y re-ejecuta el script"
      exit 1
    fi
  fi
fi

# ============================================================
# PASO 1 — Actualizar Termux (condicional)
# ============================================================
titulo "PASO 1 — Verificando Termux"

if [ -n "$ANDROID_SERVER_READY" ]; then
  log "Termux ya preparado por el maestro [skip]"
elif check_done "termux_update"; then
  log "Termux ya actualizado [checkpoint]"
else
  info "Modo standalone — actualizando Termux..."

  MIRRORS=(
    "https://packages.termux.dev/apt/termux-main"
    "https://mirror.accum.se/mirror/termux.dev/apt/termux-main"
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
  )

  try_update() {
    pkg update -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      2>&1
  }

  set_mirror() {
    echo "deb $1 stable main" > "$TERMUX_PREFIX/etc/apt/sources.list"
    info "Mirror: $1"
  }

  OUT=$(try_update)
  if echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
    warn "Mirror roto — probando alternativas..."
    OK=0
    for m in "${MIRRORS[@]}"; do
      set_mirror "$m"
      OUT=$(try_update)
      if ! echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
        log "Mirror OK: $m"; OK=1; break
      fi
    done
    [ "$OK" = "0" ] && error "Todos los mirrors fallaron. Verifica tu conexión."
  fi

  pkg upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    2>/dev/null || warn "pkg upgrade tuvo advertencias (no fatal)"

  pkg install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    curl wget tar xz-utils tmux \
    proot proot-distro busybox iproute2 \
    git unzip \
    2>/dev/null || warn "Algunos paquetes tuvieron advertencias"

  for p in curl wget tmux proot-distro git; do
    command -v "$p" &>/dev/null && log "$p ✓" || warn "$p no instaló — puede causar problemas"
  done

  mark_done "termux_update"
  log "Termux actualizado"
fi

# ============================================================
# PASO 2 — Token cloudflared
# ============================================================
titulo "PASO 2 — Configuración cloudflared"

if check_done "cf_token"; then
  log "Cloudflared ya configurado [checkpoint]"
  [ -f "$HOME/.cf_token" ] && info "Modo: URL FIJA (token guardado)" || \
    info "Modo: URL temporal (sin token)"
else
  echo ""
  echo "  TÚNEL CLOUDFLARED:"
  echo ""
  echo "  A) Sin cuenta → URL cambia en cada reinicio (ENTER)"
  echo "  B) Con cuenta Cloudflare → URL fija permanente (gratis)"
  echo "     cloudflare.com → Zero Trust → Networks → Tunnels → Create tunnel"
  echo ""
  read -r -p "  Token cloudflared (ENTER para URL temporal): " CF_TOKEN
  echo ""

  if [ -n "$CF_TOKEN" ]; then
    echo "$CF_TOKEN" > "$HOME/.cf_token"
    log "Token guardado — URL fija permanente"
  else
    rm -f "$HOME/.cf_token"
    info "Sin token — URL temporal (cambia en cada reinicio)"
  fi

  mark_done "cf_token"
fi

# ============================================================
# PASO 3 — Instalar Debian Bookworm (proot)
# ============================================================
titulo "PASO 3 — Instalando Debian Bookworm"

if check_done "debian_install"; then
  log "Debian ya instalado [checkpoint]"
else
  if proot-distro list 2>/dev/null | grep -q "debian.*installed"; then
    log "Debian ya presente en proot-distro"
  else
    info "Descargando Debian Bookworm ARM64 (~100MB)..."
    proot-distro install debian || error "Falló instalación de Debian"
    log "Debian Bookworm instalado"
  fi
  mark_done "debian_install"
fi

# ============================================================
# PASO 4 — Instalar n8n + cloudflared dentro del proot
# ============================================================
titulo "PASO 4 — Instalando n8n + cloudflared en Debian"

if check_done "n8n_install"; then
  log "n8n ya instalado [checkpoint]"
else
  info "Instalando software en Debian (15-25 min)..."
  info "No cierres Termux durante este paso..."

  proot-distro login debian -- bash << 'INNER'
set -e
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

echo "[1/6] Actualizando sistema Debian..."
apt-get update -qq
apt-get upgrade -y -qq $DPKG_OPTS 2>/dev/null
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

echo "[3/6] Configurando Python/node-gyp..."
export npm_config_python=$(which python3)
export PYTHON=$(which python3)
cat >> /root/.bashrc << 'PROFILE'
export npm_config_python=$(which python3)
export PYTHON=$(which python3)
export N8N_HOST=0.0.0.0
export N8N_PORT=5678
export N8N_PROTOCOL=http
PROFILE
echo "[OK] Variables configuradas"

echo "[4/6] Instalando n8n (10-20 min)..."
npm install -g n8n --unsafe-perm 2>&1 | tail -3
N8N_VER=$(n8n --version 2>/dev/null || echo "error")
[ "$N8N_VER" = "error" ] && echo "[ERROR] n8n no instaló" && exit 1
echo "[OK] n8n $N8N_VER"

echo "[5/6] Instalando cloudflared..."
wget -q --show-progress \
  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" \
  -O /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
echo "[OK] $(cloudflared --version 2>/dev/null | head -1)"

echo "[6/6] Verificación final..."
echo "  Node.js:     $(node --version)"
echo "  n8n:         $(n8n --version 2>/dev/null)"
echo "  cloudflared: $(cloudflared --version 2>/dev/null | head -1)"
echo "[COMPLETADO] Debian setup listo"
INNER

  [ $? -eq 0 ] || error "El setup de Debian falló. Re-ejecuta el script para reintentar."
  mark_done "n8n_install"
  log "n8n + cloudflared instalados"
fi

# ============================================================
# PASO 5 — Crear scripts de control
# ============================================================
titulo "PASO 5 — Creando scripts de control"

if check_done "scripts"; then
  log "Scripts ya creados [checkpoint]"
else

# --- start_servidor.sh ---
cat > "$HOME/start_servidor.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="\$TERMUX_PREFIX/bin:\$TERMUX_PREFIX/sbin:\$PATH"
SESSION="n8n-server"

tmux kill-session -t "\$SESSION" 2>/dev/null || true
sleep 1

echo "[*] Iniciando n8n..."
tmux new-session -d -s "\$SESSION" -n "n8n"
tmux send-keys -t "\$SESSION:n8n" \
  "proot-distro login debian -- bash -c 'export HOME=/root && export N8N_HOST=0.0.0.0 && export N8N_PORT=5678 && n8n start'" Enter

echo "[*] Esperando que n8n inicie (35 seg)..."
sleep 35

echo "[*] Iniciando cloudflared tunnel..."
tmux new-window -t "\$SESSION" -n "tunnel"

if [ -f "\$HOME/.cf_token" ]; then
  CF_TOK=\$(cat "\$HOME/.cf_token")
  tmux send-keys -t "\$SESSION:tunnel" \
    "proot-distro login debian -- bash -c 'cloudflared tunnel run --token \$CF_TOK 2>&1 | tee /root/cf_url.log'" Enter
else
  tmux send-keys -t "\$SESSION:tunnel" \
    "proot-distro login debian -- bash -c 'cloudflared tunnel --url http://localhost:5678 2>&1 | tee /root/cf_url.log'" Enter
fi

echo "[*] Obteniendo URL pública (20 seg)..."
sleep 20

CF_URL=\$(proot-distro login debian -- bash -c \
  "grep -o 'https://[a-zA-Z0-9.-]*\\.trycloudflare\\.com' /root/cf_url.log 2>/dev/null | head -1" 2>/dev/null)
IP=\$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print \$2}' | cut -d'/' -f1)
[ -z "\$IP" ] && IP=\$(ip route get 1 2>/dev/null | awk '{print \$7; exit}')
[ -n "\$CF_URL" ] && echo "\$CF_URL" > "\$HOME/.last_cf_url"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   n8n ACTIVO · proot Debian            ║"
echo "╠════════════════════════════════════════╣"
echo "║  Teléfono: http://localhost:5678       ║"
[ -n "\$IP" ]     && echo "║  WiFi PC:  http://\$IP:5678"
[ -n "\$CF_URL" ] && echo "║  Internet: \$CF_URL" || echo "║  Internet: n8n-url para ver la URL"
[ -f "\$HOME/.cf_token" ] && echo "║  Modo: URL FIJA ✓" || echo "║  Modo: URL temporal"
echo "╠════════════════════════════════════════╣"
echo "║  n8n-log → logs en vivo               ║"
echo "║  Ctrl+B D → salir sin detener         ║"
echo "╚════════════════════════════════════════╝"
SCRIPT
chmod +x "$HOME/start_servidor.sh"
log "start_servidor.sh creado"

# --- stop_servidor.sh ---
cat > "$HOME/stop_servidor.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Deteniendo n8n y cloudflared..."
proot-distro login debian -- bash -c \
  'pkill -f n8n 2>/dev/null; pkill -f cloudflared 2>/dev/null; rm -f /root/cf_url.log' 2>/dev/null || true
tmux kill-session -t "n8n-server" 2>/dev/null || true
rm -f "$HOME/.last_cf_url" 2>/dev/null
echo "[OK] Todo detenido."
SCRIPT
chmod +x "$HOME/stop_servidor.sh"
log "stop_servidor.sh creado"

# --- ver_url.sh ---
cat > "$HOME/ver_url.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
URL=""
[ -f "$HOME/.last_cf_url" ] && URL=$(cat "$HOME/.last_cf_url")
if [ -z "$URL" ]; then
  URL=$(proot-distro login debian -- bash -c \
    "grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' /root/cf_url.log 2>/dev/null | head -1" 2>/dev/null)
fi
[ -n "$URL" ] && echo "" && echo "  ▸ $URL" && echo "" || \
  echo "[!] URL no disponible — ejecuta n8n-start primero"
SCRIPT
chmod +x "$HOME/ver_url.sh"
log "ver_url.sh creado"

# --- n8n_status.sh ---
cat > "$HOME/n8n_status.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo ""
echo "╔══════════════════════════════════════╗"
echo "║        android-server · n8n         ║"
echo "╠══════════════════════════════════════╣"
tmux has-session -t "n8n-server" 2>/dev/null && \
  echo "║  n8n:         ● ACTIVO               ║" || \
  echo "║  n8n:         ○ DETENIDO             ║"
URL=""
[ -f "$HOME/.last_cf_url" ] && URL=$(cat "$HOME/.last_cf_url")
[ -n "$URL" ] && echo "║  URL:  $URL" || \
  echo "║  URL:         no disponible          ║"
[ -f "$HOME/.cf_token" ] && \
  echo "║  Túnel:       URL FIJA (token ✓)     ║" || \
  echo "║  Túnel:       URL temporal           ║"
IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
[ -n "$IP" ] && echo "║  WiFi:        http://$IP:5678"
echo "╚══════════════════════════════════════╝"
echo ""
SCRIPT
chmod +x "$HOME/n8n_status.sh"
log "n8n_status.sh creado"

# --- n8n_log.sh ---
cat > "$HOME/n8n_log.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
tmux has-session -t "n8n-server" 2>/dev/null && \
  tmux attach-session -t "n8n-server" || \
  echo "[!] n8n no está corriendo — ejecuta: n8n-start"
SCRIPT
chmod +x "$HOME/n8n_log.sh"
log "n8n_log.sh creado"

# --- n8n_update.sh ---
cat > "$HOME/n8n_update.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Actualizando n8n..."
proot-distro login debian -- bash -c \
  'export HOME=/root && npm update -g n8n && echo "n8n: $(n8n --version)"'
SCRIPT
chmod +x "$HOME/n8n_update.sh"
log "n8n_update.sh creado"

# --- backup.sh ---
cat > "$HOME/backup.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
FECHA=$(date +%Y%m%d_%H%M)
DESTINO="/sdcard/Download/n8n_backup_$FECHA.tar.gz"
echo "[*] Creando backup de workflows y credenciales n8n..."
proot-distro login debian -- bash -c \
  "tar -czf /tmp/n8n_backup.tar.gz -C /root/.n8n . 2>/dev/null && echo done"
proot-distro login debian -- bash -c "cat /tmp/n8n_backup.tar.gz" > "$DESTINO" 2>/dev/null
SIZE=$(du -h "$DESTINO" 2>/dev/null | cut -f1)
echo "[OK] Backup: $DESTINO ($SIZE)"
SCRIPT
chmod +x "$HOME/backup.sh"
log "backup.sh creado"

# --- cf_token.sh ---
cat > "$HOME/cf_token.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo ""
echo "  Token actual: $([ -f ~/.cf_token ] && echo 'configurado (URL fija)' || echo 'no configurado (URL temporal)')"
echo ""
read -r -p "  Nuevo token (ENTER para URL temporal): " TOKEN
if [ -n "$TOKEN" ]; then
  echo "$TOKEN" > "$HOME/.cf_token"
  echo "[OK] Token guardado"
else
  rm -f "$HOME/.cf_token"
  echo "[OK] Token eliminado — próximo inicio usará URL temporal"
fi
SCRIPT
chmod +x "$HOME/cf_token.sh"
log "cf_token.sh creado"

# --- debian.sh ---
cat > "$HOME/debian.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
proot-distro login debian
SCRIPT
chmod +x "$HOME/debian.sh"
log "debian.sh creado"

mark_done "scripts"
log "Todos los scripts de control creados"
fi

# ============================================================
# PASO 6 — Aliases en .bashrc
# ============================================================
titulo "PASO 6 — Configurando aliases"

if check_done "aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"

  grep -v "n8n-start\|n8n-stop\|n8n-url\|n8n-status\|n8n-log\|n8n-update\|n8n-backup\|cf-token\|alias debian\|alias help" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << 'ALIASES'

# ════════════════════════════════
#  n8n · aliases
# ════════════════════════════════
alias n8n-start='bash ~/start_servidor.sh'
alias n8n-stop='bash ~/stop_servidor.sh'
alias n8n-url='bash ~/ver_url.sh'
alias n8n-status='bash ~/n8n_status.sh'
alias n8n-log='bash ~/n8n_log.sh'
alias n8n-update='bash ~/n8n_update.sh'
alias n8n-backup='bash ~/backup.sh'
alias cf-token='bash ~/cf_token.sh'
alias debian='bash ~/debian.sh'
alias help='bash ~/help.sh'
ALIASES

  mark_done "aliases"
  log "Aliases configurados"
fi

# ============================================================
# PASO 7 — Arranque automático (Termux:Boot)
# ============================================================
titulo "PASO 7 — Arranque automático"

if check_done "boot"; then
  log "Arranque automático ya configurado [checkpoint]"
else
  BOOT_DIR="$HOME/.termux/boot"
  mkdir -p "$BOOT_DIR"
  cat > "$BOOT_DIR/start_n8n.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/sbin:\$PATH
sleep 25
termux-wake-lock
bash ~/start_servidor.sh
SCRIPT
  chmod +x "$BOOT_DIR/start_n8n.sh"
  mark_done "boot"
  warn "Para arranque automático: instala Termux:Boot desde F-Droid y ábrelo UNA VEZ"
fi

# ============================================================
# PASO 8 — Actualizar registry
# ============================================================
titulo "PASO 8 — Actualizando registry"

N8N_VER_REG=$(proot-distro login debian -- bash -c \
  'n8n --version 2>/dev/null' 2>/dev/null | head -1)
[ -z "$N8N_VER_REG" ] && N8N_VER_REG="unknown"

update_registry "$N8N_VER_REG"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

source "$HOME/.bashrc" 2>/dev/null || true

IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
[ -z "$IP" ] && IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║      n8n instalado con éxito ✓              ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  n8n:       $N8N_VER_REG"
echo "  Puerto:    5678"
[ -n "$IP" ] && echo "  IP WiFi:   $IP"
echo ""
echo "  COMANDOS:"
echo "  n8n-start   → inicia n8n + cloudflared"
echo "  n8n-stop    → detiene todo"
echo "  n8n-url     → muestra URL pública"
echo "  n8n-status  → estado del sistema"
echo "  n8n-log     → logs en vivo"
echo "  n8n-update  → actualizar n8n"
echo "  n8n-backup  → backup de workflows"
echo "  cf-token    → cambiar token cloudflared"
echo "  debian      → consola Debian proot"
echo ""
echo -e "${YELLOW}  IMPORTANTE:${NC}"
echo "  1. Cierra y reabre Termux para activar aliases"
echo "  2. Luego escribe: n8n-start"
echo "  3. Primera vez en :5678 → crea cuenta de administrador"
if [ -z "$ANDROID_SERVER_READY" ]; then
  echo ""
  echo -e "${CYAN}  TIP: ejecuta instalar.sh para aplicar tema visual${NC}"
  echo -e "${CYAN}       y configurar las teclas rápidas de Termux${NC}"
fi
echo ""

rm -f "$CHECKPOINT"

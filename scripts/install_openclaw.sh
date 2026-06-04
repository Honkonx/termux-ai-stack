#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_openclaw.sh
#  Instala OpenClaw en proot Debian (ARM64, sin root)
#
#  USO STANDALONE:
#    bash install_openclaw.sh
#
#  QUÉ HACE:
#    ✅ Verifica que proot-distro y Debian estén instalados
#    ✅ Instala NVM + Node 22 en proot (si no existe)
#    ✅ Crea shim de red Android (os.networkInterfaces fix)
#    ✅ Instala OpenClaw vía npm (npm install -g openclaw)
#    ✅ Ejecuta openclaw setup (config inicial)
#    ✅ Crea lanzador ~/openclaw_start.sh en Termux
#    ✅ Agrega aliases a .bashrc
#    ✅ Escribe estado al registry ~/.android_server_registry
#
#  NOTA TÉCNICA:
#    OpenClaw requiere Node 22 y glibc — no funciona en Termux
#    nativo (Bionic libc). Se instala en proot Debian compartido
#    con n8n y OpenCode. NVM se instala SOLO para OpenClaw
#    (Node 22) — n8n usa Node 20 del sistema Debian, no se toca.
#    El shim parchea os.networkInterfaces() para Android.
#
#  VERSIÓN: 1.1.0 | Mayo 2026
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

# ── Archivos de estado ────────────────────────────────────────
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_openclaw_checkpoint"

# ── Rutas de scripts ──────────────────────────────────────────
OPENCLAW_SCRIPTS="$HOME/scripts/openclaw"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

update_registry() {
  local version="$1"
  local date_now; date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^openclaw\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
openclaw.installed=true
openclaw.version=$version
openclaw.install_date=$date_now
openclaw.location=proot_debian
openclaw.port=18789
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · OpenClaw Installer     ║
  ║   proot Debian ARM64 · sin root            ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ============================================================
# DETECCIÓN TEMPRANA DEL ROOTFS
# Canónica por directorio — antes de cualquier otra operación.
# Ref: ARCHITECTURE.md §3.11 — proot-distro list produce falsos negativos
# ============================================================

# Instalar proot-distro si no está disponible
if ! command -v proot-distro &>/dev/null; then
  info "Instalando proot-distro..."
  pkg install proot-distro proot tmux curl wget tar xz-utils git busybox -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    error "No se pudo instalar proot-distro."
fi

# Detección canónica: buscar cualquier distro con /bin/bash
# NO usar proot-distro list ni login debian hardcodeado
ROOTFS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/installed-rootfs"
DISTRO_NAME=""
ROOTFS_PATH=""
_detect_rootfs() {
  DISTRO_NAME=""
  ROOTFS_PATH=""
  if [ -d "$ROOTFS_BASE" ]; then
    for _d in "$ROOTFS_BASE"/*/; do
      _d="${_d%/}"   # quitar trailing slash
      if [ -f "${_d}/bin/bash" ] || [ -f "${_d}/usr/bin/bash" ] || [ -f "${_d}/etc/os-release" ]; then
        DISTRO_NAME=$(basename "$_d")
        ROOTFS_PATH="$_d"
        break
      fi
    done
  fi
}
_detect_rootfs

# ── Verificar si OpenClaw ya está instalado ──────────────────
# Este check se hace DESPUÉS de tener DISTRO_NAME
if [ -n "$DISTRO_NAME" ]; then
  if proot-distro login "$DISTRO_NAME" -- bash -c \
    'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; command -v openclaw' \
    &>/dev/null 2>&1; then
    CL_VER=$(proot-distro login "$DISTRO_NAME" -- bash -c \
      'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
       openclaw --version 2>/dev/null | head -1' 2>/dev/null \
      | grep -oE '[0-9]+\.[0-9.]+' | head -1)
    echo -e "${GREEN}  ✓ OpenClaw ya está instalado${NC}"
    echo -e "  Versión actual: ${CYAN}${CL_VER:-?}${NC}"
    echo ""
    echo -n "  ¿Reinstalar/actualizar? (s/n): "
    read -r REINSTALL < /dev/tty
    [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
      info "Nada que hacer. Saliendo."
      exit 0
    }
    rm -f "$CHECKPOINT"
  fi
fi

echo ""
echo "  Este script instalará OpenClaw en proot Debian:"
echo "  ▸ NVM + Node 22 (solo para OpenClaw)"
echo "  ▸ Shim de red Android (fix Bionic libc)"
echo "  ▸ OpenClaw vía npm install -g openclaw"
echo "  ▸ Configuración inicial (openclaw setup)"
echo "  ▸ Lanzador: ~/openclaw_start.sh"
echo "  ▸ Aliases: openclaw-start, openclaw-stop, openclaw-status"
echo ""
echo -e "  ${YELLOW}NOTA:${NC} Ollama debe estar corriendo en Termux"
echo -e "  durante el setup. Inícialo si no está activo."
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRM < /dev/tty
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 1 — Verificar proot-distro y rootfs Debian
# ============================================================
titulo "PASO 1 — Verificando entorno proot"

# Si no hay rootfs → ofrecer instalación
if [ -z "$DISTRO_NAME" ]; then
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
        error "Falló la restauración del rootfs Debian"
      ;;
    2)
      info "Instalando Debian con proot-distro..."
      # Verificar que no exista ya (evita "already exists")
      if [ -d "$ROOTFS_BASE/debian" ] && \
         { [ -f "$ROOTFS_BASE/debian/bin/bash" ] || [ -f "$ROOTFS_BASE/debian/usr/bin/bash" ] || [ -f "$ROOTFS_BASE/debian/etc/os-release" ]; }; then
        log "Rootfs debian ya existe en disco — saltando instalación"
      else
        proot-distro install debian || error "No se pudo instalar Debian en proot."
      fi
      ;;
    b|B|"")
      error "Cancelado por el usuario"
      ;;
    *)
      error "Opción inválida"
      ;;
  esac

  # Re-detectar tras instalación (con sleep para esperar flush del FS)
  sleep 2
  _detect_rootfs
  [ -z "$DISTRO_NAME" ] && \
    error "Rootfs Debian no disponible tras la instalación — verifica: ls $ROOTFS_BASE"
  log "Rootfs listo: $DISTRO_NAME"
else
  log "Rootfs encontrado: $DISTRO_NAME ($ROOTFS_PATH)"
fi

info "Usando distro: ${DISTRO_NAME}"

# ============================================================
# PASO 2 — NVM + Node 22 en proot
# ============================================================
titulo "PASO 2 — NVM + Node 22"

if check_done "openclaw_nvm"; then
  log "NVM + Node 22 ya configurados [checkpoint]"
else
  # Verificar si NVM ya existe en proot
  NVM_EXISTS=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    '[ -s "$HOME/.nvm/nvm.sh" ] && echo "yes" || echo "no"' 2>/dev/null)

  if [ "$NVM_EXISTS" = "yes" ]; then
    log "NVM ya existe en proot"
  else
    info "Instalando NVM en proot Debian..."
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' || \
      error "No se pudo instalar NVM."
    log "NVM instalado"
  fi

  # Verificar si Node 22 ya está disponible via NVM
  NODE22_EXISTS=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     node --version 2>/dev/null | grep -c "^v22"' 2>/dev/null)

  if [ "$NODE22_EXISTS" = "1" ]; then
    log "Node 22 ya está activo"
  else
    info "Instalando Node 22 via NVM..."
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
       nvm install 22 && nvm use 22 && nvm alias default 22' || \
      error "No se pudo instalar Node 22."
    NODE_VER=$(proot-distro login "$DISTRO_NAME" -- bash -c \
      'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
       node --version 2>/dev/null' 2>/dev/null)
    log "Node ${NODE_VER:-22} instalado"
  fi

  mark_done "openclaw_nvm"
fi

# ============================================================
# PASO 3 — Shim de red Android
# ============================================================
titulo "PASO 3 — Shim de red Android"

if check_done "openclaw_shim"; then
  log "Shim ya creado [checkpoint]"
else
  info "Creando shim de red (fix os.networkInterfaces)..."
  proot-distro login "$DISTRO_NAME" -- bash -c \
'cat > /root/openclaw-shim.cjs << '"'"'EOF'"'"'
const os = require('"'"'os'"'"');
os.networkInterfaces = () => ({
  lo: [{
    address: '"'"'127.0.0.1'"'"',
    netmask: '"'"'255.0.0.0'"'"',
    family: '"'"'IPv4'"'"',
    mac: '"'"'00:00:00:00:00:00'"'"',
    internal: true,
    cidr: '"'"'127.0.0.1/8'"'"'
  }]
});
EOF' || error "No se pudo crear el shim."

  log "Shim creado en /root/openclaw-shim.cjs"
  mark_done "openclaw_shim"
fi

# ============================================================
# PASO 4 — Instalar OpenClaw
# ============================================================
titulo "PASO 4 — Instalando OpenClaw"

if check_done "openclaw_install"; then
  log "OpenClaw ya instalado [checkpoint]"
else
  info "Instalando openclaw via npm (Node 22 + shim)..."
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
     npm install -g openclaw@latest 2>&1 | tail -5' || \
    error "No se pudo instalar OpenClaw."

  # Verificar instalación
  CL_OK=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     command -v openclaw && echo "ok" || echo "fail"' 2>/dev/null | tail -1)

  [ "$CL_OK" != "ok" ] && error "OpenClaw no quedó accesible. Revisa la instalación."

  CL_VER=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     openclaw --version 2>/dev/null | head -1' 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9.]+' | head -1)
  [ -z "$CL_VER" ] && CL_VER="unknown"

  log "OpenClaw ${CL_VER} instalado"
  mark_done "openclaw_install"
fi

# ============================================================
# PASO 5 — Setup inicial de OpenClaw
# ============================================================
titulo "PASO 5 — Setup inicial"

if check_done "openclaw_setup"; then
  log "Setup ya ejecutado [checkpoint]"
else
  echo ""
  echo -e "  ${CYAN}Ejecutando openclaw setup --wizard...${NC}"
  echo ""
  echo -e "  ${YELLOW}IMPORTANTE — Lee antes de continuar:${NC}"
  echo -e "  ▸ Ollama debe estar corriendo en Termux (otra sesión)"
  echo -e "  ▸ El wizard puede tardar 1-3 minutos en ARM64"
  echo -e "  ▸ Cada pantalla puede demorar en cargar — es normal"
  echo -e "  ▸ Selecciona: Ollama → http://127.0.0.1:11434"
  echo -e "  ▸ Canal: elige 'Do this later' para configurar después"
  echo ""
  echo -n "  ¿Ollama está activo y listo para continuar? (s/n): "
  read -r OL_OK < /dev/tty

  if [ "$OL_OK" = "s" ] || [ "$OL_OK" = "S" ]; then
    echo ""
    info "Lanzando wizard — puede tardar, ten paciencia..."
    echo ""
    proot-distro login "$DISTRO_NAME" -- bash -c \
      'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
       export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
       openclaw setup --wizard' < /dev/tty

    # Verificar que el token quedó guardado
    TOKEN_CHECK=$(proot-distro login "$DISTRO_NAME" -- bash -c \
      "python3 -c \"import json; d=json.load(open('/root/.openclaw/openclaw.json')); print(d['gateway']['auth']['token'])\"" \
      2>/dev/null)
    if [ -n "$TOKEN_CHECK" ]; then
      log "Setup completado — token generado correctamente"
    else
      warn "Setup terminó pero no se detectó token en openclaw.json"
      warn "Puedes re-ejecutar el setup desde el menú: [1] OpenClaw → [8]"
    fi
  else
    warn "Setup omitido — el gateway NO arrancará sin configuración"
    warn "Ejecuta después: proot-distro login $DISTRO_NAME → openclaw setup --wizard"
    warn "O desde el menú: [1] OpenClaw → [8] Instalar/configurar"
  fi

  mark_done "openclaw_setup"
fi

# ============================================================
# PASO 6 — Configurar .bashrc en proot
# ============================================================
titulo "PASO 6 — Configurando entorno proot"

if check_done "openclaw_proot_bashrc"; then
  log "Entorno proot ya configurado [checkpoint]"
else
  info "Configurando NVM + shim en .bashrc del proot..."
  proot-distro login "$DISTRO_NAME" -- bash -c \
'grep -v "NVM_DIR\|openclaw-shim\|openclaw aliases\|openclaw-start\|openclaw-stop\|claw-status\|claw-logs" \
  /root/.bashrc > /root/.bashrc.tmp 2>/dev/null && mv /root/.bashrc.tmp /root/.bashrc

cat >> /root/.bashrc << '"'"'BASHRC'"'"'

# ════════════════════════════════
#  OpenClaw · NVM + shim de red
# ════════════════════════════════
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export NODE_OPTIONS="--require /root/openclaw-shim.cjs"

# OpenClaw aliases (dentro del proot)
alias openclaw-start='"'"'openclaw gateway --bind loopback'"'"'
alias claw-status='"'"'ps aux | grep openclaw'"'"'
alias claw-logs='"'"'tail -f /tmp/openclaw/*.log 2>/dev/null || echo "Sin logs activos"'"'"'
BASHRC'

  log ".bashrc del proot configurado"
  mark_done "openclaw_proot_bashrc"
fi

# ============================================================
# PASO 7 — Lanzador desde Termux nativo
# ============================================================
titulo "PASO 7 — Scripts de control desde Termux"

if check_done "openclaw_scripts"; then
  log "Scripts ya creados [checkpoint]"
else
  mkdir -p "$OPENCLAW_SCRIPTS"

  # Capturar DISTRO_NAME para embeber en los scripts generados
  _DN="$DISTRO_NAME"

  # ── openclaw_start.sh ─────────────────────────────────────
  cat > "$OPENCLAW_SCRIPTS/openclaw_start.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
# Lanzador OpenClaw Gateway — termux-ai-stack
# Arranca el gateway en background desde Termux nativo

PID_FILE="\$HOME/.openclaw_gateway.pid"
PORT=18789
DISTRO_NAME="${_DN}"

# Verificar si ya está corriendo
if curl -sf http://127.0.0.1:\$PORT &>/dev/null; then
  TOKEN=\$(proot-distro login "\$DISTRO_NAME" -- bash -c \
    "python3 -c \"import json; d=json.load(open('/root/.openclaw/openclaw.json')); print(d['gateway']['auth']['token'])\"" \
    2>/dev/null)
  echo ""
  echo -e "\033[0;32m[OK]\033[0m Gateway ya corriendo en :\${PORT}"
  echo ""
  echo -e "  URL: \033[0;36mhttp://127.0.0.1:\${PORT}/#token=\${TOKEN}\033[0m"
  echo ""
  exit 0
fi

echo ""
echo -e "\033[0;36m[+] Iniciando OpenClaw Gateway...\033[0m"
echo -e "    Espera ~30-60 segundos en ARM64"
echo ""

# Lanzar en background desde Termux nativo
proot-distro login "\$DISTRO_NAME" -- bash -c \
  'export NVM_DIR="\$HOME/.nvm"; [ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
   export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
   openclaw gateway --bind loopback' > "\$HOME/.openclaw_gateway.log" 2>&1 &

echo \$! > "\$PID_FILE"

# Esperar hasta que responda (máx 60s — ARM64 es lento al arrancar)
TRIES=0
while [ \$TRIES -lt 30 ]; do
  sleep 2
  if curl -sf http://127.0.0.1:\$PORT &>/dev/null; then
    break
  fi
  TRIES=\$((TRIES + 1))
  echo -n "."
done
echo ""

if curl -sf http://127.0.0.1:\$PORT &>/dev/null; then
  TOKEN=\$(proot-distro login "\$DISTRO_NAME" -- bash -c \
    "python3 -c \"
import json, sys
try:
    d=json.load(open('/root/.openclaw/openclaw.json'))
    print(d['gateway']['auth']['token'])
except Exception as e:
    print('')
\"" 2>/dev/null | tr -d '[:space:]')
  echo ""
  echo -e "\033[0;32m[OK]\033[0m Gateway iniciado"
  echo ""
  if [ -n "\$TOKEN" ]; then
    echo -e "  URL con token:"
    echo -e "  \033[0;36mhttp://127.0.0.1:\${PORT}/#token=\${TOKEN}\033[0m"
    echo ""
    echo -e "  Abre la URL manualmente en Brave o Chrome"
  else
    echo -e "  URL base: \033[0;36mhttp://127.0.0.1:\${PORT}\033[0m"
    echo -e "  \033[1;33m[AVISO]\033[0m Token no encontrado — ejecuta openclaw setup --wizard"
  fi
  echo ""
else
  echo ""
  echo -e "\033[0;31m[ERROR]\033[0m Gateway no respondió a tiempo"
  echo "  Revisa el log: cat ~/.openclaw_gateway.log"
  echo ""
fi
SCRIPT
  chmod +x "$OPENCLAW_SCRIPTS/openclaw_start.sh"
  log "openclaw_start.sh creado"

  # ── openclaw_stop.sh ──────────────────────────────────────
  cat > "$OPENCLAW_SCRIPTS/openclaw_stop.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
# Detener OpenClaw Gateway — termux-ai-stack
PID_FILE="\$HOME/.openclaw_gateway.pid"
DISTRO_NAME="${_DN}"

echo -e "\033[0;36m[+] Deteniendo OpenClaw...\033[0m"

# Matar por PID guardado
if [ -f "\$PID_FILE" ]; then
  PID=\$(cat "\$PID_FILE")
  kill "\$PID" 2>/dev/null && echo -e "\033[0;32m[OK]\033[0m Proceso \$PID terminado"
  rm -f "\$PID_FILE"
fi

# Respaldo: pkill por nombre
pkill -f "openclaw gateway" 2>/dev/null || true
proot-distro login "\$DISTRO_NAME" -- bash -c \
  'pkill -f "openclaw gateway" 2>/dev/null || true' 2>/dev/null || true

sleep 1
if curl -sf http://127.0.0.1:18789 &>/dev/null; then
  echo -e "\033[1;33m[AVISO]\033[0m Gateway aún responde — puede necesitar más tiempo"
else
  echo -e "\033[0;32m[OK]\033[0m Gateway detenido"
fi
echo ""
SCRIPT
  chmod +x "$OPENCLAW_SCRIPTS/openclaw_stop.sh"
  log "openclaw_stop.sh creado"

  # ── openclaw_token.sh ─────────────────────────────────────
  cat > "$OPENCLAW_SCRIPTS/openclaw_token.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
# Mostrar URL con token de OpenClaw — termux-ai-stack
PORT=18789
DISTRO_NAME="${_DN}"
TOKEN=\$(proot-distro login "\$DISTRO_NAME" -- bash -c \
  "python3 -c \"
import json, sys
try:
    d=json.load(open('/root/.openclaw/openclaw.json'))
    print(d['gateway']['auth']['token'])
except Exception:
    print('')
\"" 2>/dev/null | tr -d '[:space:]')

if [ -z "\$TOKEN" ]; then
  echo ""
  echo -e "\033[0;31m[ERROR]\033[0m Token no encontrado"
  echo "  OpenClaw necesita configuración inicial."
  echo "  Ejecuta: proot-distro login \$DISTRO_NAME"
  echo "  Luego:   openclaw setup --wizard"
  echo ""
  exit 1
fi

echo ""
echo -e "  URL con token:"
echo -e "  \033[0;36mhttp://127.0.0.1:\${PORT}/#token=\${TOKEN}\033[0m"
echo ""

echo "  Copia la URL y ábrela en Brave o Chrome"
echo ""
SCRIPT
  chmod +x "$OPENCLAW_SCRIPTS/openclaw_token.sh"
  log "openclaw_token.sh creado"

  mark_done "openclaw_scripts"
fi

# ============================================================
# PASO 8 — Aliases en .bashrc de Termux
# ============================================================
titulo "PASO 8 — Aliases en Termux"

if check_done "openclaw_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"
  # Limpiar aliases anteriores
  grep -v "openclaw-start\|openclaw-stop\|openclaw-status\|openclaw-token\|openclaw-tui\|# OpenClaw" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  # DISTRO_NAME se expande aquí (fuera del heredoc con comillas simples)
  cat >> "$BASHRC" << ALIASES

# ════════════════════════════════
#  OpenClaw · aliases Termux
# ════════════════════════════════
alias openclaw-start='bash ~/scripts/openclaw/openclaw_start.sh'
alias openclaw-stop='bash ~/scripts/openclaw/openclaw_stop.sh'
alias openclaw-token='bash ~/scripts/openclaw/openclaw_token.sh'
alias openclaw-status='curl -sf http://127.0.0.1:18789 &>/dev/null && echo "OpenClaw activo :18789" || echo "OpenClaw detenido"'
alias openclaw-tui='proot-distro login ${DISTRO_NAME} -- bash -c "source ~/.bashrc 2>/dev/null; openclaw tui"'
ALIASES

  log "Aliases agregados a ~/.bashrc de Termux"
  mark_done "openclaw_aliases"
fi

# ============================================================
# PASO 9 — Registry
# ============================================================
titulo "PASO 9 — Actualizando registry"

CL_VER_FINAL=$(proot-distro login "$DISTRO_NAME" -- bash -c \
  'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
   openclaw --version 2>/dev/null | head -1' 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9.]+' | head -1)
[ -z "$CL_VER_FINAL" ] && CL_VER_FINAL="unknown"

update_registry "$CL_VER_FINAL"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║     OpenClaw instalado con éxito ✓         ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  Versión:  ${CL_VER_FINAL}"
echo "  Puerto:   18789"
echo "  Entorno:  proot Debian (Node 22 via NVM)"
echo "  Distro:   ${DISTRO_NAME}"
echo ""
echo "  COMANDOS:"
echo "  openclaw-start   → iniciar gateway + abrir browser con token"
echo "  openclaw-stop    → detener gateway"
echo "  openclaw-status  → verificar estado"
echo "  openclaw-token   → mostrar/abrir URL con token"
echo "  openclaw-tui     → interfaz TUI en terminal"
echo ""
echo "  DESDE EL MENÚ:"
echo "  menu → [1] → OpenClaw → submenú"
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para activar aliases${NC}"
echo ""

# Limpiar checkpoint
rm -f "$CHECKPOINT"

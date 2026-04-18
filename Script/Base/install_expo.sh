#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  android-server · install_expo.sh
#  Instala EAS CLI (Expo Application Services) en Termux
#
#  USO STANDALONE:
#    bash install_expo.sh
#
#  USO VÍA MAESTRO (cuando repo sea público):
#    bash <(curl -fsSL https://raw.githubusercontent.com/TU_USUARIO/android-server/main/modules/install_expo.sh)
#
#  QUÉ HACE:
#    ✅ Actualiza Termux (solo si no lo hizo el maestro)
#    ✅ Verifica/instala Node.js >= 18 y git
#    ✅ Instala eas-cli vía npm
#    ✅ Login opcional en expo.dev
#    ✅ Crea scripts de control (build/status/submit/push)
#    ✅ Configura aliases en .bashrc
#    ✅ Escribe estado al registry ~/.android_server_registry
#
#  RESPONSABILIDAD DEL MAESTRO (instalar.sh):
#    ⏭  Tema visual (GitHub Dark + JetBrains Mono)
#    ⏭  termux.properties + extra-keys
#    ⏭  pkg update base → exporta ANDROID_SERVER_READY=1
#
#  VERSIÓN: 1.0.0 | Abril 2026
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
CHECKPOINT="$HOME/.install_expo_checkpoint"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Función: actualizar registry ─────────────────────────────
update_registry() {
  local version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)

  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"

  local tmp="$REGISTRY.tmp"
  grep -v "^expo\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"

  cat >> "$tmp" << EOF
expo.installed=true
expo.version=$version
expo.install_date=$date_now
expo.commands=expo-build,expo-status,expo-submit,expo-push,expo-login,expo-info
expo.port=none
expo.location=termux_native
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → $REGISTRY"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   android-server · Expo / EAS Installer     ║
  ║   React Native Cloud Build · ARM64          ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado ───────────────────────────
if command -v eas &>/dev/null; then
  CURRENT_VER=$(eas --version 2>/dev/null | head -1)
  echo -e "${GREEN}  ✓ EAS CLI ya está instalado${NC}"
  echo -e "  Versión actual: ${CYAN}${CURRENT_VER}${NC}"
  echo -e "  Usuario Expo:   ${CYAN}$(eas whoami 2>/dev/null || echo 'no logueado')${NC}"
  echo ""
  read -r -p "  ¿Reinstalar/actualizar? (s/n): " REINSTALL
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
fi

# ── Mostrar checkpoints previos ───────────────────────────────
if [ -f "$CHECKPOINT" ] && [ -s "$CHECKPOINT" ]; then
  echo -e "${YELLOW}  Instalación previa detectada — se omitirán:${NC}"
  while IFS= read -r line; do
    echo -e "  ${GREEN}✓${NC} $line"
  done < "$CHECKPOINT"
  echo ""
  read -r -p "  ¿Continuar desde donde quedó? (s/n): " CONT
  [ "$CONT" != "s" ] && [ "$CONT" != "S" ] && {
    read -r -p "  ¿Reiniciar desde cero? (s/n): " RESET
    [ "$RESET" = "s" ] || [ "$RESET" = "S" ] && rm -f "$CHECKPOINT"
  }
  echo ""
fi

echo "  Este script instala:"
echo "  ▸ Node.js >= 18 y git (si no están)"
echo "  ▸ eas-cli vía npm (compilación en la nube de Expo)"
echo "  ▸ Scripts de control: build, status, submit, push"
echo "  ▸ Aliases en .bashrc"
echo ""
[ -z "$ANDROID_SERVER_READY" ] && \
  echo "  Tema y termux.properties → ejecuta instalar.sh para eso"
echo "  n8n, Claude Code, Ollama → cada uno tiene su propio script"
echo ""
read -r -p "  ¿Continuar? (s/n): " CONFIRMAR
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

  mark_done "termux_update"
  log "Termux actualizado"
fi

# ============================================================
# PASO 2 — Node.js y git
# ============================================================
titulo "PASO 2 — Node.js y git"

if check_done "nodejs_git"; then
  log "Node.js y git ya verificados [checkpoint]"
else
  # Node.js
  if command -v node &>/dev/null; then
    NODE_MAJOR=$(node --version 2>/dev/null | sed 's/v//' | cut -d'.' -f1)
    if [ "$NODE_MAJOR" -ge 18 ] 2>/dev/null; then
      log "Node.js $(node --version) ✓"
    else
      warn "Node.js $(node --version) — versión < 18, actualizando..."
      pkg install nodejs -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
      log "Node.js actualizado: $(node --version)"
    fi
  else
    info "Instalando Node.js..."
    pkg install nodejs -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      error "Falló instalación de Node.js"
    log "Node.js $(node --version) instalado"
  fi

  # git
  if command -v git &>/dev/null; then
    log "git $(git --version | cut -d' ' -f3) ✓"
  else
    info "Instalando git..."
    pkg install git -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      error "Falló instalación de git"
    log "git instalado"
  fi

  mark_done "nodejs_git"
fi

# ============================================================
# PASO 3 — Instalar EAS CLI
# ============================================================
titulo "PASO 3 — Instalando EAS CLI"

if check_done "eas_install"; then
  log "EAS CLI ya instalado [checkpoint]"
else
  info "Instalando eas-cli desde npm (1-2 min)..."
  npm install -g eas-cli 2>&1 | tail -3
  command -v eas &>/dev/null || error "EAS CLI no instaló correctamente"
  log "EAS CLI $(eas --version 2>/dev/null | head -1)"
  mark_done "eas_install"
fi

# ============================================================
# PASO 4 — Login en Expo (opcional)
# ============================================================
titulo "PASO 4 — Login en Expo"

if check_done "expo_login"; then
  log "Login ya completado [checkpoint]"
  info "Usuario: $(eas whoami 2>/dev/null || echo 'verificar con: eas whoami')"
else
  echo ""
  echo "  Para compilar en la nube necesitas una cuenta en expo.dev"
  echo "  (gratis — 30 builds/mes en el plan gratuito)"
  echo ""
  read -r -p "  ¿Hacer login ahora? (s/n): " DO_LOGIN

  if [ "$DO_LOGIN" = "s" ] || [ "$DO_LOGIN" = "S" ]; then
    eas login
    if eas whoami &>/dev/null; then
      log "Sesión iniciada: $(eas whoami)"
      mark_done "expo_login"
    else
      warn "Login no completado — usa 'expo-login' después"
    fi
  else
    info "Login pendiente — usa: expo-login"
    mark_done "expo_login"
  fi
fi

# ============================================================
# PASO 5 — Crear scripts de control
# ============================================================
titulo "PASO 5 — Creando scripts de control"

if check_done "expo_scripts"; then
  log "Scripts ya creados [checkpoint]"
else

# --- eas_build.sh ---
cat > "$HOME/eas_build.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# USO: expo-build [ruta_proyecto] [preview|production]
#   preview    → APK instalable directo (~5-10 min)
#   production → AAB para Google Play Store

PROYECTO="${1:-$(pwd)}"
PERFIL="${2:-preview}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}━━━ EAS Build ━━━${NC}"
echo "  Proyecto: $PROYECTO"
echo "  Perfil:   $PERFIL"
echo ""

[ -d "$PROYECTO" ]            || { echo -e "${RED}[ERROR]${NC} No existe: $PROYECTO"; exit 1; }
[ -f "$PROYECTO/package.json" ] || { echo -e "${RED}[ERROR]${NC} No es un proyecto Expo: $PROYECTO"; exit 1; }

cd "$PROYECTO"

eas whoami &>/dev/null || {
  echo -e "${YELLOW}[AVISO]${NC} No estás logueado — ejecuta: expo-login"
  exit 1
}

echo -e "${GREEN}[OK]${NC} Usuario: $(eas whoami)"
echo ""

[ ! -f "eas.json" ] && {
  echo -e "${YELLOW}[AVISO]${NC} eas.json no encontrado — configurando proyecto..."
  eas build:configure
}

echo "  Iniciando build en la nube de Expo..."
echo "  (Puedes cerrar Termux — el build sigue en la nube)"
echo ""
eas build --platform android --profile "$PERFIL"
SCRIPT
chmod +x "$HOME/eas_build.sh"
log "eas_build.sh creado"

# --- eas_status.sh ---
cat > "$HOME/eas_status.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# Estados: IN_QUEUE · IN_PROGRESS · FINISHED · ERRORED
echo ""
echo "━━━ Builds en Expo Cloud (últimos 5) ━━━"
echo ""
eas build:list --platform android --limit 5
SCRIPT
chmod +x "$HOME/eas_status.sh"
log "eas_status.sh creado"

# --- eas_submit.sh ---
cat > "$HOME/eas_submit.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# Sube un build production a Google Play Store
# Requiere: build production completado + credenciales en expo.dev
PROYECTO="${1:-$(pwd)}"
cd "$PROYECTO" || { echo "[ERROR] No existe: $PROYECTO"; exit 1; }
echo "━━━ EAS Submit → Google Play ━━━"
echo ""
eas submit --platform android
SCRIPT
chmod +x "$HOME/eas_submit.sh"
log "eas_submit.sh creado"

# --- git_push.sh ---
cat > "$HOME/git_push.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# USO: expo-push [ruta_proyecto] ["mensaje del commit"]
PROYECTO="${1:-$(pwd)}"
MENSAJE="${2:-"update: cambios desde Android"}"

cd "$PROYECTO" || { echo "[ERROR] No existe: $PROYECTO"; exit 1; }

echo "━━━ Git Push ━━━"
echo "  Proyecto: $PROYECTO"
echo "  Mensaje:  $MENSAJE"
echo ""

git add .
git status --short
echo ""
git commit -m "$MENSAJE"
git push
echo ""
echo "[OK] Cambios subidos al repositorio"
SCRIPT
chmod +x "$HOME/git_push.sh"
log "git_push.sh creado"

# --- expo_info.sh ---
cat > "$HOME/expo_info.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo ""
echo "╔══════════════════════════════════════╗"
echo "║     android-server · Expo / EAS     ║"
echo "╠══════════════════════════════════════╣"
echo "║  Node.js:  $(node --version 2>/dev/null || echo 'no instalado')"
echo "║  npm:      v$(npm --version 2>/dev/null || echo 'no instalado')"
echo "║  EAS CLI:  $(eas --version 2>/dev/null | head -1 || echo 'no instalado')"
echo "║  git:      $(git --version 2>/dev/null | cut -d' ' -f3 || echo 'no instalado')"
echo "╠══════════════════════════════════════╣"
echo "║  Expo: $(eas whoami 2>/dev/null || echo 'no logueado')"
echo "╠══════════════════════════════════════╣"
echo "║  expo-build [proyecto] [perfil]     ║"
echo "║  expo-status                        ║"
echo "║  expo-submit [proyecto]             ║"
echo "║  expo-push [proyecto] [mensaje]     ║"
echo "║  expo-login                         ║"
echo "╚══════════════════════════════════════╝"
echo ""
SCRIPT
chmod +x "$HOME/expo_info.sh"
log "expo_info.sh creado"

mark_done "expo_scripts"
log "Todos los scripts de control creados"
fi

# ============================================================
# PASO 6 — Aliases en .bashrc
# ============================================================
titulo "PASO 6 — Configurando aliases"

if check_done "expo_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"

  # Eliminar aliases anteriores para evitar duplicados
  grep -v "expo-build\|expo-status\|expo-submit\|expo-push\|expo-login\|expo-info" \
    "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"

  cat >> "$BASHRC" << 'ALIASES'

# ════════════════════════════════
#  Expo / EAS · aliases
# ════════════════════════════════
alias expo-build='bash ~/eas_build.sh'
alias expo-status='bash ~/eas_status.sh'
alias expo-submit='bash ~/eas_submit.sh'
alias expo-push='bash ~/git_push.sh'
alias expo-login='eas login'
alias expo-info='bash ~/expo_info.sh'
ALIASES

  mark_done "expo_aliases"
  log "Aliases configurados"
fi

# ============================================================
# PASO 7 — Actualizar registry
# ============================================================
titulo "PASO 7 — Actualizando registry"

EAS_VER_REG=$(eas --version 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1)
[ -z "$EAS_VER_REG" ] && EAS_VER_REG="unknown"

update_registry "$EAS_VER_REG"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

source "$HOME/.bashrc" 2>/dev/null || true

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║    Expo / EAS CLI instalado con éxito ✓     ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  EAS CLI:  $(eas --version 2>/dev/null | head -1)"
echo "  Node.js:  $(node --version)"
echo "  git:      $(git --version | cut -d' ' -f3)"
echo "  Usuario:  $(eas whoami 2>/dev/null || echo 'no logueado')"
echo ""
echo "  COMANDOS:"
echo "  expo-build [proyecto] preview    → APK de prueba"
echo "  expo-build [proyecto] production → AAB Play Store"
echo "  expo-status                      → ver builds activos"
echo "  expo-submit [proyecto]           → subir a Play Store"
echo "  expo-push [proyecto] [mensaje]   → commit + push"
echo "  expo-login                       → login en expo.dev"
echo "  expo-info                        → info general"
echo ""
echo -e "${YELLOW}  IMPORTANTE:${NC}"
echo "  1. Cierra y reabre Termux para activar aliases"
if [ -z "$(eas whoami 2>/dev/null)" ]; then
  echo "  2. Haz login con: expo-login"
  echo "  3. Luego: expo-build /ruta/a/tu/proyecto preview"
else
  echo "  2. Ya logueado — prueba: expo-build /ruta/proyecto preview"
fi
if [ -z "$ANDROID_SERVER_READY" ]; then
  echo ""
  echo -e "${CYAN}  TIP: ejecuta instalar.sh para aplicar tema visual${NC}"
  echo -e "${CYAN}       y configurar las teclas rápidas de Termux${NC}"
fi
echo ""

rm -f "$CHECKPOINT"

#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_hermes.sh
#  Instalador de Hermes Agent para Termux ARM64 (sin root)
#
#  Basado en el instalador oficial de NousResearch con
#  adaptaciones para el stack:
#    - Integración con ~/.android_server_registry
#    - Checkpoint para evitar reinstalación
#    - Wizard lanzado igual que openclaw (hermes setup)
#    - Sin uv, sin sudo, sin /tmp/ (noexec Android 15)
#    - read siempre con < /dev/tty (regla Termux)
#    - Paths: $HOME en lugar de /tmp
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
# ============================================================

set -e

# ── Limpiar env heredado que rompe pip en sesiones anidadas ──
[ -n "${PYTHONPATH:-}"  ] && unset PYTHONPATH
[ -n "${PYTHONHOME:-}"  ] && unset PYTHONHOME
export UV_NO_CONFIG=1

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Variables del stack ───────────────────────────────────
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_hermes_checkpoint"

# ── Variables de Hermes ───────────────────────────────────
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
INSTALL_DIR="$HERMES_HOME/hermes-agent"
REPO_URL_HTTPS="https://github.com/NousResearch/hermes-agent.git"
REPO_URL_SSH="git@github.com:NousResearch/hermes-agent.git"
BRANCH="main"

# ── Colores ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info()    { echo -e "  ${CYAN}→${NC} $1"; }
log_ok()      { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "  ${RED}✗${NC} $1"; }
mark_done()   { grep -q "^hermes_${1}=done" "$CHECKPOINT" 2>/dev/null || echo "hermes_${1}=done" >> "$CHECKPOINT"; }
check_done()  { grep -q "^hermes_${1}=done" "$CHECKPOINT" 2>/dev/null; }

# ════════════════════════════════════════════
#  BANNER
# ════════════════════════════════════════════
clear; echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║  ⚕ HERMES AGENT — Instalador            ║"
echo "  ║  termux-ai-stack · ARM64 · sin root     ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ════════════════════════════════════════════
#  DETECCIÓN DE REINSTALACIÓN
# ════════════════════════════════════════════
if command -v hermes &>/dev/null && [ -d "$INSTALL_DIR" ]; then
  EXISTING_VER=$(hermes version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  echo -e "  ${YELLOW}[AVISO]${NC} Hermes ya está instalado${EXISTING_VER:+ (v${EXISTING_VER})}"
  echo ""
  echo -e "  ${BOLD}[1]${NC} Reinstalar (borra venv y clona de nuevo)"
  echo -e "  ${BOLD}[2]${NC} Actualizar (hermes update)"
  echo -e "  ${BOLD}[b]${NC} Cancelar"
  echo ""; echo -n "  Opción: "
  read -r REINST_OPT < /dev/tty
  case "$REINST_OPT" in
    2)
      echo ""
      log_info "Ejecutando hermes update..."
      hermes update < /dev/tty
      echo ""
      log_ok "Actualización completada"
      echo ""; exit 0 ;;
    b|B|"") echo ""; exit 0 ;;
    1|*) # Continuar con reinstalación
      rm -f "$CHECKPOINT" 2>/dev/null
      log_info "Eliminando instalación anterior..."
      rm -rf "$INSTALL_DIR" 2>/dev/null || true
      rm -f "${TERMUX_PREFIX}/bin/hermes" 2>/dev/null || true
      rm -f "$HOME/.local/bin/hermes"    2>/dev/null || true
      echo "" ;;
  esac
fi

# ════════════════════════════════════════════
#  PASO 1 — DEPENDENCIAS DEL SISTEMA
# ════════════════════════════════════════════
echo -e "  ${CYAN}${BOLD}[PASO 1/6]${NC} Instalando dependencias del sistema..."
echo ""

if check_done "pkgs"; then
  log_ok "Paquetes del sistema ya instalados [checkpoint]"
else
  TERMUX_PKGS=(
    python git clang rust make pkg-config
    libffi openssl ca-certificates curl
    ripgrep ffmpeg nodejs
  )
  log_info "Actualizando pkg e instalando: ${TERMUX_PKGS[*]}"
  pkg update -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>/dev/null || true
  pkg install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    "${TERMUX_PKGS[@]}" 2>/dev/null \
    && log_ok "Paquetes instalados" \
    || log_warn "Algunos paquetes tuvieron advertencias — continuando"
  mark_done "pkgs"
fi
echo ""

# ════════════════════════════════════════════
#  PASO 2 — CLONAR REPOSITORIO
# ════════════════════════════════════════════
echo -e "  ${CYAN}${BOLD}[PASO 2/6]${NC} Clonando repositorio de Hermes..."
echo ""

mkdir -p "$HERMES_HOME"

if check_done "clone" && [ -d "$INSTALL_DIR/.git" ]; then
  log_ok "Repositorio ya clonado [checkpoint]"
else
  if [ -d "$INSTALL_DIR" ]; then
    log_info "Directorio existente detectado — eliminando..."
    rm -rf "$INSTALL_DIR"
  fi

  log_info "Intentando clonar via SSH..."
  if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
     git clone --depth 1 --branch "$BRANCH" "$REPO_URL_SSH" "$INSTALL_DIR" 2>/dev/null; then
    log_ok "Clonado via SSH"
  else
    log_info "SSH falló, intentando HTTPS..."
    if git clone --depth 1 --branch "$BRANCH" "$REPO_URL_HTTPS" "$INSTALL_DIR"; then
      log_ok "Clonado via HTTPS"
    else
      log_error "No se pudo clonar el repositorio"
      echo -e "  ${DIM}Verifica tu conexión a internet${NC}"
      exit 1
    fi
  fi
  mark_done "clone"
fi
echo ""

# ════════════════════════════════════════════
#  PASO 3 — VENV PYTHON
# ════════════════════════════════════════════
echo -e "  ${CYAN}${BOLD}[PASO 3/6]${NC} Creando entorno virtual Python..."
echo ""

cd "$INSTALL_DIR"

if check_done "venv" && [ -f "$INSTALL_DIR/venv/bin/python" ]; then
  log_ok "Virtualenv ya existe [checkpoint]"
else
  PYTHON_PATH=$(command -v python 2>/dev/null || command -v python3 2>/dev/null)
  if [ -z "$PYTHON_PATH" ]; then
    log_error "Python no encontrado — instala con: pkg install python"
    exit 1
  fi

  PYTHON_VER=$("$PYTHON_PATH" --version 2>/dev/null)
  log_info "Python detectado: $PYTHON_VER"

  # Recrear venv limpio
  [ -d "venv" ] && rm -rf venv
  "$PYTHON_PATH" -m venv venv
  log_ok "Virtualenv listo ($(./venv/bin/python --version 2>/dev/null))"
  mark_done "venv"
fi
echo ""

# ════════════════════════════════════════════
#  PASO 4 — INSTALAR DEPENDENCIAS PYTHON
# ════════════════════════════════════════════
echo -e "  ${CYAN}${BOLD}[PASO 4/6]${NC} Instalando dependencias Python..."
echo ""

cd "$INSTALL_DIR"
PIP_PYTHON="$INSTALL_DIR/venv/bin/python"
export VIRTUAL_ENV="$INSTALL_DIR/venv"

if check_done "deps"; then
  log_ok "Dependencias Python ya instaladas [checkpoint]"
else
  # ANDROID_API_LEVEL requerido para wheels con Rust/maturin (jiter, psutil)
  if [ -z "${ANDROID_API_LEVEL:-}" ]; then
    ANDROID_API_LEVEL="$(getprop ro.build.version.sdk 2>/dev/null || echo 34)"
    export ANDROID_API_LEVEL
  fi
  log_info "ANDROID_API_LEVEL=$ANDROID_API_LEVEL"

  log_info "Actualizando pip, setuptools, wheel..."
  "$PIP_PYTHON" -m pip install --upgrade pip setuptools wheel -q

  # psutil no funciona en Android — requiere parche previo
  # El script install_psutil_android.py está incluido en el repo oficial
  if "$PIP_PYTHON" -c 'import sys; raise SystemExit(0 if sys.platform == "android" else 1)' 2>/dev/null; then
    log_info "Android Python detectado — pre-compilando psutil..."
    if [ -f "$INSTALL_DIR/scripts/install_psutil_android.py" ]; then
      "$PIP_PYTHON" "$INSTALL_DIR/scripts/install_psutil_android.py" \
        --pip "$PIP_PYTHON -m pip" 2>/dev/null \
        || log_warn "psutil Android prebuild falló — el install principal puede fallar"
    fi
  fi

  # Intentar perfiles en orden: termux-all → termux → base
  log_info "Instalando paquete Hermes (perfil .[termux-all])..."
  if "$PIP_PYTHON" -m pip install -e '.[termux-all]' -c constraints-termux.txt -q; then
    log_ok "Instalado con perfil .[termux-all]"
  else
    log_warn "Perfil termux-all falló, probando .[termux]..."
    if "$PIP_PYTHON" -m pip install -e '.[termux]' -c constraints-termux.txt -q; then
      log_ok "Instalado con perfil .[termux]"
    else
      log_warn "Perfil termux falló, probando instalación base..."
      if "$PIP_PYTHON" -m pip install -e '.' -c constraints-termux.txt -q; then
        log_ok "Instalado con perfil base"
      else
        log_error "La instalación de paquetes falló en los 3 perfiles"
        log_info "Verifica los paquetes del sistema:"
        log_info "  pkg install clang rust make pkg-config libffi openssl"
        exit 1
      fi
    fi
  fi
  mark_done "deps"
fi
echo ""

# ════════════════════════════════════════════
#  PASO 5 — CONFIGURAR COMANDO hermes en PATH
# ════════════════════════════════════════════
echo -e "  ${CYAN}${BOLD}[PASO 5/6]${NC} Configurando comando hermes en PATH..."
echo ""

HERMES_BIN="$INSTALL_DIR/venv/bin/hermes"

if [ ! -x "$HERMES_BIN" ]; then
  log_error "Binario hermes no encontrado en: $HERMES_BIN"
  log_info "La instalación de dependencias puede no haberse completado"
  exit 1
fi

# Crear shim en $PREFIX/bin (ya en PATH en Termux — igual que el instalador oficial)
# Usar shim en lugar de symlink para proteger contra PYTHONPATH/PYTHONHOME heredados
LINK_DIR="$TERMUX_PREFIX/bin"
rm -f "$LINK_DIR/hermes" 2>/dev/null || true
cat > "$LINK_DIR/hermes" << SHIM
#!/data/data/com.termux/files/usr/bin/bash
unset PYTHONPATH
unset PYTHONHOME
exec "$HERMES_BIN" "\$@"
SHIM
chmod +x "$LINK_DIR/hermes"
log_ok "Shim instalado → $LINK_DIR/hermes"

# Verificar que funciona
if hermes version &>/dev/null; then
  HM_VER=$(hermes version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  log_ok "hermes v${HM_VER:-?} accesible en PATH"
else
  log_warn "hermes no responde — verifica: hermes version"
fi
echo ""

# ════════════════════════════════════════════
#  PASO 6 — ARCHIVOS DE CONFIGURACIÓN
# ════════════════════════════════════════════
echo -e "  ${CYAN}${BOLD}[PASO 6/6]${NC} Preparando archivos de configuración..."
echo ""

mkdir -p "$HERMES_HOME"/{cron,sessions,logs,pairing,hooks,image_cache,audio_cache,memories,skills}

# ~/.hermes/.env — claves API
if [ ! -f "$HERMES_HOME/.env" ]; then
  if [ -f "$INSTALL_DIR/.env.example" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
    log_ok "Creado ~/.hermes/.env desde plantilla"
  else
    touch "$HERMES_HOME/.env"
    log_ok "Creado ~/.hermes/.env (vacío)"
  fi
else
  log_info "~/.hermes/.env ya existe — conservado"
fi
chmod 600 "$HERMES_HOME/.env" 2>/dev/null || true

# ~/.hermes/config.yaml
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
  if [ -f "$INSTALL_DIR/cli-config.yaml.example" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
    log_ok "Creado ~/.hermes/config.yaml desde plantilla"
  fi
else
  log_info "~/.hermes/config.yaml ya existe — conservado"
fi

# SOUL.md — personalidad del agente
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
  cat > "$HERMES_HOME/SOUL.md" << 'SOUL_EOF'
# Hermes Agent Persona
# Edita este archivo para personalizar el tono y estilo del agente.
# Se carga en cada mensaje — no requiere reinicio.
SOUL_EOF
  log_ok "Creado ~/.hermes/SOUL.md"
fi

# Skills bundled — sincronizar si el script existe
if [ -f "$INSTALL_DIR/tools/skills_sync.py" ]; then
  "$PIP_PYTHON" "$INSTALL_DIR/tools/skills_sync.py" 2>/dev/null \
    && log_ok "Skills sincronizadas en ~/.hermes/skills/" \
    || log_warn "sync de skills falló — se pueden sincronizar después con: hermes update"
fi

mark_done "config"
echo ""

# ════════════════════════════════════════════
#  REGISTRO EN STACK
# ════════════════════════════════════════════
HM_VER=$(hermes version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$HM_VER" ] && HM_VER="unknown"

# Limpiar entradas anteriores y escribir nuevas
grep -v "^hermes\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null || touch "$REGISTRY.tmp"
{
  echo "hermes.installed=true"
  echo "hermes.version=$HM_VER"
  echo "hermes.install_date=$(date +%Y-%m-%d)"
  echo "hermes.install_dir=$INSTALL_DIR"
  echo "hermes.model=no configurado"
} >> "$REGISTRY.tmp"
mv "$REGISTRY.tmp" "$REGISTRY"

# ════════════════════════════════════════════
#  WIZARD DE CONFIGURACIÓN (hermes setup)
#  Igual que openclaw → lanza el wizard
#  interactivo para configurar proveedor y API key
# ════════════════════════════════════════════
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║  ✓ Hermes Agent instalado correctamente ║"
echo "  ╠══════════════════════════════════════════╣"
echo -e "  ║  ${NC}Versión:  ${HM_VER}${CYAN}${BOLD}"
echo -e "  ║  ${NC}Código:   ${INSTALL_DIR}${CYAN}${BOLD}"
echo -e "  ║  ${NC}Config:   ${HERMES_HOME}/config.yaml${CYAN}${BOLD}"
echo -e "  ║  ${NC}API keys: ${HERMES_HOME}/.env${CYAN}${BOLD}"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ── Preguntar si lanzar wizard (igual que openclaw) ──────
echo -e "  Necesitas configurar un proveedor de IA para usar Hermes."
echo -e "  ${DIM}(OpenRouter, Anthropic, Ollama local, etc.)${NC}"
echo ""
echo -n "  ¿Configurar ahora con el wizard? (s/n): "
read -r SETUP_NOW < /dev/tty

if [ "$SETUP_NOW" = "s" ] || [ "$SETUP_NOW" = "S" ]; then
  echo ""
  echo -e "  ${CYAN}Lanzando hermes setup...${NC}"
  echo -e "  ${DIM}Selecciona tu proveedor con las flechas y configura las claves${NC}"
  echo ""
  cd "$INSTALL_DIR"
  "$PIP_PYTHON" -m hermes_cli.main setup < /dev/tty || hermes setup < /dev/tty || true
  echo ""
  # Refrescar versión y modelo en registry tras wizard
  HM_VER_POST=$(hermes version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$HM_VER_POST" ] && {
    sed -i "s/^hermes\.version=.*/hermes.version=$HM_VER_POST/" "$REGISTRY" 2>/dev/null || true
  }
else
  echo ""
  echo -e "  ${DIM}Configura después con: hermes setup${NC}"
  echo -e "  ${DIM}O desde el menú: Servicios → Hermes → [7] Wizard${NC}"
fi

echo ""
echo -e "  ${GREEN}${BOLD}Hermes listo.${NC} Úsalo con: hermes"
echo -e "  ${DIM}Desde el menú: Servicios → Hermes → [1] Abrir Hermes${NC}"
echo ""

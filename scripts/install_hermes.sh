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

# ── Limpiar env heredado que rompe pip en sesiones anidadas ──
[ -n "${PYTHONPATH:-}"  ] && unset PYTHONPATH
[ -n "${PYTHONHOME:-}"  ] && unset PYTHONHOME
export UV_NO_CONFIG=1

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Modo silencioso (invocado desde menu.sh, confirmación ya hecha ahí) ──
SILENT_MODE=false
for _arg in "$@"; do [ "$_arg" = "--silent" ] && SILENT_MODE=true; done

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
  if $SILENT_MODE; then
    log_info "Modo silencioso — actualizando instalación existente (no destructivo)"
    REINST_OPT="2"
  else
    echo ""
    echo -e "  ${BOLD}[1]${NC} Reinstalar (borra venv y clona de nuevo)"
    echo -e "  ${BOLD}[2]${NC} Actualizar (hermes update)"
    echo -e "  ${BOLD}[b]${NC} Cancelar"
    echo ""; echo -n "  Opción: "
    read -r REINST_OPT < /dev/tty
  fi
  case "$REINST_OPT" in
    2)
      echo ""
      _HM_VER_BEFORE=$(hermes version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      log_info "Versión actual: ${_HM_VER_BEFORE:-desconocida}"
      log_info "Ejecutando hermes update..."
      hermes update < /dev/tty
      echo ""
      # Capturar versión nueva y actualizar registry
      _HM_VER_AFTER=$(hermes version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      [ -n "$_HM_VER_AFTER" ] && {
        _HM_DATE_U=$(python3 -c "from datetime import datetime; print(datetime.now().strftime('%Y-%m-%d'))" 2>/dev/null || date +%Y-%m-%d)
        _TMP_R="$REGISTRY.tmp"
        grep -v "^hermes\.version=\|^hermes\.install_date=" "$REGISTRY" > "$_TMP_R" 2>/dev/null || touch "$_TMP_R"
        echo "hermes.version=$_HM_VER_AFTER" >> "$_TMP_R"
        echo "hermes.install_date=$_HM_DATE_U" >> "$_TMP_R"
        mv "$_TMP_R" "$REGISTRY"
      }
      log_ok "Actualización completada"
      echo -e "  Antes: ${_HM_VER_BEFORE:-?}  →  Ahora: ${_HM_VER_AFTER:-?}"
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
#  ELEGIR VERSIÓN DE PYTHON PARA EL VENV
#  hermes-agent exige Python <3.14 (ver su pyproject.toml) — Termux
#  ahora empaqueta 3.14.6 por defecto, lo que rompe la instalación
#  oficial (ver docs/BUGS_PERSISTENTES_2026-07-26.md e issues
#  NousResearch/hermes-agent #71331, #59877, #48723). No hay
#  workaround oficial documentado para esto — es experimental.
# ════════════════════════════════════════════
HERMES_PYTHON_MODE="oficial"
if $SILENT_MODE; then
  HERMES_PYTHON_MODE="${HERMES_PYTHON_MODE_ENV:-oficial}"
else
  echo -e "  ${BOLD}¿Qué versión de Python usar para Hermes?${NC}"; echo ""
  echo -e "  ${GREEN}[1]${NC} Oficial ${DIM}(Python del sistema — falla si Termux trae 3.14+)${NC}"
  echo -e "  [2] Local/venv ${DIM}(intenta una versión <3.14 vía TUR — EXPERIMENTAL, sin soporte oficial)${NC}"
  echo ""; echo -n "  Opción [1/2]: "
  read -r _PY_MODE_OPT < /dev/tty
  [ "$_PY_MODE_OPT" = "2" ] && HERMES_PYTHON_MODE="local"
fi
echo ""

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
  PYTHON_PATH=""
  if [ "$HERMES_PYTHON_MODE" = "local" ]; then
    log_info "Modo local/venv: buscando un Python <3.14 compatible (experimental, vía TUR)..."
    for _cand in python3.13 python3.12 python3.11; do
      if command -v "$_cand" >/dev/null 2>&1; then
        PYTHON_PATH=$(command -v "$_cand")
        log_ok "Encontrado ya instalado: $_cand"
        break
      fi
    done
    if [ -z "$PYTHON_PATH" ]; then
      log_info "Ninguno instalado — habilitando TUR e intentando instalar uno..."
      pkg install -y tur-repo >/dev/null 2>&1
      pkg update -y >/dev/null 2>&1
      for _cand in python3.13 python3.12 python3.11; do
        if pkg install -y "$_cand" >/dev/null 2>&1 && command -v "$_cand" >/dev/null 2>&1; then
          PYTHON_PATH=$(command -v "$_cand")
          log_ok "Instalado desde TUR: $_cand"
          break
        fi
      done
    fi
    if [ -z "$PYTHON_PATH" ]; then
      log_warn "No se encontró ningún Python <3.14 vía TUR — usando la versión oficial del sistema como respaldo"
    fi
  fi
  if [ -z "$PYTHON_PATH" ]; then
    PYTHON_PATH=$(command -v python 2>/dev/null || command -v python3 2>/dev/null)
  fi
  if [ -z "$PYTHON_PATH" ]; then
    log_error "Python no encontrado — instala con: pkg install python"
    exit 1
  fi

  PYTHON_VER=$("$PYTHON_PATH" --version 2>/dev/null)
  log_info "Python detectado: $PYTHON_VER"

  # Recrear venv limpio
  [ -d "venv" ] && rm -rf venv
  "$PYTHON_PATH" -m venv venv || { log_error "No se pudo crear el virtualenv"; exit 1; }
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
  "$PIP_PYTHON" -m pip install --upgrade pip setuptools wheel -q \
    || log_warn "No se pudo actualizar pip/setuptools/wheel — continuando con las versiones actuales"

  # psutil y cryptography vía pkg (binarios ARM64 precompilados de Termux) — evita que
  # pip intente compilarlos desde fuente dentro del venv (build nativo/Rust, lento o
  # directamente falla en Android). Patrón confirmado en core-termux-main (proyecto de
  # referencia): su install.sh de hermes-agent instala python-psutil/python-cryptography
  # vía pkg ANTES de correr pip, exactamente por este motivo.
  log_info "Verificando psutil/cryptography del sistema (evita compilar en el venv)..."
  _HERMES_PKG_DEPS=()
  python -c "import psutil" &>/dev/null || _HERMES_PKG_DEPS+=("python-psutil")
  python -c "import cryptography" &>/dev/null || _HERMES_PKG_DEPS+=("python-cryptography")
  if [ "${#_HERMES_PKG_DEPS[@]}" -gt 0 ]; then
    pkg install -y "${_HERMES_PKG_DEPS[@]}" \
      || log_warn "No se pudieron instalar algunos paquetes del sistema: ${_HERMES_PKG_DEPS[*]}"
  fi

  # Symlink de psutil/cryptography del sistema dentro del venv — el venv no ve el
  # site-packages del sistema por defecto, así que sin esto pip los reconstruiría ahí
  # de todas formas. Solo aplica si la versión de Python del venv coincide con la del
  # sistema (si HERMES_PYTHON_MODE=local usa una versión distinta, el check de abajo
  # simplemente no encuentra coincidencia y no hace nada — no rompe nada).
  _PY_VER_SHORT=$("$PIP_PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
  if [ -n "$_PY_VER_SHORT" ]; then
    _VENV_SITE="$INSTALL_DIR/venv/lib/python${_PY_VER_SHORT}/site-packages"
    _SYS_SITE="$TERMUX_PREFIX/lib/python${_PY_VER_SHORT}/site-packages"
    for _pkgname in psutil cryptography; do
      if [ -d "$_SYS_SITE/$_pkgname" ] && [ -d "$_VENV_SITE" ] && [ ! -e "$_VENV_SITE/$_pkgname" ]; then
        ln -s "$_SYS_SITE/$_pkgname" "$_VENV_SITE/$_pkgname" 2>/dev/null
      fi
    done
  fi

  # psutil no funciona en Android — requiere parche previo
  # El script install_psutil_android.py está incluido en el repo oficial
  # NOTA: sys.platform en CPython de Termux siempre reporta "linux", nunca "android" —
  # se detecta Termux directamente en vez de confiar en sys.platform (antes esta condición
  # nunca era verdadera y el parche de psutil jamás se aplicaba)
  if [ -d /data/data/com.termux ]; then
    log_info "Android Python detectado — pre-compilando psutil..."
    if [ -f "$INSTALL_DIR/scripts/install_psutil_android.py" ]; then
      "$PIP_PYTHON" "$INSTALL_DIR/scripts/install_psutil_android.py" \
        --pip "$PIP_PYTHON -m pip" 2>/dev/null \
        || log_warn "psutil Android prebuild falló — el install principal puede fallar"
    fi
  fi

  # --ignore-requires-python: fuerza a pip a ignorar el gate de versión que hermes-agent
  # declara en su pyproject.toml (<3.14,>=3.11) — necesario porque Termux ya empaqueta
  # Python 3.14 por defecto. Mismo mecanismo usado como último recurso en core-termux-main
  # (proyecto de referencia). Riesgo real, no ocultarlo: esto solo evita el chequeo de
  # METADATA de pip — si el código de hermes-agent usa algo removido en 3.12+/3.14+
  # (ej. distutils), la instalación puede pasar pero fallar en runtime. No hay forma de
  # confirmar esto sin probarlo en un dispositivo real.
  # Intentar perfiles en orden: termux-all → termux → base
  log_info "Instalando paquete Hermes (perfil .[termux-all])..."
  if "$PIP_PYTHON" -m pip install --ignore-requires-python -e '.[termux-all]' -c constraints-termux.txt -q; then
    log_ok "Instalado con perfil .[termux-all]"
  else
    log_warn "Perfil termux-all falló, probando .[termux]..."
    if "$PIP_PYTHON" -m pip install --ignore-requires-python -e '.[termux]' -c constraints-termux.txt -q; then
      log_ok "Instalado con perfil .[termux]"
    else
      log_warn "Perfil termux falló, probando instalación base..."
      if "$PIP_PYTHON" -m pip install --ignore-requires-python -e '.' -c constraints-termux.txt -q; then
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
_HM_DATE=$(python3 -c "from datetime import datetime; print(datetime.now().strftime('%Y-%m-%d'))" 2>/dev/null || date +%Y-%m-%d)
grep -v "^hermes\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null || touch "$REGISTRY.tmp"
{
  echo "hermes.installed=true"
  echo "hermes.version=$HM_VER"
  echo "hermes.install_date=$_HM_DATE"
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
if $SILENT_MODE; then
  log_warn "Modo silencioso — omitiendo wizard, ejecuta 'hermes setup' manualmente después"
  SETUP_NOW="n"
else
  echo -e "  Necesitas configurar un proveedor de IA para usar Hermes."
  echo -e "  ${DIM}(OpenRouter, Anthropic, Ollama local, etc.)${NC}"
  echo ""
  echo -n "  ¿Configurar ahora con el wizard? (s/n): "
  read -r SETUP_NOW < /dev/tty
fi

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

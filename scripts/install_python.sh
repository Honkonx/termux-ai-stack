#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_python.sh
#  Instala Python + SQLite en Termux nativo (ARM64, sin root)
#
#  USO STANDALONE:
#    bash install_python.sh
#
#  QUÉ HACE:
#    ✅ PASO 1 — Actualiza Termux
#    ✅ PASO 2 — Instala Python 3 vía pkg
#    ✅ PASO 3 — Instala SQLite CLI
#    ✅ PASO 4 — Configura aliases en .bashrc
#    ✅ PASO 5 — Instala Pillow + libjpeg-turbo (visión)
#    ✅ PASO 6 — Instala numpy + scipy via pkg ARM64
#    ✅ PASO 7 — Descarga scripts (sports + trading + bots)
#    ✅ PASO 8 — Actualiza registry
#
#  ESTRUCTURA EN TERMUX:
#    ~/sports/scripts/   ~/sports/db/
#    ~/trading/scripts/  ~/trading/db/
#    ~/bots/scripts/     ~/bots/db/
#
#  NOTA:
#    Los .db los crean los scripts Python al primer uso.
#    No se suben a GitHub — se generan en el dispositivo.
#
#  VERSIÓN: 2.0.0 | Mayo 2026
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
CHECKPOINT="$HOME/.install_python_checkpoint"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Función: actualizar registry ─────────────────────────────
update_registry() {
  local py_version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^python\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
python.installed=true
python.version=$py_version
python.install_date=$date_now
python.location=termux_native
python.sqlite=true
python.pillow=true
python.numpy=true
python.scipy=true
python.sports=true
python.bots=true
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → $REGISTRY"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · Python Installer        ║
  ║   Termux ARM64 · sin root · v2.0.0          ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado ───────────────────────────
if command -v python3 &>/dev/null; then
  CURRENT_VER=$(python3 --version 2>/dev/null | awk '{print $2}')
  echo -e "${GREEN}  ✓ Python ya está instalado${NC}"
  echo -e "  Versión actual: ${CYAN}${CURRENT_VER}${NC}"
  echo ""
  echo -n "  ¿Reinstalar/actualizar todos los componentes? (s/n): "
  read -r REINSTALL < /dev/tty
  if [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ]; then
    info "Nada que hacer. Saliendo."
    exit 0
  fi
  rm -f "$CHECKPOINT"
fi

# ── Lista completa de lo que se instalará ────────────────────
echo ""
echo -e "${BOLD}  Este script instalará los siguientes componentes:${NC}"
echo ""
echo "  SISTEMA:"
echo "  ▸ Python 3 vía pkg"
echo "  ▸ pip (incluido con Python)"
echo "  ▸ sqlite3 CLI (cliente interactivo)"
echo "  ▸ módulo sqlite3 (incluido en Python)"
echo ""
echo "  LIBRERÍAS:"
echo "  ▸ libjpeg-turbo + libpng + zlib (dependencias imagen)"
echo "  ▸ Pillow (procesamiento de imágenes — vision_bot.py)"
echo "  ▸ numpy (binarios ARM64 precompilados)"
echo "  ▸ scipy (motor Poisson bivariante — pronostico.py)"
echo ""
echo "  SCRIPTS (descarga dinámica desde GitHub):"
echo "  ▸ python/sports/   → ~/sports/scripts/"
echo "  ▸ python/trading/  → ~/trading/scripts/"
echo "  ▸ python/bots/     → ~/bots/scripts/"
echo ""
echo "  ESTRUCTURA DE DIRECTORIOS:"
echo "  ▸ ~/sports/{scripts,db}   ~/trading/{scripts,db}   ~/bots/{scripts,db}"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRM < /dev/tty
if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
  echo "  Cancelado."
  exit 0
fi

# ============================================================
# PASO 1 — Actualizar Termux
# ============================================================
titulo "PASO 1 — Verificando Termux"

if [ -n "$ANDROID_SERVER_READY" ]; then
  log "Termux ya preparado por el maestro [skip]"
elif check_done "termux_update"; then
  log "Termux ya verificado [checkpoint]"
else
  info "Actualizando Termux..."

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
        log "Mirror OK: $m"
        OK=1
        break
      fi
    done
    if [ "$OK" = "0" ]; then
      error "Todos los mirrors fallaron. Verifica tu conexión."
    fi
  fi

  log "Termux actualizado"
  mark_done "termux_update"
fi

# ============================================================
# PASO 2 — Instalar Python
# ============================================================
titulo "PASO 2 — Instalando Python"

if check_done "python_install"; then
  log "Python ya instalado [checkpoint]"
else
  info "Instalando Python vía pkg..."
  pkg install python -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    error "Error instalando Python. Verifica conexión."

  if ! command -v python3 &>/dev/null; then
    error "python3 no disponible después de instalar. Intenta: pkg install python"
  fi

  PY_VER=$(python3 --version 2>/dev/null | awk '{print $2}')
  log "Python instalado: $PY_VER"
  mark_done "python_install"
fi

# ============================================================
# PASO 3 — Instalar SQLite CLI
# ============================================================
titulo "PASO 3 — Instalando SQLite CLI"

if check_done "sqlite_install"; then
  log "SQLite CLI ya instalado [checkpoint]"
else
  info "Instalando sqlite CLI vía pkg..."
  pkg install sqlite -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    warn "sqlite CLI no instalado — el módulo Python sqlite3 sigue disponible"

  if python3 -c "import sqlite3; print(sqlite3.sqlite_version)" 2>/dev/null; then
    log "Módulo Python sqlite3 OK"
  else
    warn "Módulo sqlite3 no disponible — puede requerir reinicio de Termux"
  fi

  mark_done "sqlite_install"
fi

# ============================================================
# PASO 4 — Aliases en .bashrc
# ============================================================
titulo "PASO 4 — Configurando aliases"

if check_done "python_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"

  if [ -f "$BASHRC" ]; then
    grep -v "py3\|pip3-install\|sqlite-n8n\|# Python · aliases" \
      "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
  fi

  cat >> "$BASHRC" << 'ALIASES'

# ════════════════════════════════
#  Python · aliases
# ════════════════════════════════
alias py3='python3'
alias pip3-install='pip install --break-system-packages'
alias sqlite-n8n='proot-distro login debian -- sqlite3 /root/.n8n/database.sqlite'
ALIASES

  log "Aliases agregados a ~/.bashrc"
  mark_done "python_aliases"
fi

# ============================================================
# PASO 5 — Pillow + dependencias de visión
# ============================================================
titulo "PASO 5 — Instalando Pillow (visión)"

if check_done "pillow_install"; then
  log "Pillow ya instalado [checkpoint]"
else
  info "Instalando librerías de imagen..."
  pkg install libjpeg-turbo libpng zlib -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    warn "Algunas librerías tuvieron advertencias — Pillow puede funcionar igual"

  info "Instalando Pillow..."
  pip install Pillow --break-system-packages || \
    warn "Error instalando Pillow — instala manualmente: pip install Pillow --break-system-packages"

  if python3 -c "from PIL import Image; print('OK')" 2>/dev/null; then
    log "Pillow instalado y verificado"
  else
    warn "Pillow no verificado — puede requerir reinicio de Termux"
  fi

  mark_done "pillow_install"
fi

# ============================================================
# PASO 6 — numpy + scipy (binarios ARM64 precompilados)
# ============================================================
titulo "PASO 6 — Instalando numpy + scipy"

if check_done "scipy_install"; then
  log "numpy + scipy ya instalados [checkpoint]"
else
  info "Instalando via pkg (binarios ARM64 precompilados — NO pip)..."
  pkg install python-numpy python-scipy -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    warn "Error en la instalación — el bot deportivo usará math puro como fallback"

  if python3 -c "import numpy, scipy; print('OK')" 2>/dev/null; then
    log "numpy + scipy instalados y verificados"
  else
    warn "No se pudieron verificar — el submenú usará motor math puro"
  fi

  mark_done "scipy_install"
fi

# ============================================================
# PASO 7 — Descargar scripts (sports + trading + bots)
# ============================================================
titulo "PASO 7 — Descargando scripts"

REPO_API="https://api.github.com/repos/Honkonx/termux-ai-stack/contents/python"
REPO_RAW="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/python"

SPORTS_SCRIPTS_DIR="$HOME/sports/scripts"
TRADING_SCRIPTS_DIR="$HOME/trading/scripts"
BOTS_SCRIPTS_DIR="$HOME/bots/scripts"

if check_done "all_scripts"; then
  log "Scripts ya descargados [checkpoint]"
else
  # Crear estructura de directorios
  mkdir -p "$HOME/sports/scripts"  "$HOME/sports/db" \
           "$HOME/sports/logs"     "$HOME/sports/models" \
           "$HOME/trading/scripts" "$HOME/trading/db" \
           "$HOME/bots/scripts"    "$HOME/bots/db"
  log "Estructura de directorios creada"

  # ── Función: descargar todos los .py de una carpeta del repo ──
  descargar_carpeta() {
    local carpeta="$1"
    local destino="$2"
    local ok=0
    local fail=0

    echo ""
    echo -e "  ${CYAN}▸ python/${carpeta}/ → ${destino}${NC}"

    local lista
    lista=$(curl -fsSL "$REPO_API/$carpeta" 2>/dev/null || \
            wget -qO- "$REPO_API/$carpeta" 2>/dev/null)

    if [ -z "$lista" ]; then
      warn "No se pudo consultar la API para python/$carpeta"
      return
    fi

    local archivos
    archivos=$(echo "$lista" | \
      grep -o '"name": *"[^"]*\.py"' | \
      grep -o '"[^"]*\.py"' | \
      tr -d '"')

    if [ -z "$archivos" ]; then
      info "Sin archivos .py en python/$carpeta — carpeta vacía o no creada aún"
      return
    fi

    for script in $archivos; do
      echo -n "    $script... "
      local TMP="$destino/${script}.tmp"
      curl -fsSL "$REPO_RAW/$carpeta/$script" -o "$TMP" 2>/dev/null || \
        wget -q "$REPO_RAW/$carpeta/$script" -O "$TMP" 2>/dev/null
      if [ -f "$TMP" ] && [ -s "$TMP" ]; then
        mv "$TMP" "$destino/$script"
        chmod +x "$destino/$script"
        echo -e "${GREEN}✓${NC}"
        ok=$((ok + 1))
      else
        rm -f "$TMP"
        echo -e "${RED}✗${NC}"
        fail=$((fail + 1))
      fi
    done

    [ $ok -gt 0 ]   && log "$ok scripts descargados en $destino"
    [ $fail -gt 0 ] && warn "$fail scripts fallaron — descarga manual: github.com/Honkonx/termux-ai-stack"
  }

  descargar_carpeta "sports"  "$SPORTS_SCRIPTS_DIR"
  descargar_carpeta "trading" "$TRADING_SCRIPTS_DIR"
  descargar_carpeta "bots"    "$BOTS_SCRIPTS_DIR"

  # ── Init BD sports ────────────────────────────────────────
  if [ -f "$SPORTS_SCRIPTS_DIR/db_query.py" ]; then
    echo ""
    echo -n "  Inicializando BD bot deportivo... "
    python3 "$SPORTS_SCRIPTS_DIR/db_query.py" verificar_acceso '{"user_id":"init"}' \
      > /dev/null 2>&1 \
      && echo -e "${GREEN}✓ BD creada${NC}" \
      || echo -e "${YELLOW}omitido (se crea al primer uso)${NC}"
  fi

  # ── Init BD trading ───────────────────────────────────────
  if [ -f "$TRADING_SCRIPTS_DIR/signal_bot.py" ]; then
    echo -n "  Inicializando BD trading... "
    python3 "$TRADING_SCRIPTS_DIR/signal_bot.py" init 2>/dev/null \
      && echo -e "${GREEN}✓${NC}" \
      || echo -e "${YELLOW}omitido (se crea al primer uso)${NC}"
  fi

  # ── Verificar scipy ───────────────────────────────────────
  if python3 -c "import numpy, scipy" 2>/dev/null; then
    log "Motor scipy disponible — pronostico.py usará Poisson bivariante"
  else
    warn "scipy no verificado — pronostico.py usará motor math puro"
  fi

  # ── Aviso ruta antigua ────────────────────────────────────
  if [ -d "$HOME/python/trading" ]; then
    warn "Ruta antigua detectada: ~/python/trading/ — ya no se usa"
    info "Elimínala con: rm -rf ~/python/trading"
  fi

  mark_done "all_scripts"
fi

# ============================================================
# PASO 8 — Actualizar registry
# ============================================================
titulo "PASO 8 — Actualizando registry"

PY_VER=$(python3 --version 2>/dev/null | awk '{print $2}')
[ -z "$PY_VER" ] && PY_VER="unknown"
update_registry "$PY_VER"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║       Python instalado con éxito ✓          ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  Python:  $(python3 --version 2>/dev/null)"
echo "  pip:     $(pip --version 2>/dev/null | awk '{print $1, $2}')"
echo "  sqlite3: $(python3 -c 'import sqlite3; print(sqlite3.sqlite_version)' 2>/dev/null)"
echo ""
echo "  DIRECTORIOS CREADOS:"
echo "  ~/sports/{scripts,db}   ~/trading/{scripts,db}   ~/bots/{scripts,db}"
echo ""
echo "  COMANDOS:"
echo "  python3                                    → REPL interactivo"
echo "  pip install --break-system-packages X      → instalar paquete"
echo "  sqlite3 archivo.db                         → CLI interactivo"
echo "  sqlite-n8n                                 → BD interna de n8n"
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para activar los aliases${NC}"
echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}  ║  💡 Stack IA completo — dependencias        ║${NC}"
echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  ▸ Ollama  → modelos IA local (:11434)  — menú opción [3]"
echo "  ▸ n8n     → bots Telegram (:5678)      — menú opción [1]"
echo ""

# Limpiar checkpoint
rm -f "$CHECKPOINT"

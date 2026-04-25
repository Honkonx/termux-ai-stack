#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_python.sh
#  Instala Python + SQLite en Termux nativo (ARM64, sin root)
#
#  USO STANDALONE:
#    bash install_python.sh
#
#  QUÉ HACE:
#    ✅ Verifica si Python ya está instalado
#    ✅ Instala Python vía pkg (incluye pip y sqlite3)
#    ✅ Instala sqlite CLI separado (pkg install sqlite)
#    ✅ PASO 6 — Pillow + deps visión (opcional, para vision_bot.py)
#    ✅ Escribe estado al registry ~/.android_server_registry
#    ✅ Agrega aliases a .bashrc
#    ✅ Info sobre dependencias del stack IA completo
#
#  NOTA:
#    sqlite3 viene incluido en Python — no requiere instalación
#    extra. pkg install sqlite agrega el CLI interactivo.
#
#  VERSIÓN: 1.1.0 | Abril 2026
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
  ║   Termux ARM64 · sin root                   ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado ───────────────────────────
if command -v python3 &>/dev/null; then
  CURRENT_VER=$(python3 --version 2>/dev/null | awk '{print $2}')
  echo -e "${GREEN}  ✓ Python ya está instalado${NC}"
  echo -e "  Versión actual: ${CYAN}${CURRENT_VER}${NC}"
  echo ""
  echo -n "  ¿Reinstalar/actualizar? (s/n): "
  read -r REINSTALL < /dev/tty
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
fi

echo ""
echo "  Este script instalará:"
echo "  ▸ Python 3 vía pkg"
echo "  ▸ pip (incluido con Python)"
echo "  ▸ sqlite3 CLI (cliente interactivo)"
echo "  ▸ módulo sqlite3 (incluido en Python)"
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

  # Verificar que funcionó
  if ! command -v python3 &>/dev/null; then
    error "python3 no disponible después de instalar. Intenta manualmente: pkg install python"
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

  # Verificar módulo Python sqlite3
  if python3 -c "import sqlite3; print(sqlite3.sqlite_version)" 2>/dev/null; then
    log "Módulo Python sqlite3 OK"
  else
    warn "Módulo sqlite3 no disponible en Python — puede requerir reinstalación"
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

  # Limpiar aliases anteriores
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
# PASO 5 — Dependencias visión (Pillow) — OPCIONAL
# ============================================================
titulo "PASO 5 — Dependencias visión (opcional)"

if check_done "pillow_install"; then
  log "Pillow ya instalado [checkpoint]"
else
  echo "  Pillow + libjpeg-turbo son necesarios para:"
  echo "  ▸ vision_bot.py  → procesar imágenes en bots Telegram"
  echo "  ▸ moondream:1.8b → análisis visual con Ollama"
  echo ""
  echo "  Si no usas visión puedes omitirlo. Se puede instalar"
  echo "  después desde el menú principal → Python → Submenú."
  echo ""
  echo -n "  ¿Instalar dependencias de visión? (s/n): "
  read -r INST_PILLOW < /dev/tty
  if [ "$INST_PILLOW" = "s" ] || [ "$INST_PILLOW" = "S" ]; then
    info "Instalando librerías de imagen..."
    pkg install libjpeg-turbo libpng zlib -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      warn "Algunas librerías tuvieron advertencias — Pillow puede funcionar igual"

    info "Instalando Pillow..."
    pip install Pillow --break-system-packages || \
      warn "Error instalando Pillow — instala manualmente después"

    if python3 -c "from PIL import Image; print('OK')" 2>/dev/null; then
      log "Pillow instalado y verificado"
      sed -i '/^python\.pillow=/d' "$REGISTRY" 2>/dev/null
      echo "python.pillow=true" >> "$REGISTRY"
    else
      warn "Pillow no verificado — puede requerir reinicio de Termux"
      echo "python.pillow=false" >> "$REGISTRY"
    fi
    mark_done "pillow_install"
  else
    info "Visión omitida — instala después con:"
    info "  pkg install libjpeg-turbo && pip install Pillow --break-system-packages"
    echo "python.pillow=false" >> "$REGISTRY"
    mark_done "pillow_install"
  fi
fi

# ============================================================
# PASO 6 — Actualizar registry
# ============================================================
titulo "PASO 6 — Actualizando registry"

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
echo "  COMANDOS:"
echo "  python3                    → REPL interactivo"
echo "  pip install X              → instalar paquete"
echo "  pip install --break-system-packages X  → si pip rechaza"
echo "  sqlite3 archivo.db         → CLI interactivo"
echo "  sqlite-n8n                 → BD interna de n8n"
echo ""
echo -e "${CYAN}  → Cierra y reabre Termux para activar los aliases${NC}"
echo ""

# ── Info dependencias del stack IA ───────────────────────────
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}  ║  💡 Stack IA completo — dependencias        ║${NC}"
echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Python + SQLite es la base del stack."
echo "  Para el stack IA completo también necesitas:"
echo ""
echo "  ▸ Ollama     → modelos de IA local (:11434)"
echo "               instala desde el menú: opción [3]"
echo ""
echo "  ▸ n8n        → bots Telegram y automatización (:5678)"
echo "               requiere Python + Ollama para los workflows WF1-WF4"
echo "               instala desde el menú: opción [1]"
echo ""
echo "  Sin Ollama los bots n8n no tienen IA."
echo "  Sin Python los scripts de visión no funcionan."
echo ""

# Limpiar checkpoint
rm -f "$CHECKPOINT"

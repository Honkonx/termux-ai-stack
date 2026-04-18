#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  android-server · install_ollama.sh
#  Instala Ollama en Termux nativo (ARM64, sin root)
#
#  USO STANDALONE:
#    bash install_ollama.sh
#
#  USO VÍA MAESTRO (cuando repo sea público):
#    bash <(curl -fsSL https://raw.githubusercontent.com/TU_USUARIO/android-server/main/modules/install_ollama.sh)
#
#  QUÉ HACE:
#    ✅ Actualiza Termux (solo si no lo hizo el maestro)
#    ✅ Verifica si Ollama ya está instalado
#    ✅ Instala Ollama vía pkg (método estable)
#    ✅ Ofrece descargar un modelo inicial
#    ✅ Crea script de inicio con tmux
#    ✅ Escribe estado al registry ~/.android_server_registry
#    ✅ Agrega aliases a .bashrc
#
#  RESPONSABILIDAD DEL MAESTRO (instalar.sh):
#    ⏭  Tema visual (GitHub Dark + JetBrains Mono)
#    ⏭  termux.properties + extra-keys
#    ⏭  pkg update base → exporta ANDROID_SERVER_READY=1
#
#  PROBLEMA CONOCIDO:
#    Ollama v0.11.5+ tiene regresión de rendimiento en Termux ARM64
#    (bug #27290 en termux-packages). Pendiente fix oficial.
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
CHECKPOINT="$HOME/.install_ollama_checkpoint"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Función: actualizar registry ─────────────────────────────
update_registry() {
  local version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)

  if [ ! -f "$REGISTRY" ]; then
    touch "$REGISTRY"
  fi

  local tmp="$REGISTRY.tmp"
  grep -v "^ollama\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"

  cat >> "$tmp" << EOF
ollama.installed=true
ollama.version=$version
ollama.install_date=$date_now
ollama.commands=ollama serve,ollama run,ollama list,ollama pull,ollama rm
ollama.port=11434
ollama.location=termux_native
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → $REGISTRY"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   android-server · Ollama Installer         ║
  ║   Termux ARM64 · sin root                   ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado ───────────────────────────
if command -v ollama &>/dev/null; then
  CURRENT_VER=$(ollama --version 2>/dev/null | head -1)
  echo -e "${GREEN}  ✓ Ollama ya está instalado${NC}"
  echo -e "  Versión actual: ${CYAN}${CURRENT_VER}${NC}"
  echo ""
  echo -n "  ¿Reinstalar/actualizar? (s/n): "
  read -r REINSTALL
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
fi

echo ""
echo "  Este script instalará:"
echo "  ▸ Ollama vía pkg (método funcional en Termux ARM64)"
echo "  ▸ Puerto: 11434"
echo "  ▸ API compatible con OpenAI"
echo "  ▸ Script de inicio con tmux"
echo "  ▸ Aliases: ollama-start, ollama-stop, ollama-status"
echo ""
echo -e "  ${YELLOW}⚠️  NOTA DE RENDIMIENTO:${NC}"
echo "  La versión actual de pkg puede tener respuestas lentas (bug conocido)."
echo "  Funciona correctamente — solo más lento en algunos dispositivos."
echo "  Estado: pendiente fix oficial en termux-packages."
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRM
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 1 — Actualizar Termux (condicional)
# ============================================================
titulo "PASO 1 — Verificando Termux"

if [ -n "$ANDROID_SERVER_READY" ]; then
  log "Termux ya preparado por el maestro [skip]"

  # Aunque el maestro haya actualizado, tmux es crítico para ollama-start
  if ! command -v tmux &>/dev/null; then
    info "Instalando tmux..."
    pkg install tmux -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"
    log "tmux instalado"
  fi

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

  for dep in curl wget; do
    if ! command -v "$dep" &>/dev/null; then
      info "Instalando $dep..."
      pkg install "$dep" -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>/dev/null
    fi
  done

  if ! command -v tmux &>/dev/null; then
    info "Instalando tmux..."
    pkg install tmux -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"
    log "tmux instalado"
  fi

  log "Termux actualizado"
  mark_done "termux_update"
fi

# ============================================================
# PASO 2 — Instalar Ollama
# ============================================================
titulo "PASO 2 — Instalando Ollama"

if check_done "ollama_install"; then
  log "Ollama ya instalado [checkpoint]"
else
  info "Instalando Ollama vía pkg..."
  pkg install ollama -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || \
    error "Error instalando Ollama. Verifica conexión."
  log "Ollama instalado: $(ollama --version 2>/dev/null | head -1)"

  mark_done "ollama_install"
fi

# ============================================================
# PASO 3 — Crear script de inicio (ollama_start.sh)
# ============================================================
titulo "PASO 3 — Script de inicio"

if check_done "ollama_scripts"; then
  log "Scripts ya creados [checkpoint]"
else
  # Script de inicio en tmux
  cat > "$HOME/ollama_start.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
SESSION="ollama-server"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Ollama ya está corriendo en tmux sesión: $SESSION"
  echo "Para ver logs: tmux attach -t $SESSION"
  exit 0
fi

tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "ollama serve" Enter
sleep 2

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "✓ Ollama iniciado en puerto 11434"
  echo "  Sesión tmux: $SESSION"
  echo "  Para ver logs: tmux attach -t $SESSION (Ctrl+B D para salir)"
  echo "  Para detener: ollama-stop"
else
  echo "Error iniciando Ollama. Revisa logs con: tmux attach -t $SESSION"
fi
SCRIPT
  chmod +x "$HOME/ollama_start.sh"

  # Script de parada
  cat > "$HOME/ollama_stop.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
SESSION="ollama-server"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  echo "✓ Ollama detenido"
else
  echo "Ollama no estaba corriendo"
fi
SCRIPT
  chmod +x "$HOME/ollama_stop.sh"

  log "ollama_start.sh creado"
  log "ollama_stop.sh creado"
  mark_done "ollama_scripts"
fi

# ============================================================
# PASO 4 — Aliases en .bashrc
# ============================================================
titulo "PASO 4 — Configurando aliases"

if check_done "ollama_aliases"; then
  log "Aliases ya configurados [checkpoint]"
else
  BASHRC="$HOME/.bashrc"

  # Eliminar aliases anteriores de ollama
  if [ -f "$BASHRC" ]; then
    grep -v "ollama-start\|ollama-stop\|ollama-list\|ollama-run\|ollama-pull\|ollama-status\|OLLAMA_HOST" \
      "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
  fi

  cat >> "$BASHRC" << 'ALIASES'

# ════════════════════════════════
#  Ollama · aliases
# ════════════════════════════════
alias ollama-start='bash ~/ollama_start.sh'
alias ollama-stop='bash ~/ollama_stop.sh'
alias ollama-status='curl -s http://localhost:11434 && echo " (corriendo)" || echo "Ollama no responde en :11434"'
alias ollama-list='ollama list'
alias ollama-run='ollama run'
alias ollama-pull='ollama pull'
alias ollama-lan='OLLAMA_HOST=0.0.0.0 ollama serve'
ALIASES

  log "Aliases agregados a ~/.bashrc"
  mark_done "ollama_aliases"
fi

# ============================================================
# PASO 5 — Descargar modelo inicial (opcional)
# ============================================================
titulo "PASO 5 — Modelo inicial (opcional)"

echo "  Modelos recomendados para POCO F5 (12GB RAM):"
echo ""
echo "  [1] qwen:0.5b    ~395MB  — Más liviano, respuestas rápidas"
echo "  [2] qwen:1.8b    ~1.1GB  — Balance velocidad/calidad"
echo "  [3] phi3:mini    ~2.3GB  — Mejor calidad (recomendado si tienes tiempo)"
echo "  [4] llama3.2:1b  ~1.3GB  — Buena calidad, liviano"
echo "  [5] Omitir       — Lo haré después manualmente"
echo ""
echo -n "  Elige modelo [1-5]: "
read -r MODEL_CHOICE

SELECTED_MODEL=""
case "$MODEL_CHOICE" in
  1) SELECTED_MODEL="qwen:0.5b" ;;
  2) SELECTED_MODEL="qwen:1.8b" ;;
  3) SELECTED_MODEL="phi3:mini" ;;
  4) SELECTED_MODEL="llama3.2:1b" ;;
  *) SELECTED_MODEL="" ;;
esac

if [ -n "$SELECTED_MODEL" ]; then
  info "Iniciando servidor Ollama para descarga..."
  ollama serve &>/dev/null &
  OLLAMA_PID=$!
  sleep 3

  info "Descargando modelo: $SELECTED_MODEL"
  info "Esto puede tardar varios minutos dependiendo de tu conexión..."
  echo ""

  ollama pull "$SELECTED_MODEL"
  PULL_STATUS=$?

  kill $OLLAMA_PID 2>/dev/null || true

  if [ $PULL_STATUS -eq 0 ]; then
    log "Modelo $SELECTED_MODEL descargado"
  else
    warn "Error descargando modelo. Puedes hacerlo después con: ollama pull $SELECTED_MODEL"
  fi
else
  info "Modelo omitido. Puedes descargarlo después con: ollama pull qwen:0.5b"
fi

# ============================================================
# PASO 6 — Actualizar registry
# ============================================================
titulo "PASO 6 — Actualizando registry"

OLLAMA_VER=$(pkg show ollama 2>/dev/null | grep "^Version:" | awk '{print $2}')
[ -z "$OLLAMA_VER" ] && OLLAMA_VER=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$OLLAMA_VER" ] && OLLAMA_VER="unknown"

update_registry "$OLLAMA_VER"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║       Ollama instalado con éxito ✓          ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  Versión:   $(ollama --version 2>/dev/null | head -1)"
echo "  Puerto:    11434"
echo ""
echo "  COMANDOS:"
echo "  ollama-start              → inicia servidor en tmux"
echo "  ollama-stop               → detiene el servidor"
echo "  ollama-status             → verifica si responde"
echo "  ollama-list               → modelos instalados"
echo "  ollama run qwen:0.5b      → iniciar chat directo"
echo "  ollama pull phi3:mini     → descargar modelo"
echo "  ollama-lan                → exponer en red local (:11434)"
echo ""
echo "  API REST:"
echo "  curl http://localhost:11434/api/tags     → listar modelos"
echo "  curl http://localhost:11434/api/chat ... → chat"
echo ""
echo -e "${YELLOW}  IMPORTANTE:${NC}"
echo "  1. Cierra y reabre Termux para activar los aliases"
echo "  2. Inicia con: ollama-start"
echo "  3. La primera ejecución de un modelo tarda más"
echo ""
if [ -z "$ANDROID_SERVER_READY" ]; then
  echo -e "${CYAN}  TIP: ejecuta instalar.sh para aplicar tema visual${NC}"
  echo -e "${CYAN}       y configurar las teclas rápidas de Termux${NC}"
  echo ""
fi
echo -e "${CYAN}  → Cierra y reabre Termux, luego escribe: ollama-start${NC}"
echo ""

# Limpiar checkpoint
rm -f "$CHECKPOINT"

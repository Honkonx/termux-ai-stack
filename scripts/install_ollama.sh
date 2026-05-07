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
#    ✅ PASO 7 — Genera vision_bot.py, bot_utils.py, image_archive.py
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
#  VERSIÓN: 3.0.0 | Mayo 2026
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
  read -r REINSTALL < /dev/tty
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
fi

# ============================================================
# DETECCIÓN DE HARDWARE — GPU + CPU features
# ============================================================
titulo "DETECCIÓN DE HARDWARE"

detect_vulkan_type() {
  local vk_type=""
  if command -v vulkaninfo &>/dev/null; then
    vk_type=$(vulkaninfo 2>/dev/null | grep "deviceType" | head -1)
  fi
  [ -z "$vk_type" ] && \
    vk_type=$(LD_LIBRARY_PATH=/system/lib64 vulkaninfo 2>/dev/null \
      | grep "deviceType" | head -1)
  echo "$vk_type"
}

detect_cpu_features() {
  local features result="base"
  features=$(grep -m1 -i "^Features" /proc/cpuinfo 2>/dev/null)
  [ -z "$features" ] && features=$(grep -i "features" /proc/cpuinfo 2>/dev/null | head -1)

  # i8mm — multiplicación de matrices int8 (ARMv8.6+)
  echo "$features" | grep -q "i8mm" && result="i8mm"
  # dotprod — "asimddp" es el nombre ARM oficial de dotprod en kernels Android
  echo "$features" | grep -qE "dotprod|asimddp" && {
    [ "$result" = "base" ] && result="dotprod" || result="${result}+dotprod"
  }
  # sve — Scalable Vector Extension
  echo "$features" | grep -q "sve" && result="${result}+sve"
  echo "$result"
}

# detect_gpu — sin requerir vulkaninfo instalado
detect_gpu() {
  local info=""
  if command -v vulkaninfo &>/dev/null; then
    info=$(vulkaninfo 2>/dev/null | grep -i "deviceName" | head -1)
  fi
  if [ -z "$info" ]; then
    info=$(LD_LIBRARY_PATH=/system/lib64 vulkaninfo 2>/dev/null \
      | grep -i "deviceName" | head -1)
    [ -n "$info" ] && GPU_SRC="system_lib"
  fi

  if echo "$info" | grep -qi "adreno"; then
    echo "adreno"
    return
  elif echo "$info" | grep -qi "mali"; then
    echo "mali"
    return
  elif echo "$info" | grep -qi "swiftshader\|llvmpipe"; then
    echo "software"
    return
  elif [ -n "$info" ]; then
    echo "vulkan_system"
    return
  fi

  # Fallback sin vulkaninfo — getprop (más confiable que /proc/cpuinfo en HyperOS)
  local hw_prop
  hw_prop=$(getprop ro.hardware 2>/dev/null | tr '[:upper:]' '[:lower:]')
  [ -z "$hw_prop" ] && hw_prop=$(getprop ro.board.platform 2>/dev/null | tr '[:upper:]' '[:lower:]')

  if echo "$hw_prop" | grep -qE "^sm[0-9]|qualcomm|snapdragon"; then
    echo "adreno_no_vulkan"
  elif echo "$hw_prop" | grep -qE "^mt[0-9]|mediatek|dimensity|helio"; then
    echo "mali_no_vulkan"
  else
    # Último fallback: /proc/cpuinfo Hardware field
    local hw_cpu
    hw_cpu=$(grep -m1 "^Hardware" /proc/cpuinfo 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if echo "$hw_cpu" | grep -qE "qualcomm|snapdragon|sm[0-9]"; then
      echo "adreno_no_vulkan"
    elif echo "$hw_cpu" | grep -qE "mediatek|dimensity|helio|mt[0-9]"; then
      echo "mali_no_vulkan"
    else
      [ -e /dev/mali0 ] || [ -e /sys/class/misc/mali0 ] && echo "mali_no_vulkan" && return
      [ -e /dev/kgsl-3d0 ] && echo "adreno_no_vulkan" && return
      echo "none"
    fi
  fi
}

HW_GPU=$(detect_gpu)
HW_CPU=$(detect_cpu_features)
HW_VK_TYPE=$(detect_vulkan_type)

# Determinar modo recomendado
# CPU optimizada se ofrece siempre que haya i8mm o dotprod — independiente de GPU
HW_MODE="cpu_standard"
HW_GPU_AVAILABLE=false
[ "$HW_CPU" != "base" ] && HW_MODE="cpu_optimized"

case "$HW_GPU" in
  adreno)
    if echo "$HW_VK_TYPE" | grep -qi "INTEGRATED_GPU\|DISCRETE_GPU"; then
      HW_MODE="gpu_vulkan"
      HW_GPU_AVAILABLE=true
    fi
    ;;
  adreno_no_vulkan)
    # Snapdragon sin vulkaninfo — CPU optimizada si hay features, si no estándar
    : # HW_MODE ya seteado arriba según CPU
    ;;
  mali|mali_no_vulkan|software|vulkan_system|none)
    # Sin GPU offload — HW_MODE depende solo de CPU features (ya seteado arriba)
    : ;;
esac

echo "  ┌─────────────────────────────────────────┐"
echo "  │  HARDWARE DETECTADO                     │"
echo "  ├─────────────────────────────────────────┤"
printf "  │  GPU: %-34s│\n" "$HW_GPU"
printf "  │  CPU: %-34s│\n" "$HW_CPU"
printf "  │  Modo recomendado: %-22s│\n" "$HW_MODE"
echo "  └─────────────────────────────────────────┘"
echo ""

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
# ── Selección de versión de instalación ──────────────────────
echo "  Versiones disponibles:"
echo ""
echo -e "  ${CYAN}[1] Estándar${NC}   — pkg install ollama (genérico ARM64)"
echo -e "               Compatible con cualquier dispositivo"

if [ "$HW_MODE" = "cpu_optimized" ] || [ "$HW_MODE" = "gpu_vulkan" ]; then
  echo -e "  ${GREEN}[2] Optimizada${NC} — llama.cpp compilado con flags CPU avanzados"
  printf   "               Ganancia estimada ~1.5x–2.5x tokens/s (%s)\n" "$HW_CPU"
  echo -e "               Requiere: cmake clang git (~15min compilación)"
else
  echo -e "  ${YELLOW}[2] Optimizada${NC} — no disponible (CPU sin instrucciones avanzadas)"
fi

if $HW_GPU_AVAILABLE; then
  echo -e "  ${GREEN}[3] GPU Vulkan${NC}  — llama.cpp compilado con Vulkan (Adreno detectado)"
  echo -e "               Más rápido para modelos grandes"
  echo -e "               Requiere: cmake clang git vulkan-tools (~20min)"
else
  echo -e "  ${YELLOW}[3] GPU Vulkan${NC}  — no disponible en este dispositivo"
fi

echo ""
echo -e "  Recomendado para tu hardware: ${GREEN}${HW_MODE}${NC}"
echo ""
echo -n "  Elige versión [1"
[ "$HW_MODE" != "cpu_standard" ] && echo -n "/2"
$HW_GPU_AVAILABLE && echo -n "/3"
echo "]: "
read -r VERSION_CHOICE < /dev/tty

# Validar y asignar modo de instalación
INSTALL_MODE="standard"
case "$VERSION_CHOICE" in
  2)
    if [ "$HW_MODE" = "cpu_optimized" ] || [ "$HW_MODE" = "gpu_vulkan" ]; then
      INSTALL_MODE="optimized"
    else
      warn "CPU estándar — usando instalación estándar"
      INSTALL_MODE="standard"
    fi
    ;;
  3)
    if $HW_GPU_AVAILABLE; then
      INSTALL_MODE="gpu_vulkan"
    else
      warn "GPU Vulkan no disponible — usando instalación estándar"
      INSTALL_MODE="standard"
    fi
    ;;
  *) INSTALL_MODE="standard" ;;
esac

echo ""
echo -n "  ¿Continuar con instalación ${INSTALL_MODE}? (s/n): "
read -r CONFIRM < /dev/tty
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
titulo "PASO 2 — Instalando Ollama (modo: ${INSTALL_MODE})"

if check_done "ollama_install"; then
  log "Ollama ya instalado [checkpoint]"
else
  case "$INSTALL_MODE" in

    standard)
      info "Instalando Ollama vía pkg (genérico ARM64)..."
      pkg install ollama -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || \
        error "Error instalando Ollama. Verifica conexión."
      log "Ollama instalado: $(ollama --version 2>/dev/null | head -1)"
      ;;

    optimized)
      info "Instalando llama.cpp optimizado con flags CPU: ${HW_CPU}"
      info "Instalando dependencias de compilación..."
      pkg install cmake clang git -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || \
        error "Error instalando dependencias de compilación."

      # Determinar flags según CPU features detectadas
      CPU_FLAGS="-march=armv8-a"
      echo "$HW_CPU" | grep -q "i8mm"    && CPU_FLAGS="-march=armv8.6-a+i8mm+dotprod"
      echo "$HW_CPU" | grep -q "dotprod" && [ "$CPU_FLAGS" = "-march=armv8-a" ] && \
        CPU_FLAGS="-march=armv8.2-a+dotprod"
      echo "$HW_CPU" | grep -q "sve"     && CPU_FLAGS="${CPU_FLAGS}+sve"

      info "Flags de compilación: ${CPU_FLAGS}"
      info "Clonando llama.cpp (puede tardar)..."

      BUILD_DIR="$HOME/llama_cpp_build"
      rm -rf "$BUILD_DIR"
      git clone --depth=1 https://github.com/ggerganov/llama.cpp "$BUILD_DIR" || \
        error "Error clonando llama.cpp. Verifica conexión."

      cd "$BUILD_DIR" && mkdir -p build && cd build
      cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CPU_FLAGS" \
        -DCMAKE_CXX_FLAGS="$CPU_FLAGS" \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=ON || error "Error en cmake."

      info "Compilando (esto puede tardar 10-20 minutos)..."
      make -j4 llama-server llama-cli 2>&1 | tail -5
      [ $? -ne 0 ] && error "Error de compilación. Intenta con versión estándar."

      # Instalar binarios
      cp bin/llama-server "$TERMUX_PREFIX/bin/llama-server" 2>/dev/null
      cp bin/llama-cli    "$TERMUX_PREFIX/bin/llama-cli"    2>/dev/null
      chmod +x "$TERMUX_PREFIX/bin/llama-server" "$TERMUX_PREFIX/bin/llama-cli" 2>/dev/null

      # Instalar Ollama pkg también (para gestión de modelos)
      info "Instalando Ollama pkg para gestión de modelos..."
      pkg install ollama -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>/dev/null || \
        warn "Ollama pkg no instalado — usa llama-server directamente"

      cd "$HOME"
      log "llama.cpp optimizado compilado e instalado"
      log "Binarios: llama-server · llama-cli"
      ;;

    gpu_vulkan)
      info "Instalando llama.cpp con soporte Vulkan GPU..."
      pkg install cmake clang git vulkan-tools -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || \
        error "Error instalando dependencias."

      BUILD_DIR="$HOME/llama_cpp_build"
      rm -rf "$BUILD_DIR"
      git clone --depth=1 https://github.com/ggerganov/llama.cpp "$BUILD_DIR" || \
        error "Error clonando llama.cpp."

      cd "$BUILD_DIR" && mkdir -p build && cd build
      cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_VULKAN=ON || error "Error en cmake con Vulkan."

      info "Compilando con Vulkan (puede tardar 15-25 minutos)..."
      make -j4 llama-server llama-cli 2>&1 | tail -5
      [ $? -ne 0 ] && error "Error compilando con Vulkan."

      cp bin/llama-server "$TERMUX_PREFIX/bin/llama-server" 2>/dev/null
      cp bin/llama-cli    "$TERMUX_PREFIX/bin/llama-cli"    2>/dev/null
      chmod +x "$TERMUX_PREFIX/bin/llama-server" "$TERMUX_PREFIX/bin/llama-cli" 2>/dev/null

      pkg install ollama -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>/dev/null

      cd "$HOME"
      log "llama.cpp con Vulkan compilado e instalado"
      ;;

  esac

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
tmux send-keys -t "$SESSION" "OLLAMA_HOST=0.0.0.0:11434 ollama serve" Enter
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

echo "  Hardware: GPU=${HW_GPU} · CPU=${HW_CPU}"
echo ""
echo "  Modelos de texto recomendados:"
echo "  [1] qwen2.5:0.5b  ~395MB  — Más liviano, respuestas rápidas"
echo "  [2] qwen2.5:1.5b  ~1.0GB  — Balance velocidad/calidad"
echo "  [3] phi3:mini      ~2.3GB  — Mejor calidad"
echo "  [4] llama3.2:1b   ~1.3GB  — Buena calidad, liviano"
echo ""
echo "  Modelos de visión (análisis de imágenes):"
echo "  [5] moondream:1.8b ~1.1GB — Visión ligero (recomendado)"
echo "  [6] llava:7b       ~4.7GB — Visión calidad (requiere RAM)"
echo ""

# Opciones GPU solo si hay hardware compatible
if $HW_GPU_AVAILABLE; then
  echo -e "  ${GREEN}GPU Vulkan detectada ✅ — modelos GPU disponibles:${NC}"
  echo "  [7] llama3.2:3b   ~2.0GB — CPU/GPU híbrido"
  echo "  [8] qwen2.5:3b    ~2.0GB — CPU/GPU híbrido"
  echo ""
elif [ "$HW_GPU" = "adreno" ] || [ "$HW_GPU" = "adreno_no_vulkan" ]; then
  echo -e "  ${YELLOW}Adreno detectado — GPU Vulkan no confirmada.${NC}"
  echo -e "  ${YELLOW}Se usará CPU optimizada (${HW_CPU}).${NC}"
  echo ""
elif [ "$HW_GPU" = "mali" ] || [ "$HW_GPU" = "mali_no_vulkan" ]; then
  echo -e "  ${CYAN}Mali detectado — GPU offload no disponible sin root.${NC}"
  echo -e "  ${CYAN}Se usará CPU optimizada (${HW_CPU}).${NC}"
  echo ""
fi

echo "  [0] Omitir — lo haré después manualmente"
echo ""
echo -n "  Elige modelo: "
read -r MODEL_CHOICE < /dev/tty

SELECTED_MODEL=""
case "$MODEL_CHOICE" in
  1) SELECTED_MODEL="qwen2.5:0.5b" ;;
  2) SELECTED_MODEL="qwen2.5:1.5b" ;;
  3) SELECTED_MODEL="phi3:mini" ;;
  4) SELECTED_MODEL="llama3.2:1b" ;;
  5) SELECTED_MODEL="moondream:1.8b" ;;
  6) SELECTED_MODEL="llava:7b" ;;
  7) $HW_GPU_AVAILABLE && SELECTED_MODEL="llama3.2:3b" || warn "GPU no disponible — elige otra opción" ;;
  8) $HW_GPU_AVAILABLE && SELECTED_MODEL="qwen2.5:3b"  || warn "GPU no disponible — elige otra opción" ;;
  *) SELECTED_MODEL="" ;;
esac

if [ -n "$SELECTED_MODEL" ]; then
  info "Iniciando servidor Ollama para descarga..."
  OLLAMA_HOST=0.0.0.0:11434 ollama serve &>/dev/null &
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
  info "Modelo omitido. Puedes descargarlo después con: ollama pull qwen2.5:0.5b"
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

# ============================================================
# PASO 7 — Crear scripts de visión y utilidades SQLite
# ============================================================
titulo "PASO 7 — Scripts de visión y utilidades"

if check_done "ollama_vision_scripts"; then
  log "Scripts de visión ya creados [checkpoint]"
else
  # ── vision_bot.py ─────────────────────────────────────────
  cat > "$HOME/vision_bot.py" << 'VISION_PYEOF'
#!/data/data/com.termux/files/usr/bin/python3
"""
vision_bot.py — Bot de visión para termux-ai-stack
BUG 4 FIX: redimensionado automático a 512px para imágenes >500KB
SQLite FIX: sin DEFAULT (datetime('now')) — incompatible con ARM64
urllib FIX: sin dependencia de requests
"""
import sys, os, base64, sqlite3, json, argparse
from urllib import request as ureq
from datetime import datetime

try:
    from PIL import Image
    PILLOW_OK = True
except ImportError:
    PILLOW_OK = False

OLLAMA_URL    = "http://localhost:11434"
VISION_MODEL  = "moondream:1.8b"
TEXT_MODEL    = "qwen2.5:0.5b"
DB_PATH       = os.path.expanduser("~/bot_history.db")
IMG_CACHE_DIR = os.path.expanduser("~/img_cache")
os.makedirs(IMG_CACHE_DIR, exist_ok=True)

def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""CREATE TABLE IF NOT EXISTS historial (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT, rol TEXT, content TEXT,
        tiene_imagen INTEGER DEFAULT 0, modelo TEXT, fecha TEXT)""")
    conn.execute("""CREATE TABLE IF NOT EXISTS imagenes_analizadas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT, ruta TEXT, descripcion TEXT,
        pregunta TEXT, modelo TEXT, fecha TEXT)""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_chat ON historial(chat_id)")
    conn.commit()
    return conn

def redimensionar(ruta):
    if not PILLOW_OK: return ruta
    if os.path.getsize(ruta) <= 500_000: return ruta
    img = Image.open(ruta)
    w, h = img.size
    r = min(512/w, 512/h)
    img = img.resize((int(w*r), int(h*r)), Image.LANCZOS)
    tmp = os.path.expanduser("~/vision_tmp.jpg")
    img.save(tmp, "JPEG", quality=80)
    return tmp

def _post_ollama(payload, timeout=300):
    data = json.dumps(payload).encode("utf-8")
    req = ureq.Request(f"{OLLAMA_URL}/api/generate", data=data,
                       headers={"Content-Type": "application/json"})
    with ureq.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())

def analizar_imagen(ruta, pregunta, chat_id):
    conn = init_db()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    ruta_proc = redimensionar(ruta)
    with open(ruta_proc, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    tmp = os.path.expanduser("~/vision_tmp.jpg")
    if ruta_proc != ruta and os.path.exists(tmp): os.remove(tmp)
    try:
        result = _post_ollama({"model": VISION_MODEL,
            "prompt": f"You must respond ONLY in Spanish. {pregunta} Responde en español.",
            "images": [b64], "stream": False,
            "options": {"num_predict": 150, "temperature": 0.1}})
        descripcion = result.get("response", "").strip()
    except Exception as e:
        descripcion = f"[ERROR Ollama] {e}"
    conn.execute("INSERT INTO historial (chat_id,rol,content,tiene_imagen,modelo,fecha) VALUES (?,?,?,1,?,?)",
        (chat_id, "user", f"[IMAGEN] {pregunta}", None, now))
    conn.execute("INSERT INTO historial (chat_id,rol,content,tiene_imagen,modelo,fecha) VALUES (?,?,?,1,?,?)",
        (chat_id, "assistant", descripcion, VISION_MODEL, now))
    conn.execute("INSERT INTO imagenes_analizadas (chat_id,ruta,descripcion,pregunta,modelo,fecha) VALUES (?,?,?,?,?,?)",
        (chat_id, ruta, descripcion, pregunta, VISION_MODEL, now))
    conn.commit(); conn.close()
    return descripcion

def chat_texto(chat_id, mensaje):
    conn = init_db()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    hist = list(reversed(conn.execute(
        "SELECT rol, content FROM historial WHERE chat_id=? ORDER BY id DESC LIMIT 4",
        (chat_id,)).fetchall()))
    context = "\n".join([f"{'Usuario' if r=='user' else 'Bot'}: {c}" for r,c in hist[:-1]])
    prompt = f"{context}\nUsuario: {mensaje}\nBot:" if context else mensaje
    conn.execute("INSERT INTO historial (chat_id,rol,content,fecha) VALUES (?,?,?,?)",
        (chat_id, "user", mensaje, now))
    conn.commit()
    try:
        result = _post_ollama({"model": TEXT_MODEL, "prompt": prompt,
            "stream": False, "options": {"num_predict": 100}}, timeout=60)
        respuesta = result.get("response", "").strip()
    except Exception as e:
        respuesta = f"[ERROR Ollama] {e}"
    conn.execute("INSERT INTO historial (chat_id,rol,content,modelo,fecha) VALUES (?,?,?,?,?)",
        (chat_id, "assistant", respuesta, TEXT_MODEL, now))
    conn.commit(); conn.close()
    return respuesta

def get_stats(chat_id=None):
    conn = init_db()
    if chat_id:
        result = {"chat_id": chat_id,
            "mensajes": conn.execute("SELECT COUNT(*) FROM historial WHERE chat_id=?", (chat_id,)).fetchone()[0],
            "imagenes": conn.execute("SELECT COUNT(*) FROM imagenes_analizadas WHERE chat_id=?", (chat_id,)).fetchone()[0]}
    else:
        result = {"total_mensajes": conn.execute("SELECT COUNT(*) FROM historial").fetchone()[0],
            "imagenes_analizadas": conn.execute("SELECT COUNT(*) FROM imagenes_analizadas").fetchone()[0],
            "usuarios": conn.execute("SELECT COUNT(DISTINCT chat_id) FROM historial").fetchone()[0]}
    conn.close()
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("imagen",   nargs="?")
    parser.add_argument("chat_id",  nargs="?", default="test_chat")
    parser.add_argument("pregunta", nargs="?", default="¿Qué ves en esta imagen? Responde en español.")
    parser.add_argument("--texto",  help="Mensaje de texto sin imagen")
    parser.add_argument("--stats",  action="store_true")
    args = parser.parse_args()
    if args.stats:
        print(json.dumps(get_stats(), ensure_ascii=False, indent=2))
    elif args.texto:
        print(chat_texto(args.chat_id, args.texto))
    elif args.imagen:
        if not os.path.exists(args.imagen):
            print(f"ERROR: imagen no encontrada: {args.imagen}", file=sys.stderr); sys.exit(1)
        print(analizar_imagen(args.imagen, args.pregunta, args.chat_id))
    else:
        parser.print_help()
VISION_PYEOF
  chmod +x "$HOME/vision_bot.py"
  log "vision_bot.py creado en $HOME/vision_bot.py"

  # ── bot_utils.py (helpers SQLite reutilizables) ───────────
  cat > "$HOME/bot_utils.py" << 'UTILS_PYEOF'
#!/data/data/com.termux/files/usr/bin/python3
"""
bot_utils.py — Helpers SQLite reutilizables para termux-ai-stack
Compatible con SQLite ARM64 (sin DEFAULT datetime functions)
"""
import sqlite3, os
from datetime import datetime

def get_conn(db_path):
    """Abre conexión y garantiza que las tablas existen."""
    conn = sqlite3.connect(os.path.expanduser(db_path))
    conn.execute("""CREATE TABLE IF NOT EXISTS historial (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id TEXT NOT NULL, rol TEXT NOT NULL,
        content TEXT NOT NULL, modelo TEXT,
        tiene_img INTEGER DEFAULT 0, fecha TEXT)""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_c ON historial(chat_id)")
    conn.commit()
    return conn

def save_turn(conn, chat_id, user_msg, assistant_msg, modelo=None, tiene_img=0):
    """Guarda un turno completo (user + assistant) con timestamp Python."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,modelo,tiene_img,fecha) VALUES (?,?,?,?,?,?)",
        (chat_id, "user", user_msg, None, tiene_img, now))
    conn.execute(
        "INSERT INTO historial (chat_id,rol,content,modelo,tiene_img,fecha) VALUES (?,?,?,?,?,?)",
        (chat_id, "assistant", assistant_msg, modelo, tiene_img, now))
    conn.commit()

def get_history(conn, chat_id, limit=10):
    """Retorna historial reciente de un chat como lista de (rol, content)."""
    rows = conn.execute(
        "SELECT rol, content FROM historial WHERE chat_id=? ORDER BY id DESC LIMIT ?",
        (chat_id, limit)).fetchall()
    return list(reversed(rows))

def trim_history(conn, chat_id, max_msgs):
    """Elimina mensajes más antiguos si se supera max_msgs."""
    total = conn.execute(
        "SELECT COUNT(*) FROM historial WHERE chat_id=?", (chat_id,)).fetchone()[0]
    if total > max_msgs:
        ids = [str(r[0]) for r in conn.execute(
            "SELECT id FROM historial WHERE chat_id=? ORDER BY id ASC LIMIT ?",
            (chat_id, total - max_msgs)).fetchall()]
        conn.execute(f"DELETE FROM historial WHERE id IN ({','.join(ids)})")
        conn.commit()

def stats(conn, chat_id=None):
    """Retorna dict con estadísticas de la BD."""
    if chat_id:
        return {"chat_id": chat_id,
            "mensajes": conn.execute("SELECT COUNT(*) FROM historial WHERE chat_id=?", (chat_id,)).fetchone()[0]}
    return {
        "total_mensajes": conn.execute("SELECT COUNT(*) FROM historial").fetchone()[0],
        "chats": conn.execute("SELECT COUNT(DISTINCT chat_id) FROM historial").fetchone()[0]}
UTILS_PYEOF
  chmod +x "$HOME/bot_utils.py"
  log "bot_utils.py creado en $HOME/bot_utils.py"

  # ── image_archive.py (archivo de imágenes con SQLite + nube) ─
  info "Descargando image_archive.py desde repo..."
  if curl -fsSL     "https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/python/image_archive.py"     -o "$HOME/image_archive.py" 2>/dev/null; then
    chmod +x "$HOME/image_archive.py"
    log "image_archive.py descargado en $HOME/image_archive.py"
  else
    warn "No se pudo descargar image_archive.py desde GitHub"
    warn "Descárgalo manualmente desde: python/image_archive.py"
  fi

  # ── image_archive_config.example (plantilla de nube) ─────────
  if curl -fsSL     "https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/python/image_archive_config.example"     -o "$HOME/image_archive_config.example" 2>/dev/null; then
    log "image_archive_config.example descargado en $HOME/"
    info "Para activar nube (R2/Drive):"
    info "  cp ~/image_archive_config.example ~/.image_archive_config"
    info "  nano ~/.image_archive_config"
  fi

  # Crear directorio de archivo de imágenes
  mkdir -p "$HOME/vision_archive"
  mkdir -p "$HOME/vision_imgs"
  log "Directorios creados: ~/vision_archive/ ~/vision_imgs/"

  mark_done "ollama_vision_scripts"
fi

# ── Verificar Pillow (requerido para BUG 4 fix) ──────────────
if python3 -c "from PIL import Image" 2>/dev/null; then
  log "Pillow OK — redimensionado de imágenes activo"
else
  warn "Pillow no instalado — imágenes no se redimensionarán (posible timeout)"
  echo -n "  ¿Instalar Pillow y deps visión ahora? (s/n): "
  read -r INSTALL_PILLOW < /dev/tty
  if [ "$INSTALL_PILLOW" = "s" ] || [ "$INSTALL_PILLOW" = "S" ]; then
    pkg install libjpeg-turbo libpng zlib -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"
    pip install Pillow --break-system-packages
    python3 -c "from PIL import Image" 2>/dev/null && \
      log "Pillow instalado correctamente" || \
      warn "Pillow falló — instala manualmente: pip install Pillow --break-system-packages"
  fi
fi

# Limpiar checkpoint
rm -f "$CHECKPOINT"

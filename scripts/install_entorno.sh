#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_entorno.sh
#  Instalador base del módulo [8] Entorno
#
#  Instala SOLO dependencias base:
#    - proot-distro + udocker (contenedores)
#    - termux-x11 (APK), pulseaudio (audio)
#    - Drivers GPU según hardware (ver más abajo)
#    - Crea ~/scripts/entorno/ (scripts de gestión)
#
#  SOPORTE GPU:
#    Adreno (Qualcomm) → mesa-zink + vulkan-loader-generic (nativo)
#                         Turnip (dentro del proot, descarga GitHub)
#    Mali   (ARM)      → virglrenderer-android + angle-android (nativo)
#    Xclipse (Samsung) → virglrenderer-android (experimental)
#    Otra/desconocida  → mesa (softGPU llvmpipe)
#
#  GUI: Termux:X11 (primario) · VNC (secundario/opcional)
#  VNC no se instala aquí — se instala bajo demanda desde el submenú.
#
#  NO instala distros ni DEs — el usuario elige desde
#  el submenú Terminal / Interfaz bajo demanda.
#
#  FLAGS:
#    --silent  → sin prompts interactivos
#    --force   → reinstalar aunque ya esté
#
#  VERSIÓN: 1.1.0 | Julio 2026
# ============================================================

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"
export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib"
export DEBIAN_FRONTEND=noninteractive

SILENT=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --silent) SILENT=1 ;;
    --force)  FORCE=1  ;;
  esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }

REGISTRY="$TERMUX_HOME/.android_server_registry"
CHECKPOINT="$TERMUX_HOME/.install_entorno_checkpoint"
ENTORNO_SCRIPTS="$TERMUX_HOME/scripts/entorno"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── pkg update con fallback de mirrors (mismo patrón que install_bootstrap.sh) ──
_MIRRORS=(
  "https://packages.termux.dev/apt/termux-main"
  "https://mirror.accum.se/mirror/termux.dev/apt/termux-main"
  "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
)

_set_mirror() {
  echo "deb $1 stable main" > "$TERMUX_PREFIX/etc/apt/sources.list"
  info "Mirror: $1"
}

_pkg_update_with_fallback() {
  local out
  out=$(pkg update -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>&1)
  if echo "$out" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
    warn "Mirror roto — probando alternativas..."
    local m ok=0
    for m in "${_MIRRORS[@]}"; do
      _set_mirror "$m"
      out=$(pkg update -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" 2>&1)
      if ! echo "$out" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
        log "Mirror OK: $m"; ok=1; break
      fi
    done
    [ "$ok" = "0" ] && warn "Todos los mirrors fallaron — continuando con el índice actual (puede haber errores de instalación)"
  fi
}

update_registry() {
  local version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^entorno\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  local _gpu="${GPU_TYPE:-$(_check_gpu)}"
  cat >> "$tmp" << EOF
entorno.installed=true
entorno.version=$version
entorno.install_date=$date_now
entorno.gpu=$_gpu
entorno.gpu_method=${GPU_METHOD:-auto}
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → $REGISTRY"
}

# ── Detección de GPU ──────────────────────────────────────────
# Usa getprop (no dmesg — requiere root en Android 15)
_check_gpu() {
  local gpu
  gpu=$(getprop ro.board.platform 2>/dev/null)
  case "$gpu" in
    *sm*|*kona*|*lahaina*|*shima*)      echo "adreno" ;;
    *mt*|*t618*|*g610*|*g720*)          echo "mali" ;;
    *s5e*|*exynos*)                     echo "xclipse" ;;
    *)                                   echo "unknown" ;;
  esac
}

# ── Instalación proot-distro ──────────────────────────────────
_install_proot_distro() {
  titulo "proot-distro"
  command -v proot-distro &>/dev/null && { log "proot-distro ya instalado"; return 0; }
  pkg install -y proot-distro 2>/dev/null || error "No se pudo instalar proot-distro"
  log "proot-distro instalado"
}

# ── Instalación udocker ──────────────────────────────────────
_install_udocker() {
  titulo "udocker"
  command -v udocker &>/dev/null && { log "udocker ya instalado"; return 0; }
  mkdir -p "$TERMUX_HOME/tmp"
  rm -f "$TERMUX_PREFIX/bin/udocker" 2>/dev/null
  curl -fsSL https://raw.githubusercontent.com/indigo-dc/udocker/main/udocker.py \
    -o "$TERMUX_PREFIX/bin/udocker" 2>/dev/null || \
    wget -q https://raw.githubusercontent.com/indigo-dc/udocker/main/udocker.py \
      -O "$TERMUX_PREFIX/bin/udocker" 2>/dev/null || {
    rm -f "$TERMUX_PREFIX/bin/udocker" 2>/dev/null
    warn "No se pudo descargar udocker — se puede instalar manualmente después"
    return 0
  }
  chmod +x "$TERMUX_PREFIX/bin/udocker"
  log "udocker instalado"
}

# ── Instalación Termux-X11 (APK) ─────────────────────────────
_install_x11() {
  titulo "Termux:X11 (APK) — GUI primaria"
  if pm list packages 2>/dev/null | grep -q "com.termux.x11"; then
    log "Termux:X11 APK ya instalado"
    return 0
  fi
  local X11_APK="$TERMUX_HOME/tmp/termux-x11.apk"
  local X11_URL
  X11_URL=$(curl -fsSL "https://api.github.com/repos/termux/termux-x11/releases/latest" 2>/dev/null \
    | grep -oE 'https://[^"]+arm64-v8a\.apk' | head -1)
  [ -z "$X11_URL" ] && {
    warn "No se pudo obtener URL de Termux:X11 — descarga manual: https://github.com/termux/termux-x11/releases"
    return 0
  }
  info "Descargando Termux:X11..."
  curl -fsSL "$X11_URL" -o "$X11_APK" 2>/dev/null || \
    wget -q "$X11_URL" -O "$X11_APK" 2>/dev/null || {
    warn "No se pudo descargar Termux:X11 APK"
    return 0
  }
  pm install --user 0 "$X11_APK" 2>/dev/null && {
    log "Termux:X11 APK instalado"
    rm -f "$X11_APK"
  } || {
    warn "No se pudo instalar Termux:X11 APK (puede requerir permisos)"
    rm -f "$X11_APK"
  }
}

# ── Instalación PulseAudio (configurado TCP para proot) ──────
_install_pulseaudio() {
  titulo "PulseAudio"
  if command -v pulseaudio &>/dev/null; then
    log "PulseAudio ya instalado"
  else
    pkg install -y pulseaudio 2>/dev/null || error "No se pudo instalar pulseaudio"
    log "PulseAudio instalado"
  fi
  local PA_CONF="$TERMUX_PREFIX/etc/pulse/default.pa"
  if [ -f "$PA_CONF" ]; then
    grep -q "load-module module-native-protocol-tcp" "$PA_CONF" 2>/dev/null || {
      echo "load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1" >> "$PA_CONF"
      log "PulseAudio TCP configurado (127.0.0.1)"
    }
  fi
}

# ── Instalación drivers GPU nativos ──────────────────────────
_install_gpu_native() {
  titulo "GPU nativa — $GPU_TYPE"
  case "$GPU_TYPE" in
    adreno)
      # mesa-zink: OpenGL sobre Vulkan via Zink
      # vulkan-loader-generic: expone Vulkan nativo de Android
      if dpkg -s mesa-zink &>/dev/null && dpkg -s vulkan-loader-generic &>/dev/null; then
        log "GPU Adreno: mesa-zink + vulkan-loader-generic ya instalados"
      else
        pkg install -y mesa-zink vulkan-loader-generic 2>/dev/null || \
          warn "GPU Adreno: algunos paquetes fallaron (puede que ya estén)"
        log "GPU Adreno: mesa-zink + vulkan-loader-generic instalados"
      fi
      GPU_METHOD="zink"
      ;;
    mali)
      # Mali no tiene Vulkan nativo accesible → VirGL+ANGLE
      # virglrenderer-android + angle-android: renderer OpenGL virtual
      if dpkg -s mesa &>/dev/null && dpkg -s virglrenderer-android &>/dev/null && dpkg -s angle-android &>/dev/null; then
        log "GPU Mali: mesa + virglrenderer-android + angle-android ya instalados"
      else
        pkg install -y mesa virglrenderer-android angle-android 2>/dev/null || \
          warn "GPU Mali: algunos paquetes fallaron (puede que ya estén)"
      fi
      # Crear symlinks necesarios para ANGLE
      local ANGLE_OPT="$TERMUX_PREFIX/opt/angle-android/vulkan"
      if [ -d "$ANGLE_OPT" ]; then
        [ ! -f "$ANGLE_OPT/libEGL.so.1" ] && \
          ln -s "$ANGLE_OPT/libEGL_angle.so" "$ANGLE_OPT/libEGL.so.1" 2>/dev/null
        [ ! -f "$ANGLE_OPT/libGLESv1_CM.so.1" ] && \
          ln -s "$ANGLE_OPT/libGLESv1_CM_angle.so" "$ANGLE_OPT/libGLESv1_CM.so.1" 2>/dev/null
        [ ! -f "$ANGLE_OPT/libGLESv2.so.2" ] && \
          ln -s "$ANGLE_OPT/libGLESv2_angle.so" "$ANGLE_OPT/libGLESv2.so.2" 2>/dev/null
      fi
      log "GPU Mali: mesa + virglrenderer-android + angle-android instalados"
      GPU_METHOD="virgl_angle"
      ;;
    xclipse)
      if dpkg -s mesa &>/dev/null && dpkg -s virglrenderer-android &>/dev/null && dpkg -s angle-android &>/dev/null; then
        log "GPU Xclipse: mesa + virglrenderer-android ya instalados"
      else
        pkg install -y mesa virglrenderer-android angle-android 2>/dev/null || \
          warn "GPU Xclipse: algunos paquetes fallaron"
        log "GPU Xclipse: mesa + virglrenderer-android instalados"
      fi
      GPU_METHOD="virgl"
      ;;
    unknown)
      if dpkg -s mesa &>/dev/null; then
        log "mesa (softGPU llvmpipe) ya instalado"
      else
        warn "GPU no detectada — instalando mesa (softGPU llvmpipe)"
        pkg install -y mesa 2>/dev/null || true
      fi
      GPU_METHOD="llvmpipe"
      ;;
  esac
}

# ── Crear scripts de gestión ────────────────────────────────
_create_scripts() {
  titulo "Scripts de gestión"
  mkdir -p "$ENTORNO_SCRIPTS"

  # xs_start.sh — Iniciar Termux:X11 con GPU
  cat > "$ENTORNO_SCRIPTS/tx11_start.sh" << 'TX11EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Iniciar Termux:X11 — GUI primaria
# Flags: --nogpu (desactivar aceleración GPU)
#        --legacy (dibujado legacy)
#        --nodbus (sin dbus-launch)
pkill termux-x11 2>/dev/null; sleep 1
NOGPU=0; LEGACY=0; NODBUS=0
for arg in "$@"; do
  case "$arg" in --nogpu) NOGPU=1;; --legacy) LEGACY=1;; --nodbus) NODBUS=1;; esac
done
if [ "$NOGPU" = "0" ]; then
  am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null || true
  termux-x11 :0 -xres 1920x1080 &
else
  am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null || true
  [ "$LEGACY" = "1" ] && termux-x11 :0 -xres 1920x1080 -legacy-drawing & || termux-x11 :0 -xres 1920x1080 &
fi
[ "$NODBUS" = "0" ] && sleep 2 || sleep 1
echo "Termux:X11 iniciado en :0 (GPU: $([ "$NOGPU" = "1" ] && echo off || echo on))"
TX11EOF
  chmod +x "$ENTORNO_SCRIPTS/tx11_start.sh"

  # tx11_stop.sh — Detener Termux:X11
  cat > "$ENTORNO_SCRIPTS/tx11_stop.sh" << 'TX11STOP'
#!/data/data/com.termux/files/usr/bin/bash
pkill termux-x11 2>/dev/null
echo "Termux:X11 detenido"
TX11STOP
  chmod +x "$ENTORNO_SCRIPTS/tx11_stop.sh"

  # vnc_start.sh — Iniciar VNC (secundario)
  cat > "$ENTORNO_SCRIPTS/vnc_start.sh" << 'VNCSTART'
#!/data/data/com.termux/files/usr/bin/bash
export DISPLAY=:1
vncserver :1 -geometry 1920x1080 -depth 24 -localhost 2>/dev/null || \
  tigervncserver :1 -geometry 1920x1080 -depth 24 -localhost 2>/dev/null || {
  echo "VNC no instalado — usa el menú Interfaz para instalarlo"
  exit 1
}
echo "VNC en :5901 — conectar: vncviewer 127.0.0.1:5901"
VNCSTART
  chmod +x "$ENTORNO_SCRIPTS/vnc_start.sh"

  cat > "$ENTORNO_SCRIPTS/vnc_stop.sh" << 'VNCSTOP'
#!/data/data/com.termux/files/usr/bin/bash
vncserver -kill :1 2>/dev/null || tigervncserver -kill :1 2>/dev/null || true
echo "VNC detenido"
VNCSTOP
  chmod +x "$ENTORNO_SCRIPTS/vnc_stop.sh"

  # pulse_start/stop.sh
  cat > "$ENTORNO_SCRIPTS/pulse_start.sh" << 'PULSESTART'
#!/data/data/com.termux/files/usr/bin/bash
pkill pulseaudio 2>/dev/null; sleep 1
pulseaudio --start --exit-idle-time=-1
echo "PulseAudio iniciado"
PULSESTART
  chmod +x "$ENTORNO_SCRIPTS/pulse_start.sh"

  cat > "$ENTORNO_SCRIPTS/pulse_stop.sh" << 'PULSESTOP'
#!/data/data/com.termux/files/usr/bin/bash
pkill pulseaudio 2>/dev/null
echo "PulseAudio detenido"
PULSESTOP
  chmod +x "$ENTORNO_SCRIPTS/pulse_stop.sh"

  # gpu_env.sh — Cargar variables de entorno GPU
  cat > "$ENTORNO_SCRIPTS/gpu_env.sh" << 'GPUENVEOF'
#!/data/data/com.termux/files/usr/bin/bash
# Cargar variables de entorno para aceleración GPU
# USO: source ~/scripts/entorno/gpu_env.sh
export MESA_NO_ERROR=1
export vblank_mode=0
# Detectar tipo de GPU del registry
GPU_TYPE=$(grep "^entorno\.gpu=" ~/.android_server_registry 2>/dev/null | cut -d= -f2)
GPU_METHOD=$(grep "^entorno\.gpu_method=" ~/.android_server_registry 2>/dev/null | cut -d= -f2)
case "$GPU_METHOD" in
  zink)
    export GALLIUM_DRIVER=zink
    export MESA_GL_VERSION_OVERRIDE=4.3COMPAT
    export MESA_GLES_VERSION_OVERRIDE=3.2 ;;
  virgl_angle|virgl)
    export GALLIUM_DRIVER=virpipe
    export MESA_GL_VERSION_OVERRIDE=4.3COMPAT
    export MESA_GLES_VERSION_OVERRIDE=3.2
    export LIBGL_DRI3_DISABLE=1 ;;
  llvmpipe)
    export GALLIUM_DRIVER=llvmpipe ;;
esac
echo "GPU: $GPU_TYPE ($GPU_METHOD) — variables cargadas"
GPUENVEOF
  chmod +x "$ENTORNO_SCRIPTS/gpu_env.sh"

  log "$ENTORNO_SCRIPTS creado con scripts de gestión"
}

# ════════════════════════════════════════════════════════════════
#  EJECUCIÓN PRINCIPAL
# ════════════════════════════════════════════════════════════════

[ "$SILENT" = "0" ] && {
  clear
  echo -e "${CYAN}${BOLD}"
  cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · Entorno Installer v1.1  ║
  ║   Base de contenedores + desktop + GPU       ║
  ╚══════════════════════════════════════════════╝
HEADER
  echo -e "${NC}"

  echo -e "  Este instalador prepara las dependencias base para:"
  echo -e "  ${CYAN}•${NC} proot-distro + udocker (contenedores Linux)"
  echo -e "  ${CYAN}•${NC} Termux:X11 + PulseAudio (display + audio)"
  echo -e "  ${CYAN}•${NC} Drivers GPU según tu hardware:"
  echo -e "       Adreno → Zink (OpenGL sobre Vulkan)"
  echo -e "       Mali   → VirGL + ANGLE (aceleración virtual)"
  echo -e "       Otro   → llvmpipe (software)"
  echo ""
  echo -e "  ${YELLOW}NOTA:${NC} No instala distros ni escritorios — eso lo eliges"
  echo -e "        después desde el submenú [8] Entorno → Terminal / Interfaz."
  echo ""

  local _RAM_LIBRE _DISK_LIBRE
  _RAM_LIBRE=$(free -h 2>/dev/null | awk '/^Mem:/{print $7}')
  [ -z "$_RAM_LIBRE" ] && _RAM_LIBRE="?"
  _DISK_LIBRE=$(df -h "$TERMUX_HOME" 2>/dev/null | awk 'NR==2{print $4}')
  [ -z "$_DISK_LIBRE" ] && _DISK_LIBRE="?"
  echo -e "  ${CYAN}Espacio disponible:${NC} RAM libre: ${_RAM_LIBRE}  ·  Disco libre: ${_DISK_LIBRE}"
  echo ""

  echo -n "  ¿Continuar? [s/N]: "
  read -r CONFIRM < /dev/tty
  case "$CONFIRM" in
    s|S|y|Y) echo "" ;;
    *) echo ""; echo -e "  ${YELLOW}Instalación cancelada${NC}"; exit 0 ;;
  esac
}

command -v getent &>/dev/null && [ "$(getent group aid_inet 2>/dev/null)" ] && log "aid_inet detectado"

if [ "$FORCE" = "0" ] && [ "$(grep "^entorno\.installed=" "$REGISTRY" 2>/dev/null | cut -d= -f2)" = "true" ]; then
  info "Entorno ya instalado (usa --force para reinstalar)"
  exit 0
fi

# Detectar GPU al inicio
GPU_TYPE=$(_check_gpu)
GPU_METHOD="auto"

check_done "entorno_arch" || {
  titulo "Arquitectura"
  ARCH=$(uname -m)
  case "$ARCH" in
    aarch64|arm64) : ;; # válido
    *) error "Solo ARM64 (aarch64/arm64) — detectado: $ARCH" ;;
  esac
  log "Arquitectura: $ARCH"
  mark_done "entorno_arch"
}

check_done "entorno_pkg_update" || {
  titulo "Actualizando índice de paquetes"
  _pkg_update_with_fallback
  mark_done "entorno_pkg_update"
}

check_done "entorno_proot_distro" || {
  _install_proot_distro
  mark_done "entorno_proot_distro"
}

check_done "entorno_udocker" || {
  _install_udocker
  mark_done "entorno_udocker"
}

check_done "entorno_x11" || {
  _install_x11
  mark_done "entorno_x11"
}

check_done "entorno_pulse" || {
  _install_pulseaudio
  mark_done "entorno_pulse"
}

check_done "entorno_gpu" || {
  _install_gpu_native
  mark_done "entorno_gpu"
}

check_done "entorno_dirs" || {
  _create_scripts
  mark_done "entorno_dirs"
}

check_done "entorno_registry" || {
  update_registry "1.1.0"
  mark_done "entorno_registry"
}

echo ""
echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  Entorno instalado correctamente       ║"
echo    "  ╠══════════════════════════════════════════╣"
echo -e "  ║  GPU: ${GPU_TYPE} (${GPU_METHOD})                ║"
echo -e "  ║  Menu: [8] Entorno                      ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"
echo ""
exit 0

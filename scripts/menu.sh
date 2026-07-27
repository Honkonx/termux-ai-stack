#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · menu.sh
#  Orquestador principal — carga módulos bajo demanda
#
#  NAVEGACIÓN:
#    [1-8]  → submenú del módulo
#    [0]    → backup / restore
#    [r]    → refrescar   [h] → ayuda
#    [u]    → actualizar scripts desde GitHub
#    [d]    → desinstalar módulo
#    [s/q]  → salir al shell
#    [p]    → rendimiento & keepalive
#
#  MÓDULOS:
#    [1] Servicios     — n8n + OpenClaw + Hermes (proot + nativo)
#    [2] Code Tools    — Claude + OpenCode (nativo + proot)
#    [3] Ollama        — modelos IA local  (nativo)
#    [4] Expo/EAS/Git  — builds móviles    (nativo)
#    [5] Python        — Python + SQLite + Trading (nativo)
#    [6] Remote        — SSH + Dashboard   (nativo)
#    [8] Entorno       — proot + desktop + VNC + GPU (nativo)
#    [0] Backup / Restore
#
#  CARGA DE MÓDULOS:
#    Bajo demanda con caché en memoria.
#    menu_nativo.sh y menu_proot.sh se cargan una sola vez
#    la primera vez que se necesitan — luego quedan en memoria.
#    Arranque rápido: solo variables + helpers base se inicializan.
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 5.0.0 | Mayo 2026
# ============================================================

TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
# .npm-global/bin (openclaw, codex, otras CLIs npm) y .openclaw-android/bin
# (wrapper node glibc) van acá para que el menú los encuentre aunque la
# sesión interactiva actual haya sourceado .bashrc ANTES de que el
# instalador escribiera esas rutas ahí — confirmado en dispositivo real
# como causa de "openclaw: command not found" pese a figurar instalado
# (2026-07-26)
export PATH="$HOME/.npm-global/bin:$HOME/.openclaw-android/bin:$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

REPO_RAW="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts"
REPO_RAW_ROOT="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main"
REGISTRY="$HOME/.android_server_registry"
EAS_PROJECT_FILE="$HOME/.eas_active_project"

# ════════════════════════════════════════════
#  FLAGS DE CARGA DE MÓDULOS
#  0 = no cargado aún · 1 = ya en memoria
# ════════════════════════════════════════════
_NATIVO_LOADED=0
_PROOT_LOADED=0

# ════════════════════════════════════════════
#  CACHÉ PROOT — variables globales
#  Definidas aquí para que persistan entre
#  renders del loop aunque los módulos se
#  carguen tarde.
# ════════════════════════════════════════════
_CC_CACHE=""     ; _CC_REFRESH=0
_OC_CACHE=""     ; _OC_CACHE_TS=0
_CLAW_CACHE=""   ; _CLAW_CACHE_TS=0
_OCL_CACHE=""    ; _OCL_REFRESH=0
_HERMES_CACHE="" ; _HERMES_REFRESH=0
_PROOT_CACHE_TTL=30          # TTL caché en memoria (segundos)
_PROOT_CACHE_TTL_PERSIST=300 # TTL caché en archivo — sobrevive reinicios (5 min)

# ════════════════════════════════════════════
#  COLORES
# ════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ════════════════════════════════════════════
#  RUTAS DE SCRIPTS
#  Definidas una sola vez aquí — todos los
#  módulos las heredan vía source.
# ════════════════════════════════════════════
SCRIPTS_DIR="$HOME/scripts"
N8N_SCRIPTS="$SCRIPTS_DIR/n8n"
OLLAMA_SCRIPTS="$SCRIPTS_DIR/ollama"
OPENCLAW_SCRIPTS="$SCRIPTS_DIR/openclaw"
OPENCODE_SCRIPTS="$SCRIPTS_DIR/opencode"
REMOTE_SCRIPTS="$SCRIPTS_DIR/remote"
EXPO_SCRIPTS="$SCRIPTS_DIR/expo"
ENTORNO_SCRIPTS="$SCRIPTS_DIR/entorno"

# ════════════════════════════════════════════
#  DETECCIÓN ROOTFS PROOT — Fix S22, corregido 2026-07-26
#  PRIMARIO: proot-distro list (funciona con permisos 0700)
#  FALLBACK:  enumeración de directorios (solo [ -d ], no [ -f ] interno)
#  Soporta ambos layouts de proot-distro: el moderno ("containers/<n>/rootfs",
#  reescritura bash→Python) y el legacy ("installed-rootfs/<n>", solo para
#  migrar instalaciones viejas según el propio código fuente de proot-distro)
#  — confiar solo en el legacy causaba falsos "no instalado" (2026-07-26)
#  Variable global — heredada por menu_proot.sh via source
# ════════════════════════════════════════════
DISTRO_NAME=""
ROOTFS_PATH=""
_ROOTFS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/installed-rootfs"
_CONTAINERS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/containers"

_proot_rootfs_path() {
  local _name="$1"
  [ -d "$_CONTAINERS_BASE/$_name/rootfs" ] && { echo "$_CONTAINERS_BASE/$_name/rootfs"; return 0; }
  [ -d "$_ROOTFS_BASE/$_name" ] && { echo "$_ROOTFS_BASE/$_name"; return 0; }
  return 1
}

_refresh_distro() {
  DISTRO_NAME=""
  ROOTFS_PATH=""
  # Método 1: proot-distro list (no requiere entrar al dir 0700)
  if command -v proot-distro &>/dev/null; then
    local _pd_out _d _path
    _pd_out=$(proot-distro list 2>/dev/null)
    for _d in debian ubuntu fedora archlinux; do
      if echo "$_pd_out" | grep -qE "^\s*\*?\s*${_d}\b"; then
        _path=$(_proot_rootfs_path "$_d") && {
          DISTRO_NAME="$_d"
          ROOTFS_PATH="$_path"
          return 0
        }
      fi
    done
  fi
  # Método 2: fallback — escanear ambos layouts directamente
  local _rd
  if [ -d "$_CONTAINERS_BASE" ]; then
    for _rd in "$_CONTAINERS_BASE"/*/; do
      _rd="${_rd%/}"
      [ -d "$_rd/rootfs" ] && { DISTRO_NAME=$(basename "$_rd"); ROOTFS_PATH="$_rd/rootfs"; return 0; }
    done
  fi
  if [ -d "$_ROOTFS_BASE" ]; then
    for _rd in "$_ROOTFS_BASE"/*/; do
      _rd="${_rd%/}"
      if [ -d "$_rd" ]; then
        DISTRO_NAME=$(basename "$_rd")
        ROOTFS_PATH="$_rd"
        return 0
      fi
    done
  fi
  return 1
}
_refresh_distro

# ════════════════════════════════════════════
#  CREAR ESTRUCTURA DE CARPETAS
#  Idempotente — no falla si ya existen.
# ════════════════════════════════════════════
_ensure_dirs() {
  mkdir -p \
    "$N8N_SCRIPTS" \
    "$OLLAMA_SCRIPTS" \
    "$OPENCLAW_SCRIPTS" \
    "$OPENCODE_SCRIPTS" \
    "$REMOTE_SCRIPTS" \
    "$EXPO_SCRIPTS" \
    "$ENTORNO_SCRIPTS"
}

# ════════════════════════════════════════════
#  MIGRACIÓN AUTOMÁTICA
#  Mueve scripts de ~/ a sus subcarpetas si
#  todavía están en la raíz (usuarios que
#  tenían el stack instalado antes del refactor).
#  Solo se ejecuta si el script existe en ~/
#  pero NO existe ya en la subcarpeta destino.
# ════════════════════════════════════════════
_migrate_legacy_scripts() {
  local migrated=0

  _mv_legacy() {
    local f="$1" dest="$2"
    if [ -f "$HOME/$f" ] && [ ! -f "$dest/$f" ]; then
      mv "$HOME/$f" "$dest/$f" 2>/dev/null
      chmod +x "$dest/$f" 2>/dev/null
      migrated=$((migrated + 1))
    fi
  }

  # n8n
  _mv_legacy "start_servidor.sh"  "$N8N_SCRIPTS"
  _mv_legacy "stop_servidor.sh"   "$N8N_SCRIPTS"
  _mv_legacy "ver_url.sh"         "$N8N_SCRIPTS"
  _mv_legacy "n8n_status.sh"      "$N8N_SCRIPTS"
  _mv_legacy "n8n_log.sh"         "$N8N_SCRIPTS"
  _mv_legacy "n8n_update.sh"      "$N8N_SCRIPTS"
  _mv_legacy "n8n_backup.sh"      "$N8N_SCRIPTS"
  _mv_legacy "cf_token.sh"        "$N8N_SCRIPTS"

  # ollama
  _mv_legacy "ollama_start.sh"    "$OLLAMA_SCRIPTS"
  _mv_legacy "ollama_stop.sh"     "$OLLAMA_SCRIPTS"

  # remote
  _mv_legacy "ssh_start.sh"       "$REMOTE_SCRIPTS"
  _mv_legacy "ssh_stop.sh"        "$REMOTE_SCRIPTS"

  # openclaw
  _mv_legacy "openclaw_start.sh"  "$OPENCLAW_SCRIPTS"
  _mv_legacy "openclaw_stop.sh"   "$OPENCLAW_SCRIPTS"
  _mv_legacy "openclaw_token.sh"  "$OPENCLAW_SCRIPTS"

  [ "$migrated" -gt 0 ] && \
    echo -e "  ${CYAN}[INFO]${NC} $migrated scripts migrados a ~/scripts/"
}

# ════════════════════════════════════════════
#  HELPERS GLOBALES BASE
#  Disponibles sin cargar ningún módulo.
# ════════════════════════════════════════════

get_reg() { grep "^${1}\.${2}=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2; }

_get_ip() {
  local ip
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | \
    grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep "inet " | \
    grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ip addr show 2>/dev/null | grep "inet " | \
    grep -v "127\." | awk '{print $2}' | cut -d'/' -f1 | head -1)
  echo "${ip:-<tu_IP_WiFi>}"
}

_eas_get_project() { [ -f "$EAS_PROJECT_FILE" ] && cat "$EAS_PROJECT_FILE" 2>/dev/null || echo ""; }
_eas_set_project() { echo "$1" > "$EAS_PROJECT_FILE"; }

find_claude_cli() {
  # Método nativo: buscar cli.js dentro del binario no aplica,
  # pero devolver ruta vacía para que check_claude use la detección por método
  # Método legacy: buscar cli.js via wrapper o rutas conocidas
  local wrapper="$TERMUX_PREFIX/bin/claude"
  if [ -f "$wrapper" ]; then
    local cli_from_wrapper
    cli_from_wrapper=$(grep "node " "$wrapper" 2>/dev/null | grep "cli\.js" | \
      grep -oE '/[^ "]+cli\.js' | head -1)
    [ -n "$cli_from_wrapper" ] && [ -f "$cli_from_wrapper" ] && {
      echo "$cli_from_wrapper"; return
    }
  fi
  local KNOWN=(
    "/data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js"
    "$HOME/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js"
    "$HOME/.node_modules/@anthropic-ai/claude-code/cli.js"
  )
  for p in "${KNOWN[@]}"; do
    [ -f "$p" ] && { echo "$p"; return; }
  done
  local npm_root; npm_root=$(npm root -g 2>/dev/null)
  echo "${npm_root}/@anthropic-ai/claude-code/cli.js"
}

# Detecta qué método de Claude está instalado: "native" | "legacy" | "broken" | "none"
# Mismo criterio que install_claude.sh para consistencia
detect_claude_method() {
  local native_bin="$HOME/.local/share/claude-code/claude"
  if [ -f "$native_bin" ] && [ -x "$native_bin" ]; then
    echo "native"; return
  fi
  local npm_root; npm_root=$(npm root -g 2>/dev/null)
  if [ -f "${npm_root}/@anthropic-ai/claude-code/cli.js" ]; then
    echo "legacy"; return
  fi
  [ -f "$TERMUX_PREFIX/bin/claude" ] && { echo "broken"; return; }
  echo "none"
}

draw_module() {
  local num="$1" icon="$2" name="$3" state="$4" ver="$5" cmd="$6"
  local status_col cmd_col
  case "$state" in
    running)       status_col="${GREEN}● activo   ${NC}"; cmd_col="${CYAN}${cmd}${NC}" ;;
    stopped)       status_col="${GREEN}● listo    ${NC}"; cmd_col="${CYAN}${cmd}${NC}" ;;
    ready)         status_col="${GREEN}● listo    ${NC}"; cmd_col="${CYAN}${cmd}${NC}" ;;
    not_installed) status_col="${YELLOW}○ no instal${NC}"; cmd_col="${YELLOW}[instalar]${NC}"; ver="──────────" ;;
  esac
  printf "  ${BOLD}[%s]${NC} %s %-13s %b  %b\n" "$num" "$icon" "$name" "$status_col" "$cmd_col"
  if [ "$ver" = "err:reinstalar" ]; then
    printf "       ${RED}⚠ cli.js corrompido — presiona [2] para reinstalar${NC}\n"
  else
    printf "       ${DIM}%s${NC}\n" "$ver"
  fi
  echo ""
}

_ensure_install_script() {
  local script="$1"
  # Guard: script no puede estar vacío
  [ -z "$script" ] && {
    echo -e "\n  ${RED}[ERROR]${NC} _ensure_install_script: nombre de script vacío"
    return 1
  }
  local dest="$HOME/$script"

  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    echo -e "  ${YELLOW}[AVISO]${NC} ~/$script no encontrado — descargando..."

    # Todos los install_*.sh, menu_nativo.sh, menu_proot.sh, backup.sh, restore.sh
    # están en la RAÍZ del repo — NO en scripts/
    # REPO_RAW apunta a scripts/ (solo para scripts Python/bot)
    local url
    case "$script" in
      install_*.sh|menu_nativo.sh|menu_proot.sh|menu_entorno.sh|backup.sh|restore.sh|instalar.sh)
        url="$REPO_RAW_ROOT/$script" ;;
      *)
        url="$REPO_RAW/$script" ;;
    esac

    curl -fsSL "$url" -o "$dest" 2>/dev/null || \
      wget -q "$url" -O "$dest" 2>/dev/null

    if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
      echo -e "\n  ${RED}[ERROR]${NC} No se pudo obtener $script"
      echo -e "  ${DIM}URL intentada: $url${NC}"
      rm -f "$dest" 2>/dev/null
      read -r _ < /dev/tty
      return 1
    fi
    chmod +x "$dest"
    echo -e "  ${GREEN}[OK]${NC} $script descargado"
  fi
  return 0
}

_ensure_restore_for_install() {
  if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
    echo -e "\n  ${YELLOW}[AVISO]${NC} restore.sh no encontrado — descargando..."
    curl -fsSL "$REPO_RAW_ROOT/restore.sh" -o "$HOME/restore.sh" 2>/dev/null || \
      wget -q "$REPO_RAW_ROOT/restore.sh" -O "$HOME/restore.sh" 2>/dev/null
    [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ] && {
      echo -e "  ${RED}[ERROR]${NC} No se pudo obtener restore.sh"
      read -r _ < /dev/tty; return 1
    }
    chmod +x "$HOME/restore.sh"
  fi
  return 0
}

# ════════════════════════════════════════════
#  CARGA BAJO DEMANDA
#  Cada _require_* carga el módulo una sola
#  vez. Las llamadas siguientes son no-op.
#  Si el archivo no existe en ~/scripts/ lo descarga.
# ════════════════════════════════════════════
_require_nativo() {
  [ "$_NATIVO_LOADED" = "1" ] && return 0
  local f="$SCRIPTS_DIR/menu_nativo.sh"
  if [ ! -f "$f" ] || [ ! -s "$f" ]; then
    echo -e "\n  ${YELLOW}[AVISO]${NC} menu_nativo.sh no encontrado — descargando..."
    curl -fsSL "$REPO_RAW_ROOT/menu_nativo.sh" -o "$f" 2>/dev/null || \
      wget -q "$REPO_RAW_ROOT/menu_nativo.sh" -O "$f" 2>/dev/null
    [ ! -f "$f" ] || [ ! -s "$f" ] && {
      echo -e "  ${RED}[ERROR]${NC} No se pudo obtener menu_nativo.sh"
      read -r _ < /dev/tty; return 1
    }
    chmod +x "$f"
  fi
  # shellcheck source=/dev/null
  source "$f" || { echo -e "  ${RED}[ERROR]${NC} Fallo al cargar menu_nativo.sh"; return 1; }
  # Cargar menu_entorno.sh (descargar si no existe)
  local ef="$SCRIPTS_DIR/menu_entorno.sh"
  if [ ! -f "$ef" ] || [ ! -s "$ef" ]; then
    curl -fsSL "$REPO_RAW_ROOT/menu_entorno.sh" -o "$ef" 2>/dev/null || \
      wget -q "$REPO_RAW_ROOT/menu_entorno.sh" -O "$ef" 2>/dev/null
    [ -f "$ef" ] && chmod +x "$ef"
  fi
  if [ -f "$ef" ]; then
    source "$ef" 2>/dev/null || true
  fi
  _NATIVO_LOADED=1
  return 0
}

_require_proot() {
  [ "$_PROOT_LOADED" = "1" ] && return 0
  local f="$SCRIPTS_DIR/menu_proot.sh"
  if [ ! -f "$f" ] || [ ! -s "$f" ]; then
    echo -e "\n  ${YELLOW}[AVISO]${NC} menu_proot.sh no encontrado — descargando..."
    curl -fsSL "$REPO_RAW_ROOT/menu_proot.sh" -o "$f" 2>/dev/null || \
      wget -q "$REPO_RAW_ROOT/menu_proot.sh" -O "$f" 2>/dev/null
    [ ! -f "$f" ] || [ ! -s "$f" ] && {
      echo -e "  ${RED}[ERROR]${NC} No se pudo obtener menu_proot.sh"
      read -r _ < /dev/tty; return 1
    }
    chmod +x "$f"
  fi
  # shellcheck source=/dev/null
  source "$f" || { echo -e "  ${RED}[ERROR]${NC} Fallo al cargar menu_proot.sh"; return 1; }
  _PROOT_LOADED=1
  return 0
}

# ════════════════════════════════════════════
#  WRAPPERS DE CHECKS — disponibles desde el
#  arranque. Cargan el módulo si hace falta,
#  luego delegan a la función real del módulo.
#  Sin recursión: usan _run_check_* como
#  nombres temporales hasta que el source
#  sobreescribe con las funciones reales.
# ════════════════════════════════════════════
_run_check_nativo() {
  local fn="$1"; shift
  [ "$_NATIVO_LOADED" != "1" ] && { echo "not_installed||"; return; }
  "$fn" "$@"
}
_run_check_proot() {
  local fn="$1"; shift
  [ "$_PROOT_LOADED" != "1" ] && { echo "not_installed||"; return; }
  "$fn" "$@"
}

# Estas funciones son llamadas por el loop principal.
# Una vez que menu_nativo.sh / menu_proot.sh hacen source,
# sus definiciones propias sobreescriben estas — sin conflicto.
check_ollama()          { _run_check_nativo check_ollama         "$@"; }
check_expo()            { _run_check_nativo check_expo           "$@"; }
check_python()          { _run_check_nativo check_python         "$@"; }
check_remote()          { _run_check_nativo check_remote         "$@"; }
check_claude()          { _run_check_nativo check_claude         "$@"; }
check_hermes()          { _run_check_nativo check_hermes         "$@"; }
check_n8n()             { _run_check_proot  check_n8n            "$@"; }
check_opencode_cached() { _run_check_proot  check_opencode_cached "$@"; }
check_openclaw_cached() { _run_check_proot  check_openclaw_cached "$@"; }
check_openclaw_native() { _run_check_nativo check_openclaw_native "$@"; }
check_antigravity()     { _run_check_nativo check_antigravity     "$@"; }
check_codex()           { _run_check_nativo check_codex           "$@"; }
check_entorno()          { _run_check_nativo check_entorno          "$@"; }

# ════════════════════════════════════════════
#  POST-INSTALL CLEANUP
#  Llamado después de ejecutar cualquier script
#  de instalación — limpia el estado del shell
#  para evitar que el menú quede en estado
#  inconsistente sin necesitar reiniciar Termux.
#
#  Problemas que resuelve:
#  1. stdin residual: proot/npm/wget dejan datos
#     en /dev/tty que el siguiente read() consume
#     como opción del menú
#  2. Módulos cargados en memoria obsoletos: las
#     funciones de menu_proot.sh / menu_nativo.sh
#     en memoria pueden no reflejar el nuevo estado
#     → forzar reload en la próxima iteración
#  3. Caché de estado stale: los checks de proot
#     devolverían not_installed aunque ya instaló
# ════════════════════════════════════════════
_post_install_cleanup() {
  # 1. Re-detectar DISTRO_NAME — puede haberse instalado durante este paso
  _refresh_distro

  # 2. Forzar reload de módulos en la próxima iteración
  _PROOT_LOADED=0
  _NATIVO_LOADED=0

  # 3. Limpiar caché de estado — el módulo acaba de instalarse
  _invalidate_cache

  # 4. Drenar stdin residual — proot/npm/wget pueden dejar
  #    bytes en el buffer de /dev/tty que el siguiente
  #    read -r OPT < /dev/tty consumiría como opción
  local _drain
  while IFS= read -r -t 0 _drain < /dev/tty 2>/dev/null; do :; done

  # 5. Mensaje orientativo
  echo -e "\n  ${CYAN}[INFO]${NC} Recargando stack..."
}

# ════════════════════════════════════════════
#  INSTALL_MODULE — lógica de instalación
#  Disponible sin módulos cargados.
# ════════════════════════════════════════════
# ════════════════════════════════════════════
#  HELPER: instalar con output limpio
#  Uso: _run_installer_menu "install_hermes.sh" "Hermes Agent" [silent]
#  silent="1" → corre en background con --silent + spinner, output
#               solo al log (el install_*.sh debe soportar --silent)
#  silent="0" o vacío (default) → foreground con tee, visible + log,
#               igual que siempre (necesario para scripts con prompts
#               reales que todavía no soportan --silent)
# ════════════════════════════════════════════
_run_installer_menu() {
  local _script="$1"
  local _label="$2"
  local _silent="${3:-0}"
  local _log_dir="$HOME/.termux-ai-stack/logs"
  local _log="$_log_dir/install_$(python3 -c     "from datetime import datetime; print(datetime.now().strftime('%Y%m%d_%H%M%S'))"     2>/dev/null || date +%Y%m%d_%H%M%S).log"
  mkdir -p "$_log_dir"

  clear; echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "Instalando: ${_label}"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}Log: ~/.termux-ai-stack/logs/          ${CYAN}${BOLD}║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""

  local _exit
  if [ "$_silent" = "1" ]; then
    echo -e "  ${DIM}Instalación silenciosa — el log completo queda en el archivo de arriba${NC}"
    echo ""
    bash "$HOME/$_script" --silent > "$_log" 2>&1 &
    local _pid=$!
    local _SC="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏" _SI=0
    while kill -0 "$_pid" 2>/dev/null; do
      printf "\r  ${CYAN}%s${NC} ${DIM}Instalando ${_label}...${NC}" "${_SC:$((_SI%${#_SC})):1}"
      _SI=$((_SI+1)); sleep 0.12
    done
    wait "$_pid"; _exit=$?
    printf "\r\033[2K"
  else
    echo -e "  ${DIM}No cierres Termux durante la instalación${NC}"
    echo ""
    bash "$HOME/$_script" < /dev/tty 2>&1 | tee "$_log"
    _exit=$?
  fi

  echo ""
  if [ "$_exit" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}[OK]${NC} ${_label} instalado correctamente"
  else
    echo -e "  ${RED}[ERROR]${NC} Falló la instalación — código: ${_exit}"
    echo -e "  ${DIM}Ver detalles: cat ${_log}${NC}"
    if [ "$_silent" = "1" ]; then
      echo ""
      echo -e "  ${YELLOW}Últimas líneas del log:${NC}"
      tail -15 "$_log" 2>/dev/null | sed 's/^/  /'
    fi
  fi
  echo ""; read -r _ < /dev/tty
}

# ════════════════════════════════════════════
#  HELPER: confirmación previa a instalar
#  Solo se muestra si el módulo NO está instalado —
#  si ya está instalado, el propio install_*.sh
#  pregunta reinstalar/actualizar internamente.
# ════════════════════════════════════════════
_confirm_install() {
  local _label="$1"
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "Instalar ${_label}"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}[1] Instalar${CYAN}${BOLD}                           ║"
  echo -e "  ║  ${NC}[2] Cancelar${CYAN}${BOLD}                           ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""; echo -n "  Opción: "
  read -r _CI_OPT < /dev/tty
  [ "$_CI_OPT" = "1" ]
}

install_module() {
  local name="$1" module_key="$2"
  local script="install_${module_key}.sh"
  local dest="$HOME/$script"
  clear; echo ""

  if [ "$module_key" = "n8n" ]; then
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⬡ N8N — Instalar                        ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] n8n en proot Debian${CYAN}${BOLD}                 ║"
    echo -e "  ║      ${DIM}Node.js 20 LTS · ARM64 nativo · ~300MB${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] n8n en udocker${CYAN}${BOLD}                       ║"
    echo -e "  ║      ${DIM}Imagen oficial n8nio/n8n · ~800MB${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                             ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r INST_OPT < /dev/tty
    case "$INST_OPT" in
      1|2)
        _ensure_install_script "$script" || return 1
        export N8N_INSTALL_MODE="$INST_OPT"
        local _silent_ok=1
        [ "$(get_reg "$module_key" "installed")" = "true" ] && _silent_ok=0
        _run_installer_menu "$script" "n8n" "$_silent_ok"
        unset N8N_INSTALL_MODE
        _post_install_cleanup ;;
      b|B|"") return 0 ;;
    esac
    return 0
  fi

  # python/ssh/remote: elegir "instalación limpia" YA es la confirmación —
  # ahora pasan por _run_installer_menu (antes corrían crudo, sin log ni spinner)
  if [ "$module_key" = "python" ] || [ "$module_key" = "ssh" ] || \
     [ "$module_key" = "remote" ]; then
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    printf  "  ║  %-40s║\n" "Instalar ${name}"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Instalación limpia${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                            ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r INST_OPT < /dev/tty
    case "$INST_OPT" in
      b|B|"") return 0 ;;
      1|*)
        _ensure_install_script "$script" || return 1
        local _silent_ok=1
        [ "$(get_reg "$module_key" "installed")" = "true" ] && _silent_ok=0
        _run_installer_menu "$script" "${name}" "$_silent_ok"
        _post_install_cleanup ;;
    esac
    return 0
  fi

  # Ollama: elegir versión YA es la confirmación (solo en instalación fresca —
  # si ya está instalado, install_ollama.sh muestra su propio menú actualizar/reinstalar)
  if [ "$module_key" = "ollama" ]; then
    if [ "$(get_reg "$module_key" "installed")" = "true" ]; then
      _ensure_install_script "$script" || return 1
      _run_installer_menu "$script" "Ollama" "0"
    else
      echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
      echo    "  ║  Ollama — elige versión                  ║"
      echo    "  ╠══════════════════════════════════════════╣"
      echo -e "  ║  ${NC}[1] Estándar  — versión oficial${CYAN}${BOLD}         ║"
      echo -e "  ║  ${NC}[2] Termux    — GPU optimizada ★${CYAN}${BOLD}        ║"
      echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                            ║"
      echo -e "  ╚══════════════════════════════════════════╝${NC}"
      echo ""; echo -n "  Opción [1/2]: "
      read -r OLLAMA_OPT < /dev/tty
      case "$OLLAMA_OPT" in
        b|B|"") return 0 ;;
        2) export OLLAMA_INSTALL_MODE="termux_npm" ;;
        *) export OLLAMA_INSTALL_MODE="standard" ;;
      esac
      _ensure_install_script "$script" || return 1
      _run_installer_menu "$script" "Ollama" "1"
      unset OLLAMA_INSTALL_MODE
    fi
    _post_install_cleanup
    return 0
  fi

  # Claude: elegir método YA es la confirmación (solo en instalación fresca —
  # si ya está instalado, install_claude.sh muestra su propio menú
  # actualizar/reinstalar/resolver conflicto, que necesita ser interactivo)
  if [ "$module_key" = "claude" ]; then
    if [ "$(get_reg "$module_key" "installed")" = "true" ]; then
      _ensure_install_script "install_claude.sh" || return 1
      _run_installer_menu "install_claude.sh" "Claude Code" "0"
    else
      echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
      echo    "  ║  Selecciona el método de instalación      ║"
      echo    "  ╠══════════════════════════════════════════╣"
      echo -e "  ║  ${NC}[1] Native  — binario ELF, recomendado${CYAN}${BOLD}  ║"
      echo -e "  ║  ${NC}[2] Legacy  — npm, garantizado${CYAN}${BOLD}          ║"
      echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                            ║"
      echo -e "  ╚══════════════════════════════════════════╝${NC}"
      echo ""; echo -n "  Opción: "
      read -r CLAUDE_OPT < /dev/tty
      case "$CLAUDE_OPT" in
        b|B|"") return 0 ;;
        2) export CLAUDE_METHOD="legacy" ;;
        *) export CLAUDE_METHOD="native" ;;
      esac
      _ensure_install_script "install_claude.sh" || return 1
      _run_installer_menu "install_claude.sh" "Claude Code" "1"
      unset CLAUDE_METHOD
    fi
    _post_install_cleanup
    return 0
  fi

  # Antigravity: instalar con output limpio
  # Instalación npm rápida — sin menú fuente, sin GitHub
  if [ "$module_key" = "antigravity" ]; then
    local _silent_ok=1
    if [ "$(get_reg "$module_key" "installed")" = "true" ]; then
      _silent_ok=0
    else
      _confirm_install "Antigravity CLI" || return 0
    fi
    _ensure_install_script "install_antigravity.sh" || return 1
    _run_installer_menu "install_antigravity.sh" "Antigravity CLI" "$_silent_ok"
    _post_install_cleanup
    return 0
  fi

  # Hermes: output interno oculto — solo spinner + resultado
  if [ "$module_key" = "hermes" ]; then
    local _silent_ok=1
    if [ "$(get_reg "$module_key" "installed")" = "true" ]; then
      _silent_ok=0
    else
      _confirm_install "Hermes Agent" || return 0
    fi
    _ensure_install_script "install_hermes.sh" || return 1
    _run_installer_menu "install_hermes.sh" "Hermes Agent" "$_silent_ok"
    _post_install_cleanup
    return 0
  fi

  # Expo, opencode, openclaw — instalación directa sin menú de fuente.
  # Soportan --silent → instalación fresca corre en silencio con spinner;
  # si ya estaban instalados, van interactivos (su propio menú reinstalar/actualizar).
  local _silent_ok=1
  if [ "$(get_reg "$module_key" "installed")" = "true" ]; then
    _silent_ok=0
  else
    _confirm_install "$name" || return 0
  fi
  _ensure_install_script "$script" || return 1
  _run_installer_menu "$script" "${name}" "$_silent_ok"
  _post_install_cleanup
  return 0

  # (bloque legacy — no se llega aquí)
  case "$INST_OPT" in
    b|B|"") return 0 ;;
    1|*)
      echo -e "\n${CYAN}${BOLD}  Instalando ${name}...${NC}\n"
      _ensure_install_script "$script" || return 1
      bash "$dest" < /dev/tty
      echo ""; read -r _ < /dev/tty
      _post_install_cleanup ;;
  esac
}


#  AYUDA
# ════════════════════════════════════════════
show_help() {
  clear; echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║     termux-ai-stack · AYUDA  v5.0.0    ║"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  MENÚ${NC}"
  echo    "  ║  1-6  → módulo/submenú  0 → backup"
  echo    "  ║  r → refrescar  h → ayuda  d → desinstalar"
  echo    "  ║  s/q → shell    u → actualizar scripts"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  N8N${NC}"
  echo    "  ║  n8n-start  n8n-stop  n8n-url  debian"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  CLAUDE CODE${NC}"
  echo    "  ║  claude  claude -p \"...\"  claude --continue"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  OLLAMA${NC}"
  echo    "  ║  ollama-start  ollama-stop  ollama run [m]"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  OPENCLAUDE${NC}"
  echo    "  ║  agy             (Antigravity CLI)"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  HERMES AGENT${NC}"
  echo    "  ║  hermes  hermes chat  hermes model"
  echo    "  ║  hermes gateway run  hermes status"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  REMOTE (SSH + Dashboard)${NC}"
  echo    "  ║  SSH WiFi: ssh -p 8022 user@IP"
  echo    "  ║  SSH Tunnel: cloudflared access ssh"
  echo    "  ║  Dashboard: http://IP:8080"
  echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -n "  Presiona ENTER para volver..."
  read -r _ < /dev/tty
}

# ════════════════════════════════════════════
#  HELPERS RENDIMIENTO
# ════════════════════════════════════════════
_perf_info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
_perf_ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
_perf_warn() { echo -e "  ${YELLOW}[AVISO]${NC} $1"; }
_wakelock_active() { pgrep -f "termux-wake-lock" &>/dev/null; }
_has_termux_api()  { command -v termux-wake-lock &>/dev/null; }
_add_bashrc()      { grep -q "$1" "$HOME/.bashrc" 2>/dev/null || echo "$1" >> "$HOME/.bashrc"; }

# ════════════════════════════════════════════
#  HELPERS DE CACHÉ
# ════════════════════════════════════════════
_invalidate_cache() {
  _CC_REFRESH=1;       _CC_CACHE=""
  _OCL_REFRESH=1;      _OCL_CACHE=""
  _HERMES_REFRESH=1;   _HERMES_CACHE=""
  _OC_CACHE="";        _OC_CACHE_TS=0
  _CLAW_CACHE="";      _CLAW_CACHE_TS=0
  # Borrar caché persistente — fuerza que el próximo render
  # llame a proot y escriba estado fresco al archivo
  rm -f "$HOME/.proot_status_cache" 2>/dev/null || true
}

# ════════════════════════════════════════════
#  LOOP PRINCIPAL
# ════════════════════════════════════════════
while true; do

  # ── Crear carpetas y migrar scripts legacy (primera iteración) ─
  _ensure_dirs
  _migrate_legacy_scripts

  # ── Cargar módulos ANTES del clear ───────────────────────────
  # Foreground obligatorio — los flags deben actualizarse en el padre.
  # Al ser la primera iteracion muestra mensaje breve para evitar
  # pantalla negra. Desde la segunda iteracion es no-op instantaneo.
  if [ "$_NATIVO_LOADED" = "0" ] || [ "$_PROOT_LOADED" = "0" ]; then
    echo -e "\n  ${CYAN}Cargando stack...${NC}"
    [ "$_NATIVO_LOADED" = "0" ] && _require_nativo 2>/dev/null
    [ "$_PROOT_LOADED"  = "0" ] && _require_proot  2>/dev/null
  fi

  clear

  # NOTA: no usar 'local' aqui — este bloque esta en el while, no en una funcion.
  _TMP="$HOME/.menu_check_$$"

  # ── Checks en paralelo ────────────────────────────────────────
  { check_n8n;    } > "${_TMP}_n8n" 2>/dev/null &
  { check_ollama; } > "${_TMP}_ol"  2>/dev/null &
  { check_expo;   } > "${_TMP}_ex"  2>/dev/null &
  { check_python; } > "${_TMP}_py"  2>/dev/null &
  { check_remote; } > "${_TMP}_rm"  2>/dev/null &
  { check_entorno; } > "${_TMP}_en" 2>/dev/null &

  # Hermes: nativo — caché ligero
  if [ -z "$_HERMES_CACHE" ] || [ "$_HERMES_REFRESH" = "1" ]; then
    { _HERMES_CACHE=$(check_hermes 2>/dev/null); _HERMES_REFRESH=0
      echo "$_HERMES_CACHE"; } > "${_TMP}_hm" 2>/dev/null &
    _HERMES_FROM_FILE=1
  else
    _HERMES_FROM_FILE=0
  fi

  # Antigravity: usa caché si está vigente (nativo — rápido)
  if [ -z "$_OCL_CACHE" ] || [ "$_OCL_REFRESH" = "1" ]; then
    { _OCL_CACHE=$(check_antigravity 2>/dev/null); _OCL_REFRESH=0
      echo "$_OCL_CACHE"; } > "${_TMP}_ocl" 2>/dev/null &
    _OCL_FROM_FILE=1
  else
    _OCL_FROM_FILE=0
  fi

  # Claude: usa caché si está vigente
  if [ -z "$_CC_CACHE" ] || [ "$_CC_REFRESH" = "1" ]; then
    { _CC_CACHE=$(check_claude 2>/dev/null); _CC_REFRESH=0
      echo "$_CC_CACHE"; } > "${_TMP}_cc" 2>/dev/null &
    _CC_FROM_FILE=1
  else
    _CC_FROM_FILE=0
  fi

  # OpenClaw nativo: rápido (~10ms), prioridad sobre proot
  { check_openclaw_native; } > "${_TMP}_cln" 2>/dev/null &
  _CLNATIVE_FROM_FILE=1

  # Proot combinado: refresca si caché expiró
  _now=$SECONDS
  if [ -z "$_OC_CACHE" ] || \
     [ $(( _now - _OC_CACHE_TS )) -gt $_PROOT_CACHE_TTL ] || \
     [ -z "$_CLAW_CACHE" ] || \
     [ $(( _now - _CLAW_CACHE_TS )) -gt $_PROOT_CACHE_TTL ]; then
    # Intentar caché de archivo antes de lanzar proot (evita 3-5s de login)
    if [ "$_PROOT_LOADED" = "1" ] && _load_proot_cache 2>/dev/null; then
      # Caché de archivo válido — variables ya actualizadas por _load_proot_cache
      # Escribir a archivos tmp para que el loop los lea normalmente
      echo "$_OC_CACHE"   > "${_TMP}_oc"
      echo "$_CLAW_CACHE" > "${_TMP}_cl"
      _PROOT_FROM_FILE=1
    else
      {
        # _check_proot_combined solo existe si menu_proot.sh está cargado
        if [ "$_PROOT_LOADED" = "1" ]; then
          _check_proot_combined
          echo "$_OC_CACHE"   > "${_TMP}_oc"
          echo "$_CLAW_CACHE" > "${_TMP}_cl"
        else
          echo "not_installed||" > "${_TMP}_oc"
          echo "not_installed||" > "${_TMP}_cl"
        fi
      } &
      _PROOT_FROM_FILE=1
    fi
  else
    _PROOT_FROM_FILE=0
  fi

  wait

  # ── Leer resultados ───────────────────────────────────────────
  IFS='|' read -r N8N_STATE   N8N_VER   N8N_EXTRA   < "${_TMP}_n8n"  2>/dev/null
  IFS='|' read -r OL_STATE    OL_VER    OL_EXTRA    < "${_TMP}_ol"   2>/dev/null
  IFS='|' read -r EX_STATE    EX_VER    EX_EXTRA    < "${_TMP}_ex"   2>/dev/null
  IFS='|' read -r PY_STATE    PY_VER    PY_EXTRA    < "${_TMP}_py"   2>/dev/null
  IFS='|' read -r RM_STATE    RM_VER    RM_EXTRA    < "${_TMP}_rm"   2>/dev/null
  IFS='|' read -r EN_STATE    EN_VER    EN_EXTRA    < "${_TMP}_en"   2>/dev/null

  if [ "$_OCL_FROM_FILE" = "1" ]; then
    _OCL_CACHE=$(cat "${_TMP}_ocl" 2>/dev/null)
  fi
  IFS='|' read -r OCL_STATE OCL_VER OCL_EXTRA <<< "$_OCL_CACHE"

  if [ "$_CC_FROM_FILE" = "1" ]; then
    _CC_CACHE=$(cat "${_TMP}_cc" 2>/dev/null)
  fi
  IFS='|' read -r CC_STATE CC_VER CC_EXTRA <<< "$_CC_CACHE"

  if [ "$_HERMES_FROM_FILE" = "1" ]; then
    _HERMES_CACHE=$(cat "${_TMP}_hm" 2>/dev/null)
  fi
  IFS='|' read -r HM_STATE HM_VER HM_EXTRA <<< "$_HERMES_CACHE"

  if [ "$_PROOT_FROM_FILE" = "1" ]; then
    _OC_CACHE=$(cat   "${_TMP}_oc" 2>/dev/null)
    _CLAW_CACHE=$(cat "${_TMP}_cl" 2>/dev/null)
    _OC_CACHE_TS=$SECONDS
    _CLAW_CACHE_TS=$SECONDS
  fi
  if [ "$_CLNATIVE_FROM_FILE" = "1" ]; then
    IFS='|' read -r CLN_STATE CLN_VER CLN_EXTRA < "${_TMP}_cln" 2>/dev/null || CLN_STATE="not_installed"
  else
    CLN_STATE="not_installed"
  fi

  # Openclaw: nativo tiene prioridad si está instalado
  if [ "$CLN_STATE" != "not_installed" ] && [ -n "$CLN_STATE" ]; then
    CL_STATE="$CLN_STATE"; CL_VER="$CLN_VER"; CL_EXTRA="$CLN_EXTRA"
  else
    IFS='|' read -r CL_STATE CL_VER CL_EXTRA <<< "$_CLAW_CACHE"
  fi
  IFS='|' read -r OC_STATE OC_VER OC_EXTRA <<< "$_OC_CACHE"

  rm -f "${_TMP}"_* 2>/dev/null

  # ── Info sistema ──────────────────────────────────────────────
  IP=$(_get_ip)
  RAM_FREE=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%.1fGB", $7/1024}')
  [ -z "$RAM_FREE" ] && RAM_FREE="--"
  DISK_FREE=$(df -h /data 2>/dev/null | awk 'NR==2{print $4}')
  [ -z "$DISK_FREE" ] && DISK_FREE="--"

  # ── Header ────────────────────────────────────────────────────
  echo -e "${CYAN}${BOLD}"
  echo    "  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "⬡ TERMUX·AI·STACK"
  printf  "  ║  %-40s║\n" "RAM: ${RAM_FREE}  Disk: ${DISK_FREE} libre"
  printf  "  ║  %-40s║\n" "$([ -n "$IP" ] && echo "IP: $IP" || echo "Sin red")"
  echo    "  ╠══════════════════════════════════════════╣"
  printf  "  ║  ${NC}%-38b${CYAN}${BOLD}║\n" "MÓDULOS"
  echo    "  ╚══════════════════════════════════════════╝"
  echo -e "${NC}"

  # ── Módulos ───────────────────────────────────────────────────
  # [1] Servicios — n8n + OpenClaw + Hermes
  SVC_STATE="not_installed"
  { [ "$N8N_STATE" != "not_installed" ] || \
    [ "$CL_STATE"  != "not_installed" ] || \
    [ "$HM_STATE"  != "not_installed" ]; } && SVC_STATE="ready"
  { [ "$N8N_STATE" = "running" ] || \
    [ "$CL_STATE"  = "running" ] || \
    [ "$HM_STATE"  = "running" ]; }        && SVC_STATE="running"
  SVC_VER=""
  [ "$N8N_STATE" != "not_installed" ] && SVC_VER="n8n:${N8N_VER:-?}"
  [ "$CL_STATE"  != "not_installed" ] && SVC_VER="${SVC_VER:+${SVC_VER} }claw:${CL_VER:-?}"
  [ "$HM_STATE"  != "not_installed" ] && SVC_VER="${SVC_VER:+${SVC_VER} }hm:${HM_VER:-?}"
  [ -z "$SVC_VER" ] && SVC_VER="──────────"
  draw_module "1" "⬡" "Servicios"    "$SVC_STATE" "$SVC_VER"        "→ submenú"

  # [2] Code Tools — Claude Code + OpenCode + Antigravity
  CT_STATE="ready"
  [ "$CC_STATE"  = "not_installed" ] && \
  [ "$OC_STATE"  = "not_installed" ] && \
  [ "$OCL_STATE" = "not_installed" ] && CT_STATE="not_installed"
  CT_VER="cc:${CC_VER:-?} oc:${OC_VER:-?}"
  [ "$OCL_STATE" != "not_installed" ] && CT_VER="${CT_VER} agy:${OCL_VER:-?}"
  draw_module "2" "◆" "Code Tools"   "$CT_STATE"  "$CT_VER"         "→ submenú"

  case "$OL_STATE" in running|stopped) OL_CMD="→ submenú" ;; *) OL_CMD="" ;; esac
  draw_module "3" "◎" "Ollama"       "$OL_STATE"  "$OL_VER"         "$OL_CMD"

  case "$EX_STATE" in ready)           EX_CMD="→ submenú" ;; *) EX_CMD="" ;; esac
  draw_module "4" "◈" "Expo/EAS/Git" "$EX_STATE"  "$EX_VER"         "$EX_CMD"

  case "$PY_STATE" in ready)           PY_CMD="→ submenú" ;; *) PY_CMD="" ;; esac
  draw_module "5" "◉" "Python"       "$PY_STATE"  "$PY_VER"         "$PY_CMD"

  case "$RM_STATE" in running|stopped) RM_CMD="→ submenú" ;; *) RM_CMD="" ;; esac
  RM_DISPLAY_VER="$RM_VER"
  [ -n "$RM_EXTRA" ] && RM_DISPLAY_VER="${RM_VER} ${RM_EXTRA}"
  draw_module "6" "⬡" "Remote"       "$RM_STATE"  "$RM_DISPLAY_VER" "$RM_CMD"

  case "$EN_STATE" in running|stopped|ready) EN_CMD="→ submenú" ;; *) EN_CMD="" ;; esac
  draw_module "8" "⏣" "Entorno"      "$EN_STATE"  "$EN_VER"         "$EN_CMD"

  # ── Separador + Backup ────────────────────────────────────────
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}[0]${NC} ◉ Backup / Restore"
  echo ""
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${DIM}[r] refrescar  [h] ayuda  [u] actualizar  [s] shell  [d] desinstalar${NC}"
  echo -e "  ${DIM}[p] rendimiento Termux${NC}"
  echo ""
  echo -n "  Opción: "
  read -r OPT < /dev/tty

  case "$OPT" in
    1)
      _require_proot  || continue
      _require_nativo || continue
      submenu_servicios "$N8N_STATE" "$CL_STATE" "$HM_STATE" ;;
    2)
      _require_proot  || continue
      _require_nativo || continue
      submenu_code_tools "$CC_STATE" "$OC_STATE" ;;
    3)
      _require_nativo || continue
      if [ "$OL_STATE" = "not_installed" ]; then
        install_module "Ollama" "ollama"
        _invalidate_cache
      else
        submenu_ollama "$OL_STATE"
      fi ;;
    4)
      _require_nativo || continue
      if [ "$EX_STATE" = "not_installed" ]; then
        install_module "Expo/EAS/Git" "expo"
        _invalidate_cache
      else
        submenu_expo
      fi ;;
    5)
      _require_nativo || continue
      if [ "$PY_STATE" = "not_installed" ]; then
        install_module "Python" "python"
        _invalidate_cache
      else
        submenu_python "$PY_VER"
      fi ;;
     6)
      _require_nativo || continue
      if [ "$RM_STATE" = "not_installed" ]; then
        install_module "Remote/SSH/Dashboard" "remote"
        _invalidate_cache
      else
        submenu_remote
      fi ;;
     8)
      _require_nativo || continue
      if [ "$EN_STATE" = "not_installed" ]; then
        install_module "Entorno" "entorno"
        _invalidate_cache
      else
        submenu_entorno "$EN_STATE"
      fi ;;
     0)
      _require_nativo || continue
      submenu_backup ;;
    d|D)
      _require_nativo || continue
      _require_proot  || continue
      submenu_desinstalar ;;
    r|R)
      _invalidate_cache
      # Forzar recarga de módulos si se quiere refrescar todo
      # (los flags de carga NO se resetean — las funciones ya están en memoria)
      continue ;;
    u|U)
      clear; echo ""
      echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
      echo    "  ║   Actualizando scripts desde GitHub...  ║"
      echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""

      # Scripts en raíz del repo → se descargan a ~/
      ROOT_SCRIPTS=(
        "menu.sh"
        "instalar.sh"
      )
      # Scripts en scripts/ del repo → se descargan a ~/
      INSTALL_SCRIPTS=(
        "install_n8n.sh" "install_claude.sh" "install_ollama.sh"
        "install_expo.sh" "install_python.sh" "install_ssh.sh"
        "install_remote.sh" "install_opencode.sh" "install_openclaw.sh"
        "install_antigravity.sh" "install_hermes.sh" "install_entorno.sh"
        "backup.sh" "restore.sh"
      )
      # Scripts en raíz del repo → se descargan a ~/scripts/
      MENU_SCRIPTS=(
        "menu_nativo.sh"
        "menu_proot.sh"
        "menu_entorno.sh"
      )

      UPDATE_OK=0; UPDATE_FAIL=0

      # Descargar scripts de raíz del repo a ~/
      for SCRIPT in "${ROOT_SCRIPTS[@]}"; do
        echo -n "  Descargando $SCRIPT... "
        TMP_DL="$HOME/${SCRIPT}.tmp"
        curl -fsSL "$REPO_RAW_ROOT/$SCRIPT" -o "$TMP_DL" 2>/dev/null || \
          wget -q "$REPO_RAW_ROOT/$SCRIPT" -O "$TMP_DL" 2>/dev/null
        if [ -f "$TMP_DL" ] && [ -s "$TMP_DL" ]; then
          mv "$TMP_DL" "$HOME/$SCRIPT"; chmod +x "$HOME/$SCRIPT"
          echo -e "${GREEN}✓${NC}"; UPDATE_OK=$((UPDATE_OK + 1))
        else
          rm -f "$TMP_DL"; echo -e "${RED}✗${NC}"; UPDATE_FAIL=$((UPDATE_FAIL + 1))
        fi
      done

      # Descargar install_*.sh, backup.sh, restore.sh desde scripts/ del repo a ~/
      for SCRIPT in "${INSTALL_SCRIPTS[@]}"; do
        echo -n "  Descargando $SCRIPT... "
        TMP_DL="$HOME/${SCRIPT}.tmp"
        curl -fsSL "$REPO_RAW/$SCRIPT" -o "$TMP_DL" 2>/dev/null || \
          wget -q "$REPO_RAW/$SCRIPT" -O "$TMP_DL" 2>/dev/null
        if [ -f "$TMP_DL" ] && [ -s "$TMP_DL" ]; then
          mv "$TMP_DL" "$HOME/$SCRIPT"; chmod +x "$HOME/$SCRIPT"
          echo -e "${GREEN}✓${NC}"; UPDATE_OK=$((UPDATE_OK + 1))
        else
          rm -f "$TMP_DL"; echo -e "${RED}✗${NC}"; UPDATE_FAIL=$((UPDATE_FAIL + 1))
        fi
      done

      # Descargar menu_nativo.sh y menu_proot.sh desde raíz del repo a ~/scripts/
      mkdir -p "$SCRIPTS_DIR"
      for SCRIPT in "${MENU_SCRIPTS[@]}"; do
        echo -n "  Descargando $SCRIPT... "
        TMP_DL="$SCRIPTS_DIR/${SCRIPT}.tmp"
        curl -fsSL "$REPO_RAW_ROOT/$SCRIPT" -o "$TMP_DL" 2>/dev/null || \
          wget -q "$REPO_RAW_ROOT/$SCRIPT" -O "$TMP_DL" 2>/dev/null
        if [ -f "$TMP_DL" ] && [ -s "$TMP_DL" ]; then
          mv "$TMP_DL" "$SCRIPTS_DIR/$SCRIPT"; chmod +x "$SCRIPTS_DIR/$SCRIPT"
          echo -e "${GREEN}✓${NC}"; UPDATE_OK=$((UPDATE_OK + 1))
        else
          rm -f "$TMP_DL"; echo -e "${RED}✗${NC}"; UPDATE_FAIL=$((UPDATE_FAIL + 1))
        fi
      done

      echo ""
      echo -e "  ${GREEN}[OK]${NC} $UPDATE_OK actualizados   ${RED}[FAIL]${NC} $UPDATE_FAIL fallidos"
      echo ""; read -r _ < /dev/tty
      # Recargar con la versión nueva — los módulos se recargarán al ser llamados
      exec bash "$HOME/menu.sh" ;;
    h|H)
      show_help ;;
    p|P)
      WL_STATUS="$(_wakelock_active && echo "${GREEN}● activo${NC}" || echo "${YELLOW}○ inactivo${NC}")"
      API_STATUS="$(_has_termux_api && echo "${GREEN}✓${NC}" || echo "${YELLOW}✗ instalar pkg termux-api${NC}")"

      while true; do
        clear; echo ""
        echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
        echo    "  ║  ⚡ Rendimiento & Keepalive Termux       ║"
        echo    "  ╠══════════════════════════════════════════╣"
        echo -e "  ║  ${NC}[1] Instalar paquetes de rendimiento     ${CYAN}${BOLD}║"
        echo -e "  ║  ${DIM}    htop nload zstd binutils clang       ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[2] Aplicar variables y aliases .bashrc  ${CYAN}${BOLD}║"
        echo -e "  ║  ${DIM}    MALLOC_ARENA_MAX=2 + alias boost     ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[3] Wake-lock manual (evita throttling)  ${CYAN}${BOLD}║"
        printf  "  ║      termux-api: %-24b${CYAN}${BOLD}║\n" "$API_STATUS"
        printf  "  ║      estado:     %-24b${CYAN}${BOLD}║\n" "$WL_STATUS"
        echo -e "  ║  ${NC}[4] Keepalive Android (no matar Termux)  ${CYAN}${BOLD}║"
        echo -e "  ║  ${DIM}    boot script + notification + wakelock${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[5] Parchear scripts de inicio           ${CYAN}${BOLD}║"
        echo -e "  ║  ${DIM}    wake-lock auto en ollama + n8n       ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[a] TODO lo anterior (recomendado)       ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[b] Volver al menú principal             ${CYAN}${BOLD}║"
        echo -e "  ╚══════════════════════════════════════════╝${NC}"
        echo ""; echo -n "  Opción: "
        read -r POPT < /dev/tty

        case "$POPT" in
          1|a|A)
            clear; echo ""
            _perf_info "Instalando paquetes de rendimiento..."
            pkg install -y \
              -o Dpkg::Options::="--force-confdef" \
              -o Dpkg::Options::="--force-confold" \
              htop nload zstd binutils clang termux-api 2>/dev/null \
              && _perf_ok "Paquetes instalados" \
              || _perf_warn "Algunos paquetes tuvieron advertencias"
            echo ""
            [ "$POPT" = "1" ] && { read -r _ < /dev/tty; continue; }
            ;&
          2|a|A)
            clear; echo ""
            _perf_info "Aplicando variables y aliases en ~/.bashrc..."
            BASHRC_P="$HOME/.bashrc"; touch "$BASHRC_P"
            _add_bashrc "export MALLOC_ARENA_MAX=2"
            _add_bashrc "export OLLAMA_MAX_LOADED_MODELS=1"
            _add_bashrc "export OLLAMA_NUM_PARALLEL=1"
            _add_bashrc "export OLLAMA_FLASH_ATTENTION=1"
            if ! grep -q "alias termux-boost" "$BASHRC_P" 2>/dev/null; then
              cat >> "$BASHRC_P" << 'ALIAS_BOOST'

# ── termux-ai-stack: aliases de rendimiento ──
alias termux-boost='termux-wake-lock 2>/dev/null; echo "[OK] Wake-lock activado"'
alias termux-unboost='termux-wake-unlock 2>/dev/null; echo "[OK] Wake-lock desactivado"'
alias ollama-fast='nice -n -10 ollama serve'
alias mem-check='free -m | awk "/^Mem:/{printf \"RAM libre: %.1f GB / Total: %.1f GB\n\", \$7/1024, \$2/1024}"'
ALIAS_BOOST
            fi
            _perf_ok "MALLOC_ARENA_MAX=2 — reduce fragmentación de memoria"
            _perf_ok "OLLAMA_MAX_LOADED_MODELS=1 — evita OOM"
            _perf_ok "OLLAMA_NUM_PARALLEL=1 — conserva RAM ARM64"
            _perf_ok "OLLAMA_FLASH_ATTENTION=1 — atención más eficiente"
            _perf_ok "aliases termux-boost / unboost / ollama-fast / mem-check"
            echo ""; _perf_warn "Ejecuta: source ~/.bashrc  para activar en sesión actual"
            echo ""
            [ "$POPT" = "2" ] && { read -r _ < /dev/tty; continue; }
            ;&
          3|a|A)
            clear; echo ""
            if ! _has_termux_api; then
              _perf_warn "termux-api no instalado. Instalando..."
              pkg install -y termux-api 2>/dev/null \
                && _perf_ok "termux-api instalado" \
                || { _perf_warn "Instala Termux:API desde F-Droid"; read -r _ < /dev/tty; continue; }
            fi
            if _wakelock_active; then
              _perf_warn "Wake-lock ya está activo"
            else
              termux-wake-lock 2>/dev/null &
              sleep 1
              _wakelock_active \
                && _perf_ok "Wake-lock activado — CPU sin throttling" \
                || _perf_warn "Wake-lock iniciado (verifica: pgrep termux-wake-lock)"
            fi
            WL_STATUS="${GREEN}● activo${NC}"
            echo ""
            [ "$POPT" = "3" ] && { read -r _ < /dev/tty; continue; }
            ;&
          4|a|A)
            clear; echo ""
            _perf_info "Configurando keepalive para evitar que Android mate Termux..."
            echo ""
            BOOT_DIR="$HOME/.termux/boot"; mkdir -p "$BOOT_DIR"
            cat > "$BOOT_DIR/start_services.sh" << BOOT_EOF
#!/data/data/com.termux/files/usr/bin/bash
# Auto-generado por termux-ai-stack [p]
termux-wake-lock 2>/dev/null &
sleep 10
termux-notification \
  --title "Termux AI Stack" \
  --content "Servicios iniciados — keepalive activo" \
  --id 1001 --ongoing 2>/dev/null &
[ -f "$N8N_SCRIPTS/start_servidor.sh" ] && \
  tmux new-session -d -s "n8n-server" "bash $N8N_SCRIPTS/start_servidor.sh" 2>/dev/null
[ -f "$OLLAMA_SCRIPTS/ollama_start.sh" ] && \
  tmux new-session -d -s "ollama-server" "bash $OLLAMA_SCRIPTS/ollama_start.sh" 2>/dev/null
BOOT_EOF
            chmod +x "$BOOT_DIR/start_services.sh"
            _perf_ok "Boot script: $BOOT_DIR/start_services.sh"
            if _has_termux_api; then
              termux-notification \
                --title "Termux AI Stack" --content "Stack activo — keepalive ON" \
                --id 1001 --ongoing 2>/dev/null \
                && _perf_ok "Notificación persistente activa" \
                || _perf_warn "No se pudo crear notificación — instala Termux:API"
            else
              _perf_warn "Instala Termux:API desde F-Droid para notificación persistente"
            fi
            echo ""
            _perf_warn "Para auto-inicio: instala Termux:Boot desde F-Droid"
            echo ""
            [ "$POPT" = "4" ] && { read -r _ < /dev/tty; continue; }
            ;&
          5|a|A)
            clear; echo ""
            _perf_info "Parcheando scripts de inicio con wake-lock automático..."
            echo ""
            _patch_wakelock() {
              local script="$1" label="$2"
              [ ! -f "$script" ] && { _perf_warn "$label: $script no encontrado"; return; }
              grep -q "termux-wake-lock" "$script" 2>/dev/null && {
                _perf_ok "$label: ya tiene wake-lock"; return
              }
              local SHEBANG; SHEBANG=$(head -1 "$script")
              local REST;    REST=$(tail -n +2 "$script")
              { echo "$SHEBANG"
                echo "# wake-lock auto — agregado por termux-ai-stack [p]"
                echo "termux-wake-lock 2>/dev/null &"
                echo ""
                echo "$REST"
              } > "${script}.tmp" && mv "${script}.tmp" "$script"
              chmod +x "$script"
              _perf_ok "$label: wake-lock inyectado"
            }
            _patch_wakelock "$OLLAMA_SCRIPTS/ollama_start.sh" "Ollama"
            _patch_wakelock "$N8N_SCRIPTS/start_servidor.sh"  "n8n"
            echo ""
            [ "$POPT" = "5" ] && { read -r _ < /dev/tty; continue; }
            ;;
          b|B|"") break ;;
          *) _perf_warn "Opción inválida"; sleep 1 ;;
        esac

        if [ "$POPT" = "a" ] || [ "$POPT" = "A" ]; then
          echo ""
          _perf_ok "━━━ TODO aplicado correctamente ━━━"
          echo ""
          echo -e "  ${DIM}Recuerda: source ~/.bashrc  para activar aliases${NC}"
          echo -e "  ${DIM}Instala Termux:Boot y Termux:API desde F-Droid${NC}"
          echo ""; read -r _ < /dev/tty
        fi

        WL_STATUS="$(_wakelock_active && echo "${GREEN}● activo${NC}" || echo "${YELLOW}○ inactivo${NC}")"
        API_STATUS="$(_has_termux_api && echo "${GREEN}✓${NC}" || echo "${YELLOW}✗ instalar pkg termux-api${NC}")"
      done ;;
    s|S|q|Q|"")
      clear; echo ""
      echo -e "  ${DIM}termux-ai-stack · escribe 'menu' para volver${NC}"; echo ""
      break ;;
  esac

done

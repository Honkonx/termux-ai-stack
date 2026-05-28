#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · menu.sh
#  Orquestador principal — carga módulos bajo demanda
#
#  NAVEGACIÓN:
#    [1-6]  → submenú del módulo
#    [0]    → backup / restore
#    [r]    → refrescar   [h] → ayuda
#    [u]    → actualizar scripts desde GitHub
#    [d]    → desinstalar módulo
#    [s/q]  → salir al shell
#    [p]    → rendimiento & keepalive
#
#  MÓDULOS:
#    [1] Servicios     — n8n + OpenClaw   (proot)
#    [2] Code Tools    — Claude + OpenCode (nativo + proot)
#    [3] Ollama        — modelos IA local  (nativo)
#    [4] Expo/EAS/Git  — builds móviles    (nativo)
#    [5] Python        — Python + SQLite + Trading (nativo)
#    [6] Remote        — SSH + Dashboard   (nativo)
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

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

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
_CC_CACHE=""   ; _CC_REFRESH=0
_OC_CACHE=""   ; _OC_CACHE_TS=0
_CLAW_CACHE="" ; _CLAW_CACHE_TS=0
_OCL_CACHE=""  ; _OCL_REFRESH=0
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

# ════════════════════════════════════════════
#  DETECCIÓN ROOTFS PROOT — canónica por directorio
#  NO usar proot-distro list (falsos negativos — ARCHITECTURE.md §3.11)
#  Variable global — heredada por menu_proot.sh via source
# ════════════════════════════════════════════
DISTRO_NAME=""
ROOTFS_PATH=""
_ROOTFS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/installed-rootfs"
if [ -d "$_ROOTFS_BASE" ]; then
  for _d in "$_ROOTFS_BASE"/*/; do
    if [ -f "${_d}bin/bash" ]; then
      DISTRO_NAME=$(basename "$_d")
      ROOTFS_PATH="$_d"
      break
    fi
  done
fi
unset _d

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
    "$EXPO_SCRIPTS"
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
  _mv_legacy "dashboard_start.sh" "$REMOTE_SCRIPTS"
  _mv_legacy "dashboard_stop.sh"  "$REMOTE_SCRIPTS"
  _mv_legacy "dashboard_server.py" "$REMOTE_SCRIPTS"

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
      install_*.sh|menu_nativo.sh|menu_proot.sh|backup.sh|restore.sh|instalar.sh)
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
check_n8n()             { _run_check_proot  check_n8n            "$@"; }
check_opencode_cached() { _run_check_proot  check_opencode_cached "$@"; }
check_openclaw_cached() { _run_check_proot  check_openclaw_cached "$@"; }
check_openclaude()      { _run_check_nativo check_openclaude      "$@"; }

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
  # 1. Forzar reload de módulos en la próxima iteración
  #    Las funciones en memoria quedan del source anterior —
  #    tras instalar n8n/openclaw/opencode el proot cambió
  _PROOT_LOADED=0
  _NATIVO_LOADED=0

  # 2. Limpiar caché de estado — el módulo acaba de instalarse
  _invalidate_cache

  # 3. Drenar stdin residual — proot/npm/wget pueden dejar
  #    bytes en el buffer de /dev/tty que el siguiente
  #    read -r OPT < /dev/tty consumiría como opción
  #    Timeout 0 = no bloquea si no hay nada que leer
  local _drain
  while IFS= read -r -t 0 _drain < /dev/tty 2>/dev/null; do :; done

  # 4. Mensaje orientativo — el usuario sabe que el estado se refresca
  echo -e "\n  ${CYAN}[INFO]${NC} Recargando stack..."
}

# ════════════════════════════════════════════
#  INSTALL_MODULE — lógica de instalación
#  Disponible sin módulos cargados.
# ════════════════════════════════════════════
install_module() {
  local name="$1" module_key="$2"
  local script="install_${module_key}.sh"
  local dest="$HOME/$script"
  clear; echo ""

  if [ "$module_key" = "n8n" ]; then
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ¿Cómo instalar n8n?                     ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Todo desde GitHub Releases${CYAN}${BOLD}          ║"
    echo -e "  ║      ${DIM}rootfs + n8n precompilados · recomend${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Todo limpio${CYAN}${BOLD}                          ║"
    echo -e "  ║      ${DIM}proot-distro + npm install · 25-40 min${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Rootfs GitHub + n8n limpio${CYAN}${BOLD}           ║"
    echo -e "  ║  ${NC}[4] Rootfs limpio + n8n GitHub${CYAN}${BOLD}           ║"
    echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                             ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r INST_OPT < /dev/tty
    case "$INST_OPT" in
      1|2|3|4)
        _ensure_restore_for_install || return 1
        _ensure_install_script "$script" || return 1
        export N8N_INSTALL_MODE="$INST_OPT"
        bash "$dest" < /dev/tty
        unset N8N_INSTALL_MODE
        echo ""; read -r _ < /dev/tty
        _post_install_cleanup ;;
      b|B|"") return 0 ;;
    esac
    return 0
  fi

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
        echo -e "\n${CYAN}${BOLD}  Instalando ${name}...${NC}\n"
        _ensure_install_script "$script" || return 1
        bash "$dest" < /dev/tty
        echo ""; read -r _ < /dev/tty
        _post_install_cleanup ;;
    esac
    return 0
  fi

  if [ "$module_key" = "ollama" ]; then
    echo -e "\n${CYAN}${BOLD}  Instalando Ollama...${NC}\n"
    _ensure_install_script "$script" || return 1
    bash "$dest" < /dev/tty
    echo ""; read -r _ < /dev/tty
    _post_install_cleanup
    return 0
  fi

  # Claude: pass-through directo a install_claude.sh
  # El nuevo instalador tiene su propio flujo de 2 niveles (método + fuente)
  # NO duplicar lógica aquí
  if [ "$module_key" = "claude" ]; then
    _ensure_install_script "install_claude.sh" || return 1
    bash "$HOME/install_claude.sh" < /dev/tty
    echo ""; read -r _ < /dev/tty
    _post_install_cleanup
    return 0
  fi

  # OpenClaude: pass-through directo a install_openclaude.sh
  # Instalación npm rápida — sin menú fuente, sin GitHub
  if [ "$module_key" = "openclaude" ]; then
    _ensure_install_script "install_openclaude.sh" || return 1
    bash "$HOME/install_openclaude.sh" < /dev/tty
    echo ""; read -r _ < /dev/tty
    _post_install_cleanup
    return 0
  fi

  # Expo, opencode, openclaw — menú fuente estándar
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "¿Cómo instalar ${name}?"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}[1] Instalación limpia${CYAN}${BOLD}                  ║"
  echo -e "  ║  ${NC}[2] Desde GitHub Releases${CYAN}${BOLD}               ║"
  echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                            ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""; echo -n "  Opción: "
  read -r INST_OPT < /dev/tty
  case "$INST_OPT" in
    2)
      _ensure_restore_for_install || return 1
      bash "$HOME/restore.sh" --module "$module_key" < /dev/tty
      echo ""; read -r _ < /dev/tty
      _post_install_cleanup ;;
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
  echo    "  ║  openclaude  oc  (alias corto)"
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
  _CC_REFRESH=1;  _CC_CACHE=""
  _OCL_REFRESH=1; _OCL_CACHE=""
  _OC_CACHE="";   _OC_CACHE_TS=0
  _CLAW_CACHE=""; _CLAW_CACHE_TS=0
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

  # OpenClaude: usa caché si está vigente (nativo — rápido)
  if [ -z "$_OCL_CACHE" ] || [ "$_OCL_REFRESH" = "1" ]; then
    { _OCL_CACHE=$(check_openclaude 2>/dev/null); _OCL_REFRESH=0
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

  if [ "$_OCL_FROM_FILE" = "1" ]; then
    _OCL_CACHE=$(cat "${_TMP}_ocl" 2>/dev/null)
  fi
  IFS='|' read -r OCL_STATE OCL_VER OCL_EXTRA <<< "$_OCL_CACHE"

  if [ "$_CC_FROM_FILE" = "1" ]; then
    _CC_CACHE=$(cat "${_TMP}_cc" 2>/dev/null)
  fi
  IFS='|' read -r CC_STATE CC_VER CC_EXTRA <<< "$_CC_CACHE"

  if [ "$_PROOT_FROM_FILE" = "1" ]; then
    _OC_CACHE=$(cat   "${_TMP}_oc" 2>/dev/null)
    _CLAW_CACHE=$(cat "${_TMP}_cl" 2>/dev/null)
    _OC_CACHE_TS=$SECONDS
    _CLAW_CACHE_TS=$SECONDS
  fi
  IFS='|' read -r CL_STATE CL_VER CL_EXTRA <<< "$_CLAW_CACHE"
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
  # [1] Servicios — n8n + OpenClaw
  SVC_STATE="not_installed"
  { [ "$N8N_STATE" != "not_installed" ] || \
    [ "$CL_STATE"  != "not_installed" ]; } && SVC_STATE="ready"
  { [ "$N8N_STATE" = "running" ] || \
    [ "$CL_STATE"  = "running" ]; }        && SVC_STATE="running"
  SVC_VER=""
  [ "$N8N_STATE" != "not_installed" ] && SVC_VER="n8n:${N8N_VER:-?}"
  [ "$CL_STATE"  != "not_installed" ] && SVC_VER="${SVC_VER:+${SVC_VER} }claw:${CL_VER:-?}"
  [ -z "$SVC_VER" ] && SVC_VER="──────────"
  draw_module "1" "⬡" "Servicios"    "$SVC_STATE" "$SVC_VER"        "→ submenú"

  # [2] Code Tools — Claude Code + OpenCode + OpenClaude
  CT_STATE="ready"
  [ "$CC_STATE"  = "not_installed" ] && \
  [ "$OC_STATE"  = "not_installed" ] && \
  [ "$OCL_STATE" = "not_installed" ] && CT_STATE="not_installed"
  CT_VER="cc:${CC_VER:-?} oc:${OC_VER:-?}"
  [ "$OCL_STATE" != "not_installed" ] && CT_VER="${CT_VER} ocl:${OCL_VER:-?}"
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
      _require_proot || continue
      submenu_servicios "$N8N_STATE" "$CL_STATE" ;;
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

      # Scripts que van en ~/  (puntos de entrada)
      ROOT_SCRIPTS=(
        "menu.sh"
        "install_n8n.sh" "install_claude.sh" "install_ollama.sh"
        "install_expo.sh" "install_python.sh" "install_ssh.sh"
        "install_remote.sh" "install_opencode.sh" "install_openclaw.sh"
        "install_openclaude.sh"
        "backup.sh" "restore.sh"
      )
      # Scripts que van en ~/scripts/  (módulos de menú)
      MENU_SCRIPTS=(
        "menu_nativo.sh"
        "menu_proot.sh"
      )

      UPDATE_OK=0; UPDATE_FAIL=0

      # ESTRUCTURA DEL REPO:
      #   Raiz  (REPO_RAW_ROOT): menu.sh, instalar.sh, menu_nativo.sh, menu_proot.sh
      #   scripts/ (REPO_RAW):  install_*.sh, backup.sh, restore.sh
      for SCRIPT in "${ROOT_SCRIPTS[@]}"; do
        echo -n "  Descargando $SCRIPT... "
        TMP_DL="$HOME/${SCRIPT}.tmp"
        if [ "$SCRIPT" = "menu.sh" ]; then
          _DL_URL="$REPO_RAW_ROOT/$SCRIPT"
        else
          _DL_URL="$REPO_RAW/$SCRIPT"
        fi
        curl -fsSL "$_DL_URL" -o "$TMP_DL" 2>/dev/null || \
          wget -q "$_DL_URL" -O "$TMP_DL" 2>/dev/null
        if [ -f "$TMP_DL" ] && [ -s "$TMP_DL" ]; then
          mv "$TMP_DL" "$HOME/$SCRIPT"; chmod +x "$HOME/$SCRIPT"
          echo -e "${GREEN}✓${NC}"; UPDATE_OK=$((UPDATE_OK + 1))
        else
          rm -f "$TMP_DL"; echo -e "${RED}\u2717${NC}"; UPDATE_FAIL=$((UPDATE_FAIL + 1))
        fi
      done
      unset _DL_URL

      # Descargar módulos de menú a ~/scripts/
      # menu_nativo.sh y menu_proot.sh están en raíz del repo
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

#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · menu.sh
#  Dashboard TUI — panel de control principal
#
#  NAVEGACIÓN:
#    [1-6]  → acción / submenú del módulo
#    [0]    → backup / restore
#    [r]    → refrescar   [h] → ayuda
#    [u]    → actualizar scripts desde GitHub
#    [d]    → desinstalar módulo
#    [s/q]  → salir al shell
#
#  MÓDULOS v3.7.0:
#    [1] n8n + cloudflared
#    [2] Claude Code
#    [3] Ollama
#    [4] Expo / EAS / Git
#    [5] Python + SQLite
#    [6] Remote (SSH + Dashboard + Cloudflared SSH)  ← NUEVO unificado
#    [0] Backup / Restore
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 3.7.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

REPO_RAW="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script"
REGISTRY="$HOME/.android_server_registry"
EAS_PROJECT_FILE="$HOME/.eas_active_project"

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Helpers EAS ───────────────────────────────────────────────
_eas_get_project() { [ -f "$EAS_PROJECT_FILE" ] && cat "$EAS_PROJECT_FILE" 2>/dev/null || echo ""; }
_eas_set_project() { echo "$1" > "$EAS_PROJECT_FILE"; }

# ── Registry ─────────────────────────────────────────────────
get_reg() { grep "^${1}\.${2}=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2; }

# ── IP local ─────────────────────────────────────────────────
_get_ip() {
  local ip
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ip addr show 2>/dev/null | grep "inet " | grep -v "127\." | awk '{print $2}' | cut -d'/' -f1 | head -1)
  echo "${ip:-<tu_IP_WiFi>}"
}

# ── Claude CLI path (workaround ARM64) ───────────────────────
find_claude_cli() {
  # 1. Leer ruta desde el wrapper — más confiable que npm root -g
  #    El wrapper fue creado por install_claude.sh con la ruta exacta
  local wrapper="$TERMUX_PREFIX/bin/claude"
  if [ -f "$wrapper" ]; then
    local cli_from_wrapper
    cli_from_wrapper=$(grep "node " "$wrapper" 2>/dev/null | grep "cli\.js" |       grep -oE '/[^ "]+cli\.js' | head -1)
    [ -n "$cli_from_wrapper" ] && [ -f "$cli_from_wrapper" ] && {
      echo "$cli_from_wrapper"; return
    }
  fi

  # 2. Rutas conocidas en Termux (sin depender de npm en PATH)
  #    Cubre nodejs, nodejs-lts y npm global personalizado
  local KNOWN=(
    "/data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js"
    "$HOME/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js"
    "$HOME/.node_modules/@anthropic-ai/claude-code/cli.js"
  )
  for p in "${KNOWN[@]}"; do
    [ -f "$p" ] && { echo "$p"; return; }
  done

  # 3. Fallback: npm root -g (requiere npm en PATH)
  local npm_root; npm_root=$(npm root -g 2>/dev/null)
  echo "${npm_root}/@anthropic-ai/claude-code/cli.js"
}

# ════════════════════════════════════════════
#  DETECCIÓN DE ESTADO DE MÓDULOS
# ════════════════════════════════════════════
check_n8n() {
  [ "$(get_reg n8n installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver; ver=$(get_reg n8n version)
  tmux has-session -t "n8n-server" 2>/dev/null && echo "running|${ver}|" || echo "stopped|${ver}|"
}

check_claude() {
  local cli_path wrapper_path
  cli_path=$(find_claude_cli)
  wrapper_path="$TERMUX_PREFIX/bin/claude"
  local wrapper_ok=false cli_ok=false
  [ -f "$wrapper_path" ] && [ -s "$wrapper_path" ] && wrapper_ok=true
  [ -f "$cli_path" ]     && [ -s "$cli_path" ]     && cli_ok=true

  if [ "$wrapper_ok" = "false" ] && [ "$cli_ok" = "false" ]; then
    echo "not_installed||"; return
  fi

  # Reparar registry silenciosamente si wrapper existe pero registry no
  if [ "$(get_reg claude_code installed)" != "true" ] && \
     { [ "$wrapper_ok" = "true" ] || [ "$cli_ok" = "true" ]; }; then
    local ver_repair
    ver_repair=$(node "$cli_path" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver_repair" ] && ver_repair="2.1.111"
    grep -v "^claude_code\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null || touch "$REGISTRY.tmp"
    cat >> "$REGISTRY.tmp" << EOF
claude_code.installed=true
claude_code.version=$ver_repair
claude_code.install_date=$(date +%Y-%m-%d)
claude_code.location=termux_native
EOF
    mv "$REGISTRY.tmp" "$REGISTRY"
  fi

  [ "$cli_ok" = "false" ] && [ "$wrapper_ok" = "true" ] && { echo "ready|err:reinstalar|"; return; }

  local ver; ver=$(get_reg claude_code version)
  if [ -z "$ver" ] || [ "$ver" = "unknown" ]; then
    ver=$(node "$cli_path" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  fi
  [ -z "$ver" ] && ver="err:reinstalar"
  echo "ready|${ver}|"
}

check_ollama() {
  [ "$(get_reg ollama installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver; ver=$(pkg show ollama 2>/dev/null | grep "^Version:" | awk '{print $2}')
  [ -z "$ver" ] && ver=$(get_reg ollama version)
  [ -z "$ver" ] && ver="?"
  tmux has-session -t "ollama-server" 2>/dev/null && echo "running|${ver}|" || echo "stopped|${ver}|"
}

check_expo() {
  [ "$(get_reg expo installed)" = "true" ] || { echo "not_installed||"; return; }
  echo "ready|$(get_reg expo version)|"
}

check_python() {
  [ "$(get_reg python installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver; ver=$(get_reg python version)
  [ -z "$ver" ] && ver="?"
  echo "ready|${ver}|"
}

# Remote: combina SSH + Dashboard en un solo check
# Estado: running si SSH activo O dashboard activo, stopped si ninguno
check_remote() {
  local ssh_installed dashboard_installed
  ssh_installed=$(get_reg ssh installed)
  dashboard_installed=$(get_reg dashboard installed)

  # Verificar archivos físicos como fallback al registry
  local has_ssh=false has_dashboard=false
  { [ "$ssh_installed" = "true" ] || command -v sshd &>/dev/null; } && has_ssh=true
  { [ "$dashboard_installed" = "true" ] || \
    [ -f "$HOME/dashboard_server.py" ] || \
    [ -f "$HOME/dashboard/dashboard_server.py" ]; } && has_dashboard=true

  if [ "$has_ssh" = "false" ] && [ "$has_dashboard" = "false" ]; then
    echo "not_installed||"; return
  fi

  local ssh_ver; ssh_ver=$(get_reg ssh version)
  # Normalizar versión: quitar prefijo "v", quedarse con número limpio
  ssh_ver="${ssh_ver#v}"
  # Si viene como "OpenSSH_10.3p1" → queda legible, si es vacío mostrar "?"
  [ -z "$ssh_ver" ] && ssh_ver="?"

  local ssh_active=false db_active=false
  pgrep -x sshd &>/dev/null && ssh_active=true
  pgrep -f "dashboard_server.py" &>/dev/null && db_active=true

  local status_detail=""
  $ssh_active && status_detail="SSH●"
  $db_active  && status_detail="${status_detail}${status_detail:+ }DB●"
  [ -z "$status_detail" ] && status_detail="listo"

  if $ssh_active || $db_active; then
    echo "running|${ssh_ver}|${status_detail}"
  else
    echo "stopped|${ssh_ver}|"
  fi
}

# ── Dibujar módulo ────────────────────────────────────────────
draw_module() {
  local num="$1" icon="$2" name="$3" state="$4" ver="$5" cmd="$6"
  local status_col cmd_col

  case "$state" in
    running)      status_col="${GREEN}● activo   ${NC}"; cmd_col="${CYAN}${cmd}${NC}" ;;
    stopped)      status_col="${GREEN}● listo    ${NC}"; cmd_col="${CYAN}${cmd}${NC}" ;;
    ready)        status_col="${GREEN}● listo    ${NC}"; cmd_col="${CYAN}${cmd}${NC}" ;;
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

# ── Asegurar scripts disponibles ─────────────────────────────
_ensure_restore_for_install() {
  if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
    echo -e "\n  ${YELLOW}[AVISO]${NC} restore.sh no encontrado — descargando..."
    curl -fsSL "$REPO_RAW/restore.sh" -o "$HOME/restore.sh" 2>/dev/null || \
      wget -q "$REPO_RAW/restore.sh" -O "$HOME/restore.sh" 2>/dev/null
    [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ] && {
      echo -e "  ${RED}[ERROR]${NC} No se pudo obtener restore.sh"
      read -r _ < /dev/tty; return 1
    }
    chmod +x "$HOME/restore.sh"
  fi
  return 0
}

_ensure_install_script() {
  local script="$1"
  local dest="$HOME/$script"
  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    echo -e "  ${YELLOW}[AVISO]${NC} ~/$script no encontrado — re-descargando..."
    rm -f "$dest"
    curl -fsSL "$REPO_RAW/$script" -o "$dest" 2>/dev/null || \
      wget -q "$REPO_RAW/$script" -O "$dest" 2>/dev/null
    [ ! -f "$dest" ] || [ ! -s "$dest" ] && {
      echo -e "\n  ${RED}[ERROR]${NC} No se pudo obtener $script"
      read -r _ < /dev/tty; rm -f "$dest"; return 1
    }
    chmod +x "$dest"
  fi
  return 0
}

# ── Instalar módulo ───────────────────────────────────────────
install_module() {
  local name="$1"
  local module_key="$2"
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
    echo ""
    read -r -p "  Opción: " INST_OPT < /dev/tty
    case "$INST_OPT" in
      1|2|3|4)
        _ensure_restore_for_install || return 1
        _ensure_install_script "$script" || return 1
        export N8N_INSTALL_MODE="$INST_OPT"
        bash "$dest" < /dev/tty
        unset N8N_INSTALL_MODE
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") return 0 ;;
    esac
    return 0
  fi

  # Python, SSH, Remote → solo instalación limpia (son paquetes ligeros pkg)
  if [ "$module_key" = "python" ] || [ "$module_key" = "ssh" ] || [ "$module_key" = "remote" ]; then
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    printf  "  ║  %-40s║\n" "Instalar ${name}"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Instalación limpia${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                            ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Opción: " INST_OPT < /dev/tty
    case "$INST_OPT" in
      b|B|"") return 0 ;;
      1|*)
        echo -e "\n${CYAN}${BOLD}  Instalando ${name}...${NC}\n"
        _ensure_install_script "$script" || return 1
        bash "$dest" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
    esac
    return 0
  fi

  # Claude: aviso especial ARM64
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "¿Cómo instalar ${name}?"
  echo    "  ╠══════════════════════════════════════════╣"
  if [ "$module_key" = "claude" ]; then
    echo -e "  ║  ${NC}[1] Instalar via npm     ${GREEN}← RECOMENDADO${CYAN}${BOLD}  ║"
    echo -e "  ║  ${GREEN}    ✓ npm install @2.1.111${CYAN}${BOLD}               ║"
    echo -e "  ║  ${NC}[2] Desde GitHub Releases${CYAN}${BOLD}               ║"
  else
    echo -e "  ║  ${NC}[1] Instalación limpia${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[2] Desde GitHub Releases${CYAN}${BOLD}               ║"
  fi
  echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                            ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""; read -r -p "  Opción: " INST_OPT < /dev/tty

  case "$INST_OPT" in
    2)
      _ensure_restore_for_install || return 1
      bash "$HOME/restore.sh" --module "$module_key" < /dev/tty
      echo ""; read -r _ < /dev/tty ;;
    b|B|"") return 0 ;;
    1|*)
      echo -e "\n${CYAN}${BOLD}  Instalando ${name}...${NC}\n"
      _ensure_install_script "$script" || return 1
      bash "$dest" < /dev/tty
      echo ""; read -r _ < /dev/tty ;;
  esac
}

# ════════════════════════════════════════════
#  AYUDA
# ════════════════════════════════════════════
show_help() {
  clear; echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║     termux-ai-stack · AYUDA  v3.7.0    ║"
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
  echo -e "  ║  REMOTE (SSH + Dashboard)${NC}"
  echo    "  ║  SSH WiFi: ssh -p 8022 user@IP"
  echo    "  ║  SSH Tunnel: cloudflared access ssh"
  echo    "  ║  Dashboard: http://IP:8080"
  echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  read -r -p "  Presiona ENTER para volver..." _ < /dev/tty
}

# ════════════════════════════════════════════
#  SUBMENÚ N8N (sin cambios — completo)
# ════════════════════════════════════════════
submenu_n8n() {
  local state="$1"
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    [ "$state" = "running" ] && echo "  ║  ⬡ N8N  ● activo                        ║" || \
                                echo "  ║  ⬡ N8N  ● listo                         ║"
    [ -f "$HOME/.cf_token" ] && [ -s "$HOME/.cf_token" ] && \
      echo -e "  ║  ${NC}Tunnel: URL fija ${GREEN}●${NC}${CYAN}${BOLD}                   ║" || \
      echo -e "  ║  ${NC}Tunnel: URL temporal ${YELLOW}○${NC}${CYAN}${BOLD}                 ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar n8n + cloudflared${CYAN}${BOLD}          ║"
    echo -e "  ║  ${NC}[2] Detener n8n + cloudflared${CYAN}${BOLD}          ║"
    echo -e "  ║  ${NC}[3] Ver URL pública${CYAN}${BOLD}                    ║"
    echo -e "  ║  ${NC}[4] Logs en vivo${CYAN}${BOLD}                       ║"
    echo -e "  ║  ${NC}[5] Consola Debian${CYAN}${BOLD}                     ║"
    echo -e "  ║  ${NC}[6] Ver estado del sistema${CYAN}${BOLD}             ║"
    echo -e "  ║  ${NC}[7] Token cloudflared${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[8] Configurar URL webhook${CYAN}${BOLD}             ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        if [ -f "$HOME/start_servidor.sh" ]; then
          bash "$HOME/start_servidor.sh" < /dev/tty
        else
          echo -e "  ${RED}[ERROR]${NC} start_servidor.sh no encontrado"
        fi
        echo ""; read -r _ < /dev/tty
        tmux has-session -t "n8n-server" 2>/dev/null && state="running" || state="stopped" ;;
      2)
        clear; echo ""
        bash "$HOME/stop_servidor.sh" 2>/dev/null || \
          tmux kill-session -t "n8n-server" 2>/dev/null
        sleep 1; echo -e "  ${GREEN}[OK]${NC} n8n detenido"
        echo ""; read -r _ < /dev/tty
        state="stopped" ;;
      3)
        clear; echo ""
        bash "$HOME/ver_url.sh" 2>/dev/null || {
          URL=$(cat "$HOME/.last_cf_url" 2>/dev/null)
          [ -n "$URL" ] && echo -e "  ${GREEN}URL:${NC} $URL" || echo -e "  ${YELLOW}[AVISO]${NC} n8n no está corriendo o URL no disponible"
        }
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        echo -e "  ${CYAN}Logs n8n — Ctrl+C para salir${NC}"; echo ""
        tmux has-session -t "n8n-server" 2>/dev/null && \
          tmux attach-session -t "n8n-server" || \
          echo -e "  ${YELLOW}[AVISO]${NC} n8n no está corriendo"
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        echo -e "  ${CYAN}Consola Debian — escribe 'exit' para volver${NC}"; echo ""
        proot-distro login debian 2>/dev/null || \
          echo -e "  ${RED}[ERROR]${NC} Proot Debian no encontrado"
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        bash "$HOME/n8n_status.sh" 2>/dev/null || {
          echo -e "  ${BOLD}Estado n8n:${NC}"
          tmux has-session -t "n8n-server" 2>/dev/null && \
            echo -e "  ${GREEN}● Corriendo${NC}" || echo -e "  ${YELLOW}○ Detenido${NC}"
          CF_URL=$(cat "$HOME/.last_cf_url" 2>/dev/null)
          [ -n "$CF_URL" ] && echo -e "  URL: ${CF_URL}"
        }
        echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        echo -e "  ${BOLD}Token cloudflared (URL fija)${NC}"; echo ""
        CF_CURRENT=$(cat "$HOME/.cf_token" 2>/dev/null)
        [ -n "$CF_CURRENT" ] && echo -e "  Token actual: ${GREEN}configurado${NC}" || \
          echo -e "  Token actual: ${YELLOW}no configurado (URL temporal)${NC}"
        echo ""; echo "  (ENTER para cancelar)"
        read -r -p "  Nuevo token (o ENTER para quitar): " NEW_CF < /dev/tty
        if [ -n "$NEW_CF" ]; then
          echo "$NEW_CF" > "$HOME/.cf_token"
          echo -e "  ${GREEN}[OK]${NC} Token guardado — URL fija activada"
        else
          read -r -p "  ¿Quitar token actual? (s/n): " RM_CF < /dev/tty
          [ "$RM_CF" = "s" ] || [ "$RM_CF" = "S" ] && {
            rm -f "$HOME/.cf_token"
            echo -e "  ${GREEN}[OK]${NC} Token eliminado — modo URL temporal"
          }
        fi
        echo ""; read -r _ < /dev/tty ;;
      8)
        clear; echo ""
        echo -e "  ${BOLD}Configurar URL webhook n8n${NC}"; echo ""
        CURRENT_WH=$(grep "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" 2>/dev/null | cut -d'=' -f2)
        [ -n "$CURRENT_WH" ] && echo -e "  URL actual: ${GREEN}${CURRENT_WH}${NC}" || \
          echo -e "  URL actual: ${YELLOW}no configurada${NC}"
        echo ""; echo "  (ENTER sin escribir = cancelar)"
        read -r -p "  Nueva URL webhook: " NEW_WH < /dev/tty
        if [ -n "$NEW_WH" ]; then
          grep -v "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" > "$HOME/.env_n8n.tmp" 2>/dev/null || touch "$HOME/.env_n8n.tmp"
          echo "N8N_WEBHOOK_URL=${NEW_WH}" >> "$HOME/.env_n8n.tmp"
          mv "$HOME/.env_n8n.tmp" "$HOME/.env_n8n"
          echo "$NEW_WH" > "$HOME/.last_cf_url"
          echo -e "  ${GREEN}[OK]${NC} URL guardada. Reinicia n8n para aplicar."
        fi
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ OLLAMA (completo)
# ════════════════════════════════════════════
_ollama_ensure_server() {
  tmux has-session -t "ollama-server" 2>/dev/null && return 0
  echo -e "  ${YELLOW}[AVISO]${NC} Ollama no está corriendo."
  read -r -p "  ¿Iniciarlo ahora? (s/n): " _ANS < /dev/tty
  [ "$_ANS" = "s" ] || [ "$_ANS" = "S" ] || return 1
  [ -f "$HOME/ollama_start.sh" ] && bash "$HOME/ollama_start.sh" || { ollama serve &>/dev/null & sleep 3; }
  tmux has-session -t "ollama-server" 2>/dev/null && \
    echo -e "  ${GREEN}[OK]${NC} Servidor iniciado" || echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar"
  return 0
}

_ollama_list_models() {
  ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^$"
}

submenu_ollama() {
  local state="$1"
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    [ "$state" = "running" ] && \
      echo -e "  ║  ◎ OLLAMA  ${GREEN}● activo${CYAN}${BOLD}                     ║" || \
      echo    "  ║  ◎ OLLAMA  ● listo                      ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar servidor   :11434${CYAN}${BOLD}          ║"
    echo -e "  ║  ${NC}[2] Chat rápido${CYAN}${BOLD}                        ║"
    echo -e "  ║  ${NC}[3] Ver modelos${CYAN}${BOLD}                        ║"
    echo -e "  ║  ${NC}[4] Descargar modelo${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[5] Detener servidor${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[6] Eliminar modelo${CYAN}${BOLD}                    ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        [ -f "$HOME/ollama_start.sh" ] && bash "$HOME/ollama_start.sh" || \
          echo -e "  ${RED}[ERROR]${NC} ollama_start.sh no encontrado"
        echo ""; read -r _ < /dev/tty
        tmux has-session -t "ollama-server" 2>/dev/null && state="running" || state="stopped" ;;
      2)
        clear; echo ""
        _ollama_ensure_server || { read -r _ < /dev/tty; continue; }
        mapfile -t MODELS < <(_ollama_list_models)
        if [ ${#MODELS[@]} -eq 0 ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} No hay modelos. Ve a [4] para descargar."
          echo ""; read -r _ < /dev/tty; continue
        fi
        echo -e "  ${CYAN}Modelos instalados:${NC}"; echo ""
        for i in "${!MODELS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${MODELS[$i]}"; done
        echo ""; echo -e "  ${DIM}Tip: escribe /bye para salir del chat${NC}"; echo ""
        read -r -p "  Elige número de modelo: " CHOICE < /dev/tty
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#MODELS[@]}" ]; then
          SELECTED="${MODELS[$((CHOICE-1))]}"
          echo -e "  ${GREEN}[OK]${NC} Chat con ${CYAN}${SELECTED}${NC}..."; echo ""
          ollama run "$SELECTED" < /dev/tty
        else
          echo -e "  ${RED}[ERROR]${NC} Número inválido."; read -r _ < /dev/tty
        fi ;;
      3)
        clear; echo ""
        _ollama_ensure_server || { read -r _ < /dev/tty; continue; }
        MODELS_OUT=$(_ollama_list_models)
        [ -z "$MODELS_OUT" ] && echo -e "  ${YELLOW}No hay modelos instalados.${NC}" || {
          echo -e "  ${CYAN}Modelos instalados:${NC}"; echo ""
          ollama list 2>/dev/null
        }
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        _ollama_ensure_server || { read -r _ < /dev/tty; continue; }
        echo -e "  ${CYAN}Modelos recomendados para móvil:${NC}"; echo ""
        echo "    [a] qwen2.5:0.5b    ~397MB  — más liviano"
        echo "    [b] qwen2.5:1.5b    ~986MB  — balance liviano"
        echo "    [c] qwen:1.8b       ~1.1GB  — balance velocidad"
        echo "    [d] llama3.2:1b     ~1.3GB  — buena calidad"
        echo "    [e] phi3:mini       ~2.3GB  — mejor calidad"
        echo "    [f] Escribir nombre manualmente"
        echo ""; echo -e "  ${DIM}⚠️  NO usar modelos 7B+ — crash garantizado${NC}"; echo ""
        read -r -p "  Elige [a-f]: " DCHOICE < /dev/tty
        case "$DCHOICE" in
          a|A) DL_MODEL="qwen2.5:0.5b" ;;
          b|B) DL_MODEL="qwen2.5:1.5b" ;;
          c|C) DL_MODEL="qwen:1.8b"    ;;
          d|D) DL_MODEL="llama3.2:1b"  ;;
          e|E) DL_MODEL="phi3:mini"    ;;
          f|F) read -r -p "  Nombre del modelo: " DL_MODEL < /dev/tty ;;
          *)   DL_MODEL="" ;;
        esac
        if [ -n "$DL_MODEL" ]; then
          echo -e "  ${CYAN}Descargando ${DL_MODEL}...${NC}"; echo ""
          ollama pull "$DL_MODEL" < /dev/tty
          echo ""; read -r _ < /dev/tty
        fi ;;
      5)
        clear; echo ""
        tmux kill-session -t "ollama-server" 2>/dev/null || pkill -f "ollama serve" 2>/dev/null
        sleep 1
        echo -e "  ${GREEN}[OK]${NC} Servidor Ollama detenido"
        echo ""; read -r _ < /dev/tty; state="stopped" ;;
      6)
        clear; echo ""
        mapfile -t MODELS < <(_ollama_list_models)
        if [ ${#MODELS[@]} -eq 0 ]; then
          echo -e "  ${YELLOW}No hay modelos instalados.${NC}"
          echo ""; read -r _ < /dev/tty; continue
        fi
        echo -e "  ${CYAN}Modelos instalados:${NC}"; echo ""
        for i in "${!MODELS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${MODELS[$i]}"; done
        echo ""; read -r -p "  Número a eliminar: " DCHOICE < /dev/tty
        if [[ "$DCHOICE" =~ ^[0-9]+$ ]] && [ "$DCHOICE" -ge 1 ] && [ "$DCHOICE" -le "${#MODELS[@]}" ]; then
          SELECTED="${MODELS[$((DCHOICE-1))]}"
          read -r -p "  ¿Eliminar ${SELECTED}? (s/n): " CONFIRMAR < /dev/tty
          [ "$CONFIRMAR" = "s" ] || [ "$CONFIRMAR" = "S" ] && {
            ollama rm "$SELECTED" 2>/dev/null && \
              echo -e "  ${GREEN}[OK]${NC} $SELECTED eliminado" || \
              echo -e "  ${RED}[ERROR]${NC} No se pudo eliminar"
          }
        fi
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ CLAUDE CODE
# ════════════════════════════════════════════
submenu_claude() {
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◆ CLAUDE CODE  ● listo                 ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Abrir Claude Code (directorio actual)${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Abrir Claude Code en proyecto${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[3] Gestionar proyectos${CYAN}${BOLD}                ║"
    echo -e "  ║  ${NC}[4] Actualizar Claude Code${CYAN}${BOLD}             ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        local CLI_PATH; CLI_PATH=$(find_claude_cli)
        if [ ! -f "$CLI_PATH" ]; then
          echo -e "\n  ${RED}[ERROR]${NC} cli.js no encontrado."
          echo "  Reinstala desde [0] → Restore → GitHub → claude"; echo ""
          read -r _ < /dev/tty; continue
        fi
        echo -e "\n  ${CYAN}Abriendo Claude Code en $(pwd)...${NC}\n"
        node "$CLI_PATH" ;;
      2)
        clear; echo ""
        local CLI_PATH; CLI_PATH=$(find_claude_cli)
        [ ! -f "$CLI_PATH" ] && { echo -e "  ${RED}[ERROR]${NC} cli.js no encontrado."; read -r _ < /dev/tty; continue; }
        mkdir -p "$HOME/proyectos"
        mapfile -t PROJS < <(ls -1 "$HOME/proyectos/" 2>/dev/null)
        echo -e "  ${CYAN}Proyectos disponibles en ~/proyectos/:${NC}"; echo ""
        local IDX=1
        [ ${#PROJS[@]} -gt 0 ] && for p in "${PROJS[@]}"; do printf "    [%d] %s\n" "$IDX" "$p"; IDX=$((IDX+1)); done || echo "    (ninguno)"
        echo ""; echo "    [m] Escribir ruta manual"; echo "    [d] Usar directorio de Download"; echo "    [b] Volver"
        echo ""; read -r -p "  Elige opción: " PCHOICE < /dev/tty

        local TARGET_DIR=""
        case "$PCHOICE" in
          m|M) read -r -p "  Ruta del proyecto: " TARGET_DIR < /dev/tty ;;
          d|D)
            echo ""; echo -e "  ${CYAN}Carpetas en /sdcard/Download/:${NC}"; echo ""
            mapfile -t DL_DIRS < <(find /storage/emulated/0/Download -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -I{} basename {})
            [ ${#DL_DIRS[@]} -eq 0 ] && { echo "    (ninguna)"; read -r _ < /dev/tty; continue; }
            for i in "${!DL_DIRS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DL_DIRS[$i]}"; done
            echo ""; read -r -p "  Elige número: " DCHOICE < /dev/tty
            if [[ "$DCHOICE" =~ ^[0-9]+$ ]] && [ "$DCHOICE" -ge 1 ] && [ "$DCHOICE" -le "${#DL_DIRS[@]}" ]; then
              local DNAME="${DL_DIRS[$((DCHOICE-1))]}"
              local LINK_SRC="/storage/emulated/0/Download/${DNAME}"
              local LINK_DST="$HOME/proyectos/${DNAME}"
              [ ! -e "$LINK_DST" ] && ln -s "$LINK_SRC" "$LINK_DST" 2>/dev/null && echo -e "  ${GREEN}[OK]${NC} Symlink creado: ~/proyectos/${DNAME}"
              TARGET_DIR="$LINK_DST"
            fi ;;
          b|B|"") continue ;;
          *)
            if [[ "$PCHOICE" =~ ^[0-9]+$ ]] && [ "$PCHOICE" -ge 1 ] && [ "$PCHOICE" -le "${#PROJS[@]}" ]; then
              TARGET_DIR="$HOME/proyectos/${PROJS[$((PCHOICE-1))]}"
            fi ;;
        esac

        if [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ]; then
          echo -e "\n  ${CYAN}Abriendo Claude Code en $TARGET_DIR...${NC}\n"
          cd "$TARGET_DIR" && node "$CLI_PATH"
        elif [ -n "$TARGET_DIR" ]; then
          echo -e "  ${RED}[ERROR]${NC} Directorio no existe: $TARGET_DIR"
          read -r _ < /dev/tty
        fi ;;
      3)
        clear; echo ""
        echo -e "  ${BOLD}Proyectos en ~/proyectos/:${NC}"; echo ""
        ls -la "$HOME/proyectos/" 2>/dev/null || echo "    (directorio vacío)"
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        echo -e "  ${CYAN}Actualizando Claude Code...${NC}"; echo ""
        _ensure_install_script "install_claude.sh" || { read -r _ < /dev/tty; continue; }
        bash "$HOME/install_claude.sh" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ EXPO / EAS / GIT (completo)
# ════════════════════════════════════════════
submenu_expo() {
  while true; do
    clear; echo ""
    local ACTIVE_PROJ; ACTIVE_PROJ=$(_eas_get_project)
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◈ EXPO / EAS / GIT  ● listo            ║"
    echo    "  ╠══════════════════════════════════════════╣"
    [ -n "$ACTIVE_PROJ" ] && \
      printf  "  ║  ${NC}Proyecto: %-30s${CYAN}${BOLD}║\n" "$(basename "$ACTIVE_PROJ")" || \
      printf  "  ║  ${NC}%-40s${CYAN}${BOLD}║\n" "Proyecto: <ninguno>"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Build APK preview${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[2] Build producción (AAB)${CYAN}${BOLD}             ║"
    echo -e "  ║  ${NC}[3] Ver builds activos${CYAN}${BOLD}                 ║"
    echo -e "  ║  ${NC}[4] Login en expo.dev${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[5] Info / estado general${CYAN}${BOLD}              ║"
    echo -e "  ║  ${NC}[6] Configurar proyecto activo${CYAN}${BOLD}         ║"
    echo -e "  ║  ${NC}[7] Git push (proyecto activo)${CYAN}${BOLD}         ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1|2)
        clear; echo ""
        local PROJ; PROJ=$(_eas_get_project)
        [ -z "$PROJ" ] && { echo -e "  ${YELLOW}[AVISO]${NC} No hay proyecto activo. Configúralo con [6]."; echo ""; read -r _ < /dev/tty; continue; }
        local REAL_PATH; REAL_PATH=$(readlink -f "$PROJ" 2>/dev/null || echo "$PROJ")
        [ ! -d "$REAL_PATH" ] && { echo -e "  ${RED}[ERROR]${NC} Directorio no existe: $PROJ"; echo ""; read -r _ < /dev/tty; continue; }
        local PROFILE; [ "$OPT" = "1" ] && PROFILE="preview" || PROFILE="production"
        echo -e "  ${CYAN}Build $PROFILE → $PROJ${NC}"; echo ""
        cd "$REAL_PATH" && EAS_SKIP_AUTO_FINGERPRINT=1 eas build --platform android --profile "$PROFILE" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        echo -e "  ${CYAN}Builds activos en expo.dev:${NC}"; echo ""
        eas build:list 2>/dev/null || echo -e "  ${YELLOW}Error al consultar builds${NC}"
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        echo -e "  ${CYAN}Login en expo.dev:${NC}"; echo ""
        eas whoami 2>/dev/null && echo -e "\n  ${GREEN}[OK]${NC} Ya estás logueado." || {
          EAS_SKIP_AUTO_FINGERPRINT=1 eas login < /dev/tty
        }
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        echo -e "  ${BOLD}Info Expo / EAS:${NC}"; echo ""
        echo -e "  eas:       $(eas --version 2>/dev/null | head -1)"
        echo -e "  node:      $(node --version 2>/dev/null)"
        echo -e "  whoami:    $(eas whoami 2>/dev/null | head -1)"
        local PROJ; PROJ=$(_eas_get_project)
        echo -e "  proyecto:  ${PROJ:-<ninguno configurado>}"
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        echo -e "  ${BOLD}Configurar proyecto activo${NC}"; echo ""
        mkdir -p "$HOME/proyectos"
        mapfile -t PROJS < <(ls -1 "$HOME/proyectos/" 2>/dev/null)
        [ ${#PROJS[@]} -gt 0 ] && {
          echo -e "  ${CYAN}Proyectos en ~/proyectos/:${NC}"; echo ""
          for i in "${!PROJS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${PROJS[$i]}"; done
          echo ""
        }
        echo "    [m] Escribir ruta manual"
        echo "    [d] Usar carpeta de Download"
        [ -n "$(_eas_get_project)" ] && echo "    [x] Quitar proyecto activo"
        echo "    [b] Volver"
        echo ""; read -r -p "  Opción: " PCHOICE < /dev/tty

        local NEW_PROJ=""
        case "$PCHOICE" in
          m|M) read -r -p "  Ruta: " NEW_PROJ < /dev/tty ;;
          d|D)
            echo ""; echo -e "  ${CYAN}Carpetas en /sdcard/Download/:${NC}"; echo ""
            mapfile -t DL_DIRS < <(find /storage/emulated/0/Download -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -I{} basename {})
            [ ${#DL_DIRS[@]} -eq 0 ] && { echo "    (ninguna)"; read -r _ < /dev/tty; continue; }
            for i in "${!DL_DIRS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DL_DIRS[$i]}"; done
            echo ""; read -r -p "  Número: " DCHOICE < /dev/tty
            if [[ "$DCHOICE" =~ ^[0-9]+$ ]] && [ "$DCHOICE" -ge 1 ] && [ "$DCHOICE" -le "${#DL_DIRS[@]}" ]; then
              local DNAME="${DL_DIRS[$((DCHOICE-1))]}"
              local LINK_DST="$HOME/proyectos/${DNAME}"
              [ ! -e "$LINK_DST" ] && ln -s "/storage/emulated/0/Download/${DNAME}" "$LINK_DST" 2>/dev/null
              NEW_PROJ="$LINK_DST"
            fi ;;
          x|X) rm -f "$EAS_PROJECT_FILE"; echo -e "  ${GREEN}[OK]${NC} Proyecto activo eliminado."; read -r _ < /dev/tty; continue ;;
          b|B|"") continue ;;
          *)
            if [[ "$PCHOICE" =~ ^[0-9]+$ ]] && [ "$PCHOICE" -ge 1 ] && [ "$PCHOICE" -le "${#PROJS[@]}" ]; then
              NEW_PROJ="$HOME/proyectos/${PROJS[$((PCHOICE-1))]}"
            fi ;;
        esac

        if [ -n "$NEW_PROJ" ]; then
          local REAL_PATH; REAL_PATH=$(readlink -f "$NEW_PROJ" 2>/dev/null || echo "$NEW_PROJ")
          if [ ! -d "$REAL_PATH" ]; then
            echo -e "  ${RED}[ERROR]${NC} Directorio no existe: $NEW_PROJ"
          elif [ ! -f "$REAL_PATH/package.json" ]; then
            echo -e "  ${YELLOW}[AVISO]${NC} No encontré package.json."
            read -r -p "  ¿Guardar de todas formas? (s/n): " FC < /dev/tty
            [ "$FC" = "s" ] || [ "$FC" = "S" ] && { _eas_set_project "$NEW_PROJ"; echo -e "  ${GREEN}[OK]${NC} Guardado."; }
          else
            _eas_set_project "$NEW_PROJ"
            echo -e "  ${GREEN}[OK]${NC} Proyecto activo: $NEW_PROJ"
          fi
        fi
        echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        local PROJ; PROJ=$(_eas_get_project)
        [ -z "$PROJ" ] && { echo -e "  ${YELLOW}[AVISO]${NC} No hay proyecto activo. Configúralo con [6]."; echo ""; read -r _ < /dev/tty; continue; }
        local REAL_PATH; REAL_PATH=$(readlink -f "$PROJ" 2>/dev/null || echo "$PROJ")
        [ ! -d "$REAL_PATH" ] && { echo -e "  ${RED}[ERROR]${NC} Directorio no existe: $PROJ"; echo ""; read -r _ < /dev/tty; continue; }
        [ ! -d "$REAL_PATH/.git" ] && {
          echo -e "  ${RED}[ERROR]${NC} No es un repositorio git."
          read -r -p "  ¿Inicializar git ahora? (s/n): " INITGIT < /dev/tty
          [ "$INITGIT" = "s" ] || [ "$INITGIT" = "S" ] && cd "$REAL_PATH" && git init
          echo ""; read -r _ < /dev/tty; continue
        }
        cd "$REAL_PATH" || { read -r _ < /dev/tty; continue; }
        echo -e "  ${CYAN}Proyecto:${NC} $PROJ"; echo ""
        echo -e "  ${BOLD}Estado:${NC}"; git status --short; echo ""
        read -r -p "  Commit (Enter = 'update desde Android'): " COMMIT_MSG < /dev/tty
        [ -z "$COMMIT_MSG" ] && COMMIT_MSG="update desde Android"
        echo ""; git add . && git commit -m "$COMMIT_MSG" && {
          echo ""; echo -e "  ${CYAN}Push...${NC}"; git push && \
            echo -e "  ${GREEN}[OK]${NC} Push completado." || \
            echo -e "  ${RED}[ERROR]${NC} Push falló. Verifica remote/credenciales."
        } || echo -e "  ${YELLOW}[AVISO]${NC} Nada nuevo para commitear."
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ PYTHON + SQLITE (completo)
# ════════════════════════════════════════════
submenu_sqlite() {
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⬡ SQLITE                                ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Listar bases de datos en ~/  ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[2] Abrir BD (modo interactivo)  ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[3] Ver tablas de una BD         ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[4] BD de n8n (acceso rápido)    ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[b] Volver a Python              ${CYAN}${BOLD}      ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        echo -e "  ${BOLD}Bases de datos SQLite en ~/:${NC}"; echo ""
        find "$HOME" -maxdepth 3 -name "*.db" -o -name "*.sqlite" 2>/dev/null | \
          while read -r f; do echo "  $f ($(du -h "$f" | cut -f1))"; done
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        mapfile -t DBS < <(find "$HOME" -maxdepth 3 \( -name "*.db" -o -name "*.sqlite" \) 2>/dev/null)
        [ ${#DBS[@]} -eq 0 ] && { echo -e "  ${YELLOW}No hay bases de datos.${NC}"; echo ""; read -r _ < /dev/tty; continue; }
        echo -e "  ${CYAN}BDs disponibles:${NC}"; echo ""
        for i in "${!DBS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DBS[$i]}"; done
        echo ""; read -r -p "  Número: " CHOICE < /dev/tty
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#DBS[@]}" ]; then
          echo -e "  ${CYAN}Abriendo ${DBS[$((CHOICE-1))]}...${NC}"
          sqlite3 "${DBS[$((CHOICE-1))]}"
        fi ;;
      3)
        clear; echo ""
        mapfile -t DBS < <(find "$HOME" -maxdepth 3 \( -name "*.db" -o -name "*.sqlite" \) 2>/dev/null)
        [ ${#DBS[@]} -eq 0 ] && { echo -e "  ${YELLOW}No hay bases de datos.${NC}"; echo ""; read -r _ < /dev/tty; continue; }
        for i in "${!DBS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DBS[$i]}"; done
        echo ""; read -r -p "  Número: " CHOICE < /dev/tty
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#DBS[@]}" ]; then
          echo ""; echo -e "  ${CYAN}Tablas en ${DBS[$((CHOICE-1))]}:${NC}"; echo ""
          sqlite3 "${DBS[$((CHOICE-1))]}" ".tables"
        fi
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        N8N_DB="$TERMUX_PREFIX/var/lib/proot-distro/installed-rootfs/debian/root/.n8n/database.sqlite"
        [ ! -f "$N8N_DB" ] && N8N_DB=$(find "$TERMUX_PREFIX" -name "database.sqlite" 2>/dev/null | head -1)
        if [ -z "$N8N_DB" ] || [ ! -f "$N8N_DB" ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} Base de datos n8n no encontrada."
          echo "  n8n debe estar instalado y haber corrido al menos una vez."
        else
          echo -e "  ${CYAN}BD n8n: $N8N_DB${NC}"; echo ""
          sqlite3 "$N8N_DB" ".tables"
          echo ""; echo -e "  ${DIM}Tip: usa sqlite3 directamente para queries${NC}"
        fi
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

submenu_python() {
  local py_ver="$1"
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    printf  "  ║  ◉ PYTHON  ● listo · v%-18s${CYAN}${BOLD}║\n" "${py_ver}"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Ver versión e info${CYAN}${BOLD}                 ║"
    echo -e "  ║  ${NC}[2] Abrir REPL (python3)${CYAN}${BOLD}               ║"
    echo -e "  ║  ${NC}[3] Instalar paquete (pip)${CYAN}${BOLD}             ║"
    echo -e "  ║  ${NC}[4] Listar paquetes instalados${CYAN}${BOLD}         ║"
    echo -e "  ║  ${NC}[5] SQLite → submenú${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[6] Ejecutar script .py${CYAN}${BOLD}                ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        echo -e "  ${BOLD}Python info:${NC}"; echo ""
        echo -e "  python3: $(python3 --version 2>/dev/null)"
        echo -e "  pip:     $(pip --version 2>/dev/null | awk '{print $1, $2}')"
        echo -e "  sqlite3: $(python3 -c 'import sqlite3; print(sqlite3.sqlite_version)' 2>/dev/null)"
        echo -e "  Ruta:    $(command -v python3 2>/dev/null)"
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        echo -e "  ${CYAN}REPL Python — escribe exit() para volver${NC}"; echo ""
        python3 ;;
      3)
        clear; echo ""
        echo -e "  ${BOLD}Instalar paquete pip${NC}"; echo ""
        read -r -p "  Nombre del paquete: " PKG_NAME < /dev/tty
        if [ -z "$PKG_NAME" ]; then
          echo -e "  ${YELLOW}Cancelado.${NC}"
        else
          echo ""; echo -e "  ${CYAN}Instalando ${PKG_NAME}...${NC}"; echo ""
          pip install "$PKG_NAME" 2>&1 | tee /tmp/pip_out.txt
          if grep -q "externally-managed-environment" /tmp/pip_out.txt 2>/dev/null; then
            echo ""; echo -e "  ${YELLOW}[AVISO]${NC} Reintentando con --break-system-packages..."
            pip install "$PKG_NAME" --break-system-packages
          fi
          rm -f /tmp/pip_out.txt
        fi
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        echo -e "  ${BOLD}Paquetes instalados:${NC}"; echo ""
        pip list 2>/dev/null | head -40
        echo ""; read -r _ < /dev/tty ;;
      5) submenu_sqlite ;;
      6)
        clear; echo ""
        echo -e "  ${CYAN}${BOLD}Ejecutar script Python${NC}"; echo ""
        mapfile -t PY_SCRIPTS < <(
          { find "$HOME/proyectos" -maxdepth 2 -name "*.py" 2>/dev/null
            find "$HOME" -maxdepth 1 -name "*.py" 2>/dev/null
            find /storage/emulated/0/Download -maxdepth 2 -name "*.py" 2>/dev/null
          } | sort -u
        )
        if [ ${#PY_SCRIPTS[@]} -eq 0 ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} No se encontraron scripts .py."
          read -r -p "  Escribe la ruta completa: " MANUAL_PY < /dev/tty
          [ -n "$MANUAL_PY" ] && [ -f "$MANUAL_PY" ] && PY_SCRIPTS=("$MANUAL_PY") || { read -r _ < /dev/tty; continue; }
        else
          echo -e "  ${CYAN}Scripts encontrados:${NC}"; echo ""
          for i in "${!PY_SCRIPTS[@]}"; do
            local DISPLAY="${PY_SCRIPTS[$i]}"; DISPLAY="${DISPLAY/#$HOME/~}"
            printf "    [%d] %s\n" "$((i+1))" "$DISPLAY"
          done
          echo ""; echo "    [m] Ruta manual"; echo ""
          read -r -p "  Elige número: " SCHOICE < /dev/tty
          [ "$SCHOICE" = "m" ] || [ "$SCHOICE" = "M" ] && {
            read -r -p "  Ruta: " MANUAL_PY < /dev/tty; PY_SCRIPTS=("$MANUAL_PY"); SCHOICE=1
          }
          if ! [[ "$SCHOICE" =~ ^[0-9]+$ ]] || [ "$SCHOICE" -lt 1 ] || [ "$SCHOICE" -gt "${#PY_SCRIPTS[@]}" ]; then
            echo -e "  ${RED}[ERROR]${NC} Número inválido."; read -r _ < /dev/tty; continue
          fi
        fi
        local SELECTED_PY="${PY_SCRIPTS[$((SCHOICE-1))]:-${PY_SCRIPTS[0]}}"
        [ ! -f "$SELECTED_PY" ] && { echo -e "  ${RED}[ERROR]${NC} Archivo no existe."; read -r _ < /dev/tty; continue; }
        echo ""; echo -e "  ${CYAN}▶ Ejecutando:${NC} $SELECTED_PY"; echo ""
        local SCRIPT_DIR; SCRIPT_DIR=$(dirname "$SELECTED_PY")
        cd "$SCRIPT_DIR" && python3 "$SELECTED_PY" < /dev/tty
        PY_EXIT=$?
        echo ""; [ $PY_EXIT -eq 0 ] && echo -e "  ${GREEN}[OK]${NC} Terminó (código 0)" || echo -e "  ${YELLOW}[AVISO]${NC} Terminó con código $PY_EXIT"
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ REMOTE (SSH + Dashboard + Cloudflared SSH)
#  NUEVO en v3.7.0 — reemplaza SSH [6] y Dashboard [7]
# ════════════════════════════════════════════
submenu_remote() {
  while true; do
    clear; echo ""

    # ── Re-leer estado real en cada vuelta ───────────────────────
    local SSH_ACTIVE=false DB_ACTIVE=false CF_ACTIVE=false
    pgrep -x sshd &>/dev/null && SSH_ACTIVE=true
    pgrep -f "dashboard_server.py" &>/dev/null && DB_ACTIVE=true
    pgrep -f "cloudflared.*ssh\|cloudflared.*access" &>/dev/null && CF_ACTIVE=true

    local IP; IP=$(_get_ip)
    local DB_PORT="8080"

    # ── Header con estado dinámico ────────────────────────────────
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════╗"
    echo    "  ║  ◎ REMOTE / SSH / DASHBOARD              ║"
    echo    "  ╠══════════════════════════════════════════════╣"
    # SSH status
    if $SSH_ACTIVE; then
      printf  "  ║  SSH    ${GREEN}● activo${NC}${CYAN}${BOLD}  :8022  %-16s║\n" "${IP}"
    else
      printf  "  ║  SSH    ${YELLOW}○ listo ${NC}${CYAN}${BOLD}  :8022  %-16s║\n" ""
    fi
    # Dashboard status
    if $DB_ACTIVE; then
      printf  "  ║  Dash   ${GREEN}● activo${NC}${CYAN}${BOLD}  :${DB_PORT}  %-16s║\n" "http://${IP}:${DB_PORT}"
    else
      printf  "  ║  Dash   ${YELLOW}○ listo ${NC}${CYAN}${BOLD}  :${DB_PORT}${CYAN}${BOLD}                    ║\n"
    fi
    # Cloudflared SSH status
    if $CF_ACTIVE; then
      printf  "  ║  CF-SSH ${GREEN}● activo${NC}${CYAN}${BOLD}  tunnel              ║\n"
    else
      printf  "  ║  CF-SSH ${YELLOW}○ listo ${NC}${CYAN}${BOLD}  tunnel              ║\n"
    fi
    echo    "  ╠══════════════════════════════════════════════╣"
    # ── Sección SSH ───────────────────────────────────────────────
    echo -e "  ║  ${BOLD}── SSH ──${CYAN}${BOLD}                                 ║"
    echo -e "  ║  ${NC}[1] Iniciar SSH            :8022${CYAN}${BOLD}         ║"
    echo -e "  ║  ${NC}[2] Detener SSH${CYAN}${BOLD}                          ║"
    echo -e "  ║  ${NC}[3] Ver IP + comando conexión${CYAN}${BOLD}            ║"
    echo -e "  ║  ${NC}[4] Agregar clave pública (PC)${CYAN}${BOLD}           ║"
    echo -e "  ║  ${NC}[5] Ver conexiones activas${CYAN}${BOLD}               ║"
    echo -e "  ║  ${NC}[6] Cambiar contraseña Termux${CYAN}${BOLD}            ║"
    # ── Sección Dashboard ─────────────────────────────────────────
    echo    "  ╠══════════════════════════════════════════════╣"
    echo -e "  ║  ${BOLD}── Dashboard ──${CYAN}${BOLD}                          ║"
    echo -e "  ║  ${NC}[7] Iniciar Dashboard      :8080${CYAN}${BOLD}         ║"
    echo -e "  ║  ${NC}[8] Detener Dashboard${CYAN}${BOLD}                    ║"
    echo -e "  ║  ${NC}[9] Ver URL de acceso${CYAN}${BOLD}                    ║"
    # ── Sección Cloudflared SSH ───────────────────────────────────
    echo    "  ╠══════════════════════════════════════════════╣"
    echo -e "  ║  ${BOLD}── Cloudflared SSH (acceso remoto) ──${CYAN}${BOLD}   ║"
    echo -e "  ║  ${NC}[c] Iniciar tunnel SSH${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[x] Detener tunnel SSH${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[t] Configurar token CF-SSH${CYAN}${BOLD}              ║"
    echo -e "  ║  ${NC}[i] Cómo conectarse via CF-SSH${CYAN}${BOLD}           ║"
    echo    "  ╠══════════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}             ║"
    echo -e "  ╚══════════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in

      # ════════════════ SSH ════════════════
      1) # Iniciar SSH
        clear; echo ""
        if pgrep -x sshd &>/dev/null; then
          echo -e "  ${YELLOW}[AVISO]${NC} SSH ya está corriendo."
        else
          bash "$HOME/ssh_start.sh" 2>/dev/null || sshd 2>/dev/null
          sleep 1
        fi
        if pgrep -x sshd &>/dev/null; then
          IP=$(_get_ip)
          echo -e "  ${GREEN}[OK]${NC} SSH activo en puerto 8022"
          echo ""; echo -e "  ${BOLD}Conectar desde PC (WiFi):${NC}"
          echo -e "  ${GREEN}  ssh -p 8022 $(whoami)@${IP:-<tu_IP>}${NC}"
          echo ""; echo -e "  ${YELLOW}Recuerda:${NC} PC y teléfono en la misma red WiFi"
        else
          echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar SSH"
          echo "  Prueba: sshd -d (modo debug)"
        fi
        echo ""; read -r _ < /dev/tty ;;

      2) # Detener SSH
        clear; echo ""
        bash "$HOME/ssh_stop.sh" 2>/dev/null || pkill sshd 2>/dev/null
        sleep 1
        pgrep -x sshd &>/dev/null || echo -e "  ${GREEN}[OK]${NC} SSH detenido"
        echo ""; read -r _ < /dev/tty ;;

      3) # Info conexión SSH
        clear; echo ""
        IP=$(_get_ip)
        USER_N=$(whoami)
        echo -e "  ${BOLD}Información de conexión SSH${NC}"; echo ""
        echo -e "  Estado:   $(pgrep -x sshd &>/dev/null && echo "${GREEN}● ACTIVO${NC}" || echo "${YELLOW}○ DETENIDO${NC}")"
        echo -e "  Puerto:   8022"
        echo -e "  Usuario:  ${USER_N}"
        echo -e "  IP WiFi:  ${IP:-no detectada}"; echo ""
        echo -e "  ${CYAN}Comando WiFi:${NC}"
        echo -e "  ${GREEN}  ssh -p 8022 ${USER_N}@${IP:-<IP>}${NC}"; echo ""
        echo -e "  ${CYAN}VS Code Remote SSH:${NC}"
        echo "  1. Instala extensión: Remote - SSH"
        echo "  2. Ctrl+Shift+P → Remote-SSH: Connect to Host"
        echo -e "  3. Ingresa: ${USER_N}@${IP:-<IP>}:8022"; echo ""
        echo -e "  ${CYAN}SCP — transferir archivos:${NC}"
        echo "  scp -P 8022 archivo.txt ${USER_N}@${IP:-<IP>}:~/"
        echo ""; read -r _ < /dev/tty ;;

      4) # Agregar clave pública
        clear; echo ""
        echo -e "  ${BOLD}Agregar clave pública SSH desde PC${NC}"; echo ""
        echo "  PASO 1 — En tu PC:"
        echo -e "  ${CYAN}  cat ~/.ssh/id_ed25519.pub${NC}  (o id_rsa.pub)"
        echo "  Si no tienes clave:"
        echo -e "  ${CYAN}  ssh-keygen -t ed25519${NC}"; echo ""
        echo "  PASO 2 — Pega el resultado aquí:"
        echo ""; echo -n "  Clave pública (o vacío para cancelar): "
        read -r PUB_KEY < /dev/tty
        if [ -z "$PUB_KEY" ]; then
          echo -e "  ${YELLOW}Cancelado.${NC}"
        elif echo "$PUB_KEY" | grep -qE "^ssh-(rsa|ed25519|ecdsa|dss) "; then
          mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
          echo "$PUB_KEY" >> "$HOME/.ssh/authorized_keys"
          chmod 600 "$HOME/.ssh/authorized_keys"
          echo -e "  ${GREEN}[OK]${NC} Clave agregada. Próxima conexión sin contraseña."
        else
          echo -e "  ${RED}[ERROR]${NC} Formato inválido. Debe comenzar con ssh-ed25519, ssh-rsa, etc."
        fi
        echo ""; read -r _ < /dev/tty ;;

      5) # Conexiones activas
        clear; echo ""
        echo -e "  ${BOLD}Conexiones SSH activas${NC}"; echo ""
        CONNS=$(ps aux 2>/dev/null | grep "sshd:" | grep -v grep | grep -v "sshd -D")
        [ -z "$CONNS" ] && echo -e "  ${DIM}No hay conexiones activas.${NC}" || \
          echo "$CONNS" | while IFS= read -r line; do echo "  $line"; done
        echo ""
        pgrep -x sshd &>/dev/null && \
          echo -e "  Daemon: ${GREEN}● corriendo${NC} (PID: $(pgrep -x sshd | head -1))" || \
          echo -e "  Daemon: ${YELLOW}○ detenido${NC}"
        echo ""; read -r _ < /dev/tty ;;

      6) # Cambiar contraseña
        clear; echo ""
        echo -e "  ${BOLD}Contraseña Termux (para SSH sin clave)${NC}"; echo ""
        passwd
        echo ""; read -r _ < /dev/tty ;;

      # ════════════════ Dashboard ════════════════
      7) # Iniciar Dashboard
        clear; echo ""
        if pgrep -f "dashboard_server.py" &>/dev/null; then
          IP=$(_get_ip)
          echo -e "  ${YELLOW}[AVISO]${NC} Dashboard ya está corriendo."
          echo -e "  URL: ${GREEN}http://${IP}:8080${NC}"
        else
          # Auto-crear dashboard_start.sh robusto si no existe
          # Evita el error "no encontrado" en instalaciones limpias
          if [ ! -f "$HOME/dashboard_start.sh" ] || ! grep -q "dashboard_server.py" "$HOME/dashboard_start.sh" 2>/dev/null; then
            info "Creando dashboard_start.sh..."
            cat > "$HOME/dashboard_start.sh" << 'DBSTART_AUTO'
#!/data/data/com.termux/files/usr/bin/bash
DB_SCRIPT="$HOME/dashboard_server.py"
[ ! -f "$DB_SCRIPT" ] && DB_SCRIPT="/data/data/com.termux/files/home/dashboard_server.py"
_get_ip() {
  local ip
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  echo "${ip:-localhost}"
}
if [ ! -f "$DB_SCRIPT" ]; then
  echo "[ERROR] dashboard_server.py no encontrado"
  echo "  Instala Remote desde el menú: [6] → Instalar"
  exit 1
fi
pgrep -f "dashboard_server.py" &>/dev/null && {
  echo "[INFO] Dashboard ya corriendo en http://$(_get_ip):8080"; exit 0
}
cd "$(dirname "$DB_SCRIPT")"
nohup python3 "$DB_SCRIPT" > "$HOME/.dashboard.log" 2>&1 &
sleep 2
pgrep -f "dashboard_server.py" &>/dev/null &&   echo "[OK] Dashboard → http://$(_get_ip):8080" ||   { echo "[ERROR] No se pudo iniciar. Log: cat ~/.dashboard.log"; exit 1; }
DBSTART_AUTO
            chmod +x "$HOME/dashboard_start.sh"
            echo -e "  ${GREEN}[OK]${NC} dashboard_start.sh creado"
          fi

          # Verificar que dashboard_server.py existe
          if [ ! -f "$HOME/dashboard_server.py" ]; then
            echo -e "  ${RED}[ERROR]${NC} dashboard_server.py no encontrado"
            echo "  Instala Remote desde este menú: [6] → Instalar"
            echo ""; read -r _ < /dev/tty; continue
          fi

          bash "$HOME/dashboard_start.sh" < /dev/null
          sleep 2
          if pgrep -f "dashboard_server.py" &>/dev/null; then
            IP=$(_get_ip)
            echo -e "  ${GREEN}[OK]${NC} Dashboard iniciado"
            echo -e "  URL: ${GREEN}http://${IP}:8080${NC}"
          else
            echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar"
            echo "  Log: cat ~/.dashboard.log"
          fi
        fi
        echo ""; read -r _ < /dev/tty ;;

      8) # Detener Dashboard
        clear; echo ""
        [ -f "$HOME/dashboard_stop.sh" ] && bash "$HOME/dashboard_stop.sh" < /dev/null || \
          pkill -f "dashboard_server.py" 2>/dev/null && echo -e "  ${GREEN}[OK]${NC} Dashboard detenido" || \
          echo "  Dashboard no estaba corriendo"
        echo ""; read -r _ < /dev/tty ;;

      9) # Ver URL Dashboard
        clear; echo ""
        IP=$(_get_ip)
        echo -e "  ${BOLD}URLs de acceso al Dashboard${NC}"; echo ""
        echo -e "  ${CYAN}Desde esta red WiFi:${NC}"
        echo -e "  ${GREEN}  http://${IP}:8080${NC}"; echo ""
        echo -e "  ${CYAN}Desde la app Android:${NC}"
        echo -e "  ${GREEN}  http://localhost:8080${NC}"; echo ""
        if pgrep -f "dashboard_server.py" &>/dev/null; then
          echo -e "  Estado: ${GREEN}● activo${NC}"
        else
          echo -e "  Estado: ${YELLOW}○ detenido${NC} — usa [7] para iniciar"
        fi
        echo ""; read -r _ < /dev/tty ;;

      # ════════════════ Cloudflared SSH ════════════════
      c|C) # Iniciar tunnel Cloudflared SSH
        clear; echo ""
        echo -e "  ${BOLD}Cloudflared SSH Tunnel${NC}"; echo ""

        CF_SSH_TOKEN="$HOME/.cf_ssh_token"
        if [ ! -f "$CF_SSH_TOKEN" ] || [ ! -s "$CF_SSH_TOKEN" ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} No hay token configurado para tunnel SSH."
          echo "  Configúralo con [t] primero."; echo ""
          echo -e "  ${CYAN}¿Qué es el tunnel CF-SSH?${NC}"
          echo "  Permite conectarte vía SSH desde cualquier red"
          echo "  (no solo WiFi local). Requiere cuenta Cloudflare."
          echo ""; read -r _ < /dev/tty; continue
        fi

        if ! pgrep -x sshd &>/dev/null; then
          echo -e "  ${YELLOW}[AVISO]${NC} SSH no está corriendo. Iniciando..."
          bash "$HOME/ssh_start.sh" 2>/dev/null || sshd 2>/dev/null
          sleep 1
          pgrep -x sshd &>/dev/null || { echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar SSH."; read -r _ < /dev/tty; continue; }
          echo -e "  ${GREEN}[OK]${NC} SSH iniciado"; echo ""
        fi

        CF_TOK=$(cat "$CF_SSH_TOKEN")
        echo -e "  ${CYAN}Iniciando tunnel Cloudflared SSH...${NC}"; echo ""
        # Iniciar en background via tmux para no bloquear
        tmux new-session -d -s "cf-ssh-tunnel" \
          "cloudflared tunnel run --token ${CF_TOK} 2>&1 | tee $HOME/.cf_ssh.log" 2>/dev/null || \
          tmux new-session -d -s "cf-ssh-tunnel" \
            "cloudflared access ssh-server --hostname ssh.tu-dominio.com --url ssh://localhost:8022 2>&1 | tee $HOME/.cf_ssh.log" 2>/dev/null

        sleep 3
        if tmux has-session -t "cf-ssh-tunnel" 2>/dev/null; then
          echo -e "  ${GREEN}[OK]${NC} Tunnel Cloudflared SSH activo"
          echo ""; echo -e "  ${CYAN}Para conectarte desde cualquier red:${NC}"
          echo "  ssh -o ProxyCommand='cloudflared access ssh --hostname tu-dominio.com' $(whoami)@tu-dominio.com"
          echo ""; echo -e "  ${DIM}Ver logs: tmux attach -t cf-ssh-tunnel${NC}"
        else
          echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar el tunnel"
          echo "  Verifica el token con [t]"
        fi
        echo ""; read -r _ < /dev/tty ;;

      x|X) # Detener Cloudflared SSH
        clear; echo ""
        tmux kill-session -t "cf-ssh-tunnel" 2>/dev/null
        pkill -f "cloudflared.*tunnel\|cloudflared.*ssh" 2>/dev/null
        sleep 1
        echo -e "  ${GREEN}[OK]${NC} Tunnel Cloudflared SSH detenido"
        echo ""; read -r _ < /dev/tty ;;

      t|T) # Configurar token CF-SSH
        clear; echo ""
        echo -e "  ${BOLD}Configurar token Cloudflared SSH${NC}"; echo ""
        CF_SSH_TOKEN="$HOME/.cf_ssh_token"
        CF_CURRENT=""
        [ -f "$CF_SSH_TOKEN" ] && CF_CURRENT=$(cat "$CF_SSH_TOKEN")
        [ -n "$CF_CURRENT" ] && echo -e "  Token actual: ${GREEN}configurado${NC}" || \
          echo -e "  Token actual: ${YELLOW}no configurado${NC}"
        echo ""
        echo -e "  ${CYAN}Cómo obtener el token:${NC}"
        echo "  1. cloudflare.com → Zero Trust"
        echo "  2. Access → Tunnels → Create tunnel"
        echo "  3. Tipo: SSH → pega el token aquí"
        echo ""; echo "  (ENTER para cancelar)"
        read -r -p "  Nuevo token CF-SSH: " NEW_CF_SSH < /dev/tty
        if [ -n "$NEW_CF_SSH" ]; then
          echo "$NEW_CF_SSH" > "$CF_SSH_TOKEN"
          echo -e "  ${GREEN}[OK]${NC} Token guardado en ~/.cf_ssh_token"
          echo "  Usa [c] para iniciar el tunnel."
        else
          echo -e "  ${YELLOW}Cancelado.${NC}"
        fi
        echo ""; read -r _ < /dev/tty ;;

      i|I) # Info cómo conectarse via CF-SSH
        clear; echo ""
        echo -e "  ${BOLD}Cómo conectarse via Cloudflared SSH${NC}"; echo ""
        echo -e "  ${CYAN}DESDE EL TELÉFONO (setup):${NC}"
        echo "  1. Configura el token con [t]"
        echo "  2. Inicia SSH con [1]"
        echo "  3. Inicia tunnel con [c]"; echo ""
        echo -e "  ${CYAN}DESDE TU PC (primera vez):${NC}"
        echo "  1. Instala cloudflared en tu PC:"
        echo "     brew install cloudflare/cloudflare/cloudflared"
        echo "     (o descarga desde developers.cloudflare.com)"
        echo "  2. Configura ~/.ssh/config:"; echo ""
        echo -e "  ${DIM}Host termux-remoto"
        echo "    HostName tu-dominio-ssh.com"
        echo "    User $(whoami)"
        echo "    Port 22"
        echo "    ProxyCommand cloudflared access ssh --hostname %h"
        echo -e "  ${NC}"; echo ""
        echo "  3. Conecta con:"
        echo "     ssh termux-remoto"; echo ""
        echo -e "  ${YELLOW}Nota:${NC} Reemplaza 'tu-dominio-ssh.com' con el"
        echo "  hostname que configuraste en Cloudflare Access."
        echo ""; read -r _ < /dev/tty ;;

      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ BACKUP / RESTORE
# ════════════════════════════════════════════
_ensure_backup() {
  if [ ! -f "$HOME/backup.sh" ] || [ ! -s "$HOME/backup.sh" ]; then
    curl -fsSL "$REPO_RAW/backup.sh" -o "$HOME/backup.sh" 2>/dev/null || \
      wget -q "$REPO_RAW/backup.sh" -O "$HOME/backup.sh" 2>/dev/null
    [ ! -f "$HOME/backup.sh" ] || [ ! -s "$HOME/backup.sh" ] && return 1
    chmod +x "$HOME/backup.sh"
  fi
  return 0
}

_ensure_restore() {
  if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
    curl -fsSL "$REPO_RAW/restore.sh" -o "$HOME/restore.sh" 2>/dev/null || \
      wget -q "$REPO_RAW/restore.sh" -O "$HOME/restore.sh" 2>/dev/null
    [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ] && return 1
    chmod +x "$HOME/restore.sh"
  fi
  return 0
}

submenu_backup() {
  while true; do
    clear; echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◉ BACKUP / RESTORE                     ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Backup completo (todas las partes)   ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Backup por módulo                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Restore completo (GitHub)            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Restore por módulo (interactivo)     ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver al menú principal             ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        _ensure_backup || { echo -e "  ${RED}[ERROR]${NC} backup.sh no disponible"; read -r _ < /dev/tty; continue; }
        bash "$HOME/backup.sh" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        echo -e "  ${CYAN}Selecciona módulo a respaldar:${NC}"; echo ""
        echo "  [0] base   — scripts + tema + configs"
        echo "  [2] claude — Claude Code"
        echo "  [3] expo   — EAS CLI"
        echo "  [4] ollama — Ollama (sin modelos)"
        echo "  [5] n8n    — n8n + cloudflared"
        echo "  [6] proot  — Rootfs Debian completo"
        echo "  [7] remote — SSH + Dashboard configs"
        echo "  [b] Cancelar"
        echo ""; read -r -p "  Módulo: " MOD_OPT < /dev/tty

        local BAK_MOD=""
        case "$MOD_OPT" in
          0|b0) BAK_MOD="base"   ;;
          2)    BAK_MOD="claude" ;;
          3)    BAK_MOD="expo"   ;;
          4)    BAK_MOD="ollama" ;;
          5)    BAK_MOD="n8n"    ;;
          6)    BAK_MOD="proot"  ;;
          7)    BAK_MOD="remote" ;;
          b|B|"") continue ;;
          *) echo -e "  ${RED}[ERROR]${NC} Opción inválida"; read -r _ < /dev/tty; continue ;;
        esac

        _ensure_backup || { echo -e "  ${RED}[ERROR]${NC} backup.sh no disponible"; read -r _ < /dev/tty; continue; }
        bash "$HOME/backup.sh" --module "$BAK_MOD" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear
        _ensure_restore || { echo -e "  ${RED}[ERROR]${NC} restore.sh no disponible"; read -r _ < /dev/tty; continue; }
        bash "$HOME/restore.sh" --module all --source github < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear
        _ensure_restore || { echo -e "  ${RED}[ERROR]${NC} restore.sh no disponible"; read -r _ < /dev/tty; continue; }
        bash "$HOME/restore.sh" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  DESINSTALAR
# ════════════════════════════════════════════
uninstall_module() {
  local module_key="$1" module_name="$2"
  clear; echo ""
  echo -e "${RED}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "⚠  Desinstalar ${module_name}"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}Esta acción NO se puede deshacer.${RED}${BOLD}       ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""
  read -r -p "  ¿Confirmar? (escribe SI para confirmar): " CONFIRM_DEL < /dev/tty
  [ "$CONFIRM_DEL" != "SI" ] && { echo -e "  ${YELLOW}Cancelado.${NC}"; echo ""; read -r _ < /dev/tty; return 0; }

  echo ""
  case "$module_key" in
    claude)
      npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
      npm cache clean --force 2>/dev/null || true
      NPM_ROOT_U=$(npm root -g 2>/dev/null)
      rm -rf "${NPM_ROOT_U}/@anthropic-ai" 2>/dev/null || true
      rm -f "${TERMUX_PREFIX}/bin/claude" 2>/dev/null
      rm -f "$HOME/.install_claude_checkpoint" 2>/dev/null
      grep -v "alias claude=" "$HOME/.bashrc" > "$HOME/.bashrc.tmp" 2>/dev/null && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
      grep -v "^claude_code\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Claude Code desinstalado" ;;
    ollama)
      tmux kill-session -t "ollama-server" 2>/dev/null || true
      pkg uninstall ollama -y 2>/dev/null || true
      rm -f "$HOME/ollama_start.sh" "$HOME/ollama_stop.sh" 2>/dev/null
      grep -v "^ollama\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Ollama desinstalado"
      echo -e "  ${YELLOW}⚠${NC}  ~/.ollama no eliminado — bórralo si quieres liberar espacio" ;;
    n8n)
      tmux kill-session -t "n8n-server" 2>/dev/null || true
      proot-distro remove debian 2>/dev/null || true
      rm -f "$HOME/start_servidor.sh" "$HOME/stop_servidor.sh" "$HOME/ver_url.sh" 2>/dev/null
      grep -v "^n8n\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} n8n + proot Debian desinstalado" ;;
    expo)
      npm uninstall -g eas-cli 2>/dev/null || true
      rm -f "${TERMUX_PREFIX}/bin/eas" 2>/dev/null
      grep -v "^expo\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Expo / EAS CLI desinstalado" ;;
    python)
      pkg uninstall python sqlite -y 2>/dev/null || true
      rm -f "$HOME/.install_python_checkpoint" 2>/dev/null
      grep -v "^python\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Python + SQLite desinstalados" ;;
    remote)
      pkill sshd 2>/dev/null || true
      tmux kill-session -t "cf-ssh-tunnel" 2>/dev/null || true
      pkill -f "dashboard_server.py" 2>/dev/null || true
      pkg uninstall openssh -y 2>/dev/null || true
      rm -f "$HOME/ssh_start.sh" "$HOME/ssh_stop.sh" 2>/dev/null
      rm -f "$HOME/dashboard_start.sh" "$HOME/dashboard_stop.sh" "$HOME/dashboard_server.py" 2>/dev/null
      rm -f "$HOME/.cf_ssh_token" "$HOME/.install_ssh_checkpoint" 2>/dev/null
      grep -v "^ssh\.\|^dashboard\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Remote (SSH + Dashboard + CF-SSH) desinstalado"
      echo -e "  ${DIM}(~/.ssh/authorized_keys conservado)${NC}" ;;
  esac
  echo ""; read -r _ < /dev/tty
}

submenu_desinstalar() {
  while true; do
    clear; echo ""
    echo -e "${RED}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⚠  Desinstalar módulo                  ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] n8n + proot Debian${RED}${BOLD}                 ║"
    echo -e "  ║  ${NC}[2] Claude Code${RED}${BOLD}                        ║"
    echo -e "  ║  ${NC}[3] Ollama${RED}${BOLD}                             ║"
    echo -e "  ║  ${NC}[4] Expo / EAS CLI${RED}${BOLD}                     ║"
    echo -e "  ║  ${NC}[5] Python + SQLite${RED}${BOLD}                    ║"
    echo -e "  ║  ${NC}[6] Remote (SSH + Dashboard + CF-SSH)${RED}${BOLD}  ║"
    echo -e "  ║  ${NC}[b] Cancelar${RED}${BOLD}                           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; read -r -p "  Módulo a desinstalar: " OPT < /dev/tty

    case "$OPT" in
      1) uninstall_module "n8n"    "n8n + proot Debian"          ; break ;;
      2) uninstall_module "claude" "Claude Code"                  ; break ;;
      3) uninstall_module "ollama" "Ollama"                       ; break ;;
      4) uninstall_module "expo"   "Expo / EAS CLI"               ; break ;;
      5) uninstall_module "python" "Python + SQLite"              ; break ;;
      6) uninstall_module "remote" "Remote (SSH + Dashboard)"     ; break ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  LOOP PRINCIPAL
# ════════════════════════════════════════════
while true; do
  clear

  # ── Estado módulos ────────────────────────────────────────────
  IFS='|' read -r N8N_STATE N8N_VER N8N_EXTRA <<< "$(check_n8n)"
  if [ -z "$_CC_CACHE" ] || [ "$_CC_REFRESH" = "1" ]; then
    _CC_CACHE=$(check_claude); _CC_REFRESH=0
  fi
  IFS='|' read -r CC_STATE  CC_VER  CC_EXTRA  <<< "$_CC_CACHE"
  IFS='|' read -r OL_STATE  OL_VER  OL_EXTRA  <<< "$(check_ollama)"
  IFS='|' read -r EX_STATE  EX_VER  EX_EXTRA  <<< "$(check_expo)"
  IFS='|' read -r PY_STATE  PY_VER  PY_EXTRA  <<< "$(check_python)"
  IFS='|' read -r RM_STATE  RM_VER  RM_EXTRA  <<< "$(check_remote)"

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
  case "$N8N_STATE" in running|stopped) N8N_CMD="→ submenú" ;; *) N8N_CMD="" ;; esac
  draw_module "1" "⬡" "n8n"         "$N8N_STATE" "$N8N_VER" "$N8N_CMD"

  case "$CC_STATE"  in ready)           CC_CMD="→ submenú"  ;; *) CC_CMD=""  ;; esac
  draw_module "2" "◆" "Claude Code"  "$CC_STATE"  "$CC_VER"  "$CC_CMD"

  case "$OL_STATE"  in running|stopped) OL_CMD="→ submenú" ;; *) OL_CMD="" ;; esac
  draw_module "3" "◎" "Ollama"       "$OL_STATE"  "$OL_VER"  "$OL_CMD"

  case "$EX_STATE"  in ready)           EX_CMD="→ submenú"  ;; *) EX_CMD=""  ;; esac
  draw_module "4" "◈" "Expo/EAS/Git" "$EX_STATE"  "$EX_VER"  "$EX_CMD"

  case "$PY_STATE"  in ready)           PY_CMD="→ submenú"  ;; *) PY_CMD=""  ;; esac
  draw_module "5" "◉" "Python"       "$PY_STATE"  "$PY_VER"  "$PY_CMD"

  # Remote: muestra estado compuesto SSH●/DB● en la línea extra
  case "$RM_STATE"  in running|stopped) RM_CMD="→ submenú" ;; *) RM_CMD="" ;; esac
  # Remote: mostrar versión SSH + estado de servicios activos
  RM_DISPLAY_VER="$RM_VER"
  [ -n "$RM_EXTRA" ] && RM_DISPLAY_VER="${RM_VER} ${RM_EXTRA}"
  draw_module "6" "⬡" "Remote"       "$RM_STATE"  "$RM_DISPLAY_VER" "$RM_CMD"

  # ── Separador + Backup ────────────────────────────────────────
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}[0]${NC} ◉ Backup / Restore"
  echo ""

  # ── Footer ────────────────────────────────────────────────────
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${DIM}[r] refrescar  [h] ayuda  [u] actualizar  [s] shell  [d] desinstalar${NC}"
  echo ""

  read -r -p "  Opción: " OPT < /dev/tty

  case "$OPT" in
    1)
      [ "$N8N_STATE" = "not_installed" ] && install_module "n8n" "n8n" && continue || submenu_n8n "$N8N_STATE" ;;
    2)
      if [ "$CC_STATE" = "not_installed" ]; then
        install_module "Claude Code" "claude"; continue
      elif [ "$CC_VER" = "err:reinstalar" ]; then
        clear; echo ""
        echo -e "${YELLOW}${BOLD}  ╔══════════════════════════════════════════╗"
        echo    "  ║  ⚠  Claude Code — cli.js corrompido    ║"
        echo    "  ╠══════════════════════════════════════════╣"
        echo -e "  ║  ${NC}Usa [0] → Restore → GitHub → claude     ${YELLOW}${BOLD}║"
        echo -e "  ║  ${NC}O prueba reinstalar desde este menú:     ${YELLOW}${BOLD}║"
        echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""
        read -r -p "  ¿Reinstalar ahora? (s/n): " RI < /dev/tty
        [ "$RI" = "s" ] || [ "$RI" = "S" ] && install_module "Claude Code" "claude"
        continue
      else
        submenu_claude
      fi ;;
    3)
      [ "$OL_STATE" = "not_installed" ] && install_module "Ollama" "ollama" && continue || submenu_ollama "$OL_STATE" ;;
    4)
      [ "$EX_STATE" = "not_installed" ] && install_module "Expo/EAS/Git" "expo" && continue || submenu_expo ;;
    5)
      [ "$PY_STATE" = "not_installed" ] && install_module "Python" "python" && continue || submenu_python "$PY_VER" ;;
    6)
      [ "$RM_STATE" = "not_installed" ] && install_module "Remote/SSH/Dashboard" "remote" && continue || submenu_remote ;;
    0)
      submenu_backup ;;
    d|D)
      submenu_desinstalar ;;
    r|R)
      _CC_REFRESH=1; _CC_CACHE=""; continue ;;
    u|U)
      clear; echo ""
      echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
      echo    "  ║   Actualizando scripts desde GitHub...  ║"
      echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""

      SCRIPTS=("install_n8n.sh" "install_claude.sh" "install_ollama.sh" "install_expo.sh" \
                "install_python.sh" "install_ssh.sh" "install_remote.sh" \
                "menu.sh" "backup.sh" "restore.sh")
      UPDATE_OK=0; UPDATE_FAIL=0

      for SCRIPT in "${SCRIPTS[@]}"; do
        echo -n "  Descargando $SCRIPT... "
        TMP="$HOME/${SCRIPT}.tmp"
        curl -fsSL "$REPO_RAW/$SCRIPT" -o "$TMP" 2>/dev/null || \
          wget -q "$REPO_RAW/$SCRIPT" -O "$TMP" 2>/dev/null
        if [ -f "$TMP" ] && [ -s "$TMP" ]; then
          mv "$TMP" "$HOME/$SCRIPT"; chmod +x "$HOME/$SCRIPT"
          echo -e "${GREEN}✓${NC}"; UPDATE_OK=$((UPDATE_OK + 1))
        else
          rm -f "$TMP"; echo -e "${RED}✗${NC}"; UPDATE_FAIL=$((UPDATE_FAIL + 1))
        fi
      done

      echo ""
      echo -e "  ${GREEN}[OK]${NC} $UPDATE_OK actualizados   ${RED}[FAIL]${NC} $UPDATE_FAIL fallidos"
      echo ""; read -r _ < /dev/tty
      # Recargar menu.sh con la versión nueva
      exec bash "$HOME/menu.sh" ;;
    h|H)
      show_help ;;
    s|S|q|Q|"")
      clear; echo ""
      echo -e "  ${DIM}termux-ai-stack · escribe 'menu' para volver${NC}"; echo ""
      break ;;
  esac

done

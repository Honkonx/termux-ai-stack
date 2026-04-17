#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · menu.sh
#  Dashboard TUI — panel de control principal
#
#  Se ejecuta automáticamente al abrir Termux.
#  También se puede llamar manualmente con: menu
#
#  NAVEGACIÓN:
#    [1-4]  → acción sobre el módulo
#    [r]    → refrescar estado
#    [h]    → ayuda
#    [s/q]  → salir al shell
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 1.2.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

REPO_RAW="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script"
REGISTRY="$HOME/.android_server_registry"

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Helper: leer registry ─────────────────────────────────────
get_reg() { grep "^${1}\.${2}=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2; }

# ── Detección de estado ───────────────────────────────────────
check_n8n() {
  [ "$(get_reg n8n installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver; ver=$(get_reg n8n version)
  tmux has-session -t "n8n-server" 2>/dev/null && \
    echo "running|${ver}|" || echo "stopped|${ver}|"
}

check_claude() {
  [ "$(get_reg claude_code installed)" = "true" ] || { echo "not_installed||"; return; }
  echo "ready|$(get_reg claude_code version)|"
}

check_ollama() {
  [ "$(get_reg ollama installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver; ver=$(get_reg ollama version)
  tmux has-session -t "ollama-server" 2>/dev/null && \
    echo "running|${ver}|" || echo "stopped|${ver}|"
}

check_expo() {
  [ "$(get_reg expo installed)" = "true" ] || { echo "not_installed||"; return; }
  echo "ready|$(get_reg expo version)|$(eas whoami 2>/dev/null)"
}

# ── Dibujar módulo ────────────────────────────────────────────
draw_module() {
  local num="$1" icon="$2" name="$3" state="$4" ver="$5" cmd="$6"
  local status_col cmd_col

  case "$state" in
    running)
      status_col="${GREEN}● activo   ${NC}"
      cmd_col="${CYAN}${cmd}${NC}"
      ;;
    stopped)
      status_col="${GREEN}● listo    ${NC}"
      cmd_col="${CYAN}${cmd}${NC}"
      ;;
    ready)
      status_col="${GREEN}● listo    ${NC}"
      cmd_col="${CYAN}${cmd}${NC}"
      ;;
    not_installed)
      status_col="${YELLOW}○ no instal${NC}"
      cmd_col="${YELLOW}[instalar]${NC}"
      ver="──────────"
      ;;
  esac

  printf "  ${BOLD}[%s]${NC} %s %-13s %b  %b\n" \
    "$num" "$icon" "$name" "$status_col" "$cmd_col"
  printf "       ${DIM}v%s${NC}\n" "$ver"
  echo ""
}

# ── Instalar módulo desde repo ────────────────────────────────
install_module() {
  local name="$1" script="$2"
  local tmp="$HOME/.tmp_install_${name}.sh"

  # Fix: limpiar archivo temporal huérfano antes de descargar
  rm -f "$tmp"

  clear
  echo -e "\n${CYAN}${BOLD}  Instalando ${name}...${NC}\n"
  echo -e "  ${CYAN}[INFO]${NC} Descargando $script..."

  curl -fsSL "$REPO_RAW/$script" -o "$tmp" 2>/dev/null || \
    wget -q "$REPO_RAW/$script" -O "$tmp" 2>/dev/null

  if [ ! -f "$tmp" ] || [ ! -s "$tmp" ]; then
    echo -e "\n  ${RED}[ERROR]${NC} No se pudo descargar $script"
    echo "  Verifica tu conexión a internet."
    echo ""
    read -r -p "  Presiona ENTER para volver al menú..." _
    rm -f "$tmp"
    return 1
  fi

  chmod +x "$tmp"
  bash "$tmp"
  rm -f "$tmp"

  echo ""
  read -r -p "  Presiona ENTER para volver al menú..." _
}

# ── Submenú Ollama ────────────────────────────────────────────
ollama_submenu() {
  local state="$1"

  while true; do
    clear

    # Estado en tiempo real dentro del submenú
    IFS='|' read -r OL_ST OL_V _ <<< "$(check_ollama)"
    local status_line status_dot
    if tmux has-session -t "ollama-server" 2>/dev/null; then
      status_dot="${GREEN}● activo${NC}"
    else
      status_dot="${GREEN}● listo${NC}"
    fi
    [ "$OL_ST" = "not_installed" ] && status_dot="${YELLOW}○ no instalado${NC}"

    echo -e "${CYAN}${BOLD}"
    echo    "  ╔══════════════════════════════════════════╗"
    printf  "  ║  ◎ OLLAMA  %-30b║\n" "$status_dot  "
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar servidor    ollama-start   ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Chat rápido         ollama run     ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Ver modelos         ollama list    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Descargar modelo    ollama pull    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5] Detener servidor    ollama-stop    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver                             ${CYAN}${BOLD}║"
    echo    "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"

    read -r -p "  Opción: " SUB

    case "$SUB" in
      1)
        clear
        echo -e "\n  ${CYAN}[INFO]${NC} Iniciando servidor Ollama...\n"
        ollama-start 2>/dev/null
        echo ""
        read -r -p "  Presiona ENTER para volver..." _
        ;;
      2)
        clear
        echo -e "\n  ${CYAN}[INFO]${NC} Modelos disponibles:\n"
        ollama list 2>/dev/null
        echo ""
        read -r -p "  Modelo a usar (ej: phi3:mini): " MODEL
        if [ -n "$MODEL" ]; then
          clear
          echo -e "\n  ${CYAN}[INFO]${NC} Iniciando chat con ${MODEL}...\n"
          echo -e "  ${DIM}(Ctrl+D o /bye para salir del chat)${NC}\n"
          # Asegurarse de que el servidor esté corriendo
          if ! tmux has-session -t "ollama-server" 2>/dev/null; then
            echo -e "  ${YELLOW}[AVISO]${NC} Servidor no activo. Iniciando...\n"
            ollama-start 2>/dev/null
            sleep 3
          fi
          ollama run "$MODEL"
        fi
        ;;
      3)
        clear
        echo -e "\n  ${CYAN}[INFO]${NC} Modelos instalados:\n"
        ollama list 2>/dev/null || echo -e "  ${YELLOW}[AVISO]${NC} Servidor no activo o sin modelos."
        echo ""
        read -r -p "  Presiona ENTER para volver..." _
        ;;
      4)
        clear
        echo -e "\n  ${CYAN}[INFO]${NC} Modelos recomendados para móvil:\n"
        echo -e "  ${DIM}qwen:0.5b   ~395 MB  pruebas rápidas${NC}"
        echo -e "  ${DIM}qwen:1.8b   ~1.1 GB  uso general${NC}"
        echo -e "  ${DIM}phi3:mini   ~2.3 GB  mejor calidad${NC}"
        echo -e "  ${DIM}llama3.2:1b ~1.3 GB  balance${NC}"
        echo ""
        read -r -p "  Modelo a descargar (ej: qwen:1.8b): " PULL_MODEL
        if [ -n "$PULL_MODEL" ]; then
          echo -e "\n  ${CYAN}[INFO]${NC} Descargando ${PULL_MODEL}...\n"
          ollama pull "$PULL_MODEL"
          echo ""
          read -r -p "  Presiona ENTER para volver..." _
        fi
        ;;
      5)
        clear
        echo -e "\n  ${CYAN}[INFO]${NC} Deteniendo servidor Ollama...\n"
        ollama-stop 2>/dev/null
        echo ""
        read -r -p "  Presiona ENTER para volver..." _
        ;;
      b|B)
        break
        ;;
      *)
        continue
        ;;
    esac
  done
}

# ── Acción sobre módulo ───────────────────────────────────────
module_action() {
  local num="$1" name="$2" script="$3" state="$4"

  case "$state" in
    not_installed)
      install_module "$name" "$script"
      ;;
    running)
      case "$num" in
        1) echo "" && bash ~/n8n_log.sh 2>/dev/null ;;
        3) ollama_submenu "$state" ;;
        *) echo "" && read -r -p "  Presiona ENTER para volver..." _ ;;
      esac
      ;;
    stopped|ready)
      case "$num" in
        1) clear && n8n-start 2>/dev/null
           read -r -p "  Presiona ENTER para volver al menú..." _ ;;
        2) clear && claude ;;
        3) ollama_submenu "$state" ;;
        4) clear && expo-info 2>/dev/null
           read -r -p "  Presiona ENTER para volver al menú..." _ ;;
      esac
      ;;
  esac
}

# ── Pantalla de ayuda ─────────────────────────────────────────
show_help() {
  clear
  echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║     termux-ai-stack · AYUDA             ║"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  MENÚ${NC}"
  echo    "  ║  1-4    → acción sobre el módulo"
  echo    "  ║  r      → refrescar estado"
  echo    "  ║  h      → esta pantalla"
  echo    "  ║  s/q    → salir al shell"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  N8N${NC}"
  echo    "  ║  n8n-start   → inicia n8n + cloudflared"
  echo    "  ║  n8n-stop    → detiene todo"
  echo    "  ║  n8n-url     → URL pública"
  echo    "  ║  n8n-status  → estado del sistema"
  echo    "  ║  n8n-backup  → backup de workflows"
  echo    "  ║  debian      → consola Debian proot"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  CLAUDE CODE${NC}"
  echo    "  ║  claude            → agente interactivo"
  echo    "  ║  claude -p \"...\"   → modo directo"
  echo    "  ║  claude-update     → actualizar"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  OLLAMA${NC}"
  echo    "  ║  ollama-start   → inicia servidor :11434"
  echo    "  ║  ollama-stop    → detiene servidor"
  echo    "  ║  ollama-list    → modelos instalados"
  echo    "  ║  ollama run [m] → chat con modelo"
  echo    "  ║  ollama pull [m]→ descargar modelo"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  EXPO / EAS${NC}"
  echo    "  ║  expo-build [proyecto] [perfil]"
  echo    "  ║  expo-status   → ver builds activos"
  echo    "  ║  expo-login    → login en expo.dev"
  echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣"
  echo -e "  ║  SISTEMA${NC}"
  echo    "  ║  menu   → volver al dashboard"
  echo    "  ║  help   → esta pantalla"
  echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  read -r -p "  Presiona ENTER para volver al menú..." _
}

# ═══════════════════════════════════════════
#  LOOP PRINCIPAL
# ═══════════════════════════════════════════
while true; do
  clear

  IFS='|' read -r N8N_STATE N8N_VER N8N_EXTRA <<< "$(check_n8n)"
  IFS='|' read -r CC_STATE  CC_VER  CC_EXTRA  <<< "$(check_claude)"
  IFS='|' read -r OL_STATE  OL_VER  OL_EXTRA  <<< "$(check_ollama)"
  IFS='|' read -r EX_STATE  EX_VER  EX_EXTRA  <<< "$(check_expo)"

  IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
  [ -z "$IP" ] && IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
  RAM_FREE=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%.1fGB", $7/1024}')
  [ -z "$RAM_FREE" ] && RAM_FREE="--"

  echo -e "${CYAN}${BOLD}"
  echo    "  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "⬡ TERMUX·AI·STACK"
  printf  "  ║  %-40s║\n" \
    "$([ -n "$IP" ] && echo "IP: $IP  ·  RAM: $RAM_FREE" || echo "RAM: $RAM_FREE libre")"
  echo    "  ╠══════════════════════════════════════════╣"
  printf  "  ║  ${NC}%-38b${CYAN}${BOLD}║\n" "MÓDULOS"
  echo    "  ╚══════════════════════════════════════════╝"
  echo -e "${NC}"

  case "$N8N_STATE" in
    running)  N8N_CMD="n8n-log" ;;
    stopped)  N8N_CMD="n8n-start" ;;
    *)        N8N_CMD="" ;;
  esac
  draw_module "1" "⬡" "n8n" "$N8N_STATE" "$N8N_VER" "$N8N_CMD"

  case "$CC_STATE" in
    ready)  CC_CMD="claude" ;;
    *)      CC_CMD="" ;;
  esac
  draw_module "2" "◆" "Claude Code" "$CC_STATE" "$CC_VER" "$CC_CMD"

  # Ollama: el comando ahora indica que hay submenú
  case "$OL_STATE" in
    running) OL_CMD="→ submenú" ;;
    stopped) OL_CMD="→ submenú" ;;
    *)       OL_CMD="" ;;
  esac
  draw_module "3" "◎" "Ollama" "$OL_STATE" "$OL_VER" "$OL_CMD"

  case "$EX_STATE" in
    ready)  EX_CMD="expo-build" ;;
    *)      EX_CMD="" ;;
  esac
  draw_module "4" "◈" "Expo / EAS" "$EX_STATE" "$EX_VER" "$EX_CMD"

  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${DIM}[r] refrescar   [h] ayuda   [s] shell${NC}"
  echo ""

  read -r -p "  Opción: " OPT

  case "$OPT" in
    1) module_action "1" "n8n"         "install_n8n.sh"    "$N8N_STATE" ;;
    2) module_action "2" "Claude Code" "install_claude.sh" "$CC_STATE"  ;;
    3) module_action "3" "Ollama"      "install_ollama.sh" "$OL_STATE"  ;;
    4) module_action "4" "Expo/EAS"    "install_expo.sh"   "$EX_STATE"  ;;

    r|R) continue ;;

    h|H) show_help ;;

    s|S|q|Q|"")
      clear
      echo ""
      echo -e "  ${DIM}termux-ai-stack · escribe 'menu' para volver${NC}"
      echo ""
      break
      ;;

    n8n-start|n8n-stop|n8n-url|n8n-status|n8n-log|\
    claude|ollama-start|ollama-stop|expo-info|debian|help)
      eval "$OPT" 2>/dev/null
      echo ""
      read -r -p "  Presiona ENTER para volver al menú..." _
      ;;

    *) continue ;;
  esac

done

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
#    [i]    → instalar módulo no instalado
#    [r]    → refrescar estado
#    [s]    → salir al shell
#    [q]    → salir al shell
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 1.0.0 | Abril 2026
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

# ── Helpers ───────────────────────────────────────────────────
get_reg() { grep "^${1}\." "$REGISTRY" 2>/dev/null | grep "^${1}.${2}=" | cut -d'=' -f2; }

# ── Detección de estado de módulos ───────────────────────────
# Lee del registry (instantáneo) + verifica si está corriendo (tmux/curl)

check_n8n() {
  local installed version status
  installed=$(get_reg "n8n" "installed")
  version=$(get_reg "n8n" "version")
  [ "$installed" = "true" ] || { echo "not_installed||"; return; }
  tmux has-session -t "n8n-server" 2>/dev/null && \
    status="running" || status="stopped"
  echo "${status}|${version}|"
}

check_claude() {
  local installed version
  installed=$(get_reg "claude_code" "installed")
  version=$(get_reg "claude_code" "version")
  [ "$installed" = "true" ] || { echo "not_installed||"; return; }
  echo "ready|${version}|"
}

check_ollama() {
  local installed version status
  installed=$(get_reg "ollama" "installed")
  version=$(get_reg "ollama" "version")
  [ "$installed" = "true" ] || { echo "not_installed||"; return; }
  tmux has-session -t "ollama-server" 2>/dev/null && \
    status="running" || status="stopped"
  echo "${status}|${version}|"
}

check_expo() {
  local installed version user
  installed=$(get_reg "expo" "installed")
  version=$(get_reg "expo" "version")
  [ "$installed" = "true" ] || { echo "not_installed||"; return; }
  user=$(eas whoami 2>/dev/null)
  echo "ready|${version}|${user}"
}

# ── Dibujar línea de módulo ───────────────────────────────────
# $1=número $2=icono $3=nombre $4=estado $5=version $6=extra
draw_module() {
  local num="$1" icon="$2" name="$3" state="$4" ver="$5" extra="$6"

  case "$state" in
    running)
      status_str="${GREEN}● activo${NC}"
      action_str="${CYAN}[abrir]${NC}"
      ;;
    ready|stopped)
      status_str="${GREEN}● listo${NC}"
      action_str="${CYAN}[iniciar]${NC}"
      ;;
    not_installed)
      status_str="${YELLOW}○ no instalado${NC}"
      action_str="${YELLOW}[instalar]${NC}"
      ;;
    *)
      status_str="${DIM}? desconocido${NC}"
      action_str=""
      ;;
  esac

  # Línea principal
  printf "  ${BOLD}[%s]${NC} %s %-14s  %b\n" \
    "$num" "$icon" "$name" "$status_str"

  # Línea de detalle
  if [ "$state" != "not_installed" ]; then
    printf "       ${DIM}v%-10s${NC}  %b" "${ver}" "$action_str"
    [ -n "$extra" ] && printf "  ${DIM}%s${NC}" "$extra"
    printf "\n"
  else
    printf "       ${DIM}──────────────${NC}  %b\n" "$action_str"
  fi
  echo ""
}

# ── Función: instalar módulo ──────────────────────────────────
install_module() {
  local name="$1" script="$2"
  local tmp="$HOME/.tmp_install_${name}.sh"

  clear
  echo -e "\n${CYAN}${BOLD}  Instalando ${name}...${NC}\n"
  info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
  info "Descargando $script desde el repo..."

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

# ── Función: acción sobre módulo según estado ─────────────────
module_action() {
  local num="$1" name="$2" script="$3" state="$4"

  case "$state" in
    not_installed)
      install_module "$name" "$script"
      ;;
    running)
      case "$num" in
        1) echo "" && n8n-log 2>/dev/null || \
             echo -e "  ${YELLOW}[AVISO]${NC} n8n-log no disponible" ;;
        4) tmux attach -t "ollama-server" 2>/dev/null || \
             echo -e "  ${YELLOW}[AVISO]${NC} Sesión ollama no encontrada" ;;
      esac
      ;;
    stopped|ready)
      case "$num" in
        1) echo "" && n8n-start 2>/dev/null ;;
        2) echo "" && claude ;;
        3) echo "" && ollama-start 2>/dev/null ;;
        4) echo "" && expo-info 2>/dev/null ;;
      esac
      echo ""
      read -r -p "  Presiona ENTER para volver al menú..." _
      ;;
  esac
}

# ── Loop principal ────────────────────────────────────────────
while true; do
  clear

  # ── Leer estado de todos los módulos ─────────────────────────
  IFS='|' read -r N8N_STATE   N8N_VER   N8N_EXTRA   <<< "$(check_n8n)"
  IFS='|' read -r CC_STATE    CC_VER    CC_EXTRA    <<< "$(check_claude)"
  IFS='|' read -r OL_STATE    OL_VER    OL_EXTRA    <<< "$(check_ollama)"
  IFS='|' read -r EX_STATE    EX_VER    EX_EXTRA    <<< "$(check_expo)"

  # ── Info del sistema ──────────────────────────────────────────
  IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
  [ -z "$IP" ] && IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
  RAM_FREE=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%.1fGB", $7/1024}')
  [ -z "$RAM_FREE" ] && RAM_FREE="--"

  # ── Header ───────────────────────────────────────────────────
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════╗"
  printf "  ║  %-40s║\n" "⬡ TERMUX·AI·STACK"
  printf "  ║  %-40s║\n" "$([ -n "$IP" ] && echo "IP: $IP  ·  RAM: $RAM_FREE libre" || echo "RAM: $RAM_FREE libre")"
  echo "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}MÓDULOS${CYAN}${BOLD}$(printf '%33s' '')║"
  echo "  ╚══════════════════════════════════════════╝"
  echo -e "${NC}"

  # ── Módulos ───────────────────────────────────────────────────
  draw_module "1" "⬡" "n8n"        "$N8N_STATE" "$N8N_VER" \
    "$([ "$N8N_STATE" = "running" ] && cat "$HOME/.last_cf_url" 2>/dev/null | head -c 35)"
  draw_module "2" "◆" "Claude Code" "$CC_STATE"  "$CC_VER"  "$CC_EXTRA"
  draw_module "3" "◎" "Ollama"      "$OL_STATE"  "$OL_VER"  \
    "$([ "$OL_STATE" = "running" ] && echo ":11434")"
  draw_module "4" "◈" "Expo / EAS"  "$EX_STATE"  "$EX_VER"  \
    "$([ -n "$EX_EXTRA" ] && echo "👤 $EX_EXTRA")"

  # ── Footer ────────────────────────────────────────────────────
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${DIM}[r] refrescar   [h] ayuda   [s] shell${NC}"
  echo ""

  # ── Input ────────────────────────────────────────────────────
  read -r -p "  Opción: " OPT

  case "$OPT" in
    1) module_action "1" "n8n"        "install_n8n.sh"    "$N8N_STATE" ;;
    2) module_action "2" "Claude Code" "install_claude.sh" "$CC_STATE"  ;;
    3) module_action "3" "Ollama"      "install_ollama.sh" "$OL_STATE"  ;;
    4) module_action "4" "Expo/EAS"    "install_expo.sh"   "$EX_STATE"  ;;

    r|R)
      # Refrescar — solo vuelve al inicio del loop
      continue
      ;;

    h|H)
      clear
      echo ""
      echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗${NC}"
      echo -e "${CYAN}${BOLD}  ║     termux-ai-stack · AYUDA             ║${NC}"
      echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣${NC}"
      echo -e "${CYAN}${BOLD}  ║  MENÚ${NC}"
      echo    "  ║  1-4       acción sobre el módulo"
      echo    "  ║  r         refrescar estado"
      echo    "  ║  h         esta pantalla"
      echo    "  ║  s/q       salir al shell"
      echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣${NC}"
      echo -e "${CYAN}${BOLD}  ║  N8N${NC}"
      echo    "  ║  n8n-start    inicia n8n + cloudflared"
      echo    "  ║  n8n-stop     detiene todo"
      echo    "  ║  n8n-url      URL pública"
      echo    "  ║  n8n-status   estado del sistema"
      echo    "  ║  n8n-backup   backup de workflows"
      echo    "  ║  debian       consola Debian proot"
      echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣${NC}"
      echo -e "${CYAN}${BOLD}  ║  CLAUDE CODE${NC}"
      echo    "  ║  claude               agente interactivo"
      echo    "  ║  claude -p \"texto\"    modo directo"
      echo    "  ║  claude-update        actualizar"
      echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣${NC}"
      echo -e "${CYAN}${BOLD}  ║  OLLAMA${NC}"
      echo    "  ║  ollama-start     inicia servidor :11434"
      echo    "  ║  ollama-stop      detiene servidor"
      echo    "  ║  ollama-list      modelos instalados"
      echo    "  ║  ollama run [m]   chat con modelo"
      echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣${NC}"
      echo -e "${CYAN}${BOLD}  ║  EXPO / EAS${NC}"
      echo    "  ║  expo-build [proyecto] [perfil]"
      echo    "  ║  expo-status    ver builds activos"
      echo    "  ║  expo-login     login en expo.dev"
      echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣${NC}"
      echo -e "${CYAN}${BOLD}  ║  SISTEMA${NC}"
      echo    "  ║  menu         volver al dashboard"
      echo    "  ║  help         esta pantalla"
      echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════╝${NC}"
      echo ""
      read -r -p "  Presiona ENTER para volver al menú..." _
      ;;

    s|S|q|Q|"")
      clear
      echo ""
      echo -e "  ${DIM}termux-ai-stack · escribe 'menu' para volver${NC}"
      echo ""
      break
      ;;

    n8n-start|n8n-stop|n8n-url|n8n-status|n8n-log|\
    claude|ollama-start|ollama-stop|expo-info|debian|help)
      # Alias directos desde el menú
      eval "$OPT" 2>/dev/null
      echo ""
      read -r -p "  Presiona ENTER para volver al menú..." _
      ;;

    *)
      # Opción no reconocida — refrescar sin mensaje
      continue
      ;;
  esac

done

#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · menu.sh
#  Dashboard TUI — panel de control principal
#
#  Se ejecuta automáticamente al abrir Termux.
#  También se puede llamar manualmente con: menu
#
#  NAVEGACIÓN:
#    [1-4]  → acción / submenú del módulo
#    [r]    → refrescar estado
#    [h]    → ayuda
#    [s/q]  → salir al shell
#
#  ARQUITECTURA v2:
#    - Llama bash ~/install_X.sh (sin descargar de GitHub)
#    - Llama scripts de control directamente (sin aliases)
#    - Submenús para n8n, Ollama y Expo
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 2.0.0 | Abril 2026
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

# ── Ruta de claude (workaround ARM64 — sin alias) ─────────────
# Los aliases de .bashrc no están disponibles en subprocesos bash
find_claude_cli() {
  local npm_root
  npm_root=$(npm root -g 2>/dev/null)
  echo "${npm_root}/@anthropic-ai/claude-code/cli.js"
}

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
  echo "ready|$(get_reg expo version)|"
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

# ── Instalar módulo desde ~/ (con re-descarga si falta) ───────
install_module() {
  local name="$1"
  local script="install_${2}.sh"
  local dest="$HOME/$script"

  clear
  echo -e "\n${CYAN}${BOLD}  Instalando ${name}...${NC}\n"

  # Verificar que el script existe con contenido real
  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    echo -e "  ${YELLOW}[AVISO]${NC} ~/$script no encontrado — re-descargando..."
    rm -f "$dest"
    curl -fsSL "$REPO_RAW/$script" -o "$dest" 2>/dev/null || \
      wget -q "$REPO_RAW/$script" -O "$dest" 2>/dev/null

    if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
      echo -e "\n  ${RED}[ERROR]${NC} No se pudo obtener $script"
      echo "  Verifica tu conexión a internet."
      echo ""
      read -r -p "  Presiona ENTER para volver al menú..." _ < /dev/tty
      rm -f "$dest"
      return 1
    fi
    chmod +x "$dest"
  fi

  # Ejecutar — < /dev/tty garantiza que los read del módulo funcionen
  bash "$dest" < /dev/tty

  echo ""
  read -r -p "  Presiona ENTER para volver al menú..." _ < /dev/tty
}

# ── Pantalla de ayuda ─────────────────────────────────────────
show_help() {
  clear
  echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║     termux-ai-stack · AYUDA             ║"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  MENÚ${NC}"
  echo    "  ║  1-4    → acción / submenú del módulo"
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
  read -r -p "  Presiona ENTER para volver al menú..." _ < /dev/tty
}

# ════════════════════════════════════════════
#  SUBMENÚ N8N
# ════════════════════════════════════════════
submenu_n8n() {
  local state="$1"
  while true; do
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"

    if [ "$state" = "running" ]; then
      echo    "  ║  ⬡ N8N  ● activo                        ║"
    else
      echo    "  ║  ⬡ N8N  ● listo                         ║"
    fi

    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar n8n + cloudflared${CYAN}${BOLD}          ║"
    echo -e "  ║  ${NC}[2] Detener servidor${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[3] Ver URL pública${CYAN}${BOLD}                    ║"
    echo -e "  ║  ${NC}[4] Estado del sistema${CYAN}${BOLD}                 ║"
    echo -e "  ║  ${NC}[5] Ver logs en vivo${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[6] Consola Debian (proot)${CYAN}${BOLD}             ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo    "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        if [ -f "$HOME/start_servidor.sh" ]; then
          bash "$HOME/start_servidor.sh"
        else
          echo -e "  ${RED}[ERROR]${NC} start_servidor.sh no encontrado"
          echo "  Reinstala n8n desde el menú principal."
        fi
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        # Actualizar estado
        tmux has-session -t "n8n-server" 2>/dev/null && state="running" || state="stopped"
        ;;
      2)
        clear
        if [ -f "$HOME/stop_servidor.sh" ]; then
          bash "$HOME/stop_servidor.sh"
        else
          tmux kill-session -t "n8n-server" 2>/dev/null && \
            echo "  n8n detenido" || echo "  n8n no estaba corriendo"
        fi
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        state="stopped"
        ;;
      3)
        clear
        echo ""
        if [ -f "$HOME/ver_url.sh" ]; then
          bash "$HOME/ver_url.sh"
        else
          [ -f "$HOME/.last_cf_url" ] && cat "$HOME/.last_cf_url" || \
            echo "  URL no disponible — inicia n8n primero"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      4)
        clear
        if [ -f "$HOME/n8n_status.sh" ]; then
          bash "$HOME/n8n_status.sh"
        else
          tmux has-session -t "n8n-server" 2>/dev/null && \
            echo "  n8n: ● ACTIVO" || echo "  n8n: ○ DETENIDO"
        fi
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      5)
        clear
        echo -e "  ${CYAN}Ctrl+B D para salir sin detener n8n${NC}"
        echo ""
        if [ -f "$HOME/n8n_log.sh" ]; then
          bash "$HOME/n8n_log.sh"
        else
          tmux has-session -t "n8n-server" 2>/dev/null && \
            tmux attach-session -t "n8n-server" || \
            echo "  n8n no está corriendo"
        fi
        ;;
      6)
        clear
        echo -e "  ${CYAN}Abriendo consola Debian — escribe 'exit' para volver${NC}"
        echo ""
        proot-distro login debian 2>/dev/null || \
          echo -e "  ${RED}[ERROR]${NC} proot-distro no disponible"
        ;;
      b|B|"")
        break
        ;;
      *)
        continue
        ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ OLLAMA
# ════════════════════════════════════════════
submenu_ollama() {
  local state="$1"
  while true; do
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"

    if [ "$state" = "running" ]; then
      echo    "  ║  ◎ OLLAMA  ● activo                     ║"
    else
      echo    "  ║  ◎ OLLAMA  ● listo                      ║"
    fi

    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar servidor   :11434${CYAN}${BOLD}          ║"
    echo -e "  ║  ${NC}[2] Chat rápido        ollama run${CYAN}${BOLD}       ║"
    echo -e "  ║  ${NC}[3] Ver modelos        ollama list${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[4] Descargar modelo   ollama pull${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[5] Detener servidor${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo    "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        if [ -f "$HOME/ollama_start.sh" ]; then
          bash "$HOME/ollama_start.sh"
        else
          echo -e "  ${RED}[ERROR]${NC} ollama_start.sh no encontrado"
          echo "  Reinstala Ollama desde el menú principal."
        fi
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        tmux has-session -t "ollama-server" 2>/dev/null && state="running" || state="stopped"
        ;;
      2)
        clear
        echo -e "  ${CYAN}Modelos disponibles:${NC}"
        ollama list 2>/dev/null || echo "  (inicia el servidor primero con [1])"
        echo ""
        read -r -p "  Modelo a usar (ej: qwen:0.5b): " MODEL < /dev/tty
        [ -n "$MODEL" ] && ollama run "$MODEL" < /dev/tty
        ;;
      3)
        clear
        echo ""
        ollama list 2>/dev/null || echo "  No se pudo listar modelos"
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      4)
        clear
        echo "  Modelos recomendados:"
        echo "  qwen:0.5b · qwen:1.8b · phi3:mini · llama3.2:1b"
        echo ""
        read -r -p "  Modelo a descargar (ej: qwen:0.5b): " MODEL < /dev/tty
        if [ -n "$MODEL" ]; then
          # Necesita servidor corriendo para pull
          if ! tmux has-session -t "ollama-server" 2>/dev/null; then
            echo -e "  ${CYAN}[INFO]${NC} Iniciando servidor temporalmente..."
            ollama serve &>/dev/null &
            OLLAMA_TMP_PID=$!
            sleep 3
          fi
          ollama pull "$MODEL"
          [ -n "$OLLAMA_TMP_PID" ] && kill "$OLLAMA_TMP_PID" 2>/dev/null || true
        fi
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      5)
        clear
        if [ -f "$HOME/ollama_stop.sh" ]; then
          bash "$HOME/ollama_stop.sh"
        else
          tmux kill-session -t "ollama-server" 2>/dev/null && \
            echo "  Ollama detenido" || echo "  Ollama no estaba corriendo"
        fi
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        state="stopped"
        ;;
      b|B|"")
        break
        ;;
      *)
        continue
        ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ EXPO / EAS
# ════════════════════════════════════════════
submenu_expo() {
  while true; do
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◈ EXPO / EAS  ● listo                  ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Build APK preview${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[2] Build producción (AAB)${CYAN}${BOLD}             ║"
    echo -e "  ║  ${NC}[3] Ver builds activos${CYAN}${BOLD}                 ║"
    echo -e "  ║  ${NC}[4] Login en expo.dev${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[5] Info / estado general${CYAN}${BOLD}              ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo    "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        read -r -p "  Ruta del proyecto (Enter = directorio actual): " PROJ < /dev/tty
        [ -z "$PROJ" ] && PROJ="."
        if [ -f "$HOME/eas_build.sh" ]; then
          bash "$HOME/eas_build.sh" "$PROJ" preview
        else
          cd "$PROJ" 2>/dev/null && eas build --platform android --profile preview < /dev/tty
        fi
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      2)
        clear
        read -r -p "  Ruta del proyecto (Enter = directorio actual): " PROJ < /dev/tty
        [ -z "$PROJ" ] && PROJ="."
        if [ -f "$HOME/eas_build.sh" ]; then
          bash "$HOME/eas_build.sh" "$PROJ" production
        else
          cd "$PROJ" 2>/dev/null && eas build --platform android --profile production < /dev/tty
        fi
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      3)
        clear
        echo ""
        if [ -f "$HOME/eas_status.sh" ]; then
          bash "$HOME/eas_status.sh"
        else
          eas build:list 2>/dev/null || echo "  No se pudo obtener estado de builds"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      4)
        clear
        eas login < /dev/tty
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      5)
        clear
        echo ""
        if [ -f "$HOME/expo_info.sh" ]; then
          bash "$HOME/expo_info.sh"
        else
          echo "  EAS CLI: $(eas --version 2>/dev/null || echo 'no encontrado')"
          echo "  Usuario: $(eas whoami 2>/dev/null || echo 'no logueado')"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      b|B|"")
        break
        ;;
      *)
        continue
        ;;
    esac
  done
}

# ═══════════════════════════════════════════
#  LOOP PRINCIPAL
# ═══════════════════════════════════════════
while true; do
  clear

  # ── Re-leer estado en cada iteración ──────────────────────────
  IFS='|' read -r N8N_STATE N8N_VER N8N_EXTRA <<< "$(check_n8n)"
  IFS='|' read -r CC_STATE  CC_VER  CC_EXTRA  <<< "$(check_claude)"
  IFS='|' read -r OL_STATE  OL_VER  OL_EXTRA  <<< "$(check_ollama)"
  IFS='|' read -r EX_STATE  EX_VER  EX_EXTRA  <<< "$(check_expo)"

  # ── Info del sistema ──────────────────────────────────────────
  IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
  [ -z "$IP" ] && IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
  RAM_FREE=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%.1fGB", $7/1024}')
  [ -z "$RAM_FREE" ] && RAM_FREE="--"

  # ── Header ───────────────────────────────────────────────────
  echo -e "${CYAN}${BOLD}"
  echo    "  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "⬡ TERMUX·AI·STACK"
  printf  "  ║  %-40s║\n" \
    "$([ -n "$IP" ] && echo "IP: $IP  ·  RAM: $RAM_FREE" || echo "RAM: $RAM_FREE libre")"
  echo    "  ╠══════════════════════════════════════════╣"
  printf  "  ║  ${NC}%-38b${CYAN}${BOLD}║\n" "MÓDULOS"
  echo    "  ╚══════════════════════════════════════════╝"
  echo -e "${NC}"

  # ── Comando visible según estado ─────────────────────────────
  case "$N8N_STATE" in
    running)  N8N_CMD="→ submenú" ;;
    stopped)  N8N_CMD="→ submenú" ;;
    *)        N8N_CMD="" ;;
  esac
  draw_module "1" "⬡" "n8n" "$N8N_STATE" "$N8N_VER" "$N8N_CMD"

  case "$CC_STATE" in
    ready)  CC_CMD="claude" ;;
    *)      CC_CMD="" ;;
  esac
  draw_module "2" "◆" "Claude Code" "$CC_STATE" "$CC_VER" "$CC_CMD"

  case "$OL_STATE" in
    running) OL_CMD="→ submenú" ;;
    stopped) OL_CMD="→ submenú" ;;
    *)       OL_CMD="" ;;
  esac
  draw_module "3" "◎" "Ollama" "$OL_STATE" "$OL_VER" "$OL_CMD"

  case "$EX_STATE" in
    ready)  EX_CMD="→ submenú" ;;
    *)      EX_CMD="" ;;
  esac
  draw_module "4" "◈" "Expo / EAS" "$EX_STATE" "$EX_VER" "$EX_CMD"

  # ── Footer ────────────────────────────────────────────────────
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${DIM}[r] refrescar   [h] ayuda   [s] shell${NC}"
  echo ""

  # ── Input ─────────────────────────────────────────────────────
  read -r -p "  Opción: " OPT < /dev/tty

  case "$OPT" in
    # ── n8n ──────────────────────────────────────────────────────
    1)
      if [ "$N8N_STATE" = "not_installed" ]; then
        install_module "n8n" "n8n"
      else
        submenu_n8n "$N8N_STATE"
      fi
      ;;

    # ── Claude Code ──────────────────────────────────────────────
    2)
      if [ "$CC_STATE" = "not_installed" ]; then
        install_module "Claude Code" "claude"
      else
        clear
        CLI_PATH=$(find_claude_cli)
        if [ -f "$CLI_PATH" ] && [ -s "$CLI_PATH" ]; then
          # Lanzar Claude directamente con node (workaround ARM64/Bionic)
          node "$CLI_PATH"
        else
          echo -e "\n  ${RED}[ERROR]${NC} cli.js no encontrado en $CLI_PATH"
          echo "  Reinstala Claude Code con opción [2] del menú"
          echo ""
          read -r -p "  ¿Reinstalar ahora? (s/n): " REINSTALL < /dev/tty
          [ "$REINSTALL" = "s" ] || [ "$REINSTALL" = "S" ] && \
            install_module "Claude Code" "claude"
        fi
      fi
      ;;

    # ── Ollama ───────────────────────────────────────────────────
    3)
      if [ "$OL_STATE" = "not_installed" ]; then
        install_module "Ollama" "ollama"
      else
        submenu_ollama "$OL_STATE"
      fi
      ;;

    # ── Expo / EAS ───────────────────────────────────────────────
    4)
      if [ "$EX_STATE" = "not_installed" ]; then
        install_module "Expo/EAS" "expo"
      else
        submenu_expo
      fi
      ;;

    r|R)
      continue
      ;;

    h|H)
      show_help
      ;;

    s|S|q|Q|"")
      clear
      echo ""
      echo -e "  ${DIM}termux-ai-stack · escribe 'menu' para volver${NC}"
      echo ""
      break
      ;;

    *)
      continue
      ;;
  esac

done

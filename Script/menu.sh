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
#    [b]    → backup / restore
#    [u]    → actualizar scripts
#    [s/q]  → salir al shell
#
#  ARQUITECTURA v2:
#    - Llama bash ~/install_X.sh (sin descargar de GitHub)
#    - Llama scripts de control directamente (sin aliases)
#    - Submenús para n8n, Ollama y Expo
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 2.3.0 | Abril 2026
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
  local ver
  ver=$(pkg show ollama 2>/dev/null | grep "^Version:" | awk '{print $2}')
  [ -z "$ver" ] && ver=$(get_reg ollama version)
  [ -z "$ver" ] && ver="?"
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

# ── Instalar módulo — elige limpio o desde GitHub Releases ───
install_module() {
  local name="$1"
  local module_key="$2"   # ej: n8n, claude, ollama, expo
  local script="install_${module_key}.sh"
  local dest="$HOME/$script"

  clear
  echo ""
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "¿Cómo instalar ${name}?"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}[1] Instalación limpia${CYAN}${BOLD}                  ║"
  echo -e "  ║  ${NC}[2] Desde GitHub Releases${CYAN}${BOLD}               ║"
  echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                            ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -n "  Opción: "
  read -r INST_OPT < /dev/tty

  case "$INST_OPT" in
    2)
      # Restore desde GitHub Releases
      if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
        echo -e "\n  ${YELLOW}[AVISO]${NC} restore.sh no encontrado — descargando..."
        curl -fsSL "$REPO_RAW/restore.sh" -o "$HOME/restore.sh" 2>/dev/null || \
          wget -q "$REPO_RAW/restore.sh" -O "$HOME/restore.sh" 2>/dev/null
        if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
          echo -e "  ${RED}[ERROR]${NC} No se pudo obtener restore.sh"
          echo ""
          read -r _ < /dev/tty
          return 1
        fi
        chmod +x "$HOME/restore.sh"
      fi
      bash "$HOME/restore.sh" --module "$module_key" < /dev/tty
      echo ""
      read -r _ < /dev/tty
      return 0
      ;;
    b|B|"")
      return 0
      ;;
    1|*)
      # Instalación limpia (default)
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
          read -r _ < /dev/tty
          rm -f "$dest"
          return 1
        fi
        chmod +x "$dest"
      fi

      bash "$dest" < /dev/tty
      echo ""
      read -r _ < /dev/tty
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

# Helper: asegura servidor corriendo antes de operar
_ollama_ensure_server() {
  if ! tmux has-session -t "ollama-server" 2>/dev/null; then
    echo -e "  ${YELLOW}[AVISO]${NC} El servidor Ollama no está corriendo."
    echo -n "  ¿Iniciarlo ahora? (s/n): "
    read -r _ANS < /dev/tty
    if [ "$_ANS" = "s" ] || [ "$_ANS" = "S" ]; then
      if [ -f "$HOME/ollama_start.sh" ]; then
        bash "$HOME/ollama_start.sh"
      else
        ollama serve &>/dev/null &
        sleep 3
      fi
      tmux has-session -t "ollama-server" 2>/dev/null && \
        echo -e "  ${GREEN}[OK]${NC} Servidor iniciado" || \
        echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar el servidor"
      echo ""
      return 0
    else
      return 1
    fi
  fi
  return 0
}

# Helper: lista modelos instalados como array
_ollama_list_models() {
  ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^$"
}

submenu_ollama() {
  local state="$1"
  while true; do
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"

    if [ "$state" = "running" ]; then
      echo -e "  ║  ◎ OLLAMA  ${GREEN}● activo${CYAN}${BOLD}                     ║"
    else
      echo -e "  ║  ◎ OLLAMA  ● listo                      ║"
    fi

    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar servidor   :11434${CYAN}${BOLD}          ║"
    echo -e "  ║  ${NC}[2] Chat rápido${CYAN}${BOLD}                        ║"
    echo -e "  ║  ${NC}[3] Ver modelos${CYAN}${BOLD}                        ║"
    echo -e "  ║  ${NC}[4] Descargar modelo${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[5] Detener servidor${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      # ── [1] Iniciar servidor ────────────────────────────────
      1)
        clear
        if [ -f "$HOME/ollama_start.sh" ]; then
          bash "$HOME/ollama_start.sh"
        else
          echo -e "  ${RED}[ERROR]${NC} ollama_start.sh no encontrado"
          echo "  Reinstala Ollama desde el menú principal."
        fi
        echo ""
        read -r _ < /dev/tty
        tmux has-session -t "ollama-server" 2>/dev/null && state="running" || state="stopped"
        ;;

      # ── [2] Chat rápido ─────────────────────────────────────
      2)
        clear
        echo ""

        # Verificar servidor
        _ollama_ensure_server || { read -r _ < /dev/tty; continue; }

        # Leer modelos instalados dinámicamente
        mapfile -t MODELS < <(_ollama_list_models)

        if [ ${#MODELS[@]} -eq 0 ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} No hay modelos instalados."
          echo "  Ve a [4] para descargar uno."
          echo ""
          read -r _ < /dev/tty
          continue
        fi

        echo -e "  ${CYAN}Modelos instalados:${NC}"
        echo ""
        for i in "${!MODELS[@]}"; do
          printf "    [%d] %s\n" "$((i+1))" "${MODELS[$i]}"
        done
        echo ""
        echo -e "  ${DIM}Tip: escribe /bye para salir del chat${NC}"
        echo ""
        echo -n "  Elige número de modelo: "
        read -r CHOICE < /dev/tty

        # Validar elección
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && \
           [ "$CHOICE" -ge 1 ] && \
           [ "$CHOICE" -le "${#MODELS[@]}" ]; then
          SELECTED="${MODELS[$((CHOICE-1))]}"
          echo ""
          echo -e "  ${GREEN}[OK]${NC} Iniciando chat con ${CYAN}${SELECTED}${NC}..."
          echo -e "  ${DIM}(escribe /bye para salir)${NC}"
          echo ""
          ollama run "$SELECTED" < /dev/tty
        else
          echo -e "  ${RED}[ERROR]${NC} Número inválido."
          read -r _ < /dev/tty
        fi
        ;;

      # ── [3] Ver modelos ─────────────────────────────────────
      3)
        clear
        echo ""

        _ollama_ensure_server || { read -r _ < /dev/tty; continue; }

        MODELS_OUT=$(_ollama_list_models)
        if [ -z "$MODELS_OUT" ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} No hay modelos instalados."
          echo "  Ve a [4] para descargar uno."
        else
          echo -e "  ${CYAN}Modelos instalados:${NC}"
          echo ""
          ollama list 2>/dev/null
        fi
        echo ""
        read -r _ < /dev/tty
        ;;

      # ── [4] Descargar modelo ────────────────────────────────
      4)
        clear
        echo ""

        # Servidor necesario para pull
        _ollama_ensure_server || { read -r _ < /dev/tty; continue; }

        echo -e "  ${CYAN}Modelos recomendados para móvil (≤ 12GB RAM):${NC}"
        echo ""
        echo "    [a] qwen2.5:0.5b    ~397MB  — más liviano"
        echo "    [b] qwen2.5:1.5b    ~986MB  — balance liviano"
        echo "    [c] qwen:1.8b       ~1.1GB  — balance velocidad/calidad"
        echo "    [d] llama3.2:1b     ~1.3GB  — buena calidad, liviano"
        echo "    [e] phi3:mini       ~2.3GB  — mejor calidad"
        echo "    [f] Escribir nombre manualmente"
        echo ""
        echo -e "  ${DIM}⚠️  NO usar modelos 7B o más — crash garantizado${NC}"
        echo ""
        echo -n "  Elige opción [a-f]: "
        read -r DCHOICE < /dev/tty

        case "$DCHOICE" in
          a|A) DL_MODEL="qwen2.5:0.5b" ;;
          b|B) DL_MODEL="qwen2.5:1.5b" ;;
          c|C) DL_MODEL="qwen:1.8b" ;;
          d|D) DL_MODEL="llama3.2:1b" ;;
          e|E) DL_MODEL="phi3:mini" ;;
          f|F)
            echo ""
            echo -e "  ${DIM}Escribe solo el nombre del modelo (ej: qwen2.5:1.5b)${NC}"
            echo -n "  Nombre: "
            read -r DL_MODEL < /dev/tty
            ;;
          *)
            echo -e "  ${RED}[ERROR]${NC} Opción inválida."
            read -r _ < /dev/tty
            continue
            ;;
        esac

        if [ -n "$DL_MODEL" ]; then
          echo ""
          echo -e "  ${CYAN}[INFO]${NC} Descargando ${DL_MODEL}..."
          echo "  Esto puede tardar varios minutos."
          echo ""
          ollama pull "$DL_MODEL"
          PULL_STATUS=$?
          echo ""
          if [ $PULL_STATUS -eq 0 ]; then
            echo -e "  ${GREEN}[OK]${NC} Modelo ${DL_MODEL} descargado."
          else
            echo -e "  ${RED}[ERROR]${NC} Falló la descarga. Verifica el nombre o tu conexión."
          fi
        fi
        echo ""
        read -r _ < /dev/tty
        ;;

      # ── [5] Detener servidor ────────────────────────────────
      5)
        clear
        echo ""
        if [ -f "$HOME/ollama_stop.sh" ]; then
          bash "$HOME/ollama_stop.sh"
        else
          tmux kill-session -t "ollama-server" 2>/dev/null && \
            echo -e "  ${GREEN}[OK]${NC} Ollama detenido" || \
            echo "  Ollama no estaba corriendo"
        fi
        echo ""
        read -r _ < /dev/tty
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

# ════════════════════════════════════════════
#  SUBMENÚ BACKUP / RESTORE
# ════════════════════════════════════════════
submenu_backup() {
  while true; do
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◉ BACKUP / RESTORE                     ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Backup completo${CYAN}${BOLD}                    ║"
    echo -e "  ║  ${NC}[2] Backup individual${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[3] Restore completo${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[4] Restore por partes${CYAN}${BOLD}                 ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -n "  Opción: "
    read -r OPT < /dev/tty

    # Helper interno: asegurar restore.sh disponible
    _ensure_restore() {
      if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
        echo -e "  ${YELLOW}[AVISO]${NC} restore.sh no encontrado — descargando..."
        curl -fsSL "$REPO_RAW/restore.sh" -o "$HOME/restore.sh" 2>/dev/null || \
          wget -q "$REPO_RAW/restore.sh" -O "$HOME/restore.sh" 2>/dev/null
        if [ ! -f "$HOME/restore.sh" ] || [ ! -s "$HOME/restore.sh" ]; then
          echo -e "  ${RED}[ERROR]${NC} No se pudo obtener restore.sh — verifica conexión"
          return 1
        fi
        chmod +x "$HOME/restore.sh"
      fi
      return 0
    }

    # Helper interno: asegurar backup.sh disponible
    _ensure_backup() {
      if [ ! -f "$HOME/backup.sh" ] || [ ! -s "$HOME/backup.sh" ]; then
        echo -e "  ${YELLOW}[AVISO]${NC} backup.sh no encontrado — descargando..."
        curl -fsSL "$REPO_RAW/backup.sh" -o "$HOME/backup.sh" 2>/dev/null || \
          wget -q "$REPO_RAW/backup.sh" -O "$HOME/backup.sh" 2>/dev/null
        if [ ! -f "$HOME/backup.sh" ] || [ ! -s "$HOME/backup.sh" ]; then
          echo -e "  ${RED}[ERROR]${NC} No se pudo obtener backup.sh — verifica conexión"
          return 1
        fi
        chmod +x "$HOME/backup.sh"
      fi
      return 0
    }

    case "$OPT" in
      # ── [1] Backup completo ─────────────────────────────────
      1)
        clear
        _ensure_backup || { echo ""; read -r _ < /dev/tty; continue; }
        bash "$HOME/backup.sh" < /dev/tty
        echo ""
        read -r _ < /dev/tty
        ;;

      # ── [2] Backup individual ───────────────────────────────
      2)
        clear
        echo ""
        echo -e "  ${CYAN}${BOLD}Backup individual — elige módulo:${NC}"
        echo ""
        echo "  [1] base   — .bashrc + scripts + .termux"
        echo "  [2] claude — Claude Code"
        echo "  [3] expo   — EAS CLI + credenciales"
        echo "  [4] ollama — Ollama binario + libs"
        echo "  [5] n8n    — n8n + cloudflared"
        echo "  [b] Cancelar"
        echo ""
        echo -n "  Módulo: "
        read -r MOD_OPT < /dev/tty

        case "$MOD_OPT" in
          1) BAK_MOD="base"   ;;
          2) BAK_MOD="claude" ;;
          3) BAK_MOD="expo"   ;;
          4) BAK_MOD="ollama" ;;
          5) BAK_MOD="n8n"    ;;
          b|B|"") continue    ;;
          *) echo -e "  ${RED}[ERROR]${NC} Opción inválida"
             read -r _ < /dev/tty; continue ;;
        esac

        _ensure_backup || { echo ""; read -r _ < /dev/tty; continue; }
        bash "$HOME/backup.sh" --module "$BAK_MOD" < /dev/tty
        echo ""
        read -r _ < /dev/tty
        ;;

      # ── [3] Restore completo ────────────────────────────────
      3)
        clear
        _ensure_restore || { echo ""; read -r _ < /dev/tty; continue; }
        bash "$HOME/restore.sh" --module all < /dev/tty
        echo ""
        read -r _ < /dev/tty
        ;;

      # ── [4] Restore por partes (menú interactivo) ───────────
      4)
        clear
        _ensure_restore || { echo ""; read -r _ < /dev/tty; continue; }
        bash "$HOME/restore.sh" < /dev/tty
        echo ""
        read -r _ < /dev/tty
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

  # ── Separador + Backup/Restore ───────────────────────────────
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}[0]${NC} ◉ Backup / Restore                        ${CYAN}→ submenú${NC}"
  echo ""

  # ── Footer ────────────────────────────────────────────────────
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${DIM}[r] refrescar  [h] ayuda  [u] actualizar  [s] shell${NC}"
  echo ""

  # ── Input ─────────────────────────────────────────────────────
  read -r -p "  Opción: " OPT < /dev/tty

  case "$OPT" in
    # ── n8n ──────────────────────────────────────────────────────
    1)
      if [ "$N8N_STATE" = "not_installed" ]; then
        install_module "n8n" "n8n"
        continue
      else
        submenu_n8n "$N8N_STATE"
      fi
      ;;

    # ── Claude Code ──────────────────────────────────────────────
    2)
      if [ "$CC_STATE" = "not_installed" ]; then
        install_module "Claude Code" "claude"
        continue
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
          if [ "$REINSTALL" = "s" ] || [ "$REINSTALL" = "S" ]; then
            install_module "Claude Code" "claude"
            continue
          fi
        fi
      fi
      ;;

    # ── Ollama ───────────────────────────────────────────────────
    3)
      if [ "$OL_STATE" = "not_installed" ]; then
        install_module "Ollama" "ollama"
        continue
      else
        submenu_ollama "$OL_STATE"
      fi
      ;;

    # ── Expo / EAS ───────────────────────────────────────────────
    4)
      if [ "$EX_STATE" = "not_installed" ]; then
        install_module "Expo/EAS" "expo"
        continue
      else
        submenu_expo
      fi
      ;;

    # ── Backup / Restore ─────────────────────────────────────────
    0)
      submenu_backup
      ;;

    r|R)
      continue
      ;;

    u|U)
      clear
      echo ""
      echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
      echo    "  ║   Actualizando scripts desde GitHub...  ║"
      echo    "  ╚══════════════════════════════════════════╝${NC}"
      echo ""

      SCRIPTS=("install_n8n.sh" "install_claude.sh" "install_ollama.sh" "install_expo.sh" "menu.sh" "backup.sh" "restore.sh")
      UPDATE_OK=0
      UPDATE_FAIL=0

      for SCRIPT in "${SCRIPTS[@]}"; do
        echo -n "  Descargando $SCRIPT... "
        TMP="$HOME/${SCRIPT}.tmp"
        curl -fsSL "$REPO_RAW/$SCRIPT" -o "$TMP" 2>/dev/null || \
          wget -q "$REPO_RAW/$SCRIPT" -O "$TMP" 2>/dev/null

        if [ -f "$TMP" ] && [ -s "$TMP" ]; then
          mv "$TMP" "$HOME/$SCRIPT"
          chmod +x "$HOME/$SCRIPT"
          echo -e "${GREEN}✓${NC}"
          UPDATE_OK=$((UPDATE_OK + 1))
        else
          rm -f "$TMP"
          echo -e "${RED}✗ error${NC}"
          UPDATE_FAIL=$((UPDATE_FAIL + 1))
        fi
      done

      echo ""
      echo -e "  ${GREEN}[OK]${NC} $UPDATE_OK actualizados   ${RED}[FAIL]${NC} $UPDATE_FAIL fallidos"
      echo ""

      if [ "$UPDATE_FAIL" -gt 0 ]; then
        echo -e "  ${YELLOW}[AVISO]${NC} Verifica tu conexión a internet."
        echo ""
      fi

      read -r _ < /dev/tty

      # Si menu.sh se actualizó, relanzar para cargar la versión nueva
      exec bash "$HOME/menu.sh"
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

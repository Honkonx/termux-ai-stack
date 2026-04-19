#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · menu.sh
#  Dashboard TUI — panel de control principal
#
#  Se ejecuta automáticamente al abrir Termux.
#  También se puede llamar manualmente con: menu
#
#  NAVEGACIÓN:
#    [1-6]  → acción / submenú del módulo
#    [0]    → backup / restore
#    [r]    → refrescar estado
#    [h]    → ayuda
#    [u]    → actualizar scripts
#    [s/q]  → salir al shell
#
#  ARQUITECTURA v2:
#    - Llama bash ~/install_X.sh (sin descargar de GitHub)
#    - Llama scripts de control directamente (sin aliases)
#    - Submenús para n8n, Ollama, Expo, Python y SSH
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 3.1.2 | Abril 2026
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

# ── Detectar IP local (independiente del nombre de interfaz) ──
# Usa ifconfig — funciona en Android con netlink restringido
# Prefiere interfaz con máscara /24 (WiFi real, no VPN/tunnel)
_get_ip() {
  local ip
  # Método 1: ifconfig — máscara 255.255.x.x = red local real
  ip=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | \
       grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
  # Método 2: ifconfig — cualquier inet no-loopback (fallback)
  [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep "inet " | \
       grep -v "127\." | awk '{print $2}' | head -1)
  # Método 3: ip addr — último recurso
  [ -z "$ip" ] && ip=$(ip addr show 2>/dev/null | grep "inet " | \
       grep -v "127\." | awk '{print $2}' | cut -d'/' -f1 | head -1)
  echo "${ip:-<tu_IP_WiFi>}"
}

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
  local cli_path
  cli_path=$(find_claude_cli)

  # Validación dual: registry O cli.js presente
  # Evita falso "not_installed" por race condition post-instalación
  local reg_ok=false
  local cli_ok=false
  [ "$(get_reg claude_code installed)" = "true" ] && reg_ok=true
  [ -f "$cli_path" ] && [ -s "$cli_path" ] && cli_ok=true

  if [ "$reg_ok" = "false" ] && [ "$cli_ok" = "false" ]; then
    echo "not_installed||"
    return
  fi

  # Registry dice instalado pero cli.js no existe — limpiar registry
  if [ "$reg_ok" = "true" ] && [ "$cli_ok" = "false" ]; then
    grep -v "^claude_code\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
    echo "not_installed||"
    return
  fi

  # Si cli.js existe pero registry no → reparar registry silenciosamente
  if [ "$reg_ok" = "false" ] && [ "$cli_ok" = "true" ]; then
    local ver
    ver=$(node "$cli_path" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver" ] && ver="unknown"
    grep -v "^claude_code\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null || touch "$REGISTRY.tmp"
    cat >> "$REGISTRY.tmp" << EOF
claude_code.installed=true
claude_code.version=$ver
claude_code.install_date=$(date +%Y-%m-%d)
claude_code.location=termux_native
EOF
    mv "$REGISTRY.tmp" "$REGISTRY"
  fi

  local ver
  ver=$(get_reg claude_code version)
  # Si registry tiene "unknown" o está vacío, intentar leer del binario
  if [ -z "$ver" ] || [ "$ver" = "unknown" ]; then
    ver=$(node "$cli_path" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  fi
  # Si sigue vacío, el cli.js puede ser un wrapper bash — marcar para reinstalar
  [ -z "$ver" ] && ver="err:reinstalar"
  echo "ready|${ver}|"
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

check_python() {
  [ "$(get_reg python installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver
  ver=$(get_reg python version)
  [ -z "$ver" ] && ver="?"
  echo "ready|${ver}|"
}

check_ssh() {
  [ "$(get_reg ssh installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver
  ver=$(get_reg ssh version)
  [ -z "$ver" ] && ver="?"
  pgrep -x sshd &>/dev/null && \
    echo "running|${ver}|" || echo "stopped|${ver}|"
}

check_dashboard() {
  local ver
  ver=$(get_reg dashboard version)
  [ -z "$ver" ] && ver="1.0"
  [ "$(get_reg dashboard installed)" = "true" ] || {
    # Fallback: verificar si el script existe aunque el registry no lo diga
    [ -f "$HOME/dashboard_start.sh" ] || { echo "not_installed||"; return; }
  }
  pgrep -f "dashboard_server.py" &>/dev/null && \
    echo "running|${ver}|:8080" || echo "stopped|${ver}|:8080"
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
  if [ "$ver" = "err:reinstalar" ]; then
    printf "       ${RED}⚠ cli.js corrompido — presiona [2] para reinstalar${NC}\n"
  else
    printf "       ${DIM}v%s${NC}\n" "$ver"
  fi
  echo ""
}

# ── Helper interno: asegurar restore.sh disponible ───────────
_ensure_restore_for_install() {
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
  return 0
}

# ── Helper interno: verificar/descargar script de instalación ─
_ensure_install_script() {
  local script="$1"
  local dest="$HOME/$script"
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
  return 0
}

# ── Instalar módulo — elige limpio o desde GitHub Releases ───
install_module() {
  local name="$1"
  local module_key="$2"   # ej: n8n, claude, ollama, expo
  local script="install_${module_key}.sh"
  local dest="$HOME/$script"

  clear
  echo ""

  # ── Menú especial para n8n (4 opciones) ──────────────────────
  if [ "$module_key" = "n8n" ]; then
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ¿Cómo instalar n8n?                     ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Todo desde GitHub${CYAN}${BOLD}                   ║"
    echo -e "  ║      ${DIM}rootfs + n8n precompilados · recomend${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Todo limpio${CYAN}${BOLD}                          ║"
    echo -e "  ║      ${DIM}proot-distro + npm install · 25-40 min${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Rootfs GitHub + n8n limpio${CYAN}${BOLD}           ║"
    echo -e "  ║      ${DIM}rootfs de GitHub, n8n fresco con npm  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Rootfs limpio + n8n GitHub${CYAN}${BOLD}           ║"
    echo -e "  ║      ${DIM}proot-distro + n8n del paquete GitHub ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                             ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -n "  Opción: "
    read -r INST_OPT < /dev/tty

    case "$INST_OPT" in
      1)
        _ensure_restore_for_install || return 1
        _ensure_install_script "$script" || return 1
        export N8N_INSTALL_MODE=1
        bash "$dest" < /dev/tty
        unset N8N_INSTALL_MODE
        echo ""
        read -r _ < /dev/tty
        ;;
      2)
        _ensure_install_script "$script" || return 1
        export N8N_INSTALL_MODE=2
        bash "$dest" < /dev/tty
        unset N8N_INSTALL_MODE
        echo ""
        read -r _ < /dev/tty
        ;;
      3)
        _ensure_restore_for_install || return 1
        _ensure_install_script "$script" || return 1
        export N8N_INSTALL_MODE=3
        bash "$dest" < /dev/tty
        unset N8N_INSTALL_MODE
        echo ""
        read -r _ < /dev/tty
        ;;
      4)
        _ensure_restore_for_install || return 1
        _ensure_install_script "$script" || return 1
        export N8N_INSTALL_MODE=4
        bash "$dest" < /dev/tty
        unset N8N_INSTALL_MODE
        echo ""
        read -r _ < /dev/tty
        ;;
      b|B|"")
        return 0
        ;;
      *)
        return 0
        ;;
    esac
    return 0
  fi

  # ── Menú genérico para otros módulos (2 opciones) ────────────
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "¿Cómo instalar ${name}?"
  echo    "  ╠══════════════════════════════════════════╣"

  # Python y SSH — solo instalación limpia (no tienen backup en Releases)
  if [ "$module_key" = "python" ] || [ "$module_key" = "ssh" ]; then
    echo -e "  ║  ${NC}[1] Instalación limpia${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                            ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -n "  Opción: "
    read -r INST_OPT < /dev/tty
    case "$INST_OPT" in
      b|B|"") return 0 ;;
      1|*)
        echo -e "\n${CYAN}${BOLD}  Instalando ${name}...${NC}\n"
        _ensure_install_script "$script" || return 1
        bash "$dest" < /dev/tty
        echo ""
        read -r _ < /dev/tty
        ;;
    esac
    return 0
  fi

  # Aviso especial para Claude — npm instala versión incompatible con Termux ARM64
  if [ "$module_key" = "claude" ]; then
    echo -e "  ║  ${NC}[1] Instalación limpia (npm)${CYAN}${BOLD}             ║"
    echo -e "  ║  ${RED}    ⚠ puede fallar en Termux ARM64${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[2] Desde GitHub Releases${CYAN}${BOLD}               ║"
    echo -e "  ║  ${GREEN}    ✓ recomendado — funciona siempre${CYAN}${BOLD}   ║"
  else
    echo -e "  ║  ${NC}[1] Instalación limpia${CYAN}${BOLD}                  ║"
    echo -e "  ║  ${NC}[2] Desde GitHub Releases${CYAN}${BOLD}               ║"
  fi
  echo -e "  ║  ${NC}[b] Cancelar${CYAN}${BOLD}                            ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -n "  Opción: "
  read -r INST_OPT < /dev/tty

  case "$INST_OPT" in
    2)
      _ensure_restore_for_install || return 1
      bash "$HOME/restore.sh" --module "$module_key" < /dev/tty
      echo ""
      read -r _ < /dev/tty
      return 0
      ;;
    b|B|"")
      return 0
      ;;
    1|*)
      echo -e "\n${CYAN}${BOLD}  Instalando ${name}...${NC}\n"
      _ensure_install_script "$script" || return 1
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

    if [ -f "$HOME/.cf_token" ] && [ -s "$HOME/.cf_token" ]; then
      echo -e "  ║  ${NC}Tunnel: URL fija ${GREEN}●${NC}${CYAN}${BOLD}                   ║"
    else
      echo -e "  ║  ${NC}Tunnel: URL temporal ${YELLOW}○${NC}${CYAN}${BOLD}                 ║"
    fi

    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar n8n + cloudflared${CYAN}${BOLD}          ║"
    echo -e "  ║  ${NC}[2] Detener servidor${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[3] Ver URL pública${CYAN}${BOLD}                    ║"
    echo -e "  ║  ${NC}[4] Estado del sistema${CYAN}${BOLD}                 ║"
    echo -e "  ║  ${NC}[5] Ver logs en vivo${CYAN}${BOLD}                   ║"
    echo -e "  ║  ${NC}[6] Consola Debian (proot)${CYAN}${BOLD}             ║"
    echo -e "  ║  ${NC}[7] Cambiar token cloudflared${CYAN}${BOLD}          ║"
    echo -e "  ║  ${NC}[8] Configurar URL webhook n8n${CYAN}${BOLD}         ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        # Exportar N8N_WEBHOOK_URL si está configurada
        _WH=$(grep "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" 2>/dev/null | cut -d'=' -f2)
        [ -n "$_WH" ] && export N8N_WEBHOOK_URL="$_WH" &&           echo -e "  ${GREEN}[INFO]${NC} Webhook URL: ${_WH}"
        if [ -f "$HOME/start_servidor.sh" ]; then
          bash "$HOME/start_servidor.sh"
        else
          echo -e "  ${RED}[ERROR]${NC} start_servidor.sh no encontrado"
          echo "  Reinstala n8n desde el menú principal."
        fi
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
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
        echo -e "  ${BOLD}URL pública de n8n:${NC}"
        echo ""
        # Prioridad: URL webhook configurada > .last_cf_url > ver_url.sh
        WH_URL=$(grep "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" 2>/dev/null | cut -d'=' -f2)
        if [ -n "$WH_URL" ]; then
          echo -e "  ${GREEN}${WH_URL}${NC}"
          echo ""
          echo -e "  ${DIM}(URL webhook configurada manualmente)${NC}"
        elif [ -f "$HOME/.last_cf_url" ] && [ -s "$HOME/.last_cf_url" ]; then
          echo -e "  ${GREEN}$(cat "$HOME/.last_cf_url")${NC}"
        elif [ -f "$HOME/ver_url.sh" ]; then
          bash "$HOME/ver_url.sh"
        else
          echo -e "  ${YELLOW}URL no disponible${NC}"
          echo ""
          echo "  Opciones:"
          echo "  · Inicia n8n con [1] si usas URL temporal"
          echo "  · Configura tu dominio con [8] si tienes token fijo"
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
      7)
        clear
        echo ""
        echo -e "  ${BOLD}Token cloudflared${NC}"
        echo ""
        if [ -f "$HOME/.cf_token" ] && [ -s "$HOME/.cf_token" ]; then
          echo -e "  Estado actual: ${GREEN}URL fija (token configurado)${NC}"
        else
          echo -e "  Estado actual: ${YELLOW}URL temporal (sin token)${NC}"
        fi
        echo ""
        echo "  Deja vacío + ENTER → URL temporal (cambia en cada reinicio)"
        echo "  Pega tu token      → URL fija permanente (cuenta Cloudflare)"
        echo ""
        read -r -p "  Nuevo token (ENTER = URL temporal): " NEW_TOKEN < /dev/tty
        if [ -n "$NEW_TOKEN" ]; then
          echo "$NEW_TOKEN" > "$HOME/.cf_token"
          echo -e "\n  ${GREEN}[OK]${NC} Token guardado — próximo inicio usará URL fija"
        else
          rm -f "$HOME/.cf_token"
          echo -e "\n  ${GREEN}[OK]${NC} Token eliminado — próximo inicio usará URL temporal"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      8)
        clear
        echo ""
        echo -e "  ${BOLD}Configurar URL webhook de n8n${NC}"
        echo ""
        echo "  n8n necesita saber su URL pública para que los"
        echo "  webhooks funcionen correctamente con Telegram y"
        echo "  otros servicios externos."
        echo ""
        # Mostrar valor actual
        CURRENT_WH=$(grep "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" 2>/dev/null | cut -d'=' -f2)
        CF_TOKEN_WH=$(cat "$HOME/.cf_token" 2>/dev/null)
        if [ -n "$CURRENT_WH" ]; then
          echo -e "  URL actual: ${GREEN}${CURRENT_WH}${NC}"
        elif [ -n "$CF_TOKEN_WH" ]; then
          echo -e "  Token cloudflared detectado — URL fija disponible"
        else
          echo -e "  URL actual: ${YELLOW}no configurada${NC}"
        fi
        echo ""
        echo "  Ejemplos:"
        echo "  https://mi-dominio.com"
        echo "  https://xxxx.ngrok-free.app"
        echo ""
        echo "  (ENTER sin escribir = cancelar)"
        echo -n "  Nueva URL webhook: "
        read -r NEW_WH < /dev/tty
        if [ -n "$NEW_WH" ]; then
          # Guardar en archivo de env
          grep -v "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" > "$HOME/.env_n8n.tmp" 2>/dev/null || touch "$HOME/.env_n8n.tmp"
          echo "N8N_WEBHOOK_URL=${NEW_WH}" >> "$HOME/.env_n8n.tmp"
          mv "$HOME/.env_n8n.tmp" "$HOME/.env_n8n"
          # Guardar también en .last_cf_url para que ver_url.sh la muestre
          echo "$NEW_WH" > "$HOME/.last_cf_url"
          echo ""
          echo -e "  ${GREEN}[OK]${NC} URL guardada: ${NEW_WH}"
          echo ""
          echo -e "  ${YELLOW}IMPORTANTE:${NC} Reinicia n8n para que tome efecto."
          echo "  En start_servidor.sh la variable N8N_WEBHOOK_URL"
          echo "  debe pasarse al proceso de n8n dentro del proot."
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
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
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
#  SUBMENÚ DASHBOARD
# ════════════════════════════════════════════
submenu_dashboard() {
  local state="$1"
  while true; do
    clear
    echo ""
    # Re-leer estado real en cada vuelta del submenú
    pgrep -f "dashboard_server.py" &>/dev/null && state="running" || state="stopped"
    local IP; IP=$(_get_ip)

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    if [ "$state" = "running" ]; then
      printf  "  ║  %-40s║\n" "⬡ DASHBOARD  ● activo · :8080"
      printf  "  ║  %-40s║\n" "  http://${IP}:8080"
    else
      printf  "  ║  %-40s║\n" "⬡ DASHBOARD  ● listo"
    fi
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar dashboard  (:8080)    ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[2] Detener dashboard             ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[3] Ver URL de acceso             ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal      ${CYAN}${BOLD}    ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        echo ""
        if pgrep -f "dashboard_server.py" &>/dev/null; then
          echo -e "  ${YELLOW}[AVISO]${NC} El dashboard ya está corriendo."
          echo -e "  Accede en: ${GREEN}http://$(_get_ip):8080${NC}"
        elif [ -f "$HOME/dashboard_start.sh" ]; then
          bash "$HOME/dashboard_start.sh" < /dev/null &
          sleep 2
          if pgrep -f "dashboard_server.py" &>/dev/null; then
            echo -e "  ${GREEN}[OK]${NC} Dashboard iniciado"
            echo -e "  URL: ${GREEN}http://$(_get_ip):8080${NC}"
          else
            echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar el dashboard"
            echo "  Intenta manualmente: bash ~/dashboard_start.sh"
          fi
        else
          echo -e "  ${RED}[ERROR]${NC} dashboard_start.sh no encontrado"
          echo "  Descárgalo: curl -fsSL URL -o ~/dashboard_start.sh"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      2)
        clear
        echo ""
        if [ -f "$HOME/dashboard_stop.sh" ]; then
          bash "$HOME/dashboard_stop.sh" < /dev/null
        else
          pkill -f "dashboard_server.py" 2>/dev/null && \
            echo -e "  ${GREEN}[OK]${NC} Dashboard detenido" || \
            echo "  Dashboard no estaba corriendo"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      3)
        clear
        echo ""
        local _IP; _IP=$(_get_ip)
        echo -e "  ${BOLD}URLs de acceso:${NC}"
        echo ""
        echo -e "  ${GREEN}http://${_IP}:8080${NC}       ← desde cualquier dispositivo en la misma red"
        echo -e "  ${CYAN}http://localhost:8080${NC}   ← desde la app React Native"
        echo ""
        if pgrep -f "dashboard_server.py" &>/dev/null; then
          echo -e "  Estado: ${GREEN}● activo${NC}"
        else
          echo -e "  Estado: ${RED}○ detenido — usa [1] para iniciar${NC}"
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
    echo -e "  ║  ${NC}[1] Backup completo (1 archivo)${CYAN}${BOLD}        ║"
    echo -e "  ║  ${NC}[2] Backup por partes (6 archivos)${CYAN}${BOLD}     ║"
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
      # ── [1] Backup completo en 1 archivo ───────────────────
      1)
        clear
        _ensure_backup || { echo ""; read -r _ < /dev/tty; continue; }
        bash "$HOME/backup.sh" --full < /dev/tty
        echo ""
        read -r _ < /dev/tty
        ;;

      # ── [2] Backup por partes ───────────────────────────────
      2)
        clear
        echo ""
        echo -e "  ${CYAN}${BOLD}Backup por partes — elige módulo:${NC}"
        echo ""
        echo "  [1] base   — .bashrc + scripts + .termux"
        echo "  [2] claude — Claude Code"
        echo "  [3] expo   — EAS CLI + credenciales"
        echo "  [4] ollama — Ollama binario + libs"
        echo "  [5] n8n    — n8n + cloudflared"
        echo "  [6] proot  — Rootfs Debian completo (~834MB)"
        echo "  [7] todas  — Las 6 partes en archivos separados"
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
          6) BAK_MOD="proot"  ;;
          7) BAK_MOD=""       ;;  # sin --module = todas las partes
          b|B|"") continue    ;;
          *) echo -e "  ${RED}[ERROR]${NC} Opción inválida"
             read -r _ < /dev/tty; continue ;;
        esac

        _ensure_backup || { echo ""; read -r _ < /dev/tty; continue; }
        if [ -z "$BAK_MOD" ]; then
          bash "$HOME/backup.sh" < /dev/tty
        else
          bash "$HOME/backup.sh" --module "$BAK_MOD" < /dev/tty
        fi
        echo ""
        read -r _ < /dev/tty
        ;;

      # ── [3] Restore completo ────────────────────────────────
      3)
        clear
        _ensure_restore || { echo ""; read -r _ < /dev/tty; continue; }
        bash "$HOME/restore.sh" --module all --source github < /dev/tty
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


# ════════════════════════════════════════════
#  DESINSTALAR MÓDULO
# ════════════════════════════════════════════
uninstall_module() {
  local module_key="$1"   # n8n | claude | ollama | expo
  local module_name="$2"

  clear
  echo ""
  echo -e "${RED}${BOLD}  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "⚠  Desinstalar ${module_name}"
  echo    "  ╠══════════════════════════════════════════╣"
  echo -e "  ║  ${NC}Esto eliminará todos los datos del módulo${RED}${BOLD}║"
  echo -e "  ║  ${NC}Esta acción NO se puede deshacer.${RED}${BOLD}       ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -n "  ¿Confirmar desinstalación? (escribe SI para confirmar): "
  read -r CONFIRM_DEL < /dev/tty
  [ "$CONFIRM_DEL" != "SI" ] && { echo -e "  ${YELLOW}Cancelado.${NC}"; echo ""; read -r _ < /dev/tty; return 0; }

  echo ""
  case "$module_key" in
    claude)
      echo -e "  ${CYAN}[INFO]${NC} Eliminando Claude Code..."
      npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
      npm cache clean --force 2>/dev/null || true
      # Borrar directorio manualmente — npm uninstall puede fallar si ya estaba roto
      NPM_ROOT_U=$(npm root -g 2>/dev/null)
      rm -rf "${NPM_ROOT_U}/@anthropic-ai" 2>/dev/null || true
      rm -f "${TERMUX_PREFIX}/bin/claude" 2>/dev/null
      rm -f "$HOME/.install_claude_checkpoint" 2>/dev/null
      grep -v "alias claude=" "$HOME/.bashrc" > "$HOME/.bashrc.tmp" 2>/dev/null && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
      grep -v "^claude_code\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Claude Code desinstalado completamente"
      ;;
    ollama)
      echo -e "  ${CYAN}[INFO]${NC} Eliminando Ollama..."
      tmux kill-session -t "ollama-server" 2>/dev/null || true
      pkg uninstall ollama -y 2>/dev/null || true
      rm -f "$HOME/ollama_start.sh" "$HOME/ollama_stop.sh" 2>/dev/null
      grep -v "^ollama\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Ollama desinstalado"
      echo -e "  ${YELLOW}⚠${NC}  Modelos en ~/.ollama no eliminados — bórralos manualmente si quieres liberar espacio"
      ;;
    n8n)
      echo -e "  ${CYAN}[INFO]${NC} Eliminando n8n + proot Debian..."
      tmux kill-session -t "n8n-server" 2>/dev/null || true
      proot-distro remove debian 2>/dev/null || true
      rm -f "$HOME/start_servidor.sh" "$HOME/stop_servidor.sh" "$HOME/ver_url.sh" 2>/dev/null
      rm -f "$HOME/n8n_status.sh" "$HOME/n8n_log.sh" "$HOME/n8n_backup.sh" 2>/dev/null
      grep -v "^n8n\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} n8n + proot Debian desinstalado"
      ;;
    expo)
      echo -e "  ${CYAN}[INFO]${NC} Eliminando Expo / EAS CLI..."
      npm uninstall -g eas-cli 2>/dev/null || true
      rm -f "${TERMUX_PREFIX}/bin/eas" 2>/dev/null
      grep -v "^expo\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      echo -e "  ${GREEN}[OK]${NC} Expo / EAS CLI desinstalado"
      ;;
    python)
      echo -e "  ${CYAN}[INFO]${NC} Eliminando Python + SQLite..."
      pkg uninstall python -y 2>/dev/null || true
      pkg uninstall sqlite -y 2>/dev/null || true
      rm -f "$HOME/.install_python_checkpoint" 2>/dev/null
      grep -v "^python\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      grep -v "py3\|pip3-install\|sqlite-n8n\|# Python · aliases" \
        "$HOME/.bashrc" > "$HOME/.bashrc.tmp" 2>/dev/null && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
      echo -e "  ${GREEN}[OK]${NC} Python + SQLite desinstalados"
      ;;
    ssh)
      echo -e "  ${CYAN}[INFO]${NC} Eliminando SSH..."
      pkill sshd 2>/dev/null || true
      pkg uninstall openssh -y 2>/dev/null || true
      rm -f "$HOME/ssh_start.sh" "$HOME/ssh_stop.sh" 2>/dev/null
      rm -f "$HOME/.install_ssh_checkpoint" 2>/dev/null
      grep -v "^ssh\." "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
      grep -v "ssh-start\|ssh-stop\|ssh-status\|ssh-info\|ssh-addkey\|# SSH · aliases" \
        "$HOME/.bashrc" > "$HOME/.bashrc.tmp" 2>/dev/null && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
      echo -e "  ${GREEN}[OK]${NC} SSH desinstalado"
      echo -e "  ${DIM}(~/.ssh/authorized_keys conservado — bórralo manualmente si quieres)${NC}"
      ;;
  esac

  echo ""
  read -r -p "  Presiona ENTER para volver al menú..." _ < /dev/tty
}

# ════════════════════════════════════════════
#  SUBMENÚ DESINSTALAR
# ════════════════════════════════════════════
submenu_desinstalar() {
  while true; do
    clear
    echo ""
    echo -e "${RED}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⚠  Desinstalar módulo                  ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] n8n + proot Debian${RED}${BOLD}                 ║"
    echo -e "  ║  ${NC}[2] Claude Code${RED}${BOLD}                        ║"
    echo -e "  ║  ${NC}[3] Ollama${RED}${BOLD}                             ║"
    echo -e "  ║  ${NC}[4] Expo / EAS CLI${RED}${BOLD}                     ║"
    echo -e "  ║  ${NC}[5] Python + SQLite${RED}${BOLD}                    ║"
    echo -e "  ║  ${NC}[6] SSH${RED}${BOLD}                                ║"
    echo -e "  ║  ${NC}[b] Cancelar${RED}${BOLD}                           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -r -p "  Módulo a desinstalar: " OPT < /dev/tty

    case "$OPT" in
      1) uninstall_module "n8n"    "n8n + proot Debian" ; break ;;
      2) uninstall_module "claude" "Claude Code"        ; break ;;
      3) uninstall_module "ollama" "Ollama"             ; break ;;
      4) uninstall_module "expo"   "Expo / EAS CLI"     ; break ;;
      5) uninstall_module "python" "Python + SQLite"    ; break ;;
      6) uninstall_module "ssh"    "SSH"                ; break ;;
      b|B|"") break ;;
      *) continue ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ SQLITE
# ════════════════════════════════════════════
submenu_sqlite() {
  while true; do
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⬡ SQLITE                                ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Listar bases de datos en ~/  ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[2] Abrir BD (modo interactivo)  ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[3] Ver tablas de una BD         ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[4] BD de n8n (acceso rápido)    ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[5] Exportar BD a CSV            ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[6] Crear nueva BD vacía         ${CYAN}${BOLD}      ║"
    echo -e "  ║  ${NC}[b] Volver a Python              ${CYAN}${BOLD}      ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in

      1)
        clear
        echo ""
        echo -e "  ${BOLD}Bases de datos en ~/  (.db / .sqlite)${NC}"
        echo ""
        DB_LIST=$(find "$HOME" -maxdepth 2 \( -name "*.db" -o -name "*.sqlite" \) 2>/dev/null)
        if [ -z "$DB_LIST" ]; then
          echo -e "  ${YELLOW}  No se encontraron bases de datos en ~/  ${NC}"
        else
          while IFS= read -r db; do
            SIZE=$(du -sh "$db" 2>/dev/null | awk '{print $1}')
            printf "  %-35s %s\n" "$(basename "$db")" "$SIZE"
            echo -e "  ${DIM}  $db${NC}"
            echo ""
          done <<< "$DB_LIST"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      2)
        clear
        echo ""
        echo -e "  ${BOLD}Abrir base de datos${NC}"
        echo ""
        echo "  Escribe la ruta del archivo:"
        echo "  Ejemplos: ~/trading.db   ~/mis_datos.sqlite"
        echo ""
        echo -n "  Ruta: "
        read -r DB_PATH < /dev/tty
        DB_PATH="${DB_PATH/#\~/$HOME}"
        if [ -z "$DB_PATH" ]; then
          echo -e "  ${YELLOW}Cancelado.${NC}"
        elif command -v sqlite3 &>/dev/null; then
          echo ""
          echo -e "  ${CYAN}Abriendo $DB_PATH${NC}"
          echo -e "  ${DIM}Comandos útiles: .tables  .schema  .quit${NC}"
          echo ""
          sqlite3 "$DB_PATH"
        else
          echo -e "  ${YELLOW}[AVISO]${NC} sqlite3 CLI no instalado — usando Python..."
          echo ""
          python3 -c "
import sqlite3, sys
try:
    conn = sqlite3.connect('$DB_PATH')
    print('  BD abierta. Escribe SQL o .quit para salir.')
    while True:
        try:
            q = input('  sqlite> ')
            if q.strip() in ('.quit','.exit','exit'):
                break
            for row in conn.execute(q):
                print(' ', row)
        except Exception as e:
            print('  Error:', e)
    conn.close()
except Exception as e:
    print('  Error:', e)
"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      3)
        clear
        echo ""
        echo -e "  ${BOLD}Ver tablas de una BD${NC}"
        echo ""
        echo -n "  Ruta de la BD: "
        read -r DB_PATH < /dev/tty
        DB_PATH="${DB_PATH/#\~/$HOME}"
        if [ -z "$DB_PATH" ]; then
          echo -e "  ${YELLOW}Cancelado.${NC}"
        elif [ ! -f "$DB_PATH" ]; then
          echo -e "  ${RED}[ERROR]${NC} Archivo no encontrado: $DB_PATH"
        else
          echo ""
          echo -e "  ${BOLD}Tablas en $(basename "$DB_PATH"):${NC}"
          echo ""
          python3 -c "
import sqlite3
conn = sqlite3.connect('$DB_PATH')
cur = conn.execute(\"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name\")
tables = cur.fetchall()
if tables:
    for t in tables:
        cur2 = conn.execute('SELECT COUNT(*) FROM \"' + t[0] + '\"')
        count = cur2.fetchone()[0]
        print(f'  {t[0]:<30} {count} filas')
else:
    print('  No hay tablas en esta BD.')
conn.close()
" 2>/dev/null || echo -e "  ${RED}[ERROR]${NC} No se pudo leer la BD"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      4)
        clear
        echo ""
        echo -e "  ${BOLD}Base de datos de n8n${NC}"
        echo ""
        if [ "$(get_reg n8n installed)" != "true" ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} n8n no está instalado."
          echo ""
          read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
          continue
        fi
        echo "  [1] Ver últimas 10 ejecuciones"
        echo "  [2] Ver workflows"
        echo "  [3] Ver todas las tablas"
        echo "  [4] Consola interactiva (n8n DB)"
        echo "  [b] Volver"
        echo ""
        read -r -p "  Opción: " N8N_OPT < /dev/tty
        N8N_DB="/root/.n8n/database.sqlite"
        case "$N8N_OPT" in
          1)
            echo ""
            echo -e "  ${BOLD}Últimas 10 ejecuciones:${NC}"
            echo ""
            proot-distro login debian -- python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$N8N_DB')
    cur = conn.execute(\"SELECT id, workflowName, status, startedAt FROM execution_entity ORDER BY startedAt DESC LIMIT 10\")
    rows = cur.fetchall()
    if rows:
        print(f'  {\"ID\":<6} {\"Workflow\":<25} {\"Estado\":<10} Inicio')
        print('  ' + '-'*60)
        for r in rows:
            print(f'  {str(r[0]):<6} {str(r[1] or \"-\"):<25} {str(r[2]):<10} {str(r[3])[:16]}')
    else:
        print('  Sin ejecuciones registradas.')
    conn.close()
except Exception as e:
    print('  Error:', e)
" 2>/dev/null || echo -e "  ${YELLOW}[AVISO]${NC} No se pudo acceder a la BD de n8n."
            ;;
          2)
            echo ""
            echo -e "  ${BOLD}Workflows:${NC}"
            echo ""
            proot-distro login debian -- python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$N8N_DB')
    cur = conn.execute('SELECT id, name, active FROM workflow_entity ORDER BY id')
    rows = cur.fetchall()
    if rows:
        for r in rows:
            estado = 'activo' if r[2] else 'inactivo'
            print(f'  [{r[0]}] {r[1]}  — {estado}')
    else:
        print('  No hay workflows.')
    conn.close()
except Exception as e:
    print('  Error:', e)
" 2>/dev/null || echo -e "  ${YELLOW}[AVISO]${NC} No se pudo acceder a la BD."
            ;;
          3)
            echo ""
            proot-distro login debian -- python3 -c "
import sqlite3
conn = sqlite3.connect('$N8N_DB')
cur = conn.execute(\"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name\")
for t in cur.fetchall():
    cur2 = conn.execute('SELECT COUNT(*) FROM \"' + t[0] + '\"')
    print(f'  {t[0]:<40} {cur2.fetchone()[0]} filas')
conn.close()
" 2>/dev/null
            ;;
          4)
            echo ""
            echo -e "  ${CYAN}Abriendo consola n8n DB — escribe .quit para volver${NC}"
            echo ""
            proot-distro login debian -- sqlite3 "$N8N_DB" 2>/dev/null || \
              echo -e "  ${RED}[ERROR]${NC} sqlite3 no disponible en proot"
            ;;
          b|B|"") ;;
        esac
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      5)
        clear
        echo ""
        echo -e "  ${BOLD}Exportar BD a CSV${NC}"
        echo ""
        echo -n "  Ruta de la BD fuente: "
        read -r DB_PATH < /dev/tty
        DB_PATH="${DB_PATH/#\~/$HOME}"
        [ -z "$DB_PATH" ] && { echo -e "  ${YELLOW}Cancelado.${NC}"; read -r _ < /dev/tty; continue; }
        [ ! -f "$DB_PATH" ] && { echo -e "  ${RED}[ERROR]${NC} Archivo no encontrado."; read -r _ < /dev/tty; continue; }
        echo ""
        echo -n "  Directorio de salida [ENTER = ~/]: "
        read -r OUT_DIR < /dev/tty
        OUT_DIR="${OUT_DIR/#\~/$HOME}"
        [ -z "$OUT_DIR" ] && OUT_DIR="$HOME"
        echo ""
        python3 << PYEOF
import sqlite3, csv, os
conn = sqlite3.connect('$DB_PATH')
cur = conn.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
tables = [t[0] for t in cur.fetchall()]
out_dir = '$OUT_DIR'
db_name = os.path.splitext(os.path.basename('$DB_PATH'))[0]
for t in tables:
    out_path = os.path.join(out_dir, f'{db_name}_{t}.csv')
    rows = conn.execute(f'SELECT * FROM "{t}"').fetchall()
    desc = conn.execute(f'SELECT * FROM "{t}" LIMIT 0').description
    cols = [d[0] for d in desc] if desc else []
    with open(out_path, 'w', newline='') as f:
        w = csv.writer(f)
        if cols: w.writerow(cols)
        w.writerows(rows)
    print(f'  ✓ {t} → {out_path}  ({len(rows)} filas)')
conn.close()
print()
print('  Exportación completada.')
PYEOF
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      6)
        clear
        echo ""
        echo -e "  ${BOLD}Crear nueva base de datos${NC}"
        echo ""
        echo "  La BD se creará en ~/"
        echo -n "  Nombre (sin extensión): "
        read -r DB_NAME < /dev/tty
        if [ -z "$DB_NAME" ]; then
          echo -e "  ${YELLOW}Cancelado.${NC}"
        else
          DB_FILE="$HOME/${DB_NAME}.db"
          python3 -c "
import sqlite3
conn = sqlite3.connect('$DB_FILE')
conn.close()
print('  ✓ Creada: $DB_FILE')
" 2>/dev/null || echo -e "  ${RED}[ERROR]${NC} No se pudo crear."
          echo ""
          echo -e "  ${DIM}Usa [2] para abrirla e ingresar datos.${NC}"
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
#  SUBMENÚ PYTHON
# ════════════════════════════════════════════
submenu_python() {
  local py_ver="$1"
  while true; do
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    printf  "  ║  %-40s║\n" "⬡ PYTHON  ● listo · v${py_ver}"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Ver versión e info             ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[2] Abrir REPL (python3)           ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[3] Instalar paquete (pip)         ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[4] Listar paquetes instalados     ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[5] SQLite → submenú               ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal       ${CYAN}${BOLD}    ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in
      1)
        clear
        echo ""
        echo -e "  ${BOLD}Python — información${NC}"
        echo ""
        echo -e "  Python:  $(python3 --version 2>/dev/null)"
        echo -e "  pip:     $(pip --version 2>/dev/null | awk '{print $1, $2}')"
        echo -e "  sqlite3: $(python3 -c 'import sqlite3; print(sqlite3.sqlite_version)' 2>/dev/null)"
        echo -e "  Ruta:    $(command -v python3 2>/dev/null)"
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      2)
        clear
        echo ""
        echo -e "  ${CYAN}REPL Python — escribe exit() para volver${NC}"
        echo ""
        python3
        ;;
      3)
        clear
        echo ""
        echo -e "  ${BOLD}Instalar paquete pip${NC}"
        echo ""
        echo -n "  Nombre del paquete: "
        read -r PKG_NAME < /dev/tty
        if [ -z "$PKG_NAME" ]; then
          echo -e "  ${YELLOW}Cancelado.${NC}"
        else
          echo ""
          echo -e "  ${CYAN}Instalando ${PKG_NAME}...${NC}"
          echo ""
          pip install "$PKG_NAME" 2>&1 | tee /tmp/pip_out.txt
          if grep -q "externally-managed-environment" /tmp/pip_out.txt 2>/dev/null; then
            echo ""
            echo -e "  ${YELLOW}[AVISO]${NC} Reintentando con --break-system-packages..."
            pip install "$PKG_NAME" --break-system-packages
          fi
          rm -f /tmp/pip_out.txt
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      4)
        clear
        echo ""
        echo -e "  ${BOLD}Paquetes Python instalados:${NC}"
        echo ""
        pip list 2>/dev/null | head -40
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;
      5)
        submenu_sqlite
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
#  SUBMENÚ SSH
# ════════════════════════════════════════════
submenu_ssh() {
  local ssh_state="$1"
  local ssh_ver="$2"
  while true; do
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    if [ "$ssh_state" = "running" ]; then
      printf  "  ║  %-40s║\n" "⬡ SSH  ● activo · :8022"
    else
      printf  "  ║  %-40s║\n" "⬡ SSH  ● listo · :8022"
    fi
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar servidor SSH           ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[2] Detener servidor SSH           ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[3] Ver IP + comando de conexión   ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[4] Agregar clave pública (PC)     ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[5] Ver conexiones activas         ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[6] Cambiar contraseña Termux      ${CYAN}${BOLD}    ║"
    echo -e "  ║  ${NC}[b] Volver al menú principal       ${CYAN}${BOLD}    ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -r -p "  Opción: " OPT < /dev/tty

    case "$OPT" in

      # ── [1] Iniciar SSH ─────────────────────────────────────
      1)
        clear
        echo ""
        if pgrep -x sshd &>/dev/null; then
          echo -e "  ${YELLOW}[AVISO]${NC} SSH ya está corriendo."
        else
          bash "$HOME/ssh_start.sh" 2>/dev/null || sshd 2>/dev/null
          sleep 1
        fi
        if pgrep -x sshd &>/dev/null; then
          ssh_state="running"
          IP=$(_get_ip)
          echo -e "  ${GREEN}[OK]${NC} SSH activo en puerto 8022"
          echo ""
          echo -e "  ${BOLD}Conectar desde PC:${NC}"
          echo -e "  ${GREEN}  ssh -p 8022 $(whoami)@${IP:-<tu_IP_WiFi>}${NC}"
          echo ""
          echo -e "  ${YELLOW}Recuerda:${NC} PC y teléfono en la misma red WiFi"
        else
          echo -e "  ${RED}[ERROR]${NC} No se pudo iniciar SSH"
          echo "  Intenta: sshd -d (modo debug)"
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      # ── [2] Detener SSH ─────────────────────────────────────
      2)
        clear
        echo ""
        bash "$HOME/ssh_stop.sh" 2>/dev/null || pkill sshd 2>/dev/null
        sleep 1
        pgrep -x sshd &>/dev/null || ssh_state="stopped"
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      # ── [3] Ver IP + comando ────────────────────────────────
      3)
        clear
        echo ""
        echo -e "  ${BOLD}Información de conexión SSH${NC}"
        echo ""
        IP=$(_get_ip)
        USER_N=$(whoami)
        SSH_STATUS=$(pgrep -x sshd &>/dev/null && echo "● ACTIVO" || echo "○ DETENIDO")

        echo -e "  Estado:   ${GREEN}${SSH_STATUS}${NC}"
        echo -e "  Puerto:   8022"
        echo -e "  Usuario:  ${USER_N}"
        echo -e "  IP WiFi:  ${IP:-no detectada}"
        echo ""
        echo -e "  ${CYAN}${BOLD}Comando de conexión:${NC}"
        echo -e "  ${GREEN}  ssh -p 8022 ${USER_N}@${IP:-<tu_IP>}${NC}"
        echo ""
        echo -e "  ${CYAN}Para VS Code Remote SSH:${NC}"
        echo "  1. Instala extensión: Remote - SSH"
        echo "  2. Ctrl+Shift+P → Remote-SSH: Connect to Host"
        echo -e "  3. Escribe: ${USER_N}@${IP:-<tu_IP>}:8022"
        echo ""
        echo -e "  ${CYAN}Para transferir archivos (scp):${NC}"
        echo "  scp -P 8022 archivo.txt ${USER_N}@${IP:-<tu_IP>}:~/"
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      # ── [4] Agregar clave pública ───────────────────────────
      4)
        clear
        echo ""
        echo -e "  ${BOLD}Agregar clave pública SSH desde PC${NC}"
        echo ""
        echo "  Esto permite conectarte sin contraseña."
        echo ""
        echo "  PASO 1 — En tu PC, ejecuta:"
        echo -e "  ${CYAN}  cat ~/.ssh/id_rsa.pub${NC}"
        echo "  (o id_ed25519.pub, id_ecdsa.pub)"
        echo ""
        echo "  Si no tienes clave SSH en el PC:"
        echo -e "  ${CYAN}  ssh-keygen -t ed25519${NC}"
        echo ""
        echo "  PASO 2 — Copia el resultado y pégalo aquí:"
        echo ""
        echo -n "  Clave pública (ssh-... o vacío para cancelar): "
        read -r PUB_KEY < /dev/tty
        if [ -z "$PUB_KEY" ]; then
          echo -e "  ${YELLOW}Cancelado.${NC}"
        elif echo "$PUB_KEY" | grep -qE "^ssh-(rsa|ed25519|ecdsa|dss) "; then
          mkdir -p "$HOME/.ssh"
          chmod 700 "$HOME/.ssh"
          echo "$PUB_KEY" >> "$HOME/.ssh/authorized_keys"
          chmod 600 "$HOME/.ssh/authorized_keys"
          echo ""
          echo -e "  ${GREEN}[OK]${NC} Clave agregada a ~/.ssh/authorized_keys"
          echo "  La próxima conexión no pedirá contraseña."
        else
          echo -e "  ${RED}[ERROR]${NC} Formato inválido. Debe empezar con ssh-rsa, ssh-ed25519, etc."
        fi
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      # ── [5] Ver conexiones activas ──────────────────────────
      5)
        clear
        echo ""
        echo -e "  ${BOLD}Conexiones SSH activas${NC}"
        echo ""
        # Mostrar procesos sshd hijo (conexiones activas, no el daemon principal)
        CONNS=$(ps aux 2>/dev/null | grep "sshd:" | grep -v grep | grep -v "sshd -D")
        if [ -z "$CONNS" ]; then
          echo -e "  ${DIM}No hay conexiones activas en este momento.${NC}"
        else
          echo "$CONNS" | while IFS= read -r line; do
            echo "  $line"
          done
        fi
        echo ""
        echo -e "  ${DIM}Daemon sshd:${NC}"
        pgrep -x sshd &>/dev/null && \
          echo -e "  ${GREEN}● corriendo${NC} (PID: $(pgrep -x sshd | head -1))" || \
          echo -e "  ${YELLOW}○ detenido${NC}"
        echo ""
        read -r -p "  Presiona ENTER para continuar..." _ < /dev/tty
        ;;

      # ── [6] Cambiar contraseña ──────────────────────────────
      6)
        clear
        echo ""
        echo -e "  ${BOLD}Contraseña de Termux${NC}"
        echo ""
        echo "  Esta contraseña es la que se usa para conectar"
        echo "  via SSH cuando no hay clave pública configurada."
        echo ""
        passwd
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
  # Claude: cachear resultado — node --version tarda ~400ms en cada llamada
  # Solo releer si: primera vez, o el usuario presionó [r], o CLI no existía
  IFS='|' read -r N8N_STATE N8N_VER N8N_EXTRA <<< "$(check_n8n)"
  if [ -z "$_CC_CACHE" ] || [ "$_CC_REFRESH" = "1" ]; then
    _CC_CACHE=$(check_claude)
    _CC_REFRESH=0
  fi
  IFS='|' read -r CC_STATE CC_VER CC_EXTRA <<< "$_CC_CACHE"
  IFS='|' read -r OL_STATE  OL_VER  OL_EXTRA  <<< "$(check_ollama)"
  IFS='|' read -r EX_STATE  EX_VER  EX_EXTRA  <<< "$(check_expo)"
  IFS='|' read -r PY_STATE  PY_VER  PY_EXTRA  <<< "$(check_python)"
  IFS='|' read -r SSH_STATE SSH_VER SSH_EXTRA <<< "$(check_ssh)"
  IFS='|' read -r DB_STATE  DB_VER  DB_EXTRA  <<< "$(check_dashboard)"

  # ── Info del sistema ──────────────────────────────────────────
  IP=$(_get_ip)

  # RAM libre
  RAM_FREE=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%.1fGB", $7/1024}')
  [ -z "$RAM_FREE" ] && RAM_FREE="--"

  # Almacenamiento libre en /data
  DISK_FREE=$(df -h /data 2>/dev/null | awk 'NR==2{print $4}')
  [ -z "$DISK_FREE" ] && DISK_FREE="--"

  # ── Header ───────────────────────────────────────────────────
  echo -e "${CYAN}${BOLD}"
  echo    "  ╔══════════════════════════════════════════╗"
  printf  "  ║  %-40s║\n" "⬡ TERMUX·AI·STACK"
  printf  "  ║  %-40s║\n" "RAM: ${RAM_FREE}  Disk: ${DISK_FREE} libre"
  printf  "  ║  %-40s║\n" "$([ -n "$IP" ] && echo "IP: $IP" || echo "Sin red")"
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

  case "$PY_STATE" in
    ready)  PY_CMD="→ submenú" ;;
    *)      PY_CMD="" ;;
  esac
  draw_module "5" "◉" "Python" "$PY_STATE" "$PY_VER" "$PY_CMD"

  case "$SSH_STATE" in
    running) SSH_CMD="→ submenú" ;;
    stopped) SSH_CMD="→ submenú" ;;
    *)       SSH_CMD="" ;;
  esac
  draw_module "6" "◎" "SSH" "$SSH_STATE" "$SSH_VER" "$SSH_CMD"

  case "$DB_STATE" in
    running) DB_CMD="→ submenú" ;;
    stopped) DB_CMD="→ submenú" ;;
    *)       DB_CMD="" ;;
  esac
  draw_module "7" "⬡" "Dashboard" "$DB_STATE" "$DB_VER" "$DB_CMD"

  # ── Separador + Backup/Restore ───────────────────────────────
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}[0]${NC} ◉ Backup / Restore"
  echo ""

  # ── Footer ────────────────────────────────────────────────────
  echo -e "  ${DIM}──────────────────────────────────────────${NC}"
  echo -e "  ${DIM}[r] refrescar  [h] ayuda  [u] actualizar  [s] shell  [d] desinstalar${NC}"
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
      elif [ "$CC_VER" = "err:reinstalar" ]; then
        clear
        echo ""
        echo -e "${YELLOW}${BOLD}  ╔══════════════════════════════════════════╗"
        echo    "  ║  ⚠  Claude Code — cli.js corrompido    ║"
        echo    "  ╠══════════════════════════════════════════╣"
        echo -e "  ║  ${NC}npm instala una versión incompatible     ${YELLOW}${BOLD}║"
        echo -e "  ║  ${NC}con Termux ARM64 (Bionic libc).          ${YELLOW}${BOLD}║"
        echo    "  ║                                          ║"
        echo -e "  ║  ${NC}✅ Solución: usa Backup/Restore          ${YELLOW}${BOLD}║"
        echo -e "  ║  ${NC}   [0] → Restore → GitHub Releases       ${YELLOW}${BOLD}║"
        echo -e "  ║  ${NC}   Selecciona módulo: Claude              ${YELLOW}${BOLD}║"
        echo    "  ║                                          ║"
        echo -e "  ║  ${NC}Esto descarga el paquete funcional       ${YELLOW}${BOLD}║"
        echo -e "  ║  ${NC}directamente desde GitHub.               ${YELLOW}${BOLD}║"
        echo -e "  ╚══════════════════════════════════════════╝${NC}"
        echo ""
        read -r -p "  Presiona ENTER para volver al menú..." _ < /dev/tty
        continue
      else
        clear
        WRAPPER="$TERMUX_PREFIX/bin/claude"
        CLI_PATH=$(find_claude_cli)

        # Asegurar que el wrapper existe (puede faltar en instalaciones previas)
        if [ ! -f "$WRAPPER" ] || [ ! -s "$WRAPPER" ]; then
          if [ -f "$CLI_PATH" ] && [ -s "$CLI_PATH" ]; then
            cat > "$WRAPPER" << WRAP
#!/data/data/com.termux/files/usr/bin/bash
exec node "${CLI_PATH}" "\$@"
WRAP
            chmod +x "$WRAPPER"
          fi
        fi

        # Intentar lanzar: wrapper primero, fallback a node directo
        if [ -f "$WRAPPER" ] && [ -s "$WRAPPER" ]; then
          "$WRAPPER"
        elif [ -f "$CLI_PATH" ] && [ -s "$CLI_PATH" ]; then
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

    # ── Python ───────────────────────────────────────────────────
    5)
      if [ "$PY_STATE" = "not_installed" ]; then
        install_module "Python" "python"
        continue
      else
        submenu_python "$PY_VER"
      fi
      ;;

    # ── SSH ──────────────────────────────────────────────────────
    6)
      if [ "$SSH_STATE" = "not_installed" ]; then
        install_module "SSH" "ssh"
        continue
      else
        submenu_ssh "$SSH_STATE" "$SSH_VER"
      fi
      ;;

    # ── Dashboard web ────────────────────────────────────────────
    7)
      if [ "$DB_STATE" = "not_installed" ]; then
        clear
        echo ""
        echo -e "  ${YELLOW}[AVISO]${NC} Dashboard no encontrado."
        echo "  Asegúrate de haber ejecutado instalar.sh."
        echo ""
        read -r -p "  Presiona ENTER para volver..." _ < /dev/tty
      else
        submenu_dashboard "$DB_STATE"
      fi
      ;;

    # ── Backup / Restore ─────────────────────────────────────────
    0)
      submenu_backup
      ;;

    d|D)
      submenu_desinstalar
      ;;

    r|R)
      _CC_REFRESH=1
      _CC_CACHE=""
      continue
      ;;

    u|U)
      clear
      echo ""
      echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
      echo    "  ║   Actualizando scripts desde GitHub...  ║"
      echo -e "  ╚══════════════════════════════════════════╝${NC}"
      echo ""

      SCRIPTS=("install_n8n.sh" "install_claude.sh" "install_ollama.sh" "install_expo.sh" "install_python.sh" "install_ssh.sh" "menu.sh" "backup.sh" "restore.sh")
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

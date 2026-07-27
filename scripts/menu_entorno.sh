#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · menu_entorno.sh
#  Submenús del módulo [8] Entorno
#
#  Tres puertas:
#    submenu_entorno() → [1] Terminal | [2] Interfaz | [3] Estado
#    submenu_terminal()   → proot-distro + udocker
#    submenu_interfaz()   → DE + X11 (primario) + VNC (opcional) + GPU
#    submenu_estado()     → resumen completo + registry
#
#  GUI: Termux:X11 es el método PRIMARIO por defecto.
#  VNC es solo secundario/opcional — no se instala por defecto.
#
#  GPU:
#    Adreno → mesa-zink (nativo) + Turnip (dentro del proot)
#    Mali   → virglrenderer-android + angle-android (nativo)
#    Panel independiente para seleccionar método GPU.
#
#  Cargado via 'source' por menu.sh — no ejecutar directamente.
#
#  VERSIÓN: 1.1.0 | Julio 2026
# ============================================================

REGISTRY="${REGISTRY:-$HOME/.android_server_registry}"
ENTORNO_SCRIPTS="$HOME/scripts/entorno"
TERMUX_PREFIX="${TERMUX_PREFIX:-${PREFIX:-/data/data/com.termux/files/usr}}"
# ROOTFS_BASE = layout legacy de proot-distro; CONTAINERS_BASE = layout moderno
# (reescritura bash→Python). Ver nota en install_n8n.sh / docs/PROOT.md — no
# confiar solo en ROOTFS_BASE, produce falsos "no instalada" (2026-07-26)
ROOTFS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/installed-rootfs"
CONTAINERS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/containers"

_proot_rootfs_path() {
  local _name="$1"
  [ -d "$CONTAINERS_BASE/$_name/rootfs" ] && { echo "$CONTAINERS_BASE/$_name/rootfs"; return 0; }
  [ -d "$ROOTFS_BASE/$_name" ] && { echo "$ROOTFS_BASE/$_name"; return 0; }
  return 1
}

_proot_rootfs_exists() {
  _proot_rootfs_path "$1" >/dev/null
}

# ════════════════════════════════════════════
#  CHECK DE ESTADO
# ════════════════════════════════════════════
check_entorno() {
  [ "$(get_reg entorno installed)" = "true" ] || { echo "not_installed||"; return; }

  local ver; ver=$(get_reg entorno version)
  [ -z "$ver" ] && ver="1.0"

  pgrep -f "termux-x11" &>/dev/null && { echo "running|${ver}|x11"; return; }
  pgrep -f "pulseaudio" &>/dev/null && { echo "running|${ver}|audio"; return; }
  pgrep -f "Xtightvnc|Xvnc" &>/dev/null && { echo "running|${ver}|vnc"; return; }

  echo "ready|${ver}|"
}

# ════════════════════════════════════════════
#  HELPERS INTERNOS
# ════════════════════════════════════════════

_detect_distros() {
  local distros=""
  # Método 1: proot-distro list (fuente primaria, formato con marca "installed")
  if command -v proot-distro &>/dev/null; then
    distros=$(proot-distro list 2>/dev/null | grep -iE "installed" | \
      awk '{print $1}' | tr '\n' ' ')
  fi
  # Método 2: proot-distro list sin filtrar por "installed" (formato alterno de versiones viejas)
  if [ -z "$distros" ] && command -v proot-distro &>/dev/null; then
    distros=$(proot-distro list 2>/dev/null | grep -v "^$" | grep -v "^\s*$" | \
      grep -v "^Supported" | grep -v "^---" | grep -v "proot-distro" | \
      awk '{print $1}' | tr '\n' ' ')
  fi
  # Método 3: fallback directo al directorio de rootfs (si proot-distro no reporta nada)
  # — escanea ambos layouts, moderno primero
  if [ -z "$distros" ]; then
    [ -d "$CONTAINERS_BASE" ] && distros=$(ls -1 "$CONTAINERS_BASE/" 2>/dev/null | tr '\n' ' ')
    [ -z "$distros" ] && [ -d "$ROOTFS_BASE" ] && distros=$(ls -1 "$ROOTFS_BASE/" 2>/dev/null | tr '\n' ' ')
  fi
  # Verificación cruzada: descartar nombres cuyo rootfs no existe en NINGÚN
  # layout (entradas obsoletas de proot-distro tras un borrado manual) —
  # antes solo miraba ROOTFS_BASE (legacy) y descartaba distros instaladas
  # de verdad bajo el layout moderno (containers/<n>/rootfs)
  if [ -n "$distros" ]; then
    local verified="" d
    for d in $distros; do
      _proot_rootfs_exists "$d" && verified="${verified}${d} "
    done
    distros="$verified"
  fi
  echo "${distros:-ninguna}"
}

_detect_de_installed() {
  local des=""
  command -v startxfce4 &>/dev/null && des="${des}xfce4 "
  command -v startlxqt  &>/dev/null && des="${des}lxqt "
  command -v mate-session &>/dev/null && des="${des}mate "
  command -v startplasma-x11 &>/dev/null && des="${des}plasma "
  echo "${des:-ninguno}"
}

# ── Mapeo DE → comando de arranque / nombre visible ──────────
_de_exec_cmd() {
  case "$1" in
    xfce4)  echo "startxfce4" ;;
    lxqt)   echo "startlxqt" ;;
    mate)   echo "mate-session" ;;
    plasma) echo "startplasma-x11" ;;
  esac
}

_de_label_name() {
  case "$1" in
    xfce4)  echo "XFCE4" ;;
    lxqt)   echo "LXQt" ;;
    mate)   echo "MATE" ;;
    plasma) echo "KDE Plasma" ;;
    *)      echo "$1" ;;
  esac
}

_gpu_info() {
  local gpu; gpu=$(get_reg entorno.gpu 2>/dev/null)
  [ -z "$gpu" ] && gpu="no detectada"
  echo "$gpu"
}

_gpu_method_info() {
  local method; method=$(get_reg entorno.gpu_method 2>/dev/null)
  echo "${method:-auto}"
}

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

# ════════════════════════════════════════════
#  SUBMENÚ PRINCIPAL — PUERTA DE ENTRADA
# ════════════════════════════════════════════
submenu_entorno() {
  local _EN_STATE="${1:-ready}"

  while true; do
    clear; echo ""

    local _DISTROS _DE _GPU
    _DISTROS=$(_detect_distros)
    _DE=$(_detect_de_installed)
    _GPU=$(_gpu_info)

    local _PILL
    case "$_EN_STATE" in
      running) _PILL="${GREEN}● activo   ${NC}" ;;
      ready)   _PILL="${GREEN}● listo    ${NC}" ;;
      *)       _PILL="${GREEN}● listo    ${NC}" ;;
    esac

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⏣ ENTORNO [beta] — Contenedores + Desktop    ║"
    printf "  ║  ${NC}Estado: %b                         ${CYAN}${BOLD}║\n" "$_PILL"
    printf "  ║  ${NC}GPU: %-36s${CYAN}${BOLD}║\n" "$_GPU"
    printf "  ║  ${NC}Distros: %-33s${CYAN}${BOLD}║\n" "${_DISTROS:0:33}"
    printf "  ║  ${NC}DE: %-37s${CYAN}${BOLD}║\n" "${_DE:-ninguno}"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Terminal — proot-distro + udocker  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Interfaz — escritorio + X11 + GPU  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Estado — resumen + diagnóstico     ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[r] Refrescar estado                   ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver al menú principal           ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1) submenu_terminal ;;
      2) submenu_interfaz ;;
      3) submenu_estado ;;
      r|R) continue ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ [1] — TERMINAL (proot-distro + udocker)
# ════════════════════════════════════════════
submenu_terminal() {
  while true; do
    clear; echo ""
    local _DISTROS; _DISTROS=$(_detect_distros)
    local _UDOCKER
    command -v udocker &>/dev/null && _UDOCKER="${GREEN}instalado${NC}" || _UDOCKER="${YELLOW}no instalado${NC}"

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  [1] TERMINAL — Contenedores Linux      ║"
    printf "  ║  ${NC}Distros instaladas: %-22s${CYAN}${BOLD}║\n" "${_DISTROS:0:22}"
    printf "  ║  ${NC}udocker: %-33b${CYAN}${BOLD}║\n" "$_UDOCKER"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}── proot-distro ───────────────────────${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[1] Instalar distro (debian/ubuntu/...)${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Login a distro                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Listar distros instaladas         ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Eliminar distro                   ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5] Backup distro (tar.gz)            ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}── udocker ─────────────────────────────${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6] Setup udocker (primera vez)        ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[7] Ejecutar contenedor                ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[8] Listar contenedores                ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[b] Volver al menú Entorno            ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        # Solo debian/ubuntu están confirmadas en ARM64 (ver docs/BUGS_PERSISTENTES_2026-07-26.md
        # — fedora/archlinux no tienen confirmación de funcionar, y un proyecto de referencia
        # más maduro en el mismo dominio (PocketDesk) encontró que kali falla en ARM64 y redujo
        # su propia lista soportada a solo ubuntu+debian tras probarlo en dispositivos reales)
        local _ENTORNO_DISTROS=(ubuntu debian)
        echo -e "${CYAN}${BOLD}  Distros disponibles (confirmadas en ARM64):${NC}"
        echo ""
        local _di=1 _dname
        for _dname in "${_ENTORNO_DISTROS[@]}"; do
          if _proot_rootfs_exists "$_dname"; then
            echo -e "  ${BOLD}[$_di]${NC} $_dname ${DIM}(ya instalada)${NC}"
          else
            echo -e "  ${BOLD}[$_di]${NC} $_dname"
          fi
          _di=$((_di + 1))
        done
        echo -e "  ${BOLD}[b]${NC} Cancelar"
        echo ""; echo -n "  Opción: "
        read -r _DIST_OPT < /dev/tty
        case "$_DIST_OPT" in b|B|"") continue ;; esac
        if ! [[ "$_DIST_OPT" =~ ^[0-9]+$ ]] || [ "$_DIST_OPT" -lt 1 ] || [ "$_DIST_OPT" -gt "${#_ENTORNO_DISTROS[@]}" ]; then
          echo -e "  ${YELLOW}Opción inválida${NC}"
          echo ""; read -r _ < /dev/tty; continue
        fi
        DISTRO="${_ENTORNO_DISTROS[$((_DIST_OPT - 1))]}"
        echo ""
        _EXISTING_RB=$(_proot_rootfs_path "$DISTRO")
        if [ -n "$_EXISTING_RB" ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} $DISTRO ya está instalada en $_EXISTING_RB"
          echo -n "  ¿Reinstalar desde cero? (s/n): "
          read -r _REINSTALL < /dev/tty
          if [ "$_REINSTALL" = "s" ] || [ "$_REINSTALL" = "S" ]; then
            proot-distro install "$DISTRO" --override 2>&1 | tail -5
          else
            echo -e "  ${DIM}Nada que hacer — usa [2] Login para entrar${NC}"
          fi
        else
          proot-distro install "$DISTRO" 2>&1 | tail -5
        fi
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        local _DLIST; _DLIST=$(_detect_distros)
        if [ "$_DLIST" = "ninguna" ]; then
          echo -e "  ${YELLOW}No hay distros instaladas. Usa [1] para instalar una.${NC}"
          echo ""; read -r _ < /dev/tty; continue
        fi
        echo -e "  ${CYAN}Distros disponibles:${NC} $_DLIST"
        echo -n "  Nombre de la distro: "
        read -r DISTRO < /dev/tty
        [ -z "$DISTRO" ] && continue
        echo ""
        echo -e "  ${DIM}Escribe 'exit' para volver al menú${NC}"
        echo ""
        proot-distro login "$DISTRO" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        echo -e "  ${CYAN}Distros instaladas:${NC}"
        if command -v proot-distro &>/dev/null; then
          proot-distro list 2>/dev/null || echo "    (ninguna)"
        else
          echo "    proot-distro no instalado"
        fi
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        local _DLIST2; _DLIST2=$(_detect_distros)
        [ "$_DLIST2" = "ninguna" ] && {
          echo -e "  ${YELLOW}No hay distros para eliminar${NC}"
          echo ""; read -r _ < /dev/tty; continue
        }
        echo -e "  ${CYAN}Distros instaladas:${NC} $_DLIST2"
        echo -n "  Nombre de la distro a eliminar: "
        read -r DISTRO < /dev/tty
        [ -z "$DISTRO" ] && continue
        echo ""
        echo -e "  ${RED}¿Eliminar $DISTRO?${NC}"
        echo -n "  Escribe 'SI' para confirmar: "
        read -r CONFIRM < /dev/tty
        [ "$CONFIRM" != "SI" ] && continue
        proot-distro remove "$DISTRO" 2>&1 | tail -3
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        local _DLIST3; _DLIST3=$(_detect_distros)
        [ "$_DLIST3" = "ninguna" ] && {
          echo -e "  ${YELLOW}No hay distros para respaldar${NC}"
          echo ""; read -r _ < /dev/tty; continue
        }
        echo -e "  ${CYAN}Distros instaladas:${NC} $_DLIST3"
        echo -n "  Nombre de la distro: "
        read -r DISTRO < /dev/tty
        [ -z "$DISTRO" ] && continue
        local BACKUP_PATH="$HOME/${DISTRO}_backup_$(date +%Y%m%d).tar.gz"
        echo ""
        echo -e "  ${CYAN}Comprimiendo $DISTRO...${NC}"
        if [ -d "$CONTAINERS_BASE/$DISTRO" ]; then
          # Layout moderno: respalda el contenedor completo (rootfs + manifest.json)
          tar -czf "$BACKUP_PATH" -C "$CONTAINERS_BASE" "$DISTRO" 2>&1 | tail -1
          echo -e "  ${GREEN}[OK]${NC} Backup: $BACKUP_PATH"
        elif [ -d "$ROOTFS_BASE/$DISTRO" ]; then
          tar -czf "$BACKUP_PATH" -C "$ROOTFS_BASE" "$DISTRO" 2>&1 | tail -1
          echo -e "  ${GREEN}[OK]${NC} Backup: $BACKUP_PATH"
        else
          echo -e "  ${RED}[ERROR]${NC} No se encontró $DISTRO en ningún layout de proot-distro"
        fi
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        if command -v udocker &>/dev/null; then
          echo -e "  ${CYAN}Ejecutando udocker setup...${NC}"
          udocker setup 2>&1 | tail -5
          echo ""; read -r _ < /dev/tty
        else
          echo -e "  ${YELLOW}udocker no está instalado.${NC}"
          echo -e "  ${DIM}Ejecuta install_entorno.sh o instala manualmente:${NC}"
          echo -e "  ${DIM}  curl -fsSL https://raw.githubusercontent.com/indigo-dc/udocker/main/udocker.py -o \$PREFIX/bin/udocker && chmod +x \$PREFIX/bin/udocker${NC}"
          echo ""; read -r _ < /dev/tty
        fi ;;
      7)
        clear; echo ""
        if ! command -v udocker &>/dev/null; then
          echo -e "  ${YELLOW}udocker no instalado — usa opción [6] primero${NC}"
          echo ""; read -r _ < /dev/tty; continue
        fi
        echo -e "  ${CYAN}udocker run${NC}"
        echo -e "  ${DIM}Ejemplo: ubuntu:22.04, n8nio/n8n, python:3.11${NC}"
        echo -n "  Imagen: "
        read -r IMG < /dev/tty
        [ -z "$IMG" ] && continue
        echo -e "  ${DIM}Escribe 'exit' para salir del contenedor${NC}"
        echo ""
        udocker run --proot "$IMG" < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      8)
        clear; echo ""
        if command -v udocker &>/dev/null; then
          udocker ps 2>/dev/null || echo "    (ninguno)"
          echo ""
          udocker images 2>/dev/null || echo "    (ninguna imagen)"
        else
          echo -e "  ${YELLOW}udocker no instalado${NC}"
        fi
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ [2] — INTERFAZ
#  GUI:  Termux:X11 (primario, recomendado)
#        VNC (secundario, opcional)
#  GPU:  multi-método según hardware
# ════════════════════════════════════════════
submenu_interfaz() {
  while true; do
    clear; echo ""

    local _DE _X11 _VNC _PULSE _GPU _GPU_MET
    _DE=$(_detect_de_installed)
    _GPU=$(_gpu_info)
    _GPU_MET=$(_gpu_method_info)
    pgrep -f "termux-x11" &>/dev/null && _X11="${GREEN}activo${NC}" || _X11="${YELLOW}detenido${NC}"
pgrep -f "Xtightvnc|Xvnc" &>/dev/null && _VNC="${GREEN}activo${NC}" || _VNC="${YELLOW}detenido${NC}"
pgrep -f "pulseaudio" &>/dev/null && _PULSE="${GREEN}activo${NC}" || _PULSE="${YELLOW}detenido${NC}"

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  [2] INTERFAZ — Escritorio + Display    ║"
    printf "  ║  ${NC}DE instalados: %-27s${CYAN}${BOLD}║\n" "${_DE:0:27}"
    printf "  ║  ${NC}GPU: %-15s  Método: %-10s${CYAN}${BOLD}║\n" "$_GPU" "$_GPU_MET"
    echo    "  ╠══════════════════════════════════════════╣"
    echo    "  ║  ── Escritorio ──────────────────────────║"
    echo -e "  ║  ${NC}[1]  Instalar DE (XFCE4 / LXQt / MATE)${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${BOLD}Termux:X11 — GUI PRIMARIA${NC}               ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2]  Iniciar X11 + escritorio             ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3]  Detener X11                          ${CYAN}${BOLD}║"
    printf "  ║  ${NC}       X11: %-34b${CYAN}${BOLD}║\n" "$_X11"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${BOLD}VNC — Secundario / Opcional${NC}            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4]  Instalar TigerVNC                      ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5]  Iniciar VNC (:5901)                   ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6]  Detener VNC                            ${CYAN}${BOLD}║"
    printf "  ║  ${NC}       VNC: %-34b${CYAN}${BOLD}║\n" "$_VNC"
    echo    "  ╠══════════════════════════════════════════╣"
    echo    "  ║  ── Audio + App Bridge ──────────────────║"
    echo -e "  ║  ${NC}[7]  PulseAudio: toggle                     ${CYAN}${BOLD}║"
    printf "  ║  ${NC}       Pulse: %-32b${CYAN}${BOLD}║\n" "$_PULSE"
    echo -e "  ║  ${NC}[8]  App Bridge — montar binds proot        ${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo    "  ║  ── GPU ─────────────────────────────────║"
    echo -e "  ║  ${NC}[9]  Diagnóstico GPU                        ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[0]  Configurar método GPU (Turnip/Zink/...)${CYAN}${BOLD}║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[b] Volver al menú Entorno                 ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
        echo    "  ║  Instalar Entorno de Escritorio          ║"
        echo    "  ╠══════════════════════════════════════════╣"
        echo -e "  ║  ${NC}[1] XFCE4 (ligero, recomendado)          ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[2] LXQt  (ultraligero)                  ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[3] MATE (clásico GNOME2)                ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[4] KDE Plasma (pesado)                  ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[b] Cancelar                              ${CYAN}${BOLD}║"
        echo -e "  ╚══════════════════════════════════════════╝${NC}"
        echo ""; echo -n "  Elige DE: "
        read -r DE_OPT < /dev/tty
        case "$DE_OPT" in
          1)
            echo ""
            if command -v startxfce4 &>/dev/null; then
              echo -e "  ${GREEN}[OK]${NC} XFCE4 ya instalado"
            else
              pkg install -y xfce4 xfce4-terminal 2>&1 | tail -3
              echo ""; echo -e "  ${GREEN}[OK]${NC} XFCE4 instalado"
            fi
            echo -e "  ${DIM}Usa [2] Iniciar X11 + escritorio para arrancarlo${NC}" ;;
          2)
            echo ""
            if command -v startlxqt &>/dev/null; then
              echo -e "  ${GREEN}[OK]${NC} LXQt ya instalado"
            else
              pkg install -y lxqt 2>&1 | tail -3
              echo ""; echo -e "  ${GREEN}[OK]${NC} LXQt instalado"
            fi
            echo -e "  ${DIM}Usa [2] Iniciar X11 + escritorio para arrancarlo${NC}" ;;
          3)
            echo ""
            if [ -f "$TERMUX_PREFIX/bin/mate-session" ]; then
              echo -e "  ${GREEN}[OK]${NC} MATE ya instalado"
            else
              pkg install -y mate mate-terminal 2>&1 | tail -3
              echo ""; echo -e "  ${GREEN}[OK]${NC} MATE instalado"
            fi
            echo -e "  ${DIM}Usa [2] Iniciar X11 + escritorio para arrancarlo${NC}" ;;
          4)
            echo ""
            if command -v startplasma-x11 &>/dev/null; then
              echo -e "  ${GREEN}[OK]${NC} KDE Plasma ya instalado"
            else
              pkg install -y plasma 2>&1 | tail -3
              echo ""; echo -e "  ${GREEN}[OK]${NC} KDE Plasma instalado"
            fi
            echo -e "  ${DIM}Usa [2] Iniciar X11 + escritorio para arrancarlo${NC}" ;;
          b|B|"") continue ;;
        esac
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        # Cargar variables GPU antes de iniciar X11
        [ -f "$ENTORNO_SCRIPTS/gpu_env.sh" ] && source "$ENTORNO_SCRIPTS/gpu_env.sh"
        # Iniciar X11 (primario)
        if [ -f "$ENTORNO_SCRIPTS/tx11_start.sh" ]; then
          bash "$ENTORNO_SCRIPTS/tx11_start.sh"
        else
          # Fallback directo si no existen scripts de gestión
          pkill termux-x11 2>/dev/null; sleep 1
          am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null || true
          termux-x11 :0 -xres 1920x1080 &
          sleep 2
          echo -e "  ${GREEN}[OK]${NC} Termux:X11 iniciado en :0"
        fi
        echo ""
        # Elegir/lanzar el escritorio realmente instalado — antes esto asumía
        # siempre XFCE4, sin importar qué DE(s) el usuario instaló de verdad
        local _DE_INSTALLED_STR; _DE_INSTALLED_STR=$(_detect_de_installed)
        local _DE_ARR=($_DE_INSTALLED_STR)
        if [ "${#_DE_ARR[@]}" -eq 0 ] || [ "${_DE_ARR[0]}" = "ninguno" ]; then
          echo -e "  ${YELLOW}No hay ningún escritorio instalado.${NC}"
          echo -e "  ${DIM}Usa [1] Instalar DE primero.${NC}"
        elif [ "${#_DE_ARR[@]}" -eq 1 ]; then
          local _DE_ONLY="${_DE_ARR[0]}"
          echo -e "  ${CYAN}¿Iniciar $(_de_label_name "$_DE_ONLY") ahora? [s/N]:${NC} "
          read -r START_DE < /dev/tty
          case "$START_DE" in
            s|S|y|Y)
              export DISPLAY=:0
              $(_de_exec_cmd "$_DE_ONLY") &>/dev/null &
              echo -e "  ${GREEN}[OK]${NC} $(_de_label_name "$_DE_ONLY") iniciado en :0" ;;
          esac
        else
          echo -e "  ${CYAN}${BOLD}Escritorios instalados:${NC}"
          local _dei=1 _dename
          for _dename in "${_DE_ARR[@]}"; do
            echo -e "  ${BOLD}[$_dei]${NC} $(_de_label_name "$_dename")"
            _dei=$((_dei + 1))
          done
          echo -e "  ${BOLD}[b]${NC} Cancelar"
          echo ""; echo -n "  ¿Cuál iniciar?: "
          read -r _DE_OPT < /dev/tty
          if [[ "$_DE_OPT" =~ ^[0-9]+$ ]] && [ "$_DE_OPT" -ge 1 ] && [ "$_DE_OPT" -le "${#_DE_ARR[@]}" ]; then
            local _DE_CHOSEN="${_DE_ARR[$((_DE_OPT - 1))]}"
            export DISPLAY=:0
            $(_de_exec_cmd "$_DE_CHOSEN") &>/dev/null &
            echo -e "  ${GREEN}[OK]${NC} $(_de_label_name "$_DE_CHOSEN") iniciado en :0"
          fi
        fi
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        if [ -f "$ENTORNO_SCRIPTS/tx11_stop.sh" ]; then
          bash "$ENTORNO_SCRIPTS/tx11_stop.sh"
        else
          pkill termux-x11 2>/dev/null
          echo -e "  ${GREEN}[OK]${NC} Termux:X11 detenido"
        fi
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        if command -v tigervncserver &>/dev/null; then
          echo -e "  ${GREEN}[OK]${NC} TigerVNC ya instalado"
        else
          echo -e "  ${YELLOW}NOTA:${NC} VNC es opcional. La GUI primaria es Termux:X11."
          echo ""
          pkg install -y tigervnc 2>&1 | tail -3
          echo -e "  ${GREEN}[OK]${NC} TigerVNC instalado"
          echo ""
          echo -e "  ${CYAN}Establece una contraseña VNC (opcional):${NC}"
          vncpasswd < /dev/tty 2>/dev/null || true
        fi
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        if [ -f "$ENTORNO_SCRIPTS/vnc_start.sh" ]; then
          bash "$ENTORNO_SCRIPTS/vnc_start.sh"
        else
          export DISPLAY=:1
          vncserver :1 -geometry 1920x1080 -depth 24 -localhost 2>/dev/null || \
            tigervncserver :1 -geometry 1920x1080 -depth 24 -localhost 2>/dev/null
          echo ""
          echo -e "  ${GREEN}[OK]${NC} VNC en :5901"
        fi
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        if [ -f "$ENTORNO_SCRIPTS/vnc_stop.sh" ]; then
          bash "$ENTORNO_SCRIPTS/vnc_stop.sh"
        else
          vncserver -kill :1 2>/dev/null || tigervncserver -kill :1 2>/dev/null || true
          echo -e "  ${GREEN}[OK]${NC} VNC detenido"
        fi
        echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        if pgrep -f "pulseaudio" &>/dev/null; then
          echo -e "  ${CYAN}PulseAudio está activo. ¿Detenerlo? [s/N]:${NC} "
          read -r PA_OPT < /dev/tty
          case "$PA_OPT" in
            s|S|y|Y)
              if [ -f "$ENTORNO_SCRIPTS/pulse_stop.sh" ]; then
                bash "$ENTORNO_SCRIPTS/pulse_stop.sh"
              else
                pkill pulseaudio 2>/dev/null
                echo -e "  ${GREEN}[OK]${NC} PulseAudio detenido"
              fi ;;
          esac
        else
          echo -e "  ${CYAN}Iniciando PulseAudio...${NC}"
          if [ -f "$ENTORNO_SCRIPTS/pulse_start.sh" ]; then
            bash "$ENTORNO_SCRIPTS/pulse_start.sh"
          else
            pulseaudio --start --exit-idle-time=-1 2>/dev/null
            echo -e "  ${GREEN}[OK]${NC} PulseAudio iniciado"
          fi
        fi
        echo ""; read -r _ < /dev/tty ;;
      8)
        clear; echo ""
        echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
        echo    "  ║  App Bridge — Montar binds proot       ║"
        echo    "  ╠══════════════════════════════════════════╣"
        echo -e "  ║  ${NC}Comparte archivos entre Termux nativo   ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}y el proot mediante enlaces simbólicos  ${CYAN}${BOLD}║"
        echo    "  ╠══════════════════════════════════════════╣"
        echo -e "  ║  ${NC}[1] Montar registry compartido           ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[2] Montar ~/scripts/ en proot          ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[3] Montar ~/proyectos/ en proot        ${CYAN}${BOLD}║"
        echo -e "  ║  ${NC}[b] Volver                                ${CYAN}${BOLD}║"
        echo -e "  ╚══════════════════════════════════════════╝${NC}"
        echo ""; echo -n "  Opción: "
        read -r AB_OPT < /dev/tty
        case "$AB_OPT" in
          1)
            echo ""
            local _DISTROS; _DISTROS=$(_detect_distros)
            [ "$_DISTROS" = "ninguna" ] && {
              echo -e "  ${YELLOW}Primero instala una distro (Menú Terminal → [1])${NC}"
              echo ""; read -r _ < /dev/tty; continue
            }
            local _PD; _PD=$(echo "$_DISTROS" | awk '{print $1}')
            local _RB; _RB=$(_proot_rootfs_path "$_PD")
            if [ -n "$_RB" ]; then
              mkdir -p "$_RB/tmp/registry" 2>/dev/null
              local _BRIDGE="$_RB/tmp/bridge_entorno.sh"
              cat > "$_BRIDGE" << BRIDGEEOF
#!/bin/bash
ln -sf /data/data/com.termux/files/home/.android_server_registry /tmp/registry/ 2>/dev/null
echo "Registry compartido montado en $_PD:/tmp/registry/"
BRIDGEEOF
              chmod +x "$_BRIDGE"
              echo -e "  ${GREEN}[OK]${NC} Script bridge creado en $_BRIDGE"
              echo -e "  ${DIM}Ejecuta dentro del proot: bash /tmp/bridge_entorno.sh${NC}"
            fi ;;
          2)
            echo ""
            local _DISTROS2; _DISTROS2=$(_detect_distros)
            [ "$_DISTROS2" = "ninguna" ] && {
              echo -e "  ${YELLOW}Primero instala una distro${NC}"
              echo ""; read -r _ < /dev/tty; continue
            }
            local _PD2; _PD2=$(echo "$_DISTROS2" | awk '{print $1}')
            local _RB2; _RB2=$(_proot_rootfs_path "$_PD2")
            mkdir -p "$_RB2/home/builder/scripts" 2>/dev/null
            echo -e "  ${GREEN}[OK]${NC} ~/scripts/ bindeado en $_PD2:/home/builder/scripts/"
            echo -e "  ${DIM}Para acceso real, inicia proot con: -b ~/scripts/:/home/builder/scripts/${NC}" ;;
          3)
            echo ""
            local _DISTROS3; _DISTROS3=$(_detect_distros)
            [ "$_DISTROS3" = "ninguna" ] && {
              echo -e "  ${YELLOW}Primero instala una distro${NC}"
              echo ""; read -r _ < /dev/tty; continue
            }
            local _PD3; _PD3=$(echo "$_DISTROS3" | awk '{print $1}')
            local _RB3; _RB3=$(_proot_rootfs_path "$_PD3")
            mkdir -p "$_RB3/home/builder/proyectos" 2>/dev/null
            echo -e "  ${GREEN}[OK]${NC} ~/proyectos/ bindeado en $_PD3:/home/builder/proyectos/"
            echo -e "  ${DIM}Para acceso real: proot-distro login $_PD3 -- -b ~/proyectos/:/home/builder/proyectos/${NC}" ;;
          b|B|"") continue ;;
        esac
        echo ""; read -r _ < /dev/tty ;;
      9)
        clear; echo ""
        echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
        echo    "  ║  Diagnóstico GPU                       ║"
        echo    "  ╠══════════════════════════════════════════╣"
        local _GPU_DETECTED; _GPU_DETECTED=$(_gpu_info)
        local _GPU_MET; _GPU_MET=$(_gpu_method_info)
        printf "  ║  ${NC}GPU detectada: %-26s${CYAN}${BOLD}║\n" "$_GPU_DETECTED"
        printf "  ║  ${NC}Método: %-33s${CYAN}${BOLD}║\n" "$_GPU_MET"
        echo    "  ╠══════════════════════════════════════════╣"
        echo -e "  ║  ${NC}Renderizadores disponibles:             ${CYAN}${BOLD}║"
        if command -v glxinfo &>/dev/null; then
          local _RENDERER
          _RENDERER=$(glxinfo -B 2>/dev/null | grep "OpenGL renderer" | head -1)
          printf "  ║  ${NC}  %-36s${CYAN}${BOLD}║\n" "${_RENDERER:-no detectado}"
        else
          echo -e "  ║  ${DIM}  glxinfo no instalado — usa pkgs mesa-utils${CYAN}${BOLD}║"
        fi
        # Detectar Vulkan
        if command -v vulkaninfo &>/dev/null; then
          local _VULKAN
          _VULKAN=$(vulkaninfo --summary 2>/dev/null | grep "deviceName" | head -1)
          printf "  ║  ${NC}  Vulkan: %-33s${CYAN}${BOLD}║\n" "${_VULKAN##*: }"
        fi
        echo    "  ╠══════════════════════════════════════════╣"
        echo -e "  ║  ${NC}Drivers Termux instalados:               ${CYAN}${BOLD}║"
        local _MESA; _MESA=$(pkg list-installed 2>/dev/null | grep -E "mesa|vulkan|virgl|angle|turnip|panfrost" | awk '{print $1}' | tr '\n' ' ')
        printf "  ║  ${NC}  %-36s${CYAN}${BOLD}║\n" "${_MESA:-ninguno}"
        echo -e "  ╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${DIM}GPU nativo: usa Zink (OpenGL → Vulkan) para Adreno${NC}"
        echo -e "  ${DIM}o VirGL+ANGLE para Mali.${NC}"
        echo -e "  ${DIM}Dentro del proot: Turnip (Adreno) o Panfrost (Mali) disponible.${NC}"
        echo ""; read -r _ < /dev/tty ;;
      0)
        clear; echo ""
        local _GPU_TYPE; _GPU_TYPE=$(_check_gpu)
        local _GPU_CUR; _GPU_CUR=$(_gpu_method_info)
        echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
        echo    "  ║  Configurar método GPU                ║"
        echo    "  ╠══════════════════════════════════════════╣"
        printf "  ║  ${NC}GPU detectada: %-26s${CYAN}${BOLD}║\n" "$_GPU_TYPE"
        printf "  ║  ${NC}Método actual: %-27s${CYAN}${BOLD}║\n" "$_GPU_CUR"
        echo    "  ╠══════════════════════════════════════════╣"
        echo -e "  ║  ${NC}[1] Auto (recomendado)                    ${CYAN}${BOLD}║"
        case "$_GPU_TYPE" in
          adreno)
            echo -e "  ║  ${NC}[2] Zink nativo — OpenGL sobre Vulkan     ${CYAN}${BOLD}║"
            echo -e "  ║  ${NC}[3] Turnip + Zink — Vulkan + GL en proot  ${CYAN}${BOLD}║"
            ;;
          mali)
            echo -e "  ║  ${NC}[2] VirGL + ANGLE — OpenGL virtual        ${CYAN}${BOLD}║"
            echo -e "  ║  ${NC}[3] Panfrost — driver nativo Mali (exp.)  ${CYAN}${BOLD}║"
            ;;
          *)
            echo -e "  ║  ${NC}[2] llvmpipe — software (fallback)        ${CYAN}${BOLD}║"
            echo -e "  ║  ${NC}[3] VirGL — render virtual (experimental) ${CYAN}${BOLD}║"
            ;;
        esac
        echo -e "  ║  ${NC}[b] Volver                                ${CYAN}${BOLD}║"
        echo -e "  ╚══════════════════════════════════════════╝${NC}"
        echo ""; echo -n "  Elige método: "
        read -r GPU_OPT < /dev/tty
        local _NEW_METHOD=""
        case "$GPU_OPT" in
          1) _NEW_METHOD="auto" ;;
          2)
            case "$_GPU_TYPE" in
              adreno) _NEW_METHOD="zink" ;;
              mali)   _NEW_METHOD="virgl_angle" ;;
              *)      _NEW_METHOD="llvmpipe" ;;
            esac ;;
          3)
            case "$_GPU_TYPE" in
              adreno) _NEW_METHOD="turnip" ;;
              mali)   _NEW_METHOD="panfrost" ;;
              *)      _NEW_METHOD="virgl" ;;
            esac ;;
          b|B|"") continue ;;
        esac
        if [ -n "$_NEW_METHOD" ]; then
          # Actualizar registry
          grep -v "^entorno\.gpu_method=" "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null || touch "$REGISTRY.tmp"
          echo "entorno.gpu_method=$_NEW_METHOD" >> "$REGISTRY.tmp"
          mv "$REGISTRY.tmp" "$REGISTRY"
          case "$_NEW_METHOD" in
            zink)       pkg install -y mesa-zink vulkan-loader-generic 2>/dev/null || true ;;
            virgl_angle) pkg install -y mesa virglrenderer-android angle-android 2>/dev/null || true ;;
            turnip)     pkg install -y mesa-zink vulkan-loader-generic 2>/dev/null || true
                        echo -e "  ${DIM}Turnip se descarga dentro del proot — usa setup en distro${NC}" ;;
            panfrost)   pkg install -y mesa-panfrost 2>/dev/null || true ;;
            llvmpipe)   pkg install -y mesa 2>/dev/null || true ;;
            virgl)      pkg install -y mesa virglrenderer-android 2>/dev/null || true ;;
          esac
          echo -e "  ${GREEN}[OK]${NC} Método GPU cambiado a: $_NEW_METHOD"
          echo -e "  ${DIM}Reinicia Termux:X11 para aplicar cambios${NC}"
        fi
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ [3] — ESTADO (resumen + diagnóstico)
# ════════════════════════════════════════════
submenu_estado() {
  while true; do
    clear; echo ""

    local _VER; _VER=$(get_reg entorno version)
    [ -z "$_VER" ] && _VER="1.0"
    local _DATE; _DATE=$(get_reg entorno install_date)
    [ -z "$_DATE" ] && _DATE="desconocida"
    local _GPU; _GPU=$(_gpu_info)
    local _GPU_MET; _GPU_MET=$(_gpu_method_info)
    local _DISTROS; _DISTROS=$(_detect_distros)
    local _DE; _DE=$(_detect_de_installed)
    [ -z "$_DE" ] && _DE="ninguno"

    local _U_VER="—"
    command -v udocker &>/dev/null && _U_VER=$(udocker version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$_U_VER" ] && _U_VER="instalado"

    local _XDG
    pgrep -f "termux-x11" &>/dev/null && _XDG="${GREEN}activo${NC}" || _XDG="${DIM}detenido${NC}"
    local _VNC
    pgrep -f "Xtightvnc|Xvnc" &>/dev/null && _VNC="${GREEN}activo${NC}" || _VNC="${YELLOW}detenido${NC}"
    local _PA
    pgrep -f "pulseaudio" &>/dev/null && _PA="${GREEN}activo${NC}" || _PA="${YELLOW}detenido${NC}"

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  [3] ESTADO — Resumen del módulo        ║"
    echo    "  ╠══════════════════════════════════════════╣"
    printf "  ║  ${NC}Versión: %-33s${CYAN}${BOLD}║\n" "entorno ${_VER}"
    printf "  ║  ${NC}Instalado: %-31s${CYAN}${BOLD}║\n" "$_DATE"
    echo    "  ╠══════════════════════════════════════════╣"
    printf "  ║  ${NC}GPU:      %-34s${CYAN}${BOLD}║\n" "$_GPU"
    printf "  ║  ${NC}Método:   %-34s${CYAN}${BOLD}║\n" "$_GPU_MET"
    printf "  ║  ${NC}Distros: %-33s${CYAN}${BOLD}║\n" "${_DISTROS:0:33}"
    printf "  ║  ${NC}DE:       %-33s${CYAN}${BOLD}║\n" "${_DE:0:33}"
    echo    "  ╠══════════════════════════════════════════╣"
    printf "  ║  ${NC}X11:        %-33b${CYAN}${BOLD}║\n" "$_XDG"
    printf "  ║  ${NC}VNC:        %-33b${CYAN}${BOLD}║\n" "$_VNC"
    printf "  ║  ${NC}PulseAudio: %-33b${CYAN}${BOLD}║\n" "$_PA"
    printf "  ║  ${NC}udocker:  %-33s${CYAN}${BOLD}║\n" "$_U_VER"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[v] Ver registry completo                ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[l] Ver logs de instalación              ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[r] Refrescar                            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver al menú Entorno               ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      v|V)
        clear; echo ""
        echo -e "${CYAN}${BOLD}  Registry ~/.android_server_registry (entorno.*)${NC}"
        echo ""
        grep "^entorno\." "$REGISTRY" 2>/dev/null || echo "    (no hay entries)"
        echo ""; read -r _ < /dev/tty ;;
      l|L)
        clear; echo ""
        local _LOG_DIR="$HOME/.termux-ai-stack/logs"
        if [ -d "$_LOG_DIR" ]; then
          local _LOG_FILE
          _LOG_FILE=$(ls -1t "$_LOG_DIR"/install_entorno*.log 2>/dev/null | head -1)
          if [ -n "$_LOG_FILE" ]; then
            echo -e "  ${CYAN}Último log de instalación:${NC}"
            echo "  $_LOG_FILE"
            echo ""
            cat "$_LOG_FILE"
          else
            echo -e "  ${YELLOW}No hay logs de install_entorno.sh${NC}"
          fi
        else
          echo -e "  ${YELLOW}No existe ~/.termux-ai-stack/logs/${NC}"
        fi
        echo ""; read -r _ < /dev/tty ;;
      r|R) continue ;;
      b|B|"") break ;;
    esac
  done
}

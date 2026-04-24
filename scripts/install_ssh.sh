#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_ssh.sh
#  DEPRECADO — redirige a install_remote.sh
#
#  SSH y Dashboard ahora se instalan juntos como módulo Remote.
#  Este script se mantiene por compatibilidad con versiones
#  anteriores del menú que lo llaman directamente.
#
#  VERSIÓN: 2.0.0 (stub) | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'
BOLD='\033[1m'

echo ""
echo -e "${CYAN}${BOLD}[INFO]${NC} install_ssh.sh → redirigiendo a install_remote.sh"
echo -e "${YELLOW}       SSH y Dashboard ahora se instalan juntos.${NC}"
echo ""

REMOTE_SCRIPT="$HOME/install_remote.sh"
REPO_RAW="https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts"

# Si install_remote.sh no existe, descargarlo
if [ ! -f "$REMOTE_SCRIPT" ] || [ ! -s "$REMOTE_SCRIPT" ]; then
  echo -e "${CYAN}[INFO]${NC} Descargando install_remote.sh..."
  curl -fsSL "$REPO_RAW/install_remote.sh" -o "$REMOTE_SCRIPT" 2>/dev/null || \
    wget -q "$REPO_RAW/install_remote.sh" -O "$REMOTE_SCRIPT" 2>/dev/null

  if [ ! -f "$REMOTE_SCRIPT" ] || [ ! -s "$REMOTE_SCRIPT" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m No se pudo obtener install_remote.sh"
    echo "  Descárgalo manualmente:"
    echo "  curl -fsSL $REPO_RAW/install_remote.sh -o ~/install_remote.sh"
    exit 1
  fi
  chmod +x "$REMOTE_SCRIPT"
  echo -e "${GREEN}[OK]${NC} install_remote.sh descargado"
fi

echo ""
exec bash "$REMOTE_SCRIPT" "$@"

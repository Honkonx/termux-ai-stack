#!/data/data/com.termux/files/usr/bin/bash
# termux-ai-stack — dashboard_start.sh
# Lanza el servidor dashboard en sesión tmux "dashboard"

SESSION="dashboard"
PORT=8080

# Colores
G="\033[0;32m"; Y="\033[0;33m"; C="\033[0;36m"; R="\033[0;31m"; NC="\033[0m"

echo -e "${C}⬡ termux-ai-stack · Dashboard${NC}"
echo -e "${C}─────────────────────────────${NC}"

# Verificar Python
if ! command -v python3 &>/dev/null; then
  echo -e "${R}[ERROR] Python3 no encontrado. Ejecuta: pkg install python${NC}"
  exit 1
fi

# Verificar archivo servidor
if [ ! -f "$HOME/dashboard_server.py" ]; then
  echo -e "${R}[ERROR] $HOME/dashboard_server.py no encontrado${NC}"
  exit 1
fi

# Crear directorio dashboard si no existe
mkdir -p "$HOME/dashboard"

# Copiar index.html al directorio dashboard si existe en HOME
if [ -f "$HOME/index.html" ] && [ ! -f "$HOME/dashboard/index.html" ]; then
  cp "$HOME/index.html" "$HOME/dashboard/index.html"
  echo -e "${G}[OK]${NC} index.html copiado a ~/dashboard/"
fi

# Verificar index.html
if [ ! -f "$HOME/dashboard/index.html" ]; then
  echo -e "${Y}[WARN] No se encontró ~/dashboard/index.html${NC}"
  echo -e "       Coloca el archivo index.html en ~/dashboard/ y reinicia"
fi

# Verificar si ya corre
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo -e "${Y}[INFO] Dashboard ya está corriendo en sesión tmux '$SESSION'${NC}"
  echo -e "       Usa: ${C}tmux attach -t $SESSION${NC} para ver logs"
  echo -e "       Para detener: ${C}bash ~/dashboard_stop.sh${NC}"
else
  # Lanzar en tmux
  tmux new-session -d -s "$SESSION" "python3 $HOME/dashboard_server.py"
  sleep 1

  if tmux has-session -t "$SESSION" 2>/dev/null; then
    IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
    IP=${IP:-"127.0.0.1"}
    echo -e "${G}[OK]${NC} Dashboard iniciado en sesión tmux '$SESSION'"
    echo ""
    echo -e "  ${G}▶ http://localhost:${PORT}${NC}   (este dispositivo)"
    echo -e "  ${C}▶ http://${IP}:${PORT}${NC}   (red local WiFi)"
    echo ""
    echo -e "  Logs: ${C}tmux attach -t $SESSION${NC}"
    echo -e "  Stop: ${C}bash ~/dashboard_stop.sh${NC}"
  else
    echo -e "${R}[ERROR] No se pudo iniciar. Revisa errores con:${NC}"
    echo -e "  python3 $HOME/dashboard_server.py"
  fi
fi

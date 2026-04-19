#!/data/data/com.termux/files/usr/bin/bash
# termux-ai-stack — dashboard_stop.sh

SESSION="dashboard"
G="\033[0;32m"; R="\033[0;31m"; NC="\033[0m"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  echo -e "${G}[OK]${NC} Dashboard detenido (sesión tmux '$SESSION' cerrada)"
else
  echo -e "${R}[INFO]${NC} Dashboard no estaba corriendo"
fi

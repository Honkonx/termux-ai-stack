#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · watcher.sh
#  Servicio IPC para la app React Native (Fase 8b-B)
#
#  - Lee /sdcard/termux_stack/cmd → ejecuta comandos del stack
#  - Escribe /sdcard/termux_stack/registry con estado en vivo
#  - Sincroniza ~/.android_server_registry cada ciclo
#
#  USO:
#    bash ~/watcher.sh &          ← fondo
#    bash ~/watcher.sh            ← foreground (ver logs)
#    pkill -f watcher.sh          ← detener
#
#  VERSIÓN: 1.0.0 | Abril 2026
# ============================================================

STACK_DIR="/sdcard/termux_stack"
CMD_FILE="$STACK_DIR/cmd"
REGISTRY="$STACK_DIR/registry"
HOME_REG="$HOME/.android_server_registry"
LOCK="$STACK_DIR/watcher.pid"

mkdir -p "$STACK_DIR"

# ── Evitar instancias duplicadas ─────────────────────────────
if [ -f "$LOCK" ]; then
  OLD_PID=$(cat "$LOCK")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[watcher] Ya hay una instancia corriendo (PID $OLD_PID)"
    exit 1
  fi
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"; echo "[watcher] detenido"' EXIT INT TERM

echo "[watcher] iniciado (PID $$) — IPC en $STACK_DIR"

# ── Detectar estado de módulos ───────────────────────────────
check_n8n() {
  proot-distro login debian -- bash -c \
    "pgrep -f 'node.*n8n' >/dev/null 2>&1 && echo true || echo false" 2>/dev/null || echo "false"
}

check_ollama() {
  pgrep -f "ollama serve" >/dev/null 2>&1 && echo "true" || echo "false"
}

check_dashboard() {
  pgrep -f "dashboard_server.py" >/dev/null 2>&1 && echo "true" || echo "false"
}

# ── Escribir registry unificado ──────────────────────────────
write_registry() {
  local tmp="$REGISTRY.tmp"

  # Base: copiar home registry (instalaciones, versiones, etc.)
  if [ -f "$HOME_REG" ]; then
    cp "$HOME_REG" "$tmp"
  else
    touch "$tmp"
  fi

  # Añadir estado en vivo (sobreescribe si ya existe la clave)
  {
    echo "n8n.running=$(check_n8n)"
    echo "ollama.running=$(check_ollama)"
    echo "dashboard.running=$(check_dashboard)"
    echo "watcher.running=true"
    echo "watcher.pid=$$"
    echo "watcher.sync=$(date +%H:%M:%S)"
  } >> "$tmp"

  mv "$tmp" "$REGISTRY"
}

# ── Ejecutar comando del stack ───────────────────────────────
run_cmd() {
  local cmd="$1"
  echo "[watcher] cmd → $cmd"

  case "$cmd" in
    n8n.start)
      bash "$HOME/start_servidor.sh" < /dev/null &
      ;;
    n8n.stop)
      bash "$HOME/stop_servidor.sh" < /dev/null &
      ;;
    ollama.start)
      nohup ollama serve > /dev/null 2>&1 &
      ;;
    ollama.stop)
      pkill -f "ollama serve" 2>/dev/null || true
      ;;
    dashboard.start)
      bash "$HOME/dashboard_start.sh" < /dev/null &
      ;;
    dashboard.stop)
      bash "$HOME/dashboard_stop.sh" < /dev/null &
      ;;
    *)
      echo "[watcher] cmd desconocido: $cmd"
      ;;
  esac

  # Esperar a que el proceso cambie de estado
  sleep 4
  write_registry
}

# ── Loop principal ───────────────────────────────────────────
write_registry
echo "[watcher] registry inicial escrito — esperando comandos..."

CYCLE=0
while true; do
  # Leer y ejecutar comando si existe
  if [ -f "$CMD_FILE" ]; then
    CMD=$(cat "$CMD_FILE" 2>/dev/null)
    rm -f "$CMD_FILE"
    [ -n "$CMD" ] && run_cmd "$CMD"
  fi

  # Refrescar estado cada 5 ciclos (~10s)
  CYCLE=$((CYCLE + 1))
  if [ $((CYCLE % 5)) -eq 0 ]; then
    write_registry
  fi

  sleep 2
done

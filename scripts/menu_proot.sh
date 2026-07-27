#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · menu_proot.sh
#  Módulos PROOT Debian:
#    check_n8n, _check_proot_combined,
#    check_opencode, check_openclaw,
#    check_opencode_cached, check_openclaw_cached
#    _n8n_repair_scripts
#    submenu_n8n, submenu_openclaw, submenu_opencode,
#    submenu_servicios
#
#  Cargado via 'source' por menu.sh — no ejecutar directamente.
#
#  RESTRICCIONES PROOT:
#    - proot-distro login "$DISTRO_NAME" tarda 3-5s: minimizar llamadas
#    - _check_proot_combined: 1 sola invocación para OC + CL
#    - pkill desde Termux NO mata procesos dentro del proot
#    - Caché memoria: _PROOT_CACHE_TTL=30s (definida en menu.sh)
#    - Caché archivo: _PROOT_CACHE_TTL_PERSIST=300s (~/.proot_status_cache)
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 5.0.0 | Mayo 2026
# ============================================================

# ════════════════════════════════════════════
#  RUTAS
# ════════════════════════════════════════════
N8N_SCRIPTS="${SCRIPTS_DIR:-$HOME/scripts}/n8n"
N8N_SCRIPTS_UDOCKER="${SCRIPTS_DIR:-$HOME/scripts}/n8n-udocker"

# ════════════════════════════════════════════
#  CHECK N8N
# ════════════════════════════════════════════
check_n8n() {
  [ "$(get_reg n8n installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver; ver=$(get_reg n8n version)
  local mode; mode=$(get_reg n8n mode)
  local session="n8n-server"
  [ "$mode" = "udocker" ] && session="n8n-udocker"
  tmux has-session -t "$session" 2>/dev/null \
    && echo "running|${ver}|${mode}" || echo "stopped|${ver}|${mode}"
}

# ════════════════════════════════════════════
#  CACHÉ PERSISTENTE PROOT
#  Archivo: ~/.proot_status_cache
#  Formato: timestamp|oc_cache|claw_cache
#
#  Estrategia de lectura (en orden):
#    1. Caché en memoria → 0ms
#    2. Caché en archivo → ~2ms (lectura disco)
#    3. proot-distro login → 3-5s (solo si ambos expirados)
#
#  TTL del archivo controlado por _PROOT_CACHE_TTL_PERSIST
#  (definido en menu.sh — por defecto 300s = 5 min)
#  TTL de memoria controlado por _PROOT_CACHE_TTL (30s)
#
#  El archivo sobrevive entre reinicios de Termux.
#  _invalidate_cache() en menu.sh borra el archivo.
# ════════════════════════════════════════════
PROOT_CACHE_FILE="$HOME/.proot_status_cache"

_write_proot_cache() {
  # Serializar estado actual a disco
  # Formato: timestamp|oc_cache_encoded|claw_cache_encoded
  # Los | dentro de los valores se escapan con \x7C para no romper el split
  local ts=$SECONDS
  local oc_enc  claw_enc
  oc_enc=$(echo "$_OC_CACHE"   | sed 's/|/\x7C/g')
  claw_enc=$(echo "$_CLAW_CACHE" | sed 's/|/\x7C/g')
  echo "${ts}|${oc_enc}|${claw_enc}" > "$PROOT_CACHE_FILE" 2>/dev/null || true
}

_load_proot_cache() {
  # Retorna 0 si el caché del archivo es válido y cargó variables
  # Retorna 1 si no hay archivo, está corrupto, expiró, o el rootfs no existe

  # ── Guard crítico: si no hay rootfs, el caché nunca es válido ──
  # Fix S22: no usar [ -f ROOTFS_PATH/bin/bash ] — permisos 0700 bloquean el test
  if [ -z "$DISTRO_NAME" ] || [ ! -d "$ROOTFS_PATH" ]; then
    rm -f "$PROOT_CACHE_FILE" 2>/dev/null || true
    return 1
  fi

  [ -f "$PROOT_CACHE_FILE" ] || return 1
  local line ts oc_enc claw_enc
  line=$(cat "$PROOT_CACHE_FILE" 2>/dev/null) || return 1
  [ -z "$line" ] && return 1

  # Parsear: primer campo = timestamp, segundo = oc, tercero = claw
  ts="${line%%|*}"
  local rest="${line#*|}"
  oc_enc="${rest%%|*}"
  claw_enc="${rest#*|}"

  # Validar timestamp — debe ser número
  [[ "$ts" =~ ^[0-9]+$ ]] || return 1

  # Verificar TTL persistente
  local age=$(( SECONDS - ts ))
  # Si SECONDS < ts (reinicio de Termux resetea $SECONDS a 0), aceptar igual
  # En ese caso age sería negativo — también inválido, relanzar proot
  [ "$age" -gt "${_PROOT_CACHE_TTL_PERSIST:-300}" ] && return 1
  [ "$age" -lt 0 ] && return 1

  # Decodificar valores escapados
  _OC_CACHE=$(printf '%b' "$oc_enc"   | sed 's/\x7C/|/g')
  _CLAW_CACHE=$(printf '%b' "$claw_enc" | sed 's/\x7C/|/g')

  # Validar que no estén vacíos
  [ -z "$_OC_CACHE" ]   && return 1
  [ -z "$_CLAW_CACHE" ] && return 1

  # Actualizar timestamps en memoria con el valor del archivo
  _OC_CACHE_TS=$ts
  _CLAW_CACHE_TS=$ts
  return 0
}


# ════════════════════════════════════════════
#  HELPER: proot-distro login para opencode/openclaw
#
#  NOTA TÉCNICA: proot-distro monta /storage /system /vendor
#  de forma hardcoded — no hay forma de quitarlos sin root.
#  proot directo tampoco funciona: no puede ejecutar binarios
#  ELF de Debian sin el linker que configura proot-distro.
#  El acceso al filesystem de Android es una limitación real
#  del stack proot en Android sin root.
#
#  Lo que SÍ se controla: el cwd del proyecto (cd correcto)
#  y la config de opencode (PATH explícito, HOME=/root).
# ════════════════════════════════════════════
_proot_sdcard_login() {
  local target_path="$1"; shift
  # --bind $HOME:/termux-home expone el home de Termux sin
  # sobreescribir /root del contenedor (donde vive .nvm/.config)
  proot-distro login "$DISTRO_NAME" \
    --bind "$HOME:/termux-home" \
    -- "$@"
}

# ════════════════════════════════════════════
#  CHECK COMBINADO PROOT
#  Una sola invocación proot para opencode + openclaw.
#  Formato salida interna: "found|VER@@found|" o "not_installed|@@not_installed|"
#  Resultado escrito en _OC_CACHE y _CLAW_CACHE (variables globales de menu.sh)
# ════════════════════════════════════════════
_check_proot_combined() {
  # ── Guard: sin rootfs → not_installed inmediato, sin llamar a proot ──
  # Fix S22: no usar [ -f ROOTFS_PATH/bin/bash ] — permisos 0700 bloquean el test
  if [ -z "$DISTRO_NAME" ] || [ ! -d "$ROOTFS_PATH" ]; then
    _OC_CACHE="not_installed||"
    _CLAW_CACHE="not_installed||"
    local now=$SECONDS
    _OC_CACHE_TS=$now
    _CLAW_CACHE_TS=$now
    rm -f "$PROOT_CACHE_FILE" 2>/dev/null || true
    return 0
  fi

  local raw
  raw=$(proot-distro login "$DISTRO_NAME" -- bash -c '
    # ── opencode ──
    source ~/.bashrc 2>/dev/null
    OC_BIN=$(command -v opencode 2>/dev/null)
    if [ -n "$OC_BIN" ]; then
      OC_VER=$(opencode --version 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
      [ -z "$OC_VER" ] && OC_VER="?"
      printf "found|%s" "$OC_VER"
    else
      printf "not_installed|"
    fi
    printf "@@"
    # ── openclaw (requiere NVM) ──
    export HOME=/root
    export NVM_DIR="/root/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
    CL_BIN=$(command -v openclaw 2>/dev/null)
    if [ -n "$CL_BIN" ]; then
      printf "found|"
    else
      printf "not_installed|"
    fi
  ' 2>/dev/null)

  local oc_raw cl_raw
  oc_raw="${raw%%@@*}"
  cl_raw="${raw##*@@}"

  # ── opencode → estado final con tmux (Termux, no proot) ──
  local oc_status oc_ver
  oc_status="${oc_raw%%|*}"
  oc_ver="${oc_raw#*|}"
  if [ "$oc_status" = "found" ]; then
    tmux has-session -t "opencode" 2>/dev/null \
      && _OC_CACHE="running|${oc_ver}|:3000" \
      || _OC_CACHE="stopped|${oc_ver}|"
  else
    _OC_CACHE="not_installed||"
  fi

  # ── openclaw → nativo tiene prioridad sobre proot ────────────
  # Si el binario nativo existe, no es necesario entrar al proot para el check
  local cl_status cl_ver
  local _cl_native_bin=""
  [ -f "$HOME/.npm-global/bin/openclaw" ] && _cl_native_bin="$HOME/.npm-global/bin/openclaw"
  [ -z "$_cl_native_bin" ] && command -v openclaw &>/dev/null &&     _cl_native_bin="$(command -v openclaw)"

  if [ -n "$_cl_native_bin" ]; then
    # Nativo encontrado — usar directamente sin depender del resultado proot
    cl_ver=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
    [ -z "$cl_ver" ] && cl_ver="?"
    curl -sf --max-time 1 http://127.0.0.1:18789 &>/dev/null       && _CLAW_CACHE="running|${cl_ver}|native"       || _CLAW_CACHE="stopped|${cl_ver}|native"
  else
    # Nativo no encontrado — usar resultado proot
    cl_status="${cl_raw%%|*}"
    if [ "$cl_status" = "found" ]; then
      cl_ver=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
      [ -z "$cl_ver" ] && cl_ver="?"
      curl -sf --max-time 1 http://127.0.0.1:18789 &>/dev/null         && _CLAW_CACHE="running|${cl_ver}|:18789"         || _CLAW_CACHE="stopped|${cl_ver}|"
    else
      _CLAW_CACHE="not_installed||"
    fi
  fi

  local now=$SECONDS
  _OC_CACHE_TS=$now
  _CLAW_CACHE_TS=$now

  # Persistir a disco — sobrevive entre reinicios del módulo y sesiones
  _write_proot_cache
}

# ── Checks directos (sin caché) — para submenús internos ─────
check_opencode() {
  # Fix S22: solo verificar [ -d ROOTFS_PATH ], no archivos internos (permisos 0700)
  { [ -z "$DISTRO_NAME" ] || [ ! -d "$ROOTFS_PATH" ]; } && {
    echo "not_installed||"; return
  }
  if proot-distro login "$DISTRO_NAME" -- bash -c \
    'source ~/.bashrc 2>/dev/null; command -v opencode' &>/dev/null 2>&1; then
    local oc_ver
    oc_ver=$(proot-distro login "$DISTRO_NAME" -- bash -c \
      'opencode --version 2>/dev/null | head -1' 2>/dev/null \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$oc_ver" ] && oc_ver="?"
    tmux has-session -t "opencode" 2>/dev/null \
      && echo "running|${oc_ver}|:3000" \
      || echo "stopped|${oc_ver}|"
  else
    echo "not_installed||"
  fi
}

check_openclaw() {
  # Prioridad: nativo > proot
  # 1. Nativo — instantáneo, sin login proot
  local _cn_bin=""
  [ -f "$HOME/.npm-global/bin/openclaw" ] && _cn_bin="$HOME/.npm-global/bin/openclaw"
  [ -z "$_cn_bin" ] && command -v openclaw &>/dev/null && _cn_bin="$(command -v openclaw)"
  if [ -n "$_cn_bin" ]; then
    local cl_ver; cl_ver=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
    [ -z "$cl_ver" ] && cl_ver="?"
    curl -sf --max-time 1 http://127.0.0.1:18789 &>/dev/null       && echo "running|${cl_ver}|native"       || echo "stopped|${cl_ver}|native"
    return
  fi
  # 2. Proot — Fix S22: solo verificar [ -d ROOTFS_PATH ]
  { [ -z "$DISTRO_NAME" ] || [ ! -d "$ROOTFS_PATH" ]; } && {
    echo "not_installed||"; return
  }
  if proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; export NVM_DIR="/root/.nvm"
     [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
     command -v openclaw' &>/dev/null 2>&1; then
    local cl_ver
    cl_ver=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
    [ -z "$cl_ver" ] && cl_ver="?"
    curl -sf --max-time 1 http://127.0.0.1:18789 &>/dev/null       && echo "running|${cl_ver}|"       || echo "stopped|${cl_ver}|"
  else
    echo "not_installed||"
  fi
}

# ── Wrappers con caché TTL + caché persistente en archivo ────
check_opencode_cached() {
  local now=$SECONDS

  # 1. Caché en memoria vigente → devolver directo (0ms)
  if [ -n "$_OC_CACHE" ] && \
     [ $(( now - _OC_CACHE_TS )) -le $_PROOT_CACHE_TTL ]; then
    echo "$_OC_CACHE"
    return
  fi

  # 2. Caché en archivo válido → cargar a memoria y devolver (~2ms)
  if _load_proot_cache; then
    echo "$_OC_CACHE"
    return
  fi

  # 3. Sin caché válido → llamar proot (3-5s) y escribir caché
  _check_proot_combined
  echo "$_OC_CACHE"
}

check_openclaw_cached() {
  local now=$SECONDS

  # 1. Caché en memoria vigente → devolver directo (0ms)
  if [ -n "$_CLAW_CACHE" ] && \
     [ $(( now - _CLAW_CACHE_TS )) -le $_PROOT_CACHE_TTL ]; then
    echo "$_CLAW_CACHE"
    return
  fi

  # 2. Caché en archivo válido → cargar a memoria y devolver (~2ms)
  if _load_proot_cache; then
    echo "$_CLAW_CACHE"
    return
  fi

  # 3. Sin caché válido → llamar proot (3-5s) y escribir caché
  _check_proot_combined
  echo "$_CLAW_CACHE"
}

# ════════════════════════════════════════════
#  REPARAR SCRIPTS N8N — udocker
# ════════════════════════════════════════════
_repair_n8n_udocker() {
  mkdir -p "$N8N_SCRIPTS_UDOCKER"

  # --- start.sh (n8n + cloudflared nativo) ---
  echo -n "  Creando start.sh... "
  cat > "$N8N_SCRIPTS_UDOCKER/start.sh" << 'STARTSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
N8N_DATA_ABS="${TERMUX_HOME}/n8n-udocker"
SESSION="n8n-udocker"
CF_LOG="$TERMUX_HOME/.cf_ud_url.log"

export UDOCKER_USE_PROOT_EXECUTABLE="${TERMUX_PREFIX}/bin/proot"

echo "[*] Iniciando n8n (udocker) + tunnel en sesión tmux..."
echo "    HOME:   $TERMUX_HOME"
echo "    Datos:  $N8N_DATA_ABS"
echo "    Puerto: 5678"
echo ""

[ ! -d "$N8N_DATA_ABS" ] && mkdir -p "$N8N_DATA_ABS" && chmod 777 "$N8N_DATA_ABS"
[ ! -w "$N8N_DATA_ABS" ] && { echo "[ERROR] No se puede escribir en $N8N_DATA_ABS"; exit 1; }

if ! command -v udocker &>/dev/null; then echo "[ERROR] udocker no instalado."; exit 1; fi

if ! udocker inspect n8n &>/dev/null; then
  echo "[AVISO] Contenedor 'n8n' no existe — creando..."
  if udocker images 2>/dev/null | grep -q "n8nio/n8n"; then
    udocker create --name=n8n n8nio/n8n || { echo "[ERROR] No se pudo crear contenedor"; exit 1; }
  else
    echo "[ERROR] Imagen n8nio/n8n no encontrada."; exit 1
  fi
fi

udocker setup --execmode=P2 n8n 2>/dev/null || true

tmux kill-session -t "$SESSION" 2>/dev/null || true
sleep 1
tmux new-session -d -s "$SESSION" -n "n8n"

tmux send-keys -t "$SESSION:n8n" \
  "udocker run --publish=5678:5678 --volume=${N8N_DATA_ABS}:/home/node/.n8n --env=N8N_HOST=0.0.0.0 --env=N8N_PORT=5678 --env=N8N_SECURE_COOKIE=false --env=N8N_RUNNERS_ENABLED=true --env=NODE_FUNCTION_ALLOW_BUILTIN=child_process,fs,path,os --env=NODE_FUNCTION_ALLOW_EXTERNAL=* n8n" Enter

echo "[*] Esperando que n8n arranque..."
HEALTH_OK=false
for i in $(seq 1 30); do
  sleep 2
  if curl -sf --max-time 2 http://localhost:5678/healthz >/dev/null 2>&1; then
    HEALTH_OK=true; echo "[OK] n8n respondió en ${i} intentos (~$((i*2))s)"; break
  fi
  printf "  [%2d/30] Esperando n8n...\r" "$i"
done
[ "$HEALTH_OK" = false ] && echo "" && echo "[AVISO] n8n no respondió en 60s."

echo "[*] Iniciando cloudflared nativo (Termux)..."
if ! command -v cloudflared &>/dev/null; then
  echo "[AVISO] cloudflared no instalado. n8n solo accesible en localhost:5678"
else
  tmux new-window -t "$SESSION" -n "tunnel"
  if [ -f "$TERMUX_HOME/.cf_token" ] && [ -s "$TERMUX_HOME/.cf_token" ]; then
    CF_TOK=$(cat "$TERMUX_HOME/.cf_token")
    tmux send-keys -t "$SESSION:tunnel" \
      "cloudflared tunnel --no-autoupdate run --token ${CF_TOK} 2>&1 | tee ${CF_LOG}" Enter
    echo "    Modo: URL FIJA (token cloudflare)"
  else
    tmux send-keys -t "$SESSION:tunnel" \
      "cloudflared tunnel --no-autoupdate --url http://localhost:5678 2>&1 | tee ${CF_LOG}" Enter
    echo "    Modo: URL temporal"
  fi
  echo "[*] Obteniendo URL cloudflared (20 seg)..."; sleep 20
fi

IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
CF_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$CF_LOG" 2>/dev/null | head -1)
[ -n "$CF_URL" ] && echo "$CF_URL" > "$TERMUX_HOME/.last_cf_url"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   n8n ACTIVO · udocker + tunnel       ║"
echo "╠════════════════════════════════════════╣"
echo "║  Local:    http://localhost:5678       ║"
[ -n "$IP" ]     && echo "║  WiFi PC:  http://$IP:5678"
[ -n "$CF_URL" ] && echo "║  Internet: $CF_URL" || echo "║  Internet: (tunnel iniciando...)"
[ -f "$TERMUX_HOME/.cf_token" ] && echo "║  Modo:     URL FIJA ✓"
echo "╚════════════════════════════════════════╝"
STARTSCRIPT
  chmod +x "$N8N_SCRIPTS_UDOCKER/start.sh"
  echo -e "${GREEN}✓${NC}"

  # --- start_local.sh (n8n sin tunnel) ---
  echo -n "  Creando start_local.sh... "
  cat > "$N8N_SCRIPTS_UDOCKER/start_local.sh" << 'LOCALSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
N8N_DATA_ABS="${TERMUX_HOME}/n8n-udocker"
SESSION="n8n-udocker"

export UDOCKER_USE_PROOT_EXECUTABLE="${TERMUX_PREFIX}/bin/proot"

echo "[*] Iniciando n8n (udocker, localhost sin tunnel)..."
echo "    HOME:   $TERMUX_HOME"
echo "    Datos:  $N8N_DATA_ABS"
echo "    Puerto: 5678"
echo ""

[ ! -d "$N8N_DATA_ABS" ] && mkdir -p "$N8N_DATA_ABS" && chmod 777 "$N8N_DATA_ABS"
[ ! -w "$N8N_DATA_ABS" ] && { echo "[ERROR] No se puede escribir en $N8N_DATA_ABS"; exit 1; }

if ! command -v udocker &>/dev/null; then echo "[ERROR] udocker no instalado."; exit 1; fi

if ! udocker inspect n8n &>/dev/null; then
  echo "[AVISO] Contenedor 'n8n' no existe — creando..."
  if udocker images 2>/dev/null | grep -q "n8nio/n8n"; then
    udocker create --name=n8n n8nio/n8n || { echo "[ERROR] No se pudo crear contenedor"; exit 1; }
  else
    echo "[ERROR] Imagen n8nio/n8n no encontrada."; exit 1
  fi
fi

udocker setup --execmode=P2 n8n 2>/dev/null || true

tmux kill-session -t "$SESSION" 2>/dev/null || true
sleep 1
tmux new-session -d -s "$SESSION" -n "n8n"

tmux send-keys -t "$SESSION:n8n" \
  "udocker run --publish=5678:5678 --volume=${N8N_DATA_ABS}:/home/node/.n8n --env=N8N_HOST=0.0.0.0 --env=N8N_PORT=5678 --env=N8N_SECURE_COOKIE=false --env=N8N_RUNNERS_ENABLED=true --env=NODE_FUNCTION_ALLOW_BUILTIN=child_process,fs,path,os --env=NODE_FUNCTION_ALLOW_EXTERNAL=* n8n" Enter

echo "[*] Esperando que n8n arranque..."
HEALTH_OK=false
for i in $(seq 1 30); do
  sleep 2
  if curl -sf --max-time 2 http://localhost:5678/healthz >/dev/null 2>&1; then
    HEALTH_OK=true; echo "[OK] n8n respondió en ${i} intentos (~$((i*2))s)"; break
  fi
  printf "  [%2d/30] Esperando n8n...\r" "$i"
done
[ "$HEALTH_OK" = false ] && echo "" && echo "[AVISO] n8n no respondió en 60s."

IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   n8n ACTIVO · localhost (udocker)    ║"
echo "╠════════════════════════════════════════╣"
echo "║  Local:    http://localhost:5678       ║"
[ -n "$IP" ]     && echo "║  WiFi PC:  http://$IP:5678"
echo "║  Modo: LOCAL (sin cloudflare)         ║"
echo "╚════════════════════════════════════════╝"
LOCALSCRIPT
  chmod +x "$N8N_SCRIPTS_UDOCKER/start_local.sh"
  echo -e "${GREEN}✓${NC}"

  # --- stop.sh ---
  echo -n "  Creando stop.sh... "
  cat > "$N8N_SCRIPTS_UDOCKER/stop.sh" << 'STOPSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Deteniendo n8n (udocker) + cloudflared..."
pkill -f "cloudflared tunnel" 2>/dev/null || true
tmux kill-session -t "n8n-udocker" 2>/dev/null || true
tmux kill-session -t "n8n-cf-tunnel" 2>/dev/null || true
sleep 2
rm -f "$HOME/.cf_ud_url.log" 2>/dev/null
rm -f "$HOME/.last_cf_url" 2>/dev/null
echo "[OK] n8n udocker detenido."
STOPSCRIPT
  chmod +x "$N8N_SCRIPTS_UDOCKER/stop.sh"
  echo -e "${GREEN}✓${NC}"

  # --- status.sh ---
  echo -n "  Creando status.sh... "
  cat > "$N8N_SCRIPTS_UDOCKER/status.sh" << 'STATUSSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
TERMUX_HOME="${HOME:-/data/data/com.termux/files/home}"
echo ""
echo "╔══════════════════════════════════════╗"
echo "║   termux-ai-stack · n8n (udocker)   ║"
echo "╠══════════════════════════════════════╣"
tmux has-session -t "n8n-udocker" 2>/dev/null \
  && echo "║  n8n:    ● ACTIVO                    ║" \
  || echo "║  n8n:    ○ DETENIDO                  ║"
echo "║  Puerto: 5678                        ║"
echo "║  Datos:  $TERMUX_HOME/n8n-udocker"
_CF_URL=$(cat "$TERMUX_HOME/.last_cf_url" 2>/dev/null)
[ -z "$_CF_URL" ] && _CF_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TERMUX_HOME/.cf_ud_url.log" 2>/dev/null | head -1)
[ -n "$_CF_URL" ] && echo "║  URL:    $_CF_URL"
[ -f "$TERMUX_HOME/.cf_token" ] && echo "║  Tunnel: URL FIJA (token ✓)          ║"
_IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
[ -n "$_IP" ] && echo "║  WiFi:   http://$_IP:5678"
echo "╚══════════════════════════════════════╝"
echo ""
STATUSSCRIPT
  chmod +x "$N8N_SCRIPTS_UDOCKER/status.sh"
  echo -e "${GREEN}✓${NC}"

  # --- log.sh ---
  echo -n "  Creando log.sh... "
  cat > "$N8N_SCRIPTS_UDOCKER/log.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
tmux has-session -t "n8n-udocker" 2>/dev/null && \
  tmux attach-session -t "n8n-udocker" || \
  echo "[!] n8n udocker no está corriendo — ejecuta: n8n-ud-start"
SCRIPT
  chmod +x "$N8N_SCRIPTS_UDOCKER/log.sh"
  echo -e "${GREEN}✓${NC}"

  echo ""
  echo -e "  ${GREEN}[OK]${NC} 5 scripts regenerados correctamente en ~/scripts/n8n-udocker/"
  echo -e "  ${DIM}start · start_local · stop · status · log${NC}"
}

# ════════════════════════════════════════════
#  REPARAR SCRIPTS N8N
#  Uso: _n8n_repair_scripts [proot|udocker]
#  proot → ~/scripts/n8n/
#  udocker → ~/scripts/n8n-udocker/
# ════════════════════════════════════════════
_n8n_repair_scripts() {
  local _mode="${1:-proot}"

  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  printf "  ║  ⬡ N8N — Reparar scripts [%-7s]║\n" "$_mode"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""

  if [ "$_mode" = "udocker" ]; then
    _repair_n8n_udocker
    return $?
  fi

  # Auto-detectar distro proot
  if [ -z "$DISTRO_NAME" ]; then
    DISTRO_NAME=$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print $NF}' | head -1)
  fi

  echo -n "  Verificando n8n en proot Debian... "
  if ! proot-distro login "$DISTRO_NAME" -- bash -c 'command -v n8n' &>/dev/null 2>&1; then
    echo -e "${RED}✗${NC}"
    echo -e "  ${RED}[ERROR]${NC} n8n no está instalado en proot Debian."
    echo -e "  ${YELLOW}[INFO]${NC} Ve al menú principal → [1] → instalar n8n primero."
    return 1
  fi
  echo -e "${GREEN}✓${NC}"; echo ""

  # Asegurar que existe el directorio destino
  mkdir -p "$N8N_SCRIPTS"

  local _REPAIR_PROTO
  _REPAIR_PROTO=$(cat "$HOME/.n8n_protocol" 2>/dev/null || echo "https")

  # --- start_servidor.sh ---
  echo -n "  Creando start_servidor.sh... "
  cat > "$N8N_SCRIPTS/start_servidor.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
# wake-lock auto — termux-ai-stack
termux-wake-lock 2>/dev/null &

LAST_URL="\$HOME/.last_cf_url"
SESSION="n8n-server"

WEBHOOK_URL_CFG=\$(grep "^N8N_WEBHOOK_URL=" "\$HOME/.env_n8n" 2>/dev/null | cut -d'=' -f2)

if [ -z "\$WEBHOOK_URL_CFG" ] && [ -f "\$HOME/.cf_token" ] && [ -s "\$HOME/.cf_token" ]; then
  echo "[!] Token cloudflared configurado pero sin WEBHOOK_URL."
  echo "    Configura tu dominio: menú → n8n → [8]"
  echo ""
fi

echo "[*] Iniciando n8n + cloudflared en sesión tmux..."
tmux kill-session -t "\$SESSION" 2>/dev/null || true
sleep 1

tmux new-session -d -s "\$SESSION" -n "n8n"

N8N_CMD="export HOME=/root"
N8N_CMD="\${N8N_CMD} && export NODE_FUNCTION_ALLOW_BUILTIN=child_process,fs,path,os"
N8N_CMD="\${N8N_CMD} && export NODE_FUNCTION_ALLOW_EXTERNAL=*"
N8N_CMD="\${N8N_CMD} && export N8N_HOST=0.0.0.0"
N8N_CMD="\${N8N_CMD} && export N8N_PORT=5678"
N8N_CMD="\${N8N_CMD} && export N8N_PROXY_HOPS=1"
N8N_CMD="\${N8N_CMD} && export N8N_PROTOCOL=${_REPAIR_PROTO}"
N8N_CMD="\${N8N_CMD} && export N8N_SECURE_COOKIE=false"
N8N_CMD="\${N8N_CMD} && export N8N_RUNNERS_ENABLED=true"
N8N_CMD="\${N8N_CMD} && export N8N_RUNNERS_HEARTBEAT_INTERVAL=300"
[ -n "\$WEBHOOK_URL_CFG" ] && N8N_CMD="\${N8N_CMD} && export WEBHOOK_URL=\${WEBHOOK_URL_CFG}"
N8N_CMD="\${N8N_CMD} && n8n start"

[ -n "\$WEBHOOK_URL_CFG" ] && echo "[*] Webhook URL: \$WEBHOOK_URL_CFG"
echo "[*] Protocolo: ${_REPAIR_PROTO}"
tmux send-keys -t "\$SESSION:n8n" \
  "proot-distro login "$DISTRO_NAME" -- bash -c '\${N8N_CMD}'" Enter

echo "[*] Esperando que n8n inicie (35 seg)..."
sleep 35

echo "[*] Iniciando cloudflared tunnel..."
tmux new-window -t "\$SESSION" -n "tunnel"

if [ -f "\$HOME/.cf_token" ]; then
  CF_TOK=\$(cat "\$HOME/.cf_token")
  tmux send-keys -t "\$SESSION:tunnel" \
    "proot-distro login "$DISTRO_NAME" -- bash -c 'cloudflared tunnel --no-autoupdate run --token \${CF_TOK} 2>&1 | tee /root/cf_url.log'" Enter
else
  tmux send-keys -t "\$SESSION:tunnel" \
    "proot-distro login "$DISTRO_NAME" -- bash -c 'cloudflared tunnel --no-autoupdate --url http://localhost:5678 2>&1 | tee /root/cf_url.log'" Enter
fi

echo "[*] Obteniendo URL pública (40 seg)..."
sleep 40

if [ -n "\$WEBHOOK_URL_CFG" ]; then
  CF_URL="\$WEBHOOK_URL_CFG"
else
  CF_URL=\$(proot-distro login "$DISTRO_NAME" -- bash -c \
    "grep -o 'https://[a-zA-Z0-9.-]*\\.trycloudflare\\.com' /root/cf_url.log 2>/dev/null | head -1" 2>/dev/null)
fi

IP=\$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print \$2}' | head -1)
[ -z "\$IP" ] && IP=\$(ifconfig 2>/dev/null | grep "inet " | grep -v "127\." | awk '{print \$2}' | head -1)
[ -n "\$CF_URL" ] && echo "\$CF_URL" > "\$HOME/.last_cf_url"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   n8n ACTIVO · proot Debian            ║"
echo "╠════════════════════════════════════════╣"
echo "║  Teléfono: http://localhost:5678       ║"
[ -n "\$IP" ]     && echo "║  WiFi PC:  http://\$IP:5678"
[ -n "\$CF_URL" ] && echo "║  Internet: \$CF_URL" || echo "║  Internet: usa n8n-url en ~20s"
[ -f "\$HOME/.cf_token" ] && echo "║  Modo: URL FIJA ✓" || echo "║  Modo: URL temporal"
[ -n "\$WEBHOOK_URL_CFG" ] && echo "║  Webhook:  \$WEBHOOK_URL_CFG"
echo "║  Protocolo: ${_REPAIR_PROTO}"
echo "╠════════════════════════════════════════╣"
echo "║  child_process: HABILITADO ✓           ║"
echo "╚════════════════════════════════════════╝"
SCRIPT
  chmod +x "$N8N_SCRIPTS/start_servidor.sh"
  echo -e "${GREEN}✓${NC}"

  # --- start_local.sh (n8n sin tunnel) ---
  echo -n "  Creando start_local.sh... "
  cat > "$N8N_SCRIPTS/start_local.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
# wake-lock auto — termux-ai-stack
termux-wake-lock 2>/dev/null &

SESSION="n8n-server"

echo "[*] Iniciando n8n (localhost, sin tunnel)..."
tmux kill-session -t "\$SESSION" 2>/dev/null || true
sleep 1

tmux new-session -d -s "\$SESSION" -n "n8n"

N8N_CMD="export HOME=/root"
N8N_CMD="\${N8N_CMD} && export NODE_FUNCTION_ALLOW_BUILTIN=child_process,fs,path,os"
N8N_CMD="\${N8N_CMD} && export NODE_FUNCTION_ALLOW_EXTERNAL=*"
N8N_CMD="\${N8N_CMD} && export N8N_HOST=0.0.0.0"
N8N_CMD="\${N8N_CMD} && export N8N_PORT=5678"
N8N_CMD="\${N8N_CMD} && export N8N_PROXY_HOPS=1"
N8N_CMD="\${N8N_CMD} && export N8N_PROTOCOL=${_REPAIR_PROTO}"
N8N_CMD="\${N8N_CMD} && export N8N_SECURE_COOKIE=false"
N8N_CMD="\${N8N_CMD} && export N8N_RUNNERS_ENABLED=true"
N8N_CMD="\${N8N_CMD} && export N8N_RUNNERS_HEARTBEAT_INTERVAL=300"
N8N_CMD="\${N8N_CMD} && n8n start"

tmux send-keys -t "\$SESSION:n8n" \
  "proot-distro login "$DISTRO_NAME" -- bash -c '\${N8N_CMD}'" Enter

echo "[*] Esperando que n8n inicie..."
HEALTH_OK=false
for i in \$(seq 1 30); do
  sleep 2
  if curl -sf --max-time 2 http://localhost:5678/healthz >/dev/null 2>&1; then
    HEALTH_OK=true
    echo "[OK] n8n respondió en \${i} intentos (~\$((i*2))s)"
    break
  fi
  printf "  [%2d/30] Esperando n8n...\r" "\$i"
done

if [ "\$HEALTH_OK" = false ]; then
  echo ""
  echo "[AVISO] n8n no respondió en 60s."
  echo "        Revisa logs: tmux attach -t \$SESSION"
fi

IP=\$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print \$2}' | head -1)
[ -z "\$IP" ] && IP=\$(ifconfig 2>/dev/null | grep "inet " | grep -v "127\." | awk '{print \$2}' | head -1)

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   n8n ACTIVO · localhost (proot)       ║"
echo "╠════════════════════════════════════════╣"
echo "║  Teléfono: http://localhost:5678       ║"
[ -n "\$IP" ]     && echo "║  WiFi PC:  http://\$IP:5678"
echo "║  Modo: LOCAL (sin cloudflare)         ║"
echo "╚════════════════════════════════════════╝"
SCRIPT
  chmod +x "$N8N_SCRIPTS/start_local.sh"
  echo -e "${GREEN}✓${NC}"

  # --- stop_servidor.sh ---
  echo -n "  Creando stop_servidor.sh... "
  cat > "$N8N_SCRIPTS/stop_servidor.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Deteniendo n8n y cloudflared..."
proot-distro login "$DISTRO_NAME" -- bash -c \
  'pkill -f n8n 2>/dev/null; pkill -f cloudflared 2>/dev/null; rm -f /root/cf_url.log' 2>/dev/null || true
tmux kill-session -t "n8n-server" 2>/dev/null || true
rm -f "$HOME/.last_cf_url" 2>/dev/null
echo "[OK] Todo detenido."
SCRIPT
  chmod +x "$N8N_SCRIPTS/stop_servidor.sh"
  echo -e "${GREEN}✓${NC}"

  # --- ver_url.sh ---
  echo -n "  Creando ver_url.sh... "
  cat > "$N8N_SCRIPTS/ver_url.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
URL=""
[ -f "$HOME/.last_cf_url" ] && URL=$(cat "$HOME/.last_cf_url")
if [ -z "$URL" ]; then
  URL=$(proot-distro login "$DISTRO_NAME" -- bash -c \
    "grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' /root/cf_url.log 2>/dev/null | head -1" 2>/dev/null)
fi
[ -n "$URL" ] && echo "" && echo "  ▸ $URL" && echo "" || \
  echo "[!] URL no disponible — ejecuta n8n-start primero"
SCRIPT
  chmod +x "$N8N_SCRIPTS/ver_url.sh"
  echo -e "${GREEN}✓${NC}"

  # --- n8n_status.sh ---
  echo -n "  Creando n8n_status.sh... "
  cat > "$N8N_SCRIPTS/n8n_status.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo ""
echo "╔══════════════════════════════════════╗"
echo "║        termux-ai-stack · n8n        ║"
echo "╠══════════════════════════════════════╣"
tmux has-session -t "n8n-server" 2>/dev/null && \
  echo "║  n8n:         ● ACTIVO               ║" || \
  echo "║  n8n:         ○ DETENIDO             ║"
URL=""
[ -f "$HOME/.last_cf_url" ] && URL=$(cat "$HOME/.last_cf_url")
[ -n "$URL" ] && printf "║  URL:  %-30s║\n" "$URL" || \
  echo "║  URL:         no disponible          ║"
[ -f "$HOME/.cf_token" ] && \
  echo "║  Túnel:       URL FIJA (token ✓)     ║" || \
  echo "║  Túnel:       URL temporal           ║"
IP=$(ifconfig 2>/dev/null | grep -A1 "netmask 255\.255\." | grep "inet " | grep -v "127\." | awk '{print $2}' | head -1)
[ -n "$IP" ] && printf "║  WiFi: http://%-23s║\n" "$IP:5678"
echo "╚══════════════════════════════════════╝"
echo ""
SCRIPT
  chmod +x "$N8N_SCRIPTS/n8n_status.sh"
  echo -e "${GREEN}✓${NC}"

  # --- n8n_log.sh ---
  echo -n "  Creando n8n_log.sh... "
  cat > "$N8N_SCRIPTS/n8n_log.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
tmux has-session -t "n8n-server" 2>/dev/null && \
  tmux attach-session -t "n8n-server" || \
  echo "[!] n8n no está corriendo — ejecuta: n8n-start"
SCRIPT
  chmod +x "$N8N_SCRIPTS/n8n_log.sh"
  echo -e "${GREEN}✓${NC}"

  # --- n8n_update.sh ---
  echo -n "  Creando n8n_update.sh... "
  cat > "$N8N_SCRIPTS/n8n_update.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Actualizando n8n..."
proot-distro login "$DISTRO_NAME" -- bash -c \
  'export HOME=/root && npm update -g n8n && echo "n8n: $(n8n --version)"'
SCRIPT
  chmod +x "$N8N_SCRIPTS/n8n_update.sh"
  echo -e "${GREEN}✓${NC}"

  # --- n8n_backup.sh ---
  # NOTA: usa /tmp dentro del proot Debian (no Termux) — no aplica la regla noexec
  echo -n "  Creando n8n_backup.sh... "
  cat > "$N8N_SCRIPTS/n8n_backup.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
FECHA=$(date +%Y%m%d_%H%M)
DESTINO="/sdcard/Download/n8n_workflows_$FECHA.tar.gz"
echo "[*] Creando backup de workflows y credenciales n8n..."
proot-distro login "$DISTRO_NAME" -- bash -c \
  "tar -czf /tmp/n8n_backup.tar.gz -C /root/.n8n . 2>/dev/null && echo done"
proot-distro login "$DISTRO_NAME" -- bash -c "cat /tmp/n8n_backup.tar.gz" > "$DESTINO" 2>/dev/null
SIZE=$(du -h "$DESTINO" 2>/dev/null | cut -f1)
echo "[OK] Backup: $DESTINO ($SIZE)"
SCRIPT
  chmod +x "$N8N_SCRIPTS/n8n_backup.sh"
  echo -e "${GREEN}✓${NC}"

  # --- cf_token.sh ---
  echo -n "  Creando cf_token.sh... "
  cat > "$N8N_SCRIPTS/cf_token.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo ""
echo "  Token: $([ -f ~/.cf_token ] && echo 'configurado (URL fija)' || echo 'no configurado (URL temporal)')"
echo ""
echo -n "  Nuevo token (ENTER = URL temporal): "
read -r TOKEN < /dev/tty
if [ -n "$TOKEN" ]; then
  echo "$TOKEN" > "$HOME/.cf_token"
  echo "[OK] Token guardado — URL fija activada"
else
  rm -f "$HOME/.cf_token"
  echo "[OK] Modo URL temporal activado"
fi
SCRIPT
  chmod +x "$N8N_SCRIPTS/cf_token.sh"
  echo -e "${GREEN}✓${NC}"

  echo ""
  echo -e "  ${GREEN}[OK]${NC} 9 scripts regenerados correctamente en ~/scripts/n8n/"
  echo -e "  ${DIM}start · start_local · stop · url · status · log · update · backup · cf_token${NC}"
}

# ════════════════════════════════════════════
#  SUBMENÚ N8N
# ════════════════════════════════════════════
# _run_installer() usada en este archivo es la de menu_nativo.sh (silent+
# spinner+log, corregida 2026-07-25) — antes había una copia duplicada acá
# con el mismo nombre pero siempre foreground/sin log; se eliminó para que
# no dependa del orden de carga entre menu_nativo.sh y menu_proot.sh.

# ════════════════════════════════════════════
#  SUBMENÚ N8N — UNIFICADO proot + udocker
#  Detecta modo(s) instalado(s) automáticamente.
#  Si ambos: mini-selector previo.
#  Mismas opciones 1-9 para ambos modos.
# ════════════════════════════════════════════
submenu_n8n() {
  # Auto-detectar distro proot para scripts que lo necesiten
  if [ -z "$DISTRO_NAME" ]; then
    DISTRO_NAME=$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print $NF}' | head -1)
  fi
  while true; do
    clear; echo ""
    local _MODE _VER _SESSION _IS_RUNNING
    local _HAS_PROOT=false _HAS_UDOCKER=false

    # ── Detectar modos instalados ───────────────────────────
    _MODE=$(grep "^n8n\.mode=" "$REGISTRY" 2>/dev/null | cut -d= -f2)
    _VER=$(grep "^n8n\.version=" "$REGISTRY" 2>/dev/null | cut -d= -f2)
    [ -z "$_VER" ] && _VER="?"

    [ "$_MODE" = "proot" ] && _HAS_PROOT=true
    [ "$_MODE" = "udocker" ] && _HAS_UDOCKER=true
    [ -f "$N8N_SCRIPTS/start_servidor.sh" ] && _HAS_PROOT=true
    [ -f "$N8N_SCRIPTS_UDOCKER/start.sh" ] && _HAS_UDOCKER=true

    # ── Nada instalado → instalar ──────────────────────────
    if ! $_HAS_PROOT && ! $_HAS_UDOCKER; then
      echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
      echo    "  ║  ⬡ N8N — No instalado                  ║"
      echo    "  ╠══════════════════════════════════════════╣"
      echo -e "  ║  ${NC}[1]  Instalar n8n (proot Debian)       ${CYAN}${BOLD}║"
      echo -e "  ║  ${NC}[2]  Instalar n8n (udocker)             ${CYAN}${BOLD}║"
      echo -e "  ║  ${NC}[b]  Volver                             ${CYAN}${BOLD}║"
      echo -e "  ╚══════════════════════════════════════════╝${NC}"
      echo ""; echo -n "  Opción: "
      read -r _NOPT < /dev/tty
      case "$_NOPT" in
        1) _run_installer "install_n8n.sh" "n8n proot" N8N_INSTALL_MODE=1
           echo ""; read -r _ < /dev/tty ;;
        2) _run_installer "install_n8n.sh" "n8n udocker" N8N_INSTALL_MODE=2
           echo ""; read -r _ < /dev/tty ;;
        b|B|"") break ;;
      esac
      continue
    fi

    # ── Ambos instalados → usar el modo activo del registry directo,
    # sin preguntar cada vez (el usuario puede cambiar con [c] dentro
    # del menú de control, o reinstalando en el otro modo) ─────────
    if $_HAS_PROOT && $_HAS_UDOCKER; then
      [ "$_MODE" != "proot" ] && [ "$_MODE" != "udocker" ] && _MODE="proot"
    else
      $_HAS_PROOT && _MODE="proot"
      $_HAS_UDOCKER && _MODE="udocker"
    fi

    # ── Determinar estado ──────────────────────────────────
    [ "$_MODE" = "udocker" ] && _SESSION="n8n-udocker" || _SESSION="n8n-server"
    _IS_RUNNING=false
    tmux has-session -t "$_SESSION" 2>/dev/null && _IS_RUNNING=true

    # ── Ver datos del modo seleccionado ────────────────────
    if [ "$_MODE" = "udocker" ]; then
      _VER=$(grep "^n8n\.version=" "$REGISTRY" 2>/dev/null | cut -d= -f2)
      [ -z "$_VER" ] && _VER="?"
    fi
    local _N8N_PROTO _CF_TOKEN
    _N8N_PROTO=$(cat "$HOME/.n8n_protocol" 2>/dev/null || echo "https")
    [ -f "$HOME/.cf_token" ] && [ -s "$HOME/.cf_token" ] && _CF_TOKEN=true || _CF_TOKEN=false

    # ════════════════════════════════════════════
    #  MENÚ DE CONTROL UNIFICADO (mismo para ambos)
    # ════════════════════════════════════════════
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    if $_IS_RUNNING; then
      printf "  ║  ⬡ N8N · %-8s ${GREEN}● activo${CYAN}${BOLD}        :5678  ║\n" "$_MODE"
    else
      printf "  ║  ⬡ N8N · %-8s ${YELLOW}○ detenido${CYAN}${BOLD}      :5678  ║\n" "$_MODE"
    fi
    printf "  ║  ${NC}v%-38s${CYAN}${BOLD}║\n" "$_VER"
    if $_CF_TOKEN; then
      echo -e "  ║  ${NC}Tunnel: URL fija ${GREEN}●${NC}${CYAN}${BOLD}                   ║"
    else
      echo -e "  ║  ${NC}Tunnel: URL temporal ${YELLOW}○${NC}${CYAN}${BOLD}                 ║"
    fi
    if [ "$_MODE" = "proot" ]; then
      echo -e "  ║  ${NC}Protocolo: ${GREEN}${_N8N_PROTO}${NC}${CYAN}${BOLD}                       ║"
    fi
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1]  Iniciar n8n + tunnel              ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2]  Detener n8n + tunnel              ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3]  Iniciar n8n (localhost)           ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4]  Ver URL pública (cloudflare)      ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5]  Logs en vivo                      ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6]  Ver estado del sistema            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[7]  Actualizar n8n                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[8]  Backup workflows                  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[9]  Token CF + Dominio webhook        ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[r]  Reparar scripts de control         ${CYAN}${BOLD}║"
    if [ "$_MODE" = "proot" ]; then
      echo -e "  ║  ${NC}[p]  Protocolo HTTP / HTTPS             ${CYAN}${BOLD}║"
    fi
    if $_HAS_PROOT && $_HAS_UDOCKER; then
      echo -e "  ║  ${NC}[c]  Cambiar a modo $([ "$_MODE" = "proot" ] && echo "udocker" || echo "proot")${CYAN}${BOLD}                ║"
    fi
    echo -e "  ║  ${NC}[i]  Reinstalar n8n                     ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b]  Volver                             ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        if [ "$_MODE" = "udocker" ]; then
          [ -f "$N8N_SCRIPTS_UDOCKER/start.sh" ] \
            && bash "$N8N_SCRIPTS_UDOCKER/start.sh" \
            || echo -e "  ${RED}[ERROR]${NC} Script no encontrado — reinstala n8n udocker"
        else
          if [ ! -f "$N8N_SCRIPTS/start_servidor.sh" ]; then
            echo -e "  ${YELLOW}[AVISO]${NC} start_servidor.sh no encontrado."
            echo -n "  ¿Reparar scripts ahora? (s/n): "
            read -r _REPAIR < /dev/tty
            [ "$_REPAIR" = "s" ] || [ "$_REPAIR" = "S" ] \
              && { _n8n_repair_scripts "$_MODE"; echo ""; } \
              || { echo ""; read -r _ < /dev/tty; continue; }
          fi
          [ -f "$N8N_SCRIPTS/start_servidor.sh" ] \
            && bash "$N8N_SCRIPTS/start_servidor.sh" < /dev/tty \
            || echo -e "  ${RED}[ERROR]${NC} start_servidor.sh no disponible"
        fi
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        if [ "$_MODE" = "udocker" ]; then
          bash "$N8N_SCRIPTS_UDOCKER/stop.sh" 2>/dev/null
        else
          bash "$N8N_SCRIPTS/stop_servidor.sh" 2>/dev/null || \
            tmux kill-session -t "n8n-server" 2>/dev/null
        fi
        sleep 1; echo -e "  ${GREEN}[OK]${NC} n8n detenido"
        echo ""; read -r _ < /dev/tty ;;
       3)
        clear; echo ""
        if $_IS_RUNNING; then
          echo -e "  ${GREEN}[OK]${NC} n8n ya está activo. Abriendo localhost..."; echo ""
        else
          echo -e "  ${CYAN}[...]${NC} Iniciando n8n (localhost, sin tunnel)..."; echo ""
          if [ "$_MODE" = "udocker" ]; then
            if [ -f "$N8N_SCRIPTS_UDOCKER/start_local.sh" ]; then
              bash "$N8N_SCRIPTS_UDOCKER/start_local.sh"
            else
              echo -e "  ${YELLOW}[AVISO]${NC} start_local.sh no encontrado."
              echo -n "  ¿Reparar scripts ahora? (s/n): "
              read -r _REPAIR < /dev/tty
              if [ "$_REPAIR" = "s" ] || [ "$_REPAIR" = "S" ]; then
                _n8n_repair_scripts "$_MODE"; echo ""
              fi
              [ -f "$N8N_SCRIPTS_UDOCKER/start_local.sh" ] && bash "$N8N_SCRIPTS_UDOCKER/start_local.sh"
            fi
          else
            if [ -f "$N8N_SCRIPTS/start_local.sh" ]; then
              bash "$N8N_SCRIPTS/start_local.sh"
            else
              echo -e "  ${YELLOW}[AVISO]${NC} start_local.sh no encontrado."
              echo -n "  ¿Reparar scripts ahora? (s/n): "
              read -r _REPAIR < /dev/tty
              if [ "$_REPAIR" = "s" ] || [ "$_REPAIR" = "S" ]; then
                _n8n_repair_scripts "$_MODE"; echo ""
              fi
              [ -f "$N8N_SCRIPTS/start_local.sh" ] && bash "$N8N_SCRIPTS/start_local.sh"
            fi
          fi
        fi
        local _LOC_IP; _LOC_IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        echo -e "  ${BOLD}Acceso local (sin cloudflare):${NC}"; echo ""
        echo -e "  ${GREEN}Teléfono:${NC} http://localhost:5678"
        [ -n "$_LOC_IP" ] && echo -e "  ${GREEN}WiFi PC: ${NC} http://${_LOC_IP}:5678"
        echo ""
        termux-open-url "http://localhost:5678" 2>/dev/null || true
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        local _CF_URL
        _CF_URL=$(cat "$HOME/.last_cf_url" 2>/dev/null)
        if [ -n "$_CF_URL" ]; then
          echo -e "  ${GREEN}URL pública:${NC} ${_CF_URL}"
        elif [ "$_MODE" = "udocker" ]; then
          _CF_URL=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" "$HOME/.cf_ud_url.log" 2>/dev/null | head -1)
          if [ -n "$_CF_URL" ]; then
            echo -e "  ${GREEN}URL pública:${NC} ${_CF_URL}"
          else
            echo -e "  ${YELLOW}[AVISO]${NC} Tunnel no activo — inicia con [1]"
          fi
        else
          bash "$N8N_SCRIPTS/ver_url.sh" 2>/dev/null || \
            echo -e "  ${YELLOW}[AVISO]${NC} URL no disponible — inicia con [1]"
        fi
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        echo -e "  ${CYAN}Logs n8n — Ctrl+B D para salir sin detener${NC}"; echo ""
        tmux has-session -t "$_SESSION" 2>/dev/null \
          && tmux attach-session -t "$_SESSION" \
          || echo -e "  ${YELLOW}[AVISO]${NC} n8n no está corriendo"
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        if [ "$_MODE" = "udocker" ]; then
          bash "$N8N_SCRIPTS_UDOCKER/status.sh" 2>/dev/null || {
            echo -e "  ${BOLD}Estado n8n (udocker):${NC}"; echo ""
            $_IS_RUNNING \
              && echo -e "  ${GREEN}● Corriendo${NC} — sesión: n8n-udocker" \
              || echo -e "  ${YELLOW}○ Detenido${NC}"
            local _SIP; _SIP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
            echo -e "  Puerto: 5678"
            [ -n "$_SIP" ] && echo -e "  WiFi:   http://${_SIP}:5678"
          }
        else
          bash "$N8N_SCRIPTS/n8n_status.sh" 2>/dev/null || {
            echo -e "  ${BOLD}Estado n8n (proot):${NC}"; echo ""
            $_IS_RUNNING \
              && echo -e "  ${GREEN}● Corriendo${NC} — sesión: n8n-server" \
              || echo -e "  ${YELLOW}○ Detenido${NC}"
          }
        fi
        echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        if [ "$_MODE" = "udocker" ]; then
          bash "$N8N_SCRIPTS_UDOCKER/update.sh" 2>/dev/null || {
            echo -e "  ${CYAN}Actualizando n8n (udocker)...${NC}"; echo ""
            tmux kill-session -t "n8n-udocker" 2>/dev/null || true
            udocker pull n8nio/n8n && {
              udocker rm n8n 2>/dev/null || true
              udocker create --name=n8n n8nio/n8n
              echo -e "  ${GREEN}[OK]${NC} n8n actualizado — usa [1] para iniciar"
            }
          }
        else
          bash "$N8N_SCRIPTS/n8n_update.sh" 2>/dev/null || {
            echo -e "  ${CYAN}Actualizando n8n (proot)...${NC}"; echo ""
            local _DN; _DN=$(proot-distro list 2>/dev/null | grep -E "^\s*\*?\s*(debian|ubuntu)" | awk '{print $NF}' | head -1)
            [ -z "$_DN" ] && _DN="debian"
            proot-distro login "$_DN" -- bash -c \
              'export HOME=/root && npm update -g n8n && echo "n8n: $(n8n --version)"'
          }
        fi
        echo ""; read -r _ < /dev/tty ;;
      8)
        clear; echo ""
        echo -e "  ${CYAN}Backup workflows${NC}"; echo ""
        if [ "$_MODE" = "udocker" ]; then
          bash "$N8N_SCRIPTS_UDOCKER/backup.sh" 2>/dev/null || \
            echo -e "  ${YELLOW}[AVISO]${NC} Script backup no encontrado"
        else
          bash "$N8N_SCRIPTS/n8n_backup.sh" 2>/dev/null || \
            echo -e "  ${YELLOW}[AVISO]${NC} Script backup no encontrado"
        fi
        echo ""; read -r _ < /dev/tty ;;
      9)
        while true; do
          clear; echo ""
          echo -e "  ${CYAN}${BOLD}╔══════════════════════════════════════════╗"
          echo    "  ║  Token CF + Dominio webhook            ║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"
          echo ""
          local _CF_CUR _DOM_CUR
          _CF_CUR=$(cat "$HOME/.cf_token" 2>/dev/null)
          _DOM_CUR=$(grep "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" 2>/dev/null | cut -d'=' -f2)
          [ -n "$_CF_CUR" ] \
            && echo -e "  Token CF:   ${GREEN}configurado ✓${NC}" \
            || echo -e "  Token CF:   ${YELLOW}no configurado (URL temporal)${NC}"
          [ -n "$_DOM_CUR" ] \
            && echo -e "  Dominio:    ${GREEN}${_DOM_CUR}${NC}" \
            || echo -e "  Dominio:    ${YELLOW}no configurado${NC}"
          echo ""
          echo -e "  [t]  Cambiar token cloudflared"
          echo -e "  [d]  Configurar dominio webhook"
          echo -e "  [b]  Volver"
          echo ""; echo -n "  Opción: "
          read -r _C9OPT < /dev/tty
          case "$_C9OPT" in
            t|T)
              echo ""
              echo -e "  ${DIM}Obtén token en: dash.cloudflare.com → Zero Trust → Tunnels${NC}"
              echo -n "  Nuevo token (ENTER = borrar): "
              read -r _NEW_CF < /dev/tty
              if [ -n "$_NEW_CF" ]; then
                echo "$_NEW_CF" > "$HOME/.cf_token"
                chmod 600 "$HOME/.cf_token"
                echo -e "  ${GREEN}[OK]${NC} Token guardado — URL fija activada"
              else
                rm -f "$HOME/.cf_token"
                echo -e "  ${YELLOW}[OK]${NC} Token eliminado — modo URL temporal"
              fi
              read -r _ < /dev/tty ;;
            d|D)
              echo ""
              echo -e "  ${DIM}Ej: https://n8n.tudominio.com${NC}"
              echo -n "  URL del dominio webhook (ENTER = cancelar): "
              read -r _NEW_DOM < /dev/tty
              if [ -n "$_NEW_DOM" ]; then
                grep -v "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" > "$HOME/.env_n8n.tmp" 2>/dev/null || \
                  touch "$HOME/.env_n8n.tmp"
                echo "N8N_WEBHOOK_URL=${_NEW_DOM}" >> "$HOME/.env_n8n.tmp"
                mv "$HOME/.env_n8n.tmp" "$HOME/.env_n8n"
                echo "$_NEW_DOM" > "$HOME/.last_cf_url"
                echo -e "  ${GREEN}[OK]${NC} Dominio guardado: ${_NEW_DOM}"
                echo -e "  ${DIM}Reinicia n8n para aplicar.${NC}"
              fi
              read -r _ < /dev/tty ;;
            b|B|"") break ;;
          esac
        done ;;
      r|R)
        clear; echo ""
        _n8n_repair_scripts "$_MODE"
        echo ""; read -r _ < /dev/tty ;;
      p|P)
        [ "$_MODE" != "proot" ] && continue
        clear; echo ""
        echo -e "  ${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
        echo    "  ║  ⬡ N8N — Protocolo                      ║"
        echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""
        local _PROTO_ACTUAL
        _PROTO_ACTUAL=$(cat "$HOME/.n8n_protocol" 2>/dev/null || echo "https")
        echo -e "  Protocolo actual: ${GREEN}${_PROTO_ACTUAL}${NC}"; echo ""
        echo -e "  [1] HTTPS  ${DIM}(cloudflared, producción)${NC}"
        echo -e "  [2] HTTP   ${DIM}(LAN directo, debug, sin SSL)${NC}"; echo ""
        echo -n "  Opción (ENTER = cancelar): "
        read -r _PROTO_OPT < /dev/tty
        case "$_PROTO_OPT" in
          1) echo "https" > "$HOME/.n8n_protocol"; echo -e "  ${GREEN}[OK]${NC} Protocolo → HTTPS. Repara scripts y reinicia." ;;
          2) echo "http" > "$HOME/.n8n_protocol"; echo -e "  ${GREEN}[OK]${NC} Protocolo → HTTP. Repara scripts y reinicia." ;;
          *) echo -e "  ${YELLOW}[AVISO]${NC} Sin cambios." ;;
        esac
        echo ""; read -r _ < /dev/tty ;;
      c|C)
        if $_HAS_PROOT && $_HAS_UDOCKER; then
          [ "$_MODE" = "proot" ] && _MODE="udocker" || _MODE="proot"
          # Persistir el modo activo — si no, al volver a entrar al
          # submenú siempre se recae en el que diga el registry
          grep -v "^n8n\.mode=" "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
          echo "n8n.mode=$_MODE" >> "$REGISTRY"
          continue
        fi ;;
      i|I)
        clear; echo ""
        echo -e "  ${CYAN}Reinstalar n8n${NC}"; echo ""
        echo -e "  Modo actual: ${GREEN}$_MODE${NC}"; echo ""
        echo -n "  ¿Reinstalar? (s/n): "
        read -r _REINST < /dev/tty
        if [ "$_REINST" = "s" ] || [ "$_REINST" = "S" ]; then
          [ "$_MODE" = "udocker" ] \
            && _run_installer "install_n8n.sh" "n8n udocker" N8N_INSTALL_MODE=2 \
            || _run_installer "install_n8n.sh" "n8n proot" N8N_INSTALL_MODE=1
          echo ""; read -r _ < /dev/tty
        fi ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  HELPERS OPENCLAW
# ════════════════════════════════════════════
_cl_get_token() {
  proot-distro login "$DISTRO_NAME" -- bash -c \
    "python3 -c \"
import json, sys
try:
    d=json.load(open('/root/.openclaw/openclaw.json'))
    print(d['gateway']['auth']['token'])
except Exception:
    print('')
\"" 2>/dev/null | tr -d '[:space:]'
}

_cl_status() {
  curl -sf http://127.0.0.1:18789 &>/dev/null && echo "running" || echo "stopped"
}

_cl_start() {
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'export HOME=/root; export NVM_DIR="/root/.nvm"
     [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
     openclaw gateway --bind loopback' > "$HOME/.openclaw_gateway.log" 2>&1 &
  echo $! > "$HOME/.openclaw_gateway.pid"
}

_cl_stop() {
  proot-distro login "$DISTRO_NAME" -- bash -c \
    'pkill -TERM -f "node.*openclaw" 2>/dev/null
     pkill -TERM -f "openclaw gateway" 2>/dev/null
     sleep 2
     pkill -KILL -f "node.*openclaw" 2>/dev/null || true
     pkill -KILL -f "openclaw" 2>/dev/null || true' 2>/dev/null || true
  pkill -f "openclaw" 2>/dev/null || true
  rm -f "$HOME/.openclaw_gateway.pid"
}

_cl_open_browser() {
  local token="$1"
  local url="http://127.0.0.1:18789/#token=${token}"
  echo -e "  Abre manualmente en Brave o Chrome:"
  echo -e "  ${CYAN}$url${NC}"
}

# ════════════════════════════════════════════
#  SUBMENÚ OPENCLAW
# ════════════════════════════════════════════
submenu_openclaw() {
  local CL_PROJ_DIR="$HOME/proyectos"
  while true; do
    clear; echo ""
    local _CL_ST; _CL_ST=$(_cl_status)
    local CL_STATUS CL_URL_LINE
    case "$_CL_ST" in
      running) CL_STATUS="${GREEN}● activo :18789${NC}"; CL_URL_LINE="  http://127.0.0.1:18789" ;;
      *)       CL_STATUS="detenido";                     CL_URL_LINE="" ;;
    esac

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  🦞 OPENCLAW                            ║"
    echo    "  ╠══════════════════════════════════════════╣"
    printf  "  ║  ${NC}Gateway: %-32b${CYAN}${BOLD}║\n" "$CL_STATUS"
    [ -n "$CL_URL_LINE" ] && printf "  ║  ${GREEN}%-40s${CYAN}${BOLD}║\n" "$CL_URL_LINE"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Iniciar gateway                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Abrir dashboard web (:18789)       ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] TUI — no soportado en proot        ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Abrir en proyecto                  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5] Gestionar proyectos                ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6] Detener gateway                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[7] Cambiar proveedor IA               ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[i] Migrar a nativo                     ${CYAN}${BOLD}║"
    echo -e "  ║  ${DIM}    glibc+npm · recomendada             ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver                             ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        if curl -sf http://127.0.0.1:18789 &>/dev/null; then
          local TOKEN; TOKEN=$(_cl_get_token)
          echo -e "  ${GREEN}[OK]${NC} Gateway ya corriendo"; echo ""
          [ -n "$TOKEN" ] && {
            echo -e "  ${CYAN}http://127.0.0.1:18789/#token=${TOKEN}${NC}"; echo ""
            echo -n "  ¿Abrir browser? (s/n): "
            read -r _OB < /dev/tty
            [ "$_OB" = "s" ] || [ "$_OB" = "S" ] && _cl_open_browser "$TOKEN"
          }
        else
          echo -e "  ${CYAN}[+] Iniciando OpenClaw Gateway...${NC}"
          echo -e "  ${DIM}Espera ~30-60 segundos en ARM64${NC}"; echo ""
          _cl_start
          local TRIES=0
          while [ $TRIES -lt 30 ]; do
            sleep 2; curl -sf http://127.0.0.1:18789 &>/dev/null && break
            TRIES=$((TRIES+1)); echo -n "."
          done; echo ""
          if curl -sf http://127.0.0.1:18789 &>/dev/null; then
            local TOKEN; TOKEN=$(_cl_get_token)
            echo -e "  ${GREEN}[OK]${NC} Gateway iniciado"; echo ""
            if [ -n "$TOKEN" ]; then
              echo -e "  URL con token:"
              echo -e "  ${CYAN}http://127.0.0.1:18789/#token=${TOKEN}${NC}"; echo ""
              echo -e "  ${DIM}Usa [2] para abrir en el browser${NC}"
            else
              echo -e "  ${CYAN}http://127.0.0.1:18789${NC}"
              echo -e "  ${YELLOW}[AVISO]${NC} Token no encontrado — usa [8] para setup"
            fi
          else
            echo -e "  ${RED}[ERROR]${NC} No respondió — revisa: cat ~/.openclaw_gateway.log"
          fi
        fi
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        if ! curl -sf http://127.0.0.1:18789 &>/dev/null; then
          echo -e "  ${YELLOW}[AVISO]${NC} Gateway no está corriendo — usa [1] primero"
          echo ""; read -r _ < /dev/tty; continue
        fi
        local TOKEN; TOKEN=$(_cl_get_token)
        [ -n "$TOKEN" ] && {
          echo -e "  ${CYAN}http://127.0.0.1:18789/#token=${TOKEN}${NC}"; echo ""
          _cl_open_browser "$TOKEN"
        } || echo -e "  Abre: ${CYAN}http://127.0.0.1:18789${NC}"
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        echo -e "  ${YELLOW}[AVISO]${NC} La TUI en terminal no está soportada en proot"
        echo -e "  El input del teclado no llega correctamente al proceso."
        echo ""
        echo -e "  ${CYAN}Alternativa recomendada:${NC}"
        echo -e "  Usa [2] para abrir OpenClaw en el browser — funciona perfectamente."
        echo ""
        echo -e "  ${DIM}Nota técnica: proot-distro no pasa el TTY correctamente${NC}"
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        mkdir -p "$CL_PROJ_DIR"
        mapfile -t PROJS < <(ls -1 "$CL_PROJ_DIR/" 2>/dev/null)
        echo -e "  ${CYAN}Proyectos en ~/proyectos/:${NC}"; echo ""
        local IDX=1
        [ ${#PROJS[@]} -gt 0 ] \
          && for p in "${PROJS[@]}"; do printf "    [%d] %s\n" "$IDX" "$p"; IDX=$((IDX+1)); done \
          || echo "    (ninguno — usa [5] para agregar)"
        echo ""; echo "    [m] Ruta manual  [b] Volver"
        echo ""; echo -n "  Elige: "
        read -r PCHOICE < /dev/tty
        local TARGET_DIR=""
        case "$PCHOICE" in
          m|M) echo -n "  Ruta: "; read -r TARGET_DIR < /dev/tty ;;
          b|B|"") continue ;;
          *) [[ "$PCHOICE" =~ ^[0-9]+$ ]] && [ "$PCHOICE" -ge 1 ] && \
             [ "$PCHOICE" -le "${#PROJS[@]}" ] && \
             TARGET_DIR="$CL_PROJ_DIR/${PROJS[$((PCHOICE-1))]}" ;;
        esac
        [ -z "$TARGET_DIR" ] && continue
        [ ! -d "$TARGET_DIR" ] && {
          echo -e "  ${RED}[ERROR]${NC} No existe: $TARGET_DIR"
          echo ""; read -r _ < /dev/tty; continue
        }
        local REAL_PATH
        REAL_PATH=$(readlink -f "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")
        REAL_PATH="${REAL_PATH/\/storage\/emulated\/0/\/sdcard}"
        REAL_PATH="${REAL_PATH/${HOME}/\/termux-home}"
        echo ""; echo -e "  ${CYAN}Proyecto:${NC} $(basename "$TARGET_DIR")"
        echo "  [1] Gateway web  [2] TUI"
        echo ""; echo -n "  Modo: "
        read -r MODO < /dev/tty
        case "$MODO" in
          1)
            local TOKEN; TOKEN=$(_cl_get_token)
            [ -n "$TOKEN" ] && _cl_open_browser "$TOKEN" || \
              echo -e "  Abre: ${CYAN}http://127.0.0.1:18789${NC}"
            echo ""; read -r _ < /dev/tty ;;
          2)
            _proot_sdcard_login "$REAL_PATH" bash -c \
              "export HOME=/root; export NVM_DIR=\"/root/.nvm\"
               [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
               export NODE_OPTIONS=\"--require /root/openclaw-shim.cjs\"
               openclaw tui --cwd '${REAL_PATH}'" < /dev/tty
            echo ""; read -r _ < /dev/tty ;;
        esac ;;
      5)
        while true; do
          clear; echo ""
          echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
          echo    "  ║  🦞 OPENCLAW — Proyectos               ║"
          echo    "  ╠══════════════════════════════════════════╣"
          echo -e "  ║  ${NC}[1] Listar  [2] Nuevo symlink  [3] Borrar${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[b] Volver${CYAN}${BOLD}                             ║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"
          echo ""; echo -n "  Opción: "
          read -r GOPT < /dev/tty
          case "$GOPT" in
            1)
              clear; echo ""
              ls -la "$CL_PROJ_DIR/" 2>/dev/null | grep -v "^total" || \
                echo -e "  ${DIM}(vacío)${NC}"
              echo ""; read -r _ < /dev/tty ;;
            2)
              clear; echo ""
              mapfile -t DL_DIRS < <(find /storage/emulated/0/Download \
                -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -I{} basename {})
              [ ${#DL_DIRS[@]} -eq 0 ] && {
                echo -e "  ${YELLOW}Sin carpetas en Download${NC}"
                read -r _ < /dev/tty; continue
              }
              for i in "${!DL_DIRS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${DL_DIRS[$i]}"; done
              echo ""; echo -n "  Número: "; read -r DCHOICE < /dev/tty
              [[ "$DCHOICE" =~ ^[0-9]+$ ]] && [ "$DCHOICE" -ge 1 ] && \
              [ "$DCHOICE" -le "${#DL_DIRS[@]}" ] && {
                mkdir -p "$CL_PROJ_DIR"
                ln -sf "/storage/emulated/0/Download/${DL_DIRS[$((DCHOICE-1))]}" \
                  "$CL_PROJ_DIR/${DL_DIRS[$((DCHOICE-1))]}" \
                  && echo -e "  ${GREEN}[OK]${NC} Symlink creado" \
                  || echo -e "  ${RED}[ERROR]${NC}"
              }
              echo ""; read -r _ < /dev/tty ;;
            3)
              clear; echo ""
              mapfile -t LINKS < <(find "$CL_PROJ_DIR" -maxdepth 1 -type l 2>/dev/null \
                | xargs -I{} basename {})
              [ ${#LINKS[@]} -eq 0 ] && {
                echo -e "  ${DIM}Sin symlinks${NC}"; read -r _ < /dev/tty; continue
              }
              for i in "${!LINKS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${LINKS[$i]}"; done
              echo ""; echo -n "  Número: "; read -r LCHOICE < /dev/tty
              [[ "$LCHOICE" =~ ^[0-9]+$ ]] && [ "$LCHOICE" -ge 1 ] && \
              [ "$LCHOICE" -le "${#LINKS[@]}" ] && {
                echo -n "  ¿Eliminar? (s/n): "; read -r LCONF < /dev/tty
                [ "$LCONF" = "s" ] || [ "$LCONF" = "S" ] && {
                  rm "$CL_PROJ_DIR/${LINKS[$((LCHOICE-1))]}" \
                    && echo -e "  ${GREEN}[OK]${NC} Eliminado" \
                    || echo -e "  ${RED}[ERROR]${NC}"
                }
              }
              echo ""; read -r _ < /dev/tty ;;
            b|B|"") break ;;
          esac
        done ;;
      6)
        clear; echo ""
        if ! curl -sf http://127.0.0.1:18789 &>/dev/null; then
          echo -e "  ${YELLOW}[AVISO]${NC} Gateway ya estaba detenido"
          echo ""; read -r _ < /dev/tty; continue
        fi
        echo -e "  ${CYAN}[+] Deteniendo OpenClaw...${NC}"; echo ""
        _cl_stop
        local TRIES=0
        while [ $TRIES -lt 5 ]; do
          sleep 2
          curl -sf http://127.0.0.1:18789 &>/dev/null || break
          TRIES=$((TRIES+1)); echo -n "."
        done; echo ""
        curl -sf http://127.0.0.1:18789 &>/dev/null \
          && echo -e "  ${RED}[ERROR]${NC} Gateway aún responde — intenta de nuevo" \
          || echo -e "  ${GREEN}[OK]${NC} Gateway detenido"
        echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        echo -e "  ${CYAN}Cambiar proveedor IA de OpenClaw${NC}"; echo ""
        echo -e "  ${BOLD}[1]${NC} Configurar via wizard (recomendado)"
        echo -e "  ${DIM}    Lanza: openclaw configure${NC}"; echo ""
        echo -e "  ${BOLD}[2]${NC} Configurar Ollama local rápido"
        echo -e "  ${DIM}    Detecta modelos y configura automáticamente${NC}"; echo ""
        echo -e "  ${BOLD}[b]${NC} Volver"
        echo ""; echo -n "  Opción: "
        read -r POPT < /dev/tty
        case "$POPT" in
          1)
            echo ""
            echo -e "  ${CYAN}Lanzando openclaw configure...${NC}"
            echo -e "  ${DIM}Selecciona el provider con las flechas y Enter${NC}"; echo ""
            proot-distro login "$DISTRO_NAME" -- bash -c \
              'export HOME=/root; export NVM_DIR="/root/.nvm"
               [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
               export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
               openclaw configure' < /dev/tty
            echo ""
            echo -e "  ${DIM}Reinicia el gateway [6]→[1] para aplicar cambios${NC}" ;;
          2)
            if ! curl -sf http://127.0.0.1:11434 &>/dev/null; then
              echo -e "  ${YELLOW}[AVISO]${NC} Ollama no responde — inícialo desde [3] primero"
              echo ""; read -r _ < /dev/tty; continue
            fi
            local MODELS_RAW; MODELS_RAW=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
            [ -z "$MODELS_RAW" ] && {
              echo -e "  ${YELLOW}Sin modelos descargados${NC} — usa [3] → Ollama → [5]"
              echo ""; read -r _ < /dev/tty; continue
            }
            echo ""
            mapfile -t MODELS <<< "$MODELS_RAW"
            for i in "${!MODELS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${MODELS[$i]}"; done
            echo ""; echo -n "  Elige modelo: "
            read -r MCHOICE < /dev/tty
            if [[ "$MCHOICE" =~ ^[0-9]+$ ]] && [ "$MCHOICE" -ge 1 ] && \
               [ "$MCHOICE" -le "${#MODELS[@]}" ]; then
              local CHOSEN_MODEL="${MODELS[$((MCHOICE-1))]}"
              proot-distro login "$DISTRO_NAME" -- bash -c \
                "python3 -c \"
import json
cfg_path='/root/.openclaw/openclaw.json'
try:
    cfg=json.load(open(cfg_path))
except Exception:
    cfg={}
cfg.setdefault('models',{}).setdefault('providers',{})['ollama']={
    'baseUrl':'http://127.0.0.1:11434','api':'ollama','apiKey':'OLLAMA_API_KEY',
    'models':[{'id':'${CHOSEN_MODEL}','name':'${CHOSEN_MODEL}','reasoning':False,
               'input':['text'],'cost':{'input':0,'output':0,'cacheRead':0,'cacheWrite':0},
               'contextWindow':32768,'maxTokens':8192}]}
json.dump(cfg,open(cfg_path,'w'),indent=2)
print('OK')
\"" 2>/dev/null
              echo -e "  ${GREEN}[OK]${NC} Ollama/${CHOSEN_MODEL} configurado"
              echo -e "  ${DIM}Reinicia el gateway para aplicar${NC}"
            else
              echo -e "  ${YELLOW}Cancelado${NC}"
            fi ;;
        esac
        echo ""; read -r _ < /dev/tty ;;
      i|I)
        # Migrar a nativo — install_openclaw.sh ya es solo nativo,
        # no pregunta modo (2026-07-26, antes sí lo hacía)
        clear; echo ""
        echo -e "  ${CYAN}[+] Instalando OpenClaw nativo (glibc + npm)...${NC}"; echo ""
        _ensure_install_script "install_openclaw.sh" || { read -r _ < /dev/tty; continue; }
        _run_installer "install_openclaw.sh" "OpenClaw (nativo)"
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  HELPERS OPENCODE
# ════════════════════════════════════════════
_oc_web_stop() {
  [ -f "$HOME/.opencode_web.pid" ] && {
    kill "$(cat "$HOME/.opencode_web.pid")" 2>/dev/null
    rm -f "$HOME/.opencode_web.pid"
  }
  pkill -f "opencode web" 2>/dev/null
  tmux kill-session -t "oc-web" 2>/dev/null
  echo -e "  ${GREEN}[OK]${NC} Servidor detenido"
}

_oc_web_status() {
  curl -sf http://127.0.0.1:3000 &>/dev/null && echo "running" || echo "stopped"
}

# ════════════════════════════════════════════
#  SUBMENÚ OPENCODE
# ════════════════════════════════════════════
submenu_opencode() {
  local OC_PROJ_DIR="$HOME/proyectos"
  while true; do
    clear; echo ""
    local _OC_ST; _OC_ST=$(_oc_web_status)
    local OC_STATUS OC_URL_LINE
    case "$_OC_ST" in
      running) OC_STATUS="${GREEN}● activo${NC}";  OC_URL_LINE="  http://127.0.0.1:3000" ;;
      *)       OC_STATUS="detenido";               OC_URL_LINE="" ;;
    esac

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ◆ OPENCODE                             ║"
    echo    "  ╠══════════════════════════════════════════╣"
    printf  "  ║  ${NC}Web: %-35b${CYAN}${BOLD}║\n" "$OC_STATUS"
    [ -n "$OC_URL_LINE" ] && printf "  ║  ${GREEN}%-40s${CYAN}${BOLD}║\n" "$OC_URL_LINE"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1] Abrir en TUI (terminal)            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2] Iniciar servidor web (:3000)       ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3] Abrir proyecto (TUI o web)         ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4] Gestionar proyectos                ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5] Detener servidor web               ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6] Instalar / actualizar              ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[7] Configurar Ollama local            ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b] Volver                             ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty


# ── Fix B2: pre-instalar paquetes npm de providers antes de lanzar opencode ──
# La UI web escribe providers con campo "npm". Si no están instalados → crash.
_oc_ensure_providers() {
  proot-distro login "$DISTRO_NAME" -- bash -c '
export HOME=/root
CFG="/root/.config/opencode/opencode.json"
[ -f "$CFG" ] || exit 0
PKGS=$(python3 - << PYEOF 2>/dev/null
import json
try:
  d = json.load(open("/root/.config/opencode/opencode.json"))
  pkgs = [v["npm"] for v in d.get("provider", {}).values() if "npm" in v]
  print(" ".join(pkgs))
except: pass
PYEOF
)
[ -z "$PKGS" ] && exit 0
for pkg in $PKGS; do
  node -e "require(\"$pkg\")" 2>/dev/null || \
    npm install -g "$pkg" --quiet 2>/dev/null || true
done
' 2>/dev/null || true
}

# ── Fix CWD: forzar el proyecto correcto en opencode antes de lanzar ─────────
# OpenCode persiste el último proyecto en ~/.local/share/opencode/recent.json
# Independientemente del cwd de lanzamiento, opencode reabre ese proyecto.
# Solución: escribir la ruta del proyecto actual en el archivo de recientes
# ANTES de lanzar, para que opencode lo cargue como proyecto activo.
# RUTA dentro del proot: se pasa como argumento $1
_oc_set_project() {
  local proot_path="$1"
  [ -z "$proot_path" ] && return 0
  proot-distro login "$DISTRO_NAME" -- bash -c '
export HOME=/root
RECENT_DIR="/root/.local/share/opencode"
RECENT_FILE="$RECENT_DIR/recent.json"
mkdir -p "$RECENT_DIR"
python3 - << PYEOF 2>/dev/null
import json, os, sys
path = sys.argv[1] if len(sys.argv) > 1 else ""
if not path:
    sys.exit(0)
f = os.environ.get("RECENT_FILE", "/root/.local/share/opencode/recent.json")
try:
    data = json.load(open(f))
except:
    data = {"recent": []}
# Poner el proyecto actual primero, eliminar duplicados
projects = [path] + [p for p in data.get("recent", []) if p != path]
data["recent"] = projects[:10]
json.dump(data, open(f, "w"), indent=2)
PYEOF
' "$proot_path" 2>/dev/null || true
}

    case "$OPT" in
      1)
        clear; echo ""
        echo -e "  ${CYAN}Abriendo OpenCode TUI en Debian...${NC}"
        echo -e "  ${DIM}Ctrl+C para salir${NC}"; echo ""
        _oc_ensure_providers
        proot-distro login "$DISTRO_NAME" -- bash -c \
          'export HOME=/root
           export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
           opencode' < /dev/tty
        echo ""; read -r _ < /dev/tty ;;
      2)
        clear; echo ""
        if curl -sf http://127.0.0.1:3000 &>/dev/null; then
          echo -e "  ${GREEN}[OK]${NC} Servidor ya corriendo"
          echo -e "  ${GREEN}URL:${NC} http://127.0.0.1:3000"
        else
          pkill -f "opencode web" 2>/dev/null; sleep 1
          echo -e "  ${CYAN}Iniciando OpenCode Web...${NC}"
          echo -e "  ${DIM}Cuando veas la URL presiona ENTER para volver al menú${NC}"
          echo -e "  ${DIM}El servidor quedará corriendo en background${NC}"; echo ""
          _oc_ensure_providers
          proot-distro login "$DISTRO_NAME" -- bash -c \
            'export HOME=/root
             export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
             opencode web --port 3000 --hostname 127.0.0.1' &
          echo $! > "$HOME/.opencode_web.pid"
          echo ""
          echo -n "  Presiona ENTER cuando veas 'Web interface: http://127.0.0.1:3000'..."
          read -r _ < /dev/tty
          echo ""; echo -e "  ${GREEN}URL:${NC} http://127.0.0.1:3000"
          echo -e "  ${DIM}Abre en Brave o Chrome${NC}"
        fi
        echo ""; read -r _ < /dev/tty ;;
      3)
        clear; echo ""
        mkdir -p "$OC_PROJ_DIR"
        mapfile -t PROJS < <(ls -1 "$OC_PROJ_DIR/" 2>/dev/null)
        echo -e "  ${CYAN}Proyectos en ~/proyectos/:${NC}"; echo ""
        local IDX=1
        [ ${#PROJS[@]} -gt 0 ] \
          && for p in "${PROJS[@]}"; do printf "    [%d] %s\n" "$IDX" "$p"; IDX=$((IDX+1)); done \
          || echo "    (ninguno — usa [4] para agregar)"
        echo ""; echo "    [m] Ruta manual  [b] Volver"
        echo ""; echo -n "  Elige proyecto: "
        read -r PCHOICE < /dev/tty
        local TARGET_DIR=""
        case "$PCHOICE" in
          m|M) echo -n "  Ruta: "; read -r TARGET_DIR < /dev/tty ;;
          b|B|"") continue ;;
          *)
            [[ "$PCHOICE" =~ ^[0-9]+$ ]] && [ "$PCHOICE" -ge 1 ] && \
            [ "$PCHOICE" -le "${#PROJS[@]}" ] && \
              TARGET_DIR="$OC_PROJ_DIR/${PROJS[$((PCHOICE-1))]}" ;;
        esac
        [ -z "$TARGET_DIR" ] && continue
        [ ! -d "$TARGET_DIR" ] && {
          echo -e "  ${RED}[ERROR]${NC} No existe: $TARGET_DIR"
          echo ""; read -r _ < /dev/tty; continue
        }
        # Ruta real en el host Android (para mensajes y _oc_set_project)
        local HOST_PROJECT
        HOST_PROJECT=$(readlink -f "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")
        # Ruta dentro del proot (/storage/emulated/0 → /sdcard via proot-distro)
        local PROOT_PATH="$HOST_PROJECT"
        PROOT_PATH="${PROOT_PATH/\/storage\/emulated\/0/\/sdcard}"
        PROOT_PATH="${PROOT_PATH/${HOME}/\/termux-home}"
        echo ""
        echo -e "  ${CYAN}Proyecto:${NC} $(basename "$TARGET_DIR")"
        echo -e "  ${DIM}cwd: $PROOT_PATH${NC}"; echo ""
        echo "  [1] TUI  — interfaz en terminal"
        echo "  [2] Web  — servidor en :3000"
        echo ""; echo -n "  Modo: "
        read -r MODO < /dev/tty
        case "$MODO" in
          1)
            echo ""
            _oc_ensure_providers
            _oc_set_project "$PROOT_PATH"
            _proot_sdcard_login "$PROOT_PATH" bash -c \
              "export HOME=/root
               export PATH='/root/.local/bin:/usr/local/bin:/usr/bin:/bin'
               cd '$PROOT_PATH' && opencode ." < /dev/tty
            echo ""; read -r _ < /dev/tty ;;
          2)
            pkill -f "opencode web" 2>/dev/null; sleep 1
            echo ""
            echo -e "  ${CYAN}Iniciando servidor en proyecto...${NC}"
            echo -e "  ${DIM}Proyecto: $(basename "$TARGET_DIR")${NC}"
            echo -e "  ${DIM}Cuando veas la URL presiona ENTER${NC}"; echo ""
            _oc_ensure_providers
            _oc_set_project "$PROOT_PATH"
            _proot_sdcard_login "$PROOT_PATH" bash -c \
              "export HOME=/root
               export PATH='/root/.local/bin:/usr/local/bin:/usr/bin:/bin'
               cd '$PROOT_PATH' && opencode web --port 3000 --hostname 127.0.0.1" &
            echo $! > "$HOME/.opencode_web.pid"
            echo ""
            echo -n "  Presiona ENTER cuando veas 'Web interface: http://127.0.0.1:3000'..."
            read -r _ < /dev/tty
            echo -e "  ${GREEN}URL:${NC} http://127.0.0.1:3000"
            echo ""; read -r _ < /dev/tty ;;
          *) continue ;;
        esac ;;
      4)
        while true; do
          clear; echo ""
          echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
          echo    "  ║  ◆ OPENCODE — Proyectos                 ║"
          echo    "  ╠══════════════════════════════════════════╣"
          echo -e "  ║  ${NC}[1] Listar proyectos                  ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[2] Symlink → Android (proot/nativo)  ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[3] Copiar  → Android (glibc)         ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[4] Crear proyecto vacío              ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[5] Eliminar proyecto                 ${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[b] Volver${CYAN}${BOLD}                             ║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"
          echo ""; echo -n "  Opción: "
          read -r GOPT < /dev/tty
          case "$GOPT" in
            1)
              # ── Listar proyectos ────────────────────────────────────────
              clear; echo ""
              echo -e "  ${BOLD}~/proyectos/:${NC}"; echo ""
              mkdir -p "$OC_PROJ_DIR"
              if ls "$OC_PROJ_DIR/" 2>/dev/null | grep -q .; then
                while IFS= read -r entry; do
                  local _name; _name=$(basename "$entry")
                  if [ -L "$entry" ]; then
                    local _target; _target=$(readlink -f "$entry" 2>/dev/null || readlink "$entry")
                    printf "    ${CYAN}→${NC} %-28s ${DIM}symlink → %s${NC}\n" "$_name" "$_target"
                  elif [ -d "$entry" ]; then
                    printf "    ${GREEN}■${NC} %s\n" "$_name"
                  fi
                done < <(find "$OC_PROJ_DIR" -maxdepth 1 -mindepth 1 2>/dev/null | sort)
              else
                echo -e "  ${DIM}(vacío — usa [2] symlink o [3] copiar)${NC}"
              fi
              echo ""; read -r _ < /dev/tty ;;

            2)
              # ── Symlink desde Android → ~/proyectos/ ────────────────────
              # Funciona con proot y nativo (proot puede seguir symlinks a /storage)
              clear; echo ""
              echo -e "  ${CYAN}${BOLD}Symlink desde Android${NC}"
              echo -e "  ${DIM}Busca carpetas en /storage/emulated/0/ y las vincula${NC}"
              echo ""
              echo -e "  ${DIM}Rutas comunes:${NC}"
              echo    "    [1] Download"
              echo    "    [2] Documents"
              echo    "    [3] Ruta manual"
              echo ""; echo -n "  Elige: "
              read -r _SRC_OPT < /dev/tty
              local _SRC_BASE=""
              case "$_SRC_OPT" in
                1) _SRC_BASE="/storage/emulated/0/Download" ;;
                2) _SRC_BASE="/storage/emulated/0/Documents" ;;
                3)
                  echo -n "  Ruta Android (ej: /storage/emulated/0/MiCarpeta): "
                  read -r _SRC_BASE < /dev/tty
                  _SRC_BASE="${_SRC_BASE%/}"
                  ;;
                *) echo -e "  ${YELLOW}Cancelado${NC}"; echo ""; read -r _ < /dev/tty; continue ;;
              esac
              [ ! -d "$_SRC_BASE" ] && {
                echo -e "  ${RED}[ERROR]${NC} No existe o sin permiso: $_SRC_BASE"
                echo ""; read -r _ < /dev/tty; continue
              }
              mapfile -t _SRC_DIRS < <(find "$_SRC_BASE" \
                -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | xargs -I{} basename {})
              [ ${#_SRC_DIRS[@]} -eq 0 ] && {
                echo -e "  ${YELLOW}Sin carpetas en $_SRC_BASE${NC}"
                echo ""; read -r _ < /dev/tty; continue
              }
              mkdir -p "$OC_PROJ_DIR"
              echo ""
              for i in "${!_SRC_DIRS[@]}"; do
                local _dst="$OC_PROJ_DIR/${_SRC_DIRS[$i]}"
                if [ -L "$_dst" ]; then
                  printf "    [%d] %s ${DIM}(ya vinculado)${NC}\n" "$((i+1))" "${_SRC_DIRS[$i]}"
                elif [ -d "$_dst" ]; then
                  printf "    [%d] %s ${YELLOW}(carpeta real — no reemplazar)${NC}\n" "$((i+1))" "${_SRC_DIRS[$i]}"
                else
                  printf "    [%d] %s\n" "$((i+1))" "${_SRC_DIRS[$i]}"
                fi
              done
              echo ""; echo -n "  Número: "
              read -r _DCHOICE < /dev/tty
              if [[ "$_DCHOICE" =~ ^[0-9]+$ ]] && [ "$_DCHOICE" -ge 1 ] && \
                 [ "$_DCHOICE" -le "${#_SRC_DIRS[@]}" ]; then
                local _DNAME="${_SRC_DIRS[$((_DCHOICE-1))]}"
                local _LSRC="$_SRC_BASE/${_DNAME}"
                local _LDST="$OC_PROJ_DIR/${_DNAME}"
                if [ -L "$_LDST" ]; then
                  echo -e "  ${YELLOW}[AVISO]${NC} Ya existe symlink: ~/proyectos/${_DNAME}"
                elif [ -d "$_LDST" ]; then
                  echo -e "  ${YELLOW}[AVISO]${NC} Ya existe carpeta real: ~/proyectos/${_DNAME}"
                  echo -e "  ${DIM}Usa [5] eliminar primero si quieres reemplazarla${NC}"
                else
                  ln -s "$_LSRC" "$_LDST" 2>/dev/null \
                    && echo -e "  ${GREEN}[OK]${NC} Symlink: ~/proyectos/${_DNAME} → ${_LSRC}" \
                    || echo -e "  ${RED}[ERROR]${NC} No se pudo crear el symlink"
                fi
              fi
              echo ""; read -r _ < /dev/tty ;;

            3)
              # ── Copiar desde Android → ~/proyectos/ (para glibc) ────────
              # glibc OpenCode no puede seguir symlinks a /storage —
              # necesita la carpeta físicamente en $HOME
              clear; echo ""
              echo -e "  ${CYAN}${BOLD}Copiar desde Android → ~/proyectos/${NC}"
              echo -e "  ${YELLOW}Para OpenCode glibc${NC} ${DIM}(no sigue symlinks a /storage)${NC}"
              echo ""
              echo -e "  ${DIM}Rutas comunes:${NC}"
              echo    "    [1] Download"
              echo    "    [2] Documents"
              echo    "    [3] Ruta manual"
              echo ""; echo -n "  Elige: "
              read -r _CP_OPT < /dev/tty
              local _CP_BASE=""
              case "$_CP_OPT" in
                1) _CP_BASE="/storage/emulated/0/Download" ;;
                2) _CP_BASE="/storage/emulated/0/Documents" ;;
                3)
                  echo -n "  Ruta Android (ej: /storage/emulated/0/MiCarpeta): "
                  read -r _CP_BASE < /dev/tty
                  _CP_BASE="${_CP_BASE%/}"
                  ;;
                *) echo -e "  ${YELLOW}Cancelado${NC}"; echo ""; read -r _ < /dev/tty; continue ;;
              esac
              [ ! -d "$_CP_BASE" ] && {
                echo -e "  ${RED}[ERROR]${NC} No existe o sin permiso: $_CP_BASE"
                echo ""; read -r _ < /dev/tty; continue
              }
              mapfile -t _CP_DIRS < <(find "$_CP_BASE" \
                -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | xargs -I{} basename {})
              [ ${#_CP_DIRS[@]} -eq 0 ] && {
                echo -e "  ${YELLOW}Sin carpetas en $_CP_BASE${NC}"
                echo ""; read -r _ < /dev/tty; continue
              }
              mkdir -p "$OC_PROJ_DIR"
              echo ""
              for i in "${!_CP_DIRS[@]}"; do
                local _cdst="$OC_PROJ_DIR/${_CP_DIRS[$i]}"
                if [ -d "$_cdst" ] && [ ! -L "$_cdst" ]; then
                  printf "    [%d] %s ${DIM}(ya copiado)${NC}\n" "$((i+1))" "${_CP_DIRS[$i]}"
                elif [ -L "$_cdst" ]; then
                  printf "    [%d] %s ${YELLOW}(symlink — copiar encima)${NC}\n" "$((i+1))" "${_CP_DIRS[$i]}"
                else
                  printf "    [%d] %s\n" "$((i+1))" "${_CP_DIRS[$i]}"
                fi
              done
              echo ""; echo -n "  Número: "
              read -r _CPCHOICE < /dev/tty
              if [[ "$_CPCHOICE" =~ ^[0-9]+$ ]] && [ "$_CPCHOICE" -ge 1 ] && \
                 [ "$_CPCHOICE" -le "${#_CP_DIRS[@]}" ]; then
                local _CPNAME="${_CP_DIRS[$((_CPCHOICE-1))]}"
                local _CPSRC="$_CP_BASE/${_CPNAME}"
                local _CPDST="$OC_PROJ_DIR/${_CPNAME}"
                # Si ya existe symlink, preguntar antes de reemplazar
                if [ -L "$_CPDST" ]; then
                  echo -e "  ${YELLOW}[AVISO]${NC} Existe symlink: ~/proyectos/${_CPNAME}"
                  echo -n "  ¿Eliminar symlink y copiar carpeta real? (s/n): "
                  read -r _CPREPL < /dev/tty
                  [ "$_CPREPL" != "s" ] && [ "$_CPREPL" != "S" ] && {
                    echo ""; read -r _ < /dev/tty; continue
                  }
                  rm "$_CPDST"
                fi
                # Si ya existe carpeta real, preguntar si actualizar
                if [ -d "$_CPDST" ]; then
                  echo -e "  ${YELLOW}[AVISO]${NC} Ya existe: ~/proyectos/${_CPNAME}"
                  echo -n "  ¿Actualizar (rsync)? (s/n): "
                  read -r _CPUPD < /dev/tty
                  [ "$_CPUPD" != "s" ] && [ "$_CPUPD" != "S" ] && {
                    echo ""; read -r _ < /dev/tty; continue
                  }
                fi
                echo -e "  ${CYAN}Copiando...${NC} ${DIM}(puede tardar)${NC}"
                # rsync si disponible, cp -r como fallback
                if command -v rsync &>/dev/null; then
                  rsync -a --info=progress2 "$_CPSRC/" "$_CPDST/" 2>/dev/null \
                    && echo -e "  ${GREEN}[OK]${NC} Copiado/actualizado: ~/proyectos/${_CPNAME}" \
                    || echo -e "  ${RED}[ERROR]${NC} rsync falló"
                else
                  cp -r "$_CPSRC" "$_CPDST" 2>/dev/null \
                    && echo -e "  ${GREEN}[OK]${NC} Copiado: ~/proyectos/${_CPNAME}" \
                    || echo -e "  ${RED}[ERROR]${NC} cp falló"
                fi
              fi
              echo ""; read -r _ < /dev/tty ;;

            4)
              # ── Crear proyecto vacío ────────────────────────────────────
              clear; echo ""
              echo -n "  Nombre del proyecto: "; read -r NEW_NAME < /dev/tty
              NEW_NAME=$(echo "$NEW_NAME" | tr ' ' '-' | tr -cd '[:alnum:]-_')
              [ -z "$NEW_NAME" ] && {
                echo -e "  ${YELLOW}Nombre vacío${NC}"; echo ""; read -r _ < /dev/tty; continue
              }
              mkdir -p "$OC_PROJ_DIR/$NEW_NAME" \
                && echo -e "  ${GREEN}[OK]${NC} Creado: ~/proyectos/$NEW_NAME" \
                || echo -e "  ${RED}[ERROR]${NC}"
              echo ""; read -r _ < /dev/tty ;;

            5)
              # ── Eliminar proyecto (symlink o carpeta real) ───────────────
              clear; echo ""
              mapfile -t _ALL_PROJS < <(find "$OC_PROJ_DIR" -maxdepth 1 -mindepth 1 \
                2>/dev/null | sort | xargs -I{} basename {})
              [ ${#_ALL_PROJS[@]} -eq 0 ] && {
                echo -e "  ${DIM}Sin proyectos en ~/proyectos/${NC}"
                echo ""; read -r _ < /dev/tty; continue
              }
              echo -e "  ${BOLD}~/proyectos/:${NC}"; echo ""
              for i in "${!_ALL_PROJS[@]}"; do
                local _ep="$OC_PROJ_DIR/${_ALL_PROJS[$i]}"
                if [ -L "$_ep" ]; then
                  printf "    [%d] %s ${DIM}(symlink)${NC}\n" "$((i+1))" "${_ALL_PROJS[$i]}"
                else
                  printf "    [%d] %s ${DIM}(carpeta)${NC}\n" "$((i+1))" "${_ALL_PROJS[$i]}"
                fi
              done
              echo ""; echo -n "  Número: "
              read -r _ECHOICE < /dev/tty
              if [[ "$_ECHOICE" =~ ^[0-9]+$ ]] && [ "$_ECHOICE" -ge 1 ] && \
                 [ "$_ECHOICE" -le "${#_ALL_PROJS[@]}" ]; then
                local _ENAME="${_ALL_PROJS[$((_ECHOICE-1))]}"
                local _EPATH="$OC_PROJ_DIR/$_ENAME"
                if [ -L "$_EPATH" ]; then
                  echo -n "  ¿Eliminar symlink ~/proyectos/${_ENAME}? (s/n): "
                  read -r _ECONF < /dev/tty
                  [ "$_ECONF" = "s" ] || [ "$_ECONF" = "S" ] && {
                    rm "$_EPATH" \
                      && echo -e "  ${GREEN}[OK]${NC} Symlink eliminado" \
                      || echo -e "  ${RED}[ERROR]${NC}"
                  }
                else
                  echo -e "  ${YELLOW}[AVISO]${NC} Esto eliminará la carpeta y TODO su contenido"
                  echo -n "  ¿Eliminar ~/proyectos/${_ENAME}? Escribe el nombre para confirmar: "
                  read -r _ECONF2 < /dev/tty
                  [ "$_ECONF2" = "$_ENAME" ] && {
                    rm -rf "$_EPATH" \
                      && echo -e "  ${GREEN}[OK]${NC} Carpeta eliminada" \
                      || echo -e "  ${RED}[ERROR]${NC}"
                  } || echo -e "  ${YELLOW}Cancelado${NC}"
                fi
              fi
              echo ""; read -r _ < /dev/tty ;;

            b|B|"") break ;;
          esac
        done ;;
      5)
        clear; echo ""
        if tmux has-session -t "oc-web" 2>/dev/null || \
           curl -sf http://127.0.0.1:3000 &>/dev/null; then
          _oc_web_stop
        else
          echo -e "  ${YELLOW}[AVISO]${NC} El servidor no estaba corriendo"
        fi
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        echo -e "  ${CYAN}${BOLD}OpenCode — Debian proot${NC}"; echo ""
        echo -e "  ${GREEN}[1]${NC} Actualizar   ${DIM}(curl opencode.ai/install en Debian)${NC}"
        echo -e "  [2] Reinstalar  ${DIM}(instalación completa desde cero)${NC}"
        echo -e "  [q] Cancelar"
        echo ""; echo -n "  Opción: "
        read -r _OC_UPD < /dev/tty
        case "$_OC_UPD" in
          1)
            echo ""
            echo -e "  ${CYAN}Actualizando OpenCode en Debian...${NC}"; echo ""
            proot-distro login "$DISTRO_NAME" -- bash -c \
              'export HOME=/root
               export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
               curl -fsSL https://opencode.ai/install | bash 2>&1 | tail -10
               echo ""
               echo "Versión: $(opencode --version 2>/dev/null | head -1)"' < /dev/tty
            ;;
          2)
            echo ""
            _ensure_install_script "install_opencode.sh" || { echo ""; read -r _ < /dev/tty; continue; }
            _run_installer "install_opencode.sh" "OpenCode"
            ;;
          q|Q|"") ;;
        esac
        echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        echo -e "  ${CYAN}${BOLD}Configurar Ollama en OpenCode${NC}"; echo ""
        echo -e "  ${YELLOW}[AVISO]${NC} Modelos locales en ARM64 sin GPU son lentos"
        echo -e "  ${DIM}  (~30-60s/resp). Para uso real: Big Pickle es gratis.${NC}"
        echo ""
        echo -e "  ${DIM}[r] Quitar Ollama (volver al provider por defecto)${NC}"; echo ""

        if ! curl -sf http://127.0.0.1:11434 &>/dev/null; then
          echo -e "  ${YELLOW}[AVISO]${NC} Ollama no está corriendo en :11434"
          echo -e "  ${DIM}Inícialo con: ollama-start${NC}"; echo ""
          echo -n "  ¿Continuar de todas formas? (s/n): "
          read -r _OL < /dev/tty
          [ "$_OL" != "s" ] && [ "$_OL" != "S" ] && {
            echo ""; read -r _ < /dev/tty; continue
          }
        fi

        # Listar modelos via urllib (no requests)
        mapfile -t OL_MODEL_LIST < <(
          curl -sf http://127.0.0.1:11434/api/tags 2>/dev/null | \
          python3 -c "
import sys, json
try:
  d=json.load(sys.stdin)
  [print(m['name']) for m in d.get('models',[])]
except: pass
" 2>/dev/null)

        echo -e "  ${CYAN}Modelos instalados:${NC}"; echo ""
        if [ ${#OL_MODEL_LIST[@]} -eq 0 ]; then
          echo -e "  ${YELLOW}(ninguno — instala con ollama pull)${NC}"
        else
          for i in "${!OL_MODEL_LIST[@]}"; do
            printf "    [%d] %s\n" "$((i+1))" "${OL_MODEL_LIST[$i]}"
          done
        fi
        echo ""
        echo -n "  Número o nombre ([r] quitar, ENTER cancela): "
        read -r OL_INPUT < /dev/tty

        if [ "$OL_INPUT" = "r" ] || [ "$OL_INPUT" = "R" ]; then
          proot-distro login "$DISTRO_NAME" -- bash -c \
            'rm -f /root/.config/opencode/opencode.json /root/.config/opencode/config.json && echo ok' 2>/dev/null
          echo -e "  ${GREEN}[OK]${NC} Config eliminado — OpenCode usará provider por defecto"
          echo ""; read -r _ < /dev/tty; continue
        fi
        [ -z "$OL_INPUT" ] && {
          echo -e "  ${YELLOW}Cancelado${NC}"; echo ""; read -r _ < /dev/tty; continue
        }

        local OL_MODEL=""
        if [[ "$OL_INPUT" =~ ^[0-9]+$ ]] && [ "$OL_INPUT" -ge 1 ] && \
           [ "$OL_INPUT" -le "${#OL_MODEL_LIST[@]}" ]; then
          OL_MODEL="${OL_MODEL_LIST[$((OL_INPUT-1))]}"
        else
          OL_MODEL="$OL_INPUT"
        fi

        echo -e "  Configurando: ${CYAN}${OL_MODEL}${NC}"; echo ""

        # Escribir config con formato correcto para OpenCode v1.15.5+
        # apiKey requerido aunque Ollama no lo valide — sin él el provider
        # no aparece en el selector de modelos de la UI
        local OC_CFG_OK=false
        python3 - << PYEOF | proot-distro login "$DISTRO_NAME" -- bash -c \
          'mkdir -p /root/.config/opencode && cat > /root/.config/opencode/opencode.json' \
          2>/dev/null && OC_CFG_OK=true || OC_CFG_OK=false
import json
print(json.dumps({
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/${OL_MODEL}",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": {
        "baseURL": "http://127.0.0.1:11434/v1",
        "apiKey": "ollama"
      },
      "models": {
        "${OL_MODEL}": {
          "name": "${OL_MODEL}"
        }
      }
    }
  }
}, indent=2))
PYEOF

        if $OC_CFG_OK; then
          echo -e "  ${GREEN}[OK]${NC} Ollama configurado: ${OL_MODEL}"
          echo -e "  ${DIM}Reinicia el servidor: [5] detener → [2] iniciar${NC}"
          echo ""
          echo -e "  ${DIM}Si el modelo no aparece en el selector UI, ejecuta${NC}"
          echo -e "  ${DIM}dentro de Debian: opencode auth login → Ollama (local)${NC}"
        else
          echo -e "  ${RED}[ERROR]${NC} No se pudo escribir config"
        fi
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  SUBMENÚ SERVICIOS (n8n + OpenClaw + Hermes)
#  $1 = N8N_STATE precalculado desde el loop principal (opcional)
#  $2 = CL_STATE  precalculado desde el loop principal (opcional)
#  $3 = HM_STATE  precalculado desde el loop principal (opcional)
#  Si se pasan, se usan en el primer render — evita re-chequeo.
#  En renders siguientes (al volver de sub-submenú) sí re-chequea.
# ════════════════════════════════════════════
submenu_servicios() {
  # Estados iniciales: usar los valores del loop principal si se pasan
  local _N8_INIT="${1:-}"
  local _CL_INIT="${2:-}"
  local _HM_INIT="${3:-}"
  local _FIRST_RENDER=1

  while true; do
    clear; echo ""

    local N8_S N8_V N8_E CL_S CL_V CL_E HM_S HM_V HM_E

    if [ "$_FIRST_RENDER" = "1" ] && [ -n "$_N8_INIT" ] && [ -n "$_CL_INIT" ]; then
      # Primer render: n8n y Hermes usan estado pre-calculado.
      # OpenClaw: siempre hacer check_openclaw_native primero — garantiza
      # prioridad nativa aunque _CL_INIT venga del caché proot.
      N8_S="$_N8_INIT"
      N8_V=$(grep "^n8n\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
      [ -z "$N8_V" ] && N8_V="?"
      N8_E=""
      local _CLN_FIRST; _CLN_FIRST=$(check_openclaw_native 2>/dev/null)
      IFS='|' read -r _CLN_S _CLN_V _CLN_E <<< "$_CLN_FIRST"
      if [ "$_CLN_S" != "not_installed" ] && [ -n "$_CLN_S" ]; then
        CL_S="$_CLN_S"; CL_V="$_CLN_V"; CL_E="$_CLN_E"
      else
        IFS='|' read -r CL_S CL_V CL_E <<< "$_CL_INIT"
      fi
      IFS='|' read -r HM_S HM_V HM_E <<< "${_HM_INIT:-not_installed||}"
      _FIRST_RENDER=0
    else
      # Renders siguientes: chequeo real (usuario volvió de sub-submenú)
      IFS='|' read -r N8_S N8_V N8_E <<< "$(check_n8n)"
      IFS='|' read -r CL_S CL_V CL_E <<< "$(check_openclaw_cached)"
      IFS='|' read -r HM_S HM_V HM_E <<< "$(check_hermes)"
    fi

    local N8_PILL CL_PILL HM_PILL
    case "$N8_S" in
      running)       N8_PILL="${GREEN}● activo  ${NC}" ;;
      stopped)       N8_PILL="${GREEN}● listo   ${NC}" ;;
      not_installed) N8_PILL="${YELLOW}○ no instal${NC}"; N8_V="──────────" ;;
      *)             N8_PILL="${YELLOW}● ${N8_S}${NC}" ;;
    esac
    case "$CL_S" in
      running)       CL_PILL="${GREEN}● activo  ${NC}" ;;
      stopped)       CL_PILL="${GREEN}● listo   ${NC}" ;;
      not_installed) CL_PILL="${YELLOW}○ no instal${NC}"; CL_V="──────────" ;;
      *)             CL_PILL="${YELLOW}● ${CL_S}${NC}" ;;
    esac
    case "$HM_S" in
      running)       HM_PILL="${GREEN}● activo  ${NC}" ;;
      stopped)       HM_PILL="${GREEN}● listo   ${NC}" ;;
      not_installed) HM_PILL="${YELLOW}○ no instal${NC}"; HM_V="──────────" ;;
      *)             HM_PILL="${YELLOW}● ${HM_S}${NC}" ;;
    esac

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⬡ SERVICIOS                            ║"
    echo    "  ╠══════════════════════════════════════════╣"
    printf  "  ║  ${NC}[1] n8n        %b  %b${CYAN}${BOLD}║\n" "$N8_PILL" "${NC}→ submenú${CYAN}${BOLD}"
    printf  "  ║      ${NC}${DIM}%s${NC}${CYAN}${BOLD}%-$((28 - ${#N8_V}))s║\n" "$N8_V" ""
    local _CL_MODE_LABEL
    [ "$CL_E" = "native" ] && _CL_MODE_LABEL="${DIM} ·native${NC}" || _CL_MODE_LABEL=""
    printf  "  ║  ${NC}[2] OpenClaw   %b  %b${CYAN}${BOLD}║\n" "$CL_PILL" "${NC}→ submenú${CYAN}${BOLD}"
    printf  "  ║      ${NC}${DIM}v%s%b${NC}${CYAN}${BOLD}%-$((26 - ${#CL_V}))s║\n" "$CL_V" "$_CL_MODE_LABEL" ""
    printf  "  ║  ${NC}[3] Hermes     %b  %b${CYAN}${BOLD}║\n" "$HM_PILL" "${NC}→ submenú${CYAN}${BOLD}"
    printf  "  ║      ${NC}${DIM}%s${NC}${CYAN}${BOLD}%-$((28 - ${#HM_V}))s║\n" "$HM_V" ""
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[b] Volver al menú principal${CYAN}${BOLD}           ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        [ "$N8_S" = "not_installed" ] \
          && install_module "n8n" "n8n" \
          || submenu_n8n "$N8_S" ;;
      2)
        if [ "$CL_S" = "not_installed" ]; then
          install_module "OpenClaw" "openclaw"
        elif [ "$CL_E" = "native" ]; then
          # Nativo instalado → submenú nativo (sin proot, sin NVM)
          submenu_openclaw_native
        else
          # Proot instalado → submenú proot existente
          submenu_openclaw
        fi ;;
      3)
        [ "$HM_S" = "not_installed" ] \
          && install_module "Hermes Agent" "hermes" \
          || submenu_hermes ;;
      b|B|"") break ;;
    esac
  done
}

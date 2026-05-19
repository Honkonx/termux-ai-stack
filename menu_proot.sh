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
#    - proot-distro login debian tarda 3-5s: minimizar llamadas
#    - _check_proot_combined: 1 sola invocación para OC + CL
#    - pkill desde Termux NO mata procesos dentro del proot
#    - Caché memoria: _PROOT_CACHE_TTL=30s (definida en menu.sh)
#    - Caché archivo: _PROOT_CACHE_TTL_PERSIST=300s (~/.proot_status_cache)
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 5.0.0 | Mayo 2026
# ============================================================

# ════════════════════════════════════════════
#  CHECK N8N
# ════════════════════════════════════════════
check_n8n() {
  [ "$(get_reg n8n installed)" = "true" ] || { echo "not_installed||"; return; }
  local ver; ver=$(get_reg n8n version)
  tmux has-session -t "n8n-server" 2>/dev/null \
    && echo "running|${ver}|" || echo "stopped|${ver}|"
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
  # Retorna 1 si no hay archivo, está corrupto o expiró
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
#  CHECK COMBINADO PROOT
#  Una sola invocación proot para opencode + openclaw.
#  Formato salida interna: "found|VER@@found|" o "not_installed|@@not_installed|"
#  Resultado escrito en _OC_CACHE y _CLAW_CACHE (variables globales de menu.sh)
# ════════════════════════════════════════════
_check_proot_combined() {
  local raw
  raw=$(proot-distro login debian -- bash -c '
    # ── opencode ──
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
    export NVM_DIR="$HOME/.nvm"
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

  # ── openclaw → estado final con curl (Termux, no proot) ──
  local cl_status cl_ver
  cl_status="${cl_raw%%|*}"
  if [ "$cl_status" = "found" ]; then
    cl_ver=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
    [ -z "$cl_ver" ] && cl_ver="?"
    curl -sf --max-time 1 http://127.0.0.1:18789 &>/dev/null \
      && _CLAW_CACHE="running|${cl_ver}|:18789" \
      || _CLAW_CACHE="stopped|${cl_ver}|"
  else
    _CLAW_CACHE="not_installed||"
  fi

  local now=$SECONDS
  _OC_CACHE_TS=$now
  _CLAW_CACHE_TS=$now

  # Persistir a disco — sobrevive entre reinicios del módulo y sesiones
  _write_proot_cache
}

# ── Checks directos (sin caché) — para submenús internos ─────
check_opencode() {
  if proot-distro login debian -- bash -c 'command -v opencode' &>/dev/null 2>&1; then
    local oc_ver
    oc_ver=$(proot-distro login debian -- bash -c \
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
  if proot-distro login debian -- bash -c \
    'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     command -v openclaw' &>/dev/null 2>&1; then
    local cl_ver
    cl_ver=$(grep "^openclaw\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
    [ -z "$cl_ver" ] && cl_ver="?"
    curl -sf --max-time 1 http://127.0.0.1:18789 &>/dev/null \
      && echo "running|${cl_ver}|:18789" \
      || echo "stopped|${cl_ver}|"
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
#  REPARAR SCRIPTS N8N
#  Regenera: start_servidor.sh, stop_servidor.sh,
#  ver_url.sh, n8n_status.sh, n8n_log.sh,
#  n8n_update.sh, n8n_backup.sh, cf_token.sh
#  Destino: $N8N_SCRIPTS (~/scripts/n8n/)
# ════════════════════════════════════════════
_n8n_repair_scripts() {
  echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo    "  ║  ⬡ N8N — Reparar scripts de control    ║"
  echo -e "  ╚══════════════════════════════════════════╝${NC}"
  echo ""

  echo -n "  Verificando n8n en proot Debian... "
  if ! proot-distro login debian -- bash -c 'command -v n8n' &>/dev/null 2>&1; then
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
  "proot-distro login debian -- bash -c '\${N8N_CMD}'" Enter

echo "[*] Esperando que n8n inicie (35 seg)..."
sleep 35

echo "[*] Iniciando cloudflared tunnel..."
tmux new-window -t "\$SESSION" -n "tunnel"

if [ -f "\$HOME/.cf_token" ]; then
  CF_TOK=\$(cat "\$HOME/.cf_token")
  tmux send-keys -t "\$SESSION:tunnel" \
    "proot-distro login debian -- bash -c 'cloudflared tunnel --no-autoupdate run --token \${CF_TOK} 2>&1 | tee /root/cf_url.log'" Enter
else
  tmux send-keys -t "\$SESSION:tunnel" \
    "proot-distro login debian -- bash -c 'cloudflared tunnel --no-autoupdate --url http://localhost:5678 2>&1 | tee /root/cf_url.log'" Enter
fi

echo "[*] Obteniendo URL pública (40 seg)..."
sleep 40

if [ -n "\$WEBHOOK_URL_CFG" ]; then
  CF_URL="\$WEBHOOK_URL_CFG"
else
  CF_URL=\$(proot-distro login debian -- bash -c \
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

  # --- stop_servidor.sh ---
  echo -n "  Creando stop_servidor.sh... "
  cat > "$N8N_SCRIPTS/stop_servidor.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Deteniendo n8n y cloudflared..."
proot-distro login debian -- bash -c \
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
  URL=$(proot-distro login debian -- bash -c \
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
proot-distro login debian -- bash -c \
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
proot-distro login debian -- bash -c \
  "tar -czf /tmp/n8n_backup.tar.gz -C /root/.n8n . 2>/dev/null && echo done"
proot-distro login debian -- bash -c "cat /tmp/n8n_backup.tar.gz" > "$DESTINO" 2>/dev/null
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
  echo -e "  ${GREEN}[OK]${NC} 8 scripts regenerados correctamente en ~/scripts/n8n/"
  echo -e "  ${DIM}start · stop · url · status · log · update · backup · cf_token${NC}"
}

# ════════════════════════════════════════════
#  SUBMENÚ N8N
# ════════════════════════════════════════════
submenu_n8n() {
  local state="$1"
  while true; do
    clear; echo ""
    local _N8N_PROTO
    _N8N_PROTO=$(cat "$HOME/.n8n_protocol" 2>/dev/null || echo "https")

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    [ "$state" = "running" ] \
      && echo "  ║  ⬡ N8N  ● activo                        ║" \
      || echo "  ║  ⬡ N8N  ● listo                         ║"
    [ -f "$HOME/.cf_token" ] && [ -s "$HOME/.cf_token" ] \
      && echo -e "  ║  ${NC}Tunnel: URL fija ${GREEN}●${NC}${CYAN}${BOLD}                   ║" \
      || echo -e "  ║  ${NC}Tunnel: URL temporal ${YELLOW}○${NC}${CYAN}${BOLD}                 ║"
    echo -e "  ║  ${NC}Protocolo: ${GREEN}${_N8N_PROTO}${NC}${CYAN}${BOLD}                       ║"
    echo    "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${NC}[1]  Iniciar n8n + cloudflared          ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[2]  Detener n8n + cloudflared          ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[3]  Ver URL pública                    ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[4]  Logs en vivo                       ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[5]  Consola Debian                     ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[6]  Ver estado del sistema             ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[7]  Token cloudflared                  ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[8]  Configurar URL webhook             ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[9]  Reparar scripts de control         ${CYAN}${BOLD}║"
    echo -e "  ║  ${DIM}     regenera start/stop/url/status/log ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[10] Protocolo HTTP / HTTPS             ${CYAN}${BOLD}║"
    echo -e "  ║  ${NC}[b]  Volver al menú principal           ${CYAN}${BOLD}║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""; echo -n "  Opción: "
    read -r OPT < /dev/tty

    case "$OPT" in
      1)
        clear; echo ""
        if [ ! -f "$N8N_SCRIPTS/start_servidor.sh" ]; then
          echo -e "  ${YELLOW}[AVISO]${NC} start_servidor.sh no encontrado."
          echo -n "  ¿Reparar scripts de control ahora? (s/n): "
          read -r _REPAIR < /dev/tty
          if [ "$_REPAIR" = "s" ] || [ "$_REPAIR" = "S" ]; then
            _n8n_repair_scripts; echo ""
          else
            echo ""; read -r _ < /dev/tty; continue
          fi
        fi
        if [ -f "$N8N_SCRIPTS/start_servidor.sh" ]; then
          bash "$N8N_SCRIPTS/start_servidor.sh" < /dev/tty
        else
          echo -e "  ${RED}[ERROR]${NC} No se pudo crear start_servidor.sh — verifica que n8n esté instalado en proot"
        fi
        echo ""; read -r _ < /dev/tty
        tmux has-session -t "n8n-server" 2>/dev/null && state="running" || state="stopped" ;;
      2)
        clear; echo ""
        bash "$N8N_SCRIPTS/stop_servidor.sh" 2>/dev/null || \
          tmux kill-session -t "n8n-server" 2>/dev/null
        sleep 1; echo -e "  ${GREEN}[OK]${NC} n8n detenido"
        echo ""; read -r _ < /dev/tty
        state="stopped" ;;
      3)
        clear; echo ""
        bash "$N8N_SCRIPTS/ver_url.sh" 2>/dev/null || {
          local URL; URL=$(cat "$HOME/.last_cf_url" 2>/dev/null)
          [ -n "$URL" ] \
            && echo -e "  ${GREEN}URL:${NC} $URL" \
            || echo -e "  ${YELLOW}[AVISO]${NC} n8n no está corriendo o URL no disponible"
        }
        echo ""; read -r _ < /dev/tty ;;
      4)
        clear; echo ""
        echo -e "  ${CYAN}Logs n8n — Ctrl+B D para salir sin detener${NC}"; echo ""
        tmux has-session -t "n8n-server" 2>/dev/null \
          && tmux attach-session -t "n8n-server" \
          || echo -e "  ${YELLOW}[AVISO]${NC} n8n no está corriendo"
        echo ""; read -r _ < /dev/tty ;;
      5)
        clear; echo ""
        echo -e "  ${CYAN}Consola Debian — escribe 'exit' para volver${NC}"; echo ""
        proot-distro login debian 2>/dev/null || \
          echo -e "  ${RED}[ERROR]${NC} Proot Debian no encontrado"
        echo ""; read -r _ < /dev/tty ;;
      6)
        clear; echo ""
        bash "$N8N_SCRIPTS/n8n_status.sh" 2>/dev/null || {
          echo -e "  ${BOLD}Estado n8n:${NC}"
          tmux has-session -t "n8n-server" 2>/dev/null \
            && echo -e "  ${GREEN}● Corriendo${NC}" \
            || echo -e "  ${YELLOW}○ Detenido${NC}"
          local CF_URL; CF_URL=$(cat "$HOME/.last_cf_url" 2>/dev/null)
          [ -n "$CF_URL" ] && echo -e "  URL: ${CF_URL}"
        }
        echo ""; read -r _ < /dev/tty ;;
      7)
        clear; echo ""
        echo -e "  ${BOLD}Token cloudflared (URL fija)${NC}"; echo ""
        local CF_CURRENT; CF_CURRENT=$(cat "$HOME/.cf_token" 2>/dev/null)
        [ -n "$CF_CURRENT" ] \
          && echo -e "  Token actual: ${GREEN}configurado${NC}" \
          || echo -e "  Token actual: ${YELLOW}no configurado (URL temporal)${NC}"
        echo ""; echo "  (ENTER para cancelar)"
        echo -n "  Nuevo token (o ENTER para quitar): "
        read -r NEW_CF < /dev/tty
        if [ -n "$NEW_CF" ]; then
          echo "$NEW_CF" > "$HOME/.cf_token"
          echo -e "  ${GREEN}[OK]${NC} Token guardado — URL fija activada"
        else
          echo -n "  ¿Quitar token actual? (s/n): "
          read -r RM_CF < /dev/tty
          [ "$RM_CF" = "s" ] || [ "$RM_CF" = "S" ] && {
            rm -f "$HOME/.cf_token"
            echo -e "  ${GREEN}[OK]${NC} Token eliminado — modo URL temporal"
          }
        fi
        echo ""; read -r _ < /dev/tty ;;
      8)
        clear; echo ""
        echo -e "  ${BOLD}Configurar URL webhook n8n${NC}"; echo ""
        local CURRENT_WH; CURRENT_WH=$(grep "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" 2>/dev/null | cut -d'=' -f2)
        [ -n "$CURRENT_WH" ] \
          && echo -e "  URL actual: ${GREEN}${CURRENT_WH}${NC}" \
          || echo -e "  URL actual: ${YELLOW}no configurada${NC}"
        echo ""; echo "  (ENTER sin escribir = cancelar)"
        echo -n "  Nueva URL webhook: "
        read -r NEW_WH < /dev/tty
        if [ -n "$NEW_WH" ]; then
          grep -v "^N8N_WEBHOOK_URL=" "$HOME/.env_n8n" > "$HOME/.env_n8n.tmp" 2>/dev/null || \
            touch "$HOME/.env_n8n.tmp"
          echo "N8N_WEBHOOK_URL=${NEW_WH}" >> "$HOME/.env_n8n.tmp"
          mv "$HOME/.env_n8n.tmp" "$HOME/.env_n8n"
          echo "$NEW_WH" > "$HOME/.last_cf_url"
          echo -e "  ${GREEN}[OK]${NC} URL guardada. Reinicia n8n para aplicar."
        fi
        echo ""; read -r _ < /dev/tty ;;
      9)
        clear; echo ""
        _n8n_repair_scripts
        echo ""; read -r _ < /dev/tty ;;
      10)
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
          1)
            echo "https" > "$HOME/.n8n_protocol"
            echo -e "  ${GREEN}[OK]${NC} Protocolo → HTTPS guardado."
            echo -e "  ${CYAN}[INFO]${NC} Usa [9] Reparar scripts y reinicia n8n." ;;
          2)
            echo "http" > "$HOME/.n8n_protocol"
            echo -e "  ${GREEN}[OK]${NC} Protocolo → HTTP guardado."
            echo -e "  ${CYAN}[INFO]${NC} Usa [9] Reparar scripts y reinicia n8n." ;;
          *) echo -e "  ${YELLOW}[AVISO]${NC} Sin cambios." ;;
        esac
        echo ""; read -r _ < /dev/tty ;;
      b|B|"") break ;;
    esac
  done
}

# ════════════════════════════════════════════
#  HELPERS OPENCLAW
# ════════════════════════════════════════════
_cl_get_token() {
  proot-distro login debian -- bash -c \
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
  proot-distro login debian -- bash -c \
    'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
     export NODE_OPTIONS="--require /root/openclaw-shim.cjs"
     openclaw gateway --bind loopback' > "$HOME/.openclaw_gateway.log" 2>&1 &
  echo $! > "$HOME/.openclaw_gateway.pid"
}

_cl_stop() {
  proot-distro login debian -- bash -c \
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
    echo -e "  ║  ${NC}[8] Instalar / actualizar              ${CYAN}${BOLD}║"
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
        REAL_PATH="${REAL_PATH/\/data\/data\/com.termux\/files\/home/\/root}"
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
            proot-distro login debian -- bash -c \
              "export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
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
            proot-distro login debian -- bash -c \
              'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
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
              proot-distro login debian -- bash -c \
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
      8)
        clear; echo ""
        _ensure_install_script "install_openclaw.sh" || { read -r _ < /dev/tty; continue; }
        bash "$HOME/install_openclaw.sh" < /dev/tty
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

    case "$OPT" in
      1)
        clear; echo ""
        echo -e "  ${CYAN}Abriendo OpenCode TUI en Debian...${NC}"
        echo -e "  ${DIM}Ctrl+C para salir${NC}"; echo ""
        proot-distro login debian -- bash -c \
          'source ~/.bashrc 2>/dev/null; opencode' < /dev/tty
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
          proot-distro login debian -- bash -c \
            'source ~/.bashrc 2>/dev/null; BROWSER= opencode web --port 3000 --hostname 127.0.0.1' &
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
        local REAL_PATH
        REAL_PATH=$(readlink -f "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")
        REAL_PATH="${REAL_PATH/\/storage\/emulated\/0/\/sdcard}"
        REAL_PATH="${REAL_PATH/\/data\/data\/com.termux\/files\/home/\/root}"
        echo ""
        echo -e "  ${CYAN}Proyecto:${NC} $(basename "$TARGET_DIR")"
        echo -e "  ${DIM}cwd: $REAL_PATH${NC}"; echo ""
        echo "  [1] TUI  — interfaz en terminal"
        echo "  [2] Web  — servidor en :3000"
        echo ""; echo -n "  Modo: "
        read -r MODO < /dev/tty
        case "$MODO" in
          1)
            echo ""
            proot-distro login debian -- bash -c \
              "source ~/.bashrc 2>/dev/null; cd '$REAL_PATH' && opencode ." < /dev/tty
            echo ""; read -r _ < /dev/tty ;;
          2)
            pkill -f "opencode web" 2>/dev/null; sleep 1
            echo ""
            echo -e "  ${CYAN}Iniciando servidor en proyecto...${NC}"
            echo -e "  ${DIM}Cuando veas la URL presiona ENTER${NC}"; echo ""
            proot-distro login debian -- bash -c \
              "source ~/.bashrc 2>/dev/null; cd '$REAL_PATH' && BROWSER= opencode web --port 3000 --hostname 127.0.0.1" &
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
          echo -e "  ║  ${NC}[1] Listar  [2] Symlink  [3] Crear  [4] Borrar${CYAN}${BOLD}║"
          echo -e "  ║  ${NC}[b] Volver${CYAN}${BOLD}                             ║"
          echo -e "  ╚══════════════════════════════════════════╝${NC}"
          echo ""; echo -n "  Opción: "
          read -r GOPT < /dev/tty
          case "$GOPT" in
            1)
              clear; echo ""
              echo -e "  ${BOLD}~/proyectos/:${NC}"; echo ""
              mkdir -p "$OC_PROJ_DIR"
              ls "$OC_PROJ_DIR/" 2>/dev/null | grep -q . \
                && ls -la "$OC_PROJ_DIR/" \
                || echo -e "  ${DIM}(vacío)${NC}"
              echo ""; read -r _ < /dev/tty ;;
            2)
              clear; echo ""
              mapfile -t DL_DIRS < <(find /storage/emulated/0/Download \
                -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -I{} basename {})
              [ ${#DL_DIRS[@]} -eq 0 ] && {
                echo -e "  ${YELLOW}Sin carpetas en Download${NC}"
                read -r _ < /dev/tty; continue
              }
              mkdir -p "$OC_PROJ_DIR"
              for i in "${!DL_DIRS[@]}"; do
                local LDST="$OC_PROJ_DIR/${DL_DIRS[$i]}"
                [ -L "$LDST" ] \
                  && printf "    [%d] %s ${DIM}(ya vinculado)${NC}\n" "$((i+1))" "${DL_DIRS[$i]}" \
                  || printf "    [%d] %s\n" "$((i+1))" "${DL_DIRS[$i]}"
              done
              echo ""; echo -n "  Número: "; read -r DCHOICE < /dev/tty
              if [[ "$DCHOICE" =~ ^[0-9]+$ ]] && [ "$DCHOICE" -ge 1 ] && \
                 [ "$DCHOICE" -le "${#DL_DIRS[@]}" ]; then
                local DNAME="${DL_DIRS[$((DCHOICE-1))]}"
                local LSRC="/storage/emulated/0/Download/${DNAME}"
                local LDST="$OC_PROJ_DIR/${DNAME}"
                [ -L "$LDST" ] \
                  && echo -e "  ${YELLOW}[AVISO]${NC} Ya existe: ~/proyectos/${DNAME}" \
                  || { ln -s "$LSRC" "$LDST" 2>/dev/null \
                    && echo -e "  ${GREEN}[OK]${NC} Symlink: ~/proyectos/${DNAME}" \
                    || echo -e "  ${RED}[ERROR]${NC}"; }
              fi
              echo ""; read -r _ < /dev/tty ;;
            3)
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
            4)
              clear; echo ""
              mapfile -t LINKS < <(find "$OC_PROJ_DIR" -maxdepth 1 -type l 2>/dev/null \
                | xargs -I{} basename {})
              [ ${#LINKS[@]} -eq 0 ] && {
                echo -e "  ${DIM}Sin symlinks${NC}"; read -r _ < /dev/tty; continue
              }
              for i in "${!LINKS[@]}"; do printf "    [%d] %s\n" "$((i+1))" "${LINKS[$i]}"; done
              echo ""; echo -n "  Número: "; read -r LCHOICE < /dev/tty
              if [[ "$LCHOICE" =~ ^[0-9]+$ ]] && [ "$LCHOICE" -ge 1 ] && \
                 [ "$LCHOICE" -le "${#LINKS[@]}" ]; then
                local LNAME="${LINKS[$((LCHOICE-1))]}"
                echo -n "  ¿Eliminar ~/proyectos/${LNAME}? (s/n): "
                read -r LCONFIRM < /dev/tty
                [ "$LCONFIRM" = "s" ] || [ "$LCONFIRM" = "S" ] && {
                  rm "$OC_PROJ_DIR/$LNAME" \
                    && echo -e "  ${GREEN}[OK]${NC} Eliminado" \
                    || echo -e "  ${RED}[ERROR]${NC}"
                }
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
        echo -e "  ${CYAN}Instalando/actualizando OpenCode en Debian...${NC}"; echo ""
        if [ -f "$HOME/install_opencode.sh" ]; then
          bash "$HOME/install_opencode.sh" < /dev/tty
        else
          echo -e "  ${CYAN}Ejecutando instalación directa en Debian...${NC}"; echo ""
          proot-distro login debian -- bash -c \
            'apt update -qq && apt install -y curl ripgrep tmux && \
             curl -fsSL https://opencode.ai/install | bash' < /dev/tty
          echo ""
          local OC_VER
          OC_VER=$(proot-distro login debian -- bash -c \
            'source ~/.bashrc 2>/dev/null; opencode --version 2>/dev/null' 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
          [ -n "$OC_VER" ] \
            && echo -e "  ${GREEN}[OK]${NC} OpenCode v${OC_VER} instalado" \
            || echo -e "  ${YELLOW}[AVISO]${NC} Verificar: proot-distro login debian"
        fi
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
          proot-distro login debian -- bash -c \
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
        python3 - << PYEOF | proot-distro login debian -- bash -c \
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
#  SUBMENÚ SERVICIOS (n8n + OpenClaw)
#  $1 = N8N_STATE precalculado desde el loop principal (opcional)
#  $2 = CL_STATE  precalculado desde el loop principal (opcional)
#  Si se pasan, se usan en el primer render — evita re-chequeo proot.
#  En renders siguientes (al volver de sub-submenú) sí re-chequea.
# ════════════════════════════════════════════
submenu_servicios() {
  # Estados iniciales: usar los valores del loop principal si se pasan
  local _N8_INIT="${1:-}"
  local _CL_INIT="${2:-}"
  local _FIRST_RENDER=1

  while true; do
    clear; echo ""

    local N8_S N8_V N8_E CL_S CL_V CL_E

    if [ "$_FIRST_RENDER" = "1" ] && [ -n "$_N8_INIT" ] && [ -n "$_CL_INIT" ]; then
      # Primer render: usar estados ya calculados — sin proot adicional
      N8_S="$_N8_INIT"
      N8_V=$(grep "^n8n\.version=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2)
      [ -z "$N8_V" ] && N8_V="?"
      N8_E=""
      IFS='|' read -r CL_S CL_V CL_E <<< "$_CL_INIT"
      _FIRST_RENDER=0
    else
      # Renders siguientes: chequeo real (usuario volvió de sub-submenú)
      IFS='|' read -r N8_S N8_V N8_E <<< "$(check_n8n)"
      IFS='|' read -r CL_S CL_V CL_E <<< "$(check_openclaw_cached)"
    fi

    local N8_PILL CL_PILL
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

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
    echo    "  ║  ⬡ SERVICIOS                            ║"
    echo    "  ╠══════════════════════════════════════════╣"
    printf  "  ║  ${NC}[1] n8n        %b  %b${CYAN}${BOLD}║\n" "$N8_PILL" "${NC}→ submenú${CYAN}${BOLD}"
    printf  "  ║      ${NC}${DIM}%s${NC}${CYAN}${BOLD}%-$((28 - ${#N8_V}))s║\n" "$N8_V" ""
    printf  "  ║  ${NC}[2] OpenClaw   %b  %b${CYAN}${BOLD}║\n" "$CL_PILL" "${NC}→ submenú${CYAN}${BOLD}"
    printf  "  ║      ${NC}${DIM}%s${NC}${CYAN}${BOLD}%-$((28 - ${#CL_V}))s║\n" "$CL_V" ""
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
        [ "$CL_S" = "not_installed" ] \
          && install_module "OpenClaw" "openclaw" \
          || submenu_openclaw ;;
      b|B|"") break ;;
    esac
  done
}

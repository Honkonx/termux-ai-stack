#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · backup.sh
#  Crea backups por módulo para subir a GitHub Releases
#
#  USO:
#    bash ~/backup.sh                       → backup completo (interactivo)
#    bash ~/backup.sh --module base         → part0-termux-base (scripts + tema + configs)
#    bash ~/backup.sh --module claude       → part2-claude-code
#    bash ~/backup.sh --module expo         → part3-eas-expo
#    bash ~/backup.sh --module ollama       → part4-ollama
#    bash ~/backup.sh --module n8n          → part5-n8n-data
#    bash ~/backup.sh --module remote       → part7-remote (SSH configs + dashboard)
#    bash ~/backup.sh --module proot        → part6-proot-debian
#
#  PARTES GENERADAS:
#    part0-termux-base    → .bashrc + .termux + todos los scripts + registry
#                           NUEVO: paquete de instalación rápida (tema + update)
#    part2-claude-code    → npm @anthropic-ai/claude-code completo
#    part3-eas-expo       → npm eas-cli + credenciales ~/.expo/
#    part4-ollama         → binario + libs (sin modelos)
#    part5-n8n-data       → n8n modules + cloudflared + workflows
#    part6-proot-debian   → rootfs Debian completo (~600MB-1GB)
#    part7-remote         → SSH configs + authorized_keys + dashboard + cf_tokens
#    checksums.txt        → SHA256 de todos los archivos
#
#  MÓDULOS LIGEROS (no necesitan backup en GitHub, se reinstalan en segundos):
#    Python, SSH binario, Dashboard binario → se instalan con pkg/pip
#    Solo se incluye la CONFIGURACIÓN (sshd_config, authorized_keys, dashboard_server.py)
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 2.3.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }
skip()   { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }

# ── Rutas ─────────────────────────────────────────────────────
VERSION=$(date +%Y%m%d_%H%M)
TMP_DIR="$HOME/backup_tmp"
OUT_DIR="/sdcard/Download/termux-ai-stack-releases"
REGISTRY="$HOME/.android_server_registry"
NPM_GLOBAL="${TERMUX_PREFIX}/lib/node_modules"
ROOTFS_BASE="${TERMUX_PREFIX}/var/lib/proot-distro/installed-rootfs"
SSHD_CONFIG="${TERMUX_PREFIX}/etc/ssh/sshd_config"

# ── Módulo objetivo (vacío = todos) ──────────────────────────
TARGET_MODULE=""

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --module) shift; TARGET_MODULE="$1" ;;
      --full)   TARGET_MODULE="full" ;;
      *) error "Argumento desconocido: $1\n  USO: bash ~/backup.sh [--module <módulo>] [--full]" ;;
    esac
    shift
  done

  if [ -n "$TARGET_MODULE" ]; then
    case "$TARGET_MODULE" in
      base|claude|expo|ollama|n8n|proot|remote|full) ;;
      *) error "Módulo inválido: '$TARGET_MODULE'\n  Válidos: base | claude | expo | ollama | n8n | proot | remote | full" ;;
    esac
  fi
}
parse_args "$@"

should_run() {
  [ -z "$TARGET_MODULE" ] || [ "$TARGET_MODULE" = "$1" ] || [ "$TARGET_MODULE" = "full" ]
}

# ── Detectar proot ────────────────────────────────────────────
DISTRO_NAME=""
ROOTFS_PATH=""
if [ -d "$ROOTFS_BASE" ]; then
  for d in "$ROOTFS_BASE"/*/; do
    if [ -f "${d}bin/bash" ]; then
      DISTRO_NAME=$(basename "$d")
      ROOTFS_PATH="$d"
      break
    fi
  done
fi

# ── Detectar módulos instalados ───────────────────────────────
HAS_CLAUDE=false
HAS_EAS=false
HAS_OLLAMA=false
HAS_N8N=false
HAS_PROOT=false
HAS_REMOTE=false

[ -d "${NPM_GLOBAL}/@anthropic-ai/claude-code" ] && HAS_CLAUDE=true
[ -d "${NPM_GLOBAL}/eas-cli" ]                   && HAS_EAS=true
command -v ollama &>/dev/null                    && HAS_OLLAMA=true
[ -n "$DISTRO_NAME" ]                            && HAS_PROOT=true

if $HAS_PROOT; then
  proot-distro login "$DISTRO_NAME" -- bash -c 'command -v n8n &>/dev/null' 2>/dev/null && HAS_N8N=true
fi

# Remote: existe si hay sshd_config o dashboard_server.py
{ [ -f "$SSHD_CONFIG" ] || [ -f "$HOME/dashboard_server.py" ]; } && HAS_REMOTE=true

# ── Cleanup ───────────────────────────────────────────────────
cleanup() {
  [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
  echo -e "\n  ${YELLOW}[AVISO]${NC} Backup interrumpido — archivos temporales eliminados"
}
trap cleanup INT TERM

# ════════════════════════════════════════════════════════════
# CABECERA
# ════════════════════════════════════════════════════════════
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════════╗
  ║   termux-ai-stack · Backup v2.3.0               ║
  ║   Genera archivos para GitHub Releases          ║
  ╚══════════════════════════════════════════════════╝
HEADER
echo -e "${NC}"
[ -n "$TARGET_MODULE" ] && echo -e "  ${CYAN}Modo:${NC} backup individual → ${BOLD}$TARGET_MODULE${NC}\n"

if ! touch /sdcard/Download/.backup_test 2>/dev/null; then
  error "Sin permiso de escritura en /sdcard\n  Ajustes → Apps → Termux → Permisos → Almacenamiento"
fi
rm -f /sdcard/Download/.backup_test 2>/dev/null

echo "  Versión del backup : $VERSION"
echo "  Destino final      : $OUT_DIR"
echo ""
echo "  Módulos detectados:"
echo -e "  ${GREEN}✓${NC} Termux base (siempre)"
$HAS_CLAUDE  && echo -e "  ${GREEN}✓${NC} Claude Code" || echo -e "  ${YELLOW}○${NC} Claude Code     (se omitirá)"
$HAS_EAS     && echo -e "  ${GREEN}✓${NC} Expo / EAS CLI" || echo -e "  ${YELLOW}○${NC} Expo / EAS CLI  (se omitirá)"
$HAS_OLLAMA  && echo -e "  ${GREEN}✓${NC} Ollama" || echo -e "  ${YELLOW}○${NC} Ollama          (se omitirá)"
$HAS_N8N     && echo -e "  ${GREEN}✓${NC} n8n + cloudflared" || echo -e "  ${YELLOW}○${NC} n8n             (se omitirá)"
$HAS_PROOT   && echo -e "  ${GREEN}✓${NC} Proot Debian ($DISTRO_NAME)" || echo -e "  ${YELLOW}○${NC} Proot Debian    (se omitirá)"
$HAS_REMOTE  && echo -e "  ${GREEN}✓${NC} Remote (SSH + Dashboard)" || echo -e "  ${YELLOW}○${NC} Remote          (configs mínimas)"
echo ""
echo -e "  ${YELLOW}⚠${NC}  Detén n8n y ollama antes de continuar"
$HAS_PROOT && echo -e "  ${YELLOW}⚠${NC}  part6 (rootfs Debian) puede tardar 10-20 min"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRMAR < /dev/tty
[ "$CONFIRMAR" != "s" ] && [ "$CONFIRMAR" != "S" ] && { echo "Cancelado."; exit 0; }

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

GENERATED=()

make_part() {
  local name="$1"
  local src="$2"
  shift 2
  local out="$TMP_DIR/${name}-${VERSION}.tar.xz"
  info "Comprimiendo $name..."
  tar -cJf "$out" -C "$src" "$@" 2>/dev/null
  if [ -f "$out" ] && [ -s "$out" ]; then
    SIZE=$(du -h "$out" | cut -f1)
    log "${name} → $SIZE"
    GENERATED+=("$out")
    return 0
  else
    warn "${name} falló o quedó vacío"
    rm -f "$out"
    return 1
  fi
}

# ════════════════════════════════════════════════════════════
# PARTE 0 — Termux base (RENOMBRADO de part1, ahora es part0)
# Incluye: scripts, configs, tema, registry
# Es el paquete de instalación rápida — lo primero que se restaura
# ════════════════════════════════════════════════════════════
if should_run "base"; then
titulo "PARTE 0 — Termux base (paquete instalación rápida)"

P0_TMP="$TMP_DIR/base_pack"
mkdir -p "$P0_TMP/home" "$P0_TMP/termux_config"

# Scripts principales
for f in \
  menu.sh backup.sh restore.sh instalar.sh \
  install_n8n.sh install_claude.sh install_ollama.sh \
  install_expo.sh install_python.sh install_ssh.sh \
  install_remote.sh \
  start_servidor.sh stop_servidor.sh ver_url.sh \
  n8n_status.sh n8n_log.sh n8n_update.sh \
  cf_token.sh debian.sh \
  ollama_start.sh ollama_stop.sh \
  eas_build.sh eas_status.sh eas_submit.sh \
  git_push.sh expo_info.sh
  # NOTA: ssh_start.sh, ssh_stop.sh, dashboard_*.sh y dashboard_server.py
  # NO van en part0 — van en part7-remote para no falsear el estado del menú
do
  [ -f "$HOME/$f" ] && cp "$HOME/$f" "$P0_TMP/home/$f"
done

# Registry — solo claves base, NO claves de módulos específicos
# Los módulos (ssh, dashboard, claude, etc.) guardan su propio estado
# en sus respectivas partes (part2, part7, etc.)
if [ -f "$REGISTRY" ]; then
  # Filtrar claves de módulos — solo guardar claves globales/base
  grep -v "^ssh\.\|^dashboard\.\|^claude_code\.\|^ollama\.\|^n8n\.\|^expo\.\|^python\."     "$REGISTRY" > "$P0_TMP/home/.android_server_registry" 2>/dev/null ||     touch "$P0_TMP/home/.android_server_registry"
  info "Registry base guardado (sin claves de módulos específicos)"
fi

# Configs de Termux (tema + fuente + extra-keys)
[ -d "$HOME/.termux" ] && cp -r "$HOME/.termux" "$P0_TMP/termux_config/"

# .bashrc (solo el bloque de termux-ai-stack)
if [ -f "$HOME/.bashrc" ]; then
  # Extraer solo el bloque relevante para no traer basura del sistema
  cp "$HOME/.bashrc" "$P0_TMP/home/.bashrc"
fi

# .env_n8n (configuración webhook si existe)
[ -f "$HOME/.env_n8n" ] && cp "$HOME/.env_n8n" "$P0_TMP/home/.env_n8n"

# Manifest de restauración
cat > "$P0_TMP/RESTORE.txt" << EOF
# termux-ai-stack · part0-termux-base
# Versión: $VERSION
# Fecha: $(date)
#
# CONTENIDO: Scripts bash + configs Termux + registry
# RESTAURACIÓN MANUAL:
#   tar -xJf part0-termux-base-*.tar.xz -C ~/restore_tmp/
#   cp restore_tmp/home/*.sh ~/
#   cp restore_tmp/home/*.py ~/
#   cp -r restore_tmp/termux_config/.termux ~/.termux
#   cp restore_tmp/home/.bashrc ~/.bashrc
#   cp restore_tmp/home/.android_server_registry ~/
#   chmod +x ~/*.sh
#
# INSTALACIÓN RÁPIDA (primera vez):
#   bash restore.sh --module base --source github
EOF

# Contar archivos
SCRIPTS_COUNT=$(ls "$P0_TMP/home/"*.sh 2>/dev/null | wc -l)
info "Scripts incluidos: $SCRIPTS_COUNT"

# Empaquetar todo junto
make_part "part0-termux-base" "$P0_TMP" "home" "termux_config" "RESTORE.txt"
rm -rf "$P0_TMP"
fi # end should_run base

# ════════════════════════════════════════════════════════════
# PARTE 2 — Claude Code
# ════════════════════════════════════════════════════════════
if should_run "claude"; then
titulo "PARTE 2 — Claude Code"

if ! $HAS_CLAUDE; then
  skip "Claude Code no encontrado — omitiendo part2"
else
  P2_TMP="$TMP_DIR/claude_pack"
  mkdir -p "$P2_TMP/npm_modules"
  cp -r "${NPM_GLOBAL}/@anthropic-ai" "$P2_TMP/npm_modules/"

  # Incluir wrapper si existe
  WRAPPER="${TERMUX_PREFIX}/bin/claude"
  [ -f "$WRAPPER" ] && cp "$WRAPPER" "$P2_TMP/claude_wrapper"

  cat > "$P2_TMP/RESTORE.txt" << EOF
# termux-ai-stack · part2-claude-code
# Versión: $VERSION
#
# RESTAURACIÓN:
#   cp -r npm_modules/@anthropic-ai $(npm root -g 2>/dev/null)/
#   # Re-crear wrapper:
#   CLI=\$(npm root -g)/@anthropic-ai/claude-code/cli.js
#   echo '#!/data/data/com.termux/files/usr/bin/bash' > $TERMUX_PREFIX/bin/claude
#   echo "exec node \$CLI \"\\\$@\"" >> $TERMUX_PREFIX/bin/claude
#   chmod +x $TERMUX_PREFIX/bin/claude
EOF

  SIZE=$(du -sh "${NPM_GLOBAL}/@anthropic-ai" 2>/dev/null | cut -f1)
  info "Tamaño: $SIZE"

  ITEMS=("npm_modules" "RESTORE.txt")
  [ -f "$P2_TMP/claude_wrapper" ] && ITEMS+=("claude_wrapper")
  make_part "part2-claude-code" "$P2_TMP" "${ITEMS[@]}"
  rm -rf "$P2_TMP"
fi
fi # end should_run claude

# ════════════════════════════════════════════════════════════
# PARTE 3 — Expo / EAS CLI
# ════════════════════════════════════════════════════════════
if should_run "expo"; then
titulo "PARTE 3 — Expo / EAS CLI"

if ! $HAS_EAS; then
  skip "eas-cli no encontrado — omitiendo part3"
else
  P3_TMP="$TMP_DIR/expo_pack"
  mkdir -p "$P3_TMP/npm_modules" "$P3_TMP/home"
  cp -r "${NPM_GLOBAL}/eas-cli" "$P3_TMP/npm_modules/"
  [ -d "$HOME/.expo" ] && cp -r "$HOME/.expo" "$P3_TMP/home/.expo"

  cat > "$P3_TMP/RESTORE.txt" << EOF
# termux-ai-stack · part3-eas-expo
# Versión: $VERSION
#
# RESTAURACIÓN:
#   cp -r npm_modules/eas-cli $NPM_GLOBAL/
#   [ -d home/.expo ] && cp -r home/.expo ~/
#   ln -sf $NPM_GLOBAL/eas-cli/bin/eas $TERMUX_PREFIX/bin/eas
#   chmod +x $TERMUX_PREFIX/bin/eas
EOF

  SIZE=$(du -sh "$P3_TMP" 2>/dev/null | cut -f1)
  info "Tamaño: $SIZE"
  make_part "part3-eas-expo" "$P3_TMP" "npm_modules" "home" "RESTORE.txt"
  rm -rf "$P3_TMP"
fi
fi # end should_run expo

# ════════════════════════════════════════════════════════════
# PARTE 4 — Ollama (sin modelos)
# ════════════════════════════════════════════════════════════
if should_run "ollama"; then
titulo "PARTE 4 — Ollama (sin modelos)"

if ! $HAS_OLLAMA; then
  skip "Ollama no encontrado — omitiendo part4"
else
  P4_TMP="$TMP_DIR/ollama_pack"
  mkdir -p "$P4_TMP/bin" "$P4_TMP/home"
  cp "${TERMUX_PREFIX}/bin/ollama" "$P4_TMP/bin/"
  [ -d "${TERMUX_PREFIX}/lib/ollama" ] && cp -r "${TERMUX_PREFIX}/lib/ollama" "$P4_TMP/lib_ollama"
  for f in ollama_start.sh ollama_stop.sh; do
    [ -f "$HOME/$f" ] && cp "$HOME/$f" "$P4_TMP/home/"
  done

  cat > "$P4_TMP/RESTORE.txt" << EOF
# termux-ai-stack · part4-ollama
# Versión: $VERSION
#
# NOTA: Modelos NO incluidos — descargar con: ollama pull qwen2.5:0.5b
# RESTAURACIÓN:
#   cp bin/ollama $TERMUX_PREFIX/bin/ollama
#   chmod +x $TERMUX_PREFIX/bin/ollama
#   [ -d lib_ollama ] && cp -r lib_ollama $TERMUX_PREFIX/lib/ollama
#   cp home/*.sh ~/  &&  chmod +x ~/ollama_start.sh ~/ollama_stop.sh
EOF

  SIZE=$(du -sh "$P4_TMP" 2>/dev/null | cut -f1)
  info "Tamaño: $SIZE"
  ITEMS=("bin" "home" "RESTORE.txt")
  [ -d "$P4_TMP/lib_ollama" ] && ITEMS+=("lib_ollama")
  make_part "part4-ollama" "$P4_TMP" "${ITEMS[@]}"
  rm -rf "$P4_TMP"
fi
fi # end should_run ollama

# ════════════════════════════════════════════════════════════
# PARTE 5 — n8n + cloudflared (desde proot)
# ════════════════════════════════════════════════════════════
if should_run "n8n"; then
titulo "PARTE 5 — n8n + cloudflared"

if ! $HAS_N8N; then
  skip "n8n no encontrado en proot — omitiendo part5"
else
  info "Exportando desde proot ($DISTRO_NAME)..."

  proot-distro login "$DISTRO_NAME" -- bash << 'PROOT_INNER'
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ITEMS=""
[ -d /usr/local/lib/node_modules/n8n ]       && ITEMS="$ITEMS /usr/local/lib/node_modules/n8n"
[ -d /usr/local/lib/node_modules/npm ]       && ITEMS="$ITEMS /usr/local/lib/node_modules/npm"
[ -f /usr/local/bin/n8n ]                    && ITEMS="$ITEMS /usr/local/bin/n8n"
[ -f /usr/local/bin/cloudflared ]            && ITEMS="$ITEMS /usr/local/bin/cloudflared"
[ -d /root/.n8n ]                            && ITEMS="$ITEMS /root/.n8n"
[ -f /root/.bashrc ]                         && ITEMS="$ITEMS /root/.bashrc"
[ -f /root/.cf_token ]                       && ITEMS="$ITEMS /root/.cf_token"
[ -f /usr/local/bin/node ]                   && ITEMS="$ITEMS /usr/local/bin/node"
[ -d /usr/local/lib/node_modules/npm ]       && ITEMS="$ITEMS /usr/local/lib/node_modules/npm"

if [ -z "$ITEMS" ]; then
  echo "[ERROR] No se encontraron archivos de n8n"
  exit 1
fi

echo "Empaquetando: $ITEMS"
tar -cJf /tmp/n8n_backup.tar.xz $ITEMS 2>/dev/null && \
  echo "[DONE]" || { echo "[FAIL]"; exit 1; }
PROOT_INNER

  N8N_EXPORT="${ROOTFS_PATH}tmp/n8n_backup.tar.xz"
  if [ -f "$N8N_EXPORT" ] && [ -s "$N8N_EXPORT" ]; then
    mv "$N8N_EXPORT" "$TMP_DIR/part5-n8n-data-${VERSION}.tar.xz"
    SIZE=$(du -h "$TMP_DIR/part5-n8n-data-${VERSION}.tar.xz" | cut -f1)
    log "part5-n8n-data → $SIZE"
    GENERATED+=("$TMP_DIR/part5-n8n-data-${VERSION}.tar.xz")
  else
    warn "No se pudo exportar n8n desde el proot"
    info "Verifica: proot-distro login $DISTRO_NAME -- n8n --version"
  fi
fi
fi # end should_run n8n

# ════════════════════════════════════════════════════════════
# PARTE 6 — Proot Debian rootfs completo
# ════════════════════════════════════════════════════════════
if should_run "proot"; then
titulo "PARTE 6 — Proot Debian (rootfs completo)"

if ! $HAS_PROOT; then
  skip "Proot Debian no encontrado — omitiendo part6"
else
  ROOTFS_SIZE=$(du -sh "$ROOTFS_PATH" 2>/dev/null | cut -f1)
  echo "  Rootfs    : $ROOTFS_PATH"
  echo "  Tamaño    : $ROOTFS_SIZE (sin comprimir)"
  echo -e "  ${YELLOW}Tiempo estimado: 10-20 min — mantén la pantalla encendida${NC}"
  echo ""
  echo -n "  ¿Crear part6 ahora? (s/n): "
  read -r DO_PART6 < /dev/tty

  if [ "$DO_PART6" = "s" ] || [ "$DO_PART6" = "S" ]; then
    P6_OUT="$TMP_DIR/part6-proot-debian-${VERSION}.tar.xz"
    info "Comprimiendo rootfs Debian..."
    tar -cJf "$P6_OUT" -C "$ROOTFS_BASE" "$DISTRO_NAME" 2>/dev/null
    if [ -f "$P6_OUT" ] && [ -s "$P6_OUT" ]; then
      SIZE=$(du -h "$P6_OUT" | cut -f1)
      log "part6-proot-debian → $SIZE"
      GENERATED+=("$P6_OUT")
    else
      warn "No se pudo crear part6"
      rm -f "$P6_OUT"
    fi
  else
    info "part6 omitida"
  fi
fi
fi # end should_run proot

# ════════════════════════════════════════════════════════════
# PARTE 7 — Remote (SSH + Dashboard + Cloudflared SSH)
# NUEVO en v2.3.0
# Módulos ligeros: no incluye binarios (openssh se instala con pkg)
# Solo incluye: configuraciones, claves, scripts, tokens
# ════════════════════════════════════════════════════════════
if should_run "remote"; then
titulo "PARTE 7 — Remote (SSH + Dashboard + Cloudflared SSH)"

P7_TMP="$TMP_DIR/remote_pack"
mkdir -p "$P7_TMP/ssh_config" "$P7_TMP/ssh_keys" "$P7_TMP/dashboard" "$P7_TMP/home"

REMOTE_HAS_CONTENT=false

# ── SSH: configuración ───────────────────────────────────────
if [ -f "$SSHD_CONFIG" ]; then
  cp "$SSHD_CONFIG" "$P7_TMP/ssh_config/sshd_config"
  REMOTE_HAS_CONTENT=true
  log "sshd_config incluido"
fi

# ── SSH: authorized_keys (claves de PCs autorizados) ─────────
if [ -f "$HOME/.ssh/authorized_keys" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
  cp "$HOME/.ssh/authorized_keys" "$P7_TMP/ssh_keys/authorized_keys"
  log "authorized_keys incluido ($(wc -l < "$HOME/.ssh/authorized_keys") claves)"
fi

# ── SSH: scripts de control ───────────────────────────────────
for f in ssh_start.sh ssh_stop.sh; do
  [ -f "$HOME/$f" ] && cp "$HOME/$f" "$P7_TMP/home/$f" && REMOTE_HAS_CONTENT=true
done

# ── Cloudflared SSH token (si existe) ────────────────────────
[ -f "$HOME/.cf_ssh_token" ] && cp "$HOME/.cf_ssh_token" "$P7_TMP/ssh_config/.cf_ssh_token" && \
  log ".cf_ssh_token incluido"

# ── Dashboard: servidor y scripts ────────────────────────────
for f in dashboard_server.py dashboard_start.sh dashboard_stop.sh; do
  if [ -f "$HOME/$f" ]; then
    cp "$HOME/$f" "$P7_TMP/dashboard/$f"
    REMOTE_HAS_CONTENT=true
    log "$f incluido"
  fi
done

# ── Dashboard: index.html si existe ──────────────────────────
[ -f "$HOME/index.html" ] && cp "$HOME/index.html" "$P7_TMP/dashboard/index.html"

if ! $REMOTE_HAS_CONTENT; then
  skip "No se encontró configuración de Remote — creando part7 vacía con README"
fi

cat > "$P7_TMP/RESTORE.txt" << EOF
# termux-ai-stack · part7-remote
# Versión: $VERSION
# Fecha: $(date)
#
# CONTENIDO:
#   ssh_config/sshd_config    → configuración SSH (puerto 8022)
#   ssh_keys/authorized_keys  → claves de PCs autorizados
#   ssh_config/.cf_ssh_token  → token Cloudflare tunnel SSH (si existe)
#   dashboard/                → dashboard_server.py + scripts
#   home/ssh_start.sh         → script inicio SSH
#   home/ssh_stop.sh          → script detener SSH
#
# NOTA: Los binarios (openssh, python3) se reinstalan con pkg/pip
#       Este backup solo guarda la CONFIGURACIÓN.
#
# RESTAURACIÓN:
#   Para SSH:
#     cp ssh_config/sshd_config $TERMUX_PREFIX/etc/ssh/sshd_config
#     mkdir -p ~/.ssh && cp ssh_keys/authorized_keys ~/.ssh/
#     chmod 600 ~/.ssh/authorized_keys
#     cp home/*.sh ~/  &&  chmod +x ~/ssh_start.sh ~/ssh_stop.sh
#   Para Dashboard:
#     cp dashboard/* ~/
#     chmod +x ~/dashboard_start.sh ~/dashboard_stop.sh
EOF

make_part "part7-remote" "$P7_TMP" "ssh_config" "ssh_keys" "dashboard" "home" "RESTORE.txt"
rm -rf "$P7_TMP"
fi # end should_run remote

# ════════════════════════════════════════════════════════════
# MODO FULL
# ════════════════════════════════════════════════════════════
if [ "$TARGET_MODULE" = "full" ]; then
  titulo "BACKUP COMPLETO — Todo en un solo archivo"
  echo -e "  ${YELLOW}${BOLD}⚠  Este backup incluye TODO incluyendo rootfs Debian${NC}"
  echo -e "  ${YELLOW}Tamaño estimado: ~1-1.5GB | Tiempo: 20-40 min${NC}"
  echo ""
  echo -n "  ¿Continuar con backup completo? (s/n): "
  read -r DO_FULL < /dev/tty
  [ "$DO_FULL" != "s" ] && [ "$DO_FULL" != "S" ] && {
    echo "Cancelado."
    rm -rf "$TMP_DIR"
    exit 0
  }

  FULL_OUT="$TMP_DIR/termux-ai-stack-full-${VERSION}.tar.xz"
  info "Comprimiendo \$HOME completo..."
  tar -cJf "$FULL_OUT" -C "$HOME" \
    --exclude="backup_tmp" \
    --exclude="restore_tmp" \
    --exclude=".cache" \
    --exclude="claude_tmp*" \
    --exclude="claude_extract*" \
    . 2>/dev/null
  if [ -f "$FULL_OUT" ] && [ -s "$FULL_OUT" ]; then
    SIZE=$(du -h "$FULL_OUT" | cut -f1)
    log "termux-ai-stack-full → $SIZE"
    GENERATED+=("$FULL_OUT")
  fi
fi

# ════════════════════════════════════════════════════════════
# CHECKSUMS SHA256
# ════════════════════════════════════════════════════════════
titulo "Generando checksums"

CHECKSUMS_TMP="$TMP_DIR/checksums-${VERSION}.txt"
{
  echo "# termux-ai-stack — SHA256 checksums"
  echo "# Versión : $VERSION"
  echo "# Fecha   : $(date)"
  echo "# Arch    : $(uname -m)"
  echo ""
  echo "# TABLA DE PARTES (permanente):"
  echo "# part0 = termux-base   (scripts + tema + configs)"
  echo "# part2 = claude-code   (npm @anthropic-ai/claude-code)"
  echo "# part3 = eas-expo      (eas-cli + credenciales)"
  echo "# part4 = ollama        (binario, sin modelos)"
  echo "# part5 = n8n-data      (n8n + cloudflared dentro de proot)"
  echo "# part6 = proot-debian  (rootfs Debian completo)"
  echo "# part7 = remote        (SSH configs + Dashboard)"
  echo "# NOTA: part1 no existe (reservado por compatibilidad con versiones anteriores)"
  echo ""
} > "$CHECKSUMS_TMP"

for f in "$TMP_DIR"/*.tar.xz; do
  [ -f "$f" ] || continue
  SHA=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)
  echo "$SHA  $(basename "$f")" >> "$CHECKSUMS_TMP"
  log "$(basename "$f"): ${SHA:0:20}..."
done

# ════════════════════════════════════════════════════════════
# MOVER A /sdcard/Download/
# ════════════════════════════════════════════════════════════
titulo "Moviendo archivos a /sdcard/Download/"

mkdir -p "$OUT_DIR"
MOVED=0
FAILED=0

for f in "$TMP_DIR"/*.tar.xz "$TMP_DIR"/*.txt; do
  [ -f "$f" ] || continue
  DEST="$OUT_DIR/$(basename "$f")"
  if [ -f "$DEST" ]; then
    warn "Ya existe: $(basename "$f")"
    echo -n "  ¿Sobreescribir? (s/n): "
    read -r OW < /dev/tty
    [ "$OW" != "s" ] && [ "$OW" != "S" ] && { info "Omitido"; continue; }
    rm -f "$DEST"
  fi
  mv "$f" "$DEST" 2>/dev/null && {
    log "→ $(basename "$f")"
    MOVED=$((MOVED + 1))
  } || {
    warn "No se pudo mover: $(basename "$f")"
    FAILED=$((FAILED + 1))
  }
done

rm -rf "$TMP_DIR"
trap - INT TERM

# ════════════════════════════════════════════════════════════
# RESUMEN FINAL
# ════════════════════════════════════════════════════════════
titulo "BACKUP COMPLETADO"

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════════╗
  ║     termux-ai-stack · Backup generado ✓         ║
  ╚══════════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  Archivos en: $OUT_DIR/"
echo ""
for f in "$OUT_DIR"/*.tar.xz "$OUT_DIR"/*.txt; do
  [ -f "$f" ] || continue
  SIZE=$(du -h "$f" | cut -f1)
  printf "  ${GREEN}✓${NC} %-8s %s\n" "$SIZE" "$(basename "$f")"
done

echo ""
TOTAL=$(du -sh "$OUT_DIR" 2>/dev/null | cut -f1)
echo "  Total: $TOTAL"
echo ""
echo -e "${CYAN}${BOLD}  ════════════════════════════════════════════"
echo    "  CÓMO SUBIR A GITHUB RELEASES"
echo -e "  ════════════════════════════════════════════${NC}"
echo    "  1. github.com → Honkonx/termux-ai-stack → Releases"
echo    "  2. Draft a new release"
echo    "  3. Tag: v$(date +%Y.%m.%d)"
echo    "  4. Sube los .tar.xz + checksums.txt"
echo    "  5. Publish release"
echo ""
echo -e "  ${CYAN}PAQUETES LIGEROS (no subir a GitHub — se reinstalan con pkg):${NC}"
echo    "  Python, SSH binario, Dashboard binario"
echo -e "  ${CYAN}Solo sube las CONFIGURACIONES en part7-remote${NC}"
echo ""
[ "$FAILED" -gt 0 ] && warn "$FAILED archivo(s) no se pudieron mover a /sdcard"

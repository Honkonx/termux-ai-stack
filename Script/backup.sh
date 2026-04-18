#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · backup.sh
#  Crea backups por módulo para subir a GitHub Releases
#
#  USO:
#    bash ~/backup.sh                    → backup completo
#    bash ~/backup.sh --module n8n       → solo part5-n8n-data
#    bash ~/backup.sh --module claude    → solo part2-claude-code
#    bash ~/backup.sh --module ollama    → solo part4-ollama
#    bash ~/backup.sh --module expo      → solo part3-eas-expo
#    bash ~/backup.sh --module base      → solo part1-termux-base
#
#  FLUJO:
#    1. Crea archivos en ~/backup_tmp/ (trabajo temporal)
#    2. Mueve todo a /sdcard/Download/termux-ai-stack-releases/
#    3. Limpia ~/backup_tmp/
#
#  PARTES GENERADAS (si el módulo existe):
#    part1-termux-base    → .bashrc + .termux + scripts + registry
#    part2-claude-code    → npm @anthropic-ai/claude-code completo
#    part3-eas-expo       → npm eas-cli + credenciales ~/.expo/
#    part4-ollama         → binario + libs + scripts (sin modelos)
#    part5-n8n-data       → n8n modules + cloudflared + workflows
#    part6-proot-debian   → rootfs Debian completo (~600MB-1GB)
#    checksums.txt        → SHA256 de todos los archivos
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: 2.2.0 | Abril 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Colores ──────────────────────────────────────────────────
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

# ── Módulo objetivo (vacío = todos) ──────────────────────────
TARGET_MODULE=""

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --module)
        shift
        TARGET_MODULE="$1"
        ;;
      --full)
        TARGET_MODULE="full"
        ;;
      *)
        error "Argumento desconocido: $1\n  USO: bash ~/backup.sh [--module <módulo>] [--full]"
        ;;
    esac
    shift
  done

  if [ -n "$TARGET_MODULE" ]; then
    case "$TARGET_MODULE" in
      base|claude|expo|ollama|n8n|proot|full) ;;
      *)
        error "Módulo inválido: '$TARGET_MODULE'\n  Válidos: base | claude | expo | ollama | n8n | proot | full"
        ;;
    esac
  fi
}
parse_args "$@"

# Helper: devuelve 0 si el módulo debe ejecutarse
should_run() {
  [ -z "$TARGET_MODULE" ] || [ "$TARGET_MODULE" = "$1" ] || [ "$TARGET_MODULE" = "full" ]
}

# ── Detectar proot instalado ──────────────────────────────────
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

# ── Cleanup si se interrumpe ──────────────────────────────────
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
  ║   termux-ai-stack · Backup v2.2.0               ║
  ║   Genera archivos para GitHub Releases          ║
  ╚══════════════════════════════════════════════════╝
HEADER
echo -e "${NC}"
[ -n "$TARGET_MODULE" ] && \
  echo -e "  ${CYAN}Modo:${NC} backup individual → ${BOLD}$TARGET_MODULE${NC}\n"

# ── Verificar permisos /sdcard ────────────────────────────────
if ! touch /sdcard/Download/.backup_test 2>/dev/null; then
  error "Sin permiso de escritura en /sdcard\n  Ajustes → Apps → Termux → Permisos → Almacenamiento"
fi
rm -f /sdcard/Download/.backup_test 2>/dev/null

# ── Detectar módulos por existencia real (no solo registry) ──
HAS_CLAUDE=false
HAS_EAS=false
HAS_OLLAMA=false
HAS_N8N=false
HAS_PROOT=false

[ -d "${NPM_GLOBAL}/@anthropic-ai/claude-code" ] && HAS_CLAUDE=true
[ -d "${NPM_GLOBAL}/eas-cli" ]                   && HAS_EAS=true
command -v ollama &>/dev/null                    && HAS_OLLAMA=true
[ -n "$DISTRO_NAME" ]                            && HAS_PROOT=true

# Detectar n8n dentro del proot (solo si proot existe)
if $HAS_PROOT; then
  proot-distro login "$DISTRO_NAME" -- \
    bash -c 'command -v n8n &>/dev/null' 2>/dev/null && HAS_N8N=true
fi

# ── Mostrar resumen ───────────────────────────────────────────
echo "  Versión del backup : $VERSION"
echo "  Carpeta temporal   : $TMP_DIR"
echo "  Destino final      : $OUT_DIR"
echo ""
echo "  Módulos detectados:"

$HAS_CLAUDE && echo -e "  ${GREEN}✓${NC} Claude Code" || \
  echo -e "  ${YELLOW}○${NC} Claude Code     (no encontrado — se omitirá)"
$HAS_EAS    && echo -e "  ${GREEN}✓${NC} Expo / EAS CLI" || \
  echo -e "  ${YELLOW}○${NC} Expo / EAS CLI  (no encontrado — se omitirá)"
$HAS_OLLAMA && echo -e "  ${GREEN}✓${NC} Ollama" || \
  echo -e "  ${YELLOW}○${NC} Ollama          (no encontrado — se omitirá)"
$HAS_N8N    && echo -e "  ${GREEN}✓${NC} n8n + cloudflared" || \
  echo -e "  ${YELLOW}○${NC} n8n             (no encontrado en proot — se omitirá)"
$HAS_PROOT  && echo -e "  ${GREEN}✓${NC} Proot Debian ($DISTRO_NAME)" || \
  echo -e "  ${YELLOW}○${NC} Proot Debian    (no encontrado — se omitirá)"

echo ""
echo -e "  ${YELLOW}⚠${NC}  Detén n8n y ollama antes de continuar"
$HAS_PROOT && \
  echo -e "  ${YELLOW}⚠${NC}  part6 (rootfs Debian) puede tardar 10-20 min"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRMAR
[ "$CONFIRMAR" != "s" ] && [ "$CONFIRMAR" != "S" ] && { echo "Cancelado."; exit 0; }

# ── Crear directorio temporal ─────────────────────────────────
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# ── Helper: comprimir y registrar ────────────────────────────
GENERATED=()

make_part() {
  local name="$1"   # ej: part1-termux-base
  local src="$2"    # directorio base para tar -C
  shift 2           # resto = items a empaquetar

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
# PARTE 1 — Termux base
# ════════════════════════════════════════════════════════════
if should_run "base"; then
titulo "PARTE 1 — Termux base"

P1_FILES=()
for f in \
  .bashrc \
  .termux \
  .android_server_registry \
  menu.sh \
  backup.sh \
  install_n8n.sh \
  install_claude.sh \
  install_ollama.sh \
  install_expo.sh \
  start_servidor.sh \
  stop_servidor.sh \
  ver_url.sh \
  n8n_status.sh \
  n8n_log.sh \
  n8n_update.sh \
  cf_token.sh \
  debian.sh \
  ollama_start.sh \
  ollama_stop.sh \
  eas_build.sh \
  eas_status.sh \
  eas_submit.sh \
  git_push.sh \
  expo_info.sh
do
  [ -e "$HOME/$f" ] && P1_FILES+=("$f")
done

info "${#P1_FILES[@]} archivos encontrados en ~/"
make_part "part1-termux-base" "$HOME" "${P1_FILES[@]}"
fi # end should_run base

# ════════════════════════════════════════════════════════════
# PARTE 2 — Claude Code
# ════════════════════════════════════════════════════════════
if should_run "claude"; then
titulo "PARTE 2 — Claude Code"

if ! $HAS_CLAUDE; then
  skip "Claude Code no encontrado — omitiendo part2"
else
  SIZE=$(du -sh "${NPM_GLOBAL}/@anthropic-ai" 2>/dev/null | cut -f1)
  info "Tamaño: $SIZE"

  # Crear estructura con manifest de restauración
  P2_TMP="$TMP_DIR/claude_pack"
  mkdir -p "$P2_TMP/npm_modules"
  cp -r "${NPM_GLOBAL}/@anthropic-ai" "$P2_TMP/npm_modules/"

  cat > "$P2_TMP/RESTORE.txt" << EOF
# termux-ai-stack · Claude Code backup
# Versión: $VERSION
#
# RESTAURACIÓN:
#   cp -r npm_modules/@anthropic-ai $NPM_GLOBAL/
#   # Re-crear alias en .bashrc:
#   CLI=\$(npm root -g)/@anthropic-ai/claude-code/cli.js
#   echo "alias claude='node \$CLI'" >> ~/.bashrc
EOF

  make_part "part2-claude-code" "$P2_TMP" "npm_modules" "RESTORE.txt"
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
# termux-ai-stack · Expo/EAS backup
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
  [ -d "${TERMUX_PREFIX}/lib/ollama" ] && \
    cp -r "${TERMUX_PREFIX}/lib/ollama" "$P4_TMP/lib_ollama"

  for f in ollama_start.sh ollama_stop.sh; do
    [ -f "$HOME/$f" ] && cp "$HOME/$f" "$P4_TMP/home/"
  done

  cat > "$P4_TMP/RESTORE.txt" << EOF
# termux-ai-stack · Ollama backup
# Versión: $VERSION
#
# RESTAURACIÓN:
#   cp bin/ollama $TERMUX_PREFIX/bin/ollama
#   chmod +x $TERMUX_PREFIX/bin/ollama
#   [ -d lib_ollama ] && cp -r lib_ollama $TERMUX_PREFIX/lib/ollama
#   cp home/*.sh ~/  &&  chmod +x ~/ollama_start.sh ~/ollama_stop.sh
#
# NOTA: Modelos NO incluidos — descargar con: ollama pull qwen:0.5b
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
titulo "PARTE 6 — Proot Debian (rootfs completo)"

if ! should_run "proot"; then
  : # skip si no aplica
elif ! $HAS_PROOT; then
  skip "Proot Debian no encontrado — omitiendo part6"
else
  ROOTFS_SIZE=$(du -sh "$ROOTFS_PATH" 2>/dev/null | cut -f1)
  echo "  Rootfs    : $ROOTFS_PATH"
  echo "  Tamaño    : $ROOTFS_SIZE (sin comprimir)"
  echo -e "  ${YELLOW}Tiempo estimado: 10-20 min — mantén la pantalla encendida${NC}"
  echo ""
  echo -n "  ¿Crear part6 ahora? (s/n): "
  read -r DO_PART6

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

# ════════════════════════════════════════════════════════════
# MODO FULL — Todo en un solo archivo
# ════════════════════════════════════════════════════════════
if [ "$TARGET_MODULE" = "full" ]; then
  titulo "BACKUP COMPLETO — Todo en un solo archivo"

  FULL_OUT="$TMP_DIR/termux-ai-stack-full-${VERSION}.tar.xz"

  echo -e "  ${YELLOW}${BOLD}⚠  ADVERTENCIA${NC}"
  echo -e "  Este backup incluye TODO:"
  echo -e "  ▸ \$HOME completo (scripts, configs, Node modules)"
  if $HAS_PROOT; then
    ROOTFS_SIZE=$(du -sh "$ROOTFS_PATH" 2>/dev/null | cut -f1)
    echo -e "  ▸ Rootfs Debian ($ROOTFS_SIZE sin comprimir)"
  fi
  echo ""
  echo -e "  ${YELLOW}Tamaño estimado: ~1-1.5GB comprimido"
  echo -e "  Tiempo estimado: 20-40 min"
  echo -e "  Mantén la pantalla encendida.${NC}"
  echo ""
  echo -n "  ¿Continuar con backup completo? (s/n): "
  read -r DO_FULL

  if [ "$DO_FULL" != "s" ] && [ "$DO_FULL" != "S" ]; then
    echo "Cancelado."
    rm -rf "$TMP_DIR"
    exit 0
  fi

  info "Empaquetando \$HOME..."
  FULL_ITEMS=()

  # $HOME completo excepto carpetas temporales y el propio tmp de backup
  for item in "$HOME"/*/  "$HOME"/.*  "$HOME"/*.sh  "$HOME"/*.txt  "$HOME"/*.md; do
    base=$(basename "$item")
    # Excluir directorios temporales
    case "$base" in
      backup_tmp|restore_tmp|.cache|.local|.) continue ;;
    esac
    [ -e "$item" ] && FULL_ITEMS+=("$base")
  done

  info "Comprimiendo \$HOME (puede tardar varios minutos)..."
  tar -cJf "$FULL_OUT.home.tmp" -C "$HOME" --exclude="backup_tmp" \
    --exclude="restore_tmp" --exclude=".cache" . 2>/dev/null

  if $HAS_PROOT; then
    info "Comprimiendo rootfs Debian (10-20 min más)..."
    tar -cJf "$FULL_OUT.proot.tmp" -C "$ROOTFS_BASE" "$DISTRO_NAME" 2>/dev/null
  fi

  # Combinar en un solo archive con estructura clara
  FULL_STAGE="$TMP_DIR/full_stage"
  mkdir -p "$FULL_STAGE/home" "$FULL_STAGE/proot"

  info "Unificando archivos..."
  tar -xJf "$FULL_OUT.home.tmp" -C "$FULL_STAGE/home" 2>/dev/null
  rm -f "$FULL_OUT.home.tmp"

  if $HAS_PROOT && [ -f "$FULL_OUT.proot.tmp" ]; then
    tar -xJf "$FULL_OUT.proot.tmp" -C "$FULL_STAGE/proot" 2>/dev/null
    rm -f "$FULL_OUT.proot.tmp"
  fi

  info "Comprimiendo archivo final..."
  tar -cJf "$FULL_OUT" -C "$TMP_DIR" "full_stage" 2>/dev/null
  rm -rf "$FULL_STAGE"

  if [ -f "$FULL_OUT" ] && [ -s "$FULL_OUT" ]; then
    SIZE=$(du -h "$FULL_OUT" | cut -f1)
    log "termux-ai-stack-full → $SIZE"
    GENERATED+=("$FULL_OUT")
  else
    warn "No se pudo crear el backup completo"
    rm -f "$FULL_OUT"
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
} > "$CHECKSUMS_TMP"

for f in "$TMP_DIR"/*.tar.xz; do
  [ -f "$f" ] || continue
  SHA=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)
  echo "$SHA  $(basename "$f")" >> "$CHECKSUMS_TMP"
  log "$(basename "$f"): ${SHA:0:20}..."
done

# ════════════════════════════════════════════════════════════
# MOVER TODO A /sdcard/Download/
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
    read -r OW
    if [ "$OW" != "s" ] && [ "$OW" != "S" ]; then
      info "Omitido: $(basename "$f")"
      continue
    fi
    rm -f "$DEST"
  fi

  mv "$f" "$DEST" 2>/dev/null && {
    log "→ $OUT_DIR/$(basename "$f")"
    MOVED=$((MOVED + 1))
  } || {
    warn "No se pudo mover: $(basename "$f")"
    FAILED=$((FAILED + 1))
  }
done

# Limpiar tmp
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

P6_FILE="$OUT_DIR/part6-proot-debian-${VERSION}.tar.xz"
if [ -f "$P6_FILE" ]; then
  P6_SIZE=$(du -h "$P6_FILE" | cut -f1)
  echo -e "  ${YELLOW}⚠${NC}  part6 ($P6_SIZE) — límite GitHub Releases: 2GB"
  echo    "  Si falla al subir, usa Git LFS o Cloudflare R2"
  echo ""
fi

[ "$FAILED" -gt 0 ] && \
  warn "$FAILED archivo(s) no se pudieron mover a /sdcard"

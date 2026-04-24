#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_claude.sh
#  Instala Claude Code en Termux nativo (ARM64, sin root)
#
#  USO STANDALONE:
#    bash install_claude.sh
#
#  QUÉ HACE:
#    ✅ Actualiza Termux (solo si no lo hizo el maestro)
#    ✅ Verifica/instala Node.js >= 18
#    ✅ Instala @anthropic-ai/claude-code@2.1.111 vía npm
#    ✅ Crea wrapper ejecutable en PREFIX/bin
#    ✅ Escribe estado al registry ~/.android_server_registry
#
#  ESTRATEGIAS DE INSTALACIÓN (en orden de prioridad):
#    1. npm install @2.1.111 SIN --ignore-scripts  ← CONFIRMADO QUE FUNCIONA
#       Probado manualmente en POCO F5 · ARM64 · Termux
#    2. npm install @2.1.111 CON --ignore-scripts
#       Fallback si el postinstall falla por algún motivo
#    3. Descarga directa del tarball desde npmjs.com
#       Sin pasar por npm en absoluto
#    4. Reparación: npm instala el dir pero cli.js quedó roto
#       Descarga solo cli.js desde el tar del GitHub Release
#
#  NOTA TÉCNICA ARM64:
#    Claude Code incluye binarios x86/x64 incompatibles con ARM64.
#    Solución: wrapper que invoca cli.js directamente con node.
#    Probado en POCO F5 · Android 15 · ARM64 · Bionic libc.
#
#  VERSIÓN FIJA: @2.1.111
#    Versiones superiores pueden usar binario nativo incompatible
#    con Bionic libc. Actualizar solo tras verificar compatibilidad.
#
#  VERSIÓN: 2.9.0 | Abril 2026
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

# ── Archivos de estado ────────────────────────────────────────
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_claude_checkpoint"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Helper: ruta de cli.js ────────────────────────────────────
find_cli() {
  # 1. Leer desde wrapper si existe — ruta exacta donde instaló
  local wrapper="$TERMUX_PREFIX/bin/claude"
  if [ -f "$wrapper" ]; then
    local cli_from_wrapper
    cli_from_wrapper=$(grep "node " "$wrapper" 2>/dev/null | grep "cli\.js" |       grep -oE '/[^ "]+cli\.js' | head -1)
    [ -n "$cli_from_wrapper" ] && [ -f "$cli_from_wrapper" ] && {
      echo "$cli_from_wrapper"; return
    }
  fi
  # 2. Rutas conocidas en Termux
  local KNOWN=(
    "/data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js"
    "$HOME/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js"
  )
  for p in "${KNOWN[@]}"; do
    [ -f "$p" ] && { echo "$p"; return; }
  done
  # 3. Fallback npm root -g
  local npm_root; npm_root=$(npm root -g 2>/dev/null)
  echo "${npm_root}/@anthropic-ai/claude-code/cli.js"
}

# ── Validar que cli.js es JS real (no wrapper bash) ──────────
# Retorna 0 si válido, 1 si inválido
validate_cli() {
  local cli_path="$1"
  [ -f "$cli_path" ] && [ -s "$cli_path" ] || return 1
  # Verificar que node puede ejecutarlo sin SyntaxError
  node "$cli_path" --version 2>&1 | grep -qv "SyntaxError\|not found\|No such" || return 1
  # Verificar que la primera línea es JS (no bash)
  local first_line
  first_line=$(head -1 "$cli_path" 2>/dev/null)
  echo "$first_line" | grep -q "^#!/.*bash" && return 1
  return 0
}

# ── Función: actualizar registry ─────────────────────────────
update_registry() {
  local version="$1"
  local date_now
  date_now=$(date +%Y-%m-%d)

  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"

  local tmp="$REGISTRY.tmp"
  grep -v "^claude_code\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"

  cat >> "$tmp" << EOF
claude_code.installed=true
claude_code.version=${version}
claude_code.install_date=${date_now}
claude_code.commands=claude,claude -p,claude --continue,claude --version
claude_code.port=none
claude_code.location=termux_native
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado → $REGISTRY"
}

# ════════════════════════════════════════════════════════════
# CABECERA
# ════════════════════════════════════════════════════════════
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · Claude Code Installer  ║
  ║   v2.9.0 · Termux ARM64 · sin root         ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado y válido ───────────────────
CLI_PATH=$(find_cli)
if validate_cli "$CLI_PATH"; then
  CURRENT_VERSION=$(node "$CLI_PATH" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  echo -e "${GREEN}  ✓ Claude Code instalado y funcional${NC}"
  echo -e "  Versión: ${CYAN}${CURRENT_VERSION}${NC}"
  echo ""
  echo -n "  ¿Reinstalar de todas formas? (s/n): "
  read -r REINSTALL < /dev/tty
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
elif [ -f "$CLI_PATH" ]; then
  # El archivo existe pero no es JS válido
  FIRST_LINE=$(head -1 "$CLI_PATH" 2>/dev/null)
  if echo "$FIRST_LINE" | grep -q "^#!/.*bash"; then
    warn "cli.js es un wrapper bash (npm instaló versión incompatible)"
  else
    warn "cli.js existe pero falla al ejecutar con node"
  fi
  warn "Forzando reinstalación limpia..."
  rm -f "$CHECKPOINT"
fi

echo ""
echo "  Este script instalará:"
echo "  ▸ @anthropic-ai/claude-code v2.1.111"
echo "  ▸ Wrapper /usr/bin/claude (workaround ARM64)"
echo "  ▸ Alias de respaldo en .bashrc"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRM < /dev/tty
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 1 — Actualizar Termux (solo si no lo hizo instalar.sh)
# ============================================================
titulo "PASO 1 — Verificando Termux"

if [ -n "$ANDROID_SERVER_READY" ]; then
  log "Termux ya preparado por instalar.sh [skip]"
elif check_done "termux_update"; then
  log "Termux ya actualizado [checkpoint]"
else
  info "Modo standalone — actualizando Termux..."

  MIRRORS=(
    "https://packages.termux.dev/apt/termux-main"
    "https://mirror.accum.se/mirror/termux.dev/apt/termux-main"
    "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
  )

  try_update() {
    pkg update -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>&1
  }

  set_mirror() {
    echo "deb $1 stable main" > "$TERMUX_PREFIX/etc/apt/sources.list"
    info "Mirror: $1"
  }

  OUT=$(try_update)
  if echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
    warn "Mirror roto — probando alternativas..."
    OK=0
    for m in "${MIRRORS[@]}"; do
      set_mirror "$m"
      OUT=$(try_update)
      if ! echo "$OUT" | grep -q "unexpected size\|Mirror sync in progress\|Err:2"; then
        log "Mirror OK: $m"; OK=1; break
      fi
    done
    [ "$OK" = "0" ] && error "Todos los mirrors fallaron. Verifica tu conexión."
  fi

  for dep in curl wget git; do
    command -v "$dep" &>/dev/null || pkg install "$dep" -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>/dev/null
  done

  log "Termux actualizado"
  mark_done "termux_update"
fi

# ============================================================
# PASO 2 — Verificar / Instalar Node.js >= 18
# ============================================================
titulo "PASO 2 — Node.js"

if check_done "nodejs"; then
  log "Node.js ya verificado [checkpoint]"
else
  if command -v node &>/dev/null; then
    NODE_VER=$(node --version 2>/dev/null | sed 's/v//' | cut -d'.' -f1)
    if [ "$NODE_VER" -ge 18 ] 2>/dev/null; then
      log "Node.js $(node --version) ✓ (compatible con Claude Code)"
    else
      warn "Node.js $(node --version) — versión < 18, actualizando..."
      pkg install nodejs-lts -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || \
        error "Error instalando nodejs-lts."
      log "Node.js actualizado: $(node --version)"
    fi
  else
    info "Node.js no encontrado — instalando nodejs-lts..."
    pkg install nodejs-lts -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      error "Error instalando nodejs-lts."
    log "Node.js instalado: $(node --version)"
  fi

  command -v npm &>/dev/null || error "npm no encontrado. Reinstala con: pkg install nodejs"
  log "npm $(npm --version) ✓"
  mark_done "nodejs"
fi

# ============================================================
# PASO 3 — Instalar Claude Code
# ============================================================
titulo "PASO 3 — Instalando Claude Code"

# Saltar si ya hay checkpoint válido
_CLI_CHECK=$(find_cli)
_SKIP_INSTALL=false
if check_done "claude_npm" && validate_cli "$_CLI_CHECK"; then
  log "Claude Code ya instalado y válido [checkpoint]"
  _SKIP_INSTALL=true
elif check_done "claude_npm"; then
  warn "Checkpoint existente pero cli.js inválido — reinstalando..."
  sed -i '/^claude_npm$/d' "$CHECKPOINT" 2>/dev/null || true
fi

if [ "$_SKIP_INSTALL" = "false" ]; then

  NPM_ROOT=$(npm root -g 2>/dev/null)
  CLAUDE_DIR="$NPM_ROOT/@anthropic-ai/claude-code"
  CLAUDE_VERSION="2.1.111"

  # ── Limpieza completa previa ──────────────────────────────────
  info "Limpiando instalación anterior..."
  npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
  npm cache clean --force 2>/dev/null || true
  rm -rf "$CLAUDE_DIR" 2>/dev/null || true
  echo ""

  CLAUDE_OK=false

  # ════════════════════════════════════════════════════════════
  # ESTRATEGIA 1 — npm install SIN --ignore-scripts
  # ════════════════════════════════════════════════════════════
  # CONFIRMADO: Esta es la estrategia que funciona en ARM64/Bionic.
  # Sin --ignore-scripts npm ejecuta el postinstall correctamente
  # y cli.js queda como JavaScript válido (no wrapper bash).
  # Probado manualmente en POCO F5 · Android 15 · npm 10.x
  # ════════════════════════════════════════════════════════════
  info "Estrategia 1: npm install @${CLAUDE_VERSION} (sin --ignore-scripts)..."
  echo ""

  # --save-exact fuerza npm v11 a instalar exactamente @2.1.111 sin resolver a otra versión
  npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION} --save-exact 2>&1 | tail -8

  # Verificar que npm instaló la versión correcta (npm v11 puede resolver diferente)
  INSTALLED_VER=$(node "$(find_cli)" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -n "$INSTALLED_VER" ] && [ "$INSTALLED_VER" != "$CLAUDE_VERSION" ]; then
    warn "npm instaló v${INSTALLED_VER} en lugar de v${CLAUDE_VERSION} — forzando versión exacta..."
    npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION} --force --save-exact 2>&1 | tail -5
  fi
  echo ""

  CLI_PATH_NEW=$(find_cli)

  if validate_cli "$CLI_PATH_NEW"; then
    CLAUDE_OK=true
    log "Estrategia 1 exitosa ✓"
    log "cli.js válido — versión: $(node "$CLI_PATH_NEW" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  else
    warn "Estrategia 1 falló — cli.js no válido después de npm install"
    if [ -f "$CLI_PATH_NEW" ]; then
      FIRST=$(head -1 "$CLI_PATH_NEW" 2>/dev/null)
      warn "Primera línea del cli.js: ${FIRST:0:60}"
    fi
  fi

  # ════════════════════════════════════════════════════════════
  # ESTRATEGIA 2 — npm install CON --ignore-scripts
  # ════════════════════════════════════════════════════════════
  # Segundo intento: omite el postinstall.
  # Útil si el postinstall sobreescribe cli.js con un wrapper bash.
  # En algunos entornos la Estrategia 1 funciona, en otros esta.
  # ════════════════════════════════════════════════════════════
  if [ "$CLAUDE_OK" = "false" ]; then
    warn "Estrategia 2: npm install --ignore-scripts..."
    echo ""

    # Limpiar antes del segundo intento
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
    npm cache clean --force 2>/dev/null || true
    rm -rf "$CLAUDE_DIR" 2>/dev/null || true
    echo ""

    npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION} --ignore-scripts 2>&1 | tail -8
    echo ""

    CLI_PATH_NEW=$(find_cli)

    if validate_cli "$CLI_PATH_NEW"; then
      CLAUDE_OK=true
      log "Estrategia 2 exitosa ✓"
    else
      warn "Estrategia 2 también falló"
    fi
  fi

  # ════════════════════════════════════════════════════════════
  # ESTRATEGIA 3 — Tarball directo desde npmjs.com
  # ════════════════════════════════════════════════════════════
  # Descarga el .tgz oficial de npmjs sin pasar por el cliente npm.
  # Evita cualquier problema con el cliente npm o postinstall.
  # URL: registry.npmjs.org (siempre disponible, sin autenticación)
  # ════════════════════════════════════════════════════════════
  if [ "$CLAUDE_OK" = "false" ]; then
    warn "Estrategia 3: tarball directo desde registry.npmjs.org..."
    echo ""

    NPMJS_URL="https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${CLAUDE_VERSION}.tgz"
    TMP_TGZ="$HOME/claude_npm_direct.tgz"
    TMP_EXTRACT="$HOME/claude_extract_direct"

    info "Descargando claude-code-${CLAUDE_VERSION}.tgz desde npmjs.com..."
    curl -fL --progress-bar "$NPMJS_URL" -o "$TMP_TGZ" 2>/dev/null

    if [ -f "$TMP_TGZ" ] && [ -s "$TMP_TGZ" ]; then
      TGZ_SIZE=$(du -h "$TMP_TGZ" | cut -f1)
      log "Descargado: $TGZ_SIZE"

      mkdir -p "$TMP_EXTRACT"
      tar -xzf "$TMP_TGZ" -C "$TMP_EXTRACT" 2>/dev/null

      # El tgz de npmjs descomprime en ./package/
      if [ -f "$TMP_EXTRACT/package/cli.js" ]; then
        mkdir -p "$CLAUDE_DIR"
        cp -r "$TMP_EXTRACT/package/." "$CLAUDE_DIR/"
        CLI_PATH_NEW=$(find_cli)

        if validate_cli "$CLI_PATH_NEW"; then
          CLAUDE_OK=true
          log "Estrategia 3 exitosa — instalado desde npmjs.com ✓"
        else
          warn "cli.js copiado pero no validó"
          # Mostrar primeras líneas para diagnóstico
          info "Primeras líneas del cli.js:"
          head -3 "$CLI_PATH_NEW" 2>/dev/null | while read -r l; do echo "    $l"; done
        fi
      else
        warn "El tgz no contenía cli.js en ./package/"
        info "Contenido del tgz:"
        tar -tzf "$TMP_TGZ" 2>/dev/null | head -10 | while read -r l; do echo "    $l"; done
      fi
    else
      warn "Descarga del tarball falló o archivo vacío"
      info "URL intentada: $NPMJS_URL"
    fi

    rm -rf "$TMP_EXTRACT" "$TMP_TGZ" 2>/dev/null
  fi

  # ════════════════════════════════════════════════════════════
  # ESTRATEGIA 4 — Reparar cli.js desde GitHub Releases
  # ════════════════════════════════════════════════════════════
  # Solo aplica si npm instaló el directorio pero cli.js quedó roto.
  # Descarga part2-claude-code del último release y extrae solo cli.js.
  # Depende de que haya un release válido en el repo de GitHub.
  # ════════════════════════════════════════════════════════════
  if [ "$CLAUDE_OK" = "false" ] && [ -d "$CLAUDE_DIR" ]; then
    warn "Estrategia 4: reparar cli.js desde GitHub Releases..."
    echo ""

    RELEASE_API="https://api.github.com/repos/Honkonx/termux-ai-stack/releases/latest"
    info "Consultando GitHub API..."
    CLI_URL=$(curl -fsSL "$RELEASE_API" 2>/dev/null | \
      grep -o '"browser_download_url": *"[^"]*part2-claude[^"]*"' | \
      grep -o 'https://[^"]*' | head -1)

    if [ -n "$CLI_URL" ]; then
      info "Descargando part2-claude-code..."
      TMP_TAR="$HOME/claude_gh_release.tar.xz"
      curl -fL --progress-bar "$CLI_URL" -o "$TMP_TAR" 2>/dev/null

      if [ -f "$TMP_TAR" ] && [ -s "$TMP_TAR" ]; then
        TMP_EXTRACT="$HOME/claude_extract_gh"
        mkdir -p "$TMP_EXTRACT"
        tar -xJf "$TMP_TAR" -C "$TMP_EXTRACT" 2>/dev/null

        CLI_FROM_GH="$TMP_EXTRACT/npm_modules/@anthropic-ai/claude-code/cli.js"
        if [ -f "$CLI_FROM_GH" ]; then
          cp "$CLI_FROM_GH" "$CLAUDE_DIR/cli.js"
          chmod +x "$CLAUDE_DIR/cli.js"
          CLI_PATH_NEW=$(find_cli)

          if validate_cli "$CLI_PATH_NEW"; then
            CLAUDE_OK=true
            log "Estrategia 4 exitosa — cli.js reparado desde GitHub Releases ✓"
          else
            warn "cli.js de GitHub Release tampoco validó"
          fi
        else
          warn "El release no contenía cli.js en npm_modules/@anthropic-ai/claude-code/"
        fi
        rm -rf "$TMP_EXTRACT" "$TMP_TAR"
      else
        warn "Descarga del release falló"
      fi
    else
      warn "No se encontró part2-claude-code en el release de GitHub"
    fi
  fi

  # ── Resultado final ───────────────────────────────────────────
  if [ "$CLAUDE_OK" = "false" ]; then
    echo ""
    echo -e "${RED}${BOLD}[ERROR]${NC} Claude Code no instaló correctamente en ninguna estrategia."
    echo ""
    echo -e "  ${CYAN}Diagnóstico:${NC}"
    echo "  npm root -g  → $NPM_ROOT"
    echo "  Espacio ~/   → $(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
    echo "  Node.js      → $(node --version 2>/dev/null)"
    echo "  npm          → $(npm --version 2>/dev/null)"
    echo "  cli.js       → $(ls -la "$CLI_PATH_NEW" 2>/dev/null || echo 'no existe')"
    echo ""
    echo -e "  ${CYAN}Prueba manual (Opción A — la que funcionó):${NC}"
    echo "  npm uninstall -g @anthropic-ai/claude-code"
    echo "  npm cache clean --force"
    echo "  npm install -g @anthropic-ai/claude-code@2.1.111"
    echo "  node \$(npm root -g)/@anthropic-ai/claude-code/cli.js --version"
    echo ""
    echo -e "  ${CYAN}Si todo falla:${NC}"
    echo "  bash ~/restore.sh --module claude --source github"
    exit 1
  fi

  mark_done "claude_npm"
fi

# ============================================================
# PASO 4 — Crear wrapper ejecutable + alias
# ============================================================
titulo "PASO 4 — Configurando comando claude"

if check_done "claude_alias"; then
  log "Comando claude ya configurado [checkpoint]"
else
  CLI_FINAL=$(find_cli)

  if [ ! -f "$CLI_FINAL" ]; then
    error "cli.js no existe en $CLI_FINAL — algo falló en el Paso 3"
  fi

  # ── Wrapper ejecutable en PREFIX/bin ─────────────────────────
  # Está en PATH siempre — no requiere source ni reabrir sesión.
  # Persiste entre reinicios y reinstalaciones de pkg.
  WRAPPER="$TERMUX_PREFIX/bin/claude"
  cat > "$WRAPPER" << WRAPPER_SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
# termux-ai-stack wrapper — ARM64 Bionic
# DISABLE_AUTOUPDATER: evita que claude-code se auto-actualice a versiones
# incompatibles con Bionic libc (ej: v2.1.112+ usa binario nativo que falla)
# Documentación oficial: https://code.claude.com/docs/en/setup
export DISABLE_AUTOUPDATER=1
export DISABLE_UPDATES=1
exec node "${CLI_FINAL}" "\$@"
WRAPPER_SCRIPT
  chmod +x "$WRAPPER"
  log "Wrapper ejecutable → $WRAPPER (auto-update desactivado)"

  # Crear ~/.claude/settings.json con autoUpdates desactivado
  # Esto bloquea el auto-update desde la configuración interna de claude-code
  mkdir -p "$HOME/.claude"
  CLAUDE_SETTINGS="$HOME/.claude/settings.json"
  if [ -f "$CLAUDE_SETTINGS" ]; then
    # Preservar settings existentes pero desactivar autoUpdates
    # Inyectar la clave si no existe
    if ! grep -q '"autoUpdates"' "$CLAUDE_SETTINGS" 2>/dev/null; then
      # Insertar antes del último "}"
      sed -i 's/}$/,"autoUpdates": false}/' "$CLAUDE_SETTINGS" 2>/dev/null || true
    fi
  else
    cat > "$CLAUDE_SETTINGS" << 'CLAUDE_SETTINGS_JSON'
{
  "autoUpdates": false,
  "env": {
    "DISABLE_AUTOUPDATER": "1",
    "DISABLE_UPDATES": "1"
  }
}
CLAUDE_SETTINGS_JSON
  fi
  log "~/.claude/settings.json configurado (autoUpdates: false)"

  # ── Alias en .bashrc (respaldo para sesiones interactivas) ────
  BASHRC="$HOME/.bashrc"
  if [ -f "$BASHRC" ]; then
    grep -v "alias claude=\|alias claude-update=" "$BASHRC" > "$BASHRC.tmp" 2>/dev/null && mv "$BASHRC.tmp" "$BASHRC"
  fi

  cat >> "$BASHRC" << ALIASES

# ════════════════════════════════
#  Claude Code · alias ARM64
# ════════════════════════════════
# DISABLE_AUTOUPDATER=1 evita que claude-code se actualice automáticamente
# a versiones incompatibles con Bionic libc (ARM64 Termux)
alias claude='DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 node ${CLI_FINAL}'
alias claude-update='npm uninstall -g @anthropic-ai/claude-code 2>/dev/null; npm cache clean --force; npm install -g @anthropic-ai/claude-code@2.1.111 --save-exact && echo "Claude Code actualizado a v2.1.111"'
alias claude-check='node ${CLI_FINAL} --version 2>/dev/null && echo "CLI: OK" || echo "CLI: ERROR - reinstala con: bash ~/install_claude.sh"'
ALIASES

  log "Alias respaldo en .bashrc configurado"
  source "$BASHRC" 2>/dev/null || true

  mark_done "claude_alias"
fi

# ============================================================
# PASO 5 — Actualizar registry
# ============================================================
titulo "PASO 5 — Actualizando registry"

CLI_REG=$(find_cli)
VERSION_REG=$(node "$CLI_REG" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$VERSION_REG" ] && VERSION_REG="unknown"
update_registry "$VERSION_REG"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

CLI_SHOW=$(find_cli)
VERSION_SHOW=$(node "$CLI_SHOW" --version 2>/dev/null | head -1)

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║     Claude Code instalado con éxito ✓       ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  Versión:   ${VERSION_SHOW}"
echo "  Node.js:   $(node --version)"
echo "  Wrapper:   $TERMUX_PREFIX/bin/claude"
echo ""
echo "  COMANDOS:"
echo "  claude                  → agente interactivo"
echo "  claude --version        → ver versión"
echo "  claude -p \"instrucción\" → modo directo (headless)"
echo "  claude --continue       → continuar sesión anterior"
echo "  claude-update           → reinstalar v2.1.111"
echo ""
echo -e "${YELLOW}  NOTAS ARM64:${NC}"
echo "  · El comando 'claude' usa un wrapper que invoca node directamente"
echo "  · cli.js está en: $(find_cli)"
echo "  · Si vuelve a fallar: bash install_claude.sh para reinstalar"
echo ""
echo -e "${YELLOW}  PRIMER USO:${NC}"
echo "  1. Escribe 'claude' y presiona Enter"
echo "  2. Acepta los términos de uso"
echo "  3. Autentícate con tu cuenta Claude Pro"
echo ""
if [ -z "$ANDROID_SERVER_READY" ]; then
  echo -e "${CYAN}  TIP: ejecuta 'menu' para abrir el dashboard${NC}"
  echo ""
fi

rm -f "$CHECKPOINT"

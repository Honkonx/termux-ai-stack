#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · install_openclaude.sh
#  Instala @gitlawb/openclaude en Termux nativo (sin proot)
#  Configura proveedor de IA (Ollama local, Anthropic,
#  DeepSeek, OpenRouter u otro compatible con OpenAI API)
#
#  USO STANDALONE:
#    bash install_openclaude.sh
#
#  QUÉ HACE:
#    ✅ Verifica / instala Node.js en Termux nativo
#    ✅ npm install -g @gitlawb/openclaude (con fallback --ignore-scripts)
#    ✅ Configura proveedor de IA vía variables de entorno
#    ✅ Crea alias oc en .bashrc
#    ✅ Escribe estado al registry ~/.android_server_registry
#
#  NOTA TÉCNICA:
#    OpenClaude es un wrapper de Claude Code que acepta cualquier
#    API compatible con OpenAI (CLAUDE_CODE_USE_OPENAI=1).
#    Corre en Termux nativo — NO requiere proot.
#    Compatible con Ollama local (:11434), Anthropic, DeepSeek,
#    OpenRouter, o cualquier endpoint OpenAI-compatible.
#
#  VERSIÓN: 1.0.0 | Mayo 2026
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()    { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "  ${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "  ${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "  ${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }

# ── Archivos de estado ────────────────────────────────────────
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_openclaude_checkpoint"

check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# ── Registry helpers ─────────────────────────────────────────
get_reg() {
  [ -f "$REGISTRY" ] || return
  grep "^${1}\.${2}=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2- | tail -1
}

update_registry() {
  local version="$1" provider="$2" model="$3"
  local date_now; date_now=$(date +%Y-%m-%d)
  [ ! -f "$REGISTRY" ] && touch "$REGISTRY"
  local tmp="$REGISTRY.tmp"
  grep -v "^openclaude\." "$REGISTRY" > "$tmp" 2>/dev/null || touch "$tmp"
  cat >> "$tmp" << EOF
openclaude.installed=true
openclaude.version=$version
openclaude.provider=$provider
openclaude.model=$model
openclaude.install_date=$date_now
openclaude.location=termux_native
EOF
  mv "$tmp" "$REGISTRY"
  log "Registry actualizado"
}

# ── Leer config actual del .bashrc ───────────────────────────
_read_current_provider() {
  [ -f "$HOME/.bashrc" ] || return
  grep "^export OPENAI_BASE_URL=" "$HOME/.bashrc" | tail -1 | cut -d'=' -f2-
}

_read_current_model() {
  [ -f "$HOME/.bashrc" ] || return
  grep "^export OPENAI_MODEL=" "$HOME/.bashrc" | tail -1 | cut -d'=' -f2-
}

# ── Escribir proveedor en .bashrc ────────────────────────────
_write_provider() {
  local base_url="$1" api_key="$2" model="$3"
  # Limpiar config anterior de openclaude
  grep -v "# openclaude-provider\|CLAUDE_CODE_USE_OPENAI\|OPENAI_BASE_URL\|OPENAI_API_KEY\|OPENAI_MODEL" \
    "$HOME/.bashrc" > "$HOME/.bashrc.tmp" 2>/dev/null && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
  {
    echo ""
    echo "# openclaude-provider"
    echo "export CLAUDE_CODE_USE_OPENAI=1"
    echo "export OPENAI_BASE_URL=${base_url}"
    [ -n "$api_key" ] && echo "export OPENAI_API_KEY=${api_key}"
    echo "export OPENAI_MODEL=${model}"
  } >> "$HOME/.bashrc"
  # Aplicar en sesión actual
  export CLAUDE_CODE_USE_OPENAI=1
  export OPENAI_BASE_URL="$base_url"
  [ -n "$api_key" ] && export OPENAI_API_KEY="$api_key"
  export OPENAI_MODEL="$model"
}

# ── Cabecera ─────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
cat << 'HEADER'
  ╔══════════════════════════════════════════════╗
  ║   termux-ai-stack · OpenClaude Installer   ║
  ║   Termux nativo ARM64 · sin proot          ║
  ╚══════════════════════════════════════════════╝
HEADER
echo -e "${NC}"

# ── Verificar si ya está instalado ───────────────────────────
if command -v openclaude &>/dev/null; then
  OCL_VER=$(npm list -g @gitlawb/openclaude 2>/dev/null \
    | grep openclaude | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$OCL_VER" ] && OCL_VER=$(get_reg openclaude version)
  [ -z "$OCL_VER" ] && OCL_VER="?"
  CURRENT_PROV=$(_read_current_provider)
  CURRENT_MODEL=$(_read_current_model)
  echo -e "${GREEN}  ✓ OpenClaude ya está instalado — v${OCL_VER}${NC}"
  [ -n "$CURRENT_PROV" ] && echo -e "  Proveedor: ${CYAN}${CURRENT_PROV}${NC}"
  [ -n "$CURRENT_MODEL" ] && echo -e "  Modelo:    ${CYAN}${CURRENT_MODEL}${NC}"
  echo ""
  echo -n "  ¿Reinstalar / cambiar proveedor? (s/n): "
  read -r REINSTALL < /dev/tty
  [ "$REINSTALL" != "s" ] && [ "$REINSTALL" != "S" ] && {
    info "Nada que hacer. Saliendo."
    exit 0
  }
  rm -f "$CHECKPOINT"
fi

echo ""
echo "  Este script instalará OpenClaude en Termux nativo:"
echo "  ▸ npm install -g @gitlawb/openclaude"
echo "  ▸ Configura proveedor de IA (Ollama, Anthropic, etc.)"
echo "  ▸ Crea alias: oc → openclaude"
echo ""
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRM < /dev/tty
[ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ] && { echo "Cancelado."; exit 0; }

# ============================================================
# PASO 1 — Verificar Node.js y npm
# ============================================================
titulo "PASO 1 — Verificando Node.js"

if check_done "node_ok"; then
  log "Node.js ya verificado [checkpoint]"
else
  if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
    info "Instalando nodejs-lts..."
    pkg install -y nodejs-lts \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || \
      error "No se pudo instalar nodejs-lts"
    log "Node.js instalado: $(node --version)"
  else
    log "Node.js disponible: $(node --version) · npm: $(npm --version)"
  fi
  mark_done "node_ok"
fi

# ============================================================
# PASO 2 — Instalar OpenClaude
# ============================================================
titulo "PASO 2 — Instalando @gitlawb/openclaude"

if check_done "openclaude_installed"; then
  log "OpenClaude ya instalado [checkpoint]"
else
  export GYP_DEFINES="android_ndk_path=''"
  export ANDROID_API_LEVEL=24

  OCL_OK=false

  # Estrategia 1: npm directo
  info "npm install -g @gitlawb/openclaude..."
  if npm install -g @gitlawb/openclaude 2>&1 | tail -5; then
    command -v openclaude &>/dev/null && OCL_OK=true
  fi

  # Estrategia 2: --ignore-scripts
  if [ "$OCL_OK" = "false" ]; then
    warn "Reintentando con --ignore-scripts..."
    npm uninstall -g @gitlawb/openclaude 2>/dev/null || true
    npm cache clean --force 2>/dev/null || true
    if npm install -g @gitlawb/openclaude --ignore-scripts 2>&1 | tail -5; then
      command -v openclaude &>/dev/null && OCL_OK=true
    fi
  fi

  [ "$OCL_OK" = "false" ] && \
    error "Instalación fallida — verifica tu conexión e intenta de nuevo"

  OCL_VER=$(npm list -g @gitlawb/openclaude 2>/dev/null \
    | grep openclaude | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$OCL_VER" ] && OCL_VER="unknown"

  log "OpenClaude instalado: v${OCL_VER}"
  mark_done "openclaude_installed"
fi

# ============================================================
# PASO 3 — Configurar proveedor de IA
# ============================================================
titulo "PASO 3 — Configurar proveedor de IA"

if check_done "provider_configured"; then
  log "Proveedor ya configurado [checkpoint]"
else
  echo ""
  echo -e "  ${CYAN}Elige el proveedor de IA para OpenClaude:${NC}"
  echo ""
  echo -e "  ${BOLD}[1]${NC} Ollama local       ${DIM}(:11434 · gratis · modelos descargados)${NC}"
  echo -e "  ${BOLD}[2]${NC} Anthropic          ${DIM}(API oficial Claude · requiere key)${NC}"
  echo -e "  ${BOLD}[3]${NC} DeepSeek           ${DIM}(deepseek-chat · bajo costo)${NC}"
  echo -e "  ${BOLD}[4]${NC} OpenRouter         ${DIM}(multi-modelo · hay modelos gratis)${NC}"
  echo -e "  ${BOLD}[5]${NC} Otro / manual      ${DIM}(cualquier endpoint OpenAI-compatible)${NC}"
  echo -e "  ${BOLD}[b]${NC} Omitir             ${DIM}(configurar después desde el menú)${NC}"
  echo ""
  echo -n "  Proveedor: "
  read -r PROV_OPT < /dev/tty

  PROV_NAME=""
  PROV_URL=""
  PROV_KEY=""
  PROV_MODEL=""

  case "$PROV_OPT" in
    1)
      # Ollama local — verificar y listar modelos
      PROV_NAME="ollama"
      PROV_URL="http://localhost:11434/v1"
      PROV_KEY="ollama"

      if ! curl -sf http://127.0.0.1:11434 &>/dev/null; then
        warn "Ollama no responde en :11434"
        echo -e "  ${DIM}Asegúrate de iniciarlo antes de usar OpenClaude${NC}"
        echo ""
      fi

      # Listar modelos instalados
      mapfile -t OL_MODELS < <(
        curl -sf http://127.0.0.1:11434/api/tags 2>/dev/null | \
        python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  [print(m['name']) for m in d.get('models',[])]
except: pass
" 2>/dev/null)

      echo ""
      if [ ${#OL_MODELS[@]} -gt 0 ]; then
        echo -e "  ${CYAN}Modelos disponibles:${NC}"; echo ""
        for i in "${!OL_MODELS[@]}"; do
          printf "    [%d] %s\n" "$((i+1))" "${OL_MODELS[$i]}"
        done
        echo ""
        echo -n "  Número o nombre del modelo: "
        read -r ML_INPUT < /dev/tty
        if [[ "$ML_INPUT" =~ ^[0-9]+$ ]] && [ "$ML_INPUT" -ge 1 ] && \
           [ "$ML_INPUT" -le "${#OL_MODELS[@]}" ]; then
          PROV_MODEL="${OL_MODELS[$((ML_INPUT-1))]}"
        else
          PROV_MODEL="$ML_INPUT"
        fi
      else
        echo -e "  ${YELLOW}(ningún modelo instalado — usa 'ollama pull <modelo>' primero)${NC}"
        echo -n "  Escribe el nombre del modelo a usar: "
        read -r PROV_MODEL < /dev/tty
      fi
      [ -z "$PROV_MODEL" ] && PROV_MODEL="qwen2.5-coder:7b"
      ;;

    2)
      # Anthropic
      PROV_NAME="anthropic"
      PROV_URL="https://api.anthropic.com/v1"
      echo ""
      echo -e "  ${DIM}Obtén tu key en: https://console.anthropic.com${NC}"
      echo -n "  API Key (sk-ant-...): "
      read -r PROV_KEY < /dev/tty
      [ -z "$PROV_KEY" ] && warn "Sin key — la configuración puede no funcionar"
      echo ""
      echo -e "  ${CYAN}Modelos disponibles:${NC}"
      echo "    [1] claude-sonnet-4-5       (recomendado)"
      echo "    [2] claude-haiku-4-5        (rápido, bajo costo)"
      echo "    [3] claude-opus-4-5         (más capaz)"
      echo ""
      echo -n "  Número o nombre del modelo [Enter=1]: "
      read -r ML_INPUT < /dev/tty
      case "$ML_INPUT" in
        2) PROV_MODEL="claude-haiku-4-5" ;;
        3) PROV_MODEL="claude-opus-4-5" ;;
        "") PROV_MODEL="claude-sonnet-4-5" ;;
        *) PROV_MODEL="$ML_INPUT" ;;
      esac
      ;;

    3)
      # DeepSeek
      PROV_NAME="deepseek"
      PROV_URL="https://api.deepseek.com/v1"
      echo ""
      echo -e "  ${DIM}Obtén tu key en: https://platform.deepseek.com${NC}"
      echo -n "  API Key: "
      read -r PROV_KEY < /dev/tty
      [ -z "$PROV_KEY" ] && warn "Sin key — la configuración puede no funcionar"
      echo ""
      echo -e "  ${CYAN}Modelos disponibles:${NC}"
      echo "    [1] deepseek-chat           (recomendado)"
      echo "    [2] deepseek-coder          (especializado en código)"
      echo "    [3] deepseek-reasoner       (razonamiento)"
      echo ""
      echo -n "  Número o nombre del modelo [Enter=1]: "
      read -r ML_INPUT < /dev/tty
      case "$ML_INPUT" in
        2) PROV_MODEL="deepseek-coder" ;;
        3) PROV_MODEL="deepseek-reasoner" ;;
        "") PROV_MODEL="deepseek-chat" ;;
        *) PROV_MODEL="$ML_INPUT" ;;
      esac
      ;;

    4)
      # OpenRouter
      PROV_NAME="openrouter"
      PROV_URL="https://openrouter.ai/api/v1"
      echo ""
      echo -e "  ${DIM}Crea cuenta gratis en: https://openrouter.ai${NC}"
      echo -n "  API Key (sk-or-...): "
      read -r PROV_KEY < /dev/tty
      [ -z "$PROV_KEY" ] && warn "Sin key — la configuración puede no funcionar"
      echo ""
      echo -e "  ${CYAN}Modelos sugeridos:${NC}"
      echo "    [1] qwen/qwen3-coder:free        (gratis · 262K ctx)"
      echo "    [2] deepseek/deepseek-chat:free   (gratis)"
      echo "    [3] meta-llama/llama-3.3-70b-instruct:free (gratis)"
      echo "    [4] otro (escribe el nombre)"
      echo ""
      echo -n "  Número o nombre del modelo [Enter=1]: "
      read -r ML_INPUT < /dev/tty
      case "$ML_INPUT" in
        2) PROV_MODEL="deepseek/deepseek-chat:free" ;;
        3) PROV_MODEL="meta-llama/llama-3.3-70b-instruct:free" ;;
        4)
          echo -n "  Nombre del modelo: "
          read -r PROV_MODEL < /dev/tty ;;
        "") PROV_MODEL="qwen/qwen3-coder:free" ;;
        *) PROV_MODEL="$ML_INPUT" ;;
      esac
      ;;

    5)
      # Manual
      PROV_NAME="manual"
      echo ""
      echo -n "  Base URL (ej: http://localhost:11434/v1): "
      read -r PROV_URL < /dev/tty
      [ -z "$PROV_URL" ] && error "URL requerida"
      echo -n "  API Key (Enter si no aplica): "
      read -r PROV_KEY < /dev/tty
      echo -n "  Modelo: "
      read -r PROV_MODEL < /dev/tty
      [ -z "$PROV_MODEL" ] && error "Modelo requerido"
      ;;

    b|B|"")
      warn "Proveedor omitido — configura desde el menú: CODE TOOLS → OpenClaude → [2]"
      PROV_NAME="none"
      PROV_URL=""
      PROV_MODEL=""
      ;;

    *)
      warn "Opción inválida — proveedor omitido"
      PROV_NAME="none"
      PROV_URL=""
      PROV_MODEL=""
      ;;
  esac

  if [ -n "$PROV_URL" ] && [ -n "$PROV_MODEL" ]; then
    _write_provider "$PROV_URL" "$PROV_KEY" "$PROV_MODEL"
    log "Proveedor configurado: ${PROV_NAME} · ${PROV_MODEL}"
  else
    # Limpiar config anterior aunque no se configure uno nuevo
    grep -v "# openclaude-provider\|CLAUDE_CODE_USE_OPENAI\|OPENAI_BASE_URL\|OPENAI_API_KEY\|OPENAI_MODEL" \
      "$HOME/.bashrc" > "$HOME/.bashrc.tmp" 2>/dev/null && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
  fi

  # Guardar en checkpoint para registry
  echo "PROV_NAME=${PROV_NAME}" >> "$CHECKPOINT"
  echo "PROV_MODEL=${PROV_MODEL}" >> "$CHECKPOINT"
  mark_done "provider_configured"
fi

# ============================================================
# PASO 4 — Alias en .bashrc
# ============================================================
titulo "PASO 4 — Alias"

if check_done "alias_created"; then
  log "Alias ya configurado [checkpoint]"
else
  # Limpiar alias anterior si existe
  grep -v "^alias oc=\|# openclaude-alias" "$HOME/.bashrc" \
    > "$HOME/.bashrc.tmp" 2>/dev/null && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
  {
    echo ""
    echo "# openclaude-alias"
    echo "alias oc='openclaude'"
  } >> "$HOME/.bashrc"
  log "Alias creado: oc → openclaude"
  mark_done "alias_created"
fi

# ============================================================
# PASO 5 — Registry
# ============================================================
titulo "PASO 5 — Actualizando registry"

# Leer versión y proveedor finales
OCL_VER_FINAL=$(npm list -g @gitlawb/openclaude 2>/dev/null \
  | grep openclaude | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$OCL_VER_FINAL" ] && OCL_VER_FINAL="unknown"

FINAL_PROV=$(grep "^PROV_NAME=" "$CHECKPOINT" 2>/dev/null | tail -1 | cut -d'=' -f2-)
FINAL_MODEL=$(grep "^PROV_MODEL=" "$CHECKPOINT" 2>/dev/null | tail -1 | cut -d'=' -f2-)
[ -z "$FINAL_PROV"  ] && FINAL_PROV="none"
[ -z "$FINAL_MODEL" ] && FINAL_MODEL="none"

update_registry "$OCL_VER_FINAL" "$FINAL_PROV" "$FINAL_MODEL"

# ============================================================
# RESUMEN FINAL
# ============================================================
titulo "INSTALACIÓN COMPLETADA"

echo -e "${GREEN}${BOLD}"
cat << 'RESUMEN'
  ╔══════════════════════════════════════════════╗
  ║     OpenClaude instalado con éxito ✓       ║
  ╚══════════════════════════════════════════════╝
RESUMEN
echo -e "${NC}"

echo "  Versión:   v${OCL_VER_FINAL}"
echo "  Proveedor: ${FINAL_PROV}"
echo "  Modelo:    ${FINAL_MODEL}"
echo ""
echo "  COMANDOS:"
echo "  openclaude          → abrir OpenClaude"
echo "  oc                  → alias corto"
echo ""
echo "  DESDE EL MENÚ:"
echo "  menu → CODE TOOLS → [3] OpenClaude"
echo ""
echo -e "  ${CYAN}→ Cierra y reabre Termux (o: source ~/.bashrc) para activar alias${NC}"
echo ""

# Limpiar checkpoint
rm -f "$CHECKPOINT"

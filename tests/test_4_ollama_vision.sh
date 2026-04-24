#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · TEST 4 — Ollama visión (imágenes)
#  Valida: moondream/llava, API REST con base64, imagen desde
#          /sdcard, generación de imagen de prueba con Python
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

OK()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
FAIL() { echo -e "  ${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS+1)); }
INFO() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
SKIP() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }
ERRORS=0

OLLAMA_URL="http://localhost:11434"
# Modelos de visión en orden de preferencia (peso)
VISION_MODELS=("moondream:1.8b" "llava-phi3:3.8b" "llava:7b" "llava:13b")

clear; echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  TEST 4 — Ollama Visión (imágenes)      ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""

# ── 1. Verificar Ollama ──────────────────────────────────────
INFO "Verificando Ollama..."
curl -sf "$OLLAMA_URL" &>/dev/null || { FAIL "Ollama no responde — ejecuta: ollama serve"; exit 1; }
OK "Ollama activo"

# ── 2. Detectar modelo de visión instalado ───────────────────
INFO "Buscando modelo de visión instalado..."
INSTALLED=$(curl -sf "$OLLAMA_URL/api/tags" | python3 -c "
import json, sys
models = [m['name'] for m in json.load(sys.stdin).get('models', [])]
print('\n'.join(models))
" 2>/dev/null)

VISION_MODEL=""
for candidate in "${VISION_MODELS[@]}"; do
  if echo "$INSTALLED" | grep -q "^${candidate}$"; then
    VISION_MODEL="$candidate"
    break
  fi
done

if [ -z "$VISION_MODEL" ]; then
  echo ""
  echo -e "  ${YELLOW}No hay modelo de visión instalado.${NC}"
  echo -e "  ${BOLD}Modelos disponibles (por RAM requerida):${NC}"
  echo "    [1] moondream:1.8b   ~1.1GB  ← RECOMENDADO para POCO F5"
  echo "    [2] llava-phi3:3.8b  ~2.5GB"
  echo "    [3] llava:7b         ~4.7GB  (puede crashear)"
  echo "    [s] Skip — no descargar ahora"
  echo ""
  echo -n "  Elige [1/2/3/s]: "
  read -r CHOICE < /dev/tty
  case "$CHOICE" in
    1|"") VISION_MODEL="moondream:1.8b" ;;
    2) VISION_MODEL="llava-phi3:3.8b" ;;
    3) VISION_MODEL="llava:7b" ;;
    s|S) SKIP "Test de visión omitido por el usuario"; exit 0 ;;
  esac
  echo ""
  INFO "Descargando $VISION_MODEL..."
  ollama pull "$VISION_MODEL"
  [ $? -eq 0 ] && OK "$VISION_MODEL descargado" || { FAIL "No se pudo descargar $VISION_MODEL"; exit 1; }
else
  OK "Modelo de visión: $VISION_MODEL"
fi

# ── 3. Preparar imagen de prueba ─────────────────────────────
echo ""
INFO "Preparando imagen de prueba..."
TEST_IMG="$HOME/test_vision.jpg"

# Intentar usar foto real de /sdcard primero
REAL_IMG=""
if [ -d "/sdcard/DCIM/Camera" ]; then
  REAL_IMG=$(find /sdcard/DCIM/Camera -name "*.jpg" -o -name "*.jpeg" 2>/dev/null | head -1)
fi
[ -z "$REAL_IMG" ] && REAL_IMG=$(find /sdcard -name "*.jpg" 2>/dev/null | head -1)

if [ -n "$REAL_IMG" ]; then
  # F2: Redimensionar si la imagen es mayor a 800px — reduce tiempo de inferencia
  IMG_BYTES=$(stat -c%s "$REAL_IMG" 2>/dev/null || echo 0)
  if [ "$IMG_BYTES" -gt 500000 ]; then
    INFO "Foto real grande ($(du -h "$REAL_IMG" | cut -f1)) — redimensionando a 512px para ARM64..."
    python3 << PYEOF
import sys, os
try:
    from PIL import Image
    img = Image.open("$REAL_IMG")
    w, h = img.size
    max_dim = 512
    if w > max_dim or h > max_dim:
        ratio = min(max_dim/w, max_dim/h)
        new_w, new_h = int(w*ratio), int(h*ratio)
        img = img.resize((new_w, new_h), Image.LANCZOS)
    img.save("$TEST_IMG", "JPEG", quality=80)
    print(f"  Redimensionado: {w}x{h} → {img.size[0]}x{img.size[1]} ({os.path.getsize('$TEST_IMG')} bytes)")
except ImportError:
    # Sin Pillow: copiar y avisar
    import shutil
    shutil.copy("$REAL_IMG", "$TEST_IMG")
    print("  Sin Pillow: usando imagen original (puede ser lenta)")
except Exception as e:
    import shutil
    shutil.copy("$REAL_IMG", "$TEST_IMG")
    print(f"  Error resize: {e} — usando original")
PYEOF
    OK "Imagen preparada: $TEST_IMG ($(du -h "$TEST_IMG" | cut -f1))"
  else
    cp "$REAL_IMG" "$TEST_IMG" 2>/dev/null
    OK "Usando foto real (ya es pequeña): $REAL_IMG"
  fi
else
  # Crear imagen de prueba con Python o con convert (ImageMagick)
  python3 << 'PYEOF'
import os, sys
try:
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (320, 240), color=(30, 80, 160))
    draw = ImageDraw.Draw(img)
    draw.rectangle([20,20,300,220], outline=(255,255,255), width=4)
    draw.ellipse([60,60,160,160], fill=(255,180,0), outline=(255,255,255), width=2)
    draw.rectangle([180,80,290,190], fill=(50,200,80), outline=(255,255,255), width=2)
    path = os.path.expanduser("~/test_vision.jpg")
    img.save(path, "JPEG", quality=85)
    print(f"  Imagen creada: {path} ({os.path.getsize(path)} bytes)")
except ImportError:
    # Sin Pillow: crear imagen mínima válida via bytes JPEG
    import base64
    # JPEG 1x1 pixel rojo — mínimo válido para probar la API
    jpeg_1px = base64.b64decode(
        "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U"
        "HRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgN"
        "DRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy"
        "MjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFgABAQEAAAAAAAAAAAAAAAAABgUE/8QAIhAA"
        "AgIBBAMAAAAAAAAAAAAAAQIDBAUREiExUf/EABQBAQAAAAAAAAAAAAAAAAAAAAD/xAAUEQEA"
        "AAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCBd3lHbWyatbXoirxRqFCqOgAB6AAe2"
        "lKUClKUH/9k="
    )
    path = os.path.expanduser("~/test_vision.jpg")
    with open(path, "wb") as f:
        f.write(jpeg_1px)
    print(f"  Imagen mínima creada (sin Pillow): {path}")
PYEOF
  OK "Imagen de prueba generada"
fi

# Verificar imagen
[ -f "$TEST_IMG" ] || { FAIL "No se pudo crear imagen de prueba"; exit 1; }
IMG_SIZE=$(du -h "$TEST_IMG" | cut -f1)
IMG_BYTES=$(stat -c%s "$TEST_IMG" 2>/dev/null || echo "?")
OK "Imagen lista: $TEST_IMG ($IMG_SIZE / $IMG_BYTES bytes)"

# Advertir si sigue siendo grande
if [ "$IMG_BYTES" -gt 1000000 ] 2>/dev/null; then
  echo -e "  ${YELLOW}[AVISO]${NC} Imagen >1MB — inferencia puede tardar 2-4 min en ARM64 sin GPU"
  echo -e "  ${YELLOW}[AVISO]${NC} Instala Pillow para auto-resize: bash test_2_python.sh"
fi

# ── 4. Convertir a base64 ────────────────────────────────────
echo ""
INFO "Convirtiendo imagen a base64..."
IMG_B64=$(base64 -w 0 "$TEST_IMG" 2>/dev/null)
[ -n "$IMG_B64" ] && OK "Base64: ${#IMG_B64} chars" || { FAIL "No se pudo convertir a base64"; exit 1; }

# ── 5. Enviar a Ollama vía API REST ──────────────────────────
echo ""
INFO "Enviando imagen a $VISION_MODEL via API REST..."

# F2: timeout dinámico según tamaño — 60s por cada 100KB
IMG_KB=$(( IMG_BYTES / 1024 ))
TIMEOUT=$(( 60 + (IMG_KB * 60 / 100) ))
[ "$TIMEOUT" -gt 300 ] && TIMEOUT=300
INFO "Timeout calculado: ${TIMEOUT}s (imagen ${IMG_KB}KB)"
echo ""

# F3: prompt agresivo en español — evita que el modelo siga el idioma de la imagen
PROMPT_ES="You must respond ONLY in Spanish. Describe en español lo que ves: objetos, colores, formas. Máximo 3 oraciones en español."

START_TIME=$(date +%s)
VISION_RESP=$(curl -sf "$OLLAMA_URL/api/generate" \
  -H "Content-Type: application/json" \
  --max-time "$TIMEOUT" \
  -d "{
    \"model\": \"$VISION_MODEL\",
    \"prompt\": \"$PROMPT_ES\",
    \"images\": [\"$IMG_B64\"],
    \"stream\": false,
    \"options\": {\"num_predict\": 120, \"temperature\": 0.1}
  }" 2>/dev/null)
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

if [ -n "$VISION_RESP" ]; then
  DESCRIPTION=$(echo "$VISION_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null)
  echo -e "  ${BOLD}Descripción generada:${NC}"
  echo "  ─────────────────────────────────────"
  echo "$DESCRIPTION" | fold -s -w 60 | while read line; do echo "  $line"; done
  echo "  ─────────────────────────────────────"
  echo ""
  OK "Respuesta recibida en ${ELAPSED}s"
  [ -n "$DESCRIPTION" ] && OK "Descripción no vacía" || FAIL "Descripción vacía"
else
  FAIL "No se recibió respuesta (timeout o error) — ${ELAPSED}s"
fi

# ── 6. Test Python script independiente ──────────────────────
echo ""
INFO "Creando ~/test_vision.py (script reutilizable)..."
cat > "$HOME/test_vision.py" << PYEOF
#!/data/data/com.termux/files/usr/bin/python3
"""
test_vision.py — Analiza imágenes con Ollama
Uso: python3 test_vision.py [ruta_imagen] [pregunta]
"""
import sys, base64, requests, json, os

OLLAMA_URL = "http://localhost:11434"
VISION_MODEL = "$VISION_MODEL"

def analizar_imagen(ruta, pregunta="¿Qué ves en esta imagen? Describe en español."):
    if not os.path.exists(ruta):
        return f"ERROR: archivo no encontrado: {ruta}"
    with open(ruta, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    try:
        r = requests.post(f"{OLLAMA_URL}/api/generate", json={
            "model": VISION_MODEL,
            "prompt": pregunta,
            "images": [b64],
            "stream": False,
            "options": {"num_predict": 200, "temperature": 0.3}
        }, timeout=180)
        return r.json().get("response", "Sin respuesta").strip()
    except requests.exceptions.Timeout:
        return "ERROR: timeout (modelo muy lento para esta imagen)"
    except Exception as e:
        return f"ERROR: {e}"

def listar_modelos_vision():
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        modelos = r.json().get("models", [])
        vision = [m["name"] for m in modelos
                  if any(v in m["name"] for v in ["moondream","llava","bakllava","llama3.2-vision"])]
        return vision
    except:
        return []

if __name__ == "__main__":
    ruta = sys.argv[1] if len(sys.argv) > 1 else "$TEST_IMG"
    pregunta = sys.argv[2] if len(sys.argv) > 2 else "¿Qué ves en esta imagen?"

    print(f"Modelo: {VISION_MODEL}")
    print(f"Imagen: {ruta}")
    print(f"Pregunta: {pregunta}")
    print("─" * 50)
    resultado = analizar_imagen(ruta, pregunta)
    print(resultado)
    print("─" * 50)

    modelos = listar_modelos_vision()
    if modelos:
        print(f"\nModelos de visión disponibles: {', '.join(modelos)}")
PYEOF
chmod +x "$HOME/test_vision.py"
OK "~/test_vision.py creado"
echo -e "  Uso: ${CYAN}python3 ~/test_vision.py /sdcard/DCIM/foto.jpg \"¿Qué hay aquí?\"${NC}"

# ── 7. RAM usada ─────────────────────────────────────────────
echo ""
INFO "RAM después de inferencia de visión..."
RAM_FREE=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%.1f GB libre de %.1f GB total", $7/1024, $2/1024}')
echo "  $RAM_FREE"

# ── Cleanup ──────────────────────────────────────────────────
[ -n "$REAL_IMG" ] || rm -f "$TEST_IMG"  # solo borrar si fue imagen generada

# ── Resumen ──────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}✓ TEST 4 PASADO — Ollama visión funciona${NC}"
else
  echo -e "  ${RED}${BOLD}✗ TEST 4: $ERRORS error(s) — revisar arriba${NC}"
fi
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
echo ""
echo -e "  Modelo: ${CYAN}$VISION_MODEL${NC}"
echo -e "  Script: ${CYAN}~/test_vision.py /sdcard/foto.jpg${NC}"
echo ""

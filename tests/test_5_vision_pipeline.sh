#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · TEST 5 — Ollama visión + Python + SQLite
#  Pipeline completo local: imagen → análisis → BD → historial
#
#  NOTA ARM64: sin DEFAULT (datetime('now')) en SQLite Python.
#  HTTP: urllib builtin en lugar de requests.
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

OK()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
FAIL() { echo -e "  ${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS+1)); }
INFO() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
SKIP() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }
ERRORS=0

OLLAMA_URL="http://localhost:11434"

clear; echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo    "  ║  TEST 5 — Visión + Python + SQLite      ║"
echo    "  ║  Pipeline completo local (sin n8n)      ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"; echo ""

# ── 1. Pre-checks ────────────────────────────────────────────
INFO "Verificando dependencias del pipeline..."
curl -sf "$OLLAMA_URL" &>/dev/null && OK "Ollama activo" || { FAIL "Ollama no responde"; exit 1; }
python3 -c "import sqlite3, base64, urllib.request" 2>/dev/null && OK "Python + librerías OK" || { FAIL "Librerías Python faltantes"; exit 1; }

# Detectar modelo de visión
VISION_MODEL=$(curl -sf "$OLLAMA_URL/api/tags" | python3 -c "
import json, sys
models = [m['name'] for m in json.load(sys.stdin).get('models', [])]
for p in ['moondream:1.8b','llava-phi3:3.8b','llava:7b']:
    if p in models: print(p); break
" 2>/dev/null)

[ -n "$VISION_MODEL" ] && OK "Modelo visión: $VISION_MODEL" || { FAIL "No hay modelo de visión — ejecuta TEST 4 primero"; exit 1; }

# Detectar modelo de texto
TEXT_MODEL=$(curl -sf "$OLLAMA_URL/api/tags" | python3 -c "
import json, sys
models = [m['name'] for m in json.load(sys.stdin).get('models', [])]
for p in ['qwen2.5:0.5b','qwen2.5:1.5b','qwen:1.8b','llama3.2:1b']:
    if p in models: print(p); break
" 2>/dev/null)

[ -n "$TEXT_MODEL" ] && OK "Modelo texto: $TEXT_MODEL" || { SKIP "No hay modelo de texto — se usará solo visión"; TEXT_MODEL="$VISION_MODEL"; }

# ── 2. Crear imagen de prueba si no hay foto real ────────────
echo ""
INFO "Preparando imagen..."
TEST_IMG=""
REAL_IMG=$(find /sdcard/DCIM /sdcard/Pictures -name "*.jpg" 2>/dev/null | head -1)
if [ -n "$REAL_IMG" ]; then
  TEST_IMG="$REAL_IMG"
  # F2: redimensionar si >500KB
  IMG_BYTES=$(stat -c%s "$REAL_IMG" 2>/dev/null || echo 0)
  if [ "$IMG_BYTES" -gt 500000 ]; then
    INFO "Redimensionando foto grande a 512px..."
    python3 -c "
from PIL import Image; import os
img=Image.open('$REAL_IMG')
w,h=img.size; r=min(512/w,512/h)
img=img.resize((int(w*r),int(h*r)),Image.LANCZOS)
img.save('$HOME/pipeline_img.jpg','JPEG',quality=80)
print(f'  {w}x{h} → {img.size[0]}x{img.size[1]}')
" 2>/dev/null && TEST_IMG="$HOME/pipeline_img.jpg" \
    || { INFO "Sin Pillow — usando original"; TEST_IMG="$REAL_IMG"; }
  fi
  OK "Foto real: $TEST_IMG ($(du -h "$TEST_IMG" | cut -f1))"
else
  python3 -c "
from PIL import Image, ImageDraw
import os
img = Image.new('RGB',(400,300),(20,60,120))
d = ImageDraw.Draw(img)
d.rectangle([10,10,390,290], outline=(255,255,255), width=3)
d.ellipse([50,50,200,200], fill=(240,180,0))
d.rectangle([220,80,370,220], fill=(40,180,60))
d.text((10,270),'Test pipeline - termux-ai-stack', fill=(200,200,200))
img.save(os.path.expanduser('~/pipeline_test.jpg'),'JPEG')
print('OK')
" 2>/dev/null && TEST_IMG="$HOME/pipeline_test.jpg" && OK "Imagen generada: $TEST_IMG"
fi
[ -f "$TEST_IMG" ] || { FAIL "No hay imagen disponible"; exit 1; }

# ── 3. Pipeline completo en Python ───────────────────────────
echo ""
INFO "Ejecutando pipeline completo..."
echo ""

python3 << PYEOF
import sqlite3, base64, json, os, sys, time
from urllib import request as ureq
from datetime import datetime

OLLAMA_URL  = "http://localhost:11434"
VISION_MODEL = "$VISION_MODEL"
TEXT_MODEL   = "$TEXT_MODEL"
DB_PATH      = os.path.expanduser("~/vision_pipeline.db")
IMG_PATH     = "$TEST_IMG"

# ── Inicializar BD — sin DEFAULT (datetime('now')) ARM64 fix ─
conn = sqlite3.connect(DB_PATH)
conn.execute("""
    CREATE TABLE IF NOT EXISTS analisis_imagenes (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        ruta          TEXT,
        descripcion   TEXT,
        resumen       TEXT,
        modelo_vision TEXT,
        modelo_texto  TEXT,
        duracion_seg  REAL,
        fecha         TEXT
    )
""")
conn.execute("""
    CREATE TABLE IF NOT EXISTS tags (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        imagen_id INTEGER,
        tag       TEXT,
        FOREIGN KEY(imagen_id) REFERENCES analisis_imagenes(id)
    )
""")
conn.commit()
print("  [1/5] BD inicializada ✓")

# ── Cargar imagen ────────────────────────────────────────────
with open(IMG_PATH, "rb") as f:
    img_b64 = base64.b64encode(f.read()).decode()
img_size = os.path.getsize(IMG_PATH)
print(f"  [2/5] Imagen cargada: {os.path.basename(IMG_PATH)} ({img_size} bytes) ✓")

def _post(payload, timeout=300):
    data = json.dumps(payload).encode("utf-8")
    req = ureq.Request(
        f"{OLLAMA_URL}/api/generate",
        data=data,
        headers={"Content-Type": "application/json"}
    )
    with ureq.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())

# ── Análisis de visión ───────────────────────────────────────
print(f"  [3/5] Analizando con {VISION_MODEL}...")
t0 = time.time()
try:
    result = _post({
        "model": VISION_MODEL,
        "prompt": "You must respond ONLY in Spanish. Describe en español: objetos, colores, composición. Máximo 3 oraciones en español.",
        "images": [img_b64],
        "stream": False,
        "options": {"num_predict": 150, "temperature": 0.1}
    })
    descripcion = result.get("response", "").strip()
    duracion = time.time() - t0
    print(f"       Descripción ({duracion:.1f}s): {descripcion[:100]}...")
except Exception as e:
    descripcion = f"ERROR: {e}"
    duracion = 0
    print(f"       ERROR: {e}")

# ── Resumen con modelo de texto ──────────────────────────────
print(f"  [4/5] Resumiendo con {TEXT_MODEL}...")
if TEXT_MODEL != VISION_MODEL and descripcion and not descripcion.startswith("ERROR"):
    try:
        result2 = _post({
            "model": TEXT_MODEL,
            "prompt": f"Resume en 1 oración: {descripcion}",
            "stream": False,
            "options": {"num_predict": 50}
        }, timeout=60)
        resumen = result2.get("response", "").strip()
    except Exception as e:
        resumen = descripcion[:80]
else:
    resumen = descripcion[:80] if descripcion else "Sin descripción"
print(f"       Resumen: {resumen[:80]}")

# ── Guardar en SQLite ────────────────────────────────────────
now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
cursor = conn.execute(
    "INSERT INTO analisis_imagenes (ruta,descripcion,resumen,modelo_vision,modelo_texto,duracion_seg,fecha) VALUES (?,?,?,?,?,?,?)",
    (IMG_PATH, descripcion, resumen, VISION_MODEL, TEXT_MODEL, duracion, now)
)
imagen_id = cursor.lastrowid

palabras_clave = []
for keyword in ["persona","gato","perro","coche","edificio","árbol","comida","texto","rectángulo","círculo","color","azul","rojo","verde","amarillo"]:
    if keyword.lower() in descripcion.lower():
        palabras_clave.append(keyword)
for tag in palabras_clave:
    conn.execute("INSERT INTO tags (imagen_id, tag) VALUES (?,?)", (imagen_id, tag))
conn.commit()
print(f"  [5/5] Guardado en SQLite (id={imagen_id}, tags={palabras_clave or ['(ninguno)']}) ✓")

# ── Verificar desde BD ───────────────────────────────────────
print()
print("  ─── Verificación desde BD ───")
rows = conn.execute("SELECT id, ruta, resumen, duracion_seg FROM analisis_imagenes ORDER BY id DESC LIMIT 3").fetchall()
for row in rows:
    print(f"  ID {row[0]}: {os.path.basename(row[1])}")
    print(f"    Resumen: {row[2][:80]}")
    print(f"    Duración: {row[3]:.1f}s")

tags_row = conn.execute("SELECT tag FROM tags WHERE imagen_id=?", (imagen_id,)).fetchall()
if tags_row:
    print(f"    Tags: {[t[0] for t in tags_row]}")

stats = conn.execute("SELECT COUNT(*), AVG(duracion_seg) FROM analisis_imagenes").fetchone()
print(f"\n  Stats BD: {stats[0]} análisis, promedio {stats[1]:.1f}s por imagen")

conn.close()
print("\n  RESULTADO: PIPELINE COMPLETO OK")
PYEOF
[ $? -eq 0 ] && OK "Pipeline completo ejecutado" || FAIL "Pipeline falló"

# ── 4. Mostrar BD resultante ─────────────────────────────────
echo ""
INFO "BD resultante: ~/vision_pipeline.db"
if [ -f "$HOME/vision_pipeline.db" ]; then
  sqlite3 "$HOME/vision_pipeline.db" << 'SQL'
.headers on
.mode column
SELECT id, substr(ruta,-20) as imagen, substr(resumen,1,40) as resumen, duracion_seg as segs FROM analisis_imagenes;
SQL
fi

# ── 5. Cleanup imagen generada ───────────────────────────────
[ "$TEST_IMG" = "$HOME/pipeline_test.jpg" ] && rm -f "$TEST_IMG"

# ── Resumen ──────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}✓ TEST 5 PASADO — Pipeline completo local OK${NC}"
else
  echo -e "  ${RED}${BOLD}✗ TEST 5: $ERRORS error(s) — revisar arriba${NC}"
fi
echo -e "  ${CYAN}──────────────────────────────────────────${NC}"
echo ""
echo -e "  BD: ${CYAN}~/vision_pipeline.db${NC}"
echo -e "  Contiene: analisis_imagenes + tags"
echo ""

<div align="center">

```
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   ░█████╗░███╗░░██╗██████╗░██████╗░░█████╗░██╗██████╗   ║
║   ██╔══██╗████╗░██║██╔══██╗██╔══██╗██╔══██╗██║██╔══██╗  ║
║   ███████║██╔██╗██║██║░░██║██████╔╝██║░░██║██║██║░░██║  ║
║   ██╔══██║██║╚████║██║░░██║██╔══██╗██║░░██║██║██║░░██║  ║
║   ██║░░██║██║░╚███║██████╔╝██║░░██║╚█████╔╝██║██████╔╝  ║
║   ╚═╝░░╚═╝╚═╝░░╚══╝╚═════╝░╚═╝░░╚═╝░╚════╝░╚═╝╚═════╝   ║
║                                                           ║
║              A I  ·  S T A C K                           ║
╚═══════════════════════════════════════════════════════════╝
```

**Tu Android como servidor de desarrollo. Sin root. Sin VPS. Sin costos.**

[![Platform](https://img.shields.io/badge/Platform-Android%20ARM64-3DDC84?style=flat-square&logo=android&logoColor=white)](.)
[![Termux](https://img.shields.io/badge/Termux-F--Droid-000000?style=flat-square&logo=terminal&logoColor=white)](https://f-droid.org/packages/com.termux/)
[![Root](https://img.shields.io/badge/Root-No%20required-brightgreen?style=flat-square)](.)
[![Version](https://img.shields.io/badge/Version-v5.1.0-blue?style=flat-square)](.)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude%20AI-CC785C?style=flat-square&logo=anthropic&logoColor=white)](https://claude.ai)

</div>

---

## Instalación

Abre Termux y pega este comando:

```bash
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/instalar.sh \
  -o instalar.sh && bash instalar.sh
```

> **Requisito:** [Termux desde F-Droid](https://f-droid.org/packages/com.termux/) — no uses la versión de Play Store, está desactualizada y sin mantenimiento.

El script se encarga de todo: permisos, dependencias, tema visual, descarga de scripts y configuración del dashboard. Tiene checkpoints automáticos — si algo falla, vuélvelo a ejecutar y continúa desde donde quedó.

---

## ¿Qué es esto?

**termux-ai-stack** convierte tu teléfono Android en un servidor de desarrollo completo usando [Termux](https://termux.dev). Sin root, sin configuración manual, un script por módulo.

```
Tu Android (sin root) — ARM64
  └─ Termux
       ├─ menu.sh v5.1.0         → dashboard TUI — se abre al iniciar Termux
       │
       ├─ Termux nativo
       │    ├─ Ollama :11434     → modelos de IA locales
       │    │    ├─ vision_bot.py     → bot de visión para n8n/Telegram
       │    │    └─ bot_utils.py      → helpers SQLite reutilizables
       │    ├─ Claude Code       → agente de IA en terminal
       │    ├─ EAS CLI           → compilación de apps Expo/React Native
       │    ├─ Python 3.13 + SQLite → scripting, automatización, BD
       │    ├─ SSH :8022         → acceso remoto desde PC
       │    └─ Dashboard :8080   → panel de control web + API
       │
       ├─ proot Debian Bookworm ARM64
       │    ├─ n8n :5678         → automatización y bots Telegram
       │    ├─ cloudflared       → túnel público sin abrir puertos
       │    ├─ OpenCode :3000    → IDE web con agente IA
       │    └─ OpenClaw :18789   → gateway multi-proveedor de IA
       │
       ├─ App Android v3.2.0     → panel de control nativo (APK)
       │
       └─ backup.sh / restore.sh → backup completo o por módulo
```

> 🤖 Este proyecto está siendo desarrollado con [Claude](https://claude.ai) de Anthropic. A medida que crezca, Claude Code participará directamente como contribuidor en el repo.

---

## Dashboard TUI

Al abrir Termux aparece automáticamente el dashboard (menu.sh). Muestra el estado real de cada módulo y permite instalar, controlar y hacer backup sin escribir comandos.

```
  ╔══════════════════════════════════════════╗
  ║  ⬡ TERMUX·AI·STACK                      ║
  ║  RAM: 4.2GB  Disk: 77G  IP: 192.168.1.x ║
  ╠══════════════════════════════════════════╣
  ║  MÓDULOS                                 ║
  ╚══════════════════════════════════════════╝

  [1] Servicios      n8n ● activo · OpenClaw ● activo
  [2] Code Tools     Claude Code ● listo · OpenCode ● activo
  [3] Ollama         ● listo    v0.22.1
  [4] Expo/EAS/Git   ● listo    v18.9.1
  [5] Python         ● listo    v3.13.13
  [6] Remote         SSH ● activo · Dashboard ● activo

  ──────────────────────────────────────────
  [0] Backup / Restore

  ──────────────────────────────────────────
  [r] refrescar  [h] ayuda  [u] actualizar  [s] shell
  [d] desinstalar  [p] rendimiento
```

### Arquitectura v5.1.0 — 3 archivos

El menú está dividido en 3 archivos con carga bajo demanda:

| Archivo | Ubicación | Responsabilidad |
|---------|-----------|-----------------|
| `menu.sh` | `~/` | Loop principal · variables globales · helpers base · constantes de rutas |
| `menu_nativo.sh` | `~/scripts/` | Ollama · Expo · Python · Remote · Claude · backup |
| `menu_proot.sh` | `~/scripts/` | n8n · OpenCode · OpenClaw · caché persistente proot |

**Caché proot de 3 niveles:**

| Nivel | Fuente | Latencia | TTL |
|-------|--------|----------|-----|
| 1 | Variables en memoria | 0 ms | 30 s |
| 2 | Archivo `~/.proot_status_cache` | ~2 ms | 5 min |
| 3 | `proot-distro login debian` | 3–5 s | — |

| Operación | v4.1 | v4.3 | v5.x |
|-----------|------|------|------|
| Primer render | ~15-20 s | ~4-6 s | ~4-6 s |
| Renders con caché memoria | ~5-8 s | ~0.3 s | ~0.3 s |
| Render tras reiniciar Termux | ~5-8 s | ~4-6 s | ~2 ms |

---

## Módulos

| Módulo | Versión | Script | Entorno | Puerto |
|--------|---------|--------|---------|--------|
| n8n + cloudflared | 2.8.4 | `install_n8n.sh` | proot Debian | 5678 |
| OpenCode | latest | `install_opencode.sh` | proot Debian | 3000 |
| OpenClaw | latest | `install_openclaw.sh` | proot Debian | 18789 |
| Claude Code | 2.1.111 | `install_claude.sh` | Termux nativo | — |
| Ollama | 0.22.1 | `install_ollama.sh` | Termux nativo | 11434 |
| Expo / EAS CLI | 18.9.1 | `install_expo.sh` | Termux nativo | — |
| Python + SQLite | 3.13.13 | `install_python.sh` | Termux nativo | — |
| SSH | OpenSSH 10.3 | `install_ssh.sh` | Termux nativo | 8022 |
| Dashboard web | 2.11.0 | `install_remote.sh` | Termux nativo | 8080 |

Cada módulo es independiente — se instala solo o desde el menú maestro.

---

## Módulo: n8n

Automatización de workflows. Corre dentro de proot Debian para tener glibc real (necesario para node-gyp). Cloudflared provee una URL pública desde internet sin configurar puertos.

```
✅ proot-distro + Debian Bookworm ARM64
✅ Node.js 20 LTS + n8n + cloudflared (dentro del proot)
✅ Túnel cloudflared → URL pública (dominio fijo o URL temporal)
✅ Webhook Telegram funcionando (WEBHOOK_URL + N8N_PROTOCOL=https)
✅ Scripts de control: start / stop / url / status / logs / token CF
✅ Sesión tmux "n8n-server" en background
✅ WF2 y WF3 JSON listos para importar (workflows/)
```

**Variables requeridas para webhooks Telegram:**
```bash
# En ~/.env_n8n (configurable desde menú → Servicios → n8n → [8]):
N8N_WEBHOOK_URL=https://tu-dominio.com
```

---

## Módulo: OpenCode

IDE web con agente IA. Corre en proot Debian con Node.js 20 LTS.

```
✅ opencode latest en proot Debian
✅ Servidor web en :3000
✅ Integración con Ollama local (requiere modelo ≥1.5b + config apiKey)
✅ Integración con proveedores externos (Big Pickle gratis, APIs externas)
✅ Abrir proyectos con TUI o modo web desde el menú
```

> ⚠️ Ollama local en ARM64 sin GPU es lento para agentes (~30-60s por respuesta). Se recomienda un proveedor externo para uso real.

---

## Módulo: OpenClaw

Gateway multi-proveedor de IA. Corre en proot Debian con Node.js 22 via NVM.

```
✅ OpenClaw latest en proot Debian
✅ Gateway en :18789
✅ Soporte múltiples proveedores (Anthropic, OpenAI, Ollama, etc.)
✅ No abre navegador automáticamente — URL se muestra en pantalla
✅ Token configurable desde el menú
```

---

## Módulo: Ollama

Modelos de IA locales. Sin internet, sin costo por token, API compatible con OpenAI. Al instalar se generan automáticamente `vision_bot.py` y `bot_utils.py`.

```
✅ pkg install ollama (compilado para Termux ARM64)
✅ Servidor en :11434 con API compatible OpenAI
✅ Chat texto con historial SQLite persistente por chat_id
✅ Chat con imágenes (visión) — redimensionado automático
✅ vision_bot.py — bot de visión para n8n/Telegram
✅ bot_utils.py  — helpers SQLite reutilizables
```

**Modelos recomendados (dispositivos ≥ 8GB RAM):**

| Modelo | Tamaño | Uso |
|--------|--------|-----|
| `qwen2.5:0.5b` | ~397 MB | Texto liviano, bots Telegram |
| `qwen2.5:1.5b` | ~986 MB | Balance velocidad/calidad |
| `qwen2.5:3b` | ~1.9 GB | Texto general, tool calling |
| `llama3.2:1b` | ~1.3 GB | Texto general |
| `gemma3:1b` | ~815 MB | Texto general |
| `moondream:1.8b` | ~1.7 GB | Visión — análisis de imágenes |
| `llava-phi3:3.8b` | ~2.9 GB | Visión — mayor calidad |

> ⚠️ No usar modelos 7B o más en dispositivos móviles — crash por RAM insuficiente.
> ⚠️ Para OpenCode con agente (bash, editor, herramientas) usar mínimo `qwen2.5:1.5b`.

**Modelos con tool calling:** `qwen2.5:*`, `llama3.2:*`, `phi3:mini`
**Sin tool calling:** `gemma3`, `gemma2`, `mistral:7b-instruct`

**Submenú desde el dashboard:**
```
[1] Iniciar / detener servidor
[2] Chat rápido        (sin historial)
[3] Chat completo      (SQLite · historial persistente)
[4] Chat con imágenes  (visión · redimensionado automático)
[5] Modelos            (ver / descargar / eliminar — 9 predefinidos)
[6] Configurar historial SQLite
```

---

## Módulo: Claude Code

Agente de IA de Anthropic. Requiere workaround en ARM64 porque el binario nativo usa glibc y Termux usa Bionic libc.

```
✅ nodejs-lts
✅ @anthropic-ai/claude-code @2.1.111 fijo
✅ Lanzamiento via node cli.js (workaround ARM64/Bionic)
✅ Alias configurado en .bashrc
✅ Wrapper en $PREFIX/bin para invocación directa
```

> ⚠️ Versión fija en `@2.1.111` — versiones superiores usan binario nativo incompatible con Bionic libc.

---

## Módulo: Python + SQLite

```
✅ Python 3.13.13 (pkg install python)
✅ sqlite3 builtin
✅ Pillow, numpy, pandas 3.0.2, matplotlib 3.10.9 (ARM64 confirmado)
✅ image_archive.py — archivo de imágenes con respaldo en nube
✅ Submenú Python: REPL · pip · SQLite · Trading · Bot deportivo
```

**Reglas ARM64 críticas en Python:**
```python
# ❌ NUNCA en SQLite:  DEFAULT (datetime('now'))
# ✅ SIEMPRE:          datetime.now().strftime('%Y-%m-%d %H:%M:%S')

# ❌ NUNCA:  import requests
# ✅ SIEMPRE: from urllib import request as ureq  (builtin)
```

---

## Módulo: SSH

Acceso remoto completo desde PC, VS Code o cualquier cliente SSH.

```
✅ OpenSSH 10.3 vía pkg (Termux nativo)
✅ Puerto 8022 (sin root requerido)
✅ Autenticación por contraseña y clave pública
✅ Dashboard TUI accesible desde PC via SSH
✅ Claude Code con teclado físico desde PC
✅ CF-SSH: túnel Cloudflare para acceso remoto sin IP fija
```

**Conectar desde PC:**
```bash
ssh -p 8022 usuario@192.168.x.x
```

---

## App Android

Panel de control nativo compilado con React Native + Expo SDK 52.

```
✅ versionCode 9 — v3.2.0
✅ ModulesScreen — estado en tiempo real de todos los módulos
✅ ChatScreen — chat Ollama asíncrono con historial SQLite
✅ OllamaScreen — control y selección de modelos
✅ SshScreen — información y comandos SSH
✅ PythonScreen — REPL, SQLite, accesos directos
✅ Tema Noche / Océano / Día
✅ Compilación automática via GitHub Actions → APK en Artifacts
```

**APK:** `Actions → Build APK → Artifacts → apk-debug-arm64`

| versionCode | Versión | Cambios |
|-------------|---------|---------|
| 1–2 | 1.0.0 | Primeras versiones (crash) |
| 3 | 1.1.0 | Fix cleartext HTTP |
| 4 | 1.2.0 | Fix botones tools |
| 5 | 1.3.0 | Tabs · polling · backup |
| 6 | 1.4.0 | BackHandler · submenús · Switch |
| 7 | 1.5.0 | Rediseño cards · iconos · footer nav |
| 8 | 2.x.x | ChatScreen · OllamaScreen · ThemeContext |
| **9** | **3.2.0** | **SshScreen · PythonScreen · guard Ollama · TabBar fix · IP fix** |

---

## Backup y Restore

El sistema genera archivos `.tar.xz` por módulo, verifica integridad con SHA256 y permite restaurar desde GitHub Releases o desde tu propio backup.

### Hacer backup

```bash
bash ~/backup.sh                   # backup completo (todas las partes)
bash ~/backup.sh --module base     # solo scripts y configuración base
bash ~/backup.sh --module claude   # solo Claude Code
bash ~/backup.sh --module expo     # solo EAS CLI
bash ~/backup.sh --module ollama   # solo Ollama
bash ~/backup.sh --module n8n      # solo n8n + cloudflared
bash ~/backup.sh --module remote   # solo SSH + Dashboard
bash ~/backup.sh --module opencode # solo OpenCode
bash ~/backup.sh --module openclaw # solo OpenClaw
```

Los archivos se guardan en `/sdcard/Download/termux-ai-stack-releases/`.

### Restaurar

```bash
bash ~/restore.sh                               # menú interactivo
bash ~/restore.sh --module ollama               # módulo específico
bash ~/restore.sh --module all --source github  # todo desde GitHub Releases
bash ~/restore.sh --module n8n --source local   # desde tu backup propio
```

### Partes del backup

| Parte | Contenido | Tamaño aprox. |
|-------|-----------|---------------|
| part0-termux-base | Scripts + config + .bashrc + ~/scripts/ | ~175 KB |
| part2-claude-code | Claude Code @2.1.111 completo | ~11 MB |
| part3-eas-expo | EAS CLI + credenciales ~/.expo | ~12 MB |
| part4-ollama | Binario Ollama (sin modelos) | ~9 MB |
| part5-n8n-data | n8n + cloudflared + workflows | ~156 MB |
| part6-proot-base | Rootfs Debian limpio + Node 20.20.2 | ~588 MB |
| part7-remote | SSH config + scripts dashboard | ~13 KB |
| part8-opencode | OpenCode completo en proot | ~229 MB |
| part9-openclaw | OpenClaw + NVM + Node 22 en proot | ~489 MB |

> ⚠️ Los modelos de Ollama NO se incluyen en el backup. Descárgalos de nuevo con `ollama pull`.

---

## Arquitectura

```
Android (sin root) — ARM64
  └─ Termux (F-Droid)
       ├─ menu.sh v5.1.0 → TUI principal
       │    ├─ menu_nativo.sh  → módulos Termux nativos
       │    └─ menu_proot.sh   → módulos proot + caché persistente
       │
       ├─ tmux
       │    ├─ "n8n-server"      → n8n :5678 + cloudflared
       │    ├─ "ollama-server"   → Ollama :11434
       │    ├─ "opencode-server" → OpenCode :3000
       │    └─ "openclaw-server" → OpenClaw :18789
       │
       ├─ Python 3.13.13
       │    ├─ sqlite3 (builtin)
       │    ├─ Pillow · numpy · pandas · matplotlib
       │    ├─ vision_bot.py     → bot visión para n8n/Telegram
       │    ├─ bot_utils.py      → helpers SQLite
       │    └─ image_archive.py  → archivo de imágenes + nube
       │
       ├─ Node.js LTS
       │    ├─ Claude Code v2.1.111
       │    └─ EAS CLI v18.9.1
       │
       ├─ OpenSSH 10.3 (:8022)
       ├─ Ollama v0.22.1 (:11434)
       ├─ Dashboard v2.11.0 (:8080)
       │
       └─ proot-distro + Debian Bookworm ARM64
            ├─ Node.js 20 LTS (sistema)
            ├─ Node.js 22 (NVM — OpenClaw)
            ├─ n8n 2.8.4 (:5678)
            ├─ cloudflared → túnel público
            ├─ OpenCode latest (:3000)
            └─ OpenClaw latest (:18789)

BDs SQLite activas:
  ~/ollama_[modelo].db   → historial chat local por modelo
  ~/bot_history.db       → historial bot Telegram por chat_id
  ~/vision_pipeline.db   → análisis de imágenes
  ~/trading/senales.db   → señales trading (submenú Python)
```

**¿Por qué proot para n8n, OpenCode y OpenClaw?**
Estos servicios requieren glibc (Linux estándar). Termux usa Bionic libc (Android). El proot con Debian provee el entorno sin root.

**¿Por qué Node.js 20 en proot (sistema) pero 22 para OpenClaw?**
n8n usa `isolated-vm`, que rompe en Node.js 22+. OpenClaw requiere Node.js 22. Se resuelve con NVM dentro del proot: sistema en v20, OpenClaw en v22 via NVM independiente.

---

## Estructura del repo

```
termux-ai-stack/
├── instalar.sh              ← entrada única — curl + bash   (v2.5.0)
├── menu.sh                  ← dashboard TUI principal       (v5.1.0)
├── backup.sh                ← backup modular completo       (v2.5.0)
├── restore.sh               ← restore modular               (v2.6.0)
├── README.md
├── ARCHITECTURE.md          ← documentación técnica detallada
├── ROADMAP.md               ← estado del proyecto y versiones
├── MEJORAS_PENDIENTES.md    ← próximas mejoras ordenadas
├── scripts/
│   ├── menu_nativo.sh       ← módulos Termux nativos
│   ├── menu_proot.sh        ← módulos proot + caché        (v5.1.0)
│   ├── install_n8n.sh
│   ├── install_claude.sh
│   ├── install_ollama.sh    ← genera vision_bot.py + bot_utils.py
│   ├── install_expo.sh
│   ├── install_python.sh
│   ├── install_remote.sh
│   ├── install_ssh.sh
│   ├── install_opencode.sh
│   └── install_openclaw.sh
├── python/
│   ├── vision_bot.py        ← bot visión para n8n/Telegram
│   ├── bot_utils.py         ← helpers SQLite reutilizables
│   ├── image_archive.py     ← archivo de imágenes + nube
│   └── dashboard/
│       └── dashboard_server.py   ← API REST + servidor web :8080
├── App/                     ← React Native Expo SDK 52
│   └── src/
│       ├── navigation/      ← routes.js · TabBar.js · RootNavigator.js
│       ├── theme/           ← themes.js · ThemeContext.js · icons.js
│       ├── hooks/           ← useStatus.js · useAction.js · useChatSession.js
│       ├── services/        ← api.js · dashboard.js
│       ├── components/      ← ModuleIcon · StatusPill · ActionButton · etc.
│       └── screens/         ← ModulesScreen · ChatScreen · OllamaScreen
│                               SshScreen · PythonScreen · SystemScreen
├── tests/
│   ├── test_1_sqlite.sh
│   ├── test_2_python.sh
│   ├── test_3_ollama_sqlite.sh
│   ├── test_4_ollama_vision.sh
│   ├── test_5_vision_pipeline.sh
│   ├── test_6_n8n_ollama_sqlite.sh
│   └── test_7_bot_vision.sh
└── workflows/               ← WF2, WF3 JSON para importar en n8n
```

---

## Instalación por módulo

Si no quieres usar el instalador maestro, cada script funciona de forma independiente:

```bash
# n8n + cloudflared
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_n8n.sh \
  -o install_n8n.sh && bash install_n8n.sh

# OpenCode
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_opencode.sh \
  -o install_opencode.sh && bash install_opencode.sh

# OpenClaw
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_openclaw.sh \
  -o install_openclaw.sh && bash install_openclaw.sh

# Claude Code
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_claude.sh \
  -o install_claude.sh && bash install_claude.sh

# Ollama (incluye vision_bot.py + bot_utils.py)
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_ollama.sh \
  -o install_ollama.sh && bash install_ollama.sh

# Expo / EAS CLI
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_expo.sh \
  -o install_expo.sh && bash install_expo.sh

# Python + SQLite
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_python.sh \
  -o install_python.sh && bash install_python.sh

# SSH
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_ssh.sh \
  -o install_ssh.sh && bash install_ssh.sh
```

> Cada script verifica si el módulo ya está instalado antes de hacer nada. Si falla a mitad, vuélvelo a ejecutar — tiene checkpoints automáticos.

---

## Actualizar scripts

Desde el dashboard, presiona `[u]`. Descarga la versión más reciente de todos los scripts desde GitHub y recarga el menú automáticamente.

O manualmente:
```bash
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/menu.sh \
  -o ~/menu.sh && exec bash ~/menu.sh
```

---

## Bots e IA — ecosistema

```
Telegram usuario
    ↓ mensaje de texto o imagen
n8n webhook (proot :5678) · URL pública cloudflared
    ↓
bot_history.db (SQLite — historial por chat_id)
    ↓
Ollama :11434 (Termux nativo)
    ├─ texto  → qwen2.5:0.5b / qwen2.5:1.5b / llama3.2:1b
    └─ visión → moondream:1.8b / llava-phi3:3.8b + vision_bot.py
    ↓
respuesta → Telegram

WF2 — Bot texto + historial SQLite  (workflows/wf2_texto_ollama_http_v3.json)
WF3 — Bot visión + HTTP             (workflows/wf3_vision_http_v4.json)
```

---

## Problemas conocidos

| Problema | Estado |
|----------|--------|
| Ollama switch OFF no mata proceso en dashboard/app | ⏳ `pkill` no matchea proceso real — pendiente identificar nombre exacto |
| Terminal PTY output vacío en app | ⏳ Hipótesis: secuencia `\x1b[?1049h` — pendiente diagnóstico |
| OpenCode + Ollama local muy lento | ⚠️ Limitación de hardware — agente complejo + ARM64 CPU-only (~30-60s/resp) |
| GPU Vulkan Ollama no activa | ⏳ Investigando `llamux` (compilación NDK) — única vía confirmada sin root |
| OpenClaw wizard automático | ⏳ Investigando `expect` en proot Debian |
| moondream:1.8b responde en idioma de la imagen | ⚠️ Workaround: prompt forzado en español |
| Open WebUI incompatible con Python 3.13 | ❌ Requiere Python < 3.13 — pendiente soporte oficial |

---

## Roadmap

```
✅ Fase 1  — Módulos independientes (install_*.sh)
✅ Fase 2  — Script maestro (instalar.sh) con checkpoints
✅ Fase 3  — Dashboard TUI (menu.sh)
✅ Fase 4  — Backup/Restore modular con SHA256
✅ Fase 5  — Mejoras UI y fixes de rendimiento
✅ Fase 6  — Python + SQLite · SSH
✅ Fase 7  — Webhook n8n · Telegram + Ollama (WF2, WF3)
✅ Fase 8a — Dashboard web (:8080) con API REST
✅ Fase 8b — App React Native (v3.2.0 · versionCode 9)
✅ Fase 8c — Chat Ollama asíncrono con historial SQLite · visión
✅ Fase 8d — Tests T1-T7 · vision_bot · bot_utils
✅ Fase 9  — OpenCode + OpenClaw en proot · menú 3 archivos
✅ Fase 10 — Fixes S22: OpenCode --cwd · OpenClaw sin navegador
              Config Ollama v1.15.5 · caché persistente proot

📋 Fase 11 — GPU Vulkan Ollama (llamux) · backup proot-full
              Termux:Boot rutas actualizadas · OpenClaw Cloudflared
📋 Fase 12 — App: SystemScreen · OpenClawScreen · OpenCodeScreen
              Terminal PTY · SqliteScreen · TradingScreen
```

---

## Versiones fijas — no cambiar

| Componente | Versión | Razón |
|------------|---------|-------|
| Claude Code | @2.1.111 | >2.1.111 usa binario nativo incompatible con Bionic libc |
| Node.js proot (sistema) | v20.20.2 LTS | v22+ rompe `isolated-vm` en n8n |
| Node.js proot OpenClaw | v22 via NVM | OpenClaw requiere Node 22 |
| Expo SDK | ~52.0.0 | SDK 53+ obliga Nueva Arquitectura → crash ARM64 Bionic |
| React Native | 0.76.9 | Par fijo con Expo SDK 52 |
| newArchEnabled | false | CRÍTICO — crash ARM64 sin root si se activa |
| pandas ARM64 | 3.0.2 | Confirmado funcional en ARM64 |
| matplotlib ARM64 | 3.10.9 | Confirmado funcional en ARM64 |

---

## Dispositivos probados

| Dispositivo | Android | RAM | Estado |
|------------|---------|-----|--------|
| Xiaomi POCO F5 | 15 (HyperOS 2.0) | 12 GB | ✅ Stack completo funcionando |
| Xiaomi Mi 11 Lite 5G NE | 13+ (EvolutionX) | 8 GB | ✅ n8n + webhook OK |

> Si lo probaste en otro dispositivo, abre un issue con: modelo · Android · RAM · qué pasó.

---

## Contribuir

1. Fork del repo
2. Prueba en tu dispositivo
3. Abre un issue: modelo · Android · error exacto
4. O PR directo con el fix

**Para agregar un módulo nuevo, sigue estas reglas:**

```bash
# 1. Checkpoints y registry
check_done "paso_X" || { hacer_algo && mark_done "paso_X"; }

# 2. stdin siempre explícito en Termux
read -r VAR < /dev/tty

# 3. Sin /tmp/ — Android 15 lo monta noexec
TMPFILE="$HOME/tempfile_$$"

# 4. SQLite en Python — datetime explícito
# ❌  DEFAULT (datetime('now'))
# ✅  datetime.now().strftime('%Y-%m-%d %H:%M:%S')

# 5. HTTP en Python — sin requests
# ❌  import requests
# ✅  from urllib import request as ureq

# 6. Rutas de scripts — usar constantes del menú
# ❌  bash "$HOME/start_servidor.sh"
# ✅  bash "$N8N_SCRIPTS/start_servidor.sh"
```

---

## Licencia

MIT — úsalo como quieras.

---

## Créditos

Construido con [Claude](https://claude.ai) de Anthropic — arquitectura, scripts y documentación. No es un secreto: es simplemente cómo se desarrolla software hoy.

---

<div align="center">

Hecho con Termux · ARM64 · sin root · sin excusas

</div>

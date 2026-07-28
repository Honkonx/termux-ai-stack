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
[![Version](https://img.shields.io/badge/Version-v6.0.0-blue?style=flat-square)](.)
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

El script se encarga de todo: permisos, dependencias, tema visual, descarga de scripts y configuración. Tiene checkpoints automáticos — si algo falla, vuélvelo a ejecutar y continúa desde donde quedó.

---

## ¿Qué es esto?

**termux-ai-stack** convierte tu teléfono Android en un servidor de desarrollo completo usando [Termux](https://termux.dev). Sin root, sin configuración manual, un script por módulo.

```
Tu Android (sin root) — ARM64
  └─ Termux
       ├─ menu.sh                → dashboard TUI — se abre al iniciar Termux
       │
       ├─ Termux nativo
       │    ├─ Ollama :11434     → modelos de IA locales (GPU o estándar)
       │    │    ├─ vision_bot.py     → bot de visión para n8n/Telegram
       │    │    └─ bot_utils.py      → helpers SQLite reutilizables
       │    ├─ Hermes Agent      → agente IA + gateway Telegram (Python nativo)
       │    ├─ Claude Code       → agente de IA en terminal
       │    ├─ Codex CLI         → agente de IA en terminal (OpenAI)
       │    ├─ Antigravity CLI   → agente de IA en terminal
       │    ├─ OpenCode :3000    → IDE web con agente IA (nativo glibc)
       │    ├─ OpenClaw :18789   → gateway multi-proveedor de IA (nativo glibc)
       │    ├─ EAS CLI           → compilación de apps Expo/React Native
       │    ├─ Python 3.13 + SQLite → scripting, automatización, BD
       │    └─ Remote (SSH :8022 + Cloudflared) → acceso remoto desde PC
       │
       ├─ proot Debian / udocker
       │    ├─ n8n :5678         → automatización y bots Telegram (proot o udocker)
       │    └─ cloudflared       → túnel público sin abrir puertos
       │
       ├─ Entorno [8]            → proot-distro genérico + Desktop + VNC + GPU
       │
       ├─ KairosApp v0.10.0      → app Android nativa (fork termux-app)
       │
       └─ backup.sh / restore.sh → backup completo o por módulo
```

> 🤖 Este proyecto está siendo desarrollado con [Claude](https://claude.ai) de Anthropic. A medida que crezca, Claude Code participa directamente como contribuidor en el repo.

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

  [1] Servicios      n8n ● activo · OpenClaw ● activo · Hermes ● activo
  [2] Code Tools     Claude Code ● listo · OpenCode ● activo
  [3] Ollama         ● listo    v0.22.1
  [4] Expo/EAS/Git   ● listo    v18.9.1
  [5] Python         ● listo    v3.13.13
  [6] Remote         SSH ● activo
  [8] Entorno        ● listo

  ──────────────────────────────────────────
  [0] Backup / Restore

  ──────────────────────────────────────────
  [r] refrescar  [h] ayuda  [u] actualizar  [s] shell
  [d] desinstalar  [p] rendimiento
```

### Arquitectura — 4 archivos

El menú está dividido en 4 archivos con carga bajo demanda (`source` al primer uso):

| Archivo | Ubicación | Responsabilidad |
|---------|-----------|-----------------|
| `menu.sh` | `~/` | Loop principal · variables globales · helpers base · constantes de rutas |
| `menu_nativo.sh` | `~/scripts/` | Ollama · Expo · Python · Remote · Claude Code · Codex · Antigravity · OpenCode · OpenClaw (nativo) · Hermes · backup |
| `menu_proot.sh` | `~/scripts/` | n8n (proot/udocker) · dashboard "Servicios" (n8n/OpenClaw/Hermes) · caché persistente proot |
| `menu_entorno.sh` | `~/scripts/` | Módulo [8] Entorno — proot-distro genérico, Desktop, VNC, GPU |

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

| Módulo | Versión | Script | Entorno | Puerto | Variantes |
|--------|---------|--------|---------|--------|-----------|
| n8n + cloudflared | 2.8.4 | `install_n8n.sh` | proot Debian / udocker | 5678 | ⚡ proot · 📦 udocker |
| OpenCode | latest | `install_opencode.sh` | Termux nativo glibc | 3000 | — |
| OpenClaw | latest | `install_openclaw.sh` | Termux nativo glibc | 18789 | — |
| Hermes Agent | 0.16.0 | `install_hermes.sh` | Termux nativo Python | 8642 (opt.) | — |
| Claude Code | 2.1.111 | `install_claude.sh` | Termux nativo | — | ⚡ Native ELF · 📦 Legacy npm |
| Codex CLI | latest | `install_codex.sh` | Termux nativo | — | — |
| Antigravity CLI | latest | `install_antigravity.sh` | Termux nativo | — | — |
| Ollama | 0.22.1 | `install_ollama.sh` | Termux nativo | 11434 | ⚡ GPU · 📦 Estándar |
| Expo / EAS CLI | 18.9.1 | `install_expo.sh` | Termux nativo | — | — |
| Python + SQLite | 3.13.13 | `install_python.sh` | Termux nativo | — | — |
| Remote (SSH + Cloudflared) | OpenSSH 10.3 | `install_remote.sh` | Termux nativo | 8022 | — |
| Entorno | 1.1.0 | `install_entorno.sh` | proot-distro genérico + GPU/X11/VNC | — | Ver sección [8] Entorno |

Cada módulo es independiente — se instala solo o desde el menú maestro. Los scripts aceptan `--silent` (sin preguntas) y `--force` (reinstalar).

---

## ⏣ [BETA] Entorno — proot-distro + Desktop + VNC + GPU

> ⚠️ **Módulo en desarrollo activo.** Probado en POCO F5 (HyperOS 2.0). Reporta issues en otras configuraciones.

El módulo **[8] Entorno** proporciona un entorno gráfico Linux completo sobre Termux: acelaración GPU, escritorio XFCE4/LXQt/MATE/KDE Plasma, contenedores proot-distro o udocker, y acceso por VNC a monitor externo.

### Instalación

```bash
# Desde el dashboard
menu → [8] Entorno → [1] Instalar

# O directo
bash <(curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_entorno.sh)
```

### Desktop Environments

Puedes instalar los 4 DEs a la vez y cambiar el activo en runtime sin reinstalar.

| DE | RAM aprox | Descripción |
|----|-----------|-------------|
| XFCE4 | ~250MB | Rápido, personalizable — recomendado |
| LXQt | ~150MB | Ultra ligero — ideal sin monitor |
| MATE | ~350MB | GNOME 2 clásico |
| KDE Plasma | ~600MB | Moderno — ideal con monitor externo |

### GPU Acceleration

El instalador detecta tu SoC automáticamente y configura el driver correcto.

| GPU | Driver | Dispositivos |
|-----|--------|--------------|
| Adreno 610+ | Turnip (Vulkan nativo) | Snapdragon 7xx / 8xx |
| Adreno antiguo | Zink (OpenGL→Vulkan) | Snapdragon 6xx y anteriores |
| Mali Bifrost/Valhall | Panfrost | Dimensity G31/G52/G57/G68/G78/G710 |
| Mali otros | Virgl + Zink | Compatible con más dispositivos |
| Desconocido | LLVMpipe (software) | Siempre funciona |

### udocker

Ejecuta imágenes Docker sin root. Útil para n8n (alternativa al proot) y otros servicios empaquetados como contenedores Docker.

```bash
# udocker se instala con el módulo Entorno
udocker pull n8nio/n8n
udocker run --name=n8n n8nio/n8n
```

### Monitor externo

**Opción A — USB-C a HDMI directo** (si tu SoC soporta DisplayPort Alt Mode):

```
teléfono → USB-C a HDMI → monitor
```

**Opción B — VNC** (para teléfonos sin salida de video):

```bash
# En el teléfono, iniciar VNC
menu → [8] Entorno → VNC → Iniciar

# Conectar desde PC
vncviewer 192.168.x.x:5901
```

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

IDE web con agente IA. Nativo glibc (Termux) — la variante proot quedó archivada, ya no se ofrece como opción.

```
✅ opencode latest (nativo glibc)
✅ Servidor web en :3000
✅ Integración con Ollama local (requiere modelo ≥1.5b + config apiKey)
✅ Integración con proveedores externos (Big Pickle gratis, APIs externas)
✅ Abrir proyectos con TUI o modo web desde el menú
✅ AGENTS.md / CLAUDE.md para contexto de proyecto
```

> ⚠️ Ollama local en ARM64 sin GPU es lento para agentes (~30-60s por respuesta). Se recomienda un proveedor externo para uso real.

---

## Módulo: OpenClaw

Gateway multi-proveedor de IA. Nativo glibc (Termux) — la variante proot quedó archivada, ya no se ofrece como opción.

```
✅ OpenClaw latest (nativo glibc)
✅ Gateway en :18789
✅ Soporte múltiples proveedores (Anthropic, OpenAI, Ollama, etc.)
✅ No abre navegador automáticamente — URL se muestra en pantalla
✅ Token configurable desde el menú
```

---

## Módulo: Hermes Agent

Agente IA de Nous Research. Corre **nativo en Termux** (Python venv) sin proot ni contenedores. Gateway de mensajería multicanal con Telegram integrado de forma nativa — sin webhooks, sin cloudflared.

```
✅ Hermes Agent v0.16.0 (Nous Research — MIT)
✅ Runtime: Python venv en ~/.hermes/hermes-agent/venv/
✅ TUI interactiva: hermes chat
✅ Gateway Telegram nativo (long polling — sin URL pública)
✅ Soporte multi-proveedor: OpenRouter, Anthropic, Ollama local, Google
✅ API server OpenAI-compatible opcional en :8642
✅ Memoria persistente por sesión + SOUL.md (personalidad del agente)
✅ Shim lanzador protege PYTHONPATH/PYTHONHOME (crítico en Termux)
✅ Integrado en menú [1] Servicios junto a n8n y OpenClaw
```

**Diferencias vs OpenClaw / n8n para Telegram:**

| Aspecto | n8n + webhook | Hermes |
|---------|--------------|--------|
| Conexión Telegram | Webhook (requiere URL pública) | Long polling (sin URL pública) |
| Runtime | proot Debian + Node.js | Termux nativo Python |
| Cloudflared | Requerido | No requerido |
| Memoria persistente | Manual (SQLite) | Nativa por sesión |
| Tool calling | Via nodos n8n | Nativo (model.tools) |

**Configuración básica (`~/.hermes/config.yaml`):**
```yaml
# Proveedor cloud (recomendado)
model:
  provider: openrouter
  default: google/gemini-flash-1.5

# Ollama local (requiere modelo ≥64k contexto)
model:
  provider: custom
  base_url: http://127.0.0.1:11434/v1
  default: qwen2.5:7b-65k
  ollama_num_ctx: 65536
  context_length: 65536
```

> ⚠️ Hermes requiere mínimo 64,000 tokens de contexto para tool calling confiable. `qwen2.5:3b` y modelos más pequeños son insuficientes con la configuración estándar.

**Comandos Telegram disponibles:** `/help` · `/new` · `/status` · `/model` · `/sessions` · `/stop` · `/update`

---

## Módulo: Ollama

Modelos de IA locales. Sin internet, sin costo por token, API compatible con OpenAI. Al instalar se generan automáticamente `vision_bot.py` y `bot_utils.py`. Disponible en variante GPU (experimental) o estándar.

```
✅ pkg install ollama (compilado para Termux ARM64)
✅ Servidor en :11434 con API compatible OpenAI
✅ Chat texto con historial SQLite persistente por chat_id
✅ Chat con imágenes (visión) — redimensionado automático
✅ vision_bot.py — bot de visión para n8n/Telegram
✅ bot_utils.py  — helpers SQLite reutilizables
```

**Modelos recomendados según RAM disponible:**

| Modelo | Tamaño | RAM mín. | Uso |
|--------|--------|----------|-----|
| `qwen2.5:0.5b` | ~397 MB | 4 GB | Texto liviano, bots Telegram |
| `qwen2.5:1.5b` | ~986 MB | 4 GB | Balance velocidad/calidad |
| `qwen2.5:3b` | ~1.9 GB | 6 GB | Texto general, tool calling básico |
| `llama3.2:1b` | ~1.3 GB | 4 GB | Texto general |
| `gemma3:1b` | ~815 MB | 4 GB | Texto general |
| `moondream:1.8b` | ~1.7 GB | 6 GB | Visión — análisis de imágenes |
| `llava-phi3:3.8b` | ~2.9 GB | 6 GB | Visión — mayor calidad |
| `qwen2.5:4b` | ~2.5 GB | 6 GB | Texto general mejorado |
| `qwen2.5:7b` | ~4.7 GB | 8 GB | Tool calling confiable (Hermes) |
| `llama3.1:8b` | ~4.9 GB | 10 GB | Texto avanzado |
| `qwen2.5:14b` | ~9.0 GB | 14 GB | Modelos grandes — dispositivos ≥16 GB |
| `qwen2.5:16b` | ~10.7 GB | 16 GB | Alta calidad — POCO F5 / dispositivos top |

> ⚠️ Validar RAM libre antes de descargar modelos 7B o mayores. Con el stack completo activo quedan ~6-7 GB libres en dispositivos de 12 GB.
> ℹ️ Para Hermes Agent (tool calling) usar mínimo `qwen2.5:7b` con `num_ctx 65536`.

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

Agente de IA de Anthropic. Requiere workaround en ARM64 porque el binario nativo usa glibc y Termux usa Bionic libc. Disponible en dos variantes.

```
✅ nodejs-lts
✅ @anthropic-ai/claude-code @2.1.111 fijo (variante legacy)
✅ Variante native ELF glibc (recomendada — más reciente)
✅ Lanzamiento via node cli.js (workaround ARM64/Bionic)
✅ Alias configurado en .bashrc
✅ Wrapper en $PREFIX/bin para invocación directa
```

> ⚠️ Versión legacy fija en `@2.1.111` — versiones superiores usan binario nativo incompatible con Bionic libc.

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

# ❌ NUNCA:  /tmp/archivo  (noexec en Android 15)
# ✅ SIEMPRE: $HOME/tmp/archivo
```

---

## Módulo: Remote

Acceso remoto completo desde PC, VS Code o cualquier cliente SSH — instalado por `install_remote.sh` (SSH y Cloudflared en un solo módulo).

```
✅ OpenSSH 10.3 vía pkg (Termux nativo)
✅ Puerto 8022 (sin root requerido)
✅ Autenticación por contraseña y clave pública
✅ Dashboard TUI accesible desde PC via SSH
✅ Claude Code con teclado físico desde PC
✅ CF-SSH: túnel Cloudflare nativo para acceso remoto sin IP fija
```

**Conectar desde PC:**
```bash
ssh -p 8022 usuario@192.168.x.x
```

---

## KairosApp

App Android nativa en desarrollo activo — fork de [termux-app](https://github.com/termux/termux-app) que integra todos los módulos del stack en un solo APK. La esencia es Termux: el motor de terminal VT100, las sesiones bash y el bootstrap APT se mantienen intactos. La app agrega una interfaz nativa Kotlin por encima sin reemplazar ni envolver el motor — la terminal siempre está accesible desde un FAB overlay.

```
🔧 En desarrollo — fork de github.com/termux/termux-app
✅ Motor Termux (Java) — sesiones bash, bootstrap APT, terminal VT100
✅ UI nativa Kotlin — 4 tabs + terminal overlay (FAB)
✅ Gestión de todos los módulos del stack desde la app
✅ Chat Ollama con streaming HTTP
✅ Estado del sistema en tiempo real (RAM, storage, servicios)
✅ Instalación por módulo con selector de variantes
✅ Compilación automática via GitHub Actions → APK en Artifacts (~15 min)
```

**APK:** `Actions → Build APK → Artifacts → apk-debug-arm64`

> ⚠️ `targetSdkVersion` fijo en 28 — NO cambiar. Valores superiores bloquean `exec()` del motor Termux en Android 10+.

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
bash ~/backup.sh --module remote   # solo SSH
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
| part7-remote | SSH config + scripts | ~13 KB |
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
       │    ├─ "opencode-server" → OpenCode :3000 / :4096
       │    ├─ "openclaw-server" → OpenClaw :18789
       │    └─ "hermes-gw"       → Hermes gateway (long polling)
       │
       ├─ Python 3.13.13
       │    ├─ sqlite3 (builtin)
       │    ├─ Pillow · numpy · pandas · matplotlib
       │    ├─ vision_bot.py      → bot visión para n8n/Telegram
       │    ├─ bot_utils.py       → helpers SQLite
       │    └─ image_archive.py   → archivo de imágenes + nube
       │
       ├─ Node.js LTS
       │    ├─ Claude Code v2.1.111 (legacy) / native ELF
       │    └─ EAS CLI v18.9.1
       │
       ├─ Hermes Agent v0.16.0
       │    └─ ~/.hermes/hermes-agent/venv/bin/hermes
       │
       ├─ OpenSSH 10.3 (:8022)
       ├─ Ollama v0.22.1 (:11434)
       │
       └─ proot-distro + Debian Bookworm ARM64
            ├─ Node.js 20 LTS (sistema)
            ├─ Node.js 22 (NVM — OpenClaw proot)
            ├─ n8n 2.8.4 (:5678)
            ├─ cloudflared → túnel público
            ├─ OpenCode latest (:3000 / :4096)
            └─ OpenClaw latest (:18789)

Registry (~/.android_server_registry):
  Fuente de verdad de estado — escrito por scripts bash y controladores internos
  Leído por: KairosApp · menu.sh · servicios del stack

BDs SQLite activas:
  ~/ollama_[modelo].db   → historial chat local por modelo
  ~/bot_history.db       → historial bot Telegram por chat_id
  ~/vision_pipeline.db   → análisis de imágenes
  ~/trading/senales.db   → señales trading (submenú Python)
```

**¿Por qué proot para n8n, OpenCode y OpenClaw?**
Estos servicios requieren glibc (Linux estándar). Termux usa Bionic libc (Android). El proot con Debian provee el entorno sin root. OpenCode y OpenClaw tienen variante nativa glibc que no requiere proot.

**¿Por qué Node.js 20 en proot (sistema) pero 22 para OpenClaw?**
n8n usa `isolated-vm`, que rompe en Node.js 22+. OpenClaw requiere Node.js 22. Se resuelve con NVM dentro del proot: sistema en v20, OpenClaw en v22 via NVM independiente.

**¿Por qué Hermes nativo y no en proot?**
Hermes corre en Python con venv. Termux tiene Python 3.13 nativo. No hay dependencia de glibc — el venv funciona con Bionic libc directamente.

---

## Estructura del repo

```
termux-ai-stack/
├── instalar.sh                    ← entrada única — curl + bash
├── README.md
├── LICENSE
├── scripts/
│   ├── menu.sh                    ← dashboard TUI principal
│   ├── menu_nativo.sh             ← módulos Termux nativos
│   ├── menu_proot.sh              ← n8n (proot/udocker) + dashboard Servicios
│   ├── menu_entorno.sh            ← módulo [8] Entorno
│   ├── backup.sh                  ← backup modular completo
│   ├── restore.sh                 ← restore modular
│   ├── install_n8n.sh             (N8N_INSTALL_MODE=1|2 → proot|udocker)
│   ├── install_claude.sh          (CLAUDE_METHOD=native|legacy)
│   ├── install_ollama.sh          (OLLAMA_INSTALL_MODE)
│   ├── install_opencode.sh        (solo nativo glibc)
│   ├── install_openclaw.sh        (solo nativo glibc)
│   ├── install_hermes.sh
│   ├── install_codex.sh
│   ├── install_antigravity.sh
│   ├── install_expo.sh
│   ├── install_python.sh
│   ├── install_remote.sh          (SSH + Cloudflared)
│   └── install_entorno.sh
├── python/
│   └── bots/                      ← vision_bot.py, bot_utils.py, image_archive.py
└── workflows/                     ← WF2, WF3 JSON para importar en n8n
```

---

## Instalación por módulo

Si no quieres usar el instalador maestro, cada script funciona de forma independiente:

```bash
# n8n + cloudflared (pregunta proot o udocker si no se fija N8N_INSTALL_MODE)
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_n8n.sh \
  -o install_n8n.sh && bash install_n8n.sh
# o silencioso, eligiendo modo:  N8N_INSTALL_MODE=1 bash install_n8n.sh --silent  (1=proot, 2=udocker)

# OpenCode (nativo glibc)
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_opencode.sh \
  -o install_opencode.sh && bash install_opencode.sh

# OpenClaw (nativo glibc)
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_openclaw.sh \
  -o install_openclaw.sh && bash install_openclaw.sh

# Hermes Agent
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_hermes.sh \
  -o install_hermes.sh && bash install_hermes.sh

# Claude Code (pregunta método native/legacy si no se fija CLAUDE_METHOD)
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_claude.sh \
  -o install_claude.sh && bash install_claude.sh
# o silencioso, eligiendo método:  CLAUDE_METHOD=native bash install_claude.sh --silent

# Codex CLI
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_codex.sh \
  -o install_codex.sh && bash install_codex.sh

# Antigravity CLI
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_antigravity.sh \
  -o install_antigravity.sh && bash install_antigravity.sh

# Ollama (estándar)
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_ollama.sh \
  -o install_ollama.sh && bash install_ollama.sh

# Expo / EAS CLI
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_expo.sh \
  -o install_expo.sh && bash install_expo.sh

# Python + SQLite
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_python.sh \
  -o install_python.sh && bash install_python.sh

# Remote (SSH + Cloudflared)
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_remote.sh \
  -o install_remote.sh && bash install_remote.sh

# Entorno (proot-distro + Desktop + VNC + GPU)
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_entorno.sh \
  -o install_entorno.sh && bash install_entorno.sh
```

> Todos los scripts aceptan `--silent` (sin preguntas interactivas) y `--force` (reinstalar aunque ya esté). Tienen checkpoints automáticos — si falla a mitad, vuélvelo a ejecutar y continúa desde donde quedó.

---

## Actualizar scripts

Desde el dashboard, presiona `[u]`. Descarga la versión más reciente de todos los scripts desde GitHub y recarga el menú automáticamente.

O manualmente:
```bash
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/menu.sh \
  -o ~/menu.sh && exec bash ~/menu.sh
```

---

## Bots e IA — ecosistema

```
Telegram usuario
    ↓ mensaje de texto o imagen
┌─── Vía n8n (webhook) ───────────────────────────────────────┐
│ n8n webhook (proot :5678) · URL pública cloudflared         │
│     ↓                                                        │
│ bot_history.db (SQLite — historial por chat_id)             │
│     ↓                                                        │
│ Ollama :11434 (Termux nativo)                               │
│     ├─ texto  → qwen2.5:0.5b / qwen2.5:1.5b / llama3.2:1b │
│     └─ visión → moondream:1.8b / llava-phi3:3.8b           │
└─────────────────────────────────────────────────────────────┘
┌─── Vía Hermes (nativo) ─────────────────────────────────────┐
│ Hermes gateway (long polling — sin URL pública)             │
│     ↓                                                        │
│ Proveedor IA (OpenRouter / Anthropic / Ollama local)        │
│     ↓                                                        │
│ Memoria persistente + tool calling nativo                   │
└─────────────────────────────────────────────────────────────┘
    ↓
respuesta → Telegram

WF2 — Bot texto + historial SQLite  (workflows/wf2_texto_ollama_http_v3.json)
WF3 — Bot visión + HTTP             (workflows/wf3_vision_http_v4.json)
```

---

## Problemas conocidos

| Problema | Estado |
|----------|--------|
| moondream:1.8b responde en idioma de la imagen | ⚠️ Workaround: prompt forzado en español |
| Open WebUI incompatible con Python 3.13 | 🔍 Pendiente revisión — requería Python < 3.13, verificar soporte actual |

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
✅ Fase 8a — App React Native (v3.2.0 · versionCode 9)
✅ Fase 8b — Chat Ollama asíncrono con historial SQLite · visión
✅ Fase 8c — Tests T1-T7 · vision_bot · bot_utils
✅ Fase 9  — OpenCode + OpenClaw en proot · menú 3 archivos
✅ Fase 10 — Fixes: OpenCode --cwd · OpenClaw sin navegador
              Config Ollama v1.15.5 · caché persistente proot
✅ Fase 11 — Hermes Agent nativo · kairos_manager.py
              Scripts --silent/--force · variantes por módulo
✅ Fase 12 — KairosApp (fork termux-app) · UI nativa Kotlin
              4 tabs · BottomSheet instalación · terminal overlay

📋 Fase 13 — KairosApp completa: lógica real de módulos · wizard primer arranque
              submenús conectados · WebView para n8n/OpenClaw/OpenCode
📋 Fase 14 — llama.cpp embebido en la app como .so (NDK)
              Inferencia local sin Ollama · GPU Vulkan (llamux)
📋 Fase 15 — Chat web desde la app (Ollama, OpenCode, Claude Code, Hermes)
              Control remoto del teléfono via SSH desde PC u otro dispositivo
```

---

## Versiones sugeridas

Versiones probadas y confirmadas funcionales en ARM64 Termux. Cambiar sin validar puede romper módulos.

| Componente | Versión | Notas |
|------------|---------|-------|
| Claude Code legacy | @2.1.111 | >2.1.111 usa binario nativo incompatible con Bionic libc |
| Node.js proot n8n (sistema) | v20.20.2 LTS | v22+ rompe `isolated-vm` en n8n |
| Node.js OpenClaw (nativo glibc) | v22-24 | Rango probado — versiones más nuevas (ej. v26) rompen el ABI de módulos nativos que OpenClaw usa |
| Expo SDK | ~52.0.0 | SDK 53+ obliga Nueva Arquitectura → crash ARM64 Bionic |
| React Native | 0.76.9 | Par fijo con Expo SDK 52 |
| newArchEnabled | false | Crash ARM64 sin root si se activa |
| KairosApp targetSdkVersion | 28 | SDK 29+ bloquea exec() del motor Termux |
| KairosApp NDK | r29 (29.0.14206865) | Requerido por terminal-emulator C |
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

# 2. Modo --silent (sin preguntas interactivas) y --force
# Todos los install_*.sh deben aceptar estos flags

# 3. stdin siempre explícito en Termux
read -r VAR < /dev/tty

# 4. Sin /tmp/ — Android 15 lo monta noexec
TMPFILE="$HOME/tmp/tempfile_$$"

# 5. SQLite en Python — datetime explícito
# ❌  DEFAULT (datetime('now'))
# ✅  datetime.now().strftime('%Y-%m-%d %H:%M:%S')

# 6. HTTP en Python — sin requests
# ❌  import requests
# ✅  from urllib import request as ureq

# 7. Escribir en registry al finalizar
echo "modulo.installed=true" >> ~/.android_server_registry
echo "modulo.version=x.y.z"  >> ~/.android_server_registry
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

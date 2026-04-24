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
[![Version](https://img.shields.io/badge/Version-v4.0.0-blue?style=flat-square)](.)
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
Tu Android (sin root)
  └─ Termux
       ├─ n8n + cloudflared  → automatización y bots Telegram     :5678
       ├─ Claude Code         → agente de IA en terminal
       ├─ Ollama              → modelos de IA locales              :11434
       │    ├─ vision_bot.py  → bot de visión para n8n
       │    └─ bot_utils.py   → helpers SQLite reutilizables
       ├─ EAS CLI             → compilación de apps Expo/RN
       ├─ Python + SQLite     → scripting, automatización, BD
       ├─ SSH                 → acceso remoto desde PC             :8022
       ├─ Dashboard web       → panel de control desde navegador   :8080
       ├─ backup.sh           → backup completo o por módulo
       ├─ restore.sh          → restaurar desde GitHub o backup propio
       └─ menu.sh             → dashboard TUI — se abre al iniciar Termux
```

> 🤖 Este proyecto está siendo desarrollado con [Claude](https://claude.ai) de Anthropic. A medida que crezca, Claude Code participará directamente como contribuidor en el repo.

---

## Dashboard TUI

Al abrir Termux aparece automáticamente el dashboard. Muestra el estado real de cada módulo y permite instalar, controlar y hacer backup sin escribir comandos.

```
  ╔══════════════════════════════════════════╗
  ║  ⬡ TERMUX·AI·STACK                      ║
  ║  RAM: 4.2GB  Disk: 77G  IP: 192.168.1.x ║
  ╠══════════════════════════════════════════╣
  ║  MÓDULOS                                 ║
  ╚══════════════════════════════════════════╝

  [1] ⬡ n8n           ● activo    → submenú
       v2.8.4

  [2] ◆ Claude Code   ● listo     claude
       v2.1.111

  [3] ◎ Ollama        ● listo     → submenú
       v0.21.0

  [4] ◈ Expo / EAS    ● listo     → submenú
       v18.7.0

  [5] ◉ Python        ● listo     → submenú
       v3.13.13

  [6] ⌁ SSH           ● activo    → submenú
       v10.3

  ──────────────────────────────────────────
  [0] ◉ Backup / Restore

  ──────────────────────────────────────────
  [r] refrescar  [h] ayuda  [u] actualizar  [s] shell  [d] desinstalar
```

---

## Módulos

| Módulo | Versión | Script | Dónde corre | Puerto |
|--------|---------|--------|-------------|--------|
| n8n + cloudflared | 2.8.4 | `install_n8n.sh` | proot Debian | 5678 |
| Claude Code | 2.1.111 | `install_claude.sh` | Termux nativo | — |
| Ollama | 0.21.0 | `install_ollama.sh` | Termux nativo | 11434 |
| Expo / EAS CLI | 18.7.0 | `install_expo.sh` | Termux nativo | — |
| Python + SQLite | 3.13.13 | `install_python.sh` | Termux nativo | — |
| SSH | OpenSSH 10.3 | `install_ssh.sh` | Termux nativo | 8022 |
| Dashboard web | 1.3.0 | `install_remote.sh` | Termux nativo | 8080 |

Cada módulo es independiente — se instala solo o desde el menú maestro.

---

## Backup y Restore

El sistema de backup genera archivos `.tar.xz` por módulo, verifica integridad con SHA256 y permite restaurar desde GitHub Releases o desde tu propio backup.

### Hacer backup

```bash
bash ~/backup.sh                   # backup completo (6 partes + checksums)
bash ~/backup.sh --module ollama   # solo Ollama
bash ~/backup.sh --module claude   # solo Claude Code
bash ~/backup.sh --module n8n      # solo n8n + cloudflared
bash ~/backup.sh --module expo     # solo EAS CLI
bash ~/backup.sh --module base     # solo scripts y configuración base
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
| part1-termux-base | .bashrc + scripts + .termux | ~120KB |
| part2-claude-code | @anthropic-ai/claude-code completo | ~12KB |
| part3-eas-expo | eas-cli + credenciales ~/.expo | ~12MB |
| part4-ollama | binario + libs (sin modelos) | ~9MB |
| part5-n8n-data | n8n + cloudflared + workflows | ~15MB |
| part6-proot-debian | rootfs Debian completo | ~834MB |

> ⚠️ Los modelos de Ollama NO se incluyen en el backup. Descárgalos de nuevo con `ollama pull`.

---

## Módulo: n8n

Automatización de workflows. Corre dentro de proot Debian para tener glibc real (necesario para node-gyp). Cloudflared provee una URL pública desde internet sin configurar puertos.

```
✅ proot-distro + Debian Bookworm ARM64
✅ Node.js 20 LTS + n8n + cloudflared (dentro del proot)
✅ Túnel cloudflared → URL pública (dominio fijo o URL temporal)
✅ Webhook Telegram funcionando (WEBHOOK_URL + N8N_PROTOCOL=https)
✅ Scripts de control: start / stop / url / status / logs
✅ Sesión tmux "n8n-server" en background
```

**Variables requeridas para webhooks Telegram:**
```bash
# En ~/.env_n8n (configurable desde menú → n8n → [8]):
N8N_WEBHOOK_URL=https://tu-dominio.com

# n8n arranca automáticamente con:
export WEBHOOK_URL=https://tu-dominio.com
export N8N_PROTOCOL=https
export N8N_PROXY_HOPS=1
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
| `qwen2.5:0.5b` | ~397MB | Texto liviano, muy rápido |
| `qwen2.5:1.5b` | ~986MB | Balance velocidad/calidad |
| `gemma3:1b` | ~815MB | Texto general |
| `moondream:1.8b` | ~1.7GB | Visión — análisis de imágenes |

> ⚠️ No usar modelos 7B o más en dispositivos móviles — crash por RAM insuficiente.

**Submenú desde el dashboard:**
```
[1] Iniciar / detener servidor
[2] Chat rápido        (sin historial)
[3] Chat completo      (SQLite · historial persistente)
[4] Chat con imágenes  (visión · redimensionado automático)
[5] Modelos            (ver / descargar / eliminar)
[6] Configurar historial SQLite
```

---

## Módulo: Claude Code

Agente de IA de Anthropic. Requiere workaround en ARM64 porque el binario nativo usa glibc y Termux usa Bionic libc.

```
✅ nodejs-lts (v24)
✅ @anthropic-ai/claude-code @2.1.111 fijo
✅ Lanzamiento via node cli.js (workaround ARM64/Bionic)
✅ Alias configurado en .bashrc
```

> **Nota técnica:** Versión fijada en @2.1.111 — versiones superiores incluyen binario nativo incompatible con Bionic libc de Android.

**Comandos:**
```bash
claude                     # agente interactivo
claude -p "instrucción"    # modo directo
claude --continue          # continuar última sesión
```

---

## Módulo: Python + SQLite

Scripting, automatización e integración con el stack.

```
✅ Python 3.13.13 vía pkg (Termux nativo)
✅ pip incluido
✅ sqlite3 CLI + módulo Python
✅ Pillow para procesamiento de imágenes (ARM64)
✅ urllib builtin para HTTP (sin dependencias externas)
```

> **Nota ARM64:** `DEFAULT (datetime('now'))` no funciona en Python/SQLite en Termux. El stack usa siempre `datetime.now()` explícito en Python. Ver `bot_utils.py` como referencia.

**Comandos directos:**
```bash
python3                                       # REPL interactivo
pip install PAQUETE --break-system-packages   # instalar paquete
sqlite3 archivo.db                            # CLI SQLite
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
```

**Conectar desde PC:**
```bash
ssh -p 8022 usuario@192.168.x.x
```

---

## Arquitectura

```
Android (sin root) — ARM64
  └─ Termux (F-Droid)
       ├─ menu.sh v4.0.0 → TUI principal
       │
       ├─ Scripts de control (~/):
       │    ├─ backup.sh / restore.sh
       │    ├─ start_servidor.sh / ollama_start.sh
       │    ├─ vision_bot.py     → bot visión para n8n
       │    ├─ bot_utils.py      → helpers SQLite
       │    └─ install_*.sh      → instaladores
       │
       ├─ tmux
       │    ├─ "n8n-server"     → n8n + cloudflared
       │    └─ "ollama-server"  → Ollama :11434
       │
       ├─ Python 3.13.13
       │    ├─ sqlite3 3.53.0 (builtin)
       │    └─ Pillow (ARM64 — visión)
       │
       ├─ Node.js LTS v24
       │    ├─ Claude Code v2.1.111
       │    └─ EAS CLI v18.7.0
       │
       ├─ OpenSSH 10.3 (:8022)
       ├─ Ollama v0.21.0 (:11434)
       ├─ Dashboard web (:8080)
       │
       └─ proot-distro + Debian Bookworm ARM64
            ├─ Node.js 20 LTS
            ├─ n8n 2.8.4 (:5678)
            └─ cloudflared → túnel público

BDs SQLite:
  ~/ollama_chat.db   → historial chat (por chat_id + modelo)
  ~/bot_history.db   → historial bot Telegram (por chat_id)
```

**¿Por qué proot para n8n?**
n8n requiere glibc (Linux estándar). Termux usa Bionic libc (Android). El proot con Debian provee el entorno sin root.

**¿Por qué Node.js 20 en proot y v24 en Termux?**
n8n usa `isolated-vm`, que rompe en Node.js 22+. Claude Code requiere Node.js ≥18.

---

## Estructura del repo

```
termux-ai-stack/
├── instalar.sh              ← entrada única — curl + bash
├── menu.sh                  ← dashboard TUI v4.0.0
├── README.md
├── ARCHITECTURE.md          ← documentación técnica detallada
├── ROADMAP.md               ← estado del proyecto y versiones
├── MEJORAS_PENDIENTES.md    ← próximas mejoras ordenadas
├── scripts/
│   ├── backup.sh
│   ├── restore.sh
│   ├── install_n8n.sh
│   ├── install_claude.sh
│   ├── install_ollama.sh    ← genera vision_bot.py + bot_utils.py
│   ├── install_expo.sh
│   ├── install_python.sh
│   ├── install_remote.sh
│   └── install_ssh.sh
├── python/
│   ├── vision_bot.py        ← bot visión para n8n/Telegram
│   ├── bot_utils.py         ← helpers SQLite reutilizables
│   └── dashboard/
│       ├── dashboard_server.py
│       └── index.html
├── tests/
│   ├── test_1_sqlite.sh
│   ├── test_2_python.sh
│   ├── test_3_ollama_sqlite.sh
│   ├── test_4_ollama_vision.sh
│   ├── test_5_vision_pipeline.sh
│   ├── test_6_n8n_ollama_sqlite.sh
│   └── test_7_bot_vision.sh
└── workflows/               ← WF1-WF4 JSON para n8n (próximamente)
```

---

## Instalación por módulo

Si no quieres usar el instalador maestro, cada script funciona de forma independiente:

```bash
# n8n + cloudflared
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/scripts/install_n8n.sh \
  -o install_n8n.sh && bash install_n8n.sh

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

## Problemas conocidos

| Problema | Estado |
|----------|--------|
| Ollama respuestas lentas en modelos >1GB | ⏳ Bug #27290 termux-packages — pendiente fix oficial |
| Claude Code UI web no funciona | ❌ `node-pty` sin prebuild ARM64 — usar terminal directo |
| Open WebUI incompatible con Python 3.13 | ❌ Requiere Python <3.13 — pendiente soporte oficial |
| SSH solo en red local | ⏳ Para internet usar cloudflared SSH tunnel |
| moondream:1.8b responde en idioma de la imagen | ⚠️ Workaround: prompt forzado en español |

---

## Roadmap

```
✅ Fase 1 — Módulos independientes
✅ Fase 2 — Script maestro (instalar.sh)
✅ Fase 3 — Dashboard TUI (menu.sh)
✅ Fase 4 — Backup/Restore completo
✅ Fase 5 — Mejoras UI, monitoring y fixes
✅ Fase 6 — Python + SQLite · SSH
✅ Fase 7 — Webhook n8n · Telegram + Ollama
✅ Fase 8a — Dashboard web (:8080)
✅ Fase 8b — App React Native (v1.5.0 código listo)
✅ Fase 8c — Chat Ollama con historial SQLite · visión
✅ Fase 8d — Tests T1-T7 · vision_bot · bot_utils

📋 Fase 9 — Bots Telegram funcionales con n8n
     WF1-WF4: workflows texto + visión
     Contexto persistente por usuario (chat_id)
     BD por modelo en Ollama

📋 Fase 10 — APK estable + distribución
     App v1.5.0 compilada desde GitHub Actions
     APK en GitHub Releases
```

---

## Dispositivos probados

| Dispositivo | Android | RAM | Estado |
|------------|---------|-----|--------|
| Xiaomi POCO F5 | 15 (HyperOS 2.0) | 12 GB | ✅ Todo funcionando |
| Xiaomi Mi 11 Lite 5G NE | 13+ (EvolutionX) | 8 GB | ✅ n8n + webhook OK |

> Si lo probaste en otro dispositivo, abre un issue con: modelo · Android · RAM · qué pasó.

---

## Contribuir

1. Fork del repo
2. Prueba en tu dispositivo
3. Abre un issue: modelo · Android · error exacto
4. O PR directo con el fix

Para agregar un módulo nuevo, sigue el patrón de `install_ollama.sh`: checkpoints, registry, fix stdin (`read -r < /dev/tty`), sin `DEFAULT (datetime('now'))` en SQLite Python, HTTP con `urllib` en lugar de `requests`.

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

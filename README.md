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
[![Version](https://img.shields.io/badge/Version-v3.1.2-blue?style=flat-square)](.)
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
       ├─ n8n + cloudflared  → automatización y workflows       :5678
       ├─ Claude Code         → agente de IA en terminal
       ├─ Ollama              → modelos de IA locales            :11434
       ├─ EAS CLI             → compilación de apps Expo/RN
       ├─ Python + SQLite     → scripting, automatización, BD
       ├─ SSH                 → acceso remoto desde PC           :8022
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

Al presionar `[1-6]` con un módulo no instalado, aparece:
```
  ¿Cómo instalar n8n?
  [1] Instalación limpia       → descarga e instala desde cero
  [2] Desde GitHub Releases    → restaura backup precompilado (~segundos)
  [b] Cancelar
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
bash ~/restore.sh --module ollama               # módulo específico (pregunta fuente)
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

**Submenú desde el dashboard:**
```
[1] Iniciar n8n + cloudflared
[2] Detener servidor
[3] Ver URL pública
[4] Estado del sistema
[5] Ver logs en vivo
[6] Consola Debian (proot)
[7] Cambiar token cloudflared
[8] Configurar URL webhook n8n
```

**Comandos directos:**
```bash
bash ~/start_servidor.sh   # inicia n8n + cloudflared
bash ~/stop_servidor.sh    # detiene todo
bash ~/ver_url.sh          # URL pública actual
bash ~/n8n_status.sh       # estado detallado
proot-distro login debian  # consola dentro del proot
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

## Módulo: Claude Code

Agente de IA de Anthropic. Requiere workaround en ARM64 porque el binario nativo usa glibc y Termux usa Bionic libc.

```
✅ nodejs-lts (v24)
✅ @anthropic-ai/claude-code @2.1.111 fijo
✅ Lanzamiento via node cli.js (workaround ARM64/Bionic)
✅ Alias configurado en .bashrc
```

**Comandos:**
```bash
claude                     # agente interactivo
claude -p "instrucción"    # modo directo
claude --continue          # continuar última sesión
```

> **Nota técnica:** Claude Code incluye binarios x86/x64 incompatibles con ARM64. El workaround es invocar `cli.js` directamente con Node.js en lugar del binario empaquetado. Funciona 100% — probado en POCO F5 · Android 15 · ARM64.

---

## Módulo: Ollama

Modelos de IA locales. Sin internet, sin costo por token, API compatible con OpenAI.

```
✅ pkg install ollama (compilado para Termux ARM64)
✅ Servidor en :11434 con API compatible OpenAI
✅ Sesión tmux "ollama-server" en background
✅ Chat por número desde el submenú del dashboard
✅ Descarga de modelos recomendados desde el menú
```

**Modelos recomendados (dispositivos ≥ 8GB RAM):**

| Modelo | Tamaño | Uso recomendado |
|--------|--------|-----------------|
| `qwen2.5:0.5b` | ~397MB | Pruebas rápidas, muy liviano |
| `qwen2.5:1.5b` | ~986MB | Balance liviano |
| `qwen:1.8b` | ~1.1GB | Uso general |
| `llama3.2:1b` | ~1.3GB | Buena calidad, liviano |
| `phi3:mini` | ~2.3GB | Mejor calidad disponible |

> ⚠️ No usar modelos 7B o más en dispositivos móviles — crash garantizado por RAM insuficiente.

**Submenú desde el dashboard:**
```
[1] Iniciar servidor   :11434
[2] Chat rápido        (lista modelos instalados por número)
[3] Ver modelos
[4] Descargar modelo   (lista recomendados + manual)
[5] Detener servidor
```

**Comandos directos:**
```bash
bash ~/ollama_start.sh     # inicia en tmux :11434
bash ~/ollama_stop.sh      # detiene
ollama list                # modelos instalados
ollama pull qwen2.5:0.5b   # descargar modelo
ollama run qwen2.5:0.5b    # chat directo
```

---

## Módulo: Expo / EAS CLI

Compila apps React Native en la nube de Expo sin compilar localmente en el teléfono.

```
✅ nodejs-lts (v24) + eas-cli vía npm
✅ Scripts: build, status, submit, push, info
✅ Symlink /usr/bin/eas apuntando a eas-cli
```

**Submenú desde el dashboard:**
```
[1] Build APK preview
[2] Build producción (AAB)
[3] Ver builds activos
[4] Login en expo.dev
[5] Info / estado general
```

**Comandos directos:**
```bash
eas build --platform android --profile preview     # APK de prueba
eas build --platform android --profile production  # AAB para Play Store
eas build:list                                     # builds activos
eas whoami                                         # usuario logueado
```

---

## Módulo: Python + SQLite

Scripting, automatización e integración con el stack. Incluye acceso directo a la base de datos interna de n8n.

```
✅ Python 3.13.13 vía pkg (Termux nativo)
✅ pip incluido
✅ sqlite3 CLI + módulo Python
✅ Acceso rápido a BD de n8n desde submenú
✅ Aliases: py3, pip3-install, sqlite-n8n
```

**Submenú desde el dashboard:**
```
[1] Ver versión e info
[2] Abrir REPL (python3)
[3] Instalar paquete (pip)
[4] Listar paquetes instalados
[5] SQLite → submenú
     [1] Listar bases de datos
     [2] Abrir BD interactivo
     [3] Ver tablas
     [4] BD de n8n (acceso rápido)
     [5] Exportar a CSV
     [6] Crear nueva BD
```

**Comandos directos:**
```bash
python3                                       # REPL interactivo
pip install PAQUETE                           # instalar paquete
pip install --break-system-packages PAQUETE   # si pip rechaza
sqlite3 archivo.db                            # CLI SQLite
sqlite-n8n                                    # BD interna de n8n (alias)
```

---

## Módulo: SSH

Acceso remoto completo desde PC, VS Code o cualquier cliente SSH. Sin configuración de router, funciona en la misma red WiFi.

```
✅ OpenSSH 10.3 vía pkg (Termux nativo)
✅ Puerto 8022 (sin root requerido)
✅ Autenticación por contraseña y clave pública
✅ Dashboard TUI accesible desde PC via SSH
✅ Claude Code con teclado físico desde PC
```

**Submenú desde el dashboard:**
```
[1] Iniciar servidor SSH
[2] Detener servidor SSH
[3] Ver IP + comando de conexión
[4] Agregar clave pública (PC)
[5] Ver conexiones activas
[6] Cambiar contraseña Termux
```

**Conectar desde PC:**
```bash
# Terminal / PowerShell:
ssh -p 8022 usuario@192.168.x.x

# VS Code Remote-SSH:
# usuario@192.168.x.x:8022
```

---

## Arquitectura

```
Android (sin root) — ARM64
  └─ Termux (F-Droid)
       ├─ ~/.bashrc
       │    └─ auto-ejecuta menu.sh al abrir Termux
       │
       ├─ menu.sh v3.1.2
       │    └─ dashboard TUI — control de todos los módulos
       │
       ├─ Scripts de control (~/):
       │    ├─ backup.sh        → genera backups por módulo
       │    ├─ restore.sh       → restaura desde GitHub o backup local
       │    ├─ start_servidor.sh / stop_servidor.sh
       │    ├─ ollama_start.sh / ollama_stop.sh
       │    ├─ ssh_start.sh / ssh_stop.sh
       │    └─ install_*.sh     → instaladores de cada módulo
       │
       ├─ tmux
       │    ├─ sesión "n8n-server"     → n8n + cloudflared en background
       │    └─ sesión "ollama-server"  → Ollama en background
       │
       ├─ Node.js LTS v24 (Termux nativo)
       │    ├─ Claude Code v2.1.111    → via node cli.js
       │    └─ EAS CLI v18.7.0         → via symlink /usr/bin/eas
       │
       ├─ Python 3.13.13 (Termux nativo)
       │    └─ sqlite3 3.53.0 (incluido)
       │
       ├─ OpenSSH 10.3 (Termux nativo · puerto 8022)
       │
       ├─ Ollama (Termux nativo · puerto 11434)
       │
       └─ proot-distro + Debian Bookworm ARM64
            ├─ Node.js 20 LTS
            ├─ n8n 2.8.4              → :5678
            └─ cloudflared            → túnel público

~/.android_server_registry  → estado de todos los módulos (key=value)
~/.env_n8n                  → variables de entorno n8n (WEBHOOK_URL etc.)
```

**¿Por qué proot para n8n?**
n8n requiere glibc (Linux estándar). Termux usa Bionic libc (Android). El proot con Debian provee el entorno completo sin root. Claude Code, Ollama, Python y SSH corren en Termux nativo porque tienen soporte directo para ARM64/Bionic.

**¿Por qué Node.js 20 en proot y v24 en Termux?**
n8n usa `isolated-vm`, que rompe en Node.js 22+. Claude Code requiere Node.js ≥18. Cada entorno usa la versión óptima.

---

## Estructura del repo

```
termux-ai-stack/
├── instalar.sh              ← entrada única — curl + bash
├── README.md                ← este archivo
├── ARCHITECTURE.md          ← documentación técnica detallada
├── PROGRESO.md              ← estado del proyecto y roadmap interno
├── MEJORAS_RECOMENDADAS.md  ← roadmap de mejoras futuras
└── Script/
    ├── menu.sh              ← dashboard TUI v3.1.2
    ├── backup.sh            ← sistema de backup v2.2.0
    ├── restore.sh           ← sistema de restore v2.4.0
    ├── install_n8n.sh       ← instalador n8n + cloudflared v2.5.0
    ├── install_claude.sh    ← instalador Claude Code v2.8.0
    ├── install_ollama.sh    ← instalador Ollama v1.2.0
    ├── install_expo.sh      ← instalador EAS CLI v1.1.0
    ├── install_python.sh    ← instalador Python + SQLite v1.0.0
    └── install_ssh.sh       ← instalador SSH v1.0.2
```

---

## Instalación por módulo

Si no quieres usar el instalador maestro, cada script funciona de forma independiente:

```bash
# n8n + cloudflared
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_n8n.sh \
  -o install_n8n.sh && bash install_n8n.sh

# Claude Code
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_claude.sh \
  -o install_claude.sh && bash install_claude.sh

# Ollama
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_ollama.sh \
  -o install_ollama.sh && bash install_ollama.sh

# Expo / EAS CLI
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_expo.sh \
  -o install_expo.sh && bash install_expo.sh

# Python + SQLite
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_python.sh \
  -o install_python.sh && bash install_python.sh

# SSH
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_ssh.sh \
  -o install_ssh.sh && bash install_ssh.sh
```

> Cada script verifica si el módulo ya está instalado antes de hacer nada. Si falla a mitad, vuélvelo a ejecutar — tiene checkpoints automáticos.

---

## Actualizar scripts

Desde el dashboard, presiona `[u]`. Descarga la versión más reciente de todos los scripts desde GitHub y recarga el menú automáticamente.

O manualmente:
```bash
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/menu.sh \
  -o ~/menu.sh && exec bash ~/menu.sh
```

---

## Problemas conocidos

| Problema | Estado |
|----------|--------|
| Ollama respuestas lentas (>20s en modelos >1GB) | ⏳ Limitación de hardware móvil — usar modelos ≤1GB |
| Claude Code UI web no funciona | ❌ `node-pty` sin prebuild ARM64 — usar terminal directo |
| Open WebUI incompatible con Python 3.13 | ❌ Requiere Python <3.13 — pendiente soporte oficial |
| SSH solo en red local | ⏳ Para internet usar cloudflared SSH tunnel |

---

## Roadmap

```
✅ Fase 1 — Módulos independientes
✅ Fase 2 — Script maestro (instalar.sh)
✅ Fase 3 — Dashboard TUI v2 (menu.sh)
✅ Fase 3.5 — Fixes y pulido
✅ Fase 4 — Backup/Restore completo
✅ Fase 5 — Mejoras UI, monitoring y fixes
✅ Fase 6 — Módulos nuevos (Python + SQLite · SSH)
✅ Fase 7 — Fix webhook n8n · Telegram + Ollama funcionando

📋 Fase 8 — App Android nativa (React Native)
     Interfaz con switches para controlar módulos
     Reemplaza el TUI bash con UI visual
     Termux sigue siendo el motor — la app solo controla
     EAS Build → APK distribuido desde GitHub Releases
```

---

## Dispositivos probados

| Dispositivo | Android | RAM | Estado |
|------------|---------|-----|--------|
| Xiaomi POCO F5 (Redmi Note 12 Turbo) | 15 (HyperOS 2.0) | 12 GB | ✅ Todo funcionando |
| Xiaomi Mi 11 Lite 5G NE | 13+ (EvolutionX) | 8 GB | ✅ n8n + webhook funcionando |

> Si lo probaste en otro dispositivo, abre un issue con: modelo · Android · RAM · qué pasó.

---

## Contribuir

1. Fork del repo
2. Prueba en tu dispositivo
3. Abre un issue: modelo · Android · error exacto
4. O PR directo con el fix

Para agregar un módulo nuevo, sigue el patrón de `install_ollama.sh`: checkpoints, registry, fix stdin (`echo -n` + `read -r`), sin dependencia de red en el menú.

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

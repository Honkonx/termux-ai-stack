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
║          A I  ·  S T A C K                               ║
╚═══════════════════════════════════════════════════════════╝
```

**Tu Android como servidor de desarrollo. Sin root. Sin VPS. Sin costos.**

[![Platform](https://img.shields.io/badge/Platform-Android%20ARM64-3DDC84?style=flat-square&logo=android&logoColor=white)](.)
[![Termux](https://img.shields.io/badge/Termux-F--Droid-000000?style=flat-square&logo=terminal&logoColor=white)](https://f-droid.org/packages/com.termux/)
[![Root](https://img.shields.io/badge/Root-No%20required-brightgreen?style=flat-square)](.)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Active%20Development-yellow?style=flat-square)](.)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude%20AI-CC785C?style=flat-square&logo=anthropic&logoColor=white)](https://claude.ai)

</div>

---

## Instalación

Abre Termux y pega este comando:

```bash
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/instalar.sh | bash
```

Eso es todo. El script se encarga del resto.

> **Requisito:** [Termux desde F-Droid](https://f-droid.org/packages/com.termux/) — no uses la versión de Play Store, está desactualizada.

---

## ¿Qué es esto?

**termux-ai-stack** convierte tu teléfono Android en un servidor de desarrollo completo usando [Termux](https://termux.dev). Sin root, sin configuración manual, un script por módulo.

> 🤖 Este proyecto está siendo desarrollado con [Claude](https://claude.ai) de Anthropic — arquitectura, scripts y documentación. A medida que crezca, Claude Code participará directamente como contribuidor en el repo.

```
Tu Android (sin root)
  └─ Termux
       ├─ n8n          → automatización y workflows      :5678
       ├─ Claude Code  → agente de IA en terminal
       ├─ Ollama       → modelos de IA locales           :11434
       ├─ EAS CLI      → compilación de apps Expo/RN
       └─ menu.sh      → dashboard TUI al abrir Termux
```

---

## Módulos

| Módulo | Estado | Script |
|--------|--------|--------|
| **n8n + cloudflared** | ✅ Listo | `Script/install_n8n.sh` |
| **Claude Code** | ✅ Listo | `Script/install_claude.sh` |
| **Ollama** | ✅ Listo | `Script/install_ollama.sh` |
| **Expo / EAS CLI** | ✅ Listo | `Script/install_expo.sh` |
| **Dashboard TUI** | 🔧 En desarrollo | `Script/menu.sh` |

Cada módulo es independiente — se puede instalar solo o desde el menú del maestro.

---

## Estructura del repo

```
termux-ai-stack/
├── instalar.sh          ← entrada única (curl | bash)
├── README.md
└── Script/
    ├── install_n8n.sh      ← n8n + cloudflared (proot Debian)
    ├── install_claude.sh   ← Claude Code (Termux nativo, workaround ARM64)
    ├── install_ollama.sh   ← Ollama (Termux nativo)
    ├── install_expo.sh     ← EAS CLI + scripts de build
    └── menu.sh             ← dashboard TUI (próximamente)
```

---

## Instalación por módulo

Si no quieres usar el instalador maestro, cada script funciona de forma independiente:

```bash
# n8n + cloudflared
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_n8n.sh | bash

# Claude Code
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_claude.sh | bash

# Ollama
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_ollama.sh | bash

# Expo / EAS CLI
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/Script/install_expo.sh | bash
```

> Cada script verifica si el módulo ya está instalado antes de hacer nada.
> Si falla a mitad, vuélvelo a ejecutar — tiene checkpoints automáticos.

---

## Módulo: n8n

Instala n8n (automatización de workflows) dentro de proot Debian ARM64, con cloudflared para acceso público.

```
✅ proot-distro + Debian Bookworm ARM64
✅ Node.js 20 LTS + n8n + cloudflared (dentro del proot)
✅ Túnel cloudflared → URL pública desde internet
✅ Scripts de control: start/stop/url/status/backup
✅ Arranque automático con Termux:Boot
```

**Comandos:**
```bash
n8n-start     # inicia n8n + cloudflared en tmux
n8n-stop      # detiene todo
n8n-url       # muestra URL pública
n8n-status    # estado del sistema
n8n-backup    # backup de workflows a /sdcard
debian        # consola Debian proot
```

---

## Módulo: Claude Code

Instala el agente de IA de Anthropic con el workaround necesario para ARM64.

```
✅ Node.js >= 18 (instala si falta)
✅ npm install -g @anthropic-ai/claude-code
✅ Alias funcional apuntando a cli.js (workaround ARM64)
```

**Comandos:**
```bash
claude                    # agente interactivo
claude -p "instrucción"   # modo directo
claude --continue         # continuar última sesión
claude-update             # actualizar
```

> **Nota técnica:** Claude Code incluye binarios x86/x64 incompatibles con ARM64. El workaround es invocar `cli.js` directamente con Node.js. Funciona 100% — probado en POCO F5 · Android 15 · Node.js 25.x.

---

## Módulo: Ollama

Corre modelos de IA localmente sin internet ni costo por token.

```
✅ pkg install ollama (compilado para Termux ARM64)
✅ Servidor en :11434 con API compatible OpenAI
✅ Script de inicio/parada con sesión tmux
✅ Descarga de modelo inicial opcional
```

**Modelos recomendados (≥ 8GB RAM):**

| Modelo | Tamaño | Uso |
|--------|--------|-----|
| `qwen:0.5b` | ~395 MB | Pruebas rápidas |
| `qwen:1.8b` | ~1.1 GB | Uso general |
| `phi3:mini` | ~2.3 GB | Calidad real |
| `llama3.2:1b` | ~1.3 GB | Balance |

> ⚠️ No usar modelos 7B o más — crash garantizado en móvil.

**Comandos:**
```bash
ollama-start          # inicia servidor en tmux
ollama-stop           # detiene
ollama run phi3:mini  # chat directo
ollama pull qwen:1.8b # descargar modelo
ollama-lan            # exponer en red local
```

---

## Módulo: Expo / EAS CLI

Compila apps React Native en la nube de Expo sin necesidad de compilar localmente en el teléfono.

```
✅ Node.js >= 18 + git
✅ eas-cli vía npm
✅ Scripts: build, status, submit, push
```

**Comandos:**
```bash
expo-build [proyecto] preview     # APK de prueba (~5-10 min)
expo-build [proyecto] production  # AAB para Play Store
expo-status                       # ver builds activos
expo-push [proyecto] "mensaje"    # commit + push
expo-login                        # login en expo.dev
```

---

## Arquitectura

```
Android (sin root)
  └─ Termux (F-Droid)
       ├─ Node.js (nativo)
       │    ├─ Claude Code  → alias a cli.js
       │    └─ EAS CLI      → builds Expo en la nube
       ├─ Ollama (nativo)   → :11434
       ├─ tmux              → sesiones en background
       └─ proot-distro + Debian Bookworm
            ├─ n8n          → :5678
            └─ cloudflared  → túnel público

~/.android_server_registry  → estado de módulos instalados
```

**¿Por qué proot para n8n?** n8n requiere glibc (Linux estándar) y Termux usa Bionic libc (Android). El proot con Debian provee el entorno completo sin root. Claude Code y Ollama corren en Termux nativo porque tienen soporte directo para ARM64/Bionic.

---

## Dispositivos probados

| Dispositivo | Android | RAM | Estado |
|------------|---------|-----|--------|
| Xiaomi POCO F5 (Redmi Note 12 Turbo) | 15 (HyperOS 2.0) | 12 GB | ✅ Funcionando |
| Xiaomi Mi 11 Lite 5G NE | 13+ (EvolutionX) | 8 GB | 🔧 Pendiente |

> Si lo probaste en otro dispositivo, abre un issue con: modelo · Android · qué pasó.

---

## Problemas conocidos

| Problema | Estado |
|----------|--------|
| Ollama respuestas lentas (>20s) | ⏳ Bug en termux-packages, pendiente fix oficial |
| Claude Code UI web no funciona | ❌ `node-pty` sin prebuild ARM64 — usar terminal directo |

---

## Roadmap

```
✅ Fase 1 — Módulos independientes
     install_n8n.sh · install_claude.sh · install_ollama.sh · install_expo.sh

✅ Fase 2 — Script maestro
     instalar.sh → curl | bash → instala todo

🔧 Fase 3 — Dashboard TUI
     menu.sh → se abre al iniciar Termux
     muestra estado de cada módulo en tiempo real

📋 Fase 4 — APK
     interfaz nativa Android
```

---

## Contribuir

1. Fork del repo
2. Prueba en tu dispositivo
3. Abre un issue: modelo · Android · error exacto
4. O PR directo con el fix

---

## Licencia

MIT — úsalo como quieras.

---

## Créditos

Este proyecto está siendo construido con ayuda de [Claude](https://claude.ai) de Anthropic — desde la arquitectura hasta los scripts y esta documentación. No es un secreto: es simplemente cómo se desarrolla software hoy.

A medida que el proyecto crezca, Claude Code participará directamente en el repo como contribuidor.

---

<div align="center">

Hecho con Termux · ARM64 · sin root · sin excusas

</div>

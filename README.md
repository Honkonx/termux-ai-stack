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
║              S E R V E R                                  ║
╚═══════════════════════════════════════════════════════════╝
```

**Tu Android como servidor de desarrollo. Sin root. Sin VPS. Sin costos.**

[![Platform](https://img.shields.io/badge/Platform-Android%20ARM64-3DDC84?style=flat-square&logo=android&logoColor=white)](.)
[![Termux](https://img.shields.io/badge/Termux-F--Droid-000000?style=flat-square&logo=terminal&logoColor=white)](https://f-droid.org/packages/com.termux/)
[![Root](https://img.shields.io/badge/Root-No%20required-brightgreen?style=flat-square)](.)
[![Status](https://img.shields.io/badge/Status-Active%20Development-yellow?style=flat-square)](.)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude%20AI-CC785C?style=flat-square&logo=anthropic&logoColor=white)](https://claude.ai)

</div>

---

## ¿Qué es esto?

**android-server** es una colección de scripts bash que convierten tu teléfono Android en un servidor de desarrollo completo, usando [Termux](https://termux.dev).

Sin root. Sin configuraciones manuales. Un script por módulo.

> 🤖 Este proyecto está siendo desarrollado con [Claude](https://claude.ai) de Anthropic — arquitectura, scripts y documentación. A medida que crezca, Claude Code participará directamente como contribuidor en el repo.

```
Tu Android
  └─ Termux
       ├─ n8n          → automatización y workflows  :5678
       ├─ Claude Code  → agente de IA en terminal
       ├─ Ollama       → modelos de IA locales        :11434
       ├─ EAS CLI      → compilación de apps Expo
       └─ [más módulos en camino...]
```

---

## Módulos disponibles

| Módulo | Estado | Script | Descripción |
|--------|--------|--------|-------------|
| **Claude Code** | ✅ Listo | `install_claude.sh` | Agente IA de Anthropic en terminal |
| **Ollama** | ✅ Listo | `install_ollama.sh` | Servidor de modelos IA locales |
| **n8n** | 🔧 En migración | `install_n8n.sh` | Automatización y workflows |
| **Expo / EAS** | 🔧 En migración | `install_expo.sh` | Builds de apps React Native |
| **Dashboard TUI** | 📋 Planificado | `menu.sh` | Panel de control visual en terminal |

---

## Instalación rápida

### Requisitos

- Android **13 o superior**
- Arquitectura **ARM64** (aarch64) — la mayoría de teléfonos modernos
- [Termux desde F-Droid](https://f-droid.org/packages/com.termux/) ← **no usar la versión de Play Store**
- Conexión a internet

### Instalar un módulo

Copia el script a Termux y ejecútalo:

```bash
# Claude Code
bash install_claude.sh

# Ollama
bash install_ollama.sh
```

> Cada script verifica si el módulo ya está instalado antes de hacer cualquier cosa.
> Si falla a mitad, vuélvelo a ejecutar — tiene checkpoints automáticos.

### Instalación con curl (cuando el repo sea público)

```bash
# Claude Code
bash <(curl -fsSL https://raw.githubusercontent.com/TU_USUARIO/android-server/main/modules/install_claude.sh)

# Ollama
bash <(curl -fsSL https://raw.githubusercontent.com/TU_USUARIO/android-server/main/modules/install_ollama.sh)
```

---

## Módulo: Claude Code

Instala el agente de IA de Anthropic en Termux con el workaround necesario para ARM64.

```
✅ Verifica Node.js >= 18 (instala si falta)
✅ npm install -g @anthropic-ai/claude-code
✅ Alias funcional apuntando a cli.js (workaround ARM64)
✅ Registra estado en ~/.android_server_registry
```

**Comandos tras la instalación:**

```bash
claude                    # agente interactivo
claude --version          # ver versión
claude -p "instrucción"   # modo directo (no interactivo)
claude --continue         # continuar última sesión
claude-update             # actualizar a la última versión
```

> **Nota técnica:** Los binarios nativos de Claude Code son x86/x64 y no funcionan en ARM64.
> El workaround es llamar directamente a `cli.js` con Node.js — funciona 100%.
> Probado en POCO F5 · Android 15 · Node.js 25.x

---

## Módulo: Ollama

Instala Ollama para correr modelos de IA localmente sin internet ni costo por token.

```
✅ pkg install ollama (compilado para Termux ARM64)
✅ Script de inicio/parada con sesión tmux
✅ Aliases para uso diario
✅ Opción de descargar modelo inicial
✅ API REST compatible con OpenAI en :11434
```

**Modelos recomendados para Android (≥ 8GB RAM):**

| Modelo | Tamaño | Calidad | Recomendado para |
|--------|--------|---------|-----------------|
| `qwen:0.5b` | ~395 MB | Básica | Pruebas rápidas |
| `qwen:1.8b` | ~1.1 GB | Media | Uso general |
| `phi3:mini` | ~2.3 GB | Buena | Uso real |
| `llama3.2:1b` | ~1.3 GB | Media-alta | Balance |

> ⚠️ No usar modelos de 7B o más — crash garantizado en móvil.

**Comandos tras la instalación:**

```bash
ollama-start              # inicia servidor en tmux (:11434)
ollama-stop               # detiene el servidor
ollama-status             # verifica si responde
ollama-list               # modelos instalados
ollama run phi3:mini      # iniciar chat directo
ollama pull qwen:1.8b     # descargar modelo
ollama-lan                # exponer en red local
```

**API REST directa:**

```bash
# Listar modelos
curl http://localhost:11434/api/tags

# Chat
curl http://localhost:11434/api/chat \
  -d '{"model":"qwen:0.5b","messages":[{"role":"user","content":"hola"}],"stream":false}'
```

---

## Arquitectura

```
Android (sin root)
  └─ Termux (F-Droid)
       ├─ Node.js (nativo)
       │    ├─ Claude Code  → alias a cli.js
       │    └─ EAS CLI      → builds Expo en la nube
       ├─ Ollama (nativo)   → modelos IA · :11434
       ├─ tmux              → sesiones en background
       │
       └─ proot-distro + Debian Bookworm
            ├─ n8n          → workflows · :5678
            └─ cloudflared  → túnel público

Registry de estado: ~/.android_server_registry
```

### ¿Por qué proot para n8n?

n8n requiere Node.js con glibc (Linux estándar). Termux usa Bionic libc (Android). El proot-distro con Debian Bookworm provee el entorno Linux completo sin root.

Claude Code y Ollama corren en Termux nativo porque tienen soporte directo para ARM64/Bionic.

---

## Sistema de registro

Cada script escribe su estado en `~/.android_server_registry`:

```
claude_code.installed=true
claude_code.version=2.1.110
claude_code.install_date=2026-04-17
claude_code.commands=claude,claude -p,claude --continue,claude --version
claude_code.port=none

ollama.installed=true
ollama.version=0.11.x
ollama.install_date=2026-04-17
ollama.commands=ollama serve,ollama run,ollama list
ollama.port=11434
```

El futuro dashboard TUI (`menu.sh`) lee este archivo para mostrar el estado de cada módulo sin ejecutar checks en vivo.

---

## Dispositivos probados

| Dispositivo | Android | RAM | Estado |
|------------|---------|-----|--------|
| Xiaomi POCO F5 (Redmi Note 12 Turbo) | 15 (HyperOS 2.0) | 12 GB | ✅ Funcionando |
| Xiaomi Mi 11 Lite 5G NE | 13+ (EvolutionX) | 8 GB | 🔧 Pendiente probar |

> Si probaste en otro dispositivo y funcionó, abre un issue o PR con los datos.

---

## Problemas conocidos

| Problema | Causa | Estado |
|----------|-------|--------|
| Ollama respuestas lentas (>20s) | Regresión en versión actual pkg | ⏳ Pendiente fix oficial |
| Claude Code UI web no funciona | `node-pty` sin prebuild ARM64 | ❌ No viable sin NDK |
| Binario Ollama de GitHub Releases no funciona | Compilado con glibc, Termux usa Bionic | ✅ Documentado |

---

## Roadmap

```
Fase actual — Módulos independientes
  [✅] install_claude.sh
  [✅] install_ollama.sh
  [ ]  install_n8n.sh (migración del script v1)
  [ ]  install_expo.sh

Fase 2 — Script maestro
  [ ]  instalar.sh (entrada única: curl | bash)
  [ ]  Descarga módulos desde el repo automáticamente

Fase 3 — Dashboard TUI
  [ ]  menu.sh — panel de control en terminal
  [ ]  Se abre automáticamente al iniciar Termux
  [ ]  Muestra estado de cada módulo en tiempo real

Fase 4 — APK
  [ ]  Interfaz nativa Android para los scripts
```

---

## Contribuir

1. Clona el repo
2. Prueba el script en tu dispositivo
3. Abre un issue con: modelo de teléfono · versión Android · qué falló
4. O abre un PR con el fix

---

## Licencia

MIT — úsalo como quieras.

---

## Créditos

Este proyecto está siendo construido con ayuda de [Claude](https://claude.ai) de Anthropic — desde el diseño de la arquitectura hasta la escritura de los scripts. No es un secreto ni algo de lo que haya que disculparse: es simplemente cómo se desarrolla software hoy.

A medida que el proyecto crezca, Claude Code se usará directamente en el repo para escribir y modificar código. En ese punto aparecerá como contribuidor — lo cual es completamente justo.

---

<div align="center">

Hecho con Termux · ARM64 · sin root · sin excusas

</div>

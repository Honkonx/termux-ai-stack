# termux-ai-stack · Documento de Progreso
**Última actualización:** Domingo 19 Abril 2026 — Fase 7 completa  
**Repo:** https://github.com/Honkonx/termux-ai-stack  
**Dispositivo principal:** Xiaomi POCO F5 · Android 15 · HyperOS 2.0 · 12GB RAM · ARM64 · sin root

---

## ÍNDICE

1. [Estado actual del proyecto](#1-estado-actual)
2. [Arquitectura](#2-arquitectura)
3. [Versiones de scripts](#3-versiones)
4. [Estándar de scripts](#4-estándar)
5. [Decisiones técnicas clave](#5-decisiones-técnicas)
6. [Bugs encontrados y fixes aplicados](#6-bugs-y-fixes)
7. [Problemas pendientes](#7-pendientes)
8. [Roadmap](#8-roadmap)
9. [Comandos de referencia](#9-comandos)
10. [Dispositivos probados](#10-dispositivos)
11. [Versiones fijas críticas](#11-versiones-fijas)

---

## 1. ESTADO ACTUAL

```
✅ instalar.sh                  → v2.2.0 · PENDIENTE SUBIR AL REPO
🔧 Script/menu.sh               → v3.1.2 · PENDIENTE SUBIR AL REPO
✅ Script/backup.sh             → v2.2.0 · EN REPO ✓ · PROBADO ✓
🔧 Script/restore.sh            → v2.4.0 · PENDIENTE SUBIR AL REPO
🔧 Script/install_n8n.sh        → v2.5.0 · PENDIENTE SUBIR AL REPO ← ACTUALIZADO
🔧 Script/install_claude.sh     → v2.8.0 · PENDIENTE SUBIR AL REPO
✅ Script/install_ollama.sh     → v1.2.0 · EN REPO ✓
✅ Script/install_expo.sh       → v1.1.0 · EN REPO ✓
🔧 Script/install_python.sh     → v1.0.0 · NUEVO · PENDIENTE SUBIR AL REPO
🔧 Script/install_ssh.sh        → v1.0.2 · NUEVO · PENDIENTE SUBIR AL REPO
🔧 README.md                    → PENDIENTE reescribir
🔧 ARCHITECTURE.md              → PENDIENTE actualizar
```

**Estado de módulos — POCO F5:**

| Módulo | Versión | Script | Dónde corre | Estado |
|--------|---------|--------|-------------|--------|
| n8n | 2.8.4 | install_n8n.sh v2.5.0 | proot Debian | ✅ Funcionando · ✅ Webhook Telegram OK |
| cloudflared | 2026.3.0 | install_n8n.sh | proot Debian | ✅ Tunnel activo · bot.honkon.shop |
| Claude Code | 2.1.111 | install_claude.sh v2.8.0 | Termux nativo | ⚠️ Solo funciona desde GitHub Releases |
| Ollama | v0.21.0 | install_ollama.sh v1.2.0 | Termux nativo | ✅ Funciona · ⚠️ lento |
| EAS CLI | 18.7.0 | install_expo.sh v1.1.0 | Termux nativo | ✅ Funcionando |
| Python | 3.13.13 | install_python.sh v1.0.0 | Termux nativo | ✅ Funcionando · PROBADO ✓ |
| SQLite | 3.53.0 | (incluido en Python) | Termux nativo | ✅ Funcionando · PROBADO ✓ |
| SSH | OpenSSH_10.3 | install_ssh.sh v1.0.2 | Termux nativo | ✅ Funcionando · PROBADO ✓ |
| menu.sh | 3.1.2 | — | Termux nativo | ✅ Funcionando |
| backup.sh | 2.2.0 | — | Termux nativo | ✅ Funcionando · PROBADO ✓ |
| restore.sh | 2.4.0 | — | Termux nativo | ✅ Funcionando |

**Backup v1 — 18 Abril 2026 (subido a GitHub Releases):**

| Archivo | Tamaño |
|---------|--------|
| part1-termux-base | 120KB |
| part2-claude-code | 11.92KB |
| part3-eas-expo | 11.72MB |
| part4-ollama | 9.23MB |
| part5-n8n-data | 14.58MB |
| part6-proot-debian | 834.23MB |
| checksums.txt | 748B |
| **Total** | **~871MB** |

> ⚠️ Backup v1 no incluye Python ni SSH — se reinstalan en <2 min con `pkg install`.

---

## 2. ARQUITECTURA

```
Android (sin root) — POCO F5
  └─ Termux (F-Droid)
       ├─ ~/.bashrc → auto-ejecuta menu.sh al abrir Termux
       ├─ menu.sh v3.1.2 → dashboard TUI principal (6 módulos)
       ├─ ~/install_*.sh → scripts de módulo descargados localmente
       ├─ ~/restore.sh v2.4.0 → restaurar desde GitHub Releases o backup propio
       ├─ ~/backup.sh v2.2.0 → backup completo (1 archivo) o por módulo/partes
       ├─ ~/.env_n8n → variables de entorno n8n (WEBHOOK_URL etc.)
       ├─ ~/.android_server_registry → estado de todos los módulos (key=value)
       ├─ tmux
       │    ├─ sesión "n8n-server"
       │    └─ sesión "ollama-server"
       ├─ Node.js LTS v24 (Termux nativo)
       │    ├─ Claude Code v2.1.111 (via cli.js + wrapper /usr/bin/claude)
       │    └─ EAS CLI v18.7.0
       ├─ Python 3.13.13 (Termux nativo)
       │    ├─ pip 26.0.1
       │    └─ sqlite3 3.53.0 (incluido)
       ├─ OpenSSH 10.3 (Termux nativo · puerto 8022)
       │    └─ Acceso remoto desde PC via ssh -p 8022 usuario@IP
       └─ proot-distro + Debian Bookworm ARM64
            ├─ Node.js 20 LTS
            ├─ n8n 2.8.4 (con WEBHOOK_URL + N8N_PROTOCOL=https + N8N_PROXY_HOPS=1)
            └─ cloudflared (tunnel fijo → bot.honkon.shop)
```

**Estructura del repo:**
```
termux-ai-stack/
├── instalar.sh              ← script maestro v2.2.0
├── README.md
├── ARCHITECTURE.md
├── PROGRESO.md
├── MEJORAS_RECOMENDADAS.md
└── Script/
    ├── menu.sh              ← v3.1.2
    ├── backup.sh            ← v2.2.0
    ├── restore.sh           ← v2.4.0
    ├── install_n8n.sh       ← v2.5.0
    ├── install_claude.sh    ← v2.8.0
    ├── install_ollama.sh    ← v1.2.0
    ├── install_expo.sh      ← v1.1.0
    ├── install_python.sh    ← v1.0.0
    └── install_ssh.sh       ← v1.0.2
```

---

## 3. VERSIONES DE SCRIPTS

| Script | Versión | Cambios principales |
|--------|---------|---------------------|
| instalar.sh | 2.2.0 | Descarga 6 scripts · exec bash ~/menu.sh al finalizar |
| menu.sh | 3.1.2 | Módulo [5] Python + SQLite · Módulo [6] SSH · _get_ip() via ifconfig |
| backup.sh | 2.2.0 | Sin cambios |
| restore.sh | 2.4.0 | Sin cambios |
| install_n8n.sh | **2.5.0** | **Fix webhook: N8N_PROTOCOL=https en .bashrc proot + start_servidor.sh generado** |
| install_claude.sh | 2.8.0 | Sin cambios |
| install_ollama.sh | 1.2.0 | Sin cambios |
| install_expo.sh | 1.1.0 | Sin cambios |
| install_python.sh | 1.0.0 | pkg install python + sqlite · aliases · registry |
| install_ssh.sh | 1.0.2 | pkg install openssh · puerto 8022 · _get_ip() via ifconfig |

---

## 4. ESTÁNDAR DE SCRIPTS

### Variables de control
```bash
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_NOMBRE_checkpoint"
ANDROID_SERVER_READY=1
```

### Fix stdin (crítico en Termux)
```bash
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRMAR < /dev/tty
```

### Llamadas a subprocesos
```bash
bash "$HOME/install_X.sh" < /dev/tty
bash "$HOME/restore.sh" --module ollama < /dev/tty
```

### Comandos dentro del proot
```bash
proot-distro login debian -- comando arg1 arg2

proot-distro login debian -- bash << 'PROOT_INNER'
export HOME=/root
# comandos
PROOT_INNER
```

### Versioning
| Major (X) | Cambio de arquitectura, incompatibilidad hacia atrás |
| Minor (Y) | Feature nuevo, módulo nuevo |
| Patch (Z) | Bug fix, cambio cosmético |

---

## 5. DECISIONES TÉCNICAS CLAVE

| Decisión | Alternativa descartada | Razón |
|----------|----------------------|-------|
| n8n en proot Debian | n8n en Termux nativo | `isolated-vm` requiere glibc · Bionic incompatible |
| Node.js 20 en proot | Node 22/24 | Node 22/24 rompe `isolated-vm` de n8n |
| Claude Code v2.1.111 fijo | última versión | >2.1.111 usa binario nativo glibc incompatible con Bionic |
| Claude Code desde GitHub Releases | npm install | npm produce cli.js inválido en Termux ARM64 |
| cloudflared con token fijo | URL temporal trycloudflare | URL cambia en cada reinicio, Telegram webhook se rompe |
| N8N_PROTOCOL=https en arranque | solo WEBHOOK_URL | Sin https n8n construye URLs http:// internas aunque tenga WEBHOOK_URL |
| N8N_PROXY_HOPS=1 | sin variable | cloudflared actúa como proxy — sin esto n8n rechaza requests |
| ifconfig para detectar IP | ip route get 1 | ip route da Permission denied en Android con netlink restringido |
| Puerto SSH 8022 | 22 | Termux no puede usar puertos <1024 sin root |
| Open WebUI descartado | pip install open-webui | Requiere Python <3.13 — proot tiene 3.13.5, incompatible |

---

## 6. BUGS Y FIXES

| Bug | Causa | Fix |
|-----|-------|-----|
| Webhook Telegram: "An HTTPS URL must be provided" | N8N_PROTOCOL no se pasaba al proot | install_n8n.sh v2.5.0: N8N_PROTOCOL=https en .bashrc proot y start_servidor.sh ✅ |
| WEBHOOK_URL vacía en proot | start_servidor.sh no inyectaba la variable | Fix en generación del script — leer ~/.env_n8n correctamente ✅ |
| cloudflared tunnel DOWN en segundo dispositivo | Token de otro tunnel guardado en ~/.cf_token | Usar el token del tunnel `honkon` en todos los dispositivos ✅ |
| `vunknown` en Ollama | `ollama --version` no parseable en Termux | `pkg show ollama \| grep Version` ✅ |
| Claude no abre desde menú | cli.js era wrapper bash | Usar wrapper ejecutable directamente ✅ |
| Node v24 falsamente incompatible | install_claude.sh lo reemplazaba | Eliminada lógica de reemplazo ✅ |
| Fallo extracción n8n en proot | tar silenciado, directorios no existían | Sin 2>/dev/null + mkdir -p + fallback ✅ |
| backup.sh pisado por install_n8n.sh | install_n8n.sh creaba ~/backup.sh | Renombrado a ~/n8n_backup.sh ✅ |
| Prompts s/n no visibles | read -r -p no flushea en subprocesos | echo -n + read -r separados ✅ |
| ip route Permission denied | netlink restringido en Android | ifconfig con filtro máscara ✅ |

---

## 7. PROBLEMAS PENDIENTES

### Claude Code — error de terceros
- `npm install` produce cli.js inválido — workaround: instalar siempre desde GitHub Releases.
- Depende de que Anthropic publique versión compatible con Termux ARM64 Bionic.

### Ollama — rendimiento
- Respuestas lentas — regresión conocida en v0.11.5+ en Termux ARM64 (bug #27290 termux-packages). Pendiente fix oficial.

### Open WebUI — descartado temporalmente
- `pip install open-webui` falla: requiere Python <3.13, proot tiene 3.13.5.
- Retomar cuando open-webui publique soporte para Python 3.13+.

---

## 8. ROADMAP

```
✅ Fase 1 — Módulos independientes
✅ Fase 2 — Script maestro + Dashboard TUI v1
✅ Fase 3 — Reescritura integración v2 + backup
✅ Fase 3.5 — Fixes y pulido
✅ Fase 4 — Restore + Backup individual + menú integrado
✅ Fase 4.6 — Backup/Restore completo · PROBADO ✓
✅ Fase 5a — Fixes críticos Claude + n8n · PROBADO ✓
✅ Fase 5b — Mejoras UI, monitoring y fixes · PROBADO ✓
✅ Fase 6 — Módulos nuevos (Python, SSH) · PROBADO ✓
✅ Fase 7 — Fix webhook n8n · COMPLETADA · PROBADO ✓
     install_n8n.sh v2.5.0 → N8N_PROTOCOL=https fix
     Webhook Telegram → Ollama → respuesta funcionando
     Probado en 2 dispositivos (POCO F5 + Mi 11 Lite)
     Open WebUI → descartado (Python 3.13 incompatible)

📋 Fase 8 — App Android nativa
     Framework: React Native (EAS ya instalado)
     Comunicación con Termux: Termux:API (am broadcast RUN_COMMAND)
     Estado de módulos: leer ~/.android_server_registry
     UI objetivo: switches, versiones, botones submenú (como imagen referencia)

     Fase 8a — MVP HTML (validación rápida)
       Python http.server :8080 sirviendo index.html
       Lee registry → muestra switches en tiempo real
       Botones llaman scripts bash via fetch → validar concepto

     Fase 8b — App React Native base
       npx create-expo-app termux-stack-ui
       Pantalla principal con módulos (igual que menu.sh)
       Termux:API → ejecutar start/stop scripts
       Leer registry cada 5s → actualizar switches

     Fase 8c — Submenús y funciones
       Submenú n8n: start/stop/URL/logs
       Submenú Ollama: modelos, chat básico
       Submenú SSH: IP, conexión
       Terminal integrada (opcional)

     Fase 8d — Build y distribución
       EAS Build → APK
       GitHub Releases → descargar desde repo
```

---

## 9. COMANDOS DE REFERENCIA

```bash
# Instalación desde cero:
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/instalar.sh \
  -o instalar.sh && bash instalar.sh

# Menú:
menu

# n8n:
bash ~/start_servidor.sh    # inicia n8n + cloudflared
bash ~/stop_servidor.sh     # detiene todo
bash ~/ver_url.sh           # URL pública

# Configurar webhook (dominio fijo):
echo "N8N_WEBHOOK_URL=https://tu.ejemplo.com" >> ~/.env_n8n

# Python:
python3                     # REPL
pip install PAQUETE
sqlite3 archivo.db

# SSH:
bash ~/ssh_start.sh         # puerto 8022
ssh -p 8022 u0_a649@10.15.14.222   # desde PC

# Claude Code:
bash ~/restore.sh --module claude --source github
claude

# Ollama:
bash ~/ollama_start.sh
ollama list
ollama pull qwen2.5:0.5b

# Backup/Restore:
bash ~/backup.sh
bash ~/restore.sh --module all --source github
```

---

## 10. DISPOSITIVOS PROBADOS

| Dispositivo | Android | RAM | Estado |
|------------|---------|-----|--------|
| Xiaomi POCO F5 | 15 (HyperOS 2.0) | 12 GB | ✅ Todo funcionando · webhook Telegram OK |
| Xiaomi Mi 11 Lite 5G NE | 13+ (EvolutionX) | 8 GB | ✅ n8n + webhook funcionando · ip route restringido (fix ifconfig aplicado) |

---

## 11. VERSIONES FIJAS CRÍTICAS — NO CAMBIAR SIN PROBAR

| Componente | Valor fijo | Razón |
|-----------|-----------|-------|
| Claude Code | `@2.1.111` | >2.1.111 usa binario nativo glibc incompatible con Bionic |
| Claude Code — instalación | Desde GitHub Releases únicamente | npm install produce cli.js inválido en Termux ARM64 |
| Node.js Termux | `nodejs-lts` (v24 actual) | NO reemplazar — v24 es compatible con claude-code@2.1.111 |
| Node.js en proot | `20 LTS` | Node 22/24 rompe `isolated-vm` que usa n8n |
| Lanzamiento Claude | wrapper `/usr/bin/claude` o `node cli.js` | El binario nativo no corre en Bionic libc |
| Versión Ollama | `pkg show ollama \| grep Version` | `ollama --version` devuelve `vunknown` en Termux |
| n8n en proot | `WEBHOOK_URL` + `N8N_PROTOCOL=https` + `N8N_PROXY_HOPS=1` | Sin estas variables los webhooks no funcionan detrás de cloudflared |
| SSH — Puerto | `8022` | Termux no puede usar puertos <1024 sin root |
| Detección IP | `ifconfig` con filtro máscara | `ip route get 1` da Permission denied en Android con netlink restringido |
| CPU/Temperatura | No implementado | HyperOS bloquea `/proc/stat` sin root. Termux:API mata el menú |

---

## NOTAS PARA EL PRÓXIMO CHAT

### Estado al inicio de Fase 8
- Fase 7 completada ✓ — webhook n8n funcionando en 2 dispositivos
- `install_n8n.sh v2.5.0` generado — pendiente subir al repo
- Open WebUI descartado por incompatibilidad Python 3.13
- Fase 8 es la siguiente: App React Native

### Pendiente subir al repo
- `instalar.sh` → v2.2.0 (raíz del repo)
- `Script/menu.sh` → v3.1.2
- `Script/restore.sh` → v2.4.0
- `Script/install_n8n.sh` → **v2.5.0** ← NUEVO FIX WEBHOOK
- `Script/install_claude.sh` → v2.8.0
- `Script/install_python.sh` → v1.0.0 (NUEVO)
- `Script/install_ssh.sh` → v1.0.2 (NUEVO)

### Fase 8 — punto de entrada
- Framework: **React Native con Expo** (EAS ya instalado en el dispositivo)
- Primer paso: MVP HTML con Python http.server para validar concepto de UI
- Comunicación app→Termux: **Termux:API** (`am broadcast RUN_COMMAND`)
- Estado: leer `~/.android_server_registry` via HTTP o archivo directo
- UI objetivo: igual que imagen referencia Gemini — switches por módulo, versión, botón submenú

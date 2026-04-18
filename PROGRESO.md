# termux-ai-stack · Documento de Progreso
**Última actualización:** Sábado 18 Abril 2026 — sesión completa  
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
✅ instalar.sh              → v2.1.0 · EN REPO ✓
✅ Script/menu.sh           → v2.3.0 · EN REPO ✓
✅ Script/backup.sh         → v2.1.0 · EN REPO ✓ · PROBADO ✓
✅ Script/restore.sh        → v2.1.0 · EN REPO ✓ · PROBADO ✓
✅ Script/install_n8n.sh    → v2.2.0 · EN REPO ✓
✅ Script/install_claude.sh → v2.4.0 · EN REPO ✓
✅ Script/install_ollama.sh → v1.2.0 · EN REPO ✓
✅ Script/install_expo.sh   → v1.1.0 · EN REPO ✓
🔧 README.md                → desactualizado — pendiente reescribir (Fase 4 docs)
🔧 MEJORAS_RECOMENDADAS.md  → pendiente actualizar con meta app nativa
```

**Estado de módulos — TODOS FUNCIONANDO en POCO F5:**

| Módulo | Versión | Script | Dónde corre | Estado |
|--------|---------|--------|-------------|--------|
| n8n | 2.8.4 | install_n8n.sh v2.2.0 | proot Debian | ✅ Funcionando |
| cloudflared | 2026.3.0 | install_n8n.sh | proot Debian | ✅ Funcionando |
| Claude Code | 2.1.111 | install_claude.sh v2.4.0 | Termux nativo | ✅ Funcionando |
| Ollama | v0.21.0 | install_ollama.sh v1.2.0 | Termux nativo | ✅ Funciona · ⚠️ lento |
| EAS CLI | 18.7.0 | install_expo.sh v1.1.0 | Termux nativo | ✅ Funcionando |
| menu.sh | 2.3.0 | — | Termux nativo | ✅ Funcionando |
| backup.sh | 2.1.0 | — | Termux nativo | ✅ Funcionando |
| restore.sh | 2.1.0 | — | Termux nativo | ✅ Funcionando |

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

---

## 2. ARQUITECTURA

```
Android (sin root) — POCO F5
  └─ Termux (F-Droid)
       ├─ ~/.bashrc → auto-ejecuta menu.sh al abrir Termux
       ├─ menu.sh v2.3.0 → dashboard TUI principal
       ├─ ~/install_*.sh → scripts de módulo descargados localmente
       ├─ ~/restore.sh v2.1.0 → restaurar desde GitHub Releases o backup propio
       ├─ ~/backup.sh v2.1.0 → backup completo o por módulo
       ├─ tmux
       │    ├─ sesión "n8n-server"
       │    └─ sesión "ollama-server"
       ├─ Node.js LTS v24 (Termux nativo)
       │    ├─ Claude Code v2.1.111
       │    └─ EAS CLI v18.7.0
       └─ proot-distro + Debian Bookworm ARM64
            ├─ Node.js 20 LTS
            ├─ n8n 2.8.4
            └─ cloudflared

~/.android_server_registry  → estado de todos los módulos (key=value)
```

**Estructura del repo:**
```
termux-ai-stack/
├── instalar.sh              ← script maestro v2.1.0
├── README.md
├── ARCHITECTURE.md          ← nuevo (documentación técnica)
├── MEJORAS_RECOMENDADAS.md
└── Script/
    ├── menu.sh              ← v2.3.0
    ├── backup.sh            ← v2.1.0
    ├── restore.sh           ← v2.1.0
    ├── install_n8n.sh       ← v2.2.0
    ├── install_claude.sh    ← v2.4.0
    ├── install_ollama.sh    ← v1.2.0
    └── install_expo.sh      ← v1.1.0
```

**Navegación del menú v2.3.0:**
```
[1] n8n           → submenú (iniciar/detener/url/logs/consola)
[2] Claude Code   → lanza claude directamente
[3] Ollama        → submenú (servidor/chat/modelos/descargar)
[4] Expo / EAS    → submenú (build/status/login)
──────────────────────────────────────────
[0] Backup / Restore → submenú dedicado

[r] refrescar  [h] ayuda  [u] actualizar  [s] shell
```

**Flujo backup/restore:**
```
backup.sh --module X   → genera solo la parte del módulo X
backup.sh              → genera las 6 partes + checksums.txt

restore.sh --module X --source github  → descarga de GitHub Releases directo
restore.sh --module X                  → pregunta fuente (github / backup propio)
restore.sh                             → menú interactivo completo
```

---

## 3. VERSIONES DE SCRIPTS

| Script | Versión | Cambios principales |
|--------|---------|---------------------|
| instalar.sh | 2.1.0 | Descarga 6 scripts (+ backup.sh + restore.sh) en PASO 5 |
| menu.sh | 2.3.0 | `[0]` Backup/Restore, mini-menú limpio/GitHub al instalar, `[u]` incluye backup+restore |
| backup.sh | 2.1.0 | `--module X` para backup individual de cualquier módulo |
| restore.sh | 2.1.0 | `--module X`, `--source github\|local`, verifica SHA256, restaura cada parte |
| install_n8n.sh | 2.2.0 | Fix prompts s/n (4 prompts) |
| install_claude.sh | 2.4.0 | Fix prompts s/n (2 prompts) |
| install_ollama.sh | 1.2.0 | Fix prompts s/n + fix versión pkg |
| install_expo.sh | 1.1.0 | Fix prompts s/n (5 prompts) |

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
# Prompts visibles en subprocesos Termux:
echo -n "  ¿Continuar? (s/n): "
read -r CONFIRMAR
# NO usar: read -r -p "texto" VAR  ← no flushea en subprocesos Termux
```

### Registry (formato key=value)
```
MODULO.installed=true
MODULO.version=X.X.X
MODULO.install_date=YYYY-MM-DD
MODULO.port=XXXX
MODULO.location=termux_native | proot_debian
MODULO.source=install | restore   ← nuevo campo agregado en restore.sh
```

### Llamadas entre scripts
```bash
# Siempre redirigir stdin desde /dev/tty para que los prompts funcionen
bash "$HOME/script.sh" < /dev/tty

# Lanzar dentro de proot
proot-distro login "$DISTRO_NAME" -- bash << 'INNER'
  # comandos dentro del proot
INNER
```

---

## 5. DECISIONES TÉCNICAS CLAVE

| Decisión | Razón |
|----------|-------|
| proot-distro + Debian Bookworm para n8n | Glibc real → node-gyp compila; sin root |
| Node.js 20 LTS en proot para n8n | Node 22/24 rompe `isolated-vm` |
| cloudflared dentro del proot | DNS `[::1]:53` rechaza UDP en Termux nativo |
| `nodejs-lts` (v24) NO `nodejs` (v25+) | Node v25+ rompe instalación Claude Code |
| Claude Code @2.1.111 fijo | >2.1.111 usa binario nativo glibc incompatible Bionic |
| `node cli.js` directo para Claude | Binario nativo no corre en Bionic libc |
| `pkg show ollama` para versión | `ollama --version` devuelve `vunknown` en Termux |
| Scripts en `~/` descargados localmente | menu.sh sin dependencia de red para instalar |
| `echo -n` + `read -r` | `read -r -p` no flushea buffer en subprocesos Termux |
| `[0]` para Backup/Restore en menú | Convención "opciones del sistema" — no se desplaza al agregar módulos 5, 6, etc. |
| `--source github` en restore completo | Restore completo siempre desde GitHub — sin preguntar fuente |
| SHA256 verificado en restore | Descarga checksums.txt del mismo release para integridad |
| Glob `part4-ollama-*.tar.xz` en restore local | No depende del timestamp exacto del backup |

---

## 6. BUGS ENCONTRADOS Y FIXES APLICADOS

### Sesión 18 Abril 2026 — Fase 4

| Bug | Causa raíz | Fix |
|-----|-----------|-----|
| `[b] backup` persistía en footer tras actualizar | `[u]` descargaba versión vieja del repo mientras se subía la nueva | Subir archivos al repo ANTES de presionar `[u]` ✅ |
| `→ submenú` visible en `[0] Backup/Restore` | Texto copiado de módulos normales | Eliminado — backup no tiene estado propio ✅ |
| Opción `[2] Desde mi backup` aparecía en restore completo | `select_source()` se llamaba siempre | `--source github` en llamada desde menú → salta select_source ✅ |

### Sesión 18 Abril 2026 — Fase 3.5

| Bug | Causa raíz | Fix |
|-----|-----------|-----|
| Prompts s/n no visibles en install_*.sh | `read -r -p` no flushea en subprocesos Termux | `echo -n` + `read -r` en 14 prompts ✅ |
| `vunknown` en Ollama | `ollama --version` no parseable | `pkg show ollama \| grep Version` ✅ |
| `\033[0m` visible en submenú Ollama | `echo` sin `-e` | `echo -e` en línea del `╚` ✅ |
| Chat Ollama requería escribir nombre manualmente | Sin lista dinámica | `mapfile` + `ollama list` ✅ |

### Sesión 18 Abril 2026 — Fase 3

| Bug | Causa raíz | Fix |
|-----|-----------|-----|
| `curl \| bash` no muestra prompts | `exec < /dev/tty` cierra el pipe | `curl -o instalar.sh && bash instalar.sh` ✅ |
| Aliases no funcionan en subprocesos | `.bashrc` no se hereda en bash no-interactivo | Scripts directos `bash ~/script.sh` ✅ |

---

## 7. PROBLEMAS PENDIENTES

### Media prioridad
- **Bug: Claude "no instalado" hasta refrescar** — `continue` no resuelve completamente. El registry se escribe en el script hijo pero el menú padre lo re-lee en la siguiente iteración del loop. Investigar si hay race condition.
- **Bug: "Deteniendo n8n" múltiples veces** — variable `state` no se actualiza localmente tras llamar `stop_servidor.sh`. Fix: leer estado de tmux directamente tras el stop.
- **Texto cortado en lista descarga Ollama** — descripciones muy largas para ancho de pantalla de teléfono.

### Baja prioridad
- `vunknown` Ollama — corregido en menu.sh, pendiente verificar en instalación limpia nueva.
- README.md desactualizado — documentación pendiente (Fase 4 docs).

---

## 8. ROADMAP

```
✅ Fase 1 — Módulos independientes
     install_n8n.sh · install_claude.sh · install_ollama.sh · install_expo.sh

✅ Fase 2 — Script maestro + Dashboard v1
     instalar.sh → curl | bash → instala todo
     menu.sh v1 → dashboard TUI básico

✅ Fase 3 — Reescritura integración v2
     menu.sh v2 → submenús por módulo, registry, estado real
     backup.sh → 6 partes + checksums + GitHub Releases

✅ Fase 3.5 — Fixes y pulido
     Fix prompts s/n (14 prompts en 4 scripts)
     Fix vunknown Ollama
     Submenú Ollama completo (chat dinámico, descarga por letras)
     Opción [u] actualizar scripts desde GitHub

✅ Fase 4 — Restore + Backup individual + menú integrado
     restore.sh v2.1.0 → --module X + --source github|local + SHA256
     backup.sh v2.1.0 → --module X para backup individual
     menu.sh v2.3.0 → [0] Backup/Restore + limpio/GitHub al instalar
     instalar.sh → descarga backup.sh + restore.sh en setup inicial

📋 Fase 5 — Mejoras UI y monitoring
     Monitoreo RAM/CPU/temp en header del menú
     URL n8n activa en pantalla principal
     Modelo Ollama activo en pantalla principal
     Fix texto cortado lista descarga Ollama
     Fix bug "Claude no instalado hasta refrescar"
     Fix bug "Deteniendo n8n múltiples veces"

📋 Fase 6 — Módulos nuevos
     Python + cliente Ollama (install_python.sh)
     Open WebUI para Ollama (install_open_webui.sh)
     SSH access desde PC (install_ssh.sh)
     SQLite visible desde menú (install_sqlite.sh)
     Notificaciones termux-api

📋 Fase 7 — Documentación técnica completa
     README.md reescrito con arquitectura v2
     ARCHITECTURE.md — decisiones, flujos, componentes
     MEJORAS_RECOMENDADAS.md actualizado

📋 Fase 8 — App nativa Android
     MVP: dashboard web (Python http.server + HTML/JS leyendo registry)
     App React Native con switches para controlar módulos
     Terminal integrada para Claude Code (Termux:API o WebSocket)
     Selector de modelo Ollama desde UI
     Target: reemplazar el TUI bash con interfaz nativa Android
```

---

## 9. COMANDOS DE REFERENCIA

```bash
# Instalación desde cero:
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/instalar.sh \
  -o instalar.sh && bash instalar.sh

# Menú:
menu   # alias → bash ~/menu.sh

# Actualizar todos los scripts desde GitHub:
# Presionar [u] en el menú principal

# n8n:
bash ~/start_servidor.sh    # inicia n8n + cloudflared
bash ~/stop_servidor.sh     # detiene todo
bash ~/ver_url.sh           # URL pública

# Claude Code:
node $(npm root -g)/@anthropic-ai/claude-code/cli.js

# Ollama:
bash ~/ollama_start.sh      # inicia en tmux :11434
ollama list                 # modelos instalados
ollama pull qwen2.5:0.5b    # descargar modelo

# Backup:
bash ~/backup.sh                    # backup completo → /sdcard/Download/termux-ai-stack-releases/
bash ~/backup.sh --module ollama    # solo Ollama

# Restore:
bash ~/restore.sh                              # menú interactivo
bash ~/restore.sh --module ollama              # módulo específico (pregunta fuente)
bash ~/restore.sh --module all --source github # todo desde GitHub directo
bash ~/restore.sh --module n8n --source local  # desde backup propio
```

---

## 10. DISPOSITIVOS PROBADOS

| Dispositivo | Android | RAM | Estado |
|------------|---------|-----|--------|
| Xiaomi POCO F5 | 15 (HyperOS 2.0) | 12 GB | ✅ Todo funcionando |
| Xiaomi Mi 11 Lite 5G NE | 13+ (EvolutionX) | 8 GB | 🔧 Pendiente — tiene KernelSU |

---

## 11. VERSIONES FIJAS CRÍTICAS — NO CAMBIAR SIN PROBAR

| Componente | Valor fijo | Razón |
|-----------|-----------|-------|
| Claude Code | `@2.1.111` | >2.1.111 usa binario nativo glibc incompatible con Bionic |
| Node.js Termux | `nodejs-lts` (v24) | `nodejs` (v25+) rompe instalación Claude Code |
| Node.js en proot | `20 LTS` | Node 22/24 rompe `isolated-vm` que usa n8n |
| Lanzamiento Claude | `node $(npm root -g)/@anthropic-ai/claude-code/cli.js` | El binario nativo no corre en Bionic libc |
| Versión Ollama | `pkg show ollama \| grep Version` | `ollama --version` devuelve `vunknown` en Termux |

---

## NOTAS PARA EL PRÓXIMO CHAT

### Estado al inicio de la próxima sesión
- Fase 4 completada ✓ — todos los scripts subidos al repo
- Backup v1 en GitHub Releases ✓ — probado restore desde GitHub ✓
- Documentación técnica pendiente (README, ARCHITECTURE, MEJORAS actualizado)

### Próximas tareas en orden
1. **Fase 5** — Fixes pendientes: bug Claude, bug n8n stop, texto cortado Ollama
2. **Fase 5** — Monitoreo RAM/CPU en header del menú
3. **Fase 6** — Primer módulo nuevo a decidir: Python o SSH (bajo esfuerzo, alto impacto)
4. **Fase 8 MVP** — Dashboard web como puente hacia la app nativa

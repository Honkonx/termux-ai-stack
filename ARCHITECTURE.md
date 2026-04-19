# termux-ai-stack · Arquitectura Técnica
**Versión del documento:** 3.0  
**Última actualización:** Abril 2026 — Fase 7 completa  
**Estado:** Activo — se actualiza con cada fase del proyecto

---

## ÍNDICE

1. [Visión general](#1-visión-general)
2. [Restricciones de plataforma](#2-restricciones-de-plataforma)
3. [Decisiones de arquitectura](#3-decisiones-de-arquitectura)
4. [Componentes del sistema](#4-componentes-del-sistema)
5. [Flujos de datos](#5-flujos-de-datos)
6. [Sistema de scripts](#6-sistema-de-scripts)
7. [Sistema de backup y restore](#7-sistema-de-backup-y-restore)
8. [Registry de estado](#8-registry-de-estado)
9. [Estándar de desarrollo](#9-estándar-de-desarrollo)
10. [Limitaciones conocidas](#10-limitaciones-conocidas)
11. [Evolución futura](#11-evolución-futura)

---

## 1. VISIÓN GENERAL

termux-ai-stack es un sistema de scripts bash que convierte un dispositivo Android ARM64 en un servidor de desarrollo con múltiples servicios de IA, sin root y sin modificar el sistema operativo.

**Objetivo principal:** instalar, gestionar y escalar servicios de IA y automatización en móvil con un solo comando.

```
curl -fsSL .../instalar.sh | bash
```

---

## 2. RESTRICCIONES DE PLATAFORMA

| Restricción | Causa | Impacto |
|-------------|-------|---------|
| Sin root | Decisión de diseño | Sin puertos <1024, sin acceso a /proc/stat |
| Bionic libc | Android no usa glibc | Binarios compilados para glibc no funcionan |
| ARM64 únicamente | Hardware del dispositivo | Wheels Python y binarios deben ser ARM64 |
| netlink restringido | HyperOS/MIUI | `ip route get 1` da Permission denied → usar ifconfig |
| /proc/stat bloqueado | HyperOS | No se puede leer temperatura CPU ni uso CPU sin root |
| Termux:API mata procesos | Bug conocido | No se usa para temperatura en el header del menú |

---

## 3. DECISIONES DE ARQUITECTURA

### 3.1 n8n en proot Debian (no en Termux nativo)

n8n depende de `isolated-vm` que requiere glibc. En Termux nativo (Bionic libc) no compila. Solución: proot-distro con Debian Bookworm donde sí hay glibc.

**Node.js en proot fijado en v20 LTS** — Node 22/24 rompe `isolated-vm`.

### 3.2 Claude Code desde GitHub Releases

`npm install -g @anthropic-ai/claude-code` produce un `cli.js` inválido en Termux ARM64 (binario nativo que requiere glibc). El tarball de GitHub Releases incluye el `cli.js` correcto como JavaScript puro.

**Versión fija: @2.1.111** — versiones superiores usan binario nativo incompatible con Bionic.

### 3.3 Webhook n8n con cloudflared

Para que Telegram pueda enviar mensajes a n8n se requieren 3 variables en el arranque del proceso dentro del proot:

```bash
export WEBHOOK_URL=https://tu-dominio.com   # URL pública conocida por n8n
export N8N_PROTOCOL=https                   # sin esto n8n construye URLs http://
export N8N_PROXY_HOPS=1                     # cloudflared actúa como proxy reverso
```

Sin `N8N_PROTOCOL=https`, aunque `WEBHOOK_URL` sea correcto, n8n genera internamente URLs `http://0.0.0.0:5678/...` que Telegram rechaza con "An HTTPS URL must be provided".

### 3.4 Token cloudflared por tunnel

El token de cloudflared es específico por tunnel. Si se usa el mismo dominio (`tu.ejemplo`) en múltiples dispositivos, todos deben usar el **mismo token** del tunnel `tu.ejemplo`. Un token de otro tunnel produce `Unauthorized: Tunnel not found`.

### 3.5 Detección de IP

`ip route get 1` da Permission denied en Android con netlink restringido (HyperOS, algunos ROMs). Se usa `ifconfig` con filtro de máscara de red como alternativa robusta.

### 3.6 Open WebUI descartado

`pip install open-webui` requiere Python <3.13. El proot Debian tiene Python 3.13.5 (instalado por defecto en Debian Bookworm actualizado). Incompatible hasta que open-webui publique soporte para Python 3.13+.

---

## 4. COMPONENTES DEL SISTEMA

```
Android (sin root) — ARM64
│
└─ Termux
     ├─ menu.sh v3.1.2 ────────────── Dashboard TUI principal
     ├─ instalar.sh v2.2.0 ─────────── Instalador maestro
     ├─ backup.sh v2.2.0 ───────────── Backup completo/modular
     ├─ restore.sh v2.4.0 ──────────── Restore GitHub/local
     │
     ├─ [Módulo 1] n8n ─────────────── proot Debian :5678
     │    ├─ install_n8n.sh v2.5.0
     │    ├─ cloudflared (tunnel fijo)
     │    └─ start_servidor.sh (generado)
     │
     ├─ [Módulo 2] Claude Code ──────── Termux nativo
     │    ├─ install_claude.sh v2.8.0
     │    ├─ cli.js (GitHub Releases @2.1.111)
     │    └─ wrapper /usr/bin/claude
     │
     ├─ [Módulo 3] Ollama ───────────── Termux nativo :11434
     │    └─ install_ollama.sh v1.2.0
     │
     ├─ [Módulo 4] Expo / EAS ──────── Termux nativo
     │    └─ install_expo.sh v1.1.0
     │
     ├─ [Módulo 5] Python + SQLite ──── Termux nativo
     │    └─ install_python.sh v1.0.0
     │
     └─ [Módulo 6] SSH ──────────────── Termux nativo :8022
          └─ install_ssh.sh v1.0.2
```

---

## 5. FLUJOS DE DATOS

### 5.1 Instalación desde cero

```
curl -o instalar.sh && bash instalar.sh
  │
  ├─ PASO 0: termux-setup-storage
  ├─ PASO 1: pkg update + dependencias base
  ├─ PASO 2-3: tema + extra-keys
  ├─ PASO 4: ~/menu.sh
  ├─ PASO 5: ~/install_*.sh + backup/restore
  ├─ PASO 6: ~/.bashrc
  └─ PASO 7: selección módulos → bash ~/install_X.sh
  └─ exec bash ~/menu.sh  (sin cerrar Termux)
```

### 5.2 Acceso remoto via SSH

```
PC (PowerShell/Terminal)
  │
  ssh -p 8022 usuario@192.168.x.x
  │
  OpenSSH :8022 (Termux nativo)
  │
  Shell Termux del teléfono
  │
  ├─ menu  → dashboard TUI completo desde PC
  ├─ claude → Claude Code con teclado físico
  └─ cualquier comando del stack
```

### 5.3 Flujo n8n con webhook Telegram

```
Telegram API
  │
  HTTPS POST → tu.ejemplo.com (Cloudflare DNS)
  │
  cloudflared tunnel (proot Debian)
  │
  localhost:5678 con cabecera X-Forwarded-For
  │
  n8n 2.8.4 (proot Debian)
  ├─ WEBHOOK_URL=https://tu.ejemplo.com
  ├─ N8N_PROTOCOL=https
  └─ N8N_PROXY_HOPS=1
  │
  Workflow → Ollama API (localhost:11434) → respuesta → Telegram
```

### 5.4 Generación de start_servidor.sh

```
bash install_n8n.sh
  │
  PASO 5 — Crear scripts de control
  │
  cat > ~/start_servidor.sh << SCRIPT
    ├─ Lee N8N_WEBHOOK_URL desde ~/.env_n8n
    ├─ Arranca tmux sesión "n8n-server"
    ├─ Inyecta: WEBHOOK_URL, N8N_PROTOCOL=https, N8N_PROXY_HOPS=1
    ├─ Lanza n8n en proot Debian
    ├─ Espera 35s
    ├─ Arranca cloudflared con token o URL temporal
    └─ Muestra resumen con IP y URL pública
```

---

## 6. SISTEMA DE SCRIPTS

### 6.1 Convenciones

- Todos los scripts tienen cabecera con versión y descripción
- Checkpoints en `~/.install_NOMBRE_checkpoint` — permiten reintentar sin repetir pasos
- Registry en `~/.android_server_registry` — estado de todos los módulos en key=value
- Colores: GREEN=OK, YELLOW=AVISO, RED=ERROR, CYAN=INFO
- Prompts: siempre `echo -n` + `read -r < /dev/tty` (fix Termux stdin)

### 6.2 Versioning

```
MAJOR.MINOR.PATCH
  │     │     └── Bug fix, cambio cosmético
  │     └──────── Feature nuevo, módulo nuevo
  └────────────── Cambio arquitectural, incompatibilidad hacia atrás
```

### 6.3 Registry format

```bash
# ~/.android_server_registry
n8n.installed=true
n8n.version=2.8.4
n8n.install_date=2026-04-19
n8n.port=5678
n8n.location=proot_debian
ssh.installed=true
ssh.port=8022
python.installed=true
python.version=3.13.13
```

---

## 7. SISTEMA DE BACKUP Y RESTORE

### 7.1 Partes del backup completo

| Parte | Contenido | Tamaño aprox. |
|-------|-----------|---------------|
| part1-termux-base | ~/.bashrc, scripts de control, registry | ~120KB |
| part2-claude-code | cli.js + wrapper | ~12KB |
| part3-eas-expo | EAS CLI global | ~12MB |
| part4-ollama | modelos descargados | variable |
| part5-n8n-data | ~/.n8n/ (workflows, credenciales, DB) | ~15MB |
| part6-proot-debian | rootfs completo con n8n + cloudflared | ~834MB |
| checksums.txt | SHA256 de todas las partes | ~1KB |

### 7.2 Fuentes de restore

- **GitHub Releases** — backup subido manualmente al repo
- **Local** — archivo en /sdcard/Download

### 7.3 Módulos restaurables individualmente

```bash
bash ~/restore.sh --module proot    # solo rootfs Debian
bash ~/restore.sh --module n8n      # solo datos n8n
bash ~/restore.sh --module claude   # solo Claude Code
bash ~/restore.sh --module ollama   # solo modelos
```

---

## 8. REGISTRY DE ESTADO

El archivo `~/.android_server_registry` es la fuente de verdad del estado del stack. Todos los scripts de instalación lo escriben. menu.sh lo lee para mostrar versiones y estado.

**Formato:** `clave=valor` sin espacios, una por línea.

**Uso desde la futura app Android:**
```
App React Native
  └─ HTTP GET http://localhost:8080/registry
       └─ Python http.server lee ~/.android_server_registry
            └─ devuelve JSON con estado de todos los módulos
```

---

## 9. ESTÁNDAR DE DESARROLLO

### 9.1 Fix stdin en Termux

```bash
# CORRECTO
echo -n "  ¿Continuar? (s/n): "
read -r VAR < /dev/tty

# INCORRECTO — no usar
read -r -p "  ¿Continuar? (s/n): " VAR
```

### 9.2 Llamadas a subprocesos con prompts

```bash
bash "$HOME/install_X.sh" < /dev/tty
bash "$HOME/restore.sh" --module ollama < /dev/tty
```

### 9.3 Comandos dentro del proot

```bash
proot-distro login debian -- comando arg1 arg2

proot-distro login debian -- bash << 'PROOT_INNER'
export HOME=/root
# comandos
PROOT_INNER
```

### 9.4 Variables de entorno n8n en proot

```bash
# SIEMPRE incluir las 3 variables al arrancar n8n:
export HOME=/root
export N8N_HOST=0.0.0.0
export N8N_PORT=5678
export N8N_PROXY_HOPS=1
export N8N_PROTOCOL=https        # ← crítico para webhooks
export WEBHOOK_URL=${URL_CFG}    # ← URL pública del tunnel
n8n start
```

---

## 10. LIMITACIONES CONOCIDAS

### 10.1 Rendimiento de Ollama

Los modelos corren en CPU. GPU no accesible desde Termux sin drivers específicos.

| Modelo | Tokens/seg aprox. | RAM requerida |
|--------|-------------------|---------------|
| qwen2.5:0.5b | ~8-12 t/s | ~600MB |
| qwen:1.8b | ~4-6 t/s | ~1.1GB |
| phi3:mini | ~2-3 t/s | ~2.3GB |

Regresión conocida en versiones Ollama >0.11.4 en Termux ARM64 (bug #27290). Pendiente fix oficial.

### 10.2 Open WebUI

`pip install open-webui` requiere Python <3.13. El proot Debian tiene 3.13.5. No instalable hasta que open-webui soporte Python 3.13+.

### 10.3 Claude Code UI web

`claude --web` requiere `node-pty` que necesita compilar código nativo. No tiene prebuilds para ARM64/Bionic. Usar Claude Code exclusivamente desde terminal.

### 10.4 Monitoreo CPU/temperatura

HyperOS bloquea `/proc/stat` sin root. Termux:API puede leer temperatura pero al ejecutarse mata el proceso del menú. No implementado.

### 10.5 SSH — solo red local

SSH en puerto 8022 funciona dentro de la misma red WiFi. Para acceso desde internet se requiere túnel adicional. No implementado en el stack actual.

### 10.6 Límite de RAM

| Módulo | RAM idle |
|--------|---------|
| n8n | ~200-400MB |
| Ollama + qwen2.5:0.5b | ~600-900MB |
| Claude Code | 0 (no background) |
| SSH | ~5MB |

En dispositivos de 6GB o menos, n8n + Ollama simultáneo puede provocar que Android mate procesos.

---

## 11. EVOLUCIÓN FUTURA

### 11.1 Fase 8 — App Android nativa

Reemplazar el TUI bash con app Android nativa. El stack bash sigue siendo el motor — la app es una capa de control visual.

**Framework elegido: React Native con Expo**
- EAS CLI ya instalado en el dispositivo
- No requiere libXlorie ni X11
- Build nativo sin dependencias externas complejas

**Comunicación app → Termux:**
```bash
# Termux:API — ejecutar scripts desde la app
am broadcast \
  --user 0 \
  -a com.termux.app.RUN_COMMAND \
  -n com.termux/.app.RunCommandService \
  --es com.termux.app.RUN_COMMAND_PATH '/data/data/com.termux/files/usr/bin/bash' \
  --esa com.termux.app.RUN_COMMAND_ARGUMENTS '-c,bash ~/start_servidor.sh' \
  --ez com.termux.app.RUN_COMMAND_BACKGROUND true
```

**Lectura de estado:**
```
App → HTTP GET localhost:8080/registry
   → Python http.server lee ~/.android_server_registry
   → devuelve JSON con módulos, versiones, estado
```

**Ruta de desarrollo:**
```
Fase 8a → MVP HTML (Python http.server + HTML/JS)
           Valida UI y comunicación sin escribir código nativo

Fase 8b → App React Native base
           npx create-expo-app
           Pantalla principal con switches por módulo

Fase 8c → Submenús y funciones
           n8n, Ollama, SSH, logs

Fase 8d → EAS Build → APK → GitHub Releases
```

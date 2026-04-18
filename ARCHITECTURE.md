# termux-ai-stack · Arquitectura Técnica
**Versión del documento:** 1.0  
**Última actualización:** Abril 2026  
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

### Principios de diseño

| Principio | Implementación |
|-----------|---------------|
| Sin root | proot-distro para aislamiento Linux; Termux para el resto |
| Idempotente | Checkpoints en cada script — re-ejecutable sin daño |
| Sin dependencia de red en operación | Scripts descargados a `~/` en setup; menú no requiere internet |
| Estado persistente | Registry `~/.android_server_registry` como fuente de verdad |
| Recuperable | Backup/restore completo desde GitHub Releases con SHA256 |
| Un módulo a la vez | Cada servicio es independiente — instala, para, restaura por separado |

### Stack completo en un dispositivo

```
┌─────────────────────────────────────────────────────────┐
│                    Android (ARM64)                       │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │                    Termux                         │   │
│  │                                                   │   │
│  │  menu.sh ──── dashboard TUI principal             │   │
│  │                                                   │   │
│  │  Node.js v24 ─┬─ Claude Code v2.1.111            │   │
│  │               └─ EAS CLI v18.7.0                  │   │
│  │                                                   │   │
│  │  Ollama ──────── servidor :11434                  │   │
│  │                                                   │   │
│  │  tmux ────────┬─ sesión "n8n-server"              │   │
│  │               └─ sesión "ollama-server"           │   │
│  │                                                   │   │
│  │  ┌──────────────────────────────────────────┐    │   │
│  │  │     proot-distro · Debian Bookworm       │    │   │
│  │  │                                          │    │   │
│  │  │  Node.js 20 LTS                          │    │   │
│  │  │  n8n 2.8.4 ──────── :5678               │    │   │
│  │  │  cloudflared ─────── túnel público       │    │   │
│  │  └──────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ~/.android_server_registry  (estado de módulos)         │
│  /sdcard/Download/termux-ai-stack-releases/  (backups)   │
└─────────────────────────────────────────────────────────┘
```

---

## 2. RESTRICCIONES DE PLATAFORMA

Entender estas restricciones es fundamental. Cada decisión de arquitectura existe para trabajar dentro de ellas.

### 2.1 Bionic libc vs glibc

Android usa **Bionic libc**, no la glibc estándar de Linux. La mayoría del software Linux compilado para x86/x64 con glibc no corre en Termux directamente.

**Impacto directo:**

| Componente | Problema | Solución |
|-----------|----------|----------|
| n8n | `node-gyp` requiere glibc para compilar módulos nativos | proot-distro + Debian (glibc real) |
| Claude Code | Binario empaquetado usa glibc, no Bionic | Invocar `cli.js` directamente con Node.js |
| cloudflared | DNS UDP bloqueado en Termux nativo | Correr dentro del proot |

### 2.2 Sin root

Termux corre en el espacio de usuario de Android sin privilegios de sistema. No se puede:
- Escuchar en puertos < 1024
- Modificar `/system`, `/proc` ni `/dev`
- Usar `systemd` ni `init`
- Montar sistemas de archivos arbitrarios

**Solución para Linux completo:** `proot-distro` emula un entorno Linux completo a nivel de usuario usando `proot` (un tracer de llamadas al sistema), sin necesidad de root real.

### 2.3 ARM64 (AArch64)

El dispositivo objetivo es ARM64. Binarios x86/x64 no se ejecutan nativamente. Esto afecta:
- Paquetes npm con binarios nativos precompilados para x86
- Herramientas con soporte ARM64 limitado o en beta
- Versiones de Node.js con cambios de ABI entre versiones

### 2.4 Gestión de procesos sin systemd

Termux no tiene init ni systemd. Los servicios en background se manejan con **tmux**:
- Cada servicio vive en una sesión tmux nombrada
- El proceso sobrevive al cierre de la terminal
- Se puede adjuntar (`tmux attach`) para ver logs en vivo
- Se detecta el estado con `tmux has-session -t nombre`

### 2.5 stdin en subprocesos

`read -r -p "texto" VAR` no flushea el buffer en subprocesos de Termux. El prompt no aparece en pantalla aunque el programa esté esperando input.

**Fix obligatorio en todos los scripts:**
```bash
# CORRECTO
echo -n "  ¿Continuar? (s/n): "
read -r VAR

# INCORRECTO — no usar
read -r -p "  ¿Continuar? (s/n): " VAR
```

---

## 3. DECISIONES DE ARQUITECTURA

Cada decisión aquí documentada fue tomada por una razón técnica específica. No cambiar sin entender la causa raíz.

### ADR-001: proot-distro + Debian Bookworm para n8n

**Contexto:** n8n requiere compilar módulos nativos con `node-gyp`, que necesita glibc real.

**Alternativas evaluadas:**
- Termux nativo: falla en `node-gyp` por Bionic libc
- Docker: requiere root o kernel con namespace support (no garantizado en Android)
- Termux-glibc (workaround experimental): inestable, no mantenido

**Decisión:** proot-distro con Debian Bookworm ARM64. Provee glibc real, apt completo, y Node.js 20 LTS instalable con `nvm` dentro del entorno.

**Consecuencias:** n8n y cloudflared viven en `/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian/`. Los scripts de control acceden al proot via `proot-distro login debian -- comando`.

---

### ADR-002: Node.js 20 LTS en proot, nodejs-lts (v24) en Termux nativo

**Contexto:** Dos versiones de Node.js coexisten en el mismo dispositivo con propósitos distintos.

**Razón Node.js 20 en proot:**
n8n usa el paquete `isolated-vm` para sandboxing de código JavaScript. Este paquete requiere una API de V8 específica que fue cambiada en Node.js 22+. Usar Node.js 22 o 24 dentro del proot rompe n8n silenciosamente — los workflows con código JavaScript fallan sin mensaje de error claro.

**Razón nodejs-lts (v24) en Termux:**
Claude Code y EAS CLI requieren Node.js ≥18. El paquete `nodejs` de Termux (v25+) introdujo cambios de ABI que rompen la instalación de Claude Code en ARM64. El paquete `nodejs-lts` fija v24 que es estable con ambas herramientas.

**Regla:** Nunca instalar `nodejs` (sin -lts) en Termux nativo. Siempre `pkg install nodejs-lts`.

---

### ADR-003: Claude Code @2.1.111 como versión fija

**Contexto:** Claude Code incluye binarios nativos precompilados para diferentes arquitecturas.

**Problema:** A partir de la versión 2.1.112+, el paquete incluye binarios nativos que usan glibc. En Bionic libc de Android/Termux, estos binarios fallan al ejecutarse. Las versiones ≤2.1.111 no incluyen estos binarios o los incluyen como opcionales con fallback a JavaScript puro.

**Solución:**
```bash
npm install -g @anthropic-ai/claude-code@2.1.111
```

**Método de lanzamiento:** En lugar del binario empaquetado `claude`, se invoca directamente el script JavaScript:
```bash
node $(npm root -g)/@anthropic-ai/claude-code/cli.js
```

**Fallback automático en install_claude.sh:** Si la versión `latest` falla, el script reintenta automáticamente con `@2.1.111`.

---

### ADR-004: cloudflared dentro del proot

**Contexto:** cloudflared necesita resolver DNS para establecer el túnel hacia los servidores de Cloudflare.

**Problema:** El DNS de Termux nativo redirige queries a `[::1]:53` (loopback IPv6). Las queries UDP a esta dirección son rechazadas porque no hay un servidor DNS real escuchando ahí en la mayoría de dispositivos Android. cloudflared falla silenciosamente o con errores de conexión intermitentes.

**Solución:** Correr cloudflared dentro del proot Debian, donde el DNS usa el resolver del sistema Android a través de la emulación de proot, que sí funciona correctamente.

---

### ADR-005: Scripts descargados a `~/` en setup inicial

**Contexto:** El menú necesita poder instalar módulos sin requerir internet.

**Problema:** Si `menu.sh` descargara los scripts de instalación en tiempo de uso (al presionar `[1]`), el menú dependería de tener conexión activa en cada acción. En un servidor de desarrollo, la conexión puede no estar disponible o ser lenta.

**Decisión:** `instalar.sh` descarga todos los scripts de módulo a `~/` durante el setup inicial. El menú los ejecuta localmente. Si un script no existe o está vacío, `menu.sh` lo re-descarga como fallback.

**Archivos en `~/`:**
```
~/menu.sh
~/backup.sh
~/restore.sh
~/install_n8n.sh
~/install_claude.sh
~/install_ollama.sh
~/install_expo.sh
~/start_servidor.sh
~/stop_servidor.sh
~/ver_url.sh
~/ollama_start.sh
~/ollama_stop.sh
~/eas_build.sh
... (scripts de control generados por cada instalador)
```

---

### ADR-006: `[0]` para Backup/Restore en el menú

**Contexto:** El menú usa `[1-4]` para módulos funcionales. Se necesita un slot para Backup/Restore que no colisione con módulos futuros.

**Alternativas evaluadas:**
- `[5]`: colisiona con módulos futuros (Python `[5]`, SQLite `[6]`, etc.)
- `[b]` en footer: no intuitivo, invisible para usuarios nuevos
- `[0]`: convención universal para "opciones del sistema" en menús numerados

**Decisión:** `[0]` con separador visual entre los módulos y el footer. Nunca se desplaza independientemente de cuántos módulos se agreguen.

---

## 4. COMPONENTES DEL SISTEMA

### 4.1 instalar.sh — Setup maestro

**Responsabilidad:** Setup completo desde cero en una instalación limpia de Termux.

**Flujo de ejecución:**
```
PASO 0 → Verificar permiso de escritura en /sdcard (escritura real, no solo existencia del directorio)
PASO 1 → pkg update + pkg upgrade + dependencias base (curl, wget, git, tmux, proot, proot-distro)
PASO 2 → Tema visual GitHub Dark + fuente JetBrains Mono
PASO 3 → termux.properties con extra-keys del stack
PASO 4 → Descargar menu.sh a ~/
PASO 5 → Descargar 6 scripts (install_*.sh + backup.sh + restore.sh) a ~/
PASO 6 → Configurar .bashrc (alias menu + auto-ejecutar al abrir Termux)
PASO 7 → Menú de selección de módulos a instalar (opcional)
```

**Checkpoints:** Cada paso escribe en `~/.instalar_checkpoint`. Re-ejecutar el script salta los pasos ya completados.

**Variable de control:**
```bash
export ANDROID_SERVER_READY=1
```
Los scripts hijos detectan esta variable y saltan el `pkg update` (ya hecho por el padre).

---

### 4.2 menu.sh — Dashboard TUI

**Responsabilidad:** Interfaz de control principal. Se ejecuta automáticamente al abrir Termux.

**Estructura interna:**
```
Funciones de estado:
  check_n8n()      → lee registry + tmux → devuelve "running|ver|" o "not_installed||"
  check_claude()   → lee registry → devuelve "ready|ver|" o "not_installed||"
  check_ollama()   → pkg show ollama + tmux → devuelve estado y versión real
  check_expo()     → lee registry → devuelve estado

Funciones de UI:
  draw_module()    → dibuja una fila de módulo con estado y comando
  show_help()      → pantalla de ayuda
  show_header()    → header con IP y RAM

Instalación:
  install_module() → mini-menú [1] limpio / [2] GitHub Releases / [b] cancelar

Submenús:
  submenu_n8n()    → control n8n
  submenu_ollama() → control Ollama (con _ollama_ensure_server y _ollama_list_models)
  submenu_expo()   → control EAS
  submenu_backup() → backup/restore completo

Loop principal:
  while true → leer estado → dibujar → leer input → dispatch
```

**Detección de versión Ollama:**
```bash
# CORRECTO — pkg show devuelve la versión instalada desde Termux repos
ver=$(pkg show ollama 2>/dev/null | grep "^Version:" | awk '{print $2}')

# INCORRECTO — devuelve "vunknown" en Termux porque el binario
# no tiene acceso al sistema de versiones de pkg
ollama --version
```

---

### 4.3 install_*.sh — Instaladores de módulo

**Responsabilidad:** Instalar, configurar y registrar un módulo específico.

**Estructura estándar de cada instalador:**
```bash
# 1. Variables de control
REGISTRY="$HOME/.android_server_registry"
CHECKPOINT="$HOME/.install_MODULO_checkpoint"

# 2. Helpers check_done / mark_done
check_done() { grep -q "^$1$" "$CHECKPOINT" 2>/dev/null; }
mark_done()  { echo "$1" >> "$CHECKPOINT"; }

# 3. Saltar pkg update si viene del instalador maestro
if [ -z "$ANDROID_SERVER_READY" ]; then
  pkg update -y && pkg upgrade -y
fi

# 4. Pasos con checkpoints individuales
if ! check_done "dependencias"; then
  pkg install -y ...
  mark_done "dependencias"
fi

# 5. Escribir en registry al finalizar
{
  echo "MODULO.installed=true"
  echo "MODULO.version=X.X.X"
  echo "MODULO.install_date=$(date +%Y-%m-%d)"
  echo "MODULO.location=termux_native"
} >> "$REGISTRY"

# 6. Limpiar checkpoint
rm -f "$CHECKPOINT"
```

---

### 4.4 backup.sh — Sistema de backup

**Responsabilidad:** Empaquetar el estado actual del sistema en archivos `.tar.xz` por módulo.

**Partes generadas:**

| Parte | Fuente | Contenido |
|-------|--------|-----------|
| part1-termux-base | `$HOME/` | .bashrc, .termux, scripts de control, registry |
| part2-claude-code | `$NPM_GLOBAL/@anthropic-ai` | Módulo npm completo |
| part3-eas-expo | `$NPM_GLOBAL/eas-cli` + `~/.expo` | Módulo npm + credenciales |
| part4-ollama | `$TERMUX_PREFIX/bin/ollama` + lib | Binario + librerías (sin modelos) |
| part5-n8n-data | Dentro del proot via `proot-distro login` | n8n + cloudflared + Node.js + .n8n |
| part6-proot-debian | `$ROOTFS_BASE/debian/` | Rootfs Debian completo |

**Soporte `--module X`:**
```bash
should_run() {
  [ -z "$TARGET_MODULE" ] || [ "$TARGET_MODULE" = "$1" ]
}

if should_run "ollama"; then
  # bloque de backup de Ollama
fi
```

**Generación de checksums:**
```bash
for f in "$TMP_DIR"/*.tar.xz; do
  SHA=$(sha256sum "$f" | cut -d' ' -f1)
  echo "$SHA  $(basename "$f")" >> checksums.txt
done
```

---

### 4.5 restore.sh — Sistema de restore

**Responsabilidad:** Restaurar módulos desde GitHub Releases o backup local con verificación de integridad.

**Argumentos:**
```bash
--module <base|claude|expo|ollama|n8n|proot|all>
--source <github|local>
```

**Flujo de restore desde GitHub:**
```
1. curl GitHub API → https://api.github.com/repos/Honkonx/termux-ai-stack/releases/latest
2. Parsear JSON → extraer browser_download_url de la parte necesaria
3. Descargar SOLO la parte necesaria (no todo el release)
4. Descargar checksums.txt del mismo release
5. Verificar SHA256 → error si no coincide
6. Extraer en ubicación correcta
7. Restaurar permisos de ejecución
8. Actualizar registry
```

**Diferencia restore local vs GitHub:**
- GitHub: descarga el último release publicado (instalación nueva o disaster recovery)
- Local: usa el backup generado por `backup.sh` en el mismo dispositivo (preserva configuración propia)

**Restore especial part5 (n8n dentro del proot):**
```bash
# Copia el .tar.xz al /tmp/ del rootfs
cp "$DOWNLOADED_FILE" "${ROOTFS_PATH}tmp/n8n_restore.tar.xz"

# Extrae desde adentro del proot (rutas absolutas dentro del proot)
proot-distro login "$DISTRO_NAME" -- bash << 'INNER'
  tar -xJf /tmp/n8n_restore.tar.xz -C /
  chmod +x /usr/local/bin/n8n /usr/local/bin/cloudflared
  rm -f /tmp/n8n_restore.tar.xz
INNER
```

---

## 5. FLUJOS DE DATOS

### 5.1 Instalación desde cero

```
Usuario
  │
  ▼
curl -o instalar.sh && bash instalar.sh
  │
  ├─ PASO 0: termux-setup-storage → /sdcard accesible
  ├─ PASO 1: pkg update → dependencias base
  ├─ PASO 2: tema GitHub Dark + JetBrains Mono
  ├─ PASO 3: termux.properties + extra-keys
  ├─ PASO 4: curl → ~/menu.sh
  ├─ PASO 5: curl → ~/install_*.sh + ~/backup.sh + ~/restore.sh
  ├─ PASO 6: ~/.bashrc → alias menu + auto-exec
  └─ PASO 7: selección módulos → bash ~/install_X.sh
                                      │
                                      ├─ pkg install dependencias
                                      ├─ instalar módulo
                                      ├─ generar scripts de control
                                      └─ escribir ~/.android_server_registry
```

### 5.2 Instalación de módulo desde el menú (limpio)

```
menu.sh [1-4] → not_installed
  │
  ▼
install_module() → mini-menú
  │
  ├─ [1] Limpio → bash ~/install_X.sh < /dev/tty
  │                    │
  │                    └─ instala + escribe registry + genera scripts
  │
  └─ [2] GitHub → bash ~/restore.sh --module X < /dev/tty
                       │
                       └─ descarga + verifica SHA256 + extrae + escribe registry
```

### 5.3 Flujo de backup

```
bash ~/backup.sh [--module X]
  │
  ├─ Detecta módulos instalados (existencia real, no solo registry)
  ├─ Para cada módulo activo:
  │    ├─ Empaqueta en ~/backup_tmp/
  │    └─ Genera RESTORE.txt con instrucciones
  ├─ Genera checksums.txt (SHA256 de cada parte)
  └─ Mueve todo a /sdcard/Download/termux-ai-stack-releases/
```

### 5.4 Flujo de restore

```
bash ~/restore.sh --module X [--source github|local]
  │
  ├─ Si --source no definido → select_source() → pregunta al usuario
  │
  ├─ SOURCE=github:
  │    ├─ GET https://api.github.com/.../releases/latest
  │    ├─ Extrae browser_download_url de la parte
  │    ├─ curl → ~/restore_tmp/partX.tar.xz
  │    ├─ curl → ~/restore_tmp/checksums.txt
  │    └─ sha256sum --check → error si falla
  │
  ├─ SOURCE=local:
  │    ├─ ls /sdcard/Download/termux-ai-stack-releases/partX-*.tar.xz
  │    └─ cp → ~/restore_tmp/ + copiar checksums local
  │
  ├─ restore_partX() → extrae en ubicación correcta
  └─ update_registry() → escribe módulo.installed=true + módulo.source=restore
```

---

## 6. SISTEMA DE SCRIPTS

### 6.1 Árbol de dependencias

```
instalar.sh
  ├─ descarga → menu.sh
  ├─ descarga → install_n8n.sh
  ├─ descarga → install_claude.sh
  ├─ descarga → install_ollama.sh
  ├─ descarga → install_expo.sh
  ├─ descarga → backup.sh
  └─ descarga → restore.sh

menu.sh
  ├─ llama → install_*.sh (locales en ~/)
  ├─ llama → restore.sh (local en ~/ o descarga si falta)
  ├─ llama → backup.sh (local en ~/ o descarga si falta)
  ├─ llama → start_servidor.sh (generado por install_n8n.sh)
  ├─ llama → stop_servidor.sh
  ├─ llama → ollama_start.sh (generado por install_ollama.sh)
  └─ llama → eas_build.sh (generado por install_expo.sh)

backup.sh
  └─ llama → proot-distro login (para part5 y detectar part6)

restore.sh
  ├─ llama → GitHub API (para fuente github)
  └─ llama → proot-distro login (para restore part5)
```

### 6.2 Convenciones de nomenclatura

| Patrón | Ejemplo | Propósito |
|--------|---------|-----------|
| `install_X.sh` | `install_ollama.sh` | Instalador de módulo |
| `X_start.sh` | `ollama_start.sh` | Arrancar servicio |
| `X_stop.sh` | `ollama_stop.sh` | Detener servicio |
| `X_status.sh` | `n8n_status.sh` | Estado detallado |
| `X_log.sh` | `n8n_log.sh` | Ver logs |
| `ver_X.sh` | `ver_url.sh` | Mostrar información |

### 6.3 Comunicación entre scripts

```bash
# Pasar stdin al script hijo (obligatorio para prompts en subprocesos)
bash "$HOME/script.sh" < /dev/tty

# Señal de entorno controlado (skip pkg update)
export ANDROID_SERVER_READY=1
bash "$HOME/install_X.sh"

# Pasar argumentos estructurados
bash "$HOME/restore.sh" --module ollama --source github
```

---

## 7. SISTEMA DE BACKUP Y RESTORE

### 7.1 Formato de archivos

```
/sdcard/Download/termux-ai-stack-releases/
├── part1-termux-base-YYYYMMDD_HHMM.tar.xz
├── part2-claude-code-YYYYMMDD_HHMM.tar.xz
├── part3-eas-expo-YYYYMMDD_HHMM.tar.xz
├── part4-ollama-YYYYMMDD_HHMM.tar.xz
├── part5-n8n-data-YYYYMMDD_HHMM.tar.xz
├── part6-proot-debian-YYYYMMDD_HHMM.tar.xz
└── checksums-YYYYMMDD_HHMM.txt
```

El timestamp en el nombre permite múltiples backups coexistentes. `restore.sh` usa glob `partX-*.tar.xz` y toma el más reciente con `tail -1`.

### 7.2 Estructura interna de cada parte

**part2-claude-code:**
```
npm_modules/
  @anthropic-ai/
    claude-code/
      cli.js          ← punto de entrada principal
      ...
RESTORE.txt           ← instrucciones manuales de restauración
```

**part4-ollama:**
```
bin/
  ollama              ← binario principal
lib_ollama/           ← librerías de soporte (si existen)
home/
  ollama_start.sh
  ollama_stop.sh
RESTORE.txt
```

**part5-n8n-data** (extraído desde dentro del proot):
```
usr/local/bin/n8n
usr/local/bin/cloudflared
usr/local/bin/node
usr/local/lib/node_modules/n8n/
usr/local/lib/node_modules/npm/
root/.n8n/           ← workflows, credenciales, DB
root/.bashrc
root/.cf_token       ← token cloudflared (si existe)
```

### 7.3 Verificación de integridad

```bash
# Generación en backup.sh
SHA=$(sha256sum "$archivo" | cut -d' ' -f1)
echo "$SHA  $(basename "$archivo")" >> checksums.txt

# Verificación en restore.sh
EXPECTED=$(grep "$FILENAME" checksums.txt | cut -d' ' -f1)
ACTUAL=$(sha256sum "$archivo" | cut -d' ' -f1)
[ "$EXPECTED" = "$ACTUAL" ] || error "SHA256 no coincide"
```

---

## 8. REGISTRY DE ESTADO

### 8.1 Formato

Archivo de texto plano `~/.android_server_registry` con pares `clave=valor`. Una entrada por línea.

```
n8n.installed=true
n8n.version=2.8.4
n8n.install_date=2026-04-18
n8n.port=5678
n8n.location=proot_debian

claude_code.installed=true
claude_code.version=2.1.111
claude_code.install_date=2026-04-18
claude_code.location=termux_native

ollama.installed=true
ollama.version=0.21.0
ollama.install_date=2026-04-18
ollama.port=11434
ollama.location=termux_native

expo.installed=true
expo.version=18.7.0
expo.install_date=2026-04-18
expo.location=termux_native
```

### 8.2 API de lectura

```bash
# Función helper usada en todos los scripts
get_reg() {
  grep "^${1}\.${2}=" "$REGISTRY" 2>/dev/null | cut -d'=' -f2
}

# Uso
VER=$(get_reg n8n version)          # → "2.8.4"
LOC=$(get_reg claude_code location) # → "termux_native"
IS=$(get_reg ollama installed)      # → "true"
```

### 8.3 API de escritura

```bash
# Escritura inicial (append)
{
  echo "modulo.installed=true"
  echo "modulo.version=X.X.X"
} >> "$REGISTRY"

# Actualización (usado en restore.sh — elimina entradas previas)
sed -i "/^modulo\./d" "$REGISTRY"
{
  echo "modulo.installed=true"
  echo "modulo.version=restored"
  echo "modulo.source=restore"
} >> "$REGISTRY"
```

### 8.4 Limitaciones del registry

- No es atómico: si el proceso se interrumpe durante la escritura, puede quedar inconsistente
- No es el único indicador de estado: `menu.sh` verifica existencia física de archivos además del registry (ej: `[ -d "$NPM_GLOBAL/@anthropic-ai" ]`)
- `tmux has-session` es la fuente de verdad para estado "corriendo" de servicios

---

## 9. ESTÁNDAR DE DESARROLLO

### 9.1 Estructura de un script nuevo

```bash
#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  termux-ai-stack · nombre_script.sh
#  Descripción en una línea
#
#  USO:
#    bash ~/nombre_script.sh [opciones]
#
#  REPO: https://github.com/Honkonx/termux-ai-stack
#  VERSIÓN: X.Y.Z | Mes Año
# ============================================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$TERMUX_PREFIX/sbin:$PATH"

# Colores estándar
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"; }
```

### 9.2 Prompts interactivos

```bash
# SIEMPRE así — flushea en subprocesos Termux
echo -n "  ¿Continuar? (s/n): "
read -r VAR

# NUNCA así
read -r -p "  ¿Continuar? (s/n): " VAR
```

### 9.3 Llamadas a subprocesos con prompts

```bash
# Siempre redirigir stdin para que los read del hijo funcionen
bash "$HOME/install_X.sh" < /dev/tty
bash "$HOME/restore.sh" --module ollama < /dev/tty
```

### 9.4 Comandos dentro del proot

```bash
# Para comandos simples
proot-distro login "$DISTRO_NAME" -- comando arg1 arg2

# Para bloques multi-línea (heredoc)
proot-distro login "$DISTRO_NAME" -- bash << 'PROOT_INNER'
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# comandos aquí
PROOT_INNER
```

### 9.5 Versioning

| Componente | Formato | Criterio de incremento |
|-----------|---------|----------------------|
| Major (X) | Cambio de arquitectura, incompatibilidad hacia atrás |
| Minor (Y) | Feature nuevo, cambio de comportamiento |
| Patch (Z) | Bug fix, cambio cosmético |

### 9.6 Checklist para agregar un módulo nuevo

- [ ] Script `install_X.sh` con checkpoints y registry
- [ ] `should_run "X"` en `backup.sh` con función `make_part "partN-X"`
- [ ] `restore_partN()` en `restore.sh` con extracción correcta
- [ ] Módulo `[N]` en el loop de `menu.sh` con `draw_module`
- [ ] Submenú `submenu_X()` si el módulo tiene estado (running/stopped)
- [ ] Descarga agregada en PASO 5 de `instalar.sh`
- [ ] Descarga agregada en lista de `[u] actualizar` de `menu.sh`
- [ ] Documentado en `README.md` y `ARCHITECTURE.md`

---

## 10. LIMITACIONES CONOCIDAS

### 10.1 Rendimiento de Ollama

Los modelos de IA corren completamente en CPU en dispositivos móviles. La GPU del teléfono no es accesible desde Termux/proot sin drivers específicos. Tiempos de respuesta esperados:

| Modelo | Tokens/seg aprox. | Tiempo primera respuesta |
|--------|-------------------|--------------------------|
| qwen2.5:0.5b | ~8-12 t/s | ~3-5 seg |
| qwen:1.8b | ~4-6 t/s | ~8-12 seg |
| phi3:mini | ~2-3 t/s | ~20-30 seg |

### 10.2 Claude Code UI web

Claude Code incluye una interfaz web (`claude --web`). Requiere el módulo `node-pty` para emular una terminal en el navegador. `node-pty` necesita compilar código nativo y no tiene prebuilds para ARM64/Bionic. La instalación falla. Solución: usar Claude Code exclusivamente desde terminal.

### 10.3 Termux:Boot

El arranque automático de servicios al encender el teléfono requiere la app [Termux:Boot](https://f-droid.org/packages/com.termux.boot/). Sin ella, n8n y Ollama no arrancan solos tras un reinicio — hay que abrirlos manualmente desde el menú. No está integrado en el stack actual.

### 10.4 Límite de RAM

Con todos los módulos corriendo simultáneamente en un dispositivo de 12GB:
- n8n (idle): ~200-400MB
- Ollama + modelo qwen2.5:0.5b: ~600-900MB
- Claude Code: no consume RAM en background

En dispositivos de 6GB o menos, correr n8n + Ollama simultáneamente puede provocar que Android mate procesos en background.

---

## 11. EVOLUCIÓN FUTURA

### 11.1 Fase 5 — Mejoras UI (próxima)

- Monitoreo RAM/CPU/temperatura en header del menú (via `free`, `cat /proc/stat`, `termux-battery-status`)
- URL n8n activa en pantalla principal (leer de `~/.last_cf_url`)
- Modelo Ollama activo mostrado en el submenú

### 11.2 Fase 6 — Módulos nuevos

Cada módulo nuevo sigue el checklist de la sección 9.6.

Módulos planificados por orden de esfuerzo/impacto:

| Módulo | Script | Dónde corre | Esfuerzo |
|--------|--------|-------------|----------|
| SSH server | `install_ssh.sh` | Termux nativo | Bajo |
| Python + Ollama client | `install_python.sh` | Termux nativo | Bajo |
| Open WebUI | `install_open_webui.sh` | proot Debian | Alto |
| SQLite tools | `install_sqlite.sh` | Termux nativo | Bajo |

### 11.3 Fase 8 — App nativa Android

La meta a largo plazo es reemplazar el TUI bash con una aplicación Android nativa. El stack bash seguirá siendo el motor — la app es una capa de control encima.

**Arquitectura propuesta:**

```
App Android (React Native / Kotlin)
  │
  ├─ Lee ~/.android_server_registry → estado de módulos
  │
  ├─ Ejecuta comandos via Termux:API o WebSocket local
  │    ├─ bash ~/start_servidor.sh
  │    ├─ bash ~/ollama_start.sh
  │    └─ bash ~/restore.sh --module X
  │
  ├─ UI switches → controlar n8n / Ollama
  ├─ Selector de modelo → ollama list → ollama run X
  ├─ Terminal integrada → node cli.js (Claude Code)
  └─ Dashboard → estado, RAM, URL n8n activa
```

**MVP sugerido:**
Antes de la app nativa, construir un dashboard web local (Python `http.server` + HTML/JS) que lea el registry y controle los módulos. Sirve como prototipo de la UI y se puede usar desde el navegador del teléfono inmediatamente.

**Ruta técnica para la app:**
1. Dashboard web como MVP (Fase 8a) — valida la UI sin desarrollo nativo
2. App React Native con EAS (ya tenemos EAS CLI en el stack) (Fase 8b)
3. Comunicación app ↔ Termux via Termux:API o servidor WebSocket local
4. Distribución via APK directo o Play Store con perfil EAS production

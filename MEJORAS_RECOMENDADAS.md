# termux-ai-stack · Mejoras Recomendadas
**Última actualización:** Abril 2026  
**Estado:** Documento vivo — se actualiza con cada fase completada

---

## ESTADO DE IMPLEMENTACIÓN

| # | Mejora | Estado | Fase |
|---|--------|--------|------|
| ~~1~~ | ~~restore.sh~~ | ✅ **Completado** | Fase 4 |
| 2 | Monitoreo de recursos en header | 📋 Pendiente | Fase 5 |
| 3 | Open WebUI para Ollama | 📋 Pendiente | Fase 6 |
| 4 | SSH access desde PC | 📋 Pendiente | Fase 6 |
| 5 | Python + entorno IA | 📋 Pendiente | Fase 6 |
| 6 | Notificaciones termux-api | 📋 Pendiente | Fase 6 |
| 7 | SQLite visible desde menú | 📋 Pendiente | Fase 6 |
| 8 | Dashboard web (MVP app nativa) | 📋 Pendiente | Fase 8a |
| 9 | App nativa Android | 📋 Pendiente | Fase 8b |
| 10 | Termux:Boot — arranque automático | 📋 Pendiente | Fase 5 |

---

## FASE 5 — Mejoras UI y fixes (próxima)

### Mejora 2: Monitoreo de recursos en el header

**Qué es:** RAM libre, temperatura CPU y almacenamiento disponible en el header del dashboard.

**Por qué:** En móvil es crítico saber si Ollama o n8n están consumiendo recursos antes de lanzar otro proceso. Sin esta info el usuario no sabe cuándo detener servicios.

**Vista objetivo:**
```
  ╔══════════════════════════════════════════╗
  ║  ⬡ TERMUX·AI·STACK                      ║
  ║  IP: 192.168.1.5  ·  RAM: 4.2GB libre   ║
  ║  CPU: 34°C  ·  /sdcard: 45GB libre      ║
  ╚══════════════════════════════════════════╝
```

**Implementación técnica:**
```bash
# RAM libre
RAM_FREE=$(free -m | awk '/^Mem:/{printf "%.1fGB", $7/1024}')

# Temperatura CPU (requiere termux-api instalado)
CPU_TEMP=$(termux-battery-status 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('temperature','?')}°C\")" 2>/dev/null)
[ -z "$CPU_TEMP" ] && CPU_TEMP="--°C"

# Almacenamiento /sdcard
STORAGE=$(df -h /sdcard 2>/dev/null | awk 'NR==2{print $4}')
[ -z "$STORAGE" ] && STORAGE="--"
```

**Consideración:** `termux-battery-status` requiere la app Termux:API instalada. El header debe funcionar aunque no esté disponible — usar `--` como fallback.

**Archivo a modificar:** `menu.sh` — solo el bloque del header en el loop principal.  
**Esfuerzo estimado:** Bajo (1-2 horas).

---

### Mejora 10: Termux:Boot — arranque automático de servicios

**Qué es:** Arrancar n8n y Ollama automáticamente cuando el teléfono se enciende, sin abrir Termux manualmente.

**Por qué:** Un servidor de desarrollo real no requiere intervención manual tras un reinicio. Actualmente hay que abrir Termux y presionar `[1]` para iniciar n8n cada vez que el teléfono se reinicia.

**Cómo funciona:**
```bash
# Requiere la app Termux:Boot (F-Droid)
# Scripts en ~/.termux/boot/ se ejecutan al arrancar

mkdir -p ~/.termux/boot/

cat > ~/.termux/boot/start-stack.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Esperar que el sistema esté listo
sleep 10

# Iniciar n8n si está instalado
[ -f ~/start_servidor.sh ] && bash ~/start_servidor.sh

# Iniciar Ollama si está instalado
[ -f ~/ollama_start.sh ] && bash ~/ollama_start.sh
EOF

chmod +x ~/.termux/boot/start-stack.sh
```

**Requisitos:**
- App [Termux:Boot](https://f-droid.org/packages/com.termux.boot/) desde F-Droid
- Permiso "Ejecutar en segundo plano" para Termux en Android
- En MIUI/HyperOS: activar "Autostart" para Termux en ajustes de batería

**Script a crear:** Integrar en `instalar.sh` como PASO opcional, o crear `install_boot.sh`.  
**Esfuerzo estimado:** Bajo (2-3 horas).

---

## FASE 6 — Módulos nuevos

### Mejora 4: SSH access desde PC

**Qué es:** Servidor SSH en Termux para acceder al stack completo desde una computadora con teclado físico.

**Por qué:** Desarrollar desde el teléfono con teclado virtual es incómodo. Con SSH desde PC se puede usar VS Code, iTerm2 o cualquier cliente SSH. El stack sigue corriendo en el teléfono — el PC es solo el teclado y la pantalla.

**Capacidades que habilita:**
- VS Code Remote SSH → editar código en el teléfono desde PC
- Copiar/pegar sin limitaciones del teclado virtual
- Acceso al stack desde otra habitación o vía internet con cloudflared

**Implementación:**
```bash
pkg install openssh

# Generar claves del servidor (solo primera vez)
ssh-keygen -A

# Configurar puerto (Termux usa 8022, no 22)
# /data/data/com.termux/files/usr/etc/ssh/sshd_config
# Port 8022

# Iniciar servidor
sshd

# Detener
pkill sshd
```

**Conexión desde PC:**
```bash
# Misma red WiFi
ssh -p 8022 $(whoami)@192.168.1.X

# Desde internet (via cloudflared tunnel SSH)
ssh -o ProxyCommand='cloudflared access ssh --hostname mi-tunnel.trycloudflare.com' termux@mi-tunnel
```

**Script a crear:** `install_ssh.sh`
```
- pkg install openssh
- Configurar sshd_config (puerto 8022, autenticación por clave)
- Generar par de claves del servidor
- Crear ~/ssh_start.sh y ~/ssh_stop.sh
- Mostrar IP + comando de conexión exacto
- Agregar al menú como submenú de sistema
```

**Esfuerzo estimado:** Bajo (2-3 horas).

---

### Mejora 5: Python + entorno de scripts IA

**Qué es:** Python 3 en Termux nativo con cliente de Ollama y librerías de automatización.

**Por qué:** Permite escribir scripts que usen Ollama como backend de IA — procesamiento de texto, bots, automatizaciones que van más allá de lo que n8n ofrece visualmente. Complementa perfectamente el stack.

**Capacidades que habilita:**
```python
# Procesar texto con Ollama local
import ollama
response = ollama.chat(
  model='qwen2.5:0.5b',
  messages=[{'role': 'user', 'content': 'Resume: ...'}]
)

# Automatizar con la API de n8n
import requests
requests.post('http://localhost:5678/webhook/mi-workflow', json={...})

# Leer el registry del stack
with open(os.path.expanduser('~/.android_server_registry')) as f:
    registry = dict(line.strip().split('=') for line in f if '=' in line)
```

**Script a crear:** `install_python.sh`
```
- pkg install python (Termux nativo — ya incluye pip)
- pip install ollama requests httpx python-dotenv
- pip install jupyter (opcional — notebook via browser)
- Crear ~/scripts/ con ejemplos:
    ollama_test.py     → prueba de conexión con Ollama
    n8n_trigger.py     → disparar workflows de n8n
    registry_read.py   → leer estado del stack
- Alias: py → python3, pip → pip3
```

**Esfuerzo estimado:** Bajo (2-3 horas).

---

### Mejora 3: Open WebUI para Ollama

**Qué es:** Interfaz web tipo ChatGPT que se conecta a Ollama local. Responsive, guarda historial de conversaciones, permite cambiar modelo sin comandos.

**Por qué:** El chat de Ollama por terminal (opción `[2]` del submenú) funciona pero es incómodo en móvil para conversaciones largas. Open WebUI provee una interfaz de chat real accesible desde el navegador del teléfono o de cualquier dispositivo en la red.

**Acceso:**
- `http://localhost:3000` desde el navegador del teléfono
- Via cloudflared tunnel → accesible desde cualquier dispositivo en internet

**Cómo corre:** proot Debian, mismo entorno que n8n. Puerto 3000.

**Repo oficial:** https://github.com/open-webui/open-webui

**Script a crear:** `install_open_webui.sh`
```
- Instala en proot Debian (pip install open-webui — versión sin Docker)
- Conecta a Ollama en http://localhost:11434
- Crea start_webui.sh / stop_webui.sh
- Sesión tmux: "webui-server"
- Puerto 3000
- Agrega al menú como módulo [5]
```

**Consideraciones técnicas:**
- Open WebUI requiere Python 3.11+ y ~500MB de dependencias
- Primera instalación lenta (~5-10 min en móvil)
- Consume ~200-300MB de RAM en idle
- Requiere Ollama corriendo en :11434

**Esfuerzo estimado:** Alto (4-6 horas, dependencias complejas).

---

### Mejora 7: SQLite visible desde menú

**Qué es:** Acceso directo a la base de datos de n8n desde el menú. Permite ver workflows guardados, ejecuciones, credenciales, sin entrar al proot manualmente.

**Por qué:** n8n ya usa SQLite por defecto en `~root/.n8n/database.sqlite` dentro del proot. Hacerlo visible desde el menú facilita debugging, exportar datos y verificar el estado de los workflows.

**Implementación:**
```bash
# Ver tablas
proot-distro login debian -- sqlite3 /root/.n8n/database.sqlite ".tables"

# Ver últimas ejecuciones
proot-distro login debian -- sqlite3 /root/.n8n/database.sqlite \
  "SELECT id, workflowName, status, startedAt FROM execution_entity ORDER BY startedAt DESC LIMIT 10;"
```

**Script a crear:** `install_sqlite.sh`
```
- pkg install sqlite (Termux nativo)
- Script ~/sqlite_n8n.sh → abre la DB de n8n con sqlite3
- Opción en submenú de n8n: [7] Ver base de datos
```

**Esfuerzo estimado:** Bajo (1-2 horas).

---

### Mejora 6: Notificaciones del sistema (termux-api)

**Qué es:** Notificaciones Android nativas cuando procesos largos terminan en background.

**Por qué:** Cuando Termux está minimizado, el usuario no sabe si `ollama pull` de 1GB terminó, si el backup completó, o si n8n tuvo un error. Las notificaciones resuelven esto sin tener que revisar Termux manualmente.

**Casos de uso:**
```bash
# Al completar descarga de modelo
ollama pull phi3:mini && \
  termux-notification --title "Ollama" \
    --content "Modelo phi3:mini descargado ✓" \
    --sound

# Al completar backup
bash ~/backup.sh && \
  termux-notification --title "Backup completado" \
    --content "6 partes en /sdcard/Download"

# Al fallar n8n
# Via webhook interno de n8n → HTTP node → curl localhost → script bash
```

**Requisitos:**
- App [Termux:API](https://f-droid.org/packages/com.termux.api/) desde F-Droid
- `pkg install termux-api`

**Integración en scripts existentes:**
- `backup.sh` → notificación al completar
- `restore.sh` → notificación al completar
- `install_ollama.sh` → notificación tras `ollama pull`

**Esfuerzo estimado:** Bajo (2-3 horas).

---

## FASE 8 — App nativa Android

### Mejora 8: Dashboard web (MVP — Fase 8a)

**Qué es:** Página HTML servida localmente desde Python que muestra el estado del stack en tiempo real. Accesible desde el navegador del teléfono o de cualquier dispositivo en la misma red.

**Por qué es el primer paso hacia la app nativa:** Validar la UI y la comunicación con el stack sin escribir código Android. Si el dashboard web funciona bien, la app nativa es básicamente el mismo frontend empaquetado.

**Arquitectura:**
```
Python http.server :8080
  │
  ├─ GET /         → index.html (dashboard)
  ├─ GET /status   → lee ~/.android_server_registry → JSON
  ├─ GET /ram      → free -m → JSON
  └─ POST /action  → ejecuta bash ~/start_servidor.sh etc.

index.html
  ├─ Fetch /status cada 5 segundos
  ├─ Switches para cada módulo
  ├─ Muestra URL n8n activa
  └─ Muestra modelos Ollama instalados
```

**Acceso:**
- `http://localhost:8080` desde el navegador del teléfono
- `http://192.168.1.X:8080` desde cualquier dispositivo en WiFi

**Script a crear:** `install_dashboard.sh`
```
- Python 3 + http.server (ya disponible si se instaló Python)
- index.html generado o descargado desde repo
- ~/dashboard_start.sh / ~/dashboard_stop.sh
- Sesión tmux: "dashboard-server"
- Puerto 8080
```

**Base existente:** `termux_dashboard_preview.html` en el repo puede servir como punto de partida visual.

**Esfuerzo estimado:** Medio (4-6 horas).

---

### Mejora 9: App nativa Android (Fase 8b)

**Qué es:** Aplicación Android nativa con interfaz gráfica para controlar el stack completo. Reemplaza el TUI bash como interfaz principal. El motor bash sigue siendo el mismo — la app es una capa de control encima.

**Visión:**
```
App termux-ai-stack
  │
  ├─ Pantalla principal
  │    ├─ Switch n8n  ──── ON/OFF
  │    ├─ Switch Ollama ── ON/OFF
  │    ├─ Switch Claude ── abrir terminal
  │    ├─ Switch EAS ───── abrir builds
  │    └─ RAM / CPU / estado en tiempo real
  │
  ├─ Pantalla Ollama
  │    ├─ Lista de modelos instalados
  │    ├─ Selector de modelo activo
  │    ├─ Chat integrado (conectado a :11434)
  │    └─ Descargar modelo nuevo
  │
  ├─ Pantalla Claude Code
  │    ├─ Terminal integrada (emulador de terminal)
  │    └─ Lanza: node cli.js
  │
  ├─ Pantalla n8n
  │    ├─ Estado + URL pública
  │    └─ Abrir n8n en WebView
  │
  └─ Pantalla Backup/Restore
       ├─ Backup individual o completo
       └─ Restore desde GitHub o backup propio
```

**Stack tecnológico propuesto:**

| Componente | Tecnología | Razón |
|-----------|-----------|-------|
| Framework | React Native + Expo | Ya tenemos EAS CLI en el stack — compilación directa |
| Comunicación con Termux | Termux:API + WebSocket local | Termux:API para comandos, WS para estado en tiempo real |
| Terminal integrada | `@xterm/xterm` en WebView | Emulador de terminal en browser |
| Estado del stack | Leer `~/.android_server_registry` via Termux:API | Fuente de verdad ya existe |
| Distribución | EAS Build → APK directo | Sin Play Store, instalación directa |

**Ruta de desarrollo:**
```
Fase 8a → Dashboard web funcional
  ↓
Validar UI y comunicación con stack
  ↓
Fase 8b → React Native wrapping el dashboard web (WebView)
  ↓
Fase 8c → Componentes nativos: switches, terminal, chat Ollama
  ↓
Fase 8d → Distribución APK via EAS Build + GitHub Releases
```

**Decisión técnica pendiente:** Termux:API permite ejecutar comandos bash desde una app Android. Alternativa: servidor WebSocket local en Python que recibe acciones y ejecuta los scripts bash. La segunda opción no requiere Termux:API y funciona desde cualquier app o navegador.

**Esfuerzo estimado:** Alto (proyecto independiente, meses de desarrollo).

---

## ORDEN DE IMPLEMENTACIÓN SUGERIDO

| Prioridad | Mejora | Fase | Esfuerzo | Impacto | Dependencias |
|-----------|--------|------|----------|---------|--------------|
| 1 | Monitoreo recursos en header | 5 | Bajo | Alto | termux-api opcional |
| 2 | Termux:Boot arranque automático | 5 | Bajo | Alto | App Termux:Boot |
| 3 | SSH access desde PC | 6 | Bajo | Alto | Ninguna |
| 4 | Python + entorno IA | 6 | Bajo | Medio | Ninguna |
| 5 | Notificaciones termux-api | 6 | Bajo | Medio | App Termux:API |
| 6 | SQLite visible desde menú | 6 | Bajo | Medio | install_python.sh |
| 7 | Open WebUI para Ollama | 6 | Alto | Muy alto | Python, Ollama corriendo |
| 8 | Dashboard web MVP | 8a | Medio | Alto | install_python.sh |
| 9 | App nativa Android | 8b | Muy alto | Muy alto | Dashboard web, EAS |

---

## BUGS PENDIENTES (antes de Fase 6)

Estos bugs deben resolverse en Fase 5 antes de agregar módulos nuevos:

| Bug | Impacto | Causa conocida |
|-----|---------|----------------|
| Claude "no instalado" hasta refrescar | Medio | Race condition registry vs loop re-read |
| "Deteniendo n8n" múltiples veces | Bajo | Variable `state` no se actualiza localmente tras stop |
| Texto cortado en lista descarga Ollama | Bajo | Descripciones largas para ancho de teléfono |

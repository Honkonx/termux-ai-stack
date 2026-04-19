# termux-ai-stack · CLAUDE.md
# Contexto para Claude Code — leer al inicio de cada sesión

## Proyecto
App Android + stack de servicios corriendo en Termux sin root.
Repo: https://github.com/Honkonx/termux-ai-stack
Dispositivo: Xiaomi POCO F5 · Android 15 · ARM64 · 12GB RAM · sin root

## Stack actual
- n8n 2.8.4 → proot Debian (isolated-vm requiere glibc)
- Ollama v0.21.0 → Termux nativo
- Claude Code v2.1.111 → Termux nativo (solo desde GitHub Releases)
- EAS CLI 18.7.0 → Termux nativo
- Python 3.13.13 → Termux nativo
- SSH OpenSSH_10.3 → Termux nativo puerto 8022
- Dashboard web → Python http.server :8080 (Fase 8a ✓)

## Estructura del repo
```
termux-ai-stack/
├── instalar.sh              ← entrada única (curl | bash)
├── Script/
│   ├── menu.sh              ← dashboard TUI v3.1.2
│   ├── backup.sh / restore.sh
│   ├── install_*.sh         ← un script por módulo
│   ├── dashboard_start.sh / dashboard_stop.sh
│   └── dashboard/
│       ├── dashboard_server.py   ← servidor HTTP API
│       └── index.html            ← UI dashboard web
└── App/                     ← React Native (Fase 8b)
    ├── App.js
    ├── app.json
    ├── package.json
    └── eas.json
```

## Flujo de trabajo
1. Claude Code edita archivos en PC
2. git commit + push al repo
3. En Android/Termux: curl descarga el archivo actualizado
4. bash ejecuta el script

## Fase actual: 8b-B — App React Native con Termux:API
- Comunicación: am broadcast com.termux.app.RUN_COMMAND
- Sin servidor Python intermediario
- Lee ~/.android_server_registry directo
- UI: switches nativos por módulo (start/stop)
- Build: EAS Build → APK

## Reglas críticas — NO romper
- n8n SIEMPRE en proot Debian (no en Termux nativo)
- Node.js en proot = versión 20 LTS (no 22/24 — rompe isolated-vm)
- Claude Code = v2.1.111 fijo (versiones nuevas usan glibc incompatible)
- Claude Code instalación = solo desde GitHub Releases (npm produce cli.js inválido)
- IP detection = ifconfig (ip route da Permission denied en Android)
- Puerto SSH = 8022 (Termux no puede usar <1024 sin root)
- Registry formato = modulo.clave=valor (con punto, no guión bajo)
- N8N_PROTOCOL=https + N8N_PROXY_HOPS=1 siempre al arrancar n8n

## Comandos frecuentes
```bash
# Ver estado del stack en Android:
cat ~/.android_server_registry

# Dashboard web:
bash ~/dashboard_start.sh   # inicia :8080
bash ~/dashboard_stop.sh

# n8n:
bash ~/start_servidor.sh
bash ~/stop_servidor.sh

# Build APK:
cd ~/termux-stack-ui
EAS_SKIP_AUTO_FINGERPRINT=1 eas build --platform android --profile preview
```

## Bugs conocidos — ya documentados
- react-native-webview crashea en ARM64 (Fase 8b-A descartada)
- Ollama lento: regresión v0.11.5+ bug #27290 termux-packages
- Open WebUI: requiere Python <3.13, incompatible con proot actual
- which no existe en Termux: usar bash -c "command -v X"

## Estándar de scripts bash
```bash
# Leer input (crítico en Termux):
echo -n "¿Continuar? (s/n): "
read -r VAR < /dev/tty

# Subprocesos:
bash "$HOME/install_X.sh" < /dev/tty

# Proot:
proot-distro login debian -- bash << 'PROOT_INNER'
export HOME=/root
PROOT_INNER
```

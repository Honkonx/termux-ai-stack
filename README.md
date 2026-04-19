# termux-ai-stack

Convierte un dispositivo Android ARM64 en un servidor de desarrollo con IA, automatización y acceso remoto — sin root, sin modificar el sistema operativo.

**Stack:** n8n · Ollama · Claude Code · Python · SSH · cloudflared  
**Requisitos:** Android 8+ · Termux (F-Droid) · 4GB RAM mínimo recomendado

---

## Instalación

```bash
curl -fsSL https://raw.githubusercontent.com/Honkonx/termux-ai-stack/main/instalar.sh \
  -o instalar.sh && bash instalar.sh
```

El script maestro instala dependencias base, descarga todos los módulos y abre el dashboard automáticamente al finalizar.

---

## Módulos

| # | Módulo | Descripción | Dónde corre | Puerto |
|---|--------|-------------|-------------|--------|
| 1 | **n8n** | Automatización de workflows con IA | proot Debian | 5678 |
| 2 | **Claude Code** | Agente de desarrollo IA en terminal | Termux nativo | — |
| 3 | **Ollama** | Modelos de IA locales (LLM) | Termux nativo | 11434 |
| 4 | **Expo / EAS** | Build de apps React Native | Termux nativo | — |
| 5 | **Python + SQLite** | Scripting, automatización, BD | Termux nativo | — |
| 6 | **SSH** | Acceso remoto desde PC | Termux nativo | 8022 |

---

## Dashboard TUI

Al abrir Termux se carga automáticamente el dashboard:

```
  ╔══════════════════════════════════════════╗
  ║  ⬡ TERMUX·AI·STACK                      ║
  ║  RAM: 4.2GB  Disk: 77G  IP: 192.168.1.5 ║
  ╚══════════════════════════════════════════╝

  [1] n8n           v2.8.4   ● ACTIVO    Submenú
  [2] Claude Code   v2.1.111 ● ACTIVO    Claude
  [3] Ollama        v0.21.0  ● ACTIVO    Submenú
  [4] Expo / EAS    v18.7.0  ○           Submenú
  [5] Python        v3.13    ✓           Submenú
  [6] SSH           v10.3    ● ACTIVO    Submenú
  ──────────────────────────────────────────
  [0] Backup / Restore
  [r] refrescar  [u] actualizar  [s] shell  [d] desinstalar
```

---

## Acceso remoto via SSH

```bash
# Desde PC (misma red WiFi):
ssh -p 8022 usuario@IP_DEL_TELEFONO

# VS Code Remote-SSH:
# usuario@IP:8022
```

El dashboard TUI completo funciona desde la terminal del PC vía SSH.

---

## n8n + Telegram + Ollama

El stack permite crear bots de Telegram con IA local:

```
Telegram → cloudflared tunnel → n8n → Ollama (local) → respuesta Telegram
```

**Variables requeridas para webhooks:**
```bash
# En ~/.env_n8n:
N8N_WEBHOOK_URL=https://tu-dominio.com

# n8n arranca con:
export WEBHOOK_URL=https://tu-dominio.com
export N8N_PROTOCOL=https
export N8N_PROXY_HOPS=1
```

---

## Backup y Restore

```bash
# Backup completo a /sdcard/Download:
bash ~/backup.sh

# Backup por módulo:
bash ~/backup.sh --module n8n

# Restore desde GitHub Releases:
bash ~/restore.sh --module all --source github

# Restore desde backup local:
bash ~/restore.sh --module n8n --source local
```

Los backups se suben a GitHub Releases para restaurar en cualquier dispositivo.

---

## Dispositivos probados

| Dispositivo | Android | RAM | Estado |
|------------|---------|-----|--------|
| Xiaomi POCO F5 | 15 (HyperOS 2.0) | 12 GB | ✅ Todo funcionando |
| Xiaomi Mi 11 Lite 5G NE | 13 (EvolutionX) | 8 GB | ✅ Funcionando |

---

## Versiones fijas críticas

| Componente | Versión | Razón |
|-----------|---------|-------|
| Claude Code | `@2.1.111` | >2.1.111 incompatible con Bionic libc |
| Node.js en proot | `20 LTS` | Node 22/24 rompe `isolated-vm` de n8n |
| Claude Code — instalación | GitHub Releases únicamente | npm install produce binario inválido en ARM64 |

---

## Estructura del repositorio

```
termux-ai-stack/
├── instalar.sh           ← instalador maestro (curl | bash)
├── README.md
├── ARCHITECTURE.md       ← decisiones técnicas detalladas
├── PROGRESO.md           ← estado del proyecto y roadmap
└── Script/
    ├── menu.sh           ← dashboard TUI
    ├── backup.sh         ← backup completo o por módulo
    ├── restore.sh        ← restore desde GitHub o local
    ├── install_n8n.sh    ← n8n + cloudflared en proot Debian
    ├── install_claude.sh ← Claude Code en Termux nativo
    ├── install_ollama.sh ← Ollama en Termux nativo
    ├── install_expo.sh   ← EAS CLI en Termux nativo
    ├── install_python.sh ← Python + SQLite en Termux nativo
    └── install_ssh.sh    ← OpenSSH en Termux nativo
```

---

## Licencia

MIT

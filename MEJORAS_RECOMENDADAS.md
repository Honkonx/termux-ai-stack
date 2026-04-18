# termux-ai-stack · Mejoras Recomendadas
**Creado:** Sábado 18 Abril 2026  
**Estado:** Propuestas — ninguna implementada aún

---

## 1. Open WebUI para Ollama ⭐ ALTA PRIORIDAD

**Qué es:** Interfaz web tipo ChatGPT que se conecta a Ollama local.  
**Por qué:** El chat por terminal es incómodo en móvil. Open WebUI es responsive, guarda historial, permite cambiar modelo sin comandos.  
**Cómo corre:** proot Debian, mismo entorno que n8n. Puerto 3000.  
**Acceso:** `http://localhost:3000` desde el navegador del teléfono, o por cloudflared desde cualquier dispositivo.  
**Repo oficial:** https://github.com/open-webui/open-webui

**Script a crear:** `install_open_webui.sh`
```
- Instala Open WebUI en proot Debian (pip o Docker-less)
- Crea start_webui.sh / stop_webui.sh
- Sesión tmux: "webui-server"
- Puerto 3000, conectado a Ollama :11434
- Agrega al menú como módulo [5]
```

---

## 2. Monitoreo de recursos en el header del menú

**Qué es:** Temperatura CPU + uso RAM + almacenamiento disponible en el header del dashboard.  
**Por qué:** En móvil es crítico saber si Ollama o n8n están quemando recursos. Sin esta info el usuario no sabe cuándo hay que detener procesos.

**Datos a mostrar:**
```
RAM: 4.2GB libre / 12GB   CPU: 34°C   /sdcard: 45GB libre
```

**Cómo obtenerlo en Termux:**
```bash
# Temperatura CPU (requiere termux-api)
termux-battery-status | grep temperature

# RAM
free -m | awk '/^Mem:/{printf "%.1fGB / %.0fGB", $7/1024, $2/1024}'

# Almacenamiento
df -h /sdcard | awk 'NR==2{print $4}'
```

**Impacto:** Bajo esfuerzo, alto valor. Modifica solo el header de `menu.sh`.

---

## 3. Python + entorno de scripts IA

**Qué es:** Python 3 en Termux nativo con pip, requests, y cliente de Ollama.  
**Por qué:** Permite escribir scripts que usen Ollama local como backend — automatizaciones, procesamiento de texto, bots simples. Complementa perfectamente n8n.

**Script a crear:** `install_python.sh`
```
- pkg install python (ya disponible en Termux nativo)
- pip install ollama requests httpx
- pip install jupyter (opcional — notebook por browser)
- Script de ejemplo: ~/scripts/ollama_test.py
- Alias: py-ollama → python con OLLAMA_HOST configurado
```

**Ejemplo de uso que habilita:**
```python
import ollama
response = ollama.chat(model='qwen:0.5b', messages=[
  {'role': 'user', 'content': 'Resume este texto: ...'}
])
```

---

## 4. SQLite como base de datos local

**Qué es:** Base de datos embebida, sin servidor, directamente en Termux.  
**Por qué:** n8n puede guardar datos de workflows en SQLite. También útil para scripts Python que necesiten persistencia. No consume RAM extra.

**Script a crear:** `install_sqlite.sh`
```
- pkg install sqlite (Termux nativo)
- Configurar n8n para usar SQLite como DB (ya es el default de n8n)
- Script de utilidad: ~/scripts/db_explorer.sh
- Alias: sqlite-n8n → abre la DB de n8n directamente
```

**Nota:** n8n ya usa SQLite por defecto en `~/.n8n/database.sqlite` dentro del proot. Este módulo lo haría visible y gestionable desde el menú.

---

## 5. restore.sh — restaurar desde backup

**Qué es:** Script para restaurar cualquier parte del backup generado por `backup.sh`.  
**Por qué:** Sin restore el backup es solo tranquilidad. Si algo se rompe, el usuario necesita poder restaurar sin leer documentación.  
**Estado en roadmap:** Fase 4 — ya planificado pero no implementado.

**Script a crear:** `restore.sh`
```
- Detecta archivos en /sdcard/Download/termux-ai-stack-releases/
- Menú de selección: qué partes restaurar
- Verifica checksums SHA256 antes de restaurar
- Pregunta antes de sobreescribir datos existentes
- Extrae cada parte en su ubicación correcta
- Actualiza registry tras restaurar
```

---

## 6. Notificaciones del sistema (termux-api)

**Qué es:** Notificaciones Android cuando n8n completa un workflow o Ollama termina de descargar un modelo.  
**Por qué:** Los procesos largos (descarga de modelos, builds EAS) no tienen feedback cuando Termux está en background.

**Cómo funciona:**
```bash
# Requiere termux-api + Termux:API app
pkg install termux-api
termux-notification --title "n8n" --content "Workflow completado"
termux-notification --title "Ollama" --content "Modelo phi3:mini descargado"
```

**Integración:**
- Al final de `ollama pull` en `install_ollama.sh`
- Al final de cada workflow en n8n (via HTTP node → webhook local)
- Al completar backup en `backup.sh`

---

## 7. Acceso SSH al stack desde PC

**Qué es:** Servidor SSH en Termux para acceder al stack desde una computadora.  
**Por qué:** Trabajar con teclado físico desde PC es mucho más cómodo que el teclado virtual. Permite usar VS Code Remote SSH apuntando al teléfono.

**Script a crear:** `install_ssh.sh`
```
- pkg install openssh
- Genera par de claves
- Configura puerto (default 8022 en Termux)
- Muestra IP + comando de conexión
- Alias: ssh-start / ssh-stop
- VS Code: Remote SSH → ssh user@IP:8022
```

**Nota:** Requiere estar en la misma WiFi o usar cloudflared como tunnel SSH.

---

## 8. Panel web del stack (dashboard HTML)

**Qué es:** Página HTML servida localmente que muestra el estado de todos los módulos en tiempo real.  
**Por qué:** El menú TUI es funcional pero no compartible. Un dashboard web permitiría ver el estado del stack desde el navegador del teléfono o de otro dispositivo en la misma red.

**Implementación:**
```
- Servidor HTTP simple con Python: python -m http.server 8080
- HTML + JS que lee el registry vía endpoint local
- Muestra: estado módulos, URL n8n, modelos Ollama, RAM/CPU
- Accesible en http://IP:8080 desde cualquier dispositivo en WiFi
```

**Alternativa más simple:** el archivo `termux_dashboard_preview.html` que ya existe en el repo podría servir como base.

---

## Orden de implementación sugerido

| Prioridad | Mejora | Esfuerzo | Impacto |
|-----------|--------|---------|---------|
| 1 | restore.sh | Medio | Alto — completa el sistema de backup |
| 2 | Monitoreo recursos en header | Bajo | Alto — info crítica en móvil |
| 3 | Open WebUI | Alto | Muy alto — transforma la experiencia Ollama |
| 4 | SSH access | Bajo | Alto — comodidad de desarrollo |
| 5 | Python + Ollama client | Bajo | Medio — extiende el stack |
| 6 | Notificaciones | Bajo | Medio — calidad de vida |
| 7 | SQLite visible | Bajo | Medio — complementa n8n |
| 8 | Dashboard web | Medio | Medio — nice to have |

#!/usr/bin/env python3
"""
termux-ai-stack — Dashboard Server
Fase 8a MVP
Puerto: 8080
"""

import os
import json
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

HOME = os.path.expanduser("~")
REGISTRY_FILE = os.path.join(HOME, ".android_server_registry")
DASHBOARD_DIR = os.path.join(HOME, "dashboard")
PORT = 8080

# ── Helpers ──────────────────────────────────────────────────────────────────

def read_registry():
    """Lee ~/.android_server_registry → dict"""
    data = {}
    try:
        with open(REGISTRY_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    data[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return data

def get_ram_info():
    """Lee /proc/meminfo → dict con total/used/free en MB"""
    try:
        result = subprocess.run(
            ["free", "-m"], capture_output=True, text=True, timeout=3
        )
        lines = result.stdout.strip().split("\n")
        # Línea: Mem: total used free shared buff/cache available
        parts = lines[1].split()
        return {
            "total_mb": int(parts[1]),
            "used_mb":  int(parts[2]),
            "free_mb":  int(parts[3]),
            "available_mb": int(parts[6]) if len(parts) > 6 else int(parts[3])
        }
    except Exception as e:
        return {"error": str(e)}

def get_ip():
    """IP local de la interfaz WiFi"""
    try:
        result = subprocess.run(
            ["ip", "route", "get", "1"], capture_output=True, text=True, timeout=3
        )
        for token in result.stdout.split():
            if token.count(".") == 3 and token != "1":
                return token
    except Exception:
        pass
    return "127.0.0.1"

def run_action(action, module):
    """Ejecuta acción bash en background, retorna {ok, msg}"""
    scripts = {
        # (module, action) → comando bash
        ("n8n",    "start"):   "bash ~/start_servidor.sh",
        ("n8n",    "stop"):    "pkill -f 'n8n start' 2>/dev/null; pkill -f cloudflared 2>/dev/null",
        ("ollama", "start"):   "tmux new-session -d -s ollama 'ollama serve' 2>/dev/null || true",
        ("ollama", "stop"):    "pkill -f 'ollama serve' 2>/dev/null",
        ("ssh",    "start"):   "sshd",
        ("ssh",    "stop"):    "pkill sshd 2>/dev/null",
    }
    key = (module.lower(), action.lower())
    cmd = scripts.get(key)
    if not cmd:
        return {"ok": False, "msg": f"Acción desconocida: {action} en {module}"}
    try:
        subprocess.Popen(
            cmd, shell=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return {"ok": True, "msg": f"{module} {action} ejecutado"}
    except Exception as e:
        return {"ok": False, "msg": str(e)}

# ── API: /api/status ──────────────────────────────────────────────────────────

def build_status():
    reg = read_registry()
    ram = get_ram_info()
    ip  = get_ip()

    modules = []

    # ── n8n ──
    n8n_installed = os.path.exists(
        "/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian/root/.n8n"
    ) or reg.get("n8n_installed") == "true"
    n8n_running = _proc_running("n8n")
    n8n_url = reg.get("n8n_tunnel_url", "")
    modules.append({
        "id":        "n8n",
        "name":      "n8n",
        "icon":      "⬡",
        "installed": n8n_installed or reg.get("n8n_installed") == "true",
        "running":   n8n_running,
        "version":   reg.get("n8n_version", ""),
        "detail":    f":{reg.get('n8n_port', '5678')} · {n8n_url}" if n8n_running else "",
        "url":       n8n_url,
        "layer":     "proot"
    })

    # ── Ollama ──
    ollama_installed = bool(subprocess.run(
        ["which", "ollama"], capture_output=True
    ).returncode == 0)
    ollama_running = _proc_running("ollama serve")
    modules.append({
        "id":        "ollama",
        "name":      "Ollama",
        "icon":      "◎",
        "installed": ollama_installed or reg.get("ollama_installed") == "true",
        "running":   ollama_running,
        "version":   reg.get("ollama_version", ""),
        "detail":    ":11434" if ollama_running else "~4GB modelos",
        "url":       "http://localhost:11434",
        "layer":     "termux"
    })

    # ── Claude Code ──
    claude_installed = reg.get("claude_installed") == "true" or os.path.exists(
        os.path.join(HOME, "claude-code/cli.js")
    )
    modules.append({
        "id":        "claude",
        "name":      "Claude Code",
        "icon":      "◆",
        "installed": claude_installed,
        "running":   False,   # no background
        "version":   reg.get("claude_version", ""),
        "detail":    "node ~/claude-code/cli.js" if claude_installed else "",
        "url":       "",
        "layer":     "termux"
    })

    # ── EAS / Expo ──
    eas_installed = reg.get("eas_installed") == "true" or bool(subprocess.run(
        ["which", "eas"], capture_output=True
    ).returncode == 0)
    modules.append({
        "id":        "eas",
        "name":      "Expo / EAS",
        "icon":      "◈",
        "installed": eas_installed,
        "running":   False,
        "version":   reg.get("eas_version", ""),
        "detail":    "eas-cli listo" if eas_installed else "",
        "url":       "",
        "layer":     "termux"
    })

    # ── Python ──
    py_installed = reg.get("python_installed") == "true"
    py_ver = reg.get("python_version", "")
    modules.append({
        "id":        "python",
        "name":      "Python",
        "icon":      "🐍",
        "installed": py_installed,
        "running":   False,
        "version":   py_ver,
        "detail":    py_ver if py_installed else "",
        "url":       "",
        "layer":     "termux"
    })

    # ── SSH ──
    ssh_running = _proc_running("sshd")
    modules.append({
        "id":        "ssh",
        "name":      "SSH",
        "icon":      "⌗",
        "installed": reg.get("ssh_installed") == "true",
        "running":   ssh_running,
        "version":   reg.get("ssh_version", ""),
        "detail":    f"{ip}:8022" if ssh_running else ":8022",
        "url":       "",
        "layer":     "termux"
    })

    return {
        "ram":     ram,
        "ip":      ip,
        "device":  reg.get("device_model", "Android"),
        "modules": modules
    }

def _proc_running(pattern):
    """Comprueba si hay un proceso corriendo que coincide con pattern"""
    try:
        result = subprocess.run(
            ["pgrep", "-f", pattern], capture_output=True, text=True, timeout=2
        )
        return result.returncode == 0
    except Exception:
        return False

# ── HTTP Handler ──────────────────────────────────────────────────────────────

class DashHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        # Silenciar logs de acceso (demasiado ruido en Termux)
        pass

    def send_json(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def serve_file(self, path, ctype):
        try:
            with open(path, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", len(body))
            self.end_headers()
            self.wfile.write(body)
        except FileNotFoundError:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"404 not found")

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path   = parsed.path.rstrip("/") or "/"

        if path == "/" or path == "/index.html":
            self.serve_file(
                os.path.join(DASHBOARD_DIR, "index.html"),
                "text/html; charset=utf-8"
            )

        elif path == "/api/status":
            self.send_json(200, build_status())

        elif path == "/api/registry":
            self.send_json(200, read_registry())

        elif path == "/api/ram":
            self.send_json(200, get_ram_info())

        elif path == "/api/ping":
            self.send_json(200, {"ok": True, "port": PORT})

        else:
            # Intenta servir archivo estático desde ~/dashboard/
            fpath = os.path.join(DASHBOARD_DIR, parsed.path.lstrip("/"))
            if os.path.isfile(fpath):
                ext = os.path.splitext(fpath)[1]
                ctypes = {
                    ".css": "text/css",
                    ".js":  "application/javascript",
                    ".png": "image/png",
                    ".ico": "image/x-icon"
                }
                self.serve_file(fpath, ctypes.get(ext, "application/octet-stream"))
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"404")

    def do_POST(self):
        parsed = urlparse(self.path)
        path   = parsed.path.rstrip("/")

        if path == "/api/action":
            length  = int(self.headers.get("Content-Length", 0))
            raw     = self.rfile.read(length)
            try:
                body = json.loads(raw)
            except Exception:
                self.send_json(400, {"ok": False, "msg": "JSON inválido"})
                return

            action = body.get("action", "")
            module = body.get("module", "")

            if not action or not module:
                self.send_json(400, {"ok": False, "msg": "Faltan action/module"})
                return

            result = run_action(action, module)
            self.send_json(200, result)
        else:
            self.send_response(404)
            self.end_headers()

# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    os.makedirs(DASHBOARD_DIR, exist_ok=True)

    print(f"[dashboard] Iniciando servidor en :{PORT}")
    print(f"[dashboard] UI:  http://localhost:{PORT}")
    print(f"[dashboard] API: http://localhost:{PORT}/api/status")
    print(f"[dashboard] Ctrl+C para detener\n")

    server = HTTPServer(("0.0.0.0", PORT), DashHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[dashboard] Detenido.")
        server.server_close()

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# termux-ai-stack · dashboard_server.py
# v1.3.0 | Abril 2026
# Fix: ollama proc detection · backup action · /api/ollama/models · /api/ssh/info

import os, json, subprocess, collections, datetime, shutil
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

_cmd_log = collections.deque(maxlen=20)

HOME          = os.path.expanduser("~")
REGISTRY_FILE = os.path.join(HOME, ".android_server_registry")
DASHBOARD_DIR = os.path.join(HOME, "dashboard")
TERMUX_PREFIX = os.environ.get("TERMUX_PREFIX", "/data/data/com.termux/files/usr")
PORT          = 8080

# ── Registry ──────────────────────────────────────────────────
def read_registry():
    data = {}
    try:
        with open(REGISTRY_FILE) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    data[k.strip()] = v.strip()
    except:
        pass
    return data

def reg(d, *keys):
    for k in keys:
        if k in d:
            return d[k]
    return ""

# ── Detección de procesos ─────────────────────────────────────
def proc_running(pattern):
    """pgrep -f con fallback a ps aux para compatibilidad con Android."""
    try:
        r = subprocess.run(["pgrep", "-f", pattern],
                           capture_output=True, timeout=2)
        return r.returncode == 0
    except:
        pass
    try:
        r = subprocess.run(["ps", "aux"], capture_output=True, text=True, timeout=3)
        return pattern in r.stdout
    except:
        return False

def ollama_running():
    """Detecta ollama serve por cualquier método disponible."""
    # Método 1: pgrep/ps directo
    if proc_running("ollama serve"):
        return True
    # Método 2: tmux session ollama-server
    try:
        r = subprocess.run(["tmux", "has-session", "-t", "ollama-server"],
                           capture_output=True, timeout=2)
        if r.returncode == 0:
            return True
    except:
        pass
    # Método 3: puerto 11434 abierto (ollama responde)
    try:
        r = subprocess.run(
            ["curl", "-s", "--max-time", "1", "http://localhost:11434/api/tags"],
            capture_output=True, timeout=3
        )
        return r.returncode == 0
    except:
        pass
    return False

def n8n_running():
    """Detecta n8n en proot por tmux session y proceso."""
    try:
        r = subprocess.run(["tmux", "has-session", "-t", "n8n-server"],
                           capture_output=True, timeout=2)
        if r.returncode == 0:
            return True
    except:
        pass
    return proc_running("n8n start")

# ── RAM ───────────────────────────────────────────────────────
def get_ram():
    try:
        r = subprocess.run(["free", "-m"], capture_output=True, text=True, timeout=3)
        p = r.stdout.strip().split("\n")[1].split()
        return {
            "total_mb":     int(p[1]),
            "used_mb":      int(p[2]),
            "free_mb":      int(p[3]),
            "available_mb": int(p[6]) if len(p) > 6 else int(p[3]),
        }
    except Exception as e:
        return {"error": str(e)}

# ── IP ────────────────────────────────────────────────────────
def get_ip():
    try:
        r = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=3)
        for line in r.stdout.split("\n"):
            if "inet " in line and "127.0.0.1" not in line:
                parts = line.strip().split()
                for i, p in enumerate(parts):
                    if p == "inet" and i + 1 < len(parts):
                        return parts[i + 1]
    except:
        pass
    try:
        r = subprocess.run(["hostname", "-I"], capture_output=True, text=True, timeout=3)
        for ip in r.stdout.strip().split():
            if ip.startswith(("192.", "10.", "172.")):
                return ip
    except:
        pass
    return "127.0.0.1"

# ── Detección de módulos ──────────────────────────────────────
def claude_installed(d):
    if reg(d, "claude_code.installed", "claude.installed", "claude_installed") == "true":
        return True
    return os.path.exists(os.path.join(TERMUX_PREFIX, "bin", "claude"))

def eas_installed(d):
    if reg(d, "expo.installed", "eas.installed", "eas_installed", "expo_installed") == "true":
        return True
    return os.path.exists(os.path.join(TERMUX_PREFIX, "bin", "eas"))

# ── Modelos Ollama ────────────────────────────────────────────
def get_ollama_models():
    """Retorna lista de modelos instalados en Ollama."""
    models = []
    try:
        r = subprocess.run(["ollama", "list"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            lines = r.stdout.strip().split("\n")[1:]  # skip header
            for line in lines:
                parts = line.split()
                if parts:
                    models.append({
                        "name": parts[0],
                        "size": parts[2] if len(parts) > 2 else "?",
                    })
    except:
        pass
    return models

# ── Info SSH ──────────────────────────────────────────────────
def get_ssh_info():
    ip   = get_ip()
    port = "8022"
    user = os.environ.get("USER", "u0_a")
    authorized_keys_count = 0
    ak_path = os.path.join(HOME, ".ssh", "authorized_keys")
    try:
        with open(ak_path) as f:
            authorized_keys_count = sum(
                1 for line in f
                if line.strip() and not line.strip().startswith("#")
            )
    except:
        pass
    return {
        "ip":       ip,
        "port":     port,
        "user":     user,
        "cmd":      f"ssh -p {port} {user}@{ip}",
        "scp_cmd":  f"scp -P {port} archivo.txt {user}@{ip}:~/",
        "keys":     authorized_keys_count,
    }

# ── Tunnel URL n8n ────────────────────────────────────────────
def get_n8n_url():
    # 1. Archivo .last_cf_url
    cf_url_path = os.path.join(HOME, ".last_cf_url")
    try:
        with open(cf_url_path) as f:
            url = f.read().strip()
            if url:
                return url
    except:
        pass
    # 2. Variable en .env_n8n
    env_path = os.path.join(HOME, ".env_n8n")
    try:
        with open(env_path) as f:
            for line in f:
                if line.startswith("N8N_WEBHOOK_URL="):
                    return line.strip().split("=", 1)[1]
    except:
        pass
    return ""

# ── Status principal ─────────────────────────────────────────
def build_status():
    d       = read_registry()
    ram     = get_ram()
    ip      = get_ip()
    n8n_url = get_n8n_url()

    modules = [
        {
            "id":        "n8n",
            "name":      "n8n",
            "icon":      "⬡",
            "type":      "service",
            "installed": reg(d, "n8n.installed", "n8n_installed") == "true",
            "running":   n8n_running(),
            "version":   reg(d, "n8n.version", "n8n_version"),
            "detail":    n8n_url,
            "url":       n8n_url,
            "layer":     "proot",
        },
        {
            "id":        "ollama",
            "name":      "Ollama",
            "icon":      "◎",
            "type":      "service",
            "installed": reg(d, "ollama.installed", "ollama_installed") == "true",
            "running":   ollama_running(),
            "version":   reg(d, "ollama.version", "ollama_version"),
            "detail":    ":11434",
            "url":       "http://localhost:11434",
            "layer":     "termux",
        },
        {
            "id":        "claude",
            "name":      "Claude Code",
            "icon":      "◆",
            "type":      "tool",
            "installed": claude_installed(d),
            "running":   False,
            "version":   reg(d, "claude_code.version", "claude.version", "claude_version"),
            "detail":    "",
            "url":       "",
            "layer":     "termux",
        },
        {
            "id":        "eas",
            "name":      "Expo / EAS",
            "icon":      "◈",
            "type":      "tool",
            "installed": eas_installed(d),
            "running":   False,
            "version":   reg(d, "expo.version", "eas.version", "eas_version", "expo_version"),
            "detail":    "",
            "url":       "",
            "layer":     "termux",
        },
        {
            "id":        "python",
            "name":      "Python",
            "icon":      "🐍",
            "type":      "tool",
            "installed": reg(d, "python.installed", "python_installed") == "true",
            "running":   False,
            "version":   reg(d, "python.version", "python_version"),
            "detail":    "",
            "url":       "",
            "layer":     "termux",
        },
        {
            "id":        "ssh",
            "name":      "SSH",
            "icon":      "⌗",
            "type":      "service",
            "installed": reg(d, "ssh.installed", "ssh_installed") == "true",
            "running":   proc_running("sshd"),
            "version":   reg(d, "ssh.version", "ssh_version"),
            "detail":    f"{ip}:{reg(d, 'ssh.port', 'ssh_port') or '8022'}",
            "url":       "",
            "layer":     "termux",
        },
    ]
    return {
        "ram":     ram,
        "ip":      ip,
        "device":  reg(d, "device_model", "device") or "Android",
        "modules": modules,
    }

# ── Backup ────────────────────────────────────────────────────
def do_backup():
    """Ejecuta bash ~/backup.sh en background."""
    backup_sh = os.path.join(HOME, "backup.sh")
    if not os.path.exists(backup_sh):
        return False, "backup.sh no encontrado en ~/"
    try:
        subprocess.Popen(
            ["bash", backup_sh],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True, "Backup iniciado — revisa /sdcard/termux-backup/"
    except Exception as e:
        return False, str(e)

# ── Handler HTTP ──────────────────────────────────────────────
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def send_json(self, code, data):
        b = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type",   "application/json; charset=utf-8")
        self.send_header("Content-Length", len(b))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b)

    def serve_file(self, path, ct):
        try:
            b = open(path, "rb").read()
            self.send_response(200)
            self.send_header("Content-Type",   ct)
            self.send_header("Content-Length", len(b))
            self.end_headers()
            self.wfile.write(b)
        except:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"404")

    def do_GET(self):
        p = urlparse(self.path).path.rstrip("/") or "/"

        if p in ("/", "/index.html"):
            self.serve_file(DASHBOARD_DIR + "/index.html", "text/html; charset=utf-8")

        elif p == "/api/status":
            self.send_json(200, build_status())

        elif p == "/api/ping":
            self.send_json(200, {"ok": True, "port": PORT})

        elif p == "/api/registry":
            self.send_json(200, read_registry())

        elif p == "/api/logs":
            self.send_json(200, {"logs": list(_cmd_log)})

        # ── Endpoints específicos por módulo ──────────────────
        elif p == "/api/ollama/models":
            self.send_json(200, {
                "running": ollama_running(),
                "models":  get_ollama_models(),
            })

        elif p == "/api/ssh/info":
            self.send_json(200, get_ssh_info())

        elif p == "/api/n8n/url":
            self.send_json(200, {"url": get_n8n_url()})

        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        path = urlparse(self.path).path.rstrip("/")
        n    = int(self.headers.get("Content-Length", 0))

        if path == "/api/action":
            try:
                b      = json.loads(self.rfile.read(n))
                action = b.get("action", "").lower()
                module = b.get("module", "").lower()
                ts     = datetime.datetime.now().strftime("%H:%M:%S")

                # ── Acciones de sistema ───────────────────────
                if module == "system" and action == "backup":
                    ok, msg = do_backup()
                    _cmd_log.append({"ts": ts, "module": "system", "action": "backup",
                                     "cmd": "bash ~/backup.sh", "ok": ok})
                    self.send_json(200 if ok else 500, {"ok": ok, "msg": msg})
                    return

                # ── Acciones de ollama (pull modelo) ──────────
                if module == "ollama" and action.startswith("pull:"):
                    model_name = action.split(":", 1)[1]
                    subprocess.Popen(
                        f"tmux new-session -d -s ollama-pull 'ollama pull {model_name}'",
                        shell=True,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    _cmd_log.append({"ts": ts, "module": "ollama", "action": f"pull {model_name}",
                                     "cmd": f"ollama pull {model_name}", "ok": True})
                    self.send_json(200, {"ok": True, "msg": f"Descargando {model_name}..."})
                    return

                # ── Acciones estándar de servicios ────────────
                cmds = {
                    ("n8n",    "start"): "bash ~/start_servidor.sh",
                    ("n8n",    "stop"):  "tmux kill-session -t n8n-server 2>/dev/null; pkill -f 'n8n start'; pkill -f cloudflared",
                    ("ollama", "start"): "tmux new-session -d -s ollama-server 'ollama serve' 2>/dev/null || true",
                    ("ollama", "stop"):  "tmux kill-session -t ollama-server 2>/dev/null; pkill -f 'ollama serve' 2>/dev/null; true",
                    ("ssh",    "start"): "sshd",
                    ("ssh",    "stop"):  "pkill sshd",
                }
                cmd = cmds.get((module, action))

                if cmd:
                    subprocess.Popen(
                        cmd, shell=True,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    _cmd_log.append({"ts": ts, "module": module, "action": action,
                                     "cmd": cmd, "ok": True})
                    self.send_json(200, {"ok": True, "msg": f"{module} {action} iniciado"})
                else:
                    _cmd_log.append({"ts": ts, "module": module, "action": action,
                                     "cmd": "", "ok": False})
                    self.send_json(400, {"ok": False, "msg": "Acción no disponible"})

            except Exception as e:
                self.send_json(500, {"ok": False, "msg": str(e)})

        else:
            self.send_response(404)
            self.end_headers()

os.makedirs(DASHBOARD_DIR, exist_ok=True)
print(f"[dashboard] :{PORT}  http://localhost:{PORT}")
HTTPServer(("0.0.0.0", PORT), H).serve_forever()

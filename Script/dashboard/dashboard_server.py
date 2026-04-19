#!/usr/bin/env python3
import os, json, subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

HOME = os.path.expanduser("~")
REGISTRY_FILE = os.path.join(HOME, ".android_server_registry")
DASHBOARD_DIR = os.path.join(HOME, "dashboard")
PORT = 8080

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

def proc_running(pattern):
    try:
        r = subprocess.run(["pgrep", "-f", pattern], capture_output=True, timeout=2)
        return r.returncode == 0
    except:
        return False

def get_ram():
    try:
        r = subprocess.run(["free", "-m"], capture_output=True, text=True, timeout=3)
        p = r.stdout.strip().split("\n")[1].split()
        return {"total_mb": int(p[1]), "used_mb": int(p[2]), "free_mb": int(p[3]),
                "available_mb": int(p[6]) if len(p) > 6 else int(p[3])}
    except Exception as e:
        return {"error": str(e)}

def get_ip():
    try:
        r = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=3)
        for line in r.stdout.split("\n"):
            if "inet " in line and "127.0.0.1" not in line:
                parts = line.strip().split()
                for i, p in enumerate(parts):
                    if p == "inet" and i+1 < len(parts):
                        return parts[i+1]
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

def build_status():
    d = read_registry()
    ram = get_ram()
    ip  = get_ip()
    n8n_url = reg(d, "n8n.tunnel_url", "n8n_tunnel_url", "tunnel_url")
    modules = [
        {"id":"n8n","name":"n8n","icon":"⬡",
         "installed": reg(d,"n8n.installed","n8n_installed")=="true",
         "running":   proc_running("n8n start"),
         "version":   reg(d,"n8n.version","n8n_version"),
         "detail":    n8n_url, "url": n8n_url, "layer":"proot"},
        {"id":"ollama","name":"Ollama","icon":"◎",
         "installed": reg(d,"ollama.installed","ollama_installed")=="true",
         "running":   proc_running("ollama serve"),
         "version":   reg(d,"ollama.version","ollama_version"),
         "detail":    ":11434","url":"http://localhost:11434","layer":"termux"},
        {"id":"claude","name":"Claude Code","icon":"◆",
         "installed": reg(d,"claude_code.installed","claude.installed","claude_installed")=="true"
                      or os.path.exists(HOME+"/claude-code/cli.js"),
         "running":   False,
         "version":   reg(d,"claude_code.version","claude.version","claude_version"),
         "detail":"","url":"","layer":"termux"},
        {"id":"eas","name":"Expo / EAS","icon":"◈",
         "installed": reg(d,"eas.installed","eas_installed")=="true",
         "running":   False,
         "version":   reg(d,"eas.version","eas_version"),
         "detail":"","url":"","layer":"termux"},
        {"id":"python","name":"Python","icon":"🐍",
         "installed": reg(d,"python.installed","python_installed")=="true",
         "running":   False,
         "version":   reg(d,"python.version","python_version"),
         "detail":"","url":"","layer":"termux"},
        {"id":"ssh","name":"SSH","icon":"⌗",
         "installed": reg(d,"ssh.installed","ssh_installed")=="true",
         "running":   proc_running("sshd"),
         "version":   reg(d,"ssh.version","ssh_version"),
         "detail":    f"{ip}:{reg(d,'ssh.port','ssh_port') or '8022'}",
         "url":"","layer":"termux"},
    ]
    return {"ram":ram,"ip":ip,"device":reg(d,"device_model","device") or "Android","modules":modules}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send_json(self, code, data):
        b = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type","application/json; charset=utf-8")
        self.send_header("Content-Length",len(b))
        self.send_header("Access-Control-Allow-Origin","*")
        self.end_headers()
        self.wfile.write(b)
    def serve_file(self, path, ct):
        try:
            b = open(path,"rb").read()
            self.send_response(200)
            self.send_header("Content-Type",ct)
            self.send_header("Content-Length",len(b))
            self.end_headers()
            self.wfile.write(b)
        except:
            self.send_response(404); self.end_headers(); self.wfile.write(b"404")
    def do_GET(self):
        p = urlparse(self.path).path.rstrip("/") or "/"
        if p in ("/","/index.html"):
            self.serve_file(DASHBOARD_DIR+"/index.html","text/html; charset=utf-8")
        elif p=="/api/status":   self.send_json(200,build_status())
        elif p=="/api/ping":     self.send_json(200,{"ok":True,"port":PORT})
        elif p=="/api/registry": self.send_json(200,read_registry())
        else: self.send_response(404); self.end_headers()
    def do_POST(self):
        if urlparse(self.path).path.rstrip("/")=="/api/action":
            n = int(self.headers.get("Content-Length",0))
            try:
                b = json.loads(self.rfile.read(n))
                action,module = b.get("action",""),b.get("module","")
                cmds = {
                    ("n8n","start"):    "bash ~/start_servidor.sh",
                    ("n8n","stop"):     "pkill -f 'n8n start'; pkill -f cloudflared",
                    ("ollama","start"): "tmux new-session -d -s ollama 'ollama serve'",
                    ("ollama","stop"):  "pkill -f 'ollama serve'",
                    ("ssh","start"):    "sshd",
                    ("ssh","stop"):     "pkill sshd",
                }
                cmd = cmds.get((module.lower(),action.lower()))
                if cmd:
                    subprocess.Popen(cmd,shell=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                    self.send_json(200,{"ok":True,"msg":f"{module} {action} OK"})
                else:
                    self.send_json(400,{"ok":False,"msg":"Acción desconocida"})
            except Exception as e:
                self.send_json(500,{"ok":False,"msg":str(e)})
        else:
            self.send_response(404); self.end_headers()

os.makedirs(DASHBOARD_DIR, exist_ok=True)
print(f"[dashboard] :{PORT}  http://localhost:{PORT}")
HTTPServer(("0.0.0.0",PORT),H).serve_forever()

#!/usr/bin/env python3
# termux-ai-stack · dashboard_server.py
# v1.4.0 | Abril 2026
# Añadido endpoint /api/chatbot para SQLite (n8n proxy)

import os, json, subprocess, collections, datetime, shutil
import sqlite3
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

_cmd_log = collections.deque(maxlen=20)
HOME = os.path.expanduser("~")
REGISTRY_FILE = os.path.join(HOME, ".android_server_registry")
DASHBOARD_DIR = os.path.join(HOME, "dashboard")
TERMUX_PREFIX = os.environ.get("TERMUX_PREFIX", "/data/data/com.termux/files/usr")
PORT = 8080

# === CONFIGURACIÓN CHATBOT DB ===
CHATBOT_DB_PATH = os.path.join(HOME, "chatbot_memoria.db")

def init_chatbot_db():
    conn = sqlite3.connect(CHATBOT_DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()

# Inicializar DB al arrancar el servidor
init_chatbot_db()

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
        if k in d: return d[k]
    return ""

# ── Detección de procesos ─────────────────────────────────────
def proc_running(pattern):
    try:
        r = subprocess.run(["pgrep", "-f", pattern], capture_output=True, timeout=2)
        return r.returncode == 0
    except:
        pass
    try:
        r = subprocess.run(["ps", "aux"], capture_output=True, text=True, timeout=2)
        for line in r.stdout.split('\n'):
            if pattern in line and "grep" not in line:
                return True
    except:
        pass
    return False

# ── Status principal ─────────────────────────────────────────
def get_ram():
    try:
        r = subprocess.run(["free", "-m"], capture_output=True, text=True)
        lines = r.stdout.split('\n')
        if len(lines) > 1:
            parts = lines[1].split()
            if len(parts) >= 7:
                return f"{parts[3]}M libres"
    except: pass
    return "N/A"

def get_ip():
    try:
        r = subprocess.run(["ifconfig", "wlan0"], capture_output=True, text=True)
        for line in r.stdout.split('\n'):
            if "inet " in line:
                return line.split()[1]
    except: pass
    return "127.0.0.1"

def get_n8n_url():
    cf_url_path = os.path.join(HOME, ".last_cf_url")
    try:
        with open(cf_url_path) as f:
            url = f.read().strip()
            if url: return url
    except: pass
    env_path = os.path.join(HOME, ".env_n8n")
    try:
        with open(env_path) as f:
            for line in f:
                if line.startswith("N8N_WEBHOOK_URL="):
                    return line.strip().split("=", 1)[1]
    except: pass
    return ""

def build_status():
    d = read_registry()
    ram = get_ram()
    ip = get_ip()
    n8n_url = get_n8n_url()
    
    return {
        "device": { "ram": ram, "ip": ip, "time": datetime.datetime.now().strftime("%H:%M:%S") },
        "n8n": {
            "version": reg(d, "n8n_version"),
            "running": proc_running("n8n"),
            "url": n8n_url
        },
        "ollama": {
            "version": reg(d, "ollama.version", "ollama_version"),
            "running": proc_running("ollama serve")
        },
        "claude": {
            "version": reg(d, "claude_version"),
            "running": True if reg(d, "claude_version") else False
        },
        "expo": {
            "version": reg(d, "eas_version"),
            "running": True if reg(d, "eas_version") else False
        },
        "python": {
            "version": reg(d, "python_version"),
            "running": True if reg(d, "python_version") else False
        },
        "ssh": {
            "version": reg(d, "ssh_version"),
            "running": proc_running("sshd")
        }
    }

# ── Backup ────────────────────────────────────────────────────
def do_backup():
    backup_sh = os.path.join(HOME, "backup.sh")
    if not os.path.exists(backup_sh):
        return False, "backup.sh no encontrado en ~/"
    try:
        subprocess.Popen(["bash", backup_sh], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True, "Backup iniciado en background"
    except Exception as e:
        return False, str(e)

# ── Servidor HTTP ─────────────────────────────────────────────
class MyHandler(BaseHTTPRequestHandler):
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def send_cors_headers(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_OPTIONS(self):
        self.send_cors_headers()

    def do_GET(self):
        parsed_path = urlparse(self.path)
        path = parsed_path.path

        if path == "/api/status":
            self.send_json(build_status())
        
        elif path == "/api/chatbot/history":
            # Endpoint para que n8n lea la memoria del chatbot
            query_components = parse_qs(parsed_path.query)
            user_id = query_components.get("user_id", [""])[0]
            limit = int(query_components.get("limit", ["6"])[0])
            
            if not user_id:
                self.send_json({"error": "user_id is required"}, status=400)
                return
            
            try:
                conn = sqlite3.connect(CHATBOT_DB_PATH)
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT role, content 
                    FROM messages 
                    WHERE user_id = ? 
                    ORDER BY id DESC LIMIT ?
                """, (user_id, limit))
                
                rows = cursor.fetchall()
                messages = [dict(row) for row in rows]
                conn.close()
                
                self.send_json({"messages": messages})
            except Exception as e:
                self.send_json({"error": str(e)}, status=500)

        elif path == "/":
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            index_path = os.path.join(DASHBOARD_DIR, "index.html")
            if os.path.exists(index_path):
                with open(index_path, 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.wfile.write(b"<h1>Dashboard API corriendo</h1><p>Falta index.html en ~/dashboard/</p>")
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length) if content_length > 0 else b""
        
        try:
            req_body = json.loads(post_data.decode('utf-8')) if post_data else {}
        except json.JSONDecodeError:
            req_body = {}

        if path == "/api/chatbot/save":
            # Endpoint para que n8n guarde un nuevo par de mensajes (usuario/asistente)
            user_id = req_body.get("user_id")
            user_text = req_body.get("user_text")
            bot_text = req_body.get("bot_text")
            
            if not all([user_id, user_text, bot_text]):
                self.send_json({"error": "Missing parameters (user_id, user_text, bot_text)"}, status=400)
                return
            
            try:
                conn = sqlite3.connect(CHATBOT_DB_PATH)
                cursor = conn.cursor()
                # Insertar mensaje del usuario
                cursor.execute("INSERT INTO messages (user_id, role, content) VALUES (?, 'user', ?)", (user_id, user_text))
                # Insertar respuesta del bot
                cursor.execute("INSERT INTO messages (user_id, role, content) VALUES (?, 'assistant', ?)", (user_id, bot_text))
                conn.commit()
                conn.close()
                self.send_json({"success": True})
            except Exception as e:
                self.send_json({"error": str(e)}, status=500)

        elif path.startswith("/api/cmd/"):
            action = path.split("/")[-1]
            success = False
            msg = ""
            
            if action == "backup":
                success, msg = do_backup()
            else:
                msg = f"Acción desconocida: {action}"
                
            self.send_json({"success": success, "msg": msg})
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    print(f"Iniciando dashboard en puerto {PORT}...")
    server = HTTPServer(('0.0.0.0', PORT), MyHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
    print("Servidor detenido.")

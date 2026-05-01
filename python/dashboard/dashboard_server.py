#!/usr/bin/env python3
# termux-ai-stack · dashboard_server.py
# v2.0.0 | Mayo 2026
# API completa: status · action · ollama · ssh · n8n · logs · chat · claude config

import os, json, subprocess, collections, shutil, sqlite3
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from urllib import request as ureq
from datetime import datetime

HOME          = os.path.expanduser("~")
REGISTRY_FILE = os.path.join(HOME, ".android_server_registry")
TERMUX_PREFIX = os.environ.get("TERMUX_PREFIX", "/data/data/com.termux/files/usr")
PORT          = 8080

BOT_HISTORY_DB = os.path.join(HOME, "bot_history.db")
_cmd_log       = collections.deque(maxlen=30)

# ── Utilidades ────────────────────────────────────────────────

def now_str():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

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

def write_registry(key, value):
    data = read_registry()
    data[key] = value
    try:
        lines = []
        with open(REGISTRY_FILE) as f:
            lines = f.readlines()
        new_lines = []
        found = False
        for line in lines:
            if line.strip().startswith(key + "="):
                new_lines.append(f"{key}={value}\n")
                found = True
            else:
                new_lines.append(line)
        if not found:
            new_lines.append(f"{key}={value}\n")
        with open(REGISTRY_FILE, "w") as f:
            f.writelines(new_lines)
    except Exception as e:
        # Si no existe el archivo, crearlo
        try:
            with open(REGISTRY_FILE, "a") as f:
                f.write(f"{key}={value}\n")
        except:
            pass

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
        pass
    try:
        r = subprocess.run(["ps", "aux"], capture_output=True, text=True, timeout=2)
        for line in r.stdout.split("\n"):
            if pattern in line and "grep" not in line:
                return True
    except:
        pass
    return False

def get_ip():
    try:
        r = subprocess.run(["ifconfig", "wlan0"], capture_output=True, text=True)
        for line in r.stdout.split("\n"):
            if "inet " in line:
                return line.split()[1]
    except:
        pass
    return "127.0.0.1"

def get_ram():
    try:
        r = subprocess.run(["free", "-m"], capture_output=True, text=True)
        lines = r.stdout.strip().split("\n")
        if len(lines) > 1:
            parts = lines[1].split()
            if len(parts) >= 4:
                total = int(parts[1])
                avail = int(parts[3])
                return {"total_mb": total, "available_mb": avail}
    except:
        pass
    return {"total_mb": 0, "available_mb": 0}

def get_n8n_url():
    for path in [os.path.join(HOME, ".last_cf_url"), os.path.join(HOME, ".env_n8n")]:
        try:
            with open(path) as f:
                for line in f:
                    if path.endswith(".env_n8n") and not line.startswith("N8N_WEBHOOK_URL="):
                        continue
                    val = line.strip().split("=", 1)[-1]
                    if val.startswith("http"):
                        return val
        except:
            pass
    return ""

def log_action(module, action, ok, msg=""):
    _cmd_log.append({
        "ts":     datetime.now().strftime("%H:%M:%S"),
        "module": module,
        "action": action,
        "ok":     ok,
        "msg":    msg,
    })

# ── Build status (formato modules[] que espera App.js) ────────

def build_status():
    d   = read_registry()
    ram = get_ram()
    ip  = get_ip()

    def module(mid, name, inst_keys, ver_keys, is_service=False, pattern=None):
        installed = any(reg(d, k) for k in inst_keys)
        version   = reg(d, *ver_keys)
        running   = proc_running(pattern) if (is_service and pattern) else None
        m = {
            "id":        mid,
            "name":      name,
            "installed": bool(installed),
            "version":   version,
        }
        if is_service:
            m["running"] = bool(running)
        return m

    modules = [
        module("n8n",    "n8n",         ["n8n.installed"],          ["n8n.version","n8n_version"],     True, "n8n"),
        module("ollama", "Ollama",       ["ollama.installed"],       ["ollama.version","ollama_version"],True, "ollama serve"),
        module("claude", "Claude Code",  ["claude_code.installed"],  ["claude_code.version","claude_version"]),
        module("eas",    "Expo / EAS",   ["expo.installed","eas.installed"], ["expo.version","eas_version"]),
        module("python", "Python",       ["python.installed"],       ["python.version","python_version"]),
        module("ssh",    "SSH",          ["ssh.installed"],          ["ssh.version","ssh_version"],     True, "sshd"),
    ]

    # Claude config extra
    claude_cfg = {
        "api_key":  reg(d, "claude_code.api_key", "claude_api_key"),
        "endpoint": reg(d, "claude_code.endpoint", "claude_endpoint"),
    }

    return {
        "modules":    modules,
        "ip":         ip,
        "ram":        ram,
        "time":       datetime.now().strftime("%H:%M:%S"),
        "n8n_url":    get_n8n_url(),
        "claude_cfg": claude_cfg,
    }

# ── Ollama helpers ────────────────────────────────────────────

def ollama_list():
    try:
        r = subprocess.run(["ollama", "list"], capture_output=True, text=True, timeout=5)
        models = []
        for line in r.stdout.strip().split("\n")[1:]:
            parts = line.split()
            if len(parts) >= 3:
                name = parts[0]
                size_raw = parts[2] + " " + (parts[3] if len(parts) > 3 else "")
                models.append({"name": name, "size": size_raw.strip()})
        return models
    except:
        return []

def ollama_pull(name):
    try:
        subprocess.Popen(
            ["ollama", "pull", name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True, f"Descarga de {name} iniciada en background"
    except Exception as e:
        return False, str(e)

def ollama_delete(name):
    try:
        r = subprocess.run(["ollama", "rm", name], capture_output=True, text=True, timeout=10)
        ok = r.returncode == 0
        return ok, r.stdout.strip() or r.stderr.strip()
    except Exception as e:
        return False, str(e)

def ollama_chat(model, messages, num_ctx=4096):
    """Llamada directa a Ollama HTTP API — sin requests, solo urllib"""
    payload = {
        "model":    model,
        "messages": messages,
        "stream":   False,
        "options":  {"num_ctx": num_ctx},
    }
    data = json.dumps(payload).encode("utf-8")
    req  = ureq.Request(
        "http://127.0.0.1:11434/api/chat",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with ureq.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read())
            return True, result.get("message", {}).get("content", "")
    except Exception as e:
        return False, str(e)

# ── SSH info ──────────────────────────────────────────────────

def ssh_info():
    ip   = get_ip()
    port = "8022"
    user = os.environ.get("USER", "u0_a")
    keys = 0
    auth_keys = os.path.join(HOME, ".ssh", "authorized_keys")
    try:
        with open(auth_keys) as f:
            keys = sum(1 for l in f if l.strip() and not l.startswith("#"))
    except:
        pass
    cmd     = f"ssh -p {port} {user}@{ip}"
    scp_cmd = f"scp -P {port} archivo.txt {user}@{ip}:~/"
    return {"ip": ip, "port": port, "user": user, "keys": keys, "cmd": cmd, "scp_cmd": scp_cmd}

# ── Acciones start / stop ─────────────────────────────────────

def do_start(module_id):
    scripts = {
        "n8n":    os.path.join(HOME, "start_servidor.sh"),
        "ollama": os.path.join(HOME, "ollama_start.sh"),
        "ssh":    None,
    }
    if module_id == "ssh":
        try:
            subprocess.Popen(
                [os.path.join(TERMUX_PREFIX, "bin", "sshd")],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            log_action(module_id, "start", True)
            return True, "sshd iniciado"
        except Exception as e:
            log_action(module_id, "start", False, str(e))
            return False, str(e)

    script = scripts.get(module_id)
    if not script or not os.path.exists(script):
        msg = f"Script de inicio no encontrado para {module_id}"
        log_action(module_id, "start", False, msg)
        return False, msg
    try:
        subprocess.Popen(["bash", script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log_action(module_id, "start", True)
        return True, f"{module_id} iniciando..."
    except Exception as e:
        log_action(module_id, "start", False, str(e))
        return False, str(e)

def do_stop(module_id):
    patterns = {"n8n": "n8n", "ollama": "ollama", "ssh": "sshd"}
    pattern  = patterns.get(module_id)
    if not pattern:
        return False, "Módulo no controlable"
    try:
        subprocess.run(["pkill", "-f", pattern], timeout=5)
        log_action(module_id, "stop", True)
        return True, f"{module_id} detenido"
    except Exception as e:
        log_action(module_id, "stop", False, str(e))
        return False, str(e)

def do_backup():
    script = os.path.join(HOME, "backup.sh")
    if not os.path.exists(script):
        return False, "backup.sh no encontrado en ~/"
    try:
        subprocess.Popen(["bash", script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log_action("system", "backup", True)
        return True, "Backup iniciado en background → /sdcard/termux-backup/"
    except Exception as e:
        log_action("system", "backup", False, str(e))
        return False, str(e)

# ── Chat history (SQLite — ARM64 safe) ───────────────────────

def init_chat_db():
    conn = sqlite3.connect(BOT_HISTORY_DB)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS historial (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id TEXT NOT NULL,
            rol     TEXT NOT NULL,
            content TEXT NOT NULL,
            modelo  TEXT,
            fecha   TEXT
        )
    """)
    conn.commit()
    conn.close()

init_chat_db()

def chat_history(chat_id, limit=10):
    try:
        conn = sqlite3.connect(BOT_HISTORY_DB)
        conn.row_factory = sqlite3.Row
        cur  = conn.execute(
            "SELECT rol, content FROM historial WHERE chat_id=? ORDER BY id DESC LIMIT ?",
            (chat_id, limit)
        )
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        rows.reverse()
        return rows
    except:
        return []

def chat_save(chat_id, model, user_text, bot_text):
    try:
        ts   = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        conn = sqlite3.connect(BOT_HISTORY_DB)
        conn.execute(
            "INSERT INTO historial (chat_id, rol, content, modelo, fecha) VALUES (?,?,?,?,?)",
            (chat_id, "user", user_text, model, ts)
        )
        conn.execute(
            "INSERT INTO historial (chat_id, rol, content, modelo, fecha) VALUES (?,?,?,?,?)",
            (chat_id, "assistant", bot_text, model, ts)
        )
        conn.commit()
        conn.close()
    except:
        pass

# ── HTTP Handler ──────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        pass  # Silenciar logs de acceso

    def send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type",  "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin",  "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin",  "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        raw    = self.rfile.read(length) if length > 0 else b""
        try:
            return json.loads(raw.decode("utf-8"))
        except:
            return {}

    def do_GET(self):
        parsed = urlparse(self.path)
        path   = parsed.path
        params = parse_qs(parsed.query)

        # ── /api/status ───────────────────────────
        if path == "/api/status":
            self.send_json(build_status())

        # ── /api/logs ─────────────────────────────
        elif path == "/api/logs":
            self.send_json({"logs": list(_cmd_log)})

        # ── /api/ollama/models ────────────────────
        elif path == "/api/ollama/models":
            self.send_json({"models": ollama_list()})

        # ── /api/ssh/info ─────────────────────────
        elif path == "/api/ssh/info":
            self.send_json(ssh_info())

        # ── /api/n8n/url ──────────────────────────
        elif path == "/api/n8n/url":
            self.send_json({"url": get_n8n_url()})

        # ── /api/n8n/info ─────────────────────────
        elif path == "/api/n8n/info":
            url      = get_n8n_url()
            has_tok  = os.path.isfile(os.path.join(HOME, ".cf_token")) and \
                       os.path.getsize(os.path.join(HOME, ".cf_token")) > 0
            # Leer webhook_url de ~/.env_n8n
            webhook  = ""
            env_path = os.path.join(HOME, ".env_n8n")
            try:
                with open(env_path) as f:
                    for line in f:
                        if line.startswith("N8N_WEBHOOK_URL="):
                            webhook = line.strip().split("=", 1)[1]
            except:
                pass
            self.send_json({
                "url":         url,
                "cf_mode":     "fija" if has_tok else "temporal",
                "webhook_url": webhook,
            })

        # ── /api/n8n/logs ─────────────────────────
        elif path == "/api/n8n/logs":
            logs = ""
            try:
                # Intentar leer log de n8n desde el proot
                r = subprocess.run(
                    ["proot-distro", "login", "debian", "--",
                     "bash", "-c", "tail -n 50 /root/.n8n/n8n.log 2>/dev/null || echo '[sin log]'"],
                    capture_output=True, text=True, timeout=8
                )
                logs = r.stdout.strip() or r.stderr.strip() or "[sin output]"
            except:
                # Fallback: leer log de start desde home
                try:
                    log_path = os.path.join(HOME, "n8n_start.log")
                    with open(log_path) as f:
                        lines = f.readlines()
                    logs = "".join(lines[-50:]).strip()
                except:
                    logs = "[Logs no disponibles — n8n debe estar corriendo]"
            self.send_json({"logs": logs})

        # ── /api/chat/history ─────────────────────
        elif path == "/api/chat/history":
            chat_id = params.get("chat_id", ["app_local"])[0]
            limit   = int(params.get("limit", ["20"])[0])
            self.send_json({"messages": chat_history(chat_id, limit)})

        # ── / (index.html) ────────────────────────
        elif path == "/":
            index = os.path.join(HOME, "python", "dashboard", "index.html")
            if not os.path.exists(index):
                index = os.path.join(HOME, "dashboard", "index.html")
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            if os.path.exists(index):
                with open(index, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.wfile.write(b"<h1>Dashboard API v2.0.0</h1>")

        else:
            self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path   = parsed.path
        body   = self.read_body()

        # ── /api/action ───────────────────────────
        if path == "/api/action":
            module = body.get("module", "")
            action = body.get("action", "")

            if action == "start":
                ok, msg = do_start(module)
            elif action == "stop":
                ok, msg = do_stop(module)
            elif action == "backup" or module == "system":
                ok, msg = do_backup()
            elif action.startswith("pull:"):
                model_name = action[5:]
                ok, msg = ollama_pull(model_name)
                log_action("ollama", f"pull:{model_name}", ok, msg)
            elif action.startswith("delete:"):
                model_name = action[7:]
                ok, msg = ollama_delete(model_name)
                log_action("ollama", f"delete:{model_name}", ok, msg)
            else:
                ok, msg = False, f"Acción desconocida: {action}"

            self.send_json({"ok": ok, "msg": msg})

        # ── /api/chat ─────────────────────────────
        elif path == "/api/chat":
            model   = body.get("model", "qwen2.5:0.5b")
            message = body.get("message", "")
            chat_id = body.get("chat_id", "app_local")
            num_ctx = int(body.get("num_ctx", 4096))

            if not message:
                self.send_json({"ok": False, "error": "message vacío"}, 400)
                return

            # Recuperar historial
            history = chat_history(chat_id, limit=10)
            messages = [{"role": r["rol"], "content": r["content"]} for r in history]
            messages.append({"role": "user", "content": message})

            ok, response = ollama_chat(model, messages, num_ctx)
            if ok:
                chat_save(chat_id, model, message, response)
                self.send_json({"ok": True, "response": response})
            else:
                self.send_json({"ok": False, "error": response}, 500)

        # ── /api/chat/clear ───────────────────────
        elif path == "/api/chat/clear":
            chat_id = body.get("chat_id", "app_local")
            try:
                conn = sqlite3.connect(BOT_HISTORY_DB)
                conn.execute("DELETE FROM historial WHERE chat_id=?", (chat_id,))
                conn.commit()
                conn.close()
                self.send_json({"ok": True})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)

        # ── /api/n8n/token ────────────────────────
        elif path == "/api/n8n/token":
            token  = body.get("token", "").strip()
            remove = body.get("remove", False)
            cf_tok_path = os.path.join(HOME, ".cf_token")
            try:
                if remove or not token:
                    # Quitar token → URL temporal
                    if os.path.exists(cf_tok_path):
                        os.remove(cf_tok_path)
                    self.send_json({"ok": True, "msg": "Token eliminado — modo URL temporal activado"})
                else:
                    with open(cf_tok_path, "w") as f:
                        f.write(token)
                    os.chmod(cf_tok_path, 0o600)
                    self.send_json({"ok": True, "msg": "Token guardado — URL fija activada. Reinicia n8n."})
            except Exception as e:
                self.send_json({"ok": False, "msg": str(e)}, 500)

        # ── /api/n8n/webhook ──────────────────────
        elif path == "/api/n8n/webhook":
            webhook_url = body.get("webhook_url", "").strip()
            if not webhook_url:
                self.send_json({"ok": False, "msg": "webhook_url vacío"}, 400)
                return
            env_path = os.path.join(HOME, ".env_n8n")
            try:
                lines = []
                try:
                    with open(env_path) as f:
                        lines = f.readlines()
                except:
                    pass
                new_lines = []
                found = False
                for line in lines:
                    if line.startswith("N8N_WEBHOOK_URL="):
                        new_lines.append(f"N8N_WEBHOOK_URL={webhook_url}\n")
                        found = True
                    else:
                        new_lines.append(line)
                if not found:
                    new_lines.append(f"N8N_WEBHOOK_URL={webhook_url}\n")
                with open(env_path, "w") as f:
                    f.writelines(new_lines)
                log_action("n8n", "webhook_url", True, webhook_url)
                self.send_json({"ok": True, "msg": "Webhook URL guardada. Reinicia n8n para aplicar."})
            except Exception as e:
                self.send_json({"ok": False, "msg": str(e)}, 500)

        # ── /api/claude/config ────────────────────
        elif path == "/api/claude/config":
            api_key  = body.get("api_key", "")
            endpoint = body.get("endpoint", "")
            if api_key:
                write_registry("claude_code.api_key", api_key)
                # Escribir también en ~/.claude_api_key por compatibilidad con claude CLI
                try:
                    with open(os.path.join(HOME, ".claude_api_key"), "w") as f:
                        f.write(api_key)
                except:
                    pass
            if endpoint:
                write_registry("claude_code.endpoint", endpoint)
            self.send_json({"ok": True, "msg": "Configuración guardada"})

        else:
            self.send_json({"error": "not found"}, 404)


if __name__ == "__main__":
    print(f"[dashboard] v2.0.0 iniciando en puerto {PORT}...")
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
    print("[dashboard] Servidor detenido.")

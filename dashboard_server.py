#!/usr/bin/env python3
# termux-ai-stack · dashboard_server.py
# v2.3.0 | Mayo 2026
# S14: /api/claude/projects
# S15: WebSocket PTY (:8081) + /api/claude/download-dirs + /api/claude/project/create + delete

import os, json, subprocess, collections, shutil, sqlite3, threading, struct, fcntl, termios, pty, select, signal
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from urllib import request as ureq
from datetime import datetime

HOME          = os.path.expanduser("~")
REGISTRY_FILE = os.path.join(HOME, ".android_server_registry")
TERMUX_PREFIX = os.environ.get("TERMUX_PREFIX", "/data/data/com.termux/files/usr")
PORT          = 8080
PORT_WS       = 8081  # WebSocket PTY server

BOT_HISTORY_DB = os.path.join(HOME, "bot_history.db")
PREFS_FILE     = os.path.join(HOME, "ui_prefs.json")
_cmd_log       = collections.deque(maxlen=30)
_chat_jobs     = {}   # {job_id: {status, response, error}}

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
        module("n8n",    "n8n",         ["n8n.installed"],          ["n8n.version","n8n_version"],     True, "node.*n8n"),
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
    # Patrones específicos — evitan matar procesos no relacionados
    patterns = {"n8n": "node.*n8n", "ollama": "ollama serve", "ssh": "sshd"}
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


# ── Preferencias UI ───────────────────────────────────────────

def load_prefs():
    try:
        if os.path.exists(PREFS_FILE):
            with open(PREFS_FILE, "r") as f:
                return json.load(f)
    except Exception:
        pass
    return {"theme": "noche"}

def save_prefs(data):
    try:
        existing = load_prefs()
        existing.update(data)
        with open(PREFS_FILE, "w") as f:
            json.dump(existing, f)
    except Exception:
        pass

# ── Chat asíncrono ────────────────────────────────────────────

def _run_chat_job(job_id, model, messages, num_ctx, chat_id, user_text):
    """Ejecuta ollama_chat en un hilo separado — no bloquea el servidor HTTP"""
    _chat_jobs[job_id] = {"status": "processing", "response": None, "error": None}
    try:
        ok, response = ollama_chat(model, messages, num_ctx)
        if ok:
            chat_save(chat_id, model, user_text, response)
            _chat_jobs[job_id] = {"status": "done", "response": response, "error": None}
        else:
            _chat_jobs[job_id] = {"status": "error", "response": None, "error": response}
    except Exception as e:
        _chat_jobs[job_id] = {"status": "error", "response": None, "error": str(e)}

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

        # ── /api/claude/projects ─────────────────
        elif path == "/api/claude/projects":
            proj_dir = os.path.join(HOME, "proyectos")
            projects = []
            try:
                for name in sorted(os.listdir(proj_dir)):
                    full = os.path.join(proj_dir, name)
                    is_link = os.path.islink(full)
                    target = ""
                    if is_link:
                        try: target = os.readlink(full)
                        except: pass
                    projects.append({"name": name, "is_symlink": is_link, "target": target})
            except: pass
            self.send_json({"projects": projects})

        # ── /api/claude/download-dirs ─────────────
        elif path == "/api/claude/download-dirs":
            dl_path = "/storage/emulated/0/Download"
            dirs = []
            try:
                for name in sorted(os.listdir(dl_path)):
                    full = os.path.join(dl_path, name)
                    if os.path.isdir(full):
                        dirs.append(name)
            except: pass
            self.send_json({"dirs": dirs})

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

        # ── /api/chat/status/<job_id> ─────────────
        elif path.startswith("/api/chat/status/"):
            job_id = path.split("/api/chat/status/")[-1]
            job    = _chat_jobs.get(job_id)
            if not job:
                self.send_json({"status": "not_found"}, 404)
            else:
                self.send_json(job)
                # Limpiar jobs completados después de entregarlos
                if job["status"] in ("done", "error"):
                    _chat_jobs.pop(job_id, None)

        # ── /api/prefs ────────────────────────────
        elif path == "/api/prefs":
            self.send_json(load_prefs())

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
        # Ahora async: responde inmediato con job_id
        # La app hace polling a GET /api/chat/status/<job_id>
        elif path == "/api/chat":
            model   = body.get("model", "qwen2.5:0.5b")
            message = body.get("message", "")
            chat_id = body.get("chat_id", "app_local")
            num_ctx = int(body.get("num_ctx", 4096))

            if not message:
                self.send_json({"ok": False, "error": "message vacío"}, 400)
                return

            # Generar job_id único — datetime sin /tmp ni os.urandom
            job_id = "job_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f")

            # Recuperar historial y preparar mensajes
            history  = chat_history(chat_id, limit=10)
            messages = [{"role": r["rol"], "content": r["content"]} for r in history]
            messages.append({"role": "user", "content": message})

            # Guardar el mensaje del usuario en SQLite inmediatamente
            ts   = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            try:
                conn = sqlite3.connect(BOT_HISTORY_DB)
                conn.execute(
                    "INSERT INTO historial (chat_id, rol, content, modelo, fecha) VALUES (?,?,?,?,?)",
                    (chat_id, "user", message, model, ts)
                )
                conn.commit()
                conn.close()
            except Exception:
                pass

            # Lanzar ollama en hilo separado — no bloquea el servidor
            t = threading.Thread(
                target=_run_chat_job,
                args=(job_id, model, messages, num_ctx, chat_id, message),
                daemon=True
            )
            t.start()

            # Responder inmediato — la app hace polling
            self.send_json({"ok": True, "job_id": job_id, "status": "processing"})

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
                    try:
                        os.chmod(cf_tok_path, 0o600)  # Opcional — puede fallar en Android 15/SELinux
                    except:
                        pass
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

        # ── /api/claude/project/create ───────────
        elif path == "/api/claude/project/create":
            name = body.get("name", "").strip()
            if not name:
                self.send_json({"ok": False, "msg": "nombre vacío"}, 400)
                return
            proj_dir = os.path.join(HOME, "proyectos")
            dl_path  = "/storage/emulated/0/Download"
            src  = os.path.join(dl_path, name)
            dst  = os.path.join(proj_dir, name)
            try:
                os.makedirs(proj_dir, exist_ok=True)
                if os.path.exists(dst) or os.path.islink(dst):
                    self.send_json({"ok": False, "msg": f"Ya existe: ~/proyectos/{name}"})
                    return
                os.symlink(src, dst)
                self.send_json({"ok": True, "msg": f"Symlink creado: ~/proyectos/{name} → {src}"})
            except Exception as e:
                self.send_json({"ok": False, "msg": str(e)}, 500)

        # ── /api/claude/project/delete ───────────
        elif path == "/api/claude/project/delete":
            name = body.get("name", "").strip()
            if not name or "/" in name or ".." in name:
                self.send_json({"ok": False, "msg": "nombre inválido"}, 400)
                return
            target = os.path.join(HOME, "proyectos", name)
            try:
                if os.path.islink(target):
                    os.remove(target)
                    self.send_json({"ok": True, "msg": f"Symlink eliminado: {name}"})
                else:
                    self.send_json({"ok": False, "msg": "No es un symlink"})
            except Exception as e:
                self.send_json({"ok": False, "msg": str(e)}, 500)

        # ── /api/prefs ────────────────────────────
        elif path == "/api/prefs":
            try:
                save_prefs(body)
                self.send_json({"ok": True})
            except Exception as e:
                self.send_json({"ok": False, "msg": str(e)}, 500)

        else:
            self.send_json({"error": "not found"}, 404)


# ── WebSocket PTY Server (:8081) ──────────────────────────────

WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def ws_handshake(conn, key):
    import base64, hashlib
    accept = base64.b64encode(hashlib.sha1((key + WS_MAGIC).encode()).digest()).decode()
    response = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: " + accept + "\r\n\r\n"
    )
    conn.sendall(response.encode())

def ws_recv_frame(conn):
    try:
        header = b""
        while len(header) < 2:
            chunk = conn.recv(2 - len(header))
            if not chunk: return None, None
            header += chunk
        b0, b1 = header[0], header[1]
        opcode = b0 & 0x0F
        masked  = (b1 & 0x80) != 0
        plen    = b1 & 0x7F
        if plen == 126:
            ext = b""
            while len(ext) < 2: ext += conn.recv(2 - len(ext))
            plen = struct.unpack("!H", ext)[0]
        elif plen == 127:
            ext = b""
            while len(ext) < 8: ext += conn.recv(8 - len(ext))
            plen = struct.unpack("!Q", ext)[0]
        mask_key = b""
        if masked:
            while len(mask_key) < 4: mask_key += conn.recv(4 - len(mask_key))
        payload = b""
        while len(payload) < plen:
            chunk = conn.recv(plen - len(payload))
            if not chunk: return None, None
            payload += chunk
        if masked:
            payload = bytes(payload[i] ^ mask_key[i % 4] for i in range(len(payload)))
        return opcode, payload
    except: return None, None

def ws_send_text(conn, data):
    try:
        if isinstance(data, str):
            data = data.encode("utf-8", errors="replace")
        length = len(data)
        if length <= 125:
            header = bytes([0x81, length])
        elif length <= 65535:
            header = struct.pack("!BBH", 0x81, 126, length)
        else:
            header = struct.pack("!BBQ", 0x81, 127, length)
        frame = header + data
        # Enviar en modo blocking temporalmente para evitar pérdida de datos
        import socket as _sock
        try:
            conn.setblocking(True)
            conn.sendall(frame)
        finally:
            conn.setblocking(False)
    except Exception:
        pass

def find_claude_cli():
    """Localiza cli.js de Claude Code — misma lógica que menu.sh"""
    candidates = [
        "/data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js",
        os.path.join(HOME, ".npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js"),
        os.path.join(HOME, ".node_modules/@anthropic-ai/claude-code/cli.js"),
    ]
    # Intentar leer ruta desde el wrapper /usr/bin/claude
    wrapper = "/data/data/com.termux/files/usr/bin/claude"
    try:
        with open(wrapper) as f:
            for line in f:
                if "cli.js" in line and "node" in line:
                    import re
                    m = re.search(r'(/[^\s"]+cli\.js)', line)
                    if m and os.path.isfile(m.group(1)):
                        return m.group(1)
    except: pass
    for p in candidates:
        if os.path.isfile(p):
            return p
    return None

def handle_ws_client(conn, addr):
    try:
        # HTTP upgrade — leer request completo
        request = b""
        while b"\r\n\r\n" not in request:
            chunk = conn.recv(4096)
            if not chunk: return
            request += chunk

        req_str = request.decode("utf-8", errors="replace")
        lines   = req_str.split("\r\n")

        ws_key      = ""
        project_dir = None
        cols, rows  = 80, 30

        # Extraer key y query string de la primera línea (GET /ws?project=xxx HTTP/1.1)
        first_line = lines[0] if lines else ""
        import urllib.parse as _up
        if " " in first_line:
            path_part = first_line.split(" ")[1]  # /ws?project=xxx
            if "?" in path_part:
                qs = _up.parse_qs(_up.urlparse(path_part).query)
                project_dir = qs.get("project", [None])[0]
                if project_dir: project_dir = project_dir.strip() or None
                cols = int(qs.get("cols", [80])[0])
                rows = int(qs.get("rows", [30])[0])

        for line in lines:
            if line.lower().startswith("sec-websocket-key:"):
                ws_key = line.split(":", 1)[1].strip()
                break

        if not ws_key:
            conn.close(); return

        ws_handshake(conn, ws_key)
        conn.setblocking(False)
        print(f"[ws-pty] cliente conectado — proyecto: {project_dir!r} cols:{cols} rows:{rows}")

        # Resolver comando y directorio de trabajo
        node_bin = "/data/data/com.termux/files/usr/bin/node"
        cli_js   = find_claude_cli()

        if not cli_js or not os.path.isfile(cli_js):
            ws_send_text(conn, b"\x1b[31m[ERROR] claude cli.js no encontrado\x1b[0m\r\n")
            ws_send_text(conn, b"\x1b[33mReinstala Claude Code desde el menu de Termux\x1b[0m\r\n")
            conn.close(); return

        # Directorio de trabajo
        work_dir = HOME
        if project_dir and os.path.isdir(project_dir):
            work_dir = project_dir
        elif project_dir:
            # Intentar resolver como nombre relativo a ~/proyectos/
            candidate = os.path.join(HOME, "proyectos", project_dir)
            if os.path.isdir(candidate):
                work_dir = candidate

        # Spawn Claude Code en PTY
        cmd = [node_bin, cli_js]
        env = os.environ.copy()
        env["TERM"]                 = "xterm-256color"
        env["LANG"]                 = "en_US.UTF-8"
        env["DISABLE_AUTOUPDATER"]  = "1"
        env["DISABLE_UPDATES"]      = "1"
        env["HOME"]                 = HOME

        master_fd, slave_fd = pty.openpty()
        # Configurar tamaño inicial del PTY
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

        proc = subprocess.Popen(
            cmd,
            stdin=slave_fd, stdout=slave_fd, stderr=slave_fd,
            close_fds=True, env=env, cwd=work_dir,
            preexec_fn=os.setsid,
        )
        os.close(slave_fd)
        # conn ya es non-blocking desde el handshake
        # ws_send_text maneja errores internamente

        def pty_to_ws():
            while proc.poll() is None:
                try:
                    r, _, _ = select.select([master_fd], [], [], 0.05)
                    if r:
                        try:
                            data = os.read(master_fd, 4096)
                            ws_send_text(conn, data)
                        except OSError: break
                except: break
            ws_send_text(conn, b"\r\n\x1b[33m[sesion terminada]\x1b[0m\r\n")
            try: conn.close()
            except: pass

        threading.Thread(target=pty_to_ws, daemon=True).start()

        while proc.poll() is None:
            try:
                r, _, _ = select.select([conn], [], [], 0.1)
                if not r: continue
                opcode, payload = ws_recv_frame(conn)
                if opcode is None or opcode == 8:
                    break
                if opcode == 1 and payload:
                    try:
                        msg = json.loads(payload.decode("utf-8"))
                        if msg.get("type") == "input":
                            os.write(master_fd, msg["data"].encode("utf-8", errors="replace"))
                        elif msg.get("type") == "resize":
                            cols = int(msg.get("cols", 80))
                            rows = int(msg.get("rows", 24))
                            winsize = struct.pack("HHHH", rows, cols, 0, 0)
                            fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
                    except: pass
            except (BlockingIOError, OSError): continue
            except: break

        try: proc.terminate()
        except: pass
        try: os.close(master_fd)
        except: pass
        try: conn.close()
        except: pass
    except Exception:
        try: conn.close()
        except: pass


def start_ws_server():
    """Inicia el servidor WebSocket PTY en PORT_WS"""
    import socket
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(("0.0.0.0", PORT_WS))
        srv.listen(5)
        print(f"[ws-pty] Escuchando en :{PORT_WS}")
        while True:
            try:
                conn, addr = srv.accept()
                threading.Thread(target=handle_ws_client, args=(conn, addr), daemon=True).start()
            except: break
    except Exception as e:
        print(f"[ws-pty] Error: {e}")
    finally:
        srv.close()


if __name__ == "__main__":
    print(f"[dashboard] v2.3.0 iniciando en puerto {PORT}...")
    # Iniciar WebSocket PTY en hilo separado
    ws_thread = threading.Thread(target=start_ws_server, daemon=True)
    ws_thread.start()
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
    print("[dashboard] Servidor detenido.")

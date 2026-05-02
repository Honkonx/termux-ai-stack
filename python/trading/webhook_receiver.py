#!/data/data/com.termux/files/usr/bin/python3
# python/trading/webhook_receiver.py
# termux-ai-stack — Receptor de señales MT5/EA vía HTTP
# EA en MT5 hace POST a http://IP_TERMUX:9000/senal
# REGLAS ARM64: datetime.now() · urllib · rutas $HOME · sin /tmp/

import os
import sys
import json
import sqlite3
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

HOME    = os.environ.get("HOME", "/data/data/com.termux/files/home")
DB_PATH = os.path.join(HOME, "trading", "senales.db")
LOG_PATH = os.path.join(HOME, "trading", "webhook.log")
PORT    = 9000

# ── Init BD (misma que signal_bot.py) ───────────────────────────
def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS senales (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            activo    TEXT NOT NULL,
            tipo      TEXT NOT NULL,
            entrada   REAL,
            sl        REAL,
            tp1       REAL,
            tp2       REAL,
            be        REAL,
            cierre    REAL,
            confianza INTEGER DEFAULT 0,
            resultado TEXT DEFAULT 'PENDIENTE',
            notas     TEXT DEFAULT '',
            fuente    TEXT DEFAULT 'manual',
            fecha     TEXT NOT NULL,
            fecha_cierre TEXT DEFAULT ''
        )
    """)
    # Migración: agregar columnas nuevas si BD ya existe
    for col, tipo in [("be", "REAL"), ("cierre", "REAL"),
                      ("fuente", "TEXT"), ("fecha_cierre", "TEXT")]:
        try:
            c.execute(f"ALTER TABLE senales ADD COLUMN {col} {tipo} DEFAULT ''")
        except sqlite3.OperationalError:
            pass  # columna ya existe
    conn.commit()
    conn.close()

# ── Guardar señal desde webhook ──────────────────────────────────
def guardar_senal(data):
    fecha = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        INSERT INTO senales
        (activo, tipo, entrada, sl, tp1, tp2, be, cierre, confianza,
         resultado, notas, fuente, fecha, fecha_cierre)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        data.get("activo", "UNKNOWN"),
        data.get("tipo", "BUY").upper(),
        float(data.get("entrada", 0)),
        float(data.get("sl", 0)),
        float(data.get("tp1", 0)),
        float(data.get("tp2", 0)) if data.get("tp2") else None,
        float(data.get("be", 0)) if data.get("be") else None,
        float(data.get("cierre", 0)) if data.get("cierre") else None,
        int(data.get("confianza", 0)),
        data.get("resultado", "PENDIENTE").upper(),
        data.get("notas", ""),
        data.get("fuente", "mt5_ea"),
        fecha,
        data.get("fecha_cierre", "")
    ))
    conn.commit()
    sid = c.lastrowid
    conn.close()
    return sid

# ── Actualizar señal existente (cierre, BE, resultado) ───────────
def actualizar_senal(data):
    sid = int(data.get("id", 0))
    if not sid:
        return None, "id requerido"
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id FROM senales WHERE id=?", (sid,))
    if not c.fetchone():
        conn.close()
        return None, f"señal #{sid} no encontrada"

    updates = []
    valores = []
    for campo in ["resultado", "cierre", "be", "notas", "fecha_cierre"]:
        if campo in data and data[campo] != "":
            updates.append(f"{campo}=?")
            valores.append(data[campo])
    if not updates:
        conn.close()
        return sid, "sin cambios"
    valores.append(sid)
    c.execute(f"UPDATE senales SET {', '.join(updates)} WHERE id=?", valores)
    conn.commit()
    conn.close()
    return sid, "ok"

# ── Log ──────────────────────────────────────────────────────────
def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    linea = f"[{ts}] {msg}"
    print(linea)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(linea + "\n")
    except Exception:
        pass

# ── Handler HTTP ─────────────────────────────────────────────────
class TradingHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass  # silenciar log por defecto del servidor

    def _responder(self, code, body):
        resp = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/ping":
            self._responder(200, {"status": "ok", "servidor": "trading-webhook"})

        elif path == "/senales":
            # Últimas 20 señales en JSON
            conn = sqlite3.connect(DB_PATH)
            conn.row_factory = sqlite3.Row
            c = conn.cursor()
            c.execute("""
                SELECT id, activo, tipo, entrada, sl, tp1, tp2, be, cierre,
                       resultado, fuente, fecha, fecha_cierre
                FROM senales ORDER BY id DESC LIMIT 20
            """)
            rows = [dict(r) for r in c.fetchall()]
            conn.close()
            self._responder(200, {"senales": rows, "total": len(rows)})

        elif path == "/stats":
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute("SELECT COUNT(*) FROM senales")
            total = c.fetchone()[0]
            c.execute("SELECT COUNT(*) FROM senales WHERE resultado='WIN'")
            wins = c.fetchone()[0]
            c.execute("SELECT COUNT(*) FROM senales WHERE resultado='LOSS'")
            losses = c.fetchone()[0]
            c.execute("SELECT COUNT(*) FROM senales WHERE resultado='PENDIENTE'")
            pend = c.fetchone()[0]
            conn.close()
            wr = round(wins/(wins+losses)*100, 1) if (wins+losses) > 0 else 0.0
            self._responder(200, {
                "total": total, "wins": wins, "losses": losses,
                "pendientes": pend, "winrate": wr
            })
        else:
            self._responder(404, {"error": "ruta no encontrada"})

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        if length > 4096:
            self._responder(400, {"error": "payload muy grande"})
            return
        try:
            raw = self.rfile.read(length)
            data = json.loads(raw.decode("utf-8"))
        except Exception as e:
            self._responder(400, {"error": f"JSON inválido: {e}"})
            return

        if path == "/senal":
            # Nueva señal desde EA
            if not data.get("activo") or not data.get("tipo"):
                self._responder(400, {"error": "activo y tipo requeridos"})
                return
            sid = guardar_senal(data)
            log(f"NUEVA señal #{sid} | {data.get('activo')} {data.get('tipo')} @ {data.get('entrada')}")
            self._responder(201, {"ok": True, "id": sid})

        elif path == "/actualizar":
            # Actualizar señal (cierre, BE, resultado)
            sid, msg = actualizar_senal(data)
            if sid:
                log(f"UPDATE señal #{sid} | {msg} | resultado={data.get('resultado','-')} cierre={data.get('cierre','-')}")
                self._responder(200, {"ok": True, "id": sid, "msg": msg})
            else:
                self._responder(400, {"error": msg})
        else:
            self._responder(404, {"error": "ruta no encontrada"})


# ── Main ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    init_db()

    if len(sys.argv) > 1 and sys.argv[1] == "test":
        # Modo test: insertar señal de prueba y salir
        sid = guardar_senal({
            "activo": "GainX 500", "tipo": "BUY",
            "entrada": 1234.5, "sl": 1200.0, "tp1": 1280.0,
            "confianza": 8, "fuente": "test"
        })
        print(f"  [TEST] Señal #{sid} insertada OK")
        sys.exit(0)

    log(f"Servidor trading webhook iniciado en :{PORT}")
    log(f"BD: {DB_PATH}")
    log("Endpoints:")
    log("  GET  /ping          → health check")
    log("  GET  /senales       → últimas 20 señales (JSON)")
    log("  GET  /stats         → estadísticas")
    log("  POST /senal         → nueva señal desde EA")
    log("  POST /actualizar    → actualizar cierre/BE/resultado")
    log("Ctrl+C para detener")

    try:
        server = HTTPServer(("0.0.0.0", PORT), TradingHandler)
        server.serve_forever()
    except KeyboardInterrupt:
        log("Servidor detenido")
    except OSError as e:
        print(f"  [ERROR] Puerto {PORT} ocupado: {e}")
        print(f"  Verifica con: lsof -i :{PORT}")
        sys.exit(1)

#!/data/data/com.termux/files/usr/bin/python3
# python/trading/webhook_receiver.py v4
# termux-ai-stack — Receptor de señales MT5/EA vía HTTP
# v2: log rotativo + GET /senal/<id>
# v3: duracion_min + pips por activo
# v4: tabla activos (categoría/broker) + campo tipo_senal
# REGLAS ARM64: datetime.now() · urllib · rutas $HOME · sin /tmp/

import os
import sys
import json
import sqlite3
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# ── Multiplicadores de pips por tipo de activo ───────────────────
PIP_MULT = {
    # Sintéticos Deriv
    "BOOM500": 1, "BOOM1000": 1, "CRASH500": 1, "CRASH1000": 1,
    "GAINX500": 1, "GAINX800": 1, "PAINX500": 1, "PAINX800": 1,
    # Sintéticos con espacio (Weltrade)
    "GAINX 500": 1, "GAINX 800": 1, "PAINX 500": 1, "PAINX 800": 1,
    "BOOM 500": 1, "BOOM 1000": 1, "CRASH 500": 1, "CRASH 1000": 1,
    # FX
    "EURUSD": 10000, "GBPUSD": 10000, "AUDUSD": 10000,
    "NZDUSD": 10000, "USDCAD": 10000, "USDCHF": 10000,
    "USDJPY": 100, "EURJPY": 100, "GBPJPY": 100,
    # Metales
    "XAUUSD": 100, "XAGUSD": 100,
    # Índices
    "US30": 1, "US500": 1, "NAS100": 1, "GER40": 1,
}

def get_pip_mult(activo, override=None):
    if override and float(override) > 0:
        return float(override)
    # Consultar tabla activos primero (fuente de verdad)
    try:
        conn = sqlite3.connect(DB_PATH)
        c    = conn.cursor()
        c.execute("SELECT pip_mult FROM activos WHERE simbolo=? AND activo=1",
                  (activo.strip(),))
        row = c.fetchone()
        conn.close()
        if row and row[0]:
            return float(row[0])
    except Exception:
        pass
    # Fallback al diccionario hardcoded
    return PIP_MULT.get(activo.upper().strip(), 1)

def calcular_pips(activo, entrada, cierre, tipo, pip_mult_override=None):
    try:
        mult = get_pip_mult(activo, pip_mult_override)
        if tipo.upper() == "BUY":
            return round((float(cierre) - float(entrada)) * mult, 2)
        else:
            return round((float(entrada) - float(cierre)) * mult, 2)
    except Exception:
        return None

def calcular_duracion(fecha_apertura, fecha_cierre):
    try:
        fmt = "%Y-%m-%d %H:%M:%S"
        delta = datetime.strptime(fecha_cierre, fmt) - datetime.strptime(fecha_apertura, fmt)
        return max(0, int(delta.total_seconds() / 60))
    except Exception:
        return None

HOME     = os.environ.get("HOME", "/data/data/com.termux/files/home")
DB_PATH  = os.path.join(HOME, "trading", "senales.db")
LOG_PATH = os.path.join(HOME, "trading", "webhook.log")
PORT     = 9000
LOG_MAX  = 500  # líneas máximas antes de rotar

# ── Log rotativo ─────────────────────────────────────────────────
def log(msg):
    ts    = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    linea = f"[{ts}] {msg}"
    print(linea)
    try:
        # Leer líneas actuales
        lineas = []
        if os.path.exists(LOG_PATH):
            with open(LOG_PATH, "r") as f:
                lineas = f.readlines()
        # Rotar si supera el límite
        if len(lineas) >= LOG_MAX:
            # Conservar la última mitad + nueva línea
            lineas = lineas[-(LOG_MAX // 2):]
            lineas.insert(0, f"[{ts}] [LOG ROTADO — se conservan últimas {LOG_MAX // 2} líneas]\n")
        lineas.append(linea + "\n")
        with open(LOG_PATH, "w") as f:
            f.writelines(lineas)
    except Exception:
        pass

# ── Init BD ──────────────────────────────────────────────────────
def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # ── Tabla senales ────────────────────────────────────────────
    c.execute("""
        CREATE TABLE IF NOT EXISTS senales (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            activo       TEXT NOT NULL,
            tipo         TEXT NOT NULL,
            tipo_senal   TEXT DEFAULT 'manual',
            entrada      REAL,
            sl           REAL,
            tp1          REAL,
            tp2          REAL,
            be           REAL,
            cierre       REAL,
            pips         REAL,
            duracion_min INTEGER,
            confianza    INTEGER DEFAULT 0,
            resultado    TEXT DEFAULT 'PENDIENTE',
            notas        TEXT DEFAULT '',
            fuente       TEXT DEFAULT 'manual',
            fecha        TEXT NOT NULL,
            fecha_cierre TEXT DEFAULT ''
        )
    """)

    # ── Migración: columnas nuevas si BD ya existe ───────────────
    cols_nuevas = [
        ("be", "REAL"), ("cierre", "REAL"), ("fuente", "TEXT"),
        ("fecha_cierre", "TEXT"), ("duracion_min", "INTEGER"),
        ("pips", "REAL"), ("tipo_senal", "TEXT")
    ]
    for col, tipo in cols_nuevas:
        try:
            c.execute(f"ALTER TABLE senales ADD COLUMN {col} {tipo} DEFAULT ''")
        except sqlite3.OperationalError:
            pass  # ya existe

    # ── Tabla activos ────────────────────────────────────────────
    # Centraliza metadatos de activos: categoría, broker, pip_mult
    c.execute("""
        CREATE TABLE IF NOT EXISTS activos (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            simbolo     TEXT NOT NULL UNIQUE,
            nombre      TEXT DEFAULT '',
            categoria   TEXT NOT NULL,
            broker      TEXT DEFAULT '',
            pip_mult    REAL DEFAULT 1,
            activo      INTEGER DEFAULT 1,
            notas       TEXT DEFAULT ''
        )
    """)

    # ── Seed tabla activos (solo si está vacía) ──────────────────
    c.execute("SELECT COUNT(*) FROM activos")
    if c.fetchone()[0] == 0:
        seed = [
            # (simbolo, nombre, categoria, broker, pip_mult)
            # Sintéticos Deriv
            ("BOOM500",   "Boom 500 Index",    "sintetico_deriv",    "Deriv",    1),
            ("BOOM1000",  "Boom 1000 Index",   "sintetico_deriv",    "Deriv",    1),
            ("CRASH500",  "Crash 500 Index",   "sintetico_deriv",    "Deriv",    1),
            ("CRASH1000", "Crash 1000 Index",  "sintetico_deriv",    "Deriv",    1),
            ("GAINX500",  "GainX 500 Index",   "sintetico_deriv",    "Deriv",    1),
            ("GAINX800",  "GainX 800 Index",   "sintetico_deriv",    "Deriv",    1),
            ("PAINX500",  "PainX 500 Index",   "sintetico_deriv",    "Deriv",    1),
            ("PAINX800",  "PainX 800 Index",   "sintetico_deriv",    "Deriv",    1),
            # Sintéticos Weltrade (mismo activo, distinto broker)
            ("GAINX 500", "GainX 500",         "sintetico_weltrade", "Weltrade", 1),
            ("GAINX 800", "GainX 800",         "sintetico_weltrade", "Weltrade", 1),
            ("PAINX 500", "PainX 500",         "sintetico_weltrade", "Weltrade", 1),
            ("PAINX 800", "PainX 800",         "sintetico_weltrade", "Weltrade", 1),
            ("BOOM 500",  "Boom 500",          "sintetico_weltrade", "Weltrade", 1),
            ("BOOM 1000", "Boom 1000",         "sintetico_weltrade", "Weltrade", 1),
            ("CRASH 500", "Crash 500",         "sintetico_weltrade", "Weltrade", 1),
            ("CRASH 1000","Crash 1000",        "sintetico_weltrade", "Weltrade", 1),
            # FX Majors
            ("EURUSD", "Euro / US Dollar",     "forex",              "MT5",   10000),
            ("GBPUSD", "Pound / US Dollar",    "forex",              "MT5",   10000),
            ("AUDUSD", "Aussie / US Dollar",   "forex",              "MT5",   10000),
            ("NZDUSD", "Kiwi / US Dollar",     "forex",              "MT5",   10000),
            ("USDCAD", "US Dollar / CAD",      "forex",              "MT5",   10000),
            ("USDCHF", "US Dollar / CHF",      "forex",              "MT5",   10000),
            ("USDJPY", "US Dollar / Yen",      "forex",              "MT5",     100),
            ("EURJPY", "Euro / Yen",           "forex",              "MT5",     100),
            ("GBPJPY", "Pound / Yen",          "forex",              "MT5",     100),
            # Metales
            ("XAUUSD", "Gold / US Dollar",     "metal",              "MT5",     100),
            ("XAGUSD", "Silver / US Dollar",   "metal",              "MT5",     100),
            # Índices
            ("US30",   "Dow Jones",            "indice",             "MT5",       1),
            ("US500",  "S&P 500",              "indice",             "MT5",       1),
            ("NAS100", "Nasdaq 100",           "indice",             "MT5",       1),
            ("GER40",  "DAX 40",               "indice",             "MT5",       1),
        ]
        c.executemany("""
            INSERT OR IGNORE INTO activos (simbolo, nombre, categoria, broker, pip_mult)
            VALUES (?,?,?,?,?)
        """, seed)

    conn.commit()
    conn.close()

# ── Guardar señal ────────────────────────────────────────────────
def guardar_senal(data):
    fecha = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn  = sqlite3.connect(DB_PATH)
    c     = conn.cursor()
    c.execute("""
        INSERT INTO senales
        (activo, tipo, tipo_senal, entrada, sl, tp1, tp2, be, cierre,
         confianza, resultado, notas, fuente, fecha, fecha_cierre)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        data.get("activo", "UNKNOWN"),
        data.get("tipo", "BUY").upper(),
        data.get("tipo_senal", "manual"),       # manual/pre_senal/senal_completa/ea_automatico
        float(data.get("entrada", 0)),
        float(data.get("sl", 0)),
        float(data.get("tp1", 0)),
        float(data.get("tp2", 0))    if data.get("tp2")    else None,
        float(data.get("be", 0))     if data.get("be")     else None,
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

# ── Actualizar señal ─────────────────────────────────────────────
def actualizar_senal(data):
    sid = int(data.get("id", 0))
    if not sid:
        return None, "id requerido"
    conn = sqlite3.connect(DB_PATH)
    c    = conn.cursor()
    # Leer datos actuales para calcular duracion y pips
    c.execute("SELECT activo, tipo, entrada, fecha FROM senales WHERE id=?", (sid,))
    row = c.fetchone()
    if not row:
        conn.close()
        return None, f"senal #{sid} no encontrada"

    activo_db, tipo_db, entrada_db, fecha_db = row

    updates = []
    valores = []
    for campo in ["resultado", "cierre", "be", "notas", "fecha_cierre"]:
        if campo in data and data[campo] != "":
            updates.append(f"{campo}=?")
            valores.append(data[campo])

    # Calcular duracion_min si hay fecha_cierre
    fecha_cierre = data.get("fecha_cierre", "")
    if fecha_cierre and fecha_db:
        dur = calcular_duracion(fecha_db, fecha_cierre)
        if dur is not None:
            updates.append("duracion_min=?")
            valores.append(dur)

    # Calcular pips si hay cierre
    cierre = data.get("cierre")
    if cierre and entrada_db:
        pip_mult_override = data.get("pip_mult")
        pips = calcular_pips(activo_db, entrada_db, cierre, tipo_db, pip_mult_override)
        if pips is not None:
            updates.append("pips=?")
            valores.append(pips)

    if not updates:
        conn.close()
        return sid, "sin cambios"
    valores.append(sid)
    c.execute(f"UPDATE senales SET {', '.join(updates)} WHERE id=?", valores)
    conn.commit()
    conn.close()
    return sid, "ok"

# ── Obtener señal por ID ─────────────────────────────────────────
def get_senal_by_id(sid):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c    = conn.cursor()
    c.execute("""
        SELECT id, activo, tipo, entrada, sl, tp1, tp2, be, cierre,
               confianza, resultado, notas, fuente, fecha, fecha_cierre
        FROM senales WHERE id=?
    """, (sid,))
    row = c.fetchone()
    conn.close()
    return dict(row) if row else None

# ── Handler HTTP ─────────────────────────────────────────────────
class TradingHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass  # silenciar log interno del servidor

    def _responder(self, code, body):
        resp = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)

    def do_GET(self):
        path = urlparse(self.path).path

        # ── /ping ────────────────────────────────────────────────
        if path == "/ping":
            self._responder(200, {"status": "ok", "servidor": "trading-webhook", "version": "2"})

        # ── /senales ─────────────────────────────────────────────
        elif path == "/senales":
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

        # ── /senal/<id> ──────────────────────────────────────────
        elif path.startswith("/senal/"):
            partes = path.strip("/").split("/")
            # path = /senal/123 → partes = ["senal", "123"]
            if len(partes) == 2 and partes[1].isdigit():
                sid  = int(partes[1])
                data = get_senal_by_id(sid)
                if data:
                    self._responder(200, {"senal": data})
                else:
                    self._responder(404, {"error": f"senal #{sid} no encontrada"})
            else:
                self._responder(400, {"error": "uso: GET /senal/<id>"})

        # ── /stats ───────────────────────────────────────────────
        elif path == "/stats":
            conn = sqlite3.connect(DB_PATH)
            c    = conn.cursor()
            c.execute("SELECT COUNT(*) FROM senales")
            total = c.fetchone()[0]
            c.execute("SELECT COUNT(*) FROM senales WHERE resultado='WIN'")
            wins = c.fetchone()[0]
            c.execute("SELECT COUNT(*) FROM senales WHERE resultado='LOSS'")
            losses = c.fetchone()[0]
            c.execute("SELECT COUNT(*) FROM senales WHERE resultado='PENDIENTE'")
            pend = c.fetchone()[0]
            conn.close()
            wr = round(wins / (wins + losses) * 100, 1) if (wins + losses) > 0 else 0.0
            self._responder(200, {
                "total": total, "wins": wins, "losses": losses,
                "pendientes": pend, "winrate": wr
            })

        # ── /activos ─────────────────────────────────────────────
        elif path == "/activos" or path.startswith("/activos/"):
            conn = sqlite3.connect(DB_PATH)
            conn.row_factory = sqlite3.Row
            c = conn.cursor()
            # /activos/<categoria> filtra por categoría
            partes = path.strip("/").split("/")
            if len(partes) == 2 and partes[1]:
                cat = partes[1]
                c.execute("""
                    SELECT simbolo, nombre, categoria, broker, pip_mult
                    FROM activos WHERE categoria=? AND activo=1
                    ORDER BY categoria, simbolo
                """, (cat,))
            else:
                c.execute("""
                    SELECT simbolo, nombre, categoria, broker, pip_mult
                    FROM activos WHERE activo=1
                    ORDER BY categoria, simbolo
                """)
            rows = [dict(r) for r in c.fetchall()]
            conn.close()
            self._responder(200, {"activos": rows, "total": len(rows)})

        # ── /log ─────────────────────────────────────────────────
        elif path == "/log":
            try:
                if os.path.exists(LOG_PATH):
                    with open(LOG_PATH, "r") as f:
                        lineas = f.readlines()
                    # Devolver últimas 50 líneas
                    ultimas = [l.rstrip() for l in lineas[-50:]]
                    self._responder(200, {"lineas": ultimas, "total": len(lineas)})
                else:
                    self._responder(200, {"lineas": [], "total": 0})
            except Exception as e:
                self._responder(500, {"error": str(e)})

        else:
            self._responder(404, {"error": "ruta no encontrada"})

    def do_POST(self):
        path   = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        if length > 4096:
            self._responder(400, {"error": "payload muy grande"})
            return
        try:
            raw  = self.rfile.read(length)
            data = json.loads(raw.decode("utf-8"))
        except Exception as e:
            self._responder(400, {"error": f"JSON invalido: {e}"})
            return

        # ── POST /senal ──────────────────────────────────────────
        if path == "/senal":
            if not data.get("activo") or not data.get("tipo"):
                self._responder(400, {"error": "activo y tipo requeridos"})
                return
            sid = guardar_senal(data)
            log(f"NUEVA #{sid} | {data.get('activo')} {data.get('tipo')} @ {data.get('entrada')} | fuente={data.get('fuente','?')}")
            self._responder(201, {"ok": True, "id": sid})

        # ── POST /actualizar ─────────────────────────────────────
        elif path == "/actualizar":
            sid, msg = actualizar_senal(data)
            if sid:
                pips_info = f" cierre={data.get('cierre','?')}" if data.get("cierre") else ""
                log(f"UPDATE #{sid} | resultado={data.get('resultado','-')}{pips_info}")
                self._responder(200, {"ok": True, "id": sid, "msg": msg})
            else:
                self._responder(400, {"error": msg})

        # ── POST /activos ─────────────────────────────────────────
        elif path == "/activos":
            simbolo = data.get("simbolo", "").strip()
            if not simbolo:
                self._responder(400, {"error": "simbolo requerido"})
                return
            conn = sqlite3.connect(DB_PATH)
            c    = conn.cursor()
            try:
                c.execute("""
                    INSERT INTO activos (simbolo, nombre, categoria, broker, pip_mult, notas)
                    VALUES (?,?,?,?,?,?)
                    ON CONFLICT(simbolo) DO UPDATE SET
                        nombre=excluded.nombre, categoria=excluded.categoria,
                        broker=excluded.broker, pip_mult=excluded.pip_mult,
                        notas=excluded.notas, activo=1
                """, (
                    simbolo,
                    data.get("nombre", simbolo),
                    data.get("categoria", "custom"),
                    data.get("broker", ""),
                    float(data.get("pip_mult", 1)),
                    data.get("notas", "")
                ))
                conn.commit()
                log(f"ACTIVO: {simbolo} cat={data.get('categoria','custom')} pip={data.get('pip_mult',1)}")
                self._responder(201, {"ok": True, "simbolo": simbolo})
            except Exception as e:
                self._responder(500, {"error": str(e)})
            finally:
                conn.close()

        else:
            self._responder(404, {"error": "ruta no encontrada"})


# ── Main ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    init_db()

    if len(sys.argv) > 1 and sys.argv[1] == "test":
        sid = guardar_senal({
            "activo": "GainX 500", "tipo": "BUY",
            "entrada": 1234.5, "sl": 1200.0, "tp1": 1280.0,
            "confianza": 8, "fuente": "test"
        })
        print(f"  [TEST] Senal #{sid} insertada OK")
        # Simular cierre con fecha_cierre para probar duracion y pips
        from datetime import timedelta
        fecha_cierre = (datetime.now() + timedelta(minutes=47)).strftime("%Y-%m-%d %H:%M:%S")
        sid2, msg = actualizar_senal({
            "id": sid, "resultado": "WIN",
            "cierre": 1275.0, "fecha_cierre": fecha_cierre
        })
        data = get_senal_by_id(sid)
        print(f"  [TEST] pips     = {data.get('pips')}   (esperado: 40.5)")
        print(f"  [TEST] duracion = {data.get('duracion_min')} min")
        print(f"  [TEST] GET /senal/{sid} OK")
        sys.exit(0)

    log(f"Servidor trading webhook v4 en :{PORT}")
    log(f"BD: {DB_PATH}")
    log(f"Log: {LOG_PATH} (max {LOG_MAX} lineas)")
    log("Endpoints:")
    log("  GET  /ping              → health check")
    log("  GET  /senales           → ultimas 20 (JSON)")
    log("  GET  /senal/<id>        → señal por ID")
    log("  GET  /stats             → winrate y totales")
    log("  GET  /activos           → todos los activos")
    log("  GET  /activos/<cat>     → activos por categoria")
    log("  GET  /log               → ultimas 50 lineas del log")
    log("  POST /senal             → nueva señal")
    log("  POST /actualizar        → cierre/BE/resultado")
    log("  POST /activos           → agregar/editar activo")
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

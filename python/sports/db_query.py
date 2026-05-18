#!/data/data/com.termux/files/usr/bin/python3
"""
db_query.py — Motor SQL del bot deportivo
Ruta: /data/data/com.termux/files/home/sports/scripts/db_query.py

Uso desde n8n (execSync):
  python3 db_query.py <operacion> <json_args>

Operaciones:
  verificar_acceso   {"user_id": "123"}
  verificar_cache    {"match_id": "abc", "fecha": "20260515"}
  crear_job          {"match_id": "abc", "fecha": "20260515", "chat_id": "123"}
  leer_job_pendiente {}
  leer_stats         {}
  guardar_prediccion {"partido_id":"abc", "fuente":"claude", "pick":"Local",
                      "confianza":"ALTA", "score":78, "razonamiento":"...",
                      "texto_completo":"...", "job_id":"job_abc_123"}
  guardar_cache      {"input_hash":"abc123", "respuesta_json":"{...}",
                      "partido_id":"abc", "horas_ttl":6}
  actualizar_job        {"job_id":"job_abc_123", "status":"listo"}
  verificar_limite      {"user_id": "123", "plan": "pro"}
  crear_job             {"match_id":"abc", "fecha":"20260515", "chat_id":"123",
                          "user_id":"456", "plan":"pro"}
  guardar_comparativo   {"partido_id":"abc", "pick_python":"Local",
                          "prob_local_py":0.52, "prob_empate_py":0.27,
                          "prob_visit_py":0.21, "score_py":65,
                          "pick_claude":"Local", "pick_final":"Local",
                          "fuentes_disponibles":3, "confianza":"ALTA",
                          "score_final":70, "consenso":"COINCIDEN",
                          "peso_python":0.65, "peso_ia":0.35}
"""

import sys
import json
import sqlite3
import hashlib
from datetime import datetime, timedelta

DB = '/data/data/com.termux/files/home/sports/db/bot_deportivo.db'

# ─── helpers ─────────────────────────────────────────────────────────────────

def conectar():
    """Conexión con timeout para manejar escrituras concurrentes sin crash."""
    conn = sqlite3.connect(DB, timeout=5)
    conn.row_factory = sqlite3.Row
    return conn

def now():
    return datetime.now().strftime('%Y-%m-%d %H:%M:%S')

def ok(data):
    print(json.dumps({'ok': True, 'data': data}, ensure_ascii=False))

def error(msg):
    print(json.dumps({'ok': False, 'error': msg}, ensure_ascii=False))

def init_db(conn):
    """Crear tablas si no existen. Idempotente."""
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS usuarios (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT UNIQUE NOT NULL,
            activo    INTEGER NOT NULL DEFAULT 1,
            plan      TEXT NOT NULL DEFAULT 'free',
            creado_en TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS jobs (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            job_id        TEXT UNIQUE NOT NULL,
            match_id      TEXT NOT NULL,
            fecha_partido TEXT NOT NULL,
            chat_id       TEXT NOT NULL,
            origen        TEXT NOT NULL DEFAULT 'telegram',
            status        TEXT NOT NULL DEFAULT 'pendiente',
            intentos      INTEGER NOT NULL DEFAULT 0,
            creado_en     TEXT NOT NULL,
            completado_en TEXT
        );
        CREATE TABLE IF NOT EXISTS predicciones (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            partido_id      TEXT NOT NULL,
            fuente          TEXT NOT NULL,
            pick            TEXT,
            confianza       TEXT,
            confianza_score INTEGER,
            razonamiento    TEXT,
            texto_completo  TEXT,
            creado_en       TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS cache_predicciones (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            input_hash    TEXT UNIQUE NOT NULL,
            respuesta_json TEXT NOT NULL,
            partido_id    TEXT NOT NULL,
            expira_en     TEXT NOT NULL,
            hits          INTEGER NOT NULL DEFAULT 0,
            creado_en     TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_usuarios_device ON usuarios(device_id);
        CREATE INDEX IF NOT EXISTS idx_jobs_status     ON jobs(status);
        CREATE INDEX IF NOT EXISTS idx_cache_hash      ON cache_predicciones(input_hash);

        -- Tabla comparativa: guarda picks separados por fuente para análisis posterior
        CREATE TABLE IF NOT EXISTS analisis_comparativo (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            partido_id       TEXT NOT NULL,
            fecha            TEXT NOT NULL,
            local            TEXT,
            visitante        TEXT,
            liga             TEXT,
            pick_python      TEXT,
            prob_local_py    REAL,
            prob_empate_py   REAL,
            prob_visit_py    REAL,
            score_py         INTEGER,
            pick_claude      TEXT,
            pick_externo     TEXT,
            pick_final       TEXT,
            fuentes_disp     INTEGER,
            consenso         TEXT,
            score_final      INTEGER,
            confianza        TEXT,
            peso_python      REAL,
            peso_ia          REAL,
            resultado_real   TEXT,
            pick_correcto    INTEGER,
            creado_en        TEXT NOT NULL
        );

        -- Agregar columnas user_id y plan a jobs si no existen (migracion segura)
        -- SQLite no soporta IF NOT EXISTS en ALTER TABLE, se hace con try/except en Python
        CREATE INDEX IF NOT EXISTS idx_comparativo_partido ON analisis_comparativo(partido_id);
        CREATE INDEX IF NOT EXISTS idx_comparativo_fecha   ON analisis_comparativo(fecha);
    """)
    # Migración segura: agregar user_id y plan a jobs si no existen
    for col, tipo in [('user_id', 'TEXT'), ('plan', "TEXT DEFAULT 'free'")]:
        try:
            conn.execute(f'ALTER TABLE jobs ADD COLUMN {col} {tipo}')
            conn.commit()
        except Exception:
            pass  # columna ya existe
    conn.commit()

# ─── operaciones ─────────────────────────────────────────────────────────────

def verificar_acceso(args):
    user_id = str(args.get('user_id', ''))
    conn = conectar()
    init_db(conn)
    row = conn.execute(
        'SELECT activo, plan FROM usuarios WHERE device_id = ?', (user_id,)
    ).fetchone()
    conn.close()
    if row:
        ok({'autorizado': bool(row['activo']), 'plan': row['plan']})
    else:
        # Usuario no existe → no autorizado
        ok({'autorizado': False, 'plan': None})


def verificar_cache(args):
    match_id = str(args.get('match_id', ''))
    fecha    = str(args.get('fecha', ''))
    h        = hashlib.md5(f"{match_id}{fecha}".encode()).hexdigest()
    conn     = conectar()
    init_db(conn)
    row = conn.execute(
        """SELECT respuesta_json, hits FROM cache_predicciones
           WHERE input_hash = ? AND expira_en > ?""",
        (h, now())
    ).fetchone()
    if row:
        # Incrementar hits (escritura rápida, timeout cubre concurrencia)
        conn.execute(
            'UPDATE cache_predicciones SET hits = hits + 1 WHERE input_hash = ?', (h,)
        )
        conn.commit()
        conn.close()
        ok({'cache_hit': True, 'respuesta_json': row['respuesta_json'], 'hash': h})
    else:
        conn.close()
        ok({'cache_hit': False, 'respuesta_json': None, 'hash': h})


def crear_job(args):
    match_id  = str(args.get('match_id', ''))
    fecha     = str(args.get('fecha', ''))
    chat_id   = str(args.get('chat_id', ''))
    user_id   = str(args.get('user_id', ''))
    plan      = str(args.get('plan', 'free'))
    job_id    = f"job_{match_id}_{int(datetime.now().timestamp() * 1000)}"
    conn      = conectar()
    init_db(conn)
    conn.execute(
        """INSERT INTO jobs
           (job_id, match_id, fecha_partido, chat_id, user_id, plan, origen, status, intentos, creado_en)
           VALUES (?, ?, ?, ?, ?, ?, 'telegram', 'pendiente', 0, ?)""",
        (job_id, match_id, fecha, chat_id, user_id, plan, now())
    )
    conn.commit()
    conn.close()
    ok({'job_id': job_id, 'match_id': match_id, 'chat_id': chat_id, 'user_id': user_id, 'plan': plan})


def leer_job_pendiente(args):
    """Lee el job más antiguo con status=pendiente. Usado por WF-B Worker."""
    conn = conectar()
    init_db(conn)
    row = conn.execute(
        """SELECT job_id, match_id, fecha_partido, chat_id,
                  COALESCE(user_id, '') AS user_id,
                  COALESCE(plan, 'free') AS plan
           FROM jobs WHERE status = 'pendiente'
           ORDER BY creado_en ASC LIMIT 1"""
    ).fetchone()
    conn.close()
    if row:
        ok({
            'job_id':        row['job_id'],
            'match_id':      row['match_id'],
            'fecha_partido': row['fecha_partido'],
            'chat_id':       row['chat_id'],
            'user_id':       row['user_id'],
            'plan':          row['plan']
        })
    else:
        ok({'job_id': None})


def leer_stats(args):
    conn = conectar()
    init_db(conn)
    row = conn.execute("""
        SELECT
          COUNT(*) AS total,
          SUM(CASE WHEN confianza='ALTA'  THEN 1 ELSE 0 END) AS alta,
          SUM(CASE WHEN confianza='MEDIA' THEN 1 ELSE 0 END) AS media,
          SUM(CASE WHEN confianza='BAJA'  THEN 1 ELSE 0 END) AS baja
        FROM predicciones
    """).fetchone()
    jobs_row = conn.execute("""
        SELECT
          SUM(CASE WHEN status='listo'     THEN 1 ELSE 0 END) AS completados,
          SUM(CASE WHEN status='error'     THEN 1 ELSE 0 END) AS errores,
          SUM(CASE WHEN status='pendiente' THEN 1 ELSE 0 END) AS pendientes
        FROM jobs
    """).fetchone()
    conn.close()
    ok({
        'predicciones': {
            'total': row['total'] or 0,
            'alta':  row['alta']  or 0,
            'media': row['media'] or 0,
            'baja':  row['baja']  or 0,
        },
        'jobs': {
            'completados': jobs_row['completados'] or 0,
            'errores':     jobs_row['errores']     or 0,
            'pendientes':  jobs_row['pendientes']  or 0,
        }
    })


def guardar_prediccion(args):
    conn = conectar()
    init_db(conn)
    conn.execute(
        """INSERT INTO predicciones
           (partido_id, fuente, pick, confianza, confianza_score, razonamiento, texto_completo, creado_en)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            str(args.get('partido_id', '')),
            str(args.get('fuente', 'claude')),
            str(args.get('pick', '')),
            str(args.get('confianza', '')),
            int(args.get('score', 0)),
            str(args.get('razonamiento', '')),
            str(args.get('texto_completo', '')),
            now()
        )
    )
    # Actualizar job si viene job_id
    job_id = str(args.get('job_id', ''))
    if job_id:
        conn.execute(
            "UPDATE jobs SET status='listo', completado_en=? WHERE job_id=?",
            (now(), job_id)
        )
    conn.commit()
    conn.close()
    ok({'guardado': True})


def guardar_cache(args):
    h         = str(args.get('input_hash', ''))
    resp_json = str(args.get('respuesta_json', ''))
    partido   = str(args.get('partido_id', ''))
    horas     = int(args.get('horas_ttl', 6))
    expira    = (datetime.now() + timedelta(hours=horas)).strftime('%Y-%m-%d %H:%M:%S')
    conn      = conectar()
    init_db(conn)
    conn.execute(
        """INSERT OR REPLACE INTO cache_predicciones
           (input_hash, respuesta_json, partido_id, expira_en, hits, creado_en)
           VALUES (?, ?, ?, ?, 0, ?)""",
        (h, resp_json, partido, expira, now())
    )
    conn.commit()
    conn.close()
    ok({'hash': h, 'expira_en': expira})


def actualizar_job(args):
    job_id = str(args.get('job_id', ''))
    status = str(args.get('status', 'listo'))
    conn   = conectar()
    conn.execute(
        "UPDATE jobs SET status=?, completado_en=? WHERE job_id=?",
        (status, now(), job_id)
    )
    conn.commit()
    conn.close()
    ok({'job_id': job_id, 'status': status})

# ─── dispatcher ──────────────────────────────────────────────────────────────



def verificar_limite(args):
    """Verifica si el usuario puede hacer más análisis hoy según su plan."""
    user_id = str(args.get('user_id', ''))
    plan    = str(args.get('plan', 'free'))

    LIMITES = {
        'free':  0,   # solo Python, sin Claude
        'pro':  10,   # 10 análisis completos/día
        'max':  30,   # 30 análisis completos/día
    }
    limite = LIMITES.get(plan, 0)

    if plan == 'free':
        ok({'puede': True, 'plan': plan, 'limite': 0,
            'usados': 0, 'restantes': 0, 'es_free': True})
        return

    if not user_id:
        ok({'puede': False, 'plan': plan, 'limite': limite,
            'usados': 0, 'restantes': 0, 'es_free': False})
        return

    conn = conectar()
    init_db(conn)
    hoy = datetime.now().strftime('%Y-%m-%d')
    row = conn.execute(
        """SELECT COUNT(*) AS total FROM jobs
           WHERE user_id = ? AND plan IN ('pro','max')
           AND status IN ('listo','procesando')
           AND DATE(creado_en) = ?""",
        (user_id, hoy)
    ).fetchone()
    conn.close()

    usados    = row['total'] if row else 0
    puede     = usados < limite
    restantes = max(0, limite - usados)
    ok({
        'puede':     puede,
        'plan':      plan,
        'limite':    limite,
        'usados':    usados,
        'restantes': restantes,
        'es_free':   False
    })


def guardar_comparativo(args):
    """Guarda picks de Python, Claude y pick final para análisis posterior."""
    conn = conectar()
    init_db(conn)
    conn.execute(
        """INSERT INTO analisis_comparativo
           (partido_id, fecha, local, visitante, liga,
            pick_python, prob_local_py, prob_empate_py, prob_visit_py, score_py,
            pick_claude, pick_externo, pick_final,
            fuentes_disp, consenso, score_final, confianza,
            peso_python, peso_ia, creado_en)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            str(args.get('partido_id', '')),
            datetime.now().strftime('%Y-%m-%d'),
            str(args.get('local', '')),
            str(args.get('visitante', '')),
            str(args.get('liga', '')),
            str(args.get('pick_python', '')),
            float(args.get('prob_local_py') or 0),
            float(args.get('prob_empate_py') or 0),
            float(args.get('prob_visit_py') or 0),
            int(args.get('score_py') or 0),
            str(args.get('pick_claude', '')),
            str(args.get('pick_externo', '')),
            str(args.get('pick_final', '')),
            int(args.get('fuentes_disponibles') or 0),
            str(args.get('consenso', '')),
            int(args.get('score_final') or 0),
            str(args.get('confianza', '')),
            float(args.get('peso_python') or 0.5),
            float(args.get('peso_ia') or 0.5),
            now()
        )
    )
    conn.commit()
    conn.close()
    ok({'guardado': True})

OPERACIONES = {
    'verificar_acceso':   verificar_acceso,
    'verificar_cache':    verificar_cache,
    'crear_job':          crear_job,
    'leer_job_pendiente': leer_job_pendiente,
    'leer_stats':         leer_stats,
    'guardar_prediccion': guardar_prediccion,
    'guardar_cache':      guardar_cache,
    'actualizar_job':     actualizar_job,
    'verificar_limite':   verificar_limite,
    'guardar_comparativo':guardar_comparativo,
}

if __name__ == '__main__':
    if len(sys.argv) < 2:
        error('Uso: db_query.py <operacion> [json_args]')
        sys.exit(1)

    operacion = sys.argv[1]
    args_raw  = sys.argv[2] if len(sys.argv) > 2 else '{}'

    try:
        args = json.loads(args_raw)
    except Exception as e:
        error(f'JSON inválido en args: {e}')
        sys.exit(1)

    fn = OPERACIONES.get(operacion)
    if not fn:
        error(f'Operación desconocida: {operacion}. Válidas: {list(OPERACIONES.keys())}')
        sys.exit(1)

    try:
        fn(args)
    except Exception as e:
        error(f'Error en {operacion}: {str(e)}')
        sys.exit(1)

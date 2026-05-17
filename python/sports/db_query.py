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
  actualizar_job     {"job_id":"job_abc_123", "status":"listo"}
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
    """)
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
    job_id    = f"job_{match_id}_{int(datetime.now().timestamp() * 1000)}"
    conn      = conectar()
    init_db(conn)
    conn.execute(
        """INSERT INTO jobs
           (job_id, match_id, fecha_partido, chat_id, origen, status, intentos, creado_en)
           VALUES (?, ?, ?, ?, 'telegram', 'pendiente', 0, ?)""",
        (job_id, match_id, fecha, chat_id, now())
    )
    conn.commit()
    conn.close()
    ok({'job_id': job_id, 'match_id': match_id, 'chat_id': chat_id})


def leer_job_pendiente(args):
    """Lee el job más antiguo con status=pendiente. Usado por WF-B Worker."""
    conn = conectar()
    init_db(conn)
    row = conn.execute(
        """SELECT job_id, match_id, fecha_partido, chat_id
           FROM jobs WHERE status = 'pendiente'
           ORDER BY creado_en ASC LIMIT 1"""
    ).fetchone()
    conn.close()
    if row:
        ok({
            'job_id':        row['job_id'],
            'match_id':      row['match_id'],
            'fecha_partido': row['fecha_partido'],
            'chat_id':       row['chat_id']
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

OPERACIONES = {
    'verificar_acceso':   verificar_acceso,
    'verificar_cache':    verificar_cache,
    'crear_job':          crear_job,
    'leer_job_pendiente': leer_job_pendiente,
    'leer_stats':         leer_stats,
    'guardar_prediccion': guardar_prediccion,
    'guardar_cache':      guardar_cache,
    'actualizar_job':     actualizar_job,
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

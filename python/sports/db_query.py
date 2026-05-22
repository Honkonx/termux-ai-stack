#!/data/data/com.termux/files/usr/bin/python3
"""
db_query.py v3 — Motor SQL del bot deportivo
Ruta: /data/data/com.termux/files/home/sports/scripts/db_query.py

Configuración admin:
  Crear ~/sports/.env con:
    SPORTS_ADMIN_ID=tu_telegram_id

Uso desde n8n (execSync) o Termux:
  python3 db_query.py <operacion> <json_args>

Operaciones v1/v2 (sin cambios):
  verificar_acceso      {"user_id": "123"}
  verificar_limite      {"user_id": "123", "plan": "pro"}
  verificar_cache       {"match_id": "abc", "fecha": "20260515"}
  crear_job             {"match_id":"abc", "fecha":"20260515", "chat_id":"123",
                         "user_id":"456", "plan":"pro"}
  leer_job_pendiente    {}
  leer_stats            {}
  guardar_prediccion    {"partido_id":"abc", "fuente":"claude", "pick":"Local",
                         "confianza":"ALTA", "score":78, "razonamiento":"...",
                         "texto_completo":"...", "job_id":"job_abc_123"}
  guardar_cache         {"input_hash":"abc123", "respuesta_json":"{...}",
                         "partido_id":"abc", "horas_ttl":6}
  actualizar_job        {"job_id":"job_abc_123", "status":"listo"}
  guardar_comparativo   {"partido_id":"abc", "local":"River", "visitante":"Boca",
                         "liga":"Argentina", "pick_python":"Local",
                         "prob_local_py":0.52, "prob_empate_py":0.27,
                         "prob_visit_py":0.21, "score_py":65,
                         "pick_claude":"Local", "pick_externo":"Local",
                         "pick_final":"Local", "fuentes_disponibles":3,
                         "confianza":"ALTA", "score_final":70,
                         "consenso":"COINCIDEN", "peso_python":0.65,
                         "peso_ia":0.35, "hora_kickoff":"20:00"}

Operaciones nuevas v3:
  verificar_admin           {"user_id": "123"}
  gestionar_usuario         {"accion":"agregar",    "user_id":"123", "plan":"pro"}
                            {"accion":"activar",    "user_id":"123"}
                            {"accion":"desactivar", "user_id":"123"}
                            {"accion":"cambiar_plan","user_id":"123", "plan":"max"}
                            {"accion":"eliminar",   "user_id":"123"}
  guardar_recomendaciones   {"fecha":"20260520", "partidos":[
                               {"fixture_id":"999", "local":"Equipo A",
                                "visitante":"Equipo B", "liga":"Premier",
                                "hora_chile":"20:45"}
                             ]}
  leer_recomendaciones      {"fecha":"20260520"}
  leer_pendientes_actualizar {"fecha":"2026-05-19"}
  guardar_resultado         {"fixture_id":"31736329", "local":"River",
                              "visitante":"Boca", "liga":"Argentina",
                              "goles_local":2, "goles_visitante":1,
                              "status_api":"FT", "fecha_partido":"2026-05-20",
                              "hora_kickoff":"20:00"}
  leer_stats_aciertos       {"dias":30}
"""

import sys
import os
import json
import sqlite3
import hashlib
from datetime import datetime, timedelta

DB = '/data/data/com.termux/files/home/sports/db/bot_deportivo.db'

# ─── carga de admin desde .env ────────────────────────────────────────────────

def _cargar_admin_ids():
    """
    Lee SPORTS_ADMIN_ID desde ~/sports/.env
    Formato del archivo:
      SPORTS_ADMIN_ID=123456789
    Si el archivo no existe o la variable no está → lista vacía.
    Nunca falla — devuelve [] en cualquier error.
    """
    try:
        env_path = os.path.join(
            os.path.dirname(DB), '..', '.env'
        )
        env_path = os.path.normpath(env_path)
        if not os.path.isfile(env_path):
            return []
        ids = []
        with open(env_path, 'r') as f:
            for linea in f:
                linea = linea.strip()
                if linea.startswith('SPORTS_ADMIN_ID='):
                    valor = linea.split('=', 1)[1].strip()
                    # Soporta lista separada por comas: 111,222
                    for v in valor.split(','):
                        v = v.strip()
                        if v:
                            ids.append(v)
        return ids
    except Exception:
        return []

ADMIN_IDS = _cargar_admin_ids()

# ─── helpers ──────────────────────────────────────────────────────────────────

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

def _es_admin(user_id):
    return str(user_id) in ADMIN_IDS

def init_db(conn):
    """Crear tablas si no existen. Idempotente. Incluye migración segura."""
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
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            input_hash     TEXT UNIQUE NOT NULL,
            respuesta_json TEXT NOT NULL,
            partido_id     TEXT NOT NULL,
            expira_en      TEXT NOT NULL,
            hits           INTEGER NOT NULL DEFAULT 0,
            creado_en      TEXT NOT NULL
        );

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

        -- v3: resultados reales para actualización automática
        CREATE TABLE IF NOT EXISTS resultados_partidos (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            fixture_id      TEXT UNIQUE NOT NULL,
            local           TEXT,
            visitante       TEXT,
            liga            TEXT,
            goles_local     INTEGER,
            goles_visitante INTEGER,
            ganador         TEXT,
            status_api      TEXT,
            fecha_partido   TEXT,
            hora_kickoff    TEXT,
            actualizado_en  TEXT NOT NULL
        );

        -- v3: partidos filtrados por WF-D como recomendaciones del día
        CREATE TABLE IF NOT EXISTS recomendaciones_dia (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            fixture_id TEXT NOT NULL,
            local      TEXT NOT NULL,
            visitante  TEXT NOT NULL,
            liga       TEXT NOT NULL,
            hora_chile TEXT,
            fecha      TEXT NOT NULL,
            creado_en  TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_usuarios_device     ON usuarios(device_id);
        CREATE INDEX IF NOT EXISTS idx_jobs_status         ON jobs(status);
        CREATE INDEX IF NOT EXISTS idx_cache_hash          ON cache_predicciones(input_hash);
        CREATE INDEX IF NOT EXISTS idx_comparativo_partido ON analisis_comparativo(partido_id);
        CREATE INDEX IF NOT EXISTS idx_comparativo_fecha   ON analisis_comparativo(fecha);
        CREATE INDEX IF NOT EXISTS idx_resultados_fixture  ON resultados_partidos(fixture_id);
        CREATE INDEX IF NOT EXISTS idx_recom_fecha         ON recomendaciones_dia(fecha);

        -- v4: análisis individuales para sistema de caché consenso
        CREATE TABLE IF NOT EXISTS analisis_individuales (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            partido_id     TEXT NOT NULL,
            pick_final     TEXT NOT NULL,
            confianza      TEXT,
            score_final    INTEGER,
            texto_completo TEXT NOT NULL,
            creado_en      TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS cache_consenso (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            partido_id     TEXT UNIQUE NOT NULL,
            pick_consenso  TEXT NOT NULL,
            texto_consenso TEXT NOT NULL,
            total_analisis INTEGER NOT NULL DEFAULT 0,
            usos           INTEGER NOT NULL DEFAULT 0,
            max_usos       INTEGER NOT NULL DEFAULT 5,
            expira_en      TEXT NOT NULL,
            creado_en      TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_analisis_ind_partido ON analisis_individuales(partido_id);
        CREATE INDEX IF NOT EXISTS idx_cache_consenso_partido ON cache_consenso(partido_id);

    """)

    # Migración segura: columnas nuevas sin romper BD existente
    migraciones = [
        ('jobs',                 'user_id',          'TEXT'),
        ('jobs',                 'plan',             "TEXT DEFAULT 'free'"),
        ('analisis_comparativo', 'hora_kickoff',     'TEXT'),
        ('analisis_comparativo', 'goles_local',      'INTEGER'),
        ('analisis_comparativo', 'goles_visitante',  'INTEGER'),
        ('analisis_comparativo', 'status_partido',   'TEXT'),
        ('predicciones',         'pick_correcto',    'INTEGER'),
        # v4: verificación granular por fuente en analisis_comparativo
        ('analisis_comparativo', 'pick_form',             'TEXT'),
        ('analisis_comparativo', 'score_form',            'INTEGER'),
        ('analisis_comparativo', 'pick_python_correcto',  'INTEGER'),
        ('analisis_comparativo', 'pick_claude_correcto',  'INTEGER'),
        ('analisis_comparativo', 'pick_form_correcto',    'INTEGER'),
    ]
    for tabla, col, tipo in migraciones:
        try:
            conn.execute(f'ALTER TABLE {tabla} ADD COLUMN {col} {tipo}')
            conn.commit()
        except Exception:
            pass  # columna ya existe

    conn.commit()

# ─── operaciones v1/v2 ────────────────────────────────────────────────────────

def verificar_acceso(args):
    user_id = str(args.get('user_id', ''))

    if _es_admin(user_id):
        ok({'autorizado': True, 'plan': 'admin', 'es_admin': True})
        return

    conn = conectar()
    init_db(conn)
    row = conn.execute(
        'SELECT activo, plan FROM usuarios WHERE device_id = ?', (user_id,)
    ).fetchone()
    conn.close()

    if row:
        ok({'autorizado': bool(row['activo']), 'plan': row['plan'], 'es_admin': False})
    else:
        ok({'autorizado': False, 'plan': None, 'es_admin': False})


def verificar_limite(args):
    user_id = str(args.get('user_id', ''))
    plan    = str(args.get('plan', 'free'))

    if _es_admin(user_id) or plan == 'admin':
        ok({'puede': True, 'plan': 'admin', 'limite': 9999,
            'usados': 0, 'restantes': 9999, 'es_free': False, 'es_admin': True})
        return

    LIMITES = {'free': 0, 'pro': 10, 'max': 30}
    limite  = LIMITES.get(plan, 0)

    if plan == 'free':
        ok({'puede': True, 'plan': plan, 'limite': 0,
            'usados': 0, 'restantes': 0, 'es_free': True, 'es_admin': False})
        return

    if not user_id:
        ok({'puede': False, 'plan': plan, 'limite': limite,
            'usados': 0, 'restantes': 0, 'es_free': False, 'es_admin': False})
        return

    conn  = conectar()
    init_db(conn)
    hoy   = datetime.now().strftime('%Y-%m-%d')
    row   = conn.execute(
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
    ok({'puede': puede, 'plan': plan, 'limite': limite,
        'usados': usados, 'restantes': restantes,
        'es_free': False, 'es_admin': False})


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
        conn.execute(
            'UPDATE cache_predicciones SET hits = hits + 1 WHERE input_hash = ?', (h,)
        )
        conn.commit()
        conn.close()
        ok({'cache_hit': True, 'respuesta_json': row['respuesta_json'], 'hash': h})
    else:
        conn.close()
        ok({'cache_hit': False, 'respuesta_json': None, 'hash': h})


def verificar_job_activo(args):
    """Devuelve job_activo=True si ya existe un job pendiente o procesando
    para este match_id. Evita crear jobs duplicados en WF-A."""
    match_id = str(args.get('match_id', ''))
    conn     = conectar()
    init_db(conn)
    row = conn.execute(
        """SELECT job_id FROM jobs
           WHERE match_id = ?
             AND status IN ('pendiente', 'procesando')
           ORDER BY creado_en DESC LIMIT 1""",
        (match_id,)
    ).fetchone()
    conn.close()
    if row:
        ok({'job_activo': True, 'job_id': row['job_id']})
    else:
        ok({'job_activo': False, 'job_id': None})


def leer_aciertos_por_fuente(args):
    """
    Lee winrate del día (o rango) desglosado por fuente:
    pick_final (global), pick_python, pick_claude, pick_form.
    Devuelve el conteo de aciertos/total por cada fuente.
    """
    fecha     = str(args.get('fecha', ''))
    fecha_fin = str(args.get('fecha_fin', fecha))
    if not fecha:
        from datetime import datetime as _dt
        fecha = fecha_fin = _dt.now().strftime('%Y-%m-%d')
    conn = conectar()
    init_db(conn)
    row = conn.execute(
        """SELECT
             COUNT(*) AS total,
             SUM(CASE WHEN pick_correcto         = 1 THEN 1 ELSE 0 END) AS aciertos_final,
             SUM(CASE WHEN pick_python_correcto  = 1 THEN 1 ELSE 0 END) AS aciertos_python,
             SUM(CASE WHEN pick_claude_correcto  = 1 THEN 1 ELSE 0 END) AS aciertos_claude,
             SUM(CASE WHEN pick_form_correcto    = 1 THEN 1 ELSE 0 END) AS aciertos_form,
             SUM(CASE WHEN pick_python_correcto IS NOT NULL THEN 1 ELSE 0 END) AS total_python,
             SUM(CASE WHEN pick_claude_correcto IS NOT NULL THEN 1 ELSE 0 END) AS total_claude,
             SUM(CASE WHEN pick_form_correcto   IS NOT NULL THEN 1 ELSE 0 END) AS total_form
           FROM analisis_comparativo
           WHERE fecha BETWEEN ? AND ?
             AND resultado_real IS NOT NULL
             AND resultado_real != 'CANC'""",
        (fecha, fecha_fin)
    ).fetchone()
    conn.close()

    def wr(aciertos, total):
        return round(aciertos / total * 100, 1) if total > 0 else None

    total      = row['total']              or 0
    ac_final   = row['aciertos_final']     or 0
    ac_python  = row['aciertos_python']    or 0
    ac_claude  = row['aciertos_claude']    or 0
    ac_form    = row['aciertos_form']      or 0
    tot_python = row['total_python']       or 0
    tot_claude = row['total_claude']       or 0
    tot_form   = row['total_form']         or 0

    ok({
        'fecha':     fecha,
        'fecha_fin': fecha_fin,
        'total':     total,
        'final':     {'aciertos': ac_final,  'total': total,      'winrate': wr(ac_final,  total)},
        'python':    {'aciertos': ac_python,  'total': tot_python, 'winrate': wr(ac_python, tot_python)},
        'claude':    {'aciertos': ac_claude,  'total': tot_claude, 'winrate': wr(ac_claude, tot_claude)},
        'form':      {'aciertos': ac_form,    'total': tot_form,   'winrate': wr(ac_form,   tot_form)},
    })


def guardar_analisis_individual(args):
    """Guarda el resultado completo de un análisis individual antes de evaluar consenso."""
    partido_id     = str(args.get('partido_id', ''))
    pick_final     = str(args.get('pick_final', ''))
    confianza      = str(args.get('confianza', ''))
    score_final    = int(args.get('score_final', 0))
    texto_completo = str(args.get('texto_completo', ''))
    if not partido_id or not pick_final or not texto_completo:
        error('partido_id, pick_final y texto_completo son obligatorios')
        return
    conn = conectar()
    init_db(conn)
    conn.execute(
        """INSERT INTO analisis_individuales
           (partido_id, pick_final, confianza, score_final, texto_completo, creado_en)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (partido_id, pick_final, confianza, score_final, texto_completo, now())
    )
    conn.commit()
    total = conn.execute(
        "SELECT COUNT(*) AS cnt FROM analisis_individuales WHERE partido_id = ?",
        (partido_id,)
    ).fetchone()['cnt']
    conn.close()
    ok({'guardado': True, 'total_analisis': total, 'partido_id': partido_id})


def verificar_consenso_cache(args):
    """
    Verifica en orden:
    1. Caché consenso activo (3+ coincidentes, usos < max_usos, no expirado) → servir
    2. Job pendiente/procesando → dedup (no crear otro job)
    3. Sin nada → crear job normalmente
    """
    partido_id = str(args.get('partido_id', '') or args.get('match_id', ''))
    conn = conectar()
    init_db(conn)

    # 1. Caché consenso activo
    row_cc = conn.execute(
        """SELECT pick_consenso, texto_consenso, total_analisis, usos, max_usos
           FROM cache_consenso
           WHERE partido_id = ? AND expira_en > ? AND usos < max_usos""",
        (partido_id, now())
    ).fetchone()

    if row_cc:
        conn.execute(
            "UPDATE cache_consenso SET usos = usos + 1 WHERE partido_id = ?",
            (partido_id,)
        )
        conn.commit()
        conn.close()
        ok({
            'cache_consenso_hit': True,
            'debe_generar':       False,
            'job_en_vuelo':       False,
            'pick_consenso':      row_cc['pick_consenso'],
            'texto_consenso':     row_cc['texto_consenso'],
            'total_analisis':     row_cc['total_analisis'],
            'usos_restantes':     row_cc['max_usos'] - row_cc['usos'] - 1
        })
        return

    # 2. Job en vuelo — dedup
    row_job = conn.execute(
        """SELECT job_id FROM jobs
           WHERE match_id = ? AND status IN ('pendiente', 'procesando')
           ORDER BY creado_en DESC LIMIT 1""",
        (partido_id,)
    ).fetchone()

    if row_job:
        conn.close()
        ok({
            'cache_consenso_hit': False,
            'debe_generar':       False,
            'job_en_vuelo':       True,
            'pick_consenso':      None,
            'texto_consenso':     None,
            'total_analisis':     0,
            'usos_restantes':     0
        })
        return

    # 3. Contar análisis previos del partido
    total = conn.execute(
        "SELECT COUNT(*) AS cnt FROM analisis_individuales WHERE partido_id = ?",
        (partido_id,)
    ).fetchone()['cnt']

    conn.close()
    ok({
        'cache_consenso_hit': False,
        'debe_generar':       True,
        'job_en_vuelo':       False,
        'pick_consenso':      None,
        'texto_consenso':     None,
        'total_analisis':     total,
        'usos_restantes':     0
    })


def activar_cache_consenso(args):
    """
    Evalúa los últimos 3 análisis individuales del partido.
    Si los 3 coinciden en pick_final → activa caché consenso (TTL 3h, max 5 usos).
    Si no coinciden → no activa, el siguiente usuario generará un análisis nuevo.
    """
    partido_id = str(args.get('partido_id', ''))
    max_usos   = int(args.get('max_usos', 5))
    horas_ttl  = int(args.get('horas_ttl', 3))
    if not partido_id:
        error('partido_id es obligatorio')
        return
    conn = conectar()
    init_db(conn)

    rows = conn.execute(
        """SELECT pick_final, texto_completo, score_final
           FROM analisis_individuales
           WHERE partido_id = ?
           ORDER BY creado_en DESC LIMIT 3""",
        (partido_id,)
    ).fetchall()

    if len(rows) < 3:
        conn.close()
        ok({'activado': False, 'razon': f'Solo {len(rows)}/3 análisis disponibles',
            'total_analisis': len(rows)})
        return

    picks = [r['pick_final'] for r in rows]
    if len(set(picks)) != 1:
        conn.close()
        ok({'activado': False, 'razon': f'Picks divergen: {picks}',
            'total_analisis': len(rows)})
        return

    # 3 picks coinciden — tomar el texto del análisis con mayor score
    mejor = max(rows, key=lambda r: r['score_final'] or 0)
    pick_consenso  = picks[0]
    texto_consenso = mejor['texto_completo']
    expira = (datetime.now() + timedelta(hours=horas_ttl)).strftime('%Y-%m-%d %H:%M:%S')

    total = conn.execute(
        "SELECT COUNT(*) AS cnt FROM analisis_individuales WHERE partido_id = ?",
        (partido_id,)
    ).fetchone()['cnt']

    conn.execute(
        """INSERT OR REPLACE INTO cache_consenso
           (partido_id, pick_consenso, texto_consenso, total_analisis,
            usos, max_usos, expira_en, creado_en)
           VALUES (?, ?, ?, ?, 0, ?, ?, ?)""",
        (partido_id, pick_consenso, texto_consenso, total, max_usos, expira, now())
    )
    conn.commit()
    conn.close()
    ok({
        'activado':       True,
        'pick_consenso':  pick_consenso,
        'total_analisis': total,
        'expira_en':      expira,
        'max_usos':       max_usos
    })


def crear_job(args):
    match_id = str(args.get('match_id', ''))
    fecha    = str(args.get('fecha', ''))
    chat_id  = str(args.get('chat_id', ''))
    user_id  = str(args.get('user_id', ''))
    plan     = str(args.get('plan', 'free'))
    job_id   = f"job_{match_id}_{int(datetime.now().timestamp() * 1000)}"
    conn     = conectar()
    init_db(conn)
    conn.execute(
        """INSERT INTO jobs
           (job_id, match_id, fecha_partido, chat_id, user_id, plan,
            origen, status, intentos, creado_en)
           VALUES (?, ?, ?, ?, ?, ?, 'telegram', 'pendiente', 0, ?)""",
        (job_id, match_id, fecha, chat_id, user_id, plan, now())
    )
    conn.commit()
    conn.close()
    ok({'job_id': job_id, 'match_id': match_id,
        'chat_id': chat_id, 'user_id': user_id, 'plan': plan})


def leer_job_pendiente(args):
    conn = conectar()
    init_db(conn)
    row  = conn.execute(
        """SELECT job_id, match_id, fecha_partido, chat_id,
                  COALESCE(user_id, '') AS user_id,
                  COALESCE(plan, 'free') AS plan
           FROM jobs WHERE status = 'pendiente'
           ORDER BY creado_en ASC LIMIT 1"""
    ).fetchone()
    conn.close()
    if row:
        ok({'job_id':        row['job_id'],
            'match_id':      row['match_id'],
            'fecha_partido': row['fecha_partido'],
            'chat_id':       row['chat_id'],
            'user_id':       row['user_id'],
            'plan':          row['plan']})
    else:
        ok({'job_id': None})


def leer_stats(args):
    conn = conectar()
    init_db(conn)
    row = conn.execute("""
        SELECT COUNT(*) AS total,
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
    ok({'predicciones': {'total': row['total'] or 0,
                         'alta':  row['alta']  or 0,
                         'media': row['media'] or 0,
                         'baja':  row['baja']  or 0},
        'jobs': {'completados': jobs_row['completados'] or 0,
                 'errores':     jobs_row['errores']     or 0,
                 'pendientes':  jobs_row['pendientes']  or 0}})


def guardar_prediccion(args):
    conn = conectar()
    init_db(conn)
    conn.execute(
        """INSERT INTO predicciones
           (partido_id, fuente, pick, confianza, confianza_score,
            razonamiento, texto_completo, creado_en)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (str(args.get('partido_id', '')),
         str(args.get('fuente', 'claude')),
         str(args.get('pick', '')),
         str(args.get('confianza', '')),
         int(args.get('score', 0)),
         str(args.get('razonamiento', '')),
         str(args.get('texto_completo', '')),
         now())
    )
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
    h       = str(args.get('input_hash', ''))
    resp    = str(args.get('respuesta_json', ''))
    partido = str(args.get('partido_id', ''))
    horas   = int(args.get('horas_ttl', 6))
    expira  = (datetime.now() + timedelta(hours=horas)).strftime('%Y-%m-%d %H:%M:%S')
    conn    = conectar()
    init_db(conn)
    conn.execute(
        """INSERT OR REPLACE INTO cache_predicciones
           (input_hash, respuesta_json, partido_id, expira_en, hits, creado_en)
           VALUES (?, ?, ?, ?, 0, ?)""",
        (h, resp, partido, expira, now())
    )
    conn.commit()
    conn.close()
    ok({'hash': h, 'expira_en': expira})


def actualizar_job(args):
    job_id = str(args.get('job_id', ''))
    status = str(args.get('status', 'listo'))
    conn   = conectar()
    init_db(conn)
    conn.execute(
        "UPDATE jobs SET status=?, completado_en=? WHERE job_id=?",
        (status, now(), job_id)
    )
    conn.commit()
    conn.close()
    ok({'job_id': job_id, 'status': status})


def guardar_comparativo(args):
    conn = conectar()
    init_db(conn)
    conn.execute(
        """INSERT INTO analisis_comparativo
           (partido_id, fecha, local, visitante, liga,
            pick_python, prob_local_py, prob_empate_py, prob_visit_py, score_py,
            pick_claude, pick_externo, pick_final,
            fuentes_disp, consenso, score_final, confianza,
            peso_python, peso_ia, hora_kickoff, creado_en)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (str(args.get('partido_id', '')),
         datetime.now().strftime('%Y-%m-%d'),
         str(args.get('local', '')),
         str(args.get('visitante', '')),
         str(args.get('liga', '')),
         str(args.get('pick_python', '')),
         float(args.get('prob_local_py')  or 0),
         float(args.get('prob_empate_py') or 0),
         float(args.get('prob_visit_py')  or 0),
         int(args.get('score_py')         or 0),
         str(args.get('pick_claude', '')),
         str(args.get('pick_externo', '')),
         str(args.get('pick_final', '')),
         int(args.get('fuentes_disponibles') or 0),
         str(args.get('consenso', '')),
         int(args.get('score_final')      or 0),
         str(args.get('confianza', '')),
         float(args.get('peso_python')    or 0.5),
         float(args.get('peso_ia')        or 0.5),
         str(args.get('hora_kickoff', '')),
         now())
    )
    conn.commit()
    conn.close()
    ok({'guardado': True})

# ─── operaciones nuevas v3 ────────────────────────────────────────────────────

def verificar_admin(args):
    user_id  = str(args.get('user_id', ''))
    es_admin = _es_admin(user_id)
    ok({'es_admin': es_admin, 'user_id': user_id})


def gestionar_usuario(args):
    """
    Administra usuarios desde Termux o WF-A.
    Acciones: agregar | activar | desactivar | cambiar_plan | eliminar
    """
    accion  = str(args.get('accion', ''))
    user_id = str(args.get('user_id', ''))
    plan    = str(args.get('plan', 'free'))

    if not accion or not user_id:
        error('accion y user_id son requeridos')
        return

    PLANES_VALIDOS = ('free', 'pro', 'max')
    if accion == 'agregar' and plan not in PLANES_VALIDOS:
        error(f'plan inválido: {plan}. Válidos: {PLANES_VALIDOS}')
        return

    conn = conectar()
    init_db(conn)

    if accion == 'agregar':
        existe = conn.execute(
            'SELECT id FROM usuarios WHERE device_id = ?', (user_id,)
        ).fetchone()
        if existe:
            # Si ya existe, solo reactivar y actualizar plan
            conn.execute(
                'UPDATE usuarios SET activo=1, plan=? WHERE device_id=?',
                (plan, user_id)
            )
            conn.commit()
            conn.close()
            ok({'accion': 'reactivado', 'user_id': user_id, 'plan': plan})
        else:
            conn.execute(
                'INSERT INTO usuarios (device_id, activo, plan, creado_en) VALUES (?,1,?,?)',
                (user_id, plan, now())
            )
            conn.commit()
            conn.close()
            ok({'accion': 'agregado', 'user_id': user_id, 'plan': plan})

    elif accion == 'activar':
        conn.execute(
            'UPDATE usuarios SET activo=1 WHERE device_id=?', (user_id,)
        )
        conn.commit()
        conn.close()
        ok({'accion': 'activado', 'user_id': user_id})

    elif accion == 'desactivar':
        conn.execute(
            'UPDATE usuarios SET activo=0 WHERE device_id=?', (user_id,)
        )
        conn.commit()
        conn.close()
        ok({'accion': 'desactivado', 'user_id': user_id})

    elif accion == 'cambiar_plan':
        if plan not in PLANES_VALIDOS:
            conn.close()
            error(f'plan inválido: {plan}. Válidos: {PLANES_VALIDOS}')
            return
        conn.execute(
            'UPDATE usuarios SET plan=? WHERE device_id=?', (plan, user_id)
        )
        conn.commit()
        conn.close()
        ok({'accion': 'plan_actualizado', 'user_id': user_id, 'plan': plan})

    elif accion == 'eliminar':
        conn.execute('DELETE FROM usuarios WHERE device_id=?', (user_id,))
        conn.commit()
        conn.close()
        ok({'accion': 'eliminado', 'user_id': user_id})

    else:
        conn.close()
        error(f'accion inválida: {accion}. Válidas: agregar|activar|desactivar|cambiar_plan|eliminar')


def guardar_recomendaciones(args):
    """
    Guarda partidos sobrantes del filtro WF-D como recomendaciones del día.
    Reemplaza las del mismo día si ya existen (idempotente).
    """
    fecha    = str(args.get('fecha', datetime.now().strftime('%Y%m%d')))
    partidos = args.get('partidos', [])

    if not partidos:
        ok({'guardados': 0})
        return

    conn = conectar()
    init_db(conn)
    # Borrar del mismo día para evitar duplicados
    conn.execute('DELETE FROM recomendaciones_dia WHERE fecha = ?', (fecha,))

    guardados = 0
    for p in partidos:
        fixture_id = str(p.get('fixture_id', ''))
        local      = str(p.get('local', ''))
        visitante  = str(p.get('visitante', ''))
        if not fixture_id or not local or not visitante:
            continue
        conn.execute(
            """INSERT INTO recomendaciones_dia
               (fixture_id, local, visitante, liga, hora_chile, fecha, creado_en)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (fixture_id, local, visitante,
             str(p.get('liga', '')), str(p.get('hora_chile', '')), fecha, now())
        )
        guardados += 1

    conn.commit()
    conn.close()
    ok({'guardados': guardados, 'fecha': fecha})


def leer_recomendaciones(args):
    """
    Lee recomendaciones del día. Comando /recomendaciones en WF-A.
    """
    fecha = str(args.get('fecha', datetime.now().strftime('%Y%m%d')))
    conn  = conectar()
    init_db(conn)
    rows  = conn.execute(
        """SELECT fixture_id, local, visitante, liga, hora_chile
           FROM recomendaciones_dia
           WHERE fecha = ?
           ORDER BY hora_chile ASC""",
        (fecha,)
    ).fetchall()
    conn.close()
    ok({'partidos': [{'fixture_id': r['fixture_id'],
                      'local':      r['local'],
                      'visitante':  r['visitante'],
                      'liga':       r['liga'],
                      'hora_chile': r['hora_chile']} for r in rows],
        'total': len(rows),
        'fecha': fecha})


def leer_pendientes_actualizar(args):
    """
    Lee analisis_comparativo sin resultado_real para la fecha dada.
    WF-E llama esto a las 23:30 para armar la lista de fixture_ids a consultar.
    """
    fecha = str(args.get('fecha', ''))
    if not fecha:
        fecha = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

    conn  = conectar()
    init_db(conn)
    rows  = conn.execute(
        """SELECT DISTINCT partido_id, local, visitante, liga, hora_kickoff
           FROM analisis_comparativo
           WHERE fecha = ? AND resultado_real IS NULL
           ORDER BY hora_kickoff ASC""",
        (fecha,)
    ).fetchall()
    conn.close()
    ok({'pendientes': [{'fixture_id':   r['partido_id'],
                        'local':        r['local'],
                        'visitante':    r['visitante'],
                        'liga':         r['liga'],
                        'hora_kickoff': r['hora_kickoff']} for r in rows],
        'total': len(rows),
        'fecha': fecha})


def guardar_resultado(args):
    """
    Guarda resultado real y calcula pick_correcto en analisis_comparativo
    y predicciones. Llamado por actualizar_resultados.py.
    """
    fixture_id      = str(args.get('fixture_id', ''))
    local           = str(args.get('local', ''))
    visitante       = str(args.get('visitante', ''))
    liga            = str(args.get('liga', ''))
    goles_local     = int(args.get('goles_local',     0))
    goles_visitante = int(args.get('goles_visitante', 0))
    status_api      = str(args.get('status_api', 'FT'))
    fecha_partido   = str(args.get('fecha_partido', ''))
    hora_kickoff    = str(args.get('hora_kickoff', ''))

    if not fixture_id:
        error('fixture_id requerido')
        return

    if goles_local > goles_visitante:
        ganador = 'local'
    elif goles_visitante > goles_local:
        ganador = 'visitante'
    else:
        ganador = 'empate'

    resultado_str = f"{goles_local}-{goles_visitante}"

    conn = conectar()
    init_db(conn)

    # 1) Tabla resultados_partidos
    conn.execute(
        """INSERT OR REPLACE INTO resultados_partidos
           (fixture_id, local, visitante, liga, goles_local, goles_visitante,
            ganador, status_api, fecha_partido, hora_kickoff, actualizado_en)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
        (fixture_id, local, visitante, liga,
         goles_local, goles_visitante, ganador,
         status_api, fecha_partido, hora_kickoff, now())
    )

    # 2) analisis_comparativo: llenar resultado_real y pick_correcto por pick_final
    rows_comp = conn.execute(
        """SELECT id, pick_final
           FROM analisis_comparativo
           WHERE partido_id = ? AND resultado_real IS NULL""",
        (fixture_id,)
    ).fetchall()

    for row in rows_comp:
        acierto = 1 if _pick_acerto(row['pick_final'], ganador, local, visitante) else 0
        conn.execute(
            """UPDATE analisis_comparativo
               SET resultado_real=?, goles_local=?, goles_visitante=?,
                   status_partido=?, pick_correcto=?
               WHERE id=?""",
            (resultado_str, goles_local, goles_visitante,
             status_api, acierto, row['id'])
        )

    # 3) predicciones: pick_correcto por fuente individual
    rows_pred = conn.execute(
        'SELECT id, pick FROM predicciones WHERE partido_id = ?',
        (fixture_id,)
    ).fetchall()

    for row in rows_pred:
        acierto = 1 if _pick_acerto(row['pick'], ganador, local, visitante) else 0
        conn.execute(
            'UPDATE predicciones SET pick_correcto=? WHERE id=?',
            (acierto, row['id'])
        )

    conn.commit()
    conn.close()
    ok({'fixture_id':    fixture_id,
        'resultado':     resultado_str,
        'ganador':       ganador,
        'comparativos':  len(rows_comp),
        'predicciones':  len(rows_pred)})


def _pick_acerto(pick, ganador, local, visitante):
    """Determina si un pick acertó. Case-insensitive."""
    if not pick:
        return False
    p = pick.strip().lower()
    if ganador == 'empate':
        return p in ('empate', 'draw', 'x')
    if ganador == 'local':
        return p in (local.strip().lower(), 'local')
    if ganador == 'visitante':
        return p in (visitante.strip().lower(), 'visitante')
    return False


def leer_stats_aciertos(args):
    """Winrate por fuente, por confianza y por consenso."""
    dias  = int(args.get('dias', 30))
    desde = (datetime.now() - timedelta(days=dias)).strftime('%Y-%m-%d')

    conn = conectar()
    init_db(conn)

    rows_f = conn.execute(
        """SELECT fuente,
                  COUNT(*) AS total,
                  SUM(CASE WHEN pick_correcto=1 THEN 1 ELSE 0 END) AS aciertos,
                  SUM(CASE WHEN pick_correcto IS NOT NULL THEN 1 ELSE 0 END) AS evaluados
           FROM predicciones
           WHERE DATE(creado_en) >= ?
           GROUP BY fuente ORDER BY fuente""",
        (desde,)
    ).fetchall()

    row_c = conn.execute(
        """SELECT
             COUNT(*) AS total,
             SUM(CASE WHEN pick_correcto=1 THEN 1 ELSE 0 END) AS aciertos,
             SUM(CASE WHEN pick_correcto IS NOT NULL THEN 1 ELSE 0 END) AS evaluados,
             SUM(CASE WHEN confianza='ALTA'  AND pick_correcto=1 THEN 1 ELSE 0 END) AS alta_ok,
             SUM(CASE WHEN confianza='ALTA'  THEN 1 ELSE 0 END) AS alta_total,
             SUM(CASE WHEN confianza='MEDIA' AND pick_correcto=1 THEN 1 ELSE 0 END) AS media_ok,
             SUM(CASE WHEN confianza='MEDIA' THEN 1 ELSE 0 END) AS media_total,
             SUM(CASE WHEN consenso='COINCIDEN' AND pick_correcto=1 THEN 1 ELSE 0 END) AS cons_ok,
             SUM(CASE WHEN consenso='COINCIDEN' THEN 1 ELSE 0 END) AS cons_total
           FROM analisis_comparativo
           WHERE DATE(fecha) >= ? AND pick_correcto IS NOT NULL""",
        (desde,)
    ).fetchone()
    conn.close()

    def wr(a, t):
        return round((a or 0) / t * 100, 1) if t and t > 0 else None

    fuentes = [{'fuente':    r['fuente'],
                'total':     r['total']     or 0,
                'evaluados': r['evaluados'] or 0,
                'aciertos':  r['aciertos']  or 0,
                'winrate':   wr(r['aciertos'], r['evaluados'])} for r in rows_f]

    ok({'periodo_dias': dias,
        'desde':        desde,
        'por_fuente':   fuentes,
        'pick_final': {
            'total':            row_c['total']      or 0,
            'evaluados':        row_c['evaluados']  or 0,
            'aciertos':         row_c['aciertos']   or 0,
            'winrate':          wr(row_c['aciertos'],  row_c['evaluados']),
            'alta_winrate':     wr(row_c['alta_ok'],   row_c['alta_total']),
            'media_winrate':    wr(row_c['media_ok'],  row_c['media_total']),
            'consenso_winrate': wr(row_c['cons_ok'],   row_c['cons_total'])
        }})

def setup_inicial(args):
    """
    Configura o actualiza el admin en ~/sports/.env
    Usado por el menú [4] cuando el plan elegido es 'admin'.

    args: {"user_id": "123456789", "forzar": false}

    Respuestas posibles:
      - {"estado": "ya_existe", "admin_actual": "123"} → hay admin, no se reemplazó
      - {"estado": "creado",    "admin_id": "123"}     → .env creado con el ID
      - {"estado": "actualizado","admin_id": "123"}    → .env reemplazado
      - {"estado": "sin_id"}                           → no se pasó user_id, devuelve admin actual
    """
    user_id = str(args.get('user_id', '')).strip()
    forzar  = bool(args.get('forzar', False))

    env_path = os.path.normpath(
        os.path.join(os.path.dirname(DB), '..', '.env')
    )
    # Asegurar que el directorio existe
    os.makedirs(os.path.dirname(env_path), exist_ok=True)

    # Leer admin actual si existe
    admin_actual = None
    if os.path.isfile(env_path):
        try:
            with open(env_path, 'r') as f:
                for linea in f:
                    linea = linea.strip()
                    if linea.startswith('SPORTS_ADMIN_ID='):
                        admin_actual = linea.split('=', 1)[1].strip()
                        break
        except Exception:
            pass

    # Sin user_id → solo consultar estado actual
    if not user_id:
        ok({'estado':        'consulta',
            'admin_actual':  admin_actual,
            'env_existe':    os.path.isfile(env_path),
            'env_path':      env_path})
        return

    # Ya hay admin y no se fuerza el reemplazo
    if admin_actual and not forzar:
        ok({'estado':       'ya_existe',
            'admin_actual': admin_actual,
            'env_path':     env_path})
        return

    # Escribir o reemplazar .env
    estado = 'actualizado' if admin_actual else 'creado'
    try:
        with open(env_path, 'w') as f:
            f.write(f'SPORTS_ADMIN_ID={user_id}\n')
        # Recargar ADMIN_IDS en memoria para esta sesión
        global ADMIN_IDS
        ADMIN_IDS = [user_id]
        ok({'estado':    estado,
            'admin_id':  user_id,
            'env_path':  env_path})
    except Exception as e:
        error(f'No se pudo escribir .env: {e}')


# ─── dispatcher ───────────────────────────────────────────────────────────────

OPERACIONES = {
    # v1/v2
    'verificar_acceso':           verificar_acceso,
    'verificar_cache':            verificar_cache,
    'guardar_analisis_individual': guardar_analisis_individual,
    'verificar_consenso_cache':   verificar_consenso_cache,
    'activar_cache_consenso':     activar_cache_consenso,
    'verificar_job_activo':        verificar_job_activo,
    'crear_job':                  crear_job,
    'leer_job_pendiente':         leer_job_pendiente,
    'leer_stats':                 leer_stats,
    'guardar_prediccion':         guardar_prediccion,
    'guardar_cache':              guardar_cache,
    'actualizar_job':             actualizar_job,
    'verificar_limite':           verificar_limite,
    'guardar_comparativo':        guardar_comparativo,
    # v3
    'verificar_admin':            verificar_admin,
    'gestionar_usuario':          gestionar_usuario,
    'setup_inicial':              setup_inicial,
    'guardar_recomendaciones':    guardar_recomendaciones,
    'leer_recomendaciones':       leer_recomendaciones,
    'leer_pendientes_actualizar': leer_pendientes_actualizar,
    'guardar_resultado':          guardar_resultado,
    'leer_stats_aciertos':        leer_stats_aciertos,
    'leer_aciertos_por_fuente':   leer_aciertos_por_fuente,
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

#!/data/data/com.termux/files/usr/bin/python3
"""
actualizar_resultados.py — Actualiza resultados reales de partidos desde api-football
Ruta: /data/data/com.termux/files/home/sports/scripts/actualizar_resultados.py

Uso:
  # Automático — llamado por WF-E con lista de fixture_ids JSON
  python3 actualizar_resultados.py '["31736329","1774185"]'

  # Manual desde Termux — actualiza los pendientes de hoy o una fecha específica
  python3 actualizar_resultados.py
  python3 actualizar_resultados.py fecha 2026-05-19

Reglas técnicas:
  - NUNCA import requests → urllib.request (builtin)
  - NUNCA /tmp/ → $HOME/
  - NUNCA datetime('now') en SQLite → datetime.now() explícito
"""

import sys
import json
import os
import sqlite3
from datetime import datetime, timedelta
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

# ─── configuración ────────────────────────────────────────────────────────────

DB         = '/data/data/com.termux/files/home/sports/db/bot_deportivo.db'
SCRIPT_DIR = '/data/data/com.termux/files/home/sports/scripts'
DB_QUERY   = os.path.join(SCRIPT_DIR, 'db_query.py')
PYTHON     = '/data/data/com.termux/files/usr/bin/python3'
LOG_FILE   = '/data/data/com.termux/files/home/sports/logs/actualizar_resultados.log'
ENV_FILE   = '/data/data/com.termux/files/home/sports/.env'

API_BASE   = 'https://v3.football.api-sports.io'

# Status de api-football que significan "partido terminado"
STATUS_TERMINADOS = {'FT', 'AET', 'PEN'}
# Status que significan "partido suspendido/cancelado — no tendrá resultado"
STATUS_CANCELADOS = {'CANC', 'PST', 'ABD', 'AWD', 'WO'}

# ─── lectura de .env ──────────────────────────────────────────────────────────

def _leer_env(key):
    """
    Lee una variable del archivo ~/sports/.env
    Formato: KEY=valor  — nunca lanza excepción, devuelve '' si no la encuentra.
    """
    try:
        if not os.path.isfile(ENV_FILE):
            return ''
        with open(ENV_FILE, 'r') as f:
            for linea in f:
                linea = linea.strip()
                if linea.startswith(f'{key}='):
                    return linea.split('=', 1)[1].strip()
    except Exception:
        pass
    return ''

def _get_api_key():
    """
    Devuelve la api-football key desde .env.
    Si no está configurada, termina con error claro.
    """
    key = _leer_env('SPORTS_API_KEY')
    if not key:
        msg = (
            'SPORTS_API_KEY no configurada. '
            f'Agrega en {ENV_FILE}: SPORTS_API_KEY=tu_key_aqui '
            'O usa el menu: Bot Deportivo > [4] Configuracion > [3] Gestionar APIs'
        )
        print(json.dumps({'ok': False, 'error': msg}))
        sys.exit(1)
    return key

# ─── helpers ──────────────────────────────────────────────────────────────────

def now_str():
    return datetime.now().strftime('%Y-%m-%d %H:%M:%S')

def log(msg):
    """Escribe en log y en stdout."""
    linea = f"[{now_str()}] {msg}"
    print(linea)
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, 'a') as f:
            f.write(linea + '\n')
    except Exception:
        pass

def api_get(endpoint):
    """
    GET a api-football v3.
    Usa urllib.request (sin import requests — regla ARM64).
    La key se lee de ~/sports/.env en cada llamada (no en módulo-load).
    Devuelve el dict parsed o None si falla.
    """
    url = f"{API_BASE}/{endpoint}"
    req = Request(url, headers={'x-apisports-key': _get_api_key()})
    try:
        with urlopen(req, timeout=15) as resp:
            raw = resp.read().decode('utf-8')
            return json.loads(raw)
    except HTTPError as e:
        log(f"HTTP {e.code} en {endpoint}")
        return None
    except URLError as e:
        log(f"URLError en {endpoint}: {e.reason}")
        return None
    except Exception as e:
        log(f"Error inesperado en {endpoint}: {e}")
        return None

def conectar_db():
    conn = sqlite3.connect(DB, timeout=5)
    conn.row_factory = sqlite3.Row
    return conn

def leer_pendientes_db(fecha):
    """
    Lee directamente de la BD los comparativos sin resultado_real.
    Fallback si db_query.py no está disponible.
    """
    conn = conectar_db()
    rows = conn.execute(
        """SELECT DISTINCT partido_id, local, visitante, liga, hora_kickoff
           FROM analisis_comparativo
           WHERE fecha = ? AND resultado_real IS NULL
           ORDER BY hora_kickoff ASC""",
        (fecha,)
    ).fetchall()
    conn.close()
    return [{'fixture_id':   r['partido_id'],
             'local':        r['local'],
             'visitante':    r['visitante'],
             'liga':         r['liga'],
             'hora_kickoff': r['hora_kickoff']} for r in rows]

def guardar_resultado_db(fixture_id, local, visitante, liga,
                         goles_local, goles_visitante, status_api,
                         fecha_partido, hora_kickoff):
    """
    Guarda resultado directamente en BD.
    Replica la lógica de db_query.guardar_resultado sin llamada subprocess.
    Más eficiente cuando actualizamos varios partidos en lote.
    """
    if goles_local > goles_visitante:
        ganador = 'local'
    elif goles_visitante > goles_local:
        ganador = 'visitante'
    else:
        ganador = 'empate'

    resultado_str = f"{goles_local}-{goles_visitante}"
    ts            = now_str()

    conn = conectar_db()

    # 1) resultados_partidos
    conn.execute(
        """INSERT OR REPLACE INTO resultados_partidos
           (fixture_id, local, visitante, liga, goles_local, goles_visitante,
            ganador, status_api, fecha_partido, hora_kickoff, actualizado_en)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
        (fixture_id, local, visitante, liga,
         goles_local, goles_visitante, ganador,
         status_api, fecha_partido, hora_kickoff, ts)
    )

    # 2) analisis_comparativo — pick_final
    rows_comp = conn.execute(
        """SELECT id, pick_final FROM analisis_comparativo
           WHERE partido_id = ? AND resultado_real IS NULL""",
        (fixture_id,)
    ).fetchall()

    for row in rows_comp:
        acierto = _pick_acerto(row['pick_final'], ganador, local, visitante)
        conn.execute(
            """UPDATE analisis_comparativo
               SET resultado_real=?, goles_local=?, goles_visitante=?,
                   status_partido=?, pick_correcto=?
               WHERE id=?""",
            (resultado_str, goles_local, goles_visitante,
             status_api, 1 if acierto else 0, row['id'])
        )

    # 3) predicciones — por fuente individual
    rows_pred = conn.execute(
        'SELECT id, pick FROM predicciones WHERE partido_id = ?',
        (fixture_id,)
    ).fetchall()

    for row in rows_pred:
        acierto = _pick_acerto(row['pick'], ganador, local, visitante)
        conn.execute(
            'UPDATE predicciones SET pick_correcto=? WHERE id=?',
            (1 if acierto else 0, row['id'])
        )

    conn.commit()
    conn.close()

    return {
        'fixture_id':    fixture_id,
        'resultado':     resultado_str,
        'ganador':       ganador,
        'comparativos':  len(rows_comp),
        'predicciones':  len(rows_pred)
    }

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

# ─── lógica principal ─────────────────────────────────────────────────────────

def consultar_fixtures(fixture_ids):
    """
    Consulta api-football con lista de IDs en una sola llamada.
    Máximo 20 IDs por llamada (límite de la API).
    Devuelve dict {fixture_id: fixture_data}.
    """
    if not fixture_ids:
        return {}

    resultados = {}
    # Lotes de 20 para respetar el límite de la API
    for i in range(0, len(fixture_ids), 20):
        lote = fixture_ids[i:i+20]
        ids_str = '-'.join(str(fid) for fid in lote)
        data = api_get(f'fixtures?ids={ids_str}')

        if not data or 'response' not in data:
            log(f"Sin respuesta para lote: {ids_str}")
            continue

        for fixture in data['response']:
            fid    = str(fixture['fixture']['id'])
            status = fixture['fixture']['status']['short']
            resultados[fid] = {
                'fixture_id':     fid,
                'status':         status,
                'local':          fixture['teams']['home']['name'],
                'visitante':      fixture['teams']['away']['name'],
                'liga':           fixture['league']['name'],
                'goles_local':    fixture['goals']['home'],
                'goles_visitante':fixture['goals']['away'],
                'fecha':          fixture['fixture']['date'][:10],
                'timestamp':      fixture['fixture']['timestamp'],
            }

    return resultados

def procesar_fixture(fid, datos_api, pendiente_db):
    """
    Procesa un fixture individual.
    Devuelve dict con el resultado del procesamiento.
    """
    status = datos_api['status']

    if status in STATUS_CANCELADOS:
        local_str     = datos_api.get('local')     or pendiente_db.get('local',     '?')
        visitante_str = datos_api.get('visitante') or pendiente_db.get('visitante', '?')
        log(f"  [{fid}] {local_str} vs {visitante_str} — {status} (cancelado/suspendido)")
        # Marcar como cancelado para no volver a consultar
        try:
            conn = conectar_db()
            conn.execute(
                """UPDATE analisis_comparativo
                   SET status_partido=?, resultado_real='CANC'
                   WHERE partido_id=? AND resultado_real IS NULL""",
                (status, fid)
            )
            conn.commit()
            conn.close()
        except Exception as e:
            log(f"  Error marcando cancelado {fid}: {e}")
        return {'fixture_id': fid, 'estado': 'cancelado', 'status': status}

    if status not in STATUS_TERMINADOS:
        log(f"  [{fid}] {datos_api['local']} vs {datos_api['visitante']} — {status} (aún en juego o programado)")
        return {'fixture_id': fid, 'estado': 'pendiente', 'status': status}

    # Partido terminado — guardar resultado
    goles_local     = datos_api['goles_local']     or 0
    goles_visitante = datos_api['goles_visitante'] or 0

    try:
        res = guardar_resultado_db(
            fixture_id      = fid,
            local           = datos_api['local'],
            visitante       = datos_api['visitante'],
            liga            = datos_api['liga'],
            goles_local     = int(goles_local),
            goles_visitante = int(goles_visitante),
            status_api      = status,
            fecha_partido   = datos_api['fecha'],
            hora_kickoff    = pendiente_db.get('hora_kickoff', '')
        )
        log(f"  [{fid}] {datos_api['local']} {goles_local}-{goles_visitante} {datos_api['visitante']}"
            f" — {res['ganador'].upper()} | comp:{res['comparativos']} pred:{res['predicciones']}")
        return {'fixture_id': fid, 'estado': 'actualizado', 'resultado': res}
    except Exception as e:
        log(f"  [{fid}] Error guardando resultado: {e}")
        return {'fixture_id': fid, 'estado': 'error', 'error': str(e)}

def calcular_resumen(procesados):
    """Calcula estadísticas del lote para el mensaje de Telegram."""
    actualizados = [p for p in procesados if p['estado'] == 'actualizado']
    pendientes   = [p for p in procesados if p['estado'] == 'pendiente']
    cancelados   = [p for p in procesados if p['estado'] == 'cancelado']
    errores      = [p for p in procesados if p['estado'] == 'error']
    sin_datos    = [p for p in procesados if p['estado'] == 'sin_datos_api']

    # Calcular aciertos del día desde BD
    aciertos_dia = _leer_aciertos_hoy()

    return {
        'total':        len(procesados),
        'actualizados': len(actualizados),
        'pendientes':   len(pendientes),
        'cancelados':   len(cancelados),
        'errores':      len(errores),
        'sin_datos':    len(sin_datos),
        'aciertos':     aciertos_dia,
    }

def _leer_aciertos_hoy():
    """Lee winrate del día actual desde analisis_comparativo."""
    try:
        hoy  = datetime.now().strftime('%Y-%m-%d')
        conn = conectar_db()
        row  = conn.execute(
            """SELECT
                 COUNT(*) AS evaluados,
                 SUM(CASE WHEN pick_correcto=1 THEN 1 ELSE 0 END) AS aciertos
               FROM analisis_comparativo
               WHERE fecha=? AND pick_correcto IS NOT NULL""",
            (hoy,)
        ).fetchone()
        conn.close()
        evaluados = row['evaluados'] or 0
        aciertos  = row['aciertos']  or 0
        winrate   = round(aciertos / evaluados * 100, 1) if evaluados > 0 else None
        return {'evaluados': evaluados, 'aciertos': aciertos, 'winrate': winrate}
    except Exception:
        return {'evaluados': 0, 'aciertos': 0, 'winrate': None}

def formatear_mensaje_resumen(resumen, fecha):
    """Formatea el mensaje de resumen para Telegram (tu chat personal)."""
    a = resumen['aciertos']
    winrate_str = f"{a['winrate']}%" if a['winrate'] is not None else 'N/D'

    lineas = [
        f"📊 Resultados del día — {fecha}",
        f"━━━━━━━━━━━━━━━━━━━━━━",
        f"✅ Actualizados:  {resumen['actualizados']}/{resumen['total']}",
    ]
    if resumen['pendientes']:
        lineas.append(f"⏳ Aún en juego:  {resumen['pendientes']}")
    if resumen['cancelados']:
        lineas.append(f"🚫 Cancelados:    {resumen['cancelados']}")
    if resumen['errores']:
        lineas.append(f"❌ Errores:       {resumen['errores']}")
    if resumen['sin_datos']:
        lineas.append(f"❓ Sin datos API: {resumen['sin_datos']}")

    lineas += [
        f"━━━━━━━━━━━━━━━━━━━━━━",
        f"🎯 Aciertos hoy:  {a['aciertos']}/{a['evaluados']} ({winrate_str})",
    ]
    return '\n'.join(lineas)

# ─── entry point ──────────────────────────────────────────────────────────────

def main():
    log("══════════════════════════════════════")
    log("actualizar_resultados.py — inicio")

    # ── Determinar lista de fixture_ids a procesar ──
    fixture_ids_input = []
    fecha_consulta    = datetime.now().strftime('%Y-%m-%d')

    if len(sys.argv) >= 2:
        arg = sys.argv[1]

        if arg == 'fecha':
            # Modo manual: python3 actualizar_resultados.py fecha 2026-05-19
            if len(sys.argv) >= 3:
                fecha_consulta = sys.argv[2]
            log(f"Modo manual — fecha: {fecha_consulta}")

        else:
            # Modo WF-E: lista JSON de fixture_ids
            try:
                fixture_ids_input = json.loads(arg)
                if not isinstance(fixture_ids_input, list):
                    raise ValueError("Se esperaba una lista JSON")
                log(f"Modo WF-E — {len(fixture_ids_input)} fixture_ids recibidos")
            except Exception as e:
                log(f"Argumento inválido: {e}")
                print(json.dumps({'ok': False, 'error': str(e)}))
                sys.exit(1)

    # ── Leer pendientes de BD si no vinieron por argumento ──
    pendientes_map = {}  # {fixture_id: datos_db}

    if not fixture_ids_input:
        log(f"Leyendo pendientes de BD para fecha: {fecha_consulta}")
        pendientes_db = leer_pendientes_db(fecha_consulta)
        if not pendientes_db:
            log("Sin partidos pendientes de actualizar")
            print(json.dumps({'ok': True, 'data': {
                'total': 0, 'actualizados': 0,
                'mensaje': 'Sin pendientes'
            }}))
            return
        for p in pendientes_db:
            pendientes_map[p['fixture_id']] = p
        fixture_ids_input = list(pendientes_map.keys())
        log(f"  {len(fixture_ids_input)} pendientes encontrados")
    else:
        # Vienen de WF-E — buscar datos contextuales en BD
        try:
            pendientes_db = leer_pendientes_db(fecha_consulta)
            for p in pendientes_db:
                pendientes_map[p['fixture_id']] = p
        except Exception:
            pass
        # Para IDs que no estén en la BD, crear entrada mínima
        for fid in fixture_ids_input:
            if fid not in pendientes_map:
                pendientes_map[fid] = {'fixture_id': fid, 'hora_kickoff': ''}

    # ── Consultar api-football ──
    log(f"Consultando api-football para {len(fixture_ids_input)} fixtures...")
    datos_api = consultar_fixtures(fixture_ids_input)
    log(f"  API respondió con {len(datos_api)} fixtures")

    # ── Procesar cada fixture ──
    procesados = []
    for fid in fixture_ids_input:
        pendiente = pendientes_map.get(fid, {'fixture_id': fid, 'hora_kickoff': ''})

        if fid not in datos_api:
            log(f"  [{fid}] Sin datos en API — fixture_id no encontrado")
            procesados.append({'fixture_id': fid, 'estado': 'sin_datos_api'})
            continue

        resultado = procesar_fixture(fid, datos_api[fid], pendiente)
        procesados.append(resultado)

    # ── Resumen final ──
    resumen = calcular_resumen(procesados)
    log("──────────────────────────────────────")
    log(f"Resumen: {resumen['actualizados']} actualizados | "
        f"{resumen['pendientes']} pendientes | "
        f"{resumen['errores']} errores")
    log(f"Aciertos hoy: {resumen['aciertos']['aciertos']}/{resumen['aciertos']['evaluados']}"
        f" ({resumen['aciertos']['winrate']}%)")
    log("══════════════════════════════════════")

    # Salida JSON para WF-E
    print(json.dumps({
        'ok':   True,
        'data': {
            'fecha':        fecha_consulta,
            'total':        resumen['total'],
            'actualizados': resumen['actualizados'],
            'pendientes':   resumen['pendientes'],
            'cancelados':   resumen['cancelados'],
            'errores':      resumen['errores'],
            'sin_datos':    resumen['sin_datos'],
            'aciertos':     resumen['aciertos'],
            'mensaje_tg':   formatear_mensaje_resumen(resumen, fecha_consulta),
            'detalle':      procesados
        }
    }, ensure_ascii=False))

if __name__ == '__main__':
    main()

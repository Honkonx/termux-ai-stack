#!/data/data/com.termux/files/usr/bin/python3
"""
datos.py — Orquestador del motor de análisis multi-modelo
Ruta: /data/data/com.termux/files/home/sports/scripts/datos.py

Responsabilidades:
  1. Recibir el JSON crudo de n8n (mismo schema que antes recibía pronostico.py)
  2. Validar y normalizar todos los campos — una sola vez para todos los módulos
  3. Detectar qué módulos tienen datos suficientes
  4. Lanzar en paralelo: pronostico.py, form_recent.py, h2h.py, odds.py, tabla_pos.py
  5. Recoger resultados con timeout por módulo
  6. Llamar a consenso.py con todos los resultados
  7. Emitir dos outputs:
       - bloque_python  → texto formateado para mensaje final (free y premium)
       - bloque_claude  → JSON rico para Claude (solo premium)
  8. Guardar en BD si guardar_en_db=true

Uso desde n8n (execSync) — reemplaza llamada a pronostico.py en wfb-023:
  python3 datos.py '<json_datos>'

Input JSON — mismo schema de siempre:
  {
    "local":                  "Real Madrid",
    "visitante":              "Barcelona",
    "liga":                   "LaLiga",
    "partido_id":             "abc123",
    "goles_local_avg":        1.8,
    "goles_visit_avg":        1.2,
    "goles_contra_local_avg": 0.9,
    "goles_contra_visit_avg": 1.4,
    "liga_goles_avg":         2.6,
    "pos_local":              2,
    "pos_visit":              1,
    "forma_local_wins":       3,
    "forma_visit_wins":       4,
    "h2h_local_wins":         4,
    "h2h_visit_wins":         3,
    "h2h_empates":            3,
    "h2h_total":              10,
    "h2h_disponible":         true,
    "odds_local":             2.10,
    "odds_empate":            3.20,
    "odds_visit":             3.50,
    "odds_disponibles":       true,
    "guardar_en_db":          false
  }

Output JSON:
  {
    "ok": true,
    "pick_final":        "Local",
    "confianza_final":   "ALTA",
    "score_final":       78,
    "consenso_nivel":    "FUERTE",          // FUERTE / MODERADO / DEBIL / SOLO_POISSON
    "consenso_detalle":  "4/5 modelos coinciden en Local",

    // Para mensaje final (free y premium) — texto listo para Telegram/app
    "bloque_python": "📊 *Análisis Estadístico*\n• ...",

    // Para Claude (premium) — JSON rico
    "bloque_claude": {
      "poisson":   { ... },
      "forma":     { ... },
      "h2h":       { ... },
      "odds":      { ... },
      "tabla":     { ... },
      "consenso":  { ... }
    },

    // Compatibilidad con wfb-023 actual (campos que n8n ya usa)
    "pick":              "Local",
    "prob_local":        0.4523,
    "prob_empate":       0.2814,
    "prob_visitante":    0.2663,
    "over25_prob":       0.5821,
    "btts_prob":         0.4932,
    "marcador_probable": "1-0",
    "confianza_score":   78,
    "confianza":         "ALTA",
    "value_bet":         true,
    "value_pct":         9.2,
    "score_para_claude": "...",   // texto plano legado

    // Módulos ejecutados y su estado
    "modulos_ok":        ["poisson", "forma", "h2h", "odds", "tabla"],
    "modulos_skip":      [],
    "modulos_error":     []
  }
"""

import sys
import json
import math
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError as FuturesTimeout
from datetime import datetime

# ─── Rutas ───────────────────────────────────────────────────────────────────

PYTHON_BIN  = '/data/data/com.termux/files/usr/bin/python3'
SCRIPTS_DIR = '/data/data/com.termux/files/home/sports/scripts'
DB_SCRIPT   = f'{SCRIPTS_DIR}/db_query.py'

SCRIPT_POISSON  = f'{SCRIPTS_DIR}/pronostico.py'
SCRIPT_FORMA    = f'{SCRIPTS_DIR}/form_recent.py'
SCRIPT_H2H      = f'{SCRIPTS_DIR}/h2h.py'
SCRIPT_ODDS     = f'{SCRIPTS_DIR}/odds.py'
SCRIPT_TABLA    = f'{SCRIPTS_DIR}/tabla_pos.py'
SCRIPT_CONSENSO = f'{SCRIPTS_DIR}/consenso.py'

# Timeout por módulo en segundos
TIMEOUT_MODULO  = 12
# Timeout total para todos los módulos en paralelo
TIMEOUT_TOTAL   = 20

# ─── Helpers ─────────────────────────────────────────────────────────────────

def salida_ok(data):
    print(json.dumps({'ok': True, **data}, ensure_ascii=False))

def salida_error(msg):
    print(json.dumps({'ok': False, 'error': msg}, ensure_ascii=False))

def safe_float(val, default=0.0):
    try:
        return float(val) if val is not None else default
    except (TypeError, ValueError):
        return default

def safe_int(val, default=0):
    try:
        return int(val) if val is not None else default
    except (TypeError, ValueError):
        return default

def safe_bool(val, default=False):
    if isinstance(val, bool):
        return val
    if isinstance(val, str):
        return val.lower() in ('true', '1', 'yes')
    if isinstance(val, int):
        return val != 0
    return default


# ─── Normalización del JSON de entrada ───────────────────────────────────────

def normalizar(d):
    """
    Normaliza todos los campos del JSON de entrada.
    Devuelve un dict limpio con todos los campos necesarios y sus flags de disponibilidad.
    """
    n = {}

    # ── Identidad del partido ─────────────────────────────────────────────────
    n['local']      = str(d.get('local', 'Local')).strip()
    n['visitante']  = str(d.get('visitante', 'Visitante')).strip()
    n['liga']       = str(d.get('liga', '')).strip()
    n['partido_id'] = str(d.get('partido_id', d.get('match_id', ''))).strip()
    n['job_id']     = str(d.get('job_id', '')).strip()

    # ── Goles promedio ────────────────────────────────────────────────────────
    liga_avg_input = safe_float(d.get('liga_goles_avg'), 0.0)

    n['goles_local_avg']        = safe_float(d.get('goles_local_avg'), 0.0)
    n['goles_visit_avg']        = safe_float(d.get('goles_visit_avg'), 0.0)
    n['goles_contra_local_avg'] = safe_float(d.get('goles_contra_local_avg'), 0.0)
    n['goles_contra_visit_avg'] = safe_float(d.get('goles_contra_visit_avg'), 0.0)
    n['liga_goles_avg']         = liga_avg_input

    # Flag: hay datos de goles reales (no son todos cero)
    n['goles_disponibles'] = (
        n['goles_local_avg'] > 0 or
        n['goles_visit_avg'] > 0
    )

    # ── Forma reciente ────────────────────────────────────────────────────────
    n['forma_local_wins'] = max(0, min(5, safe_int(d.get('forma_local_wins'), 2)))
    n['forma_visit_wins'] = max(0, min(5, safe_int(d.get('forma_visit_wins'), 2)))
    # forma siempre disponible — tiene defaults razonables (2/5)
    n['forma_disponible'] = True

    # ── Posición en tabla ─────────────────────────────────────────────────────
    n['pos_local'] = safe_int(d.get('pos_local'), 10)
    n['pos_visit'] = safe_int(d.get('pos_visit'), 10)
    # Disponible si al menos uno no es el default (10)
    n['tabla_disponible'] = not (n['pos_local'] == 10 and n['pos_visit'] == 10)

    # ── H2H ───────────────────────────────────────────────────────────────────
    n['h2h_disponible'] = safe_bool(d.get('h2h_disponible'), False)
    n['h2h_total']      = safe_int(d.get('h2h_total'), 0)
    n['h2h_local_wins'] = safe_int(d.get('h2h_local_wins'), 0)
    n['h2h_visit_wins'] = safe_int(d.get('h2h_visit_wins'), 0)
    n['h2h_empates']    = safe_int(d.get('h2h_empates'), 0)
    # H2H útil si está disponible y tiene muestra mínima
    n['h2h_util'] = n['h2h_disponible'] and n['h2h_total'] >= 3

    # ── Odds ──────────────────────────────────────────────────────────────────
    n['odds_disponibles'] = safe_bool(d.get('odds_disponibles'), False)
    n['odds_local']       = safe_float(d.get('odds_local'), 0.0)
    n['odds_empate']      = safe_float(d.get('odds_empate'), 0.0)
    n['odds_visit']       = safe_float(d.get('odds_visit'), d.get('odds_visitante', 0.0))
    # Odds útiles si están disponibles y son valores reales (>= 1.01)
    n['odds_util'] = (
        n['odds_disponibles'] and
        n['odds_local'] >= 1.01 and
        n['odds_empate'] >= 1.01 and
        n['odds_visit'] >= 1.01
    )

    # ── Flags de control ─────────────────────────────────────────────────────
    n['guardar_en_db'] = safe_bool(d.get('guardar_en_db'), False)

    return n


# ─── Ejecutar script externo ─────────────────────────────────────────────────

def ejecutar_script(script_path, payload_json, timeout=TIMEOUT_MODULO):
    """
    Ejecuta un script Python con el payload JSON como argumento.
    Devuelve el dict parseado o {'ok': False, 'error': '...'}.
    """
    try:
        # Escapar comillas simples para shell
        payload_escapado = payload_json.replace("'", "'\\''")
        resultado = subprocess.run(
            [PYTHON_BIN, script_path, payload_escapado],
            timeout=timeout,
            capture_output=True,
            encoding='utf-8'
        )
        stdout = resultado.stdout.strip()
        if not stdout:
            stderr = resultado.stderr.strip()
            return {'ok': False, 'error': f'Sin output. stderr: {stderr[:200]}'}
        return json.loads(stdout)
    except subprocess.TimeoutExpired:
        return {'ok': False, 'error': f'Timeout ({timeout}s)'}
    except json.JSONDecodeError as e:
        return {'ok': False, 'error': f'JSON inválido: {str(e)[:100]}'}
    except FileNotFoundError:
        return {'ok': False, 'error': f'Script no encontrado: {script_path}'}
    except Exception as e:
        return {'ok': False, 'error': str(e)[:200]}


# ─── Lanzar módulos en paralelo ──────────────────────────────────────────────

def lanzar_modulos(n, payload_json):
    """
    Lanza en paralelo los módulos disponibles según los datos normalizados.
    Devuelve dict con resultados por nombre de módulo.
    """
    # Definir qué módulos corren y bajo qué condición
    modulos_a_correr = {
        'poisson': SCRIPT_POISSON,   # siempre — tiene defaults para todo
        'forma':   SCRIPT_FORMA,     # siempre — forma siempre disponible
    }

    modulos_skip = []

    # H2H: solo si hay datos útiles
    if n['h2h_util']:
        modulos_a_correr['h2h'] = SCRIPT_H2H
    else:
        modulos_skip.append('h2h')

    # Odds: solo si hay odds reales
    if n['odds_util']:
        modulos_a_correr['odds'] = SCRIPT_ODDS
    else:
        modulos_skip.append('odds')

    # Tabla: solo si hay posiciones reales
    if n['tabla_disponible']:
        modulos_a_correr['tabla'] = SCRIPT_TABLA
    else:
        modulos_skip.append('tabla')

    resultados = {}
    modulos_ok = []
    modulos_error = []

    # Ejecutar en paralelo con ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=5) as executor:
        futuros = {
            executor.submit(ejecutar_script, script, payload_json): nombre
            for nombre, script in modulos_a_correr.items()
        }

        # Recoger resultados con timeout total
        try:
            for futuro in as_completed(futuros, timeout=TIMEOUT_TOTAL):
                nombre = futuros[futuro]
                try:
                    resultado = futuro.result()
                    resultados[nombre] = resultado
                    if resultado.get('ok'):
                        modulos_ok.append(nombre)
                    else:
                        modulos_error.append(nombre)
                        resultados[nombre]['_skip_reason'] = resultado.get('error', 'Error desconocido')
                except Exception as e:
                    resultados[nombre] = {'ok': False, 'error': str(e)[:200]}
                    modulos_error.append(nombre)
        except FuturesTimeout:
            # Algunos módulos no terminaron — marcar los que faltan
            for futuro, nombre in futuros.items():
                if nombre not in resultados:
                    resultados[nombre] = {'ok': False, 'error': 'Timeout total del orquestador'}
                    modulos_error.append(nombre)

    return resultados, modulos_ok, modulos_error, modulos_skip


# ─── Llamar a consenso.py ────────────────────────────────────────────────────

def calcular_consenso(resultados, n):
    """
    Llama a consenso.py con todos los resultados de módulos.
    Si consenso.py no existe aún, usa lógica de consenso básica interna.
    """
    import os
    if os.path.exists(SCRIPT_CONSENSO):
        payload = json.dumps({
            'resultados': resultados,
            'partido': {
                'local':     n['local'],
                'visitante': n['visitante'],
                'liga':      n['liga'],
                'partido_id': n['partido_id'],
            }
        })
        resultado = ejecutar_script(SCRIPT_CONSENSO, payload, timeout=10)
        if resultado.get('ok'):
            return resultado
    # Fallback: consenso básico interno
    return _consenso_basico(resultados, n)


def _consenso_basico(resultados, n):
    """
    Consenso básico cuando consenso.py no existe todavía.
    Cuenta cuántos módulos coinciden en el mismo pick.
    """
    picks = []
    for nombre, res in resultados.items():
        if res.get('ok') and res.get('pick') in ('Local', 'Visitante', 'Empate'):
            picks.append(res['pick'])

    if not picks:
        # Ningún módulo ok — fallback a pick por odds o default Local
        pick_final = 'Local'
        return {
            'ok': True,
            'pick_final':       pick_final,
            'nivel':            'SOLO_FALLBACK',
            'coinciden':        0,
            'total_modulos':    0,
            'detalle':          'Ningún módulo devolvió resultado válido',
            'score_consenso':   30,
            'confianza_final':  'BAJA',
        }

    # Contar votos por pick
    votos = {'Local': 0, 'Visitante': 0, 'Empate': 0}
    for p in picks:
        votos[p] += 1

    pick_final    = max(votos, key=votos.get)
    votos_pick    = votos[pick_final]
    total_modulos = len(picks)

    # Nivel de consenso
    ratio = votos_pick / total_modulos
    if total_modulos == 1:
        nivel = 'SOLO_POISSON'
    elif ratio >= 0.8:
        nivel = 'FUERTE'
    elif ratio >= 0.6:
        nivel = 'MODERADO'
    else:
        nivel = 'DEBIL'

    # Score base del módulo Poisson (el más completo)
    score_base = 50
    if resultados.get('poisson', {}).get('ok'):
        score_base = resultados['poisson'].get('confianza_score', 50)

    # Ajuste por nivel de consenso
    ajuste = {'FUERTE': +10, 'MODERADO': +5, 'DEBIL': -10, 'SOLO_POISSON': 0}
    score_consenso = max(10, min(95, score_base + ajuste.get(nivel, 0)))

    if score_consenso > 60:
        confianza_final = 'ALTA'
    elif score_consenso >= 40:
        confianza_final = 'MEDIA'
    else:
        confianza_final = 'BAJA'

    return {
        'ok':             True,
        'pick_final':     pick_final,
        'nivel':          nivel,
        'coinciden':      votos_pick,
        'total_modulos':  total_modulos,
        'detalle':        f'{votos_pick}/{total_modulos} modelos coinciden en {pick_final}',
        'score_consenso': score_consenso,
        'confianza_final': confianza_final,
        'votos':          votos,
    }


# ─── Construir bloque_python (texto para mensaje final) ──────────────────────

def construir_bloque_python(consenso, resultados, n, modulos_skip):
    """
    Texto formateado para la sección 'Análisis Estadístico' del mensaje final.
    Aparece siempre — en free y en premium (al final del mensaje).
    """
    pick    = consenso.get('pick_final', '?')
    nivel   = consenso.get('nivel', '?')
    coinc   = consenso.get('coinciden', 0)
    total   = consenso.get('total_modulos', 0)
    score   = consenso.get('score_consenso', 0)
    conf    = consenso.get('confianza_final', '?')

    # Emoji por nivel de consenso
    emoji_nivel = {
        'FUERTE':       '🟢',
        'MODERADO':     '🟡',
        'DEBIL':        '🔴',
        'SOLO_POISSON': '⚪',
        'SOLO_FALLBACK':'⚫',
    }.get(nivel, '⚪')

    # Emoji de confianza
    emoji_conf = {'ALTA': '🔥', 'MEDIA': '📊', 'BAJA': '⚠️'}.get(conf, '📊')

    lineas = ['📊 *Análisis Estadístico*']

    # Consenso (línea principal)
    lineas.append(
        f'• Consenso: {emoji_nivel} *{nivel}* {pick} ({coinc}/{total} coinciden)'
    )

    # Confianza y score
    lineas.append(f'• Confianza: {emoji_conf} {conf} ({score}/100)')

    # Datos de Poisson si están disponibles (Over/BTTS/Marcador son exclusivos de Poisson)
    poisson = resultados.get('poisson', {})
    if poisson.get('ok'):
        over25 = poisson.get('over25_prob', 0)
        btts   = poisson.get('btts_prob', 0)
        marc   = poisson.get('marcador_probable', '?-?')

        if over25 > 0:
            lineas.append(
                f'• Over 2.5: {round(over25*100,1)}% | '
                f'BTTS: {round(btts*100,1)}%'
            )
        if marc and marc != '?-?':
            lineas.append(f'• Marcador probable: {marc}')

        # Value bet si existe
        if poisson.get('value_bet') and poisson.get('value_pct', 0) > 0:
            lineas.append(f'• 💰 Value bet: +{poisson["value_pct"]}%')

    # Módulos no disponibles (info transparente)
    if modulos_skip:
        etiquetas = {
            'h2h':   'H2H',
            'odds':  'Odds',
            'tabla': 'Tabla',
        }
        no_disp = [etiquetas.get(m, m) for m in modulos_skip]
        if no_disp:
            lineas.append(f'• Sin datos: {", ".join(no_disp)}')

    return '\n'.join(lineas)


# ─── Construir bloque_claude (JSON rico para Claude) ─────────────────────────

def construir_bloque_claude(consenso, resultados, n):
    """
    JSON estructurado para inyectar en el prompt de Claude.
    Claude usa esto para razonar con datos completos.
    """
    bloque = {}

    # Cada módulo disponible
    for nombre in ('poisson', 'forma', 'h2h', 'odds', 'tabla'):
        res = resultados.get(nombre, {})
        if res.get('ok'):
            # Incluir solo los campos relevantes para Claude (sin ruido interno)
            bloque[nombre] = _campos_claude(nombre, res)
        else:
            bloque[nombre] = {
                'disponible': False,
                'razon': res.get('error', 'No ejecutado') if res else 'No ejecutado'
            }

    # Consenso
    bloque['consenso'] = {
        'pick_final':    consenso.get('pick_final', '?'),
        'nivel':         consenso.get('nivel', '?'),
        'coinciden':     consenso.get('coinciden', 0),
        'total_modulos': consenso.get('total_modulos', 0),
        'detalle':       consenso.get('detalle', ''),
        'score':         consenso.get('score_consenso', 0),
        'confianza':     consenso.get('confianza_final', '?'),
    }

    # Contexto del partido
    bloque['partido'] = {
        'local':           n['local'],
        'visitante':       n['visitante'],
        'liga':            n['liga'],
        'odds_disponibles': n['odds_util'],
        'h2h_disponible':  n['h2h_util'],
        'tabla_disponible': n['tabla_disponible'],
    }

    return bloque


def _campos_claude(nombre, res):
    """Extrae campos relevantes por módulo para bloque_claude."""
    base = {
        'disponible':     True,
        'pick':           res.get('pick'),
        'prob_local':     res.get('prob_local'),
        'prob_empate':    res.get('prob_empate'),
        'prob_visitante': res.get('prob_visitante'),
        'confianza':      res.get('confianza'),
        'score':          res.get('confianza_score'),
    }

    if nombre == 'poisson':
        base.update({
            'motor':             res.get('motor'),
            'lambda_local':      res.get('lambda_local'),
            'lambda_visit':      res.get('lambda_visit'),
            'over25_prob':       res.get('over25_prob'),
            'btts_prob':         res.get('btts_prob'),
            'marcador_probable': res.get('marcador_probable'),
            'value_bet':         res.get('value_bet'),
            'value_pct':         res.get('value_pct'),
            'dixon_coles':       res.get('dixon_coles'),  # cuando se implemente
            'penalizaciones':    res.get('penalizaciones', []),
            'bonificaciones':    res.get('bonificaciones', []),
        })

    elif nombre == 'forma':
        base.update({
            'forma_local_wins': res.get('forma_local_wins'),
            'forma_visit_wins': res.get('forma_visit_wins'),
        })

    elif nombre == 'h2h':
        base.update({
            'h2h_local_wins': res.get('h2h_local_wins'),
            'h2h_visit_wins': res.get('h2h_visit_wins'),
            'h2h_empates':    res.get('h2h_empates'),
            'h2h_total':      res.get('h2h_total'),
            'dominancia':     res.get('dominancia'),
            'tendencia':      res.get('tendencia'),
        })

    elif nombre == 'odds':
        base.update({
            'odds_local':     res.get('odds_local'),
            'odds_empate':    res.get('odds_empate'),
            'odds_visit':     res.get('odds_visit'),
            'prob_impl_local':  res.get('prob_impl_local'),
            'prob_impl_empate': res.get('prob_impl_empate'),
            'prob_impl_visit':  res.get('prob_impl_visit'),
            'overround':        res.get('overround'),
            'value_bet':        res.get('value_bet'),
            'value_pct':        res.get('value_pct'),
        })

    elif nombre == 'tabla':
        base.update({
            'pos_local':   res.get('pos_local'),
            'pos_visit':   res.get('pos_visit'),
            'brecha_pos':  res.get('brecha_pos'),
            'favorito_tabla': res.get('favorito_tabla'),
        })

    # Eliminar None para no ensuciar el JSON de Claude
    return {k: v for k, v in base.items() if v is not None}


# ─── Campos de compatibilidad con wfb-023 ────────────────────────────────────

def campos_compatibilidad(consenso, resultados):
    """
    Devuelve los campos que wfb-023 espera encontrar hoy en el output.
    Mantiene compatibilidad mientras se migra el workflow.
    """
    poisson = resultados.get('poisson', {})

    # score_para_claude legado (texto plano)
    score_texto = f"Consenso {consenso.get('nivel','?')}: {consenso.get('detalle','')} | Score: {consenso.get('score_consenso',0)}/100"
    if poisson.get('ok'):
        pL  = round(poisson.get('prob_local', 0) * 100, 1)
        pE  = round(poisson.get('prob_empate', 0) * 100, 1)
        pV  = round(poisson.get('prob_visitante', 0) * 100, 1)
        o25 = round(poisson.get('over25_prob', 0) * 100, 1)
        bt  = round(poisson.get('btts_prob', 0) * 100, 1)
        score_texto += (
            f" | Poisson: Local {pL}% Empate {pE}% Visit {pV}%"
            f" | Over2.5 {o25}% | BTTS {bt}%"
        )

    return {
        # Pick y probabilidades del módulo Poisson (el más completo)
        'pick':              consenso.get('pick_final', poisson.get('pick', '?')),
        'prob_local':        poisson.get('prob_local',     0),
        'prob_empate':       poisson.get('prob_empate',    0),
        'prob_visitante':    poisson.get('prob_visitante', 0),
        'over25_prob':       poisson.get('over25_prob',    0),
        'btts_prob':         poisson.get('btts_prob',      0),
        'marcador_probable': poisson.get('marcador_probable', '?-?'),
        'confianza_score':   consenso.get('score_consenso', 0),
        'confianza':         consenso.get('confianza_final', 'BAJA'),
        'value_bet':         poisson.get('value_bet',  False),
        'value_pct':         poisson.get('value_pct',  0.0),
        'score_para_claude': score_texto,
    }


# ─── Guardar en BD ────────────────────────────────────────────────────────────

def guardar_en_bd(resultado_final, n):
    """
    Guarda el análisis completo en BD via db_query.py guardar_prediccion.
    Guarda el bloque_claude completo como texto_completo para el agente IA.
    """
    args = json.dumps({
        'partido_id':     n['partido_id'],
        'fuente':         'datos_multimodelo',
        'pick':           resultado_final.get('pick_final', '?'),
        'confianza':      resultado_final.get('confianza_final', 'BAJA'),
        'score':          resultado_final.get('score_final', 0),
        'razonamiento':   resultado_final.get('score_para_claude', ''),
        # bloque_claude completo → agente IA tiene todos los datos
        'texto_completo': json.dumps(resultado_final.get('bloque_claude', {}), ensure_ascii=False),
        'job_id':         n['job_id'],
    })
    try:
        subprocess.run(
            [PYTHON_BIN, DB_SCRIPT, 'guardar_prediccion', args],
            timeout=8,
            capture_output=True
        )
    except Exception:
        pass  # No fallar el análisis si falla el guardado


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        salida_error("Uso: datos.py '<json_datos>'")
        sys.exit(1)

    # 1. Parsear JSON de entrada
    try:
        datos_crudos = json.loads(sys.argv[1])
    except json.JSONDecodeError as e:
        salida_error(f'JSON inválido: {e}')
        sys.exit(1)

    try:
        # 2. Normalizar
        n = normalizar(datos_crudos)

        # 3. Construir payload JSON para los módulos
        #    Mismo schema que antes recibía pronostico.py — compatibilidad total
        payload = {
            'local':                  n['local'],
            'visitante':              n['visitante'],
            'liga':                   n['liga'],
            'partido_id':             n['partido_id'],
            'goles_local_avg':        n['goles_local_avg'],
            'goles_visit_avg':        n['goles_visit_avg'],
            'goles_contra_local_avg': n['goles_contra_local_avg'],
            'goles_contra_visit_avg': n['goles_contra_visit_avg'],
            'liga_goles_avg':         n['liga_goles_avg'],
            'pos_local':              n['pos_local'],
            'pos_visit':              n['pos_visit'],
            'forma_local_wins':       n['forma_local_wins'],
            'forma_visit_wins':       n['forma_visit_wins'],
            'h2h_local_wins':         n['h2h_local_wins'],
            'h2h_visit_wins':         n['h2h_visit_wins'],
            'h2h_empates':            n['h2h_empates'],
            'h2h_total':              n['h2h_total'],
            'h2h_disponible':         n['h2h_disponible'],
            'odds_local':             n['odds_local']  if n['odds_util'] else None,
            'odds_empate':            n['odds_empate'] if n['odds_util'] else None,
            'odds_visit':             n['odds_visit']  if n['odds_util'] else None,
            'odds_disponibles':       n['odds_util'],
            'guardar_en_db':          False,  # datos.py maneja el guardado
        }
        payload_json = json.dumps(payload, ensure_ascii=False)

        # 4. Lanzar módulos en paralelo
        resultados, modulos_ok, modulos_error, modulos_skip = lanzar_modulos(n, payload_json)

        # 5. Consenso
        consenso = calcular_consenso(resultados, n)

        # 6. Construir outputs
        bloque_python = construir_bloque_python(consenso, resultados, n, modulos_skip)
        bloque_claude = construir_bloque_claude(consenso, resultados, n)
        compat        = campos_compatibilidad(consenso, resultados)

        # 7. Resultado final
        resultado_final = {
            # Campos principales
            'pick_final':      consenso.get('pick_final', '?'),
            'confianza_final': consenso.get('confianza_final', 'BAJA'),
            'score_final':     consenso.get('score_consenso', 0),
            'consenso_nivel':  consenso.get('nivel', '?'),
            'consenso_detalle': consenso.get('detalle', ''),

            # Los dos outputs
            'bloque_python': bloque_python,
            'bloque_claude': bloque_claude,

            # Compatibilidad con wfb-023
            **compat,

            # Diagnóstico
            'modulos_ok':    modulos_ok,
            'modulos_skip':  modulos_skip,
            'modulos_error': modulos_error,
            'timestamp':     datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
        }

        # 8. Guardar en BD si se solicita
        if n['guardar_en_db'] and n['partido_id']:
            guardar_en_bd(resultado_final, n)

        salida_ok(resultado_final)

    except Exception as e:
        salida_error(f'Error en orquestador: {str(e)}')
        sys.exit(1)

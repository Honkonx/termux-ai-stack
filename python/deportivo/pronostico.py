#!/data/data/com.termux/files/usr/bin/python3
"""
pronostico.py — Motor de análisis estadístico deportivo
Ruta: /data/data/com.termux/files/home/sports/scripts/pronostico.py

Diseño dual:
  - Sin scipy/numpy  → Poisson con math puro (Termux ARM64)
  - Con scipy/numpy  → Poisson bivariante completo (Docker/VPS/PC)
  - Con scikit-learn → Regresión logística (si hay modelo entrenado)

Uso desde n8n (execSync):
  python3 pronostico.py '<json_datos>'

Input JSON requerido:
  {
    "local":                  "Real Madrid",
    "visitante":              "Barcelona",
    "liga":                   "LaLiga",
    "fecha":                  "20260516",

    // Estadísticas de ataque/defensa (promedio últimos 10 partidos)
    "goles_local_avg":        1.8,   // goles por partido anotados como local
    "goles_visit_avg":        1.2,   // goles por partido anotados como visitante
    "goles_contra_local_avg": 0.9,   // goles recibidos como local
    "goles_contra_visit_avg": 1.4,   // goles recibidos como visitante
    "liga_goles_avg":         2.6,   // promedio de goles por partido en la liga

    // Contexto del partido
    "pos_local":              2,     // posición en tabla del local
    "pos_visit":              1,     // posición en tabla del visitante
    "forma_local_wins":       3,     // victorias en últimos 5 partidos (local)
    "forma_visit_wins":       4,     // victorias en últimos 5 partidos (visitante)

    // H2H (puede ser 0 si no está disponible)
    "h2h_local_wins":         4,
    "h2h_visit_wins":         3,
    "h2h_empates":            3,
    "h2h_total":              10,
    "h2h_disponible":         true,

    // Odds (puede ser null si no están disponibles)
    "odds_local":             2.10,
    "odds_empate":            3.20,
    "odds_visit":             3.50,
    "odds_disponibles":       true,

    // Flags opcionales
    "partido_id":             "abc123",
    "guardar_en_db":          false   // true = llama a db_query.py al final
  }

Output JSON:
  {
    "ok": true,
    "motor": "scipy" | "math_puro",
    "pick": "Local" | "Visitante" | "Empate",
    "prob_local":     0.4523,
    "prob_empate":    0.2814,
    "prob_visitante": 0.2663,
    "lambda_local":   1.72,
    "lambda_visit":   1.09,
    "over25_prob":    0.5821,
    "btts_prob":      0.4932,
    "value_bet":      true,
    "value_pct":      8.5,
    "confianza_score": 74,
    "confianza":      "ALTA" | "MEDIA" | "BAJA",
    "marcador_probable": "1-1",
    "score_para_claude": "Score estadístico: 74/100 | Poisson: Local 45.2% Empate 28.1% Visitante 26.7% | λ local=1.72 visit=1.09 | Over2.5: 58.2% | BTTS: 49.3% | Value bet: +8.5%",
    "penalizaciones": ["H2H no disponible: -15", ...]
  }
"""

import sys
import json
import math
from datetime import datetime

# ─── Detección de dependencias opcionales ────────────────────────────────────

try:
    import numpy as np
    from scipy.stats import poisson as sp_poisson
    MOTOR = 'scipy'
except ImportError:
    MOTOR = 'math_puro'

try:
    import joblib
    import os
    JOBLIB_OK = True
except ImportError:
    JOBLIB_OK = False

SCRIPT_DIR = '/data/data/com.termux/files/home/sports/scripts'
DB_SCRIPT  = '/data/data/com.termux/files/home/sports/scripts/db_query.py'
PYTHON_BIN = '/data/data/com.termux/files/usr/bin/python3'
MODEL_PATH = f'{SCRIPT_DIR}/../models/logistic_1x2.pkl'

# ─── Utilidades ──────────────────────────────────────────────────────────────

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

# ─── Poisson con math puro (sin numpy/scipy) ─────────────────────────────────

def poisson_pmf(k, lam):
    """P(X=k) para distribución Poisson con parámetro lam."""
    if lam <= 0:
        return 1.0 if k == 0 else 0.0
    return math.exp(-lam) * (lam ** k) / math.factorial(k)

def calcular_poisson_math(lambda_local, lambda_visit, max_goles=10):
    """
    Genera la matriz de probabilidades de marcadores.
    Devuelve prob_local, prob_empate, prob_visit, over25, btts, marcador_probable.
    """
    matriz = []
    for i in range(max_goles):
        fila = []
        for j in range(max_goles):
            fila.append(poisson_pmf(i, lambda_local) * poisson_pmf(j, lambda_visit))
        matriz.append(fila)

    prob_local    = sum(matriz[i][j] for i in range(max_goles) for j in range(max_goles) if i > j)
    prob_empate   = sum(matriz[i][i] for i in range(max_goles))
    prob_visitante= sum(matriz[i][j] for i in range(max_goles) for j in range(max_goles) if j > i)

    over25_prob = 1.0 - sum(
        matriz[i][j]
        for i in range(max_goles)
        for j in range(max_goles)
        if i + j <= 2
    )

    btts_prob = (1 - poisson_pmf(0, lambda_local)) * (1 - poisson_pmf(0, lambda_visit))

    # Marcador más probable
    max_prob = 0
    marcador = '1-1'
    for i in range(min(5, max_goles)):
        for j in range(min(5, max_goles)):
            if matriz[i][j] > max_prob:
                max_prob = matriz[i][j]
                marcador = f'{i}-{j}'

    return prob_local, prob_empate, prob_visitante, over25_prob, btts_prob, marcador

# ─── Poisson con scipy/numpy (más preciso) ───────────────────────────────────

def calcular_poisson_scipy(lambda_local, lambda_visit, max_goles=10):
    """Misma lógica pero usando scipy para mayor precisión numérica."""
    pmf_local = [sp_poisson.pmf(i, lambda_local) for i in range(max_goles)]
    pmf_visit = [sp_poisson.pmf(i, lambda_visit) for i in range(max_goles)]
    matriz = np.outer(pmf_local, pmf_visit)

    prob_local     = float(np.sum(np.tril(matriz, -1)))
    prob_empate    = float(np.sum(np.diag(matriz)))
    prob_visitante = float(np.sum(np.triu(matriz, 1)))

    over25_prob = 1.0 - float(sum(
        matriz[i][j]
        for i in range(max_goles)
        for j in range(max_goles)
        if i + j <= 2
    ))

    btts_prob = float(
        (1 - sp_poisson.pmf(0, lambda_local)) *
        (1 - sp_poisson.pmf(0, lambda_visit))
    )

    # Marcador más probable
    idx = np.unravel_index(np.argmax(matriz[:5, :5]), (5, 5))
    marcador = f'{idx[0]}-{idx[1]}'

    return prob_local, prob_empate, prob_visitante, over25_prob, btts_prob, marcador

# ─── Calcular lambdas ────────────────────────────────────────────────────────

def calcular_lambdas(d):
    """
    Fórmula Dixon-Coles simplificada.
    Fuerza de ataque = goles_propios / liga_avg
    Debilidad defensa = goles_recibidos_rival / liga_avg
    Lambda = ataque_propio * debilidad_defensa_rival * liga_avg
    """
    liga_avg = safe_float(d.get('liga_goles_avg'), 2.6)
    if liga_avg <= 0:
        liga_avg = 2.6

    # Ataque y defensa normalizados
    ataque_local  = safe_float(d.get('goles_local_avg'), 1.3) / liga_avg
    defensa_visit = safe_float(d.get('goles_contra_visit_avg'), 1.3) / liga_avg

    ataque_visit  = safe_float(d.get('goles_visit_avg'), 1.0) / liga_avg
    defensa_local = safe_float(d.get('goles_contra_local_avg'), 1.0) / liga_avg

    lambda_local = ataque_local * defensa_visit * liga_avg
    lambda_visit = ataque_visit * defensa_local * liga_avg

    # Clamp: entre 0.3 y 5.0 (valores imposibles = datos faltantes)
    lambda_local = max(0.3, min(5.0, lambda_local))
    lambda_visit = max(0.3, min(5.0, lambda_visit))

    return round(lambda_local, 3), round(lambda_visit, 3)

# ─── Score de confianza ──────────────────────────────────────────────────────

def calcular_confianza(d, prob_ganador, over25_prob, value_pct):
    """
    Sistema de puntuación basado en MEJORAS-BOT.md sección 2.4 y Apéndice B.
    Base: 50 puntos. Rango final: 10-95.
    """
    score = 50
    penalizaciones = []
    bonificaciones = []

    odds_local  = safe_float(d.get('odds_local'))
    odds_visit  = safe_float(d.get('odds_visit'))
    odds_disponibles = d.get('odds_disponibles', True)

    # ── Odds (favorito claro) ──
    if odds_disponibles and odds_local > 0:
        mejor_odds = min(odds_local, odds_visit) if odds_visit > 0 else odds_local
        if mejor_odds < 1.5:
            score += 15
            bonificaciones.append('Favorito claro (odds < 1.5): +15')
        elif mejor_odds < 1.8:
            score += 8
            bonificaciones.append('Favorito moderado (odds < 1.8): +8')
        elif mejor_odds > 2.5:
            score -= 10
            penalizaciones.append('Partido abierto (odds > 2.5): -10')
    else:
        score -= 10
        penalizaciones.append('Odds no disponibles: -10')

    # ── Forma reciente ──
    forma_local = safe_int(d.get('forma_local_wins'), 0)
    forma_visit = safe_int(d.get('forma_visit_wins'), 0)

    if forma_local >= 4:
        score += 10
        bonificaciones.append('Forma local excelente (4-5W): +10')
    elif forma_local <= 1:
        score -= 8
        penalizaciones.append('Forma local pobre (0-1W): -8')

    if forma_visit >= 4:
        score -= 8
        penalizaciones.append('Forma visitante excelente (contra nosotros): -8')

    # ── H2H ──
    h2h_disponible = d.get('h2h_disponible', True)
    h2h_total = safe_int(d.get('h2h_total'), 0)

    if not h2h_disponible or h2h_total == 0:
        score -= 15
        penalizaciones.append('H2H no disponible: -15')
    else:
        h2h_local_wins = safe_int(d.get('h2h_local_wins'), 0)
        h2h_ratio = h2h_local_wins / max(h2h_total, 1)
        if h2h_ratio > 0.6:
            score += 10
            bonificaciones.append('H2H favorable (>60% victorias): +10')
        elif h2h_ratio < 0.3:
            score -= 5
            penalizaciones.append('H2H desfavorable (<30% victorias): -5')

    # ── Posición tabla ──
    pos_local = safe_int(d.get('pos_local'), 10)
    pos_visit = safe_int(d.get('pos_visit'), 10)

    if pos_local < 5 and pos_visit > 15:
        score += 15
        bonificaciones.append('Dominio de tabla (top5 vs bottom5): +15')
    elif pos_local > 15 and pos_visit < 5:
        score -= 15
        penalizaciones.append('Desventaja de tabla (bottom5 vs top5): -15')
    elif pos_local < pos_visit:
        score += 5
        bonificaciones.append('Local mejor ubicado en tabla: +5')

    # ── Probabilidad Poisson alta ──
    if prob_ganador > 0.55:
        score += 8
        bonificaciones.append(f'Poisson alta confianza ({round(prob_ganador*100,1)}%): +8')
    elif prob_ganador < 0.35:
        score -= 8
        penalizaciones.append(f'Poisson baja confianza ({round(prob_ganador*100,1)}%): -8')

    # ── Value bet ──
    if value_pct > 5:
        score += 5
        bonificaciones.append(f'Value bet detectado (+{round(value_pct,1)}%): +5')

    # Clamp 10-95
    score = max(10, min(95, score))

    return score, penalizaciones, bonificaciones

# ─── Value bet ───────────────────────────────────────────────────────────────

def calcular_value_bet(prob_real, odds):
    """
    Value = (prob_real * odds - 1) * 100
    Positivo = hay valor. Negativo = no hay valor.
    """
    if not odds or odds <= 0:
        return False, 0.0
    value = (prob_real * odds - 1) * 100
    return value > 3.0, round(value, 2)  # umbral: 3% mínimo

# ─── Core del análisis ───────────────────────────────────────────────────────

def analizar(d):
    # 1. Calcular lambdas
    lambda_local, lambda_visit = calcular_lambdas(d)

    # 2. Distribución Poisson (motor según disponibilidad)
    if MOTOR == 'scipy':
        prob_local, prob_empate, prob_visit, over25, btts, marcador = \
            calcular_poisson_scipy(lambda_local, lambda_visit)
    else:
        prob_local, prob_empate, prob_visit, over25, btts, marcador = \
            calcular_poisson_math(lambda_local, lambda_visit)

    # 3. Pick principal
    probs = {'Local': prob_local, 'Empate': prob_empate, 'Visitante': prob_visit}
    pick = max(probs, key=probs.get)
    prob_ganador = probs[pick]

    # 4. Value bet del pick principal
    odds_map = {
        'Local':     safe_float(d.get('odds_local')),
        'Empate':    safe_float(d.get('odds_empate')),
        'Visitante': safe_float(d.get('odds_visit')),
    }
    odds_pick = odds_map.get(pick, 0)
    value_bet, value_pct = calcular_value_bet(prob_ganador, odds_pick)

    # 5. Score de confianza
    confianza_score, penalizaciones, bonificaciones = calcular_confianza(
        d, prob_ganador, over25, value_pct
    )

    if confianza_score > 60:
        confianza = 'ALTA'
    elif confianza_score >= 40:
        confianza = 'MEDIA'
    else:
        confianza = 'BAJA'

    # 6. Texto para inyectar en prompt Claude (Apéndice A de PLAN-BOT-V2.md)
    score_para_claude = (
        f"Score estadístico: {confianza_score}/100 | "
        f"Motor: {MOTOR} | "
        f"Poisson: Local {round(prob_local*100,1)}% "
        f"Empate {round(prob_empate*100,1)}% "
        f"Visitante {round(prob_visit*100,1)}% | "
        f"λ local={lambda_local} visit={lambda_visit} | "
        f"Over2.5: {round(over25*100,1)}% | "
        f"BTTS: {round(btts*100,1)}%"
        + (f" | Value bet pick: +{value_pct}%" if value_bet else "")
    )

    resultado = {
        'motor':            MOTOR,
        'pick':             pick,
        'prob_local':       round(prob_local, 4),
        'prob_empate':      round(prob_empate, 4),
        'prob_visitante':   round(prob_visit, 4),
        'lambda_local':     lambda_local,
        'lambda_visit':     lambda_visit,
        'over25_prob':      round(over25, 4),
        'btts_prob':        round(btts, 4),
        'value_bet':        value_bet,
        'value_pct':        value_pct,
        'odds_pick':        odds_pick,
        'confianza_score':  confianza_score,
        'confianza':        confianza,
        'marcador_probable':marcador,
        'score_para_claude':score_para_claude,
        'penalizaciones':   penalizaciones,
        'bonificaciones':   bonificaciones,
        'partido_id':       str(d.get('partido_id', '')),
        'local':            str(d.get('local', '')),
        'visitante':        str(d.get('visitante', '')),
        'liga':             str(d.get('liga', '')),
    }

    # 7. Guardar en BD si se solicita
    if d.get('guardar_en_db') and d.get('partido_id'):
        _guardar_en_db(resultado, d)

    return resultado

# ─── Guardar en BD (opcional) ────────────────────────────────────────────────

def _guardar_en_db(resultado, d):
    """Llama a db_query.py para guardar la predicción estadística."""
    import subprocess
    args = json.dumps({
        'partido_id':   resultado['partido_id'],
        'fuente':       f"python_poisson_{MOTOR}",
        'pick':         resultado['pick'],
        'confianza':    resultado['confianza'],
        'score':        resultado['confianza_score'],
        'razonamiento': resultado['score_para_claude'],
        'texto_completo': json.dumps(resultado, ensure_ascii=False),
        'job_id':       str(d.get('job_id', ''))
    })
    try:
        subprocess.run(
            [PYTHON_BIN, DB_SCRIPT, 'guardar_prediccion', args],
            timeout=8,
            capture_output=True
        )
    except Exception:
        pass  # No fallar el análisis si falla el guardado

# ─── Regresión logística (si hay modelo entrenado) ──────────────────────────

def analizar_logistico(d):
    """
    Usa modelo entrenado si existe.
    Sin modelo: devuelve None (el caller usa solo Poisson).
    Solo disponible si scikit-learn está instalado.
    """
    if not JOBLIB_OK:
        return None
    try:
        import numpy as np
        from sklearn.linear_model import LogisticRegression

        if not os.path.exists(MODEL_PATH):
            return None

        model = joblib.load(MODEL_PATH)
        features = np.array([[
            safe_int(d.get('pos_local'), 10) - safe_int(d.get('pos_visit'), 10),
            safe_int(d.get('forma_local_wins'), 0) - safe_int(d.get('forma_visit_wins'), 0),
            safe_int(d.get('h2h_local_wins'), 0) / max(safe_int(d.get('h2h_total'), 1), 1),
            1 / safe_float(d.get('odds_local'), 2) if safe_float(d.get('odds_local')) > 0 else 0.5,
            1 / safe_float(d.get('odds_empate'), 3) if safe_float(d.get('odds_empate')) > 0 else 0.33,
            safe_float(d.get('goles_local_avg'), 1.3) - safe_float(d.get('goles_visit_avg'), 1.0),
            1.0 if d.get('h2h_disponible', True) else 0.0,
        ]])
        probs = model.predict_proba(features)[0]
        clases = list(model.classes_)
        prob_dict = dict(zip(clases, [round(float(p), 4) for p in probs]))
        pick = max(prob_dict, key=prob_dict.get)
        return {'pick': pick, 'probabilidades': prob_dict, 'modelo_entrenado': True}
    except Exception as e:
        return {'error': str(e), 'modelo_entrenado': False}

# ─── Consenso Poisson + Logístico ────────────────────────────────────────────

def calcular_consenso(resultado_poisson, resultado_logistico):
    """
    Reglas de PLAN-BOT-V2.md Apéndice B.
    """
    if not resultado_logistico or resultado_logistico.get('error'):
        return {
            'nivel': 'SOLO_POISSON',
            'ajuste_score': 0,
            'detalle': 'Modelo logístico no disponible'
        }

    pick_poisson   = resultado_poisson['pick']
    pick_logistico = resultado_logistico['pick']

    if pick_poisson == pick_logistico:
        return {
            'nivel': 'ALTO',
            'ajuste_score': 0,
            'detalle': f'Ambos modelos coinciden en {pick_poisson}'
        }
    else:
        return {
            'nivel': 'BAJO',
            'ajuste_score': -15,
            'detalle': f'Divergencia: Poisson={pick_poisson} vs Logístico={pick_logistico}'
        }

# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        salida_error('Uso: pronostico.py \'<json_datos>\'')
        sys.exit(1)

    try:
        datos = json.loads(sys.argv[1])
    except json.JSONDecodeError as e:
        salida_error(f'JSON inválido: {e}')
        sys.exit(1)

    try:
        # Análisis Poisson principal
        resultado = analizar(datos)

        # Análisis logístico si hay modelo entrenado
        resultado_logistico = analizar_logistico(datos)

        # Consenso
        consenso = calcular_consenso(resultado, resultado_logistico)

        # Aplicar ajuste de consenso al score
        score_final = max(10, min(95,
            resultado['confianza_score'] + consenso['ajuste_score']
        ))
        resultado['confianza_score'] = score_final
        resultado['consenso'] = consenso

        # Reajustar confianza después del consenso
        if score_final > 60:
            resultado['confianza'] = 'ALTA'
        elif score_final >= 40:
            resultado['confianza'] = 'MEDIA'
        else:
            resultado['confianza'] = 'BAJA'

        # Agregar logístico si está disponible
        if resultado_logistico:
            resultado['modelo_logistico'] = resultado_logistico

        salida_ok(resultado)

    except Exception as e:
        salida_error(f'Error en análisis: {str(e)}')
        sys.exit(1)

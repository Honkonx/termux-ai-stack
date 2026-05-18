#!/data/data/com.termux/files/usr/bin/python3
"""
pronostico.py — Motor de análisis estadístico deportivo
Ruta: /data/data/com.termux/files/home/sports/scripts/pronostico.py

Diseño dual:
  - Sin scipy/numpy  → Poisson con math puro (Termux ARM64)
  - Con scipy/numpy  → Poisson bivariante completo (Docker/VPS/PC)
  - Con scikit-learn → Regresión logística (si hay modelo entrenado)

Mejoras v2 (M4a-M4f):
  - M4a: Tabla de promedios por liga (fallback cuando liga_avg es dudoso)
  - M4b: Pesos dinámicos en lambdas según calidad de muestra
  - M4c: Home advantage factor (+0.35 goles en casa)
  - M4d: Penalización por contradicción H2H vs Poisson
  - M4e: Umbral value bet subido a 8%
  - M4f: Cap de score por datos escasos

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
    "score_para_claude": "Score estadístico: 74/100 | ...",
    "penalizaciones": ["H2H no disponible: -15", ...],
    "bonificaciones": [...]
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

# ─── M4a: Tabla de promedios históricos por liga ─────────────────────────────
# Fuente: promedios históricos 2022-2025. Matching por subcadena en liga.lower().

HOME_ADVANTAGE = 0.35  # M4c: goles extra promedio jugando en casa (global)

LIGA_AVG = {
    # Europa top
    'premier league':      2.82,
    'la liga':             2.52,
    'bundesliga':          3.03,
    'serie a':             2.67,
    'ligue 1':             2.57,
    'eredivisie':          3.07,
    'primeira liga':       2.58,
    'primeira liga portugal': 2.58,
    'süper lig':           2.74,
    'super lig':           2.74,
    # Europa secundaria
    'championship':        2.65,
    'serie b':             2.47,
    'segunda division':    2.45,
    'segunda división':    2.45,
    'ligue 2':             2.41,
    'bundesliga 2':        2.89,
    '2. bundesliga':       2.89,
    'pro league':          2.89,
    'jupiler':             2.89,
    'primeira liga bra':   2.55,
    # Américas
    'mls':                 3.02,
    'liga mx':             2.71,
    'brasileirao':         2.55,
    'serie a brasil':      2.55,
    'liga profesional':    2.43,
    'liga pro':            2.43,
    'primera division argentina': 2.43,
    'primera división argentina': 2.43,
    'apertura':            2.43,
    'clausura':            2.43,
    'campeonato brasileiro': 2.55,
    # Asia / África / MENA
    'saudi pro league':    2.61,
    'saudi':               2.61,
    'uae pro league':      2.48,
    'j1 league':           2.61,
    'j-league':            2.61,
    'k league':            2.55,
    'chinese super league': 2.69,
    'csl':                 2.69,
    'egypt premier':       2.38,
    'egyptian premier':    2.38,
    'libya premier':       2.31,
    'tunisian':            2.29,
    'moroccan':            2.35,
    'botola':              2.35,
    'algerian':            2.27,
    'nigerian':            2.41,
    # Europa del Este
    'premier liga ukraine': 2.42,
    'ukrainian':           2.42,
    'ekstraklasa':         2.51,
    'czech':               2.63,
    'romanian':            2.48,
    'greek super':         2.45,
    'super league greece': 2.45,
    'scottish':            2.69,
    # Competiciones continentales
    'champions league':    2.98,
    'europa league':       2.76,
    'conference league':   2.71,
    'copa libertadores':   2.57,
    'copa sudamericana':   2.48,
}

DEFAULT_LIGA_AVG = 2.60


def get_liga_avg(liga_nombre, liga_avg_input):
    """
    M4a: Resuelve el promedio real de la liga.
    Prioridad: tabla interna > input si parece razonable > DEFAULT.
    """
    liga_lower = (liga_nombre or '').lower()
    for key, avg in LIGA_AVG.items():
        if key in liga_lower:
            return avg
    # El input de n8n suele ser sum(goles_A + goles_B) de solo 2 equipos.
    # Solo usarlo si cae en rango razonable para una liga completa.
    if 1.8 <= liga_avg_input <= 4.2:
        return liga_avg_input
    return DEFAULT_LIGA_AVG


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

    prob_local     = sum(matriz[i][j] for i in range(max_goles) for j in range(max_goles) if i > j)
    prob_empate    = sum(matriz[i][i] for i in range(max_goles))
    prob_visitante = sum(matriz[i][j] for i in range(max_goles) for j in range(max_goles) if j > i)

    over25_prob = 1.0 - sum(
        matriz[i][j]
        for i in range(max_goles)
        for j in range(max_goles)
        if i + j <= 2
    )

    btts_prob = (1 - poisson_pmf(0, lambda_local)) * (1 - poisson_pmf(0, lambda_visit))

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

    idx = np.unravel_index(np.argmax(matriz[:5, :5]), (5, 5))
    marcador = f'{idx[0]}-{idx[1]}'

    return prob_local, prob_empate, prob_visitante, over25_prob, btts_prob, marcador


# ─── Calcular lambdas (M4a + M4b + M4c) ─────────────────────────────────────

def calcular_lambdas(d, liga_avg):
    """
    Fórmula Dixon-Coles con mejoras M4b (pesos dinámicos) y M4c (home advantage).

    liga_avg ya viene resuelto por get_liga_avg() — no se recalcula aquí.

    M4b — pesos dinámicos:
      Cuando h2h_total >= 5, se da peso parcial al ratio H2H de victorias
      como señal de "quién domina históricamente" para ajustar lambdas.
      No se inventan goles H2H — se usa la tasa de victoria como factor
      multiplicador suave sobre el lambda base.

    M4c — home advantage:
      Lambda local se incrementa, lambda visitante se reduce.
    """
    # Defaults basados en liga_avg para no usar valores genéricos fijos
    default_goles = liga_avg / 2.0  # mitad del promedio de liga = estimación neutra

    goles_local_avg       = safe_float(d.get('goles_local_avg'),       default_goles)
    goles_visit_avg       = safe_float(d.get('goles_visit_avg'),        default_goles * 0.85)
    goles_contra_local    = safe_float(d.get('goles_contra_local_avg'), default_goles * 0.85)
    goles_contra_visit    = safe_float(d.get('goles_contra_visit_avg'), default_goles)

    if liga_avg <= 0:
        liga_avg_safe = DEFAULT_LIGA_AVG
    else:
        liga_avg_safe = liga_avg

    # Dixon-Coles base
    ataque_local  = goles_local_avg    / liga_avg_safe
    defensa_visit = goles_contra_visit / liga_avg_safe
    ataque_visit  = goles_visit_avg    / liga_avg_safe
    defensa_local = goles_contra_local / liga_avg_safe

    lambda_local_base = ataque_local  * defensa_visit * liga_avg_safe
    lambda_visit_base = ataque_visit  * defensa_local * liga_avg_safe

    # ── M4b: ajuste por dominio histórico H2H ────────────────────────────────
    # Usamos la tasa de victorias H2H como factor multiplicador suave (±10% max).
    # Solo actúa si h2h_total >= 5 (muestra mínima confiable).
    h2h_disponible = d.get('h2h_disponible', False)
    h2h_total      = safe_int(d.get('h2h_total'), 0)
    h2h_local_wins = safe_int(d.get('h2h_local_wins'), 0)
    h2h_visit_wins = safe_int(d.get('h2h_visit_wins'), 0)

    if h2h_disponible and h2h_total >= 5:
        # Peso H2H alto si muestra es grande, bajo si es justa
        peso_h2h = 0.5 if h2h_total >= 8 else 0.3

        tasa_local = h2h_local_wins / h2h_total
        tasa_visit = h2h_visit_wins / h2h_total
        # Factor: 0.9 (dominado) a 1.1 (dominador), centrado en 0.5
        factor_local_h2h = 0.9 + (tasa_local - 0.33) * (0.2 / 0.34)
        factor_visit_h2h = 0.9 + (tasa_visit - 0.33) * (0.2 / 0.34)
        # Clamp factor entre 0.85 y 1.15
        factor_local_h2h = max(0.85, min(1.15, factor_local_h2h))
        factor_visit_h2h = max(0.85, min(1.15, factor_visit_h2h))

        lambda_local = lambda_local_base * (1 - peso_h2h) + lambda_local_base * factor_local_h2h * peso_h2h
        lambda_visit = lambda_visit_base * (1 - peso_h2h) + lambda_visit_base * factor_visit_h2h * peso_h2h
    else:
        lambda_local = lambda_local_base
        lambda_visit = lambda_visit_base

    # ── M4c: home advantage ───────────────────────────────────────────────────
    ha_factor = HOME_ADVANTAGE / liga_avg_safe
    lambda_local *= (1 + ha_factor)
    lambda_visit *= (1 - ha_factor * 0.5)

    # Clamp: entre 0.3 y 5.0
    lambda_local = max(0.3, min(5.0, lambda_local))
    lambda_visit = max(0.3, min(5.0, lambda_visit))

    return round(lambda_local, 3), round(lambda_visit, 3)


# ─── Score de confianza (M4d + M4f) ─────────────────────────────────────────

def calcular_confianza(d, prob_ganador, over25_prob, value_pct, pick_poisson, liga_avg):
    """
    Sistema de puntuación.
    Base: 50 puntos. Rango final: 10-95.

    Nuevos parámetros vs versión anterior:
      pick_poisson — M4d: necesario para detectar contradicción H2H vs Poisson
      liga_avg     — disponible para uso futuro en ajustes contextuales
    """
    score = 50
    penalizaciones = []
    bonificaciones = []

    odds_local       = safe_float(d.get('odds_local'))
    odds_visit       = safe_float(d.get('odds_visit'))
    odds_disponibles = d.get('odds_disponibles', True)

    # ── Odds ──────────────────────────────────────────────────────────────────
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

    # ── Forma reciente ─────────────────────────────────────────────────────────
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

    # ── H2H base ──────────────────────────────────────────────────────────────
    h2h_disponible = d.get('h2h_disponible', True)
    h2h_total      = safe_int(d.get('h2h_total'), 0)

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

    # ── M4d: Penalización por contradicción H2H vs Poisson ───────────────────
    if h2h_disponible and h2h_total >= 5:
        h2h_visit_wins = safe_int(d.get('h2h_visit_wins'), 0)
        h2h_local_wins_val = safe_int(d.get('h2h_local_wins'), 0)

        if h2h_local_wins_val > h2h_visit_wins:
            h2h_pick = 'Local'
        elif h2h_visit_wins > h2h_local_wins_val:
            h2h_pick = 'Visitante'
        else:
            h2h_pick = 'Empate'

        dominio_h2h = max(h2h_local_wins_val, h2h_visit_wins) / h2h_total

        if h2h_pick != pick_poisson and dominio_h2h >= 0.6:
            penalizacion_contradiccion = 10 + round(dominio_h2h * 10)
            score -= penalizacion_contradiccion
            penalizaciones.append(
                f'Contradicción H2H ({h2h_pick}) vs Poisson ({pick_poisson}): -{penalizacion_contradiccion}'
            )

    # ── Posición tabla ─────────────────────────────────────────────────────────
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

    # ── Probabilidad Poisson ──────────────────────────────────────────────────
    if prob_ganador > 0.55:
        score += 8
        bonificaciones.append(f'Poisson alta confianza ({round(prob_ganador*100,1)}%): +8')
    elif prob_ganador < 0.35:
        score -= 8
        penalizaciones.append(f'Poisson baja confianza ({round(prob_ganador*100,1)}%): -8')

    # ── Value bet ─────────────────────────────────────────────────────────────
    if value_pct > 5:
        score += 5
        bonificaciones.append(f'Value bet detectado (+{round(value_pct,1)}%): +5')

    # ── M4f: Cap de score por datos escasos ───────────────────────────────────
    # Cuenta fuentes de datos reales (no defaults)
    tabla_real = not (pos_local == 10 and pos_visit == 10)  # pos 10/10 = default
    fuentes_reales = sum([
        1 if (h2h_disponible and h2h_total >= 5) else 0,
        1 if odds_disponibles else 0,
        1 if tabla_real else 0,
    ])

    if fuentes_reales == 0:
        score = min(score, 35)
        penalizaciones.append('Datos insuficientes (0 fuentes reales): cap 35')
    elif fuentes_reales == 1:
        score = min(score, 55)
        # Solo agregar nota si el score se está recortando de verdad
        if score == 55:
            penalizaciones.append('Datos escasos (1 fuente real): cap 55')

    # Clamp final 10-95
    score = max(10, min(95, score))

    return score, penalizaciones, bonificaciones


# ─── Value bet (M4e: umbral 8%) ──────────────────────────────────────────────

def calcular_value_bet(prob_real, odds):
    """
    Value = (prob_real * odds - 1) * 100
    M4e: umbral subido de 3% a 8% — 3% era ruido estadístico.
    """
    if not odds or odds <= 0:
        return False, 0.0
    value = (prob_real * odds - 1) * 100
    return value > 8.0, round(value, 2)  # M4e: umbral 8%


# ─── Core del análisis ───────────────────────────────────────────────────────

def analizar(d):
    # 1. Resolver liga_avg una sola vez (M4a) — se pasa a todo lo que lo necesita
    liga_avg_input = safe_float(d.get('liga_goles_avg'), DEFAULT_LIGA_AVG)
    liga_nombre    = d.get('liga', '')
    liga_avg       = get_liga_avg(liga_nombre, liga_avg_input)

    # 2. Calcular lambdas con liga_avg resuelto (M4b + M4c incluidos)
    lambda_local, lambda_visit = calcular_lambdas(d, liga_avg)

    # 3. Distribución Poisson (motor según disponibilidad)
    if MOTOR == 'scipy':
        prob_local, prob_empate, prob_visit, over25, btts, marcador = \
            calcular_poisson_scipy(lambda_local, lambda_visit)
    else:
        prob_local, prob_empate, prob_visit, over25, btts, marcador = \
            calcular_poisson_math(lambda_local, lambda_visit)

    # 4. Pick principal
    probs = {'Local': prob_local, 'Empate': prob_empate, 'Visitante': prob_visit}
    pick = max(probs, key=probs.get)
    prob_ganador = probs[pick]

    # 5. Value bet del pick principal (M4e: umbral 8%)
    odds_map = {
        'Local':     safe_float(d.get('odds_local')),
        'Empate':    safe_float(d.get('odds_empate')),
        'Visitante': safe_float(d.get('odds_visit')),
    }
    odds_pick = odds_map.get(pick, 0)
    value_bet, value_pct = calcular_value_bet(prob_ganador, odds_pick)

    # 6. Score de confianza (M4d: pasamos pick; M4f: cap por datos escasos)
    confianza_score, penalizaciones, bonificaciones = calcular_confianza(
        d, prob_ganador, over25, value_pct, pick, liga_avg
    )

    if confianza_score > 60:
        confianza = 'ALTA'
    elif confianza_score >= 40:
        confianza = 'MEDIA'
    else:
        confianza = 'BAJA'

    # 7. Texto para inyectar en prompt Claude
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
        'motor':             MOTOR,
        'pick':              pick,
        'prob_local':        round(prob_local, 4),
        'prob_empate':       round(prob_empate, 4),
        'prob_visitante':    round(prob_visit, 4),
        'lambda_local':      lambda_local,
        'lambda_visit':      lambda_visit,
        'over25_prob':       round(over25, 4),
        'btts_prob':         round(btts, 4),
        'value_bet':         value_bet,
        'value_pct':         value_pct,
        'odds_pick':         odds_pick,
        'confianza_score':   confianza_score,
        'confianza':         confianza,
        'marcador_probable': marcador,
        'score_para_claude': score_para_claude,
        'penalizaciones':    penalizaciones,
        'bonificaciones':    bonificaciones,
        'partido_id':        str(d.get('partido_id', '')),
        'local':             str(d.get('local', '')),
        'visitante':         str(d.get('visitante', '')),
        'liga':              str(d.get('liga', '')),
        'liga_avg_usado':    round(liga_avg, 2),  # diagnóstico: qué avg se usó
    }

    # 8. Guardar en BD si se solicita
    if d.get('guardar_en_db') and d.get('partido_id'):
        _guardar_en_db(resultado, d)

    return resultado


# ─── Guardar en BD (opcional) ────────────────────────────────────────────────

def _guardar_en_db(resultado, d):
    """Llama a db_query.py para guardar la predicción estadística."""
    import subprocess
    args = json.dumps({
        'partido_id':     resultado['partido_id'],
        'fuente':         f"python_poisson_{MOTOR}",
        'pick':           resultado['pick'],
        'confianza':      resultado['confianza'],
        'score':          resultado['confianza_score'],
        'razonamiento':   resultado['score_para_claude'],
        'texto_completo': json.dumps(resultado, ensure_ascii=False),
        'job_id':         str(d.get('job_id', ''))
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
    """Reglas de PLAN-BOT-V2.md Apéndice B."""
    if not resultado_logistico or resultado_logistico.get('error'):
        return {
            'nivel':        'SOLO_POISSON',
            'ajuste_score': 0,
            'detalle':      'Modelo logístico no disponible'
        }

    pick_poisson   = resultado_poisson['pick']
    pick_logistico = resultado_logistico['pick']

    if pick_poisson == pick_logistico:
        return {
            'nivel':        'ALTO',
            'ajuste_score': 0,
            'detalle':      f'Ambos modelos coinciden en {pick_poisson}'
        }
    else:
        return {
            'nivel':        'BAJO',
            'ajuste_score': -15,
            'detalle':      f'Divergencia: Poisson={pick_poisson} vs Logístico={pick_logistico}'
        }


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        salida_error("Uso: pronostico.py '<json_datos>'")
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

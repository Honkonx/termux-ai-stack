#!/data/data/com.termux/files/usr/bin/python3
"""
h2h.py — Análisis exclusivo de historial Head to Head
Ruta: /data/data/com.termux/files/home/sports/scripts/h2h.py

Complementa a pronostico.py. Misma interfaz de entrada/salida.
Solo analiza el historial directo entre los dos equipos.
No usa goles promedio, odds ni posición de tabla.

Lógica:
  - Tasa de victorias de cada equipo en enfrentamientos directos
  - Dominancia: quién gana más y por cuánto margen
  - Tendencia: si los últimos partidos difieren del histórico total
    (h2h_total >= 6 permite comparar mitad reciente vs mitad antigua)
  - Penaliza si la muestra es pequeña (< 5 partidos)
  - Bonifica si hay dominancia clara (> 60% de victorias)

Uso desde datos.py (ThreadPoolExecutor):
  python3 h2h.py '<json_datos>'

Input JSON — mismos campos que pronostico.py (compatibilidad total):
  {
    "local":          "Real Madrid",
    "visitante":      "Barcelona",
    "liga":           "LaLiga",
    "partido_id":     "abc123",

    // Solo estos campos son relevantes para h2h.py:
    "h2h_local_wins": 4,
    "h2h_visit_wins": 3,
    "h2h_empates":    3,
    "h2h_total":      10,
    "h2h_disponible": true,

    // Campos ignorados pero aceptados sin error (compatibilidad total):
    "goles_local_avg", "goles_visit_avg", "goles_contra_local_avg",
    "goles_contra_visit_avg", "liga_goles_avg",
    "pos_local", "pos_visit", "forma_local_wins", "forma_visit_wins",
    "odds_local", "odds_empate", "odds_visit", "odds_disponibles",
    "guardar_en_db"
  }

Output JSON — mismo schema que pronostico.py:
  {
    "ok":              true,
    "fuente":          "h2h",
    "pick":            "Local" | "Visitante" | "Empate",
    "prob_local":      0.44,
    "prob_empate":     0.30,
    "prob_visitante":  0.26,
    "over25_prob":     null,   // h2h no calcula goles
    "btts_prob":       null,
    "value_bet":       false,
    "value_pct":       0.0,
    "confianza_score": 68,
    "confianza":       "ALTA",
    "marcador_probable": null, // h2h no calcula marcador
    "score_para_claude": "H2H: Local 4W-3E-3V (10 partidos) | Dominancia local 40% | ...",
    "penalizaciones":  [...],
    "bonificaciones":  [...],

    // Campos exclusivos de h2h.py (para bloque_claude)
    "h2h_local_wins":  4,
    "h2h_visit_wins":  3,
    "h2h_empates":     3,
    "h2h_total":       10,
    "dominancia":      0.40,    // tasa de victorias del equipo dominante
    "dominador":       "Local", // quién domina el H2H
    "tendencia":       "estable" | "local_mejora" | "visit_mejora" | "sin_datos"
  }
"""

import sys
import json


# ─── Rutas ───────────────────────────────────────────────────────────────────

PYTHON_BIN = '/data/data/com.termux/files/usr/bin/python3'
DB_SCRIPT  = '/data/data/com.termux/files/home/sports/scripts/db_query.py'

# ─── Constantes ──────────────────────────────────────────────────────────────

# Muestra mínima para que el análisis sea confiable
MUESTRA_MINIMA    = 3   # menos de esto → skip (datos.py ya filtra, pero doble check)
MUESTRA_CONFIABLE = 5   # >= 5 → análisis completo sin penalización por muestra
MUESTRA_OPTIMA    = 8   # >= 8 → bonificación por muestra grande

# Umbral de dominancia clara
DOMINANCIA_CLARA  = 0.60  # 60% de victorias = dominio claro
DOMINANCIA_FUERTE = 0.70  # 70% = dominio fuerte

# Probabilidad base de empate en H2H (ligeramente más alta que en otros modelos
# porque los empates son frecuentes en enfrentamientos históricos)
PROB_EMPATE_BASE  = 0.28

# Home advantage en H2H: el local actual tiene ligera ventaja
HOME_ADVANTAGE_H2H = 0.05  # +5% al local en probabilidades H2H


# ─── Helpers ─────────────────────────────────────────────────────────────────

def salida_ok(data):
    print(json.dumps({'ok': True, **data}, ensure_ascii=False))

def salida_error(msg):
    print(json.dumps({'ok': False, 'error': msg}, ensure_ascii=False))

def safe_int(val, default=0):
    try:
        return int(val) if val is not None else default
    except (TypeError, ValueError):
        return default

def safe_float(val, default=0.0):
    try:
        return float(val) if val is not None else default
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

def clamp(val, mn, mx):
    return max(mn, min(mx, val))


# ─── Validación de datos H2H ─────────────────────────────────────────────────

def validar_h2h(d):
    """
    Verifica que los datos H2H sean suficientes y coherentes.
    Devuelve (ok, razon) donde ok=False significa que el módulo debe saltar.
    """
    h2h_disponible = safe_bool(d.get('h2h_disponible'), False)
    if not h2h_disponible:
        return False, 'H2H no disponible (h2h_disponible=false)'

    h2h_total      = safe_int(d.get('h2h_total'), 0)
    h2h_local_wins = safe_int(d.get('h2h_local_wins'), 0)
    h2h_visit_wins = safe_int(d.get('h2h_visit_wins'), 0)
    h2h_empates    = safe_int(d.get('h2h_empates'), 0)

    if h2h_total < MUESTRA_MINIMA:
        return False, f'Muestra H2H insuficiente ({h2h_total} partidos, mínimo {MUESTRA_MINIMA})'

    # Coherencia: la suma no puede superar el total
    suma = h2h_local_wins + h2h_visit_wins + h2h_empates
    if suma > h2h_total:
        # Corregible: usar la suma real como total
        return True, 'ok_con_correccion'

    return True, 'ok'


# ─── Cálculo de probabilidades desde H2H ─────────────────────────────────────

def calcular_probs_h2h(h2h_local_wins, h2h_visit_wins, h2h_empates, h2h_total):
    """
    Convierte resultados H2H en probabilidades 1X2.

    Lógica:
      - Probabilidad base = frecuencia histórica de cada resultado
      - Se aplica suavizado de Laplace (pseudoconteo +1 por clase)
        para evitar probabilidades 0 cuando algún resultado no aparece
      - Se aplica HOME_ADVANTAGE_H2H al equipo que juega en casa ahora
      - Normalización final

    El suavizado de Laplace es importante: si el local nunca ganó en H2H
    (0/10), la probabilidad real no es 0% — hay incertidumbre.
    """
    # Suavizado de Laplace: +1 a cada clase, +3 al total
    pseudo_local = h2h_local_wins + 1
    pseudo_visit = h2h_visit_wins + 1
    pseudo_emp   = h2h_empates    + 1
    pseudo_total = h2h_total      + 3

    prob_local_raw  = pseudo_local / pseudo_total
    prob_visit_raw  = pseudo_visit / pseudo_total
    prob_empate_raw = pseudo_emp   / pseudo_total

    # Aplicar home advantage: trasvasar HOME_ADVANTAGE_H2H desde visitante → local
    ajuste = HOME_ADVANTAGE_H2H
    prob_local_adj  = prob_local_raw  + ajuste
    prob_visit_adj  = prob_visit_raw  - ajuste
    prob_empate_adj = prob_empate_raw

    # Clamp mínimos antes de normalizar
    MIN_PROB = 0.05
    prob_local_adj  = max(MIN_PROB, prob_local_adj)
    prob_visit_adj  = max(MIN_PROB, prob_visit_adj)
    prob_empate_adj = max(MIN_PROB, prob_empate_adj)

    # Normalizar
    total = prob_local_adj + prob_visit_adj + prob_empate_adj
    prob_local  = round(prob_local_adj  / total, 4)
    prob_visit  = round(prob_visit_adj  / total, 4)
    prob_empate = round(prob_empate_adj / total, 4)

    # Micro-ajuste para que sumen exactamente 1.0000
    diff = round(1.0 - prob_local - prob_empate - prob_visit, 4)
    prob_local = round(prob_local + diff, 4)

    return prob_local, prob_empate, prob_visit


# ─── Detectar tendencia ──────────────────────────────────────────────────────

def detectar_tendencia(h2h_local_wins, h2h_visit_wins, h2h_empates, h2h_total):
    """
    Compara la primera mitad del historial con la segunda mitad.
    Solo útil si h2h_total >= 6 (3 partidos por mitad mínimo).

    Nota: no tenemos los partidos individuales, solo los totales.
    La tendencia se infiere de la distribución, no de los partidos en orden.
    Con los datos que llegan de n8n (solo totales), solo podemos marcar
    'sin_datos_suficientes' si h2h_total < 6.

    Cuando tengamos acceso a los partidos individuales (h2h_resumen),
    esta función se puede mejorar para analizar los últimos N vs primeros N.
    """
    if h2h_total < 6:
        return 'sin_datos'

    # Con solo totales no podemos ordenar cronológicamente.
    # Devolvemos 'estable' como valor conservador hasta tener datos individuales.
    # TODO: cuando h2h.py reciba la lista de partidos individuales, implementar
    #       comparación reciente vs histórico real.
    tasa_local = h2h_local_wins / h2h_total
    tasa_visit = h2h_visit_wins / h2h_total

    if tasa_local > 0.55:
        return 'local_domina'
    elif tasa_visit > 0.55:
        return 'visit_domina'
    else:
        return 'equilibrado'


# ─── Score de confianza H2H ──────────────────────────────────────────────────

def calcular_score_h2h(h2h_local_wins, h2h_visit_wins, h2h_empates,
                        h2h_total, prob_ganador, dominador, dominancia):
    """
    Score de confianza 10-95 basado exclusivamente en H2H.

    Diferencias vs pronostico.py:
      - No penaliza por odds ausentes (no aplica aquí)
      - No penaliza por forma ausente (no aplica aquí)
      - Sí penaliza por muestra pequeña
      - Sí bonifica por dominancia clara y muestra grande
    """
    score = 50
    penalizaciones = []
    bonificaciones = []

    # ── Tamaño de muestra ─────────────────────────────────────────────────────
    if h2h_total >= MUESTRA_OPTIMA:
        score += 10
        bonificaciones.append(f'Muestra grande ({h2h_total} partidos): +10')
    elif h2h_total >= MUESTRA_CONFIABLE:
        score += 5
        bonificaciones.append(f'Muestra suficiente ({h2h_total} partidos): +5')
    else:
        penalidad = (MUESTRA_CONFIABLE - h2h_total) * 5
        score -= penalidad
        penalizaciones.append(f'Muestra pequeña ({h2h_total} partidos): -{penalidad}')

    # ── Dominancia ────────────────────────────────────────────────────────────
    if dominancia >= DOMINANCIA_FUERTE:
        score += 15
        bonificaciones.append(
            f'{dominador} domina H2H ({round(dominancia*100)}%): +15'
        )
    elif dominancia >= DOMINANCIA_CLARA:
        score += 8
        bonificaciones.append(
            f'{dominador} ventaja H2H ({round(dominancia*100)}%): +8'
        )
    elif dominancia < 0.40:
        # Ningún equipo domina — historial muy equilibrado, menos confianza
        score -= 5
        penalizaciones.append('H2H muy equilibrado (< 40% dominancia): -5')

    # ── Empates frecuentes ────────────────────────────────────────────────────
    if h2h_total > 0:
        tasa_empate = h2h_empates / h2h_total
        if tasa_empate >= 0.40:
            # Muchos empates → historial sugiere partido cerrado
            score -= 8
            penalizaciones.append(
                f'Empates frecuentes en H2H ({round(tasa_empate*100)}%): -8'
            )
        elif tasa_empate <= 0.15 and h2h_total >= 5:
            # Pocos empates → partidos suelen tener resultado claro
            score += 5
            bonificaciones.append(
                f'Pocos empates en H2H ({round(tasa_empate*100)}%): +5'
            )

    # ── Confianza estadística de la probabilidad ──────────────────────────────
    if prob_ganador > 0.55:
        score += 8
        bonificaciones.append(
            f'Prob. ganador alta ({round(prob_ganador*100, 1)}%): +8'
        )
    elif prob_ganador < 0.38:
        score -= 8
        penalizaciones.append(
            f'Prob. ganador baja ({round(prob_ganador*100, 1)}%): -8'
        )

    # ── Cap por partido muy equilibrado (todos cerca de 33%) ─────────────────
    if (abs(h2h_local_wins - h2h_visit_wins) <= 1 and
            h2h_empates >= h2h_total * 0.30):
        score = min(score, 52)
        penalizaciones.append('H2H equilibrado con muchos empates: cap 52')

    score = clamp(score, 10, 95)
    return score, penalizaciones, bonificaciones


# ─── Core del análisis ───────────────────────────────────────────────────────

def analizar(d):
    # Extraer campos H2H
    h2h_local_wins = safe_int(d.get('h2h_local_wins'), 0)
    h2h_visit_wins = safe_int(d.get('h2h_visit_wins'), 0)
    h2h_empates    = safe_int(d.get('h2h_empates'),    0)
    h2h_total      = safe_int(d.get('h2h_total'),      0)

    # Corregir total si la suma supera (coherencia)
    suma_real = h2h_local_wins + h2h_visit_wins + h2h_empates
    if suma_real > h2h_total:
        h2h_total = suma_real

    # Probabilidades
    prob_local, prob_empate, prob_visit = calcular_probs_h2h(
        h2h_local_wins, h2h_visit_wins, h2h_empates, h2h_total
    )

    # Pick
    probs = {'Local': prob_local, 'Empate': prob_empate, 'Visitante': prob_visit}
    pick = max(probs, key=probs.get)
    prob_ganador = probs[pick]

    # Dominancia: tasa de victorias del equipo con más wins en H2H
    if h2h_total > 0:
        tasa_local = h2h_local_wins / h2h_total
        tasa_visit = h2h_visit_wins / h2h_total
        if tasa_local >= tasa_visit:
            dominador  = 'Local'
            dominancia = tasa_local
        else:
            dominador  = 'Visitante'
            dominancia = tasa_visit
    else:
        dominador  = 'Empate'
        dominancia = 0.0

    # Tendencia
    tendencia = detectar_tendencia(
        h2h_local_wins, h2h_visit_wins, h2h_empates, h2h_total
    )

    # Score
    confianza_score, penalizaciones, bonificaciones = calcular_score_h2h(
        h2h_local_wins, h2h_visit_wins, h2h_empates,
        h2h_total, prob_ganador, dominador, dominancia
    )

    if confianza_score > 60:
        confianza = 'ALTA'
    elif confianza_score >= 40:
        confianza = 'MEDIA'
    else:
        confianza = 'BAJA'

    # Texto para Claude
    score_para_claude = (
        f"H2H: {d.get('local','Local')} {h2h_local_wins}W-"
        f"{h2h_empates}E-{h2h_visit_wins}V "
        f"({h2h_total} partidos) | "
        f"Dominancia {dominador}: {round(dominancia*100)}% | "
        f"Tendencia: {tendencia} | "
        f"Prob H2H: Local {round(prob_local*100,1)}% "
        f"Empate {round(prob_empate*100,1)}% "
        f"Visitante {round(prob_visit*100,1)}% | "
        f"Score H2H: {confianza_score}/100"
    )

    return {
        'fuente':            'h2h',
        'pick':              pick,
        'prob_local':        prob_local,
        'prob_empate':       prob_empate,
        'prob_visitante':    prob_visit,
        'over25_prob':       None,   # h2h no calcula goles
        'btts_prob':         None,
        'value_bet':         False,
        'value_pct':         0.0,
        'confianza_score':   confianza_score,
        'confianza':         confianza,
        'marcador_probable': None,   # h2h no calcula marcador
        'score_para_claude': score_para_claude,
        'penalizaciones':    penalizaciones,
        'bonificaciones':    bonificaciones,
        # Campos exclusivos para bloque_claude
        'h2h_local_wins':    h2h_local_wins,
        'h2h_visit_wins':    h2h_visit_wins,
        'h2h_empates':       h2h_empates,
        'h2h_total':         h2h_total,
        'dominancia':        round(dominancia, 4),
        'dominador':         dominador,
        'tendencia':         tendencia,
        'partido_id':        str(d.get('partido_id', '')),
        'local':             str(d.get('local', '')),
        'visitante':         str(d.get('visitante', '')),
        'liga':              str(d.get('liga', '')),
    }


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        salida_error("Uso: h2h.py '<json_datos>'")
        sys.exit(1)

    try:
        datos = json.loads(sys.argv[1])
    except json.JSONDecodeError as e:
        salida_error(f'JSON inválido: {e}')
        sys.exit(1)

    try:
        # Validar antes de analizar
        ok, razon = validar_h2h(datos)
        if not ok:
            salida_error(razon)
            sys.exit(1)

        resultado = analizar(datos)
        salida_ok(resultado)

    except Exception as e:
        salida_error(f'Error en análisis H2H: {str(e)}')
        sys.exit(1)

#!/data/data/com.termux/files/usr/bin/python3
"""
odds.py — Análisis de probabilidades implícitas desde cuotas de mercado
Ruta: /data/data/com.termux/files/home/sports/scripts/odds.py

Complementa a pronostico.py. Misma interfaz de entrada/salida.
Solo analiza las cuotas (odds) del partido.
No usa goles promedio, H2H ni posición de tabla.

Lógica:
  - Convierte odds decimales a probabilidades implícitas (1/odd)
  - Elimina el overround (margen de la casa) para obtener probs reales
  - Detecta value bet comparando prob_implicita vs umbral de confianza
  - Detecta favorito claro vs partido abierto
  - Score basado en claridad del favorito y tamaño del overround

Uso desde datos.py (ThreadPoolExecutor):
  python3 odds.py '<json_datos>'

Input JSON — mismos campos que pronostico.py (compatibilidad total):
  {
    "local":          "Real Madrid",
    "visitante":      "Barcelona",
    "liga":           "LaLiga",
    "partido_id":     "abc123",

    // Solo estos campos son relevantes para odds.py:
    "odds_local":       2.10,
    "odds_empate":      3.20,
    "odds_visit":       3.50,
    "odds_disponibles": true,

    // Campos ignorados pero aceptados sin error (compatibilidad total):
    "goles_local_avg", "goles_visit_avg", ..., "h2h_*", "forma_*", "pos_*"
  }

Output JSON — mismo schema que pronostico.py:
  {
    "ok":              true,
    "fuente":          "odds",
    "pick":            "Local" | "Visitante" | "Empate",
    "prob_local":      0.4476,    // prob implícita normalizada
    "prob_empate":     0.2941,
    "prob_visitante":  0.2583,
    "over25_prob":     null,      // odds.py no calcula goles
    "btts_prob":       null,
    "value_bet":       false,     // odds.py siempre false — no tiene prob propia de referencia
    "value_pct":       0.0,
    "confianza_score": 72,
    "confianza":       "ALTA",
    "marcador_probable": null,
    "score_para_claude": "Odds: Local @2.10 (47.6% impl) | ...",
    "penalizaciones":  [...],
    "bonificaciones":  [...],

    // Campos exclusivos de odds.py (para bloque_claude)
    "odds_local":       2.10,
    "odds_empate":      3.20,
    "odds_visit":       3.50,
    "prob_impl_local":  0.4762,   // ANTES de quitar overround
    "prob_impl_empate": 0.3125,
    "prob_impl_visit":  0.2857,
    "overround":        1.074,    // suma de probs implícitas brutas (> 1.0 = margen casa)
    "margen_pct":       7.4,      // overround expresado en %
    "favorito":         "Local",  // equipo con menor odd
    "odd_favorito":     2.10
  }
"""

import sys
import json
import math


# ─── Rutas ───────────────────────────────────────────────────────────────────

PYTHON_BIN = '/data/data/com.termux/files/usr/bin/python3'
DB_SCRIPT  = '/data/data/com.termux/files/home/sports/scripts/db_query.py'

# ─── Constantes ──────────────────────────────────────────────────────────────

# Overround razonable para una casa de apuestas seria (5-12%)
# Por encima de 15% = odds de mala calidad (penalizar)
OVERROUND_MAX_RAZONABLE = 1.15
OVERROUND_IDEAL         = 1.06  # < 6% = odds de buena calidad

# Odd mínima válida (< 1.01 es error de datos)
ODD_MINIMA = 1.01

# Favorito claro: odd < 1.70
# Partido abierto: odd del favorito > 2.50
FAVORITO_CLARO   = 1.70
FAVORITO_ABIERTO = 2.50

# Umbral de diferencia de probabilidad para considerar un resultado dominante
# Si la prob del pick supera al segundo en más de este margen → confianza extra
MARGEN_DOMINANTE = 0.15  # 15 puntos de diferencia


# ─── Helpers ─────────────────────────────────────────────────────────────────

def salida_ok(data):
    print(json.dumps({'ok': True, **data}, ensure_ascii=False))

def salida_error(msg):
    print(json.dumps({'ok': False, 'error': msg}, ensure_ascii=False))

def safe_float(val, default=0.0):
    try:
        v = float(val) if val is not None else default
        return v if not math.isnan(v) and not math.isinf(v) else default
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


# ─── Validación de odds ───────────────────────────────────────────────────────

def validar_odds(d):
    """
    Verifica que las odds sean válidas para análisis.
    Devuelve (ok, razon).
    """
    odds_disponibles = safe_bool(d.get('odds_disponibles'), False)
    if not odds_disponibles:
        return False, 'Odds no disponibles (odds_disponibles=false)'

    odds_local  = safe_float(d.get('odds_local'),  0.0)
    odds_empate = safe_float(d.get('odds_empate'), 0.0)
    odds_visit  = safe_float(d.get('odds_visit'),  0.0)

    if odds_local < ODD_MINIMA:
        return False, f'Odd local inválida ({odds_local})'
    if odds_empate < ODD_MINIMA:
        return False, f'Odd empate inválida ({odds_empate})'
    if odds_visit < ODD_MINIMA:
        return False, f'Odd visitante inválida ({odds_visit})'

    return True, 'ok'


# ─── Cálculo de probabilidades implícitas ────────────────────────────────────

def calcular_probs_implicitas(odds_local, odds_empate, odds_visit):
    """
    Convierte odds decimales a probabilidades implícitas.

    Paso 1: prob_bruta = 1 / odd  (incluye el margen de la casa)
    Paso 2: overround  = suma de las tres probs brutas (siempre > 1.0)
    Paso 3: prob_norm  = prob_bruta / overround  (elimina el margen)

    El overround representa el margen de la casa:
      overround=1.074 → la casa se queda con ~7.4% del volumen apostado
    """
    prob_bruta_local  = 1.0 / odds_local
    prob_bruta_empate = 1.0 / odds_empate
    prob_bruta_visit  = 1.0 / odds_visit

    overround = prob_bruta_local + prob_bruta_empate + prob_bruta_visit

    # Normalizar dividiendo por overround (quitar margen de la casa)
    prob_local  = round(prob_bruta_local  / overround, 4)
    prob_empate = round(prob_bruta_empate / overround, 4)
    prob_visit  = round(prob_bruta_visit  / overround, 4)

    # Micro-ajuste para que sumen exactamente 1.0000
    diff = round(1.0 - prob_local - prob_empate - prob_visit, 4)
    prob_local = round(prob_local + diff, 4)

    return (
        prob_local, prob_empate, prob_visit,
        round(prob_bruta_local, 4),
        round(prob_bruta_empate, 4),
        round(prob_bruta_visit, 4),
        round(overround, 4)
    )


# ─── Score de confianza por odds ─────────────────────────────────────────────

def calcular_score_odds(odds_local, odds_empate, odds_visit,
                         prob_local, prob_empate, prob_visit,
                         overround, favorito, odd_favorito, prob_ganador):
    """
    Score de confianza 10-95 basado exclusivamente en odds.

    Principio: las odds del mercado son el consenso de miles de apostadores
    y analistas. Un favorito claro con overround bajo = señal fuerte.
    Un partido muy abierto con overround alto = señal débil.
    """
    score = 50
    penalizaciones = []
    bonificaciones = []

    # ── Calidad del overround ─────────────────────────────────────────────────
    margen_pct = (overround - 1.0) * 100
    if overround <= OVERROUND_IDEAL:
        score += 8
        bonificaciones.append(f'Odds de calidad (margen {round(margen_pct,1)}%): +8')
    elif overround > OVERROUND_MAX_RAZONABLE:
        score -= 12
        penalizaciones.append(
            f'Odds de baja calidad (margen {round(margen_pct,1)}%): -12'
        )
    else:
        # Margen normal (6-15%) — sin ajuste
        pass

    # ── Claridad del favorito ─────────────────────────────────────────────────
    if odd_favorito < FAVORITO_CLARO:
        score += 15
        bonificaciones.append(
            f'Favorito claro {favorito} (@{odd_favorito}): +15'
        )
    elif odd_favorito < 2.00:
        score += 8
        bonificaciones.append(
            f'Favorito moderado {favorito} (@{odd_favorito}): +8'
        )
    elif odd_favorito > FAVORITO_ABIERTO:
        score -= 12
        penalizaciones.append(
            f'Partido muy abierto (menor odd @{odd_favorito}): -12'
        )

    # ── Margen entre primer y segundo pick ────────────────────────────────────
    probs_ord = sorted([prob_local, prob_empate, prob_visit], reverse=True)
    margen_picks = probs_ord[0] - probs_ord[1]
    if margen_picks >= MARGEN_DOMINANTE:
        score += 8
        bonificaciones.append(
            f'Diferencia de probabilidad amplia ({round(margen_picks*100,1)}pp): +8'
        )
    elif margen_picks < 0.05:
        score -= 8
        penalizaciones.append(
            f'Probabilidades muy igualadas ({round(margen_picks*100,1)}pp): -8'
        )

    # ── Probabilidad del ganador según odds ───────────────────────────────────
    if prob_ganador > 0.55:
        score += 5
        bonificaciones.append(
            f'Prob. implícita alta ({round(prob_ganador*100,1)}%): +5'
        )
    elif prob_ganador < 0.38:
        score -= 5
        penalizaciones.append(
            f'Prob. implícita baja ({round(prob_ganador*100,1)}%): -5'
        )

    # ── Partido con empate como favorito (raro, pero ocurre) ─────────────────
    if favorito == 'Empate':
        score -= 5
        penalizaciones.append('Empate como favorito de mercado: -5')

    score = clamp(score, 10, 95)
    return score, penalizaciones, bonificaciones


# ─── Core del análisis ───────────────────────────────────────────────────────

def analizar(d):
    odds_local  = safe_float(d.get('odds_local'),  0.0)
    odds_empate = safe_float(d.get('odds_empate'), 0.0)
    odds_visit  = safe_float(d.get('odds_visit'),  0.0)

    # Calcular probabilidades implícitas
    (prob_local, prob_empate, prob_visit,
     prob_impl_local, prob_impl_empate, prob_impl_visit,
     overround) = calcular_probs_implicitas(odds_local, odds_empate, odds_visit)

    # Pick: resultado con mayor probabilidad implícita (normalizada)
    probs = {'Local': prob_local, 'Empate': prob_empate, 'Visitante': prob_visit}
    pick = max(probs, key=probs.get)
    prob_ganador = probs[pick]

    # Favorito: equipo con menor odd (no siempre el mismo que pick por normalización)
    odds_map = {
        'Local':     odds_local,
        'Empate':    odds_empate,
        'Visitante': odds_visit,
    }
    favorito     = min(odds_map, key=odds_map.get)
    odd_favorito = odds_map[favorito]

    margen_pct = round((overround - 1.0) * 100, 2)

    # Score
    confianza_score, penalizaciones, bonificaciones = calcular_score_odds(
        odds_local, odds_empate, odds_visit,
        prob_local, prob_empate, prob_visit,
        overround, favorito, odd_favorito, prob_ganador
    )

    if confianza_score > 60:
        confianza = 'ALTA'
    elif confianza_score >= 40:
        confianza = 'MEDIA'
    else:
        confianza = 'BAJA'

    # Texto para Claude
    score_para_claude = (
        f"Odds: {d.get('local','Local')} @{odds_local} "
        f"({round(prob_impl_local*100,1)}% impl) | "
        f"Empate @{odds_empate} ({round(prob_impl_empate*100,1)}%) | "
        f"{d.get('visitante','Visitante')} @{odds_visit} "
        f"({round(prob_impl_visit*100,1)}%) | "
        f"Overround: {round(overround,3)} (+{margen_pct}%) | "
        f"Prob norm: Local {round(prob_local*100,1)}% "
        f"Empate {round(prob_empate*100,1)}% "
        f"Visit {round(prob_visit*100,1)}% | "
        f"Favorito mercado: {favorito} @{odd_favorito} | "
        f"Score odds: {confianza_score}/100"
    )

    return {
        'fuente':            'odds',
        'pick':              pick,
        'prob_local':        prob_local,
        'prob_empate':       prob_empate,
        'prob_visitante':    prob_visit,
        'over25_prob':       None,   # odds.py no calcula goles
        'btts_prob':         None,
        'value_bet':         False,  # no tenemos prob propia para comparar vs odds
        'value_pct':         0.0,
        'confianza_score':   confianza_score,
        'confianza':         confianza,
        'marcador_probable': None,
        'score_para_claude': score_para_claude,
        'penalizaciones':    penalizaciones,
        'bonificaciones':    bonificaciones,
        # Campos exclusivos para bloque_claude
        'odds_local':        odds_local,
        'odds_empate':       odds_empate,
        'odds_visit':        odds_visit,
        'prob_impl_local':   prob_impl_local,
        'prob_impl_empate':  prob_impl_empate,
        'prob_impl_visit':   prob_impl_visit,
        'overround':         overround,
        'margen_pct':        margen_pct,
        'favorito':          favorito,
        'odd_favorito':      odd_favorito,
        'partido_id':        str(d.get('partido_id', '')),
        'local':             str(d.get('local', '')),
        'visitante':         str(d.get('visitante', '')),
        'liga':              str(d.get('liga', '')),
    }


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        salida_error("Uso: odds.py '<json_datos>'")
        sys.exit(1)

    try:
        datos = json.loads(sys.argv[1])
    except json.JSONDecodeError as e:
        salida_error(f'JSON inválido: {e}')
        sys.exit(1)

    try:
        ok, razon = validar_odds(datos)
        if not ok:
            salida_error(razon)
            sys.exit(1)

        resultado = analizar(datos)
        salida_ok(resultado)

    except Exception as e:
        salida_error(f'Error en análisis Odds: {str(e)}')
        sys.exit(1)

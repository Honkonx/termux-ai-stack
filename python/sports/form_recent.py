#!/data/data/com.termux/files/usr/bin/python3
"""
form_recent.py — Análisis por forma reciente (últimos 5 partidos)
Ruta: /data/data/com.termux/files/home/sports/scripts/form_recent.py

Complementa a pronostico.py. Misma interfaz de entrada/salida.
Ignora H2H histórico y Dixon-Coles.
Solo usa forma reciente (victorias, empates, derrotas en últimos 5).

Lógica:
  - Construye probabilidades a partir de los ratios de resultados recientes
  - Aplica home_advantage simple (+10% al local)
  - Penaliza si un equipo está en racha negativa (0-1 victorias en 5)
  - Bonifica si un equipo está en racha positiva (4-5 victorias en 5)
  - Score de confianza propio (sin penalizar por ausencia de H2H — no aplica aquí)

Uso desde n8n (execSync):
  python3 form_recent.py '<json_datos>'

Input JSON — mismos campos que pronostico.py (compatibilidad total):
  {
    "local":             "Real Madrid",
    "visitante":         "Barcelona",
    "liga":              "LaLiga",
    "partido_id":        "abc123",

    // Solo estos campos son relevantes para form_recent:
    "forma_local_wins":  3,   // victorias en últimos 5 (local)
    "forma_visit_wins":  4,   // victorias en últimos 5 (visitante)

    // Campos ignorados pero aceptados sin error (compatibilidad con pronostico.py):
    "goles_local_avg", "goles_visit_avg", "goles_contra_local_avg",
    "goles_contra_visit_avg", "liga_goles_avg", "pos_local", "pos_visit",
    "h2h_local_wins", "h2h_visit_wins", "h2h_empates", "h2h_total",
    "h2h_disponible", "odds_local", "odds_empate", "odds_visit",
    "odds_disponibles", "guardar_en_db"
  }

Output JSON — mismo schema que pronostico.py:
  {
    "ok":              true,
    "fuente":          "form_recent",
    "pick":            "Local" | "Visitante" | "Empate",
    "prob_local":      0.48,
    "prob_empate":     0.28,
    "prob_visitante":  0.24,
    "over25_prob":     null,      // form_recent no calcula esto
    "btts_prob":       null,      // form_recent no calcula esto
    "value_bet":       false,
    "value_pct":       0.0,
    "confianza_score": 62,
    "confianza":       "MEDIA",
    "marcador_probable": null,    // form_recent no calcula marcador
    "score_para_claude": "Forma reciente: Local 3W/5 | Visitante 1W/5 | Score: 62/100",
    "penalizaciones":  ["Visitante en racha negativa favorece Local: contexto aplicado"],
    "bonificaciones":  ["Local 3W últimos 5: +10"]
  }
"""

import sys
import json
import math


# ─── Rutas ───────────────────────────────────────────────────────────────────

PYTHON_BIN = '/data/data/com.termux/files/usr/bin/python3'
DB_SCRIPT  = '/data/data/com.termux/files/home/sports/scripts/db_query.py'

# ─── Constantes ──────────────────────────────────────────────────────────────

HOME_ADVANTAGE_PCT = 0.10   # +10% de prob al local por jugar en casa
PROB_EMPATE_BASE   = 0.26   # base de empate antes de ajustes

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

def clamp(val, mn, mx):
    return max(mn, min(mx, val))


# ─── Lógica principal ────────────────────────────────────────────────────────

def calcular_probs_forma(forma_local_wins, forma_visit_wins):
    """
    Convierte victorias recientes en probabilidades 1X2.

    Lógica:
      - Ratio de victorias de cada equipo sobre el total disponible (10 slots: 5+5)
      - Se reserva PROB_EMPATE_BASE como probabilidad base de empate
      - El resto se distribuye entre local y visitante según sus ratios
      - Se aplica HOME_ADVANTAGE_PCT al local
      - Normalización final para que sumen 1.0

    Rangos de entrada esperados: 0-5 victorias por equipo.
    """
    # Ratio bruto — cuánto "merece" cada equipo sobre 5 partidos
    ratio_local = forma_local_wins / 5.0
    ratio_visit = forma_visit_wins / 5.0

    # Suma de ratios puede ser 0 si ambos tienen 0 victorias → usar 50/50
    total_ratios = ratio_local + ratio_visit
    if total_ratios == 0:
        ratio_local = 0.5
        ratio_visit = 0.5
        total_ratios = 1.0

    # Distribuir la "masa" restante (1 - empate_base) entre local y visitante
    masa_1x2 = 1.0 - PROB_EMPATE_BASE
    prob_local_raw  = masa_1x2 * (ratio_local / total_ratios)
    prob_visit_raw  = masa_1x2 * (ratio_visit / total_ratios)
    prob_empate_raw = PROB_EMPATE_BASE

    # Home advantage: trasvasar HOME_ADVANTAGE_PCT desde visitante → local
    ajuste = HOME_ADVANTAGE_PCT * prob_visit_raw
    prob_local_adj  = prob_local_raw  + ajuste
    prob_visit_adj  = prob_visit_raw  - ajuste
    prob_empate_adj = prob_empate_raw

    # Normalizar primero para que sumen 1.0
    total = prob_local_adj + prob_empate_adj + prob_visit_adj
    if total <= 0:
        total = 1.0
    prob_local  = prob_local_adj  / total
    prob_empate = prob_empate_adj / total
    prob_visit  = prob_visit_adj  / total

    # Clamp POST-normalización para garantizar mínimos reales
    # Si alguno queda por debajo del mínimo, lo subimos y redistribuimos
    MIN_PROB = 0.05
    if prob_local < MIN_PROB:
        deficit = MIN_PROB - prob_local
        prob_local = MIN_PROB
        # Restar el déficit del más alto
        if prob_empate >= prob_visit:
            prob_empate -= deficit
        else:
            prob_visit -= deficit
    if prob_visit < MIN_PROB:
        deficit = MIN_PROB - prob_visit
        prob_visit = MIN_PROB
        if prob_local >= prob_empate:
            prob_local -= deficit
        else:
            prob_empate -= deficit
    if prob_empate < MIN_PROB:
        deficit = MIN_PROB - prob_empate
        prob_empate = MIN_PROB
        if prob_local >= prob_visit:
            prob_local -= deficit
        else:
            prob_visit -= deficit

    # Redondear a 4 decimales
    prob_local  = round(prob_local,  4)
    prob_empate = round(prob_empate, 4)
    prob_visit  = round(prob_visit,  4)

    # Micro-ajuste final para que sumen exactamente 1.0000
    diff = round(1.0 - prob_local - prob_empate - prob_visit, 4)
    prob_local = round(prob_local + diff, 4)

    return prob_local, prob_empate, prob_visit


def calcular_score(forma_local_wins, forma_visit_wins, prob_ganador):
    """
    Score de confianza 10-95 basado exclusivamente en forma reciente.

    Diferencias vs pronostico.py:
      - No penaliza por H2H ausente (irrelevante en este modelo)
      - No penaliza por odds ausentes (no usamos odds aquí)
      - Sí aplica bonificaciones/penalizaciones por rachas extremas
    """
    score = 50
    penalizaciones = []
    bonificaciones = []

    # ── Racha local ────────────────────────────────────────────────────────────
    if forma_local_wins >= 4:
        score += 12
        bonificaciones.append(f'Local {forma_local_wins}W últimos 5: +12')
    elif forma_local_wins == 3:
        score += 6
        bonificaciones.append(f'Local 3W últimos 5: +6')
    elif forma_local_wins <= 1:
        score -= 10
        penalizaciones.append(f'Local en racha negativa ({forma_local_wins}W/5): -10')

    # ── Racha visitante ────────────────────────────────────────────────────────
    if forma_visit_wins >= 4:
        score -= 10
        penalizaciones.append(f'Visitante en buena forma ({forma_visit_wins}W/5): -10')
    elif forma_visit_wins == 3:
        score -= 4
        penalizaciones.append(f'Visitante 3W últimos 5: -4')
    elif forma_visit_wins <= 1:
        score += 8
        bonificaciones.append(f'Visitante en racha negativa ({forma_visit_wins}W/5): +8')

    # ── Diferencia de forma ────────────────────────────────────────────────────
    diff_forma = forma_local_wins - forma_visit_wins
    if diff_forma >= 3:
        score += 8
        bonificaciones.append(f'Diferencia de forma +{diff_forma}: +8')
    elif diff_forma <= -3:
        score -= 8
        penalizaciones.append(f'Diferencia de forma {diff_forma}: -8')

    # ── Confianza estadística de la probabilidad ───────────────────────────────
    if prob_ganador > 0.55:
        score += 8
        bonificaciones.append(f'Prob. ganador alta ({round(prob_ganador*100,1)}%): +8')
    elif prob_ganador < 0.38:
        score -= 8
        penalizaciones.append(f'Prob. ganador baja ({round(prob_ganador*100,1)}%): -8')

    # ── Cap por datos muy escasos (ambos con 2-3W — partido equilibrado) ───────
    if abs(diff_forma) <= 1 and forma_local_wins in (2, 3) and forma_visit_wins in (2, 3):
        score = min(score, 55)
        penalizaciones.append('Formas equilibradas — cap 55')

    score = clamp(score, 10, 95)
    return score, penalizaciones, bonificaciones


def analizar(d):
    forma_local_wins = safe_int(d.get('forma_local_wins'), 2)
    forma_visit_wins = safe_int(d.get('forma_visit_wins'), 2)

    # Clamp por si llegan valores fuera de rango
    forma_local_wins = clamp(forma_local_wins, 0, 5)
    forma_visit_wins = clamp(forma_visit_wins, 0, 5)

    # Probabilidades
    prob_local, prob_empate, prob_visit = calcular_probs_forma(
        forma_local_wins, forma_visit_wins
    )

    # Pick
    probs = {'Local': prob_local, 'Empate': prob_empate, 'Visitante': prob_visit}
    pick = max(probs, key=probs.get)
    prob_ganador = probs[pick]

    # Score
    confianza_score, penalizaciones, bonificaciones = calcular_score(
        forma_local_wins, forma_visit_wins, prob_ganador
    )

    if confianza_score > 60:
        confianza = 'ALTA'
    elif confianza_score >= 40:
        confianza = 'MEDIA'
    else:
        confianza = 'BAJA'

    # Texto para Claude
    score_para_claude = (
        f"Forma reciente: {d.get('local','Local')} {forma_local_wins}W/5 | "
        f"{d.get('visitante','Visitante')} {forma_visit_wins}W/5 | "
        f"Prob forma: Local {round(prob_local*100,1)}% "
        f"Empate {round(prob_empate*100,1)}% "
        f"Visitante {round(prob_visit*100,1)}% | "
        f"Score forma: {confianza_score}/100"
    )

    resultado = {
        'fuente':          'form_recent',
        'pick':            pick,
        'prob_local':      prob_local,
        'prob_empate':     prob_empate,
        'prob_visitante':  prob_visit,
        'over25_prob':     None,      # form_recent no calcula goles
        'btts_prob':       None,      # form_recent no calcula goles
        'value_bet':       False,
        'value_pct':       0.0,
        'confianza_score': confianza_score,
        'confianza':       confianza,
        'marcador_probable': None,    # form_recent no calcula marcador
        'score_para_claude': score_para_claude,
        'penalizaciones':  penalizaciones,
        'bonificaciones':  bonificaciones,
        'forma_local_wins': forma_local_wins,
        'forma_visit_wins': forma_visit_wins,
        'partido_id':      str(d.get('partido_id', '')),
        'local':           str(d.get('local', '')),
        'visitante':       str(d.get('visitante', '')),
        'liga':            str(d.get('liga', '')),
    }

    # Guardar en BD si se solicita (misma interfaz que pronostico.py)
    if d.get('guardar_en_db') and d.get('partido_id'):
        _guardar_en_db(resultado, d)

    return resultado


# ─── Guardar en BD (opcional) ────────────────────────────────────────────────

def _guardar_en_db(resultado, d):
    """Llama a db_query.py guardar_prediccion — misma interfaz que pronostico.py."""
    import subprocess
    args = json.dumps({
        'partido_id':     resultado['partido_id'],
        'fuente':         'form_recent',
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


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        salida_error("Uso: form_recent.py '<json_datos>'")
        sys.exit(1)

    try:
        datos = json.loads(sys.argv[1])
    except json.JSONDecodeError as e:
        salida_error(f'JSON inválido: {e}')
        sys.exit(1)

    try:
        resultado = analizar(datos)
        salida_ok(resultado)
    except Exception as e:
        salida_error(f'Error en análisis: {str(e)}')
        sys.exit(1)

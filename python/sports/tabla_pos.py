#!/data/data/com.termux/files/usr/bin/python3
"""
tabla_pos.py — Análisis por posición en tabla y diferencia de standing
Ruta: /data/data/com.termux/files/home/sports/scripts/tabla_pos.py

Complementa a pronostico.py. Misma interfaz de entrada/salida.
Solo analiza la posición en tabla y la forma reciente en contexto de standing.
No usa goles promedio, H2H ni odds.

Lógica:
  - Brecha de posiciones entre local y visitante
  - Zona en tabla: Champions/Europa/Descenso/Mid-table
  - Momentum: combina posición + forma reciente para detectar equipos
    que están subiendo o bajando
  - Penaliza partidos entre equipos de zonas similares (resultado incierto)
  - Bonifica cuando hay brecha clara entre zonas distintas

Uso desde datos.py (ThreadPoolExecutor):
  python3 tabla_pos.py '<json_datos>'

Input JSON — mismos campos que pronostico.py (compatibilidad total):
  {
    "local":       "Real Madrid",
    "visitante":   "Barcelona",
    "liga":        "LaLiga",
    "partido_id":  "abc123",

    // Campos relevantes para tabla_pos.py:
    "pos_local":         2,    // posición en tabla del local
    "pos_visit":         1,    // posición en tabla del visitante
    "forma_local_wins":  3,    // victorias en últimos 5 (para momentum)
    "forma_visit_wins":  4,

    // Campos ignorados pero aceptados sin error:
    "goles_*", "h2h_*", "odds_*", "liga_goles_avg", "guardar_en_db"
  }

Output JSON — mismo schema que pronostico.py:
  {
    "ok":              true,
    "fuente":          "tabla_pos",
    "pick":            "Local" | "Visitante" | "Empate",
    "prob_local":      0.45,
    "prob_empate":     0.29,
    "prob_visitante":  0.26,
    "over25_prob":     null,
    "btts_prob":       null,
    "value_bet":       false,
    "value_pct":       0.0,
    "confianza_score": 65,
    "confianza":       "ALTA",
    "marcador_probable": null,
    "score_para_claude": "Tabla: Local pos2 vs Visit pos8 | Brecha: 6 | ...",
    "penalizaciones":  [...],
    "bonificaciones":  [...],

    // Campos exclusivos de tabla_pos.py (para bloque_claude)
    "pos_local":        2,
    "pos_visit":        8,
    "brecha_pos":       6,       // abs(pos_local - pos_visit)
    "favorito_tabla":   "Local", // equipo mejor posicionado
    "zona_local":       "Champions",
    "zona_visit":       "Mid-table",
    "momentum_local":   "positivo",  // sube/baja/estable
    "momentum_visit":   "estable",
    "ventaja_zona":     true         // true si están en zonas distintas
  }
"""

import sys
import json


# ─── Rutas ───────────────────────────────────────────────────────────────────

PYTHON_BIN = '/data/data/com.termux/files/usr/bin/python3'
DB_SCRIPT  = '/data/data/com.termux/files/home/sports/scripts/db_query.py'

# ─── Constantes ──────────────────────────────────────────────────────────────

# Posición default cuando no hay datos reales (señal de que es default de n8n)
POS_DEFAULT = 10

# Número de equipos típico en una liga (para relativizar posición)
# Se usa para calcular zona cuando no conocemos el tamaño exacto de la liga
LIGA_TAMANO_DEFAULT = 20

# Brecha mínima para considerar ventaja real
BRECHA_MINIMA    = 3   # >= 3 posiciones → ventaja leve
BRECHA_MODERADA  = 6   # >= 6 posiciones → ventaja moderada
BRECHA_CLARA     = 10  # >= 10 posiciones → ventaja clara

# Forma para calcular momentum (victorias en últimos 5)
FORMA_ALTA  = 4  # 4-5 victorias = en forma
FORMA_BAJA  = 1  # 0-1 victorias = fuera de forma

# Home advantage: ligero bonus al local independientemente de tabla
HOME_ADVANTAGE_TABLA = 0.04  # +4% al local


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


# ─── Validación ──────────────────────────────────────────────────────────────

def validar_tabla(d):
    """
    Verifica que los datos de tabla sean reales (no defaults de n8n).
    Devuelve (ok, razon).
    """
    pos_local = safe_int(d.get('pos_local'), POS_DEFAULT)
    pos_visit = safe_int(d.get('pos_visit'), POS_DEFAULT)

    # Si ambos son el default → no hay datos reales de tabla
    if pos_local == POS_DEFAULT and pos_visit == POS_DEFAULT:
        return False, 'Sin datos de tabla (ambas posiciones son default 10/10)'

    # Posiciones deben ser >= 1
    if pos_local < 1 or pos_visit < 1:
        return False, f'Posición inválida (local={pos_local}, visit={pos_visit})'

    return True, 'ok'


# ─── Zona en tabla ───────────────────────────────────────────────────────────

def calcular_zona(pos, n_equipos=LIGA_TAMANO_DEFAULT):
    """
    Clasifica la posición en zonas según el tamaño de la liga.

    Zonas relativas al tamaño de la liga:
      - Champions:  top 20% (pos 1-4 en liga de 20)
      - Europa:     siguiente 20% (pos 5-8)
      - Mid-top:    siguiente 20% (pos 9-12)
      - Mid-bottom: siguiente 20% (pos 13-16)
      - Descenso:   último 20% (pos 17-20)
    """
    ratio = pos / n_equipos

    if ratio <= 0.20:
        return 'Champions'
    elif ratio <= 0.40:
        return 'Europa'
    elif ratio <= 0.60:
        return 'Mid-top'
    elif ratio <= 0.80:
        return 'Mid-bottom'
    else:
        return 'Descenso'


def zona_a_valor(zona):
    """Convierte zona a valor numérico para comparación. Mayor = mejor zona."""
    return {
        'Champions':  5,
        'Europa':     4,
        'Mid-top':    3,
        'Mid-bottom': 2,
        'Descenso':   1,
    }.get(zona, 3)


# ─── Momentum ────────────────────────────────────────────────────────────────

def calcular_momentum(pos, forma_wins):
    """
    Detecta si un equipo tiene momentum positivo, negativo o estable.

    Combina posición en tabla y forma reciente:
      - En buena posición + en forma = estable (ya está arriba)
      - En mala posición + en forma = subiendo (mejorando)
      - En buena posición + sin forma = bajando (deterioro)
      - En mala posición + sin forma = estable negativo
    """
    en_forma  = forma_wins >= FORMA_ALTA
    sin_forma = forma_wins <= FORMA_BAJA
    pos_baja  = pos > 12   # posición baja en tabla
    pos_alta  = pos <= 6   # posición alta en tabla

    if sin_forma and pos_alta:
        return 'bajando'
    elif en_forma and pos_baja:
        return 'subiendo'
    elif en_forma and pos_alta:
        return 'estable_positivo'
    elif sin_forma and pos_baja:
        return 'estable_negativo'
    else:
        return 'estable'


# ─── Cálculo de probabilidades desde tabla ───────────────────────────────────

def calcular_probs_tabla(pos_local, pos_visit, zona_local, zona_visit,
                          momentum_local, momentum_visit):
    """
    Convierte la diferencia de tabla en probabilidades 1X2.

    Lógica:
      - Base: 40% local / 28% empate / 32% visitante (home advantage base)
      - Ajuste por brecha de posición: cada posición de ventaja da +1% al favorito
      - Ajuste por zona: brecha entre zonas distintas amplifica el ajuste
      - Ajuste por momentum: equipo en mejor momentum recibe +3-5%
      - Normalización final
    """
    # Probabilidades base (home advantage incluido)
    prob_local  = 0.40
    prob_empate = 0.28
    prob_visit  = 0.32

    brecha = pos_visit - pos_local  # positivo = local mejor posicionado

    # Ajuste base por brecha de posición (cap en ±20%)
    ajuste_brecha = clamp(brecha * 0.015, -0.20, 0.20)

    # Ajuste adicional por diferencia de zona
    val_zona_local = zona_a_valor(zona_local)
    val_zona_visit = zona_a_valor(zona_visit)
    diff_zona = val_zona_local - val_zona_visit  # positivo = local en mejor zona

    ajuste_zona = clamp(diff_zona * 0.03, -0.09, 0.09)

    # Ajuste por momentum
    momentum_map = {
        'estable_positivo': 0.02,
        'subiendo':         0.03,
        'estable':          0.00,
        'estable_negativo': -0.02,
        'bajando':          -0.03,
    }
    ajuste_mom_local = momentum_map.get(momentum_local, 0.0)
    ajuste_mom_visit = momentum_map.get(momentum_visit, 0.0)

    # Aplicar ajustes: si local tiene ventaja → sube prob_local, baja prob_visit
    ajuste_total = ajuste_brecha + ajuste_zona + ajuste_mom_local - ajuste_mom_visit

    prob_local  += ajuste_total
    prob_visit  -= ajuste_total * 0.7   # visita pierde menos que gana el local
    # El empate absorbe el resto para mantener coherencia
    prob_empate  = 1.0 - prob_local - prob_visit

    # Clamp mínimos
    MIN_PROB = 0.05
    prob_local  = max(MIN_PROB, prob_local)
    prob_visit  = max(MIN_PROB, prob_visit)
    prob_empate = max(MIN_PROB, prob_empate)

    # Normalizar
    total = prob_local + prob_empate + prob_visit
    prob_local  = round(prob_local  / total, 4)
    prob_empate = round(prob_empate / total, 4)
    prob_visit  = round(prob_visit  / total, 4)

    # Micro-ajuste final
    diff = round(1.0 - prob_local - prob_empate - prob_visit, 4)
    prob_local = round(prob_local + diff, 4)

    return prob_local, prob_empate, prob_visit


# ─── Score de confianza por tabla ────────────────────────────────────────────

def calcular_score_tabla(pos_local, pos_visit, zona_local, zona_visit,
                          momentum_local, momentum_visit,
                          brecha, prob_ganador):
    """Score de confianza 10-95 basado en tabla y momentum."""
    score = 50
    penalizaciones = []
    bonificaciones = []

    # ── Brecha de posición ────────────────────────────────────────────────────
    if brecha >= BRECHA_CLARA:
        score += 15
        bonificaciones.append(f'Brecha de tabla clara ({brecha} pos): +15')
    elif brecha >= BRECHA_MODERADA:
        score += 8
        bonificaciones.append(f'Brecha de tabla moderada ({brecha} pos): +8')
    elif brecha >= BRECHA_MINIMA:
        score += 4
        bonificaciones.append(f'Brecha de tabla leve ({brecha} pos): +4')
    elif abs(brecha) < BRECHA_MINIMA:
        score -= 8
        penalizaciones.append(f'Posiciones muy similares (brecha {abs(brecha)}): -8')

    # Si el visitante está mejor posicionado (brecha negativa)
    if brecha < -BRECHA_MODERADA:
        score -= 8
        penalizaciones.append(f'Visitante mucho mejor posicionado ({abs(brecha)} pos): -8')

    # ── Diferencia de zona ────────────────────────────────────────────────────
    val_local = zona_a_valor(zona_local)
    val_visit = zona_a_valor(zona_visit)
    diff_zona = val_local - val_visit

    if diff_zona >= 2:
        score += 10
        bonificaciones.append(
            f'Diferencia de zona clara ({zona_local} vs {zona_visit}): +10'
        )
    elif diff_zona <= -2:
        score -= 10
        penalizaciones.append(
            f'Visitante en zona superior ({zona_visit} vs {zona_local}): -10'
        )
    elif diff_zona == 0:
        score -= 5
        penalizaciones.append(f'Misma zona ({zona_local}): -5')

    # ── Momentum ──────────────────────────────────────────────────────────────
    if momentum_local == 'subiendo':
        score += 6
        bonificaciones.append('Local con momentum ascendente: +6')
    elif momentum_local == 'bajando':
        score -= 6
        penalizaciones.append('Local con momentum descendente: -6')

    if momentum_visit == 'subiendo':
        score -= 5
        penalizaciones.append('Visitante con momentum ascendente: -5')
    elif momentum_visit == 'bajando':
        score += 5
        bonificaciones.append('Visitante con momentum descendente: +5')

    # ── Probabilidad resultante ───────────────────────────────────────────────
    if prob_ganador > 0.55:
        score += 5
        bonificaciones.append(
            f'Prob. resultante alta ({round(prob_ganador*100,1)}%): +5'
        )
    elif prob_ganador < 0.38:
        score -= 5
        penalizaciones.append(
            f'Prob. resultante baja ({round(prob_ganador*100,1)}%): -5'
        )

    # ── Equipos en zona de descenso (resultados muy volátiles) ───────────────
    if zona_local == 'Descenso' and zona_visit == 'Descenso':
        score = min(score, 50)
        penalizaciones.append('Ambos en zona de descenso — volatilidad alta: cap 50')

    score = clamp(score, 10, 95)
    return score, penalizaciones, bonificaciones


# ─── Core del análisis ───────────────────────────────────────────────────────

def analizar(d):
    pos_local  = safe_int(d.get('pos_local'),  POS_DEFAULT)
    pos_visit  = safe_int(d.get('pos_visit'),  POS_DEFAULT)
    forma_lw   = clamp(safe_int(d.get('forma_local_wins'), 2), 0, 5)
    forma_vw   = clamp(safe_int(d.get('forma_visit_wins'), 2), 0, 5)

    # Clamp posiciones a rango válido
    pos_local = max(1, pos_local)
    pos_visit = max(1, pos_visit)

    # Brecha: positivo = local mejor, negativo = visitante mejor
    brecha = pos_visit - pos_local

    # Favorito de tabla: quien esté más arriba (número menor)
    if pos_local < pos_visit:
        favorito_tabla = 'Local'
    elif pos_visit < pos_local:
        favorito_tabla = 'Visitante'
    else:
        favorito_tabla = 'Empate'

    # Zona de cada equipo
    zona_local = calcular_zona(pos_local)
    zona_visit = calcular_zona(pos_visit)

    # Ventaja de zona: están en zonas distintas
    ventaja_zona = zona_local != zona_visit

    # Momentum
    momentum_local = calcular_momentum(pos_local, forma_lw)
    momentum_visit = calcular_momentum(pos_visit, forma_vw)

    # Probabilidades
    prob_local, prob_empate, prob_visit = calcular_probs_tabla(
        pos_local, pos_visit, zona_local, zona_visit,
        momentum_local, momentum_visit
    )

    # Pick
    probs = {'Local': prob_local, 'Empate': prob_empate, 'Visitante': prob_visit}
    pick = max(probs, key=probs.get)
    prob_ganador = probs[pick]

    # Score
    confianza_score, penalizaciones, bonificaciones = calcular_score_tabla(
        pos_local, pos_visit, zona_local, zona_visit,
        momentum_local, momentum_visit,
        brecha, prob_ganador
    )

    if confianza_score > 60:
        confianza = 'ALTA'
    elif confianza_score >= 40:
        confianza = 'MEDIA'
    else:
        confianza = 'BAJA'

    # Texto para Claude
    score_para_claude = (
        f"Tabla: {d.get('local','Local')} pos{pos_local} ({zona_local}) "
        f"vs {d.get('visitante','Visitante')} pos{pos_visit} ({zona_visit}) | "
        f"Brecha: {brecha:+d} | "
        f"Momentum: local={momentum_local} visit={momentum_visit} | "
        f"Prob tabla: Local {round(prob_local*100,1)}% "
        f"Empate {round(prob_empate*100,1)}% "
        f"Visitante {round(prob_visit*100,1)}% | "
        f"Score tabla: {confianza_score}/100"
    )

    return {
        'fuente':            'tabla_pos',
        'pick':              pick,
        'prob_local':        prob_local,
        'prob_empate':       prob_empate,
        'prob_visitante':    prob_visit,
        'over25_prob':       None,
        'btts_prob':         None,
        'value_bet':         False,
        'value_pct':         0.0,
        'confianza_score':   confianza_score,
        'confianza':         confianza,
        'marcador_probable': None,
        'score_para_claude': score_para_claude,
        'penalizaciones':    penalizaciones,
        'bonificaciones':    bonificaciones,
        # Campos exclusivos para bloque_claude
        'pos_local':         pos_local,
        'pos_visit':         pos_visit,
        'brecha_pos':        brecha,
        'favorito_tabla':    favorito_tabla,
        'zona_local':        zona_local,
        'zona_visit':        zona_visit,
        'momentum_local':    momentum_local,
        'momentum_visit':    momentum_visit,
        'ventaja_zona':      ventaja_zona,
        'partido_id':        str(d.get('partido_id', '')),
        'local':             str(d.get('local', '')),
        'visitante':         str(d.get('visitante', '')),
        'liga':              str(d.get('liga', '')),
    }


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        salida_error("Uso: tabla_pos.py '<json_datos>'")
        sys.exit(1)

    try:
        datos = json.loads(sys.argv[1])
    except json.JSONDecodeError as e:
        salida_error(f'JSON inválido: {e}')
        sys.exit(1)

    try:
        ok, razon = validar_tabla(datos)
        if not ok:
            salida_error(razon)
            sys.exit(1)

        resultado = analizar(datos)
        salida_ok(resultado)

    except Exception as e:
        salida_error(f'Error en análisis Tabla: {str(e)}')
        sys.exit(1)

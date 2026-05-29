#!/data/data/com.termux/files/usr/bin/python3
"""
consenso.py — Árbitro final del motor de análisis multi-modelo
Ruta: /data/data/com.termux/files/home/sports/scripts/consenso.py

Recibe los resultados de todos los módulos (desde datos.py) y emite
el veredicto final ponderado. Reemplaza al _consenso_basico() de datos.py.

Lógica de ponderación:
  - Cada módulo tiene un peso base distinto según su riqueza de datos
  - El peso se ajusta dinámicamente según la confianza del módulo (score)
  - Un módulo con score bajo reduce su propio peso automáticamente
  - Si hay pocos módulos disponibles se ajustan los pesos relativos

Pesos base:
  poisson: 35%  ← más completo (Poisson + Dixon-Coles + forma + tabla + odds)
  forma:   15%  ← forma pura de los últimos 5
  h2h:     20%  ← historial directo, muy relevante para ciertos partidos
  odds:    20%  ← sabiduría del mercado (miles de apostadores)
  tabla:   10%  ← posición en tabla, contexto de standing

Uso desde datos.py (subprocess):
  python3 consenso.py '<json_resultados>'

Input JSON (construido por datos.py):
  {
    "resultados": {
      "poisson": { "ok": true, "pick": "Local", "confianza_score": 72, "prob_local": 0.48, ... },
      "forma":   { "ok": true, "pick": "Local", "confianza_score": 65, ... },
      "h2h":     { "ok": false, "error": "H2H no disponible" },
      "odds":    { "ok": true, "pick": "Local", "confianza_score": 78, ... },
      "tabla":   { "ok": true, "pick": "Empate", "confianza_score": 45, ... }
    },
    "partido": {
      "local":      "Real Madrid",
      "visitante":  "Barcelona",
      "liga":       "LaLiga",
      "partido_id": "abc123"
    }
  }

Output JSON:
  {
    "ok":              true,
    "pick_final":      "Local",
    "nivel":           "FUERTE",      // FUERTE / MODERADO / DEBIL / SOLO_POISSON / SOLO_FALLBACK
    "coinciden":       3,             // módulos ok que coinciden con pick_final
    "total_modulos":   4,             // módulos ok total
    "detalle":         "3/4 modelos coinciden en Local",
    "score_consenso":  76,
    "confianza_final": "ALTA",
    "votos": {
      "Local": 3, "Empate": 1, "Visitante": 0
    },
    "prob_ponderada": {               // promedio ponderado de probabilidades
      "local":    0.4712,
      "empate":   0.2834,
      "visitante": 0.2454
    },
    "modulos_en_consenso": ["poisson", "forma", "odds"],
    "modulos_disidentes":  ["tabla"],
    "peso_efectivo": {                // pesos reales usados (después de ajustes)
      "poisson": 0.38, "forma": 0.17, "h2h": 0.00, "odds": 0.25, "tabla": 0.11
    },
    // Compatibilidad con datos.py _consenso_basico
    "pick":           "Local",
    "confianza":      "ALTA",
    "score":          76
  }
"""

import sys
import json


# ─── Pesos base por módulo ────────────────────────────────────────────────────

PESOS_BASE = {
    'poisson': 0.35,
    'forma':   0.15,
    'h2h':     0.20,
    'odds':    0.20,
    'tabla':   0.10,
}

# Todos los módulos reconocidos
MODULOS_TODOS = list(PESOS_BASE.keys())

# ─── Niveles de consenso ─────────────────────────────────────────────────────

# Umbral de ratio de voto ponderado para cada nivel
UMBRAL_FUERTE   = 0.70   # >= 70% del peso total coincide con pick_final
UMBRAL_MODERADO = 0.55   # >= 55%

# Score mínimo de un módulo para que su voto cuente con peso completo
SCORE_UMBRAL_BAJO = 40   # score < 40 → peso reducido al 50%
SCORE_UMBRAL_MUY_BAJO = 25  # score < 25 → peso reducido al 20%


# ─── Helpers ─────────────────────────────────────────────────────────────────

def salida_ok(data):
    print(json.dumps({'ok': True, **data}, ensure_ascii=False))

def salida_error(msg):
    print(json.dumps({'ok': False, 'error': msg}, ensure_ascii=False))

def clamp(val, mn, mx):
    return max(mn, min(mx, val))

def safe_float(val, default=0.0):
    try:
        return float(val) if val is not None else default
    except (TypeError, ValueError):
        return default


# ─── Ajuste dinámico de pesos ────────────────────────────────────────────────

def calcular_pesos_efectivos(resultados):
    """
    Calcula los pesos efectivos de cada módulo según:
      1. Si el módulo no está disponible (ok=False) → peso 0
      2. Si el módulo tiene score bajo → peso reducido
      3. Renormalización para que los pesos disponibles sumen 1.0

    Devuelve dict {modulo: peso_efectivo} y lista de módulos ok.
    """
    pesos = {}
    modulos_ok = []

    for modulo in MODULOS_TODOS:
        res = resultados.get(modulo, {})

        if not res.get('ok', False):
            pesos[modulo] = 0.0
            continue

        score = res.get('confianza_score', 50)
        peso_base = PESOS_BASE[modulo]

        # Ajuste por score bajo
        if score < SCORE_UMBRAL_MUY_BAJO:
            factor = 0.20
        elif score < SCORE_UMBRAL_BAJO:
            factor = 0.50
        else:
            # Escala lineal: score 40 → 1.0x, score 95 → 1.3x (bonifica módulos seguros)
            factor = 1.0 + clamp((score - 40) / 183.3, 0.0, 0.30)

        pesos[modulo] = peso_base * factor
        modulos_ok.append(modulo)

    # Renormalizar para que los pesos ok sumen 1.0
    total_peso = sum(pesos.values())
    if total_peso > 0:
        pesos = {m: round(p / total_peso, 4) for m, p in pesos.items()}
    else:
        # Ningún módulo ok → pesos uniformes para los que haya
        for m in MODULOS_TODOS:
            pesos[m] = 0.0

    return pesos, modulos_ok


# ─── Votación ponderada ───────────────────────────────────────────────────────

def calcular_votos_ponderados(resultados, pesos_efectivos, modulos_ok):
    """
    Suma el peso de cada módulo según su pick.
    También calcula el promedio ponderado de probabilidades.

    Devuelve:
      - votos_peso: {'Local': 0.62, 'Empate': 0.21, 'Visitante': 0.17}
      - votos_count: {'Local': 3, 'Empate': 1, 'Visitante': 0}
      - prob_ponderada: {'local': 0.47, 'empate': 0.28, 'visitante': 0.25}
    """
    votos_peso  = {'Local': 0.0, 'Empate': 0.0, 'Visitante': 0.0}
    votos_count = {'Local': 0,   'Empate': 0,   'Visitante': 0}

    # Para promedio ponderado de probabilidades
    prob_local_acum  = 0.0
    prob_empate_acum = 0.0
    prob_visit_acum  = 0.0
    peso_prob_acum   = 0.0

    for modulo in modulos_ok:
        res  = resultados.get(modulo, {})
        pick = res.get('pick', '')
        peso = pesos_efectivos.get(modulo, 0.0)

        if pick in votos_peso:
            votos_peso[pick]  += peso
            votos_count[pick] += 1

        # Acumular probabilidades (solo si el módulo las tiene)
        prob_local = safe_float(res.get('prob_local'),  0.0)
        prob_emp   = safe_float(res.get('prob_empate'), 0.0)
        prob_visit = safe_float(res.get('prob_visitante'), 0.0)

        if prob_local + prob_emp + prob_visit > 0:
            prob_local_acum  += prob_local  * peso
            prob_empate_acum += prob_emp    * peso
            prob_visit_acum  += prob_visit  * peso
            peso_prob_acum   += peso

    # Normalizar probabilidades ponderadas
    if peso_prob_acum > 0:
        prob_local_pond  = round(prob_local_acum  / peso_prob_acum, 4)
        prob_empate_pond = round(prob_empate_acum / peso_prob_acum, 4)
        prob_visit_pond  = round(prob_visit_acum  / peso_prob_acum, 4)
        # Micro-ajuste
        diff = round(1.0 - prob_local_pond - prob_empate_pond - prob_visit_pond, 4)
        prob_local_pond = round(prob_local_pond + diff, 4)
    else:
        prob_local_pond  = 0.3334
        prob_empate_pond = 0.3333
        prob_visit_pond  = 0.3333

    prob_ponderada = {
        'local':     prob_local_pond,
        'empate':    prob_empate_pond,
        'visitante': prob_visit_pond,
    }

    # Normalizar votos_peso para que sumen ~1.0 (pueden haber picks inválidos)
    total_votos = sum(votos_peso.values())
    if total_votos > 0:
        votos_peso = {k: round(v / total_votos, 4) for k, v in votos_peso.items()}

    return votos_peso, votos_count, prob_ponderada


# ─── Score de consenso ───────────────────────────────────────────────────────

def calcular_score_consenso(resultados, pesos_efectivos, modulos_ok,
                              pick_final, votos_peso, nivel):
    """
    Score final 10-95 que combina:
      - Score ponderado de los módulos que coinciden con el pick
      - Bonus por nivel de consenso
      - Bonus por número de módulos disponibles
    """
    # Score base: promedio ponderado de los módulos que votan por pick_final
    score_base = 0.0
    peso_base_acum = 0.0

    for modulo in modulos_ok:
        res  = resultados.get(modulo, {})
        pick = res.get('pick', '')
        if pick == pick_final:
            score_mod = res.get('confianza_score', 50)
            peso_mod  = pesos_efectivos.get(modulo, 0.0)
            score_base  += score_mod * peso_mod
            peso_base_acum += peso_mod

    if peso_base_acum > 0:
        score_base = score_base / peso_base_acum
    else:
        score_base = 40.0

    # Ajuste por nivel de consenso
    ajuste_nivel = {
        'FUERTE':       +10,
        'MODERADO':     +3,
        'DEBIL':        -10,
        'SOLO_POISSON': 0,
        'SOLO_FALLBACK': -15,
    }.get(nivel, 0)

    # Bonus por número de módulos disponibles
    bonus_modulos = {1: 0, 2: 3, 3: 5, 4: 7, 5: 10}.get(len(modulos_ok), 0)

    score_final = clamp(
        round(score_base + ajuste_nivel + bonus_modulos),
        10, 95
    )
    return score_final


# ─── Nivel de consenso ───────────────────────────────────────────────────────

def determinar_nivel(modulos_ok, votos_peso, pick_final):
    """
    Determina el nivel de consenso basado en el peso acumulado del pick ganador.
    """
    if not modulos_ok:
        return 'SOLO_FALLBACK'

    if len(modulos_ok) == 1 and 'poisson' in modulos_ok:
        return 'SOLO_POISSON'

    ratio = votos_peso.get(pick_final, 0.0)

    if ratio >= UMBRAL_FUERTE:
        return 'FUERTE'
    elif ratio >= UMBRAL_MODERADO:
        return 'MODERADO'
    else:
        return 'DEBIL'


# ─── Core del análisis ───────────────────────────────────────────────────────

def calcular_consenso(resultados, partido):
    """
    Orquesta todo el proceso de consenso.
    """
    # 1. Pesos efectivos
    pesos_efectivos, modulos_ok = calcular_pesos_efectivos(resultados)

    # 2. Fallback si ningún módulo ok
    if not modulos_ok:
        return {
            'pick_final':      'Local',
            'nivel':           'SOLO_FALLBACK',
            'coinciden':       0,
            'total_modulos':   0,
            'detalle':         'Ningún módulo devolvió resultado válido',
            'score_consenso':  25,
            'confianza_final': 'BAJA',
            'votos':           {'Local': 0, 'Empate': 0, 'Visitante': 0},
            'prob_ponderada':  {'local': 0.3334, 'empate': 0.3333, 'visitante': 0.3333},
            'modulos_en_consenso': [],
            'modulos_disidentes':  [],
            'peso_efectivo':   pesos_efectivos,
            'pick':            'Local',
            'confianza':       'BAJA',
            'score':           25,
        }

    # 3. Votación ponderada
    votos_peso, votos_count, prob_ponderada = calcular_votos_ponderados(
        resultados, pesos_efectivos, modulos_ok
    )

    # 4. Pick final: resultado con mayor peso acumulado
    pick_final = max(votos_peso, key=votos_peso.get)

    # 5. Nivel de consenso
    nivel = determinar_nivel(modulos_ok, votos_peso, pick_final)

    # 6. Score de consenso
    score_consenso = calcular_score_consenso(
        resultados, pesos_efectivos, modulos_ok,
        pick_final, votos_peso, nivel
    )

    # 7. Confianza final
    if score_consenso > 60:
        confianza_final = 'ALTA'
    elif score_consenso >= 40:
        confianza_final = 'MEDIA'
    else:
        confianza_final = 'BAJA'

    # 8. Módulos en consenso vs disidentes
    modulos_en_consenso = [
        m for m in modulos_ok
        if resultados.get(m, {}).get('pick') == pick_final
    ]
    modulos_disidentes = [
        m for m in modulos_ok
        if resultados.get(m, {}).get('pick') != pick_final
    ]

    # 9. Conteo de votos (enteros, para el bloque_python)
    coinciden = votos_count.get(pick_final, 0)
    total_mod = len(modulos_ok)

    detalle = f'{coinciden}/{total_mod} modelos coinciden en {pick_final}'

    # Pesos efectivos redondeados para output
    peso_efectivo_out = {m: round(pesos_efectivos.get(m, 0.0), 3) for m in MODULOS_TODOS}

    return {
        'pick_final':          pick_final,
        'nivel':               nivel,
        'coinciden':           coinciden,
        'total_modulos':       total_mod,
        'detalle':             detalle,
        'score_consenso':      score_consenso,
        'confianza_final':     confianza_final,
        'votos':               votos_count,
        'votos_peso':          {k: round(v, 3) for k, v in votos_peso.items()},
        'prob_ponderada':      prob_ponderada,
        'modulos_en_consenso': modulos_en_consenso,
        'modulos_disidentes':  modulos_disidentes,
        'peso_efectivo':       peso_efectivo_out,
        # Compatibilidad con datos.py _consenso_basico
        'pick':                pick_final,
        'confianza':           confianza_final,
        'score':               score_consenso,
    }


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        salida_error("Uso: consenso.py '<json_resultados>'")
        sys.exit(1)

    try:
        datos = json.loads(sys.argv[1])
    except json.JSONDecodeError as e:
        salida_error(f'JSON inválido: {e}')
        sys.exit(1)

    try:
        resultados = datos.get('resultados', {})
        partido    = datos.get('partido', {})

        if not resultados:
            salida_error('Campo "resultados" vacío o ausente')
            sys.exit(1)

        resultado = calcular_consenso(resultados, partido)
        salida_ok(resultado)

    except Exception as e:
        salida_error(f'Error en consenso: {str(e)}')
        sys.exit(1)

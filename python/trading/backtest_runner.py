#!/data/data/com.termux/files/usr/bin/python3
# python/trading/backtest_runner.py v1
# termux-ai-stack — Backtesting desde historial MT5
# Lee CSV o HTML exportado desde MT5 → calcula métricas → genera reporte HTML
# REGLAS ARM64: datetime.now() · sin pandas · sin requests · rutas $HOME

import os
import sys
import csv
import sqlite3
import json
from datetime import datetime
from html.parser import HTMLParser

HOME        = os.environ.get("HOME", "/data/data/com.termux/files/home")
OUTPUT_DIR  = os.path.join(HOME, "trading", "reportes")
DB_PATH     = os.path.join(HOME, "trading", "senales.db")

# ════════════════════════════════════════════════════════════════
#  PARSER CSV MT5
# ════════════════════════════════════════════════════════════════
def parse_csv_mt5(filepath):
    """Lee CSV exportado desde MT5 Historial de Operaciones.
    Detecta automáticamente el separador (, o ;) y el encoding."""
    operaciones = []
    errores = []

    # Detectar encoding
    for enc in ["utf-8", "utf-8-sig", "latin-1", "cp1252"]:
        try:
            with open(filepath, "r", encoding=enc) as f:
                muestra = f.read(1024)
            encoding = enc
            break
        except Exception:
            continue
    else:
        return [], ["No se pudo detectar el encoding del archivo"]

    # Detectar separador
    separador = "," if muestra.count(",") > muestra.count(";") else ";"

    try:
        with open(filepath, "r", encoding=encoding, newline="") as f:
            reader = csv.reader(f, delimiter=separador)
            headers = []
            for i, row in enumerate(reader):
                if not row or all(c.strip() == "" for c in row):
                    continue
                # Detectar fila de headers
                if not headers:
                    row_lower = [c.strip().lower() for c in row]
                    if any(k in row_lower for k in ["time", "symbol", "type", "profit", "deal"]):
                        headers = [c.strip().lower() for c in row]
                        continue
                    # Si no hay headers detectados en primeras 5 filas, usar posiciones fijas
                    if i >= 5:
                        headers = ["time","deal","symbol","type","direction",
                                   "volume","price","order","commission","swap","profit","balance","comment"]

                if not headers:
                    continue

                row_dict = {}
                for j, val in enumerate(row):
                    if j < len(headers):
                        row_dict[headers[j]] = val.strip()

                # Solo procesar filas con symbol y profit válidos
                symbol  = row_dict.get("symbol", "").strip()
                profit_s = row_dict.get("profit", "0").replace(" ", "")
                if not symbol or symbol.lower() in ("symbol", ""):
                    continue
                try:
                    profit = float(profit_s) if profit_s else 0.0
                except ValueError:
                    continue

                # Parsear fecha
                time_str = row_dict.get("time", "")
                fecha = None
                for fmt in ["%Y.%m.%d %H:%M:%S", "%Y-%m-%d %H:%M:%S",
                            "%d/%m/%Y %H:%M:%S", "%Y.%m.%d"]:
                    try:
                        fecha = datetime.strptime(time_str, fmt)
                        break
                    except ValueError:
                        continue

                tipo = row_dict.get("type", "").lower()
                direction = row_dict.get("direction", "").lower()

                # En MT5: type=buy/sell, direction=in/out
                # Solo operaciones cerradas (out) tienen profit real
                if direction and direction not in ("out", ""):
                    continue

                try:
                    precio = float(row_dict.get("price", "0"))
                    volumen = float(row_dict.get("volume", "0"))
                    swap = float(row_dict.get("swap", "0").replace(" ", "") or "0")
                    comision = float(row_dict.get("commission", "0").replace(" ", "") or "0")
                except ValueError:
                    precio = volumen = swap = comision = 0.0

                operaciones.append({
                    "fecha":     fecha.strftime("%Y-%m-%d %H:%M:%S") if fecha else time_str,
                    "symbol":    symbol,
                    "tipo":      tipo,
                    "precio":    precio,
                    "volumen":   volumen,
                    "profit":    profit,
                    "swap":      swap,
                    "comision":  comision,
                    "profit_neto": profit + swap + comision,
                    "deal":      row_dict.get("deal", ""),
                    "comentario": row_dict.get("comment", ""),
                })
    except Exception as e:
        errores.append(f"Error leyendo CSV: {e}")

    return operaciones, errores


# ════════════════════════════════════════════════════════════════
#  CÁLCULO DE MÉTRICAS
# ════════════════════════════════════════════════════════════════
def calcular_metricas(operaciones):
    if not operaciones:
        return {}

    profits = [op["profit_neto"] for op in operaciones]
    wins    = [p for p in profits if p > 0]
    losses  = [p for p in profits if p < 0]
    breakeven = [p for p in profits if p == 0]

    total       = len(profits)
    n_wins      = len(wins)
    n_losses    = len(losses)
    winrate     = round(n_wins / total * 100, 1) if total > 0 else 0.0
    profit_total = round(sum(profits), 2)
    avg_win     = round(sum(wins) / len(wins), 2) if wins else 0.0
    avg_loss    = round(sum(losses) / len(losses), 2) if losses else 0.0
    profit_factor = round(abs(sum(wins) / sum(losses)), 2) if losses and sum(losses) != 0 else 0.0

    # Drawdown máximo (sobre equity acumulada)
    equity = 0.0
    peak   = 0.0
    max_dd = 0.0
    for p in profits:
        equity += p
        if equity > peak:
            peak = equity
        dd = peak - equity
        if dd > max_dd:
            max_dd = dd
    max_dd = round(max_dd, 2)

    # Racha máxima WIN y LOSS consecutivos
    racha_win_max = racha_loss_max = 0
    racha_win_act = racha_loss_act = 0
    for p in profits:
        if p > 0:
            racha_win_act += 1
            racha_loss_act = 0
            racha_win_max = max(racha_win_max, racha_win_act)
        elif p < 0:
            racha_loss_act += 1
            racha_win_act = 0
            racha_loss_max = max(racha_loss_max, racha_loss_act)
        else:
            racha_win_act = racha_loss_act = 0

    # Por símbolo
    por_simbolo = {}
    for op in operaciones:
        s = op["symbol"]
        if s not in por_simbolo:
            por_simbolo[s] = {"total": 0, "wins": 0, "losses": 0, "profit": 0.0}
        por_simbolo[s]["total"] += 1
        por_simbolo[s]["profit"] = round(por_simbolo[s]["profit"] + op["profit_neto"], 2)
        if op["profit_neto"] > 0:
            por_simbolo[s]["wins"] += 1
        elif op["profit_neto"] < 0:
            por_simbolo[s]["losses"] += 1

    # Fechas
    fechas = [op["fecha"] for op in operaciones if op["fecha"]]
    fecha_inicio = min(fechas) if fechas else ""
    fecha_fin    = max(fechas) if fechas else ""

    return {
        "total":          total,
        "wins":           n_wins,
        "losses":         n_losses,
        "breakeven":      len(breakeven),
        "winrate":        winrate,
        "profit_total":   profit_total,
        "avg_win":        avg_win,
        "avg_loss":       avg_loss,
        "profit_factor":  profit_factor,
        "max_drawdown":   max_dd,
        "racha_win_max":  racha_win_max,
        "racha_loss_max": racha_loss_max,
        "por_simbolo":    por_simbolo,
        "fecha_inicio":   fecha_inicio,
        "fecha_fin":      fecha_fin,
    }


# ════════════════════════════════════════════════════════════════
#  GENERAR REPORTE HTML
# ════════════════════════════════════════════════════════════════
def generar_html(metricas, operaciones, nombre_archivo):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    ts        = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_path  = os.path.join(OUTPUT_DIR, f"backtest_{ts}.html")
    generado  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    m = metricas
    wc = "#2ecc71" if m.get("winrate", 0) >= 50 else "#e74c3c"
    pfc = "#2ecc71" if m.get("profit_factor", 0) >= 1 else "#e74c3c"
    ptc = "#2ecc71" if m.get("profit_total", 0) >= 0 else "#e74c3c"

    # Tabla por símbolo
    filas_simbolo = ""
    for sim, datos in sorted(m.get("por_simbolo", {}).items(),
                              key=lambda x: x[1]["total"], reverse=True):
        wr_s = round(datos["wins"]/datos["total"]*100,1) if datos["total"] > 0 else 0
        color = "#2ecc71" if datos["profit"] >= 0 else "#e74c3c"
        filas_simbolo += f"""
        <tr>
          <td>{sim}</td>
          <td>{datos['total']}</td>
          <td style="color:#2ecc71">{datos['wins']}</td>
          <td style="color:#e74c3c">{datos['losses']}</td>
          <td>{wr_s}%</td>
          <td style="color:{color}">{datos['profit']}</td>
        </tr>"""

    # Últimas 50 operaciones
    filas_ops = ""
    for op in operaciones[-50:]:
        color = "#2ecc71" if op["profit_neto"] > 0 else ("#e74c3c" if op["profit_neto"] < 0 else "#888")
        filas_ops += f"""
        <tr>
          <td>{op['fecha']}</td>
          <td>{op['symbol']}</td>
          <td>{op['tipo'].upper()}</td>
          <td>{op['precio']}</td>
          <td>{op['volumen']}</td>
          <td style="color:{color}">{op['profit_neto']}</td>
        </tr>"""

    html = f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Backtest — {nombre_archivo}</title>
<style>
  body {{ font-family: monospace; background: #0d0d0d; color: #ccc; margin: 0; padding: 16px; }}
  h1 {{ color: #00bcd4; font-size: 1.1em; border-bottom: 1px solid #222; padding-bottom: 8px; }}
  h2 {{ color: #888; font-size: 0.9em; margin-top: 24px; text-transform: uppercase; letter-spacing: 2px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 8px; margin: 12px 0; }}
  .card {{ background: #151515; border: 1px solid #222; border-radius: 6px; padding: 10px; }}
  .card .label {{ font-size: 0.7em; color: #666; text-transform: uppercase; }}
  .card .value {{ font-size: 1.2em; font-weight: bold; margin-top: 4px; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 0.8em; margin-top: 8px; }}
  th {{ background: #151515; color: #666; padding: 6px 8px; text-align: left; font-size: 0.75em; text-transform: uppercase; }}
  td {{ padding: 5px 8px; border-bottom: 1px solid #1a1a1a; }}
  tr:hover td {{ background: #111; }}
  .meta {{ color: #555; font-size: 0.75em; margin-top: 24px; }}
</style>
</head>
<body>
<h1>◈ BACKTEST — {nombre_archivo}</h1>
<p style="color:#555;font-size:0.8em">
  {m.get('fecha_inicio','')} → {m.get('fecha_fin','')} &nbsp;|&nbsp; Generado: {generado}
</p>

<h2>Resumen</h2>
<div class="grid">
  <div class="card"><div class="label">Total ops</div><div class="value">{m.get('total',0)}</div></div>
  <div class="card"><div class="label">Winrate</div><div class="value" style="color:{wc}">{m.get('winrate',0)}%</div></div>
  <div class="card"><div class="label">Profit total</div><div class="value" style="color:{ptc}">{m.get('profit_total',0)}</div></div>
  <div class="card"><div class="label">Profit factor</div><div class="value" style="color:{pfc}">{m.get('profit_factor',0)}</div></div>
  <div class="card"><div class="label">Max drawdown</div><div class="value" style="color:#e67e22">{m.get('max_drawdown',0)}</div></div>
  <div class="card"><div class="label">WIN / LOSS</div><div class="value"><span style="color:#2ecc71">{m.get('wins',0)}</span> / <span style="color:#e74c3c">{m.get('losses',0)}</span></div></div>
  <div class="card"><div class="label">Avg WIN</div><div class="value" style="color:#2ecc71">{m.get('avg_win',0)}</div></div>
  <div class="card"><div class="label">Avg LOSS</div><div class="value" style="color:#e74c3c">{m.get('avg_loss',0)}</div></div>
  <div class="card"><div class="label">Racha WIN</div><div class="value">{m.get('racha_win_max',0)}</div></div>
  <div class="card"><div class="label">Racha LOSS</div><div class="value" style="color:#e74c3c">{m.get('racha_loss_max',0)}</div></div>
</div>

<h2>Por símbolo</h2>
<table>
  <tr><th>Símbolo</th><th>Total</th><th>WIN</th><th>LOSS</th><th>Winrate</th><th>Profit</th></tr>
  {filas_simbolo}
</table>

<h2>Últimas 50 operaciones</h2>
<table>
  <tr><th>Fecha</th><th>Símbolo</th><th>Tipo</th><th>Precio</th><th>Vol</th><th>Profit</th></tr>
  {filas_ops}
</table>

<p class="meta">termux-ai-stack · backtest_runner.py v1 · {generado}</p>
</body>
</html>"""

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)

    return out_path


# ════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════
def main():
    print("\n  ╔══════════════════════════════════════════╗")
    print("  ║  BACKTEST RUNNER — termux-ai-stack       ║")
    print("  ╚══════════════════════════════════════════╝\n")

    # Modo CLI: backtest_runner.py <archivo.csv>
    if len(sys.argv) > 1:
        filepath = sys.argv[1]
        if filepath == "test":
            _run_test()
            return
    else:
        # Buscar CSVs en rutas comunes
        rutas = [
            os.path.join(HOME, "trading"),
            "/sdcard/Download",
            os.path.join(HOME, "Downloads"),
        ]
        csvs = []
        for ruta in rutas:
            if os.path.isdir(ruta):
                for f in os.listdir(ruta):
                    if f.endswith(".csv") or f.endswith(".CSV"):
                        csvs.append(os.path.join(ruta, f))

        if not csvs:
            print("  No se encontraron archivos CSV.")
            print(f"  Coloca el CSV exportado de MT5 en:")
            print(f"    ~/trading/  o  /sdcard/Download/")
            print(f"\n  Uso directo: python3 backtest_runner.py <archivo.csv>")
            return

        print(f"  Archivos CSV encontrados:\n")
        for i, f in enumerate(csvs, 1):
            print(f"    [{i}] {f}")
        print()
        try:
            idx = int(input("  Elige número: ").strip()) - 1
            if idx < 0 or idx >= len(csvs):
                print("  Número inválido.")
                return
            filepath = csvs[idx]
        except (ValueError, KeyboardInterrupt):
            print("\n  Cancelado.")
            return

    if not os.path.exists(filepath):
        print(f"  [ERROR] Archivo no encontrado: {filepath}")
        return

    print(f"\n  Leyendo: {filepath}")
    ops, errores = parse_csv_mt5(filepath)

    if errores:
        for e in errores:
            print(f"  [AVISO] {e}")

    if not ops:
        print("  No se encontraron operaciones válidas en el archivo.")
        print("  Verifica que sea un CSV exportado desde MT5 → Historial de Operaciones.")
        return

    print(f"  {len(ops)} operaciones cargadas\n")

    metricas = calcular_metricas(ops)
    m = metricas

    # Mostrar en terminal
    print(f"  {'Total ops':<22}: {m['total']}")
    print(f"  {'WIN / LOSS':<22}: {m['wins']} / {m['losses']}")
    print(f"  {'Winrate':<22}: {m['winrate']}%")
    print(f"  {'Profit total':<22}: {m['profit_total']}")
    print(f"  {'Profit factor':<22}: {m['profit_factor']}")
    print(f"  {'Max drawdown':<22}: {m['max_drawdown']}")
    print(f"  {'Racha WIN max':<22}: {m['racha_win_max']}")
    print(f"  {'Racha LOSS max':<22}: {m['racha_loss_max']}")
    print(f"  {'Avg WIN':<22}: {m['avg_win']}")
    print(f"  {'Avg LOSS':<22}: {m['avg_loss']}")

    if m["por_simbolo"]:
        print(f"\n  Por símbolo:")
        for sim, datos in sorted(m["por_simbolo"].items(),
                                  key=lambda x: x[1]["total"], reverse=True):
            wr_s = round(datos["wins"]/datos["total"]*100,1) if datos["total"] > 0 else 0
            print(f"    {sim:<18} {datos['total']} ops  W:{datos['wins']} L:{datos['losses']}  {wr_s}%  profit:{datos['profit']}")

    # Generar HTML
    print()
    nombre = os.path.basename(filepath)
    out = generar_html(metricas, ops, nombre)
    print(f"  [OK] Reporte HTML generado:")
    print(f"       {out}")
    print(f"\n  Abre en el navegador del teléfono o via SSH.")


def _run_test():
    """Test con datos sintéticos."""
    import random
    random.seed(42)
    ops = []
    fecha_base = datetime(2026, 1, 1, 9, 0, 0)
    for i in range(50):
        from datetime import timedelta
        fecha_base = fecha_base + timedelta(hours=random.randint(1, 6))
        profit = random.choice([random.uniform(10, 80), random.uniform(-50, -5)])
        ops.append({
            "fecha":      fecha_base.strftime("%Y-%m-%d %H:%M:%S"),
            "symbol":     random.choice(["GAINX500", "PAINX500", "BOOM500", "EURUSD"]),
            "tipo":       random.choice(["buy", "sell"]),
            "precio":     round(random.uniform(1000, 2000), 2),
            "volumen":    0.01,
            "profit":     round(profit, 2),
            "swap":       0.0,
            "comision":   0.0,
            "profit_neto": round(profit, 2),
            "deal":       str(i),
            "comentario": "",
        })
    metricas = calcular_metricas(ops)
    out = generar_html(metricas, ops, "test_sintetico")
    m = metricas
    print(f"  [TEST] {m['total']} ops | WR:{m['winrate']}% | PF:{m['profit_factor']} | DD:{m['max_drawdown']}")
    print(f"  [TEST] HTML: {out}")


if __name__ == "__main__":
    main()

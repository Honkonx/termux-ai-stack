#!/data/data/com.termux/files/usr/bin/python3
# python/trading/backtest_runner.py v3 UNIFICADO
# termux-ai-stack — Backtest CSV MT5
# Sin pandas: metricas + HTML basico
# Con pandas+matplotlib: + equity curve, histograma, semanal, winrate por simbolo
# REGLAS ARM64: datetime.now() sin requests rutas HOME

import os, sys, csv, io, base64, random
from datetime import datetime, timedelta

HOME       = os.environ.get("HOME", "/data/data/com.termux/files/home")
OUTPUT_DIR = os.path.join(HOME, "trading", "reportes")

try:
    import pandas as pd
    PANDAS_OK = True
except ImportError:
    PANDAS_OK = False

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    MPL_OK = True
except ImportError:
    MPL_OK = False

GRAFICAS_OK = PANDAS_OK and MPL_OK


# ── Selector CSV ─────────────────────────────────────────────────
def buscar_csvs():
    rutas = [
        os.path.join(HOME, "trading"),
        "/sdcard/Download/trading",
        "/sdcard/Download/mt5",
        "/sdcard/Download/backtest",
        "/sdcard/Download",
        os.path.join(HOME, "Downloads"),
    ]
    csvs = []
    for ruta in rutas:
        if os.path.isdir(ruta):
            for f in sorted(os.listdir(ruta)):
                if f.lower().endswith(".csv"):
                    csvs.append(os.path.join(ruta, f))
    return csvs

def elegir_csv():
    while True:
        csvs = buscar_csvs()
        print("  Rutas: ~/trading/ · /sdcard/Download/trading/ · /sdcard/Download/")
        print()
        if csvs:
            print("  CSVs encontrados:\n")
            for i, f in enumerate(csvs, 1):
                tam = os.path.getsize(f)
                ts  = f"{tam//1024}KB" if tam < 1024*1024 else f"{tam//1024//1024}MB"
                print(f"    [{i}] {os.path.basename(f)}  ({ts})")
                print(f"        {os.path.dirname(f)}")
        else:
            print("  Sin CSVs en rutas predeterminadas.")
        print()
        print("    [m] Ruta/carpeta manual")
        print("    [c] Crear /sdcard/Download/trading/")
        print("    [b] Cancelar")
        print()
        try:
            op = input("  Elige: ").strip()
        except (KeyboardInterrupt, EOFError):
            return None
        if op.lower() == "b":
            return None
        elif op.lower() == "c":
            carpeta = "/sdcard/Download/trading"
            try:
                os.makedirs(carpeta, exist_ok=True)
                print(f"\n  [OK] {carpeta} creada")
                print("  Copia tu CSV ahi y presiona ENTER...")
                input()
            except Exception as e:
                print(f"  [ERROR] {e}"); input("  ENTER...")
            continue
        elif op.lower() == "m":
            try:
                ruta = input("  Ruta CSV o carpeta: ").strip().replace("~", HOME)
                if os.path.isdir(ruta):
                    enc = [os.path.join(ruta, f) for f in sorted(os.listdir(ruta))
                           if f.lower().endswith(".csv")]
                    if not enc:
                        print("  Sin CSVs ahi."); input("  ENTER..."); continue
                    for i, f in enumerate(enc, 1):
                        print(f"    [{i}] {os.path.basename(f)}")
                    try:
                        idx = int(input("  Numero: ").strip()) - 1
                        if 0 <= idx < len(enc): return enc[idx]
                    except ValueError:
                        pass
                elif os.path.isfile(ruta) and ruta.lower().endswith(".csv"):
                    return ruta
                else:
                    print("  No es CSV ni carpeta valida."); input("  ENTER...")
            except (KeyboardInterrupt, EOFError):
                return None
            continue
        else:
            try:
                idx = int(op) - 1
                if csvs and 0 <= idx < len(csvs): return csvs[idx]
                print("  Invalido."); input("  ENTER...")
            except ValueError:
                print("  Invalido."); input("  ENTER...")


# ── Parser CSV MT5 ───────────────────────────────────────────────
def parse_csv_mt5(filepath):
    ops, errores = [], []
    for enc in ["utf-8", "utf-8-sig", "latin-1", "cp1252"]:
        try:
            with open(filepath, "r", encoding=enc) as f:
                muestra = f.read(1024)
            encoding = enc; break
        except Exception:
            continue
    else:
        return [], ["No se pudo detectar encoding"]

    sep = "," if muestra.count(",") > muestra.count(";") else ";"
    try:
        with open(filepath, "r", encoding=encoding, newline="") as f:
            reader = csv.reader(f, delimiter=sep)
            headers = []
            for i, row in enumerate(reader):
                if not row or all(c.strip() == "" for c in row): continue
                if not headers:
                    rl = [c.strip().lower() for c in row]
                    if any(k in rl for k in ["time","symbol","type","profit","deal"]):
                        headers = rl; continue
                    if i >= 5:
                        headers = ["time","deal","symbol","type","direction",
                                   "volume","price","order","commission","swap",
                                   "profit","balance","comment"]
                if not headers: continue
                rd = {headers[j]: row[j].strip() for j in range(min(len(headers), len(row)))}
                symbol = rd.get("symbol","").strip()
                if not symbol or symbol.lower() == "symbol": continue
                try:
                    profit = float(rd.get("profit","0").replace(" ","") or "0")
                except ValueError:
                    continue
                direction = rd.get("direction","").lower()
                if direction and direction not in ("out",""): continue
                time_str = rd.get("time","")
                fecha = None
                for fmt in ["%Y.%m.%d %H:%M:%S","%Y-%m-%d %H:%M:%S",
                             "%d/%m/%Y %H:%M:%S","%Y.%m.%d"]:
                    try: fecha = datetime.strptime(time_str, fmt); break
                    except ValueError: continue
                try:
                    precio   = float(rd.get("price","0"))
                    volumen  = float(rd.get("volume","0"))
                    swap     = float(rd.get("swap","0").replace(" ","") or "0")
                    comision = float(rd.get("commission","0").replace(" ","") or "0")
                except ValueError:
                    precio = volumen = swap = comision = 0.0
                ops.append({
                    "fecha":       fecha.strftime("%Y-%m-%d %H:%M:%S") if fecha else time_str,
                    "symbol":      symbol,
                    "tipo":        rd.get("type","").lower(),
                    "precio":      precio, "volumen": volumen,
                    "profit":      profit, "swap": swap, "comision": comision,
                    "profit_neto": profit + swap + comision,
                    "deal":        rd.get("deal",""),
                    "comentario":  rd.get("comment",""),
                })
    except Exception as e:
        errores.append(f"Error leyendo CSV: {e}")
    return ops, errores


# ── Metricas ─────────────────────────────────────────────────────
def calcular_metricas(ops):
    if not ops: return {}
    profits = [op["profit_neto"] for op in ops]
    wins    = [p for p in profits if p > 0]
    losses  = [p for p in profits if p < 0]
    total   = len(profits)
    wr  = round(len(wins)/total*100, 1) if total > 0 else 0.0
    pf  = round(abs(sum(wins)/sum(losses)), 2) if losses and sum(losses) != 0 else 0.0
    equity = peak = max_dd = 0.0
    for p in profits:
        equity += p
        if equity > peak: peak = equity
        dd = peak - equity
        if dd > max_dd: max_dd = dd
    rw = rl = rwa = rla = 0
    for p in profits:
        if p > 0:   rwa += 1; rla = 0; rw = max(rw, rwa)
        elif p < 0: rla += 1; rwa = 0; rl = max(rl, rla)
        else:       rwa = rla = 0
    por_sim = {}
    for op in ops:
        s = op["symbol"]
        if s not in por_sim: por_sim[s] = {"total":0,"wins":0,"losses":0,"profit":0.0}
        por_sim[s]["total"] += 1
        por_sim[s]["profit"] = round(por_sim[s]["profit"] + op["profit_neto"], 2)
        if op["profit_neto"] > 0:   por_sim[s]["wins"]   += 1
        elif op["profit_neto"] < 0: por_sim[s]["losses"] += 1
    fechas = [op["fecha"] for op in ops if op["fecha"]]
    return {
        "total": total, "wins": len(wins), "losses": len(losses),
        "breakeven": len([p for p in profits if p == 0]),
        "winrate": wr, "profit_total": round(sum(profits), 2),
        "avg_win": round(sum(wins)/len(wins),2) if wins else 0.0,
        "avg_loss": round(sum(losses)/len(losses),2) if losses else 0.0,
        "profit_factor": pf, "max_drawdown": round(max_dd,2),
        "racha_win_max": rw, "racha_loss_max": rl,
        "por_simbolo": por_sim,
        "fecha_inicio": min(fechas) if fechas else "",
        "fecha_fin":    max(fechas) if fechas else "",
    }


# ── Graficas ─────────────────────────────────────────────────────
def _b64(fig):
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=110, bbox_inches="tight",
                facecolor="#0d0d0d", edgecolor="none")
    buf.seek(0); b = base64.b64encode(buf.read()).decode(); buf.close()
    plt.close(fig); return b

def _equity(ops):
    acc = 0.0; equity = []
    for op in ops: acc += op["profit_neto"]; equity.append(acc)
    fig, ax = plt.subplots(figsize=(8,3))
    fig.patch.set_facecolor("#0d0d0d"); ax.set_facecolor("#111")
    c = "#2ecc71" if equity[-1] >= 0 else "#e74c3c"
    ax.plot(range(len(equity)), equity, color=c, linewidth=1.5)
    ax.fill_between(range(len(equity)), equity, 0,
                    where=[v>=0 for v in equity], alpha=0.12, color="#2ecc71")
    ax.fill_between(range(len(equity)), equity, 0,
                    where=[v<0 for v in equity], alpha=0.12, color="#e74c3c")
    ax.axhline(0, color="#333", linewidth=0.8, linestyle="--")
    ax.set_title("Equity Curve", color="#888", fontsize=9, pad=5)
    ax.tick_params(colors="#555", labelsize=7)
    [s.set_color("#222") for s in ax.spines.values()]
    ax.set_xlabel("Operaciones", color="#555", fontsize=7)
    ax.set_ylabel("Profit acumulado", color="#555", fontsize=7)
    plt.tight_layout(pad=0.5); return _b64(fig)

def _histograma(ops):
    profits = [op["profit_neto"] for op in ops]
    media = sum(profits)/len(profits)
    fig, ax = plt.subplots(figsize=(8,2.8))
    fig.patch.set_facecolor("#0d0d0d"); ax.set_facecolor("#111")
    bins = min(30, max(10, len(profits)//5))
    ax.hist(profits, bins=bins, color="#00bcd4", alpha=0.7, edgecolor="#0d0d0d")
    ax.axvline(0, color="#555", linewidth=0.8, linestyle="--")
    ax.axvline(media, color="#f39c12", linewidth=1, label=f"Media: {media:.2f}")
    ax.set_title("Distribucion de Profits", color="#888", fontsize=9, pad=5)
    ax.tick_params(colors="#555", labelsize=7)
    [s.set_color("#222") for s in ax.spines.values()]
    ax.legend(fontsize=7, facecolor="#111", edgecolor="#333", labelcolor="#aaa")
    plt.tight_layout(pad=0.5); return _b64(fig)

def _semanal(ops):
    if not PANDAS_OK: return None
    df = pd.DataFrame(ops)
    df["fd"] = pd.to_datetime(df["fecha"], errors="coerce")
    df = df.dropna(subset=["fd"])
    if df.empty: return None
    sem = df.set_index("fd").resample("W")["profit_neto"].sum()
    if len(sem) < 2: return None
    fig, ax = plt.subplots(figsize=(8,2.8))
    fig.patch.set_facecolor("#0d0d0d"); ax.set_facecolor("#111")
    colores = ["#2ecc71" if v>=0 else "#e74c3c" for v in sem.values]
    ax.bar(range(len(sem)), sem.values, color=colores, edgecolor="#0d0d0d", width=0.7)
    ax.axhline(0, color="#333", linewidth=0.8, linestyle="--")
    labels = [d.strftime("%d/%m") for d in sem.index]
    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=45, fontsize=6, color="#555")
    ax.set_title("Profit por Semana", color="#888", fontsize=9, pad=5)
    ax.tick_params(colors="#555", labelsize=7)
    [s.set_color("#222") for s in ax.spines.values()]
    plt.tight_layout(pad=0.5); return _b64(fig)

def _wr_sim(ops):
    ps = {}
    for op in ops:
        s = op["symbol"]
        if s not in ps: ps[s] = {"t":0,"w":0}
        ps[s]["t"] += 1
        if op["profit_neto"] > 0: ps[s]["w"] += 1
    if not ps: return None
    sims = list(ps.keys())
    wrs  = [round(ps[s]["w"]/ps[s]["t"]*100,1) for s in sims]
    pares = sorted(zip(wrs,sims), reverse=True)
    wrs, sims = zip(*pares)
    fig, ax = plt.subplots(figsize=(8, max(2.5, len(sims)*0.45)))
    fig.patch.set_facecolor("#0d0d0d"); ax.set_facecolor("#111")
    colores = ["#2ecc71" if w>=50 else "#e74c3c" for w in wrs]
    bars = ax.barh(sims, wrs, color=colores, edgecolor="#0d0d0d", height=0.6)
    ax.axvline(50, color="#555", linewidth=0.8, linestyle="--")
    ax.set_xlim(0,105)
    ax.set_title("Winrate por Simbolo", color="#888", fontsize=9, pad=5)
    ax.tick_params(colors="#555", labelsize=7)
    [s.set_color("#222") for s in ax.spines.values()]
    for bar, wr in zip(bars, wrs):
        ax.text(bar.get_width()+1, bar.get_y()+bar.get_height()/2,
                f"{wr}%", va="center", fontsize=6, color="#aaa")
    plt.tight_layout(pad=0.5); return _b64(fig)

def generar_graficas(ops):
    if not GRAFICAS_OK: return {}
    print("  Generando graficas", end="", flush=True)
    g = {}
    g["equity"]     = _equity(ops);     print(".", end="", flush=True)
    g["histograma"] = _histograma(ops); print(".", end="", flush=True)
    g["semanal"]    = _semanal(ops);    print(".", end="", flush=True)
    g["wr_sim"]     = _wr_sim(ops);     print(" listo\n")
    return g


# ── HTML unificado ───────────────────────────────────────────────
def generar_html(metricas, ops, nombre, graficas=None):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    ts       = datetime.now().strftime("%Y%m%d_%H%M%S")
    modo     = "avanzado" if graficas else "basico"
    out_path = os.path.join(OUTPUT_DIR, f"backtest_{modo}_{ts}.html")
    generado = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    m = metricas
    wc  = "#2ecc71" if m.get("winrate",0)>=50 else "#e74c3c"
    pfc = "#2ecc71" if m.get("profit_factor",0)>=1 else "#e74c3c"
    ptc = "#2ecc71" if m.get("profit_total",0)>=0 else "#e74c3c"

    def img(key):
        b64 = (graficas or {}).get(key)
        if not b64:
            return '<p style="color:#333;font-size:0.72em;padding:8px">Instala pandas+matplotlib para ver graficas:<br>pip install pandas matplotlib --break-system-packages</p>'
        return f'<img src="data:image/png;base64,{b64}" style="width:100%;border-radius:5px;margin:3px 0">'

    badge = ('<span style="background:#1a3a1a;color:#2ecc71;padding:1px 6px;border-radius:3px;font-size:0.62em">pandas+matplotlib</span>'
             if graficas else
             '<span style="background:#1a1a1a;color:#555;padding:1px 6px;border-radius:3px;font-size:0.62em">modo basico</span>')

    filas_sim = ""
    for sim, d in sorted(m.get("por_simbolo",{}).items(), key=lambda x:x[1]["total"], reverse=True):
        wr_s = round(d["wins"]/d["total"]*100,1) if d["total"]>0 else 0
        c = "#2ecc71" if d["profit"]>=0 else "#e74c3c"
        filas_sim += f'<tr><td>{sim}</td><td>{d["total"]}</td><td style="color:#2ecc71">{d["wins"]}</td><td style="color:#e74c3c">{d["losses"]}</td><td>{wr_s}%</td><td style="color:{c}">{d["profit"]}</td></tr>'

    filas_ops = ""
    for op in ops[-50:]:
        c = "#2ecc71" if op["profit_neto"]>0 else ("#e74c3c" if op["profit_neto"]<0 else "#888")
        filas_ops += f'<tr><td>{op["fecha"]}</td><td>{op["symbol"]}</td><td>{op["tipo"].upper()}</td><td>{op["precio"]}</td><td>{op["volumen"]}</td><td style="color:{c}">{op["profit_neto"]}</td></tr>'

    html = f"""<!DOCTYPE html><html lang="es"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Backtest {nombre}</title>
<style>*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:monospace;background:#0d0d0d;color:#ccc;padding:14px}}
h1{{color:#00bcd4;font-size:1em;border-bottom:1px solid #1a1a1a;padding-bottom:7px;margin-bottom:10px}}
h2{{color:#555;font-size:0.72em;text-transform:uppercase;letter-spacing:2px;margin:16px 0 6px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(120px,1fr));gap:5px}}
.card{{background:#111;border:1px solid #1a1a1a;border-radius:5px;padding:9px}}
.card .l{{font-size:0.6em;color:#555;text-transform:uppercase}}
.card .v{{font-size:1.1em;font-weight:bold;margin-top:3px}}
.g{{background:#111;border:1px solid #1a1a1a;border-radius:5px;padding:8px;margin:4px 0}}
table{{width:100%;border-collapse:collapse;font-size:0.7em;margin-top:5px}}
th{{background:#111;color:#555;padding:5px 6px;text-align:left;font-size:0.66em;text-transform:uppercase}}
td{{padding:4px 6px;border-bottom:1px solid #131313}}
tr:hover td{{background:#0f0f0f}}
.meta{{color:#2a2a2a;font-size:0.62em;margin-top:16px}}</style></head><body>
<h1>BACKTEST {nombre} {badge}</h1>
<p style="color:#444;font-size:0.7em">{m.get("fecha_inicio","")} to {m.get("fecha_fin","")} | {generado}</p>
<h2>Metricas</h2>
<div class="grid">
<div class="card"><div class="l">Total ops</div><div class="v">{m.get("total",0)}</div></div>
<div class="card"><div class="l">Winrate</div><div class="v" style="color:{wc}">{m.get("winrate",0)}%</div></div>
<div class="card"><div class="l">Profit total</div><div class="v" style="color:{ptc}">{m.get("profit_total",0)}</div></div>
<div class="card"><div class="l">Profit factor</div><div class="v" style="color:{pfc}">{m.get("profit_factor",0)}</div></div>
<div class="card"><div class="l">Max drawdown</div><div class="v" style="color:#e67e22">{m.get("max_drawdown",0)}</div></div>
<div class="card"><div class="l">WIN / LOSS</div><div class="v"><span style="color:#2ecc71">{m.get("wins",0)}</span>/<span style="color:#e74c3c">{m.get("losses",0)}</span></div></div>
<div class="card"><div class="l">Avg WIN</div><div class="v" style="color:#2ecc71">{m.get("avg_win",0)}</div></div>
<div class="card"><div class="l">Avg LOSS</div><div class="v" style="color:#e74c3c">{m.get("avg_loss",0)}</div></div>
<div class="card"><div class="l">Racha WIN</div><div class="v">{m.get("racha_win_max",0)}</div></div>
<div class="card"><div class="l">Racha LOSS</div><div class="v" style="color:#e74c3c">{m.get("racha_loss_max",0)}</div></div>
</div>
<h2>Equity Curve</h2><div class="g">{img("equity")}</div>
<h2>Distribucion de Profits</h2><div class="g">{img("histograma")}</div>
<h2>Profit por Semana</h2><div class="g">{img("semanal")}</div>
<h2>Winrate por Simbolo</h2><div class="g">{img("wr_sim")}</div>
<h2>Por simbolo</h2>
<table><tr><th>Simbolo</th><th>Total</th><th>WIN</th><th>LOSS</th><th>Winrate</th><th>Profit</th></tr>
{filas_sim}</table>
<h2>Ultimas 50 operaciones</h2>
<table><tr><th>Fecha</th><th>Simbolo</th><th>Tipo</th><th>Precio</th><th>Vol</th><th>Profit</th></tr>
{filas_ops}</table>
<p class="meta">termux-ai-stack backtest_runner.py v3 {generado}</p>
</body></html>"""

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)
    return out_path


# ── Main ─────────────────────────────────────────────────────────
def main():
    print("\n  BACKTEST RUNNER v3 -- termux-ai-stack")
    print(f"  pandas: {'OK' if PANDAS_OK else 'NO'}  matplotlib: {'OK' if MPL_OK else 'NO'}\n")
    if not GRAFICAS_OK:
        print("  Modo basico (sin graficas)")
        print("  Para graficas: pip install pandas matplotlib --break-system-packages")
        print("  Tiempo estimado: 3-8 min primera vez, segundos con cache\n")

    if len(sys.argv) > 1 and sys.argv[1] == "test":
        _run_test(); return

    filepath = sys.argv[1].replace("~", HOME) if len(sys.argv) > 1 else elegir_csv()
    if not filepath: print("  Cancelado."); return
    if not os.path.exists(filepath): print(f"  ERROR: {filepath}"); return

    print(f"\n  Leyendo: {filepath}")
    ops, errores = parse_csv_mt5(filepath)
    for e in errores: print(f"  AVISO: {e}")
    if not ops:
        print("  Sin operaciones. Verifica CSV de MT5 > Historial de Operaciones."); return

    print(f"  {len(ops)} operaciones cargadas\n")
    metricas = calcular_metricas(ops)
    graficas = generar_graficas(ops)
    m = metricas

    print(f"  {'Total':<20}: {m['total']}")
    print(f"  {'WIN/LOSS':<20}: {m['wins']} / {m['losses']}")
    print(f"  {'Winrate':<20}: {m['winrate']}%")
    print(f"  {'Profit total':<20}: {m['profit_total']}")
    print(f"  {'Profit factor':<20}: {m['profit_factor']}")
    print(f"  {'Max drawdown':<20}: {m['max_drawdown']}")
    print(f"  {'Racha WIN/LOSS':<20}: {m['racha_win_max']} / {m['racha_loss_max']}")
    print(f"  {'Avg WIN/LOSS':<20}: {m['avg_win']} / {m['avg_loss']}")

    if m["por_simbolo"]:
        print("\n  Por simbolo:")
        for sim, d in sorted(m["por_simbolo"].items(), key=lambda x: x[1]["total"], reverse=True):
            wr_s = round(d["wins"]/d["total"]*100,1) if d["total"]>0 else 0
            print(f"    {sim:<18} {d['total']} ops  W:{d['wins']} L:{d['losses']}  {wr_s}%  {d['profit']}")

    print()
    out = generar_html(metricas, ops, os.path.basename(filepath), graficas)
    print(f"  Reporte: {out}")
    print(f"  Modo: {'avanzado con graficas' if graficas else 'basico'}")
    print("  Abre en el navegador del telefono.")


def _run_test():
    random.seed(42)
    ops = []
    fecha = datetime(2026, 1, 1, 9, 0, 0)
    for i in range(80):
        fecha += timedelta(hours=random.randint(1, 8))
        profit = random.choice([random.uniform(5,100), random.uniform(-60,-5)])
        ops.append({
            "fecha": fecha.strftime("%Y-%m-%d %H:%M:%S"),
            "symbol": random.choice(["GAINX500","PAINX500","BOOM500","EURUSD","XAUUSD"]),
            "tipo": random.choice(["buy","sell"]),
            "precio": round(random.uniform(1000,2000),2), "volumen": 0.01,
            "profit": round(profit,2), "swap": 0.0, "comision": 0.0,
            "profit_neto": round(profit,2), "deal": str(i), "comentario": "",
        })
    metricas = calcular_metricas(ops)
    graficas = generar_graficas(ops)
    out = generar_html(metricas, ops, "test_v3", graficas)
    m = metricas
    print(f"  TEST: {m['total']} ops | WR:{m['winrate']}% | PF:{m['profit_factor']} | DD:{m['max_drawdown']}")
    print(f"  Graficas: {'OK' if graficas else 'NO (instala pandas+matplotlib)'}")
    print(f"  HTML: {out}")


if __name__ == "__main__":
    main()

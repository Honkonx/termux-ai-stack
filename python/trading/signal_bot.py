#!/data/data/com.termux/files/usr/bin/python3
# python/trading/signal_bot.py
# termux-ai-stack — Bot senales GainX/PainX/Boom/Crash
# REGLAS ARM64: datetime.now() siempre · urllib (no requests) · rutas $HOME

import sqlite3
import os
import sys
import json
from datetime import datetime
from urllib import request as ureq
from urllib.error import URLError

DB_PATH = os.path.join(os.environ.get("HOME", "/data/data/com.termux/files/home"), "trading", "senales.db")
CFG_PATH = os.path.join(os.environ.get("HOME", "/data/data/com.termux/files/home"), ".trading_config")

ACTIVOS = ["GainX 500", "GainX 800", "PainX 500", "PainX 800", "Boom 500", "Boom 1000", "Crash 500", "Crash 1000"]

# ── Init BD ──────────────────────────────────────────────────────
def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS senales (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            activo    TEXT NOT NULL,
            tipo      TEXT NOT NULL,
            entrada   REAL,
            sl        REAL,
            tp1       REAL,
            tp2       REAL,
            confianza INTEGER,
            resultado TEXT DEFAULT 'PENDIENTE',
            notas     TEXT DEFAULT '',
            fecha     TEXT NOT NULL
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS config (
            clave TEXT PRIMARY KEY,
            valor TEXT NOT NULL,
            fecha TEXT NOT NULL
        )
    """)
    conn.commit()
    conn.close()

# ── Guardar señal ────────────────────────────────────────────────
def guardar_señal(activo, tipo, entrada, sl, tp1, tp2, confianza, notas=""):
    fecha = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        INSERT INTO senales (activo, tipo, entrada, sl, tp1, tp2, confianza, resultado, notas, fecha)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'PENDIENTE', ?, ?)
    """, (activo, tipo, entrada, sl, tp1, tp2, confianza, notas, fecha))
    conn.commit()
    señal_id = c.lastrowid
    conn.close()
    return señal_id

# ── Ver últimas senales ──────────────────────────────────────────
def ver_senales(limit=10):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        SELECT id, activo, tipo, entrada, sl, tp1, confianza, resultado, fecha
        FROM senales ORDER BY id DESC LIMIT ?
    """, (limit,))
    rows = c.fetchall()
    conn.close()
    return rows

# ── Stats win/loss ───────────────────────────────────────────────
def get_stats():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM senales")
    total = c.fetchone()[0]
    c.execute("SELECT COUNT(*) FROM senales WHERE resultado='WIN'")
    wins = c.fetchone()[0]
    c.execute("SELECT COUNT(*) FROM senales WHERE resultado='LOSS'")
    losses = c.fetchone()[0]
    c.execute("SELECT COUNT(*) FROM senales WHERE resultado='PENDIENTE'")
    pendientes = c.fetchone()[0]
    conn.close()
    winrate = round((wins / (wins + losses) * 100), 1) if (wins + losses) > 0 else 0.0
    return {"total": total, "wins": wins, "losses": losses, "pendientes": pendientes, "winrate": winrate}

# ── Entrada manual interactiva ───────────────────────────────────
def entrada_manual():
    print("\n  ╔══════════════════════════════════════╗")
    print("  ║  NUEVA SEÑAL MANUAL                  ║")
    print("  ╚══════════════════════════════════════╝\n")

    print("  Activos disponibles:")
    for i, a in enumerate(ACTIVOS, 1):
        print(f"    [{i}] {a}")
    print()

    try:
        idx = int(input("  Activo (número): ").strip()) - 1
        if idx < 0 or idx >= len(ACTIVOS):
            print("  [ERROR] Número inválido")
            return None
        activo = ACTIVOS[idx]

        tipo_input = input("  Tipo (1=BUY / 2=SELL): ").strip()
        tipo = "BUY" if tipo_input == "1" else "SELL"

        entrada = float(input("  Precio entrada: ").strip())
        sl      = float(input("  Stop Loss: ").strip())
        tp1     = float(input("  TP1: ").strip())
        tp2_raw = input("  TP2 (ENTER para omitir): ").strip()
        tp2     = float(tp2_raw) if tp2_raw else None
        confianza = int(input("  Confianza 1-10: ").strip())
        notas     = input("  Notas (ENTER omitir): ").strip()

    except (ValueError, KeyboardInterrupt):
        print("\n  [CANCELADO]")
        return None

    señal_id = guardar_señal(activo, tipo, entrada, sl, tp1, tp2, confianza, notas)

    print(f"\n  ✓ Señal #{señal_id} guardada")
    print(f"    {activo} · {tipo} · entrada={entrada} · SL={sl} · TP1={tp1}")
    print(f"    Confianza: {confianza}/10 · {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
    return señal_id

# ── Main ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    init_db()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "nueva"

    if cmd == "nueva":
        entrada_manual()

    elif cmd == "ver":
        limit = int(sys.argv[2]) if len(sys.argv) > 2 else 10
        rows = ver_senales(limit)
        if not rows:
            print("\n  Sin senales registradas.\n")
        else:
            print(f"\n  {'ID':<4} {'ACTIVO':<14} {'TIPO':<5} {'ENTRADA':<10} {'SL':<10} {'TP1':<10} {'CONF':<5} {'RESULT':<10} FECHA")
            print("  " + "─" * 80)
            for r in rows:
                print(f"  {r[0]:<4} {r[1]:<14} {r[2]:<5} {str(r[3]):<10} {str(r[4]):<10} {str(r[5]):<10} {str(r[6]):<5} {r[7]:<10} {r[8]}")
            print()

    elif cmd == "stats":
        s = get_stats()
        print(f"\n  ╔══════════════════════════════════════╗")
        print(f"  ║  ESTADÍSTICAS TRADING                ║")
        print(f"  ╠══════════════════════════════════════╣")
        print(f"  ║  Total senales : {s['total']:<20}║")
        print(f"  ║  WIN           : {s['wins']:<20}║")
        print(f"  ║  LOSS          : {s['losses']:<20}║")
        print(f"  ║  Pendientes    : {s['pendientes']:<20}║")
        print(f"  ║  Winrate       : {str(s['winrate']) + '%':<20}║")
        print(f"  ╚══════════════════════════════════════╝\n")

    elif cmd == "init":
        print("  [OK] BD inicializada en", DB_PATH)

    else:
        print(f"  Uso: signal_bot.py [nueva|ver|stats|init]")

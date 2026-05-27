#!/data/data/com.termux/files/usr/bin/python3
# python/trading/trade_tracker.py
# termux-ai-stack — Registrar resultados de senales
# REGLAS ARM64: datetime.now() siempre · sin requests

import sqlite3
import os
import sys
from datetime import datetime

DB_PATH = os.path.join(os.environ.get("HOME", "/data/data/com.termux/files/home"), "trading", "db", "senales.db")

# ── Actualizar resultado de señal ────────────────────────────────
def actualizar_resultado(señal_id, resultado, notas=""):
    resultado = resultado.upper()
    if resultado not in ("WIN", "LOSS", "PENDIENTE", "CANCELADA"):
        print(f"  [ERROR] Resultado inválido: {resultado}")
        print("  Valores válidos: WIN · LOSS · PENDIENTE · CANCELADA")
        return False

    if not os.path.exists(DB_PATH):
        print(f"  [ERROR] BD no encontrada: {DB_PATH}")
        print("  Ejecuta primero: python signal_bot.py init")
        return False

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Verificar que existe
    c.execute("SELECT id, activo, tipo, resultado FROM senales WHERE id=?", (señal_id,))
    row = c.fetchone()
    if not row:
        conn.close()
        print(f"  [ERROR] Señal #{señal_id} no encontrada")
        return False

    fecha_update = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if notas:
        c.execute("""
            UPDATE senales SET resultado=?, notas=notas||' ['||?||'] '||?
            WHERE id=?
        """, (resultado, fecha_update, notas, señal_id))
    else:
        c.execute("UPDATE senales SET resultado=? WHERE id=?", (resultado, señal_id))

    conn.commit()
    conn.close()

    icono = "✓" if resultado == "WIN" else "✗" if resultado == "LOSS" else "○"
    print(f"\n  {icono} Señal #{señal_id} → {resultado}")
    print(f"    {row[1]} · {row[2]} · anterior: {row[3]}\n")
    return True

# ── Actualizar interactivo ───────────────────────────────────────
def actualizar_interactivo():
    print("\n  ╔══════════════════════════════════════╗")
    print("  ║  REGISTRAR RESULTADO                 ║")
    print("  ╚══════════════════════════════════════╝\n")

    # Mostrar pendientes primero
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        SELECT id, activo, tipo, entrada, fecha
        FROM senales WHERE resultado='PENDIENTE'
        ORDER BY id DESC LIMIT 10
    """)
    pendientes = c.fetchall()
    conn.close()

    if not pendientes:
        print("  Sin senales pendientes.\n")
        return

    print("  Señales PENDIENTES:")
    for p in pendientes:
        print(f"    #{p[0]} · {p[1]} · {p[2]} · entrada={p[3]} · {p[4][:10]}")
    print()

    try:
        señal_id = int(input("  ID de señal a actualizar: ").strip())
        print("  Resultado: [1] WIN  [2] LOSS  [3] CANCELADA")
        res_input = input("  Opción: ").strip()
        mapa = {"1": "WIN", "2": "LOSS", "3": "CANCELADA"}
        resultado = mapa.get(res_input)
        if not resultado:
            print("  [CANCELADO]")
            return
        notas = input("  Notas (ENTER omitir): ").strip()
    except (ValueError, KeyboardInterrupt):
        print("\n  [CANCELADO]")
        return

    actualizar_resultado(señal_id, resultado, notas)

# ── Historial reciente ───────────────────────────────────────────
def historial(limit=20):
    if not os.path.exists(DB_PATH):
        print("  [ERROR] BD no encontrada. Ejecuta signal_bot.py init primero.")
        return

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        SELECT id, activo, tipo, entrada, resultado, confianza, fecha
        FROM senales ORDER BY id DESC LIMIT ?
    """, (limit,))
    rows = c.fetchall()
    conn.close()

    if not rows:
        print("\n  Sin historial registrado.\n")
        return

    wins   = sum(1 for r in rows if r[4] == "WIN")
    losses = sum(1 for r in rows if r[4] == "LOSS")

    print(f"\n  Últimas {len(rows)} operaciones  (W:{wins} / L:{losses})\n")
    print(f"  {'ID':<4} {'ACTIVO':<14} {'TIPO':<5} {'ENTRADA':<10} {'RESULTADO':<10} {'CONF':<5} FECHA")
    print("  " + "─" * 60)
    for r in rows:
        icono = "✓" if r[4] == "WIN" else "✗" if r[4] == "LOSS" else "○"
        print(f"  {r[0]:<4} {r[1]:<14} {r[2]:<5} {str(r[3]):<10} {icono} {r[4]:<8} {str(r[5]):<5} {r[6][:16]}")
    print()

# ── Main ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "actualizar"

    if cmd == "actualizar":
        actualizar_interactivo()

    elif cmd == "set":
        # Uso directo: trade_tracker.py set <id> <WIN|LOSS>
        if len(sys.argv) < 4:
            print("  Uso: trade_tracker.py set <id> <WIN|LOSS> [notas]")
            sys.exit(1)
        señal_id = int(sys.argv[2])
        resultado = sys.argv[3]
        notas = sys.argv[4] if len(sys.argv) > 4 else ""
        actualizar_resultado(señal_id, resultado, notas)

    elif cmd == "historial":
        limit = int(sys.argv[2]) if len(sys.argv) > 2 else 20
        historial(limit)

    else:
        print("  Uso: trade_tracker.py [actualizar|set <id> <resultado>|historial]")

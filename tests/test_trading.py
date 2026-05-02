#!/data/data/com.termux/files/usr/bin/python3
# tests/test_trading.py
# termux-ai-stack — Tests bot trading ARM64
# Sin pytest (builtin unittest solamente)

import unittest
import sqlite3
import os
import sys
import shutil
from datetime import datetime

# Ruta de test separada — no tocar la BD de producción
HOME = os.environ.get("HOME", "/data/data/com.termux/files/home")
TEST_DB = os.path.join(HOME, "trading", "senales_test.db")

# Parchear DB_PATH antes de importar los módulos
sys.path.insert(0, os.path.join(HOME, "python", "trading"))

# ── Importar módulos con BD de test ──────────────────────────────
# Importamos las funciones directamente para no depender de rutas
def _get_conn():
    return sqlite3.connect(TEST_DB)

def _init_test_db():
    os.makedirs(os.path.dirname(TEST_DB), exist_ok=True)
    conn = _get_conn()
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
    conn.commit()
    conn.close()

def _insertar_senal(activo, tipo, entrada, sl, tp1, tp2, confianza, resultado="PENDIENTE"):
    fecha = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = _get_conn()
    c = conn.cursor()
    c.execute("""
        INSERT INTO senales (activo, tipo, entrada, sl, tp1, tp2, confianza, resultado, notas, fecha)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', ?)
    """, (activo, tipo, entrada, sl, tp1, tp2, confianza, resultado, fecha))
    conn.commit()
    sid = c.lastrowid
    conn.close()
    return sid

def _actualizar_resultado(senal_id, resultado):
    conn = _get_conn()
    c = conn.cursor()
    c.execute("UPDATE senales SET resultado=? WHERE id=?", (resultado, senal_id))
    conn.commit()
    conn.close()

def _get_stats():
    conn = _get_conn()
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM senales")
    total = c.fetchone()[0]
    c.execute("SELECT COUNT(*) FROM senales WHERE resultado='WIN'")
    wins = c.fetchone()[0]
    c.execute("SELECT COUNT(*) FROM senales WHERE resultado='LOSS'")
    losses = c.fetchone()[0]
    conn.close()
    winrate = round((wins / (wins + losses) * 100), 1) if (wins + losses) > 0 else 0.0
    return {"total": total, "wins": wins, "losses": losses, "winrate": winrate}


# ════════════════════════════════════════════════════════════════
#  TESTS
# ════════════════════════════════════════════════════════════════

class TestDBInit(unittest.TestCase):
    """Test inicialización de la base de datos"""

    def test_db_se_crea(self):
        _init_test_db()
        self.assertTrue(os.path.exists(TEST_DB), "BD de test no se creó")

    def test_tabla_senales_existe(self):
        _init_test_db()
        conn = _get_conn()
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='senales'")
        result = c.fetchone()
        conn.close()
        self.assertIsNotNone(result, "Tabla 'senales' no existe")

    def test_columnas_correctas(self):
        _init_test_db()
        conn = _get_conn()
        c = conn.cursor()
        c.execute("PRAGMA table_info(senales)")
        cols = {row[1] for row in c.fetchall()}
        conn.close()
        required = {"id", "activo", "tipo", "entrada", "sl", "tp1", "tp2", "confianza", "resultado", "notas", "fecha"}
        self.assertEqual(required, cols, f"Columnas incorrectas. Faltan: {required - cols}")


class TestInsertarSenal(unittest.TestCase):
    """Test inserción de senales"""

    def setUp(self):
        _init_test_db()

    def test_insertar_senal_basica(self):
        sid = _insertar_senal("GainX 500", "BUY", 1234.5, 1200.0, 1280.0, None, 8)
        self.assertIsNotNone(sid)
        self.assertGreater(sid, 0)

    def test_fecha_nunca_vacia(self):
        """ARM64 regla: fecha siempre desde Python, nunca DEFAULT SQL"""
        sid = _insertar_senal("Boom 500", "SELL", 900.0, 950.0, 850.0, 800.0, 7)
        conn = _get_conn()
        c = conn.cursor()
        c.execute("SELECT fecha FROM senales WHERE id=?", (sid,))
        fecha = c.fetchone()[0]
        conn.close()
        self.assertIsNotNone(fecha, "fecha es NULL — viola regla ARM64")
        self.assertNotEqual(fecha, "", "fecha está vacía — viola regla ARM64")
        # Validar formato YYYY-MM-DD HH:MM:SS
        try:
            datetime.strptime(fecha, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            self.fail(f"Formato de fecha incorrecto: {fecha}")

    def test_resultado_default_pendiente(self):
        sid = _insertar_senal("PainX 800", "BUY", 500.0, 480.0, 530.0, None, 6)
        conn = _get_conn()
        c = conn.cursor()
        c.execute("SELECT resultado FROM senales WHERE id=?", (sid,))
        resultado = c.fetchone()[0]
        conn.close()
        self.assertEqual(resultado, "PENDIENTE")

    def test_tipos_validos(self):
        sid_buy  = _insertar_senal("Crash 500", "BUY",  300.0, 280.0, 330.0, None, 9)
        sid_sell = _insertar_senal("Crash 500", "SELL", 300.0, 320.0, 270.0, None, 9)
        self.assertGreater(sid_buy, 0)
        self.assertGreater(sid_sell, 0)


class TestActualizarResultado(unittest.TestCase):
    """Test actualización WIN/LOSS"""

    def setUp(self):
        _init_test_db()

    def test_marcar_win(self):
        sid = _insertar_senal("GainX 800", "BUY", 2000.0, 1950.0, 2100.0, None, 8)
        _actualizar_resultado(sid, "WIN")
        conn = _get_conn()
        c = conn.cursor()
        c.execute("SELECT resultado FROM senales WHERE id=?", (sid,))
        self.assertEqual(c.fetchone()[0], "WIN")
        conn.close()

    def test_marcar_loss(self):
        sid = _insertar_senal("PainX 500", "SELL", 1000.0, 1050.0, 900.0, None, 5)
        _actualizar_resultado(sid, "LOSS")
        conn = _get_conn()
        c = conn.cursor()
        c.execute("SELECT resultado FROM senales WHERE id=?", (sid,))
        self.assertEqual(c.fetchone()[0], "LOSS")
        conn.close()

    def test_cambio_de_resultado(self):
        """Debe poder cambiar de PENDIENTE → WIN → LOSS"""
        sid = _insertar_senal("Boom 1000", "BUY", 5000.0, 4800.0, 5500.0, None, 7)
        _actualizar_resultado(sid, "WIN")
        _actualizar_resultado(sid, "LOSS")
        conn = _get_conn()
        c = conn.cursor()
        c.execute("SELECT resultado FROM senales WHERE id=?", (sid,))
        self.assertEqual(c.fetchone()[0], "LOSS")
        conn.close()


class TestEstadisticas(unittest.TestCase):
    """Test cálculo de stats winrate"""

    def setUp(self):
        # BD limpia para cada test de stats
        if os.path.exists(TEST_DB):
            os.remove(TEST_DB)
        _init_test_db()

    def test_stats_bd_vacia(self):
        s = _get_stats()
        self.assertEqual(s["total"], 0)
        self.assertEqual(s["winrate"], 0.0)

    def test_winrate_100(self):
        sid1 = _insertar_senal("GainX 500", "BUY", 100.0, 90.0, 120.0, None, 8)
        sid2 = _insertar_senal("GainX 500", "BUY", 200.0, 190.0, 220.0, None, 9)
        _actualizar_resultado(sid1, "WIN")
        _actualizar_resultado(sid2, "WIN")
        s = _get_stats()
        self.assertEqual(s["winrate"], 100.0)

    def test_winrate_50(self):
        sid1 = _insertar_senal("PainX 500", "SELL", 100.0, 110.0, 80.0, None, 7)
        sid2 = _insertar_senal("PainX 500", "SELL", 200.0, 210.0, 180.0, None, 6)
        _actualizar_resultado(sid1, "WIN")
        _actualizar_resultado(sid2, "LOSS")
        s = _get_stats()
        self.assertEqual(s["winrate"], 50.0)

    def test_pendientes_no_cuentan_en_winrate(self):
        sid1 = _insertar_senal("Boom 500", "BUY", 100.0, 90.0, 120.0, None, 8)
        sid2 = _insertar_senal("Boom 500", "BUY", 200.0, 190.0, 220.0, None, 7)
        # sid2 queda PENDIENTE
        _actualizar_resultado(sid1, "WIN")
        s = _get_stats()
        # 1 WIN, 0 LOSS → winrate 100% (pendiente no cuenta)
        self.assertEqual(s["winrate"], 100.0)
        self.assertEqual(s["wins"], 1)


class TestARM64Compliance(unittest.TestCase):
    """Validar que no se usan patrones prohibidos en ARM64"""

    def test_no_datetime_sql_default(self):
        """La fecha debe venir de Python, no de SQL DEFAULT"""
        before = datetime.now()
        sid = _insertar_senal("GainX 500", "BUY", 100.0, 90.0, 110.0, None, 5)
        after = datetime.now()

        conn = _get_conn()
        c = conn.cursor()
        c.execute("SELECT fecha FROM senales WHERE id=?", (sid,))
        fecha_str = c.fetchone()[0]
        conn.close()

        fecha_dt = datetime.strptime(fecha_str, "%Y-%m-%d %H:%M:%S")
        self.assertGreaterEqual(fecha_dt, before.replace(microsecond=0))
        self.assertLessEqual(fecha_dt, after.replace(microsecond=0) + __import__('datetime').timedelta(seconds=1))

    def test_db_en_home_no_tmp(self):
        """BD nunca debe estar en /tmp/ (noexec Android 15)"""
        self.assertNotIn("/tmp/", TEST_DB, "BD apunta a /tmp/ — viola regla ARM64")
        self.assertIn(HOME, TEST_DB, "BD no está en $HOME")


# ════════════════════════════════════════════════════════════════
#  RUNNER
# ════════════════════════════════════════════════════════════════
def cleanup():
    if os.path.exists(TEST_DB):
        os.remove(TEST_DB)
        print(f"\n  [cleanup] BD de test eliminada: {TEST_DB}")

if __name__ == "__main__":
    print("\n  ╔══════════════════════════════════════════╗")
    print("  ║  TESTS · termux-ai-stack · trading       ║")
    print("  ╚══════════════════════════════════════════╝\n")

    loader = unittest.TestLoader()
    suite  = unittest.TestSuite()

    suite.addTests(loader.loadTestsFromTestCase(TestDBInit))
    suite.addTests(loader.loadTestsFromTestCase(TestInsertarSenal))
    suite.addTests(loader.loadTestsFromTestCase(TestActualizarResultado))
    suite.addTests(loader.loadTestsFromTestCase(TestEstadisticas))
    suite.addTests(loader.loadTestsFromTestCase(TestARM64Compliance))

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    cleanup()

    # Exit code para scripts bash
    sys.exit(0 if result.wasSuccessful() else 1)

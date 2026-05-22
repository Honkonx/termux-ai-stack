#!/usr/bin/env python3
# ============================================================
#  termux-ai-stack · image_archive.py
#  Módulo de archivo de imágenes — nivel empresa
#
#  RESPONSABILIDADES:
#    - Recibir imagen (ruta o base64)
#    - Asignar UUID único
#    - Guardar en disco: ~/vision_archive/
#    - Registrar en SQLite: ~/image_archive.db
#    - Subir a nube (opcional): Cloudflare R2 o Google Drive
#    - Soft delete (nunca borrar físico del registro)
#
#  USO DESDE n8n (Execute Command):
#    python3 ~/image_archive.py store \
#      --file /ruta/imagen.jpg \
#      --chat_id 123456789 \
#      --fuente telegram
#
#    python3 ~/image_archive.py get --uuid "abc-123-..."
#    python3 ~/image_archive.py search --chat_id 123456789 --limit 10
#    python3 ~/image_archive.py delete --uuid "abc-123-..."
#
#  SALIDA: JSON por stdout — n8n captura y parsea
#
#  REGLAS ARM64:
#    - Sin DEFAULT (datetime('now')) en SQLite
#    - Sin import requests → urllib.request
#    - Archivos en $HOME (no /tmp)
#
#  VERSIÓN: 1.0.0 | Abril 2026
# ============================================================

import os
import sys
import json
import uuid
import sqlite3
import argparse
import base64
import shutil
from datetime import datetime
from urllib import request as ureq

# ── Rutas base ────────────────────────────────────────────────
HOME         = os.path.expanduser("~")
ARCHIVE_DIR  = os.path.join(HOME, "vision_archive")
DB_PATH      = os.path.join(HOME, "image_archive.db")
CONFIG_PATH  = os.path.join(HOME, ".image_archive_config")

# ── Config nube (vacío = desactivado) ─────────────────────────
# Editar ~/.image_archive_config para activar:
#
#   [r2]
#   enabled=true
#   account_id=TU_ACCOUNT_ID
#   bucket=TU_BUCKET
#   access_key=TU_KEY
#   secret_key=TU_SECRET
#   endpoint=https://TU_ACCOUNT_ID.r2.cloudflarestorage.com
#
#   [gdrive]
#   enabled=true
#   folder_id=TU_FOLDER_ID
#   token=TU_OAUTH_TOKEN
#
# Por ahora la nube está desactivada — la base funciona sin ella.

# ── Output helpers ────────────────────────────────────────────
def ok(data: dict):
    """Salida JSON exitosa — n8n captura stdout."""
    print(json.dumps({"status": "ok", **data}, ensure_ascii=False))
    sys.exit(0)

def fail(msg: str, code: int = 1):
    """Salida JSON error."""
    print(json.dumps({"status": "error", "message": msg}, ensure_ascii=False))
    sys.exit(code)

# ── Config loader ─────────────────────────────────────────────
def load_config() -> dict:
    """
    Lee ~/.image_archive_config en formato key=value por sección.
    Retorna dict plano: {'r2.enabled': 'true', 'gdrive.enabled': 'false', ...}
    """
    cfg = {}
    if not os.path.exists(CONFIG_PATH):
        return cfg
    current_section = ""
    try:
        with open(CONFIG_PATH) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    current_section = line[1:-1].lower()
                    continue
                if "=" in line and current_section:
                    k, _, v = line.partition("=")
                    cfg[f"{current_section}.{k.strip()}"] = v.strip()
    except Exception:
        pass
    return cfg

# ── SQLite ────────────────────────────────────────────────────
def get_conn() -> sqlite3.Connection:
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS imagenes (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid          TEXT    NOT NULL UNIQUE,
            chat_id       TEXT    NOT NULL,
            fuente        TEXT    NOT NULL,
            fecha         TEXT    NOT NULL,
            ruta_local    TEXT,
            url_nube      TEXT,
            id_nube       TEXT,
            proveedor     TEXT,
            tamano_bytes  INTEGER,
            mime_type     TEXT    DEFAULT 'image/jpeg',
            procesada     INTEGER DEFAULT 0,
            modelo_ia     TEXT,
            descripcion   TEXT,
            eliminada     INTEGER DEFAULT 0
        )
    """)
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_chat_id ON imagenes(chat_id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_fecha ON imagenes(fecha)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_uuid ON imagenes(uuid)"
    )
    conn.commit()
    return conn

# ── Utilidades de imagen ──────────────────────────────────────
def detectar_mime(ruta: str) -> str:
    """Detecta mime type por magic bytes (sin dependencias externas)."""
    try:
        with open(ruta, "rb") as f:
            header = f.read(12)
        if header[:3] == b'\xff\xd8\xff':
            return "image/jpeg"
        if header[:8] == b'\x89PNG\r\n\x1a\n':
            return "image/png"
        if header[:6] in (b'GIF87a', b'GIF89a'):
            return "image/gif"
        if header[:4] == b'RIFF' and header[8:12] == b'WEBP':
            return "image/webp"
    except Exception:
        pass
    return "image/jpeg"

def ext_desde_mime(mime: str) -> str:
    return {
        "image/jpeg": ".jpg",
        "image/png":  ".png",
        "image/gif":  ".gif",
        "image/webp": ".webp",
    }.get(mime, ".jpg")

def redimensionar_si_necesario(ruta: str, destino: str) -> str:
    """
    Redimensiona a máximo 1024px si Pillow está disponible y la imagen
    supera 1MB. Retorna ruta del archivo resultante.
    """
    try:
        from PIL import Image
        if os.path.getsize(ruta) <= 1_000_000:
            shutil.copy2(ruta, destino)
            return destino
        img = Image.open(ruta)
        w, h = img.size
        ratio = min(1024 / w, 1024 / h)
        if ratio < 1:
            img = img.resize((int(w * ratio), int(h * ratio)), Image.LANCZOS)
        img.save(destino, quality=85)
        return destino
    except ImportError:
        # Pillow no disponible — copiar sin redimensionar
        shutil.copy2(ruta, destino)
        return destino

# ── Nube: Cloudflare R2 ───────────────────────────────────────
def subir_r2(ruta_local: str, nombre_objeto: str, cfg: dict) -> dict:
    """
    Sube archivo a Cloudflare R2 via API S3-compatible.
    Retorna {'url': ..., 'id_nube': ..., 'proveedor': 'r2'} o lanza Exception.

    PENDIENTE: requiere boto3 (pip install boto3 --break-system-packages)
    Por ahora retorna estructura vacía para no bloquear el flujo base.
    """
    # TODO S9+: implementar con boto3 o urllib puro (S3 SigV4)
    # cfg keys: r2.account_id, r2.bucket, r2.access_key, r2.secret_key, r2.endpoint
    raise NotImplementedError(
        "R2: pendiente implementar. "
        "Instala boto3: pip install boto3 --break-system-packages"
    )

# ── Nube: Google Drive ────────────────────────────────────────
def subir_gdrive(ruta_local: str, nombre_archivo: str, cfg: dict) -> dict:
    """
    Sube archivo a Google Drive via API REST.
    Retorna {'url': ..., 'id_nube': ..., 'proveedor': 'gdrive'} o lanza Exception.

    PENDIENTE: requiere token OAuth2 configurado en ~/.image_archive_config
    Por ahora retorna estructura vacía para no bloquear el flujo base.
    """
    # TODO S9+: implementar upload multipart via urllib.request
    # cfg keys: gdrive.folder_id, gdrive.token
    raise NotImplementedError(
        "Google Drive: pendiente implementar. "
        "Configura token OAuth2 en ~/.image_archive_config"
    )

def intentar_subida_nube(ruta_local: str, img_uuid: str, cfg: dict) -> dict:
    """
    Intenta subir a la nube según config. Si falla o está desactivado,
    retorna dict vacío — el flujo principal NO se interrumpe.
    """
    resultado = {}

    # Cloudflare R2
    if cfg.get("r2.enabled", "false").lower() == "true":
        try:
            nombre = f"vision_archive/{img_uuid}{ext_desde_mime('image/jpeg')}"
            resultado = subir_r2(ruta_local, nombre, cfg)
        except NotImplementedError as e:
            resultado = {"nube_aviso": str(e)}
        except Exception as e:
            resultado = {"nube_error": f"R2: {str(e)}"}
        return resultado

    # Google Drive
    if cfg.get("gdrive.enabled", "false").lower() == "true":
        try:
            nombre = f"{img_uuid}.jpg"
            resultado = subir_gdrive(ruta_local, nombre, cfg)
        except NotImplementedError as e:
            resultado = {"nube_aviso": str(e)}
        except Exception as e:
            resultado = {"nube_error": f"Drive: {str(e)}"}
        return resultado

    return resultado

# ════════════════════════════════════════════════════════════
# COMANDOS
# ════════════════════════════════════════════════════════════

def cmd_store(args):
    """
    Guarda una imagen en el archivo.
    Entrada: --file RUTA o --base64 DATA
    """
    if not args.file and not args.base64_data:
        fail("Debes proveer --file o --base64")

    # Preparar imagen fuente
    tmp_path = os.path.join(HOME, f".img_archive_tmp_{os.getpid()}.jpg")

    if args.base64_data:
        try:
            data = base64.b64decode(args.base64_data)
            with open(tmp_path, "wb") as f:
                f.write(data)
            fuente_path = tmp_path
        except Exception as e:
            fail(f"Error decodificando base64: {e}")
    else:
        fuente_path = os.path.expanduser(args.file)
        if not os.path.exists(fuente_path):
            fail(f"Archivo no encontrado: {fuente_path}")

    try:
        # UUID + ruta destino
        img_uuid  = str(uuid.uuid4())
        mime      = detectar_mime(fuente_path)
        ext       = ext_desde_mime(mime)
        now       = datetime.now()
        fecha_str = now.strftime("%Y-%m-%d %H:%M:%S")

        # Carpeta por año/mes/día
        subdir = os.path.join(
            ARCHIVE_DIR,
            now.strftime("%Y"),
            now.strftime("%m"),
            now.strftime("%d")
        )
        os.makedirs(subdir, exist_ok=True)
        ruta_dest = os.path.join(subdir, f"{img_uuid}{ext}")

        # Copiar/redimensionar
        redimensionar_si_necesario(fuente_path, ruta_dest)
        tamano = os.path.getsize(ruta_dest)

        # Insertar en SQLite
        conn = get_conn()
        conn.execute("""
            INSERT INTO imagenes
              (uuid, chat_id, fuente, fecha, ruta_local, tamano_bytes, mime_type)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (
            img_uuid,
            str(args.chat_id),
            args.fuente,
            fecha_str,
            ruta_dest,
            tamano,
            mime
        ))
        conn.commit()

        # Intentar nube (no bloquea si falla)
        cfg  = load_config()
        nube = intentar_subida_nube(ruta_dest, img_uuid, cfg)

        if nube.get("url"):
            conn.execute("""
                UPDATE imagenes
                SET url_nube=?, id_nube=?, proveedor=?
                WHERE uuid=?
            """, (nube["url"], nube.get("id_nube"), nube.get("proveedor"), img_uuid))
            conn.commit()

        conn.close()

        # Limpiar tmp si vino de base64
        if args.base64_data and os.path.exists(tmp_path):
            os.remove(tmp_path)

        resultado = {
            "uuid":       img_uuid,
            "chat_id":    str(args.chat_id),
            "fecha":      fecha_str,
            "ruta_local": ruta_dest,
            "tamano":     tamano,
            "mime":       mime,
        }
        if nube:
            resultado["nube"] = nube

        ok(resultado)

    except Exception as e:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        fail(f"Error guardando imagen: {e}")


def cmd_update_descripcion(args):
    """Actualiza la descripción IA y modelo de una imagen ya guardada."""
    conn = get_conn()
    cur = conn.execute(
        "SELECT id FROM imagenes WHERE uuid=? AND eliminada=0",
        (args.uuid,)
    )
    if not cur.fetchone():
        conn.close()
        fail(f"UUID no encontrado: {args.uuid}")

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn.execute("""
        UPDATE imagenes
        SET descripcion=?, modelo_ia=?, procesada=1
        WHERE uuid=?
    """, (args.descripcion, args.modelo or "moondream:1.8b", args.uuid))
    conn.commit()
    conn.close()
    ok({"uuid": args.uuid, "updated": now})


def cmd_get(args):
    """Recupera metadatos de una imagen por UUID."""
    conn = get_conn()
    cur = conn.execute(
        "SELECT * FROM imagenes WHERE uuid=? AND eliminada=0",
        (args.uuid,)
    )
    row = cur.fetchone()
    conn.close()
    if not row:
        fail(f"UUID no encontrado o eliminado: {args.uuid}")
    ok(dict(row))


def cmd_search(args):
    """Busca imágenes por chat_id y/o rango de fechas."""
    conn  = get_conn()
    query = "SELECT * FROM imagenes WHERE eliminada=0"
    params = []

    if args.chat_id:
        query += " AND chat_id=?"
        params.append(str(args.chat_id))
    if args.desde:
        query += " AND fecha >= ?"
        params.append(args.desde)
    if args.hasta:
        query += " AND fecha <= ?"
        params.append(args.hasta)
    if args.fuente:
        query += " AND fuente=?"
        params.append(args.fuente)

    query += " ORDER BY fecha DESC LIMIT ?"
    params.append(args.limit or 20)

    rows = conn.execute(query, params).fetchall()
    conn.close()
    ok({"total": len(rows), "resultados": [dict(r) for r in rows]})


def cmd_delete(args):
    """Soft delete — marca eliminada=1, no borra físico ni de SQLite."""
    conn = get_conn()
    cur = conn.execute(
        "SELECT id, ruta_local FROM imagenes WHERE uuid=? AND eliminada=0",
        (args.uuid,)
    )
    row = cur.fetchone()
    if not row:
        conn.close()
        fail(f"UUID no encontrado o ya eliminado: {args.uuid}")

    conn.execute(
        "UPDATE imagenes SET eliminada=1 WHERE uuid=?",
        (args.uuid,)
    )
    conn.commit()
    conn.close()
    ok({"uuid": args.uuid, "eliminada": True, "nota": "Registro conservado en BD"})


def cmd_stats(args):
    """Estadísticas del archivo."""
    conn = get_conn()
    total    = conn.execute("SELECT COUNT(*) FROM imagenes WHERE eliminada=0").fetchone()[0]
    proc     = conn.execute("SELECT COUNT(*) FROM imagenes WHERE procesada=1 AND eliminada=0").fetchone()[0]
    tamano   = conn.execute("SELECT SUM(tamano_bytes) FROM imagenes WHERE eliminada=0").fetchone()[0] or 0
    en_nube  = conn.execute("SELECT COUNT(*) FROM imagenes WHERE url_nube IS NOT NULL AND eliminada=0").fetchone()[0]
    conn.close()
    ok({
        "total_imagenes":  total,
        "procesadas_ia":   proc,
        "en_nube":         en_nube,
        "tamano_total_mb": round(tamano / 1_000_000, 2)
    })

# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="image_archive.py — archivo de imágenes termux-ai-stack"
    )
    sub = parser.add_subparsers(dest="cmd")

    # store
    p_store = sub.add_parser("store", help="Guardar imagen en el archivo")
    p_store.add_argument("--file",       help="Ruta al archivo de imagen")
    p_store.add_argument("--base64",     dest="base64_data", help="Imagen en base64")
    p_store.add_argument("--chat_id",    required=True, help="ID del chat o usuario")
    p_store.add_argument("--fuente",     default="telegram",
                         choices=["telegram", "api", "manual"],
                         help="Origen de la imagen")

    # update-desc
    p_upd = sub.add_parser("update-desc", help="Actualizar descripción IA")
    p_upd.add_argument("--uuid",        required=True)
    p_upd.add_argument("--descripcion", required=True)
    p_upd.add_argument("--modelo",      default="moondream:1.8b")

    # get
    p_get = sub.add_parser("get", help="Obtener metadatos por UUID")
    p_get.add_argument("--uuid", required=True)

    # search
    p_srch = sub.add_parser("search", help="Buscar imágenes")
    p_srch.add_argument("--chat_id")
    p_srch.add_argument("--desde",  help="Fecha inicio YYYY-MM-DD HH:MM:SS")
    p_srch.add_argument("--hasta",  help="Fecha fin   YYYY-MM-DD HH:MM:SS")
    p_srch.add_argument("--fuente")
    p_srch.add_argument("--limit",  type=int, default=20)

    # delete
    p_del = sub.add_parser("delete", help="Soft delete por UUID")
    p_del.add_argument("--uuid", required=True)

    # stats
    sub.add_parser("stats", help="Estadísticas del archivo")

    args = parser.parse_args()

    if not args.cmd:
        parser.print_help()
        sys.exit(1)

    dispatch = {
        "store":       cmd_store,
        "update-desc": cmd_update_descripcion,
        "get":         cmd_get,
        "search":      cmd_search,
        "delete":      cmd_delete,
        "stats":       cmd_stats,
    }
    dispatch[args.cmd](args)

if __name__ == "__main__":
    main()

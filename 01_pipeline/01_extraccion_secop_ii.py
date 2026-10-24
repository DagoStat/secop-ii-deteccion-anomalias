"""
01_extraccion_secop_ii.py
=========================
Extractor incremental del conjunto SECOP II - Procesos de Contratacion
desde la API Socrata SODA 2.1 hacia SQL Server (SECOP_DWH).

Caracteristicas:
- Paginacion por offset
- Reintentos exponenciales con tenacity
- Checkpoint persistente en JSON
- Filtros por bloque anual (variables de entorno)
- Logging estructurado
- Conexion ODBC con fast_executemany y cifrado en transito
- Idempotente sobre la tabla espejo staging.secop_ii_procesos

Variables de entorno requeridas (definir en .env):
    SECOP_SOCRATA_DOMAIN     = www.datos.gov.co
    SECOP_DATASET_ID         = p6dx-8zbt
    SECOP_APP_TOKEN          = <token de Socrata>
    SECOP_SQL_DRIVER         = ODBC Driver 18 for SQL Server
    SECOP_SQL_SERVER         = LOCALHOST
    SECOP_SQL_DATABASE       = SECOP_DWH
    SECOP_BLOQUE_INICIO      = 2020-01-01T00:00:00
    SECOP_BLOQUE_FIN         = 2026-05-14T23:59:59
    SECOP_BLOQUE_NOMBRE      = corpus_completo
    SECOP_PAGE_SIZE          = 10000

Uso:
    python pipeline/01_extraccion_secop_ii.py
"""

import json
import logging
import os
import sys
from datetime import datetime
from pathlib import Path

import pandas as pd
import pyodbc
from dotenv import load_dotenv
from sodapy import Socrata
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------
load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent
LOG_DIR = BASE_DIR / "logs"
LOG_DIR.mkdir(exist_ok=True)
CHECKPOINT_PATH = BASE_DIR / "checkpoint_secop.json"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_DIR / "etl_secop.log", encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("secop-etl")

# ---------------------------------------------------------------------------
# Parametros del bloque a extraer
# ---------------------------------------------------------------------------
DATASET_ID = os.getenv("SECOP_DATASET_ID", "p6dx-8zbt")
SOCRATA_DOMAIN = os.getenv("SECOP_SOCRATA_DOMAIN", "www.datos.gov.co")
APP_TOKEN = os.getenv("SECOP_APP_TOKEN", None)
PAGE_SIZE = int(os.getenv("SECOP_PAGE_SIZE", "10000"))

BLOQUE_INICIO = os.getenv("SECOP_BLOQUE_INICIO", "2020-01-01T00:00:00")
BLOQUE_FIN = os.getenv("SECOP_BLOQUE_FIN", datetime.utcnow().isoformat())
BLOQUE_NOMBRE = os.getenv("SECOP_BLOQUE_NOMBRE", "default")

WHERE_CLAUSE = (
    f"fecha_de_publicacion_del between '{BLOQUE_INICIO}' and '{BLOQUE_FIN}'"
)


# ---------------------------------------------------------------------------
# Checkpoint
# ---------------------------------------------------------------------------
def cargar_checkpoint() -> dict:
    if not CHECKPOINT_PATH.exists():
        return {"bloques": {}}
    with open(CHECKPOINT_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def guardar_checkpoint(state: dict) -> None:
    with open(CHECKPOINT_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Cliente Socrata
# ---------------------------------------------------------------------------
def crear_cliente_socrata() -> Socrata:
    return Socrata(SOCRATA_DOMAIN, APP_TOKEN, timeout=120)


@retry(
    stop=stop_after_attempt(8),
    wait=wait_exponential(multiplier=2, min=4, max=60),
    retry=retry_if_exception_type((Exception,)),
    reraise=True,
)
def descargar_pagina(client: Socrata, offset: int) -> list:
    log.info("Descargando offset=%s limit=%s", offset, PAGE_SIZE)
    return client.get(
        DATASET_ID,
        where=WHERE_CLAUSE,
        order="fecha_de_publicacion_del ASC",
        limit=PAGE_SIZE,
        offset=offset,
    )


# ---------------------------------------------------------------------------
# Conexion SQL Server
# ---------------------------------------------------------------------------
def crear_conexion_sql() -> pyodbc.Connection:
    driver = os.getenv("SECOP_SQL_DRIVER", "ODBC Driver 18 for SQL Server")
    server = os.getenv("SECOP_SQL_SERVER", "LOCALHOST")
    database = os.getenv("SECOP_SQL_DATABASE", "SECOP_DWH")
    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};DATABASE={database};"
        f"Trusted_Connection=yes;"
        f"Encrypt=yes;TrustServerCertificate=yes;"
    )
    cnx = pyodbc.connect(conn_str, autocommit=False)
    cnx.cursor().fast_executemany = True
    return cnx


# ---------------------------------------------------------------------------
# Insercion en staging
# ---------------------------------------------------------------------------
COLS = [
    "id_del_proceso", "entidad", "nit_entidad",
    "nombre_del_proveedor", "nit_del_proveedor_adjudicado",
    "modalidad_de_contratacion", "justificacion_modalidad_de",
    "tipo_de_contrato", "estado_del_procedimiento",
    "precio_base", "valor_total_adjudicacion", "valor_contrato",
    "fecha_de_publicacion_del", "fecha_adjudicacion", "fecha_de_firma",
    "fecha_de_inicio_del_contrato", "fecha_de_fin_del_contrato",
    "conteo_de_respuestas_a_ofertas", "numero_de_oferentes_recibidos",
    "departamento_entidad", "ciudad_entidad",
    "sector", "rama",
]

INSERT_SQL = f"""
INSERT INTO staging.secop_ii_procesos
    ({", ".join(COLS)}, fecha_ingesta)
VALUES ({", ".join("?" for _ in COLS)}, SYSUTCDATETIME())
"""


def normalizar_fila(row: dict) -> tuple:
    """Normaliza una fila del API: tipado, trim, unicode."""

    def num(v):
        try:
            return float(v) if v not in (None, "", "NULL") else None
        except (ValueError, TypeError):
            return None

    def dt(v):
        if not v:
            return None
        try:
            return pd.to_datetime(v).to_pydatetime()
        except (ValueError, TypeError):
            return None

    def txt(v):
        if v is None:
            return None
        return str(v).strip()[:5000]

    return (
        txt(row.get("id_del_proceso")),
        txt(row.get("entidad")),
        txt(row.get("nit_entidad")),
        txt(row.get("nombre_del_proveedor")),
        txt(row.get("nit_del_proveedor_adjudicado")),
        txt(row.get("modalidad_de_contratacion")),
        txt(row.get("justificacion_modalidad_de")),
        txt(row.get("tipo_de_contrato")),
        txt(row.get("estado_del_procedimiento")),
        num(row.get("precio_base")),
        num(row.get("valor_total_adjudicacion")),
        num(row.get("valor_contrato")),
        dt(row.get("fecha_de_publicacion_del")),
        dt(row.get("fecha_adjudicacion")),
        dt(row.get("fecha_de_firma")),
        dt(row.get("fecha_de_inicio_del_contrato")),
        dt(row.get("fecha_de_fin_del_contrato")),
        num(row.get("conteo_de_respuestas_a_ofertas")),
        num(row.get("numero_de_oferentes_recibidos")),
        txt(row.get("departamento_entidad")),
        txt(row.get("ciudad_entidad")),
        txt(row.get("sector")),
        txt(row.get("rama")),
    )


def insertar_lote(cursor: pyodbc.Cursor, filas: list) -> None:
    if not filas:
        return
    cursor.executemany(INSERT_SQL, filas)


# ---------------------------------------------------------------------------
# Orquestador principal
# ---------------------------------------------------------------------------
def main() -> int:
    log.info("=" * 70)
    log.info("Iniciando extraccion SECOP II - bloque %s", BLOQUE_NOMBRE)
    log.info("Ventana: %s -> %s", BLOQUE_INICIO, BLOQUE_FIN)
    log.info("=" * 70)

    state = cargar_checkpoint()
    bloque_state = state["bloques"].get(BLOQUE_NOMBRE, {"offset": 0, "filas": 0})
    offset = bloque_state["offset"]
    total_filas = bloque_state["filas"]

    client = crear_cliente_socrata()
    cnx = crear_conexion_sql()
    cursor = cnx.cursor()

    try:
        while True:
            pagina = descargar_pagina(client, offset)
            if not pagina:
                log.info("Fin del bloque. Total filas procesadas: %s", total_filas)
                break

            filas = [normalizar_fila(r) for r in pagina]
            insertar_lote(cursor, filas)
            cnx.commit()

            offset += len(pagina)
            total_filas += len(pagina)

            state["bloques"][BLOQUE_NOMBRE] = {
                "offset": offset,
                "filas": total_filas,
                "ultima_actualizacion": datetime.utcnow().isoformat(),
            }
            guardar_checkpoint(state)

            log.info(
                "Pagina ok. offset=%s acumulado=%s ult_pub=%s",
                offset, total_filas,
                pagina[-1].get("fecha_de_publicacion_del", "?"),
            )

            if len(pagina) < PAGE_SIZE:
                log.info("Pagina parcial: fin del bloque.")
                break
    except KeyboardInterrupt:
        log.warning("Interrupcion manual. Checkpoint preservado.")
        return 130
    except Exception as e:
        log.exception("Error en el bloque: %s", e)
        return 1
    finally:
        cursor.close()
        cnx.close()
        client.close()

    log.info("Bloque %s completado: %s filas.", BLOQUE_NOMBRE, total_filas)
    return 0


if __name__ == "__main__":
    sys.exit(main())

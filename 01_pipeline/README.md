# 01_pipeline — Extracción Python desde el API SECOP II

Script ETL que consume el endpoint público `p6dx-8zbt` del portal Datos Abiertos del Gobierno de Colombia y persiste los registros en la tabla `staging.secop_ii_procesos` de SQL Server.

## Archivos

- `01_extraccion_secop_ii.py` — Script principal
- `requirements.txt` — Dependencias Python (sodapy, tenacity, pyodbc)

## Instalación

```cmd
cd 01_pipeline
pip install -r requirements.txt
```

## Ejecución

```cmd
python 01_extraccion_secop_ii.py
```

## Características técnicas

- **Paginación:** descarga en bloques de 50.000 registros para no saturar el endpoint.
- **Reintentos:** `tenacity` con backoff exponencial hasta 60 segundos por intento.
- **Checkpoint:** archivo JSON local que permite reanudar tras fallos.
- **Logging:** archivo `*.log` con timestamps y eventos.
- **Inserción por lotes:** `executemany` con `fast_executemany=True` para alto rendimiento.

## Tiempo esperado

30 a 60 minutos para descargar los 8.077.847 registros del período 2020-01-01 al 2026-05-21.

## Salida

Tabla `staging.secop_ii_procesos` con 22 columnas críticas + columna `fecha_ingesta` para trazabilidad técnica (linaje hacia la fuente).

## Configuración

El script lee de un archivo `.env` opcional o de variables de entorno:

```
SQL_SERVER=localhost
SQL_DATABASE=SECOP_DWH
SECOP_APP_TOKEN=<opcional, para rate limit mayor>
```

Si no hay token, el script funciona con el rate limit anónimo del API (más lento pero suficiente).

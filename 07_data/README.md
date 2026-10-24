# 07_data — Carpeta de datos (vacía intencionalmente)

Los datos NO se incluyen en este repositorio. Esta carpeta existe para que el script de extracción Python tenga un destino opcional para checkpoints o exportes locales.

## Por qué no incluimos los datos

| Razón | Detalle |
|---|---|
| Tamaño | El backup `.bak` de la base completa pesa 5,26 GB comprimidos (27,83 GB descomprimidos). Excede el límite de GitHub (50 MB por archivo, 2 GB recomendado por repositorio) |
| Reproducibilidad | Los datos son públicos y se descargan automáticamente desde el API SECOP II |
| Trazabilidad | Cada ejecución del pipeline genera una versión fresca con `fecha_ingesta` actualizada |
| Tamaños de versión | El dato cambia diariamente; congelar una versión sería arbitrario |

## Cómo obtener los datos

### Opción A — Re-ejecutar el pipeline (recomendado)

```cmd
cd ..\01_pipeline
python 01_extraccion_secop_ii.py
```

Tiempo: 30-60 minutos. Resultado: tabla `staging.secop_ii_procesos` con ~8,08 millones de registros del API público.

### Opción B — Restaurar un backup `.bak` privado

Si recibiste un archivo `.bak` por canal privado (Google Drive, OneDrive, etc.), colócalo en esta carpeta como `07_data/SECOP_DWH_VF_v16_2.bak` y restaura con:

```sql
USE master; GO

ALTER DATABASE SECOP_DWH SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

RESTORE DATABASE SECOP_DWH
FROM DISK = N'C:\SECOP_II_VF_v16_2\07_data\SECOP_DWH_VF_v16_2.bak'
WITH REPLACE, RECOVERY, STATS = 10, CHECKSUM;

ALTER DATABASE SECOP_DWH SET MULTI_USER;
```

Tiempo: 5-10 minutos según disco.

## Estructura esperada después de cargar los datos

```
SECOP_DWH (base de datos)/
├── staging.secop_ii_procesos    ← 8.077.847 registros crudos
├── dwh.fact_contratacion        ← 7.734.679 procesos atribuibles
├── dwh.dim_entidad              ← 11.348 entidades
├── dwh.dim_proveedor            ← 30.013 proveedores
├── dwh.dim_modalidad            ← 17 modalidades
├── dwh.dim_tiempo               ← 4.748 días (2020-2026)
├── ind.alertas_proceso          ← 43.570 alertas
├── ind.riesgo_corrupcion        ← 39.951 procesos con alerta
├── meta.calidad_dimensiones     ← 21 métricas
├── meta.backups                 ← bitácora de respaldos
└── pbi.agg_* (5 tablas)         ← pre-agregaciones para Power BI
```

## Diccionario de datos del API SECOP II

Endpoint público: <https://www.datos.gov.co/resource/p6dx-8zbt.json>

El proyecto carga 22 columnas críticas de las 59 disponibles. El detalle completo está en el documento de tesis (`04_documento/VF_documento_final_V16_2.docx`, anexo del diccionario de datos).

Documentación oficial del dataset: <https://datos.gov.co/Gastos-Gubernamentales/SECOP-II-Procesos-de-Contrataci-n/p6dx-8zbt>

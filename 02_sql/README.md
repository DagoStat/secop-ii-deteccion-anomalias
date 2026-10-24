# 02_sql — Scripts SQL en orden de ejecución

Estos scripts construyen el data warehouse `SECOP_DWH`, aplican los 7 indicadores red flag V16.2, calculan el índice de riesgo, miden la calidad de datos DAMA-DMBOK 2 y aplican los controles de seguridad operativa.

## Orden de ejecución obligatorio

| # | Script | Propósito | Tiempo |
|---:|---|---|---:|
| 00 | `00_diagnostico_estructura.sql` | (Opcional) Verifica nombres de columnas en `INFORMATION_SCHEMA` | <5 s |
| 01 | `01_crear_schemas.sql` | Crea los 5 schemas: staging, dwh, ind, pbi, meta | <5 s |
| 02 | `02_crear_dimensiones_y_fact.sql` | Crea fact + dimensiones + índices | 10 s |
| 03 | `03_cargar_staging_a_dwh.sql` | Carga deduplicada staging → dwh | 5-10 min |
| **04** | **`04_indicadores_v16_2.sql`** | **Crea las 7 vistas red flag V16.2** | 5-15 min |
| 05 | `05_materializar_alertas_y_riesgo.sql` | Materializa alertas + calcula índice 0-17 | 5-15 min |
| 06 | `06_crear_agregaciones_powerbi.sql` | Pre-agrega 5 tablas `pbi.agg_*` para latencia <2s | 2-5 min |
| 07 | `07_calidad_dama_dmbok.sql` | 21 métricas sobre 7 dimensiones DAMA | 5-10 min |
| 08 | `08_backup_y_gobierno.sql` | Backup `.bak` + RESTORE VERIFYONLY | 1-2 min |
| 09 | `09_seguridad_rls_ddm.sql` | RLS + DDM + 3 roles + 22 columnas clasificadas | 1 min |
| 09b | `09b_seguridad_pruebas.sql` | Validación del comportamiento por rol | <1 min |
| 10 | `10_detalle_4_alto.sql` | Inspección de los 4 procesos ALTO V16.2 | <10 s |
| 11 | `11_validacion_convergente.sql` | Cruce con 20 casos públicos conocidos | 1-3 min |

## Ejecución desde SSMS

Abrir cada script con **File → Open → File** y ejecutar con **F5**. Alternativamente, ejecutar todos en cascada desde una nueva query:

```sql
USE SECOP_DWH; GO

:r "C:\SECOP_II_VF_v16_2\02_sql\01_crear_schemas.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\02_crear_dimensiones_y_fact.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\03_cargar_staging_a_dwh.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\04_indicadores_v16_2.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\05_materializar_alertas_y_riesgo.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\06_crear_agregaciones_powerbi.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\07_calidad_dama_dmbok.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\08_backup_y_gobierno.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\09_seguridad_rls_ddm.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\09b_seguridad_pruebas.sql"
```

## Núcleo analítico — Script 04

El script `04_indicadores_v16_2.sql` es el corazón del sistema. Define 7 vistas SQL declarativas que materializan los siete indicadores red flag finales:

| Vista | Detecta | Peso |
|---|---|:---:|
| `vw_anom_001_sobrecosto` | `valor_adjudicado / precio_base > 1,5` | 3 |
| `vw_anom_002_share_monetario` | Share por entidad-año ≥ 50 % | 3 |
| `vw_anom_003_unico_oferente` | `n_oferentes = 1` en modalidad competitiva | 3 |
| `vw_anom_005_persistencia` | 3 años consecutivos, deduplicado a 1/par-año | 2 |
| `vw_anom_007_tiempo_atipico` | \|z-score log(días)\| ≥ 3 por modalidad-año | 2 |
| `vw_anom_008_ultracorto_alto` | días ≤ P10 global Y valor ≥ P90 global | 2 |
| `vw_anom_009_fragmentacion_umbral` | ≥ 5 contratos en P95-P99 modalidad | 2 |

Suma máxima del índice = **17 puntos**.

## Escala del índice (script 05)

```
SIN RIESGO = 0
BAJO       = 1 - 3
MEDIO      = 4 - 9
ALTO       ≥ 10
```

## Verificación al terminar

```sql
SELECT codigo_anomalia, COUNT_BIG(*) AS alertas
FROM ind.alertas_proceso GROUP BY codigo_anomalia ORDER BY codigo_anomalia;
-- ANOM-001=732 | 002=11900 | 003=1515 | 005=17872 | 007=2610 | 008=7919 | 009=1022

SELECT nivel_riesgo, COUNT_BIG(*) FROM ind.riesgo_corrupcion GROUP BY nivel_riesgo;
-- BAJO=36572 | MEDIO=3375 | ALTO=4
```

## Compatibilidad sin GO

Algunos clientes SQL (Azure Data Studio, sqlcmd sin `-i`, ciertas extensiones de VS Code) no interpretan `GO` como separador de batch. Si encuentras el error `Incorrect syntax near 'GO'`, los scripts 09 y 09b deben ejecutarse en SSMS abriendo el archivo y presionando F5 (SSMS interpreta `GO` correctamente).

# Guía de replicación end-to-end — SECOP II V16.2

Esta guía permite a evaluadores, auditores o ciudadanos reproducir completamente la solución analítica desde cero. **Tiempo total estimado: 3 a 4 horas.**

---

## Paso 0 — Pre-requisitos (60 minutos)

### Software a instalar

1. **Microsoft SQL Server 2022 Express o Developer** (gratuito): <https://www.microsoft.com/sql-server>
   - Durante la instalación, activar autenticación Windows (modo recomendado).
   - Anotar el nombre de la instancia (típicamente `localhost` o `localhost\SQLEXPRESS`).
2. **SQL Server Management Studio (SSMS) 19+**: <https://aka.ms/ssms>
3. **Python 3.10+**: <https://www.python.org/downloads>
   - Durante la instalación, marcar la casilla **"Add Python to PATH"**.
4. **Power BI Desktop 2026** (gratuito): <https://www.microsoft.com/power-bi>

### Verificación

```cmd
python --version            # debe imprimir Python 3.10.x o superior
sqlcmd -? 2>nul             # SSMS instalado
```

Probar conexión SQL Server desde SSMS: abrir SSMS → conectar a `localhost` con autenticación Windows.

### Recursos del equipo

| Recurso | Mínimo | Recomendado |
|---|---:|---:|
| Disco libre | 30 GB | 50 GB |
| RAM | 16 GB | 32 GB |
| Sistema operativo | Windows 10 | Windows 11 |

---

## Paso 1 — Descargar este paquete (1 minuto)

Si recibiste el paquete por correo / Drive / OneDrive:
- Descomprimir el ZIP en una carpeta de fácil acceso, por ejemplo `C:\SECOP_II_VF_v16_2\`.

Si está en repositorio Git:
```cmd
git clone https://github.com/<usuario>/SECOP_II_VF_v16_2.git
cd SECOP_II_VF_v16_2
```

---

## Paso 2 — Crear la base de datos vacía (2 minutos)

Abrir SSMS, conectar a `localhost`, ejecutar:

```sql
CREATE DATABASE SECOP_DWH;
GO

-- Verificar que la base existe
USE SECOP_DWH;
SELECT DB_NAME() AS bd_actual;
```

---

## Paso 3 — Crear los schemas y tablas (5 minutos)

En SSMS, abrir y ejecutar **en orden**:

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\01_crear_schemas.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\02_crear_dimensiones_y_fact.sql"
```

Verificación:

```sql
SELECT s.name AS schema_name, COUNT(*) AS tablas
FROM sys.schemas s
LEFT JOIN sys.tables t ON t.schema_id = s.schema_id
WHERE s.name IN ('staging', 'dwh', 'ind', 'pbi', 'meta')
GROUP BY s.name
ORDER BY s.name;
```

Debe mostrar los 5 schemas creados.

---

## Paso 4 — Extraer datos del API SECOP II (30 a 60 minutos)

En CMD o PowerShell:

```cmd
cd C:\SECOP_II_VF_v16_2\01_pipeline
pip install -r requirements.txt
python 01_extraccion_secop_ii.py
```

Esto descarga aproximadamente **8.077.847 registros** del endpoint público Socrata `p6dx-8zbt` y los carga en `staging.secop_ii_procesos`. El proceso muestra progreso por consola y guarda un checkpoint cada 50.000 registros para reanudación tras fallos.

Verificación al terminar:

```sql
SELECT COUNT_BIG(*) AS registros, MAX(fecha_ingesta) AS ultima_ingesta
FROM staging.secop_ii_procesos;
-- Esperado: ~8.077.847 registros, fecha_ingesta de hoy
```

---

## Paso 5 — Cargar el modelo dimensional (5 a 10 minutos)

En SSMS:

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\03_cargar_staging_a_dwh.sql"
```

Este script aplica deduplicación por `ROW_NUMBER() OVER (PARTITION BY id_del_proceso ORDER BY fecha_ingesta DESC)`, normaliza catálogos en `dim_entidad`, `dim_proveedor`, `dim_modalidad`, `dim_tiempo`, y consolida la `fact_contratacion` con FK enforced. Tiempo: 5 a 10 minutos sobre el corpus completo.

Verificación:

```sql
SELECT 'staging'    AS tabla, COUNT_BIG(*) FROM staging.secop_ii_procesos
UNION ALL SELECT 'fact',     COUNT_BIG(*) FROM dwh.fact_contratacion
UNION ALL SELECT 'entidad',  COUNT_BIG(*) FROM dwh.dim_entidad
UNION ALL SELECT 'proveedor',COUNT_BIG(*) FROM dwh.dim_proveedor
UNION ALL SELECT 'modalidad',COUNT_BIG(*) FROM dwh.dim_modalidad
UNION ALL SELECT 'tiempo',   COUNT_BIG(*) FROM dwh.dim_tiempo;

-- Esperado aprox:
-- staging:   8.077.847
-- fact:      7.734.679
-- entidad:   11.348
-- proveedor: 30.013
-- modalidad: 17
-- tiempo:    4.748
```

---

## Paso 6 — Aplicar los siete indicadores V16.2 (5 a 15 minutos)

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\04_indicadores_v16_2.sql"
```

Este es el corazón analítico. Crea siete vistas SQL declarativas en el schema `ind`:

| Vista | Detecta | Peso |
|---|---|:---:|
| `vw_anom_001_sobrecosto` | `valor_adjudicado / precio_base > 1,5` | 3 |
| `vw_anom_002_share_monetario` | Share del proveedor en el valor total de la entidad por año ≥ 50 % | 3 |
| `vw_anom_003_unico_oferente` | `n_oferentes = 1` en modalidad competitiva | 3 |
| `vw_anom_005_persistencia` | Mismo proveedor adjudicado 3 años consecutivos (deduplicado a 1 alerta por par-año) | 2 |
| `vw_anom_007_tiempo_atipico` | z-score logarítmico de días pub→adj con \|z\| ≥ 3 dentro de modalidad-año | 2 |
| `vw_anom_008_ultracorto_alto` | Días ≤ percentil 10 global AND valor ≥ percentil 90 global | 2 |
| `vw_anom_009_fragmentacion_umbral` | ≥ 5 contratos del par con valor en P95-P99 de su modalidad | 2 |

**Suma máxima del índice = 17 puntos.**

---

## Paso 7 — Materializar alertas y calcular el índice (5 a 15 minutos)

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\05_materializar_alertas_y_riesgo.sql"
```

Pobla `ind.alertas_proceso` (43.570 alertas) y `ind.riesgo_corrupcion` (39.951 procesos con clasificación SIN RIESGO / BAJO 1-3 / MEDIO 4-9 / ALTO ≥10).

Verificación:

```sql
SELECT codigo_anomalia, COUNT_BIG(*) AS alertas
FROM ind.alertas_proceso GROUP BY codigo_anomalia ORDER BY codigo_anomalia;

SELECT nivel_riesgo, COUNT_BIG(*) AS procesos
FROM ind.riesgo_corrupcion GROUP BY nivel_riesgo;
```

Las cifras deben coincidir con la tabla de referencia del README.md.

---

## Paso 8 — Pre-agregaciones para Power BI (2 a 5 minutos)

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\06_crear_agregaciones_powerbi.sql"
```

Crea cinco tablas `pbi.agg_*` con reducción de ~144× para latencia menor a 2 segundos en el dashboard.

---

## Paso 9 — Métricas de calidad DAMA-DMBOK (5 a 10 minutos)

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\07_calidad_dama_dmbok.sql"
```

Aplica 21 métricas formales sobre las 7 dimensiones DAMA-DMBOK 2 (Completitud, Unicidad, Validez, Consistencia, Conformidad, Oportunidad, Trazabilidad) y registra los resultados en `meta.calidad_dimensiones`. Resultado esperado: 18/21 cumplen objetivo (85,71 %).

---

## Paso 10 — Backup verificado (1 a 2 minutos)

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\08_backup_y_gobierno.sql"
```

Genera el archivo `.bak` en `C:\Backups\` (ajustar la ruta dentro del script si tu disco es otro), aplica `RESTORE VERIFYONLY` y registra el evento en `meta.backups`.

---

## Paso 11 — Seguridad operativa (RLS + DDM) (1 minuto)

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\09_seguridad_rls_ddm.sql"
:r "C:\SECOP_II_VF_v16_2\02_sql\09b_seguridad_pruebas.sql"
```

Crea tres roles operativos (`rol_auditor`, `rol_analista_publico`, `rol_ciudadano`), aplica Dynamic Data Masking sobre 5 columnas sensibles y Row-Level Security sobre `ind.riesgo_corrupcion` filtrando por nivel de riesgo según rol. El script `09b` valida el comportamiento con usuarios de prueba.

---

## Paso 12 — Investigación de los 4 procesos ALTO (1 minuto)

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\10_detalle_4_alto.sql"
```

Inspección quirúrgica de los cuatro procesos clasificados como ALTO: entidad, proveedor, modalidad, anomalías activas, URL pública SECOP II para verificación directa.

(Opcional) Validación convergente con casos públicos conocidos:

```sql
:r "C:\SECOP_II_VF_v16_2\02_sql\11_validacion_convergente.sql"
```

Cruza el índice con 20 patrones de búsqueda de casos públicos (Centros Poblados MinTIC, PAE, Reficar, Hidroituango, DPS COVID, etc.).

---

## Paso 13 — Construir el dashboard Power BI (30 a 45 minutos)

Seguir la guía detallada en `03_powerbi/GUIA_POWERBI.md`:

1. Abrir Power BI Desktop 2026.
2. **Get data → SQL Server** → `localhost` / `SECOP_DWH`.
3. Importar las 5 tablas `pbi.agg_*`.
4. Crear tabla calculada `Anios = GENERATESERIES(2020, 2026, 1)`.
5. Crear las 21 medidas DAX documentadas en `GUIA_POWERBI.md`.
6. Construir las 4 páginas: Vista General, Por Modalidad, Mapa de Colombia, Top Proveedores.
7. **File → Save as** → `03_powerbi/SECOP_V16_Dashboard.pbix`.

---

## Paso 14 — Verificación final (5 minutos)

Comparar las cifras de tu dashboard con las del README.md:

| Página del dashboard | Debe mostrar |
|---|---|
| Vista General | 7,73 M / 39.951 con alerta / 4 ALTO |
| Por Modalidad | Contratación Directa entre los 3 con mayor % MEDIO+ALTO |
| Mapa | Antioquia, Norte de Santander, Santander, Bogotá D.C. con presencia ALTO |
| Top Proveedores | IDFES Santander, RYAN, ESP Guatapé, ESE Hospital Centro como Top 4 con ALTO |

Si todo coincide, has replicado exitosamente la solución.

---

## Troubleshooting

| Síntoma | Causa probable | Solución |
|---|---|---|
| `pip install` falla con error de SSL | Certificado expirado | Reinstalar Python o agregar `--trusted-host pypi.org` |
| Python no encuentra `pyodbc` | Driver SQL Server no instalado | Instalar **ODBC Driver 18 for SQL Server** desde Microsoft |
| El script Python termina sin descargar todo | Timeout en API SECOP II | Re-ejecutar, el checkpoint reanuda desde donde quedó |
| Cifra `fact_contratacion` ≠ 7.734.679 | Datos del API cambiaron desde la fecha de corte | Es normal si re-ejecutas en otra fecha; las cifras serán equivalentes pero distintas |
| Cifra `riesgo_corrupcion ALTO` ≠ 4 | El umbral debe ser ≥ 10, no ≥ 12 | Verificar que el script 05 tiene los umbrales V16.2 BAJO 1-3 / MEDIO 4-9 / ALTO ≥10 |
| `Cannot DROP TABLE 'ind.riesgo_corrupcion' because it is being referenced` | Política RLS activa | El script 05 maneja esto automáticamente; si persiste, ejecutar manualmente `ALTER SECURITY POLICY sec.pol_riesgo_por_rol WITH (STATE = OFF); DROP SECURITY POLICY sec.pol_riesgo_por_rol;` antes |
| Power BI Refresh falla con "No se puede conectar" | SQL Server detenido | `Services.msc → SQL Server (MSSQLSERVER) → Start` |

---

## Tiempo total estimado

| Etapa | Tiempo |
|---|---:|
| Pre-requisitos (instalación una sola vez) | 60 min |
| Pasos 1-2: descargar paquete + crear BD | 3 min |
| Paso 3: crear schemas y tablas | 5 min |
| Paso 4: extracción Python desde API | 30-60 min |
| Pasos 5-12: SQL en cascada | 30-60 min |
| Paso 13: construir dashboard Power BI | 30-45 min |
| Paso 14: verificación | 5 min |
| **Total end-to-end** | **3-4 horas** |

Si solo necesitas verificar el dashboard sin re-ejecutar el pipeline (porque ya tienes la base de datos cargada), el tiempo se reduce a **30-45 minutos**.

---

## Recursos adicionales

- Documento de tesis completo: `04_documento/Moyano-2026-trabajo-de-grado-SECOP-II.docx`
- Presentación de defensa: `05_presentacion/Moyano-2026-sustentacion-SECOP-II.pptx`
- Diagrama de arquitectura: `06_diagramas/arquitectura.md`
- Modelo entidad-relación: `06_diagramas/er_modelo_v16_2.md`

Para preguntas o reportes: `jmoyano119@uan.edu.co`.

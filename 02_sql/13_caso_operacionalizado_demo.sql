-- ============================================================================
-- 13_caso_operacionalizado_demo.sql
-- Demostración en vivo de un caso particular operacionalizado por el sistema.
-- Ideal para mostrar en sustentación: un único proceso (CO1.REQ.10248186 - FNE/RYAN)
-- recorrido desde la regla SQL hasta el puntaje compuesto y los controles RLS+DDM.
--
-- El usuario puede cambiar el @id_proceso al inicio del script para examinar
-- cualquier otro caso de la base. Los cuatro IDs de los procesos ALTO V16.2 son:
--   CO1.REQ.7819109   Municipio de Guatape
--   CO1.REQ.5954983   IDS Norte de Santander
--   CO1.REQ.7967249   Departamento de Santander
--   CO1.REQ.10248186  UAE Fondo Nacional de Estupefacientes (RYAN)
--
-- Tiempo de ejecución: <5 segundos. Ejecutar como rol_auditor para ver sin máscara.
-- ============================================================================
USE SECOP_DWH;
SET NOCOUNT ON;

-- ----------------------------------------------------------------------
-- CASO A INSPECCIONAR (cambiar aquí para ver otro proceso)
-- ----------------------------------------------------------------------
DECLARE @id_proceso NVARCHAR(200) = 'CO1.REQ.10248186';

PRINT '======================================';
PRINT 'CASO OPERACIONALIZADO: ' + @id_proceso;
PRINT 'Inicio: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';

-- ----------------------------------------------------------------------
-- BLOQUE 1: FICHA COMPLETA del proceso
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- BLOQUE 1: FICHA DEL PROCESO ---';

SELECT
    r.id_proceso,
    e.nit                                       AS nit_entidad,
    e.nombre                                    AS entidad,
    e.orden                                     AS orden_entidad,
    e.departamento                              AS depto_entidad,
    p.documento                                 AS nit_proveedor,
    p.nombre                                    AS proveedor,
    m.nombre                                    AS modalidad,
    m.es_competitiva,
    tp.fecha                                    AS fecha_publicacion,
    ta.fecha                                    AS fecha_adjudicacion,
    DATEDIFF(DAY, tp.fecha, ta.fecha)           AS dias_pub_adj,
    f.precio_base,
    f.valor_adjudicado,
    CAST(f.valor_adjudicado * 1.0 /
         NULLIF(f.precio_base, 0) AS DECIMAL(8,3)) AS ratio_sobrecosto,
    f.n_oferentes,
    f.estado,
    r.puntos_totales                            AS puntos,
    r.nivel_riesgo
FROM    ind.riesgo_corrupcion r
JOIN    dwh.fact_contratacion f ON f.id_proceso = r.id_proceso
JOIN    dwh.dim_entidad   e ON e.sk_entidad   = r.sk_entidad
LEFT JOIN dwh.dim_proveedor p ON p.sk_proveedor = r.sk_proveedor
JOIN    dwh.dim_modalidad m ON m.sk_modalidad = r.sk_modalidad
LEFT JOIN dwh.dim_tiempo tp ON tp.sk_tiempo = r.sk_t_publicacion
LEFT JOIN dwh.dim_tiempo ta ON ta.sk_tiempo = r.sk_t_adjudicacion
WHERE   r.id_proceso = @id_proceso;

-- ----------------------------------------------------------------------
-- BLOQUE 2: REGLAS QUE SE DISPARARON sobre este proceso
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- BLOQUE 2: REGLAS DISPARADAS (cuáles ANOM se activaron) ---';

SELECT
    ap.codigo_anomalia,
    ap.puntos,
    ap.descripcion,
    'vw_anom_' +
        CASE ap.codigo_anomalia
            WHEN 'ANOM-001' THEN '001_sobrecosto'
            WHEN 'ANOM-002' THEN '002_share_monetario'
            WHEN 'ANOM-003' THEN '003_unico_oferente'
            WHEN 'ANOM-005' THEN '005_persistencia'
            WHEN 'ANOM-007' THEN '007_tiempo_atipico'
            WHEN 'ANOM-008' THEN '008_ultracorto_alto'
            WHEN 'ANOM-009' THEN '009_fragmentacion_umbral'
        END                                     AS vista_sql_de_origen
FROM    ind.alertas_proceso ap
WHERE   ap.id_proceso = @id_proceso
ORDER BY ap.codigo_anomalia;

-- ----------------------------------------------------------------------
-- BLOQUE 3: OPERACIONALIZACIÓN CONCRETA de cada regla disparada
-- Muestra los números reales que activaron cada indicador
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- BLOQUE 3: NÚMEROS QUE ACTIVARON CADA REGLA ---';

-- ANOM-001 Sobrecosto: ratio > 1.5
SELECT
    'ANOM-001 Sobrecosto'                       AS indicador,
    'valor_adjudicado / precio_base > 1.5'      AS regla,
    f.precio_base                               AS precio_base,
    f.valor_adjudicado                          AS valor_adjudicado,
    CAST(f.valor_adjudicado * 1.0 /
         NULLIF(f.precio_base, 0) AS DECIMAL(8,3)) AS ratio_calculado,
    CASE WHEN f.precio_base > 0 AND f.valor_adjudicado > f.precio_base * 1.5
         THEN 'DISPARA (ratio supera 1.5)'
         ELSE 'NO dispara' END                  AS estado
FROM dwh.fact_contratacion f
WHERE f.id_proceso = @id_proceso;

-- ANOM-002 Share monetario: monto_proveedor / monto_entidad-año >= 0.50
WITH montos AS (
    SELECT f.sk_entidad, f.sk_proveedor, t.anio,
           SUM(CAST(f.valor_adjudicado AS DECIMAL(18,2))) AS monto_par
    FROM dwh.fact_contratacion f
    JOIN dwh.dim_tiempo t ON t.sk_tiempo = f.sk_t_publicacion
    WHERE f.sk_proveedor IS NOT NULL AND f.valor_adjudicado > 0
    GROUP BY f.sk_entidad, f.sk_proveedor, t.anio
),
totales AS (
    SELECT sk_entidad, anio, SUM(monto_par) AS monto_total
    FROM montos GROUP BY sk_entidad, anio
),
proceso AS (
    SELECT f.sk_entidad, f.sk_proveedor, t.anio
    FROM dwh.fact_contratacion f
    JOIN dwh.dim_tiempo t ON t.sk_tiempo = f.sk_t_publicacion
    WHERE f.id_proceso = @id_proceso
)
SELECT
    'ANOM-002 Share monetario'                  AS indicador,
    'monto_proveedor / monto_entidad-año >= 50%' AS regla,
    pr.anio,
    m.monto_par                                 AS monto_proveedor_entidad_anio,
    t.monto_total                               AS monto_total_entidad_anio,
    CAST(100.0 * m.monto_par / NULLIF(t.monto_total, 0) AS DECIMAL(6,2)) AS share_pct,
    CASE WHEN m.monto_par * 1.0 / NULLIF(t.monto_total, 0) >= 0.50
         THEN 'DISPARA (share >= 50%)'
         ELSE 'NO dispara' END                  AS estado
FROM proceso pr
JOIN montos m  ON m.sk_entidad = pr.sk_entidad AND m.sk_proveedor = pr.sk_proveedor AND m.anio = pr.anio
JOIN totales t ON t.sk_entidad = pr.sk_entidad AND t.anio = pr.anio;

-- ANOM-003 Único oferente en competitiva
SELECT
    'ANOM-003 Único oferente'                   AS indicador,
    'n_oferentes = 1 AND es_competitiva = 1'    AS regla,
    f.n_oferentes,
    m.nombre                                    AS modalidad,
    m.es_competitiva,
    CASE WHEN f.n_oferentes = 1 AND m.es_competitiva = 1
         THEN 'DISPARA (1 oferente en competitiva)'
         ELSE 'NO dispara' END                  AS estado
FROM dwh.fact_contratacion f
JOIN dwh.dim_modalidad m ON m.sk_modalidad = f.sk_modalidad
WHERE f.id_proceso = @id_proceso;

-- ANOM-005 Persistencia: par entidad-proveedor 3 años consecutivos
WITH proceso AS (
    SELECT sk_entidad, sk_proveedor FROM dwh.fact_contratacion
    WHERE id_proceso = @id_proceso
),
adjudicaciones AS (
    SELECT DISTINCT f.sk_entidad, f.sk_proveedor, t.anio
    FROM dwh.fact_contratacion f
    JOIN dwh.dim_tiempo t ON t.sk_tiempo = f.sk_t_publicacion
    JOIN proceso pr ON pr.sk_entidad = f.sk_entidad AND pr.sk_proveedor = f.sk_proveedor
    WHERE f.valor_adjudicado > 0
)
SELECT
    'ANOM-005 Persistencia'                     AS indicador,
    '3 años consecutivos del par'               AS regla,
    STRING_AGG(CAST(anio AS VARCHAR), ', ') WITHIN GROUP (ORDER BY anio) AS anios_con_adjudicacion,
    COUNT(*)                                    AS n_anios_distintos,
    CASE WHEN COUNT(*) >= 3
              AND MAX(anio) - MIN(anio) >= 2
         THEN 'DISPARA (par persistente)'
         ELSE 'NO dispara' END                  AS estado
FROM adjudicaciones;

-- ANOM-007 Tiempo atípico
WITH proceso AS (
    SELECT f.sk_modalidad,
           LOG(DATEDIFF(DAY, tp.fecha, ta.fecha) + 1.0) AS log_dias_proc,
           t.anio
    FROM dwh.fact_contratacion f
    JOIN dwh.dim_tiempo tp ON tp.sk_tiempo = f.sk_t_publicacion
    JOIN dwh.dim_tiempo ta ON ta.sk_tiempo = f.sk_t_adjudicacion
    JOIN dwh.dim_tiempo t  ON t.sk_tiempo  = f.sk_t_publicacion
    WHERE f.id_proceso = @id_proceso
),
stats AS (
    SELECT f.sk_modalidad, t.anio,
           AVG(LOG(DATEDIFF(DAY, tp.fecha, ta.fecha) + 1.0))   AS mu,
           STDEV(LOG(DATEDIFF(DAY, tp.fecha, ta.fecha) + 1.0)) AS sd,
           COUNT(*)                                            AS n
    FROM dwh.fact_contratacion f
    JOIN dwh.dim_tiempo tp ON tp.sk_tiempo = f.sk_t_publicacion
    JOIN dwh.dim_tiempo ta ON ta.sk_tiempo = f.sk_t_adjudicacion
    JOIN dwh.dim_tiempo t  ON t.sk_tiempo  = f.sk_t_publicacion
    WHERE DATEDIFF(DAY, tp.fecha, ta.fecha) >= 0
    GROUP BY f.sk_modalidad, t.anio
    HAVING STDEV(LOG(DATEDIFF(DAY, tp.fecha, ta.fecha) + 1.0)) > 0 AND COUNT(*) >= 30
)
SELECT
    'ANOM-007 Tiempo atípico'                   AS indicador,
    '|z-score log(días+1)| >= 3 por modalidad-año' AS regla,
    pr.anio,
    CAST(pr.log_dias_proc AS DECIMAL(8,4))      AS log_dias_de_este_proceso,
    CAST(s.mu AS DECIMAL(8,4))                  AS mu_modalidad_anio,
    CAST(s.sd AS DECIMAL(8,4))                  AS sd_modalidad_anio,
    CAST((pr.log_dias_proc - s.mu) / NULLIF(s.sd, 0) AS DECIMAL(8,4)) AS z_calculado,
    s.n                                         AS n_procesos_grupo,
    CASE WHEN ABS((pr.log_dias_proc - s.mu) / NULLIF(s.sd, 0)) >= 3.0
         THEN 'DISPARA (|z| >= 3)'
         ELSE 'NO dispara' END                  AS estado
FROM proceso pr
JOIN stats s ON s.sk_modalidad = pr.sk_modalidad AND s.anio = pr.anio;

-- ANOM-008 Ultracorto + valor alto
DECLARE @p10 INT, @p90 DECIMAL(18,2);

SELECT TOP 1
    @p10 = CAST(PERCENTILE_CONT(0.10) WITHIN GROUP (
        ORDER BY DATEDIFF(DAY, tp.fecha, ta.fecha)) OVER () AS INT),
    @p90 = PERCENTILE_CONT(0.90) WITHIN GROUP (
        ORDER BY f.valor_adjudicado) OVER ()
FROM dwh.fact_contratacion f
JOIN dwh.dim_tiempo tp ON tp.sk_tiempo = f.sk_t_publicacion
JOIN dwh.dim_tiempo ta ON ta.sk_tiempo = f.sk_t_adjudicacion
WHERE f.valor_adjudicado > 0 AND DATEDIFF(DAY, tp.fecha, ta.fecha) >= 0;

SELECT
    'ANOM-008 Ultracorto + valor alto'          AS indicador,
    'días <= P10 global Y valor >= P90 global'  AS regla,
    DATEDIFF(DAY, tp.fecha, ta.fecha)           AS dias_este_proceso,
    @p10                                         AS p10_dias_global,
    f.valor_adjudicado                          AS valor_este_proceso,
    @p90                                         AS p90_valor_global,
    CASE WHEN DATEDIFF(DAY, tp.fecha, ta.fecha) <= @p10
              AND f.valor_adjudicado >= @p90
         THEN 'DISPARA (ultracorto Y valor alto)'
         ELSE 'NO dispara' END                  AS estado
FROM dwh.fact_contratacion f
JOIN dwh.dim_tiempo tp ON tp.sk_tiempo = f.sk_t_publicacion
JOIN dwh.dim_tiempo ta ON ta.sk_tiempo = f.sk_t_adjudicacion
WHERE f.id_proceso = @id_proceso;

-- ANOM-009 Fragmentación P95-P99 modalidad
DECLARE @p95 DECIMAL(18,2), @p99 DECIMAL(18,2);

SELECT TOP 1
    @p95 = PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY valor_adjudicado)
        OVER (PARTITION BY f.sk_modalidad),
    @p99 = PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY valor_adjudicado)
        OVER (PARTITION BY f.sk_modalidad)
FROM dwh.fact_contratacion f
WHERE f.sk_modalidad = (
    SELECT sk_modalidad FROM dwh.fact_contratacion WHERE id_proceso = @id_proceso
) AND f.valor_adjudicado > 0;

WITH proceso AS (
    SELECT sk_entidad, sk_proveedor, sk_modalidad
    FROM dwh.fact_contratacion WHERE id_proceso = @id_proceso
),
contratos_par_en_p95_p99 AS (
    SELECT COUNT_BIG(*) AS n_proximos_umbral
    FROM dwh.fact_contratacion f
    JOIN proceso pr ON pr.sk_entidad = f.sk_entidad AND pr.sk_proveedor = f.sk_proveedor
    WHERE f.valor_adjudicado BETWEEN @p95 AND @p99
)
SELECT
    'ANOM-009 Fragmentación umbral'             AS indicador,
    '>= 5 contratos del par en P95-P99 de modalidad' AS regla,
    @p95                                         AS p95_valor_modalidad,
    @p99                                         AS p99_valor_modalidad,
    cp.n_proximos_umbral                        AS contratos_del_par_en_franja,
    CASE WHEN cp.n_proximos_umbral >= 5
         THEN 'DISPARA (par tiene 5+ contratos en franja)'
         ELSE 'NO dispara' END                  AS estado
FROM contratos_par_en_p95_p99 cp;

-- ----------------------------------------------------------------------
-- BLOQUE 4: COMO LO VEN LOS TRES ROLES (DDM + RLS en acción)
-- Requiere haber ejecutado el script 09 y 09b previamente
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- BLOQUE 4: VISTAS POR ROL (DDM + RLS) ---';

PRINT '';
PRINT '[ Como rol_auditor (UNMASK + ve todos los niveles) ]';
EXECUTE AS USER = 'test_auditor';
SELECT
    r.id_proceso, r.nivel_riesgo, r.puntos_totales,
    e.nombre AS entidad, p.documento AS nit_prov, p.nombre AS proveedor
FROM ind.riesgo_corrupcion r
JOIN dwh.dim_entidad e ON e.sk_entidad = r.sk_entidad
LEFT JOIN dwh.dim_proveedor p ON p.sk_proveedor = r.sk_proveedor
WHERE r.id_proceso = @id_proceso;
REVERT;

PRINT '';
PRINT '[ Como rol_analista_publico (sin UNMASK, hasta MEDIO) ]';
EXECUTE AS USER = 'test_analista_publico';
SELECT
    r.id_proceso, r.nivel_riesgo, r.puntos_totales,
    e.nombre AS entidad, p.documento AS nit_prov, p.nombre AS proveedor
FROM ind.riesgo_corrupcion r
JOIN dwh.dim_entidad e ON e.sk_entidad = r.sk_entidad
LEFT JOIN dwh.dim_proveedor p ON p.sk_proveedor = r.sk_proveedor
WHERE r.id_proceso = @id_proceso;
-- Si el caso es ALTO, no devuelve filas (RLS lo bloquea).
-- Si es MEDIO o BAJO, devuelve la fila pero con NIT y nombre enmascarados.
REVERT;

PRINT '';
PRINT '[ Como rol_ciudadano (sin UNMASK, solo SIN RIESGO y BAJO) ]';
EXECUTE AS USER = 'test_ciudadano';
SELECT
    r.id_proceso, r.nivel_riesgo, r.puntos_totales,
    e.nombre AS entidad, p.documento AS nit_prov, p.nombre AS proveedor
FROM ind.riesgo_corrupcion r
JOIN dwh.dim_entidad e ON e.sk_entidad = r.sk_entidad
LEFT JOIN dwh.dim_proveedor p ON p.sk_proveedor = r.sk_proveedor
WHERE r.id_proceso = @id_proceso;
-- Si el caso es MEDIO o ALTO, no devuelve filas (RLS lo bloquea).
REVERT;

-- ----------------------------------------------------------------------
-- BLOQUE 5: TEXTO PUBLICO Y URL DEL PROCESO en SECOP II para verificación
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- BLOQUE 5: TEXTO PÚBLICO Y URL DE VERIFICACIÓN ---';

SELECT TOP 1
    s.entidad,
    s.modalidad_de_contratacion,
    s.tipo_de_contrato,
    LEFT(s.nombre_del_procedimiento, 250)       AS nombre_procedimiento,
    LEFT(s.descripci_n_del_procedimiento, 500)  AS descripcion,
    s.codigo_principal_de_categoria             AS unspsc,
    s.estado_del_procedimiento                  AS estado,
    s.urlproceso                                AS url_secop_ii
FROM staging.secop_ii_procesos s
WHERE s.id_del_proceso = @id_proceso;

PRINT '';
PRINT '======================================';
PRINT 'CASO OPERACIONALIZADO COMPLETO';
PRINT 'Fin: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';

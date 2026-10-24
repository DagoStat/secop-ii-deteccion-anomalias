-- ============================================================================
-- 04c_v16_2_definitivo.sql   |   Version V16.2 final (sin GO, portable)
--
-- Aplica las dos decisiones tras el diagnostico empirico de V16.1:
--
--   1) ANOM-005 (Persistencia) DEDUPLICADA por par-anio:
--      en lugar de marcar TODOS los procesos del par persistente
--      (que generaba 88% de las alertas), marca SOLO UN proceso
--      representativo por (entidad, proveedor, anio) - el de mayor valor.
--      Esto reduce el ruido sin perder la senal estructural.
--
--   2) ANOM-006 (z_oferentes) ELIMINADO DEFINITIVAMENTE:
--      la fuente API SECOP II reporta 0 oferentes en el 99,15% de los
--      procesos competitivos, lo que hace inviable el calculo de z-score.
--      Queda documentado como limitacion de fuente y recomendacion formal
--      a Colombia Compra Eficiente.
--
-- Resultado:
--   - 7 indicadores activos: ANOM-001, 002, 003, 005, 007, 008, 009
--   - Suma maxima = 3+3+3+2+2+2+2 = 17 puntos
--   - Umbrales: SIN RIESGO=0 | BAJO 1-3 | MEDIO 4-9 | ALTO >=10
--
-- Tiempo estimado: 8-15 minutos.
-- ============================================================================
USE SECOP_DWH;

SET NOCOUNT ON;

PRINT '======================================';
PRINT 'V16.2 DEFINITIVO (7 indicadores, sin ANOM-004 ni ANOM-006)';
PRINT 'Inicio: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';

-- ----------------------------------------------------------------------
-- (1) Desactivar SECURITY POLICY
-- ----------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'pol_riesgo_por_rol')
BEGIN
    EXEC sp_executesql N'ALTER SECURITY POLICY sec.pol_riesgo_por_rol WITH (STATE = OFF)';
    EXEC sp_executesql N'DROP SECURITY POLICY sec.pol_riesgo_por_rol';
    PRINT '[1] SECURITY POLICY desactivada';
END

IF OBJECT_ID('sec.fn_filtro_riesgo', 'IF') IS NOT NULL
    EXEC sp_executesql N'DROP FUNCTION sec.fn_filtro_riesgo';

-- ----------------------------------------------------------------------
-- (2) DROP de TODAS las vistas previas
-- ----------------------------------------------------------------------
DECLARE @drop NVARCHAR(MAX) = '';
SELECT @drop = @drop + 'DROP VIEW ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + '; '
FROM sys.views
WHERE schema_id = SCHEMA_ID('ind')
  AND (name LIKE 'vw_anom_%' OR name LIKE 'vw_alertas_%');
IF LEN(@drop) > 0
BEGIN
    EXEC sp_executesql @drop;
    PRINT '[2] Vistas viejas eliminadas';
END

-- ----------------------------------------------------------------------
-- (3) CREATE 7 vistas V16.2 (sin ANOM-004 ni ANOM-006)
-- ----------------------------------------------------------------------

-- ANOM-001: Sobrecosto > 50%
EXEC sp_executesql N'
CREATE VIEW ind.vw_anom_001_sobrecosto AS
SELECT  f.id_proceso, f.sk_entidad, f.sk_proveedor, f.sk_modalidad,
        f.sk_t_publicacion, f.sk_t_adjudicacion,
        ''ANOM-001'' AS codigo_anomalia, 3 AS puntos,
        ''Sobrecosto: valor_adjudicado / precio_base > 1.5 (sobrecosto > 50%)'' AS descripcion
FROM    dwh.fact_contratacion f
WHERE   f.precio_base > 0 AND f.valor_adjudicado IS NOT NULL
  AND   f.valor_adjudicado > f.precio_base * 1.5;
';
PRINT '[3.1] ANOM-001 sobrecosto';

-- ANOM-002: Share monetario >= 50% por entidad-anio
EXEC sp_executesql N'
CREATE VIEW ind.vw_anom_002_share_monetario AS
WITH base AS (
    SELECT f.sk_entidad, f.sk_proveedor, t.anio,
           SUM(CAST(f.valor_adjudicado AS DECIMAL(18,2))) AS monto_proveedor
    FROM   dwh.fact_contratacion f
    JOIN   dwh.dim_tiempo t ON t.sk_tiempo = f.sk_t_publicacion
    WHERE  f.sk_proveedor IS NOT NULL AND f.valor_adjudicado > 0
    GROUP BY f.sk_entidad, f.sk_proveedor, t.anio
),
totales AS (
    SELECT sk_entidad, anio, SUM(monto_proveedor) AS monto_total
    FROM   base GROUP BY sk_entidad, anio
),
marcados AS (
    SELECT b.sk_entidad, b.sk_proveedor, b.anio
    FROM   base b JOIN totales t ON t.sk_entidad = b.sk_entidad AND t.anio = b.anio
    WHERE  b.monto_proveedor / NULLIF(t.monto_total, 0) >= 0.50
)
SELECT  f.id_proceso, f.sk_entidad, f.sk_proveedor, f.sk_modalidad,
        f.sk_t_publicacion, f.sk_t_adjudicacion,
        ''ANOM-002'' AS codigo_anomalia, 3 AS puntos,
        ''Share monetario >= 50% por entidad-anio'' AS descripcion
FROM    dwh.fact_contratacion f
JOIN    dwh.dim_tiempo t ON t.sk_tiempo = f.sk_t_publicacion
JOIN    marcados m ON m.sk_entidad = f.sk_entidad AND m.sk_proveedor = f.sk_proveedor AND m.anio = t.anio;
';
PRINT '[3.2] ANOM-002 share monetario';

-- ANOM-003: Unico oferente en modalidad competitiva
EXEC sp_executesql N'
CREATE VIEW ind.vw_anom_003_unico_oferente AS
SELECT  f.id_proceso, f.sk_entidad, f.sk_proveedor, f.sk_modalidad,
        f.sk_t_publicacion, f.sk_t_adjudicacion,
        ''ANOM-003'' AS codigo_anomalia, 3 AS puntos,
        ''Unico oferente en modalidad competitiva'' AS descripcion
FROM    dwh.fact_contratacion f
JOIN    dwh.dim_modalidad m ON m.sk_modalidad = f.sk_modalidad
WHERE   f.n_oferentes = 1 AND m.es_competitiva = 1;
';
PRINT '[3.3] ANOM-003 unico oferente';

-- ANOM-005 DEDUPLICADA: 1 proceso representativo por par-anio persistente
EXEC sp_executesql N'
CREATE VIEW ind.vw_anom_005_persistencia AS
WITH adjudicaciones AS (
    SELECT DISTINCT f.sk_entidad, f.sk_proveedor, t.anio
    FROM   dwh.fact_contratacion f
    JOIN   dwh.dim_tiempo t ON t.sk_tiempo = f.sk_t_publicacion
    WHERE  f.sk_proveedor IS NOT NULL AND f.valor_adjudicado > 0
),
con_lag AS (
    SELECT sk_entidad, sk_proveedor, anio,
           LAG(anio,1) OVER (PARTITION BY sk_entidad, sk_proveedor ORDER BY anio) AS anio_prev1,
           LAG(anio,2) OVER (PARTITION BY sk_entidad, sk_proveedor ORDER BY anio) AS anio_prev2
    FROM   adjudicaciones
),
pares_anios_persistentes AS (
    -- (sk_entidad, sk_proveedor, anio) donde el anio cierra una secuencia de 3 consecutivos
    SELECT sk_entidad, sk_proveedor, anio
    FROM   con_lag
    WHERE  anio - anio_prev1 = 1 AND anio_prev1 - anio_prev2 = 1
),
representante_por_par_anio AS (
    -- Para cada par-anio persistente, escoge UN proceso representativo (mayor valor)
    SELECT f.id_proceso, f.sk_entidad, f.sk_proveedor, f.sk_modalidad,
           f.sk_t_publicacion, f.sk_t_adjudicacion, t.anio,
           ROW_NUMBER() OVER (
               PARTITION BY f.sk_entidad, f.sk_proveedor, t.anio
               ORDER BY f.valor_adjudicado DESC, f.id_proceso
           ) AS rn
    FROM dwh.fact_contratacion f
    JOIN dwh.dim_tiempo t ON t.sk_tiempo = f.sk_t_publicacion
    JOIN pares_anios_persistentes pap
         ON pap.sk_entidad = f.sk_entidad
        AND pap.sk_proveedor = f.sk_proveedor
        AND pap.anio = t.anio
)
SELECT  id_proceso, sk_entidad, sk_proveedor, sk_modalidad,
        sk_t_publicacion, sk_t_adjudicacion,
        ''ANOM-005'' AS codigo_anomalia, 2 AS puntos,
        ''Persistencia: par entidad-proveedor con adjudicaciones en 3 anios consecutivos (proceso representativo del anio)'' AS descripcion
FROM    representante_por_par_anio
WHERE   rn = 1;
';
PRINT '[3.5] ANOM-005 persistencia DEDUPLICADA (1 proceso/par-anio)';

-- ANOM-007: Z-score logaritmico tiempo
EXEC sp_executesql N'
CREATE VIEW ind.vw_anom_007_tiempo_atipico AS
WITH base AS (
    SELECT f.id_proceso, f.sk_entidad, f.sk_proveedor, f.sk_modalidad,
           f.sk_t_publicacion, f.sk_t_adjudicacion,
           LOG(DATEDIFF(DAY, tp.fecha, ta.fecha) + 1.0) AS log_dias, t.anio
    FROM   dwh.fact_contratacion f
    JOIN   dwh.dim_tiempo tp ON tp.sk_tiempo = f.sk_t_publicacion
    JOIN   dwh.dim_tiempo ta ON ta.sk_tiempo = f.sk_t_adjudicacion
    JOIN   dwh.dim_tiempo t  ON t.sk_tiempo  = f.sk_t_publicacion
    WHERE  DATEDIFF(DAY, tp.fecha, ta.fecha) >= 0
),
stats AS (
    SELECT sk_modalidad, anio, AVG(log_dias) AS mu, STDEV(log_dias) AS sd, COUNT(*) AS n
    FROM   base
    GROUP BY sk_modalidad, anio
    HAVING STDEV(log_dias) > 0 AND COUNT(*) >= 30
)
SELECT  b.id_proceso, b.sk_entidad, b.sk_proveedor, b.sk_modalidad,
        b.sk_t_publicacion, b.sk_t_adjudicacion,
        ''ANOM-007'' AS codigo_anomalia, 2 AS puntos,
        ''Tiempo atipico: |z-score log(dias)| >= 3 dentro de modalidad-anio'' AS descripcion
FROM    base b
JOIN    stats s ON s.sk_modalidad = b.sk_modalidad AND s.anio = b.anio
WHERE   ABS((b.log_dias - s.mu) / s.sd) >= 3.0;
';
PRINT '[3.7] ANOM-007 tiempo atipico';

-- ANOM-008: Ultracorto + valor alto
EXEC sp_executesql N'
CREATE VIEW ind.vw_anom_008_ultracorto_alto AS
WITH datos AS (
    SELECT f.id_proceso, f.sk_entidad, f.sk_proveedor, f.sk_modalidad,
           f.sk_t_publicacion, f.sk_t_adjudicacion,
           DATEDIFF(DAY, tp.fecha, ta.fecha) AS dias, f.valor_adjudicado
    FROM   dwh.fact_contratacion f
    JOIN   dwh.dim_tiempo tp ON tp.sk_tiempo = f.sk_t_publicacion
    JOIN   dwh.dim_tiempo ta ON ta.sk_tiempo = f.sk_t_adjudicacion
    WHERE  f.valor_adjudicado > 0 AND DATEDIFF(DAY, tp.fecha, ta.fecha) >= 0
),
percentiles AS (
    SELECT TOP 1
        PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY dias) OVER () AS p10_dias,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY valor_adjudicado) OVER () AS p90_valor
    FROM datos
)
SELECT  d.id_proceso, d.sk_entidad, d.sk_proveedor, d.sk_modalidad,
        d.sk_t_publicacion, d.sk_t_adjudicacion,
        ''ANOM-008'' AS codigo_anomalia, 2 AS puntos,
        ''Ultracorto + valor alto (dias <= P10 global y valor >= P90 global)'' AS descripcion
FROM    datos d
CROSS JOIN percentiles p
WHERE   d.dias <= p.p10_dias AND d.valor_adjudicado >= p.p90_valor;
';
PRINT '[3.8] ANOM-008 ultracorto + valor alto';

-- ANOM-009: Fragmentacion proxima al umbral regulatorio
EXEC sp_executesql N'
CREATE VIEW ind.vw_anom_009_fragmentacion_umbral AS
WITH datos AS (
    SELECT f.id_proceso, f.sk_entidad, f.sk_proveedor, f.sk_modalidad,
           f.sk_t_publicacion, f.sk_t_adjudicacion, f.valor_adjudicado
    FROM   dwh.fact_contratacion f
    WHERE  f.sk_proveedor IS NOT NULL AND f.valor_adjudicado > 0
),
percentiles_mod AS (
    SELECT DISTINCT sk_modalidad,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY valor_adjudicado) OVER (PARTITION BY sk_modalidad) AS p95,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY valor_adjudicado) OVER (PARTITION BY sk_modalidad) AS p99
    FROM datos
),
candidatos AS (
    SELECT d.id_proceso, d.sk_entidad, d.sk_proveedor, d.sk_modalidad,
           d.sk_t_publicacion, d.sk_t_adjudicacion
    FROM   datos d
    JOIN   percentiles_mod p ON p.sk_modalidad = d.sk_modalidad
    WHERE  d.valor_adjudicado BETWEEN p.p95 AND p.p99
),
con_count AS (
    SELECT sk_entidad, sk_proveedor, COUNT_BIG(*) AS n
    FROM   candidatos
    GROUP BY sk_entidad, sk_proveedor
    HAVING COUNT_BIG(*) >= 5
)
SELECT  c.id_proceso, c.sk_entidad, c.sk_proveedor, c.sk_modalidad,
        c.sk_t_publicacion, c.sk_t_adjudicacion,
        ''ANOM-009'' AS codigo_anomalia, 2 AS puntos,
        ''Fragmentacion: >=5 contratos persistentes en P95-P99 del valor de su modalidad'' AS descripcion
FROM    candidatos c
JOIN    con_count cc ON cc.sk_entidad = c.sk_entidad AND cc.sk_proveedor = c.sk_proveedor;
';
PRINT '[3.9] ANOM-009 fragmentacion';

-- Union de las 7 vistas
EXEC sp_executesql N'
CREATE VIEW ind.vw_alertas_todas AS
SELECT * FROM ind.vw_anom_001_sobrecosto
UNION ALL SELECT * FROM ind.vw_anom_002_share_monetario
UNION ALL SELECT * FROM ind.vw_anom_003_unico_oferente
UNION ALL SELECT * FROM ind.vw_anom_005_persistencia
UNION ALL SELECT * FROM ind.vw_anom_007_tiempo_atipico
UNION ALL SELECT * FROM ind.vw_anom_008_ultracorto_alto
UNION ALL SELECT * FROM ind.vw_anom_009_fragmentacion_umbral;
';
PRINT '[3.10] vw_alertas_todas (7 indicadores)';

-- ----------------------------------------------------------------------
-- (4) Limpiar tablas
-- ----------------------------------------------------------------------
DELETE FROM ind.riesgo_corrupcion;
DBCC CHECKIDENT('ind.riesgo_corrupcion', RESEED, 0) WITH NO_INFOMSGS;
TRUNCATE TABLE ind.alertas_proceso;
PRINT '[4] Tablas vaciadas';

-- ----------------------------------------------------------------------
-- (5) Repoblar alertas_proceso
-- ----------------------------------------------------------------------
DECLARE @t1 DATETIME2 = SYSDATETIME();
PRINT '[5] Poblando alertas_proceso desde 7 vistas...';

INSERT INTO ind.alertas_proceso
    (id_proceso, sk_entidad, sk_proveedor, sk_modalidad,
     sk_t_publicacion, sk_t_adjudicacion,
     codigo_anomalia, puntos, descripcion)
SELECT  id_proceso, sk_entidad, sk_proveedor, sk_modalidad,
        sk_t_publicacion, sk_t_adjudicacion,
        codigo_anomalia, puntos, descripcion
FROM    ind.vw_alertas_todas;

PRINT '[5] alertas_proceso: ' + CAST(@@ROWCOUNT AS VARCHAR)
    + ' alertas en ' + CAST(DATEDIFF(SECOND, @t1, SYSDATETIME()) AS VARCHAR) + ' seg';

-- ----------------------------------------------------------------------
-- (6) Recalcular riesgo_corrupcion con UMBRALES V16.2:
--     SIN RIESGO=0 | BAJO 1-3 | MEDIO 4-9 | ALTO >=10  (escala 0-17)
-- ----------------------------------------------------------------------
DECLARE @t2 DATETIME2 = SYSDATETIME();
PRINT '[6] Calculando riesgo_corrupcion (escala 0-17)...';

INSERT INTO ind.riesgo_corrupcion
    (id_proceso, sk_entidad, sk_proveedor, sk_modalidad,
     sk_t_publicacion, sk_t_adjudicacion,
     n_alertas, puntos_totales, nivel_riesgo)
SELECT  id_proceso,
        MAX(sk_entidad), MAX(sk_proveedor), MAX(sk_modalidad),
        MAX(sk_t_publicacion), MAX(sk_t_adjudicacion),
        COUNT(*) AS n_alertas,
        SUM(puntos) AS puntos_totales,
        CASE
            WHEN SUM(puntos) = 0                THEN 'SIN RIESGO'
            WHEN SUM(puntos) BETWEEN 1 AND 3    THEN 'BAJO'
            WHEN SUM(puntos) BETWEEN 4 AND 9    THEN 'MEDIO'
            WHEN SUM(puntos) >= 10              THEN 'ALTO'
        END
FROM    ind.alertas_proceso
GROUP BY id_proceso;

PRINT '[6] riesgo_corrupcion: ' + CAST(@@ROWCOUNT AS VARCHAR)
    + ' procesos en ' + CAST(DATEDIFF(SECOND, @t2, SYSDATETIME()) AS VARCHAR) + ' seg';

-- ----------------------------------------------------------------------
-- (7) Recrear SECURITY POLICY
-- ----------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'sec')
    EXEC('CREATE SCHEMA sec AUTHORIZATION dbo');

EXEC sp_executesql N'
CREATE FUNCTION sec.fn_filtro_riesgo(@nivel_riesgo VARCHAR(20))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS fn_securitypredicate_result
    WHERE
        IS_MEMBER(''db_owner'') = 1
        OR IS_ROLEMEMBER(''rol_auditor'') = 1
        OR (IS_ROLEMEMBER(''rol_analista_publico'') = 1 AND @nivel_riesgo IN (''SIN RIESGO'',''BAJO'',''MEDIO''))
        OR (IS_ROLEMEMBER(''rol_ciudadano'') = 1 AND @nivel_riesgo IN (''SIN RIESGO'',''BAJO''));
';

EXEC sp_executesql N'
CREATE SECURITY POLICY sec.pol_riesgo_por_rol
ADD FILTER PREDICATE sec.fn_filtro_riesgo(nivel_riesgo) ON ind.riesgo_corrupcion
WITH (STATE = ON);
';

PRINT '[7] SECURITY POLICY recreada y activa';

-- ----------------------------------------------------------------------
-- (8) Verificacion final
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (8a) Conteo de alertas por indicador V16.2 ---';
SELECT  codigo_anomalia,
        COUNT_BIG(*) AS alertas,
        CAST(100.0 * COUNT_BIG(*) /
             SUM(COUNT_BIG(*)) OVER() AS DECIMAL(5,2)) AS pct
FROM    ind.alertas_proceso
GROUP BY codigo_anomalia
ORDER BY codigo_anomalia;

PRINT '';
PRINT '--- (8b) Distribucion por nivel de riesgo ---';
SELECT  nivel_riesgo,
        COUNT_BIG(*) AS procesos,
        CAST(100.0 * COUNT_BIG(*) /
             SUM(COUNT_BIG(*)) OVER() AS DECIMAL(5,2)) AS pct
FROM    ind.riesgo_corrupcion
GROUP BY nivel_riesgo
ORDER BY CASE nivel_riesgo
            WHEN 'SIN RIESGO' THEN 0
            WHEN 'BAJO'       THEN 1
            WHEN 'MEDIO'      THEN 2
            WHEN 'ALTO'       THEN 3
         END;

PRINT '';
PRINT '--- (8c) Distribucion detallada de puntos totales ---';
SELECT  puntos_totales, COUNT_BIG(*) AS procesos
FROM    ind.riesgo_corrupcion
GROUP BY puntos_totales
ORDER BY puntos_totales;

PRINT '';
PRINT '--- (8d) Top 20 entidades MEDIO + ALTO ---';
SELECT TOP 20
        e.nombre AS entidad, e.departamento,
        SUM(CASE WHEN r.nivel_riesgo = 'ALTO'  THEN 1 ELSE 0 END) AS alto,
        SUM(CASE WHEN r.nivel_riesgo = 'MEDIO' THEN 1 ELSE 0 END) AS medio,
        AVG(CAST(r.puntos_totales AS DECIMAL(5,2)))               AS prom_pts
FROM    ind.riesgo_corrupcion r
JOIN    dwh.dim_entidad e ON e.sk_entidad = r.sk_entidad
WHERE   r.nivel_riesgo IN ('MEDIO','ALTO')
GROUP BY e.nombre, e.departamento
ORDER BY alto DESC, medio DESC, prom_pts DESC;

PRINT '';
PRINT '======================================';
PRINT 'V16.2 DEFINITIVO COMPLETADO';
PRINT '7 indicadores activos. Suma maxima: 17 puntos';
PRINT 'Escala: SIN RIESGO=0 | BAJO 1-3 | MEDIO 4-9 | ALTO >=10';
PRINT 'Fin: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';

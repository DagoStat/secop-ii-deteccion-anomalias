-- ============================================================================
-- 06_crear_agregaciones_powerbi.sql
-- Pre-calcula 5 tablas agregadas para Power BI con factor de compresion ~144x.
-- Permite latencia <2s en visualizaciones interactivas.
--
-- Tablas creadas en schema pbi:
--   pbi.agg_riesgo_x_modalidad_anio   (~120 filas)
--   pbi.agg_riesgo_x_entidad_anio     (~80k filas)
--   pbi.agg_riesgo_x_departamento_anio (~240 filas)
--   pbi.agg_alertas_x_indicador_anio  (~56 filas)
--   pbi.agg_top_proveedores_riesgo    (~5k filas)
--
-- Tiempo: 2-5 minutos
-- ============================================================================
USE SECOP_DWH;
GO

SET NOCOUNT ON;

PRINT '======================================';
PRINT 'AGREGACIONES POWER BI';
PRINT 'Inicio: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';
GO

-- Drop tablas previas
IF OBJECT_ID('pbi.agg_riesgo_x_modalidad_anio',    'U') IS NOT NULL DROP TABLE pbi.agg_riesgo_x_modalidad_anio;
IF OBJECT_ID('pbi.agg_riesgo_x_entidad_anio',      'U') IS NOT NULL DROP TABLE pbi.agg_riesgo_x_entidad_anio;
IF OBJECT_ID('pbi.agg_riesgo_x_departamento_anio', 'U') IS NOT NULL DROP TABLE pbi.agg_riesgo_x_departamento_anio;
IF OBJECT_ID('pbi.agg_alertas_x_indicador_anio',   'U') IS NOT NULL DROP TABLE pbi.agg_alertas_x_indicador_anio;
IF OBJECT_ID('pbi.agg_top_proveedores_riesgo',     'U') IS NOT NULL DROP TABLE pbi.agg_top_proveedores_riesgo;
GO

-- ----------------------------------------------------------------------
-- (1) Por modalidad x ano
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();

SELECT  m.nombre AS modalidad, m.es_competitiva, t.anio,
        COUNT_BIG(*) AS total_procesos,
        COUNT_BIG(r.id_proceso) AS procesos_con_alerta,
        SUM(CASE WHEN r.nivel_riesgo = 'BAJO'  THEN 1 ELSE 0 END) AS procesos_bajo,
        SUM(CASE WHEN r.nivel_riesgo = 'MEDIO' THEN 1 ELSE 0 END) AS procesos_medio,
        SUM(CASE WHEN r.nivel_riesgo = 'ALTO'  THEN 1 ELSE 0 END) AS procesos_alto,
        SUM(CAST(ISNULL(f.valor_adjudicado, 0) AS DECIMAL(28,2))) AS valor_adjudicado_total,
        SUM(CASE WHEN r.nivel_riesgo IN ('MEDIO','ALTO')
                 THEN CAST(ISNULL(f.valor_adjudicado, 0) AS DECIMAL(28,2)) ELSE 0 END) AS valor_en_riesgo_medio_alto
INTO    pbi.agg_riesgo_x_modalidad_anio
FROM    dwh.fact_contratacion f
JOIN    dwh.dim_modalidad m ON m.sk_modalidad = f.sk_modalidad
LEFT JOIN dwh.dim_tiempo  t ON t.sk_tiempo    = f.sk_t_publicacion
LEFT JOIN ind.riesgo_corrupcion r ON r.id_proceso = f.id_proceso
WHERE   t.anio IS NOT NULL
GROUP BY m.nombre, m.es_competitiva, t.anio;

CREATE CLUSTERED INDEX IX_agg1 ON pbi.agg_riesgo_x_modalidad_anio (anio, modalidad);
PRINT '[1] agg_riesgo_x_modalidad_anio: ' + CAST(@@ROWCOUNT AS VARCHAR)
    + ' filas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- (2) Por entidad x ano
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();

SELECT  e.sk_entidad, e.nit, e.nombre AS entidad,
        e.departamento, e.orden, t.anio,
        COUNT_BIG(*) AS total_procesos,
        COUNT_BIG(r.id_proceso) AS procesos_con_alerta,
        SUM(CASE WHEN r.nivel_riesgo = 'BAJO'  THEN 1 ELSE 0 END) AS procesos_bajo,
        SUM(CASE WHEN r.nivel_riesgo = 'MEDIO' THEN 1 ELSE 0 END) AS procesos_medio,
        SUM(CASE WHEN r.nivel_riesgo = 'ALTO'  THEN 1 ELSE 0 END) AS procesos_alto,
        SUM(CAST(ISNULL(f.valor_adjudicado, 0) AS DECIMAL(28,2))) AS valor_adjudicado_total
INTO    pbi.agg_riesgo_x_entidad_anio
FROM    dwh.fact_contratacion f
JOIN    dwh.dim_entidad  e ON e.sk_entidad = f.sk_entidad
LEFT JOIN dwh.dim_tiempo t ON t.sk_tiempo  = f.sk_t_publicacion
LEFT JOIN ind.riesgo_corrupcion r ON r.id_proceso = f.id_proceso
WHERE   t.anio IS NOT NULL
GROUP BY e.sk_entidad, e.nit, e.nombre, e.departamento, e.orden, t.anio;

CREATE CLUSTERED INDEX IX_agg2 ON pbi.agg_riesgo_x_entidad_anio (anio, sk_entidad);
CREATE NONCLUSTERED INDEX IX_agg2_depto ON pbi.agg_riesgo_x_entidad_anio (departamento);
PRINT '[2] agg_riesgo_x_entidad_anio: ' + CAST(@@ROWCOUNT AS VARCHAR)
    + ' filas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- (3) Por departamento x ano
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();

SELECT  e.departamento, t.anio,
        COUNT_BIG(*) AS total_procesos,
        COUNT_BIG(DISTINCT e.sk_entidad) AS entidades_distintas,
        COUNT_BIG(r.id_proceso) AS procesos_con_alerta,
        SUM(CASE WHEN r.nivel_riesgo = 'BAJO'  THEN 1 ELSE 0 END) AS procesos_bajo,
        SUM(CASE WHEN r.nivel_riesgo = 'MEDIO' THEN 1 ELSE 0 END) AS procesos_medio,
        SUM(CASE WHEN r.nivel_riesgo = 'ALTO'  THEN 1 ELSE 0 END) AS procesos_alto,
        SUM(CAST(ISNULL(f.valor_adjudicado, 0) AS DECIMAL(28,2))) AS valor_adjudicado_total
INTO    pbi.agg_riesgo_x_departamento_anio
FROM    dwh.fact_contratacion f
JOIN    dwh.dim_entidad  e ON e.sk_entidad = f.sk_entidad
LEFT JOIN dwh.dim_tiempo t ON t.sk_tiempo  = f.sk_t_publicacion
LEFT JOIN ind.riesgo_corrupcion r ON r.id_proceso = f.id_proceso
WHERE   t.anio IS NOT NULL
GROUP BY e.departamento, t.anio;

CREATE CLUSTERED INDEX IX_agg3 ON pbi.agg_riesgo_x_departamento_anio (anio, departamento);
PRINT '[3] agg_riesgo_x_departamento_anio: ' + CAST(@@ROWCOUNT AS VARCHAR)
    + ' filas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- (4) Por indicador x ano
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();

SELECT  a.codigo_anomalia, a.puntos AS puntos_indicador, t.anio,
        COUNT_BIG(*) AS n_alertas,
        COUNT_BIG(DISTINCT a.id_proceso) AS procesos_distintos,
        SUM(CAST(ISNULL(f.valor_adjudicado, 0) AS DECIMAL(28,2))) AS valor_adjudicado_en_alertas
INTO    pbi.agg_alertas_x_indicador_anio
FROM    ind.alertas_proceso a
LEFT JOIN dwh.fact_contratacion f ON f.id_proceso = a.id_proceso
LEFT JOIN dwh.dim_tiempo t        ON t.sk_tiempo  = f.sk_t_publicacion
WHERE   t.anio IS NOT NULL
GROUP BY a.codigo_anomalia, a.puntos, t.anio;

CREATE CLUSTERED INDEX IX_agg4 ON pbi.agg_alertas_x_indicador_anio (anio, codigo_anomalia);
PRINT '[4] agg_alertas_x_indicador_anio: ' + CAST(@@ROWCOUNT AS VARCHAR)
    + ' filas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- (5) Top proveedores con riesgo
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();

SELECT  p.sk_proveedor, p.documento, p.nombre AS proveedor,
        COUNT_BIG(DISTINCT r.id_proceso) AS procesos_con_alerta,
        SUM(CASE WHEN r.nivel_riesgo = 'BAJO'  THEN 1 ELSE 0 END) AS procesos_bajo,
        SUM(CASE WHEN r.nivel_riesgo = 'MEDIO' THEN 1 ELSE 0 END) AS procesos_medio,
        SUM(CASE WHEN r.nivel_riesgo = 'ALTO'  THEN 1 ELSE 0 END) AS procesos_alto,
        SUM(r.puntos_totales) AS puntos_acumulados,
        AVG(CAST(r.puntos_totales AS DECIMAL(5,2))) AS promedio_puntos,
        SUM(CAST(ISNULL(f.valor_adjudicado, 0) AS DECIMAL(28,2))) AS valor_adjudicado_total,
        COUNT_BIG(DISTINCT r.sk_entidad) AS entidades_distintas_contratantes
INTO    pbi.agg_top_proveedores_riesgo
FROM    ind.riesgo_corrupcion r
JOIN    dwh.dim_proveedor p ON p.sk_proveedor = r.sk_proveedor
LEFT JOIN dwh.fact_contratacion f ON f.id_proceso = r.id_proceso
WHERE   r.sk_proveedor IS NOT NULL
GROUP BY p.sk_proveedor, p.documento, p.nombre;

CREATE CLUSTERED INDEX IX_agg5 ON pbi.agg_top_proveedores_riesgo (puntos_acumulados DESC);
PRINT '[5] agg_top_proveedores_riesgo: ' + CAST(@@ROWCOUNT AS VARCHAR)
    + ' filas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

PRINT '';
PRINT '======================================';
PRINT 'AGREGACIONES POWER BI COMPLETADAS';
PRINT '======================================';

SELECT t.name AS tabla, p.rows AS filas
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE SCHEMA_NAME(t.schema_id) = 'pbi' AND t.name LIKE 'agg_%'
ORDER BY t.name;

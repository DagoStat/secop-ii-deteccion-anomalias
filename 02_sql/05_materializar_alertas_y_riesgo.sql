-- ============================================================================
-- 05_materializar_alertas_y_riesgo.sql
-- Materializa las alertas individuales en ind.alertas_proceso y calcula el
-- indice de riesgo compuesto en ind.riesgo_corrupcion.
--
-- Escala de riesgo V16 (sobre indice 0-22 puntos):
--   SIN RIESGO  0
--   BAJO        1 - 5
--   MEDIO       6 - 13
--   ALTO       14 - 22
--
-- Tiempo: 8-20 minutos (escanea 7.7M para 9 indicadores; los percentiles
-- de ANOM-008 y ANOM-009 incrementan el costo respecto a versiones previas)
-- ============================================================================
USE SECOP_DWH;
GO

SET NOCOUNT ON;

PRINT '======================================';
PRINT 'MATERIALIZAR ALERTAS Y RIESGO';
PRINT 'Inicio: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';
GO

-- ----------------------------------------------------------------------
-- (1) Crear/recrear tablas
-- ----------------------------------------------------------------------
IF OBJECT_ID('ind.riesgo_corrupcion', 'U') IS NOT NULL
    DROP TABLE ind.riesgo_corrupcion;
IF OBJECT_ID('ind.alertas_proceso', 'U') IS NOT NULL
    DROP TABLE ind.alertas_proceso;
GO

CREATE TABLE ind.alertas_proceso (
    sk_alerta          BIGINT IDENTITY(1,1) NOT NULL,
    id_proceso         NVARCHAR(200)        NOT NULL,
    sk_entidad         INT                  NOT NULL,
    sk_proveedor       INT                  NULL,
    sk_modalidad       INT                  NOT NULL,
    sk_t_publicacion   INT                  NULL,
    sk_t_adjudicacion  INT                  NULL,
    codigo_anomalia    VARCHAR(20)          NOT NULL,
    puntos             INT                  NOT NULL,
    descripcion        NVARCHAR(500)        NOT NULL,
    fecha_calculo      DATETIME2            NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_alertas_proceso PRIMARY KEY (sk_alerta)
);
CREATE INDEX IX_ap_id_proceso ON ind.alertas_proceso(id_proceso);
CREATE INDEX IX_ap_codigo     ON ind.alertas_proceso(codigo_anomalia);
CREATE INDEX IX_ap_entidad    ON ind.alertas_proceso(sk_entidad);
CREATE INDEX IX_ap_proveedor  ON ind.alertas_proceso(sk_proveedor);
GO

CREATE TABLE ind.riesgo_corrupcion (
    sk_riesgo          BIGINT IDENTITY(1,1) NOT NULL,
    id_proceso         NVARCHAR(200)        NOT NULL,
    sk_entidad         INT                  NOT NULL,
    sk_proveedor       INT                  NULL,
    sk_modalidad       INT                  NOT NULL,
    sk_t_publicacion   INT                  NULL,
    sk_t_adjudicacion  INT                  NULL,
    n_alertas          INT                  NOT NULL,
    puntos_totales     INT                  NOT NULL,
    nivel_riesgo       VARCHAR(20)          NOT NULL,
    fecha_calculo      DATETIME2            NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_riesgo_corrupcion PRIMARY KEY (sk_riesgo),
    CONSTRAINT UQ_riesgo_id_proceso UNIQUE (id_proceso)
);
CREATE INDEX IX_rc_nivel     ON ind.riesgo_corrupcion(nivel_riesgo);
CREATE INDEX IX_rc_puntos    ON ind.riesgo_corrupcion(puntos_totales DESC);
CREATE INDEX IX_rc_entidad   ON ind.riesgo_corrupcion(sk_entidad);
CREATE INDEX IX_rc_proveedor ON ind.riesgo_corrupcion(sk_proveedor);
GO

PRINT '[1] Tablas creadas';
GO

-- ----------------------------------------------------------------------
-- (2) Poblar ind.alertas_proceso desde la union de las 8 vistas
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();
PRINT '[2] Poblando ind.alertas_proceso...';

INSERT INTO ind.alertas_proceso
    (id_proceso, sk_entidad, sk_proveedor, sk_modalidad,
     sk_t_publicacion, sk_t_adjudicacion,
     codigo_anomalia, puntos, descripcion)
SELECT  id_proceso, sk_entidad, sk_proveedor, sk_modalidad,
        sk_t_publicacion, sk_t_adjudicacion,
        codigo_anomalia, puntos, descripcion
FROM    ind.vw_alertas_todas;

PRINT '[2] ind.alertas_proceso: ' + CAST(@@ROWCOUNT AS VARCHAR)
    + ' alertas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- (3) Calcular ind.riesgo_corrupcion (agregacion por id_proceso)
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();
PRINT '[3] Calculando ind.riesgo_corrupcion...';

INSERT INTO ind.riesgo_corrupcion
    (id_proceso, sk_entidad, sk_proveedor, sk_modalidad,
     sk_t_publicacion, sk_t_adjudicacion,
     n_alertas, puntos_totales, nivel_riesgo)
SELECT  id_proceso,
        MAX(sk_entidad)        AS sk_entidad,
        MAX(sk_proveedor)      AS sk_proveedor,
        MAX(sk_modalidad)      AS sk_modalidad,
        MAX(sk_t_publicacion)  AS sk_t_publicacion,
        MAX(sk_t_adjudicacion) AS sk_t_adjudicacion,
        COUNT(*)               AS n_alertas,
        SUM(puntos)            AS puntos_totales,
        CASE
            WHEN SUM(puntos) = 0                    THEN 'SIN RIESGO'
            WHEN SUM(puntos) BETWEEN 1  AND 5       THEN 'BAJO'
            WHEN SUM(puntos) BETWEEN 6  AND 13      THEN 'MEDIO'
            WHEN SUM(puntos) >= 14                  THEN 'ALTO'
        END AS nivel_riesgo
FROM    ind.alertas_proceso
GROUP BY id_proceso;

PRINT '[3] ind.riesgo_corrupcion: ' + CAST(@@ROWCOUNT AS VARCHAR)
    + ' procesos en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- Verificacion
PRINT '';
PRINT '--- Conteo por indicador ---';
SELECT codigo_anomalia, COUNT_BIG(*) AS alertas
FROM   ind.alertas_proceso
GROUP BY codigo_anomalia
ORDER BY codigo_anomalia;

PRINT '';
PRINT '--- Distribucion por nivel de riesgo ---';
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
GO

-- ----------------------------------------------------------------------
-- Top 20 entidades con mas procesos en riesgo MEDIO + ALTO (verificacion V16)
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- Top 20 entidades MEDIO + ALTO ---';
SELECT TOP 20
        e.nombre AS entidad,
        e.departamento,
        SUM(CASE WHEN r.nivel_riesgo = 'ALTO'  THEN 1 ELSE 0 END) AS alto,
        SUM(CASE WHEN r.nivel_riesgo = 'MEDIO' THEN 1 ELSE 0 END) AS medio,
        AVG(CAST(r.puntos_totales AS DECIMAL(5,2)))               AS prom_pts
FROM    ind.riesgo_corrupcion r
JOIN    dwh.dim_entidad e ON e.sk_entidad = r.sk_entidad
WHERE   r.nivel_riesgo IN ('MEDIO','ALTO')
GROUP BY e.nombre, e.departamento
ORDER BY alto DESC, medio DESC, prom_pts DESC;

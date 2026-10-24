-- ============================================================================
-- 03_cargar_staging_a_dwh.sql
-- Carga las dimensiones y la fact desde staging.secop_ii_procesos.
--
-- Prerrequisito: haber ejecutado el script Python pipeline/01_extraccion_secop_ii.py
-- que poblo staging.secop_ii_procesos con ~8M registros.
--
-- Garantiza:
--   - Sin duplicados (ROW_NUMBER por id_del_proceso, fecha_ingesta DESC)
--   - Solo procesos atribuibles (INNER JOIN con dim_entidad y dim_modalidad)
--   - Trazabilidad 100% al staging
--
-- Tiempo: 5-10 minutos sobre 8M de registros.
-- ============================================================================
USE SECOP_DWH;
GO

SET NOCOUNT ON;

PRINT '======================================';
PRINT 'CARGA DWH desde staging';
PRINT 'Inicio: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';
GO

-- ----------------------------------------------------------------------
-- (1) dim_modalidad (catalogo)
-- ----------------------------------------------------------------------
PRINT '[1] Cargando dim_modalidad...';

;WITH src AS (
    SELECT DISTINCT LTRIM(RTRIM(modalidad_de_contratacion)) AS nombre
    FROM   staging.secop_ii_procesos
    WHERE  modalidad_de_contratacion IS NOT NULL
)
MERGE dwh.dim_modalidad AS tgt
USING src
   ON tgt.nombre = src.nombre
WHEN NOT MATCHED THEN
    INSERT (nombre, es_competitiva)
    VALUES (src.nombre,
            CASE WHEN src.nombre LIKE '%Licitación%'
                  OR src.nombre LIKE '%Selección%'
                  OR src.nombre LIKE '%Concurso%'
                  OR src.nombre LIKE '%Mínima cuantía%'
                  OR src.nombre LIKE '%subasta%'
                  THEN 1 ELSE 0 END);

PRINT '   dim_modalidad: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' modalidades';
GO

-- ----------------------------------------------------------------------
-- (2) dim_entidad
-- ----------------------------------------------------------------------
PRINT '[2] Cargando dim_entidad...';

;WITH src AS (
    SELECT DISTINCT
        nit_entidad        AS nit,
        MAX(nombre_entidad) AS nombre,
        MAX(departamento_entidad) AS departamento,
        MAX(ciudad_entidad)       AS ciudad,
        MAX(orden_entidad)        AS orden
    FROM staging.secop_ii_procesos
    WHERE nit_entidad IS NOT NULL
    GROUP BY nit_entidad
)
MERGE dwh.dim_entidad AS tgt
USING src
   ON tgt.nit = src.nit
WHEN NOT MATCHED THEN
    INSERT (nit, nombre, departamento, ciudad, orden)
    VALUES (src.nit,
            ISNULL(src.nombre, '(Sin nombre)'),
            ISNULL(src.departamento, 'No Definido'),
            src.ciudad,
            src.orden);

PRINT '   dim_entidad: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' entidades';
GO

-- ----------------------------------------------------------------------
-- (3) dim_proveedor
-- ----------------------------------------------------------------------
PRINT '[3] Cargando dim_proveedor...';

;WITH src AS (
    SELECT DISTINCT
        nit_del_proveedor_adjudicado AS documento,
        MAX(nombre_del_proveedor_adjudicado) AS nombre
    FROM staging.secop_ii_procesos
    WHERE nit_del_proveedor_adjudicado IS NOT NULL
    GROUP BY nit_del_proveedor_adjudicado
)
MERGE dwh.dim_proveedor AS tgt
USING src
   ON tgt.documento = src.documento
WHEN NOT MATCHED THEN
    INSERT (documento, nombre)
    VALUES (src.documento, ISNULL(src.nombre, '(Sin nombre)'));

PRINT '   dim_proveedor: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' proveedores';
GO

-- ----------------------------------------------------------------------
-- (4) dim_tiempo (2018-2030)
-- ----------------------------------------------------------------------
PRINT '[4] Cargando dim_tiempo...';

IF NOT EXISTS (SELECT 1 FROM dwh.dim_tiempo)
BEGIN
    ;WITH cte AS (
        SELECT CAST('2018-01-01' AS DATE) AS f
        UNION ALL SELECT DATEADD(DAY, 1, f) FROM cte WHERE f < '2030-12-31'
    )
    INSERT INTO dwh.dim_tiempo
           (sk_tiempo, fecha, anio, trimestre, mes, nombre_mes, dia, dia_semana)
    SELECT  CAST(FORMAT(f,'yyyyMMdd') AS INT),
            f,
            YEAR(f),
            DATEPART(QUARTER, f),
            MONTH(f),
            DATENAME(MONTH, f),
            DAY(f),
            DATEPART(WEEKDAY, f)
    FROM    cte
    OPTION (MAXRECURSION 0);

    PRINT '   dim_tiempo: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' dias';
END
ELSE
    PRINT '   dim_tiempo: ya cargada';
GO

-- ----------------------------------------------------------------------
-- (5) fact_contratacion: dedup ROW_NUMBER + INNER JOIN con dimensiones
--     Carga ano por ano para feedback de progreso
-- ----------------------------------------------------------------------
PRINT '[5] Cargando fact_contratacion ano por ano...';

DELETE FROM dwh.fact_contratacion;

DECLARE @anio INT = 2020, @msg VARCHAR(200), @t DATETIME2, @n INT;

WHILE @anio <= 2026
BEGIN
    SET @t = SYSDATETIME();

    ;WITH dedup AS (
        SELECT  CAST(id_del_proceso AS NVARCHAR(200))      AS id_proceso_clean,
                nit_entidad,
                modalidad_de_contratacion,
                nit_del_proveedor_adjudicado,
                fecha_de_publicacion_del,
                fecha_adjudicacion,
                precio_base,
                valor_total_adjudicacion,
                conteo_de_respuestas_a_ofertas,
                estado_del_procedimiento,
                ROW_NUMBER() OVER (
                    PARTITION BY CAST(id_del_proceso AS NVARCHAR(200))
                    ORDER BY    fecha_ingesta DESC,
                                fecha_adjudicacion DESC
                ) AS rn
        FROM    staging.secop_ii_procesos
        WHERE   id_del_proceso IS NOT NULL
          AND   YEAR(fecha_de_publicacion_del) = @anio
    )
    INSERT INTO dwh.fact_contratacion
        (id_proceso, sk_entidad, sk_proveedor, sk_modalidad,
         sk_t_publicacion, sk_t_adjudicacion,
         precio_base, valor_adjudicado, n_oferentes, estado)
    SELECT
        d.id_proceso_clean,
        e.sk_entidad,
        p.sk_proveedor,
        m.sk_modalidad,
        TRY_CAST(FORMAT(d.fecha_de_publicacion_del,'yyyyMMdd') AS INT),
        TRY_CAST(FORMAT(d.fecha_adjudicacion,      'yyyyMMdd') AS INT),
        TRY_CAST(d.precio_base                AS DECIMAL(20,2)),
        TRY_CAST(d.valor_total_adjudicacion   AS DECIMAL(20,2)),
        TRY_CAST(d.conteo_de_respuestas_a_ofertas AS INT),
        d.estado_del_procedimiento
    FROM   dedup d
    JOIN   dwh.dim_entidad   e   ON e.nit    = d.nit_entidad
    JOIN   dwh.dim_modalidad m   ON m.nombre = LTRIM(RTRIM(d.modalidad_de_contratacion))
    LEFT JOIN dwh.dim_proveedor p ON p.documento = d.nit_del_proveedor_adjudicado
    WHERE  d.rn = 1;

    SET @n = @@ROWCOUNT;
    SET @msg = '   Anio ' + CAST(@anio AS VARCHAR(4))
             + ': ' + CAST(@n AS VARCHAR(10))
             + ' filas (' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR(6)) + ' seg)';
    RAISERROR(@msg, 0, 1) WITH NOWAIT;

    CHECKPOINT;
    SET @anio = @anio + 1;
END;

-- Procesos sin fecha_publicacion
;WITH dedup AS (
    SELECT  CAST(id_del_proceso AS NVARCHAR(200)) AS id_proceso_clean,
            nit_entidad, modalidad_de_contratacion, nit_del_proveedor_adjudicado,
            fecha_adjudicacion, precio_base, valor_total_adjudicacion,
            conteo_de_respuestas_a_ofertas, estado_del_procedimiento,
            ROW_NUMBER() OVER (PARTITION BY CAST(id_del_proceso AS NVARCHAR(200))
                               ORDER BY fecha_ingesta DESC) AS rn
    FROM staging.secop_ii_procesos
    WHERE id_del_proceso IS NOT NULL
      AND fecha_de_publicacion_del IS NULL
)
INSERT INTO dwh.fact_contratacion
    (id_proceso, sk_entidad, sk_proveedor, sk_modalidad,
     sk_t_publicacion, sk_t_adjudicacion,
     precio_base, valor_adjudicado, n_oferentes, estado)
SELECT d.id_proceso_clean, e.sk_entidad, p.sk_proveedor, m.sk_modalidad,
       NULL,
       TRY_CAST(FORMAT(d.fecha_adjudicacion,'yyyyMMdd') AS INT),
       TRY_CAST(d.precio_base                AS DECIMAL(20,2)),
       TRY_CAST(d.valor_total_adjudicacion   AS DECIMAL(20,2)),
       TRY_CAST(d.conteo_de_respuestas_a_ofertas AS INT),
       d.estado_del_procedimiento
FROM dedup d
JOIN dwh.dim_entidad   e ON e.nit    = d.nit_entidad
JOIN dwh.dim_modalidad m ON m.nombre = LTRIM(RTRIM(d.modalidad_de_contratacion))
LEFT JOIN dwh.dim_proveedor p ON p.documento = d.nit_del_proveedor_adjudicado
WHERE d.rn = 1;
PRINT '   Sin fecha_publicacion: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' filas';

PRINT '';
PRINT '======================================';
PRINT 'CARGA DWH COMPLETADA';
PRINT 'Fin: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';
GO

-- Verificacion final
SELECT 'dim_tiempo'        AS tabla, COUNT_BIG(*) AS filas FROM dwh.dim_tiempo
UNION ALL SELECT 'dim_modalidad',     COUNT_BIG(*) FROM dwh.dim_modalidad
UNION ALL SELECT 'dim_entidad',       COUNT_BIG(*) FROM dwh.dim_entidad
UNION ALL SELECT 'dim_proveedor',     COUNT_BIG(*) FROM dwh.dim_proveedor
UNION ALL SELECT 'fact_contratacion', COUNT_BIG(*) FROM dwh.fact_contratacion;

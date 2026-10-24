
-- ============================================================================
-- 17_paso7_calidad_dama.sql
-- Paso 7: Metricas de calidad de datos sobre 7 dimensiones DAMA-DMBOK 2.
--
-- Cada metrica se inserta en meta.calidad_dimensiones con:
--   - universo_evaluado: cuantas filas se analizaron
--   - casos_con_problema: cuantas fallan la regla
--   - pct_cumplimiento: 100 - (problemas/universo)*100
--   - pct_objetivo: umbral aceptable (varia por metrica)
--   - cumple: 1 si pct_cumplimiento >= pct_objetivo, 0 caso contrario
--   - severidad: CRITICA / ALTA / MEDIA / BAJA
--
-- Las 7 dimensiones (DAMA-DMBOK 2, capitulo 13):
--   1. Completitud   - campos criticos no nulos
--   2. Unicidad      - sin duplicados por clave de negocio
--   3. Validez       - valores dentro del dominio permitido
--   4. Consistencia  - coherencia entre campos relacionados
--   5. Conformidad   - adherencia a estandares (formatos, codigos)
--   6. Oportunidad   - frescura y latencia de los datos
--   7. Trazabilidad  - capacidad de rastrear cada registro a su fuente
--
-- Estimacion: 5-15 minutos (algunas consultas escanean los 7.7M)
-- ============================================================================
USE SECOP_DWH;
GO

SET NOCOUNT ON;

PRINT '======================================';
PRINT 'PASO 7: Calidad de datos (DAMA-DMBOK 2)';
PRINT 'Inicio: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';
GO

-- ----------------------------------------------------------------------
-- (0) Schema meta y tabla destino
-- ----------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'meta')
    EXEC('CREATE SCHEMA meta AUTHORIZATION dbo');
GO

IF OBJECT_ID('meta.calidad_dimensiones', 'U') IS NOT NULL
    DROP TABLE meta.calidad_dimensiones;

CREATE TABLE meta.calidad_dimensiones (
    sk_medicion         BIGINT IDENTITY(1,1) NOT NULL,
    fecha_medicion      DATETIME2            NOT NULL DEFAULT SYSDATETIME(),
    dimension           VARCHAR(50)          NOT NULL,
    metrica             VARCHAR(200)         NOT NULL,
    universo_evaluado   BIGINT               NOT NULL,
    casos_con_problema  BIGINT               NOT NULL,
    pct_cumplimiento    DECIMAL(7,4)         NOT NULL,
    pct_objetivo        DECIMAL(7,4)         NOT NULL,
    cumple              BIT                  NOT NULL,
    severidad           VARCHAR(20)          NOT NULL,
    descripcion         NVARCHAR(500)        NOT NULL,
    CONSTRAINT PK_calidad_dimensiones PRIMARY KEY (sk_medicion)
);
CREATE INDEX IX_cd_dim ON meta.calidad_dimensiones (dimension);
GO

PRINT '[0] meta.calidad_dimensiones creada';
GO

-- ----------------------------------------------------------------------
-- DIMENSION 1: COMPLETITUD (5 metricas)
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();
PRINT '[1] Calculando COMPLETITUD...';

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.fact_contratacion)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Completitud', 'id_proceso no nulo (PK negocio)',
        base.n,
        SUM(CASE WHEN f.id_proceso IS NULL THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN f.id_proceso IS NULL THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN SUM(CASE WHEN f.id_proceso IS NULL THEN 1 ELSE 0 END) = 0 THEN 1 ELSE 0 END,
        'CRITICA',
        'PK del negocio. Si hay null, el proceso es no rastreable.'
FROM    dwh.fact_contratacion f
CROSS JOIN base
GROUP BY base.n;

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.fact_contratacion)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Completitud', 'sk_entidad no nulo',
        base.n,
        SUM(CASE WHEN f.sk_entidad IS NULL THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN f.sk_entidad IS NULL THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN SUM(CASE WHEN f.sk_entidad IS NULL THEN 1 ELSE 0 END) = 0 THEN 1 ELSE 0 END,
        'CRITICA', 'Sin entidad no se puede atribuir responsabilidad.'
FROM dwh.fact_contratacion f CROSS JOIN base GROUP BY base.n;

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.fact_contratacion)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Completitud', 'valor_adjudicado no nulo',
        base.n,
        SUM(CASE WHEN f.valor_adjudicado IS NULL THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN f.valor_adjudicado IS NULL THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        95.0000,
        CASE WHEN 100.0 * (1.0 - 1.0*SUM(CASE WHEN f.valor_adjudicado IS NULL THEN 1 ELSE 0 END) / NULLIF(base.n,0)) >= 95 THEN 1 ELSE 0 END,
        'ALTA', 'Indispensable para analisis economico.'
FROM dwh.fact_contratacion f CROSS JOIN base GROUP BY base.n;

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.fact_contratacion)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Completitud', 'sk_t_publicacion no nulo',
        base.n,
        SUM(CASE WHEN f.sk_t_publicacion IS NULL THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN f.sk_t_publicacion IS NULL THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        95.0000,
        CASE WHEN 100.0 * (1.0 - 1.0*SUM(CASE WHEN f.sk_t_publicacion IS NULL THEN 1 ELSE 0 END) / NULLIF(base.n,0)) >= 95 THEN 1 ELSE 0 END,
        'ALTA', 'Necesario para todo analisis temporal.'
FROM dwh.fact_contratacion f CROSS JOIN base GROUP BY base.n;

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.dim_entidad)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Completitud', 'departamento no es No Definido',
        base.n,
        SUM(CASE WHEN e.departamento IS NULL OR e.departamento = 'No Definido' THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN e.departamento IS NULL OR e.departamento = 'No Definido' THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        95.0000,
        CASE WHEN 100.0 * (1.0 - 1.0*SUM(CASE WHEN e.departamento IS NULL OR e.departamento = 'No Definido' THEN 1 ELSE 0 END) / NULLIF(base.n,0)) >= 95 THEN 1 ELSE 0 END,
        'MEDIA', 'Hallazgo conocido: alta proporcion de entidades sin departamento real.'
FROM dwh.dim_entidad e CROSS JOIN base GROUP BY base.n;

PRINT '[1] COMPLETITUD: 5 metricas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- DIMENSION 2: UNICIDAD (3 metricas)
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();
PRINT '[2] Calculando UNICIDAD...';

;WITH base AS (
    SELECT COUNT_BIG(*) AS n, COUNT_BIG(DISTINCT id_proceso) AS distintos
    FROM dwh.fact_contratacion
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Unicidad', 'id_proceso unico en fact_contratacion',
        n, n - distintos,
        CAST(100.0 * distintos / NULLIF(n,0) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN n = distintos THEN 1 ELSE 0 END,
        'CRITICA', 'Duplicados implicarian doble conteo en metricas.'
FROM base;

;WITH base AS (
    SELECT COUNT_BIG(*) AS n, COUNT_BIG(DISTINCT nit) AS distintos
    FROM dwh.dim_entidad WHERE nit IS NOT NULL
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Unicidad', 'nit unico en dim_entidad',
        n, n - distintos,
        CAST(100.0 * distintos / NULLIF(n,0) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN n = distintos THEN 1 ELSE 0 END,
        'ALTA', 'Cada NIT identifica una entidad publica unica.'
FROM base;

;WITH base AS (
    SELECT COUNT_BIG(*) AS n, COUNT_BIG(DISTINCT documento) AS distintos
    FROM dwh.dim_proveedor WHERE documento IS NOT NULL
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Unicidad', 'documento unico en dim_proveedor',
        n, n - distintos,
        CAST(100.0 * distintos / NULLIF(n,0) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN n = distintos THEN 1 ELSE 0 END,
        'ALTA', 'Cada documento identifica un proveedor unico.'
FROM base;

PRINT '[2] UNICIDAD: 3 metricas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- DIMENSION 3: VALIDEZ (4 metricas)
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();
PRINT '[3] Calculando VALIDEZ...';

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.fact_contratacion WHERE valor_adjudicado IS NOT NULL)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Validez', 'valor_adjudicado no negativo',
        base.n,
        SUM(CASE WHEN f.valor_adjudicado < 0 THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN f.valor_adjudicado < 0 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN SUM(CASE WHEN f.valor_adjudicado < 0 THEN 1 ELSE 0 END) = 0 THEN 1 ELSE 0 END,
        'ALTA', 'Valores negativos no tienen sentido economico.'
FROM dwh.fact_contratacion f CROSS JOIN base WHERE f.valor_adjudicado IS NOT NULL GROUP BY base.n;

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.fact_contratacion WHERE n_oferentes IS NOT NULL)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Validez', 'n_oferentes no negativo',
        base.n,
        SUM(CASE WHEN f.n_oferentes < 0 THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN f.n_oferentes < 0 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN SUM(CASE WHEN f.n_oferentes < 0 THEN 1 ELSE 0 END) = 0 THEN 1 ELSE 0 END,
        'MEDIA', 'Negativos serian conteo invalido de ofertas.'
FROM dwh.fact_contratacion f CROSS JOIN base WHERE f.n_oferentes IS NOT NULL GROUP BY base.n;

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.fact_contratacion WHERE sk_t_publicacion IS NOT NULL)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Validez', 'fecha publicacion en rango [2018, 2030]',
        base.n,
        SUM(CASE WHEN t.anio NOT BETWEEN 2018 AND 2030 THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN t.anio NOT BETWEEN 2018 AND 2030 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN SUM(CASE WHEN t.anio NOT BETWEEN 2018 AND 2030 THEN 1 ELSE 0 END) = 0 THEN 1 ELSE 0 END,
        'ALTA', 'Fechas fuera de rango indican error de captura.'
FROM dwh.fact_contratacion f JOIN dwh.dim_tiempo t ON t.sk_tiempo = f.sk_t_publicacion CROSS JOIN base GROUP BY base.n;

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.fact_contratacion WHERE valor_adjudicado IS NOT NULL)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Validez', 'valor_adjudicado dentro de magnitud razonable (<=1e14 COP)',
        base.n,
        SUM(CASE WHEN f.valor_adjudicado > 100000000000000 THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN f.valor_adjudicado > 100000000000000 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        99.9999,
        CASE WHEN 100.0 * (1.0 - 1.0*SUM(CASE WHEN f.valor_adjudicado > 100000000000000 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) >= 99.9999 THEN 1 ELSE 0 END,
        'ALTA', 'Valores >100 billones COP son fisicamente imposibles para un proceso.'
FROM dwh.fact_contratacion f CROSS JOIN base WHERE f.valor_adjudicado IS NOT NULL GROUP BY base.n;

PRINT '[3] VALIDEZ: 4 metricas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- DIMENSION 4: CONSISTENCIA (3 metricas)
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();
PRINT '[4] Calculando CONSISTENCIA...';

;WITH base AS (
    SELECT COUNT_BIG(*) AS n
    FROM dwh.fact_contratacion f
    WHERE f.sk_t_publicacion IS NOT NULL AND f.sk_t_adjudicacion IS NOT NULL
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Consistencia', 'fecha_adjudicacion >= fecha_publicacion',
        base.n,
        SUM(CASE WHEN ta.fecha < tp.fecha THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN ta.fecha < tp.fecha THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        99.9000,
        CASE WHEN 100.0 * (1.0 - 1.0*SUM(CASE WHEN ta.fecha < tp.fecha THEN 1 ELSE 0 END) / NULLIF(base.n,0)) >= 99.9 THEN 1 ELSE 0 END,
        'ALTA', 'No se puede adjudicar antes de publicar.'
FROM dwh.fact_contratacion f
JOIN dwh.dim_tiempo tp ON tp.sk_tiempo = f.sk_t_publicacion
JOIN dwh.dim_tiempo ta ON ta.sk_tiempo = f.sk_t_adjudicacion
CROSS JOIN base GROUP BY base.n;

;WITH base AS (
    SELECT COUNT_BIG(*) AS n
    FROM dwh.fact_contratacion f
    JOIN dwh.dim_modalidad m ON m.sk_modalidad = f.sk_modalidad
    WHERE m.es_competitiva = 1 AND f.n_oferentes IS NOT NULL
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Consistencia', 'modalidad competitiva tiene n_oferentes >= 1',
        base.n,
        SUM(CASE WHEN f.n_oferentes < 1 THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN f.n_oferentes < 1 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        95.0000,
        CASE WHEN 100.0 * (1.0 - 1.0*SUM(CASE WHEN f.n_oferentes < 1 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) >= 95 THEN 1 ELSE 0 END,
        'MEDIA', 'Procesos competitivos sin oferentes son inconsistencia operacional.'
FROM dwh.fact_contratacion f
JOIN dwh.dim_modalidad m ON m.sk_modalidad = f.sk_modalidad
CROSS JOIN base
WHERE m.es_competitiva = 1 AND f.n_oferentes IS NOT NULL
GROUP BY base.n;

;WITH base AS (
    SELECT COUNT_BIG(*) AS n
    FROM dwh.fact_contratacion f
    WHERE f.precio_base > 0 AND f.valor_adjudicado IS NOT NULL
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Consistencia', 'valor_adjudicado / precio_base dentro de rango economico [0, 10]',
        base.n,
        SUM(CASE WHEN CAST(f.valor_adjudicado AS FLOAT)/f.precio_base > 10 THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN CAST(f.valor_adjudicado AS FLOAT)/f.precio_base > 10 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        99.9000,
        CASE WHEN 100.0 * (1.0 - 1.0*SUM(CASE WHEN CAST(f.valor_adjudicado AS FLOAT)/f.precio_base > 10 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) >= 99.9 THEN 1 ELSE 0 END,
        'MEDIA', 'Ratio > 10x sugiere error de captura en precio_base o valor.'
FROM dwh.fact_contratacion f CROSS JOIN base
WHERE f.precio_base > 0 AND f.valor_adjudicado IS NOT NULL
GROUP BY base.n;

PRINT '[4] CONSISTENCIA: 3 metricas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- DIMENSION 5: CONFORMIDAD (2 metricas)
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();
PRINT '[5] Calculando CONFORMIDAD...';

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.fact_contratacion)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Conformidad', 'id_proceso sigue formato CO1.<TIPO>.<N>',
        base.n,
        SUM(CASE WHEN f.id_proceso NOT LIKE 'CO1.%.%' THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN f.id_proceso NOT LIKE 'CO1.%.%' THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        99.9000,
        CASE WHEN 100.0 * (1.0 - 1.0*SUM(CASE WHEN f.id_proceso NOT LIKE 'CO1.%.%' THEN 1 ELSE 0 END) / NULLIF(base.n,0)) >= 99.9 THEN 1 ELSE 0 END,
        'MEDIA', 'Formato estandar definido por Colombia Compra Eficiente.'
FROM dwh.fact_contratacion f CROSS JOIN base GROUP BY base.n;

;WITH base AS (SELECT COUNT_BIG(*) AS n FROM dwh.dim_entidad WHERE nit IS NOT NULL)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Conformidad', 'NIT entidad es numerico de 9-10 digitos',
        base.n,
        SUM(CASE WHEN e.nit NOT LIKE '%[0-9]%' OR LEN(e.nit) NOT BETWEEN 8 AND 12 THEN 1 ELSE 0 END),
        CAST(100.0 * (1.0 - 1.0*SUM(CASE WHEN e.nit NOT LIKE '%[0-9]%' OR LEN(e.nit) NOT BETWEEN 8 AND 12 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) AS DECIMAL(7,4)),
        99.0000,
        CASE WHEN 100.0 * (1.0 - 1.0*SUM(CASE WHEN e.nit NOT LIKE '%[0-9]%' OR LEN(e.nit) NOT BETWEEN 8 AND 12 THEN 1 ELSE 0 END) / NULLIF(base.n,0)) >= 99 THEN 1 ELSE 0 END,
        'MEDIA', 'NIT colombiano es numerico, longitud estandar 9-10.'
FROM dwh.dim_entidad e CROSS JOIN base WHERE e.nit IS NOT NULL GROUP BY base.n;

PRINT '[5] CONFORMIDAD: 2 metricas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- DIMENSION 6: OPORTUNIDAD (2 metricas)
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();
PRINT '[6] Calculando OPORTUNIDAD...';

;WITH base AS (
    SELECT MAX(fecha_ingesta) AS max_ing,
           DATEDIFF(DAY, MAX(fecha_ingesta), SYSDATETIME()) AS dias_desde_ingesta,
           COUNT_BIG(*) AS n
    FROM staging.secop_ii_procesos
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Oportunidad', 'frescura: dias desde ultima ingesta <= 30',
        n,
        CASE WHEN dias_desde_ingesta > 30 THEN n ELSE 0 END,
        CASE WHEN dias_desde_ingesta <= 30 THEN 100.0000 ELSE CAST(100.0 - dias_desde_ingesta AS DECIMAL(7,4)) END,
        100.0000,
        CASE WHEN dias_desde_ingesta <= 30 THEN 1 ELSE 0 END,
        'MEDIA', 'Dato fresco asegura relevancia analitica.'
FROM base;

;WITH base AS (
    SELECT COUNT_BIG(*) AS n
    FROM dwh.fact_contratacion f
    JOIN dwh.dim_tiempo t ON t.sk_tiempo = f.sk_t_publicacion
    WHERE t.anio = 2026
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Oportunidad', 'cobertura 2026: procesos del anio en curso',
        (SELECT COUNT_BIG(*) FROM dwh.fact_contratacion),
        0,
        CAST(100.0 * n / NULLIF((SELECT COUNT_BIG(*) FROM dwh.fact_contratacion), 0) AS DECIMAL(7,4)),
        5.0000,
        CASE WHEN 100.0 * n / NULLIF((SELECT COUNT_BIG(*) FROM dwh.fact_contratacion), 0) >= 5 THEN 1 ELSE 0 END,
        'BAJA', 'Cobertura del anio en curso (informativo).'
FROM base;

PRINT '[6] OPORTUNIDAD: 2 metricas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

-- ----------------------------------------------------------------------
-- DIMENSION 7: TRAZABILIDAD (2 metricas)
-- ----------------------------------------------------------------------
DECLARE @t DATETIME2 = SYSDATETIME();
PRINT '[7] Calculando TRAZABILIDAD...';

;WITH base AS (
    SELECT COUNT_BIG(*) AS n_fact,
           SUM(CASE WHEN s.id_del_proceso IS NULL THEN 1 ELSE 0 END) AS huerfanos
    FROM dwh.fact_contratacion f
    LEFT JOIN staging.secop_ii_procesos s
      ON CAST(s.id_del_proceso AS NVARCHAR(200)) = f.id_proceso
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Trazabilidad', 'todo proceso en fact tiene origen en staging',
        n_fact, huerfanos,
        CAST(100.0 * (1.0 - 1.0*huerfanos/NULLIF(n_fact,0)) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN huerfanos = 0 THEN 1 ELSE 0 END,
        'CRITICA', 'Linaje completo es requisito de trazabilidad regulatoria.'
FROM base;

;WITH base AS (
    SELECT COUNT_BIG(*) AS n,
           SUM(CASE WHEN fecha_ingesta IS NULL THEN 1 ELSE 0 END) AS sin_fecha
    FROM staging.secop_ii_procesos
)
INSERT INTO meta.calidad_dimensiones
    (dimension, metrica, universo_evaluado, casos_con_problema, pct_cumplimiento, pct_objetivo, cumple, severidad, descripcion)
SELECT  'Trazabilidad', 'todo registro en staging tiene fecha_ingesta',
        n, sin_fecha,
        CAST(100.0 * (1.0 - 1.0*sin_fecha/NULLIF(n,0)) AS DECIMAL(7,4)),
        100.0000,
        CASE WHEN sin_fecha = 0 THEN 1 ELSE 0 END,
        'CRITICA', 'Sin fecha de ingesta no hay auditoria temporal.'
FROM base;

PRINT '[7] TRAZABILIDAD: 2 metricas en ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS VARCHAR) + ' seg';
GO

PRINT '';
PRINT '======================================';
PRINT 'PASO 7 COMPLETADO';
PRINT 'Fin: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';
GO

-- ----------------------------------------------------------------------
-- (8) Resumen ejecutivo
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (8a) Resumen por dimension ---';
SELECT  dimension,
        COUNT(*)                                                   AS metricas_evaluadas,
        SUM(CASE WHEN cumple = 1 THEN 1 ELSE 0 END)                AS cumplen,
        SUM(CASE WHEN cumple = 0 THEN 1 ELSE 0 END)                AS no_cumplen,
        CAST(AVG(pct_cumplimiento) AS DECIMAL(6,2))                AS pct_cumplimiento_promedio
FROM    meta.calidad_dimensiones
GROUP BY dimension
ORDER BY dimension;

PRINT '';
PRINT '--- (8b) Detalle: metricas que NO cumplen ---';
SELECT  dimension, metrica, universo_evaluado, casos_con_problema,
        pct_cumplimiento, pct_objetivo, severidad, descripcion
FROM    meta.calidad_dimensiones
WHERE   cumple = 0
ORDER BY CASE severidad
            WHEN 'CRITICA' THEN 1
            WHEN 'ALTA'    THEN 2
            WHEN 'MEDIA'   THEN 3
            WHEN 'BAJA'    THEN 4
         END,
         pct_cumplimiento;

PRINT '';
PRINT '--- (8c) Detalle completo ordenado ---';
SELECT  dimension, metrica, universo_evaluado, casos_con_problema,
        pct_cumplimiento, pct_objetivo, cumple, severidad
FROM    meta.calidad_dimensiones
ORDER BY dimension, metrica;

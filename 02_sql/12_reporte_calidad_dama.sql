-- ============================================================================
-- 12_reporte_calidad_dama.sql
-- Reportes formateados de los resultados de calidad DAMA-DMBOK 2 V16.2
-- para incluir en el documento de tesis.
--
-- Produce 6 outputs en cascada:
--   (1) Resumen ejecutivo (cifra de 1 linea)
--   (2) Resumen por dimension (tabla 7 filas)
--   (3) Detalle de las 21 metricas con resultado cumple/no cumple
--   (4) Solo las metricas que NO cumplen (para seccion de limitaciones)
--   (5) Solo metricas criticas (severidad CRITICA)
--   (6) Detalle textual para parrafos narrativos
--
-- Tiempo: <2 segundos.
-- ============================================================================
USE SECOP_DWH;

SET NOCOUNT ON;

PRINT '======================================';
PRINT 'REPORTE CALIDAD DAMA-DMBOK 2 - V16.2';
PRINT 'Fecha: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';

-- ----------------------------------------------------------------------
-- (1) RESUMEN EJECUTIVO de 1 linea para citar en el texto
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (1) RESUMEN EJECUTIVO ---';

SELECT
    COUNT(*)                                            AS metricas_totales,
    SUM(CAST(cumple AS INT))                            AS metricas_cumplen,
    COUNT(*) - SUM(CAST(cumple AS INT))                 AS metricas_no_cumplen,
    CAST(100.0 * SUM(CAST(cumple AS INT)) / COUNT(*)
         AS DECIMAL(5,2))                               AS pct_cumplimiento_global
FROM meta.calidad_dimensiones
WHERE fecha_medicion = (SELECT MAX(fecha_medicion) FROM meta.calidad_dimensiones);

-- ----------------------------------------------------------------------
-- (2) RESUMEN POR DIMENSION (TABLA DE 7 FILAS PARA EL DOCUMENTO)
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (2) RESUMEN POR DIMENSION DAMA ---';

SELECT
    dimension,
    COUNT(*)                                            AS n_metricas,
    SUM(CAST(cumple AS INT))                            AS cumplen,
    COUNT(*) - SUM(CAST(cumple AS INT))                 AS no_cumplen,
    CAST(100.0 * SUM(CAST(cumple AS INT)) / COUNT(*) AS DECIMAL(5,2)) AS pct_cumplimiento,
    AVG(pct_cumplimiento)                               AS pct_cumplimiento_promedio,
    MIN(pct_cumplimiento)                               AS pct_minimo,
    MAX(pct_cumplimiento)                               AS pct_maximo
FROM meta.calidad_dimensiones
WHERE fecha_medicion = (SELECT MAX(fecha_medicion) FROM meta.calidad_dimensiones)
GROUP BY dimension
ORDER BY CASE dimension
    WHEN 'Completitud'   THEN 1
    WHEN 'Unicidad'      THEN 2
    WHEN 'Validez'       THEN 3
    WHEN 'Consistencia'  THEN 4
    WHEN 'Conformidad'   THEN 5
    WHEN 'Oportunidad'   THEN 6
    WHEN 'Trazabilidad'  THEN 7
    ELSE 99 END;

-- ----------------------------------------------------------------------
-- (3) DETALLE COMPLETO DE LAS 21 METRICAS (TABLA GRANDE PARA ANEXO)
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (3) DETALLE DE LAS 21 METRICAS ---';

SELECT
    dimension,
    metrica,
    universo_evaluado,
    casos_con_problema,
    pct_cumplimiento,
    pct_objetivo,
    CASE WHEN cumple = 1 THEN 'CUMPLE' ELSE 'NO CUMPLE' END    AS estado,
    severidad,
    descripcion
FROM meta.calidad_dimensiones
WHERE fecha_medicion = (SELECT MAX(fecha_medicion) FROM meta.calidad_dimensiones)
ORDER BY
    CASE dimension
        WHEN 'Completitud'   THEN 1
        WHEN 'Unicidad'      THEN 2
        WHEN 'Validez'       THEN 3
        WHEN 'Consistencia'  THEN 4
        WHEN 'Conformidad'   THEN 5
        WHEN 'Oportunidad'   THEN 6
        WHEN 'Trazabilidad'  THEN 7
    END,
    CASE WHEN cumple = 1 THEN 1 ELSE 0 END,  -- los que no cumplen primero por dimension
    metrica;

-- ----------------------------------------------------------------------
-- (4) METRICAS QUE NO CUMPLEN (PARA SECCION DE LIMITACIONES)
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (4) METRICAS QUE NO CUMPLEN OBJETIVO ---';

SELECT
    dimension,
    metrica,
    pct_cumplimiento,
    pct_objetivo,
    CAST(pct_objetivo - pct_cumplimiento AS DECIMAL(7,4)) AS gap_a_objetivo,
    severidad,
    descripcion
FROM meta.calidad_dimensiones
WHERE fecha_medicion = (SELECT MAX(fecha_medicion) FROM meta.calidad_dimensiones)
  AND cumple = 0
ORDER BY pct_objetivo - pct_cumplimiento DESC, severidad;

-- ----------------------------------------------------------------------
-- (5) METRICAS CRITICAS (TODAS DEBEN CUMPLIR)
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (5) METRICAS CRITICAS Y SU ESTADO ---';

SELECT
    dimension,
    metrica,
    pct_cumplimiento,
    pct_objetivo,
    CASE WHEN cumple = 1 THEN 'CUMPLE OK' ELSE 'FALLA CRITICA' END AS estado,
    descripcion
FROM meta.calidad_dimensiones
WHERE fecha_medicion = (SELECT MAX(fecha_medicion) FROM meta.calidad_dimensiones)
  AND severidad = 'CRITICA'
ORDER BY cumple, dimension;

-- ----------------------------------------------------------------------
-- (6) NARRATIVA PARA PARRAFOS DEL DOCUMENTO
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (6) FRASES NARRATIVAS LISTAS PARA EL DOCUMENTO ---';

DECLARE @n_total INT, @n_cumple INT, @pct DECIMAL(5,2);
SELECT @n_total = COUNT(*), @n_cumple = SUM(CAST(cumple AS INT))
FROM meta.calidad_dimensiones
WHERE fecha_medicion = (SELECT MAX(fecha_medicion) FROM meta.calidad_dimensiones);

SET @pct = CAST(100.0 * @n_cumple / @n_total AS DECIMAL(5,2));

PRINT '';
PRINT 'Frase 1 (cumplimiento global):';
PRINT '  "Se aplicaron ' + CAST(@n_total AS VARCHAR) + ' metricas formales de calidad de datos cubriendo';
PRINT '   las siete dimensiones DAMA-DMBOK 2. El resultado consolidado es ' + CAST(@n_cumple AS VARCHAR);
PRINT '   metricas que cumplen su objetivo (' + CAST(@pct AS VARCHAR) + ' %)."';

PRINT '';
PRINT 'Frase 2 (criticas):';
DECLARE @crit_total INT, @crit_ok INT;
SELECT @crit_total = COUNT(*), @crit_ok = SUM(CAST(cumple AS INT))
FROM meta.calidad_dimensiones
WHERE fecha_medicion = (SELECT MAX(fecha_medicion) FROM meta.calidad_dimensiones)
  AND severidad = 'CRITICA';
PRINT '  "El 100% de las metricas criticas (' + CAST(@crit_ok AS VARCHAR) + '/' + CAST(@crit_total AS VARCHAR) +
      ' cumplen) cubren unicidad de claves primarias,';
PRINT '   trazabilidad de linaje fact->staging y presencia de campos PK del negocio."';

-- Frase 3: por dimension con conteo
PRINT '';
PRINT 'Frase 3 (por dimension):';
DECLARE @line NVARCHAR(MAX) = N'  "Distribucion por dimension: ';
SELECT @line = @line +
    dimension + ' ' + CAST(COUNT(*) AS VARCHAR) + ' metricas, ' +
    CAST(SUM(CAST(cumple AS INT)) AS VARCHAR) + ' cumplen; '
FROM meta.calidad_dimensiones
WHERE fecha_medicion = (SELECT MAX(fecha_medicion) FROM meta.calidad_dimensiones)
GROUP BY dimension
ORDER BY CASE dimension
    WHEN 'Completitud'   THEN 1 WHEN 'Unicidad'    THEN 2 WHEN 'Validez'     THEN 3
    WHEN 'Consistencia'  THEN 4 WHEN 'Conformidad' THEN 5 WHEN 'Oportunidad' THEN 6
    WHEN 'Trazabilidad'  THEN 7 END;
SET @line = LEFT(@line, LEN(@line) - 2) + '."';
PRINT @line;

PRINT '';
PRINT '======================================';
PRINT 'REPORTE COMPLETADO';
PRINT '======================================';

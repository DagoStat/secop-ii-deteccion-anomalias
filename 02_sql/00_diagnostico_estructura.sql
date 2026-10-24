-- ============================================================================
-- 00_diagnostico_estructura.sql
-- Lista las columnas reales de las dimensiones para evitar invocar nombres
-- inexistentes en scripts derivados. Pegar el output completo.
-- ============================================================================
USE SECOP_DWH;

SET NOCOUNT ON;

PRINT '--- Columnas de dwh.dim_entidad ---';
SELECT column_name, data_type
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  table_schema = 'dwh' AND table_name = 'dim_entidad'
ORDER BY ordinal_position;

PRINT '';
PRINT '--- Columnas de dwh.dim_proveedor ---';
SELECT column_name, data_type
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  table_schema = 'dwh' AND table_name = 'dim_proveedor'
ORDER BY ordinal_position;

PRINT '';
PRINT '--- Columnas de dwh.dim_modalidad ---';
SELECT column_name, data_type
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  table_schema = 'dwh' AND table_name = 'dim_modalidad'
ORDER BY ordinal_position;

PRINT '';
PRINT '--- Columnas de dwh.dim_tiempo ---';
SELECT column_name, data_type
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  table_schema = 'dwh' AND table_name = 'dim_tiempo'
ORDER BY ordinal_position;

PRINT '';
PRINT '--- Columnas de dwh.fact_contratacion ---';
SELECT column_name, data_type
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  table_schema = 'dwh' AND table_name = 'fact_contratacion'
ORDER BY ordinal_position;

PRINT '';
PRINT '--- Columnas de staging.secop_ii_procesos (primeras 20) ---';
SELECT TOP 20 column_name, data_type
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  table_schema = 'staging' AND table_name = 'secop_ii_procesos'
ORDER BY ordinal_position;

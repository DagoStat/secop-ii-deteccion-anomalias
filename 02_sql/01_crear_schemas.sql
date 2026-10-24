-- ============================================================================
-- 01_crear_schemas.sql
-- Crea la base de datos SECOP_DWH y los 5 schemas del modelo dimensional.
--
-- Schemas:
--   staging  - Datos crudos del API SECOP II
--   dwh      - Modelo dimensional estrella (Kimball)
--   ind      - Indicadores red flag y tabla de alertas materializadas
--   pbi      - Agregaciones precalculadas para Power BI
--   meta     - Metricas DAMA-DMBOK 2 y bitacora de backups
--
-- Tiempo de ejecucion: < 5 segundos
-- ============================================================================

USE master;
GO

-- Crear base de datos si no existe
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SECOP_DWH')
BEGIN
    CREATE DATABASE SECOP_DWH;
    PRINT 'Base SECOP_DWH creada';
END
ELSE
    PRINT 'Base SECOP_DWH ya existe';
GO

USE SECOP_DWH;
GO

SET NOCOUNT ON;

-- Crear schemas (cada uno en su propio batch porque CREATE SCHEMA debe ir solo)
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging AUTHORIZATION dbo');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dwh')
    EXEC('CREATE SCHEMA dwh AUTHORIZATION dbo');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ind')
    EXEC('CREATE SCHEMA ind AUTHORIZATION dbo');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'pbi')
    EXEC('CREATE SCHEMA pbi AUTHORIZATION dbo');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'meta')
    EXEC('CREATE SCHEMA meta AUTHORIZATION dbo');
GO

-- Verificacion
SELECT name AS schema_name
FROM sys.schemas
WHERE name IN ('staging', 'dwh', 'ind', 'pbi', 'meta')
ORDER BY name;
GO

PRINT 'Schemas creados: staging, dwh, ind, pbi, meta';

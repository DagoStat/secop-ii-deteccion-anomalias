-- ============================================================================
-- 09b_seguridad_pruebas.sql
-- Pruebas funcionales de los controles de seguridad implementados en el script 09.
--
-- Cada bloque crea un usuario de prueba, lo asigna al rol correspondiente y
-- ejecuta una consulta para demostrar el comportamiento esperado del DDM/RLS.
--
-- Limpiar al final: el bloque (5) elimina los usuarios de prueba.
-- ============================================================================
USE SECOP_DWH;
GO

SET NOCOUNT ON;

PRINT '======================================';
PRINT 'PRUEBAS DE SEGURIDAD (RLS + DDM)';
PRINT '======================================';

-- ----------------------------------------------------------------------
-- (1) Crear usuarios de prueba (sin login - solo para test impersonation)
-- ----------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID('test_auditor')          IS NULL CREATE USER test_auditor          WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('test_analista_publico') IS NULL CREATE USER test_analista_publico WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('test_ciudadano')        IS NULL CREATE USER test_ciudadano        WITHOUT LOGIN;

ALTER ROLE rol_auditor          ADD MEMBER test_auditor;
ALTER ROLE rol_analista_publico ADD MEMBER test_analista_publico;
ALTER ROLE rol_ciudadano        ADD MEMBER test_ciudadano;

PRINT '[1] Usuarios de prueba creados y asignados a roles';
GO

-- ----------------------------------------------------------------------
-- (2) PRUEBA DDM: que ve cada rol al consultar dim_proveedor
-- ----------------------------------------------------------------------
PRINT '';
PRINT '=== PRUEBA DDM: dwh.dim_proveedor (TOP 3) ===';

PRINT '';
PRINT '--- Como rol_auditor (UNMASK - ve datos reales) ---';
EXECUTE AS USER = 'test_auditor';
SELECT TOP 3 sk_proveedor, nit, nombre FROM dwh.dim_proveedor;
REVERT;

PRINT '';
PRINT '--- Como rol_analista_publico (ve datos enmascarados) ---';
EXECUTE AS USER = 'test_analista_publico';
SELECT TOP 3 sk_proveedor, nit, nombre FROM dwh.dim_proveedor;
REVERT;

PRINT '';
PRINT '--- Como rol_ciudadano (ve datos enmascarados) ---';
EXECUTE AS USER = 'test_ciudadano';
SELECT TOP 3 sk_proveedor, nit, nombre FROM dwh.dim_proveedor;
REVERT;

-- ----------------------------------------------------------------------
-- (3) PRUEBA RLS: que ve cada rol en ind.riesgo_corrupcion
-- ----------------------------------------------------------------------
PRINT '';
PRINT '=== PRUEBA RLS: ind.riesgo_corrupcion (conteo por nivel) ===';

PRINT '';
PRINT '--- Como rol_auditor (ve TODOS los niveles incluido ALTO) ---';
EXECUTE AS USER = 'test_auditor';
SELECT nivel_riesgo, COUNT_BIG(*) AS procesos
FROM ind.riesgo_corrupcion
GROUP BY nivel_riesgo
ORDER BY CASE nivel_riesgo
            WHEN 'SIN RIESGO' THEN 0
            WHEN 'BAJO'       THEN 1
            WHEN 'MEDIO'      THEN 2
            WHEN 'ALTO'       THEN 3
         END;
REVERT;

PRINT '';
PRINT '--- Como rol_analista_publico (NO ve ALTO) ---';
EXECUTE AS USER = 'test_analista_publico';
SELECT nivel_riesgo, COUNT_BIG(*) AS procesos
FROM ind.riesgo_corrupcion
GROUP BY nivel_riesgo
ORDER BY CASE nivel_riesgo
            WHEN 'SIN RIESGO' THEN 0
            WHEN 'BAJO'       THEN 1
            WHEN 'MEDIO'      THEN 2
            WHEN 'ALTO'       THEN 3
         END;
REVERT;

PRINT '';
PRINT '--- Como rol_ciudadano (solo SIN RIESGO y BAJO) ---';
EXECUTE AS USER = 'test_ciudadano';
SELECT nivel_riesgo, COUNT_BIG(*) AS procesos
FROM ind.riesgo_corrupcion
GROUP BY nivel_riesgo
ORDER BY CASE nivel_riesgo
            WHEN 'SIN RIESGO' THEN 0
            WHEN 'BAJO'       THEN 1
            WHEN 'MEDIO'      THEN 2
            WHEN 'ALTO'       THEN 3
         END;
REVERT;

-- ----------------------------------------------------------------------
-- (4) PRUEBA conjunta DDM + RLS: JOIN entre riesgo_corrupcion y dim_proveedor
-- ----------------------------------------------------------------------
PRINT '';
PRINT '=== PRUEBA CONJUNTA: TOP 5 procesos riesgo MEDIO con proveedor ===';

PRINT '';
PRINT '--- Como rol_auditor (ve todo: nivel + nombre real) ---';
EXECUTE AS USER = 'test_auditor';
SELECT TOP 5
    r.id_proceso, r.nivel_riesgo, r.puntos_totales,
    p.nit, p.nombre
FROM ind.riesgo_corrupcion r
LEFT JOIN dwh.dim_proveedor p ON p.sk_proveedor = r.sk_proveedor
WHERE r.nivel_riesgo = 'MEDIO'
ORDER BY r.puntos_totales DESC;
REVERT;

PRINT '';
PRINT '--- Como rol_analista_publico (ve nivel + nombre enmascarado) ---';
EXECUTE AS USER = 'test_analista_publico';
SELECT TOP 5
    r.id_proceso, r.nivel_riesgo, r.puntos_totales,
    p.nit, p.nombre
FROM ind.riesgo_corrupcion r
LEFT JOIN dwh.dim_proveedor p ON p.sk_proveedor = r.sk_proveedor
WHERE r.nivel_riesgo = 'MEDIO'
ORDER BY r.puntos_totales DESC;
REVERT;

-- ----------------------------------------------------------------------
-- (5) LIMPIEZA - quitar usuarios de prueba (ejecutar manualmente si se desea)
-- ----------------------------------------------------------------------
/*
ALTER ROLE rol_auditor          DROP MEMBER test_auditor;
ALTER ROLE rol_analista_publico DROP MEMBER test_analista_publico;
ALTER ROLE rol_ciudadano        DROP MEMBER test_ciudadano;
DROP USER test_auditor;
DROP USER test_analista_publico;
DROP USER test_ciudadano;
*/

PRINT '';
PRINT '======================================';
PRINT 'PRUEBAS COMPLETADAS';
PRINT 'Los usuarios test_* permanecen para reproducibilidad.';
PRINT 'Descomentar el bloque (5) para eliminarlos.';
PRINT '======================================';
GO


-- ============================================================================
-- 18_paso8_backup_final.sql
-- Paso 8 (final): Backup completo de SECOP_DWH con verificacion y gobierno.
--
-- Lo que hace este script:
--   (1) Crea tabla meta.backups si no existe (gobierno de respaldos)
--   (2) Ejecuta BACKUP DATABASE con compresion, checksum y verificacion
--   (3) Hace RESTORE VERIFYONLY (confirma que el .bak es restaurable)
--   (4) Registra el backup en meta.backups con metadatos
--   (5) Muestra resumen: tamano del backup, tiempo, ratio compresion
--
-- AJUSTAR si tu unidad de respaldos es otra:
--   Editar @ruta_backup al inicio del script
-- ============================================================================
USE master;
GO

SET NOCOUNT ON;

-- ----------------------------------------------------------------------
-- Parametros (AJUSTAR @ruta_backup si tu carpeta es otra)
-- ----------------------------------------------------------------------
DECLARE @ruta_backup       NVARCHAR(500) = N'C:\Backups\';
DECLARE @nombre_bd         NVARCHAR(128) = N'SECOP_DWH';
DECLARE @fecha_tag         NVARCHAR(20)  = REPLACE(REPLACE(CONVERT(VARCHAR(19), SYSDATETIME(), 120), ':', ''), ' ', '_');
DECLARE @archivo_backup    NVARCHAR(500);
DECLARE @t                 DATETIME2 = SYSDATETIME();

SET @archivo_backup = @ruta_backup + @nombre_bd + N'_V8_FINAL_' + @fecha_tag + N'.bak';

PRINT '======================================';
PRINT 'PASO 8: Backup final SECOP_DWH V8';
PRINT 'Inicio: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT 'Destino: ' + @archivo_backup;
PRINT '======================================';

-- ----------------------------------------------------------------------
-- (1) Asegurar carpeta destino (xp_create_subdir es idempotente)
-- ----------------------------------------------------------------------
EXEC master.dbo.xp_create_subdir @ruta_backup;
PRINT '[1] Carpeta destino OK';

-- ----------------------------------------------------------------------
-- (2) Crear tabla de gobierno de backups si no existe
-- ----------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'meta')
    EXEC SECOP_DWH..sp_executesql N'EXEC(''CREATE SCHEMA meta AUTHORIZATION dbo'')';

IF OBJECT_ID('SECOP_DWH.meta.backups', 'U') IS NULL
BEGIN
    EXEC SECOP_DWH..sp_executesql N'
        CREATE TABLE meta.backups (
            sk_backup         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
            fecha_backup      DATETIME2         NOT NULL DEFAULT SYSDATETIME(),
            tipo              VARCHAR(20)       NOT NULL,
            nombre_bd         NVARCHAR(128)     NOT NULL,
            ruta_archivo      NVARCHAR(500)     NOT NULL,
            tamano_mb         DECIMAL(12,2)     NULL,
            duracion_seg      INT               NULL,
            ratio_compresion  DECIMAL(6,2)      NULL,
            checksum_ok       BIT               NULL,
            verify_ok         BIT               NULL,
            notas             NVARCHAR(500)     NULL
        );';
    PRINT '[2] meta.backups creada';
END
ELSE
    PRINT '[2] meta.backups ya existe';

-- ----------------------------------------------------------------------
-- (3) Ejecutar backup con compresion y checksum
-- ----------------------------------------------------------------------
PRINT '[3] Iniciando BACKUP DATABASE (puede tardar 5-15 minutos)...';

BACKUP DATABASE @nombre_bd
TO DISK = @archivo_backup
WITH  COMPRESSION,
      CHECKSUM,
      INIT,
      FORMAT,
      STATS = 10,
      NAME  = N'SECOP_DWH V8 Final - Tesis Especializacion Gobierno de Datos UAN 2026',
      DESCRIPTION = N'Backup final V8 con 7.7M procesos, 8 indicadores, agregaciones PBI y metricas DAMA';

DECLARE @duracion_seg INT = DATEDIFF(SECOND, @t, SYSDATETIME());
PRINT '[3] BACKUP completado en ' + CAST(@duracion_seg AS VARCHAR) + ' segundos';

-- ----------------------------------------------------------------------
-- (4) Verificar integridad del archivo .bak (RESTORE VERIFYONLY)
-- ----------------------------------------------------------------------
PRINT '[4] Verificando integridad del archivo...';

DECLARE @verify_ok BIT = 0;
BEGIN TRY
    RESTORE VERIFYONLY FROM DISK = @archivo_backup WITH CHECKSUM;
    SET @verify_ok = 1;
    PRINT '[4] RESTORE VERIFYONLY: archivo .bak integro y restaurable';
END TRY
BEGIN CATCH
    SET @verify_ok = 0;
    PRINT '[4] ERROR en verificacion: ' + ERROR_MESSAGE();
END CATCH;

-- ----------------------------------------------------------------------
-- (5) Obtener metadatos del backup recien creado
-- ----------------------------------------------------------------------
DECLARE @tamano_mb DECIMAL(12,2);

SELECT TOP 1
        @tamano_mb = CAST(backup_size / 1024.0 / 1024.0 AS DECIMAL(12,2))
FROM    msdb.dbo.backupset
WHERE   database_name = @nombre_bd
  AND   type = 'D'
ORDER BY backup_finish_date DESC;

DECLARE @ratio DECIMAL(6,2);
SELECT TOP 1
        @ratio = CAST(1.0 * backup_size / NULLIF(compressed_backup_size, 0) AS DECIMAL(6,2))
FROM    msdb.dbo.backupset
WHERE   database_name = @nombre_bd
  AND   type = 'D'
ORDER BY backup_finish_date DESC;

-- ----------------------------------------------------------------------
-- (6) Registrar backup en meta.backups (tabla de gobierno)
-- ----------------------------------------------------------------------
EXEC SECOP_DWH..sp_executesql
    N'INSERT INTO meta.backups
        (tipo, nombre_bd, ruta_archivo, tamano_mb, duracion_seg, ratio_compresion, checksum_ok, verify_ok, notas)
      VALUES
        (@tipo, @bd, @ruta, @tam, @dur, @ratio, 1, @ver, @notas)',
    N'@tipo VARCHAR(20), @bd NVARCHAR(128), @ruta NVARCHAR(500), @tam DECIMAL(12,2),
      @dur INT, @ratio DECIMAL(6,2), @ver BIT, @notas NVARCHAR(500)',
    @tipo = 'FULL',
    @bd = @nombre_bd,
    @ruta = @archivo_backup,
    @tam = @tamano_mb,
    @dur = @duracion_seg,
    @ratio = @ratio,
    @ver = @verify_ok,
    @notas = N'Backup final V8 post-Paso 7. Estado: 7.7M procesos, 8 indicadores, 5 agg PBI, 21 metricas calidad';

PRINT '[6] Registrado en meta.backups';

-- ----------------------------------------------------------------------
-- (7) Resumen ejecutivo
-- ----------------------------------------------------------------------
PRINT '';
PRINT '======================================';
PRINT 'PASO 8 COMPLETADO';
PRINT 'Tamano: ' + CAST(@tamano_mb AS VARCHAR) + ' MB';
PRINT 'Duracion: ' + CAST(@duracion_seg AS VARCHAR) + ' segundos';
PRINT 'Ratio compresion: ' + CAST(@ratio AS VARCHAR) + 'x';
PRINT 'Verificacion: ' + CASE WHEN @verify_ok = 1 THEN 'OK' ELSE 'FALLO' END;
PRINT 'Fin: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';
PRINT '';
PRINT 'Archivo: ' + @archivo_backup;
GO

-- ----------------------------------------------------------------------
-- (8) Verificacion: ultimos 5 backups registrados
-- ----------------------------------------------------------------------
USE SECOP_DWH;
GO

PRINT '';
PRINT '--- (8a) Inventario: ultimos 5 backups registrados ---';
SELECT TOP 5
        sk_backup, fecha_backup, tipo, nombre_bd,
        tamano_mb, duracion_seg, ratio_compresion, verify_ok,
        ruta_archivo
FROM    meta.backups
ORDER BY fecha_backup DESC;

PRINT '';
PRINT '--- (8b) Inventario fisico del .bak ---';
SELECT TOP 5
        bs.database_name,
        bs.backup_start_date,
        bs.backup_finish_date,
        DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS duracion_seg,
        CAST(bs.backup_size / 1024.0 / 1024.0 AS DECIMAL(12,2))       AS tamano_original_mb,
        CAST(bs.compressed_backup_size / 1024.0 / 1024.0 AS DECIMAL(12,2)) AS tamano_comprimido_mb,
        CAST(1.0 * bs.backup_size / NULLIF(bs.compressed_backup_size, 0) AS DECIMAL(6,2)) AS ratio,
        bmf.physical_device_name
FROM    msdb.dbo.backupset bs
JOIN    msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE   bs.database_name = 'SECOP_DWH'
ORDER BY bs.backup_finish_date DESC;

PRINT '';
PRINT '======================================';
PRINT 'SOLUCION V8 COMPLETA';
PRINT '======================================';
GO

/* ============================================================================
   PROCEDIMIENTO DE RESTORE (documentacion para Anexo de la tesis)
   ============================================================================
   Para restaurar este backup en otra instancia de SQL Server 2022+:

   USE master;
   GO

   -- 1) Si la base existe, ponerla en single user para forzar el restore
   ALTER DATABASE SECOP_DWH SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

   -- 2) Restaurar (ajustar la ruta segun donde quede el .bak)
   RESTORE DATABASE SECOP_DWH
   FROM DISK = N'C:\Backups\SECOP_DWH_V8_FINAL_YYYY-MM-DD_HHMMSS.bak'
   WITH  REPLACE,
         RECOVERY,
         STATS = 10,
         CHECKSUM;

   -- 3) Volver a multi user
   ALTER DATABASE SECOP_DWH SET MULTI_USER;

   -- 4) Verificar
   USE SECOP_DWH;
   SELECT 'fact_contratacion', COUNT_BIG(*) FROM dwh.fact_contratacion
   UNION ALL SELECT 'riesgo_corrupcion', COUNT_BIG(*) FROM ind.riesgo_corrupcion
   UNION ALL SELECT 'calidad_dimensiones', COUNT_BIG(*) FROM meta.calidad_dimensiones;
   ============================================================================ */

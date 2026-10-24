-- ============================================================================
-- 02_crear_dimensiones_y_fact.sql
-- Crea las 4 dimensiones y la tabla de hechos del modelo estrella Kimball.
--
-- Tablas creadas:
--   dwh.dim_entidad      (entidades contratantes del Estado)
--   dwh.dim_proveedor    (personas naturales y juridicas adjudicatarias)
--   dwh.dim_modalidad    (tipos de contratacion)
--   dwh.dim_tiempo       (calendario 2018-2030, 4748 dias)
--   dwh.fact_contratacion (procesos contractuales, ~7.7M filas esperadas)
--   staging.secop_ii_procesos (zona de aterrizaje API)
--
-- Tiempo: < 10 segundos
-- ============================================================================
USE SECOP_DWH;
GO

SET NOCOUNT ON;

-- ----------------------------------------------------------------------
-- STAGING: tabla de aterrizaje desde API
-- ----------------------------------------------------------------------
IF OBJECT_ID('staging.secop_ii_procesos', 'U') IS NULL
BEGIN
    CREATE TABLE staging.secop_ii_procesos (
        sk_staging                            BIGINT IDENTITY(1,1) NOT NULL,
        id_del_proceso                        NVARCHAR(MAX) NULL,
        nit_entidad                           NVARCHAR(50)  NULL,
        nombre_entidad                        NVARCHAR(500) NULL,
        departamento_entidad                  NVARCHAR(100) NULL,
        ciudad_entidad                        NVARCHAR(200) NULL,
        orden_entidad                         NVARCHAR(50)  NULL,
        modalidad_de_contratacion             NVARCHAR(200) NULL,
        nit_del_proveedor_adjudicado          NVARCHAR(50)  NULL,
        nombre_del_proveedor_adjudicado       NVARCHAR(500) NULL,
        fecha_de_publicacion_del              DATE          NULL,
        fecha_adjudicacion                    DATETIME      NULL,
        precio_base                           DECIMAL(20,2) NULL,
        valor_total_adjudicacion              DECIMAL(20,2) NULL,
        conteo_de_respuestas_a_ofertas        INT           NULL,
        estado_del_procedimiento              NVARCHAR(100) NULL,
        fecha_ingesta                         DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
        CONSTRAINT PK_staging_secop_ii PRIMARY KEY (sk_staging)
    );
    CREATE INDEX IX_stg_idproceso ON staging.secop_ii_procesos(fecha_ingesta);
    PRINT 'CREATED staging.secop_ii_procesos';
END
GO

-- ----------------------------------------------------------------------
-- DIM_ENTIDAD
-- ----------------------------------------------------------------------
IF OBJECT_ID('dwh.dim_entidad', 'U') IS NULL
BEGIN
    CREATE TABLE dwh.dim_entidad (
        sk_entidad      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        nit             NVARCHAR(50)  NOT NULL UNIQUE,
        nombre          NVARCHAR(500) NOT NULL,
        departamento    NVARCHAR(100) NULL,
        ciudad          NVARCHAR(200) NULL,
        orden           NVARCHAR(50)  NULL
    );
    PRINT 'CREATED dwh.dim_entidad';
END
GO

-- ----------------------------------------------------------------------
-- DIM_PROVEEDOR
-- ----------------------------------------------------------------------
IF OBJECT_ID('dwh.dim_proveedor', 'U') IS NULL
BEGIN
    CREATE TABLE dwh.dim_proveedor (
        sk_proveedor    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        documento       NVARCHAR(50)  NOT NULL UNIQUE,
        nombre          NVARCHAR(500) NOT NULL
    );
    PRINT 'CREATED dwh.dim_proveedor';
END
GO

-- ----------------------------------------------------------------------
-- DIM_MODALIDAD
-- ----------------------------------------------------------------------
IF OBJECT_ID('dwh.dim_modalidad', 'U') IS NULL
BEGIN
    CREATE TABLE dwh.dim_modalidad (
        sk_modalidad    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        nombre          NVARCHAR(200) NOT NULL UNIQUE,
        es_competitiva  BIT NOT NULL DEFAULT 0
    );
    PRINT 'CREATED dwh.dim_modalidad';
END
GO

-- ----------------------------------------------------------------------
-- DIM_TIEMPO (sk_tiempo = YYYYMMDD; dia_semana TINYINT 1-7)
-- ----------------------------------------------------------------------
IF OBJECT_ID('dwh.dim_tiempo', 'U') IS NULL
BEGIN
    CREATE TABLE dwh.dim_tiempo (
        sk_tiempo       INT NOT NULL PRIMARY KEY,    -- AAAAMMDD
        fecha           DATE NOT NULL UNIQUE,
        anio            SMALLINT NOT NULL,
        trimestre       TINYINT  NOT NULL,
        mes             TINYINT  NOT NULL,
        nombre_mes      NVARCHAR(20) NOT NULL,
        dia             TINYINT  NOT NULL,
        dia_semana      TINYINT  NOT NULL              -- DATEPART(WEEKDAY): 1=Dom, 7=Sab (DATEFIRST 7)
    );
    PRINT 'CREATED dwh.dim_tiempo';
END
GO

-- ----------------------------------------------------------------------
-- FACT_CONTRATACION (sin columnas fantasma, alineada al API)
-- ----------------------------------------------------------------------
IF OBJECT_ID('dwh.fact_contratacion', 'U') IS NULL
BEGIN
    CREATE TABLE dwh.fact_contratacion (
        sk_fact             BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        id_proceso          NVARCHAR(200) NOT NULL UNIQUE,
        sk_entidad          INT NOT NULL,
        sk_proveedor        INT NULL,
        sk_modalidad        INT NOT NULL,
        sk_t_publicacion    INT NULL,
        sk_t_adjudicacion   INT NULL,
        precio_base         DECIMAL(20,2) NULL,
        valor_adjudicado    DECIMAL(20,2) NULL,
        n_oferentes         INT NULL,
        estado              NVARCHAR(100) NULL,
        CONSTRAINT FK_fc_entidad   FOREIGN KEY (sk_entidad)        REFERENCES dwh.dim_entidad(sk_entidad),
        CONSTRAINT FK_fc_proveedor FOREIGN KEY (sk_proveedor)      REFERENCES dwh.dim_proveedor(sk_proveedor),
        CONSTRAINT FK_fc_modalidad FOREIGN KEY (sk_modalidad)      REFERENCES dwh.dim_modalidad(sk_modalidad),
        CONSTRAINT FK_fc_tpub      FOREIGN KEY (sk_t_publicacion)  REFERENCES dwh.dim_tiempo(sk_tiempo),
        CONSTRAINT FK_fc_tadj      FOREIGN KEY (sk_t_adjudicacion) REFERENCES dwh.dim_tiempo(sk_tiempo)
    );
    CREATE INDEX IX_fc_entidad   ON dwh.fact_contratacion(sk_entidad);
    CREATE INDEX IX_fc_modalidad ON dwh.fact_contratacion(sk_modalidad);
    CREATE INDEX IX_fc_tpub      ON dwh.fact_contratacion(sk_t_publicacion);
    PRINT 'CREATED dwh.fact_contratacion';
END
GO

PRINT '';
PRINT '======================================';
PRINT 'Schemas + tablas creados correctamente';
PRINT '======================================';
GO

-- Verificacion
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('staging','dwh')
ORDER BY TABLE_SCHEMA, TABLE_NAME;

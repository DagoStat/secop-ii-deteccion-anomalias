-- ============================================================================
-- 09_seguridad_rls_ddm.sql
-- Paso 9: Seguridad operativa de la solucion.
--
-- Implementa los tres pilares de proteccion de datos personales sobre el DWH:
--   (1) meta.clasificacion_sensibilidad     -- catalogo de columnas etiquetadas
--   (2) DDM (Dynamic Data Masking)          -- enmascaramiento por columna
--   (3) RLS (Row Level Security)            -- filtrado por rol del usuario
--
-- Marco legal: Articulo 29 Constitucion Politica de Colombia,
--              Ley 1581 de 2012 (proteccion de datos personales),
--              Ley 1712 de 2014 (transparencia y acceso a informacion publica).
--
-- Cada control se aplica de forma idempotente: el script se puede re-ejecutar
-- y dejara el sistema en el mismo estado final.
--
-- Estimacion: 30-60 segundos (solo DDL).
-- ============================================================================
USE SECOP_DWH;
GO

SET NOCOUNT ON;

PRINT '======================================';
PRINT 'PASO 9: Seguridad operativa (RLS + DDM)';
PRINT 'Inicio: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';
GO

-- ----------------------------------------------------------------------
-- (1) Schema sec para funciones y politicas de seguridad
-- ----------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'sec')
    EXEC('CREATE SCHEMA sec AUTHORIZATION dbo');
GO
PRINT '[1] Schema sec listo';
GO

-- ----------------------------------------------------------------------
-- (2) Tabla de gobierno: meta.clasificacion_sensibilidad
-- ----------------------------------------------------------------------
IF OBJECT_ID('meta.clasificacion_sensibilidad', 'U') IS NOT NULL
    DROP TABLE meta.clasificacion_sensibilidad;

CREATE TABLE meta.clasificacion_sensibilidad (
    sk_clasif           INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    schema_objeto       VARCHAR(50)       NOT NULL,
    nombre_objeto       VARCHAR(128)      NOT NULL,
    nombre_columna      VARCHAR(128)      NOT NULL,
    nivel_sensibilidad  VARCHAR(20)       NOT NULL
        CONSTRAINT CK_nivel CHECK (nivel_sensibilidad IN
            ('PUBLICO', 'INTERNO', 'RESTRINGIDO', 'CONFIDENCIAL')),
    base_legal          NVARCHAR(300)     NULL,
    identifica_persona  BIT               NOT NULL DEFAULT 0,
    requiere_mascara    BIT               NOT NULL DEFAULT 0,
    tipo_mascara        VARCHAR(50)       NULL,
    fecha_clasificacion DATETIME2         NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_columna UNIQUE (schema_objeto, nombre_objeto, nombre_columna)
);
GO

PRINT '[2] Tabla meta.clasificacion_sensibilidad creada';
GO

-- Poblar el catalogo con las 22 columnas criticas del modelo
INSERT INTO meta.clasificacion_sensibilidad
    (schema_objeto, nombre_objeto, nombre_columna,
     nivel_sensibilidad, base_legal, identifica_persona, requiere_mascara, tipo_mascara)
VALUES
    -- DIM_ENTIDAD (publico segun Ley 1712/2014, transparencia activa)
    ('dwh', 'dim_entidad', 'nit',                'PUBLICO',
     'Ley 1712 de 2014 - Transparencia activa', 0, 0, NULL),
    ('dwh', 'dim_entidad', 'nombre',             'PUBLICO',
     'Ley 1712 de 2014 - Transparencia activa', 0, 0, NULL),
    ('dwh', 'dim_entidad', 'departamento',       'PUBLICO',
     'Ley 1712 de 2014 - Transparencia activa', 0, 0, NULL),
    ('dwh', 'dim_entidad', 'ciudad',             'PUBLICO',
     'Ley 1712 de 2014 - Transparencia activa', 0, 0, NULL),
    ('dwh', 'dim_entidad', 'orden',              'PUBLICO',
     'Ley 1712 de 2014 - Transparencia activa', 0, 0, NULL),

    -- DIM_PROVEEDOR (datos personales si es persona natural - Ley 1581/2012)
    ('dwh', 'dim_proveedor', 'nit',              'RESTRINGIDO',
     'Ley 1581 de 2012 art. 6 - Dato semiprivado', 1, 1, 'partial(2,"XXXXXX",2)'),
    ('dwh', 'dim_proveedor', 'nombre',           'RESTRINGIDO',
     'Ley 1581 de 2012 art. 6 - Dato semiprivado', 1, 1, 'partial(2,"XXX",2)'),
    ('dwh', 'dim_proveedor', 'departamento',     'PUBLICO',
     'Ley 1712 de 2014 - Transparencia activa', 0, 0, NULL),
    ('dwh', 'dim_proveedor', 'ciudad',           'PUBLICO',
     'Ley 1712 de 2014 - Transparencia activa', 0, 0, NULL),

    -- DIM_MODALIDAD (publico)
    ('dwh', 'dim_modalidad', 'nombre',           'PUBLICO',
     'Ley 1712 de 2014', 0, 0, NULL),

    -- FACT_CONTRATACION (montos publicos por transparencia activa)
    ('dwh', 'fact_contratacion', 'id_proceso',   'PUBLICO',
     'Ley 1712 de 2014', 0, 0, NULL),
    ('dwh', 'fact_contratacion', 'valor_adjudicado', 'PUBLICO',
     'Ley 1712 de 2014 - Transparencia activa', 0, 0, NULL),
    ('dwh', 'fact_contratacion', 'precio_base',  'PUBLICO',
     'Ley 1712 de 2014', 0, 0, NULL),
    ('dwh', 'fact_contratacion', 'n_oferentes',  'PUBLICO',
     'Ley 1712 de 2014', 0, 0, NULL),

    -- INDICADORES Y RIESGO (restringido - juicio implicito)
    ('ind', 'alertas_proceso', 'codigo_anomalia', 'INTERNO',
     'Articulo 29 CP - Presuncion de inocencia', 0, 0, NULL),
    ('ind', 'alertas_proceso', 'puntos',          'INTERNO',
     'Articulo 29 CP - Presuncion de inocencia', 0, 0, NULL),
    ('ind', 'riesgo_corrupcion', 'nivel_riesgo',  'RESTRINGIDO',
     'Articulo 29 CP - Presuncion de inocencia + Ley 1581 de 2012', 0, 0, NULL),
    ('ind', 'riesgo_corrupcion', 'puntos_totales', 'RESTRINGIDO',
     'Articulo 29 CP - Presuncion de inocencia', 0, 0, NULL),

    -- STAGING (raw data - identificadores naturales)
    ('staging', 'secop_ii_procesos', 'nombre_del_proveedor_adjudicado', 'RESTRINGIDO',
     'Ley 1581 de 2012', 1, 1, 'partial(2,"XXX",2)'),
    ('staging', 'secop_ii_procesos', 'nit_del_proveedor_adjudicado',   'RESTRINGIDO',
     'Ley 1581 de 2012', 1, 1, 'partial(3,"XXXXX",2)'),
    ('staging', 'secop_ii_procesos', 'nombre_del_adjudicador',         'CONFIDENCIAL',
     'Ley 1581 de 2012 + Ley 1266 de 2008', 1, 1, 'default()'),
    ('staging', 'secop_ii_procesos', 'ciudad_proveedor',               'INTERNO',
     'Ley 1581 de 2012 art. 5', 1, 0, NULL);

PRINT '[2] Catalogo poblado con ' + CAST(@@ROWCOUNT AS VARCHAR) + ' columnas clasificadas';
GO

-- ----------------------------------------------------------------------
-- (3) Roles operativos
-- ----------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID('rol_auditor') IS NULL
    CREATE ROLE rol_auditor          AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID('rol_analista_publico') IS NULL
    CREATE ROLE rol_analista_publico AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID('rol_ciudadano') IS NULL
    CREATE ROLE rol_ciudadano        AUTHORIZATION dbo;

PRINT '[3] Roles creados: rol_auditor, rol_analista_publico, rol_ciudadano';
GO

-- Permisos basicos
GRANT SELECT ON SCHEMA::pbi TO rol_auditor;
GRANT SELECT ON SCHEMA::pbi TO rol_analista_publico;
GRANT SELECT ON SCHEMA::pbi TO rol_ciudadano;

GRANT SELECT ON SCHEMA::dwh  TO rol_auditor;
GRANT SELECT ON SCHEMA::dwh  TO rol_analista_publico;
GRANT SELECT ON SCHEMA::dwh  TO rol_ciudadano;

GRANT SELECT ON SCHEMA::ind  TO rol_auditor;
GRANT SELECT ON SCHEMA::ind  TO rol_analista_publico;
-- rol_ciudadano NO puede leer ind directamente (solo agregados pbi)
DENY SELECT ON SCHEMA::ind TO rol_ciudadano;

GRANT SELECT ON SCHEMA::meta TO rol_auditor;
DENY  SELECT ON SCHEMA::meta TO rol_analista_publico;
DENY  SELECT ON SCHEMA::meta TO rol_ciudadano;

PRINT '[3] Permisos por schema otorgados';
GO

-- ----------------------------------------------------------------------
-- (4) DYNAMIC DATA MASKING - enmascaramiento por columna
-- ----------------------------------------------------------------------
-- Las mascaras solo afectan a usuarios SIN permiso UNMASK.
-- rol_auditor recibira UNMASK al final del bloque.

PRINT '[4] Aplicando Dynamic Data Masking...';

-- dwh.dim_proveedor.nombre
IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
               JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
               WHERE OBJECT_NAME(mc.object_id) = 'dim_proveedor' AND c.name = 'nombre')
BEGIN
    ALTER TABLE dwh.dim_proveedor
    ALTER COLUMN nombre ADD MASKED WITH (FUNCTION = 'partial(2,"XXX",2)');
    PRINT '   - dwh.dim_proveedor.nombre enmascarada';
END

-- dwh.dim_proveedor.nit
IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
               JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
               WHERE OBJECT_NAME(mc.object_id) = 'dim_proveedor' AND c.name = 'nit')
BEGIN
    ALTER TABLE dwh.dim_proveedor
    ALTER COLUMN nit ADD MASKED WITH (FUNCTION = 'partial(3,"XXXXX",2)');
    PRINT '   - dwh.dim_proveedor.nit enmascarado';
END

-- staging.secop_ii_procesos.nombre_del_proveedor_adjudicado
IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
               JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
               WHERE OBJECT_NAME(mc.object_id) = 'secop_ii_procesos' AND c.name = 'nombre_del_proveedor_adjudicado')
BEGIN
    ALTER TABLE staging.secop_ii_procesos
    ALTER COLUMN nombre_del_proveedor_adjudicado NVARCHAR(500) MASKED WITH (FUNCTION = 'partial(2,"XXX",2)');
    PRINT '   - staging.secop_ii_procesos.nombre_del_proveedor_adjudicado enmascarado';
END

-- staging.secop_ii_procesos.nit_del_proveedor_adjudicado
IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
               JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
               WHERE OBJECT_NAME(mc.object_id) = 'secop_ii_procesos' AND c.name = 'nit_del_proveedor_adjudicado')
BEGIN
    ALTER TABLE staging.secop_ii_procesos
    ALTER COLUMN nit_del_proveedor_adjudicado NVARCHAR(100) MASKED WITH (FUNCTION = 'partial(3,"XXXXX",2)');
    PRINT '   - staging.secop_ii_procesos.nit_del_proveedor_adjudicado enmascarado';
END

-- staging.secop_ii_procesos.nombre_del_adjudicador (CONFIDENCIAL = default)
IF NOT EXISTS (SELECT 1 FROM sys.masked_columns mc
               JOIN sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
               WHERE OBJECT_NAME(mc.object_id) = 'secop_ii_procesos' AND c.name = 'nombre_del_adjudicador')
BEGIN
    ALTER TABLE staging.secop_ii_procesos
    ALTER COLUMN nombre_del_adjudicador NVARCHAR(500) MASKED WITH (FUNCTION = 'default()');
    PRINT '   - staging.secop_ii_procesos.nombre_del_adjudicador enmascarado (default - mas estricto)';
END

-- UNMASK para rol_auditor (puede ver datos reales)
GRANT UNMASK TO rol_auditor;

PRINT '[4] DDM aplicado a 5 columnas + UNMASK otorgado a rol_auditor';
GO

-- ----------------------------------------------------------------------
-- (5) ROW LEVEL SECURITY - filtro por nivel de riesgo
-- ----------------------------------------------------------------------
-- Politica: ciudadanos solo ven SIN RIESGO + BAJO (agregados);
--           analistas publicos ven SIN RIESGO + BAJO + MEDIO;
--           auditores ven todo (incluye ALTO).
-- ----------------------------------------------------------------------

-- Eliminar politica previa si existe (idempotencia)
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'pol_riesgo_por_rol')
BEGIN
    ALTER SECURITY POLICY sec.pol_riesgo_por_rol WITH (STATE = OFF);
    DROP SECURITY POLICY sec.pol_riesgo_por_rol;
END

IF OBJECT_ID('sec.fn_filtro_riesgo', 'IF') IS NOT NULL
    DROP FUNCTION sec.fn_filtro_riesgo;
GO

-- Funcion de predicado
CREATE FUNCTION sec.fn_filtro_riesgo(@nivel_riesgo VARCHAR(20))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS fn_securitypredicate_result
    WHERE
        -- Administrador siempre ve todo
        IS_MEMBER('db_owner') = 1
        -- Auditor ve todo
        OR IS_ROLEMEMBER('rol_auditor') = 1
        -- Analista publico ve hasta MEDIO
        OR (IS_ROLEMEMBER('rol_analista_publico') = 1 AND @nivel_riesgo IN ('SIN RIESGO','BAJO','MEDIO'))
        -- Ciudadano solo ve SIN RIESGO y BAJO
        OR (IS_ROLEMEMBER('rol_ciudadano') = 1 AND @nivel_riesgo IN ('SIN RIESGO','BAJO'));
GO

-- Aplicar Security Policy sobre ind.riesgo_corrupcion
CREATE SECURITY POLICY sec.pol_riesgo_por_rol
ADD FILTER PREDICATE sec.fn_filtro_riesgo(nivel_riesgo) ON ind.riesgo_corrupcion
WITH (STATE = ON);
GO

PRINT '[5] RLS activo en ind.riesgo_corrupcion (sec.pol_riesgo_por_rol)';
GO

-- ----------------------------------------------------------------------
-- (6) Bitacora del cambio en meta.audit_seguridad
-- ----------------------------------------------------------------------
IF OBJECT_ID('meta.audit_seguridad', 'U') IS NULL
BEGIN
    CREATE TABLE meta.audit_seguridad (
        sk INT IDENTITY(1,1) PRIMARY KEY,
        fecha DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
        accion VARCHAR(100) NOT NULL,
        objeto VARCHAR(200) NOT NULL,
        detalle NVARCHAR(500) NULL,
        ejecutor SYSNAME NOT NULL DEFAULT SUSER_SNAME()
    );
END

INSERT INTO meta.audit_seguridad (accion, objeto, detalle)
VALUES
    ('CREATE_SCHEMA',     'sec',                          'Schema para funciones y politicas de seguridad'),
    ('CREATE_TABLE',      'meta.clasificacion_sensibilidad','22 columnas clasificadas en 4 niveles'),
    ('CREATE_ROLES',      'rol_auditor/rol_analista_publico/rol_ciudadano', 'Tres roles operativos'),
    ('DDM_APPLIED',       'dwh.dim_proveedor (nombre,nit) + staging.secop_ii_procesos (3 cols)',
                          'Enmascaramiento dinamico activo'),
    ('RLS_APPLIED',       'ind.riesgo_corrupcion',         'Filtro por nivel_riesgo segun rol'),
    ('UNMASK_GRANTED',    'rol_auditor',                   'Auditor puede leer datos reales');

PRINT '[6] Bitacora meta.audit_seguridad actualizada';
GO

PRINT '';
PRINT '======================================';
PRINT 'PASO 9 COMPLETADO';
PRINT 'Fin: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';
PRINT 'Controles activos:';
PRINT '  meta.clasificacion_sensibilidad : 22 columnas clasificadas';
PRINT '  Dynamic Data Masking            : 5 columnas con mascara aplicada';
PRINT '  Row Level Security              : ind.riesgo_corrupcion filtrado por rol';
PRINT '  Roles                           : 3 roles operativos (auditor, analista, ciudadano)';
PRINT '======================================';
GO

-- ----------------------------------------------------------------------
-- (7) VERIFICACION
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (7a) Inventario de columnas clasificadas ---';
SELECT  nivel_sensibilidad,
        COUNT(*) AS columnas
FROM    meta.clasificacion_sensibilidad
GROUP BY nivel_sensibilidad
ORDER BY CASE nivel_sensibilidad
            WHEN 'PUBLICO'      THEN 1
            WHEN 'INTERNO'      THEN 2
            WHEN 'RESTRINGIDO'  THEN 3
            WHEN 'CONFIDENCIAL' THEN 4
         END;

PRINT '';
PRINT '--- (7b) Columnas enmascaradas activas ---';
SELECT  s.name              AS [schema],
        OBJECT_NAME(mc.object_id) AS tabla,
        c.name              AS columna,
        mc.masking_function AS funcion_mascara
FROM    sys.masked_columns mc
JOIN    sys.columns c ON c.object_id = mc.object_id AND c.column_id = mc.column_id
JOIN    sys.objects o ON o.object_id = mc.object_id
JOIN    sys.schemas s ON s.schema_id = o.schema_id
ORDER BY [schema], tabla, columna;

PRINT '';
PRINT '--- (7c) Politicas RLS activas ---';
SELECT  sp.name              AS politica,
        sp.is_enabled        AS habilitada,
        OBJECT_NAME(sp.policy_schema_id) AS schema_politica,
        OBJECT_SCHEMA_NAME(spd.target_object_id) + '.' + OBJECT_NAME(spd.target_object_id) AS objeto_protegido,
        OBJECT_SCHEMA_NAME(spd.predicate_function_id) + '.' + OBJECT_NAME(spd.predicate_function_id) AS funcion_predicado
FROM    sys.security_policies sp
JOIN    sys.security_predicates spd ON spd.object_id = sp.object_id;

PRINT '';
PRINT '--- (7d) Roles y permisos resumidos ---';
SELECT  dp.name AS rol,
        dp.type_desc,
        dp.create_date
FROM    sys.database_principals dp
WHERE   dp.name IN ('rol_auditor','rol_analista_publico','rol_ciudadano')
ORDER BY dp.name;

GO

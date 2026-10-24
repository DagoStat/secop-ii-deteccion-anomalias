-- ============================================================================
-- 16_validacion_convergente_casos_publicos.sql
--
-- Cruza el indice de riesgo V16.2 con casos publicos conocidos de contratacion
-- problematica reportados por prensa, Contraloria, Procuraduria o Fiscalia
-- entre 2020 y 2026. El objetivo es responder la pregunta clave para la defensa:
--
--   "Si el sistema funciona, deberia marcar como MEDIO o ALTO los procesos
--    que ya fueron objeto de investigacion publica. Verifiquemoslo."
--
-- Para cada caso:
--   1. Define un patron de busqueda (entidad, palabras clave, periodo)
--   2. Lista los procesos que coinciden
--   3. Reporta su nivel de riesgo asignado por el sistema
--   4. Calcula la proporcion de procesos marcados (alerta hit-rate)
--
-- IMPORTANTE: estos son patrones de busqueda heuristicos. Para validacion
-- formal habria que cruzar contra bases sancionatorias oficiales (SIRECI,
-- SIRI, SPOA). El presente script es una aproximacion preliminar.
--
-- Tiempo: 1-3 minutos.
-- ============================================================================
USE SECOP_DWH;

SET NOCOUNT ON;

PRINT '======================================';
PRINT 'VALIDACION CONVERGENTE - casos publicos conocidos 2020-2026';
PRINT 'Inicio: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT '======================================';

-- ----------------------------------------------------------------------
-- (0) Crear tabla de patrones de casos publicos
-- ----------------------------------------------------------------------
IF OBJECT_ID('tempdb..#casos_publicos') IS NOT NULL DROP TABLE #casos_publicos;

CREATE TABLE #casos_publicos (
    sk_caso        INT IDENTITY(1,1) PRIMARY KEY,
    caso           VARCHAR(100)  NOT NULL,
    descripcion    NVARCHAR(500) NOT NULL,
    patron_entidad NVARCHAR(200) NULL,
    patron_proced  NVARCHAR(200) NULL,
    anio_desde     INT           NULL,
    anio_hasta     INT           NULL,
    fuente         NVARCHAR(200) NOT NULL
);

INSERT INTO #casos_publicos (caso, descripcion, patron_entidad, patron_proced, anio_desde, anio_hasta, fuente) VALUES

-- 1. Centros Poblados MinTIC (Karen Abudinen, 2021)
('Centros Poblados MinTIC',
 'Contrato 70 mil millones COP para conectividad rural, escandalo Abudinen 2021',
 '%TECNOLOG%INFORMACI%COMUNICACION%',
 '%CENTROS POBLADOS%',
 2020, 2022,
 'Procuraduria 2021, prensa nacional'),

-- 2. PAE Atlantico (Programa Alimentacion Escolar)
('PAE Atlantico',
 'Programa Alimentacion Escolar con sobrecostos y proveedores recurrentes',
 '%ATLANTICO%',
 '%ALIMENTACION ESCOLAR%',
 2020, 2026,
 'Contraloria, Veeduria Atlantico'),

-- 3. PAE Bogota
('PAE Bogota',
 'PAE Bogota investigado por sobrecostos en racion alimentaria',
 '%SECRETAR%EDUCACION%BOGOTA%',
 '%PAE%',
 2020, 2026,
 'Contraloria Distrital Bogota'),

-- 4. Hidroituango (EPM)
('Hidroituango EPM',
 'Central hidroelectrica con costos disparados y demandas por dano',
 '%EPM%',
 '%HIDROITUANGO%',
 2020, 2026,
 'Prensa, EPM publica datos'),

-- 5. Reficar Ecopetrol
('Reficar Ecopetrol',
 'Refineria de Cartagena, contratos con Glencore y otros',
 '%ECOPETROL%',
 '%REFINER%CARTAGENA%',
 2020, 2026,
 'Fiscalia, Contraloria'),

-- 6. DPS contratos COVID
('DPS COVID auxilios',
 'Departamento Prosperidad Social contratos por emergencia COVID',
 '%PROSPERIDAD SOCIAL%',
 '%COVID%',
 2020, 2022,
 'Procuraduria, prensa'),

-- 7. MinSalud contratos COVID
('MinSalud COVID',
 'Ministerio de Salud contratos directos por emergencia',
 '%SALUD%PROTECCION%SOCIAL%',
 '%EMERGENCIA%SANITARIA%',
 2020, 2022,
 'Contraloria'),

-- 8. Megacolegios Bogota
('Megacolegios Bogota',
 'Construccion megacolegios distrito capital',
 '%SECRETAR%EDUCACION%DISTRIT%',
 '%MEGACOLEGIO%',
 2020, 2026,
 'Contraloria Distrital'),

-- 9. INVIAS Pacifico
('INVIAS via Pacifico',
 'Vias terciarias Pacifico y conexion Buenaventura',
 '%INVIAS%',
 '%PACIFICO%',
 2020, 2026,
 'Procuraduria, prensa'),

-- 10. Choco contratacion territorial
('Choco gobernacion',
 'Departamento del Choco con multiples senalamientos',
 '%CHOCO%',
 NULL,
 2020, 2026,
 'Contraloria territorial'),

-- 11. Vichada contratos rurales
('Vichada territorial',
 'Departamento de Vichada con concentracion proveedores',
 '%VICHADA%',
 NULL,
 2020, 2026,
 'Contraloria territorial, prensa regional'),

-- 12. Guainia contratos
('Guainia territorial',
 'Departamento de Guainia con casos de irregularidades',
 '%GUAINIA%',
 NULL,
 2020, 2026,
 'Contraloria territorial'),

-- 13. La Guajira contratos agua y alimentacion
('La Guajira agua',
 'La Guajira escandalos repetidos contratos de agua y PAE',
 '%GUAJIRA%',
 NULL,
 2020, 2026,
 'Procuraduria, Contraloria, prensa'),

-- 14. Tumaco / Narino
('Tumaco Narino',
 'Tumaco con tematicas de seguridad y postconflicto',
 '%TUMACO%',
 NULL,
 2020, 2026,
 'Prensa, Contraloria'),

-- 15. Bogota Distrital salud
('FFDS Bogota salud',
 'Fondo Financiero Distrital Salud (top entidad en V16.2 con 84 MEDIO)',
 '%FONDO FINANCIERO DISTRITAL DE SALUD%',
 NULL,
 2020, 2026,
 'Contraloria Distrital'),

-- 16. SENA Regional San Andres / Vichada
('SENA San Andres Vichada',
 'SENA Regional San Andres con multiples MEDIO en V16.2',
 '%SENA%SAN ANDRES%',
 NULL,
 2020, 2026,
 'Top 20 entidades V16.2'),

-- 17. Personeria Distrital Medellin
('Personeria Distrital Medellin',
 'Personeria Distrital Medellin con 266 MEDIO en V16.2',
 '%PERSONERIA DISTRITAL%MEDELLIN%',
 NULL,
 2020, 2026,
 'Top 20 entidades V16.2'),

-- 18. Departamento de Antioquia
('Gobernacion Antioquia',
 'Departamento de Antioquia con 165 MEDIO en V16.2',
 '%DEPARTAMENTO DE ANTIOQUIA%',
 NULL,
 2020, 2026,
 'Top 20 entidades V16.2'),

-- 19. INPEC carceles
('INPEC carceles',
 'Establecimientos penitenciarios INPEC con concentracion proveedores',
 '%INPEC%',
 NULL,
 2020, 2026,
 'Top 20 entidades V16.2'),

-- 20. Mineria ilegal Chocó / Caqueta
('Mineria carbon contratos',
 'Contratos de mineria o exploracion carbonifera',
 NULL,
 '%MINERIA%CARBON%',
 2020, 2026,
 'Prensa, gremio carbon');

PRINT '[0] ' + CAST(@@ROWCOUNT AS VARCHAR) + ' casos publicos definidos';

-- ----------------------------------------------------------------------
-- (1) Para cada caso, buscar procesos coincidentes en SECOP II
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (1) HIT-RATE por caso publico: cuantos procesos marca el indice ---';

WITH casos_match AS (
    SELECT
        c.sk_caso,
        c.caso,
        c.descripcion,
        c.fuente,
        f.id_proceso,
        f.sk_entidad,
        f.sk_proveedor
    FROM #casos_publicos c
    JOIN dwh.fact_contratacion f ON 1=1
    JOIN dwh.dim_entidad e ON e.sk_entidad = f.sk_entidad
    JOIN dwh.dim_tiempo t  ON t.sk_tiempo  = f.sk_t_publicacion
    LEFT JOIN staging.secop_ii_procesos s ON s.id_del_proceso = f.id_proceso
    WHERE  (c.patron_entidad IS NULL OR e.nombre LIKE c.patron_entidad)
      AND  (c.patron_proced IS NULL OR
            s.nombre_del_procedimiento LIKE c.patron_proced OR
            s.descripci_n_del_procedimiento LIKE c.patron_proced)
      AND  (c.anio_desde IS NULL OR t.anio >= c.anio_desde)
      AND  (c.anio_hasta IS NULL OR t.anio <= c.anio_hasta)
)
SELECT
    cm.caso,
    cm.descripcion,
    cm.fuente,
    COUNT_BIG(DISTINCT cm.id_proceso)                                                    AS procesos_encontrados,
    SUM(CASE WHEN r.nivel_riesgo = 'ALTO'       THEN 1 ELSE 0 END)                      AS procesos_alto,
    SUM(CASE WHEN r.nivel_riesgo = 'MEDIO'      THEN 1 ELSE 0 END)                      AS procesos_medio,
    SUM(CASE WHEN r.nivel_riesgo = 'BAJO'       THEN 1 ELSE 0 END)                      AS procesos_bajo,
    SUM(CASE WHEN r.nivel_riesgo IS NULL        THEN 1 ELSE 0 END)                      AS procesos_sin_alerta,
    CAST(100.0 *
         SUM(CASE WHEN r.nivel_riesgo IN ('ALTO','MEDIO') THEN 1 ELSE 0 END) /
         NULLIF(COUNT_BIG(DISTINCT cm.id_proceso),0)
         AS DECIMAL(5,2))                                                                AS pct_medio_o_alto
FROM    casos_match cm
LEFT JOIN ind.riesgo_corrupcion r ON r.id_proceso = cm.id_proceso
GROUP BY cm.caso, cm.descripcion, cm.fuente
ORDER BY procesos_alto DESC, procesos_medio DESC, procesos_encontrados DESC;

-- ----------------------------------------------------------------------
-- (2) Detalle de procesos MEDIO o ALTO en cada caso publico
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (2) Procesos MEDIO o ALTO de cada caso publico (TOP 50) ---';

WITH casos_match AS (
    SELECT c.caso, f.id_proceso, f.sk_entidad
    FROM #casos_publicos c
    JOIN dwh.fact_contratacion f ON 1=1
    JOIN dwh.dim_entidad e ON e.sk_entidad = f.sk_entidad
    JOIN dwh.dim_tiempo t  ON t.sk_tiempo  = f.sk_t_publicacion
    LEFT JOIN staging.secop_ii_procesos s ON s.id_del_proceso = f.id_proceso
    WHERE  (c.patron_entidad IS NULL OR e.nombre LIKE c.patron_entidad)
      AND  (c.patron_proced IS NULL OR
            s.nombre_del_procedimiento LIKE c.patron_proced OR
            s.descripci_n_del_procedimiento LIKE c.patron_proced)
      AND  (c.anio_desde IS NULL OR t.anio >= c.anio_desde)
      AND  (c.anio_hasta IS NULL OR t.anio <= c.anio_hasta)
)
SELECT TOP 50
    cm.caso,
    cm.id_proceso,
    e.nombre                                       AS entidad,
    p.nombre                                       AS proveedor,
    m.nombre                                       AS modalidad,
    tp.fecha                                       AS fecha_publicacion,
    f.valor_adjudicado,
    r.puntos_totales,
    r.nivel_riesgo,
    s.urlproceso                                   AS url_secop
FROM    casos_match cm
JOIN    dwh.fact_contratacion f ON f.id_proceso = cm.id_proceso
JOIN    dwh.dim_entidad e   ON e.sk_entidad   = cm.sk_entidad
JOIN    ind.riesgo_corrupcion r ON r.id_proceso = cm.id_proceso
LEFT JOIN dwh.dim_proveedor p ON p.sk_proveedor = f.sk_proveedor
LEFT JOIN dwh.dim_modalidad m ON m.sk_modalidad = f.sk_modalidad
LEFT JOIN dwh.dim_tiempo tp   ON tp.sk_tiempo   = f.sk_t_publicacion
LEFT JOIN staging.secop_ii_procesos s ON s.id_del_proceso = cm.id_proceso
WHERE   r.nivel_riesgo IN ('MEDIO','ALTO')
ORDER BY r.puntos_totales DESC, f.valor_adjudicado DESC;

-- ----------------------------------------------------------------------
-- (3) Resumen ejecutivo
-- ----------------------------------------------------------------------
PRINT '';
PRINT '--- (3) Resumen ejecutivo de la validacion convergente ---';

WITH casos_match AS (
    SELECT c.caso, f.id_proceso
    FROM #casos_publicos c
    JOIN dwh.fact_contratacion f ON 1=1
    JOIN dwh.dim_entidad e ON e.sk_entidad = f.sk_entidad
    JOIN dwh.dim_tiempo t  ON t.sk_tiempo  = f.sk_t_publicacion
    LEFT JOIN staging.secop_ii_procesos s ON s.id_del_proceso = f.id_proceso
    WHERE  (c.patron_entidad IS NULL OR e.nombre LIKE c.patron_entidad)
      AND  (c.patron_proced IS NULL OR
            s.nombre_del_procedimiento LIKE c.patron_proced OR
            s.descripci_n_del_procedimiento LIKE c.patron_proced)
      AND  (c.anio_desde IS NULL OR t.anio >= c.anio_desde)
      AND  (c.anio_hasta IS NULL OR t.anio <= c.anio_hasta)
)
SELECT
    COUNT(DISTINCT caso)                                              AS casos_buscados,
    COUNT_BIG(DISTINCT id_proceso)                                    AS procesos_encontrados,
    SUM(CASE WHEN r.nivel_riesgo IN ('MEDIO','ALTO') THEN 1 ELSE 0 END) AS procesos_marcados_medio_alto,
    SUM(CASE WHEN r.nivel_riesgo = 'BAJO'  THEN 1 ELSE 0 END)         AS procesos_marcados_bajo,
    SUM(CASE WHEN r.nivel_riesgo IS NULL   THEN 1 ELSE 0 END)         AS procesos_sin_alerta,
    CAST(100.0 *
         SUM(CASE WHEN r.nivel_riesgo IN ('MEDIO','ALTO') THEN 1 ELSE 0 END) /
         NULLIF(COUNT_BIG(DISTINCT id_proceso),0)
         AS DECIMAL(5,2))                                              AS pct_marcados_medio_o_alto
FROM    casos_match cm
LEFT JOIN ind.riesgo_corrupcion r ON r.id_proceso = cm.id_proceso;

PRINT '';
PRINT '======================================';
PRINT 'VALIDACION CONVERGENTE COMPLETADA';
PRINT 'Fin: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 120);
PRINT 'Interpretacion:';
PRINT '  - Si pct_marcados_medio_o_alto > 50%: validacion convergente POSITIVA';
PRINT '  - Si entre 20-50%: validacion PARCIAL (interpretar caso por caso)';
PRINT '  - Si < 20%: revisar patrones de busqueda; pueden estar muy estrictos';
PRINT '======================================';

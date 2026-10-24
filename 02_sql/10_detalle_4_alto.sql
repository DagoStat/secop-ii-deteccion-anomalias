-- ============================================================================
-- 15_v4_definitivo.sql   |   Version final con nombres reales del modelo
--
-- Tras el diagnostico de estructura los nombres correctos son:
--   dim_entidad   : nit, nombre, orden, departamento, ciudad
--   dim_proveedor : documento (es el NIT), tipo_doc, nombre
--   dim_modalidad : nombre, es_competitiva
--   dim_tiempo    : fecha, anio
--   fact          : id_proceso, sk_*, valor_adjudicado, precio_base, n_oferentes, estado
--
-- ============================================================================
USE SECOP_DWH;

SET NOCOUNT ON;

-- ----------------------------------------------------------------------
-- (A) FICHA COMPLETA de los 4 procesos ALTO con datos del modelo dimensional
-- ----------------------------------------------------------------------
SELECT 'A. FICHA COMPLETA DE LOS 4 ALTO' AS bloque;

SELECT
    -- Indice
    r.id_proceso,
    r.puntos_totales,
    r.n_alertas                                         AS n_anomalias,

    -- Entidad
    e.nit                                               AS nit_entidad,
    e.nombre                                            AS entidad,
    e.orden                                             AS orden_entidad,
    e.departamento                                      AS departamento_entidad,
    e.ciudad                                            AS ciudad_entidad,

    -- Proveedor
    p.documento                                         AS nit_proveedor,
    p.tipo_doc                                          AS tipo_doc_proveedor,
    p.nombre                                            AS proveedor,

    -- Modalidad
    m.nombre                                            AS modalidad,
    m.es_competitiva,

    -- Fechas
    tp.fecha                                            AS fecha_publicacion,
    ta.fecha                                            AS fecha_adjudicacion,
    DATEDIFF(DAY, tp.fecha, ta.fecha)                   AS dias_pub_adj,

    -- Montos
    f.precio_base,
    f.valor_adjudicado,
    CASE WHEN f.precio_base > 0
         THEN CAST(f.valor_adjudicado / NULLIF(f.precio_base, 0) AS DECIMAL(8,3))
         ELSE NULL END                                  AS ratio_sobrecosto,
    f.n_oferentes,
    f.estado

FROM    ind.riesgo_corrupcion r
JOIN    dwh.fact_contratacion f ON f.id_proceso = r.id_proceso
JOIN    dwh.dim_entidad   e ON e.sk_entidad   = r.sk_entidad
LEFT JOIN dwh.dim_proveedor p ON p.sk_proveedor = r.sk_proveedor
JOIN    dwh.dim_modalidad m ON m.sk_modalidad = r.sk_modalidad
LEFT JOIN dwh.dim_tiempo tp ON tp.sk_tiempo = r.sk_t_publicacion
LEFT JOIN dwh.dim_tiempo ta ON ta.sk_tiempo = r.sk_t_adjudicacion
WHERE   r.nivel_riesgo = 'ALTO'
ORDER BY r.puntos_totales DESC;

-- ----------------------------------------------------------------------
-- (B) ANOMALIAS DISPARADAS en cada uno de los 4 ALTO
-- ----------------------------------------------------------------------
SELECT 'B. ANOMALIAS POR PROCESO ALTO' AS bloque;

SELECT
    ap.id_proceso,
    e.nombre                                            AS entidad,
    p.nombre                                            AS proveedor,
    ap.codigo_anomalia,
    ap.puntos,
    ap.descripcion
FROM    ind.alertas_proceso ap
JOIN    ind.riesgo_corrupcion r ON r.id_proceso = ap.id_proceso
JOIN    dwh.dim_entidad e ON e.sk_entidad = ap.sk_entidad
LEFT JOIN dwh.dim_proveedor p ON p.sk_proveedor = ap.sk_proveedor
WHERE   r.nivel_riesgo = 'ALTO'
ORDER BY ap.id_proceso, ap.codigo_anomalia;

-- ----------------------------------------------------------------------
-- (C) Datos COMPLETOS del API (staging) para los 4 ALTO
--     Aqui usamos SELECT s.* para no inventar nombres de columnas
--     y ver todo lo que el API trae para defenderlos en sustentacion.
-- ----------------------------------------------------------------------
SELECT 'C. STAGING COMPLETO (todas las columnas del API)' AS bloque;

SELECT s.*
FROM    staging.secop_ii_procesos s
WHERE   s.id_del_proceso IN (
    SELECT id_proceso FROM ind.riesgo_corrupcion WHERE nivel_riesgo = 'ALTO'
);

-- ----------------------------------------------------------------------
-- (D) CONTEXTO HISTORICO del par entidad-proveedor de cada ALTO
-- ----------------------------------------------------------------------
SELECT 'D. CONTEXTO DEL PAR ENTIDAD-PROVEEDOR' AS bloque;

WITH alto AS (
    SELECT id_proceso, sk_entidad, sk_proveedor
    FROM ind.riesgo_corrupcion
    WHERE nivel_riesgo = 'ALTO'
)
SELECT
    a.id_proceso                                        AS id_proceso_alto,
    e.nombre                                            AS entidad,
    p.nombre                                            AS proveedor,
    p.documento                                         AS nit_proveedor,
    f.id_proceso                                        AS otro_contrato_del_par,
    t.anio                                              AS anio,
    t.fecha                                             AS fecha_pub,
    f.valor_adjudicado,
    f.n_oferentes,
    ISNULL(r2.nivel_riesgo, 'SIN ALERTA')               AS nivel_riesgo,
    r2.puntos_totales
FROM    alto a
JOIN    dwh.fact_contratacion f ON f.sk_entidad   = a.sk_entidad
                                AND f.sk_proveedor = a.sk_proveedor
JOIN    dwh.dim_tiempo t   ON t.sk_tiempo = f.sk_t_publicacion
JOIN    dwh.dim_entidad e  ON e.sk_entidad = a.sk_entidad
JOIN    dwh.dim_proveedor p ON p.sk_proveedor = a.sk_proveedor
LEFT JOIN ind.riesgo_corrupcion r2 ON r2.id_proceso = f.id_proceso
ORDER BY a.id_proceso, t.fecha DESC;

-- ----------------------------------------------------------------------
-- (E) TRAYECTORIA del proveedor adjudicatario en otros contratos
-- ----------------------------------------------------------------------
SELECT 'E. TRAYECTORIA DEL PROVEEDOR EN OTROS CONTRATOS' AS bloque;

WITH proveedores_alto AS (
    SELECT DISTINCT sk_proveedor
    FROM ind.riesgo_corrupcion
    WHERE nivel_riesgo = 'ALTO'
)
SELECT
    p.nombre                                            AS proveedor,
    p.documento                                         AS nit_proveedor,
    COUNT_BIG(DISTINCT r.sk_entidad)                    AS entidades_distintas,
    COUNT_BIG(*)                                        AS procesos_con_alerta,
    SUM(CASE WHEN r.nivel_riesgo = 'ALTO'  THEN 1 ELSE 0 END) AS procesos_alto,
    SUM(CASE WHEN r.nivel_riesgo = 'MEDIO' THEN 1 ELSE 0 END) AS procesos_medio,
    SUM(CASE WHEN r.nivel_riesgo = 'BAJO'  THEN 1 ELSE 0 END) AS procesos_bajo,
    AVG(CAST(r.puntos_totales AS DECIMAL(5,2)))         AS promedio_puntos
FROM    proveedores_alto pa
JOIN    ind.riesgo_corrupcion r ON r.sk_proveedor = pa.sk_proveedor
JOIN    dwh.dim_proveedor p     ON p.sk_proveedor = pa.sk_proveedor
GROUP BY p.nombre, p.documento
ORDER BY procesos_alto DESC, procesos_medio DESC, promedio_puntos DESC;

# Modelo Entidad-Relación V16.2 — SECOP_DWH

Modelo dimensional Kimball (esquema estrella) sobre Microsoft SQL Server 2022 con cinco schemas: `staging`, `dwh`, `ind`, `pbi`, `meta` + schema `sec` para los controles operativos de seguridad. Indicadores red flag V16.2 (7 vistas activas) sobre escala 0-17 puntos.

## Cómo regenerar la imagen del diagrama ER en el documento Word

1. Abrir https://mermaid.live
2. Pegar el código `erDiagram` del archivo `er_modelo_v16_2.mermaid` (en este mismo directorio)
3. Click en **Actions → PNG** (resolución alta) o **SVG** (vectorial)
4. En el documento Word abrir la Imagen del modelo entidad-relación
5. Click derecho → **Cambiar imagen** → seleccionar el PNG descargado
6. Actualizar el pie de figura a: *"Imagen N. Modelo entidad-relación V16.2 — esquema estrella Kimball con seguridad operativa (RLS + DDM)"*

---

## Convenciones del diagrama

| Símbolo | Significado |
|---|---|
| `PK` | Primary key (clave primaria) |
| `FK` | Foreign key (clave foránea) |
| `UK` | Unique key / business key |
| `sk_*` | Surrogate key (IDENTITY auto-incrementado) |
| `\|\|--o{` | Cardinalidad **uno-a-muchos** (línea continua = FK formal) |
| `\|\|..o{` | Cardinalidad **uno-a-muchos** (línea discontinua = relación lógica, no FK) |
| Anotación `"DDM RESTRINGIDO"` | Columna con Dynamic Data Masking aplicado |
| Anotación `"RLS"` | Columna afectada por política Row-Level Security |
| Anotación `"PUBLICO/INTERNO/RESTRINGIDO/CONFIDENCIAL"` | Nivel de sensibilidad (`meta.clasificacion_sensibilidad`) |

## Estructura del modelo V16.2

### Schema `staging`

| Tabla | Filas | Propósito |
|---|---:|---|
| `staging.secop_ii_procesos` | 8.077.847 | Réplica 1:1 de la fuente API SECOP II (endpoint p6dx-8zbt) |

### Schema `dwh` — Esquema estrella Kimball

| Tabla | Filas | Tipo |
|---|---:|---|
| `dwh.fact_contratacion` | 7.734.679 | Hecho transaccional |
| `dwh.dim_entidad` | ~11.348 | Dimensión |
| `dwh.dim_proveedor` | ~30.013 | Dimensión |
| `dwh.dim_modalidad` | ~17 | Dimensión |
| `dwh.dim_tiempo` | ~4.748 | Dimensión temporal |

**Nombres reales de columnas (verificados contra `INFORMATION_SCHEMA`):**

- `dim_entidad`: `sk_entidad`, `nit`, `nombre`, `orden`, `departamento`, `ciudad`
- `dim_proveedor`: `sk_proveedor`, `documento` (es el NIT), `tipo_doc`, `nombre`
- `dim_modalidad`: `sk_modalidad`, `nombre`, `es_competitiva`
- `dim_tiempo`: `sk_tiempo`, `fecha`, `anio`, `trimestre`, `mes`, `nombre_mes`, `dia`, `dia_semana`
- `fact_contratacion`: `sk_proceso`, `id_proceso`, `sk_entidad`, `sk_proveedor`, `sk_modalidad`, `sk_t_publicacion`, `sk_t_adjudicacion`, `precio_base`, `valor_adjudicado`, `n_oferentes`, `estado`

### Schema `ind` — Indicadores V16.2 (7 vistas activas)

| Vista / Tabla | Tipo | Resultado V16.2 |
|---|---|---:|
| `vw_anom_001_sobrecosto` | Vista (peso 3) | 732 alertas |
| `vw_anom_002_share_monetario` | Vista (peso 3) | 11.900 alertas |
| `vw_anom_003_unico_oferente` | Vista (peso 3) | 1.515 alertas |
| `vw_anom_005_persistencia` | Vista (peso 2) | 17.872 alertas |
| `vw_anom_007_tiempo_atipico` | Vista (peso 2) | 2.610 alertas |
| `vw_anom_008_ultracorto_alto` | Vista (peso 2) | 7.919 alertas |
| `vw_anom_009_fragmentacion_umbral` | Vista (peso 2) | 1.022 alertas |
| `vw_alertas_todas` | Vista UNION | 43.570 alertas |
| `alertas_proceso` | Tabla materializada | 43.570 filas |
| `riesgo_corrupcion` | Tabla agregada (RLS activo) | 39.951 procesos |

**Distribución del índice 0-17:** SIN RIESGO = 7.694.728 / BAJO (1-3) = 36.572 / MEDIO (4-9) = 3.375 / **ALTO (≥10) = 4**.

### Schema `pbi` — Pre-agregaciones (reducción ~144×)

| Tabla | Filas aprox | Granularidad |
|---|---:|---|
| `pbi.agg_riesgo_x_modalidad_anio` | ~120 | Modalidad × Año |
| `pbi.agg_riesgo_x_entidad_anio` | ~80.000 | Entidad × Año |
| `pbi.agg_riesgo_x_departamento_anio` | ~240 | Departamento × Año |
| `pbi.agg_alertas_x_indicador_anio` | ~49 | Indicador × Año |
| `pbi.agg_top_proveedores_riesgo` | ~15.000 | Proveedor (histórico) |

### Schema `meta` — Gobernanza transversal

| Tabla | Propósito | Filas |
|---|---|---:|
| `meta.calidad_dimensiones` | 21 métricas DAMA-DMBOK 2 sobre 7 dimensiones | 21 (18/21 cumplen) |
| `meta.backups` | Inventario de respaldos `.bak` verificados | crece con cada backup |
| `meta.clasificacion_sensibilidad` | Catálogo de 22 columnas en 4 niveles | 22 |
| `meta.audit_seguridad` | Eventos DDL de seguridad | crece con cada cambio |

### Schema `sec` — Seguridad operativa

| Objeto | Tipo | Función |
|---|---|---|
| `sec.fn_filtro_riesgo` | Función inline | Predicado de RLS por nivel de riesgo y rol |
| `sec.pol_riesgo_por_rol` | Security Policy | Aplica el predicado sobre `ind.riesgo_corrupcion` |

**Roles:** `rol_auditor` (UNMASK + ve todos los niveles), `rol_analista_publico` (hasta MEDIO, sin UNMASK), `rol_ciudadano` (solo SIN RIESGO + BAJO, sin UNMASK).

## Cambios respecto a versiones anteriores

| Elemento | V14 (Imagen vieja) | V16 inicial | V16.2 (actual) |
|---|---|---|---|
| Schemas | 3 (staging, dwh, ind) | 6 | **6 (+ sec)** |
| Vistas red flag | 9 `v_*` con nombres viejos | 9 `vw_anom_001..009` | **7 `vw_anom_*`** (sin 004 ni 006) |
| Subprecio (ANOM-004) | Incluido | Reintroducido como HHI | **Eliminado por evidencia empírica** (89% del universo) |
| HHI proveedor-entidad | No existía | ANOM-004 V16 inicial | **Eliminado tras calibración** |
| Fin de semana (ANOM-006) | Incluido | Reemplazado por z_oferentes | **Eliminado por sub-reporte fuente** (99,15%) |
| Persistencia (ANOM-005) | No existía | Marcaba todos los procesos del par | **Deduplicada a 1 por par-año** |
| Schema `pbi` con 5 `agg_*` | No existía | 5 tablas | **5 tablas con nombres reales del script 06** |
| Schema `meta` | Múltiples planeadas | Solo realmente implementadas | `calidad_dimensiones`, `backups`, `clasificacion_sensibilidad`, `audit_seguridad` |
| Schema `sec` | No existía | Diseñado | **Operativo (RLS + DDM aplicados)** |
| Anotaciones DDM/RLS | Ausentes | Presentes | **Validadas con script 11b de pruebas** |
| Índice | 0-19, ALTO ≥6 | 0-22, ALTO ≥14 | **0-17, ALTO ≥10** |
| Procesos ALTO | 2 declarados | 1.896 (sobre-disparado) | **4 (validados cualitativamente)** |

## Render alternativo (compatible con DBeaver / dbdiagram.io)

Si prefieres DBML (dbdiagram.io), exportar el SQL del schema con SSMS desde **Tasks → Generate Scripts** y pegar en https://dbdiagram.io. Las relaciones FK se infieren automáticamente.

Para SchemaSpy (auditable, genera HTML navegable):

```bash
java -jar schemaspy.jar -t mssql08 -dp mssql-jdbc.jar ^
     -host localhost -db SECOP_DWH -u sa -p <pwd> ^
     -o C:\Users\JohnD\UAN\...\VF_v9\diagrama\schemaspy_html
```

## Identificación de los 4 procesos ALTO

Los cuatro procesos con `nivel_riesgo = ALTO` (10 puntos cada uno, máximo observado) tras la calibración V16.2 son:

| id_proceso | Entidad | Proveedor | Anomalías activas |
|---|---|---|---|
| CO1.REQ.7819109 | Municipio de Guatapé (Antioquia) | ESP Guatapé S.A.S | ANOM-001 + 002 + 005 + 008 |
| CO1.REQ.5954983 | IDS Norte de Santander | ESE Hospital Regional Centro | ANOM-001 + 002 + 005 + 008 |
| CO1.REQ.7967249 | Departamento de Santander | IDFES | ANOM-001 + 002 + 005 + 008 |
| CO1.REQ.10248186 | UAE Fondo Nacional de Estupefacientes | RYAN (hidromorfona) | ANOM-002 + 003 + 005 + 009 |

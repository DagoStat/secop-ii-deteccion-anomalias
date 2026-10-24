# Guía Power BI V16.2 — Dashboard SECOP II

Construcción del dashboard `SECOP_V16_Dashboard.pbix` sobre las cinco tablas pre-agregadas `pbi.agg_*` (escala 0-17, 7 indicadores activos).

## Cifras de referencia V16.2

| Métrica | Valor V16.2 |
|---|---:|
| Universo de procesos | 7.734.679 |
| Alertas individuales | 43.570 |
| Procesos con al menos una alerta | 39.951 (0,52 %) |
| Procesos en BAJO | 36.572 (91,5 % de los con alerta) |
| Procesos en MEDIO | 3.375 (8,5 %) |
| Procesos en ALTO | **4** (0,0000517 % del universo) |
| Score máximo posible | 17 |
| Score máximo observado | 10 |
| Reducción del universo | **6 órdenes de magnitud** |

## Pre-requisitos antes de construir / refrescar

Ejecutar en SSMS en este orden:

```sql
USE SECOP_DWH;
:r "C:\Users\JohnD\UAN\Proyecto de grado\2026\SECOP II\VF_v9\sql\04c_v16_2_definitivo.sql"
:r "C:\Users\JohnD\UAN\Proyecto de grado\2026\SECOP II\VF_v9\sql\06_crear_agregaciones_powerbi.sql"
```

Verificar que las 5 tablas `pbi.agg_*` quedaron pobladas:

```sql
SELECT 'agg_riesgo_x_modalidad_anio' AS tabla, COUNT(*) AS filas FROM pbi.agg_riesgo_x_modalidad_anio
UNION ALL SELECT 'agg_riesgo_x_entidad_anio',     COUNT(*) FROM pbi.agg_riesgo_x_entidad_anio
UNION ALL SELECT 'agg_riesgo_x_departamento_anio',COUNT(*) FROM pbi.agg_riesgo_x_departamento_anio
UNION ALL SELECT 'agg_alertas_x_indicador_anio',  COUNT(*) FROM pbi.agg_alertas_x_indicador_anio
UNION ALL SELECT 'agg_top_proveedores_riesgo',    COUNT(*) FROM pbi.agg_top_proveedores_riesgo;
```

## Conexión y carga

1. Abrir Power BI Desktop 2026.
2. **Get data → SQL Server**.
3. Servidor: `localhost`. Base de datos: `SECOP_DWH`.
4. Modo: **Import** (no DirectQuery — VertiPaq comprime ~144×).
5. Importar las 5 tablas `pbi.agg_*` + una tabla calculada `Anios`.

## Tabla calculada `Anios` (DAX)

```dax
Anios = GENERATESERIES(2020, 2026, 1)
```

Renombrar la columna `Value` a `Anio`.

## Relaciones del modelo

| Desde | Hacia | Cardinalidad |
|---|---|---|
| `Anios[Anio]` | `agg_riesgo_x_modalidad_anio[anio]` | 1 a muchos |
| `Anios[Anio]` | `agg_riesgo_x_entidad_anio[anio]` | 1 a muchos |
| `Anios[Anio]` | `agg_riesgo_x_departamento_anio[anio]` | 1 a muchos |
| `Anios[Anio]` | `agg_alertas_x_indicador_anio[anio]` | 1 a muchos |

`agg_top_proveedores_riesgo` queda sin relación con `Anios` (es agregado global histórico).

## Las 21 medidas DAX

### KPIs globales (5 medidas)

```dax
Total Procesos = SUM(agg_riesgo_x_modalidad_anio[total_procesos])

Procesos Con Alerta = SUM(agg_riesgo_x_modalidad_anio[procesos_con_alerta])

Procesos ALTO = SUM(agg_riesgo_x_modalidad_anio[procesos_alto])

Procesos MEDIO = SUM(agg_riesgo_x_modalidad_anio[procesos_medio])

Procesos BAJO = SUM(agg_riesgo_x_modalidad_anio[procesos_bajo])
```

### Porcentajes (4 medidas)

```dax
% Con Alerta = DIVIDE([Procesos Con Alerta], [Total Procesos], 0)
% ALTO       = DIVIDE([Procesos ALTO],       [Total Procesos], 0)
% MEDIO      = DIVIDE([Procesos MEDIO],      [Total Procesos], 0)
% Riesgo Acumulado = DIVIDE([Procesos MEDIO] + [Procesos ALTO], [Total Procesos], 0)
```

### Montos (3 medidas)

```dax
Valor Adjudicado Total =
    SUM(agg_riesgo_x_modalidad_anio[valor_adjudicado_total])

Valor En Riesgo MEDIO ALTO =
    SUM(agg_riesgo_x_modalidad_anio[valor_en_riesgo_medio_alto])

% Valor En Riesgo =
    DIVIDE([Valor En Riesgo MEDIO ALTO], [Valor Adjudicado Total], 0)
```

### Por indicador (4 medidas)

```dax
Total Alertas =
    SUM(agg_alertas_x_indicador_anio[n_alertas])

Procesos Unicos Con Alerta =
    SUM(agg_alertas_x_indicador_anio[procesos_distintos])

Alertas Por Proceso =
    DIVIDE([Total Alertas], [Procesos Con Alerta], 0)

Indicador Mas Frecuente =
    CALCULATE(
        MAX(agg_alertas_x_indicador_anio[codigo_anomalia]),
        TOPN(1, ALL(agg_alertas_x_indicador_anio[codigo_anomalia]),
             [Total Alertas], DESC)
    )
```

### Por entidad / proveedor / departamento (5 medidas)

```dax
Entidades Unicas =
    DISTINCTCOUNT(agg_riesgo_x_entidad_anio[sk_entidad])

Entidades Con ALTO =
    CALCULATE(
        DISTINCTCOUNT(agg_riesgo_x_entidad_anio[sk_entidad]),
        agg_riesgo_x_entidad_anio[procesos_alto] > 0
    )

Departamentos Con Alerta =
    CALCULATE(
        DISTINCTCOUNT(agg_riesgo_x_departamento_anio[departamento]),
        agg_riesgo_x_departamento_anio[procesos_con_alerta] > 0
    )

Proveedores En Riesgo =
    COUNTROWS(
        FILTER(agg_top_proveedores_riesgo,
               agg_top_proveedores_riesgo[procesos_alto] +
               agg_top_proveedores_riesgo[procesos_medio] > 0)
    )

Promedio Puntos Top Proveedores =
    AVERAGE(agg_top_proveedores_riesgo[promedio_puntos])
```

## Cuatro páginas del dashboard

### Página 1 — Vista General

**KPI Cards (5)**

```
7,73 M       Procesos
39.951       Con alerta
3.375        MEDIO
4            ALTO   ← destacar con color rojo
0,0000517 %  % ALTO del universo
```

**Visuales**

- Donut chart "Distribución por nivel" (SIN RIESGO, BAJO, MEDIO, ALTO)
- Bar chart horizontal "Alertas por indicador" (7 barras: ANOM-001 a ANOM-009 sin 004 ni 006)
- Card grande "$ valor en riesgo MEDIO+ALTO" en miles de millones COP
- Line chart "Procesos con alerta por año" (2020-2026)

**Filtros laterales:** Año (slider), Nivel de riesgo (slicer), Modalidad (dropdown)

### Página 2 — Por Modalidad

**Visual principal:** Tabla con columnas

```
Modalidad | Total procesos | Con alerta | % MEDIO+ALTO | Valor adjudicado
```

ordenada por `% MEDIO+ALTO` descendente.

**Visual lateral:** Bar chart "% Riesgo por modalidad" con barra horizontal por modalidad.

**Hallazgo esperado V16.2:** Contratación Directa (con ofertas) en ~3-5 % MEDIO+ALTO (3 de los 4 ALTO son de esta modalidad). Selección abreviada subasta inversa también presente (caso RYAN-FNE).

### Página 3 — Mapa de Colombia

**Visual principal:** Mapa coroplético de 32 departamentos coloreado por `% MEDIO + ALTO` o por `Procesos ALTO` absoluto.

**Configuración:**
- Tipo: ArcGIS Map o Shape Map de Colombia
- Color por: `% Riesgo Acumulado`
- Tooltip: nombre departamento, procesos, ALTO, MEDIO, BAJO

**Hallazgo esperado V16.2:** Antioquia, Norte de Santander, Santander, Distrito Capital con casos ALTO. Sin sesgo geográfico desproporcionado (4 deptos distintos para 4 ALTO).

### Página 4 — Top Proveedores y los 4 ALTO

**Visual 1:** Tabla "Top 20 proveedores por procesos en riesgo"

```
Proveedor | Documento | Entidades | Procesos | ALTO | MEDIO | BAJO | Promedio pts
```

**Visual 2:** Card "Los 4 procesos ALTO V16.2"

Tabla pequeña con los 4 ID de proceso, entidad, modalidad y puntaje. Habilitar **drill-through** a una página detalle.

**Hallazgo esperado V16.2:** Los 4 proveedores con procesos ALTO son IDFES (Santander), RYAN (FNE Bogotá), ESP Guatapé (Antioquia), ESE Hospital Regional Centro (NS).

## Configuración visual recomendada

- **Tema:** UAN colors → principal `#1E2761`, acento `#CADCFC`, alerta `#C62828`, advertencia `#F57F17`
- **Tipografía:** Segoe UI 10 pt cuerpo, 14 pt títulos, 22 pt KPIs
- **Latencia objetivo:** < 2 segundos en cualquier interacción

## Validación rápida del dashboard

Al abrir el `.pbix` refrescado contra V16.2, las 4 páginas deben mostrar:

| Página | Esperado V16.2 |
|---|---|
| Vista General | 7,73 M / 39.951 con alerta / 4 ALTO / ~ $130 B COP valor total |
| Por Modalidad | Contratación Directa (con ofertas) entre los 3 con mayor `% MEDIO+ALTO`. Selección abreviada subasta inversa también presente |
| Mapa | Antioquia, Norte de Santander, Santander, Bogotá D.C. con presencia ALTO. Sin un solo departamento dominante |
| Top Proveedores | IDFES Santander, RYAN, ESP Guatapé, ESE Hospital Centro como Top 4 con procesos ALTO |

## Cambios visuales si vienes de una versión anterior (V14 o V16)

Si tu `.pbix` ya estaba construido para V14 (8 indicadores, escala 0-19, 2 procesos ALTO), debes actualizar:

| Elemento | Antes | Ahora V16.2 |
|---|---|---|
| Bar chart de indicadores | 8 barras (ANOM-001 a 009 sin 004) | **7 barras** (ANOM-001, 002, 003, 005, 007, 008, 009) |
| Slicer escala índice | 0-19 | 0-17 |
| Tarjeta "Procesos ALTO" | 2 | **4** |
| Card "% ALTO del universo" | 2,59 × 10⁻⁷ | **5,17 × 10⁻⁵** |
| Card "Procesos con alerta" | 40.081 | **39.951** |
| Card "Alertas totales" | 53.543 | **43.570** |
| Card "BAJO / MEDIO / ALTO" | 29.014 / 11.065 / 2 | **36.572 / 3.375 / 4** |

## Si las cifras no coinciden

1. Volver a SSMS y verificar que el script 04c se ejecutó: `SELECT TOP 5 * FROM ind.alertas_proceso ORDER BY sk_alerta DESC;`
2. Verificar conteo: `SELECT codigo_anomalia, COUNT(*) FROM ind.alertas_proceso GROUP BY codigo_anomalia;` (debe mostrar 7 indicadores, ANOM-001 a 009 sin 004 ni 006)
3. Re-ejecutar script 06 si las `pbi.agg_*` están vacías.
4. En Power BI: **Inicio → Actualizar** (no solo refresh visual).

## Tamaño esperado del `.pbix`

Entre 1,8 y 3 MB con la calibración V16.2 (menos alertas → menos datos en `agg_alertas_x_indicador_anio` que en versiones anteriores).

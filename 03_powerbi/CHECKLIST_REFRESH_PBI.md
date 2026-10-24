# Checklist — Refrescar el `.pbix` existente a V16.2

Paso a paso para llevar el dashboard de la versión anterior (V14 o V16) a la calibración final V16.2.

## Resumen ejecutivo del refresh

Tres etapas, tiempo total ~10-15 minutos:

1. SSMS — Refrescar `pbi.agg_*` con datos V16.2 (5 min)
2. Power BI Desktop — Hacer **Refresh** del modelo (2 min)
3. Ajustes visuales — Actualizar tarjetas y leyendas a la nueva escala (5 min)

---

## Etapa 1 — SSMS: refrescar tablas pre-agregadas

**Pre-requisito:** las tablas `ind.alertas_proceso` e `ind.riesgo_corrupcion` ya están pobladas con V16.2 (el script `04c_v16_2_definitivo.sql` ya fue ejecutado).

Si no estás seguro, verifica:

```sql
USE SECOP_DWH;
SELECT TOP 1 codigo_anomalia, COUNT(*) AS n
FROM ind.alertas_proceso
GROUP BY codigo_anomalia
ORDER BY codigo_anomalia;
-- Debe mostrar 7 indicadores: ANOM-001, 002, 003, 005, 007, 008, 009
-- NO debe aparecer ANOM-004 ni ANOM-006

SELECT nivel_riesgo, COUNT(*) AS n FROM ind.riesgo_corrupcion GROUP BY nivel_riesgo;
-- Debe mostrar BAJO: 36572, MEDIO: 3375, ALTO: 4
```

**Acción:** Re-ejecutar el script 06 para refrescar las 5 tablas `pbi.agg_*`:

```sql
:r "C:\Users\JohnD\UAN\Proyecto de grado\2026\SECOP II\VF_v9\sql\06_crear_agregaciones_powerbi.sql"
```

Tiempo: 2-5 minutos.

**Verificación rápida:**

```sql
SELECT 'modalidad'    AS tabla, COUNT(*) AS filas FROM pbi.agg_riesgo_x_modalidad_anio
UNION ALL SELECT 'entidad',     COUNT(*) FROM pbi.agg_riesgo_x_entidad_anio
UNION ALL SELECT 'departamento',COUNT(*) FROM pbi.agg_riesgo_x_departamento_anio
UNION ALL SELECT 'indicador',   COUNT(*) FROM pbi.agg_alertas_x_indicador_anio
UNION ALL SELECT 'proveedores', COUNT(*) FROM pbi.agg_top_proveedores_riesgo;
```

Resultado esperado:

| tabla | filas aprox |
|---|---:|
| modalidad | ~115-120 |
| entidad | ~75.000-85.000 |
| departamento | ~225-240 |
| indicador | ~49 (7 indicadores × 7 años) |
| proveedores | ~14.000-16.000 |

---

## Etapa 2 — Power BI Desktop: Refresh del modelo

1. Abrir el `.pbix` existente.
2. Pestaña **Inicio → Actualizar** (o presionar `Ctrl+R`).
3. Esperar ~30-60 segundos mientras VertiPaq recomprime las 5 tablas.
4. Verificar que no aparezcan errores de conexión.

Si aparece error "No se puede conectar al servidor":
- Verificar que SQL Server esté corriendo
- Verificar el origen de datos: **Transformar datos → Configuración de origen de datos**
- Servidor debe ser `localhost`, BD debe ser `SECOP_DWH`

---

## Etapa 3 — Ajustes visuales necesarios

### En Página 1 — Vista General

Ajustar los siguientes elementos:

| Elemento | Valor anterior | Nuevo valor V16.2 |
|---|---|---|
| Card "Procesos ALTO" | 2 | **4** |
| Card "% ALTO" | 2,59 × 10⁻⁷ | **5,17 × 10⁻⁵** o 0,0000517 % |
| Card "Procesos con alerta" | 40.081 | **39.951** |
| Card "Alertas totales" | 53.543 | **43.570** |
| Card "BAJO" | 29.014 | **36.572** |
| Card "MEDIO" | 11.065 | **3.375** |

Los cards se actualizan automáticamente al hacer refresh si están conectadas a las medidas DAX correctas. Si quedan congelados (porque tenían valores hardcoded), reemplazarlos por las medidas:

- `Procesos ALTO` → ahora muestra 4
- `% ALTO` → ahora muestra 0,000052
- `Procesos Con Alerta` → ahora muestra 39.951

### En Bar chart "Alertas por indicador"

Verificar que muestra **7 barras** (no 8 ni 9):

```
ANOM-001 (Sobrecosto)              ~732
ANOM-002 (Share monetario)         ~11.900   ← segunda más alta
ANOM-003 (Único oferente)          ~1.515
ANOM-005 (Persistencia)            ~17.872   ← la más alta
ANOM-007 (Z-score tiempo)          ~2.610
ANOM-008 (Ultracorto + alto)       ~7.919
ANOM-009 (Fragmentación)           ~1.022
```

Si aparecen ANOM-004 o ANOM-006 con 0 alertas: revisar filtros del visual, deben estar excluidos.

### En Slicer/rango de escala del índice

Cambiar el rango de la escala mostrada al usuario:

| Antes | Ahora |
|---|---|
| BAJO 1-4 / MEDIO 5-11 / ALTO ≥12 (sobre 0-19) | **BAJO 1-3 / MEDIO 4-9 / ALTO ≥10 (sobre 0-17)** |

Si tienes una imagen estática (banner) con la leyenda de umbrales, reemplazarla.

### En Página 2 — Por Modalidad

La tabla y bar chart se actualizan automáticamente. Verificar que **Contratación Directa (con ofertas)** aparece con `procesos_alto >= 3` (3 de los 4 ALTO son de esta modalidad).

### En Página 3 — Mapa

Los colores y tooltips se actualizan automáticamente. Verificar que estos 4 departamentos quedan resaltados:

- **Antioquia** (Municipio de Guatapé)
- **Norte de Santander** (IDS)
- **Santander** (Departamento)
- **Distrito Capital de Bogotá** (UAE Fondo Nacional de Estupefacientes)

### En Página 4 — Top Proveedores

La tabla se actualiza automáticamente. Verificar que el Top 4 (filtrando por `procesos_alto >= 1`) incluya:

1. **INSTITUTO FINANCIERO PARA EL DESARROLLO DE SANTANDER** (1 ALTO, 8 MEDIO)
2. **RYAN** (1 ALTO, 6 MEDIO)
3. **EMPRESA DE SERVICIOS PUBLICOS DE GUATAPE S.A.S** (1 ALTO, 1 MEDIO)
4. **ESE HOSPITAL REGIONAL CENTRO** (1 ALTO, 0 MEDIO)

Si quieres agregar una tabla nueva "Los 4 procesos ALTO" como subvisual:
- Necesitarás conectar a `ind.riesgo_corrupcion` directamente (no a `agg_top_proveedores_riesgo`)
- Filtrar por `nivel_riesgo = 'ALTO'`
- Mostrar columnas: id_proceso, entidad, proveedor, modalidad, puntos_totales

---

## Etapa 4 — Validación final

Después del refresh y ajustes, hacer screenshots de las 4 páginas como respaldo para la defensa. Las cifras deben coincidir con la sección "Cifras de referencia V16.2" de `GUIA_POWERBI.md`.

## Si algo falla

| Síntoma | Causa probable | Solución |
|---|---|---|
| Cards muestran valores antiguos | Hardcoded en lugar de medida DAX | Reemplazar valor por medida correspondiente |
| Bar chart de indicadores muestra 8 o 9 barras | El cache del visual no se refrescó | Click derecho en el visual → Refrescar |
| Mapa no muestra Colombia | Locale del visual está en inglés | Cambiar tipo de visual a "Shape Map" con archivo TopoJSON de Colombia |
| Latencia > 2s | Falta índice clustered en `agg_*` | Re-ejecutar script 06 (incluye los `CREATE CLUSTERED INDEX`) |
| Error de conexión SQL Server | Servicio detenido | `Services.msc → SQL Server (MSSQLSERVER) → Start` |

## Tamaño esperado del `.pbix` después del refresh

Entre 1,8 y 3 MB. Si supera 5 MB es señal de que las `pbi.agg_*` están desnormalizadas innecesariamente.

## Después del refresh

Guardar el `.pbix` como `SECOP_V16_Dashboard.pbix` en `powerbi/` y subirlo al repositorio. Los `.pbix` son binarios opacos: la trazabilidad real vive en este checklist + en `GUIA_POWERBI.md` + en los scripts SQL.

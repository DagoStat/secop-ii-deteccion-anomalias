# SECOP II · Detección de posibles anomalías en la contratación estatal colombiana

![SQL Server](https://img.shields.io/badge/SQL%20Server-2022-CC2927)
![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB)
![Power BI](https://img.shields.io/badge/Power%20BI-Desktop-F2C811)
![DAMA-DMBOK](https://img.shields.io/badge/DAMA--DMBOK-2-2E75B6)
![Licencia](https://img.shields.io/badge/Licencia-MIT-yellow)

Solución analítica de extremo a extremo que procesa **7,7 millones de procesos de contratación pública** de Colombia, aplica siete indicadores de riesgo calibrados empíricamente y entrega una lista priorizada de auditoría.

Construida sobre datos abiertos, con marco DAMA-DMBOK 2 para gobierno y CRISP-DM para la analítica.

**John Dagoberto Moyano Duarte** · Estadístico (UNAL) · Especialista en Gobierno de Datos (UAN)
[LinkedIn](https://www.linkedin.com/in/john-moyano) · [GitHub](https://github.com/DagoStat) · jdmoyanod@unal.edu.co

Trabajo de grado de la Especialización en Gobierno de Datos, Universidad Antonio Nariño, 2026. Director: Elio Higinio Cables Pérez, PhD.

---

## El problema

Colombia publica cada proceso de contratación pública en SECOP II. Son más de nueve millones de registros. Ningún organismo de control puede auditarlos todos.

La pregunta de este proyecto: **¿se puede reducir ese universo a una lista de revisión manejable, con criterios defendibles y reproducibles?**

## El resultado

| Nivel de riesgo | Procesos | Qué significa |
|---|---:|---|
| Universo analizado | 7.734.679 | Procesos atribuibles, ene-2020 a may-2026 |
| Con al menos una alerta | 39.951 | 0,52 % del universo |
| **MEDIO — resultado operativo** | **3.375** | **Volumen auditable por un equipo de control en un año** |
| ALTO | 4 | Revisión inmediata |

**El entregable operativo es el nivel MEDIO.** Pasar de 7,7 millones a 3.375 procesos priorizados es la reducción que hace viable un programa de auditoría.

Sobre los 4 procesos en ALTO: el análisis caso por caso determinó que **tres corresponden a un artefacto de captura de la fuente** —ratio valor adjudicado sobre precio base exactamente igual a 1.000— y **uno es un hallazgo sustantivo**: concentración institucional real de un proveedor único durante seis años consecutivos en un mercado con competencia posible.

Ese resultado contraintuitivo es, en sí mismo, un hallazgo: el sistema detectó un defecto sistemático del endpoint público que no había sido reportado. Se elevó como recomendación formal a Colombia Compra Eficiente, y motivó el módulo de plausibilidad incluido en este repositorio.

---

## Arquitectura

```
datos.gov.co          SQL Server 2022              Power BI
API Socrata     →     SECOP_DWH              →     4 páginas
p6dx-8zbt             6 esquemas                   21 medidas DAX

                 staging → dwh → ind → pbi
                      meta (gobernanza transversal)
                      sec  (seguridad: RLS + DDM)
```

| Esquema | Propósito |
|---|---|
| `staging` | Espejo del API sin reglas de negocio |
| `dwh` | Modelo dimensional estrella (Kimball) |
| `ind` | Siete indicadores de riesgo y el índice compuesto |
| `pbi` | Agregaciones para la capa de visualización |
| `meta` | Metadatos, calidad, bitácora y versionado |
| `sec` | Seguridad a nivel de fila y enmascaramiento dinámico |

## Los siete indicadores

Basados en literatura especializada: Fazekas y Tóth (2016), Ferwerda y Deleanu (2017), OCDE (2016), Open Contracting Partnership (2018).

| Código | Indicador | Peso | Regla |
|---|---|:---:|---|
| ANOM-001 | Sobrecosto | 3 | Valor adjudicado / precio base > 1,5 |
| ANOM-002 | Concentración monetaria | 3 | Participación del proveedor ≥ 50 % del gasto entidad-año |
| ANOM-003 | Único oferente | 3 | Un solo oferente en modalidad competitiva |
| ANOM-005 | Persistencia | 2 | Mismo par entidad-proveedor 3 años consecutivos |
| ANOM-007 | Tiempo atípico | 2 | \|z-score de log(días)\| ≥ 3 por modalidad-año |
| ANOM-008 | Ultracorto y alto valor | 2 | Días ≤ P10 global y valor ≥ P90 global |
| ANOM-009 | Fragmentación en el umbral | 2 | ≥ 5 contratos en el rango P95–P99 de la modalidad |

**Índice 0–17 puntos.** SIN RIESGO = 0 · BAJO 1–3 · MEDIO 4–9 · ALTO ≥ 10.

Los pesos son de criterio experto: 3 puntos a los indicadores con respaldo más fuerte en la literatura, 2 a los demás. El índice es **ordinal y sirve para priorizar auditoría**; no estima probabilidad de corrupción.

---

## Limitaciones conocidas

Esta sección existe porque un sistema de detección sin límites declarados no es defendible.

**1. ANOM-003 opera sobre una fracción del universo.** El API reporta cero oferentes en el 99,15 % de los procesos competitivos. El indicador solo puede evaluar el 0,85 % restante, que no es una muestra aleatoria: son las entidades que diligencian mejor. Es un indicador de alta precisión y cobertura muy baja. La limitación es de fuente y está documentada como recomendación a Colombia Compra Eficiente.

**2. El nivel ALTO tiene un rendimiento efectivo de un caso.** Tres de los cuatro son artefactos de datos. El nivel operativo real es MEDIO.

**3. No hay validación contra verdad de terreno.** No existe un registro público de procesos verificados como corruptos, de modo que no se pueden calcular precisión ni exhaustividad. El script `11_validacion_convergente.sql` contrasta contra veinte casos de dominio público como aproximación preliminar; la validación formal exigiría cruzar contra SIRECI, SIRI y SPOA.

**4. Falsos positivos estructurales en mercados regulados.** El índice desconoce las restricciones regulatorias de cada mercado. Una categoría con un único fabricante autorizado por ley generará siempre alerta de oferente único sin que exista anomalía. El caso ALTO sustantivo de este estudio es precisamente de ese tipo.

**5. Brecha de atribución del 4,25 %.** De 8.077.847 registros sincronizados, 7.734.679 llegan a la tabla de hechos. Los 343.168 restantes se descartan por no tener entidad o proveedor identificables. Pendiente caracterizar si ese descarte es aleatorio.

**6. Tres de las veintiuna métricas de calidad DAMA no alcanzan el objetivo.** Se reportan sin corregir en `12_reporte_calidad_dama.sql`.

---

## Qué contiene el repositorio

```
├── 01_pipeline/
│   ├── 01_extraccion_secop_ii.py        Extracción desde la API Socrata
│   └── 02_calidad_plausibilidad.py      Reglas de plausibilidad y cuarentena
├── 02_sql/                              14 scripts en orden de ejecución
├── 03_powerbi/                          Guía de construcción y 21 medidas DAX
├── 04_documento/                        Tesis completa
├── 05_presentacion/                     Defensa
├── 06_diagramas/                        Arquitectura y modelo entidad-relación
└── REPLICAR.md                          Guía paso a paso con cifras esperadas
```

### Módulo de plausibilidad

Implementa la recomendación derivada del hallazgo del factor 1.000. Detecta errores de unidad, valores que exceden el techo plausible de la contratación pública colombiana y adjudicaciones en cero, y los pone en cuarentena **antes** del cálculo de indicadores.

```bash
python 01_pipeline/02_calidad_plausibilidad.py --demo
python 01_pipeline/02_calidad_plausibilidad.py --api --limite 50000
```

Sobre el conjunto de prueba identifica los tres casos de factor 1.000 y descarta correctamente el caso de concentración real, que tiene ratio 0,998.

---

## Replicar

Tres a cuatro horas de extremo a extremo. El detalle está en [`REPLICAR.md`](./REPLICAR.md), con las cifras exactas que deben aparecer al terminar.

Requiere SQL Server 2022 Express, Python 3.10+, Power BI Desktop, 30 GB de disco y 16 GB de RAM. Todo el software es gratuito.

---

## Marco legal y ético

| Norma | Aplicación |
|---|---|
| Art. 29 Constitución Política | Presunción de inocencia: el sistema marca para auditoría, no juzga |
| Ley 1581 de 2012 | Enmascaramiento dinámico sobre NIT y nombres de personas naturales |
| Ley 1712 de 2014 | Transparencia: montos y entidades son información pública |
| Ley 80 de 1993, Ley 1150 de 2007, Decreto 1082 de 2015, Ley 2195 de 2022 | Marco de la contratación estatal |

> Una alerta de este índice es una señal estadística o normativa que invita a verificación. **No constituye evidencia ni juicio** sobre ninguna entidad o proveedor. Las verificaciones corresponden a la Contraloría, la Procuraduría, la Fiscalía y las veedurías ciudadanas.

---

## Evolución del proyecto

El [`CHANGELOG.md`](./CHANGELOG.md) documenta las dieciséis versiones, incluidos los errores corregidos: un indicador que marcaba el 89 % del universo y fue eliminado, otro que generaba el 88 % de las alertas y fue deduplicado, un tercero inoperante por sub-reporte de la fuente, y una errata de documentación en cinco de ocho indicadores que se publicó con tabla comparativa.

La calibración empírica llevó el sistema de marcar el 23 % del universo a marcar el 0,52 %.

## Licencia

MIT con cláusula de presunción de inocencia. Ver [`LICENSE`](./LICENSE).

## Cita

> Moyano Duarte, J. D. (2026). *Visualización de posibles anomalías en la contratación estatal a partir de datos abiertos SECOP II — V16.2*. Trabajo de grado, Especialización en Gobierno de Datos, Universidad Antonio Nariño. Bogotá D.C.

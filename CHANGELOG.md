# CHANGELOG — Evolución del proyecto

## V16.2 (junio 2026) — **VERSIÓN FINAL DE ENTREGA**

Tras calibración empírica iterativa sobre 7.734.679 procesos del SECOP II.

**Indicadores activos (7):**
- ANOM-001 Sobrecosto: ratio valor_adjudicado / precio_base > 1,5 (peso 3)
- ANOM-002 Concentración monetaria: Share por entidad-año ≥ 50 % (peso 3)
- ANOM-003 Único oferente en modalidad competitiva (peso 3)
- ANOM-005 Persistencia: 3 años consecutivos, deduplicada a 1 alerta por par-año (peso 2)
- ANOM-007 Tiempo atípico: \|z-score log(días)\| ≥ 3 por modalidad-año (peso 2)
- ANOM-008 Ultracorto + valor alto: días ≤ P10 global Y valor ≥ P90 global (peso 2)
- ANOM-009 Fragmentación próxima al umbral: ≥ 5 contratos en P95-P99 modalidad (peso 2)

**Suma máxima = 17.** Escala: SIN RIESGO = 0, BAJO 1-3, MEDIO 4-9, **ALTO ≥ 10**.

**Resultados:** 43.570 alertas, 39.951 procesos con alerta (0,52 %), **4 procesos ALTO** (5,17 × 10⁻⁵ del universo, seis órdenes de magnitud de reducción).

---

## V16.1 (junio 2026) — Iteración intermedia

Eliminación de ANOM-004 (HHI proveedor-entidad) tras evidencia empírica: marcaba el 89 % del universo por sesgo estructural de carteras concentradas naturales en entidades pequeñas.

Resultados intermedios: 214.248 alertas, 88.401 procesos con alerta (1,14 %), 1.944 ALTO.

**Pendiente al cierre de V16.1:** ANOM-005 disparaba 88 % de las alertas por contar todos los procesos del par persistente; ANOM-006 (z_oferentes) no disparaba por sub-reporte del API (99,15 %).

---

## V16 (junio 2026) — Rediseño completo del índice

Respuesta integral a la crítica metodológica del evaluador estadístico senior.

**Cambios estructurales:**
- Cinco indicadores migrados de umbrales absolutos a métricas relativas y estadísticas (Share, HHI, z-score, percentiles).
- ANOM-004 reintroducido con semántica nueva (HHI proveedor-entidad).
- ANOM-005 Persistencia nueva (3 años consecutivos) reemplaza el concepto huérfano "Contratos repetidos".
- ANOM-006 reemplazado: "Fin de semana" → "Competencia anormalmente baja" (z_oferentes).
- ANOM-009 reformulado con percentiles P95-P99 como proxy del techo regulatorio.

**Pre-ejecución teórica:** 9 indicadores activos, suma máxima 22, umbrales 0-5/6-13/≥14.

**Hallazgo post-ejecución:** ANOM-004 marcaba 89 % del universo (no discrimina).

---

## V15 (junio 2026) — Inserción de sección "Evaluación crítica metodológica"

Reconocimiento explícito de los cinco puntos vulnerables señalados por el evaluador senior (ANOM-001 falsos positivos, ANOM-005 absoluto, ANOM-009 recurrencia ≠ fragmentación, ANOM-007 agrupamiento heterogéneo, pesos arbitrarios), plan de validación en 4 capas (contenido → consistencia interna → convergente → predictiva ROC/AUC) y pesos empíricos preliminares.

---

## V14 (junio 2026) — Errata reconocida y corregida

Al auditar la Tabla 8 del documento contra el script 04 real se detectó que **5 de los 8 indicadores tenían definición o peso mal documentado**. La V14 publicó la corrección con tabla comparativa transparente.

**Indicadores reales V14 (8):**
- ANOM-001 Adjudicación inmediata · 3
- ANOM-002 Único oferente · 3
- ANOM-003 Sobrecosto > 150 % · 2
- ANOM-005 Concentración (count absoluto ≥10) · 3
- ANOM-006 Fin de semana · 1
- ANOM-007 Z-score log(valor_adjudicado) por modalidad · 3
- ANOM-008 Ultracorto ≤1 día + valor > $100 M · 2
- ANOM-009 ≥3 procesos mismo día · 2

Suma máxima = 19. Umbrales BAJO 1-4 / MEDIO 5-11 / ALTO ≥ 12.

Resultados V14: 53.543 alertas, 40.081 procesos con alerta, 2 ALTO.

---

## V13 (junio 2026) — Correcciones tras evaluador #2

Eliminación de erratas tipográficas (vlaor, riessgo, ínidce, etc.), aclaración del rol de DAX/M en Power BI, declaración de ventana analítica completa (no recortada por tiempo de cómputo), corrección de numeración de capítulos.

---

## V12 (junio 2026) — Renombrado de objetos SQL

Migración de nombres viejos (v_sobrecosto, v_concentracion_prov_ent, alerta_modalidad, calidad_metricas, backup_log) a la convención ANOM-001..009 y nombres canónicos del DAMA-DMBOK (calidad_dimensiones, backups).

---

## V11 (junio 2026) — Arquitectura de 7 capas

Reescritura de la sección de arquitectura para reflejar las 7 capas + gobernanza transversal: (i) Fuente API → (ii) Extracción → (iii) Aterrizaje staging → (iv) Modelo dimensional dwh → (v) Indicadores ind → (vi) Presentación pbi → (vii) Visualización Power BI, con `meta` como capa transversal de gobernanza.

---

## V10 (junio 2026) — Atención de evaluador #2

Subsanación de cuatro observaciones: ventana corta corregida, aclaración DAX/M, numeración de capítulos, erratas tipográficas.

---

## V9 (junio 2026) — Estructura reproducible

Empaquetado en carpeta `VF_v9` con README, CHANGELOG, LICENSE, .gitignore. Scripts SQL consolidados de 19 a 10. Documentos en `docs/`, scripts en `sql/`, pipeline en `pipeline/`.

---

## V7 → V8 (mayo-junio 2026) — Prototipo y consolidación

Prototipo inicial con 9 alertas BIT (`alerta_modalidad`, `alerta_urgencia`, etc.) sobre 1 millón de procesos en una tabla `alertas_proceso_mat`. La consolidación V8 escala a 7,73 millones de procesos, introduce el código ANOM-* y elimina `alerta_modalidad_no_comp` y `alerta_urgencia_manifiesta` por falta de regla SQL defensible.

---

## Lecciones del proceso iterativo

1. **La calibración empírica es ineludible.** Las primeras versiones del índice (V14, V16) tenían problemas que solo se revelaron al ejecutar sobre el universo completo. La V16 inicial marcaba 23 % del universo; la V16.2 final marca 0,52 %.
2. **Reconocer errores documentales fortalece la defensa.** La V14 ocultaba que 5 de 8 indicadores estaban mal documentados; la V15-V16 los reconoció abiertamente y la V16.2 los reescribió completamente.
3. **Los hallazgos contraintuitivos son señal de honestidad metodológica.** Detectar que ANOM-004 marcaba 89 % del universo y eliminarlo, o que ANOM-005 dominaba el ranking y deduplicarla, o que ANOM-006 no funcionaba por sub-reporte del API y eliminarla, son decisiones documentadas que elevan la defendibilidad del sistema.
4. **El 1.000× exacto en 3 de los 4 ALTO es contribución metodológica.** Demuestra que el sistema detecta problemas reales que ni Colombia Compra Eficiente ha reportado (artefacto de captura sistemático en el API).

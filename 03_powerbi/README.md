# 03_powerbi — Dashboard interactivo

Dashboard de cuatro páginas construido sobre las cinco tablas pre-agregadas `pbi.agg_*` con latencia inferior a 2 segundos.

## Archivos

- **`GUIA_POWERBI.md`** — Construcción completa del dashboard desde cero (conexión, modelo, 21 medidas DAX, 4 páginas con visuales). 30-45 minutos.
- **`CHECKLIST_REFRESH_PBI.md`** — Para refrescar un `.pbix` existente a V16.2 en 10-15 minutos.
- `SECOP_V16_Dashboard.pbix` — (placeholder, **construir siguiendo `GUIA_POWERBI.md`**)

## Por qué no incluimos el `.pbix` directamente

El archivo `.pbix` es un binario opaco (zip con XML interno propietario de Microsoft). Para que el repositorio sea auditable, mantenemos la **fuente de verdad en `GUIA_POWERBI.md`** con todas las medidas DAX explícitas. Esto permite:

1. Reconstruir el dashboard desde cero sin depender del binario.
2. Auditar las reglas de cálculo línea por línea.
3. Versionar cambios en Git (el `.pbix` es ilegible en diffs).

Si solo necesitas verificar visualmente, construye el `.pbix` en 30-45 minutos siguiendo la guía y guárdalo aquí. Estará incluido en `.gitignore` para no contaminar el repositorio.

## Cifras esperadas tras refresh

| Página | Debe mostrar |
|---|---|
| Vista General | 7,73 M procesos · 39.951 con alerta · 4 ALTO · 0,0000517 % en ALTO |
| Por Modalidad | Contratación Directa entre las 3 con mayor `% MEDIO+ALTO` |
| Mapa de Colombia | Antioquia, Norte de Santander, Santander, Bogotá D.C. con presencia ALTO |
| Top Proveedores | IDFES Santander, RYAN, ESP Guatapé, ESE Hospital Centro como Top 4 con ALTO |

## Tema visual

Colores institucionales UAN:
- Principal: `#1E2761` (azul profundo)
- Acento: `#CADCFC` (azul claro)
- Alerta: `#C62828` (rojo)
- Advertencia: `#F57F17` (naranja)

Tipografía: Segoe UI (10pt cuerpo, 14pt títulos, 22pt KPIs).

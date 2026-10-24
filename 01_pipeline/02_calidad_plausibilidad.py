"""
================================================================================
 PIPELINE SECOP II  ·  CAPA DE CALIDAD - REGLAS DE PLAUSIBILIDAD
--------------------------------------------------------------------------------
 Proyecto       : Deteccion de anomalias en la contratacion estatal colombiana
 Autor          : John Dagoberto Moyano Duarte
 Especializacion: Gobierno de Datos - Universidad Antonio Narino (UAN) - 2026
 Marco          : DAMA-DMBOK 2 (dimension Exactitud / Validez)
--------------------------------------------------------------------------------
 POR QUE EXISTE ESTE MODULO
 --------------------------
 En la version V16.2 el indice de riesgo clasifico 4 procesos como ALTO.
 El analisis cualitativo revelo que 3 de los 4 presentaban un ratio
 valor_adjudicado / precio_base EXACTAMENTE igual a 1.000, es decir un
 artefacto de captura del API y no un sobrecosto real.

 Que esos registros llegaran hasta la cima del indice de riesgo significa
 que la capa de calidad no tenia una regla de coherencia entre campos.
 Este modulo cierra ese hueco: cuarentena los registros implausibles ANTES
 de que entren al calculo de indicadores.

 Regla central: si valor_adjudicado / precio_base es un multiplo exacto de
 una potencia de diez (10, 100, 1.000, 10.000), la explicacion mas probable
 es un error de unidad en el origen, no un sobrecosto.
--------------------------------------------------------------------------------
 USO
   python 02_calidad_plausibilidad.py --demo              # datos sinteticos
   python 02_calidad_plausibilidad.py --api --limite 50000
   python 02_calidad_plausibilidad.py --csv ruta/datos.csv
================================================================================
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

# Campos minimos que necesita el modulo
COL_ID = "id_del_proceso"
COL_BASE = "precio_base"
COL_ADJ = "valor_total_adjudicacion"
COL_ENTIDAD = "entidad"

# Factores de error de unidad que se consideran implausibles
FACTORES_SOSPECHOSOS = [10, 100, 1_000, 10_000]
# Tolerancia relativa: 0.001 = el ratio debe estar a menos de 0,1% del factor
TOLERANCIA = 0.001
# Techo de contratacion publica en Colombia. Por encima de esto, revisar.
TECHO_PLAUSIBLE_COP = 5_000_000_000_000  # 5 billones


# ==============================================================================
# 1. CARGA DE DATOS
# ==============================================================================
def cargar_desde_api(limite: int) -> pd.DataFrame:
    """Descarga una muestra del endpoint Socrata p6dx-8zbt."""
    import requests

    url = "https://www.datos.gov.co/resource/p6dx-8zbt.json"
    params = {
        "$select": f"{COL_ID},{COL_ENTIDAD},{COL_BASE},{COL_ADJ}",
        "$where": "adjudicado='Si' AND precio_base>0",
        "$limit": limite,
    }
    print(f"Descargando hasta {limite:,} procesos adjudicados del API...")
    resp = requests.get(url, params=params, timeout=120)
    resp.raise_for_status()
    return pd.DataFrame(resp.json())


def cargar_demo() -> pd.DataFrame:
    """Dataset sintetico que reproduce los patrones observados en V16.2."""
    return pd.DataFrame(
        {
            COL_ID: [f"CO1.REQ.{i}" for i in range(1, 11)],
            COL_ENTIDAD: ["Entidad " + c for c in "ABCDEFGHIJ"],
            COL_BASE: [
                245_250_000,      # artefacto 1.000x (caso Guatape)
                138_443_500,      # artefacto 1.000x (caso IDS Norte de Santander)
                2_600_000_000,    # artefacto 1.000x (caso Santander)
                3_518_163_000,    # normal, ratio 0,998 (caso FNE-RYAN)
                100_000_000,      # sobrecosto real 60%
                50_000_000,       # normal
                80_000_000,       # artefacto 100x
                10_000_000,       # adjudicado en cero
                0,                # base en cero -> no evaluable
                1_000_000,        # normal
            ],
            COL_ADJ: [
                245_250_000_000,
                138_443_500_000,
                2_600_000_000_000,
                3_510_000_000,
                160_000_000,
                50_000_000,
                8_000_000_000,
                0,
                5_000_000,
                1_000_000,
            ],
        }
    )


# ==============================================================================
# 2. REGLAS DE PLAUSIBILIDAD
# ==============================================================================
def evaluar_plausibilidad(df: pd.DataFrame) -> pd.DataFrame:
    """Anade columnas de diagnostico. No elimina filas: marca."""
    d = df.copy()

    d[COL_BASE] = pd.to_numeric(d[COL_BASE], errors="coerce")
    d[COL_ADJ] = pd.to_numeric(d[COL_ADJ], errors="coerce")

    # El ratio solo tiene sentido con base positiva
    d["ratio"] = np.where(d[COL_BASE] > 0, d[COL_ADJ] / d[COL_BASE], np.nan)

    # --- R1. Error de unidad: ratio == potencia de diez exacta ---------------
    def factor_detectado(r):
        if pd.isna(r) or r <= 0:
            return 0
        for f in FACTORES_SOSPECHOSOS:
            if abs(r - f) / f <= TOLERANCIA:
                return f
        return 0

    d["factor_unidad"] = d["ratio"].apply(factor_detectado)
    d["R1_error_unidad"] = d["factor_unidad"] > 0

    # --- R2. Valor por encima del techo plausible ----------------------------
    d["R2_excede_techo"] = d[COL_ADJ] > TECHO_PLAUSIBLE_COP

    # --- R3. Adjudicado en cero con base positiva ----------------------------
    d["R3_adjudicado_cero"] = (d[COL_BASE] > 0) & (d[COL_ADJ] == 0)

    # --- R4. Base no evaluable -----------------------------------------------
    d["R4_base_no_valida"] = ~(d[COL_BASE] > 0)

    # --- Veredicto ------------------------------------------------------------
    d["en_cuarentena"] = d[["R1_error_unidad", "R2_excede_techo", "R3_adjudicado_cero"]].any(axis=1)

    d["motivo"] = np.select(
        [d["R1_error_unidad"], d["R2_excede_techo"], d["R3_adjudicado_cero"], d["R4_base_no_valida"]],
        ["Error de unidad (factor exacto)", "Excede techo plausible",
         "Adjudicado en cero", "Base no evaluable"],
        default="OK",
    )
    return d


# ==============================================================================
# 3. REPORTE
# ==============================================================================
def reportar(d: pd.DataFrame) -> str:
    n = len(d)
    evaluables = int((~d["R4_base_no_valida"]).sum())
    cuarentena = int(d["en_cuarentena"].sum())

    lineas = [
        "# Reporte de plausibilidad - SECOP II",
        "",
        f"- Registros analizados: **{n:,}**",
        f"- Evaluables (precio_base > 0): **{evaluables:,}**",
        f"- En cuarentena: **{cuarentena:,}** ({cuarentena / n * 100:.3f} %)",
        "",
        "## Desglose por regla",
        "",
        "| Regla | Descripcion | Registros |",
        "|---|---|---:|",
        f"| R1 | Error de unidad (factor exacto de 10, 100, 1.000 o 10.000) | {int(d['R1_error_unidad'].sum()):,} |",
        f"| R2 | Valor adjudicado superior a 5 billones COP | {int(d['R2_excede_techo'].sum()):,} |",
        f"| R3 | Adjudicado en cero con precio base positivo | {int(d['R3_adjudicado_cero'].sum()):,} |",
        f"| R4 | Precio base nulo o cero (no evaluable) | {int(d['R4_base_no_valida'].sum()):,} |",
        "",
    ]

    if int(d["R1_error_unidad"].sum()):
        lineas += ["## Factores de unidad detectados", "",
                   "| Factor | Registros |", "|---:|---:|"]
        vc = d.loc[d["R1_error_unidad"], "factor_unidad"].value_counts().sort_index()
        for f, c in vc.items():
            lineas.append(f"| {int(f):,}x | {int(c):,} |")
        lineas.append("")

    detalle = d[d["en_cuarentena"]].head(20)
    if len(detalle):
        lineas += ["## Primeros registros en cuarentena", "",
                   "| id_del_proceso | precio_base | valor_adjudicado | ratio | motivo |",
                   "|---|---:|---:|---:|---|"]
        for _, r in detalle.iterrows():
            lineas.append(
                f"| {r[COL_ID]} | {r[COL_BASE]:,.0f} | {r[COL_ADJ]:,.0f} "
                f"| {r['ratio']:,.3f} | {r['motivo']} |"
            )
        lineas.append("")

    lineas += [
        "## Interpretacion",
        "",
        "Un ratio exactamente igual a una potencia de diez no es un sobrecosto:",
        "es un error de unidad en el origen. Estos registros deben excluirse del",
        "calculo del indice de riesgo y reportarse a Colombia Compra Eficiente",
        "como hallazgo de calidad del endpoint p6dx-8zbt.",
        "",
    ]
    return "\n".join(lineas)


# ==============================================================================
# 4. ORQUESTACION
# ==============================================================================
def main() -> int:
    p = argparse.ArgumentParser(description="Reglas de plausibilidad SECOP II")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--demo", action="store_true", help="Usa datos sinteticos")
    g.add_argument("--api", action="store_true", help="Descarga del API Socrata")
    g.add_argument("--csv", type=Path, help="Lee de un CSV local")
    p.add_argument("--limite", type=int, default=50_000)
    p.add_argument("--salida", type=Path, default=Path("reporte_plausibilidad.md"))
    args = p.parse_args()

    if args.demo:
        df = cargar_demo()
    elif args.api:
        df = cargar_desde_api(args.limite)
    else:
        df = pd.read_csv(args.csv)

    faltantes = [c for c in (COL_ID, COL_BASE, COL_ADJ) if c not in df.columns]
    if faltantes:
        print(f"ERROR: faltan columnas {faltantes}", file=sys.stderr)
        return 1

    d = evaluar_plausibilidad(df)
    reporte = reportar(d)

    args.salida.write_text(reporte, encoding="utf-8")
    d.to_csv(args.salida.with_suffix(".csv"), index=False, encoding="utf-8")

    print(reporte)
    print(f"\nReporte: {args.salida}")
    print(f"Detalle: {args.salida.with_suffix('.csv')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

@echo off
REM ============================================================================
REM replicar.bat - Orquestador end-to-end de la solucion SECOP II V16.2
REM
REM Uso: doble click o desde CMD ejecutar replicar.bat
REM
REM Pre-requisitos: SQL Server 2022 corriendo en localhost, Python 3.10+ en PATH,
REM                 SQLCMD instalado con SSMS.
REM
REM Salida: log completo en C:\SECOP_II_VF_v16_2\replicar.log
REM ============================================================================

setlocal enabledelayedexpansion

set BASE=%~dp0
set LOG=%BASE%replicar.log
set BD=SECOP_DWH
set SERVIDOR=localhost

echo. > "%LOG%"
echo ====================================== | tee -a "%LOG%"
echo  REPLICACION SECOP II V16.2
echo  Inicio: %DATE% %TIME%
echo  Base:    %BD%
echo  Servidor: %SERVIDOR%
echo  Log:      %LOG%
echo ======================================
echo.

REM ---------------------------------------------------------------------------
REM Verificacion de pre-requisitos
REM ---------------------------------------------------------------------------
echo [VERIFICACION] Pre-requisitos...

where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python no encontrado. Instalar desde https://www.python.org/downloads
    pause & exit /b 1
)

where sqlcmd >nul 2>&1
if errorlevel 1 (
    echo [ERROR] sqlcmd no encontrado. Instalar SSMS desde https://aka.ms/ssms
    pause & exit /b 1
)

sqlcmd -S %SERVIDOR% -E -d master -Q "SELECT 1" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] No se puede conectar a SQL Server en %SERVIDOR%. Verificar que el servicio este corriendo.
    pause & exit /b 1
)

echo [OK] Pre-requisitos verificados.
echo.

REM ---------------------------------------------------------------------------
REM Paso 1: Crear base de datos
REM ---------------------------------------------------------------------------
echo [PASO 1] Creando base de datos %BD% (si no existe)...
sqlcmd -S %SERVIDOR% -E -d master -Q "IF DB_ID('%BD%') IS NULL CREATE DATABASE %BD%" 2>&1 | findstr /v "^$" >> "%LOG%"

REM ---------------------------------------------------------------------------
REM Paso 2: Crear schemas + dimensiones + fact
REM ---------------------------------------------------------------------------
echo [PASO 2] Creando schemas y modelo dimensional... (estimado: 30 seg)
sqlcmd -S %SERVIDOR% -E -d %BD% -i "%BASE%02_sql\01_crear_schemas.sql" 2>&1 >> "%LOG%"
sqlcmd -S %SERVIDOR% -E -d %BD% -i "%BASE%02_sql\02_crear_dimensiones_y_fact.sql" 2>&1 >> "%LOG%"

REM ---------------------------------------------------------------------------
REM Paso 3: Pipeline Python
REM ---------------------------------------------------------------------------
echo [PASO 3] Extrayendo del API SECOP II... (estimado: 30-60 min)
echo         Para reanudar tras fallos, simplemente vuelve a ejecutar este script.
cd /d "%BASE%01_pipeline"
pip install -q -r requirements.txt 2>&1 >> "%LOG%"
python 01_extraccion_secop_ii.py 2>&1 >> "%LOG%"
cd /d "%BASE%"

REM ---------------------------------------------------------------------------
REM Paso 4: Cargar staging -> dwh
REM ---------------------------------------------------------------------------
echo [PASO 4] Cargando staging -> dwh (deduplicacion)... (estimado: 5-10 min)
sqlcmd -S %SERVIDOR% -E -d %BD% -i "%BASE%02_sql\03_cargar_staging_a_dwh.sql" 2>&1 >> "%LOG%"

REM ---------------------------------------------------------------------------
REM Paso 5: Indicadores V16.2
REM ---------------------------------------------------------------------------
echo [PASO 5] Creando 7 vistas red flag V16.2... (estimado: 15 seg)
sqlcmd -S %SERVIDOR% -E -d %BD% -i "%BASE%02_sql\04_indicadores_v16_2.sql" 2>&1 >> "%LOG%"

REM ---------------------------------------------------------------------------
REM Paso 6: Materializar alertas + riesgo
REM ---------------------------------------------------------------------------
echo [PASO 6] Materializando alertas y calculando indice 0-17... (estimado: 5-15 min)
sqlcmd -S %SERVIDOR% -E -d %BD% -i "%BASE%02_sql\05_materializar_alertas_y_riesgo.sql" 2>&1 >> "%LOG%"

REM ---------------------------------------------------------------------------
REM Paso 7: Pre-agregaciones Power BI
REM ---------------------------------------------------------------------------
echo [PASO 7] Pre-agregando 5 tablas pbi.agg_*... (estimado: 2-5 min)
sqlcmd -S %SERVIDOR% -E -d %BD% -i "%BASE%02_sql\06_crear_agregaciones_powerbi.sql" 2>&1 >> "%LOG%"

REM ---------------------------------------------------------------------------
REM Paso 8: Calidad DAMA-DMBOK
REM ---------------------------------------------------------------------------
echo [PASO 8] Calidad DAMA-DMBOK (21 metricas)... (estimado: 5-10 min)
sqlcmd -S %SERVIDOR% -E -d %BD% -i "%BASE%02_sql\07_calidad_dama_dmbok.sql" 2>&1 >> "%LOG%"

REM ---------------------------------------------------------------------------
REM Paso 9: Backup verificado
REM ---------------------------------------------------------------------------
echo [PASO 9] Backup verificado... (estimado: 1-2 min)
sqlcmd -S %SERVIDOR% -E -d %BD% -i "%BASE%02_sql\08_backup_y_gobierno.sql" 2>&1 >> "%LOG%"

REM ---------------------------------------------------------------------------
REM Paso 10: Seguridad RLS + DDM
REM ---------------------------------------------------------------------------
echo [PASO 10] Seguridad operativa RLS + DDM... (estimado: 30 seg)
sqlcmd -S %SERVIDOR% -E -d %BD% -i "%BASE%02_sql\09_seguridad_rls_ddm.sql" 2>&1 >> "%LOG%"

REM ---------------------------------------------------------------------------
REM Verificacion final
REM ---------------------------------------------------------------------------
echo.
echo ======================================
echo  VERIFICACION FINAL
echo ======================================

sqlcmd -S %SERVIDOR% -E -d %BD% -Q "SELECT 'staging' AS tabla, COUNT_BIG(*) AS filas FROM staging.secop_ii_procesos UNION ALL SELECT 'fact', COUNT_BIG(*) FROM dwh.fact_contratacion UNION ALL SELECT 'alertas', COUNT_BIG(*) FROM ind.alertas_proceso UNION ALL SELECT 'riesgo', COUNT_BIG(*) FROM ind.riesgo_corrupcion"

echo.
sqlcmd -S %SERVIDOR% -E -d %BD% -Q "SELECT nivel_riesgo, COUNT_BIG(*) AS procesos FROM ind.riesgo_corrupcion GROUP BY nivel_riesgo ORDER BY CASE nivel_riesgo WHEN 'SIN RIESGO' THEN 0 WHEN 'BAJO' THEN 1 WHEN 'MEDIO' THEN 2 WHEN 'ALTO' THEN 3 END"

echo.
echo ======================================
echo  REPLICACION COMPLETA
echo  Fin: %DATE% %TIME%
echo  Log: %LOG%
echo ======================================
echo.
echo Siguiente paso: construir el dashboard Power BI siguiendo
echo                 03_powerbi\GUIA_POWERBI.md (30-45 min adicionales).
echo.
pause
endlocal

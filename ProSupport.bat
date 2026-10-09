@echo off
:: Script para configurar tarea de mantenimiento interactivo con menú y logging
:: Pregunta frecuencia, hora y cuenta de ejecución

:: Verifica si el script se está ejecutando como administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Ejecutando con permisos de administrador...
    powershell -Command "Start-Process cmd -ArgumentList '/c %~s0' -Verb RunAs"
    exit /b
)

:: Definir variables
set SCRIPT_PATH="%USERPROFILE%\Documents\mantenimiento_profesional.ps1"
set TASK_NAME="Mantenimiento_Interactivo_TI"

echo ============================================
echo Configuración de la tarea de mantenimiento
echo ============================================
echo.
echo Seleccione la frecuencia de ejecución:
echo 1. Diario
echo 2. Semanal
echo 3. Mensual
echo.
set /p FREQ=Ingrese opción (1-3):

if "%FREQ%"=="1" set SCH_FREQ=daily
if "%FREQ%"=="2" set SCH_FREQ=weekly
if "%FREQ%"=="3" set SCH_FREQ=monthly

echo.
set /p SCH_TIME=Ingrese la hora de ejecución (HH:MM, formato 24h):

echo.
echo Seleccione la cuenta de ejecución:
echo 1. Usuario actual (%USERNAME%)
echo 2. SYSTEM (máxima autoridad, acceso limitado a Documentos)
echo.
set /p ACC=Ingrese opción (1-2):

if "%ACC%"=="1" (
    set SCH_USER=%USERNAME%
) else (
    set SCH_USER=SYSTEM
)

:: Crear la tarea programada con los parámetros elegidos
schtasks /create /tn "%TASK_NAME%" ^
 /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File %SCRIPT_PATH%" ^
 /sc %SCH_FREQ% /st %SCH_TIME% /ru %SCH_USER% /rl HIGHEST /f

:: Confirmación
echo.
echo Tarea programada "%TASK_NAME%" creada exitosamente.
echo Frecuencia: %SCH_FREQ%
echo Hora: %SCH_TIME%
echo Cuenta: %SCH_USER%
echo Se ejecutará el script con menú interactivo y se generarán logs en TXT y HTML en Documentos.
pause

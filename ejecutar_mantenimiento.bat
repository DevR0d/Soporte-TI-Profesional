@echo off
setlocal
chcp 65001 >nul
set "SRC=%~dp0mantenimiento_profesional.ps1"
set "INSTALLED=%LOCALAPPDATA%\SoporteTI\Herramienta\mantenimiento_profesional.ps1"
if exist "%SRC%" (
    set "TARGET=%SRC%"
) else if exist "%INSTALLED%" (
    set "TARGET=%INSTALLED%"
) else (
    echo ERROR: No se encontro mantenimiento_profesional.ps1.
    pause
    exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%TARGET%"
if errorlevel 1 echo La ejecucion termino con errores.
pause
endlocal

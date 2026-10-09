@echo off
setlocal
set "SRC=%~dp0mantenimiento_profesional.ps1"
if not exist "%SRC%" set "SRC=%LOCALAPPDATA%\SoporteTI\Herramienta\mantenimiento_profesional.ps1"
if not exist "%SRC%" (
    echo ERROR: Falta mantenimiento_profesional.ps1
    pause
    exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%SRC%" -Preview
pause
endlocal

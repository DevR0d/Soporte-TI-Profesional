@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0verificar_paquete.ps1"
if errorlevel 1 echo [ERROR] Hay fallos de configuracion o sintaxis.
pause
endlocal

@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0administrador_tareas.ps1" -Mode Run
if errorlevel 1 echo [ERROR] No se pudo lanzar la tarea programada.
pause
endlocal

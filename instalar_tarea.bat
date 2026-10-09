@echo off
setlocal
cd /d "%~dp0"
title SOPORTE TI - INSTALACION DE TAREA
rem Este acceso conserva compatibilidad con la version 1.0.
rem Para cualquier otra frecuencia use Administrador_SoporteTI.bat.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0administrador_tareas.ps1" -Mode InstallDaily
if errorlevel 1 echo [ERROR] Consulte el mensaje anterior y la GUIA_RAPIDA.md.
pause
endlocal

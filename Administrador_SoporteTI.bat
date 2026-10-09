@echo off
setlocal
cd /d "%~dp0"
title SOPORTE TI PROFESIONAL - CONSOLA DE ADMINISTRACION
if not exist "%~dp0administrador_tareas.ps1" (
  echo [ERROR] No se encuentra administrador_tareas.ps1 en esta carpeta.
  pause
  exit /b 1
)
rem Respeta RemoteSigned y todas las politicas GPO / AppLocker / WDAC.
rem Nunca utiliza ExecutionPolicy Bypass ni credenciales SYSTEM.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0administrador_tareas.ps1" -Mode Menu
if errorlevel 1 (
  echo.
  echo [ERROR] La consola no pudo completarse.
  echo Si Windows bloquea el script, revise GUIA_RAPIDA.md antes de cambiar politicas.
)
echo.
pause
endlocal

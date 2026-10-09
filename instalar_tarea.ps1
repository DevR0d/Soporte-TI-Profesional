#requires -Version 5.1
# Compatibilidad version anterior. Ahora gestiona el administrador central.
& (Join-Path $PSScriptRoot 'administrador_tareas.ps1') -Mode InstallDaily

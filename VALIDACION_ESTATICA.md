# Validación técnica y alcance

- Versión: Soporte TI Profesional 2.0.
- Sistemas objetivo: Windows 10/11, Windows PowerShell 5.1 y servicio Programador de tareas.
- Esta distribución integra el motor previo `mantenimiento_profesional.ps1` con un nuevo administrador de tareas con COM (`Schedule.Service`), accesos BAT y verificación en Windows.
- En este entorno de creación (Linux) se verificó **estáticamente** la existencia de archivos, estructura BAT/PS1, integridad de los ZIP, patrones del modelo de seguridad y cálculos matemáticos del calendario de meses. **No es posible afirmar que se haya probado la creación real de tareas COM en Windows ni la elevación UAC.**
- Para comprobar sintaxis real de PowerShell usa `verificar_paquete.bat` en Windows. La prueba sintáctica no sustituye la prueba operativa de cada frecuencia.
- Antes de usar el paquete en equipos de producción: probar en VM, validar `Get-ScheduledTaskInfo` y permisos, confirmar interacción visible bajo el usuario correcto, ejecutar simulación y revisar reportes.

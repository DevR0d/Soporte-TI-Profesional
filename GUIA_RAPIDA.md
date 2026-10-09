# Chuleta de soporte TI — Administración de tareas v2.0

> Ejecutar desde Windows PowerShell 5.1 en el perfil que verá el menú. Requiere Windows 10/11. Un cambio de frecuencia **reemplaza** el desencadenador previo y crea un XML de respaldo automáticamente.

## Lo más fácil: menú visual por consola

**Doble clic en `Administrador_SoporteTI.bat` → opción 3** para seleccionar la frecuencia, el día, el mes de inicio (si aplica) y hora `HH:mm`.

| Selección | Ejemplo de configuración |
|---|---|
| Diario | 08:00 cada día |
| Semanal | Lunes a las 10:30 |
| Mensual | Día 15 de cada mes a las 09:00 |
| Cada 2 meses | Febrero, abril, junio, agosto, octubre, diciembre |
| Cada 3 meses | Febrero, mayo, agosto, noviembre |
| Cada 4 meses | Marzo, julio, noviembre |
| Cada 6 meses | Abril, octubre |
| Anual | 12 de septiembre a las 11:00 |

**Precisión:** el mes inicial define el patrón dentro del año. Se admiten ciclos que dividen 12 para que la frecuencia no se desplace con el cambio de año. El día de mes se limita a 1–28 para evitar omisiones en febrero. La ejecución se basa en el reloj local de Windows.

## Comandos de programación rápida (PowerShell)

Primero, desde la carpeta descomprimida:

```powershell
cd 'C:\RUTA\SoporteTI_Profesional_v2'
```

Adapta la ruta a tu carpeta real y ejecuta cualquiera de estos comandos (cada uno cambia la misma tarea):

```powershell
# Todos los dias a las 09:30
.\administrador_tareas.ps1 -Mode Schedule -Frequency Daily -Time '09:30'

# Semanal, viernes a las 16:00
.\administrador_tareas.ps1 -Mode Schedule -Frequency Weekly -WeekDay FRI -Time '16:00'

# Mensual, dia 15 a las 10:00
.\administrador_tareas.ps1 -Mode Schedule -Frequency Monthly -Day 15 -Time '10:00'

# Cada 3 meses, empezando en febrero (FEB, MAY, AGO, NOV)
.\administrador_tareas.ps1 -Mode Schedule -Frequency Quarterly -Day 15 -Month 2 -Time '09:00'

# Cada 4 meses, empezando en marzo (MAR, JUL, NOV)
.\administrador_tareas.ps1 -Mode Schedule -Frequency FourMonthly -Day 10 -Month 3 -Time '15:30'

# Cada 6 meses, empezando en abril (ABR, OCT)
.\administrador_tareas.ps1 -Mode Schedule -Frequency SemiAnnual -Day 12 -Month 4 -Time '08:30'

# Anual: cada 20 de septiembre
.\administrador_tareas.ps1 -Mode Schedule -Frequency Annual -Day 20 -Month 9 -Time '11:00'
```

**No es necesario invocar `-ExecutionPolicy Bypass`.** Si se bloquearon por marca de Internet, tras revisar los scripts puedes desbloquear los `.ps1` confiables con `Get-ChildItem -Filter '*.ps1' -File | Unblock-File`. Si tu organización exige AllSigned, firma el código y coordina con TI; no eludas las políticas.

## Operación y diagnóstico (PowerShell)

```powershell
# Estado / proxima ejecucion / cuenta de Windows
.\administrador_tareas.ps1 -Mode Status

# Ejecutar ahora la tarea REGISTRADA (abre menu)
.\administrador_tareas.ps1 -Mode Run

# Abrir el mantenimiento sin esperar a la programacion
.\administrador_tareas.ps1 -Mode Manual

# Vista previa sin limpiar archivos
.\administrador_tareas.ps1 -Mode Preview

# Pausar/reactivar programacion
.\administrador_tareas.ps1 -Mode Disable
.\administrador_tareas.ps1 -Mode Enable

# Guardar respaldo XML de tarea
.\administrador_tareas.ps1 -Mode Backup

# Consultar eventos recientes del programador de Windows
.\administrador_tareas.ps1 -Mode History

# Actualizar el script instalado SIN modificar calendario
.\administrador_tareas.ps1 -Mode Sync

# Eliminar solo la tarea; conserva motor, reportes y respaldos
.\administrador_tareas.ps1 -Mode Uninstall
```

## Comandos nativos útiles (CMD o PowerShell)

```bat
schtasks /query /tn "Mantenimiento_Interactivo_TI" /fo LIST /v
schtasks /run /tn "Mantenimiento_Interactivo_TI"
schtasks /change /tn "Mantenimiento_Interactivo_TI" /disable
schtasks /change /tn "Mantenimiento_Interactivo_TI" /enable
schtasks /change /tn "Mantenimiento_Interactivo_TI" /st 10:30
taskschd.msc
```

`/change /st` cambia solamente la hora, **no la periodicidad**. Las tareas pueden requerir derechos para su modificación. Usar el administrador v2.0 para cambios de frecuencia y respaldos automáticos.

## ¿Dónde ver las evidencias?

```powershell
# Ultimas ejecuciones y codigo del Programador
Get-ScheduledTaskInfo -TaskName 'Mantenimiento_Interactivo_TI'

# Triggers, accion y cuenta
Get-ScheduledTask -TaskName 'Mantenimiento_Interactivo_TI' |
    Format-List TaskName,State,Actions,Triggers,Principal

# Ruta local de administracion / logs
$base = Join-Path $env:LOCALAPPDATA 'SoporteTI\Mantenimiento'
explorer.exe (Join-Path $base 'Administracion')
explorer.exe (Join-Path $base 'Reportes')

# Ultimas modificaciones de programacion
Get-Content (Join-Path $base 'Administracion\auditoria_programacion.jsonl') -Tail 15
```

## Fallos frecuentes

- **No firmado / RemoteSigned:** comprueba `Get-ExecutionPolicy -List`; si está en RemoteSigned, revisa el código y desbloquea solamente los archivos confiables. No necesitas cambiar la política global.
- **No aparece la ventana a la hora:** el usuario asignado debe tener sesión iniciada; revisa `Principal.LogonType` y `LastTaskResult`. Si el equipo está apagado, no habrá menú en ese instante.
- **Acceso denegado al programar:** podrían existir restricciones por GPO, tareas creadas por otra cuenta o falta de privilegios. No utilices `SYSTEM` para mostrar una consola interactiva.
- **Hora incorrecta:** revisa hora, zona horaria, cambios horario verano y desencadenadores en `taskschd.msc`.
- **No se guarda la tarea:** verifica las pruebas básicas con `verificar_paquete.bat` y el evento en la pestaña Historial del Programador.
- **No se ejecuta limpieza automáticamente:** es intencional. La tarea abre el menú y el operador confirma las operaciones. Para mantenimiento desatendido es necesario diseñar otro proceso con criterios, controles, registro, ventana y autorización específica.

## Despliegue profesional

La consola se instala por perfil en `%LOCALAPPDATA%`. Para múltiples PC, copiar el paquete a cada equipo, iniciarlo desde la cuenta que verá el menú y registrar la frecuencia autorizada. Integrar con gestión de endpoints y firmar los scripts antes de despliegue masivo. Esta versión no configura equipos remotos ni implementa ejecución desatendida con privilegios SYSTEM.

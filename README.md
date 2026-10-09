# Soporte TI Profesional 2.0 — consola de administración + mantenimiento

**Plataforma:** Windows 10/11, Windows PowerShell 5.1. **Cuenta programada:** usuario actual con sesión iniciada. **Zona horaria:** la del equipo. **Modo predeterminado:** menú interactivo, sin borrados automáticos.

## Empieza aquí (5 pasos)

1. Descomprime **todo el ZIP** en una carpeta local y revisa los archivos `.ps1` y `.bat`. No ejecutar desde el ZIP.
2. Si Windows bloquea scripts descargados, abre PowerShell y desbloquea **solo los archivos revisados y de confianza**: `Get-ChildItem -LiteralPath 'C:\RUTA\SoporteTI_Profesional_v2' -Filter '*.ps1' -File | Unblock-File`. Reemplaza `C:\RUTA\...` por tu carpeta real. Una alternativa es usar **Propiedades > Desbloquear** sobre el ZIP *antes* de extraerlo. No cambiar GPO ni utilizar `Bypass`.
3. Haz doble clic en `verificar_paquete.bat` para verificar sintaxis en Windows, archivos y módulo del Programador.
4. Abre `Administrador_SoporteTI.bat`. Selecciona **2** para simular o **1** para ejecutar mantenimiento manual; **3** para crear/modificar la tarea.
5. Comprueba con **4** la próxima ejecución y usa **5** para probar la tarea registrada sin esperar su fecha.

## Archivos

| Archivo | Función |
|---|---|
| **`Administrador_SoporteTI.bat`** | Consola principal de soporte técnico: 13 funciones + salir. |
| **`administrador_tareas.ps1`** | Motor de programación COM: diario, semanal, mensual, cada 2/3/4/6 meses y anual. |
| `mantenimiento_profesional.ps1` | Motor independiente de limpieza, diagnóstico, optimización, inventario y reportes. |
| `ejecutar_mantenimiento.bat` | Menú de mantenimiento manual (compatibilidad). |
| `ejecutar_simulacion.bat` | Vista previa, sin efectuar limpiezas. |
| `instalar_tarea.bat` | Configura tarea **diaria a las 08:00** (compatibilidad; para otras frecuencias usar administrador). |
| `probar_tarea.bat` | Ejecuta la tarea ya registrada. |
| `desinstalar_tarea.bat` | Elimina **solo** la programación, conservando archivos/evidencias. |
| `instalar_tarea.ps1`, `desinstalar_tarea.ps1` | Accesos compatibles delegados al nuevo administrador. |
| `verificar_paquete.bat`, `verificar_paquete.ps1` | Autodiagnóstico de estructura y sintaxis PowerShell ejecutable en Windows. |
| `GUIA_RAPIDA.md` | Comandos listos para copiar, calendario, solución de incidencias. |
| `SHA256SUMS.txt` | Hashes de los archivos de esta distribución (integridad, **no firma digital**). |
| `VALIDACION_ESTATICA.md` | Alcance y límites de las pruebas disponibles. |

## Menú de administración

```text
 1 Ejecutar mantenimiento manual
 2 Simular mantenimiento
 3 Configurar o modificar horario y frecuencia
 4 Ver estado, cuenta y próxima ejecución
 5 Ejecutar tarea registrada ahora
 6 Pausar tarea
 7 Reactivar tarea
 8 Exportar configuración XML (respaldo)
 9 Abrir logs y reportes
10 Consultar eventos del Programador de tareas
11 Eliminar programación con respaldo
12 Abrir taskschd.msc
13 Sincronizar copia instalada del motor (sin tocar horario)
 0 Salir
```

En opción **3**, elegir entre diario, semanal, mensual, bimestral, trimestral, cuatrimestral, semestral o anual. Indicar hora `HH:mm` (24 horas), día de mes 1–28 para evitar meses sin esa fecha; seleccionar **mes de inicio** en ciclos de varios meses. El calendario usa **meses explícitos**: por ejemplo, cada 4 meses desde febrero significa febrero, junio y octubre cada año. Se registra *una sola tarea*, cuyo nombre es `Mantenimiento_Interactivo_TI`.

La primera instalación copia el motor a `%LOCALAPPDATA%\SoporteTI\Herramienta\mantenimiento_profesional.ps1`, ruta estable por perfil. Para actualizar el motor desde un nuevo paquete usar **13**, sin sobrescribir la programación existente.

## Modelo de seguridad

- La tarea interactiva utiliza el usuario Windows que ejecuta la consola (`InteractiveToken`), **no SYSTEM**; no almacena contraseña y se ejecuta con nivel limitado. Las acciones especiales del motor solicitan UAC por separado.
- La tarea **solo abre el menú**. Cada limpieza requiere selección/confirmación; no se ejecuta un mantenimiento integral sin intervención.
- Si el usuario está desconectado, la tarea no puede mostrar la ventana a la hora indicada. Con equipo apagado/suspendido tampoco se garantiza ejecución exacta; `StartWhenAvailable` puede permitir recuperación bajo condiciones de Windows. No se despierta el equipo automáticamente.
- Los scripts **no tienen firma de código**. Un hash permite comprobar integridad respecto de este ZIP, pero no demuestra autoría ni convierte el script en confiable. Revisar y probar antes de utilizar en empresas.
- Respeta GPO/WDAC/AppLocker/EDR y el proceso de gestión de cambios de la organización. **No cambiar la política de ejecución global** para hacerlo funcionar.
- Los cambios del Programador de tareas pueden estar limitados por permisos de Windows, aun para tareas propias.
- No borra Prefetch ni perfiles completos; no modifica cookies/contraseñas. La opción avanzada de descargas de Windows Update exige especial cuidado y es operada por el motor original de mantenimiento.
- Los reportes del motor reflejan lo realizado en la sesión de mantenimiento. Un `LastTaskResult` igual a 0 únicamente indica el resultado del proceso registrado, no garantiza que las limpiezas seleccionadas hayan terminado sin errores.

## Datos locales, respaldo y reversión

| Ruta | Contenido |
|---|---|
| `%LOCALAPPDATA%\SoporteTI\Herramienta\` | Script de mantenimiento instalado. |
| `%LOCALAPPDATA%\SoporteTI\Mantenimiento\Logs\` | Consola de operaciones del motor de mantenimiento. |
| `%LOCALAPPDATA%\SoporteTI\Mantenimiento\Reportes\` | Reportes JSON de sesiones de mantenimiento. |
| `%LOCALAPPDATA%\SoporteTI\Mantenimiento\Respaldos\` | Respaldos de programas de inicio. |
| `%LOCALAPPDATA%\SoporteTI\Mantenimiento\Administracion\programacion.json` | Última programación configurada mediante consola. |
| `%LOCALAPPDATA%\SoporteTI\Mantenimiento\Administracion\auditoria_programacion.jsonl` | Auditoría de cambios de horario, estado, eliminación y respaldos. |
| `%LOCALAPPDATA%\SoporteTI\Mantenimiento\Administracion\RespaldosTarea\` | XML de la tarea antes de cambios/desinstalación y respaldos manuales. |

El respaldo XML contiene una definición del Programador de tareas y puede revisarse o importarse manualmente por un administrador autorizado. **No ejecutar XML de procedencia desconocida**. El menú **11** borra la tarea pero conserva registros, reportes, XML y motor para auditoría.

## Compatibilidad con la versión 1.0

Si ya tenías `Mantenimiento_Interactivo_TI` de la primera versión, abre el **Administrador v2.0** con **la misma cuenta de Windows**. Al reprogramar, se revisa que la tarea existente corresponda al motor `mantenimiento_profesional.ps1`, se respalda su XML y luego se sustituye la definición. Si otra tarea usa ese nombre y ejecuta otro programa, la consola **se niega a sobrescribirla**. Si la tarea pertenece a otra cuenta, también la rechaza.

**Atención:** `instalar_tarea.bat` conserva su semántica original: **reprograma diariamente a las 08:00** después de confirmar. Para cambiarla, usa la opción **3** del administrador, **no reinstales con el BAT antiguo**.

## Pruebas antes de producción

1. Ejecuta `verificar_paquete.bat` en Windows. Su análisis sintáctico detecta errores de PowerShell, **pero no prueba tareas COM**.
2. En una máquina virtual, abre consola y configura una tarea diaria para minutos después de la hora actual. Verifica usuario, tipo de inicio, ventana y próxima ejecución.
3. Prueba el calendario trimestral empezando en febrero (feb/may/ago/nov) y cuatrimestral empezando en marzo (mar/jul/nov). Comprueba lo indicado en el Programador.
4. Pausa, reactiva, ejecuta manualmente, revisa la auditoría JSONL y confirma que el respaldo XML se genera antes de cambiar/eliminar.
5. Ejecuta simulación en el motor de mantenimiento y verifica que no haya cambios. Luego prueba módulos seguros y controles UAC en entorno controlado.

Para sintaxis de comandos y solución de bloqueos consulta **`GUIA_RAPIDA.md`**.

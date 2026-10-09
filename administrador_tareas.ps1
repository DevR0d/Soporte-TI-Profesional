#requires -Version 5.1
<#
.SYNOPSIS
   Consola de administracion del mantenimiento interactivo de Soporte TI.
.DESCRIPTION
   Programa la tarea para el usuario que tiene sesion iniciada, sin SYSTEM,
   contrasenas persistidas, bypass de politicas ni limpiezas automaticas.
   Windows 10/11 - Windows PowerShell 5.1 - Programador de tareas (COM).
.EXAMPLE
   .\administrador_tareas.ps1
.EXAMPLE
   .\administrador_tareas.ps1 -Mode Schedule -Frequency Quarterly -Time 09:00 -Day 15 -Month 2
.EXAMPLE
   .\administrador_tareas.ps1 -Mode Status
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu','Manual','Preview','InstallDaily','Schedule','Status','Run','Disable','Enable','Backup','Logs','History','Uninstall','Sync')]
    [string]$Mode = 'Menu',
    [ValidateSet('Daily','Weekly','Monthly','Bimonthly','Quarterly','FourMonthly','SemiAnnual','Annual')]
    [string]$Frequency = 'Daily',
    [ValidatePattern('^([01][0-9]|2[0-3]):[0-5][0-9]$')]
    [string]$Time = '08:00',
    [ValidateRange(1,28)]
    [int]$Day = 15,
    [ValidateRange(1,12)]
    [int]$Month = 1,
    [ValidateSet('MON','TUE','WED','THU','FRI','SAT','SUN')]
    [string]$WeekDay = 'MON',
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:TaskName = 'Mantenimiento_Interactivo_TI'
$script:CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$script:CurrentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$script:InstallFolder = Join-Path $env:LOCALAPPDATA 'SoporteTI\Herramienta'
$script:InstalledEngine = Join-Path $script:InstallFolder 'mantenimiento_profesional.ps1'
$script:EngineSource = Join-Path $PSScriptRoot 'mantenimiento_profesional.ps1'
$script:BaseFolder = Join-Path $env:LOCALAPPDATA 'SoporteTI\Mantenimiento'
$script:AdminFolder = Join-Path $script:BaseFolder 'Administracion'
$script:BackupFolder = Join-Path $script:AdminFolder 'RespaldosTarea'
$script:ConfigFile = Join-Path $script:AdminFolder 'programacion.json'
$script:AuditFile = Join-Path $script:AdminFolder 'auditoria_programacion.jsonl'
$script:LogFolder = Join-Path $script:BaseFolder 'Logs'
$script:ReportFolder = Join-Path $script:BaseFolder 'Reportes'
$script:PowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Write-Title([string]$Value) {
    Write-Host "`n==============================================================" -ForegroundColor Cyan
    Write-Host ("  {0}" -f $Value) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
}
function Write-Ok([string]$Value) { Write-Host ('[OK] ' + $Value) -ForegroundColor Green }
function Write-Info([string]$Value) { Write-Host ('[INFO] ' + $Value) -ForegroundColor Yellow }
function Ask-Yes([string]$Prompt) {
    $answer = Read-Host ($Prompt + ' [S/N]')
    return ($answer -match '^(s|si|sí)$')
}
function Confirm-IfNeeded([string]$Prompt) {
    if ($Force) { return $true }
    return Ask-Yes $Prompt
}
function Wait-Enter { [void](Read-Host 'Presione ENTER para continuar') }
function Ensure-Folders {
    foreach ($path in @($script:InstallFolder,$script:AdminFolder,$script:BackupFolder)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            [void](New-Item -Path $path -ItemType Directory -Force)
        }
    }
}
function Write-AdminAudit([string]$ActionName,[string]$Status,[string]$Detail) {
    try {
        Ensure-Folders
        $entry = [pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            Equipo = $env:COMPUTERNAME
            Cuenta = $script:CurrentUser
            Accion = $ActionName
            Resultado = $Status
            Detalle = $Detail
        }
        $entry | ConvertTo-Json -Compress -Depth 3 | Add-Content -LiteralPath $script:AuditFile -Encoding UTF8
    } catch { Write-Warning ('No se pudo escribir auditoria de programacion: ' + $_.Exception.Message) }
}
function Get-TaskSafe {
    return (Get-ScheduledTask -TaskName $script:TaskName -TaskPath '\' -ErrorAction SilentlyContinue)
}
function Assert-TaskOwnership($Existing) {
    if ($null -eq $Existing) { return }
    $parameters = (($Existing.Actions | ForEach-Object { $_.Arguments }) -join ' ')
    if ($parameters -notmatch '(?i)mantenimiento_profesional\.ps1') {
        throw ('Ya existe una tarea con el nombre ' + $script:TaskName + ' y no corresponde a este paquete. No se modificara.')
    }
    $actualPrincipal = [string]$Existing.Principal.UserId
    if ($actualPrincipal -and $actualPrincipal -ine $script:CurrentUser -and $actualPrincipal -ine $script:CurrentSid) {
        throw ('La tarea pertenece a otra cuenta: ' + $actualPrincipal + '. Inicie sesion con dicha cuenta.')
    }
}
function Save-TaskBackup {
    $task = Get-TaskSafe
    if ($null -eq $task) { Write-Info 'No hay tarea existente para respaldar.'; return $null }
    Assert-TaskOwnership $task
    Ensure-Folders
    $filename = 'tarea_{0}.xml' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
    $path = Join-Path $script:BackupFolder $filename
    $xml = Export-ScheduledTask -TaskName $script:TaskName -TaskPath '\' -ErrorAction Stop
    [IO.File]::WriteAllText($path, $xml, [Text.Encoding]::Unicode)
    Write-Ok ('Respaldo XML generado: ' + $path)
    Write-AdminAudit 'Backup' 'OK' $path
    return $path
}
function Get-EnginePath {
    if (Test-Path -LiteralPath $script:InstalledEngine -PathType Leaf) { return $script:InstalledEngine }
    if (Test-Path -LiteralPath $script:EngineSource -PathType Leaf) { return $script:EngineSource }
    throw 'No se encuentra mantenimiento_profesional.ps1. Extraiga el paquete completo.'
}
function Install-Engine {
    Ensure-Folders
    if (-not (Test-Path -LiteralPath $script:EngineSource -PathType Leaf)) {
        if (Test-Path -LiteralPath $script:InstalledEngine -PathType Leaf) {
            Write-Info 'Origen no disponible. Se utilizara el motor previamente instalado.'
            return
        }
        throw 'No existe mantenimiento_profesional.ps1 junto a este administrador.'
    }
    if ([IO.Path]::GetFullPath($script:EngineSource) -ine [IO.Path]::GetFullPath($script:InstalledEngine)) {
        Copy-Item -LiteralPath $script:EngineSource -Destination $script:InstalledEngine -Force -ErrorAction Stop
    }
    Write-Ok ('Motor listo en: ' + $script:InstalledEngine)
    # No desbloquear archivos automaticamente ni pasar ExecutionPolicy Bypass.
    try {
        $zone = Get-Item -LiteralPath $script:InstalledEngine -Stream Zone.Identifier -ErrorAction SilentlyContinue
        if ($null -ne $zone) {
            Write-Warning 'El motor conserva marca de descarga de Internet. Revise el codigo y aplique Unblock-File si confia en el archivo.'
        }
    } catch { }
}
function Read-Choice([string]$Text, [int]$Min, [int]$Max, [int]$Default) {
    while ($true) {
        $raw = Read-Host ("{0} [{1}]" -f $Text,$Default)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        $number = 0
        if ([int]::TryParse($raw,[ref]$number) -and $number -ge $Min -and $number -le $Max) { return $number }
        Write-Warning ('Ingrese un numero entre {0} y {1}.' -f $Min,$Max)
    }
}
function Read-Time([string]$Default) {
    while ($true) {
        $raw = Read-Host ('Hora HH:mm (24 horas) [' + $Default + ']')
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        if ($raw -match '^([01][0-9]|2[0-3]):[0-5][0-9]$') { return $raw }
        Write-Warning 'Formato incorrecto. Ejemplo: 09:30 o 16:00.'
    }
}
function Get-FrequencyLabel([string]$Name) {
    switch ($Name) {
        'Daily'       { 'Diario' }
        'Weekly'      { 'Semanal' }
        'Monthly'     { 'Mensual' }
        'Bimonthly'   { 'Cada 2 meses' }
        'Quarterly'   { 'Cada 3 meses' }
        'FourMonthly' { 'Cada 4 meses' }
        'SemiAnnual'  { 'Cada 6 meses' }
        'Annual'      { 'Anual' }
    }
}
function Get-Interval([string]$Name) {
    switch ($Name) {
        'Monthly' { return 1 }
        'Bimonthly' { return 2 }
        'Quarterly' { return 3 }
        'FourMonthly' { return 4 }
        'SemiAnnual' { return 6 }
        'Annual' { return 12 }
        default { return 0 }
    }
}
function Get-MonthMask([int]$Interval, [int]$Anchor) {
    # Se aceptan solo divisores de 12: el patron se mantiene entre anos.
    if ((12 % $Interval) -ne 0) { throw 'El intervalo debe dividir 12 meses exactamente.' }
    $mask = 0
    for ($i = 0; $i -lt (12 / $Interval); $i++) {
        $monthNumber = (($Anchor - 1 + ($i * $Interval)) % 12) + 1
        $mask = $mask -bor (1 -shl ($monthNumber - 1))
    }
    return $mask
}
function Get-CalendarDescription([string]$Name, [string]$Clock, [int]$MonthDay, [int]$Anchor, [string]$Week) {
    $label = Get-FrequencyLabel $Name
    if ($Name -eq 'Daily') { return "$label, $Clock" }
    if ($Name -eq 'Weekly') { return "$label ($Week), $Clock" }
    $months = @('ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic')
    $interval = Get-Interval $Name
    $selected = @()
    for ($i = 0; $i -lt (12/$interval); $i++) { $selected += $months[(($Anchor - 1 + $i*$interval) % 12)] }
    return ('{0}, dia {1}, {2}, meses: {3}' -f $label,$MonthDay,$Clock,($selected -join ', '))
}
function Register-MaintenanceSchedule([string]$Name,[string]$Clock,[int]$MonthDay,[int]$Anchor,[string]$Week) {
    if ($Clock -notmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$') { throw 'Hora invalida.' }
    if ($MonthDay -lt 1 -or $MonthDay -gt 28) { throw 'Por consistencia, utilice un dia entre 1 y 28.' }
    if ($Anchor -lt 1 -or $Anchor -gt 12) { throw 'Mes de inicio invalido.' }
    $frequencyDescription = Get-CalendarDescription $Name $Clock $MonthDay $Anchor $Week
    Write-Title 'CONFIRMAR NUEVA PROGRAMACION'
    Write-Host ('Frecuencia: ' + $frequencyDescription)
    Write-Host ('Usuario: ' + $script:CurrentUser)
    Write-Host 'Modo: MENU, sin limpiezas automaticas, solo con sesion iniciada.'
    $existing = Get-TaskSafe
    Assert-TaskOwnership $existing
    if ($null -ne $existing) {
        Write-Info 'La programacion anterior se reemplazara. Se guardara un respaldo XML.'
    }
    if (-not (Confirm-IfNeeded 'Desea guardar esta programacion')) { Write-Info 'Sin cambios.'; return }
    if ($null -ne $existing) { [void](Save-TaskBackup) }
    Install-Engine
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $folder = $service.GetFolder('\')
    $definition = $service.NewTask(0)
    $definition.RegistrationInfo.Description = 'Menu interactivo SoporteTI. ' + $frequencyDescription
    $definition.RegistrationInfo.Author = $script:CurrentUser
    $definition.Principal.UserId = $script:CurrentUser
    $definition.Principal.LogonType = 3  # TASK_LOGON_INTERACTIVE_TOKEN
    $definition.Principal.RunLevel = 0   # TASK_RUNLEVEL_LUA (sin elevacion general)
    $definition.Settings.Enabled = $true
    $definition.Settings.StartWhenAvailable = $true
    $definition.Settings.AllowDemandStart = $true
    $definition.Settings.MultipleInstances = 2 # TASK_INSTANCES_IGNORE_NEW
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.ExecutionTimeLimit = 'PT3H'
    $action = $definition.Actions.Create(0)  # TASK_ACTION_EXEC
    $action.Path = $script:PowerShellExe
    $action.Arguments = ('-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "{0}"' -f $script:InstalledEngine)
    $action.WorkingDirectory = $script:InstallFolder
    $triggerType = if ($Name -eq 'Daily') { 2 } elseif ($Name -eq 'Weekly') { 3 } else { 4 }
    $trigger = $definition.Triggers.Create($triggerType)
    $trigger.StartBoundary = ((Get-Date -Format 'yyyy-MM-dd') + 'T' + $Clock + ':00')
    $trigger.Enabled = $true
    if ($Name -eq 'Daily') {
        $trigger.DaysInterval = 1
    } elseif ($Name -eq 'Weekly') {
        $daysMask = @{ SUN=1; MON=2; TUE=4; WED=8; THU=16; FRI=32; SAT=64 }
        $trigger.DaysOfWeek = $daysMask[$Week]
        $trigger.WeeksInterval = 1
    } else {
        $interval = Get-Interval $Name
        $trigger.DaysOfMonth = (1 -shl ($MonthDay - 1))
        $trigger.MonthsOfYear = Get-MonthMask $interval $Anchor
        $trigger.RunOnLastDayOfMonth = $false
    }
    # 6 = TASK_CREATE_OR_UPDATE; 3 = TASK_LOGON_INTERACTIVE_TOKEN.
    # Sin credenciales almacenadas, sin cuenta SYSTEM; no muestra GUI sin sesion.
    [void]$folder.RegisterTaskDefinition($script:TaskName,$definition,6,$script:CurrentUser,$null,3,$null)
    Ensure-Folders
    $configuration = [pscustomobject]@{
        Version = '2.0'; TaskName = $script:TaskName; User = $script:CurrentUser
        Frequency = $Name; Time = $Clock; Day = $MonthDay; Month = $Anchor; WeekDay = $Week
        Description = $frequencyDescription; InstalledScript = $script:InstalledEngine
        UpdatedAt = (Get-Date).ToString('o')
    }
    $configuration | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigFile -Encoding UTF8
    Write-Ok ('Tarea programada: ' + $frequencyDescription)
    Write-AdminAudit 'Schedule' 'OK' $frequencyDescription
    Write-Info 'No se realizan limpiezas hasta que una persona seleccione un modulo.'
    Write-Info 'La tarea se presenta solamente durante la sesion iniciada del usuario.'
    Show-Status
}
function Show-Status {
    Write-Title 'ESTADO DEL MANTENIMIENTO'
    $task = Get-TaskSafe
    if ($null -eq $task) { Write-Info 'No se encontro la tarea registrada.'; return }
    Write-Host ('Nombre: ' + $task.TaskName)
    Write-Host ('Estado: ' + $task.State)
    Write-Host ('Cuenta: ' + $task.Principal.UserId)
    Write-Host ('Inicio interactivo: ' + $task.Principal.LogonType)
    Write-Host ('Nivel: ' + $task.Principal.RunLevel)
    foreach ($trigger in $task.Triggers) {
        Write-Host ('Desencadenador real: ' + $trigger.CimClass.CimClassName)
        foreach ($propertyName in @('StartBoundary','DaysInterval','WeeksInterval','DaysOfWeek','DaysOfMonth','MonthsOfYear')) {
            $prop = $trigger.PSObject.Properties[$propertyName]
            if ($null -ne $prop -and $null -ne $prop.Value) {
                Write-Host ('  {0}: {1}' -f $propertyName,([string]::Join(', ',[string[]]@($prop.Value))))
            }
        }
    }
    if (Test-Path -LiteralPath $script:ConfigFile -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $script:ConfigFile -Raw | ConvertFrom-Json
            Write-Host ('Programacion registrada por consola: ' + $config.Description)
            Write-Info 'Si altero la tarea fuera de esta consola, confirme el desencadenador REAL arriba y la proxima ejecucion.'
        } catch { Write-Warning 'No se pudo leer la configuracion local.' }
    } else { Write-Info 'La tarea puede provenir de la version anterior del instalador.' }
    try {
        $info = Get-ScheduledTaskInfo -TaskName $script:TaskName -TaskPath '\' -ErrorAction Stop
        Write-Host ('Proxima ejecucion: ' + $info.NextRunTime)
        Write-Host ('Ultima ejecucion: ' + $info.LastRunTime)
        Write-Host ('Ultimo resultado (codigo): ' + $info.LastTaskResult)
        Write-Info 'Un codigo 0 no certifica que todas las acciones del mantenimiento hayan finalizado bien.'
    } catch { Write-Warning ('No se pudo consultar informacion de ejecucion: ' + $_.Exception.Message) }
    foreach ($action in $task.Actions) {
        Write-Host ('Ejecutable: ' + $action.Execute)
        Write-Host ('Argumentos: ' + $action.Arguments)
    }
}
function Start-Manual([bool]$Preview) {
    $engine = Get-EnginePath
    $args = '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "{0}"' -f $engine
    if ($Preview) { $args += ' -Preview' }
    Write-Info 'Se abrira una ventana nueva. El usuario selecciona que acciones ejecutar.'
    Start-Process -FilePath $script:PowerShellExe -ArgumentList $args -ErrorAction Stop | Out-Null
}
function Start-Registered {
    $task = Get-TaskSafe
    if ($null -eq $task) { throw 'No hay tarea registrada. Configure la programacion primero.' }
    Assert-TaskOwnership $task
    Start-ScheduledTask -TaskName $script:TaskName -TaskPath '\' -ErrorAction Stop
    Write-Ok 'Se solicito ejecutar la tarea. Verifique la ventana del usuario.'
    Write-AdminAudit 'Run' 'OK' 'Inicio solicitado al Programador de tareas; no confirma acciones dentro del menu.'
}
function Set-Enabled([bool]$Enabled) {
    $task = Get-TaskSafe
    if ($null -eq $task) { throw 'No existe la tarea.' }
    Assert-TaskOwnership $task
    if ($Enabled) {
        Enable-ScheduledTask -TaskName $script:TaskName -TaskPath '\' -ErrorAction Stop | Out-Null
        Write-Ok 'Programacion reactivada.'
        Write-AdminAudit 'Enable' 'OK' 'Tarea habilitada'
    } else {
        Disable-ScheduledTask -TaskName $script:TaskName -TaskPath '\' -ErrorAction Stop | Out-Null
        Write-Ok 'Programacion pausada. No se borraron scripts ni registros.'
        Write-AdminAudit 'Disable' 'OK' 'Tarea deshabilitada'
    }
}
function Remove-MaintenanceTask {
    $task = Get-TaskSafe
    if ($null -eq $task) { Write-Info 'La tarea no existe.'; return }
    Assert-TaskOwnership $task
    if (-not (Confirm-IfNeeded 'Eliminar la tarea programada (no borra reportes ni script)')) { Write-Info 'Cancelado.'; return }
    [void](Save-TaskBackup)
    Unregister-ScheduledTask -TaskName $script:TaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
    if (Test-Path -LiteralPath $script:ConfigFile) { Remove-Item -LiteralPath $script:ConfigFile -Force }
    Write-Ok 'Tarea eliminada. Motor, logs, reportes y XML conservados.'
    Write-AdminAudit 'Uninstall' 'OK' 'Se elimino solo la tarea programada.'
}
function Open-Logs {
    Write-Title 'BITACORAS Y REPORTES'
    Write-Host ('Carpeta logs: ' + $script:LogFolder)
    Write-Host ('Carpeta reportes: ' + $script:ReportFolder)
    Write-Host ('Auditoria del administrador: ' + $script:AuditFile)
    if (Test-Path -LiteralPath $script:ReportFolder -PathType Container) {
        $reports = @(Get-ChildItem -LiteralPath $script:ReportFolder -File -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
        foreach ($item in $reports) { Write-Host ('  ' + $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm') + '  ' + $item.Name) }
    }
    Write-Host '1. Abrir logs en el explorador'
    Write-Host '2. Abrir reportes JSON en el explorador'
    Write-Host '0. Volver'
    $answer = Read-Host 'Opcion'
    $folder = if ($answer -eq '1') { $script:LogFolder } elseif ($answer -eq '2') { $script:ReportFolder } else { $null }
    if ($null -ne $folder) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { Write-Info 'Todavia no existen registros de ese tipo.'; return }
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $folder + '"') | Out-Null
    }
}
function Show-History {
    Write-Title 'HISTORIAL DEL PROGRAMADOR DE TAREAS'
    $logName = 'Microsoft-Windows-TaskScheduler/Operational'
    try {
        $matching = @(Get-WinEvent -FilterHashtable @{LogName=$logName; Id=100,101,102,107,200,201} -MaxEvents 250 -ErrorAction Stop |
            Where-Object { $_.Message -like ('*' + $script:TaskName + '*') } | Select-Object -First 15)
        if ($matching.Count -eq 0) { Write-Info 'Sin eventos recientes para esta tarea o historial deshabilitado.'; return }
        $matching | Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List | Out-Host
    } catch { Write-Warning ('Historial no disponible: ' + $_.Exception.Message) }
}
function Show-SchedulingWizard {
    Write-Title 'PROGRAMAR MANTENIMIENTO'
    Write-Host ' 1. Todos los dias'
    Write-Host ' 2. Semanal'
    Write-Host ' 3. Mensual'
    Write-Host ' 4. Cada 2 meses'
    Write-Host ' 5. Cada 3 meses'
    Write-Host ' 6. Cada 4 meses'
    Write-Host ' 7. Cada 6 meses'
    Write-Host ' 8. Una vez al ano'
    Write-Host ' 0. Cancelar'
    $selected = Read-Host 'Frecuencia'
    $freqMap = @{'1'='Daily';'2'='Weekly';'3'='Monthly';'4'='Bimonthly';'5'='Quarterly';'6'='FourMonthly';'7'='SemiAnnual';'8'='Annual'}
    if ($selected -eq '0' -or -not $freqMap.ContainsKey($selected)) { Write-Info 'Operacion cancelada.'; return }
    $name = $freqMap[$selected]
    $clock = Read-Time '08:00'
    $monthDay = 15
    $anchor = 1
    $week = 'MON'
    if ($name -eq 'Weekly') {
        Write-Host '1=Lunes  2=Martes  3=Miercoles  4=Jueves  5=Viernes  6=Sabado  7=Domingo'
        $choice = Read-Choice 'Dia de la semana' 1 7 1
        $week = @('MON','TUE','WED','THU','FRI','SAT','SUN')[$choice-1]
    } elseif ($name -ne 'Daily') {
        $monthDay = Read-Choice 'Dia del mes (1-28 evita omisiones)' 1 28 15
        if ($name -ne 'Monthly') {
            $anchor = Read-Choice 'Mes de inicio (1=enero ... 12=diciembre)' 1 12 1
        }
    }
    Register-MaintenanceSchedule $name $clock $monthDay $anchor $week
}
function Show-MainMenu {
    Write-Title 'SOPORTE TI PROFESIONAL 2.0 - CONSOLA DE ADMINISTRACION'
    Write-Host ('Equipo: {0}  |  Cuenta: {1}' -f $env:COMPUTERNAME,$script:CurrentUser)
    Write-Host ' 1. Ejecutar mantenimiento manual (interactivo)'
    Write-Host ' 2. Ejecutar mantenimiento en SIMULACION'
    Write-Host ' 3. Programar o cambiar frecuencia y horario'
    Write-Host ' 4. Consultar tarea y proxima ejecucion'
    Write-Host ' 5. Ejecutar la tarea programada AHORA'
    Write-Host ' 6. Pausar tarea programada'
    Write-Host ' 7. Reactivar tarea programada'
    Write-Host ' 8. Respaldar configuracion XML de tarea'
    Write-Host ' 9. Abrir logs y reportes'
    Write-Host '10. Historial de errores y ejecuciones'
    Write-Host '11. Eliminar tarea programada (con respaldo)'
    Write-Host '12. Abrir Programador de tareas de Windows'
    Write-Host '13. Actualizar motor instalado (sin cambiar horario)'
    Write-Host ' 0. Salir'
    Write-Info 'La tarea solo abre el menu. Ninguna limpieza es automatica.'
}
function Invoke-Selected([string]$Operation) {
    switch ($Operation) {
        'Manual'       { Start-Manual $false }
        'Preview'      { Start-Manual $true }
        'Schedule'     {
            if ($Mode -eq 'Menu') { Show-SchedulingWizard }
            else { Register-MaintenanceSchedule $Frequency $Time $Day $Month $WeekDay }
        }
        'InstallDaily' { Register-MaintenanceSchedule 'Daily' '08:00' 15 1 'MON' }
        'Status'       { Show-Status }
        'Run'          { Start-Registered }
        'Disable'      { Set-Enabled $false }
        'Enable'       { Set-Enabled $true }
        'Backup'       { [void](Save-TaskBackup) }
        'Logs'         { Open-Logs }
        'History'      { Show-History }
        'Uninstall'    { Remove-MaintenanceTask }
        'Sync'         {
            if (Confirm-IfNeeded 'Actualizar el motor instalado sin cambiar el horario') { Install-Engine; Write-AdminAudit 'Sync' 'OK' 'Motor copiado, tarea sin cambios.' }
        }
        default        { throw ('Modo desconocido: ' + $Operation) }
    }
}

try {
    Import-Module ScheduledTasks -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $script:PowerShellExe -PathType Leaf)) {
        throw 'Este administrador requiere Windows PowerShell 5.1 en Windows 10/11.'
    }
    if ($Mode -ne 'Menu') {
        if ($Mode -eq 'Schedule' -and -not $PSBoundParameters.ContainsKey('Frequency')) {
            throw 'En modo Schedule debe indicar -Frequency (Daily/Weekly/Monthly/Bimonthly/Quarterly/FourMonthly/SemiAnnual/Annual).'
        }
        Invoke-Selected $Mode
    } else {
        do {
            Show-MainMenu
            $choice = Read-Host 'Seleccione opcion'
            if ($choice -eq '0') { break }
            $selection = @{'1'='Manual';'2'='Preview';'3'='Schedule';'4'='Status';'5'='Run';'6'='Disable';'7'='Enable';'8'='Backup';'9'='Logs';'10'='History';'11'='Uninstall';'12'='Taskschd';'13'='Sync'}
            if (-not $selection.ContainsKey($choice)) { Write-Warning 'Opcion no valida.'; continue }
            try {
                if ($selection[$choice] -eq 'Taskschd') { Start-Process 'taskschd.msc' | Out-Null }
                else { Invoke-Selected $selection[$choice] }
            } catch {
                Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
                Write-AdminAudit $selection[$choice] 'ERROR' $_.Exception.Message
                Write-Info 'Revise permisos, GPO y el nombre de la tarea. No deshabilite controles de seguridad.'
            }
            Wait-Enter
        } while ($true)
    }
} catch {
    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
    Write-AdminAudit $Mode 'ERROR' $_.Exception.Message
    exit 1
}

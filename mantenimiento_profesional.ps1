#requires -Version 5.1
<#
.SYNOPSIS
    Suite de mantenimiento TI interactivo para Windows 10/11.
.DESCRIPTION
    Corre como usuario normal. Eleva solo las tareas que lo exigen.
    No borra Prefetch, historiales, contrasenas, cookies ni perfiles.
    Incluye simulacion, confirmaciones, respaldo y auditoria.
.EXAMPLE
    .\mantenimiento_profesional.ps1
.EXAMPLE
    .\mantenimiento_profesional.ps1 -Preview
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu','Startup','RestoreStartup','Temp','SystemTemp','Browser','Components','WUDownloads','Recycle','Optimize','Health','Repair','Dns','Inventory','Full')]
    [string]$Action = 'Menu',
    [switch]$Preview
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:PreviewMode = [bool]$Preview
$script:BasePath = Join-Path $env:LOCALAPPDATA 'SoporteTI\Mantenimiento'
$script:LogPath = Join-Path $script:BasePath 'Logs'
$script:ReportPath = Join-Path $script:BasePath 'Reportes'
$script:BackupPath = Join-Path $script:BasePath 'Respaldos'
$script:Events = New-Object 'System.Collections.Generic.List[object]'
$script:TranscriptActive = $false
$script:FreeBefore = $null
$script:StartedAt = Get-Date

function Initialize-Workspace {
    foreach ($p in @($script:BasePath,$script:LogPath,$script:ReportPath,$script:BackupPath)) {
        if (-not (Test-Path -LiteralPath $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
    }
    $file = Join-Path $script:LogPath ('mantenimiento_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    try {
        Start-Transcript -Path $file -ErrorAction Stop | Out-Null
        $script:TranscriptActive = $true
    } catch { Write-Warning ('No se pudo iniciar la transcripcion: ' + $_.Exception.Message) }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-Operation([string]$Text) {
    $answer = Read-Host ($Text + ' [S/N]')
    return ($answer -match '^(s|si|sí)$')
}

function Get-FreeSpaceGB {
    try {
        $drive = [System.IO.Path]::GetPathRoot($env:SystemRoot).TrimEnd('\')
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $drive) -ErrorAction Stop
        if ($null -ne $disk -and $null -ne $disk.FreeSpace) { return [math]::Round(($disk.FreeSpace / 1GB), 2) }
    } catch { Write-Warning ('No se pudo medir espacio libre: ' + $_.Exception.Message) }
    return $null
}

function Invoke-AsAdministrator([string]$SelectedAction) {
    if (-not (Confirm-Operation 'Esta operacion requiere permisos administrativos. Solicitar elevacion UAC')) {
        return 'OMITIDO'
    }
    $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # La ruta del script se delimita con comillas para admitir espacios.
    $args = @('-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-File',('"' + $PSCommandPath + '"'),'-Action',$SelectedAction)
    if ($script:PreviewMode) { $args += '-Preview' }
    try {
        $p = Start-Process -FilePath $psExe -ArgumentList $args -Verb RunAs -PassThru -Wait -ErrorAction Stop
        if ($p.ExitCode -ne 0) { Write-Warning ("La sesion elevada finalizo con codigo {0}." -f $p.ExitCode) }
        return 'ELEVADO'
    } catch {
        Write-Warning ('Elevacion cancelada o denegada: ' + $_.Exception.Message)
        return 'OMITIDO'
    }
}

function Clear-SafeFiles([string]$Folder, [int]$OlderThanDays = 0) {
    if ([string]::IsNullOrWhiteSpace($Folder) -or -not (Test-Path -LiteralPath $Folder -PathType Container)) { return 0 }
    $resolved = (Resolve-Path -LiteralPath $Folder).ProviderPath
    # Nunca aceptar raices de unidades, enlaces simbolicos o puntos de union como carpeta base.
    if ($resolved -match '^[A-Za-z]:\\?$' -or $resolved.StartsWith('\\')) { throw 'Se rechazo una ruta raiz o compartida por seguridad.' }
    $root = Get-Item -LiteralPath $resolved -Force
    if (($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'No se limpian directorios enlazados.' }
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $count = 0
    $failures = 0
    # Se eliminan solo archivos, nunca carpetas completas. No se atraviesan enlaces.
    Get-ChildItem -LiteralPath $resolved -File -Force -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff -and (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) } |
        ForEach-Object {
            if ($script:PreviewMode) {
                $count++
            } else {
                try {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    $count++
                } catch { $failures++ }
            }
        }
    $suffix = if ($script:PreviewMode) { 'candidatos identificados' } else { 'archivos eliminados' }
    Write-Host ('  {0}: {1}; archivos bloqueados/omitidos: {2}' -f $suffix, $count, $failures)
    return $count
}

function Invoke-Startup {
    Write-Host "`n[INICIO] Seleccion explicita de aplicaciones; NO se infiere impacto desde el registro." -ForegroundColor Cyan
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    if (-not (Test-Path -LiteralPath $key)) { Write-Host 'No existen entradas compatibles para el usuario actual.'; return 'OMITIDO' }
    $entries = @((Get-ItemProperty -LiteralPath $key).PSObject.Properties |
        Where-Object { $_.Value -is [byte[]] -and $_.Value.Length -gt 0 -and $_.Value[0] -eq 2 } |
        Sort-Object Name)
    if ($entries.Count -eq 0) { Write-Host 'No hay entradas habilitadas compatibles.'; return 'OMITIDO' }
    for ($i = 0; $i -lt $entries.Count; $i++) { Write-Host (' {0,2}. {1}' -f ($i + 1), $entries[$i].Name) }
    $selected = Read-Host 'Numero de aplicacion que desea deshabilitar (0 = cancelar)'
    $index = 0
    if (-not [int]::TryParse($selected, [ref]$index) -or $index -lt 1 -or $index -gt $entries.Count) { return 'OMITIDO' }
    $entry = $entries[$index - 1]
    if (-not (Confirm-Operation ("Deshabilitar inicio de '{0}'" -f $entry.Name))) { return 'OMITIDO' }
    if ($script:PreviewMode) { Write-Host ('[SIMULACION] Se deshabilitaria: ' + $entry.Name); return 'SIMULACION' }
    $backup = Join-Path $script:BackupPath ('inicio_usuario_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    & reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' $backup /y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) { throw 'No se pudo respaldar el registro. No se modifico el inicio.' }
    $singleBackup = Join-Path $script:BackupPath ('inicio_elemento_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    [pscustomobject]@{Registro='HKCU:StartupApproved\Run'; Nombre=$entry.Name; DatosBase64=[Convert]::ToBase64String([byte[]]$entry.Value)} |
        ConvertTo-Json | Set-Content -LiteralPath $singleBackup -Encoding UTF8
    $newData = [byte[]]$entry.Value.Clone()
    $newData[0] = 3
    Set-ItemProperty -LiteralPath $key -Name $entry.Name -Value $newData -ErrorAction Stop
    Write-Host ('Deshabilitada: {0}. Respaldos: {1} y {2}' -f $entry.Name,$backup,$singleBackup)
    Write-Warning 'El respaldo .reg restaura el estado de TODAS las entradas de esa clave a la fecha del respaldo.'
    return 'OK'
}

function Invoke-RestoreStartup {
    Write-Host "`n[RECUPERACION] Restaurar UN elemento de inicio desde copia JSON." -ForegroundColor Cyan
    $backups = @(Get-ChildItem -LiteralPath $script:BackupPath -Filter 'inicio_elemento_*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($backups.Count -eq 0) { Write-Host 'No existen respaldos individuales.'; return 'OMITIDO' }
    for ($i=0; $i -lt $backups.Count; $i++) {
        Write-Host (' {0,2}. {1}' -f ($i + 1), $backups[$i].Name)
    }
    $inputNumber = Read-Host 'Elija respaldo (0 = cancelar)'
    $index = 0
    if (-not [int]::TryParse($inputNumber, [ref]$index) -or $index -lt 1 -or $index -gt $backups.Count) { return 'OMITIDO' }
    $record = Get-Content -LiteralPath $backups[$index-1].FullName -Raw | ConvertFrom-Json
    if ($record.Registro -ne 'HKCU:StartupApproved\Run' -or [string]::IsNullOrWhiteSpace($record.Nombre)) { throw 'Formato de respaldo invalido.' }
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    $bytes = [Convert]::FromBase64String($record.DatosBase64)
    if ($bytes.Length -lt 1) { throw 'Datos de respaldo invalidos.' }
    if (-not (Confirm-Operation ("Restaurar estado de '{0}'" -f $record.Nombre))) { return 'OMITIDO' }
    if ($script:PreviewMode) { Write-Host '[SIMULACION] Restauracion individual'; return 'SIMULACION' }
    Set-ItemProperty -LiteralPath $key -Name $record.Nombre -Value ([byte[]]$bytes) -ErrorAction Stop
    Write-Host ('Estado restaurado: ' + $record.Nombre)
    return 'OK'
}

function Invoke-Temp {
    if (-not (Confirm-Operation 'Borrar archivos temporales del usuario de mas de 2 dias')) { return 'OMITIDO' }
    Write-Host ('Carpeta: ' + $env:TEMP)
    $count = Clear-SafeFiles -Folder $env:TEMP -OlderThanDays 2
    Write-Host ('Total procesado: {0}' -f $count)
    if ($script:PreviewMode) { return 'SIMULACION' } else { return 'OK' }
}

function Invoke-SystemTemp {
    if (-not (Confirm-Operation 'Limpiar temporales del sistema con antiguedad minima de 7 dias')) { return 'OMITIDO' }
    $path = Join-Path $env:WINDIR 'Temp'
    Write-Host ('Carpeta: ' + $path)
    $count = Clear-SafeFiles -Folder $path -OlderThanDays 7
    Write-Host ('Total procesado: {0}' -f $count)
    if ($script:PreviewMode) { return 'SIMULACION' } else { return 'OK' }
}

function Invoke-Browser {
    if (-not (Confirm-Operation 'Borrar SOLO archivos de cache de navegadores cerrados (sin cookies, historial, sesiones ni claves)')) { return 'OMITIDO' }
    $total = 0
    $targets = @(
        @{ Name='Chrome'; Process='chrome'; Root=(Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') },
        @{ Name='Edge'; Process='msedge'; Root=(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') }
    )
    foreach ($browser in $targets) {
        if (Get-Process -Name $browser.Process -ErrorAction SilentlyContinue) {
            Write-Warning ("{0} esta abierto; se omite su cache." -f $browser.Name)
            continue
        }
        if (-not (Test-Path -LiteralPath $browser.Root)) { continue }
        $profiles = @(Get-ChildItem -LiteralPath $browser.Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^(Default|Profile [0-9]+)$' })
        foreach ($profile in $profiles) {
            foreach ($part in @('Cache','Code Cache','GPUCache')) {
                $target = Join-Path $profile.FullName $part
                if (Test-Path -LiteralPath $target) {
                    Write-Host ("{0} / {1} / {2}" -f $browser.Name,$profile.Name,$part)
                    $total += (Clear-SafeFiles -Folder $target)
                }
            }
        }
    }
    if (Get-Process -Name firefox -ErrorAction SilentlyContinue) {
        Write-Warning 'Firefox esta abierto; se omite su cache.'
    } else {
        $firefoxRoot = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
        if (Test-Path -LiteralPath $firefoxRoot) {
            foreach ($profile in @(Get-ChildItem -LiteralPath $firefoxRoot -Directory -ErrorAction SilentlyContinue)) {
                $target = Join-Path $profile.FullName 'cache2\entries'
                if (Test-Path -LiteralPath $target) {
                    Write-Host ("Firefox / {0} / cache2\entries" -f $profile.Name)
                    $total += (Clear-SafeFiles -Folder $target)
                }
            }
        }
    }
    Write-Host ('Total cache procesada: {0} archivos' -f $total)
    if ($script:PreviewMode) { return 'SIMULACION' } else { return 'OK' }
}

function Invoke-Components {
    Write-Host 'DISM limpia componentes reemplazados del almacen de Windows (no borra SoftwareDistribution manualmente).'
    if (-not (Confirm-Operation 'Ejecutar DISM /Online /Cleanup-Image /StartComponentCleanup')) { return 'OMITIDO' }
    if ($script:PreviewMode) { Write-Host '[SIMULACION] DISM /Online /Cleanup-Image /StartComponentCleanup'; return 'SIMULACION' }
    & (Join-Path $env:WINDIR 'System32\dism.exe') /Online /Cleanup-Image /StartComponentCleanup
    if ($LASTEXITCODE -ne 0) { throw ("DISM finalizo con codigo {0}." -f $LASTEXITCODE) }
    return 'OK'
}

function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($key in $keys) { if (Test-Path -LiteralPath $key) { return $true } }
    try {
        $session = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($null -ne $session -and $null -ne $session.PendingFileRenameOperations) { return $true }
    } catch {}
    return $false
}

function Invoke-WUDownloads {
    Write-Warning 'MODO AVANZADO: la cache de descargas Windows Update solo debe limpiarse tras verificar que NO hay instalaciones ni descargas activas.'
    if (Test-PendingReboot) { Write-Warning 'Reinicio pendiente: operacion bloqueada.'; return 'OMITIDO' }
    if (@(Get-Process -Name 'TiWorker','TrustedInstaller','MoUsoCoreWorker','SetupHost' -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-Warning 'Posible mantenimiento/actualizacion en curso: operacion bloqueada.'
        return 'OMITIDO'
    }
    if (-not (Confirm-Operation 'Confirmo haber verificado Windows Update sin actividad y deseo borrar SOLO archivos descargados de mas de 7 dias')) { return 'OMITIDO' }
    $download = Join-Path $env:WINDIR 'SoftwareDistribution\Download'
    if ($script:PreviewMode) {
        $cnt = Clear-SafeFiles -Folder $download -OlderThanDays 7
        Write-Host ("[SIMULACION] {0} archivos candidatos." -f $cnt)
        return 'SIMULACION'
    }
    $services = @('bits','wuauserv')
    $previousRunning = New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($name in $services) {
            $svc = Get-Service -Name $name -ErrorAction Stop
            if ($svc.Status -eq 'Running') {
                $previousRunning.Add($name)
                Stop-Service -Name $name -ErrorAction Stop
            }
        }
        foreach ($name in $services) {
            if ((Get-Service -Name $name -ErrorAction Stop).Status -ne 'Stopped') { throw ('No se pudo detener ' + $name) }
        }
        $cnt = Clear-SafeFiles -Folder $download -OlderThanDays 7
        Write-Host ('Archivos antiguos eliminados de cache WU: ' + $cnt)
    } finally {
        foreach ($name in $previousRunning) {
            try { Start-Service -Name $name -ErrorAction Stop } catch { Write-Warning ('Revisar servicio ' + $name + ': ' + $_.Exception.Message) }
        }
    }
    return 'OK'
}

function Invoke-Recycle {
    Write-Warning 'El vaciado de papelera es irreversible para los archivos afectados.'
    if (-not (Confirm-Operation 'Vaciar la papelera de reciclaje del usuario')) { return 'OMITIDO' }
    if ($script:PreviewMode) { Write-Host '[SIMULACION] Clear-RecycleBin'; return 'SIMULACION' }
    Clear-RecycleBin -Force -ErrorAction Stop
    return 'OK'
}

function Invoke-Optimize {
    $letter = [System.IO.Path]::GetPathRoot($env:SystemRoot).Substring(0,1)
    Write-Host ('Windows elegira automaticamente la optimizacion apropiada para la unidad {0}: (SSD/TRIM o HDD/defrag).' -f $letter)
    if (-not (Confirm-Operation 'Optimizar unidad de sistema')) { return 'OMITIDO' }
    if ($script:PreviewMode) { Write-Host ('[SIMULACION] Optimize-Volume -DriveLetter ' + $letter); return 'SIMULACION' }
    Optimize-Volume -DriveLetter $letter -Verbose -ErrorAction Stop
    return 'OK'
}

function Invoke-Health {
    Write-Host 'Diagnostico NO reparador: DISM /ScanHealth y SFC /verifyonly.'
    if (-not (Confirm-Operation 'Analizar integridad de Windows (puede tardar)')) { return 'OMITIDO' }
    if ($script:PreviewMode) { Write-Host '[SIMULACION] DISM /ScanHealth + SFC /verifyonly'; return 'SIMULACION' }
    & (Join-Path $env:WINDIR 'System32\dism.exe') /Online /Cleanup-Image /ScanHealth
    $dismExit = $LASTEXITCODE
    & (Join-Path $env:WINDIR 'System32\sfc.exe') /verifyonly
    $sfcExit = $LASTEXITCODE
    Write-Host ('Codigos de salida: DISM={0}; SFC={1}' -f $dismExit,$sfcExit)
    if ($dismExit -ne 0 -or $sfcExit -ne 0) { throw 'Se reportaron errores o problemas de integridad. Revisar la transcripcion.' }
    return 'OK'
}

function Invoke-Repair {
    Write-Warning 'REPARACION: DISM /RestoreHealth y SFC /scannow pueden demandar tiempo, reinicio y conexion a Windows Update/WSUS.'
    if (-not (Confirm-Operation 'Iniciar reparacion del sistema operativo')) { return 'OMITIDO' }
    if ($script:PreviewMode) { Write-Host '[SIMULACION] DISM /RestoreHealth + SFC /scannow'; return 'SIMULACION' }
    & (Join-Path $env:WINDIR 'System32\dism.exe') /Online /Cleanup-Image /RestoreHealth
    $dismExit = $LASTEXITCODE
    if ($dismExit -notin @(0,3010)) { throw ("DISM fallo con codigo {0}. No se lanzo SFC." -f $dismExit) }
    & (Join-Path $env:WINDIR 'System32\sfc.exe') /scannow
    $sfcExit = $LASTEXITCODE
    Write-Host ("Codigos DISM={0}; SFC={1}" -f $dismExit,$sfcExit)
    if ($sfcExit -ne 0) { throw 'SFC reporto error o inconsistencias no resueltas; consultar el log y CBS.log.' }
    if ($dismExit -eq 3010) { Write-Warning 'Windows solicita reiniciar.' }
    return 'OK'
}

function Invoke-Inventory {
    Write-Host 'Generando inventario basico no invasivo...' -ForegroundColor Cyan
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
        Select-Object DeviceID,FileSystem,@{Name='CapacidadGB';Expression={[math]::Round($_.Size/1GB,2)}},@{Name='LibreGB';Expression={[math]::Round($_.FreeSpace/1GB,2)}})
    $inventory = [pscustomobject]@{
        Fecha=(Get-Date).ToString('o'); Equipo=$env:COMPUTERNAME
        SO=$os.Caption; Version=$os.Version; UltimoArranque=([datetime]$os.LastBootUpTime).ToString('o')
        CPU=$cpu.Name; RAM_GB=[math]::Round($os.TotalVisibleMemorySize/1MB,2)
        Discos=$disks
    }
    $destination = Join-Path $script:ReportPath ('inventario_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    Write-Host ('SO: {0} | RAM: {1} GB | CPU: {2}' -f $inventory.SO,$inventory.RAM_GB,$inventory.CPU)
    $disks | Format-Table | Out-Host
    if ($script:PreviewMode) { Write-Host '[SIMULACION] No se exporta el inventario.'; return 'SIMULACION' }
    $inventory | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $destination -Encoding UTF8
    Write-Host ('Inventario JSON: ' + $destination)
    return 'OK'
}

function Invoke-Dns {
    if (-not (Confirm-Operation 'Vaciar cache de resolucion DNS local')) { return 'OMITIDO' }
    if ($script:PreviewMode) { Write-Host '[SIMULACION] Clear-DnsClientCache'; return 'SIMULACION' }
    Clear-DnsClientCache -ErrorAction Stop
    return 'OK'
}

function Invoke-MaintenanceAction([string]$Name) {
    $adminActions = @('SystemTemp','Components','WUDownloads','Optimize','Health','Repair','Dns')
    $status = 'OK'
    $date = Get-Date
    try {
        if (($adminActions -contains $Name) -and -not $script:PreviewMode -and -not (Test-Administrator)) {
            $status = Invoke-AsAdministrator -SelectedAction $Name
        } else {
            switch ($Name) {
                'Startup'     { $status = Invoke-Startup; break }
                'RestoreStartup' { $status = Invoke-RestoreStartup; break }
                'Temp'        { $status = Invoke-Temp; break }
                'SystemTemp'  { $status = Invoke-SystemTemp; break }
                'Browser'     { $status = Invoke-Browser; break }
                'Components'  { $status = Invoke-Components; break }
                'WUDownloads' { $status = Invoke-WUDownloads; break }
                'Recycle'     { $status = Invoke-Recycle; break }
                'Optimize'    { $status = Invoke-Optimize; break }
                'Health'      { $status = Invoke-Health; break }
                'Repair'      { $status = Invoke-Repair; break }
                'Inventory'   { $status = Invoke-Inventory; break }
                'Dns'         { $status = Invoke-Dns; break }
                default       { throw ('Modulo desconocido: ' + $Name) }
            }
        }
    } catch {
        $status = 'ERROR'
        Write-Warning ('Error en ' + $Name + ': ' + $_.Exception.Message)
    }
    $script:Events.Add([pscustomobject]@{Fecha=$date.ToString('o'); Accion=$Name; Estado=$status; Simulacion=$script:PreviewMode})
    Write-Host ('[RESULTADO] {0}: {1}' -f $Name,$status) -ForegroundColor $(if ($status -eq 'ERROR') { 'Red' } else { 'Green' })
    return $status
}

function Invoke-Full {
    Write-Host 'Modo asistido: cada modulo pide consentimiento. No incluye inicio, WU avanzada, Prefetch ni reparaciones.' -ForegroundColor Yellow
    foreach ($item in @('Temp','Browser','SystemTemp','Recycle','Optimize','Dns')) {
        Write-Host ("`n--- Modulo: " + $item + ' ---') -ForegroundColor Cyan
        [void](Invoke-MaintenanceAction -Name $item)
    }
}

function Write-Report {
    $end = Get-Date
    $report = [pscustomobject]@{
        Equipo = $env:COMPUTERNAME
        Usuario = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        FechaInicio = $script:StartedAt.ToString('o')
        FechaFin = $end.ToString('o')
        VistaPrevia = $script:PreviewMode
        GB_Libres_Inicio = $script:FreeBefore
        GB_Libres_Final = Get-FreeSpaceGB
        Acciones = @($script:Events.ToArray())
    }
    $reportFile = Join-Path $script:ReportPath ('reporte_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    try {
        $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportFile -Encoding UTF8 -ErrorAction Stop
        Write-Host ('Reporte JSON guardado: ' + $reportFile)
    } catch { Write-Warning ('No se pudo guardar reporte: ' + $_.Exception.Message) }
}

function Show-Menu {
    Write-Host ''
    Write-Host '========================================================' -ForegroundColor Cyan
    Write-Host '  SOPORTE TI | MANTENIMIENTO PROFESIONAL | Windows 10/11' -ForegroundColor Cyan
    Write-Host '========================================================' -ForegroundColor Cyan
    Write-Host ('Perfil: {0} | Admin: {1} | Simulacion: {2}' -f $env:USERNAME,(Test-Administrator),$script:PreviewMode)
    Write-Host ' 1. Gestionar programas de inicio (eleccion manual + backup)'
    Write-Host ' 2. Limpiar temporales del usuario (> 2 dias)'
    Write-Host ' 3. Limpiar cache de navegadores cerrados'
    Write-Host ' 4. Limpiar componentes Windows Update (DISM, recomendado) [Admin]'
    Write-Host ' 5. Vaciar papelera (confirmacion)'
    Write-Host ' 6. Optimizar unidad SSD/HDD automaticamente [Admin]'
    Write-Host ' 7. Diagnostico de Windows: DISM/SFC (sin reparar) [Admin]'
    Write-Host ' 8. Vaciar cache DNS [Admin]'
    Write-Host ' 9. Mantenimiento integral ASISTIDO (confirma cada modulo)'
    Write-Host '10. Limpieza AVANZADA descargas Windows Update (> 7 dias) [Admin]'
    Write-Host '11. Limpiar temporales de Windows (> 7 dias) [Admin]'
    Write-Host '12. Activar/desactivar vista previa (sin cambios)'
    Write-Host '13. Restaurar programa de inicio desde respaldo individual'
    Write-Host '14. Inventario del equipo + JSON (solo lectura)'
    Write-Host '15. Reparar Windows DISM /RestoreHealth + SFC /scannow [Admin]'
    Write-Host ' 0. Salir'
    Write-Host 'NOTA: Prefetch NO se borra. Las operaciones [Admin] solicitan UAC.' -ForegroundColor Yellow
}

try {
    Initialize-Workspace
    $script:FreeBefore = Get-FreeSpaceGB
    Write-Host ('Soporte TI | Inicio: {0} | Disco libre: {1} GB' -f $script:StartedAt, $script:FreeBefore) -ForegroundColor Cyan
    if ($Action -eq 'Full') {
        Invoke-Full
    } elseif ($Action -ne 'Menu') {
        [void](Invoke-MaintenanceAction -Name $Action)
        [void](Read-Host 'Pulse ENTER para cerrar esta ventana')
    } else {
        do {
            Show-Menu
            $choice = Read-Host 'Seleccione opcion'
            switch ($choice) {
                '1'  { [void](Invoke-MaintenanceAction 'Startup') }
                '2'  { [void](Invoke-MaintenanceAction 'Temp') }
                '3'  { [void](Invoke-MaintenanceAction 'Browser') }
                '4'  { [void](Invoke-MaintenanceAction 'Components') }
                '5'  { [void](Invoke-MaintenanceAction 'Recycle') }
                '6'  { [void](Invoke-MaintenanceAction 'Optimize') }
                '7'  { [void](Invoke-MaintenanceAction 'Health') }
                '8'  { [void](Invoke-MaintenanceAction 'Dns') }
                '9'  { Invoke-Full }
                '10' { [void](Invoke-MaintenanceAction 'WUDownloads') }
                '11' { [void](Invoke-MaintenanceAction 'SystemTemp') }
                '13' { [void](Invoke-MaintenanceAction 'RestoreStartup') }
                '14' { [void](Invoke-MaintenanceAction 'Inventory') }
                '15' { [void](Invoke-MaintenanceAction 'Repair') }
                '12' {
                    $script:PreviewMode = -not $script:PreviewMode
                    Write-Host ('Modo simulacion: ' + $script:PreviewMode) -ForegroundColor Yellow
                }
                '0' { Write-Host 'Finalizando y guardando reporte...' }
                default { Write-Warning 'Opcion no valida.' }
            }
        } while ($choice -ne '0')
    }
} catch {
    Write-Error ('Error fatal: ' + $_.Exception.Message) -ErrorAction Continue
} finally {
    Write-Report
    if ($script:TranscriptActive) { try { Stop-Transcript | Out-Null } catch {} }
}

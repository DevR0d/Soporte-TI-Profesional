#requires -Version 5.1
[CmdletBinding()]
param()
Write-Host '=== DIAGNOSTICO DEL PAQUETE SOPORTE TI PROFESIONAL 2.0 ===' -ForegroundColor Cyan
$required = @('administrador_tareas.ps1','mantenimiento_profesional.ps1','Administrador_SoporteTI.bat')
$errorCount = 0
foreach ($name in $required) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host ('FALTA: ' + $name) -ForegroundColor Red
        $errorCount++
        continue
    }
    Write-Host ('OK: ' + $name) -ForegroundColor Green
}
foreach ($item in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($item.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        $errorCount += $errors.Count
        Write-Host ('ERROR SINTAXIS: ' + $item.Name) -ForegroundColor Red
        foreach ($err in $errors) { Write-Host ('  linea {0}: {1}' -f $err.Extent.StartLineNumber,$err.Message) }
    } else { Write-Host ('Sintaxis correcta: ' + $item.Name) -ForegroundColor Green }
}
$manifestPath = Join-Path $PSScriptRoot 'SHA256SUMS.txt'
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    foreach ($line in @(Get-Content -LiteralPath $manifestPath)) {
        if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') { continue }
        $expected = $Matches[1]
        $filename = $Matches[2]
        $path = Join-Path $PSScriptRoot $filename
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-Host ('FALTA (manifiesto): ' + $filename) -ForegroundColor Red
            $errorCount++
            continue
        }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ine $expected) {
            Write-Host ('HASH INCORRECTO: ' + $filename) -ForegroundColor Red
            $errorCount++
        }
    }
    Write-Host 'Comprobacion SHA256 completada (integridad, no firma digital).' -ForegroundColor Cyan
}
Write-Host "`nPoliticas de ejecucion efectivas:" -ForegroundColor Cyan
Get-ExecutionPolicy -List | Format-Table -AutoSize | Out-Host
try {
    Import-Module ScheduledTasks -ErrorAction Stop
    Write-Host 'OK: modulo ScheduledTasks accesible.' -ForegroundColor Green
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    [void]$service.GetFolder('\')
    Write-Host 'OK: API COM de lectura del Programador accesible.' -ForegroundColor Green
} catch {
    Write-Host ('ERROR: modulo ScheduledTasks: ' + $_.Exception.Message) -ForegroundColor Red
    $errorCount++
}
if ($errorCount -gt 0) {
    Write-Host ('[ERROR] Hallazgos: ' + $errorCount) -ForegroundColor Red
    exit 1
}
Write-Host 'VALIDACION LOCAL BASICA APROBADA (no sustituye prueba real de Programador de tareas).' -ForegroundColor Green

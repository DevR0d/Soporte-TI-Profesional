# mantenimiento_profesional.ps1
# Rutina integral de soporte TI con menú, logging TXT/HTML y funciones avanzadas

# Rutas de log
$logPathTxt = "$env:USERPROFILE\Documents\Mantenimiento_Log.txt"
$logPathHtml = "$env:USERPROFILE\Documents\Mantenimiento_Log.html"
$global:Eventos = @()

function Escribir-Log($accion, $detalle) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $linea = "$timestamp - $accion - $detalle"
    Add-Content -Path $logPathTxt -Value $linea
    $global:Eventos += [PSCustomObject]@{FechaHora=$timestamp;Accion=$accion;Detalle=$detalle}
}

function Generar-ReporteHTML {
    $html = @"
<html><head><title>Reporte de Mantenimiento</title>
<style>
body { font-family: Arial; margin: 20px; }
h1 { color: #2E86C1; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
th { background-color: #f2f2f2; }
</style></head><body>
<h1>Reporte de Mantenimiento - $(Get-Date)</h1>
<table><tr><th>Fecha/Hora</th><th>Acción</th><th>Detalle</th></tr>
"@
    foreach ($evento in $global:Eventos) {
        $html += "<tr><td>$($evento.FechaHora)</td><td>$($evento.Accion)</td><td>$($evento.Detalle)</td></tr>`n"
    }
    $html += "</table></body></html>"
    Set-Content -Path $logPathHtml -Value $html
}

# === Funciones de soporte ===
function Deshabilitar-ProgramasInicio {
    Escribir-Log "Inicio" "Deshabilitar programas de alto impacto"
    $startupImpactPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    $startupApps = Get-ItemProperty -Path $startupImpactPath
    foreach ($property in $startupApps.PSObject.Properties) {
        $programName = $property.Name
        $programData = $property.Value
        $estado = $programData[0]; $impacto = $programData[1]
        if ($impacto -eq 3 -and $estado -eq 2) {
            Escribir-Log "Inicio" "Deshabilitado $programName por alto impacto"
            $programData[0] = 3
            Set-ItemProperty -Path $startupImpactPath -Name $programName -Value $programData
        }
    }
}

function Limpiar-Temporales {
    Escribir-Log "Limpieza" "Archivos temporales"
    $tempPaths = @("$env:TEMP", "C:\Windows\Temp")
    foreach ($path in $tempPaths) {
        Remove-Item "$path\*" -Force -Recurse -ErrorAction SilentlyContinue
    }
}

function Limpiar-CacheNavegadores {
    Escribir-Log "Limpieza" "Caché de navegadores"
    $browserCachePaths = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:APPDATA\Mozilla\Firefox\Profiles"
    )
    foreach ($path in $browserCachePaths) {
        if (Test-Path $path) {
            Remove-Item "$path\*" -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

function Limpiar-WindowsUpdate {
    Escribir-Log "Limpieza" "Descargas de Windows Update"
    $wuLogs = "C:\Windows\SoftwareDistribution\Download"
    if (Test-Path $wuLogs) {
        Remove-Item "$wuLogs\*" -Force -Recurse -ErrorAction SilentlyContinue
    }
}

function Limpiar-Prefetch {
    Escribir-Log "Limpieza" "Prefetch"
    $prefetchPath = "C:\Windows\Prefetch"
    if (Test-Path $prefetchPath) {
        Remove-Item "$prefetchPath\*" -Force -Recurse -ErrorAction SilentlyContinue
    }
}

function Vaciar-Papelera {
    Escribir-Log "Limpieza" "Papelera de reciclaje"
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
}

function Optimizar-Disco {
    Escribir-Log "Optimización" "Desfragmentación disco C"
    Optimize-Volume -DriveLetter C -Verbose | ForEach-Object {
        Escribir-Log "Optimización" $_.ToString()
    }
}

function Reparar-Sistema {
    Escribir-Log "Reparación" "Ejecutando SFC /scannow"
    Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow
}

function Revisar-Disco {
    Escribir-Log "Revisión" "Ejecutando CHKDSK /f en C:"
    Start-Process -FilePath "chkdsk.exe" -ArgumentList "C: /f" -Wait -NoNewWindow
}

function Reiniciar-Servicios {
    Escribir-Log "Servicios" "Reiniciando Windows Update y BITS"
    Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Restart-Service -Name bits -Force -ErrorAction SilentlyContinue
}

# === Menú interactivo ===
function Mostrar-Menu {
    Write-Output "`n=== Menú de Mantenimiento ==="
    Write-Output "1. Deshabilitar programas de inicio de alto impacto"
    Write-Output "2. Limpiar archivos temporales"
    Write-Output "3. Limpiar caché de navegadores"
    Write-Output "4. Limpiar descargas de Windows Update"
    Write-Output "5. Limpiar Prefetch"
    Write-Output "6. Vaciar papelera de reciclaje"
    Write-Output "7. Optimizar disco"
    Write-Output "8. Reparar archivos del sistema (SFC)"
    Write-Output "9. Revisar disco (CHKDSK)"
    Write-Output "10. Reiniciar servicios críticos"
    Write-Output "11. Ejecutar todas las acciones"
    Write-Output "0. Salir"
}

Escribir-Log "Inicio" "Rutina de soporte TI"

do {
    Mostrar-Menu
    $opcion = Read-Host "Seleccione una opción"
    switch ($opcion) {
        1 { Deshabilitar-ProgramasInicio }
        2 { Limpiar-Temporales }
        3 { Limpiar-CacheNavegadores }
        4 { Limpiar-WindowsUpdate }
        5 { Limpiar-Prefetch }
        6 { Vaciar-Papelera }
        7 { Optimizar-Disco }
        8 { Reparar-Sistema }
        9 { Revisar-Disco }
        10 { Reiniciar-Servicios }
        11 {
            Deshabilitar-ProgramasInicio
            Limpiar-Temporales
            Limpiar-CacheNavegadores
            Limpiar-WindowsUpdate
            Limpiar-Prefetch
            Vaciar-Papelera
            Optimizar-Disco
            Reparar-Sistema
            Revisar-Disco
            Reiniciar-Servicios
        }
        0 { Escribir-Log "Salida" "Usuario terminó la rutina" }
        default { Write-Output "Opción inválida" }
    }
} while ($opcion -ne 0)

Escribir-Log "Fin" "Rutina completada"
Generar-ReporteHTML
Write-Output "Reporte generado en: $logPathHtml"

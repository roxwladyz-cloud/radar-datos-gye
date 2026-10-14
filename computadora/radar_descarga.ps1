<#
  Radar Urbano - Descarga automatica desde tu computadora (Ecuador)

  El portal del Ministerio solo acepta conexiones desde Ecuador, por eso este
  programa corre en tu computadora: revisa si hay un Excel nuevo de
  homicidios intencionales y, si lo hay, lo sube a GitHub. Alla el robot
  lo procesa y actualiza los datos de la app.

  Instalacion: doble clic en INSTALAR.bat (solo una vez).
#>
param(
    [switch]$Instalar,
    [string]$Portal = "https://datosabiertos.gob.ec",
    [string]$GitHubApi = "https://api.github.com",
    [string]$Repo = "roxwladyz-cloud/radar-datos-gye"
)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Carpeta   = Join-Path $env:LOCALAPPDATA "RadarUrbano"
$LlaveArch = Join-Path $Carpeta "llave_github.txt"
$Estado    = Join-Path $Carpeta "ultimo_excel.txt"
$Registro  = Join-Path $Carpeta "registro.txt"
$Tarea     = "Radar Urbano - Descarga Ministerio"
$Cabecera  = @{ "User-Agent" = "RadarUrbano/1.0 (github.com/$Repo)" }

function Anotar([string]$texto) {
    $linea = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm"), $texto
    Write-Host $linea
    if (-not (Test-Path $Carpeta)) { New-Item -ItemType Directory -Path $Carpeta | Out-Null }
    Add-Content -Path $Registro -Value $linea -Encoding UTF8
}

function Leer-Llave {
    $cifrada = Get-Content $LlaveArch -Raw
    $segura = ConvertTo-SecureString $cifrada.Trim()
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Instalar {
    Write-Host ""
    Write-Host "=== Instalacion de Radar Urbano ===" -ForegroundColor Cyan
    Write-Host "Pega la llave de GitHub (empieza con github_pat_) y presiona Enter."
    Write-Host "Por seguridad no se vera mientras la pegas."
    $segura = Read-Host -AsSecureString "Llave"
    if ($segura.Length -lt 20) { throw "La llave parece incompleta. Vuelve a ejecutar INSTALAR.bat." }

    if (-not (Test-Path $Carpeta)) { New-Item -ItemType Directory -Path $Carpeta | Out-Null }
    # Se guarda cifrada con tu usuario de Windows: nadie mas puede leerla
    ConvertFrom-SecureString $segura | Set-Content -Path $LlaveArch -Encoding ASCII

    $destino = Join-Path $Carpeta "radar_descarga.ps1"
    Copy-Item -Path $PSCommandPath -Destination $destino -Force
    try { Unblock-File -Path $destino } catch {}

    $accion = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destino`""
    $cuando = New-ScheduledTaskTrigger -Daily -At "10:00"
    $ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName $Tarea -Action $accion -Trigger $cuando `
        -Settings $ajustes -Description "Sube a GitHub el Excel nuevo del Ministerio para Radar Urbano" `
        -Force | Out-Null

    # StartWhenAvailable: si a las 10:00 la computadora estaba apagada, corre apenas se encienda
    Anotar "Instalado. La revision se hara todos los dias a las 10:00 (o al encender, si estaba apagada)."
    Write-Host ""
    Write-Host "Haciendo la primera revision ahora..." -ForegroundColor Cyan
}

function Buscar-ExcelMasReciente {
    $url = "$Portal/api/3/action/package_show?id=homicidios-intencionales"
    $resp = Invoke-RestMethod -Uri $url -Headers $Cabecera -TimeoutSec 120
    if (-not $resp.success) { throw "El portal respondio sin exito." }
    $candidatos = @()
    foreach ($r in $resp.result.resources) {
        $texto = "$($r.name) $($r.url)"
        if ("$($r.url)" -notmatch "\.xlsx?$") { continue }
        if ($texto -match "pm_(\d{4})") {
            $candidatos += [pscustomobject]@{
                Anio = [int]$Matches[1]; Modificado = "$($r.last_modified)"
                Url = "$($r.url)"; Nombre = "$($r.name)"
            }
        }
    }
    if ($candidatos.Count -eq 0) { throw "No se encontro ningun Excel 'pm_AAAA' en el portal." }
    return $candidatos | Sort-Object -Property Anio, Modificado -Descending | Select-Object -First 1
}

function Subir-AGitHub([string]$ruta, [string]$nombre, [string]$llave) {
    $cab = @{
        "Authorization" = "Bearer $llave"
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "RadarUrbano"
    }
    $api = "$GitHubApi/repos/$Repo/contents/$([Uri]::EscapeDataString($nombre))"
    $cuerpo = @{
        message = "Excel del Ministerio: $nombre (subido desde la computadora)"
        content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ruta))
        branch  = "main"
    }
    # Si ya existe un archivo con ese nombre, GitHub pide su "sha" para reemplazarlo
    try {
        $existe = Invoke-RestMethod -Uri "$api`?ref=main" -Headers $cab -TimeoutSec 60
        $cuerpo.sha = $existe.sha
    } catch {}
    $json = $cuerpo | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $api -Method Put -Headers $cab -Body ([Text.Encoding]::UTF8.GetBytes($json)) `
        -ContentType "application/json" -TimeoutSec 300 | Out-Null
}

try {
    if ($Instalar) { Instalar }
    if (-not (Test-Path $LlaveArch)) { throw "Falta la llave de GitHub. Ejecuta INSTALAR.bat." }

    $excel = Buscar-ExcelMasReciente
    $huella = "$($excel.Url)|$($excel.Modificado)"
    $anterior = ""
    if (Test-Path $Estado) { $anterior = (Get-Content $Estado -Raw).Trim() }
    if ($huella -eq $anterior) {
        Anotar "Sin novedades: el Ministerio no ha publicado un Excel nuevo."
        exit 0
    }

    $nombre = Split-Path ([Uri]$excel.Url).AbsolutePath -Leaf
    $temporal = Join-Path $env:TEMP $nombre
    Anotar "Excel nuevo encontrado: $nombre. Descargando..."
    Invoke-WebRequest -Uri $excel.Url -OutFile $temporal -Headers $Cabecera -UseBasicParsing -TimeoutSec 600
    $tam = (Get-Item $temporal).Length
    if ($tam -lt 10000) { throw "El archivo descargado es muy pequeno ($tam bytes); no se sube." }

    Subir-AGitHub -ruta $temporal -nombre $nombre -llave (Leer-Llave)
    Set-Content -Path $Estado -Value $huella -Encoding UTF8
    Remove-Item $temporal -ErrorAction SilentlyContinue
    Anotar "Listo: $nombre subido a GitHub ($([math]::Round($tam/1MB,1)) MB). El robot actualizara la app."
}
catch {
    $detalle = $_.Exception.Message
    if ($detalle -match "401|Bad credentials") {
        $detalle = "GitHub rechazo la llave (vencida o borrada). Crea una nueva y ejecuta INSTALAR.bat. ($detalle)"
    }
    Anotar "ERROR: $detalle"
    exit 1
}
finally {
    if ($Instalar) {
        Write-Host ""
        Write-Host "Puedes cerrar esta ventana." -ForegroundColor Green
        Read-Host "Presiona Enter para salir" | Out-Null
    }
}

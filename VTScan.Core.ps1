# =====================================================================
#  VTScan.Core.ps1  -  Motor compartido (config, consulta VT, popup, menu)
#  No ejecutar directo. Lo usan VTScan.ps1 y VTScan-CommandCenter.ps1
# =====================================================================

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# La config (incluida la API Key) vive FUERA del repo, en %APPDATA%\VTScan
$script:VTConfigDir  = Join-Path $env:APPDATA 'VTScan'
$script:VTConfigPath = Join-Path $script:VTConfigDir 'config.json'

# Extensiones "interesantes" por defecto (ejecutables / potencialmente peligrosas)
$script:VTKnownExtensions = @('.exe','.dll','.msi','.sys','.bat','.ps1','.cmd','.scr','.vbs','.js','.jar','.msix','.com')

function Get-VTDefaultConfig {
    [pscustomobject]@{
        ApiKey              = ''
        Extensions          = @('.exe','.dll','.msi','.sys','.bat','.ps1','.cmd','.scr')
        YellowThreshold     = 1     # >= este nro de detecciones -> amarillo
        RedThreshold        = 5     # >= este nro de detecciones -> rojo
        AutoUploadUnknown   = $false
        NotificationSeconds = 12
    }
}

function Get-VTConfig {
    if (Test-Path $script:VTConfigPath) {
        try   { $cfg = Get-Content $script:VTConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $cfg = Get-VTDefaultConfig }
    } else {
        $cfg = Get-VTDefaultConfig
    }
    # Asegura que existan todos los campos (por si la config es vieja)
    $def = Get-VTDefaultConfig
    foreach ($p in $def.PSObject.Properties) {
        if (-not $cfg.PSObject.Properties[$p.Name]) {
            $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
        }
    }
    $cfg
}

function Save-VTConfig {
    param([Parameter(Mandatory)] $Config)
    if (-not (Test-Path $script:VTConfigDir)) {
        New-Item -ItemType Directory -Path $script:VTConfigDir -Force | Out-Null
    }
    # Forzar que Extensions sea siempre array
    $Config.Extensions = @($Config.Extensions)
    $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $script:VTConfigPath -Encoding UTF8
}

# ---------------------------------------------------------------------
#  Consulta principal: hash local -> reporte en VirusTotal (sin subir)
# ---------------------------------------------------------------------
function Invoke-VTLookup {
    param([Parameter(Mandatory)][string]$FilePath)

    $cfg = Get-VTConfig
    $r = [ordered]@{
        FilePath = $FilePath
        FileName = (Split-Path $FilePath -Leaf)
        Status   = 'unknown'   # green / yellow / red / unknown / error / nokey
        Malicious = 0
        Suspicious = 0
        Total    = 0
        Message  = ''
        Permalink = ''
        Hash     = ''
    }

    if ([string]::IsNullOrWhiteSpace($cfg.ApiKey)) {
        $r.Status = 'nokey'
        $r.Message = 'No hay API Key. Abri el Centro de Mando y carga tu clave.'
        return [pscustomobject]$r
    }
    if (-not (Test-Path -LiteralPath $FilePath)) {
        $r.Status = 'error'; $r.Message = 'El archivo no existe.'
        return [pscustomobject]$r
    }

    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    try {
        $hash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLower()
    } catch {
        $r.Status = 'error'; $r.Message = "No se pudo leer el archivo: $($_.Exception.Message)"
        return [pscustomobject]$r
    }
    $r.Hash = $hash
    $r.Permalink = "https://www.virustotal.com/gui/file/$hash"
    $headers = @{ 'x-apikey' = $cfg.ApiKey }

    try {
        $resp = Invoke-RestMethod -Uri "https://www.virustotal.com/api/v3/files/$hash" `
                                  -Headers $headers -Method Get -ErrorAction Stop
        $stats = $resp.data.attributes.last_analysis_stats
        $mal = [int]$stats.malicious
        $sus = [int]$stats.suspicious
        $tot = [int]$stats.malicious + [int]$stats.suspicious + [int]$stats.undetected + `
               [int]$stats.harmless + [int]$stats.timeout
        $r.Malicious = $mal; $r.Suspicious = $sus; $r.Total = $tot
        $flag = $mal + $sus
        if     ($flag -ge $cfg.RedThreshold)    { $r.Status = 'red' }
        elseif ($flag -ge $cfg.YellowThreshold) { $r.Status = 'yellow' }
        else                                    { $r.Status = 'green' }
        $r.Message = "$mal/$tot motores detectan amenaza"
        if ($sus -gt 0) { $r.Message += "  ($sus sospechosos)" }
    }
    catch {
        $code = $null
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode.value__ }
        switch ($code) {
            404 {
                if ($cfg.AutoUploadUnknown -and ((Get-Item -LiteralPath $FilePath).Length -lt 32MB)) {
                    $up = Invoke-VTUpload -FilePath $FilePath -ApiKey $cfg.ApiKey
                    if ($up.Completed) {
                        $r.Malicious = $up.Malicious; $r.Suspicious = $up.Suspicious; $r.Total = $up.Total
                        $flag = $up.Malicious + $up.Suspicious
                        if     ($flag -ge $cfg.RedThreshold)    { $r.Status = 'red' }
                        elseif ($flag -ge $cfg.YellowThreshold) { $r.Status = 'yellow' }
                        else                                    { $r.Status = 'green' }
                        $r.Message = "(recien subido) $($up.Malicious)/$($up.Total) detectan amenaza"
                    } else {
                        $r.Status = 'unknown'
                        $r.Message = 'Subido a VT. El analisis sigue en curso, abri el link en un minuto.'
                    }
                } else {
                    $r.Status = 'unknown'
                    $r.Message = 'VirusTotal no conoce este archivo todavia.'
                }
            }
            401 { $r.Status = 'error'; $r.Message = 'API Key invalida (401). Revisala en el Centro de Mando.' }
            429 { $r.Status = 'error'; $r.Message = 'Limite de la API alcanzado (429). Espera ~1 minuto.' }
            default {
                $r.Status = 'error'
                $r.Message = "Error de red: $($_.Exception.Message)"
            }
        }
    }
    return [pscustomobject]$r
}

# ---------------------------------------------------------------------
#  Subida opcional de archivos que VT no conoce (<32 MB)
# ---------------------------------------------------------------------
function Invoke-VTUpload {
    param([Parameter(Mandatory)][string]$FilePath,
          [Parameter(Mandatory)][string]$ApiKey)

    $out = [pscustomobject]@{ Completed=$false; Malicious=0; Suspicious=0; Total=0 }
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        $client = [System.Net.Http.HttpClient]::new()
        $client.DefaultRequestHeaders.Add('x-apikey', $ApiKey)

        $bytes   = [System.IO.File]::ReadAllBytes($FilePath)
        $content = [System.Net.Http.MultipartFormDataContent]::new()
        $part    = [System.Net.Http.ByteArrayContent]::new($bytes)
        $content.Add($part, 'file', (Split-Path $FilePath -Leaf))

        $post = $client.PostAsync('https://www.virustotal.com/api/v3/files', $content).Result
        $json = ($post.Content.ReadAsStringAsync().Result | ConvertFrom-Json)
        $analysisId = $json.data.id
        if (-not $analysisId) { return $out }

        # Poll del analisis (hasta ~60s)
        for ($i=0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 3
            $a = Invoke-RestMethod -Uri "https://www.virustotal.com/api/v3/analyses/$analysisId" `
                                   -Headers @{ 'x-apikey'=$ApiKey } -Method Get -ErrorAction Stop
            if ($a.data.attributes.status -eq 'completed') {
                $s = $a.data.attributes.stats
                $out.Malicious  = [int]$s.malicious
                $out.Suspicious = [int]$s.suspicious
                $out.Total      = [int]$s.malicious + [int]$s.suspicious + [int]$s.undetected + `
                                  [int]$s.harmless + [int]$s.timeout
                $out.Completed  = $true
                break
            }
        }
    } catch { }
    return $out
}

# ---------------------------------------------------------------------
#  Popup tipo notificacion (abajo a la derecha), con semaforo de color
# ---------------------------------------------------------------------
function Show-VTResult {
    param([Parameter(Mandatory)]$Result, [int]$Seconds = 12)

    $accentMap = @{
        green   = [System.Drawing.Color]::FromArgb(46,160,67)
        yellow  = [System.Drawing.Color]::FromArgb(210,153,34)
        red     = [System.Drawing.Color]::FromArgb(218,54,51)
        unknown = [System.Drawing.Color]::FromArgb(110,118,129)
        error   = [System.Drawing.Color]::FromArgb(176,86,53)
        nokey   = [System.Drawing.Color]::FromArgb(67,109,177)
    }
    $titleMap = @{
        green='Limpio'; yellow='Precaucion'; red='PELIGRO'
        unknown='Desconocido'; error='Error'; nokey='Falta configurar'
    }
    $dotMap = @{ green='OK'; yellow='!'; red='X'; unknown='?'; error='!'; nokey='*' }

    $accent = $accentMap[$Result.Status]; if (-not $accent) { $accent = $accentMap['unknown'] }
    $title  = $titleMap[$Result.Status];  if (-not $title)  { $title  = 'VirusTotal' }

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.Size           = New-Object System.Drawing.Size(400, 168)
    $form.BackColor      = [System.Drawing.Color]::FromArgb(28,28,32)
    $form.TopMost        = $true
    $form.ShowInTaskbar  = $false
    $form.StartPosition  = 'Manual'
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Location = New-Object System.Drawing.Point(($wa.Right - $form.Width - 14), ($wa.Bottom - $form.Height - 14))

    # Franja de color a la izquierda
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Size = New-Object System.Drawing.Size(8, $form.Height)
    $bar.Location = New-Object System.Drawing.Point(0,0)
    $bar.BackColor = $accent
    $form.Controls.Add($bar)

    # Titulo
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = ("[{0}]  {1}" -f $dotMap[$Result.Status], $title)
    $lblTitle.ForeColor = $accent
    $lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $lblTitle.Location = New-Object System.Drawing.Point(22, 14)
    $lblTitle.AutoSize = $true
    $form.Controls.Add($lblTitle)

    # Nombre de archivo
    $lblFile = New-Object System.Windows.Forms.Label
    $lblFile.Text = $Result.FileName
    $lblFile.ForeColor = [System.Drawing.Color]::FromArgb(200,200,205)
    $lblFile.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $lblFile.Location = New-Object System.Drawing.Point(24, 50)
    $lblFile.Size = New-Object System.Drawing.Size(360, 18)
    $lblFile.AutoEllipsis = $true
    $form.Controls.Add($lblFile)

    # Mensaje
    $lblMsg = New-Object System.Windows.Forms.Label
    $lblMsg.Text = $Result.Message
    $lblMsg.ForeColor = [System.Drawing.Color]::FromArgb(160,160,168)
    $lblMsg.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $lblMsg.Location = New-Object System.Drawing.Point(24, 70)
    $lblMsg.Size = New-Object System.Drawing.Size(362, 40)
    $form.Controls.Add($lblMsg)

    # Boton: Ver en VirusTotal
    if ($Result.Permalink) {
        $btnVT = New-Object System.Windows.Forms.Button
        $btnVT.Text = 'Ver en VirusTotal'
        $btnVT.FlatStyle = 'Flat'
        $btnVT.ForeColor = [System.Drawing.Color]::White
        $btnVT.BackColor = $accent
        $btnVT.FlatAppearance.BorderSize = 0
        $btnVT.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $btnVT.Size = New-Object System.Drawing.Size(150, 30)
        $btnVT.Location = New-Object System.Drawing.Point(24, 120)
        $permalink = $Result.Permalink
        $btnVT.Add_Click({ Start-Process $permalink; $form.Close() }.GetNewClosure())
        $form.Controls.Add($btnVT)
    }

    # Boton: Cerrar
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Cerrar'
    $btnClose.FlatStyle = 'Flat'
    $btnClose.ForeColor = [System.Drawing.Color]::FromArgb(200,200,205)
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(48,48,54)
    $btnClose.FlatAppearance.BorderSize = 0
    $btnClose.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btnClose.Size = New-Object System.Drawing.Size(90, 30)
    $btnClose.Location = New-Object System.Drawing.Point(286, 120)
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    # Auto-cierre (no para rojo/peligro: ese queda hasta que lo cierres)
    if ($Result.Status -ne 'red' -and $Seconds -gt 0) {
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = $Seconds * 1000
        $timer.Add_Tick({ $timer.Stop(); $form.Close() })
        $timer.Start()
    }

    [void]$form.ShowDialog()
    $form.Dispose()
}

# ---------------------------------------------------------------------
#  Menu contextual (click derecho) - se instala en HKCU (sin admin)
# ---------------------------------------------------------------------
function Install-VTContextMenu {
    $cfg   = Get-VTConfig
    $entry = Join-Path $PSScriptRoot 'VTScan.ps1'
    $pwsh  = Join-Path $PSHOME 'powershell.exe'
    foreach ($ext in @($cfg.Extensions)) {
        $base = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\VTScan"
        New-Item -Path $base -Force | Out-Null
        Set-ItemProperty -Path $base -Name '(default)' -Value 'Analizar con VirusTotal'
        Set-ItemProperty -Path $base -Name 'Icon' -Value $pwsh
        $cmdKey = Join-Path $base 'command'
        New-Item -Path $cmdKey -Force | Out-Null
        $line = "`"$pwsh`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$entry`" `"%1`""
        Set-ItemProperty -Path $cmdKey -Name '(default)' -Value $line
    }
}

function Uninstall-VTContextMenu {
    # Limpia tanto las extensiones actuales como todas las conocidas
    $exts = @($script:VTKnownExtensions) + @((Get-VTConfig).Extensions) | Select-Object -Unique
    foreach ($ext in $exts) {
        $base = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\VTScan"
        Remove-Item -Path $base -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-VTContextMenuInstalled {
    $cfg = Get-VTConfig
    foreach ($ext in @($cfg.Extensions)) {
        if (Test-Path "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\VTScan") { return $true }
    }
    return $false
}

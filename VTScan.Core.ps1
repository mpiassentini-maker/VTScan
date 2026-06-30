# =====================================================================
#  VTScan.Core.ps1  -  Motor compartido (config, consulta VT, popup, menu)
#  Shared engine (config, VT lookup, popup, context menu)
#  No ejecutar directo / Don't run directly. Usado por VTScan.ps1 y el Centro de Mando.
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
        Language            = 'auto'  # 'auto' (idioma de Windows) | 'es' | 'en'
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
#  i18n - idioma + tabla de textos / language + strings table
# ---------------------------------------------------------------------
function Resolve-VTLang {
    param($Config)
    $lang = if ($Config) { [string]$Config.Language } else { 'auto' }
    if ([string]::IsNullOrWhiteSpace($lang) -or $lang -eq 'auto') {
        $ui = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        $lang = if ($ui -eq 'es') { 'es' } else { 'en' }
    }
    if ($lang -ne 'es' -and $lang -ne 'en') { $lang = 'en' }
    return $lang
}

function Get-VTStrings {
    param([string]$Lang = 'en')
    $es = @{
        menu_label        = 'Analizar con VirusTotal'
        # Popup
        t_clean='Limpio'; t_caution='Precaucion'; t_danger='PELIGRO'
        t_unknown='Desconocido'; t_error='Error'; t_setup='Falta configurar'
        btn_view='Ver en VirusTotal'; btn_close='Cerrar'
        msg_nokey='No hay API Key. Abri el Centro de Mando y carga tu clave.'
        msg_nofile='El archivo no existe.'
        msg_readfail='No se pudo leer el archivo: {0}'
        msg_detect='{0}/{1} motores detectan amenaza'
        msg_susp='  ({0} sospechosos)'
        msg_unknown='VirusTotal no conoce este archivo todavia.'
        msg_uploaded='(recien subido) {0}/{1} detectan amenaza'
        msg_uploading='Subido a VT. El analisis sigue en curso, abri el link en un minuto.'
        msg_401='API Key invalida (401). Revisala en el Centro de Mando.'
        msg_429='Limite de la API alcanzado (429). Espera ~1 minuto.'
        msg_neterr='Error de red: {0}'
        # Centro de Mando
        cc_title='VTScan - Centro de Mando'
        cc_subtitle='Chequeo rapido de archivos con VirusTotal'
        cc_apikey='API Key de VirusTotal'
        cc_apikey_hint='(virustotal.com -> tu perfil -> API Key. Gratis, sin tarjeta.)'
        cc_show='Ver'
        cc_language='Idioma / Language'
        cc_thresholds='Umbrales de detecciones'
        cc_yellow_from='Amarillo desde:'
        cc_red_from='Rojo desde:'
        cc_autoupload='Subir a VT los archivos que no conoce (<32MB, mas lento)'
        cc_extensions='Extensiones a vigilar (menu contextual)'
        cc_state_on='Menu contextual: INSTALADO'
        cc_state_off='Menu contextual: no instalado'
        cc_save='Guardar'; cc_install='Instalar menu'; cc_uninstall='Quitar menu'
        cc_test='Probar un archivo...'
        cc_saved='Configuracion guardada.'
        cc_needkey='Carga primero la API Key.'
        cc_installed='Listo. Boton derecho sobre un .exe/.msi/etc -> "Analizar con VirusTotal".'
        cc_uninstalled='Menu contextual quitado.'
        cc_pickfile='Elegi un archivo para analizar'
        cc_langchanged='Idioma guardado. Reabri el Centro de Mando para verlo aplicado. Si tenias el menu instalado, toca "Instalar menu" otra vez para actualizar el texto.'
    }
    $en = @{
        menu_label        = 'Scan with VirusTotal'
        # Popup
        t_clean='Clean'; t_caution='Caution'; t_danger='DANGER'
        t_unknown='Unknown'; t_error='Error'; t_setup='Setup needed'
        btn_view='View on VirusTotal'; btn_close='Close'
        msg_nokey='No API Key set. Open the Command Center and add your key.'
        msg_nofile='The file does not exist.'
        msg_readfail='Could not read the file: {0}'
        msg_detect='{0}/{1} engines flag this file'
        msg_susp='  ({0} suspicious)'
        msg_unknown='VirusTotal has not seen this file yet.'
        msg_uploaded='(just uploaded) {0}/{1} engines flag this file'
        msg_uploading='Uploaded to VT. Analysis still running, open the link in a minute.'
        msg_401='Invalid API Key (401). Check it in the Command Center.'
        msg_429='API rate limit reached (429). Wait ~1 minute.'
        msg_neterr='Network error: {0}'
        # Command Center
        cc_title='VTScan - Command Center'
        cc_subtitle='Quick file checks with VirusTotal'
        cc_apikey='VirusTotal API Key'
        cc_apikey_hint='(virustotal.com -> your profile -> API Key. Free, no card.)'
        cc_show='Show'
        cc_language='Language / Idioma'
        cc_thresholds='Detection thresholds'
        cc_yellow_from='Yellow from:'
        cc_red_from='Red from:'
        cc_autoupload='Upload unknown files to VT (<32MB, slower)'
        cc_extensions='Extensions to watch (context menu)'
        cc_state_on='Context menu: INSTALLED'
        cc_state_off='Context menu: not installed'
        cc_save='Save'; cc_install='Install menu'; cc_uninstall='Remove menu'
        cc_test='Test a file...'
        cc_saved='Settings saved.'
        cc_needkey='Enter the API Key first.'
        cc_installed='Done. Right-click an .exe/.msi/etc -> "Scan with VirusTotal".'
        cc_uninstalled='Context menu removed.'
        cc_pickfile='Pick a file to analyze'
        cc_langchanged='Language saved. Reopen the Command Center to see it applied. If the menu was installed, click "Install menu" again to update its label.'
    }
    if ($Lang -eq 'es') { return $es } else { return $en }
}

# ---------------------------------------------------------------------
#  Consulta principal: hash local -> reporte en VirusTotal (sin subir)
# ---------------------------------------------------------------------
function Invoke-VTLookup {
    param([Parameter(Mandatory)][string]$FilePath)

    $cfg = Get-VTConfig
    $s   = Get-VTStrings (Resolve-VTLang $cfg)
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
        $r.Message = $s.msg_nokey
        return [pscustomobject]$r
    }
    if (-not (Test-Path -LiteralPath $FilePath)) {
        $r.Status = 'error'; $r.Message = $s.msg_nofile
        return [pscustomobject]$r
    }

    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    try {
        $hash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLower()
    } catch {
        $r.Status = 'error'; $r.Message = ($s.msg_readfail -f $_.Exception.Message)
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
        $r.Message = ($s.msg_detect -f $mal, $tot)
        if ($sus -gt 0) { $r.Message += ($s.msg_susp -f $sus) }
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
                        $r.Message = ($s.msg_uploaded -f $up.Malicious, $up.Total)
                    } else {
                        $r.Status = 'unknown'
                        $r.Message = $s.msg_uploading
                    }
                } else {
                    $r.Status = 'unknown'
                    $r.Message = $s.msg_unknown
                }
            }
            401 { $r.Status = 'error'; $r.Message = $s.msg_401 }
            429 { $r.Status = 'error'; $r.Message = $s.msg_429 }
            default {
                $r.Status = 'error'
                $r.Message = ($s.msg_neterr -f $_.Exception.Message)
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
                $st = $a.data.attributes.stats
                $out.Malicious  = [int]$st.malicious
                $out.Suspicious = [int]$st.suspicious
                $out.Total      = [int]$st.malicious + [int]$st.suspicious + [int]$st.undetected + `
                                  [int]$st.harmless + [int]$st.timeout
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

    $s = Get-VTStrings (Resolve-VTLang (Get-VTConfig))

    $accentMap = @{
        green   = [System.Drawing.Color]::FromArgb(46,160,67)
        yellow  = [System.Drawing.Color]::FromArgb(210,153,34)
        red     = [System.Drawing.Color]::FromArgb(218,54,51)
        unknown = [System.Drawing.Color]::FromArgb(110,118,129)
        error   = [System.Drawing.Color]::FromArgb(176,86,53)
        nokey   = [System.Drawing.Color]::FromArgb(67,109,177)
    }
    $titleMap = @{
        green=$s.t_clean; yellow=$s.t_caution; red=$s.t_danger
        unknown=$s.t_unknown; error=$s.t_error; nokey=$s.t_setup
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

    # Boton: Ver en VirusTotal / View on VirusTotal
    if ($Result.Permalink) {
        $btnVT = New-Object System.Windows.Forms.Button
        $btnVT.Text = $s.btn_view
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

    # Boton: Cerrar / Close
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = $s.btn_close
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
    $s     = Get-VTStrings (Resolve-VTLang $cfg)
    $entry = Join-Path $PSScriptRoot 'VTScan.ps1'
    $pwsh  = Join-Path $PSHOME 'powershell.exe'
    foreach ($ext in @($cfg.Extensions)) {
        $base = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\VTScan"
        New-Item -Path $base -Force | Out-Null
        Set-ItemProperty -Path $base -Name '(default)' -Value $s.menu_label
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

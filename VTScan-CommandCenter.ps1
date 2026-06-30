# =====================================================================
#  VTScan-CommandCenter.ps1  -  Centro de Mando (GUI)
#  Carga tu API Key, instala/quita el menu contextual y ajusta opciones.
#  Hace doble click en este archivo (o boton derecho > Ejecutar con PowerShell).
# =====================================================================

. (Join-Path $PSScriptRoot 'VTScan.Core.ps1')

$cfg = Get-VTConfig

$form = New-Object System.Windows.Forms.Form
$form.Text = 'VTScan - Centro de Mando'
$form.Size = New-Object System.Drawing.Size(470, 540)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(32,32,38)
$form.ForeColor = [System.Drawing.Color]::White
$font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$form.Font = $font

function New-Label($text, $x, $y, $w=410, $bold=$false, $color=$null) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x,$y)
    $l.Size = New-Object System.Drawing.Size($w, 20); $l.AutoSize = $false
    if ($bold) { $l.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold) }
    if ($color) { $l.ForeColor = $color }
    $form.Controls.Add($l); return $l
}

# ---- Titulo
$lblHdr = New-Label '  VTScan' 12 12 420 $true
$lblHdr.Font = New-Object System.Drawing.Font('Segoe UI',14,[System.Drawing.FontStyle]::Bold)
$lblHdr.ForeColor = [System.Drawing.Color]::FromArgb(67,150,220)
New-Label 'Chequeo rapido de archivos con VirusTotal' 14 44 420 | Out-Null

# ---- API Key
New-Label 'API Key de VirusTotal' 14 80 420 $true | Out-Null
New-Label '(virustotal.com -> tu perfil -> API Key. Gratis, sin tarjeta.)' 14 100 440 $false ([System.Drawing.Color]::Gray) | Out-Null
$txtKey = New-Object System.Windows.Forms.TextBox
$txtKey.Location = New-Object System.Drawing.Point(14,124)
$txtKey.Size = New-Object System.Drawing.Size(330,24)
$txtKey.UseSystemPasswordChar = $true
$txtKey.Text = [string]$cfg.ApiKey
$txtKey.BackColor = [System.Drawing.Color]::FromArgb(48,48,56)
$txtKey.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($txtKey)

$chkShow = New-Object System.Windows.Forms.CheckBox
$chkShow.Text = 'Ver'; $chkShow.Location = New-Object System.Drawing.Point(352,124)
$chkShow.Size = New-Object System.Drawing.Size(90,24)
$chkShow.Add_CheckedChanged({ $txtKey.UseSystemPasswordChar = -not $chkShow.Checked })
$form.Controls.Add($chkShow)

# ---- Umbrales
New-Label 'Umbrales de detecciones' 14 164 420 $true | Out-Null
New-Label 'Amarillo desde:' 14 192 100 | Out-Null
$numY = New-Object System.Windows.Forms.NumericUpDown
$numY.Location = New-Object System.Drawing.Point(120,190); $numY.Size = New-Object System.Drawing.Size(55,24)
$numY.Minimum = 1; $numY.Maximum = 70; $numY.Value = [int]$cfg.YellowThreshold
$numY.BackColor = [System.Drawing.Color]::FromArgb(48,48,56); $numY.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($numY)

New-Label 'Rojo desde:' 200 192 80 | Out-Null
$numR = New-Object System.Windows.Forms.NumericUpDown
$numR.Location = New-Object System.Drawing.Point(290,190); $numR.Size = New-Object System.Drawing.Size(55,24)
$numR.Minimum = 1; $numR.Maximum = 70; $numR.Value = [int]$cfg.RedThreshold
$numR.BackColor = [System.Drawing.Color]::FromArgb(48,48,56); $numR.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($numR)

# ---- Auto subir desconocidos
$chkUpload = New-Object System.Windows.Forms.CheckBox
$chkUpload.Text = 'Subir a VT los archivos que no conoce (<32MB, mas lento)'
$chkUpload.Location = New-Object System.Drawing.Point(14,226)
$chkUpload.Size = New-Object System.Drawing.Size(440,24)
$chkUpload.Checked = [bool]$cfg.AutoUploadUnknown
$form.Controls.Add($chkUpload)

# ---- Extensiones
New-Label 'Extensiones a vigilar (menu contextual)' 14 262 420 $true | Out-Null
$clb = New-Object System.Windows.Forms.CheckedListBox
$clb.Location = New-Object System.Drawing.Point(14,286)
$clb.Size = New-Object System.Drawing.Size(430,90)
$clb.MultiColumn = $true; $clb.ColumnWidth = 100
$clb.CheckOnClick = $true
$clb.BackColor = [System.Drawing.Color]::FromArgb(48,48,56); $clb.ForeColor = [System.Drawing.Color]::White
foreach ($ext in $script:VTKnownExtensions) {
    $checked = @($cfg.Extensions) -contains $ext
    [void]$clb.Items.Add($ext, $checked)
}
$form.Controls.Add($clb)

# ---- Estado del menu
$lblState = New-Label '' 14 386 440 $false
function Update-State {
    if (Test-VTContextMenuInstalled) {
        $lblState.Text = 'Menu contextual: INSTALADO'
        $lblState.ForeColor = [System.Drawing.Color]::FromArgb(46,160,67)
    } else {
        $lblState.Text = 'Menu contextual: no instalado'
        $lblState.ForeColor = [System.Drawing.Color]::Gray
    }
}
Update-State

# ---- Helper: vuelca la GUI a la config y la guarda
function Sync-Config {
    $cfg.ApiKey = $txtKey.Text.Trim()
    $cfg.YellowThreshold = [int]$numY.Value
    $cfg.RedThreshold = [int]$numR.Value
    $cfg.AutoUploadUnknown = [bool]$chkUpload.Checked
    $exts = @()
    foreach ($i in $clb.CheckedItems) { $exts += [string]$i }
    if ($exts.Count -eq 0) { $exts = @('.exe') }
    $cfg.Extensions = $exts
    Save-VTConfig -Config $cfg
}

function New-Btn($text, $x, $y, $w, $bg) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x,$y)
    $b.Size = New-Object System.Drawing.Size($w,34); $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0; $b.ForeColor = [System.Drawing.Color]::White
    $b.BackColor = $bg; $form.Controls.Add($b); return $b
}

# ---- Botones
$btnSave = New-Btn 'Guardar' 14 420 130 ([System.Drawing.Color]::FromArgb(67,109,177))
$btnSave.Add_Click({
    Sync-Config
    [System.Windows.Forms.MessageBox]::Show('Configuracion guardada.','VTScan') | Out-Null
})

$btnInstall = New-Btn 'Instalar menu' 154 420 145 ([System.Drawing.Color]::FromArgb(46,140,67))
$btnInstall.Add_Click({
    Sync-Config
    if ([string]::IsNullOrWhiteSpace($cfg.ApiKey)) {
        [System.Windows.Forms.MessageBox]::Show('Carga primero la API Key.','VTScan') | Out-Null
        return
    }
    Install-VTContextMenu
    Update-State
    [System.Windows.Forms.MessageBox]::Show('Listo. Boton derecho sobre un .exe/.msi/etc -> "Analizar con VirusTotal".','VTScan') | Out-Null
})

$btnUninstall = New-Btn 'Quitar menu' 309 420 135 ([System.Drawing.Color]::FromArgb(120,60,60))
$btnUninstall.Add_Click({
    Uninstall-VTContextMenu; Update-State
    [System.Windows.Forms.MessageBox]::Show('Menu contextual quitado.','VTScan') | Out-Null
})

$btnTest = New-Btn 'Probar un archivo...' 14 462 430 ([System.Drawing.Color]::FromArgb(60,60,70))
$btnTest.Add_Click({
    Sync-Config
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Elegi un archivo para analizar'
    if ($dlg.ShowDialog() -eq 'OK') {
        $res = Invoke-VTLookup -FilePath $dlg.FileName
        Show-VTResult -Result $res -Seconds $cfg.NotificationSeconds
    }
})

[void]$form.ShowDialog()
$form.Dispose()

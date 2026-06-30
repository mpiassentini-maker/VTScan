# =====================================================================
#  VTScan.ps1  -  Punto de entrada del menu contextual
#  Uso:  powershell -File VTScan.ps1 "C:\ruta\al\archivo.exe"
# =====================================================================
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FilePath
)

. (Join-Path $PSScriptRoot 'VTScan.Core.ps1')

$cfg = Get-VTConfig
$result = Invoke-VTLookup -FilePath $FilePath
Show-VTResult -Result $result -Seconds $cfg.NotificationSeconds

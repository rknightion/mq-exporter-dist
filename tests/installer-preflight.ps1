#requires -Version 5.1
# Force rejection at OS preflight: no accounts, services or files can be changed.
$ErrorActionPreference = 'Stop'
function Get-CimInstance {
    param([string]$ClassName)
    if ($ClassName -ne 'Win32_OperatingSystem') { throw 'Unexpected CIM query' }
    [pscustomobject]@{BuildNumber='0';ProductType=3}
}
$installer = Join-Path $PSScriptRoot '../install/install.ps1'
$common = @{Version='v0.1.0-rc.9';Instance='qm1';QueueManager='QM1';ServiceAccount='mqmon';NoStart=$true}
foreach ($exporter in @('prometheus','otel')) {
    $options = @{Exporter=$exporter}
    if ($exporter -eq 'otel') { $options.OTLPEndpoint = 'https://otel.example.com:4318' }
    $message = ''
    try { & $installer @common @options } catch { $message = $_.Exception.Message }
    if ($message -notlike 'Initial Windows target is Windows Server 2019*') { throw ('Exporter preflight did not reach the safe OS guard: ' + $message) }
}
Write-Output 'Installer exporter selection reaches OS preflight; no installation changes attempted.'

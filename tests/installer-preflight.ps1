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

# S1 grammar: native revisioned/candidate forms reach the OS preflight guard;
# a custom-track version never gets that far, rejected at parameter binding.
foreach ($version in @('v6.0.0','v6.0.0-1','v6.0.0-1-rc.2','v6.0.0-rc.1')) {
    $message = ''
    try { & $installer -Version $version -Instance 'qm1' -QueueManager 'QM1' -ServiceAccount 'mqmon' -NoStart } catch { $message = $_.Exception.Message }
    if ($message -notlike 'Initial Windows target is Windows Server 2019*') { throw ('Native version ' + $version + ' did not reach the safe OS guard: ' + $message) }
}
foreach ($version in @('v6.0.0-custom-1','v6.0.0-custom-1-rc.1','V6.0.0',"v6.0.0-1`n")) {
    $message = ''
    try { & $installer -Version $version -Instance 'qm1' -QueueManager 'QM1' -ServiceAccount 'mqmon' -NoStart } catch { $message = $_.Exception.Message }
    if ($message -notlike '*does not match*' -and $message -notlike '*Cannot validate argument*') { throw ('Rejected version ' + $version + ' did not fail parameter validation: ' + $message) }
}
Write-Output 'Installer version grammar accepts native forms and rejects custom/invalid forms at parameter binding.'

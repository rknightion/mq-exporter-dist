#requires -Version 5.1
param([string]$MQPath = 'C:\Program Files\IBM\MQ')
$ErrorActionPreference = 'Stop'
try {
    $os = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{OS=$os.Caption;Build=$os.BuildNumber;Architecture=$os.OSArchitecture;PowerShell=$PSVersionTable.PSVersion.ToString()}
} catch { Write-Output 'OS details: UNAVAILABLE (CIM query failed)' }
$dll = Join-Path $MQPath 'bin64\mqm.dll'
if (Test-Path -LiteralPath $dll) {
    [pscustomobject]@{MQRuntimePresent=$true;MQFileVersion=(Get-Item -LiteralPath $dll).VersionInfo.FileVersion}
} else { Write-Output 'MQ 64-bit runtime: MISSING at supplied installation' }
Write-Output 'Native dependency loading, service lifecycle and live MQ: NOT TESTED'
Write-Output 'No machine name, account, queue manager name or configuration is collected.'

#requires -Version 5.1
# Disposable hosted-runner feasibility probe, not product acceptance.
$ErrorActionPreference = 'Stop'
$image = 'mcr.microsoft.com/windows/servercore@sha256:bea74690d808bba3e6b0d4ba4c599305aea1f66c875f133f1e75855841dcb1d5'
Write-Output ('Host build: ' + [Environment]::OSVersion.Version.ToString())
Get-WindowsFeature Hyper-V,Containers | Select-Object Name,InstallState | Format-Table
Get-CimInstance Win32_Processor | Select-Object VMMonitorModeExtensions,VirtualizationFirmwareEnabled,SecondLevelAddressTranslationExtensions | Format-Table
& docker version --format '{{.Server.Version}}'
if ($LASTEXITCODE -ne 0) { throw 'Docker engine unavailable; container test did not run' }
& docker info --format '{{.OSType}}'
if ($LASTEXITCODE -ne 0) { throw 'Docker engine information unavailable' }
& docker pull $image
if ($LASTEXITCODE -ne 0) { throw 'Image pull failed; container test did not run' }
$command = 'if ([Environment]::OSVersion.Version.Build -ne 17763) { exit 2 }; [Environment]::OSVersion.Version.ToString(); $PSVersionTable.PSVersion.ToString()'
& docker run --rm --network none --isolation=hyperv $image powershell.exe -NoLogo -NoProfile -NonInteractive -Command $command
if ($LASTEXITCODE -ne 0) { throw 'Server 2019 Hyper-V container could not complete the probe; no product tests ran' }
Write-Output 'PASS: Server 2019 kernel and PowerShell started under Hyper-V isolation. Product tests are a separate step.'

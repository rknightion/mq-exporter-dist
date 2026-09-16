#requires -Version 5.1
# Runs only inside the disposable test image. No MQ runtime is baked into it.
$ErrorActionPreference = 'Stop'
$installer = 'C:\prerequisites\vc_redist.x64.exe'
if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b') { throw 'VC runtime hash mismatch' }
$log = 'C:\prerequisites\vc-install.log'
Write-Output 'Starting verified VC runtime installer without ShellExecute'
$start = New-Object System.Diagnostics.ProcessStartInfo
$start.FileName = $installer
$start.Arguments = '/install /quiet /norestart /log ' + $log
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$process = [System.Diagnostics.Process]::Start($start)
Write-Output ('VC runtime process started: ' + $process.Id)
# Cache the process handle before waiting: Windows PowerShell otherwise can
# return a null ExitCode. Wait only for the bootstrapper, not long-lived MSI children.
$null = $process.Handle
try {
    if (-not $process.WaitForExit(300000)) {
        & taskkill.exe /PID $process.Id /T /F
        throw 'VC runtime installation exceeded five minutes'
    }
    if ($process.ExitCode -notin @(0,3010)) { throw ('VC runtime install exit: ' + $process.ExitCode) }
    foreach ($dll in @('vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll')) {
        $path = Join-Path $env:SystemRoot ('System32\' + $dll)
        if (-not (Test-Path -LiteralPath $path)) { throw ('Missing VC runtime: ' + $dll) }
        Write-Output ($dll + ' version: ' + (Get-Item -LiteralPath $path).VersionInfo.FileVersion)
    }
    Write-Output 'PASS: VC runtime installed in disposable Server 2019 image'
} catch {
    # These are synthetic build-environment installer logs, never server diagnostics.
    Get-ChildItem -LiteralPath C:\prerequisites -Filter '*.log' | ForEach-Object {
        Write-Output ('Installer log: ' + $_.Name)
        Get-Content -LiteralPath $_.FullName -Tail 60
    }
    throw
}

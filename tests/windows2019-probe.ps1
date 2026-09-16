#requires -Version 5.1
# Disposable hosted-runner feasibility probe, not product acceptance.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
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

# Download exact published bytes and separately licensed runtime only to the
# disposable runner. Never upload the SDK/runtime or raw configuration.
$work = Join-Path $env:RUNNER_TEMP ('mq-2019-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$release = Join-Path $work 'candidate.zip'
$sdk = Join-Path $work 'sdk.zip'
$pins = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../build/inputs.json') | ConvertFrom-Json
Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/rknightion/mq-exporter-dist/releases/download/v0.1.0-rc.1/mq-exporter-dist-v0.1.0-rc.1-windows-amd64.zip' -OutFile $release
if ((Get-FileHash -LiteralPath $release -Algorithm SHA256).Hash -ne '806c56e27f8b95914fab19006c53329f56801b2abc31df1dcba6dd845ec974b3') { throw 'Published candidate hash mismatch' }
Invoke-WebRequest -UseBasicParsing -Uri ('https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqdev/redist/' + $pins.mq_sdk_version + '-IBM-MQC-Redist-Win64.zip') -OutFile $sdk
if ((Get-FileHash -LiteralPath $sdk -Algorithm SHA256).Hash -ne $pins.mq_windows_sha256) { throw 'SDK hash mismatch' }
$vcRedist = Join-Path $work 'vc_redist.x64.exe'
# Version 14.44.35211.0, resolved from Microsoft's VS 2022 download route.
# A test prerequisite only: never included in public exporter payloads.
Invoke-WebRequest -UseBasicParsing -Uri 'https://download.visualstudio.microsoft.com/download/pr/bd1c8d9d-ba95-4eee-bc6e-df1fcc876373/CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B/VC_redist.x64.exe' -OutFile $vcRedist
if ((Get-FileHash -LiteralPath $vcRedist -Algorithm SHA256).Hash -ne 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b') { throw 'VC runtime hash mismatch' }
$signature = Get-AuthenticodeSignature -LiteralPath $vcRedist
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { throw 'VC runtime publisher verification failed' }
Write-Output ('Verified Microsoft VC runtime ' + (Get-Item -LiteralPath $vcRedist).VersionInfo.FileVersion)
Expand-Archive -LiteralPath $release -DestinationPath (Join-Path $work 'payload')
Expand-Archive -LiteralPath $sdk -DestinationPath (Join-Path $work 'mq')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows2019-smoke.ps1') -Destination $work
# Keep this context separate: SDK and exporter must never enter image layers.
$context = Join-Path $work 'image'
$null = New-Item -ItemType Directory -Path $context
Copy-Item -LiteralPath $vcRedist -Destination $context
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows2019/Dockerfile') -Destination $context
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows2019/install-runtime.ps1') -Destination $context
$testImage = 'mq-server2019-test:' + [Guid]::NewGuid().ToString('N')
# Build networking permits Windows prerequisite setup; the smoke test stays offline.
& docker build --isolation=hyperv --tag $testImage $context
if ($LASTEXITCODE -ne 0) { throw 'Server 2019 prerequisite image build failed' }
& docker image inspect $testImage --format '{{.Id}}'
& docker run --rm --network none --isolation=hyperv --mount ('type=bind,source=' + $work + ',target=C:\input,readonly') $testImage powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\input\windows2019-smoke.ps1
if ($LASTEXITCODE -ne 0) { throw 'Server 2019 exporter smoke tests failed' }

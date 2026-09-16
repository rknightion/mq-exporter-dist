#requires -Version 5.1
# Read-only mounted binaries, disposable local config, no network and no live MQ.
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Version.Build -ne 17763) { throw 'Wrong guest build' }
$env:PATH = 'C:\input\mq\bin64;' + (Join-Path $env:SystemRoot 'System32')
$helper = 'C:\input\payload\mq-dist.exe'
& $helper inspect --platform windows C:\input\payload\mq_prometheus.exe
if ($LASTEXITCODE -ne 0) { throw 'PE inspection failed' }
& $helper smoke --binary C:\input\payload\mq_prometheus.exe
if ($LASTEXITCODE -ne 0) { throw 'Native loading failed' }
$config = Join-Path $env:TEMP ('mq-' + [Guid]::NewGuid().ToString('N') + '.json')
$utf8 = New-Object Text.UTF8Encoding($false)
$text = & $helper config --qmgr QM1 --queues 'APP.*,!SYSTEM.*' --mode client --channel APP.SVRCONN --conn-name 'mq.example.com(1414)'
if ($LASTEXITCODE -ne 0) { throw 'Config generation failed' }
[IO.File]::WriteAllText($config, ($text -join "`n"), $utf8)
& $helper smoke --binary C:\input\payload\mq-config-check.exe --config $config
if ($LASTEXITCODE -ne 0) { throw 'Actual upstream config reader failed' }
# Bindings cannot succeed in this client-only container. Bound the subprocess.
$text = & $helper config --qmgr QM1
if ($LASTEXITCODE -ne 0) { throw 'Bindings config generation failed' }
[IO.File]::WriteAllText($config, ($text -join "`n"), $utf8)
$stdout = $config + '.stdout'
$stderr = $config + '.stderr'
$process = Start-Process -FilePath C:\input\payload\mq_prometheus.exe -ArgumentList @('-f', $config) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
if (-not $process.WaitForExit(20000)) { $process.Kill(); throw 'Initial unavailable MQ check timed out' }
$process.Refresh()
if ($process.ExitCode -ne 10) { throw ('Unexpected first connection exit: ' + $process.ExitCode) }
Write-Output 'PASS: published rc.1 PE inspection, native loading, actual config reader, first unavailable MQ exit 10 in Server Core 2019 Hyper-V container. Full installer, service identity and live MQ remain untested.'

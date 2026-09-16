#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Output, [Parameter(Mandatory=$true)][string]$MQPath)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)
$oldPath = $env:PATH
$env:PATH = (Join-Path $MQPath 'bin64') + ';' + (Join-Path $env:SystemRoot 'System32')
$helper = Join-Path $Output 'mq-dist.exe'
$config = Join-Path $Output 'unicode-config.json'
try {
    $passwordPath = Join-Path $Output ('credential-' + [char]0x03B1 + '.txt')
    [IO.File]::WriteAllText($passwordPath, 'synthetic-test-value', $utf8)
    $json = & $helper config --qmgr QM1 --queues 'APP.*,!SYSTEM.*' --mode client --channel APP.SVRCONN --conn-name 'mq.example.com(1414)' --user monitor --password-file $passwordPath
    if ($LASTEXITCODE -ne 0) { throw 'generator failed' }
    [IO.File]::WriteAllText($config, ($json -join "`n"), $utf8)
    $parsed = Get-Content -Raw -Encoding UTF8 -LiteralPath $config | ConvertFrom-Json
    if ($parsed.connection.connName -ne 'mq.example.com(1414)' -or $parsed.objects.queues[1] -ne '!SYSTEM.*') { throw 'serialization mismatch' }
    if ($parsed.connection.passwordFile -ne $passwordPath) { throw 'Unicode path mismatch' }
    & (Join-Path $Output 'mq-config-check.exe') -f $config
    if ($LASTEXITCODE -ne 0) { throw 'upstream reader failed' }
    $name = 'mq-dist-test-' + [Guid]::NewGuid().ToString('N')
    $child = Join-Path $Output 'service-child.exe'
    $wrapper = Join-Path $Output 'mq-service.exe'
    $command = '"' + $wrapper + '" -name "' + $name + '" -binary "' + $child + '" -config "' + $config + '" -mq "' + $MQPath + '" -logs "' + $Output + '"'
    $created = $false
    try {
        $null = New-Service -Name $name -BinaryPathName $command
        $created = $true
        $baseline = @(Select-String -LiteralPath (Join-Path $Output 'exporter.log') -Pattern '^synthetic child started$' -ErrorAction SilentlyContinue).Count
        Start-Service $name
        $deadline = (Get-Date).AddSeconds(30)
        do {
            Start-Sleep -Seconds 1
            $starts = @(Select-String -LiteralPath (Join-Path $Output 'exporter.log') -Pattern '^synthetic child started$' -ErrorAction SilentlyContinue)
        } while ($starts.Count -lt ($baseline + 2) -and (Get-Date) -lt $deadline)
        if ((Get-Service $name).Status -ne 'Running') { throw 'SCM adapter stopped unexpectedly' }
        $starts = @(Select-String -LiteralPath (Join-Path $Output 'exporter.log') -Pattern '^synthetic child started$')
        if ($starts.Count -lt ($baseline + 2)) { throw 'child restart was not observed' }
        Stop-Service $name
        (Get-Service $name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
        if (Get-Process -Name service-child -ErrorAction SilentlyContinue) { throw 'child survived service stop' }
        Write-Output 'SCM start, synthetic child restart and stop: PASS on this build host only'
    } finally {
        if ($created) { Stop-Service $name -ErrorAction SilentlyContinue; & (Join-Path $env:SystemRoot 'System32\sc.exe') delete $name | Out-Null }
    }
} finally { $env:PATH = $oldPath }

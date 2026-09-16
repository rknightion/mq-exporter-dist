#requires -Version 5.1
# Destructive fixtures only inside a fresh disposable, network-isolated guest.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:MQ_DIST_DISPOSABLE_TEST -ne '1' -or [Environment]::OSVersion.Version.Build -ne 17763 -or -not (Test-Path C:\input\candidate.zip)) { throw 'Disposable Server 2019 fixture required' }
$utf8 = New-Object Text.UTF8Encoding($false)
$root = 'C:\Program Files\MQ Test ' + [char]0x03B1
$null = New-Item -ItemType Directory -Path $root
$account = $env:COMPUTERNAME + '\mqtest'
$secret = ConvertTo-SecureString ([Guid]::NewGuid().ToString('N') + '!aA7') -AsPlainText -Force
$user = New-LocalUser -Name mqtest -Password $secret -AccountNeverExpires
$credential = New-Object Management.Automation.PSCredential($account,$secret)
# Preserve all current assignments; add only this fixture's service logon right.
$policy = Join-Path $root 'rights.inf'
& secedit.exe /export /cfg $policy /areas USER_RIGHTS /quiet
if ($LASTEXITCODE -ne 0) { throw 'Service rights export failed' }
$text = [IO.File]::ReadAllText($policy)
if (-not $text.Contains('[Privilege Rights]')) { throw 'Exported policy has no privilege section' }
$right = 'SeServiceLogonRight'
$match = [regex]::Match($text, '(?m)^SeServiceLogonRight\s*=([^\r\n]*)')
if ($match.Success) { $text = $text.Replace($match.Value, ($right + ' = ' + $match.Groups[1].Value.Trim() + ',*' + $user.SID.Value)) }
else { $text = $text.Replace('[Privilege Rights]', ('[Privilege Rights]' + "`r`n" + $right + ' = *' + $user.SID.Value)) }
[IO.File]::WriteAllText($policy,$text,[Text.Encoding]::Unicode)
& secedit.exe /configure /db (Join-Path $root 'rights.sdb') /cfg $policy /areas USER_RIGHTS /quiet
if ($LASTEXITCODE -ne 0) { throw 'Service rights assignment failed' }
function Assert-True($Value,[string]$Message) { if (-not $Value) { throw $Message } }
function Assert-Rejected([scriptblock]$Action,[string]$Pattern) {
    $message = ''
    try { & $Action } catch { $message = $_.Exception.Message }
    Assert-True ($message -like $Pattern) ('Expected rejection: ' + $Pattern + '; got: ' + $message)
}
function Assert-Private([string]$Path) {
    $acl = Get-Acl -LiteralPath $Path
    foreach ($ace in $acl.Access) {
        $sid = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        Assert-True ($ace.AccessControlType -ne 'Allow' -or $sid -in @($user.SID.Value,'S-1-5-18','S-1-5-32-544')) 'Unexpected configuration ACL identity'
        if ($sid -eq $user.SID.Value) {
            $writes = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions
            Assert-True (-not ($ace.FileSystemRights -band $writes)) 'Service account can modify configuration'
        }
    }
}
function Assert-Retry([string]$Instance) {
    $name = 'mq-exporter-' + $Instance
    $log = Join-Path $root ($Instance + '\logs\exporter.log')
    $deadline = (Get-Date).AddSeconds(50)
    # Allow the first child's output to settle, then require new MQ errors from
    # a subsequent launch, not two lines emitted by one failed connection.
    Start-Sleep -Seconds 3
    $baseline = @(Select-String -LiteralPath $log -Pattern 'MQRC' -ErrorAction SilentlyContinue).Count
    do {
        Start-Sleep -Seconds 1
        $errors = @(Select-String -LiteralPath $log -Pattern 'MQRC' -ErrorAction SilentlyContinue).Count
    } while ($errors -le $baseline -and (Get-Date) -lt $deadline)
    Assert-True ($baseline -gt 0 -and $errors -gt $baseline) ('No repeated actual MQ failure observed: ' + $Instance)
    Assert-True ((Get-Service $name).Status -eq 'Running') 'SCM service not running during retries'
    Write-Output ('PASS: dedicated-account SCM service and unavailable-MQ retries: ' + $Instance)
}
function Stop-Instance([string]$Instance) {
    $name = 'mq-exporter-' + $Instance
    Stop-Service $name
    (Get-Service $name).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
    $dir = Join-Path $root $Instance
    $children = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($dir + '\',[StringComparison]::OrdinalIgnoreCase) })
    Assert-True ($children.Count -eq 0) 'Service child survived stop'
}
$sum = Join-Path $root 'SHA256SUMS'
[IO.File]::WriteAllText($sum, "806c56e27f8b95914fab19006c53329f56801b2abc31df1dcba6dd845ec974b3  mq-exporter-dist-v0.1.0-rc.1-windows-amd64.zip`n",$utf8)
$common = @{Instance='qm1';QueueManager='QM1';ServiceAccount=$account;ServiceCredential=$credential;MQPath='C:\input\mq';InstallRoot=$root;NoStart=$true}
& C:\input\payload\install.ps1 @common -Version v0.1.0-rc.1 -Archive C:\input\candidate.zip -Checksums $sum
$dest = Join-Path $root 'qm1'
$config = Join-Path $dest 'config.json'
Assert-Private $config
$service = Get-CimInstance Win32_Service -Filter "Name='mq-exporter-qm1'"
Assert-True ($service.StartName -eq $account -and $service.StartMode -eq 'Auto' -and $service.State -eq 'Stopped') 'Service identity/startup mismatch'
Start-Service mq-exporter-qm1
Assert-Retry qm1
Stop-Instance qm1
Start-Service mq-exporter-qm1
Write-Output 'PASS: published rc.1 fresh offline install, private ACLs, stop and restart'
# Upgrade the running service to exact rc.3 bytes, preserving a user-edited config.
$json = Get-Content -LiteralPath $config -Raw -Encoding UTF8 | ConvertFrom-Json
$json.global.pollInterval = '20s'
[IO.File]::WriteAllText($config,($json | ConvertTo-Json -Depth 20),$utf8)
$configHash = (Get-FileHash $config).Hash
$oldBinaryHash = (Get-FileHash (Join-Path $dest 'mq_prometheus.exe')).Hash
$rc3 = 'C:\input\prometheus\mq-exporter-dist-v0.1.0-rc.3-windows-amd64.zip'
[IO.File]::WriteAllText($sum, "d83fc837dc971a1e16f72b8c63bb5482714633f83983026fd3ef4bbc04a0d897  mq-exporter-dist-v0.1.0-rc.3-windows-amd64.zip`n",$utf8)
$common.NoStart = $false
$upgrade = @{Version='v0.1.0-rc.3';Archive=$rc3;Checksums=$sum}
$installer = 'C:\input\prometheus\payload\install.ps1'
& $installer @common @upgrade
Assert-True ((Get-FileHash $config).Hash -eq $configHash) 'Upgrade overwrote user configuration'
Assert-True ((Get-FileHash (Join-Path $dest 'mq_prometheus.exe')).Hash -eq (Get-FileHash C:\input\prometheus\payload\mq_prometheus.exe).Hash) 'Installed binary differs from candidate'
$backups = @(Get-ChildItem -LiteralPath $dest -Filter 'mq_prometheus.exe.bak-*' | Where-Object { (Get-FileHash $_.FullName).Hash -eq $oldBinaryHash })
Assert-True ($backups.Count -eq 1) 'Upgrade did not preserve previous executable'
Assert-Private $config
Assert-Retry qm1
Write-Output 'PASS: running-service rc.1 to rc.3 upgrade, exact binary, backup and configuration preservation'
$other = $common.Clone(); $other.QueueManager = 'QM2'
Assert-Rejected { & $installer @other @upgrade } 'Instance identity differs*'
$badSum = Join-Path $root 'bad-sums'
[IO.File]::WriteAllText($badSum,(('0' * 64) + "  mq-exporter-dist-v0.1.0-rc.3-windows-amd64.zip`n"),$utf8)
Assert-Rejected { & $installer @common -Version v0.1.0-rc.3 -Archive $rc3 -Checksums $badSum } 'Archive checksum mismatch'
Assert-True ((Get-FileHash $config).Hash -eq $configHash -and (Get-Service mq-exporter-qm1).Status -eq 'Running') 'Rejected install changed existing instance'
$other.Instance = 'qm2'; $other.Port = 9158; $other.Mode = 'client'; $other.Channel = 'APP.SVRCONN'; $other.ConnectionName = '127.0.0.1(1)'
& $installer @other @upgrade
Assert-True ((Get-FileHash $config).Hash -eq $configHash) 'Second instance changed first configuration'
Assert-Retry qm2
Write-Output 'PASS: rejection preserves running instance; independent client instance and port'
$otel = $common.Clone(); $otel.Instance='otel'; $otel.Exporter='otel'; $otel.OTLPEndpoint='http://127.0.0.1:4318'; $otel.OTLPInsecure=$true
$otelArchive = 'C:\input\otel\mq-otel-dist-v0.1.0-rc.3-windows-amd64.zip'
[IO.File]::WriteAllText($sum,"30d6c55f8d2e6b6510c0fd1774caf19c046a16306a031306f79a3a9b752449da  mq-otel-dist-v0.1.0-rc.3-windows-amd64.zip`n",$utf8)
& C:\input\otel\payload\install.ps1 @otel -Version v0.1.0-rc.3 -Archive $otelArchive -Checksums $sum
Assert-Private (Join-Path $root 'otel\config.json')
Assert-Retry otel
Write-Output 'PASS: separate OTel offline installation and actual upstream reader'
# Removal deliberately keeps binaries, logs and configuration for recovery.
foreach ($instance in @('qm1','qm2','otel')) {
    Stop-Instance $instance
    & sc.exe delete ('mq-exporter-' + $instance)
    if ($LASTEXITCODE -ne 0) { throw 'Service removal failed' }
    Assert-True (-not (Get-Service ('mq-exporter-' + $instance) -ErrorAction SilentlyContinue)) 'Service still registered'
    Assert-True (Test-Path (Join-Path $root ($instance + '\config.json'))) 'Removal lost configuration'
}
Write-Output 'PASS: Server Core 2019 offline install/upgrade/start/retry/stop/service removal cycle. No live MQ, reboot or full-server acceptance claimed.'

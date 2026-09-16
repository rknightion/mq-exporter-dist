#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$')][string]$Version,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9-]{0,39}$')][string]$Instance,
    [Parameter(Mandatory=$true)][string]$QueueManager,
    [Parameter(Mandatory=$true)][string]$ServiceAccount,
    [string]$Archive, [string]$Checksums,
    [string]$MQPath = 'C:\Program Files\IBM\MQ',
    [string]$InstallRoot = 'C:\Program Files\mq-exporter',
    [ValidateRange(1,65535)][int]$Port = 9157,
    [ValidateSet('prometheus','otel')][string]$Exporter = 'prometheus',
    [string]$OTLPEndpoint = '', [switch]$OTLPInsecure,
    [string]$Queues = 'APP.*,!SYSTEM.*,!AMQ.*', [string]$Channels = '*',
    [ValidateSet('bindings','client')][string]$Mode = 'bindings',
    [string]$Channel = '', [string]$ConnectionName = '', [string]$CCDT = '',
    [string]$MQUser = '', [string]$PasswordFile = '',
    [switch]$ReplaceConfig, [switch]$Repoint, [switch]$NoStart,
    [System.Management.Automation.PSCredential]$ServiceCredential
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$exporterBinary = 'mq_' + $Exporter + '.exe'
$prefix = 'mq-exporter-dist'
$identityPort = $Port
if ($Exporter -eq 'otel') {
    if (-not $OTLPEndpoint) { throw 'OTLP endpoint required' }
    $prefix = 'mq-otel-dist'
    $identityPort = 0
} elseif ($OTLPEndpoint -or $OTLPInsecure) { throw 'OTLP settings require otel exporter' }
function Invoke-Native([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('Native command failed, exit ' + $LASTEXITCODE) }
}
function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $utf8) }
function Protect-Directory([string]$Path, [string]$Sid) {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($entry in @(@('S-1-5-18','FullControl'), @('S-1-5-32-544','FullControl'), @($Sid,'ReadAndExecute'))) {
        $id = New-Object Security.Principal.SecurityIdentifier($entry[0])
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($id, $entry[1], 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function Assert-SafePath([string]$Path) {
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '["\r\n%]' -or $Path.Contains('..')) { throw 'Absolute local paths without quotes, percent signs or traversal required' }
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not allowed in install paths' }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}
function Assert-TrustedParent([string]$Path) {
    $parent = $Path
    while (-not (Test-Path -LiteralPath $parent)) { $parent = [IO.Path]::GetDirectoryName($parent) }
    $acl = Get-Acl -LiteralPath $parent
    $admin = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($ace in $acl.Access) {
        $identity = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
        if ($ace.AccessControlType -eq 'Allow' -and ($ace.FileSystemRights -band $writeMask) -and $identity -notin @($admin,'S-1-5-18','S-1-5-32-544','S-1-3-0','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { throw 'Installation parent is writable by an untrusted identity' }
    }
}
function Assert-PrivateFile([string]$Path, [string]$Sid) {
    Assert-SafePath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Password file missing' }
    $acl = Get-Acl -LiteralPath $Path
    foreach ($ace in $acl.Access) {
        $identity = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($ace.AccessControlType -eq 'Allow' -and $identity -notin @($Sid,'S-1-5-18','S-1-5-32-544')) { throw 'Password file must be restricted to the service account, SYSTEM and Administrators' }
    }
}
if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) { throw '64-bit Windows and PowerShell required' }
$os = Get-CimInstance Win32_OperatingSystem
if ($os.BuildNumber -ne '17763' -or $os.ProductType -eq 1) { throw 'Initial Windows target is Windows Server 2019 (build 17763)' }
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run elevated' }
Assert-SafePath $InstallRoot
Assert-TrustedParent $InstallRoot
Assert-SafePath $MQPath
$sid = (New-Object Security.Principal.NTAccount($ServiceAccount)).Translate([Security.Principal.SecurityIdentifier]).Value
if ($sid -in @('S-1-5-18','S-1-5-19','S-1-5-20')) { throw 'Use a dedicated service account with MQ permissions' }
if ($PasswordFile) { Assert-PrivateFile $PasswordFile $sid }
if (-not (Test-Path -LiteralPath (Join-Path $MQPath 'bin64\mqm.dll'))) { throw 'Existing MQ 64-bit runtime missing' }
$dest = Join-Path $InstallRoot $Instance
Assert-SafePath $dest
Assert-TrustedParent $dest
$name = 'mq-exporter-' + $Instance
$existing = Get-Service -Name $name -ErrorAction SilentlyContinue
if ($existing -and -not (Test-Path -LiteralPath (Join-Path $dest 'identity.json'))) { throw 'Existing service is not managed by this installer' }
if (-not $existing) {
    if (-not $ServiceCredential -or $ServiceCredential.UserName -ne $ServiceAccount) { throw 'Supply ServiceCredential for the specified dedicated account; grant Log on as a service beforehand' }
}
$identity = [ordered]@{qmgr=$QueueManager;port=$identityPort;account=$ServiceAccount;mq=$MQPath;mode=$Mode;channel=$Channel;connName=$ConnectionName;ccdt=$CCDT}
if ($Exporter -eq 'otel') { $identity.exporter = 'otel'; $identity.endpoint = $OTLPEndpoint; $identity.insecure = [bool]$OTLPInsecure }
$identityText = $identity | ConvertTo-Json -Compress
if (Test-Path -LiteralPath (Join-Path $dest 'identity.json')) {
    if ([IO.File]::ReadAllText((Join-Path $dest 'identity.json')) -ne $identityText -and -not ($Repoint -and $ReplaceConfig)) { throw 'Instance identity differs; use explicit Repoint and ReplaceConfig' }
    $previous = Get-Content -Raw -LiteralPath (Join-Path $dest 'identity.json') | ConvertFrom-Json
    if ($previous.account -ne $ServiceAccount) { throw 'Changing an existing SCM service account requires a separate administrator action' }
}
foreach ($file in @(Get-ChildItem -LiteralPath $InstallRoot -Filter identity.json -Recurse -ErrorAction SilentlyContinue)) {
    if ($Exporter -eq 'prometheus' -and $file.DirectoryName -ne $dest -and (Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json).port -eq $Port) { throw 'Port reserved by another instance' }
}
$mutex = New-Object Threading.Mutex($false, 'Global\mq-exporter-dist-install')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); throw 'Another installer is active' }
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('mq-exporter-' + [Guid]::NewGuid().ToString('N'))
$scratchCreated = $false
$oldPath = $env:PATH
$oldTLS = [Net.ServicePointManager]::SecurityProtocol
$stopped = $false
try {
    # Recheck shared reservations while all installer writes are serialized.
    if (Test-Path -LiteralPath (Join-Path $dest 'identity.json')) {
        if ([IO.File]::ReadAllText((Join-Path $dest 'identity.json')) -ne $identityText -and -not ($Repoint -and $ReplaceConfig)) { throw 'Instance changed during preflight' }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $InstallRoot -Filter identity.json -Recurse -ErrorAction SilentlyContinue)) {
        if ($Exporter -eq 'prometheus' -and $file.DirectoryName -ne $dest -and (Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json).port -eq $Port) { throw 'Port reserved during preflight' }
    }
    if ($Archive -and -not $Checksums) { throw 'Archive requires Checksums' }
    # New-Item without Force refuses an existing path; cleanup needs ownership.
    $null = New-Item -ItemType Directory -Path $scratch
    $scratchCreated = $true
    Protect-Directory $scratch $sid
    $asset = $prefix + '-' + $Version + '-windows-amd64.zip'
    if (-not $Archive) {
        if ($Checksums) { throw 'Checksums requires Archive' }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $base = 'https://github.com/rknightion/mq-exporter-dist/releases/download/' + $Version
        $Archive = Join-Path $scratch $asset
        $Checksums = Join-Path $scratch 'SHA256SUMS'
        Invoke-WebRequest -UseBasicParsing -Uri ($base + '/' + $asset) -OutFile $Archive
        Invoke-WebRequest -UseBasicParsing -Uri ($base + '/SHA256SUMS') -OutFile $Checksums
    }
    $lines = @(Get-Content -LiteralPath $Checksums | Where-Object { $_ -match ('^[a-fA-F0-9]{64}  ' + [regex]::Escape($asset) + '$') })
    if ($lines.Count -ne 1) { throw 'Missing or duplicate archive checksum' }
    if ($Archive -ne (Join-Path $scratch $asset)) {
        Copy-Item -LiteralPath $Archive -Destination (Join-Path $scratch $asset)
        $Archive = Join-Path $scratch $asset
    }
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $lines[0].Substring(0,64)) { throw 'Archive checksum mismatch' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $allowed = @($exporterBinary,'mq-config-check.exe','mq-dist.exe','mq-service.exe','install.ps1','diagnose.ps1','LICENSE','THIRD-PARTY-NOTICES.txt','build-metadata.json','sbom.cdx.json')
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    $payload = Join-Path $scratch 'payload'
    $null = New-Item -ItemType Directory -Path $payload
    try {
        if ($zip.Entries.Count -ne $allowed.Count) { throw 'Unexpected archive entry count' }
        $seen = @{}
        foreach ($entry in $zip.Entries) {
            $unixType = ($entry.ExternalAttributes -shr 16) -band 61440
            if ($entry.FullName -cnotin $allowed -or $seen.ContainsKey($entry.FullName) -or $unixType -notin @(0,32768) -or $entry.Length -gt 268435456) { throw 'Unsafe archive member' }
            $seen[$entry.FullName] = $true
        }
        foreach ($entry in $zip.Entries) { [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $payload $entry.FullName), $false) }
    } finally { $zip.Dispose() }
    $metadata = Get-Content -LiteralPath (Join-Path $payload 'build-metadata.json') -Raw | ConvertFrom-Json
    if ($metadata.distribution_version -ne $Version -or $metadata.platform -ne 'windows-amd64') { throw 'Release metadata mismatch' }
    $helper = Join-Path $payload 'mq-dist.exe'
    Invoke-Native $helper @('inspect','--platform','windows',(Join-Path $payload $exporterBinary))
    $argsConfig = @('config','--qmgr',$QueueManager,'--port',"$Port",'--queues',$Queues,'--channels',$Channels,'--mode',$Mode)
    if ($Exporter -eq 'otel') { $argsConfig += @('--exporter','otel','--otlp-endpoint',$OTLPEndpoint,('--otlp-insecure=' + ([bool]$OTLPInsecure).ToString().ToLowerInvariant())) }
    foreach ($pair in @(@('--channel',$Channel),@('--conn-name',$ConnectionName),@('--ccdt',$CCDT),@('--user',$MQUser),@('--password-file',$PasswordFile))) {
        if ($pair[1]) { $argsConfig += $pair }
    }
    $text = & $helper @argsConfig
    if ($LASTEXITCODE -ne 0) { throw 'Configuration generation failed' }
    $candidateConfig = Join-Path $scratch 'config.json'
    Write-Utf8 $candidateConfig ($text -join "`n")
    $config = Join-Path $dest 'config.json'
    $checkConfig = $candidateConfig
    if ((Test-Path -LiteralPath $config) -and -not $ReplaceConfig) { $checkConfig = $config }
    Invoke-Native $helper @('same-identity',$candidateConfig,$checkConfig)
    $env:PATH = (Join-Path $MQPath 'bin64') + ';' + (Join-Path $env:SystemRoot 'System32')
    Invoke-Native $helper @('smoke','--binary',(Join-Path $payload $exporterBinary))
    Invoke-Native $helper @('smoke','--binary',(Join-Path $payload 'mq-config-check.exe'),'--config',$checkConfig)
    $null = New-Item -ItemType Directory -Path $dest -Force
    Protect-Directory $dest $sid
    $logs = Join-Path $dest 'logs'
    $null = New-Item -ItemType Directory -Path $logs -Force
    $acl = Get-Acl -LiteralPath $logs
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($ServiceAccount,'Modify','ContainerInherit,ObjectInherit','None','Allow')))
    Set-Acl -LiteralPath $logs -AclObject $acl
    if ($existing -and $existing.Status -ne 'Stopped') { Stop-Service -Name $name; (Get-Service $name).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30)); $stopped = $true }
    foreach ($binary in @($exporterBinary,'mq-config-check.exe','mq-dist.exe','mq-service.exe')) { Invoke-Native $helper @('replace',(Join-Path $payload $binary),(Join-Path $dest $binary)) }
    if (-not (Test-Path -LiteralPath $config) -or $ReplaceConfig) { Invoke-Native $helper @('replace',$candidateConfig,$config) }
    Write-Utf8 (Join-Path $scratch 'identity.json') $identityText
    Invoke-Native $helper @('replace',(Join-Path $scratch 'identity.json'),(Join-Path $dest 'identity.json'))
    $command = '"' + (Join-Path $dest 'mq-service.exe') + '" -name "' + $name + '" -binary "' + (Join-Path $dest $exporterBinary) + '" -config "' + $config + '" -mq "' + $MQPath + '" -logs "' + $logs + '"'
    if (-not $existing) { $null = New-Service -Name $name -BinaryPathName $command -Credential $ServiceCredential -StartupType Automatic }
    else {
        $serviceObject = Get-CimInstance Win32_Service -Filter ("Name='" + $name + "'")
        $change = Invoke-CimMethod -InputObject $serviceObject -MethodName Change -Arguments @{PathName=$command}
        if ($change.ReturnValue -ne 0) { throw ('SCM path update failed, code ' + $change.ReturnValue) }
    }
    if (-not $NoStart) { Start-Service -Name $name }
    Write-Output 'Installed. MQ connection and queue coverage are not yet verified.'
    if ($Exporter -eq 'prometheus') { Write-Output ('Check: & "' + (Join-Path $dest 'mq-dist.exe') + '" health --qmgr "' + $QueueManager + '" --url "http://127.0.0.1:' + $Port + '/metrics"') }
    else { Write-Output 'Verify queue-manager attributes and queue metrics at your OTLP receiver; no HTTP health listener is provided.' }
} catch {
    if ($stopped) { Write-Warning 'The existing service was stopped. Inspect the error and backups before restarting it manually.' }
    throw
} finally {
    $env:PATH = $oldPath
    [Net.ServicePointManager]::SecurityProtocol = $oldTLS
    # Only this invocation's reserved scratch directory is removed.
    try {
        if ($scratchCreated -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force }
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

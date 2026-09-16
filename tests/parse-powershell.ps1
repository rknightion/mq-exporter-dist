$ErrorActionPreference = 'Stop'
$failed = $false
Get-ChildItem (Join-Path $PSScriptRoot '../install/*.ps1') | ForEach-Object {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) { $errors | Write-Output; $failed = $true }
}
if ($failed) { exit 1 }
Write-Output 'PowerShell syntax parsed. This is not a Windows PowerShell 5.1 runtime test.'

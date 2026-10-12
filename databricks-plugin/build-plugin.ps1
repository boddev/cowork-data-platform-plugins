<#
.SYNOPSIS
  Builds the Azure Databricks Data Connector plugin ZIP for Microsoft 365 Copilot Cowork.

.DESCRIPTION
  Asks you for your workspace host name and OAuth registration ID(s), checks them, and creates
  dist\databricks-cowork-plugin.zip. Works in Windows PowerShell 5.1 and PowerShell 7+. Installs nothing.

.EXAMPLE
  .\build-plugin.ps1
  (Run with no parameters. The script asks for what it needs.)

.EXAMPLE
  .\build-plugin.ps1 -WorkspaceHost "adb-1234567890123456.7.azuredatabricks.net" -GenieAuthConfigId "abc123" -SqlAuthConfigId "def456"
#>
[CmdletBinding()]
param(
    [string]$WorkspaceHost,
    [string]$GenieAuthConfigId,
    [string]$SqlAuthConfigId,
    [string]$PluginVersion = "1.0.0"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgDir  = Join-Path $root 'package'
$distDir = Join-Path $root 'dist'
$zipPath = Join-Path $distDir 'databricks-cowork-plugin.zip'

function Fail($msg) { Write-Host ""; Write-Host "PROBLEM: $msg" -ForegroundColor Red; Write-Host "Nothing was built. Fix the item above and run the script again." -ForegroundColor Yellow; exit 1 }
function Clean([string]$s) { if ($null -eq $s) { return '' }; return $s.Trim().Trim('"').Trim("'").Trim() }
function CheckId($id, $label) {
    if ($id -match '\s')    { Fail "The $label contains a space. It should be a single code with no spaces." }
    if ($id.Length -gt 128) { Fail "The $label is longer than 128 characters. Check you copied the registration ID and not the client secret." }
}

Write-Host ""
Write-Host "=== Azure Databricks plugin builder ===" -ForegroundColor Cyan
Write-Host "You need these from the setup steps in README.md:"
Write-Host "  1) Your workspace host name           (README Step 1.2)"
Write-Host "  2) The OAuth registration ID for Genie (README Step 3.5)"
Write-Host "  3) OPTIONAL: a second registration ID for Databricks SQL (README Part 5)"
Write-Host ""

if (-not $WorkspaceHost) {
    Write-Host "Workspace host looks like:  adb-1234567890123456.7.azuredatabricks.net   (no https://, no slashes)" -ForegroundColor DarkGray
    $WorkspaceHost = Read-Host "Paste the workspace host name"
}
if (-not $GenieAuthConfigId) { $GenieAuthConfigId = Read-Host "Paste the OAuth registration ID for the GENIE connector" }
if (-not $PSBoundParameters.ContainsKey('SqlAuthConfigId') -and -not $SqlAuthConfigId) {
    Write-Host "Press Enter to skip the Databricks SQL connector (recommended for a first install)." -ForegroundColor DarkGray
    $SqlAuthConfigId = Read-Host "Paste the OAuth registration ID for the SQL connector (optional)"
}

$h = Clean $WorkspaceHost
$h = $h -replace '^https?://',''
$h = ($h -split '[/?#]')[0].TrimEnd('/')
$GenieAuthConfigId = Clean $GenieAuthConfigId
$SqlAuthConfigId   = Clean $SqlAuthConfigId

if (-not $h)                 { Fail "The workspace host name is empty." }
if ($h -match '[<>{}\s_]')   { Fail "The workspace host name '$h' contains a placeholder, space, or underscore. Copy it again from the browser address bar." }
if ($h -notmatch '^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') { Fail "'$h' does not look like a host name." }
if ($h -notlike '*.azuredatabricks.net') {
    Write-Host "NOTICE: '$h' does not end in .azuredatabricks.net. That is only expected for a custom or sovereign-cloud workspace URL." -ForegroundColor Yellow
    $ans = Read-Host "Type YES to continue, anything else to stop"
    if ($ans -ne 'YES') { Fail "Stopped by you." }
}
if (-not $GenieAuthConfigId) { Fail "The Genie OAuth registration ID is empty." }
CheckId $GenieAuthConfigId 'Genie OAuth registration ID'
if ($SqlAuthConfigId) {
    CheckId $SqlAuthConfigId 'SQL OAuth registration ID'
    if ($SqlAuthConfigId -eq $GenieAuthConfigId) { Fail "The SQL and Genie registration IDs are identical. Each connector needs its own registration (README Part 5)." }
}
if ($PluginVersion -notmatch '^\d+\.\d+\.\d+$') { Fail "PluginVersion must look like 1.0.0" }

$template = Join-Path $pkgDir 'manifest.template.json'
$fragment = Join-Path $pkgDir 'sql-connector.fragment.json'
if (-not (Test-Path $template) -or -not (Test-Path $fragment)) { Fail "Cannot find the template files in $pkgDir. Run this script from inside the databricks-plugin folder you downloaded, without moving files." }

$sqlBlock = ''
if ($SqlAuthConfigId) { $sqlBlock = [System.IO.File]::ReadAllText($fragment).Replace('{{SQL_AUTH_CONFIG_ID}}', $SqlAuthConfigId) }

$manifest = [System.IO.File]::ReadAllText($template)
$manifest = $manifest.Replace('{{SQL_CONNECTOR}}', $sqlBlock)
$manifest = $manifest.Replace('{{PLUGIN_VERSION}}', $PluginVersion).Replace('{{WORKSPACE_HOST}}', $h).Replace('{{GENIE_AUTH_CONFIG_ID}}', $GenieAuthConfigId)
try { $null = $manifest | ConvertFrom-Json } catch { Fail "The generated manifest is not valid JSON ($($_.Exception.Message)). Check for quotes or backslashes in the values you pasted." }

New-Item -ItemType Directory -Force $distDir | Out-Null
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$utf8 = New-Object System.Text.UTF8Encoding($false)
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $entry = $zip.CreateEntry('manifest.json')
    $w = New-Object System.IO.StreamWriter($entry.Open(), $utf8); $w.Write($manifest); $w.Dispose()

    $files = Get-ChildItem $pkgDir -Recurse -File | Where-Object { $_.Name -notlike 'manifest.template.json' -and $_.Name -notlike '*.fragment.json' }
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($pkgDir.Length).TrimStart('\','/').Replace('\','/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel)
    }
} finally { $zip.Dispose() }

$check = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try { $names = $check.Entries | ForEach-Object { $_.FullName } } finally { $check.Dispose() }
foreach ($need in 'manifest.json','color.png','outline.png','skills/databricks-data-assistant/SKILL.md') {
    if ($names -notcontains $need) { Fail "Built ZIP is missing $need" }
}
if ($names | Where-Object { $_ -match '\\' }) { Fail "Built ZIP contains backslash paths." }

Write-Host ""
Write-Host "SUCCESS" -ForegroundColor Green
Write-Host "Built: $zipPath"
Write-Host "Connectors included: Genie$(if ($SqlAuthConfigId) { ' + Databricks SQL' })"
Write-Host "Contents:"; $names | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "NEXT: go to README Part 4 and upload this ZIP in the Microsoft 365 admin center." -ForegroundColor Cyan

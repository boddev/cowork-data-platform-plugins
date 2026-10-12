<#
.SYNOPSIS
  Builds the Snowflake Data Connector plugin ZIP for Microsoft 365 Copilot Cowork.

.DESCRIPTION
  Asks you for two values, checks them, and creates dist\snowflake-cowork-plugin.zip.
  Works in Windows PowerShell 5.1 and PowerShell 7+. Needs no internet connection and installs nothing.

.EXAMPLE
  .\build-plugin.ps1
  (Run with no parameters. The script asks for what it needs.)

.EXAMPLE
  .\build-plugin.ps1 -McpUrl "https://myorg-myaccount.snowflakecomputing.com/api/v2/databases/MCP_DB/schemas/MCP_SCHEMA/mcp-servers/MY_MCP" -AuthConfigId "abc123"
#>
[CmdletBinding()]
param(
    [string]$McpUrl,
    [string]$AuthConfigId,
    [string]$PluginVersion = "1.0.0",
    [switch]$AllowNonSnowflakeHost
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgDir  = Join-Path $root 'package'
$distDir = Join-Path $root 'dist'
$zipPath = Join-Path $distDir 'snowflake-cowork-plugin.zip'

function Fail($msg) { Write-Host ""; Write-Host "PROBLEM: $msg" -ForegroundColor Red; Write-Host "Nothing was built. Fix the item above and run the script again." -ForegroundColor Yellow; exit 1 }
function Clean([string]$s) { if ($null -eq $s) { return '' }; return $s.Trim().Trim('"').Trim("'").Trim() }

Write-Host ""
Write-Host "=== Snowflake plugin builder ===" -ForegroundColor Cyan
Write-Host "You need two things from the setup steps in README.md:"
Write-Host "  1) The MCP server URL  (README Part 2, Step 2.3)"
Write-Host "  2) The OAuth client registration ID  (README Part 3, Step 3.4)"
Write-Host ""

if (-not $McpUrl) {
    Write-Host "MCP server URL looks like:"
    Write-Host "  https://myorg-myaccount.snowflakecomputing.com/api/v2/databases/MCP_DB/schemas/MCP_SCHEMA/mcp-servers/CORTEX_MCP" -ForegroundColor DarkGray
    $McpUrl = Read-Host "Paste the MCP server URL"
}
if (-not $AuthConfigId) {
    Write-Host ""
    Write-Host "The OAuth client registration ID is the code shown in the Teams Developer Portal after you saved the OAuth registration."
    $AuthConfigId = Read-Host "Paste the OAuth client registration ID"
}

$McpUrl       = (Clean $McpUrl).TrimEnd('/')
$AuthConfigId = Clean $AuthConfigId

if (-not $McpUrl)       { Fail "The MCP server URL is empty." }
if (-not $AuthConfigId) { Fail "The OAuth client registration ID is empty." }
if ($McpUrl -notmatch '^https://') { Fail "The MCP server URL must start with https://" }
if ($McpUrl -match '\s')           { Fail "The MCP server URL contains a space. Copy it again without extra characters." }
if ($McpUrl -match '[<>{}]')       { Fail "The MCP server URL still contains a placeholder such as <account_url>. Replace it with your real value." }

$uri = $null
if (-not [Uri]::TryCreate($McpUrl, [UriKind]::Absolute, [ref]$uri)) { Fail "The MCP server URL is not a valid web address." }
if ($uri.Host -match '_') { Fail "The host name '$($uri.Host)' contains an underscore (_). Snowflake MCP needs hyphens (-) in the account host name. See README Troubleshooting." }

$isSnowflake = $uri.Host -like '*.snowflakecomputing.com'
if ($isSnowflake) {
    if ($uri.AbsolutePath -notmatch '^/api/v2/databases/[^/]+/schemas/[^/]+/mcp-servers/[^/]+$') {
        Fail "The path of the URL should look like /api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<NAME>. Yours is: $($uri.AbsolutePath)"
    }
    if ($uri.Host -like '*.privatelink.snowflakecomputing.com') {
        Write-Host "WARNING: This is a PrivateLink URL. Copilot Cowork is a cloud service and cannot reach PrivateLink addresses. Use the public URL. See README Part 6." -ForegroundColor Yellow
        Fail "PrivateLink URL supplied."
    }
} elseif (-not $AllowNonSnowflakeHost) {
    Write-Host ""
    Write-Host "NOTICE: '$($uri.Host)' is not a *.snowflakecomputing.com address." -ForegroundColor Yellow
    Write-Host "That is correct ONLY if you are putting Azure API Management in front of Snowflake (README Part 6, Option B)."
    $ans = Read-Host "Type YES to continue, anything else to stop"
    if ($ans -ne 'YES') { Fail "Stopped by you." }
}
if ($AuthConfigId -match '\s')        { Fail "The OAuth client registration ID contains a space. It should be a single code with no spaces." }
if ($AuthConfigId.Length -gt 128)     { Fail "The OAuth client registration ID is longer than 128 characters. Check you copied the ID and not the secret." }
if ($PluginVersion -notmatch '^\d+\.\d+\.\d+$') { Fail "PluginVersion must look like 1.0.0" }

$template = Join-Path $pkgDir 'manifest.template.json'
if (-not (Test-Path $template)) { Fail "Cannot find $template. Run this script from inside the snowflake-plugin folder you downloaded, without moving files." }

$manifest = [System.IO.File]::ReadAllText($template)
$manifest = $manifest.Replace('{{PLUGIN_VERSION}}', $PluginVersion).Replace('{{MCP_URL}}', $McpUrl).Replace('{{AUTH_CONFIG_ID}}', $AuthConfigId)
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
foreach ($need in 'manifest.json','color.png','outline.png','skills/snowflake-data-assistant/SKILL.md') {
    if ($names -notcontains $need) { Fail "Built ZIP is missing $need" }
}
if ($names | Where-Object { $_ -match '\\' }) { Fail "Built ZIP contains backslash paths." }

Write-Host ""
Write-Host "SUCCESS" -ForegroundColor Green
Write-Host "Built: $zipPath"
Write-Host "Contents:"; $names | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "NEXT: go to README Part 4 and upload this ZIP in the Microsoft 365 admin center." -ForegroundColor Cyan

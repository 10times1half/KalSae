#
# fetch-webview2.ps1
# Downloads the Microsoft.Web.WebView2 NuGet package and extracts its
# contents into Vendor/WebView2/ so that CkalsaeWebView2 can find
# WebView2.h and WebView2LoaderStatic.lib.
#
# Usage:
#   .\Scripts\fetch-webview2.ps1              # latest stable
#   .\Scripts\fetch-webview2.ps1 -Version 1.0.2792.45
#
[CmdletBinding()]
param(
    [string]$Version = "latest",
    [string]$Destination = "Vendor/WebView2"
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$dest     = Join-Path $repoRoot $Destination

if ($Version -eq 'latest') {
    Write-Host "Querying NuGet for the latest Microsoft.Web.WebView2 version..."
    $idx = Invoke-RestMethod -UseBasicParsing `
        'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json'
    $stable = $idx.versions | Where-Object { $_ -notmatch '-' } | Select-Object -Last 1
    if (-not $stable) { throw "No stable version found on NuGet." }
    $Version = $stable
}

Write-Host "WebView2 SDK version: $Version"

$nupkgUrl = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$Version/microsoft.web.webview2.$Version.nupkg"
$tmp      = Join-Path ([System.IO.Path]::GetTempPath()) "wv2-$Version"
$nupkg    = "$tmp.zip"

if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }

Write-Host "Downloading $nupkgUrl..."
Invoke-WebRequest -UseBasicParsing -Uri $nupkgUrl -OutFile $nupkg

Write-Host "Extracting..."
Expand-Archive -Path $nupkg -DestinationPath $tmp -Force

New-Item -ItemType Directory -Force -Path $dest | Out-Null
# Copy just the parts we need (build/ and runtimes/).
Copy-Item -Recurse -Force (Join-Path $tmp 'build')    (Join-Path $dest 'build')
if (Test-Path (Join-Path $tmp 'runtimes')) {
    Copy-Item -Recurse -Force (Join-Path $tmp 'runtimes') (Join-Path $dest 'runtimes')
}

# Write a tiny marker so we remember which version is checked out.
Set-Content -Path (Join-Path $dest 'VERSION.txt') -Value $Version -NoNewline

Remove-Item -Recurse -Force $tmp
Remove-Item -Force $nupkg

Write-Host "Installed WebView2 SDK $Version -> $dest" -ForegroundColor Green

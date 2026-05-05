#
# fetch-webview2.ps1
# Downloads the Microsoft.Web.WebView2 NuGet package and extracts its
# contents into Sources/CKalsaeWV2/Vendor/WebView2/ so that CKalsaeWV2 can
# find WebView2.h. The path lives inside the target so SwiftPM does not
# treat the headerSearchPath as an unsafe build flag (no `..` escapes).
#
# Usage:
#   .\Scripts\fetch-webview2.ps1              # latest stable
#   .\Scripts\fetch-webview2.ps1 -Version 1.0.2792.45
#   .\Scripts\fetch-webview2.ps1 -ProjectRoot C:\MyApp
#   .\Scripts\fetch-webview2.ps1 -ProjectRoot C:\MyApp -Destination Sources/CKalsaeWV2/Vendor/WebView2
#   .\Scripts\fetch-webview2.ps1 -ProjectRoot C:\MyApp -DryRun
#
[CmdletBinding()]
param(
    [string]$Version = "latest",
    [string]$Destination = "Sources/CKalsaeWV2/Vendor/WebView2",
    [string]$ProjectRoot = "",
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$installRootRaw = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    [string]$repoRoot
} elseif ([System.IO.Path]::IsPathRooted($ProjectRoot)) {
    $ProjectRoot
} else {
    Join-Path (Get-Location) $ProjectRoot
}
$installRoot = [System.IO.Path]::GetFullPath($installRootRaw)
$dest = Join-Path $installRoot $Destination

if ($DryRun) {
    Write-Host "[DryRun] repoRoot    : $repoRoot"
    Write-Host "[DryRun] installRoot : $installRoot"
    Write-Host "[DryRun] destination : $dest"
    if ($Version -eq 'latest') {
        Write-Host "[DryRun] version     : latest (NuGet query skipped)"
    } else {
        Write-Host "[DryRun] version     : $Version"
    }
    return
}

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

# 헤더 — 빌드 입력 (CKalsaeWV2 의 headerSearchPath 가 이곳을 가리킴)
$includeOut = Join-Path $dest 'build\native\include'
New-Item -ItemType Directory -Force -Path $includeOut | Out-Null
Copy-Item -Recurse -Force (Join-Path $tmp 'build\native\include\*') $includeOut

# 런타임 DLL — 패키징 입력 (fixed-runtime 모드에서 동봉할 WebView2Loader.dll)
# WebView2LoaderStatic.lib 은 정적 링크를 쓰지 않으므로 복사하지 않는다.
foreach ($arch in @('win-x64', 'win-x86', 'win-arm64')) {
    $srcDll  = Join-Path $tmp "runtimes\$arch\native\WebView2Loader.dll"
    if (Test-Path $srcDll) {
        $dstDir = Join-Path $dest "runtimes\$arch\native"
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -Force $srcDll $dstDir
    }
}

# 라이선스 — 배포물 컴플라이언스용
foreach ($f in @('LICENSE.txt', 'THIRD_PARTY_NOTICES.txt')) {
    $src = Join-Path $tmp $f
    if (Test-Path $src) { Copy-Item -Force $src $dest }
}

# Write a tiny marker so we remember which version is checked out.
Set-Content -Path (Join-Path $dest 'VERSION.txt') -Value $Version -NoNewline

Remove-Item -Recurse -Force $tmp
Remove-Item -Force $nupkg

Write-Host "Installed WebView2 SDK $Version -> $dest" -ForegroundColor Green

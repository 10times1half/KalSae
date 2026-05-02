#
# smoke-fetch-webview2.ps1
# Verifies fetch-webview2 path resolution behavior without network/download.
#
# Usage:
#   .\Scripts\smoke-fetch-webview2.ps1
#
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fetchScript = Join-Path $repoRoot 'Scripts\fetch-webview2.ps1'

function Assert-Destination([string]$output, [string]$expectedDestination, [string]$label) {
    $line = ($output -split "`n" |
        Where-Object { $_ -match '^\[DryRun\] destination\s*:' } |
        Select-Object -First 1)

    if (-not $line) {
        throw "[$label] could not find destination line in output.`nActual output:`n$output"
    }

    $normalizedActual = $line.Trim().Replace('\\', '/')
    $normalizedExpected = "[DryRun] destination : $expectedDestination".Replace('\\', '/')
    if ($normalizedActual -ne $normalizedExpected) {
        throw "[$label] destination mismatch.`nExpected: $normalizedExpected`nActual  : $normalizedActual`nFull output:`n$output"
    }
}

Write-Host '[1/3] default install root dry-run check'
$defaultOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $fetchScript -DryRun 2>&1 | Out-String -Width 4096
$defaultDest = Join-Path $repoRoot 'Vendor\WebView2'
Assert-Destination $defaultOut $defaultDest 'default'

Write-Host '[2/3] absolute ProjectRoot dry-run check'
$tmpAbs = Join-Path ([System.IO.Path]::GetTempPath()) "kalsae-wv2-smoke-$([Guid]::NewGuid())"
New-Item -ItemType Directory -Path $tmpAbs | Out-Null
try {
    $absOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $fetchScript -ProjectRoot $tmpAbs -DryRun 2>&1 | Out-String -Width 4096
    $absDest = Join-Path $tmpAbs 'Vendor\WebView2'
    Assert-Destination $absOut $absDest 'absolute'
} finally {
    Remove-Item -Recurse -Force $tmpAbs
}

Write-Host '[3/3] relative ProjectRoot dry-run check'
$cwdBefore = Get-Location
$tmpBase = Join-Path ([System.IO.Path]::GetTempPath()) "kalsae-wv2-smoke-base-$([Guid]::NewGuid())"
$tmpRel = Join-Path $tmpBase 'consumer'
New-Item -ItemType Directory -Path $tmpRel -Force | Out-Null
try {
    Set-Location $tmpBase
    $relOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $fetchScript -ProjectRoot '.\consumer' -DryRun 2>&1 | Out-String -Width 4096
    $relDest = Join-Path $tmpRel 'Vendor\WebView2'
    Assert-Destination $relOut $relDest 'relative'
} finally {
    Set-Location $cwdBefore
    Remove-Item -Recurse -Force $tmpBase
}

Write-Host 'smoke-fetch-webview2: PASS' -ForegroundColor Green

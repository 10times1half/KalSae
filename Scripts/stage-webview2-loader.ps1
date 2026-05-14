#
# stage-webview2-loader.ps1
# Copies WebView2Loader.dll from Sources/CKalsaeWV2/Vendor/WebView2/runtimes/<arch>/native/
# into the SwiftPM build output directories so that bare `swift build` followed
# by direct invocation of `.\.build\<config>\app.exe` works without
# `0x8007007E (ERROR_MOD_NOT_FOUND)` on `LoadLibraryW("WebView2Loader.dll")`.
#
# `kalsae dev` / `kalsae build` already do this internally via
# `KSWebView2Provisioner.stageLoaderDLL`. This script is only needed for
# developers running `swift build` directly against the Kalsae checkout (or
# against a downstream consumer that uses `path:` dependency on Kalsae).
#
# Usage:
#   .\Scripts\stage-webview2-loader.ps1                          # stages debug + release if present
#   .\Scripts\stage-webview2-loader.ps1 -Configuration debug
#   .\Scripts\stage-webview2-loader.ps1 -ProjectRoot C:\MyApp -KalsaeRoot C:\Projects\Kalsae
#   .\Scripts\stage-webview2-loader.ps1 -Architecture win-arm64
#
[CmdletBinding()]
param(
    [ValidateSet('debug', 'release', 'both')]
    [string]$Configuration = 'both',
    [ValidateSet('win-x64', 'win-x86', 'win-arm64')]
    [string]$Architecture = 'win-x64',
    [string]$ProjectRoot = '',
    [string]$KalsaeRoot = ''
)

$ErrorActionPreference = 'Stop'

$scriptRepoRoot = [string](Resolve-Path (Join-Path $PSScriptRoot '..'))

# Resolve project root (where .build/ lives).
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $projectRoot = [string](Get-Location)
} elseif ([System.IO.Path]::IsPathRooted($ProjectRoot)) {
    $projectRoot = $ProjectRoot
} else {
    $projectRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $ProjectRoot))
}

# Resolve Kalsae root (where Sources/CKalsaeWV2/Vendor/WebView2 lives).
if ([string]::IsNullOrWhiteSpace($KalsaeRoot)) {
    # Default: the repo containing this script.
    $kalsaeRoot = $scriptRepoRoot
} elseif ([System.IO.Path]::IsPathRooted($KalsaeRoot)) {
    $kalsaeRoot = $KalsaeRoot
} else {
    $kalsaeRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $KalsaeRoot))
}

$src = Join-Path $kalsaeRoot "Sources/CKalsaeWV2/Vendor/WebView2/runtimes/$Architecture/native/WebView2Loader.dll"
if (-not (Test-Path $src)) {
    throw "WebView2Loader.dll not found at: $src`nRun .\Scripts\fetch-webview2.ps1 against the Kalsae checkout first."
}

$configs = @()
switch ($Configuration) {
    'debug'   { $configs = @('debug') }
    'release' { $configs = @('release') }
    'both'    { $configs = @('debug', 'release') }
}

$triples = @('x86_64-unknown-windows-msvc', 'aarch64-unknown-windows-msvc')

$buildDir = Join-Path $projectRoot '.build'
if (-not (Test-Path $buildDir)) {
    Write-Host "No .build/ directory at $buildDir — run ``swift build`` first." -ForegroundColor Yellow
    return
}

$staged = 0
foreach ($config in $configs) {
    # Triple-qualified output dirs.
    foreach ($triple in $triples) {
        $dest = Join-Path $buildDir (Join-Path $triple $config)
        if (Test-Path $dest -PathType Container) {
            Copy-Item -Force $src (Join-Path $dest 'WebView2Loader.dll')
            Write-Host "  staged -> $dest\WebView2Loader.dll" -ForegroundColor Green
            $staged++
        }
    }
    # Legacy .build/<config>/ — only if SwiftPM has already created it (as symlink or dir).
    $legacy = Join-Path $buildDir $config
    if (Test-Path $legacy) {
        Copy-Item -Force $src (Join-Path $legacy 'WebView2Loader.dll')
        Write-Host "  staged -> $legacy\WebView2Loader.dll" -ForegroundColor Green
        $staged++
    }
}

if ($staged -eq 0) {
    Write-Host "No matching .build/<triple>/<config>/ directories found. Run ``swift build`` (and optionally ``swift build -c release``) first." -ForegroundColor Yellow
} else {
    Write-Host "Done — staged WebView2Loader.dll into $staged location(s)." -ForegroundColor Green
}

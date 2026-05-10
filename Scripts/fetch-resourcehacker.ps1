#
# fetch-resourcehacker.ps1
# Downloads Resource Hacker (freeware, http://www.angusj.com/resourcehacker/)
# and extracts ResourceHacker.exe into a Kalsae tools cache directory so
# `kalsae build --standalone` can embed PE resources (RCDATA / RT_MANIFEST /
# frontend asset zip) without requiring the user to install it manually.
#
# Default install location:
#   $env:LOCALAPPDATA\Kalsae\Tools\ResourceHacker\
#
# This is a user-scoped cache so multiple projects share a single download.
# Override with -Destination (absolute or relative to current directory).
#
# Usage:
#   .\Scripts\fetch-resourcehacker.ps1
#   .\Scripts\fetch-resourcehacker.ps1 -Destination C:\Tools\ResourceHacker
#   .\Scripts\fetch-resourcehacker.ps1 -DryRun
#
[CmdletBinding()]
param(
    [string]$Destination = "",
    [string]$DownloadUrl = "https://www.angusj.com/resourcehacker/resource_hacker.zip",
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Join-Path $env:USERPROFILE 'AppData\Local'
    }
    $destPath = Join-Path $base 'Kalsae\Tools\ResourceHacker'
} elseif ([System.IO.Path]::IsPathRooted($Destination)) {
    $destPath = $Destination
} else {
    $destPath = Join-Path (Get-Location) $Destination
}
$destPath = [System.IO.Path]::GetFullPath($destPath)
$exePath = Join-Path $destPath 'ResourceHacker.exe'

if ($DryRun) {
    Write-Host "[DryRun] destination : $destPath"
    Write-Host "[DryRun] executable  : $exePath"
    Write-Host "[DryRun] downloadUrl : $DownloadUrl"
    return
}

if ((Test-Path $exePath) -and (-not $Force)) {
    Write-Host "ResourceHacker already installed at: $exePath"
    Write-Host "(Pass -Force to redownload.)"
    return
}

if (-not (Test-Path $destPath)) {
    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rh-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$zipPath = Join-Path $tmp 'resource_hacker.zip'

try {
    Write-Host "Downloading Resource Hacker from $DownloadUrl ..."
    # TLS 1.2 for older PowerShell versions.
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.SecurityProtocolType]::Tls12 -bor `
        [System.Net.SecurityProtocolType]::Tls11 -bor `
        [System.Net.SecurityProtocolType]::Tls
    Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $zipPath

    Write-Host "Extracting to $destPath ..."
    Expand-Archive -Path $zipPath -DestinationPath $destPath -Force

    if (-not (Test-Path $exePath)) {
        # Some Resource Hacker zips nest the exe in a subdirectory; flatten.
        $found = Get-ChildItem -Path $destPath -Filter 'ResourceHacker.exe' -Recurse `
            | Select-Object -First 1
        if ($found) {
            Copy-Item -Path $found.FullName -Destination $exePath -Force
        }
    }

    if (-not (Test-Path $exePath)) {
        throw "ResourceHacker.exe not found inside extracted archive at $destPath."
    }

    Write-Host "ResourceHacker installed: $exePath"
}
finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

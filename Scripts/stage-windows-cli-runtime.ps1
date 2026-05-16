#
# stage-windows-cli-runtime.ps1
#
# kalsae.exe(또는 임의 Swift-on-Windows 실행파일) 옆에 필요한 Swift 런타임
# DLL + VC++ 재배포 DLL 을 화이트리스트 방식으로 복사한다. dumpbin 이 보고하는
# 의존 DLL 을 BFS 로 재귀 해석하면서, 다음 두 화이트리스트에 매칭되는 것만
# 복사한다:
#   1) Swift 런타임 (swift*.dll, Foundation*.dll, _FoundationICU.dll,
#      _InternationalizationStubs.dll, dispatch.dll, BlocksRuntime.dll,
#      icudt*.dll, icuuc*.dll, icuin*.dll, swift_*.dll, etc.)
#   2) VC++ 재배포 (vcruntime140*.dll, msvcp140*.dll)
#
# 사용:
#   .\Scripts\stage-windows-cli-runtime.ps1 -Destination stage/kalsae-x64
#   .\Scripts\stage-windows-cli-runtime.ps1 -Executable .\.build\release\kalsae.exe `
#                                            -Destination stage/kalsae-x64
#
# 종속:
#   - dumpbin.exe 가 PATH 또는 VS Developer Environment 에 존재해야 함.
#     GitHub Actions 의 windows-latest 러너는 기본 포함.
#   - swift.exe 가 PATH 에 있어 런타임 디렉터리를 자동 탐지한다.
#
[CmdletBinding()]
param(
    [string]$Executable = "",
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. 경로 정규화
# ---------------------------------------------------------------------------

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if ([string]::IsNullOrWhiteSpace($Executable)) {
    $Executable = Join-Path $repoRoot '.build\release\kalsae.exe'
}
if (-not (Test-Path $Executable)) {
    throw "Executable not found: $Executable"
}
$Executable = (Resolve-Path $Executable).Path

if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
}
$Destination = (Resolve-Path $Destination).Path

Write-Host "[stage] executable  = $Executable"
Write-Host "[stage] destination = $Destination"

# ---------------------------------------------------------------------------
# 1. dumpbin 위치 확인
# ---------------------------------------------------------------------------

$dumpbin = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
if (-not $dumpbin) {
    # vcvars 환경이 활성화되지 않은 경우, VS Build Tools 의 dumpbin 을 직접 찾는다.
    $candidates = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\*\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe"
    )
    foreach ($pattern in $candidates) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $dumpbin = $found; break }
    }
    if (-not $dumpbin) {
        throw "dumpbin.exe not found. Run inside a VS Developer Prompt or call vcvars64.bat first."
    }
}
$dumpbinPath = if ($dumpbin -is [System.Management.Automation.CommandInfo]) { $dumpbin.Source } else { $dumpbin.FullName }
Write-Host "[stage] dumpbin     = $dumpbinPath"

# ---------------------------------------------------------------------------
# 2. Swift 런타임 / VC redist 검색 경로 수집
# ---------------------------------------------------------------------------

$searchDirs = [System.Collections.Generic.List[string]]::new()

# (a) swift.exe 옆 디렉터리 (compnerd/gha-setup-swift 가 PATH 에 등록).
$swift = Get-Command swift.exe -ErrorAction SilentlyContinue
if ($swift) {
    $swiftDir = Split-Path -Parent $swift.Source
    $searchDirs.Add($swiftDir)
    Write-Host "[stage] swift bin   = $swiftDir"

    # (b) 같은 설치의 Runtimes\<ver>\usr\bin 도 후보로 추가.
    $maybeRuntimes = @(
        (Join-Path (Split-Path -Parent $swiftDir) 'Runtimes'),
        (Join-Path (Split-Path -Parent (Split-Path -Parent $swiftDir)) 'Runtimes'),
        (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $swiftDir))) 'Runtimes')
    )
    foreach ($r in $maybeRuntimes) {
        if (Test-Path $r) {
            Get-ChildItem -Path $r -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $bin = Join-Path $_.FullName 'usr\bin'
                    if (Test-Path $bin) { $searchDirs.Add($bin) }
                }
        }
    }
}

# (c) Windows System32 (vcruntime140.dll 등이 여기에 있을 수 있음).
$searchDirs.Add("$env:SystemRoot\System32")

# (d) VS Build Tools 의 VC redist 디렉터리.
$vcRedistPatterns = @(
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT"
)
foreach ($pattern in $vcRedistPatterns) {
    Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $searchDirs.Add($_.FullName) }
}

$searchDirs = $searchDirs | Where-Object { Test-Path $_ } | Select-Object -Unique
Write-Host "[stage] search dirs:"
foreach ($d in $searchDirs) { Write-Host "    $d" }

# ---------------------------------------------------------------------------
# 3. 화이트리스트: 어떤 DLL 만 동봉할지 결정
# ---------------------------------------------------------------------------

# 정규식 매칭. 시스템 DLL (kernel32, user32 등) 은 제외한다.
$whitelist = @(
    '^swift.*\.dll$',                 # swiftCore, swift_Concurrency, swift_StringProcessing, etc.
    '^Foundation.*\.dll$',
    '^_Foundation.*\.dll$',
    '^_Concurrency.*\.dll$',
    '^_StringProcessing.*\.dll$',
    '^_InternationalizationStubs\.dll$',
    '^dispatch\.dll$',
    '^BlocksRuntime\.dll$',
    '^icudt\d*\.dll$',
    '^icuuc\d*\.dll$',
    '^icuin\d*\.dll$',
    '^icuio\d*\.dll$',
    '^vcruntime140.*\.dll$',
    '^msvcp140.*\.dll$',
    '^concrt140\.dll$'
)

function Test-Whitelisted {
    param([string]$Name)
    foreach ($pattern in $whitelist) {
        if ($Name -match $pattern) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# 4. dumpbin 으로 직접 의존성 추출
# ---------------------------------------------------------------------------

function Get-DllDependencies {
    param([string]$BinaryPath)
    $lines = & $dumpbinPath /dependents $BinaryPath 2>$null
    $deps = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match 'Image has the following dependencies:') {
            $inSection = $true; continue
        }
        if ($inSection) {
            $trim = $line.Trim()
            if ($trim -eq '') { continue }
            if ($trim -match '^Summary' -or $trim -match '^\s*\d') { break }
            if ($trim -match '\.dll$') { $deps.Add($trim) | Out-Null }
        }
    }
    return $deps
}

function Find-Dll {
    param([string]$Name)
    foreach ($dir in $searchDirs) {
        $candidate = Join-Path $dir $Name
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

# ---------------------------------------------------------------------------
# 5. BFS 로 전이 의존성 수집 (화이트리스트만 추적)
# ---------------------------------------------------------------------------

$visited = New-Object 'System.Collections.Generic.HashSet[string]'
$toCopy  = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$queue   = New-Object System.Collections.Generic.Queue[string]
$queue.Enqueue($Executable)

while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    $deps = Get-DllDependencies -BinaryPath $current
    foreach ($dep in $deps) {
        $depLower = $dep.ToLowerInvariant()
        if ($visited.Contains($depLower)) { continue }
        $visited.Add($depLower) | Out-Null
        if (-not (Test-Whitelisted -Name $dep)) {
            if ($Verbose) { Write-Host "  skip (sys) : $dep" }
            continue
        }
        $resolved = Find-Dll -Name $dep
        if (-not $resolved) {
            Write-Warning "Whitelisted DLL not found in search dirs: $dep"
            continue
        }
        $toCopy[$dep] = $resolved
        $queue.Enqueue($resolved)
    }
}

# ---------------------------------------------------------------------------
# 6. 복사
# ---------------------------------------------------------------------------

Write-Host "[stage] copying $($toCopy.Count) DLL(s):"
foreach ($entry in $toCopy.GetEnumerator() | Sort-Object Key) {
    Write-Host "    $($entry.Key)  <-  $($entry.Value)"
    Copy-Item -Path $entry.Value -Destination (Join-Path $Destination $entry.Key) -Force
}

# 최종 manifest 도 저장해 디버깅을 돕는다.
$manifest = $toCopy.GetEnumerator() | Sort-Object Key | ForEach-Object {
    [PSCustomObject]@{ name = $_.Key; source = $_.Value }
}
$manifest | ConvertTo-Json -Depth 3 |
    Set-Content -Path (Join-Path $Destination 'runtime-manifest.json') -Encoding utf8

Write-Host "[stage] done. manifest -> runtime-manifest.json"

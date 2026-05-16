#
# extract-windows-notices.ps1
#
# Docs/THIRD-PARTY-NOTICES.md 에서 Windows CLI 배포에 관련된 섹션만 추출해
# 별도 NOTICE.md 파일로 저장한다. Linux 의 LGPL 섹션 (§2.2, §3.x) 등을
# 배제하여 Windows zip 사용자에게 노이즈가 되지 않도록 한다.
#
# 포함되는 섹션:
#   - §1 Scope (전체 라이선스 모델 소개)
#   - §2.1 MIT / Apache-2.0 dependencies (정적 링크)
#   - §2.3 OS-provided components (WebView2 항목만 관련)
#   - §4 Apache-2.0 Dependencies
#   - §5 Microsoft WebView2 (Windows)
#   - §9 Reporting issues
#   - Changelog
#
# 사용:
#   .\Scripts\extract-windows-notices.ps1 -Output NOTICE.md
#
[CmdletBinding()]
param(
    [string]$Source = "",
    [Parameter(Mandatory = $true)]
    [string]$Output
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $repoRoot 'Docs\THIRD-PARTY-NOTICES.md'
}
if (-not (Test-Path $Source)) {
    throw "Source NOTICE file not found: $Source"
}

$lines = Get-Content -Path $Source -Encoding utf8

# 포함할 H2 (## N) 섹션의 번호. 하위 H3 는 본문 안에서 별도 처리.
$includeH2 = @('1', '2', '4', '5', '9')

# 결과 빌더
$result = New-Object System.Collections.Generic.List[string]
$result.Add('# Third-Party Notices — Kalsae CLI (Windows)')
$result.Add('')
$result.Add('> This is a Windows-specific extract of [Docs/THIRD-PARTY-NOTICES.md].')
$result.Add('> Linux / macOS / Android / iOS 전용 항목은 본 배포에 무관해 제외했다.')
$result.Add('> 전체 라이선스 본문은 https://github.com/<owner>/Kalsae 에서 참조하라.')
$result.Add('')
$result.Add('---')
$result.Add('')

# 상태 머신: 헤더를 만나면 포함 여부 결정.
$includeCurrent = $false
$inSubsection = $false
$includeSub = $true

foreach ($line in $lines) {
    if ($line -match '^# ') {
        # 최상위 제목은 우리가 직접 생성했으므로 건너뜀
        continue
    }
    if ($line -match '^## (\d+)\.\s') {
        $num = $Matches[1]
        $includeCurrent = $includeH2 -contains $num
        $inSubsection = $false
        if ($includeCurrent) { $result.Add($line) }
        continue
    }
    if ($line -match '^### (\d+)\.(\d+)\s') {
        # §2 안의 하위 항목: 2.1 / 2.3 만 포함, 2.2 (LGPL) 제외.
        # §3 안의 하위 항목: 전부 제외 (이미 §3 자체가 includeH2 에 없음).
        $major = $Matches[1]
        $minor = $Matches[2]
        $inSubsection = $true
        if ($major -eq '2') {
            $includeSub = ($minor -ne '2')
        }
        else {
            $includeSub = $true
        }
        if ($includeCurrent -and $includeSub) { $result.Add($line) }
        continue
    }
    if ($line -match '^## Changelog') {
        $includeCurrent = $true
        $inSubsection = $false
        $result.Add($line)
        continue
    }

    # 본문 라인
    if ($includeCurrent -and ((-not $inSubsection) -or $includeSub)) {
        $result.Add($line)
    }
}

# 파일 디렉터리 보장.
$outDir = Split-Path -Parent $Output
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$result | Set-Content -Path $Output -Encoding utf8
Write-Host "[notices] wrote $($result.Count) lines -> $Output"

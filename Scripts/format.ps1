# 로컬에서 swift-format 자동 수정 + CI 와 동일한 strict lint 검증.
# 사용법:
#   ./Scripts/format.ps1            # 포맷 후 lint
#   ./Scripts/format.ps1 -CheckOnly # lint 만 (CI 동등)
[CmdletBinding()]
param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Push-Location $root
try {
    if (-not $CheckOnly) {
        Write-Host "Formatting Sources/ Tests/ ..."
        swift format format -i --recursive Sources Tests
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    Write-Host "Linting (strict) ..."
    swift format lint --strict --recursive Sources Tests
    if ($LASTEXITCODE -ne 0) {
        Write-Error "swift-format lint failed. Run './Scripts/format.ps1' to auto-fix."
        exit $LASTEXITCODE
    }
    Write-Host "OK"
}
finally {
    Pop-Location
}

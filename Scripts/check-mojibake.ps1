[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$CodeOnly,
    [switch]$NoFail
)

$ErrorActionPreference = 'Stop'

$include = @(
    '*.swift', '*.md', '*.json', '*.yml', '*.yaml', '*.ps1',
    '*.kts', '*.gradle', '*.txt', '*.html', '*.js', '*.ts',
    '*.c', '*.cpp', '*.h', '*.modulemap', '*.log'
)

if ($CodeOnly) {
    $include = @(
        '*.swift', '*.md', '*.json', '*.yml', '*.yaml', '*.ps1',
        '*.kts', '*.gradle', '*.txt', '*.html', '*.js', '*.ts',
        '*.c', '*.cpp', '*.h', '*.modulemap'
    )
}

$excludeDirRegex = @(
    '\\.git\\',
    '\\.build\\',
    '\\node_modules\\',
    '\\Vendor\\WebView2\\'
)

# Signatures that commonly indicate mojibake in this repository.
$patterns = @(
    '[\uFFFD]',       # Unicode replacement character
    '[\uF900-\uFAFF]',  # CJK compatibility ideographs often seen in broken UTF-8
    '(?:^|[^A-Za-z0-9_])\?[\uAC00-\uD7A3]'  # Question mark followed by Hangul (not try? style)
)

$files = Get-ChildItem -Path $Root -Recurse -File -Include $include |
    Where-Object {
        $full = $_.FullName
        foreach ($r in $excludeDirRegex) {
            if ($full -match $r) { return $false }
        }
        return $true
    }

$hits = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
    foreach ($pattern in $patterns) {
        $matches = Select-String -Path $file.FullName -Pattern $pattern -AllMatches
        foreach ($m in $matches) {
            $hits.Add([pscustomobject]@{
                    Path = $m.Path
                    Line = $m.LineNumber
                    Text = $m.Line.TrimEnd()
                    Pattern = $pattern
                })
        }
    }
}

if ($hits.Count -eq 0) {
    Write-Host 'No mojibake signatures found.' -ForegroundColor Green
    exit 0
}

$unique = $hits |
    Sort-Object Path, Line, Text, Pattern -Unique

Write-Host "Detected $($unique.Count) mojibake signature(s):" -ForegroundColor Yellow
foreach ($h in $unique) {
    Write-Host ("{0}:{1}: {2}" -f $h.Path, $h.Line, $h.Text)
}

if ($NoFail) {
    exit 0
}

exit 1

#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot '프로그램\구글참조무결성검증.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('naver-google-integrity-' + [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $testRoot 'google-reference'
$outputRoot = Join-Path $testRoot 'naver-output'
$manifestPath = Join-Path $outputRoot 'integrity.json'
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'nested') -Force
    $null = New-Item -ItemType Directory -Path $outputRoot -Force
    Set-Content -LiteralPath (Join-Path $sourceRoot 'one.txt') -Value '원본 1' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $sourceRoot 'nested\two.txt') -Value '원본 2' -Encoding UTF8
    $before = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | ForEach-Object {
        [pscustomobject]@{ Path=$_.FullName; Hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    & $scriptPath -Mode Capture -SourceRoot $sourceRoot -ManifestPath $manifestPath | Out-Null
    & $scriptPath -Mode Verify -SourceRoot $sourceRoot -ManifestPath $manifestPath | Out-Null
    foreach ($file in $before) {
        if ((Get-FileHash -LiteralPath $file.Path -Algorithm SHA256).Hash -ne $file.Hash) {
            throw '무결성 검사기가 참조 원본을 변경했습니다.'
        }
    }
    Add-Content -LiteralPath (Join-Path $sourceRoot 'one.txt') -Value '변경' -Encoding UTF8
    $failed = $false
    try { & $scriptPath -Mode Verify -SourceRoot $sourceRoot -ManifestPath $manifestPath | Out-Null }
    catch { $failed = $_.Exception.Message -match '무결성 검사 실패' }
    if (-not $failed) { throw '참조 원본 변경이 차단되지 않았습니다.' }
    $insideFailed = $false
    try { & $scriptPath -Mode Capture -SourceRoot $sourceRoot -ManifestPath (Join-Path $sourceRoot 'forbidden.json') | Out-Null }
    catch { $insideFailed = $_.Exception.Message -match '참조 폴더 안에 만들 수 없습니다' }
    if (-not $insideFailed) { throw '참조 원본 폴더 내부 기록 생성이 차단되지 않았습니다.' }
    Write-Output 'Google reference integrity test passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

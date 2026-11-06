#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot '프로그램\독자반응분석.ps1'
$configPath = Join-Path $projectRoot '설정.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('NaverReaderTest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $posts = @()
    for ($index = 1; $index -le 6; $index++) {
        $posts += [pscustomobject]@{
            title = "테스트 글 $index"
            category = $(if ($index -le 3) { 'AI·데이터센터' } else { '전력·스마트그리드' })
            bodyLength = 2500 + ($index * 100)
            views = 10 + ($index * 20)
            likes = $index
            comments = [math]::Floor($index / 2)
        }
    }
    $metrics = [pscustomobject]@{
        periodStart = '2026-10-01'
        periodEnd = '2026-10-31'
        summary = [pscustomobject]@{ views = 450; uniqueVisitors = 300; visits = 360; averageDurationSeconds = 95 }
        posts = $posts
        searchTerms = @(
            [pscustomobject]@{ term = 'AI 데이터센터 전력'; visits = 22 },
            [pscustomobject]@{ term = '스마트그리드 기술'; visits = 15 }
        )
        device = [pscustomobject]@{ mobilePercent = 78 }
    }
    $inputPath = Join-Path $tempRoot '독자 반응.json'
    $outputPath = Join-Path $tempRoot '분석 결과.json'
    $metrics | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inputPath -Encoding UTF8

    $validation = & $scriptPath -Mode Validate -Path $inputPath -ConfigPath $configPath
    if (-not $validation.IsValid) { throw "Valid reader metrics were rejected: $($validation.Issues -join '; ')" }
    $analysis = & $scriptPath -Mode Analyze -Path $inputPath -OutputPath $outputPath -ConfigPath $configPath
    if ($analysis.evidenceStatus -ne 'sufficient' -or -not $analysis.mobileFirst -or $analysis.rankingGuarantee) {
        throw 'Sufficient reader evidence was not analyzed correctly.'
    }
    if ($analysis.recommendedBodyLength.minimum -lt 1700 -or $analysis.recommendedBodyLength.maximum -gt 3300) {
        throw 'Recommended length escaped the configured bounds.'
    }
    if (@($analysis.topSearchTerms).Count -ne 2) { throw 'Qualified search terms were not returned.' }

    $insufficient = $metrics | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $insufficient.periodStart = '2026-10-30'
    $insufficient.posts = @($insufficient.posts | Select-Object -First 2)
    $insufficient.summary.views = 20
    $smallPath = Join-Path $tempRoot '표본 부족.json'
    $smallOutput = Join-Path $tempRoot '표본 부족 결과.json'
    $insufficient | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $smallPath -Encoding UTF8
    $smallResult = & $scriptPath -Mode Analyze -Path $smallPath -OutputPath $smallOutput -ConfigPath $configPath
    if ($smallResult.evidenceStatus -ne 'insufficient' -or
        $smallResult.recommendedBodyLength.minimum -ne 2000 -or
        $smallResult.recommendedBodyLength.maximum -ne 3000 -or
        @($smallResult.topSearchTerms).Count -ne 0) {
        throw 'Insufficient evidence did not preserve safe defaults.'
    }

    $invalid = $metrics | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $invalid.device.mobilePercent = 120
    $invalid | Add-Member -NotePropertyName gender -NotePropertyValue @('unknown')
    $invalidPath = Join-Path $tempRoot '잘못된 입력.json'
    $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidPath -Encoding UTF8
    $invalidResult = & $scriptPath -Mode Validate -Path $invalidPath -ConfigPath $configPath
    if ($invalidResult.IsValid -or $invalidResult.Issues.Count -lt 2) {
        throw 'Invalid or sensitive reader metrics were not rejected.'
    }

    $overwriteBlocked = $false
    try { & $scriptPath -Mode Analyze -Path $inputPath -OutputPath $outputPath -ConfigPath $configPath | Out-Null }
    catch { $overwriteBlocked = $true }
    if (-not $overwriteBlocked) { throw 'Existing analysis output was overwritten.' }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Output 'Reader analytics tests passed.'

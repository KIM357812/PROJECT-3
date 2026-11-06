#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $projectRoot '프로그램\편집기재구성실행검증.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('네이버 재구성 실행 검증 ' + [guid]::NewGuid().ToString('N'))

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $planPath = Join-Path $testRoot 'plan.json'
    $goodPath = Join-Path $testRoot 'good.json'
    $badPath = Join-Path $testRoot 'bad.json'
    $plan = [pscustomobject]@{
        contentId = 'NTE-EXEC-001'
        actions = @(
            [pscustomobject]@{ sequence=1; action='InsertBlock'; text='첫 문단' },
            [pscustomobject]@{ sequence=2; action='InsertMeasuredSpacer'; expectedGapPx=18; tolerancePx=0.5; fontSizePx=11; lineHeight=1.6 },
            [pscustomobject]@{ sequence=3; action='InsertBlock'; text='둘째 문단' }
        )
    }
    $good = [pscustomobject]@{
        contentId = 'NTE-EXEC-001'
        saveAttempted = $false
        records = @(
            [pscustomobject]@{ sequence=1; editorBodyFocusedBefore=$true; toolbarOrDialogFocusedBefore=$false; editorParagraphCountAfter=1; observedText='첫 문단'; standaloneParagraph=$true; mergedWithAdjacentBlock=$false },
            [pscustomobject]@{ sequence=2; editorBodyFocusedBefore=$true; toolbarOrDialogFocusedBefore=$false; editorParagraphCountAfter=2; observedText=''; emptyStandaloneParagraph=$true; renderedHeightPx=17.6; fontSizePx=11; lineHeight=1.6 },
            [pscustomobject]@{ sequence=3; editorBodyFocusedBefore=$true; toolbarOrDialogFocusedBefore=$false; editorParagraphCountAfter=3; observedText='둘째 문단'; standaloneParagraph=$true; mergedWithAdjacentBlock=$false }
        )
    }
    $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8
    $good | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $goodPath -Encoding UTF8
    $valid = & $validator -PlanPath $planPath -ObservationPath $goodPath | ConvertFrom-Json
    if (-not $valid.IsValid -or -not $valid.SaveAllowed -or $valid.ActionCount -ne 3) {
        throw 'A valid action-by-action reconstruction observation was rejected.'
    }

    $bad = $good | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $bad.records[2].observedText = '첫 문단둘째 문단'
    $bad.records[2].mergedWithAdjacentBlock = $true
    $bad.records[2].editorParagraphCountAfter = 2
    $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $blocked = $false
    try { & $validator -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $blocked = $true }
    if (-not $blocked) { throw 'A missing and merged paragraph was not blocked before save.' }
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
Write-Output 'Editor reconstruction execution validation tests passed.'

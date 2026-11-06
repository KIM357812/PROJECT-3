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
            [pscustomobject]@{ sequence=3; action='InsertBlock'; text='둘째 문단' },
            [pscustomobject]@{ sequence=4; action='InsertCalloutTable'; text="육하원칙 한눈에 보기`n누가 : 실제 주체"; calloutKind='FiveWOneH'; formatting=[pscustomobject]@{ backgroundColor='#e3fdc8'; accentColor='#66a33b'; accentWidthPx=4; titleColor='#2f7d19' } },
            [pscustomobject]@{ sequence=5; action='InsertImage'; fileName='01-대표.jpg'; role='대표'; formatting=[pscustomobject]@{ alignment='center'; displayWidthPx=340 } }
        )
    }
    $good = [pscustomobject]@{
        contentId = 'NTE-EXEC-001'
        saveAttempted = $false
        records = @(
            [pscustomobject]@{ sequence=1; editorBodyFocusedBefore=$true; toolbarOrDialogFocusedBefore=$false; editorParagraphCountAfter=1; observedText='첫 문단'; standaloneParagraph=$true; mergedWithAdjacentBlock=$false },
            [pscustomobject]@{ sequence=2; editorBodyFocusedBefore=$true; toolbarOrDialogFocusedBefore=$false; editorParagraphCountAfter=2; observedText=''; emptyStandaloneParagraph=$true; renderedHeightPx=17.6; fontSizePx=11; lineHeight=1.6 },
            [pscustomobject]@{ sequence=3; editorBodyFocusedBefore=$true; toolbarOrDialogFocusedBefore=$false; editorParagraphCountAfter=3; observedText='둘째 문단'; standaloneParagraph=$true; mergedWithAdjacentBlock=$false },
            [pscustomobject]@{ sequence=4; editorBodyFocusedBefore=$true; toolbarOrDialogFocusedBefore=$false; editorLogicalBlockCountAfter=4; observedText="육하원칙 한눈에 보기`n누가 : 실제 주체"; standaloneComponent=$true; singleCellTable=$true; horizontalOverflow=$false; blankParagraphCountBefore=0; blankParagraphCountAfter=0; calloutKind='FiveWOneH'; backgroundColor='#e3fdc8'; accentColor='#66a33b'; accentWidthPx=4; titleColor='#2f7d19' },
            [pscustomobject]@{ sequence=5; editorBodyFocusedBefore=$true; toolbarOrDialogFocusedBefore=$false; editorLogicalBlockCountAfter=5; fileName='01-대표.jpg'; role='대표'; standaloneComponent=$true; naverHostedImage=$true; alignment='center'; displayWidthPx=340 }
        )
    }
    $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8
    $good | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $goodPath -Encoding UTF8
    $valid = & $validator -PlanPath $planPath -ObservationPath $goodPath | ConvertFrom-Json
    if (-not $valid.IsValid -or -not $valid.SaveAllowed -or $valid.ActionCount -ne 5) {
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

    $badCallout = $good | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $badCallout.records[3].accentWidthPx = 18
    $badCallout.records[3].horizontalOverflow = $true
    $badCallout | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $badCalloutBlocked = $false
    try { & $validator -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $badCalloutBlocked = $true }
    if (-not $badCalloutBlocked) { throw 'An invalid callout table was not blocked before save.' }

    $badImage = $good | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $badImage.records[4].displayWidthPx = 520
    $badImage.records[4].alignment = 'left'
    $badImage | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $badImageBlocked = $false
    try { & $validator -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $badImageBlocked = $true }
    if (-not $badImageBlocked) { throw 'An incorrectly aligned image was not blocked before save.' }
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
Write-Output 'Editor reconstruction execution validation tests passed.'

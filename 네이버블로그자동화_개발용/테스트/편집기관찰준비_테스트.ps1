#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$prepareScript = Join-Path $projectRoot '프로그램\편집기관찰준비.ps1'
$validatorScript = Join-Path $projectRoot '프로그램\편집기결과검증.ps1'
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('편집기 관찰 준비 ' + [guid]::NewGuid().ToString('N'))
$planPath = Join-Path $testRoot 'plan.json'
$outputPath = Join-Path $testRoot 'observation.json'

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    [pscustomobject]@{
        contentId='NTE-OBSERVE-TEST'; title='제목'; body='본문'; tags=@('AI')
        category='블로그 소개'; visibility='비공개'; registerAsNotice=$false
        allowPublicPublish=$false
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planPath -Encoding UTF8

    $created = & $prepareScript -Mode BeforeSave -PlanPath $planPath `
        -OutputPath $outputPath | ConvertFrom-Json
    if (-not $created.requiresActualObservation -or
        -not (Test-Path -LiteralPath $created.output -PathType Leaf)) {
        throw 'The editor observation template was not created.'
    }
    $template = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $template.registerAsNotice -or
        $null -ne $template.publicPublishAttempted -or
        $null -ne $template.imageCount -or
        $null -ne $template.imageServerUploadVerified -or
        $null -ne $template.saveAttemptCount -or
        $null -ne $template.bodyFontSizePx -or
        -not [string]::IsNullOrWhiteSpace([string]$template.bodyFontFamily) -or
        -not [string]::IsNullOrWhiteSpace([string]$template.bodyTextAlignment) -or
        -not [string]::IsNullOrWhiteSpace([string]$template.bodyLastLineAlignment) -or
        $null -ne $template.bodyLineHeightPx -or
        $null -ne $template.paragraphMarginBottomPx -or
        $null -ne $template.bodyParagraphPairCount -or
        @($template.paragraphGapLayouts).Count -ne 0 -or
        $null -ne $template.questionToReferenceGapLayout -or
        @($template.headingLayouts).Count -ne 0 -or
        @($template.calloutLayouts).Count -ne 0 -or
        $null -ne $template.mobileBodyFontSizePx -or
        -not [string]::IsNullOrWhiteSpace([string]$template.mobileBodyFontFamily) -or
        -not [string]::IsNullOrWhiteSpace([string]$template.mobileBodyTextAlignment) -or
        -not [string]::IsNullOrWhiteSpace([string]$template.mobileBodyLastLineAlignment) -or
        $null -ne $template.mobileBodyLineHeightPx -or
        $null -ne $template.mobileParagraphMarginBottomPx -or
        $null -ne $template.mobileBodyParagraphPairCount -or
        @($template.mobileParagraphGapLayouts).Count -ne 0 -or
        $null -ne $template.mobileQuestionToReferenceGapLayout -or
        @($template.mobileHeadingLayouts).Count -ne 0 -or
        @($template.mobileCalloutLayouts).Count -ne 0 -or
        [string]$template.evidenceNote -notlike '*기본서체·양쪽 정렬*' -or
        -not [string]::IsNullOrWhiteSpace([string]$template.layoutMeasurementSource) -or
        -not [string]::IsNullOrWhiteSpace([string]$template.title)) {
        throw 'The editor observation template prefilled unobserved safety values.'
    }

    $blankWasBlocked = $false
    try {
        & $validatorScript -Mode BeforeSave -PlanPath $planPath `
            -ObservationPath $outputPath | Out-Null
    }
    catch { $blankWasBlocked = $true }
    if (-not $blankWasBlocked) { throw 'A blank observation template passed validation.' }

    $overwriteBlocked = $false
    try { & $prepareScript -Mode BeforeSave -PlanPath $planPath -OutputPath $outputPath | Out-Null }
    catch { $overwriteBlocked = $true }
    if (-not $overwriteBlocked) { throw 'An existing observation template was overwritten.' }

    Write-Output 'Editor observation preparation tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        if (-not $resolved.StartsWith($systemTemp + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean outside the system temp directory: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

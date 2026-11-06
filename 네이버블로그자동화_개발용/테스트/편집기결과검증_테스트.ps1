#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $projectRoot '프로그램\편집기결과검증.ps1'
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('편집기 결과 검증 ' + [guid]::NewGuid().ToString('N'))
$planPath = Join-Path $testRoot 'plan.json'
$beforePath = Join-Path $testRoot 'before.json'
$afterPath = Join-Path $testRoot 'after.json'
$badPath = Join-Path $testRoot 'bad.json'

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $plan = [pscustomobject]@{
        contentId='NTE-EDITOR-TEST'; draftType='TechnicalArticle'; title='검증 제목'; body="첫 문단입니다.`r`n`r`n첫 소제목`r`n`r`n두 번째 문단입니다."
        tags=@('AI','데이터센터','전력산업'); category='블로그 소개'; visibility='비공개'
        registerAsNotice=$false
        sectionHeadings=@('첫 소제목')
        sectionFormatting=[pscustomobject]@{
            headingFontSize=19; bodyFontSize=16; bodyLineHeight=1.75; bodyLineHeightPx=28
            paragraphMarginBottomPx=18; headingMarginTopPx=35; headingMarginBottomPx=15
        }
        paragraphGapFormatting=[pscustomobject]@{
            mode='SingleSizedSpacerParagraph'; gapPx=18; gapTolerancePx=0.5; spacerParagraphCount=1
            spacerFontSizePx=11; spacerLineHeight=1.6
            applyOnlyBetweenOrdinaryBodyParagraphs=$true
            forbidAdjacentToSectionHeadings=$true; forbidAdjacentToCallouts=$true
            requirePcAndMobileMeasurement=$true
        }
        referenceFormatting=[pscustomobject]@{
            questionToReferenceGap=[pscustomobject]@{
                order='ReaderQuestionToReferenceLine'; mode='SingleSizedSpacerParagraph'
                gapPx=32; gapTolerancePx=0.5; spacerParagraphCount=1
                spacerFontSizePx=16; spacerLineHeight=2.0
                requirePcAndMobileMeasurement=$true
            }
        }
        calloutFormatting=[pscustomobject]@{
            titleFontSizePx=15; bodyLineHeight=1.75; paragraphMarginBottomPx=18
            forbidAdjacentBlankParagraphs=$true
            styles=@(
                [pscustomobject]@{ name='배경·맥락'; titleMarginBottomPx=8; outerMarginTopPx=30; outerMarginBottomPx=20 },
                [pscustomobject]@{ name='육하원칙·핵심요약'; titleMarginBottomPx=10; outerMarginTopPx=30; outerMarginBottomPx=20 },
                [pscustomobject]@{ name='운영자판단·결론'; titleMarginBottomPx=8; outerMarginTopPx=30; outerMarginBottomPx=20 }
            )
        }
        imageSpecification=[pscustomobject]@{ count=3 }
        imagePlacements=@(
            [pscustomobject]@{ order=1; fileName='01-대표.jpg' },
            [pscustomobject]@{ order=2; fileName='02-비용경로.jpg' },
            [pscustomobject]@{ order=3; fileName='03-비용분담.jpg' }
        )
    }
    $plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planPath -Encoding UTF8

    $before = [pscustomobject]@{
        contentId='NTE-EDITOR-TEST'; observedAt='2026-11-05T12:00:00+09:00'
        editorUrl='https://blog.naver.com/PostWriteForm.naver'
        title='검증 제목'; body="첫 문단입니다.`n`n첫 소제목`n`n두 번째 문단입니다."
        tags=@('전력산업','AI','데이터센터'); category='블로그 소개'; visibility='비공개'
        registerAsNotice=$false; publicPublishAttempted=$false
        externalSavePerformed=$false; savedAsPrivate=$false; publicUrlCreated=$false
        savedDraftIndicator=''
        imageCount=3; imageFileNames=@('01-대표.jpg','02-비용경로.jpg','03-비용분담.jpg')
        imageOrderVerified=$true; imageServerUploadVerified=$true
        pcLayoutVerified=$true; mobileLayoutVerified=$false
        layoutMeasurementSource='RenderedNaverDomAndScreen'
        bodyFontSizePx=16; bodyLineHeightPx=28; paragraphMarginBottomPx=18
        bodyParagraphPairCount=1
        paragraphGapLayouts=@(
            [pscustomobject]@{
                context='OrdinaryBodyToOrdinaryBody'; gapPx=17.6; spacerParagraphCount=1
                spacerHeightPx=17.6; spacerFontSizePx=11; spacerLineHeight=1.6
                adjacentToSectionHeading=$false; adjacentToCallout=$false
            }
        )
        questionToReferenceGapLayout=[pscustomobject]@{
            order='ReaderQuestionToReferenceLine'; gapPx=32; spacerParagraphCount=1
            spacerHeightPx=32; spacerFontSizePx=16; spacerLineHeight=2.0
        }
        headingLayouts=@(
            [pscustomobject]@{
                text='첫 소제목'; standaloneParagraph=$true; fontSizePx=19
                marginTopPx=35; marginBottomPx=15
            }
        )
        calloutLayouts=@(
            [pscustomobject]@{ name='배경·맥락'; titleFontSizePx=15; titleMarginBottomPx=8; bodyFontSizePx=16; bodyLineHeight=1.75; paragraphMarginBottomPx=18; outerMarginTopPx=30; outerMarginBottomPx=20; blankParagraphCountBefore=0; blankParagraphCountAfter=0 },
            [pscustomobject]@{ name='육하원칙·핵심요약'; titleFontSizePx=15; titleMarginBottomPx=10; bodyFontSizePx=16; bodyLineHeight=1.75; paragraphMarginBottomPx=18; outerMarginTopPx=30; outerMarginBottomPx=20; blankParagraphCountBefore=0; blankParagraphCountAfter=0 },
            [pscustomobject]@{ name='운영자판단·결론'; titleFontSizePx=15; titleMarginBottomPx=8; bodyFontSizePx=16; bodyLineHeight=1.75; paragraphMarginBottomPx=18; outerMarginTopPx=30; outerMarginBottomPx=20; blankParagraphCountBefore=0; blankParagraphCountAfter=0 }
        )
        mobileBodyFontSizePx=16; mobileBodyLineHeightPx=28; mobileParagraphMarginBottomPx=18
        mobileBodyParagraphPairCount=1
        mobileParagraphGapLayouts=@(
            [pscustomobject]@{
                context='OrdinaryBodyToOrdinaryBody'; gapPx=17.6; spacerParagraphCount=1
                spacerHeightPx=17.6; spacerFontSizePx=11; spacerLineHeight=1.6
                adjacentToSectionHeading=$false; adjacentToCallout=$false
            }
        )
        mobileQuestionToReferenceGapLayout=[pscustomobject]@{
            order='ReaderQuestionToReferenceLine'; gapPx=32; spacerParagraphCount=1
            spacerHeightPx=32; spacerFontSizePx=16; spacerLineHeight=2.0
        }
        mobileHeadingLayouts=@(
            [pscustomobject]@{
                text='첫 소제목'; standaloneParagraph=$true; fontSizePx=19
                marginTopPx=35; marginBottomPx=15
            }
        )
        mobileCalloutLayouts=@(
            [pscustomobject]@{ name='배경·맥락'; titleFontSizePx=15; titleMarginBottomPx=8; bodyFontSizePx=16; bodyLineHeight=1.75; paragraphMarginBottomPx=18; outerMarginTopPx=30; outerMarginBottomPx=20; blankParagraphCountBefore=0; blankParagraphCountAfter=0 },
            [pscustomobject]@{ name='육하원칙·핵심요약'; titleFontSizePx=15; titleMarginBottomPx=10; bodyFontSizePx=16; bodyLineHeight=1.75; paragraphMarginBottomPx=18; outerMarginTopPx=30; outerMarginBottomPx=20; blankParagraphCountBefore=0; blankParagraphCountAfter=0 },
            [pscustomobject]@{ name='운영자판단·결론'; titleFontSizePx=15; titleMarginBottomPx=8; bodyFontSizePx=16; bodyLineHeight=1.75; paragraphMarginBottomPx=18; outerMarginTopPx=30; outerMarginBottomPx=20; blankParagraphCountBefore=0; blankParagraphCountAfter=0 }
        )
        saveAttemptCount=1; publishDelayObserved=$false; recoveryAction=''
    }
    $before | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $beforePath -Encoding UTF8
    $beforeResult = & $validator -Mode BeforeSave -PlanPath $planPath `
        -ObservationPath $beforePath | ConvertFrom-Json
    if (-not $beforeResult.IsValid -or $beforeResult.ExternalSavePerformed) {
        throw 'A valid before-save observation was rejected.'
    }

    $after = $before | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $after.externalSavePerformed = $true
    $after.savedAsPrivate = $true
    $after.mobileLayoutVerified = $true
    $after.savedDraftIndicator = '임시저장 완료'
    $after | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $afterPath -Encoding UTF8
    $afterResult = & $validator -Mode AfterSave -PlanPath $planPath `
        -ObservationPath $afterPath | ConvertFrom-Json
    if (-not $afterResult.IsValid -or -not $afterResult.ExternalSavePerformed) {
        throw 'A valid after-save observation was rejected.'
    }

    $bad = $after | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $bad.title = '다른 제목'
    $bad.visibility = '전체공개'
    $bad.publicPublishAttempted = $true
    $bad.publicUrlCreated = $true
    $bad | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $badWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $badWasBlocked = $true }
    if (-not $badWasBlocked) { throw 'An unsafe editor observation was not blocked.' }

    $badImage = $after | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $badImage.imageFileNames = @('02-비용경로.jpg','01-대표.jpg','03-비용분담.jpg')
    $badImage.imageServerUploadVerified = $false
    $badImage | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $badImageWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $badImageWasBlocked = $true }
    if (-not $badImageWasBlocked) { throw 'An invalid technical-article image observation was not blocked.' }

    $missingLayout = $after | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $missingLayout.headingLayouts = @()
    $missingLayout.calloutLayouts = @()
    $missingLayout.mobileHeadingLayouts = @()
    $missingLayout.mobileCalloutLayouts = @()
    $missingLayout.layoutMeasurementSource = ''
    $missingLayout | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $missingLayoutWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $missingLayoutWasBlocked = $true }
    if (-not $missingLayoutWasBlocked) { throw 'Missing rendered Naver layout measurements were not blocked.' }

    $attachedHeading = $after | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $attachedHeading.headingLayouts[0].standaloneParagraph = $false
    $attachedHeading.headingLayouts[0].marginTopPx = 0
    $attachedHeading | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $attachedHeadingWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $attachedHeadingWasBlocked = $true }
    if (-not $attachedHeadingWasBlocked) { throw 'A heading attached to the preceding paragraph was not blocked.' }

    $wrongHeadingGap = $after | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $wrongHeadingGap.headingLayouts[0].marginTopPx = 18
    $wrongHeadingGap | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $wrongHeadingGapWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $wrongHeadingGapWasBlocked = $true }
    if (-not $wrongHeadingGapWasBlocked) { throw 'An incorrect section-heading top gap was not blocked.' }

    $wrongCallout = $after | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $wrongCallout.calloutLayouts[1].titleMarginBottomPx = 21
    $wrongCallout | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $wrongCalloutWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $wrongCalloutWasBlocked = $true }
    if (-not $wrongCalloutWasBlocked) { throw 'An incorrect callout title gap was not blocked.' }

    $legacyTwentySevenPixelGap = $after | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $legacyTwentySevenPixelGap.paragraphGapLayouts[0].gapPx = 27
    $legacyTwentySevenPixelGap.paragraphGapLayouts[0].spacerHeightPx = 27
    $legacyTwentySevenPixelGap.paragraphGapLayouts[0].spacerLineHeight = 1.8
    $legacyTwentySevenPixelGap | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $legacyTwentySevenPixelGapWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $legacyTwentySevenPixelGapWasBlocked = $true }
    if (-not $legacyTwentySevenPixelGapWasBlocked) { throw 'A legacy 27px PC paragraph gap was not blocked.' }

    $missingMobileGap = $after | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $missingMobileGap.mobileParagraphGapLayouts = @()
    $missingMobileGap | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $missingMobileGapWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $missingMobileGapWasBlocked = $true }
    if (-not $missingMobileGapWasBlocked) { throw 'Missing mobile paragraph-gap measurements were not blocked.' }

    $stuckReferenceGap = $after | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $stuckReferenceGap.questionToReferenceGapLayout.gapPx = 0
    $stuckReferenceGap.questionToReferenceGapLayout.spacerHeightPx = 0
    $stuckReferenceGap.questionToReferenceGapLayout.spacerParagraphCount = 0
    $stuckReferenceGap | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $stuckReferenceGapWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $stuckReferenceGapWasBlocked = $true }
    if (-not $stuckReferenceGapWasBlocked) { throw 'A stuck 0px reader-question to reference gap was not blocked.' }

    $ordinaryGapUsedForReference = $after | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $ordinaryGapUsedForReference.questionToReferenceGapLayout.gapPx = 18
    $ordinaryGapUsedForReference.questionToReferenceGapLayout.spacerHeightPx = 18
    $ordinaryGapUsedForReference.questionToReferenceGapLayout.spacerFontSizePx = 11
    $ordinaryGapUsedForReference.questionToReferenceGapLayout.spacerLineHeight = 1.6
    $ordinaryGapUsedForReference | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $ordinaryGapUsedForReferenceWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $ordinaryGapUsedForReferenceWasBlocked = $true }
    if (-not $ordinaryGapUsedForReferenceWasBlocked) { throw 'An ordinary 18px paragraph gap used for the reference boundary was not blocked.' }

    $missingMobileReferenceGap = $after | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $missingMobileReferenceGap.mobileQuestionToReferenceGapLayout = $null
    $missingMobileReferenceGap | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $missingMobileReferenceGapWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $missingMobileReferenceGapWasBlocked = $true }
    if (-not $missingMobileReferenceGapWasBlocked) { throw 'Missing mobile reader-question to reference gap measurement was not blocked.' }

    $headingAdjacentGap = $after | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $headingAdjacentGap.paragraphGapLayouts[0].adjacentToSectionHeading = $true
    $headingAdjacentGap | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $headingAdjacentGapWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $headingAdjacentGapWasBlocked = $true }
    if (-not $headingAdjacentGapWasBlocked) { throw 'A paragraph spacer adjacent to a heading was not blocked.' }

    $wrongCalloutOuterGap = $after | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $wrongCalloutOuterGap.calloutLayouts[1].outerMarginTopPx = 48
    $wrongCalloutOuterGap | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $wrongCalloutOuterGapWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $wrongCalloutOuterGapWasBlocked = $true }
    if (-not $wrongCalloutOuterGapWasBlocked) { throw 'An excessive callout top gap was not blocked.' }

    $blankBeforeCallout = $after | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $blankBeforeCallout.calloutLayouts[1].blankParagraphCountBefore = 1
    $blankBeforeCallout | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $blankBeforeCalloutWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $blankBeforeCalloutWasBlocked = $true }
    if (-not $blankBeforeCalloutWasBlocked) { throw 'A blank paragraph before a PC callout was not blocked.' }

    $mobileBlankAfterCallout = $after | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $mobileBlankAfterCallout.mobileCalloutLayouts[1].blankParagraphCountAfter = 1
    $mobileBlankAfterCallout | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $mobileBlankAfterCalloutWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $mobileBlankAfterCalloutWasBlocked = $true }
    if (-not $mobileBlankAfterCalloutWasBlocked) { throw 'A blank paragraph after a mobile callout was not blocked.' }

    $wrongMobileHeadingGap = $after | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $wrongMobileHeadingGap.mobileHeadingLayouts[0].marginTopPx = 18
    $wrongMobileHeadingGap | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $wrongMobileHeadingGapWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $wrongMobileHeadingGapWasBlocked = $true }
    if (-not $wrongMobileHeadingGapWasBlocked) { throw 'An incorrect mobile section-heading top gap was not blocked.' }

    $mobileNotVerified = $after | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $mobileNotVerified.mobileLayoutVerified = $false
    $mobileNotVerified | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath -Encoding UTF8
    $mobileNotVerifiedWasBlocked = $false
    try { & $validator -Mode AfterSave -PlanPath $planPath -ObservationPath $badPath | Out-Null }
    catch { $mobileNotVerifiedWasBlocked = $true }
    if (-not $mobileNotVerifiedWasBlocked) { throw 'An unverified mobile layout was not blocked after save.' }

    $recovered = $after | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $recovered.saveAttemptCount = 2
    $recovered.publishDelayObserved = $true
    $recovered.recoveryAction = '멈춘 탭을 유지하고 공식 수정 링크로 새 편집창을 열어 비공개 설정을 재확인한 뒤 한 번 재시도'
    $recovered | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $afterPath -Encoding UTF8
    $recoveredResult = & $validator -Mode AfterSave -PlanPath $planPath `
        -ObservationPath $afterPath | ConvertFrom-Json
    if (-not $recoveredResult.IsValid) { throw 'A valid one-time recovery observation was rejected.' }

    Write-Output 'Editor result validation tests passed.'
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

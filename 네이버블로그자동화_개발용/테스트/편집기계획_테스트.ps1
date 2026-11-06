#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$planScript = Join-Path $projectRoot '프로그램\편집기계획.ps1'
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('편집기 계획 테스트 ' + [guid]::NewGuid().ToString('N'))
$draftPath = Join-Path $testRoot 'draft.json'
$planPath = Join-Path $testRoot 'editor-plan.json'

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $paragraph = '검증된 사실과 기술적 의미를 일반 독자가 이해하기 쉽게 설명하는 모바일 문단입니다. 실제 적용 조건과 확인되지 않은 한계도 구분하여 전달합니다.'
    $sectionHeadings = @('핵심만 먼저 보면','무엇이 달라졌나','앞으로 확인할 점')
    $fiveWOneHValues = @('시험 기업','검증 기술','2026년 11월 4일','시험 지역','단계별 검증','상용성 확인')
    $body = @($sectionHeadings + $fiveWOneHValues + @(1..32 | ForEach-Object { "$paragraph 문단 번호 $($_)." })) -join "`r`n`r`n"
    [pscustomobject]@{
        contentId='NTE-20261105-001'
        draftType='TechnicalArticle'
        requestedCategory=''
        editorialContext=[pscustomobject]@{
            convergenceDomains=@('ET·환경·에너지'); coreAnalysisAxes=@('AI','데이터센터','전력')
            connectionContext='AI와 데이터센터 전력 수요의 연결입니다.'
            domesticRelevance='국내 전력망과 데이터센터 투자에 주는 의미입니다.'
            aiConnectionExplained=$true; crossFieldImpactExplained=$true
            domesticRelevanceExplained=$true; factAnalysisSeparated=$true; forcedConnectionsExcluded=$true
        }
        title='데이터센터 전력 이슈를 쉽게 이해하는 방법'
        body=$body
        sectionHeadings=$sectionHeadings
        tags=@('AI','데이터센터','전력산업','스마트그리드','기술동향')
        sources=@([pscustomobject]@{
            name='TechCrunch'; title='Verified article'; publishedDate='2026-11-04'
            url='https://techcrunch.com/example'
        })
        articleFiveWOneH=[pscustomobject]@{
            provenance='selectedArticle'; sourceUrl='https://techcrunch.com/example'
            who=[pscustomobject]@{value='시험 기업';evidence='기사의 주체 근거'}
            what=[pscustomobject]@{value='검증 기술';evidence='기사의 대상 근거'}
            when=[pscustomobject]@{value='2026년 11월 4일';evidence='기사의 날짜 근거'}
            where=[pscustomobject]@{value='시험 지역';evidence='기사의 장소 근거'}
            how=[pscustomobject]@{value='단계별 검증';evidence='기사의 방식 근거'}
            why=[pscustomobject]@{value='상용성 확인';evidence='기사의 이유 근거'}
        }
        bodyLinks=@([pscustomobject]@{
            text='적용 조건'; url='https://example.com/grid'; purpose='관련 공식 설명 확인'
        })
        boldHighlights=@('기술적 의미')
        imagePrompts=@('one','two','three')
        allowImagePromptException=$false
        benchmarkReview=[pscustomobject]@{
            analyzedDate=(Get-Date).ToString('yyyy-MM-dd'); candidateCount=4; activeReferenceCount=3
            primaryBlogId='backeclub'; selectionReason='General-reader technology fit and qualified public reach.'
            adoptedPatterns=@('three-line summary','plain-language opening','limitations section')
            rejectedPatterns=@('excessive length'); noCopy=$true; generalAudienceFirst=$true
            publicMetricsOnly=$true; primaryHasHighestQualifiedReach=$true
        }
        officialCompliance=[pscustomobject]@{
            searchIntentMatched=$true
            originalStructureAndAnalysis=$true
            noKeywordStuffing=$true
            noHiddenTextOrLinks=$true
            noMechanicalMassProduction=$true
        }
        readerDesign=[pscustomobject]@{
            leadSentenceCount=3
            keySummaryCount=3
            readerQuestionCount=1
        }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $draftPath -Encoding UTF8

    $created = & $planScript -DraftPath $draftPath -OutputPath $planPath | ConvertFrom-Json
    if ($created.visibility -ne '비공개' -or $created.stopPoint -ne '외부 저장 버튼 클릭 직전') {
        throw 'The editor plan does not enforce the private pre-save stop point.'
    }
    $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($plan.allowPublicPublish -or -not $plan.requiresApprovalBeforeExternalSave -or
        $plan.verificationSteps.Count -lt 7 -or $plan.tags.Count -ne 5 -or
        @($plan.verificationSteps | Where-Object { $_ -like '*실제 화면 표시 순서*첫 출현*약어(한글 설명)*편집기 입력*중단*' }).Count -ne 1 -or
        $plan.imagePrompts.Count -ne 3 -or $plan.imagePlacements.Count -ne 3 -or
        $plan.imageSpecification.width -ne 1200 -or $plan.imageSpecification.height -ne 800 -or
        $plan.imageSpecification.editorDisplayWidth -ne 340 -or
        $plan.imageSpecification.editorAlignment -ne 'center' -or
        $plan.sectionHeadings.Count -ne 3 -or -not $plan.sectionFormatting.bold -or
        $plan.sectionFormatting.titleFontSize -ne 26 -or $plan.sectionFormatting.titleMobileFontSize -ne 24 -or
        $plan.sectionFormatting.headingFontSize -ne 19 -or $plan.sectionFormatting.bodyFontSize -ne 16 -or
        $plan.sectionFormatting.bodyLineHeight -ne 1.75 -or
        $plan.sectionFormatting.bodyLineHeightPx -ne 28 -or
        $plan.sectionFormatting.paragraphMarginBottomPx -ne 18 -or
        $plan.paragraphGapFormatting.mode -ne 'SingleSizedSpacerParagraph' -or
        $plan.paragraphGapFormatting.gapPx -ne 18 -or
        $plan.paragraphGapFormatting.gapTolerancePx -ne 0.5 -or
        $plan.paragraphGapFormatting.spacerParagraphCount -ne 1 -or
        $plan.paragraphGapFormatting.spacerFontSizePx -ne 11 -or
        $plan.paragraphGapFormatting.spacerLineHeight -ne 1.6 -or
        -not $plan.paragraphGapFormatting.applyOnlyBetweenOrdinaryBodyParagraphs -or
        -not $plan.paragraphGapFormatting.forbidAdjacentToSectionHeadings -or
        -not $plan.paragraphGapFormatting.forbidAdjacentToCallouts -or
        -not $plan.paragraphGapFormatting.requirePcAndMobileMeasurement -or
        $plan.sectionFormatting.headingMarginTopPx -ne 35 -or
        $plan.sectionFormatting.headingMarginBottomPx -ne 15 -or
        $plan.sectionFormatting.blankLineBeforeAndAfter -or
        -not $plan.sectionFormatting.forbidSpacingBlankParagraphs -or
        -not $plan.sectionFormatting.dividerEnabled -or
        $plan.sectionFormatting.dividerThicknessPx -ne 2 -or
        $plan.calloutFormatting.renderMode -ne 'ResponsiveSingleCellBorderTable' -or
        $plan.calloutFormatting.defaultCount -ne 3 -or
        $plan.calloutFormatting.maximumCount -ne 4 -or
        $plan.calloutFormatting.fourthBlockMinimumBodyChars -ne 2600 -or
        $plan.calloutFormatting.fourthBlockUse -ne '국내영향·향후확인' -or
        -not $plan.calloutFormatting.leftAccentEnabled -or
        $plan.calloutFormatting.leftAccentWidthPx -ne 4 -or
        $plan.calloutFormatting.innerPaddingVerticalPx -ne 16 -or
        $plan.calloutFormatting.innerPaddingHorizontalPx -ne 18 -or
        $plan.calloutFormatting.outerMarginTopPx -ne 30 -or
        $plan.calloutFormatting.outerMarginBottomPx -ne 20 -or
        $plan.calloutFormatting.borderRadiusPx -ne 4 -or
        $plan.calloutFormatting.titleFontSizePx -ne 15 -or
        $plan.calloutFormatting.titleFontWeight -ne 700 -or
        $plan.calloutFormatting.titleMarginBottomPx -ne 8 -or
        $plan.calloutFormatting.bodyLineHeight -ne 1.75 -or
        $plan.calloutFormatting.paragraphMarginBottomPx -ne 18 -or
        $plan.calloutFormatting.calloutParagraphSpacerEnabled -or
        $plan.calloutFormatting.calloutParagraphSpacerLineHeightPercent -ne 100 -or
        -not $plan.calloutFormatting.forbidAdjacentBlankParagraphs -or
        -not $plan.calloutFormatting.fiveWOneHLabelBold -or
        $plan.calloutFormatting.labelSeparator -ne ' : ' -or
        ($plan.calloutFormatting.fixedPlacementOrder -join '|') -ne '완결된 도입부|육하원칙 한눈에 보기|연결 문장|핵심만 먼저 보면|첫 번째 소제목' -or
        -not $plan.calloutFormatting.requireSourceOutletInFiveWOneH -or
        -not $plan.calloutFormatting.requireConcreteEventDate -or
        -not $plan.calloutFormatting.requireOfficialVerificationLinks -or
        ($plan.calloutFormatting.judgmentEvidenceLabels -join '|') -ne '확인된 사실|주의할 표현|운영자의 판단' -or
        -not $plan.calloutFormatting.requireFiveWOneHSummary -or
        $plan.calloutFormatting.styles.Count -ne 3 -or
        $plan.calloutFormatting.styles[0].titleColor -ne '#555555' -or
        $plan.calloutFormatting.styles[1].titleColor -ne '#36851e' -or
        $plan.calloutFormatting.styles[2].titleColor -ne '#b85c00' -or
        $plan.calloutFormatting.styles[0].titleMarginBottomPx -ne 8 -or
        $plan.calloutFormatting.styles[1].titleMarginBottomPx -ne 10 -or
        $plan.calloutFormatting.styles[2].titleMarginBottomPx -ne 8 -or
        $plan.calloutFormatting.styles[0].outerMarginTopPx -ne 30 -or
        $plan.calloutFormatting.styles[1].outerMarginTopPx -ne 30 -or
        $plan.calloutFormatting.styles[2].outerMarginTopPx -ne 30 -or
        $plan.referenceFormatting.label -ne '참고자료 : ' -or
        $plan.referenceFormatting.placement -ne '독자 질문 다음 줄' -or
        $plan.referenceFormatting.displayMode -ne 'LinkedSourceNamesOnly' -or
        $plan.referenceFormatting.questionToReferenceGap.order -ne 'ReaderQuestionToReferenceLine' -or
        $plan.referenceFormatting.questionToReferenceGap.gapPx -ne 32 -or
        $plan.referenceFormatting.questionToReferenceGap.gapTolerancePx -ne 0.5 -or
        $plan.referenceFormatting.questionToReferenceGap.spacerParagraphCount -ne 1 -or
        $plan.referenceFormatting.questionToReferenceGap.spacerFontSizePx -ne 16 -or
        $plan.referenceFormatting.questionToReferenceGap.spacerLineHeight -ne 2.0 -or
        -not $plan.referenceFormatting.questionToReferenceGap.requirePcAndMobileMeasurement -or
        -not $plan.referenceFormatting.hideRawUrls -or
        @($plan.referenceFormatting.links).Count -ne 1 -or
        @($plan.referenceFormatting.links)[0].text -ne 'TechCrunch' -or
        @($plan.bodyLinks).Count -ne 1 -or
        @($plan.boldHighlights).Count -ne 1 -or
        $plan.inlineFormatting.maximumBodyLinks -ne 3 -or
        $plan.inlineFormatting.bodyLinkMaximumWords -ne 3 -or
        $plan.inlineFormatting.maximumBoldHighlights -ne 3 -or
        $plan.inlineFormatting.unfamiliarAcronymFirstUseFormat -ne '약어(한글 설명)' -or
        $plan.inlineFormatting.unfamiliarAcronymScanOrder -ne '제목·태그·참고자료 제외, 도입부→바탕글→일반 본문→운영자 판단의 실제 화면 표시 순서' -or
        -not $plan.inlineFormatting.stopBeforeEditorOnAcronymFailure -or
        -not $plan.officialCompliance.searchIntentMatched -or
        $plan.readerDesign.keySummaryCount -ne 3 -or
        -not $plan.editorialContext.factAnalysisSeparated -or
        -not $plan.benchmarkReview.noCopy) {
        throw 'The editor plan is missing required safety or content fields.'
    }

    Write-Output 'Editor plan tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $tempPrefix = $systemTemp + [System.IO.Path]::DirectorySeparatorChar
        if (-not $resolvedTestRoot.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean a test path outside the system temp directory: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

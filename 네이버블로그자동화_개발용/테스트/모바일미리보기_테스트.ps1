#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$previewScript = Join-Path $projectRoot '프로그램\모바일미리보기.ps1'
$settingsPath = Join-Path $projectRoot '설정.json'
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('네이버 모바일 미리보기 ' + [guid]::NewGuid().ToString('N'))
$draftPath = Join-Path $testRoot '검증 초안.json'
$outputPath = Join-Path $testRoot '모바일 미리보기.html'

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $paragraph = '검증된 사실과 기술적 의미를 모바일 독자가 쉽게 이해하도록 설명합니다. 적용 조건과 확인되지 않은 한계도 분명히 나눕니다.'
    $sectionHeadings = @('핵심만 먼저 보면','무엇이 달라졌나','앞으로 확인할 점')
    $fiveWOneHValues = @('시험 기업','검증 기술','2026년 11월 4일','시험 지역','단계별 검증','상용성 확인')
    $body = @($sectionHeadings + $fiveWOneHValues + @(1..26 | ForEach-Object { "$paragraph 문단 번호 $($_)." })) -join "`r`n`r`n"
    [pscustomobject]@{
        contentId = 'NTE-20261105-MOBILE'
        draftType = 'TechnicalArticle'
        requestedCategory = ''
        editorialContext = [pscustomobject]@{
            convergenceDomains=@('ET·환경·에너지'); coreAnalysisAxes=@('AI','데이터센터','전력')
            connectionContext='AI와 데이터센터 전력 수요의 연결입니다.'
            domesticRelevance='국내 전력망과 데이터센터 투자에 주는 의미입니다.'
            aiConnectionExplained=$true; crossFieldImpactExplained=$true
            domesticRelevanceExplained=$true; factAnalysisSeparated=$true; forcedConnectionsExcluded=$true
        }
        title = 'AI 데이터센터 전력 이슈를 모바일에서 읽는 법 <안전>'
        body = $body
        editorBlocks = @(
            [pscustomobject]@{ id='p1'; type='BodyParagraph'; text='검증된 도입부입니다.' },
            [pscustomobject]@{ id='c1'; type='Callout'; calloutKind='FiveWOneH'; text="육하원칙 한눈에 보기`n누가 : 시험 기업`n무엇을 : 검증 기술" },
            [pscustomobject]@{ id='p2'; type='BodyParagraph'; text='핵심을 이어 설명합니다.' },
            [pscustomobject]@{ id='c2'; type='Callout'; calloutKind='KeySummary'; text="핵심만 먼저 보면`n• 첫 번째 핵심`n• 두 번째 핵심" },
            [pscustomobject]@{ id='h1'; type='SectionHeading'; text='핵심만 먼저 보면' },
            [pscustomobject]@{ id='i1'; type='Image'; text=''; fileName='01-대표.jpg'; role='대표'; altText='AI 데이터센터와 전력망' },
            [pscustomobject]@{ id='c3'; type='Callout'; calloutKind='OperatorJudgment'; text="운영자의 판단 : 검증 기준`n• 확인된 사실 : 공식자료 확인" },
            [pscustomobject]@{ id='q1'; type='ReaderQuestion'; text='어떤 기준이 필요할까요?' },
            [pscustomobject]@{ id='r1'; type='ReferenceLine'; text='참고자료 : TechCrunch'; links=@([pscustomobject]@{text='TechCrunch';url='https://techcrunch.com/example?x=1&y=2'}) }
        )
        sectionHeadings = $sectionHeadings
        tags = @('AI','데이터센터','전력산업','스마트그리드','기술동향')
        sources = @([pscustomobject]@{
            name = 'TechCrunch'; title = 'Verified <article>'; publishedDate = '2026-11-04'
            url = 'https://techcrunch.com/example?x=1&y=2'
        })
        articleFiveWOneH = [pscustomobject]@{
            provenance='selectedArticle'; sourceUrl='https://techcrunch.com/example?x=1&y=2'
            who=[pscustomobject]@{value='시험 기업';evidence='기사의 주체 근거'}
            what=[pscustomobject]@{value='검증 기술';evidence='기사의 대상 근거'}
            when=[pscustomobject]@{value='2026년 11월 4일';evidence='기사의 날짜 근거'}
            where=[pscustomobject]@{value='시험 지역';evidence='기사의 장소 근거'}
            how=[pscustomobject]@{value='단계별 검증';evidence='기사의 방식 근거'}
            why=[pscustomobject]@{value='상용성 확인';evidence='기사의 이유 근거'}
        }
        imagePrompts = @('one','two','three')
        allowImagePromptException = $false
        benchmarkReview = [pscustomobject]@{
            analyzedDate=(Get-Date).ToString('yyyy-MM-dd'); candidateCount=4; activeReferenceCount=3
            primaryBlogId='backeclub'; selectionReason='General-reader technology fit and qualified public reach.'
            adoptedPatterns=@('three-line summary','plain-language opening','limitations section')
            rejectedPatterns=@('excessive length'); noCopy=$true; generalAudienceFirst=$true
            publicMetricsOnly=$true; primaryHasHighestQualifiedReach=$true
        }
        officialCompliance = [pscustomobject]@{
            searchIntentMatched = $true; originalStructureAndAnalysis = $true
            noKeywordStuffing = $true; noHiddenTextOrLinks = $true; noMechanicalMassProduction = $true
        }
        readerDesign = [pscustomobject]@{ leadSentenceCount = 3; keySummaryCount = 3; readerQuestionCount = 1 }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $draftPath -Encoding UTF8

    $created = & $previewScript -DraftPath $draftPath -OutputPath $outputPath -ConfigPath $settingsPath |
        ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $created.output -PathType Leaf) -or
        $created.viewportWidth -ne 390 -or $created.headingCount -ne 3 -or $created.externalTransmission) {
        throw 'The local mobile preview was not created safely.'
    }
    $html = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
    foreach ($required in @('width:390px', 'name="viewport"', '&lt;안전&gt;', 'x=1&amp;y=2', '<h2 class="section-heading">핵심만 먼저 보면</h2>', 'font-size:24px', 'font-size:19px', 'font-size:15px', 'width:340px', 'font-weight:700', 'margin:32px 0 21px', 'margin:0 0 18px', 'line-height:27px', '.callout-five', '.callout-summary', 'background:#e3fdc8', 'background:#f7f7f7', 'background:#ffe3c8', 'border-left:4px solid', 'border-radius:4px', 'padding:16px 18px', 'border-left-color:#66a33b', 'color:#2f7d19', 'color:#4d4d4d', 'color:#b85c00', '.callout-title { display:block; margin:0 0 8px; color:inherit; font-size:15px; font-weight:700; }', '.callout-summary { margin-top:30px; margin-bottom:20px; }', '.callout-five .callout-title { margin-bottom:10px;', '.callout-judgment { margin-top:30px; margin-bottom:20px; }', '.callout p { margin:0 0 18px; line-height:1.75; }', '.callout p:last-child { margin-bottom:0; }', 'overflow-wrap:anywhere', '.five-w-one-h-label', 'class="content-image-placeholder"', '01-대표.jpg', '어떤 기준이 필요할까요?', '참고자료 : <a href="https://techcrunch.com/example?x=1&amp;y=2"', 'margin:22px auto', '네이버 실제 모바일 화면과 동일함을 보장하지 않습니다.')) {
        if ($html.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
            throw "Mobile preview is missing encoded or responsive content: $required"
        }
    }
    if ($html -match '<script\b') { throw 'The local mobile preview must not contain scripts.' }

    $overwriteBlocked = $false
    try { & $previewScript -DraftPath $draftPath -OutputPath $outputPath -ConfigPath $settingsPath | Out-Null }
    catch { $overwriteBlocked = $true }
    if (-not $overwriteBlocked) { throw 'An existing mobile preview was overwritten.' }
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

Write-Output 'Mobile preview tests passed.'


#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$actualValidatorPath = Join-Path $projectRoot '프로그램\초안검증.ps1'

if (-not (Test-Path -LiteralPath $actualValidatorPath -PathType Leaf)) {
    throw 'The draft validator script was not found.'
}

. $actualValidatorPath -Path 'unused'

$rules = [pscustomobject]@{
    AllowedDraftTypes = @('TechnicalArticle','Introduction','OperatorProfile','Policy')
    MaximumTitleLength = 60
    MinimumBodyLength = 20
    MaximumBodyLength = 500
    MaximumParagraphLength = 100
    MinimumSectionHeadings = 3
    MaximumSectionHeadings = 10
    ForbidHtmlTags = $true
    RequireUniqueParagraphs = $true
    TagPattern = '^[\p{L}\p{Nd}_]+$'
    LeadSentenceCountMinimum = 3
    LeadSentenceCountMaximum = 5
    KeySummaryCount = 3
    ReaderQuestionCount = 1
    MinimumTags = 5
    MaximumTags = 10
    MinimumSources = 1
    MaximumSources = 3
    MaximumBodyLinks = 3
    BodyLinkMaximumWords = 3
    MaximumBoldHighlights = 3
    TechnicalArticleImagePrompts = 3
    RequireBenchmarkReview = $true
    MinimumBenchmarkCandidates = 3
    MinimumActiveBenchmarkReferences = 2
    MaximumBenchmarkAgeDays = 30
    MinimumAdoptedBenchmarkPatterns = 3
    MinimumRejectedBenchmarkPatterns = 1
    RequireEditorialFocusReview = $true
    RequireFiveWOneHSummary = $true
}

$validDraft = [pscustomobject]@{
    draftType = 'TechnicalArticle'
    editorialContext = [pscustomobject]@{
        convergenceDomains=@('ET·환경·에너지')
        coreAnalysisAxes=@('AI','데이터센터','전력')
        connectionContext='AI와 데이터센터 전력 수요의 연결을 설명합니다.'
        domesticRelevance='국내 전력망과 데이터센터 투자에 주는 의미입니다.'
        aiConnectionExplained=$true
        crossFieldImpactExplained=$true
        domesticRelevanceExplained=$true
        factAnalysisSeparated=$true
        forcedConnectionsExcluded=$true
    }
    title = 'A valid title'
    body = "핵심 요약`r`n`r`n기술 변화`r`n`r`n앞으로 확인할 점`r`n`r`n시험 기업`r`n`r`n검증 기술`r`n`r`n2026년 11월 1일`r`n`r`n시험 지역`r`n`r`n단계별 검증`r`n`r`n상용성 확인`r`n`r`nThis body contains enough verified information for the test."
    sectionHeadings = @('핵심 요약','기술 변화','앞으로 확인할 점')
    tags = @('ai','energy','grid','battery','technology')
    sources = @([pscustomobject]@{
        name='TechCrunch'
        title='Verified source title'
        publishedDate='2026-11-01'
        url='https://techcrunch.com/example'
    })
    articleFiveWOneH = [pscustomobject]@{
        provenance='selectedArticle'; sourceUrl='https://techcrunch.com/example'
        who=[pscustomobject]@{value='시험 기업';evidence='기사의 주체 근거'}
        what=[pscustomobject]@{value='검증 기술';evidence='기사의 대상 근거'}
        when=[pscustomobject]@{value='2026년 11월 1일';evidence='기사의 날짜 근거'}
        where=[pscustomobject]@{value='시험 지역';evidence='기사의 장소 근거'}
        how=[pscustomobject]@{value='단계별 검증';evidence='기사의 방식 근거'}
        why=[pscustomobject]@{value='상용성 확인';evidence='기사의 이유 근거'}
    }
    bodyLinks = @([pscustomobject]@{
        text='기술 변화'
        url='https://example.com/official'
        purpose='공식 설명 확인'
    })
    boldHighlights = @('verified information')
    imagePrompts = @('one','two','three')
    allowImagePromptException = $false
    benchmarkReview = [pscustomobject]@{
        analyzedDate=(Get-Date).ToString('yyyy-MM-dd')
        candidateCount=4
        activeReferenceCount=3
        primaryBlogId='backeclub'
        selectionReason='Closest active general-reader technology benchmark with the highest qualified public reach.'
        adoptedPatterns=@('three-line summary','plain-language opening','limitations section')
        rejectedPatterns=@('excessive length')
        noCopy=$true
        generalAudienceFirst=$true
        publicMetricsOnly=$true
        primaryHasHighestQualifiedReach=$true
    }
    officialCompliance = [pscustomobject]@{
        searchIntentMatched=$true
        originalStructureAndAnalysis=$true
        noKeywordStuffing=$true
        noHiddenTextOrLinks=$true
        noMechanicalMassProduction=$true
    }
    readerDesign = [pscustomobject]@{
        leadSentenceCount=3
        keySummaryCount=3
        readerQuestionCount=1
    }
}

$validResult = Test-NaverDraft -Draft $validDraft -Rules $rules
if (-not $validResult.IsValid) {
    throw ('A valid draft was rejected: ' + (@($validResult.Issues) -join '; '))
}

$bodyDerivedFiveWOneHDraft = $validDraft | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$bodyDerivedFiveWOneHDraft.articleFiveWOneH.who.value = '완성 본문에서 다시 만든 주체'
$bodyDerivedResult = Test-NaverDraft -Draft $bodyDerivedFiveWOneHDraft -Rules $rules
if ($bodyDerivedResult.IsValid -or
    (@($bodyDerivedResult.Issues | Where-Object { $_ -like 'Five-W-one-H who value*' })).Count -ne 1) {
    throw 'A five-W-one-H value not traceable to the selected-article record was not rejected.'
}

$calendarYearDraft = $validDraft | Select-Object *
$calendarYearDraft.body = $validDraft.body + "`r`n`r`n" + 'The 20' + '30' + [char]0xB144 + ' electricity outlook is a calendar year, not a career claim.'
$calendarYearDraft.bodyLinks = @()
$calendarYearDraft.boldHighlights = @()
$calendarYearResult = Test-NaverDraft -Draft $calendarYearDraft -Rules $rules
if (-not $calendarYearResult.IsValid) {
    throw ('A calendar year ending in a blocked career duration was rejected: ' + (@($calendarYearResult.Issues) -join '; '))
}

$careerYearDraft = $validDraft | Select-Object *
$careerYearDraft.body = $validDraft.body + "`r`n`r`n" + 'The operator claims 경력 ' + '30' + [char]0xB144 + ' in this draft and must be rejected.'
$careerYearResult = Test-NaverDraft -Draft $careerYearDraft -Rules $rules
if ($careerYearResult.IsValid -or
    (@($careerYearResult.Issues | Where-Object { $_ -like 'Specific career-year claims*' })).Count -ne 1) {
    throw 'A specific career-year claim was not rejected.'
}

$invalidDraft = [pscustomobject]@{
    draftType = 'Unknown'
    title = ''
    body = 'short'
    tags = @('ai','ai','#bad tag')
    sources = @([pscustomobject]@{ name='Bad'; title=''; publishedDate='bad'; url='http://example.com' })
    imagePrompts = @('one')
    allowImagePromptException = $false
    benchmarkReview = $null
    officialCompliance = $null
    readerDesign = $null
}

$htmlDraft = $validDraft | Select-Object *
$htmlDraft.body = '<div>This paragraph contains copied HTML and must be rejected.</div>'
$htmlResult = Test-NaverDraft -Draft $htmlDraft -Rules $rules
if ($htmlResult.IsValid -or
    (@($htmlResult.Issues | Where-Object { $_ -like 'HTML tags*' })).Count -ne 1) {
    throw 'Copied HTML was not rejected.'
}

$repeatedDraft = $validDraft | Select-Object *
$sameParagraph = 'This is a sufficiently long repeated paragraph for duplicate-content validation.'
$repeatedDraft.body = $sameParagraph + "`r`n`r`n" + $sameParagraph
$repeatedResult = Test-NaverDraft -Draft $repeatedDraft -Rules $rules
if ($repeatedResult.IsValid -or
    (@($repeatedResult.Issues | Where-Object { $_ -like 'Repeated body paragraphs*' })).Count -ne 1) {
    throw 'Repeated body paragraphs were not rejected.'
}

$invalidResult = Test-NaverDraft -Draft $invalidDraft -Rules $rules
if ($invalidResult.IsValid -or $invalidResult.Issues.Count -lt 5) {
    throw 'An invalid draft did not produce the expected issues.'
}

$longParagraphDraft = $validDraft | Select-Object *
$longParagraphDraft.body = 'a' * 101
$longParagraphResult = Test-NaverDraft -Draft $longParagraphDraft -Rules $rules
if ($longParagraphResult.IsValid -or
    (@($longParagraphResult.Issues | Where-Object { $_ -like 'A body paragraph*' })).Count -ne 1) {
    throw 'A paragraph that is too long for mobile was not rejected.'
}

$tooManyHighlightsDraft = $validDraft | Select-Object *
$tooManyHighlightsDraft.boldHighlights = @('핵심 요약','기술 변화','앞으로 확인할 점','verified information')
$tooManyHighlightsResult = Test-NaverDraft -Draft $tooManyHighlightsDraft -Rules $rules
if ($tooManyHighlightsResult.IsValid -or
    (@($tooManyHighlightsResult.Issues | Where-Object { $_ -like 'Bold highlight count*' })).Count -ne 1) {
    throw 'Too many body bold highlights were not rejected.'
}

$longLinkTextDraft = $validDraft | Select-Object *
$longLinkTextDraft.bodyLinks = @([pscustomobject]@{
    text='This body contains enough'
    url='https://example.com/too-long'
    purpose='공식 설명 확인'
})
$longLinkTextResult = Test-NaverDraft -Draft $longLinkTextDraft -Rules $rules
if ($longLinkTextResult.IsValid -or
    (@($longLinkTextResult.Issues | Where-Object { $_ -like 'Body link text*' })).Count -ne 1) {
    throw 'An overlong body link label was not rejected.'
}

Write-Output 'Draft validator tests passed.'

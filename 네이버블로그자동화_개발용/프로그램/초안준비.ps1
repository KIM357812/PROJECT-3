#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FactCheckPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ReaderAnalysisPath
)

$ErrorActionPreference = 'Stop'
$validatorPath = Join-Path $PSScriptRoot '작업자료검증.ps1'
. $validatorPath -Mode FactCheck -Path 'unused'

if (-not (Test-Path -LiteralPath $FactCheckPath -PathType Leaf)) {
    throw "사실검증 파일을 찾을 수 없습니다: $FactCheckPath"
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "기존 네이버 초안 파일을 덮어쓰지 않습니다: $OutputPath"
}

$factCheck = Get-Content -LiteralPath $FactCheckPath -Raw -Encoding UTF8 | ConvertFrom-Json
$validation = Test-FactCheckRecord -Record $factCheck
if (-not $validation.IsValid) {
    throw ('사실검증 자료를 먼저 보완해야 합니다: ' + (@($validation.Issues) -join '; '))
}

$readerGuidance = [pscustomobject]@{
    evidenceStatus = 'notProvided'
    recommendedBodyLength = $null
    topCategory = $null
    topSearchTerms = @()
    mobileFirst = $true
    rankingGuarantee = $false
    applicationRule = '네이버 공식 기준과 사실 정확성을 먼저 적용하고 독자 반응은 두 번째 편집 참고값으로 사용한다.'
}
if (-not [string]::IsNullOrWhiteSpace($ReaderAnalysisPath)) {
    if (-not (Test-Path -LiteralPath $ReaderAnalysisPath -PathType Leaf)) {
        throw "독자 반응 분석 파일을 찾을 수 없습니다: $ReaderAnalysisPath"
    }
    $readerAnalysis = Get-Content -LiteralPath $ReaderAnalysisPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@('sufficient', 'insufficient') -notcontains [string]$readerAnalysis.evidenceStatus -or
        $null -eq $readerAnalysis.recommendedBodyLength -or
        [bool]$readerAnalysis.rankingGuarantee) {
        throw '독자 반응 분석 파일의 근거 상태·권장 길이·검색 노출 비보장 값을 확인하세요.'
    }
    $readerGuidance = [pscustomobject]@{
        evidenceStatus = [string]$readerAnalysis.evidenceStatus
        recommendedBodyLength = [pscustomobject]@{
            minimum = [int]$readerAnalysis.recommendedBodyLength.minimum
            maximum = [int]$readerAnalysis.recommendedBodyLength.maximum
        }
        topCategory = $readerAnalysis.topCategory
        topSearchTerms = @($readerAnalysis.topSearchTerms | ForEach-Object { [string]$_.term })
        mobileFirst = [bool]$readerAnalysis.mobileFirst
        rankingGuarantee = $false
        applicationRule = '네이버 공식 기준과 사실 정확성을 먼저 적용하고 독자 반응은 두 번째 편집 참고값으로 사용한다.'
    }
}

$draft = [pscustomobject]@{
    contentId = [string]$factCheck.contentId
    draftType = 'TechnicalArticle'
    requestedCategory = ''
    editorialContext = [pscustomobject]@{
        convergenceDomains = @($factCheck.editorialContext.convergenceDomains)
        coreAnalysisAxes = @($factCheck.editorialContext.coreAnalysisAxes)
        connectionContext = [string]$factCheck.editorialContext.connectionContext
        domesticRelevance = [string]$factCheck.editorialContext.domesticRelevance
        aiConnectionExplained = $false
        crossFieldImpactExplained = $false
        domesticRelevanceExplained = $false
        factAnalysisSeparated = $false
        forcedConnectionsExcluded = $false
    }
    title = ''
    body = ''
    sectionHeadings = @()
    tags = @()
    sources = @(
        [pscustomobject]@{
            name = [string]$factCheck.primarySource.name
            title = [string]$factCheck.primarySource.title
            publishedDate = [string]$factCheck.primarySource.publishedDate
            url = [string]$factCheck.primarySource.url
        }
    )
    articleFiveWOneH = $factCheck.articleFiveWOneH
    imagePrompts = @()
    allowImagePromptException = $false
    benchmarkReview = [pscustomobject]@{
        analyzedDate = ''
        candidateCount = 0
        activeReferenceCount = 0
        primaryBlogId = ''
        selectionReason = ''
        adoptedPatterns = @()
        rejectedPatterns = @()
        noCopy = $false
        generalAudienceFirst = $false
        publicMetricsOnly = $false
        primaryHasHighestQualifiedReach = $false
    }
    officialCompliance = [pscustomobject]@{
        searchIntentMatched = $false
        originalStructureAndAnalysis = $false
        noKeywordStuffing = $false
        noHiddenTextOrLinks = $false
        noMechanicalMassProduction = $false
    }
    readerDesign = [pscustomobject]@{
        leadSentenceCount = 0
        keySummaryCount = 0
        readerQuestionCount = 0
    }
    readerGuidance = $readerGuidance
    factCheckSummary = [pscustomobject]@{
        lifecycleStages = @($factCheck.lifecycleStages)
        sourceFindings = [string]$factCheck.sourceFindings
        authorAnalysis = [string]$factCheck.authorAnalysis
        uncertainties = @($factCheck.uncertainties)
    }
}

$directory = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($directory)) {
    throw 'OutputPath는 상위 폴더를 포함해야 합니다.'
}
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $directory
}
$draft | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    output = [System.IO.Path]::GetFullPath($OutputPath)
    contentId = $draft.contentId
    sourceCount = @($draft.sources).Count
    readerEvidenceStatus = [string]$draft.readerGuidance.evidenceStatus
    requiresWriting = $true
} | ConvertTo-Json -Depth 4

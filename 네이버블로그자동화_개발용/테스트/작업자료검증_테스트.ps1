#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $projectRoot '프로그램\작업자료검증.ps1'

. $validatorPath -Mode CandidateCollection -Path 'unused'

$settingsFilePath = Join-Path $projectRoot '설정.json'
$config = Get-Content -LiteralPath $settingsFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$sites = @()
$articleIndex = 0

foreach ($source in @($config.Collection.Sources)) {
    $articleIndex++
    $articleUrl = ([string]$source.Url).TrimEnd('/') + "/article-$articleIndex"
    $sites += [pscustomobject]@{
        name = [string]$source.Name
        baseUrl = [string]$source.Url
        missingCount = 1
        articles = @(
            [pscustomobject]@{
                title = "Verified article $articleIndex"
                url = $articleUrl
                publishedDate = '2026-11-01'
                selectionReason = 'The topic has measurable technical and market impact.'
                summary = @(
                    '첫 번째 문장은 기사에서 확인한 핵심 사실을 설명합니다.',
                    '두 번째 문장은 이 사실이 중요한 이유를 설명합니다.'
                )
                convergenceDomains = @('AI·IT·소프트웨어')
                coreAnalysisAxes = @('AI', '데이터센터')
                connectionContext = 'AI 연산 수요가 데이터센터 인프라에 미치는 영향을 연결합니다.'
                domesticRelevance = '국내 데이터센터 투자와 전력 수요에 영향을 줄 수 있습니다.'
            }
        )
    }
}

$validCollection = [pscustomobject]@{
    collectedDate = '2026-11-05'
    sites = $sites
    recommendations = @(
        [pscustomobject]@{ url = 'https://techcrunch.com/article-1'; reason = 'High technical impact.' },
        [pscustomobject]@{ url = 'https://www.theverge.com/article-2'; reason = 'High reader relevance.' },
        [pscustomobject]@{ url = 'https://electrek.co/article-3'; reason = 'High energy-sector relevance.' }
    )
}

$validCollectionResult = Test-CandidateCollection -Collection $validCollection -Rules $config.Collection `
    -EditorialFocus $config.EditorialFocus
if (-not $validCollectionResult.IsValid -or $validCollectionResult.ArticleCount -ne 8) {
    throw "A valid candidate collection was rejected: $($validCollectionResult.Issues -join '; ')"
}

$completedUrlResult = Test-CandidateCollection -Collection $validCollection -Rules $config.Collection `
    -EditorialFocus $config.EditorialFocus `
    -CompletedUrls @('https://techcrunch.com/article-1')
if ($completedUrlResult.IsValid -or
    (@($completedUrlResult.Issues | Where-Object { $_ -like 'Article URL was already completed:*' })).Count -ne 1) {
    throw 'A previously completed article URL was not rejected.'
}

$invalidCollection = $validCollection | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$invalidCollection.sites[0].articles[0].url = 'http://techcrunch.com/'
$invalidCollection.sites[0].articles[0].publishedDate = '2025-01-01'
$invalidCollection.sites[0].articles[0].summary = @('Only one sentence')
$invalidCollection.recommendations[0].url = 'https://not-collected.example/article'
$invalidCollection.sites[0].articles[0].convergenceDomains = @('알 수 없는 분야')
$invalidCollection.sites[0].articles[0].coreAnalysisAxes = @('전력')
$invalidCollection.sites[0].articles[0].connectionContext = ''
$invalidCollection.sites[0].articles[0].domesticRelevance = ''
$invalidCollectionResult = Test-CandidateCollection -Collection $invalidCollection -Rules $config.Collection `
    -EditorialFocus $config.EditorialFocus
if ($invalidCollectionResult.IsValid -or $invalidCollectionResult.Issues.Count -lt 4) {
    throw 'An invalid candidate collection did not produce the expected issues.'
}

$validFactCheck = [pscustomobject]@{
    contentId = 'NTE-20261105-001'
    editorialContext = [pscustomobject]@{
        convergenceDomains = @('ET·환경·에너지')
        coreAnalysisAxes = @('AI', '전력', '에너지')
        connectionContext = 'AI 확산과 전력 인프라의 상호 영향을 검토합니다.'
        domesticRelevance = '국내 전력망과 데이터센터 계획에 주는 의미를 검토합니다.'
    }
    primarySource = [pscustomobject]@{
        name = 'POWER Magazine'
        title = 'Example verified article'
        url = 'https://www.powermag.com/example-article'
        publishedDate = '2026-11-01'
        checkedDate = '2026-11-05'
    }
    articleFiveWOneH = [pscustomobject]@{
        provenance = 'selectedArticle'
        sourceUrl = 'https://www.powermag.com/example-article'
        who = [pscustomobject]@{ value='사업자와 규제기관'; evidence='기사에서 두 주체의 발표와 결정을 확인했다.' }
        what = [pscustomobject]@{ value='100MW 사업 계획'; evidence='기사에 100MW 계획이 명시됐다.' }
        when = [pscustomobject]@{ value='2026년 11월 1일'; evidence='기사 게시일과 발표일을 확인했다.' }
        where = [pscustomobject]@{ value='미국 전력시장'; evidence='기사의 사업 지역 설명을 확인했다.' }
        how = [pscustomobject]@{ value='단계별 실증 방식'; evidence='기사의 추진 절차를 확인했다.' }
        why = [pscustomobject]@{ value='전력 수요 대응'; evidence='기사에 제시된 추진 이유를 확인했다.' }
    }
    coreFacts = @(
        [pscustomobject]@{
            claim = 'The article reports a verified project milestone.'
            sourceUrls = @('https://www.powermag.com/example-article')
        }
    )
    lifecycleStages = @('발표', '실증')
    sourceFindings = 'The source reports a project milestone and its announced scope.'
    authorAnalysis = 'The milestone is meaningful, but commercial performance remains unverified.'
    numericClaims = @(
        [pscustomobject]@{
            value = '100'
            unit = 'MW'
            valueType = '목표'
            sourceUrl = 'https://www.powermag.com/example-article'
        }
    )
    discrepancies = @()
    uncertainties = @('Commercial operation date is not confirmed.')
    correctionSources = @()
}

$validFactCheckResult = Test-FactCheckRecord -Record $validFactCheck
if (-not $validFactCheckResult.IsValid) {
    throw "A valid fact-check record was rejected: $($validFactCheckResult.Issues -join '; ')"
}

$invalidFactCheck = $validFactCheck | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$invalidFactCheck.contentId = ''
$invalidFactCheck.editorialContext.coreAnalysisAxes = @('전력')
$invalidFactCheck.primarySource.url = 'http://example.com'
$invalidFactCheck.lifecycleStages = @('보도')
$invalidFactCheck.authorAnalysis = $invalidFactCheck.sourceFindings
$invalidFactCheck.articleFiveWOneH.sourceUrl = 'https://example.com/not-selected'
$invalidFactCheck.articleFiveWOneH.when.evidence = ''
$invalidFactCheck.PSObject.Properties.Remove('uncertainties')
$invalidFactCheckResult = Test-FactCheckRecord -Record $invalidFactCheck
if ($invalidFactCheckResult.IsValid -or $invalidFactCheckResult.Issues.Count -lt 7) {
    throw 'An invalid fact-check record did not produce the expected issues.'
}

Write-Output 'Work data validator tests passed.'

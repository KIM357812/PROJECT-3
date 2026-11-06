#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$collectionScript = Join-Path $projectRoot '프로그램\수집작업.ps1'
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('수집 작업 테스트 ' + [guid]::NewGuid().ToString('N'))
$collectionPath = Join-Path $testRoot '후보.json'
$historyPath = Join-Path $testRoot 'completed-urls.json'

try {
    $created = & $collectionScript -Action New -CollectionPath $collectionPath `
        -CollectedDate '2026-11-05' | ConvertFrom-Json
    if ($created.sites.Count -ne 8 -or ($created.sites | Measure-Object missingCount -Sum).Sum -ne 16) {
        throw 'The collection template does not contain eight empty source slots.'
    }

    [pscustomobject]@{
        version = 1
        completedUrls = @([pscustomobject]@{
            url = 'https://techcrunch.com/already-completed'
            contentId = 'OLD'
            completedAt = '2026-11-01T00:00:00Z'
        })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $historyPath -Encoding UTF8

    $browserChecklist = & $collectionScript -Action BrowserChecklist -CollectionPath $collectionPath `
        -HistoryPath $historyPath | ConvertFrom-Json
    if (-not $browserChecklist.readOnlyBrowserResearch -or
        $browserChecklist.allowLoginOrSecurityChanges -or
        $browserChecklist.tasks.Count -ne 8 -or
        ($browserChecklist.tasks | Measure-Object maximumAdditionalArticles -Sum).Sum -ne 16 -or
        $browserChecklist.tasks[0].lookbackStartDate -ne '2026-10-06' -or
        $browserChecklist.tasks[0].requiredChecks.Count -lt 5 -or
        $browserChecklist.tasks[0].completedUrlsToExclude.Count -ne 1) {
        throw 'The repeatable browser checklist is incomplete or unsafe.'
    }

    $completedWasBlocked = $false
    try {
        $null = & $collectionScript -Action AddArticle -CollectionPath $collectionPath `
            -HistoryPath $historyPath -SiteName 'TechCrunch' -Title 'Old' `
            -Url 'https://techcrunch.com/already-completed' -PublishedDate '2026-11-01' `
            -SelectionReason 'Reason' -FactSummary '사실 문장입니다.' `
            -ImportanceSummary '중요성 문장입니다.' `
            -ConvergenceDomains @('AI·IT·소프트웨어') -CoreAnalysisAxes @('AI') `
            -ConnectionContext 'AI와 산업 변화의 관계입니다.' `
            -DomesticRelevance '국내 독자에게 중요한 이유입니다.'
    }
    catch { $completedWasBlocked = $true }
    if (-not $completedWasBlocked) { throw 'A completed URL was added to a new collection.' }

    $articles = @(
        @{ Site='TechCrunch'; Url='https://techcrunch.com/2026/11/04/example-one'; Title='One' },
        @{ Site='POWER Magazine'; Url='https://www.powermag.com/example-two'; Title='Two' },
        @{ Site='SpaceNews'; Url='https://spacenews.com/example-three/'; Title='Three' }
    )
    foreach ($article in $articles) {
        $null = & $collectionScript -Action AddArticle -CollectionPath $collectionPath `
            -HistoryPath $historyPath -SiteName $article.Site -Title $article.Title `
            -Url $article.Url -PublishedDate '2026-11-03' -SelectionReason '검증 가능한 선정 이유입니다.' `
            -FactSummary '첫 문장은 확인된 사실을 설명합니다.' `
            -ImportanceSummary '두 번째 문장은 중요한 이유를 설명합니다.' `
            -ConvergenceDomains @('ET·환경·에너지') `
            -CoreAnalysisAxes @('AI','데이터센터','전력') `
            -ConnectionContext 'AI 수요와 데이터센터 전력 인프라를 연결해 설명합니다.' `
            -DomesticRelevance '국내 데이터센터와 전력망 계획에 영향을 줄 수 있습니다.'
        $null = & $collectionScript -Action AddRecommendation -CollectionPath $collectionPath `
            -Url $article.Url -RecommendationReason '추천 이유입니다.'
    }

    $final = & $collectionScript -Action Finalize -CollectionPath $collectionPath `
        -HistoryPath $historyPath | ConvertFrom-Json
    if (-not $final.IsValid -or $final.ArticleCount -ne 3) {
        throw 'A valid collection could not be finalized.'
    }

    $status = & $collectionScript -Action Status -CollectionPath $collectionPath | ConvertFrom-Json
    if ($status.articleCount -ne 3 -or $status.recommendationCount -ne 3) {
        throw 'Collection status counts are incorrect.'
    }

    $updatedChecklist = & $collectionScript -Action BrowserChecklist -CollectionPath $collectionPath `
        -HistoryPath $historyPath | ConvertFrom-Json
    $techCrunchTask = @($updatedChecklist.tasks | Where-Object { $_.siteName -eq 'TechCrunch' })[0]
    if ($techCrunchTask.existingArticleCount -ne 1 -or $techCrunchTask.maximumAdditionalArticles -ne 1) {
        throw 'The browser checklist did not resume from the existing site count.'
    }

    $backups = @(Get-ChildItem -LiteralPath $testRoot -File -Filter '*.backup.json')
    if ($backups.Count -lt 3) { throw 'Collection updates were not backed up.' }

    Write-Output 'Collection workflow tests passed.'
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

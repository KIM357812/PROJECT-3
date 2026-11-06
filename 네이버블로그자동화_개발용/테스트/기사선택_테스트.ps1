#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$collectionScript = Join-Path $projectRoot '프로그램\수집작업.ps1'
$selectorScript = Join-Path $projectRoot '프로그램\기사선택.ps1'
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('기사 선택 테스트 ' + [guid]::NewGuid().ToString('N'))
$collectionPath = Join-Path $testRoot 'collection.json'

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    & $collectionScript -Action New -CollectionPath $collectionPath -CollectedDate '2026-11-05' | Out-Null
    $articles = @(
        @{Site='TechCrunch';Url='https://techcrunch.com/2026/11/04/one';Title='One'},
        @{Site='The Verge';Url='https://www.theverge.com/2026/11/04/two';Title='Two'},
        @{Site='Electrek';Url='https://electrek.co/2026/11/04/three';Title='Three'},
        @{Site='POWER Magazine';Url='https://www.powermag.com/four';Title='Four'}
    )
    foreach ($article in $articles) {
        & $collectionScript -Action AddArticle -CollectionPath $collectionPath `
            -SiteName $article.Site -Title $article.Title -Url $article.Url `
            -PublishedDate '2026-11-04' -SelectionReason '검증 가능한 최신 AI 융합 기사입니다.' `
            -FactSummary '확인된 핵심 사실입니다.' -ImportanceSummary '국내 독자에게 중요한 이유입니다.' `
            -ConvergenceDomains @('AI·IT·소프트웨어') `
            -CoreAnalysisAxes @('AI','데이터센터') `
            -ConnectionContext 'AI와 데이터센터의 연결 맥락입니다.' `
            -DomesticRelevance '국내 산업에 주는 의미입니다.' | Out-Null
    }
    foreach ($article in $articles[0..2]) {
        & $collectionScript -Action AddRecommendation -CollectionPath $collectionPath `
            -Url $article.Url -RecommendationReason ("추천 " + $article.Title) | Out-Null
    }

    $listResult = & $selectorScript -Mode List -CollectionPath $collectionPath | ConvertFrom-Json
    $choices = @($listResult.choices)
    if ($listResult.count -ne 4 -or $choices.Count -ne 4 -or
        $choices[0].recommendationRank -ne 1 -or
        $choices[1].recommendationRank -ne 2 -or
        $choices[2].recommendationRank -ne 3 -or
        $choices[3].recommendationRank -ne 0 -or
        $choices[0].url -ne $articles[0].Url -or
        [string]::IsNullOrWhiteSpace([string]$choices[0].connectionContext)) {
        throw 'Validated article choices were not ordered or transferred correctly.'
    }

    Write-Output 'Article selector tests passed.'
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

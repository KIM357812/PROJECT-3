#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$prepareScript = Join-Path $projectRoot '프로그램\초안준비.ps1'
$draftValidator = Join-Path $projectRoot '프로그램\초안검증.ps1'
$settingsPath = Join-Path $projectRoot '설정.json'
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('초안 준비 테스트 ' + [guid]::NewGuid().ToString('N'))
$factPath = Join-Path $testRoot 'fact-check.json'
$draftPath = Join-Path $testRoot 'draft.json'
$readerPath = Join-Path $testRoot 'reader-analysis.json'

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $factCheck = [pscustomobject]@{
        contentId='NTE-20261105-001'
        editorialContext=[pscustomobject]@{
            convergenceDomains=@('ET·환경·에너지')
            coreAnalysisAxes=@('AI','데이터센터','전력')
            connectionContext='AI와 데이터센터 전력 수요의 연결입니다.'
            domesticRelevance='국내 전력망과 데이터센터 투자에 주는 의미입니다.'
        }
        primarySource=[pscustomobject]@{
            name='TechCrunch'; title='Verified article'; url='https://techcrunch.com/example'
            publishedDate='2026-11-04'; checkedDate='2026-11-05'
        }
        articleFiveWOneH=[pscustomobject]@{
            provenance='selectedArticle'; sourceUrl='https://techcrunch.com/example'
            who=[pscustomobject]@{value='시험 기업';evidence='기사에서 기업 발표를 확인했다.'}
            what=[pscustomobject]@{value='검증 기술';evidence='기사에 검증 대상이 적혀 있다.'}
            when=[pscustomobject]@{value='2026년 11월 4일';evidence='기사 게시일을 확인했다.'}
            where=[pscustomobject]@{value='시험 지역';evidence='기사의 지역 설명을 확인했다.'}
            how=[pscustomobject]@{value='단계별 검증';evidence='기사의 검증 방식을 확인했다.'}
            why=[pscustomobject]@{value='상용성 확인';evidence='기사의 목적 설명을 확인했다.'}
        }
        coreFacts=@([pscustomobject]@{claim='Verified fact';sourceUrls=@('https://techcrunch.com/example')})
        lifecycleStages=@('발표')
        sourceFindings='The source reports a verified announcement.'
        authorAnalysis='Commercial impact is not confirmed.'
        numericClaims=@()
        discrepancies=@()
        uncertainties=@('Commercial schedule is unknown.')
        correctionSources=@()
    }
    $factCheck | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $factPath -Encoding UTF8

    $readerAnalysis = [pscustomobject]@{
        evidenceStatus = 'sufficient'
        recommendedBodyLength = [pscustomobject]@{ minimum = 2000; maximum = 3000 }
        topCategory = [pscustomobject]@{ category = 'AI·데이터센터'; postCount = 3; averageViews = 80 }
        topSearchTerms = @([pscustomobject]@{ term = 'AI 데이터센터 전력'; visits = 22 })
        mobileFirst = $true
        rankingGuarantee = $false
    }
    $readerAnalysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $readerPath -Encoding UTF8

    $prepared = & $prepareScript -FactCheckPath $factPath -OutputPath $draftPath `
        -ReaderAnalysisPath $readerPath | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $prepared.output -PathType Leaf) -or
        $prepared.sourceCount -ne 1 -or -not $prepared.requiresWriting -or
        $prepared.readerEvidenceStatus -ne 'sufficient') {
        throw 'The Naver draft preparation file was not created correctly.'
    }
    $draft = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($draft.sources[0].title -ne 'Verified article' -or
        $draft.draftType -ne 'TechnicalArticle' -or
        $draft.factCheckSummary.uncertainties.Count -ne 1 -or
        $draft.articleFiveWOneH.provenance -ne 'selectedArticle' -or
        $draft.articleFiveWOneH.sourceUrl -ne 'https://techcrunch.com/example' -or
        $draft.editorialContext.coreAnalysisAxes -notcontains 'AI' -or
        $draft.editorialContext.aiConnectionExplained -or
        $draft.readerGuidance.recommendedBodyLength.maximum -ne 3000 -or
        $draft.readerGuidance.topSearchTerms[0] -ne 'AI 데이터센터 전력') {
        throw 'Fact-check evidence was not transferred to the draft preparation file.'
    }

    . $draftValidator -Path 'unused'
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $draftValidation = Test-NaverDraft -Draft $draft -Rules $settings.NaverDraft
    if ($draftValidation.IsValid) {
        throw 'An unwritten Naver draft incorrectly passed validation.'
    }

    $duplicateWasBlocked = $false
    try { $null = & $prepareScript -FactCheckPath $factPath -OutputPath $draftPath }
    catch { $duplicateWasBlocked = $true }
    if (-not $duplicateWasBlocked) { throw 'An existing Naver draft was overwritten.' }

    Write-Output 'Draft preparation tests passed.'
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

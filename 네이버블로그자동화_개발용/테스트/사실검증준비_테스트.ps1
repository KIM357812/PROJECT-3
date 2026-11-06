#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$prepareScript = Join-Path $projectRoot '프로그램\사실검증준비.ps1'
$validatorScript = Join-Path $projectRoot '프로그램\작업자료검증.ps1'
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('사실검증 준비 테스트 ' + [guid]::NewGuid().ToString('N'))
$collectionPath = Join-Path $testRoot 'collection.json'
$outputPath = Join-Path $testRoot 'fact-check.json'
$articleUrl = 'https://techcrunch.com/2026/11/04/example'

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    [pscustomobject]@{
        collectedDate='2026-11-05'
        sites=@([pscustomobject]@{
            name='TechCrunch'; baseUrl='https://techcrunch.com'; missingCount=1
            articles=@([pscustomobject]@{
                title='Selected article'; url=$articleUrl; publishedDate='2026-11-04'
                selectionReason='Reason'; summary=@('사실','중요성')
                convergenceDomains=@('ET·환경·에너지')
                coreAnalysisAxes=@('AI','데이터센터','전력')
                connectionContext='AI와 데이터센터 전력의 관계를 검토합니다.'
                domesticRelevance='국내 전력망과 데이터센터 투자에 주는 의미입니다.'
            })
        })
        recommendations=@([pscustomobject]@{url=$articleUrl;reason='Reason'})
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $collectionPath -Encoding UTF8

    $prepared = & $prepareScript -CollectionPath $collectionPath -ArticleUrl $articleUrl `
        -ContentId 'NTE-20261105-001' -OutputPath $outputPath -CheckedDate '2026-11-05' |
        ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $prepared.output -PathType Leaf) -or
        $prepared.sourceName -ne 'TechCrunch') {
        throw 'The fact-check preparation file was not created correctly.'
    }

    $record = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($record.primarySource.url -ne $articleUrl -or $record.coreFacts.Count -ne 0 -or
        $record.articleFiveWOneH.provenance -ne 'selectedArticle' -or
        $record.articleFiveWOneH.sourceUrl -ne $articleUrl -or
        -not [string]::IsNullOrWhiteSpace([string]$record.articleFiveWOneH.who.value) -or
        $record.editorialContext.coreAnalysisAxes -notcontains 'AI' -or
        [string]::IsNullOrWhiteSpace([string]$record.editorialContext.domesticRelevance) -or
        $record.PSObject.Properties.Name -notcontains 'uncertainties') {
        throw 'The selected source was not transferred to the fact-check record.'
    }

    $duplicateWasBlocked = $false
    try {
        $null = & $prepareScript -CollectionPath $collectionPath -ArticleUrl $articleUrl `
            -ContentId 'NTE-20261105-001' -OutputPath $outputPath
    }
    catch { $duplicateWasBlocked = $true }
    if (-not $duplicateWasBlocked) { throw 'An existing fact-check file was overwritten.' }

    . $validatorScript -Mode FactCheck -Path 'unused'
    $validation = Test-FactCheckRecord -Record $record
    if ($validation.IsValid) {
        throw 'An empty fact-check record incorrectly passed validation.'
    }

    Write-Output 'Fact-check preparation tests passed.'
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

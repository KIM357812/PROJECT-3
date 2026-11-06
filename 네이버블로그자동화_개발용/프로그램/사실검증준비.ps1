#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CollectionPath,

    [Parameter(Mandatory = $true)]
    [string]$ArticleUrl,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$ContentId,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$CheckedDate = (Get-Date -Format 'yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $CollectionPath -PathType Leaf)) {
    throw "수집 결과를 찾을 수 없습니다: $CollectionPath"
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "기존 사실검증 파일을 덮어쓰지 않습니다: $OutputPath"
}

$collection = Get-Content -LiteralPath $CollectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$matches = @()
foreach ($site in @($collection.sites)) {
    foreach ($article in @($site.articles)) {
        if ([string]$article.url -eq $ArticleUrl) {
            $matches += [pscustomobject]@{ site=$site; article=$article }
        }
    }
}
if ($matches.Count -ne 1) {
    throw "선택 URL은 수집 결과에 정확히 한 번 존재해야 합니다: $ArticleUrl"
}

$selected = $matches[0]
$record = [pscustomobject]@{
    contentId = $ContentId
    editorialContext = [pscustomobject]@{
        convergenceDomains = @($selected.article.convergenceDomains)
        coreAnalysisAxes = @($selected.article.coreAnalysisAxes)
        connectionContext = [string]$selected.article.connectionContext
        domesticRelevance = [string]$selected.article.domesticRelevance
    }
    primarySource = [pscustomobject]@{
        name = [string]$selected.site.name
        title = [string]$selected.article.title
        url = [string]$selected.article.url
        publishedDate = [string]$selected.article.publishedDate
        checkedDate = $CheckedDate
    }
    articleFiveWOneH = [pscustomobject]@{
        provenance = 'selectedArticle'
        sourceUrl = [string]$selected.article.url
        who = [pscustomobject]@{ value = ''; evidence = '' }
        what = [pscustomobject]@{ value = ''; evidence = '' }
        when = [pscustomobject]@{ value = ''; evidence = '' }
        where = [pscustomobject]@{ value = ''; evidence = '' }
        how = [pscustomobject]@{ value = ''; evidence = '' }
        why = [pscustomobject]@{ value = ''; evidence = '' }
    }
    coreFacts = @()
    lifecycleStages = @()
    sourceFindings = ''
    authorAnalysis = ''
    numericClaims = @()
    discrepancies = @()
    uncertainties = @()
    correctionSources = @()
}

$directory = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($directory)) {
    throw 'OutputPath는 상위 폴더를 포함해야 합니다.'
}
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $directory
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    output = [System.IO.Path]::GetFullPath($OutputPath)
    contentId = $ContentId
    sourceName = $record.primarySource.name
    sourceTitle = $record.primarySource.title
    sourceUrl = $record.primarySource.url
} | ConvertTo-Json -Depth 4

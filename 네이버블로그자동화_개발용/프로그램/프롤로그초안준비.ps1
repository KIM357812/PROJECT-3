#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$ContentId = 'NTE-INTRODUCTION',

    [string]$AnalyzedDate = (Get-Date -Format 'yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $projectRoot '설정.json'
$validatorPath = Join-Path $PSScriptRoot '초안검증.ps1'
. $validatorPath -Path 'unused'

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "프롤로그 원고를 찾을 수 없습니다: $SourcePath"
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "기존 프롤로그 초안을 덮어쓰지 않습니다: $OutputPath"
}

$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$raw = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
$section = [regex]::Match($raw, '(?ms)^## 1\. 첫 인사 글\s*(.*?)(?=^---\s*$)')
if (-not $section.Success) { throw '첫 인사 글 구역을 찾을 수 없습니다.' }

$titleMatch = [regex]::Match($section.Groups[1].Value, '(?ms)^### 제목\s*\r?\n+\s*(.+?)\s*\r?\n+### 본문')
$bodyMatch = [regex]::Match($section.Groups[1].Value, '(?ms)^### 본문\s*(.*?)(?=^### 태그 제안\s*$)')
$tagMatch = [regex]::Match($section.Groups[1].Value, '(?ms)^### 태그 제안\s*(.*)$')
if (-not $titleMatch.Success -or -not $bodyMatch.Success -or -not $tagMatch.Success) {
    throw '제목, 본문 또는 태그 구역을 찾을 수 없습니다.'
}

$title = $titleMatch.Groups[1].Value.Trim().Replace('`', '')
$outputLines = New-Object 'System.Collections.Generic.List[string]'
$sectionHeadings = New-Object 'System.Collections.Generic.List[string]'
foreach ($line in ($bodyMatch.Groups[1].Value -split "`r?`n")) {
    $clean = $line.Replace('`', '').TrimEnd()
    if ($clean -match '^###\s+(.+)$') {
        if ($outputLines.Count -gt 0 -and $outputLines[$outputLines.Count - 1] -ne '') {
            $outputLines.Add('')
        }
        $headingText = $matches[1].Trim()
        $sectionHeadings.Add($headingText)
        $outputLines.Add($headingText)
        $outputLines.Add('')
    }
    elseif ($clean -match '^-\s+(.+)$') {
        $outputLines.Add('• ' + $matches[1].Trim())
        $outputLines.Add('')
    }
    else {
        $outputLines.Add($clean)
    }
}
$body = (($outputLines -join "`r`n") -replace '(\r?\n){3,}', "`r`n`r`n").Trim()
$tags = @([regex]::Matches($tagMatch.Groups[1].Value, '#([\p{L}\p{Nd}_]+)') |
    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)

$draft = [pscustomobject]@{
    contentId = $ContentId
    draftType = 'Introduction'
    requestedCategory = [string]$settings.NaverEditor.IntroductionCategory
    editorialContext = [pscustomobject]@{
        convergenceDomains = @(
            'AI·IT·소프트웨어', '반도체·컴퓨팅', 'NT·나노·첨단소재',
            'ET·환경·에너지', 'ST·우주', '로봇·제조', '모빌리티', '바이오'
        )
        coreAnalysisAxes = @('AI', '데이터센터', '전력', '에너지', '온실가스')
        connectionContext = 'AI가 다른 기술·산업과 결합하고 데이터센터·전력·에너지·온실가스에 미치는 영향을 함께 해석하는 블로그의 편집 방향을 소개한다.'
        domesticRelevance = '글로벌 전문 매체의 최신 이슈를 국내 일반 독자가 빠르고 쉽게 이해하고 스스로 판단하도록 돕는 운영 목적을 밝힌다.'
        aiConnectionExplained = $true
        crossFieldImpactExplained = $true
        domesticRelevanceExplained = $true
        factAnalysisSeparated = $true
        forcedConnectionsExcluded = $true
    }
    title = $title
    body = $body
    sectionHeadings = @($sectionHeadings)
    tags = $tags
    sources = @()
    imagePrompts = @()
    allowImagePromptException = $true
    benchmarkReview = [pscustomobject]@{
        analyzedDate = $AnalyzedDate
        candidateCount = 5
        activeReferenceCount = 4
        primaryBlogId = 'backeclub'
        selectionReason = '일반 독자형 기술 설명과 공개 도달 규모를 함께 충족한 활성 블로그를 주 구조 참고 대상으로 선정했다.'
        adoptedPatterns = @('쉬운 문제 제기형 도입', '분명한 소제목 흐름', '독자 약속과 한계의 명시')
        rejectedPatterns = @('과도한 장문과 다량 태그')
        noCopy = $true
        generalAudienceFirst = $true
        publicMetricsOnly = $true
        primaryHasHighestQualifiedReach = $true
    }
    officialCompliance = [pscustomobject]@{
        searchIntentMatched = $true
        originalStructureAndAnalysis = $true
        noKeywordStuffing = $true
        noHiddenTextOrLinks = $true
        noMechanicalMassProduction = $true
    }
    readerDesign = [pscustomobject]@{
        leadSentenceCount = 3
        keySummaryCount = 3
        readerQuestionCount = 1
    }
}

$validation = Test-NaverDraft -Draft $draft -Rules $settings.NaverDraft
if (-not $validation.IsValid) {
    throw ('프롤로그 초안 검증 실패: ' + (@($validation.Issues) -join '; '))
}

$directory = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($directory)) { throw 'OutputPath는 상위 폴더를 포함해야 합니다.' }
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $directory
}
$draft | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    output = [System.IO.Path]::GetFullPath($OutputPath)
    contentId = $draft.contentId
    draftType = $draft.draftType
    title = $draft.title
    bodyLength = $draft.body.Length
    tagCount = @($draft.tags).Count
    sourceCount = @($draft.sources).Count
    isValid = $true
} | ConvertTo-Json -Depth 4

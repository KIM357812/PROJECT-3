#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Validate', 'Analyze')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$OutputPath,

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

function Add-ReaderIssue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Message
    )
    $Issues.Add($Message)
}

function Get-MedianNumber {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return 0 }
    $middle = [math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2
}

function Test-ReaderMetrics {
    param([Parameter(Mandatory = $true)][psobject]$Metrics)

    $issues = New-Object 'System.Collections.Generic.List[string]'
    $required = @('periodStart', 'periodEnd', 'summary', 'posts', 'searchTerms', 'device')
    foreach ($name in $required) {
        if ($Metrics.PSObject.Properties.Name -notcontains $name) {
            Add-ReaderIssue $issues "Required field is missing: $name"
        }
    }
    if ($issues.Count -gt 0) {
        return [pscustomobject]@{ IsValid = $false; Issues = @($issues) }
    }

    $start = [datetime]::MinValue
    $end = [datetime]::MinValue
    if (-not [datetime]::TryParseExact([string]$Metrics.periodStart, 'yyyy-MM-dd', $null,
            [Globalization.DateTimeStyles]::None, [ref]$start)) {
        Add-ReaderIssue $issues 'periodStart must use yyyy-MM-dd.'
    }
    if (-not [datetime]::TryParseExact([string]$Metrics.periodEnd, 'yyyy-MM-dd', $null,
            [Globalization.DateTimeStyles]::None, [ref]$end)) {
        Add-ReaderIssue $issues 'periodEnd must use yyyy-MM-dd.'
    }
    if ($start -ne [datetime]::MinValue -and $end -ne [datetime]::MinValue -and $end -lt $start) {
        Add-ReaderIssue $issues 'periodEnd must not precede periodStart.'
    }

    foreach ($name in @('views', 'uniqueVisitors', 'visits', 'averageDurationSeconds')) {
        if ($Metrics.summary.PSObject.Properties.Name -notcontains $name -or [double]$Metrics.summary.$name -lt 0) {
            Add-ReaderIssue $issues "summary.$name must be a non-negative number."
        }
    }
    if ($Metrics.device.PSObject.Properties.Name -notcontains 'mobilePercent' -or
        [double]$Metrics.device.mobilePercent -lt 0 -or [double]$Metrics.device.mobilePercent -gt 100) {
        Add-ReaderIssue $issues 'device.mobilePercent must be between 0 and 100.'
    }

    $seenTitles = @{}
    foreach ($post in @($Metrics.posts)) {
        foreach ($name in @('title', 'category', 'bodyLength', 'views', 'likes', 'comments')) {
            if ($post.PSObject.Properties.Name -notcontains $name) {
                Add-ReaderIssue $issues "Post field is missing: $name"
            }
        }
        $title = [string]$post.title
        if ([string]::IsNullOrWhiteSpace($title)) {
            Add-ReaderIssue $issues 'Post title must not be blank.'
        }
        elseif ($seenTitles.ContainsKey($title)) {
            Add-ReaderIssue $issues "Duplicate post title: $title"
        }
        else { $seenTitles[$title] = $true }
        if ([string]::IsNullOrWhiteSpace([string]$post.category)) {
            Add-ReaderIssue $issues "Post category must not be blank: $title"
        }
        if ([int]$post.bodyLength -le 0 -or [int]$post.bodyLength -gt 50000) {
            Add-ReaderIssue $issues "Post bodyLength is outside the accepted range: $title"
        }
        foreach ($name in @('views', 'likes', 'comments')) {
            if ([int]$post.$name -lt 0) {
                Add-ReaderIssue $issues "Post $name must not be negative: $title"
            }
        }
    }

    foreach ($term in @($Metrics.searchTerms)) {
        if ($term.PSObject.Properties.Name -notcontains 'term' -or
            [string]::IsNullOrWhiteSpace([string]$term.term) -or
            $term.PSObject.Properties.Name -notcontains 'visits' -or [int]$term.visits -lt 0) {
            Add-ReaderIssue $issues 'Each search term requires non-blank term and non-negative visits.'
        }
    }

    foreach ($forbidden in @('gender', 'age', 'country', 'userId', 'visitorId', 'ipAddress')) {
        if ($Metrics.PSObject.Properties.Name -contains $forbidden) {
            Add-ReaderIssue $issues "Sensitive or unnecessary field is not accepted: $forbidden"
        }
    }

    return [pscustomobject]@{ IsValid = ($issues.Count -eq 0); Issues = @($issues) }
}

function Get-ReaderRecommendation {
    param(
        [Parameter(Mandatory = $true)][psobject]$Metrics,
        [Parameter(Mandatory = $true)][psobject]$Config
    )

    $validation = Test-ReaderMetrics -Metrics $Metrics
    if (-not $validation.IsValid) {
        throw "Reader metrics are invalid: $($validation.Issues -join '; ')"
    }

    $start = [datetime]::ParseExact([string]$Metrics.periodStart, 'yyyy-MM-dd', $null)
    $end = [datetime]::ParseExact([string]$Metrics.periodEnd, 'yyyy-MM-dd', $null)
    $days = [int](($end - $start).TotalDays + 1)
    $posts = @($Metrics.posts)
    $totalViews = [int]$Metrics.summary.views
    $reasons = @()
    if ($days -lt [int]$Config.ReaderAnalytics.MinimumObservationDays) { $reasons += '관찰 기간 부족' }
    if ($posts.Count -lt [int]$Config.ReaderAnalytics.MinimumPosts) { $reasons += '게시물 수 부족' }
    if ($totalViews -lt [int]$Config.ReaderAnalytics.MinimumTotalViews) { $reasons += '총 조회수 부족' }
    $sufficient = ($reasons.Count -eq 0)

    $lengthMinimum = [int]$Config.ReaderAnalytics.DefaultTargetMinimumBodyLength
    $lengthMaximum = [int]$Config.ReaderAnalytics.DefaultTargetMaximumBodyLength
    $topCategory = $null
    $topTerms = @()

    if ($sufficient) {
        $topCount = [math]::Max(1, [math]::Ceiling($posts.Count * [double]$Config.ReaderAnalytics.TopPostRatio))
        $topPosts = @($posts | Sort-Object @{ Expression = { [int]$_.views }; Descending = $true },
            @{ Expression = { [int]$_.likes + [int]$_.comments }; Descending = $true } | Select-Object -First $topCount)
        $median = Get-MedianNumber -Values @($topPosts | ForEach-Object { [double]$_.bodyLength })
        $margin = [double]$Config.ReaderAnalytics.RecommendedLengthMarginRatio
        $lengthMinimum = [math]::Max([int]$Config.NaverDraft.MinimumBodyLength, [math]::Floor($median * (1 - $margin)))
        $lengthMaximum = [math]::Min([int]$Config.NaverDraft.MaximumBodyLength, [math]::Ceiling($median * (1 + $margin)))

        $categoryGroups = @($posts | Group-Object category | Where-Object { $_.Count -ge 2 } | ForEach-Object {
            [pscustomobject]@{
                category = $_.Name
                postCount = $_.Count
                averageViews = [math]::Round((($_.Group | Measure-Object views -Average).Average), 1)
            }
        } | Sort-Object averageViews -Descending)
        if ($categoryGroups.Count -gt 0) { $topCategory = $categoryGroups[0] }

        $searchVisits = [int](@($Metrics.searchTerms) | Measure-Object visits -Sum).Sum
        if ($searchVisits -ge [int]$Config.ReaderAnalytics.MinimumSearchVisits) {
            $topTerms = @($Metrics.searchTerms | Sort-Object visits -Descending | Select-Object -First 5)
        }
    }

    return [pscustomobject]@{
        generatedAt = (Get-Date).ToString('s')
        evidenceStatus = $(if ($sufficient) { 'sufficient' } else { 'insufficient' })
        evidence = [pscustomobject]@{
            observationDays = $days
            postCount = $posts.Count
            totalViews = $totalViews
            insufficientReasons = @($reasons)
        }
        recommendedBodyLength = [pscustomobject]@{
            minimum = [int]$lengthMinimum
            maximum = [int]$lengthMaximum
            source = $(if ($sufficient) { '상위 조회 게시물 길이의 중앙값과 설정 여유폭' } else { '기본 네이버 초안 목표 범위' })
        }
        topCategory = $topCategory
        topSearchTerms = @($topTerms)
        mobileFirst = ([double]$Metrics.device.mobilePercent -ge 60)
        rankingGuarantee = $false
        notice = '이 결과는 내부 독자 반응을 바탕으로 한 편집 참고값이며 네이버 검색 노출이나 방문 증가를 보장하지 않습니다.'
    }
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) '설정.json'
}
$metrics = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
$validationResult = Test-ReaderMetrics -Metrics $metrics
if ($Mode -eq 'Validate') {
    $validationResult
    return
}
if (-not $OutputPath) { throw 'OutputPath is required in Analyze mode.' }
if (Test-Path -LiteralPath $OutputPath) { throw "Output file already exists: $OutputPath" }
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$result = Get-ReaderRecommendation -Metrics $metrics -Config $config
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result

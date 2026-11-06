#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ConfigPath) { $ConfigPath = Join-Path $projectRoot '설정.json' }
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "벤치마크 입력 파일을 찾을 수 없습니다: $Path" }
if (Test-Path -LiteralPath $OutputPath) { throw "기존 벤치마크 결과를 덮어쓰지 않습니다: $OutputPath" }

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$input = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
$rules = $config.Benchmark
$issues = New-Object 'System.Collections.Generic.List[string]'

$analyzedDate = [datetime]::MinValue
if (-not [datetime]::TryParseExact([string]$input.analyzedDate, 'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None,
        [ref]$analyzedDate)) {
    $issues.Add('analyzedDate는 yyyy-MM-dd 형식이어야 합니다.')
}
elseif ($analyzedDate -gt (Get-Date).Date -or
    ((Get-Date).Date - $analyzedDate).TotalDays -gt [int]$rules.MaximumMetricsAgeDays) {
    $issues.Add('벤치마크 분석일이 미래이거나 허용 기간보다 오래됐습니다.')
}
if ([string]::IsNullOrWhiteSpace([string]$input.topic)) { $issues.Add('비교 주제가 필요합니다.') }
$candidates = @($input.candidates)
if ($candidates.Count -lt [int]$rules.MinimumComparableBlogs) {
    $issues.Add("비교 블로그는 최소 $($rules.MinimumComparableBlogs)개여야 합니다.")
}

$seen = @{}
foreach ($candidate in $candidates) {
    $id = [string]$candidate.blogId
    if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^[A-Za-z0-9_-]+$') {
        $issues.Add('각 후보에는 올바른 네이버 blogId가 필요합니다.')
    }
    elseif ($seen.ContainsKey($id)) { $issues.Add("중복 blogId입니다: $id") }
    else { $seen[$id] = $true }

    $uri = $null
    if (-not [uri]::TryCreate([string]$candidate.blogUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or $uri.Host -ne 'blog.naver.com') {
        $issues.Add("후보 URL은 네이버 블로그 HTTPS 주소여야 합니다: $id")
    }
    foreach ($name in @('publicNeighbors', 'latestPostDays')) {
        if ($candidate.PSObject.Properties.Name -notcontains $name -or [int]$candidate.$name -lt 0) {
            $issues.Add("후보 $id 의 $name 값은 0 이상의 공개 수치여야 합니다.")
        }
    }
    foreach ($name in @('topicSimilarity', 'generalAudienceFit', 'sourceQuality')) {
        $value = [int]$candidate.$name
        if ($candidate.PSObject.Properties.Name -notcontains $name -or $value -lt 1 -or $value -gt 5) {
            $issues.Add("후보 $id 의 $name 값은 1~5여야 합니다.")
        }
    }
    if (-not [bool]$candidate.publicMetricsOnly) {
        $issues.Add("후보 $id 는 공개 지표만 사용해야 합니다.")
    }
}

$active = @($candidates | Where-Object { [int]$_.latestPostDays -le [int]$rules.ActiveWithinDays })
if ($active.Count -lt [int]$rules.MinimumActiveReferences) {
    $issues.Add("최근 $($rules.ActiveWithinDays)일 이내 활성 블로그가 부족합니다.")
}
$qualified = @($active | Where-Object {
    [int]$_.topicSimilarity -ge [int]$rules.MinimumTopicSimilarity -and
    [int]$_.generalAudienceFit -ge [int]$rules.MinimumGeneralAudienceFit
})
if ($qualified.Count -eq 0) { $issues.Add('주제 유사성과 일반 독자 적합성을 모두 통과한 후보가 없습니다.') }
if ($issues.Count -gt 0) { throw ('벤치마크 입력을 보완하세요: ' + (@($issues) -join '; ')) }

$primary = @($qualified | Sort-Object `
    @{ Expression = { [int]$_.publicNeighbors }; Descending = $true },
    @{ Expression = { [int]$_.latestPostDays }; Descending = $false },
    @{ Expression = { [int]$_.sourceQuality }; Descending = $true })[0]
$adopted = @($primary.adoptedPatterns | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$rejected = @($input.rejectedPatterns | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($adopted.Count -lt [int]$rules.MinimumAdoptedPatterns) {
    throw "주 참고 블로그에서 채택할 구조를 최소 $($rules.MinimumAdoptedPatterns)개 기록하세요."
}
if ($rejected.Count -lt [int]$rules.MinimumRejectedPatterns) {
    throw "따라 하지 않을 패턴을 최소 $($rules.MinimumRejectedPatterns)개 기록하세요."
}

$review = [pscustomobject]@{
    analyzedDate = $analyzedDate.ToString('yyyy-MM-dd')
    topic = [string]$input.topic
    candidateCount = $candidates.Count
    activeReferenceCount = $active.Count
    qualifiedReferenceCount = $qualified.Count
    primaryBlogId = [string]$primary.blogId
    primaryBlogUrl = [string]$primary.blogUrl
    primaryPublicNeighbors = [int]$primary.publicNeighbors
    selectionReason = '주제 유사성과 일반 독자 적합성·최근 활동성을 통과한 후보 중 공개 이웃 수가 가장 큽니다.'
    adoptedPatterns = $adopted
    rejectedPatterns = $rejected
    noCopy = $true
    generalAudienceFirst = $true
    publicMetricsOnly = $true
    primaryHasHighestQualifiedReach = $true
    excludedCandidates = @($candidates | Where-Object { [string]$_.blogId -ne [string]$primary.blogId } | ForEach-Object {
        [pscustomobject]@{
            blogId = [string]$_.blogId
            active = ([int]$_.latestPostDays -le [int]$rules.ActiveWithinDays)
            topicSimilarity = [int]$_.topicSimilarity
            generalAudienceFit = [int]$_.generalAudienceFit
            publicNeighbors = [int]$_.publicNeighbors
        }
    })
}

$directory = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($directory)) { throw 'OutputPath는 상위 폴더를 포함해야 합니다.' }
if (-not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory }
$review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$review

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '공통.ps1')
. (Join-Path $PSScriptRoot '후보준비.ps1')
function Assert([bool]$condition,[string]$message) { if (-not $condition) { throw $message } }

$rss = @'
<?xml version="1.0"?><rss version="2.0"><channel>
<item><title>새로운 전력망 기술</title><link>https://techcrunch.com/2026/09/30/grid/?utm_source=rss&amp;foo=1</link><pubDate>Wed, 30 Sep 2026 12:00:00 GMT</pubDate></item>
</channel></rss>
'@
$atom = @'
<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
<entry><title>우주 위성</title><link rel="alternate" href="https://spacenews.com/satellite/?fbclid=abc"/><published>2026-09-29T12:00:00Z</published></entry>
</feed>
'@
$sitemap = @'
<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://electrek.co/2026/09/30/battery/</loc><lastmod>2026-09-30</lastmod></url></urlset>
'@
$html = '<html><head><link rel="alternate" type="application/rss+xml" href="/feed/"></head><body><a href="/2026/09/30/important-electric-grid-story/?utm_medium=home">Important electric grid story</a></body></html>'
$r = @(Read-FeedCandidates $rss 'https://techcrunch.com/feed/')
$a = @(Read-FeedCandidates $atom 'https://spacenews.com/feed/')
$s = @(Read-SitemapCandidates $sitemap 'https://electrek.co/sitemap.xml')
$h = @(Read-HtmlCandidates $html 'https://techcrunch.com')
Assert ($r.Count -eq 1 -and $r[0].Url -eq 'https://techcrunch.com/2026/09/30/grid?foo=1') 'RSS URL 정규화'
Assert ($a.Count -eq 1 -and $a[0].Url -eq 'https://spacenews.com/satellite') 'Atom 파싱 및 추적 제거'
Assert ($s.Count -eq 1 -and -not $s[0].Date) '사이트맵 lastmod를 게시일로 오인'
Assert ($h.Count -eq 1 -and $h[0].Url -eq 'https://techcrunch.com/2026/09/30/important-electric-grid-story') 'HTML 링크 파싱'
Assert (@(Get-FeedLinks $html 'https://techcrunch.com').Count -eq 1) '피드 링크 발견'
Assert (-not (Test-ArticleHost 'https://other.example/story' 'techcrunch.com')) '외부 사이트 차단'
Assert (-not (Test-ArticleHost 'https://www.powermag.com/tag/ups' 'powermag.com')) '태그 목록 차단'
Assert (-not (Test-ArticleHost 'https://www.powermag.com/event/experience-power-2026' 'powermag.com')) '행사 페이지 차단'
Assert (Test-ArticleHost 'https://www.powermag.com/grid-modernization-helps-utilities-add-capacity' 'powermag.com') 'POWER 기사 허용'
$today = (Get-Date).Date
$older = $today.AddDays(-31).ToString('yyyy-MM-dd')
$candidate = [pscustomobject]@{ Number=1;Title='테스트';Site='TechCrunch';Date=$older;Url='https://techcrunch.com/old';Reason='이유';Summary=@('가','나');Details='테스트' }
Assert (@(Select-ValidCandidates @($candidate)).Count -eq 0) '30일 밖 기사 제외'
$candidate.Date = '게시일 확인 불가'
Assert (@(Select-ValidCandidates @($candidate)).Count -eq 1) '날짜 미확인 후보 유지'
$alreadyUsed = [pscustomobject]@{ Number=2;Title='작성 완료';Site='The Verge';Date='게시일 확인 불가';Url='https://www.theverge.com/ai-artificial-intelligence/1002033/openai-dots-launch-muse-competitor';Reason='이유';Summary=@('가','나');Details='테스트' }
$oldUsedPath = $script:UsedUrlPath
$script:UsedUrlPath = Join-Path ([IO.Path]::GetTempPath()) ('blog_used_'+[guid]::NewGuid().ToString('N')+'.txt')
try {
    Add-UsedUrl $alreadyUsed.Url
    Assert (@(Select-ValidCandidates @($alreadyUsed)).Count -eq 0) '작성 완료 URL 제외'
} finally {
    if ([IO.File]::Exists($script:UsedUrlPath)) { [IO.File]::Delete($script:UsedUrlPath) }
    $script:UsedUrlPath = $oldUsedPath
}
Write-Output '통과: RSS, Atom, 사이트맵, HTML, 피드 발견, URL 정규화, 날짜 필터, 미확인 날짜'

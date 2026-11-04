# 공개 페이지에서 URL 후보만 모읍니다. 기사 사실 확인은 Codex가 수행합니다.
$script:Sources = @(
    @{ Name='TechCrunch'; Home='https://techcrunch.com'; Host='techcrunch.com' },
    @{ Name='The Verge'; Home='https://www.theverge.com'; Host='theverge.com' },
    @{ Name='Electrek'; Home='https://electrek.co'; Host='electrek.co' },
    @{ Name='POWER Magazine'; Home='https://www.powermag.com'; Host='powermag.com' },
    @{ Name='CleanTechnica'; Home='https://cleantechnica.com'; Host='cleantechnica.com' },
    @{ Name='Canary Media'; Home='https://www.canarymedia.com'; Host='canarymedia.com' },
    @{ Name='Space.com'; Home='https://www.space.com'; Host='space.com' },
    @{ Name='SpaceNews'; Home='https://spacenews.com'; Host='spacenews.com' }
)

function Normalize-ArticleUrl([string]$value, [string]$baseUrl) {
    try {
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        $value = [Net.WebUtility]::HtmlDecode($value.Trim())
        $uri = [uri]::new([uri]$baseUrl, $value)
        if ($uri.Scheme -ne 'https' -and $uri.Scheme -ne 'http') { return $null }
        $builder = [UriBuilder]::new($uri)
        $builder.Scheme = 'https'; $builder.Port = -1; $builder.Fragment = ''
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($part in $builder.Query.TrimStart('?').Split('&')) {
            if (-not $part) { continue }
            $key = [uri]::UnescapeDataString(($part -split '=',2)[0]).ToLowerInvariant()
            if ($key -match '^(utm_|fbclid$|gclid$|dclid$|mc_|ref$|source$|cmpid$|igshid$)') { continue }
            $parts.Add($part)
        }
        $builder.Query = ($parts -join '&')
        $builder.Host = $builder.Host.ToLowerInvariant()
        $builder.Path = $builder.Path.TrimEnd('/')
        return $builder.Uri.AbsoluteUri.TrimEnd('/')
    } catch { return $null }
}

function Test-ArticleHost([string]$url, [string]$siteHost) {
    try {
        $uri = [uri]$url
        if ($uri.Host -ne $siteHost -and $uri.Host -ne ('www.'+$siteHost)) { return $false }
        $path = $uri.AbsolutePath.Trim('/')
        if (-not $path -or $path -match '^(category|categories|tag|tags|author|authors|search|feed|about|contact|newsletter|topics|topic|page|latest)(/|$)') { return $false }
        if ($siteHost -eq 'powermag.com') {
            if ($path -match '^(event|events|issues|white-papers|partner-content|press-releases|power-awards|publications|podcasts|webinars)(/|$)') { return $false }
            if ([regex]::Matches($path,'-').Count -lt 4) { return $false }
        }
        if ($path -match '\.(xml|jpg|jpeg|png|webp|gif|pdf|css|js)$') { return $false }
        return $true
    } catch { return $false }
}

function Convert-PublicDate([string]$value) {
    if (-not $value) { return $null }
    try { return ([DateTimeOffset]::Parse($value,[Globalization.CultureInfo]::InvariantCulture)).ToLocalTime().ToString('yyyy-MM-dd') }
    catch { return $null }
}

function Get-ChildText([xml.XmlNode]$node,[string[]]$names) {
    foreach ($name in $names) {
        $child = @($node.ChildNodes | Where-Object LocalName -eq $name | Select-Object -First 1)
        if ($child.Count -and $child[0].InnerText) { return $child[0].InnerText.Trim() }
    }
    return ''
}

function Read-FeedCandidates([string]$content,[string]$baseUrl) {
    $doc = New-Object xml.XmlDocument
    $doc.LoadXml($content)
    if ($doc.DocumentElement.LocalName -notin @('rss','feed','RDF')) { throw 'RSS/Atom 형식이 아닙니다.' }
    $result = New-Object System.Collections.ArrayList
    foreach ($node in @($doc.SelectNodes('//*[local-name()="item" or local-name()="entry"]'))) {
        $linkNode = @($node.ChildNodes | Where-Object LocalName -eq 'link' | Select-Object -First 1)
        $link = if ($linkNode.Count -and $linkNode[0].Attributes['href']) { $linkNode[0].Attributes['href'].Value } else { Get-ChildText $node @('link') }
        if (-not $link) { continue }
        [void]$result.Add([pscustomobject]@{
            Url=(Normalize-ArticleUrl $link $baseUrl)
            Title=([Net.WebUtility]::HtmlDecode((Get-ChildText $node @('title'))))
            Date=(Convert-PublicDate (Get-ChildText $node @('pubDate','published','date','issued','updated')))
            Source='RSS/Atom'
        })
    }
    return @($result.ToArray())
}

function Read-SitemapCandidates([string]$content,[string]$baseUrl) {
    $doc = New-Object xml.XmlDocument
    $doc.LoadXml($content)
    if ($doc.DocumentElement.LocalName -notin @('urlset','sitemapindex')) { throw '사이트맵 형식이 아닙니다.' }
    $result = New-Object System.Collections.ArrayList
    foreach ($node in @($doc.DocumentElement.ChildNodes)) {
        if ($node.LocalName -notin @('url','sitemap')) { continue }
        $dateNode = @($node.SelectNodes('.//*[local-name()="publication_date"]') | Select-Object -First 1)
        $date = if ($dateNode.Count) { Convert-PublicDate $dateNode[0].InnerText } else { $null }
        [void]$result.Add([pscustomobject]@{
            Url=(Normalize-ArticleUrl (Get-ChildText $node @('loc')) $baseUrl)
            Title=''
            Date=$date # lastmod는 게시일로 취급하지 않습니다.
            LastMod=(Convert-PublicDate (Get-ChildText $node @('lastmod')))
            Source='사이트맵'
            IsIndex=($node.LocalName -eq 'sitemap')
        })
    }
    return @($result.ToArray())
}

function Read-HtmlCandidates([string]$content,[string]$baseUrl) {
    $result = New-Object System.Collections.ArrayList
    foreach ($match in [regex]::Matches($content,'(?is)<a\b[^>]*\bhref\s*=\s*["''](?<url>[^"'']+)["''][^>]*>(?<title>.*?)</a>')) {
        $title = [Net.WebUtility]::HtmlDecode(([regex]::Replace($match.Groups['title'].Value,'<[^>]+>',' ')).Trim())
        if ($title.Length -lt 12) { continue }
        [void]$result.Add([pscustomobject]@{ Url=(Normalize-ArticleUrl $match.Groups['url'].Value $baseUrl); Title=$title; Date=$null; Source='최신 기사 페이지' })
    }
    return @($result.ToArray())
}

function Get-FeedLinks([string]$content,[string]$baseUrl) {
    $urls = New-Object System.Collections.ArrayList
    foreach ($match in [regex]::Matches($content,'(?is)<link\b[^>]*>')) {
        $tag = $match.Value
        if ($tag -notmatch '(?i)application/(rss|atom)\+xml') { continue }
        $href = [regex]::Match($tag,'(?i)\bhref\s*=\s*["''](?<url>[^"'']+)["'']')
        if ($href.Success) { $url = Normalize-ArticleUrl $href.Groups['url'].Value $baseUrl; if ($url) { [void]$urls.Add($url) } }
    }
    return @($urls.ToArray() | Select-Object -Unique)
}

function Get-PublicPage([string]$url) {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -MaximumRedirection 3 -TimeoutSec 5 -Headers @{ 'User-Agent'='BlogCandidateCollector/1.0 (public feeds and pages)'; 'Accept'='application/rss+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.8' } -ErrorAction Stop
    if ([int]$response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode)" }
    return [pscustomobject]@{ Content=$response.Content; Url=$response.BaseResponse.ResponseUri.AbsoluteUri; Type=([string]$response.Headers['Content-Type']) }
}

function Invoke-SiteCollect([hashtable]$site,[datetime]$today) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $items = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $methods = New-Object System.Collections.ArrayList
    $homePage = $null
    try { $homePage = Get-PublicPage $site.Home } catch { [void]$errors.Add("홈: $($_.Exception.Message)") }
    if ($homePage) {
        foreach ($feedUrl in @(Get-FeedLinks $homePage.Content $homePage.Url | Select-Object -First 2)) {
            try {
                $page = Get-PublicPage $feedUrl
                if ($page.Type -notmatch 'xml|rss|atom' -and $page.Content -notmatch '^\s*<\?xml|^\s*<(rss|feed|rdf)\b') { throw '응답이 XML이 아닙니다.' }
                foreach ($item in @(Read-FeedCandidates $page.Content $page.Url)) { [void]$items.Add($item) }
                if ($items.Count) { [void]$methods.Add('RSS/Atom'); break }
            } catch { [void]$errors.Add("피드 ${feedUrl}: $($_.Exception.Message)") }
        }
    }
    if ($items.Count -lt 2) {
        $sitemapUrls = New-Object System.Collections.ArrayList
        try {
            $robots = Get-PublicPage ($site.Home.TrimEnd('/')+'/robots.txt')
            foreach ($match in [regex]::Matches($robots.Content,'(?im)^\s*Sitemap:\s*(https?://\S+)')) { [void]$sitemapUrls.Add($match.Groups[1].Value) }
        } catch { [void]$errors.Add("robots.txt: $($_.Exception.Message)") }
        if (-not $sitemapUrls.Count) { [void]$sitemapUrls.Add($site.Home.TrimEnd('/')+'/sitemap.xml') }
        foreach ($sitemapUrl in @($sitemapUrls.ToArray() | Select-Object -First 2)) {
            try {
                $page = Get-PublicPage $sitemapUrl
                $entries = @(Read-SitemapCandidates $page.Content $page.Url)
                if ($entries.Count -and $entries[0].IsIndex) {
                    $selected = @($entries | Sort-Object @{Expression={ if ($_.Url -match 'news|post|article') { 1 } else { 0 } };Descending=$true}, @{Expression='LastMod';Descending=$true} | Select-Object -First 1)
                    $page = Get-PublicPage $selected[0].Url
                    $entries = @(Read-SitemapCandidates $page.Content $page.Url)
                }
                foreach ($item in $entries) { if (-not $item.IsIndex) { [void]$items.Add($item) } }
                if ($entries.Count) { [void]$methods.Add('사이트맵'); break }
            } catch { [void]$errors.Add("사이트맵 ${sitemapUrl}: $($_.Exception.Message)") }
        }
    }
    $usable = @($items | Where-Object { $_.Url -and (Test-ArticleHost $_.Url $site.Host) })
    if ($usable.Count -lt 2 -and $homePage) {
        foreach ($item in @(Read-HtmlCandidates $homePage.Content $homePage.Url)) { [void]$items.Add($item) }
        [void]$methods.Add('최신 기사 페이지')
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $clean = New-Object System.Collections.ArrayList
    foreach ($item in $items) {
        if (-not $item.Url -or -not (Test-ArticleHost $item.Url $site.Host) -or -not $seen.Add($item.Url)) { continue }
        if ($item.Date) {
            $age = ($today.Date - ([datetime]::ParseExact($item.Date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)).Date).Days
            if ($age -lt 0 -or $age -gt 30) { continue }
        }
        [void]$clean.Add([pscustomobject]@{Site=$site.Name;Url=$item.Url;Title=$item.Title;Date=$(if($item.Date){$item.Date}else{'게시일 확인 불가'});Source=$item.Source})
        if ($clean.Count -ge 10) { break }
    }
    $watch.Stop()
    return [pscustomobject]@{ Site=$site.Name; Status=$(if($clean.Count){'성공'}else{'실패'}); Seconds=[math]::Round($watch.Elapsed.TotalSeconds,2); Count=$clean.Count; Method=($methods -join ', '); Error=($errors -join ' | '); Candidates=@($clean.ToArray()) }
}

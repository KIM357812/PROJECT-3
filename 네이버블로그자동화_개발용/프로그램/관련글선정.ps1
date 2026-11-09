#requires -Version 5.1

function ConvertTo-RelatedPlainText([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $text = [regex]::Replace($Value, '(?is)<(?:script|style)\b[^>]*>.*?</(?:script|style)>', ' ')
    $text = [regex]::Replace($text, '(?is)<[^>]+>', ' ')
    $text = [Net.WebUtility]::HtmlDecode($text)
    return [regex]::Replace($text, '\s+', ' ').Trim()
}

function Get-NaverPostIdentity([string]$Url, [string]$ExpectedBlogId = '') {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    try { $uri = [Uri]$Url.Trim() } catch { return $null }
    if ($uri.Scheme -notin @('http','https')) { return $null }
    if ($uri.Host -notin @('blog.naver.com','m.blog.naver.com')) { return $null }

    $blogId = ''
    $logNo = ''
    $segments = @($uri.AbsolutePath.Trim('/') -split '/')
    if ($segments.Count -ge 2 -and $segments[0] -and $segments[1] -match '^\d+$') {
        $blogId = $segments[0]
        $logNo = $segments[1]
    }
    else {
        $blogMatch = [regex]::Match($uri.Query, '(?:^|[?&])blogId=(?<value>[^&]+)', 'IgnoreCase')
        $logMatch = [regex]::Match($uri.Query, '(?:^|[?&])logNo=(?<value>\d+)', 'IgnoreCase')
        if ($blogMatch.Success) { $blogId = [Uri]::UnescapeDataString($blogMatch.Groups['value'].Value) }
        if ($logMatch.Success) { $logNo = $logMatch.Groups['value'].Value }
    }
    if (-not $blogId -or $logNo -notmatch '^\d+$') { return $null }
    if ($ExpectedBlogId -and $blogId -ne $ExpectedBlogId) { return $null }
    return [pscustomobject]@{
        BlogId = $blogId
        LogNo = $logNo
        ComparableUrl = ('https://blog.naver.com/{0}/{1}' -f $blogId,$logNo).ToLowerInvariant()
        PublicUrl = ('https://blog.naver.com/{0}/{1}' -f $blogId,$logNo)
    }
}

function Get-RelatedKeywords([string]$Value) {
    $plain = (ConvertTo-RelatedPlainText $Value).ToLowerInvariant()
    $stop = @('그리고','그러나','하지만','관련','분석','전망','이번','현재','새로운','대한','통해','위한','있는','없는','하는','되는','에서','보다','으로','로서','에게','까지','부터','처럼','따라','때문','무엇','어떻게','이유')
    $particles = @('으로','에서','보다','에게','까지','부터','처럼','하고','이며','이나','거나','은','는','이','가','을','를','에','의','로','와','과','도','만')
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($match in [regex]::Matches($plain, '[가-힣]{2,}|[a-z0-9]{3,}')) {
        $word = $match.Value
        foreach ($particle in $particles) {
            if ($word.Length -gt ($particle.Length + 1) -and $word.EndsWith($particle,[StringComparison]::Ordinal)) {
                $word = $word.Substring(0,$word.Length-$particle.Length)
                break
            }
        }
        if ($word.Length -lt 2 -or $stop -contains $word) { continue }
        [void]$set.Add($word)
    }
    return @($set)
}

function Test-RelatedKeywordMatch([string]$Left, [string]$Right) {
    if ($Left -eq $Right) { return $true }
    if ($Left.Length -ge 3 -and $Right.Length -ge 3 -and ($Left.Contains($Right) -or $Right.Contains($Left))) { return $true }
    return $false
}

function Get-RelatedKeywordMatches([string[]]$Query, [string[]]$Candidate) {
    $matches = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($left in @($Query)) {
        foreach ($right in @($Candidate)) {
            if (Test-RelatedKeywordMatch $left $right) { [void]$matches.Add($left); break }
        }
    }
    return @($matches)
}

function Get-RelatedUrlsFromHtml([string]$Html, [string]$BlogId) {
    $urls = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($match in [regex]::Matches([string]$Html, '(?is)(?:href|data-href)\s*=\s*["''](?<url>https?://(?:m\.)?blog\.naver\.com/[^"'']+)["'']')) {
        $identity = Get-NaverPostIdentity $match.Groups['url'].Value $BlogId
        if ($identity) { [void]$urls.Add($identity.PublicUrl) }
    }
    return @($urls.ToArray())
}

function ConvertTo-NaverPublicPost([object]$Post, [string]$BlogId) {
    $identity = Get-NaverPostIdentity ([string]$Post.Url) $BlogId
    if (-not $identity) { return $null }
    $published = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Post.Published,[ref]$published)) { return $null }
    $title = (ConvertTo-RelatedPlainText ([string]$Post.Title)).Trim()
    if (-not $title) { return $null }
    return [pscustomobject]@{
        Title = $title
        Url = $identity.PublicUrl
        ComparableUrl = $identity.ComparableUrl
        Published = $published
        Labels = @($Post.Labels | ForEach-Object { ConvertTo-RelatedPlainText ([string]$_) } | Where-Object { $_ })
        Content = ConvertTo-RelatedPlainText ([string]$Post.Content)
        RelatedUrls = @($Post.RelatedUrls | ForEach-Object {
            $relatedIdentity = Get-NaverPostIdentity ([string]$_) $BlogId
            if ($relatedIdentity) { $relatedIdentity.PublicUrl }
        } | Where-Object { $_ } | Select-Object -Unique)
    }
}

function Get-NaverPublicPosts([string]$BlogId, [int]$Maximum = 150, [string]$PostListPath = '', [int]$DetailLookbackDays = 60) {
    if ($PostListPath) {
        if (-not (Test-Path -LiteralPath $PostListPath -PathType Leaf)) { throw "관련 글 게시물 목록을 찾을 수 없습니다: $PostListPath" }
        $items = @(Get-Content -LiteralPath $PostListPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        return @($items | ForEach-Object { ConvertTo-NaverPublicPost $_ $BlogId } | Where-Object { $_ })
    }

    try {
        $rssUrl = 'https://rss.blog.naver.com/{0}.xml' -f $BlogId
        [xml]$rss = (Invoke-WebRequest -UseBasicParsing -Uri $rssUrl -TimeoutSec 20).Content
        $posts = New-Object 'System.Collections.Generic.List[object]'
        foreach ($item in @($rss.rss.channel.item) | Select-Object -First $Maximum) {
            $description = [string]$item.description
            $labels = @()
            if ($item.category) { $labels = @($item.category | ForEach-Object { [string]$_.'#text' }) }
            $post = ConvertTo-NaverPublicPost ([pscustomobject]@{
                Title = [string]$item.title
                Url = [string]$item.link
                Published = [string]$item.pubDate
                Labels = $labels
                Content = $description
                RelatedUrls = @(Get-RelatedUrlsFromHtml $description $BlogId)
            }) $BlogId
            if ($post) { $posts.Add($post) }
        }
        if ($posts.Count -gt 0) { return @($posts.ToArray()) }
    }
    catch {
        # RSS를 사용하지 않는 블로그는 아래 공개 모바일 목록 API로 다시 확인한다.
    }

    try {
        $apiUrl = 'https://m.blog.naver.com/api/blogs/{0}/category/0/post?itemCount={1}' -f $BlogId,$Maximum
        $headers = @{ Referer=('https://m.blog.naver.com/{0}' -f $BlogId); Accept='application/json' }
        $payload = (Invoke-WebRequest -UseBasicParsing -Uri $apiUrl -Headers $headers -TimeoutSec 20).Content | ConvertFrom-Json
        if (-not [bool]$payload.isSuccess) { return @() }
        $posts = New-Object 'System.Collections.Generic.List[object]'
        foreach ($item in @($payload.result.items) | Select-Object -First $Maximum) {
            $logNo = [string]$item.logNo
            $title = if ($item.titleWithInspectMessage) { [string]$item.titleWithInspectMessage } else { [string]$item.title }
            $published = ''
            foreach ($name in @('addDate','postAddDate','publishedAt','publishDate','addDateStr')) {
                if ($item.PSObject.Properties.Name -contains $name -and $item.$name) { $published = [string]$item.$name; break }
            }
            $content = if ($item.briefContents) { [string]$item.briefContents } elseif ($item.contents) { [string]$item.contents } else { '' }
            $labels = @()
            foreach ($name in @('categoryName','tags','tagList')) {
                if ($item.PSObject.Properties.Name -contains $name -and $item.$name) { $labels += @($item.$name | ForEach-Object { [string]$_ }) }
            }
            if ($logNo -notmatch '^\d+$' -or -not $title -or -not $published) { continue }
            $publicUrl = 'https://blog.naver.com/{0}/{1}' -f $BlogId,$logNo
            $relatedUrls = @(Get-RelatedUrlsFromHtml $content $BlogId)
            $publishedAt = [DateTimeOffset]::MinValue
            $isRecent = [DateTimeOffset]::TryParse($published,[ref]$publishedAt) -and $publishedAt -ge [DateTimeOffset]::Now.AddDays(-1 * $DetailLookbackDays)
            if ($relatedUrls.Count -eq 0 -and $isRecent) {
                try {
                    $detail = (Invoke-WebRequest -UseBasicParsing -Uri $publicUrl -TimeoutSec 10).Content
                    $relatedUrls = @(Get-RelatedUrlsFromHtml $detail $BlogId)
                    if (-not $content) { $content = $detail }
                } catch { }
            }
            $post = ConvertTo-NaverPublicPost ([pscustomobject]@{
                Title=$title; Url=$publicUrl; Published=$published; Labels=$labels; Content=$content; RelatedUrls=$relatedUrls
            }) $BlogId
            if ($post) { $posts.Add($post) }
        }
        return @($posts.ToArray())
    }
    catch { return @() }
}

function Select-NaverRelatedPosts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CurrentTitle,
        [string]$CurrentSummary = '',
        [string[]]$CurrentLabels = @(),
        [string]$CurrentUrl = '',
        [DateTimeOffset]$ScheduledAt = [DateTimeOffset]::Now,
        [object[]]$Posts = @(),
        [string]$BlogId = 'ij1128',
        [int]$LookbackDays = 60,
        [int]$Maximum = 3,
        [int]$TitleMatchPoints = 10,
        [int]$LabelMatchPoints = 6,
        [int]$BodyMatchPoints = 2,
        [int]$MaximumBodyMatches = 5,
        [int]$RepeatPenaltyPoints = 3,
        [int]$MaximumRepeatPenalty = 12,
        [int]$ReplacementMinimumScore = 10,
        [double]$ReplacementMinimumRatio = 0.6
    )

    $currentIdentity = Get-NaverPostIdentity $CurrentUrl $BlogId
    $titleTerms = @(Get-RelatedKeywords $CurrentTitle)
    $bodyTerms = @(Get-RelatedKeywords $CurrentSummary)
    $labelTerms = @(Get-RelatedKeywords (@($CurrentLabels) -join ' '))
    $allTerms = @($titleTerms + $bodyTerms + $labelTerms | Select-Object -Unique)
    $cutoff = $ScheduledAt.AddDays(-[Math]::Abs($LookbackDays))
    $normalized = @($Posts | ForEach-Object { ConvertTo-NaverPublicPost $_ $BlogId } | Where-Object { $_ })
    $usage = @{}
    $recentCombinations = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($post in $normalized) {
        if ($post.Published -lt $cutoff -or $post.Published -ge $ScheduledAt) { continue }
        $combination = @($post.RelatedUrls | ForEach-Object { (Get-NaverPostIdentity $_ $BlogId).ComparableUrl } | Where-Object { $_ } | Sort-Object -Unique)
        if ($combination.Count -eq 3) { [void]$recentCombinations.Add(($combination -join '|')) }
        foreach ($url in $combination) {
            if (-not $usage.ContainsKey($url)) { $usage[$url] = 0 }
            $usage[$url]++
        }
    }

    $candidates = New-Object 'System.Collections.Generic.List[object]'
    $seenUrls = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seenTitles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($post in $normalized) {
        if ($post.Published -lt $cutoff -or $post.Published -ge $ScheduledAt) { continue }
        if ($currentIdentity -and $post.ComparableUrl -eq $currentIdentity.ComparableUrl) { continue }
        if (-not $seenUrls.Add($post.ComparableUrl) -or -not $seenTitles.Add($post.Title)) { continue }

        $candidateTitleTerms = @(Get-RelatedKeywords $post.Title)
        $candidateLabelTerms = @(Get-RelatedKeywords (@($post.Labels) -join ' '))
        $candidateBodyTerms = @(Get-RelatedKeywords $post.Content)
        $titleMatches = @(Get-RelatedKeywordMatches $titleTerms $candidateTitleTerms)
        $tagMatches = @(Get-RelatedKeywordMatches @($labelTerms + $titleTerms | Select-Object -Unique) $candidateLabelTerms)
        $bodyMatches = @(Get-RelatedKeywordMatches $allTerms $candidateBodyTerms)
        $passes = ($titleMatches.Count -ge 2) -or
            ($titleMatches.Count -ge 1 -and $tagMatches.Count -ge 1) -or
            ($titleMatches.Count -ge 1 -and $bodyMatches.Count -ge 2) -or
            ($tagMatches.Count -ge 2 -and $bodyMatches.Count -ge 2)
        if (-not $passes) { continue }

        $baseScore = ($titleMatches.Count * $TitleMatchPoints) + ($tagMatches.Count * $LabelMatchPoints) + ([Math]::Min($bodyMatches.Count,$MaximumBodyMatches) * $BodyMatchPoints)
        $repeatCount = if ($usage.ContainsKey($post.ComparableUrl)) { [int]$usage[$post.ComparableUrl] } else { 0 }
        $adjustedScore = $baseScore - [Math]::Min($repeatCount * $RepeatPenaltyPoints,$MaximumRepeatPenalty)
        $candidates.Add([pscustomobject]@{
            Title=$post.Title; Url=$post.Url; ComparableUrl=$post.ComparableUrl; Published=$post.Published
            TitleMatches=$titleMatches.Count; TagMatches=$tagMatches.Count; BodyMatches=$bodyMatches.Count
            BaseScore=$baseScore; RepeatCount=$repeatCount; AdjustedScore=$adjustedScore
        })
    }

    $ordered = @($candidates.ToArray() | Sort-Object @{Expression='AdjustedScore';Descending=$true},@{Expression='BaseScore';Descending=$true},@{Expression='Published';Descending=$true})
    $selected = @($ordered | Select-Object -First $Maximum)
    if ($selected.Count -eq 3) {
        $key = (@($selected.ComparableUrl | Sort-Object) -join '|')
        if ($recentCombinations.Contains($key)) {
            $lowest = @($selected | Sort-Object @{Expression='AdjustedScore';Descending=$false},@{Expression='BaseScore';Descending=$false} | Select-Object -First 1)[0]
            $threshold = [Math]::Max($ReplacementMinimumScore,[Math]::Ceiling($lowest.BaseScore * $ReplacementMinimumRatio))
            $selectedUrls = @($selected.ComparableUrl)
            $replacement = @($ordered | Where-Object { $selectedUrls -notcontains $_.ComparableUrl -and $_.BaseScore -ge $threshold } | Select-Object -First 1)
            if ($replacement.Count) {
                $selected = @($selected | Where-Object { $_.ComparableUrl -ne $lowest.ComparableUrl }) + @($replacement[0])
                $selected = @($selected | Sort-Object @{Expression='AdjustedScore';Descending=$true},@{Expression='BaseScore';Descending=$true},@{Expression='Published';Descending=$true})
            }
        }
    }
    return @($selected)
}

function Set-NaverRelatedPostsHtml([string]$Html, [object[]]$RelatedPosts) {
    $result = [regex]::Replace($Html, '(?is)\s*<div\b(?=[^>]*\bdata-blog-related\s*=\s*["'']true["''])[^>]*>[\s\S]*?</div>', '')
    if (-not $RelatedPosts -or $RelatedPosts.Count -eq 0) { return $result }
    $lines = foreach ($post in @($RelatedPosts | Select-Object -First 3)) {
        $title = [Net.WebUtility]::HtmlEncode([string]$post.Title)
        $url = [Net.WebUtility]::HtmlEncode([string]$post.Url)
        '<p style="margin:0 0 4px;font-size:14px;font-weight:400;"><a href="{0}">{1}</a></p>' -f $url,$title
    }
    $block = '<div data-blog-related="true" style="margin:6px 0 0 0;background:transparent;"><p style="margin:0 0 6px;font-size:14px;font-weight:700;">관련 글</p>{0}</div>' -f ($lines -join '')
    $source = [regex]::Match($result, '(?is)<div\b(?=[^>]*\bdata-blog-sources\s*=\s*["'']true["''])[^>]*>[\s\S]*?</div>')
    if (-not $source.Success) { return $result }
    return $result.Insert($source.Index + $source.Length,$block)
}

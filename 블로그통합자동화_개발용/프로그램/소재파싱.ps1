# 출력 장식과 기사 검증을 분리합니다. 네트워크 수집이나 파일 쓰기는 하지 않습니다.
$script:ArticleSites = @{
    'techcrunch.com'='TechCrunch'; 'theverge.com'='The Verge'
    'electrek.co'='Electrek'; 'powermag.com'='POWER Magazine'
    'cleantechnica.com'='CleanTechnica'; 'canarymedia.com'='Canary Media'
    'space.com'='Space.com'; 'spacenews.com'='SpaceNews'
}

function Get-ResponseUrls([string]$text) {
    # 링크 표시 문구는 URL 근거로 사용하지 않고 실제 링크 목적지만 읽습니다.
    $text = [regex]::Replace($text, '\[[^\]\r\n]*\]\(\s*(https?://[^\s]+?)\s*\)', '$1')
    $urls = foreach ($m in [regex]::Matches($text, 'https?://[^\s<>\[\]"`]+')) {
        $value = $m.Value.TrimEnd('.', ',', ';', ':', '*')
        while ($value.EndsWith(')') -and ([regex]::Matches($value,'\)').Count -gt [regex]::Matches($value,'\(').Count)) {
            $value = $value.Substring(0,$value.Length-1)
        }
        $value
    }
    return @($urls | Select-Object -Unique)
}

function Get-ArticleSite([string]$url) {
    $uri = $null
    if (-not [uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri)) { return $null }
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or -not $uri.IsDefaultPort -or $uri.Query -or $uri.Fragment) { return $null }
    $siteHost = $uri.DnsSafeHost.ToLowerInvariant() -replace '^www\.', ''
    if (-not $script:ArticleSites.ContainsKey($siteHost)) { return $null }
    $path = [uri]::UnescapeDataString($uri.AbsolutePath).Trim('/')
    if (-not $path -or $path -match '(?i)(^|/)(category|categories|tag|tags|author|authors|search|feed|about|contact|newsletter|topics|topic|page|latest|events?|issues|white-papers|partner-content|press-releases|power-awards|publications|podcasts|webinars)(/|$)' -or $path -match '(?i)\.(xml|jpg|jpeg|png|webp|gif|pdf|css|js)$') { return $null }
    $articlePath = switch ($siteHost) {
        { $_ -in @('techcrunch.com','electrek.co','cleantechnica.com') } { $path -match '^\d{4}/\d{2}/\d{2}/[^/]+$'; break }
        'theverge.com' { $path -match '^(?:[^/]+/)*\d{5,}/[^/]+$' -or $path -match '^\d{4}/\d{1,2}/\d{1,2}/(?:\d+/)?[^/]+$'; break }
        'canarymedia.com' { $path -match '^articles/[^/]+/[^/]+$'; break }
        'powermag.com' { $path -notmatch '/' -and [regex]::Matches($path,'-').Count -ge 4; break }
        'spacenews.com' { $path -notmatch '/' -and $path.Contains('-'); break }
        'space.com' {
            $leaf=($path -split '/')[-1]
            ($path.Contains('/') -and [regex]::Matches($leaf,'-').Count -ge 3) -or $path -match '^\d+-[^/]+\.html$'
            break
        }
        default { $false }
    }
    if (-not $articlePath) { return $null }
    return $script:ArticleSites[$siteHost]
}

function Get-Candidates([string]$response) {
    $items = New-Object System.Collections.ArrayList
    # 번호, 제목, 필드를 먼저 구분하고 각 블록을 독립적으로 검증합니다.
    $lines = @($response.Replace("`r`n","`n").Replace("`r","`n") -split "`n" | ForEach-Object {
        (($_.Trim() -replace '^#{1,6}\s+','') -replace '\*\*','')
    })
    $headers = @()
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(?<number>\d{1,2})(?:번\s*[.)．:]?|[.)．])\s+(?<title>\S.*)$') {
            $headers += [pscustomobject]@{Index=$i;Number=[int]$matches.number;Title=$matches.title}
        }
    }
    for ($h=0; $h -lt $headers.Count; $h++) {
        $header = $headers[$h]
        if ($header.Number -lt 1 -or @($headers | Where-Object Number -eq $header.Number).Count -ne 1) { continue }
        $end = if ($h+1 -lt $headers.Count) { $headers[$h+1].Index } else { $lines.Count }
        $fields = @{}
        $summary = New-Object System.Collections.Generic.List[string]
        $inSummary = $false
        $invalid = $false
        for ($i=$header.Index+1; $i -lt $end; $i++) {
            $value = $lines[$i] -replace '^[-*]\s+', ''
            if ($value -match '^(사이트명?|게시일|URL|최종 원문 URL|원문 URL|선정 이유|주요 내용)\s*[:：]\s*(.*)$') {
                $key=$matches[1]; $fieldValue=$matches[2].Trim()
                if ($key -eq '사이트명') { $key='사이트' }
                if ($key -in @('최종 원문 URL','원문 URL')) { $key='URL' }
                if ($key -eq '주요 내용') {
                    $inSummary=$true
                    if ($fieldValue) { $summary.Add($fieldValue) }
                } else {
                    $inSummary=$false
                    if ($fields.ContainsKey($key)) { $invalid=$true }
                    $fields[$key]=$fieldValue
                }
                continue
            }
            if ($inSummary) {
                if (-not $value -and $summary.Count -gt 0) { $inSummary=$false; continue }
                if (-not $value) { continue }
                if ($value -match '^(확보 결과|미확보|검색 결과|검증 결과|총\s*\d+|SpaceNews|TechCrunch|The Verge|Electrek|POWER Magazine|CleanTechnica|Canary Media|Space\.com)(\s|:|$)') { $inSummary=$false; continue }
                $summary.Add($value)
            }
        }
        if ($invalid -or -not $fields['사이트'] -or -not $fields['게시일'] -or -not $fields['선정 이유']) { continue }
        if ($summary.Count -lt 2 -or $summary.Count -gt 3 -or @($summary | Where-Object { $_ -notmatch '[가-힣]' }).Count -gt 0) { continue }
        if ($fields['게시일'] -ne '게시일 확인 불가') {
            $date=[datetime]::MinValue
            if (-not [datetime]::TryParseExact($fields['게시일'],'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)) { continue }
        }
        # 명시된 URL 필드가 있으면 그것을 사용합니다. 잘못된 필드를 제목 URL로 대체하지 않습니다.
        $urlText = if ($fields.ContainsKey('URL')) { $fields['URL'] } else { $header.Title }
        $urls = @(Get-ResponseUrls $urlText)
        if ($urls.Count -ne 1) { continue }
        $site = Get-ArticleSite $urls[0]
        if (-not $site -or $fields['사이트'] -ne $site) { continue }
        $title = [regex]::Replace($header.Title,'\[([^\]]+)\]\(https?://[^\s]+\)', '$1')
        foreach ($url in @(Get-ResponseUrls $title)) { $title=$title.Replace($url,'') }
        $title=$title.Trim(' ', '-', '|', '(', ')', '<', '>', '`')
        if (-not $title) { continue }
        $item = [pscustomobject]@{
            Number=$header.Number; Title=$title; Site=$site; Date=$fields['게시일']
            Url=([uri]$urls[0]).AbsoluteUri; Reason=$fields['선정 이유']; Summary=@($summary.ToArray()); Details=''
        }
        $item.Details=Format-CandidateList @($item)
        [void]$items.Add($item)
    }
    return @($items.ToArray())
}

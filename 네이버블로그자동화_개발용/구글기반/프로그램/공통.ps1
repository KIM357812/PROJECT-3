$script:Root = Split-Path $PSScriptRoot -Parent
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:RuntimeRoot = if ($env:NAVER_AUTOMATION_RUNTIME_ROOT) { [IO.Path]::GetFullPath($env:NAVER_AUTOMATION_RUNTIME_ROOT) } else { $script:Root }
$script:PromptDir = Join-Path $script:Root '프롬프트'
$script:PendingDir = Join-Path $script:RuntimeRoot '작업대기'
$script:CompleteDir = Join-Path $script:RuntimeRoot '작업완료'
$script:BackupDir = Join-Path $script:RuntimeRoot '백업'
$script:TemporaryDir = Join-Path ([IO.Path]::GetTempPath()) 'SOLIDB_ImageTemp'
$script:LogPath = Join-Path $script:RuntimeRoot '기록\오류기록.txt'
$script:ConfigPath = Join-Path $script:Root '설정.json'
$script:Config = if ([IO.File]::Exists($script:ConfigPath)) {
    [IO.File]::ReadAllText($script:ConfigPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
} else { [pscustomobject]@{} }
$script:CodexModel = if ($env:BLOG_AUTOMATION_CODEX_MODEL) { $env:BLOG_AUTOMATION_CODEX_MODEL } elseif ($script:Config.CodexModel) { [string]$script:Config.CodexModel } else { 'gpt-5.6-sol' }
$script:MaximumCandidates = if ($script:Config.MaximumCandidates) { [int]$script:Config.MaximumCandidates } else { 16 }
$script:MaximumCandidatesPerSite = if ($script:Config.MaximumCandidatesPerSite) { [int]$script:Config.MaximumCandidatesPerSite } else { 2 }
$script:BlogUrl = if ($script:Config.BlogUrl) { ([string]$script:Config.BlogUrl).TrimEnd('/')+'/' } else { '' }
$script:ExistingPostMaximum = if ($script:Config.ExistingPostMaximum) { [int]$script:Config.ExistingPostMaximum } else { 150 }
$script:ImageMaximumPixels = if ($script:Config.ImageMaximumPixels) { [int]$script:Config.ImageMaximumPixels } else { 1600 }
$script:ImageWebpQuality = if ($script:Config.ImageWebpQuality) { [double]$script:Config.ImageWebpQuality } else { 0.86 }
$script:BackupOriginalImages = if ($null -ne $script:Config.BackupOriginalImages) { [bool]$script:Config.BackupOriginalImages } else { $true }
$script:ExistingPostsLoaded = $false
$script:ExistingPostsCache = @()

foreach ($requiredDirectory in @($script:PromptDir,$script:PendingDir,$script:CompleteDir,$script:BackupDir,$script:TemporaryDir,(Split-Path $script:LogPath -Parent))) {
    [IO.Directory]::CreateDirectory($requiredDirectory) | Out-Null
}

function Write-ErrorLog([string]$message) {
    $line = '[{0}] {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message, [Environment]::NewLine
    [IO.File]::AppendAllText($script:LogPath, $line, $script:Utf8)
}

function New-RunDirectory([string]$prefix) {
    $path = Join-Path $script:PendingDir ($prefix + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

function Write-JsonAtomic([string]$path,[object]$value,[int]$depth=10) {
    $parent = Split-Path $path -Parent
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = $path + '.tmp.' + [Guid]::NewGuid().ToString('N')
    $replaceBackup = $path + '.replace.' + [Guid]::NewGuid().ToString('N')
    try {
        $json = $value | ConvertTo-Json -Depth $depth
        [IO.File]::WriteAllText($temporary,$json,$script:Utf8)
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temporary,$path,$replaceBackup); [IO.File]::Delete($replaceBackup) }
        else { [IO.File]::Move($temporary,$path) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($replaceBackup)) { [IO.File]::Delete($replaceBackup) }
    }
}

function Save-RunState([string]$run,[object]$state) {
    $state.UpdatedAt = (Get-Date).ToString('o')
    Write-JsonAtomic (Join-Path $run '작업상태.json') $state 12
}

function Read-RunState([string]$run) {
    $path = Join-Path $run '작업상태.json'
    if (-not [IO.File]::Exists($path)) { throw "작업상태 파일을 찾지 못했습니다: $path" }
    return [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Test-ProgramEnvironment([switch]$RequireBrowser) {
    $checks = New-Object System.Collections.Generic.List[object]
    $add = {
        param($name,$ok,$detail)
        $checks.Add([pscustomobject]@{ Name=$name; Ok=[bool]$ok; Detail=[string]$detail })
    }
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    & $add 'Codex CLI' ($null -ne $codex) $(if($codex){$codex.Source}else{'설치 또는 PATH 등록 필요'})
    & $add '모델 설정' (-not [string]::IsNullOrWhiteSpace($script:CodexModel)) $script:CodexModel
    foreach ($prompt in @('01_소재_URL_프롬프트.md','02_최종_글쓰기_프롬프트.md','03_이미지_생성_프롬프트.md')) {
        $path = Join-Path $script:PromptDir $prompt
        & $add ("프롬프트: $prompt") ([IO.File]::Exists($path)) $path
    }
    foreach ($directory in @($script:PendingDir,$script:CompleteDir,$script:BackupDir,$script:TemporaryDir)) {
        & $add ("폴더: "+(Split-Path $directory -Leaf)) ([IO.Directory]::Exists($directory)) $directory
    }
    if ($RequireBrowser) {
        try { $browser = Get-ChromePath; & $add '이미지 변환 브라우저' $true $browser }
        catch { & $add '이미지 변환 브라우저' $false $_.Exception.Message }
    }
    return @($checks.ToArray())
}

function Assert-ProgramEnvironment([switch]$RequireBrowser) {
    $checks = @(Test-ProgramEnvironment -RequireBrowser:$RequireBrowser)
    $failed = @($checks | Where-Object { -not $_.Ok })
    if ($failed.Count) { throw ('실행 전 점검 실패: '+(($failed | ForEach-Object { $_.Name+': '+$_.Detail }) -join ' / ')) }
    return $checks
}

function Get-SafeName([string]$value) {
    $name = [regex]::Replace($value, '[<>:"/\\|?*\x00-\x1F]', '')
    $name = [regex]::Replace($name, '\s+', ' ').Trim(' ', '.')
    if ($name.Length -gt 60) { $name = $name.Substring(0,60).Trim(' ', '.') }
    if (-not $name -or $name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { return '제목없음' }
    return $name
}

. (Join-Path $PSScriptRoot '소재파싱.ps1')

function Format-CandidateList([object[]]$candidates) {
    $blocks = foreach ($item in $candidates) {
        @(
            ('{0}번. {1}' -f $item.Number,$item.Title)
            ('사이트: {0}' -f $item.Site)
            ('게시일: {0}' -f $item.Date)
            ('URL: {0}' -f $item.Url)
            ('선정 이유: {0}' -f $item.Reason)
            '주요 내용:'
            $item.Summary
        ) -join "`n"
    }
    return ($blocks -join "`n`n")
}

function Resolve-SelectionInput([string]$inputText) {
    $original = if ($null -eq $inputText) { '' } else { $inputText }
    $normalized = $original.Trim() -replace '[;；，、]', ','
    $normalized = $normalized -replace '\s+', ','
    $normalized = $normalized -replace ',+', ','
    $normalized = $normalized.TrimEnd(' ', ',', '.', ':')
    if ($normalized -match '^\d+(\s*,\s*\d+)*$') {
        return [PSCustomObject]@{ Selection=$normalized; RemovedText='' }
    }
    $trailing = [regex]::Match($normalized,'(?<!\d)(?<selection>\d+(?:\s*,\s*\d+)*)\s*$')
    if (-not $trailing.Success) { throw '번호는 1 또는 2,4,7처럼 입력하세요.' }
    $removed = $normalized.Substring(0,$trailing.Index).Trim()
    return [PSCustomObject]@{ Selection=$trailing.Groups['selection'].Value; RemovedText=$removed }
}

function Get-Selection([string]$inputText, [object[]]$candidates) {
    $resolved = Resolve-SelectionInput $inputText
    $numbers = @($resolved.Selection -split ',' | ForEach-Object { [int]$_.Trim() } | Select-Object -Unique)
    if ($numbers.Count -lt 1 -or $numbers.Count -gt 3) { throw '작성할 기사 번호는 1개부터 3개까지만 선택할 수 있습니다.' }
    $lookup = @{}
    foreach ($candidate in $candidates) { $lookup[[int]$candidate.Number] = $candidate }
    $selected = New-Object System.Collections.ArrayList
    foreach ($number in $numbers) {
        if (-not $lookup.ContainsKey($number)) { throw '목록에 없는 번호가 포함되어 있습니다.' }
        [void]$selected.Add($lookup[$number])
    }
    return @($selected.ToArray())
}

function Read-CandidateSelection([object[]]$candidates) {
    while ($true) {
        $inputText = Read-Host '작성할 기사 번호 1~3개를 입력하세요 (예: 1 또는 2,4,7 / 취소: Q)'
        if ($null -eq $inputText) { throw '번호 입력이 종료되었습니다.' }
        if ($inputText.Trim() -in @('q','Q','취소','종료')) { return @() }
        try {
            $resolved = Resolve-SelectionInput $inputText
            if ($resolved.RemovedText) {
                Write-Host ("앞에 섞인 문자 '{0}'는 제외하고 번호 {1}을 사용합니다." -f $resolved.RemovedText,$resolved.Selection) -ForegroundColor Yellow
            }
            return @(Get-Selection $resolved.Selection $candidates)
        } catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host '소재 목록은 그대로 유지됩니다. 번호만 다시 입력하세요.' -ForegroundColor Yellow
        }
    }
}

function Get-ImageSections([string]$imagePart) {
    # 글쓰기 응답은 "1. 제목" 또는 "### 1. 제목" 형식으로 올 수 있다.
    # 검증과 파일 생성을 같은 분리 규칙으로 처리한다.
    $headings = [regex]::Matches($imagePart,'(?m)^[ \t]*(?:#{1,4}[ \t]*)?(?<number>[1-4])[\.)][ \t]+[^\r\n]+[ \t]*$')
    if ($headings.Count -ne 4) { throw '이미지 프롬프트가 정확히 4개로 분리되지 않았습니다.' }
    $fileNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $requiredPromptTerms = @('photorealistic','realistic editorial photography','natural lighting','high detail','professional composition','textless','no text','no letters','no numbers','no watermark','no AI-generated logos')
    for ($i = 0; $i -lt 4; $i++) {
        $number = [int]$headings[$i].Groups['number'].Value
        if ($number -ne ($i + 1)) { throw '이미지 프롬프트 번호가 1~4 순서가 아닙니다.' }
        $end = if ($i -lt 3) { $headings[$i + 1].Index } else { $imagePart.Length }
        $section = $imagePart.Substring($headings[$i].Index, $end - $headings[$i].Index).Trim()
        foreach ($field in @('삽입 위치·역할','간략한 한글 장면 설명','핵심 시각 요소','권장 파일명','상세 영문 프롬프트','금지 요소')) {
            if ([regex]::Matches($section,('(?m)^[ \t]*-[ \t]*'+[regex]::Escape($field)+'[ \t]*:')).Count -ne 1) {
                throw ("{0}번 이미지에 {1} 항목이 정확히 1개 있어야 합니다." -f $number,$field)
            }
        }
        $fileName = [regex]::Match($section,'(?m)^[ \t]*-[ \t]*권장 파일명[ \t]*:[ \t]*(?<value>[^\r\n]+)').Groups['value'].Value.Trim()
        if ($fileName -notmatch ('^{0:D2}-[a-z0-9]+(?:-[a-z0-9]+)*\.webp$' -f $number)) { throw ("{0}번 권장 파일명은 {0:D2}-로 시작하는 영문 소문자·숫자·하이픈 WebP 형식이어야 합니다." -f $number) }
        if (-not $fileNames.Add($fileName)) { throw "이미지 권장 파일명이 중복되었습니다: $fileName" }
        $englishPrompt = [regex]::Match($section,'(?m)^[ \t]*-[ \t]*상세 영문 프롬프트[ \t]*:[ \t]*(?<value>[^\r\n]+)').Groups['value'].Value
        foreach ($term in $requiredPromptTerms) {
            if ($englishPrompt.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -lt 0) { throw ("{0}번 상세 영문 프롬프트에 필수 문구가 없습니다: {1}" -f $number,$term) }
        }
        [PSCustomObject]@{ Number=$number; FileName=$fileName; Text=$section }
    }
}

function Get-ComparableUrl([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    try {
        $uri = New-Object Uri($value.Trim())
        if ($uri.Scheme -notin @('http','https')) { return '' }
        $builder = New-Object UriBuilder($uri)
        $builder.Fragment = ''
        return $builder.Uri.AbsoluteUri.TrimEnd('/').ToLowerInvariant()
    } catch { return '' }
}

function Get-PlainText([string]$html) {
    $value = [regex]::Replace($html,'(?is)<(?:script|style)\b[^>]*>.*?</(?:script|style)>',' ')
    $value = [regex]::Replace($value,'(?is)<[^>]+>',' ')
    $value = [Net.WebUtility]::HtmlDecode($value)
    return [regex]::Replace($value,'\s+',' ').Trim()
}

function Get-ArticleVisibleText([string]$html) {
    $value = [regex]::Replace($html,'(?is)<div\b(?=[^>]*\bdata-blog-(?:sources|related)\s*=)[^>]*>.*?</div>',' ')
    return Get-PlainText $value
}

function Get-ExistingPosts {
    if ($script:ExistingPostsLoaded) { return @($script:ExistingPostsCache) }
    $script:ExistingPostsLoaded = $true
    if ([string]::IsNullOrWhiteSpace($script:BlogUrl)) { return @() }
    try {
        $feedUrl = $script:BlogUrl.TrimEnd('/') + '/feeds/posts/default?alt=json&max-results=' + $script:ExistingPostMaximum
        $feed = Invoke-RestMethod -Uri $feedUrl -Method Get -TimeoutSec 20
        $posts = New-Object System.Collections.Generic.List[object]
        foreach ($entry in @($feed.feed.entry)) {
            $alternate = @($entry.link | Where-Object { $_.rel -eq 'alternate' } | Select-Object -First 1)
            if (-not $alternate.Count) { continue }
            $title = [string]$entry.title.'$t'
            $url = [string]$alternate[0].href
            if ($title -and (Get-ComparableUrl $url)) {
                $posts.Add([pscustomobject]@{ Title=$title.Trim(); Url=$url; Published=[string]$entry.published.'$t' })
            }
        }
        $script:ExistingPostsCache = @($posts.ToArray())
        return @($script:ExistingPostsCache)
    } catch {
        Write-ErrorLog ('기존 게시글 공개 피드 확인 실패: '+$_.Exception.Message)
        return @()
    }
}

function Format-ExistingPostContext([object[]]$posts) {
    if (-not $posts -or $posts.Count -eq 0) {
        return "# 기존 게시글 목록`n공개 피드를 확인하지 못했거나 기존 글이 없습니다. 관련 글 영역은 만들지 마십시오."
    }
    $lines = foreach ($post in $posts) { '- ' + $post.Title + ' | ' + $post.Url }
    return "# 기존 게시글 목록`n아래 목록으로 동일 사건 중복 여부를 점검하고, 실제 관련 글만 0~3개 연결하십시오.`n" + ($lines -join "`n")
}

function ConvertTo-TableLabel([string]$value) {
    $plain = [regex]::Replace([string]$value,'(?is)<[^>]+>',' ')
    $plain = [Net.WebUtility]::HtmlDecode($plain)
    return ([regex]::Replace($plain,'\s+',' ').Trim())
}

function ConvertTo-HtmlAttributeValue([string]$value) {
    return [Net.WebUtility]::HtmlEncode([string]$value).Replace("'",'&#39;')
}

function Get-ResponsiveTableBlocks([string]$html) {
    return @([regex]::Matches(
        [string]$html,
        '(?is)<div\b(?=[^>]*\bclass\s*=\s*["''][^"'']*\bsolidb-responsive-table\b[^"'']*["''])[^>]*>\s*<table\b[^>]*>[\s\S]*?</table>\s*</div>'
    ))
}

function Repair-ResponsiveTableDataLabels([string]$html) {
    $blocks = @(Get-ResponsiveTableBlocks $html)
    for ($blockIndex = $blocks.Count - 1; $blockIndex -ge 0; $blockIndex--) {
        $block = $blocks[$blockIndex]
        $tableHtml = $block.Value
        $headerRow = [regex]::Match($tableHtml,'(?is)<thead\b[^>]*>[\s\S]*?<tr\b[^>]*>(?<cells>[\s\S]*?)</tr>[\s\S]*?</thead>')
        if (-not $headerRow.Success) { throw '반응형 데이터 표의 열 제목 행을 찾을 수 없습니다.' }
        $headers = @([regex]::Matches($headerRow.Groups['cells'].Value,'(?is)<th\b[^>]*>(?<content>[\s\S]*?)</th>'))
        if ($headers.Count -lt 1) { throw '반응형 데이터 표에 열 제목이 없습니다.' }
        $labels = @($headers | ForEach-Object { ConvertTo-TableLabel $_.Groups['content'].Value })
        if (@($labels | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw '반응형 데이터 표에 비어 있는 열 제목이 있습니다.' }

        $body = [regex]::Match($tableHtml,'(?is)<tbody\b[^>]*>(?<rows>[\s\S]*?)</tbody>')
        $rowsHtml = $body.Groups['rows'].Value
        $rows = @([regex]::Matches($rowsHtml,'(?is)<tr\b[^>]*>[\s\S]*?</tr>'))
        if ($rows.Count -lt 1) { throw '반응형 데이터 표에 내용 행이 없습니다.' }
        for ($rowIndex = $rows.Count - 1; $rowIndex -ge 0; $rowIndex--) {
            $row = $rows[$rowIndex]
            $rowHtml = $row.Value
            $cells = @([regex]::Matches($rowHtml,'(?is)<td\b(?<attrs>[^>]*)>'))
            if ($cells.Count -ne $labels.Count) {
                throw ('반응형 데이터 표의 열 제목 수({0})와 {1}번째 내용 행의 셀 수({2})가 다릅니다.' -f $labels.Count,($rowIndex + 1),$cells.Count)
            }
            for ($cellIndex = $cells.Count - 1; $cellIndex -ge 0; $cellIndex--) {
                $cell = $cells[$cellIndex]
                $attrs = [regex]::Replace($cell.Groups['attrs'].Value,'(?is)\s*\bdata-label\s*=\s*(?:"[^"]*"|''[^'']*'')','').Trim()
                $open = '<td' + $(if ($attrs) { ' ' + $attrs } else { '' }) + ' data-label="' + (ConvertTo-HtmlAttributeValue $labels[$cellIndex]) + '">'
                $rowHtml = $rowHtml.Substring(0,$cell.Index) + $open + $rowHtml.Substring($cell.Index + $cell.Length)
            }
            $rowsHtml = $rowsHtml.Substring(0,$row.Index) + $rowHtml + $rowsHtml.Substring($row.Index + $row.Length)
        }
        $tableHtml = $tableHtml.Substring(0,$body.Groups['rows'].Index) + $rowsHtml + $tableHtml.Substring($body.Groups['rows'].Index + $body.Groups['rows'].Length)
        $html = $html.Substring(0,$block.Index) + $tableHtml + $html.Substring($block.Index + $block.Length)
    }
    return $html
}

function Assert-ResponsiveTableDataLabels([string]$html) {
    $blocks = @(Get-ResponsiveTableBlocks $html)
    $dataTableCount = @([regex]::Matches([string]$html,'(?is)<table\b[^>]*>[\s\S]*?</table>') | Where-Object { $_.Value -match '(?is)<thead\b' }).Count
    if ($dataTableCount -gt $blocks.Count) { throw '데이터 표에는 모바일 세로형 변환 영역이 필요합니다.' }
    if ($blocks.Count -eq 0) { return }
    if ($html -notmatch '(?is)@media\s*\(max-width\s*:\s*600px\)[\s\S]*?\.solidb-responsive-table\s+td::before[\s\S]*?attr\(data-label\)') { throw '데이터 표의 모바일 세로형 스타일이 없습니다.' }

    foreach ($block in $blocks) {
        $headerRow = [regex]::Match($block.Value,'(?is)<thead\b[^>]*>[\s\S]*?<tr\b[^>]*>(?<cells>[\s\S]*?)</tr>[\s\S]*?</thead>')
        $headers = @([regex]::Matches($headerRow.Groups['cells'].Value,'(?is)<th\b[^>]*>(?<content>[\s\S]*?)</th>'))
        if ($headers.Count -lt 1) { throw '반응형 데이터 표에 열 제목이 없습니다.' }
        $labels = @($headers | ForEach-Object { ConvertTo-TableLabel $_.Groups['content'].Value })
        $body = [regex]::Match($block.Value,'(?is)<tbody\b[^>]*>(?<rows>[\s\S]*?)</tbody>')
        $rows = @([regex]::Matches($body.Groups['rows'].Value,'(?is)<tr\b[^>]*>(?<cells>[\s\S]*?)</tr>'))
        if ($rows.Count -lt 1) { throw '반응형 데이터 표에 내용 행이 없습니다.' }
        for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) {
            $cells = @([regex]::Matches($rows[$rowIndex].Groups['cells'].Value,'(?is)<td\b(?<attrs>[^>]*)>'))
            if ($cells.Count -ne $labels.Count) { throw '반응형 데이터 표의 열 제목과 내용 셀 개수가 일치하지 않습니다.' }
            for ($cellIndex = 0; $cellIndex -lt $cells.Count; $cellIndex++) {
                $labelMatch = [regex]::Match($cells[$cellIndex].Groups['attrs'].Value,'(?is)\bdata-label\s*=\s*["''](?<value>[^"'']+)["'']')
                $actual = if ($labelMatch.Success) { [Net.WebUtility]::HtmlDecode($labelMatch.Groups['value'].Value).Trim() } else { '' }
                if ($actual -ne $labels[$cellIndex]) { throw '모바일 표의 각 셀에는 순서가 일치하는 해당 열 제목 data-label이 필요합니다.' }
            }
        }
    }
}

function Set-DataBlogDivStyle([string]$html,[string]$role,[hashtable]$required,[string[]]$remove=@()) {
    $match = [regex]::Match($html,('(?is)<div\b(?=[^>]*\bdata-blog-{0}\s*=\s*["'']true["''])(?<attrs>[^>]*)>' -f [regex]::Escape($role)))
    if (-not $match.Success) { return $html }
    $attrs = $match.Groups['attrs'].Value
    $styleMatch = [regex]::Match($attrs,'(?is)\bstyle\s*=\s*["''](?<value>[^"'']*)["'']')
    $declarations = New-Object System.Collections.Generic.List[string]
    $removeNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($remove) + @($required.Keys)) { [void]$removeNames.Add(([string]$name).Trim()) }
    if ($styleMatch.Success) {
        foreach ($part in @($styleMatch.Groups['value'].Value -split ';')) {
            $item = $part.Trim()
            if (-not $item -or $item -notmatch '^(?<name>[-a-zA-Z]+)\s*:') { continue }
            if (-not $removeNames.Contains($Matches['name'])) { $declarations.Add($item) }
        }
    }
    foreach ($name in @($required.Keys | Sort-Object)) { $declarations.Add(('{0}: {1}' -f $name,[string]$required[$name])) }
    $newStyle = ($declarations -join '; ') + ';'
    if ($styleMatch.Success) {
        $attrs = $attrs.Substring(0,$styleMatch.Index) + ('style="' + $newStyle + '"') + $attrs.Substring($styleMatch.Index + $styleMatch.Length)
    } else { $attrs += (' style="' + $newStyle + '"') }
    $newTag = '<div' + $attrs + '>'
    return $html.Substring(0,$match.Index) + $newTag + $html.Substring($match.Index + $match.Length)
}

function Repair-NaverDeterministicStyles([string]$html) {
    $html = Set-DataBlogDivStyle $html 'sources' @{ 'background-color'='#f8f9fa'; 'padding'='8px 12px' } @('background','border-left')
    $html = Set-DataBlogDivStyle $html 'related' @{ 'background-color'='#eef3fb' } @('background')
    return $html
}

function Repair-SourceRelatedStructure([string]$html) {
    # The model can omit the closing tag of the sources block and place the
    # related-post block inside it.  In that case source validation sees the
    # related link as a fourth source.  Both blocks are final root children,
    # so normalize that one deterministic shape before semantic validation.
    $nestedPattern = '(?is)(?<sourceOpen><div\b(?=[^>]*\bdata-blog-sources\s*=\s*["'']true["''])[^>]*>)(?<sourceLine>\s*<p\b[^>]*>[\s\S]*?</p>)\s*(?<related><div\b(?=[^>]*\bdata-blog-related\s*=\s*["'']true["''])[^>]*>[\s\S]*?</div>)\s*</div>(?<rootClose>\s*</div>\s*)\z'
    $nested = [regex]::Match([string]$html,$nestedPattern)
    if (-not $nested.Success) { return $html }
    $replacement = $nested.Groups['sourceOpen'].Value + $nested.Groups['sourceLine'].Value + "`n</div>`n" + $nested.Groups['related'].Value + $nested.Groups['rootClose'].Value
    return $html.Substring(0,$nested.Index) + $replacement
}

function Remove-GeneratedRelatedPosts([string]$html) {
    # 관련 글은 AI가 URL을 만들지 않습니다. 네이버 패키지 단계에서 실제 공개
    # 게시물 목록을 조회한 뒤 결정적으로 다시 선정하므로 생성 응답의 선택 영역은
    # 본문 검증 전에 제거합니다. 관련 글이 없어도 본문은 정상 완성되어야 합니다.
    return [regex]::Replace(
        $html,
        '(?is)\s*<div\b(?=[^>]*\bdata-blog-related\s*=\s*["'']true["''])[^>]*>[\s\S]*?</div>(?=\s*</div>\s*\z)',
        ''
    )
}

function Split-Article([string]$response, [string]$expectedSourceSite='', [string]$expectedSourceUrl='', [string[]]$allowedRelatedUrls=@()) {
    $normalized = $response.Trim().Replace("`r`n", "`n")
    $match = [regex]::Match($normalized, '\A```html\n(?<html>[\s\S]+?)\n```\n\n(?<meta>## 1\. SEO 키워드 분석[\s\S]+)\z')
    if (-not $match.Success) { throw 'HTML 코드 블록과 일반 Markdown 메타데이터가 정확히 분리되지 않았습니다.' }
    $html = Remove-GeneratedRelatedPosts (Repair-NaverDeterministicStyles (Repair-SourceRelatedStructure (Repair-ResponsiveTableDataLabels $match.Groups['html'].Value.Trim())))
    $allMeta = $match.Groups['meta'].Value.Trim()
    $expectedSourceSite = $expectedSourceSite.Trim()
    if (-not $expectedSourceSite) { throw '선택한 소재의 출처 사이트명이 없습니다.' }
    $expectedComparableUrl = Get-ComparableUrl $expectedSourceUrl
    if (-not $expectedComparableUrl) { throw '선택한 소재의 실제 기사 URL이 없습니다.' }
    if (-not $html.EndsWith('</div>')) { throw '본문 HTML이 바깥쪽 div로 끝나지 않습니다.' }

    $outer = [regex]::Match($html,'(?is)\A\s*<div\b(?<attrs>[^>]*)>')
    if (-not $outer.Success) { throw '본문 HTML의 바깥쪽 div를 찾을 수 없습니다.' }
    $outerAttrs = $outer.Groups['attrs'].Value
    if ($outerAttrs -notmatch '(?i)width\s*:\s*100%' -or $outerAttrs -notmatch '(?i)max-width\s*:\s*800px' -or $outerAttrs -notmatch '(?i)margin\s*:\s*0(?:px)?\s+auto' -or $outerAttrs -notmatch '(?i)box-sizing\s*:\s*border-box' -or $outerAttrs -notmatch '(?i)clear\s*:\s*both') {
        throw '본문 바깥쪽 div가 Blogger 중앙 정렬·반응형 기준을 지키지 않았습니다.'
    }
    if ($html -match '(?im)^##\s+[1-6]\.' -or $html -match '(?is)글\s*설정\s*라벨.*게시\s*날짜.*퍼머링크.*검색\s*설명') { throw '본문 HTML에 메타데이터 또는 Blogger 설정 문구가 섞여 있습니다.' }

    $h2Count = [regex]::Matches($html,'(?is)<h2\b').Count
    $h3Count = [regex]::Matches($html,'(?is)<h3\b').Count
    if ($h2Count -lt 3 -or $h2Count -gt 4) { throw '본문 H2는 기사에 따라 3~4개여야 합니다.' }
    if ($h3Count -lt 2 -or $h3Count -gt 3) { throw '결론 H3는 기사에 따라 2~3개여야 합니다.' }
    foreach ($label in @('누가\s*\(Who\)','무엇을\s*\(What\)','언제\s*\(When\)','어디서\s*\(Where\)','어떻게\s*\(How\)','왜\s*\(Why\)')) {
        if ($html -notmatch $label) { throw "육하원칙 박스 항목이 없습니다: $label" }
    }
    $sixFactsOpen = [regex]::Match($html,'(?is)<div\b(?=[^>]*\bdata-blog-six-facts\s*=\s*["'']true["''])(?<attrs>[^>]*)>')
    if (-not $sixFactsOpen.Success) { throw '육하원칙 내용 영역에 모바일 양쪽 정렬 표시가 없습니다.' }
    $sixFactsAttrs = $sixFactsOpen.Groups['attrs'].Value
    if ($sixFactsAttrs -notmatch '(?i)text-align\s*:\s*justify' -or $sixFactsAttrs -notmatch '(?i)text-align-last\s*:\s*left' -or $sixFactsAttrs -notmatch '(?i)overflow-wrap\s*:\s*anywhere') {
        throw '육하원칙 내용은 양쪽 정렬, 마지막 줄 왼쪽 정렬과 긴 영문 줄바꿈 속성이 필요합니다.'
    }

    Assert-ResponsiveTableDataLabels $html

    $imageTags = @([regex]::Matches($html,'(?is)<img\b[^>]*>'))
    if ($imageTags.Count -ne 4) { throw '본문 이미지 placeholder가 4개가 아닙니다.' }
    $imageWrappers = @([regex]::Matches($html,'(?is)<div\b(?=[^>]*\bdata-blog-image-wrap\s*=\s*["'']true["''])(?<attrs>[^>]*)>'))
    if ($imageWrappers.Count -ne 4) { throw '네 이미지에는 위·아래 간격을 유지하는 부모 영역이 각각 필요합니다.' }
    foreach ($wrapper in $imageWrappers) {
        $wrapperAttrs = $wrapper.Groups['attrs'].Value
        if ($wrapperAttrs -notmatch '(?i)margin\s*:\s*28px\s+0(?:px)?\s+28px\s+0(?:px)?' -or $wrapperAttrs -notmatch '(?i)text-align\s*:\s*center') {
            throw '이미지 부모 영역은 위·아래 28px 간격과 가운데 정렬을 지켜야 합니다.'
        }
    }
    for ($i=0; $i -lt $imageTags.Count; $i++) {
        $tag = $imageTags[$i].Value
        $style = [regex]::Match($tag,'(?is)\bstyle\s*=\s*["''](?<value>[^"'']+)["'']').Groups['value'].Value
        $alt = [regex]::Match($tag,'(?is)\balt\s*=\s*["''](?<value>[^"'']+)["'']').Groups['value'].Value
        $title = [regex]::Match($tag,'(?is)\btitle\s*=\s*["''](?<value>[^"'']+)["'']').Groups['value'].Value
        if ($style -notmatch '(?i)width\s*:\s*100%' -or $style -notmatch '(?i)max-width\s*:\s*400px' -or $style -notmatch '(?i)height\s*:\s*auto' -or $style -notmatch '(?i)display\s*:\s*block' -or $style -notmatch '(?i)margin\s*:\s*0(?:px)?\s+auto') { throw '본문 이미지는 최대 400px·가운데 정렬·모바일 자동 축소 스타일을 지켜야 합니다.' }
        if (-not $alt -or $alt -ne $title) { throw '본문 이미지의 alt와 title에는 같은 장면 설명이 있어야 합니다.' }
        if ($i -eq 0) {
            if ($tag -notmatch '(?i)\bloading\s*=\s*["'']eager["'']' -or $tag -notmatch '(?i)\bfetchpriority\s*=\s*["'']high["'']') { throw '첫 번째 대표 이미지는 eager와 높은 불러오기 우선순위가 필요합니다.' }
        } elseif ($tag -notmatch '(?i)\bloading\s*=\s*["'']lazy["'']') { throw '두 번째부터 네 번째 이미지는 lazy 로딩이어야 합니다.' }
    }

    foreach ($paragraph in @([regex]::Matches($html,'(?is)<p\b(?<attrs>[^>]*)>'))) {
        $attrs = $paragraph.Groups['attrs'].Value
        if ($attrs -match '(?i)font-weight\s*:\s*400' -and $attrs -match '(?i)width\s*:\s*100%') {
            if ($attrs -notmatch '(?i)text-align\s*:\s*justify' -or $attrs -notmatch '(?i)text-align-last\s*:\s*left' -or $attrs -notmatch '(?i)overflow-wrap\s*:\s*anywhere') { throw '일반 본문은 오른쪽 끝이 맞는 양쪽 정렬, 마지막 줄 왼쪽 정렬과 긴 영문 줄바꿈 속성이 필요합니다.' }
        }
    }
    if ([regex]::Matches($html,'(?is)<strong\b').Count -ne [regex]::Matches($html,'(?is)</strong>').Count -or $html -match '(?is)<strong\b[^>]*>[^<]*(?:<p\b|<div\b|<strong\b)' -or $html -match '(?is)<b\b|\*\*') { throw '굵은 글씨 태그가 문단 경계를 넘거나 허용되지 않은 굵게 표시가 있습니다.' }

    if ($html -match '(?is)<p\b[^>]*>\s*(?:<strong>\s*)?출처\s*사이트:') { throw '기존 형식인 출처 사이트 문단은 사용할 수 없습니다.' }
    $ending = [regex]::Match($html,'(?is)<div\b(?=[^>]*\bdata-blog-sources\s*=\s*["'']true["''])[^>]*>(?<source>[\s\S]*?)</div>(?<related>\s*<div\b(?=[^>]*\bdata-blog-related\s*=\s*["'']true["''])[^>]*>(?<relatedContent>[\s\S]*?)</div>)?\s*</div>\s*\z')
    if (-not $ending.Success) { throw '질문 아래에 출처 영역이 있고 선택적으로 관련 글 영역이 이어져야 합니다.' }
    if ([regex]::Matches($html,'(?is)data-blog-sources\s*=').Count -ne 1 -or [regex]::Matches($html,'(?is)data-blog-related\s*=').Count -gt 1) { throw '출처 또는 관련 글 영역이 중복되었습니다.' }
    $beforeSource = $html.Substring(0,$ending.Index)
    $questionMatch = [regex]::Match($beforeSource,'(?is)<div\b(?=[^>]*background(?:-color)?\s*:\s*#fff3e0)[^>]*>\s*<p\b[^>]*>[\s\S]*?</p>\s*<p\b[^>]*>(?<question>[\s\S]*?)</p>\s*</div>\s*\z')
    if (-not $questionMatch.Success) { throw '출처 바로 앞에 주황색 질문 상자가 있어야 합니다.' }
    $questionText = Get-PlainText $questionMatch.Groups['question'].Value
    if ($questionText.Length -lt 45 -or $questionText.Length -gt 90 -or ([regex]::Matches($questionText,'\?').Count -ne 1) -or -not $questionText.EndsWith('?')) { throw '질문은 전체 내용을 반영한 45~90자의 한 문장이어야 하며 물음표는 끝에 하나만 있어야 합니다.' }

    $sourceBlock = $ending.Groups['source'].Value
    $sourceOpen = [regex]::Match($html,'(?is)<div\b(?=[^>]*\bdata-blog-sources\s*=\s*["'']true["''])(?<attrs>[^>]*)>')
    $sourceAttrs = $sourceOpen.Groups['attrs'].Value
    if ($sourceAttrs -notmatch '(?i)background(?:-color)?\s*:\s*#f8f9fa') { throw '출처 영역은 핵심 요약 상자와 같은 회색 배경이어야 합니다.' }
    if ($sourceAttrs -match '(?i)border-left\s*:') { throw '출처 영역에는 왼쪽 세로선을 표시하지 않습니다.' }
    if ($sourceAttrs -notmatch '(?i)padding\s*:\s*8px\s+12px') { throw '출처 영역은 한 줄 높이에 맞는 8px 12px 여백이어야 합니다.' }
    $sourceAnchors = @([regex]::Matches($sourceBlock,'(?is)<a\b[^>]*\bhref\s*=\s*["''](?<url>https?://[^"'']+)["''][^>]*>(?<text>[\s\S]*?)</a>'))
    if ($sourceAnchors.Count -lt 1 -or $sourceAnchors.Count -gt 3) { throw '출처 영역의 클릭 가능한 원문 링크는 1~3개여야 합니다.' }
    $sourceLine = [regex]::Match($sourceBlock,'(?is)<p\b(?<attrs>[^>]*)>\s*<strong\b[^>]*>\s*출처\s*:\s*</strong>\s*<a\b[^>]*>[\s\S]*?</a>(?:\s*,\s*<a\b[^>]*>[\s\S]*?</a>){0,2}\s*</p>')
    if (-not $sourceLine.Success -or [regex]::Matches($sourceLine.Value,'(?is)<a\b').Count -ne $sourceAnchors.Count) { throw '출처는 제목과 링크를 같은 줄에 두고 쉼표와 공백으로 구분해야 합니다.' }
    if ($sourceLine.Groups['attrs'].Value -notmatch '(?i)font-size\s*:\s*14px') { throw '출처 제목과 링크 글자는 14px여야 합니다.' }
    $sourceUrls = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $selectedFound = $false
    foreach ($anchor in $sourceAnchors) {
        $url = Get-ComparableUrl ([Net.WebUtility]::HtmlDecode($anchor.Groups['url'].Value))
        if (-not $url -or -not $sourceUrls.Add($url)) { throw '출처 영역에 올바르지 않거나 중복된 URL이 있습니다.' }
        $text = Get-PlainText $anchor.Groups['text'].Value
        if ([string]::IsNullOrWhiteSpace($text) -or $text.Length -gt 80 -or $text -match '(?i)https?://|www\.|/|—') { throw '출처 링크에는 URL이나 기사 제목 대신 매체명·기관명만 표시해야 합니다.' }
        if ($url -eq $expectedComparableUrl) {
            if ($text -notmatch [regex]::Escape($expectedSourceSite)) { throw ("선택 기사 출처 링크에는 사이트명이 포함되어야 합니다: {0}" -f $expectedSourceSite) }
            $selectedFound = $true
        }
    }
    if (-not $selectedFound) { throw '출처 영역에 사용자가 선택한 실제 기사 URL이 없습니다.' }
    foreach ($anchor in @([regex]::Matches($beforeSource,'(?is)<a\b[^>]*\bhref\s*=\s*["''](?<url>https?://[^"'']+)["''][^>]*>(?<text>[\s\S]*?)</a>'))) {
        $inlineUrl = Get-ComparableUrl ([Net.WebUtility]::HtmlDecode($anchor.Groups['url'].Value))
        if (-not $sourceUrls.Contains($inlineUrl)) { throw '본문 하이퍼링크 URL은 하단 출처 영역에도 반드시 표시해야 합니다.' }
        $inlineText = Get-PlainText $anchor.Groups['text'].Value
        if ([string]::IsNullOrWhiteSpace($inlineText) -or $inlineText.Length -ge 15) { throw '본문 하이퍼링크 문구는 공백을 포함해 15자 미만이어야 합니다.' }
    }

    $relatedUrls = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if ($ending.Groups['related'].Success) {
        $relatedBlock = $ending.Groups['relatedContent'].Value
        $relatedOpen = [regex]::Match($html,'(?is)<div\b(?=[^>]*\bdata-blog-related\s*=\s*["'']true["''])(?<attrs>[^>]*)>')
        if ($relatedOpen.Groups['attrs'].Value -notmatch '(?i)background(?:-color)?\s*:\s*#eef3fb') { throw '관련 글 영역은 이 글에서 다루는 내용과 같은 파란색 배경이어야 합니다.' }
        if ($relatedBlock -notmatch '(?is)<p\b[^>]*>\s*(?:<strong>\s*)?관련 글(?:\s*</strong>)?\s*</p>') { throw '내부 링크 영역의 제목은 관련 글이어야 합니다.' }
        $relatedTitle = [regex]::Match($relatedBlock,'(?is)<p\b(?<attrs>[^>]*)>\s*(?:<strong>\s*)?관련 글(?:\s*</strong>)?\s*</p>')
        if ($relatedTitle.Groups['attrs'].Value -notmatch '(?i)font-size\s*:\s*14px') { throw '관련 글 제목은 이 글에서 다루는 내용과 같은 14px여야 합니다.' }
        $relatedAnchors = @([regex]::Matches($relatedBlock,'(?is)<a\b[^>]*\bhref\s*=\s*["''](?<url>https?://[^"'']+)["''][^>]*>(?<text>[\s\S]*?)</a>'))
        if ($relatedAnchors.Count -lt 1 -or $relatedAnchors.Count -gt 3) { throw '관련 기존 글 링크는 1~3개여야 합니다.' }
        foreach ($relatedLine in @([regex]::Matches($relatedBlock,'(?is)<p\b(?<attrs>[^>]*)>\s*<a\b'))) {
            if ($relatedLine.Groups['attrs'].Value -notmatch '(?i)font-size\s*:\s*14px') { throw '관련 글 링크 글자도 14px여야 합니다.' }
        }
        $allowed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($value in @($allowedRelatedUrls)) { $normalizedUrl=Get-ComparableUrl $value; if($normalizedUrl){[void]$allowed.Add($normalizedUrl)} }
        if ($allowed.Count -eq 0) { throw '기존 게시글 공개 목록이 없으므로 관련 글 영역을 만들 수 없습니다.' }
        $blogHost = if ($script:BlogUrl) { ([uri]$script:BlogUrl).Host } else { '' }
        foreach ($anchor in $relatedAnchors) {
            $url = Get-ComparableUrl ([Net.WebUtility]::HtmlDecode($anchor.Groups['url'].Value))
            $text = Get-PlainText $anchor.Groups['text'].Value
            if (-not $url -or -not $relatedUrls.Add($url)) { throw '관련 글 URL이 올바르지 않거나 중복되었습니다.' }
            if ($blogHost -and ([uri]$url).Host -ne $blogHost) { throw '관련 글에는 현재 Blogger 내부 URL만 사용할 수 있습니다.' }
            if (-not $allowed.Contains($url)) { throw '관련 글 URL이 제공된 기존 게시글 목록에 없습니다.' }
            if (-not $text -or $text -match '(?i)https?://|www\.') { throw '관련 글 링크에는 URL이 아니라 게시글 제목을 표시해야 합니다.' }
        }
    }

    $metaHeadings = @([regex]::Matches($allMeta,'(?m)^## [1-6]\. .+$') | ForEach-Object Value)
    $expectedHeadings = @('## 1. SEO 키워드 분석','## 2. SEO 최적화 제목','## 3. 메타 디스크립션','## 4. 이미지 프롬프트 팩','## 5. 해시태그','## 6. 내부 사실검증표')
    if (($metaHeadings -join '|') -ne ($expectedHeadings -join '|')) { throw '공개 메타데이터 5개와 내부 사실검증표의 제목이나 순서가 맞지 않습니다.' }
    if ($allMeta -match '<[^>]+>') { throw '메타데이터에 HTML 태그가 들어 있습니다.' }
    $factIndex = $allMeta.IndexOf('## 6. 내부 사실검증표',[StringComparison]::Ordinal)
    $publicMeta = $allMeta.Substring(0,$factIndex).Trim()
    $factCheck = $allMeta.Substring($factIndex).Trim()

    $titleBlock = [regex]::Match($publicMeta,'(?s)## 2\. SEO 최적화 제목\n(?<content>.*?)\n## 3\. 메타 디스크립션').Groups['content'].Value
    $titleNames = @('최종 권장 제목','대체 제목 1','대체 제목 2')
    $titles = New-Object System.Collections.Generic.List[string]
    foreach ($name in $titleNames) {
        $value = [regex]::Match($titleBlock,('(?m)^'+[regex]::Escape($name)+'\s*:\s*(?<value>[^\r\n]+)$')).Groups['value'].Value.Trim()
        if (-not $value) { throw "SEO 제목 항목이 없습니다: $name" }
        $titles.Add($value)
    }
    if (@($titles | Select-Object -Unique).Count -ne 3) { throw '최종 권장 제목과 대체 제목은 서로 달라야 합니다.' }
    $visibleText = Get-ArticleVisibleText $html
    $stopWords = @('이유','분석','핵심','방법','과제','전망','새로운','어떻게','무엇','정리')
    $titleTokens = @([regex]::Matches($titles[0],'[가-힣A-Za-z0-9]{2,}') | ForEach-Object Value | Where-Object { $_ -notin $stopWords } | Select-Object -Unique)
    $matchedTokens = @($titleTokens | Where-Object { $visibleText.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
    if ($matchedTokens.Count -lt 1) { throw '최종 권장 제목이 본문 핵심 내용과 충분히 일치하지 않습니다.' }

    $description = [regex]::Match($publicMeta,'(?s)## 3\. 메타 디스크립션\n(?<content>.*?)\n## 4\. 이미지 프롬프트 팩').Groups['content'].Value.Trim()
    if ($description.Length -lt 40 -or $description.Length -gt 150 -or $description -match '[\r\n].*\S') { throw '메타 디스크립션은 한 문단의 40~150자여야 합니다.' }
    $imagePart = [regex]::Match($publicMeta,'(?s)## 4\. 이미지 프롬프트 팩\n(?<content>.*?)\n## 5\. 해시태그').Groups['content'].Value
    $prompts = @(Get-ImageSections $imagePart)
    $hashText = [regex]::Match($publicMeta,'(?s)## 5\. 해시태그\n(?<content>.*)\z').Groups['content'].Value.Trim()
    $hashtags = @($hashText -split '\s*,\s*' | Where-Object { $_ })
    if ($hashtags.Count -lt 4 -or $hashtags.Count -gt 5 -or @($hashtags | Where-Object { $_ -match '#|\s' }).Count -gt 0) { throw '해시태그는 #과 띄어쓰기 없이 쉼표로 구분한 4~5개여야 합니다.' }

    $visibleLength = $visibleText.Length
    if ($visibleLength -lt 1000 -or $visibleLength -gt 4800) { throw "화면 표시 글은 1,000~4,800자여야 합니다. 현재 $visibleLength자입니다." }
    $shortReason = [regex]::Match($factCheck,'(?m)^짧은 글 예외 사유\s*:\s*(?<value>[^\r\n]+)$').Groups['value'].Value.Trim()
    if (-not $shortReason) { throw '내부 사실검증표에 짧은 글 예외 사유가 없습니다.' }
    if ($visibleLength -lt 1300 -and ($shortReason -eq '해당 없음' -or $shortReason.Length -lt 10)) { throw '1,000~1,299자 예외 글에는 구체적인 짧은 글 사유가 필요합니다.' }
    if ($factCheck -notmatch '(?m)^기존 글 중복 점검\s*:\s*(?:중복 없음|후속 분석\s*—\s*.+)$') { throw '내부 사실검증표에 기존 글 중복 점검 결과가 없습니다.' }
    # Codex가 같은 사실검증 내용을 Markdown 소제목 또는 번호 목록으로
    # 표현할 수 있으므로 두 형식을 모두 구조화된 검증 항목으로 인정한다.
    $factItemPattern = '(?ms)^(?:###\s*검증\s+\d+\s*$|\d+\.\s*핵심 주장\s*:).*?(?=^(?:###\s*검증\s+\d+\s*$|\d+\.\s*핵심 주장\s*:)|\z)'
    $factItems = @([regex]::Matches($factCheck,$factItemPattern))
    if ($factItems.Count -lt 3) { throw '내부 사실검증표에는 검증 항목이 3개 이상 필요합니다.' }
    $factUrls = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $factItems) {
        foreach ($field in @('핵심 주장','구분','확인 URL','확인일','검증 결과','정정 내용')) {
            $fieldPattern = '(?m)^(?:\d+\.\s*)?-?[ \t]*'+[regex]::Escape($field)+'\s*:\s*\S'
            if ($item.Value -notmatch $fieldPattern) { throw "사실검증 항목에 필드가 없습니다: $field" }
        }
        $kind = [regex]::Match($item.Value,'(?m)^(?:\d+\.\s*)?-?[ \t]*구분\s*:\s*(?<value>[^\r\n]+)').Groups['value'].Value.Trim()
        if ($kind -notin @('원문 사실','보완 자료','일반 기술 배경','작성자 분석')) { throw "사실검증 구분이 올바르지 않습니다: $kind" }
        $urlText = [regex]::Match($item.Value,'(?m)^(?:\d+\.\s*)?-?[ \t]*확인 URL\s*:\s*(?<value>[^\r\n]+)').Groups['value'].Value.Trim()
        if ($kind -ne '작성자 분석') {
            $url = Get-ComparableUrl $urlText
            if (-not $url) { throw '사실·수치·날짜 검증 항목에는 실제 확인 URL이 필요합니다.' }
            [void]$factUrls.Add($url)
        } elseif ($urlText -ne '해당 없음' -and -not (Get-ComparableUrl $urlText)) { throw '작성자 분석의 확인 URL은 해당 없음 또는 실제 URL이어야 합니다.' }
        $checkedDate = [regex]::Match($item.Value,'(?m)^(?:\d+\.\s*)?-?[ \t]*확인일\s*:\s*(?<value>\d{4}-\d{2}-\d{2})\s*$').Groups['value'].Value
        if (-not $checkedDate) { throw '사실검증 확인일은 YYYY-MM-DD 형식이어야 합니다.' }
    }
    if (-not $factUrls.Contains($expectedComparableUrl)) { throw '내부 사실검증표에 선택한 원문 URL 검증 기록이 없습니다.' }

    return [PSCustomObject]@{
        Html=$html+"`n"
        Metadata=$publicMeta+"`n"
        FactCheck=$factCheck+"`n"
        ImagePrompts=$imagePart.Trim()+"`n"
        ImageFiles=@($prompts | ForEach-Object FileName)
        RecommendedTitle=$titles[0]
        VisibleTextLength=$visibleLength
    }
}

function Invoke-Codex([string]$prompt, [string]$outputPath) {
    $command = Get-Command codex -ErrorAction Stop
    if ([IO.File]::Exists($outputPath)) { throw "기존 응답 파일을 덮어쓸 수 없습니다: $outputPath" }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $command.Source
    # 콘텐츠 생성 실행은 개발 저장소의 AGENTS.md와 코딩 작업 문맥을 읽으면 안 된다.
    # 저장소 밖 전용 작업 폴더에서 매번 독립·비영속 세션으로 실행한다.
    $executionRoot = if($env:NAVER_AUTOMATION_RUNTIME_ROOT){Join-Path $env:NAVER_AUTOMATION_RUNTIME_ROOT 'codex-content-runtime'}else{Join-Path ([IO.Path]::GetTempPath()) 'solidb-content-runtime'}
    [IO.Directory]::CreateDirectory($executionRoot)|Out-Null
    # Naver uses the CLI's configured account/model instead of a hard-coded model ID.
    $modelArgument = if ($env:NAVER_AUTOMATION_RUNTIME_ROOT) { '' } else { ' --model ' + $script:CodexModel }
    $psi.Arguments = 'exec' + $modelArgument + ' --ephemeral --skip-git-repo-check --sandbox read-only -C "' + $executionRoot + '" -o "' + $outputPath + '" -'
    $psi.WorkingDirectory = $executionRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($psi)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $inputBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($prompt)
        $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
        $process.StandardInput.BaseStream.Flush()
        $process.StandardInput.Close()
        $process.WaitForExit()
        $outText = $stdout.Result
        $errText = $stderr.Result
        [IO.File]::WriteAllText(($outputPath+'.stdout.log'),$outText,$script:Utf8)
        [IO.File]::WriteAllText(($outputPath+'.stderr.log'),$errText,$script:Utf8)
        if ($process.ExitCode -ne 0 -or -not [IO.File]::Exists($outputPath)) {
            throw "Codex CLI 실패 (종료 코드 $($process.ExitCode)). 작업대기의 원문 및 CLI 로그를 확인하세요: $outputPath"
        }
        return [IO.File]::ReadAllText($outputPath,[Text.Encoding]::UTF8)
    } finally { $process.Dispose() }
}

function New-FactCheckRepairPrompt([string]$response, [string]$expectedArticleUrl) {
    return @"
아래 블로그 글 생성 응답은 내부 사실검증 항목이 3개 미만이라 프로그램 검증을 통과하지 못했습니다.
공개 본문 HTML과 ## 1~5 공개 메타데이터는 내용과 형식을 바꾸지 말고, ## 6. 내부 사실검증표만 보완한 전체 응답을 다시 출력하세요.

필수 조건:
1. 검증 항목을 최소 3개 작성합니다.
2. 각 항목은 `### 검증 1` 형식의 제목과 핵심 주장, 구분, 확인 URL, 확인일, 검증 결과, 정정 내용을 모두 포함합니다.
3. 구분은 원문 사실, 보완 자료, 일반 기술 배경, 작성자 분석 중 하나만 사용합니다.
4. 사실·수치·날짜 항목은 실제 http 또는 https 확인 URL을 사용하고, 작성자 분석만 확인 URL을 `해당 없음`으로 쓸 수 있습니다.
5. 선택한 원문 URL `$expectedArticleUrl`의 검증 기록을 반드시 포함합니다.
6. 확인하지 않은 사실이나 URL을 만들지 마세요. 근거가 부족하면 공개 자료에서 확인한 뒤 기록하세요.
7. HTML 코드 블록부터 ## 6. 내부 사실검증표까지 전체 응답을 빠짐없이 반환합니다.

--- 보완할 원래 응답 시작 ---
$response
--- 보완할 원래 응답 끝 ---
"@
}

function Resolve-ArticleWithFactCheckRepair(
    [string]$response,
    [string]$expectedSourceSite,
    [string]$expectedArticleUrl,
    [object[]]$allowedRelatedUrls=@(),
    [string]$repairOutputPath='',
    [scriptblock]$repairInvoker=$null
) {
    $factHeading = '## 6. 내부 사실검증표'
    $factErrorPattern = '내부 사실검증표|사실검증 항목|사실검증 구분|사실검증 확인일|검증 기록|확인 URL'
    $currentResponse = $response
    $originalFactIndex = $response.IndexOf($factHeading,[StringComparison]::Ordinal)
    $originalPublic = if($originalFactIndex -lt 0){$response.TrimEnd()}else{$response.Substring(0,$originalFactIndex).TrimEnd()}

    for ($attempt=0; $attempt -le 3; $attempt++) {
        try {
            return Split-Article $currentResponse $expectedSourceSite $expectedArticleUrl $allowedRelatedUrls
        } catch {
            $validationMessage = $_.Exception.Message
            if ($attempt -ge 3 -or $validationMessage -notmatch $factErrorPattern) { throw }
        }

        # Internal repair is intentionally silent.  Users only need the final
        # completed article, not an intermediate yellow progress warning.
        $repairPrompt = New-FactCheckRepairPrompt $currentResponse $expectedArticleUrl
        $attemptPath = $repairOutputPath
        if ($attempt -gt 0 -and $attemptPath) {
            $attemptPath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($attemptPath),([IO.Path]::GetFileNameWithoutExtension($attemptPath)+'_'+($attempt+1)+[IO.Path]::GetExtension($attemptPath)))
        }
        if ($null -ne $repairInvoker) {
            $repairedResponse = & $repairInvoker $repairPrompt $attemptPath
        } else {
            if (-not $attemptPath) { throw '사실검증 자동 보완 응답을 저장할 경로가 없습니다.' }
            $repairedResponse = Invoke-Codex $repairPrompt $attemptPath
        }
        $repairedFactIndex = $repairedResponse.IndexOf($factHeading,[StringComparison]::Ordinal)
        if ($repairedFactIndex -lt 0) {
            $currentResponse = $originalPublic + "`n`n" + $factHeading + "`n"
            continue
        }
        # Never accept accidental public-content edits from a repair response.
        # Take only its private fact-check section and merge it into the exact
        # original public HTML/metadata before validating again.
        $repairedFact = $repairedResponse.Substring($repairedFactIndex).Trim()
        $currentResponse = $originalPublic + "`n`n" + $repairedFact
    }
    throw '내부 사실검증표 자동 보완을 완료하지 못했습니다.'
}

function Convert-ToBloggerHtml([string]$html) {
    $result = [regex]::Replace($html,'(?is)\A\s*<div\b[^>]*>','<div style="width: 100%; max-width: 800px; margin: 0 auto; padding: 20px; font-family: ''Apple SD Gothic Neo'', ''Malgun Gothic'', sans-serif; color: #222; box-sizing: border-box; clear: both;">',1)
    $imageWrapperMatches = @([regex]::Matches($result,'(?is)<div\b(?=[^>]*\bdata-blog-image-wrap\s*=\s*["'']true["''])[^>]*>'))
    if ($imageWrapperMatches.Count -ne 4) { throw 'Blogger용 본문에는 이미지 간격 영역이 정확히 4개 필요합니다.' }
    $imageWrapperTag = '<div data-blog-image-wrap="true" style="text-align: center; width: 100%; margin: 28px 0 28px 0; clear: both; box-sizing: border-box;">'
    for ($i=$imageWrapperMatches.Count-1; $i -ge 0; $i--) {
        $result = $result.Remove($imageWrapperMatches[$i].Index,$imageWrapperMatches[$i].Length).Insert($imageWrapperMatches[$i].Index,$imageWrapperTag)
    }
    $imageMatches = @([regex]::Matches($result,'(?is)<img\b[^>]*>'))
    if ($imageMatches.Count -ne 4) { throw 'Blogger용 본문에는 이미지 위치가 정확히 4개 필요합니다.' }
    for ($i=$imageMatches.Count-1; $i -ge 0; $i--) {
        $tag = $imageMatches[$i].Value
        $alt = [regex]::Match($tag,'(?is)\balt\s*=\s*["''](?<value>[^"'']+)["'']').Groups['value'].Value
        if (-not $alt) { throw 'Blogger용 이미지에는 alt 설명이 필요합니다.' }
        if ($tag -match '(?is)\btitle\s*=') {
            $tag = [regex]::Replace($tag,'(?is)(\btitle\s*=\s*)["''][^"'']*["'']',('$1"'+$alt+'"'),1)
        } else { $tag = $tag.Insert($tag.Length-1,(' title="'+$alt+'"')) }
        $style = 'width: 100%; max-width: 400px; height: auto; display: block; margin: 0 auto; border-radius: 4px;'
        if ($tag -match '(?is)\bstyle\s*=') {
            $tag = [regex]::Replace($tag,'(?is)(\bstyle\s*=\s*)["''][^"'']*["'']',('$1"'+$style+'"'),1)
        } else { $tag = $tag.Insert($tag.Length-1,(' style="'+$style+'"')) }
        $result = $result.Remove($imageMatches[$i].Index,$imageMatches[$i].Length).Insert($imageMatches[$i].Index,$tag)
    }
    return $result.TrimEnd()+"`n"
}

function Get-BloggerHostedImageCount([string]$articleFolder) {
    $path = Join-Path $articleFolder 'Blogger에_붙여넣을_본문.html'
    if (-not [IO.File]::Exists($path)) { return 0 }
    $html = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    return @([regex]::Matches($html,'(?is)<img\b[^>]*\bsrc\s*=\s*["'']https://blogger\.googleusercontent\.com/[^"'']+["'']')).Count
}

function Set-FileHiddenState([string]$path,[bool]$hidden) {
    if (-not [IO.File]::Exists($path)) { return }
    $attributes = [IO.File]::GetAttributes($path)
    if ($hidden) { $attributes = $attributes -bor [IO.FileAttributes]::Hidden }
    else { $attributes = $attributes -band (-bnot [IO.FileAttributes]::Hidden) }
    [IO.File]::SetAttributes($path,$attributes)
}

function Hide-ArticleInternalFiles([string]$articleFolder) {
    foreach ($name in @('본문.html','사실검증표.md','이미지_프롬프트.txt','이미지_생성용_전체프롬프트.txt','작업정보.json','미리보기.html','이미지_완료.txt')) {
        $file = Join-Path $articleFolder $name
        if ([IO.File]::Exists($file)) {
            Set-FileHiddenState $file $true
        }
    }
    $bloggerFile = Join-Path $articleFolder 'Blogger에_붙여넣을_본문.html'
    if ([IO.File]::Exists($bloggerFile)) {
        Set-FileHiddenState $bloggerFile $false
    }
}

function Save-Article([object]$candidate, [object]$article) {
    # 잘못된 응답이면 결과 폴더를 만들기 전에 중단한다.
    $imageSections = @(Get-ImageSections $article.ImagePrompts)
    $date = Get-Date -Format 'yyyy-MM-dd'
    $dateDir = Join-Path $script:CompleteDir $date
    [IO.Directory]::CreateDirectory($dateDir) | Out-Null
    $baseName = ('{0:D2}_{1}' -f $candidate.Number,(Get-SafeName $candidate.Title))
    $path = Join-Path $dateDir $baseName
    $suffix = 2
    while ([IO.Directory]::Exists($path)) { $path = Join-Path $dateDir ($baseName + '_' + $suffix); $suffix++ }
    [IO.Directory]::CreateDirectory($path) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $path '원본이미지')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $path '압축이미지')) | Out-Null
    # 내부 원고는 사용자용 글 폴더에 두지 않고 복구용 백업 위치에만 저장한다.
    $internalBackup = Get-ArticleBackupPath $path
    [IO.Directory]::CreateDirectory($internalBackup) | Out-Null
    [IO.File]::WriteAllText((Join-Path $internalBackup '본문.html'),$article.Html,$script:Utf8)
    [IO.File]::WriteAllText((Join-Path $path 'Blogger에_붙여넣을_본문.html'),(Convert-ToBloggerHtml $article.Html),$script:Utf8)
    [IO.File]::WriteAllText((Join-Path $path '메타데이터.txt'),$article.Metadata,$script:Utf8)
    [IO.File]::WriteAllText((Join-Path $path '사실검증표.md'),$article.FactCheck,$script:Utf8)
    [IO.File]::WriteAllText((Join-Path $path '이미지_프롬프트.txt'),$article.ImagePrompts,$script:Utf8)
    $jobInfo = [ordered]@{
        Number = $candidate.Number
        Title = $candidate.Title
        Site = if ($candidate.PSObject.Properties['Site']) { $candidate.Site } else { '' }
        Url = if ($candidate.PSObject.Properties['Url']) { $candidate.Url } else { '' }
        CreatedAt = (Get-Date).ToString('o')
        Status = '이미지 대기'
        RecommendedTitle = $article.RecommendedTitle
        VisibleTextLength = $article.VisibleTextLength
        ImageFiles = @($article.ImageFiles)
    }
    Write-JsonAtomic (Join-Path $path '작업정보.json') $jobInfo 5
    $imageGuide = [IO.File]::ReadAllText((Join-Path $script:PromptDir '03_이미지_생성_프롬프트.md'),[Text.Encoding]::UTF8)
    foreach ($section in $imageSections) {
        $number = $section.Number
        $singlePrompt = $imageGuide.TrimEnd()+"`n`n# 이번 입력자료`n`n"+$section.Text+"`n"
        [IO.File]::WriteAllText((Join-Path $path ('Gemini_이미지_{0:D2}.txt' -f $number)),$singlePrompt,$script:Utf8)
    }
    $geminiGuide = @'
Gemini에서 네 장을 한꺼번에 요청하면 한 장의 콜라주로 합쳐질 수 있습니다.

아래 파일을 한 번에 하나씩, 새 이미지 생성 요청으로 입력하세요.
1. Gemini_이미지_01.txt
2. Gemini_이미지_02.txt
3. Gemini_이미지_03.txt
4. Gemini_이미지_04.txt

각 요청에서 단일 이미지 한 장을 저장한 뒤 다음 번호 파일을 입력합니다.
이 파일이나 이미지_프롬프트.txt 전체를 Gemini에 통째로 입력하지 마세요.
'@
    [IO.File]::WriteAllText((Join-Path $path '이미지_생성용_전체프롬프트.txt'),$geminiGuide.Trim()+"`n",$script:Utf8)
    Backup-ArticleText $path | Out-Null
    Hide-ArticleInternalFiles $path
    return $path
}

function Get-ArticleBackupPath([string]$articleFolder) {
    $completeRoot = [IO.Path]::GetFullPath($script:CompleteDir).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($articleFolder)
    if (-not $full.StartsWith($completeRoot,[StringComparison]::OrdinalIgnoreCase)) { throw "작업완료 밖의 폴더는 백업할 수 없습니다: $full" }
    $relative = $full.Substring($completeRoot.Length)
    return Join-Path $script:BackupDir $relative
}

function Backup-ArticleText([string]$articleFolder) {
    $backup = Get-ArticleBackupPath $articleFolder
    [IO.Directory]::CreateDirectory($backup) | Out-Null
    foreach ($name in @('본문.html','Blogger에_붙여넣을_본문.html','메타데이터.txt','사실검증표.md','이미지_프롬프트.txt','이미지_생성용_전체프롬프트.txt','작업정보.json')) {
        $source = Join-Path $articleFolder $name
        $destination = Join-Path $backup $name
        if ([IO.File]::Exists($source) -and -not [IO.File]::Exists($destination)) { [IO.File]::Copy($source,$destination,$false) }
    }
    foreach ($source in @(Get-ChildItem -LiteralPath $articleFolder -File -Filter 'Gemini_이미지_*.txt')) {
        $destination = Join-Path $backup $source.Name
        if (-not [IO.File]::Exists($destination)) { [IO.File]::Copy($source.FullName,$destination,$false) }
    }
    return $backup
}

function Backup-OriginalImages([string]$articleFolder) {
    if (-not $script:BackupOriginalImages) { return $null }
    $sourceDir = Join-Path $articleFolder '원본이미지'
    $backupDir = Join-Path (Get-ArticleBackupPath $articleFolder) '원본이미지'
    [IO.Directory]::CreateDirectory($backupDir) | Out-Null
    foreach ($source in @(Get-ChildItem -LiteralPath $sourceDir -File | Where-Object Extension -Match '^\.(jpg|jpeg|png|webp)$')) {
        $destination = Join-Path $backupDir $source.Name
        if ([IO.File]::Exists($destination)) {
            if ((Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
                throw "백업에 같은 이름의 다른 이미지가 있습니다: $destination"
            }
        } else { [IO.File]::Copy($source.FullName,$destination,$false) }
    }
    return $backupDir
}

function Get-ChromePath {
    foreach ($path in @('C:\Program Files\Google\Chrome\Application\chrome.exe','C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe')) {
        if ([IO.File]::Exists($path)) { return $path }
    }
    throw 'Chrome 또는 Edge가 없어 WebP 변환을 실행할 수 없습니다.'
}

function Convert-ToWebp([string]$source, [string]$destination) {
    if ([IO.File]::Exists($destination)) { throw "기존 이미지를 덮어쓸 수 없습니다: $destination" }
    $bytes = [IO.File]::ReadAllBytes($source)
    if ($bytes.Length -eq 0) { throw "빈 이미지 파일: $source" }
    $ext = [IO.Path]::GetExtension($source).ToLowerInvariant()
    $mime = switch ($ext) { '.jpg' {'image/jpeg'} '.jpeg' {'image/jpeg'} '.png' {'image/png'} '.webp' {'image/webp'} default {throw "지원하지 않는 이미지 형식: $ext"} }
    $data = [Convert]::ToBase64String($bytes)
    $html = @'
<!doctype html><meta charset="utf-8"><body>WAIT<script>
const image=new Image();
image.onload=()=>{
 const scale=Math.min(1,MAX_PIXELS/Math.max(image.naturalWidth,image.naturalHeight));
 const canvas=document.createElement('canvas');
 canvas.width=Math.max(1,Math.round(image.naturalWidth*scale));
 canvas.height=Math.max(1,Math.round(image.naturalHeight*scale));
 canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);
 document.body.textContent='DATA:'+canvas.toDataURL('image/webp',WEBP_QUALITY);
};
image.onerror=()=>{document.body.textContent='ERROR:IMAGE';};
image.src='DATA_URI';
</script></body>
'@
    $html = $html.Replace('MAX_PIXELS',[string]$script:ImageMaximumPixels).Replace('WEBP_QUALITY',$script:ImageWebpQuality.ToString([Globalization.CultureInfo]::InvariantCulture))
    $html = $html.Replace('DATA_URI', 'data:'+$mime+';base64,'+$data)
    $run = Join-Path $script:TemporaryDir ('이미지변환_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.Directory]::CreateDirectory($run) | Out-Null
    $htmlPath = Join-Path $run '입력.html'
    [IO.File]::WriteAllText($htmlPath,$html,$script:Utf8)
    $profile = Join-Path $run '브라우저설정'
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Get-ChromePath
    $psi.Arguments = '--headless=new --no-sandbox --disable-dev-shm-usage --disable-gpu --disable-background-networking --disable-extensions --no-first-run --no-default-browser-check --no-proxy-server --user-data-dir="' + $profile + '" --virtual-time-budget=10000 --dump-dom "' + ([uri]$htmlPath).AbsoluteUri + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($psi)
    $succeeded = $false
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output = $stdout.Result
        if ($process.ExitCode -ne 0) { throw "브라우저 WebP 변환 실패: $($stderr.Result)" }
        $match = [regex]::Match($output,'DATA:data:image/webp;base64,([A-Za-z0-9+/=]+)')
        if (-not $match.Success) { throw '브라우저가 WebP 데이터를 반환하지 않았습니다.' }
        $webp = [Convert]::FromBase64String($match.Groups[1].Value)
        if ($webp.Length -lt 16 -or [Text.Encoding]::ASCII.GetString($webp,0,4) -ne 'RIFF' -or [Text.Encoding]::ASCII.GetString($webp,8,4) -ne 'WEBP') { throw '생성된 이미지가 WebP 형식이 아닙니다.' }
        [IO.File]::WriteAllBytes($destination,$webp)
        $succeeded = $true
    } finally {
        $process.Dispose()
        $temporaryRoot = [IO.Path]::GetFullPath($script:TemporaryDir).TrimEnd('\') + '\'
        $runFull = [IO.Path]::GetFullPath($run)
        $keepFailed = $null -ne $script:Config.KeepFailedTemporaryFiles -and [bool]$script:Config.KeepFailedTemporaryFiles
        if (($succeeded -or -not $keepFailed) -and $runFull.StartsWith($temporaryRoot,[StringComparison]::OrdinalIgnoreCase) -and [IO.Directory]::Exists($runFull)) {
            [IO.Directory]::Delete($runFull,$true)
        }
    }
}

function Process-Images([string]$articleFolder) {
    $sourceDir = Join-Path $articleFolder '원본이미지'
    $targetDir = Join-Path $articleFolder '압축이미지'
    $images = @(Get-ChildItem -LiteralPath $sourceDir -File | Where-Object Extension -Match '^\.(jpg|jpeg|png|webp)$' | Sort-Object Name)
    if ($images.Count -ne 4) { throw "이미지는 정확히 4장이 필요합니다. 현재 $($images.Count)장: $(if($images.Count -lt 4){'부족 '+(4-$images.Count)+'장'}else{'초과 '+($images.Count-4)+'장'})" }
    $existing = @(Get-ChildItem -LiteralPath $targetDir -File -Filter '*.webp')
    if ($existing.Count -gt 0) { throw "압축이미지 폴더에 기존 WebP $($existing.Count)장이 있어 덮어쓰지 않습니다." }
    $jobInfoPath = Join-Path $articleFolder '작업정보.json'
    $jobInfo = $null
    if ([IO.File]::Exists($jobInfoPath)) { $jobInfo = [IO.File]::ReadAllText($jobInfoPath,[Text.Encoding]::UTF8) | ConvertFrom-Json }
    $outputNames = if ($null -ne $jobInfo -and @($jobInfo.ImageFiles).Count -eq 4) { @($jobInfo.ImageFiles) } else { @(1..4 | ForEach-Object { '{0:D2}-blog-image.webp' -f $_ }) }
    if (@($outputNames | Select-Object -Unique).Count -ne 4 -or @($outputNames | Where-Object { $_ -notmatch '^\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\.webp$' }).Count -gt 0) { throw '작업정보의 이미지 파일명 4개가 올바르지 않습니다.' }
    Backup-OriginalImages $articleFolder | Out-Null
    for ($i=0; $i -lt 4; $i++) {
        $destination = Join-Path $targetDir ([string]$outputNames[$i])
        Convert-ToWebp $images[$i].FullName $destination
    }
    New-LocalPreview $articleFolder | Out-Null
    if ($null -ne $jobInfo) {
        Set-FileHiddenState $jobInfoPath $false
        $jobInfo.Status = '이미지 완료'
        $jobInfo | Add-Member -NotePropertyName ImageCompletedAt -NotePropertyValue ((Get-Date).ToString('o')) -Force
        Write-JsonAtomic $jobInfoPath $jobInfo 5
        $backupInfo = Join-Path (Get-ArticleBackupPath $articleFolder) '작업정보.json'
        Write-JsonAtomic $backupInfo $jobInfo 5
    }
    Hide-ArticleInternalFiles $articleFolder
    return $targetDir
}

function New-LocalPreview([string]$articleFolder) {
    $bodyPath = Join-Path $articleFolder 'Blogger에_붙여넣을_본문.html'
    if (-not [IO.File]::Exists($bodyPath)) { throw "Blogger 게시용 본문 파일을 찾지 못했습니다: $bodyPath" }
    $html = [IO.File]::ReadAllText($bodyPath,[Text.Encoding]::UTF8)
    $matches = @([regex]::Matches($html,'(?is)<img\b[^>]*\bsrc\s*=\s*["''][^"'']*["''][^>]*>'))
    if ($matches.Count -ne 4) { throw '로컬 미리보기에는 이미지 위치가 정확히 4개 필요합니다.' }
    $webpFiles = @(Get-ChildItem -LiteralPath (Join-Path $articleFolder '압축이미지') -File -Filter '*.webp' | Sort-Object Name)
    if ($webpFiles.Count -ne 4) { throw '로컬 미리보기에는 압축 WebP 이미지가 정확히 4개 필요합니다.' }
    for ($i=3; $i -ge 0; $i--) {
        $tag = $matches[$i].Value
        $relative = '압축이미지/' + $webpFiles[$i].Name
        $replacement = [regex]::Replace($tag,'(?is)(\bsrc\s*=\s*)["''][^"'']*["'']',('$1"'+$relative+'"'),1)
        $html = $html.Remove($matches[$i].Index,$matches[$i].Length).Insert($matches[$i].Index,$replacement)
    }
    $preview = @' 
<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>블로그 글 미리보기</title></head><body>
'@ + $html + @'
</body></html>
'@
    $path = Join-Path $articleFolder '미리보기.html'
    Set-FileHiddenState $path $false
    [IO.File]::WriteAllText($path,$preview,$script:Utf8)
    Hide-ArticleInternalFiles $articleFolder
    return $path
}

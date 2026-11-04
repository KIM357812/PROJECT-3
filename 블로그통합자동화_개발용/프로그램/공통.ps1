$script:Root = Split-Path $PSScriptRoot -Parent
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:PromptDir = Join-Path $script:Root '프롬프트'
$script:PendingDir = Join-Path $script:Root '작업대기'
$script:CompleteDir = Join-Path $script:Root '작업완료'
$script:BackupDir = Join-Path $script:Root '백업'
$script:TemporaryDir = Join-Path ([IO.Path]::GetTempPath()) 'SOLIDB_ImageTemp'
$script:LogPath = Join-Path $script:Root '기록\오류기록.txt'
$script:ConfigPath = Join-Path $script:Root '설정.json'
$script:Config = if ([IO.File]::Exists($script:ConfigPath)) {
    [IO.File]::ReadAllText($script:ConfigPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
} else { [pscustomobject]@{} }
$script:CodexModel = if ($env:BLOG_AUTOMATION_CODEX_MODEL) { $env:BLOG_AUTOMATION_CODEX_MODEL } elseif ($script:Config.CodexModel) { [string]$script:Config.CodexModel } else { 'gpt-5.6-sol' }
$script:MaximumCandidates = if ($script:Config.MaximumCandidates) { [int]$script:Config.MaximumCandidates } else { 16 }
$script:MaximumCandidatesPerSite = if ($script:Config.MaximumCandidatesPerSite) { [int]$script:Config.MaximumCandidatesPerSite } else { 2 }
$script:ImageMaximumPixels = if ($script:Config.ImageMaximumPixels) { [int]$script:Config.ImageMaximumPixels } else { 1600 }
$script:ImageWebpQuality = if ($script:Config.ImageWebpQuality) { [double]$script:Config.ImageWebpQuality } else { 0.86 }
$script:BackupOriginalImages = if ($null -ne $script:Config.BackupOriginalImages) { [bool]$script:Config.BackupOriginalImages } else { $true }

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

function Get-LatestRetryableRun {
    foreach ($folder in @(Get-ChildItem -LiteralPath $script:PendingDir -Directory -Filter '글작성_*' | Sort-Object LastWriteTime -Descending)) {
        $statePath = Join-Path $folder.FullName '작업상태.json'
        if (-not [IO.File]::Exists($statePath)) { continue }
        try {
            $state = Read-RunState $folder.FullName
            if (@($state.Failed | Where-Object { $null -ne $_.Candidate }).Count -gt 0) { return $folder.FullName }
        } catch { Write-ErrorLog ('재시도 상태 읽기 실패: '+$_.Exception.Message) }
    }
    return $null
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
    $selected = @($candidates | Where-Object { $numbers -contains $_.Number })
    if ($selected.Count -ne $numbers.Count) { throw '목록에 없는 번호가 포함되어 있습니다.' }
    return $selected
}

function Read-CandidateSelection([object[]]$candidates) {
    while ($true) {
        $inputText = Read-Host '작성할 번호를 입력하세요 (예: 1 또는 2,4,7 / 취소: 취소)'
        if ($null -eq $inputText) { throw '번호 입력이 종료되었습니다.' }
        if ($inputText.Trim() -in @('취소','종료')) { return @() }
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
    for ($i = 0; $i -lt 4; $i++) {
        $number = [int]$headings[$i].Groups['number'].Value
        if ($number -ne ($i + 1)) { throw '이미지 프롬프트 번호가 1~4 순서가 아닙니다.' }
        $end = if ($i -lt 3) { $headings[$i + 1].Index } else { $imagePart.Length }
        $section = $imagePart.Substring($headings[$i].Index, $end - $headings[$i].Index).Trim()
        if ([regex]::Matches($section,'(?m)^[ \t]*-[ \t]*상세 영문 프롬프트[ \t]*:').Count -ne 1) {
            throw ("{0}번 이미지에 상세 영문 프롬프트가 정확히 1개 있어야 합니다." -f $number)
        }
        [PSCustomObject]@{ Number=$number; Text=$section }
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

function Split-Article([string]$response, [string]$expectedSourceSite='', [string]$expectedSourceUrl='') {
    $normalized = $response.Trim().Replace("`r`n", "`n")
    $match = [regex]::Match($normalized, '\A```html\n(?<html>[\s\S]+?)\n```\n\n(?<meta>## 1\. SEO 키워드 분석[\s\S]+)\z')
    if (-not $match.Success) { throw 'HTML 코드 블록과 일반 Markdown 메타데이터가 정확히 분리되지 않았습니다.' }
    $html = $match.Groups['html'].Value.Trim()
    $meta = $match.Groups['meta'].Value.Trim()
    $expectedSourceSite = $expectedSourceSite.Trim()
    if (-not $expectedSourceSite) { throw '선택한 소재의 출처 사이트명이 없습니다.' }
    $expectedComparableUrl = Get-ComparableUrl $expectedSourceUrl
    if (-not $expectedComparableUrl) { throw '선택한 소재의 실제 기사 URL이 없습니다.' }
    if (-not $html.EndsWith('</div>')) { throw '본문 HTML이 바깥쪽 div로 끝나지 않습니다.' }
    if ([regex]::Matches($html,'(?i)<img\b').Count -ne 4) { throw '본문 이미지 placeholder가 4개가 아닙니다.' }
    $outer = [regex]::Match($html,'(?is)\A\s*<div\b(?<attrs>[^>]*)>')
    if (-not $outer.Success) { throw '본문 HTML의 바깥쪽 div를 찾을 수 없습니다.' }
    $outerAttrs = $outer.Groups['attrs'].Value
    if ($outerAttrs -notmatch '(?i)max-width\s*:\s*800px' -or $outerAttrs -notmatch '(?i)margin\s*:\s*0(?:px)?\s+auto') {
        throw '본문 바깥쪽 div가 중앙 정렬·반응형 기준(max-width: 800px; margin: 0 auto)을 지키지 않았습니다.'
    }
    if ($html -match '(?im)^##\s+[1-5]\.' -or $html -match '(?is)글\s*설정\s*라벨.*게시\s*날짜.*퍼머링크.*검색\s*설명') {
        throw '본문 HTML에 메타데이터 또는 Blogger 설정 문구가 섞여 있습니다.'
    }
    if ($html -match '(?is)<p\b[^>]*>\s*(?:<strong>\s*)?출처\s*사이트:') { throw '기존 형식인 출처 사이트 문단은 사용할 수 없습니다.' }
    $sourceMatches = [regex]::Matches($html,'(?is)<div\b(?=[^>]*\bdata-blog-sources\s*=\s*["'']true["''])[^>]*>(?<content>[\s\S]*?)</div>\s*</div>\s*\z')
    if ($sourceMatches.Count -ne 1) { throw '질문 상자 아래 본문 끝에 data-blog-sources="true"인 출처 영역이 정확히 하나 있어야 합니다.' }
    $sourceBlock = $sourceMatches[0].Groups['content'].Value
    if ($sourceBlock -notmatch '(?is)<(?:p|h[2-6])\b[^>]*>\s*(?:<strong>\s*)?출처(?:\s*</strong>)?\s*</(?:p|h[2-6])>') { throw '출처 영역의 제목은 출처여야 합니다.' }
    $sourceAnchors = @([regex]::Matches($sourceBlock,'(?is)<a\b[^>]*\bhref\s*=\s*["''](?<url>https?://[^"'']+)["''][^>]*>(?<text>[\s\S]*?)</a>'))
    if ($sourceAnchors.Count -lt 1 -or $sourceAnchors.Count -gt 3) { throw '출처 영역의 클릭 가능한 원문 링크는 1~3개여야 합니다.' }
    $sourceUrls = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $selectedFound = $false
    foreach ($anchor in $sourceAnchors) {
        $url = Get-ComparableUrl ([Net.WebUtility]::HtmlDecode($anchor.Groups['url'].Value))
        if (-not $url) { throw '출처 영역에 올바르지 않은 URL이 있습니다.' }
        if (-not $sourceUrls.Add($url)) { throw '출처 영역에 같은 URL이 중복되었습니다.' }
        $text = [regex]::Replace([Net.WebUtility]::HtmlDecode($anchor.Groups['text'].Value),'<[^>]+>','').Trim()
        if ($text -notmatch '^.+\s—\s.+$') { throw "출처 링크 문구는 '사이트명 — 실제 기사 제목' 형식이어야 합니다." }
        if ($url -eq $expectedComparableUrl) {
            if ($text -notmatch [regex]::Escape($expectedSourceSite)) { throw ("선택 기사 출처 링크에는 사이트명이 포함되어야 합니다: {0}" -f $expectedSourceSite) }
            $selectedFound = $true
        }
    }
    if (-not $selectedFound) { throw '출처 영역에 사용자가 선택한 실제 기사 URL이 없습니다.' }
    $htmlWithoutSource = $html.Remove($sourceMatches[0].Index,$sourceMatches[0].Length)
    foreach ($anchor in @([regex]::Matches($htmlWithoutSource,'(?is)<a\b[^>]*\bhref\s*=\s*["''](?<url>https?://[^"'']+)["'']'))) {
        $inlineUrl = Get-ComparableUrl ([Net.WebUtility]::HtmlDecode($anchor.Groups['url'].Value))
        if (-not $sourceUrls.Contains($inlineUrl)) { throw '본문 하이퍼링크 URL은 하단 출처 영역에도 반드시 표시해야 합니다.' }
    }
    $headings = @([regex]::Matches($meta,'(?m)^## [1-5]\. .+$') | ForEach-Object Value)
    $expected = @('## 1. SEO 키워드 분석','## 2. SEO 최적화 제목','## 3. 메타 디스크립션','## 4. 이미지 프롬프트 팩','## 5. 해시태그')
    if (($headings -join '|') -ne ($expected -join '|')) { throw '메타데이터 5개 제목이나 순서가 맞지 않습니다.' }
    if ($meta -match '<[^>]+>') { throw '메타데이터에 HTML 태그가 들어 있습니다.' }
    $imagePart = [regex]::Match($meta,'(?s)## 4\. 이미지 프롬프트 팩\n(?<content>.*?)\n## 5\. 해시태그').Groups['content'].Value
    $prompts = @(Get-ImageSections $imagePart)
    return [PSCustomObject]@{ Html=$html+"`n"; Metadata=$meta+"`n"; ImagePrompts=$imagePart.Trim()+"`n" }
}

function Invoke-Codex([string]$prompt, [string]$outputPath) {
    $command = Get-Command codex -ErrorAction Stop
    if ([IO.File]::Exists($outputPath)) { throw "기존 응답 파일을 덮어쓸 수 없습니다: $outputPath" }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $command.Source
    $psi.Arguments = 'exec --model ' + $script:CodexModel + ' --skip-git-repo-check --sandbox read-only -C "' + $script:Root + '" -o "' + $outputPath + '" -'
    $psi.WorkingDirectory = $script:Root
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
    [IO.File]::WriteAllText((Join-Path $path '본문.html'),$article.Html,$script:Utf8)
    [IO.File]::WriteAllText((Join-Path $path 'Blogger에_붙여넣을_본문.html'),$article.Html,$script:Utf8)
    [IO.File]::WriteAllText((Join-Path $path '메타데이터.txt'),$article.Metadata,$script:Utf8)
    [IO.File]::WriteAllText((Join-Path $path '이미지_프롬프트.txt'),$article.ImagePrompts,$script:Utf8)
    $jobInfo = [ordered]@{
        Number = $candidate.Number
        Title = $candidate.Title
        Site = if ($candidate.PSObject.Properties['Site']) { $candidate.Site } else { '' }
        Url = if ($candidate.PSObject.Properties['Url']) { $candidate.Url } else { '' }
        CreatedAt = (Get-Date).ToString('o')
        Status = '이미지 대기'
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
    foreach ($name in @('본문.html','Blogger에_붙여넣을_본문.html','메타데이터.txt','이미지_프롬프트.txt','이미지_생성용_전체프롬프트.txt','작업정보.json')) {
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
    Backup-OriginalImages $articleFolder | Out-Null
    for ($i=0; $i -lt 4; $i++) {
        $destination = Join-Path $targetDir ('{0:D2}.webp' -f ($i+1))
        Convert-ToWebp $images[$i].FullName $destination
    }
    New-LocalPreview $articleFolder | Out-Null
    $jobInfoPath = Join-Path $articleFolder '작업정보.json'
    if ([IO.File]::Exists($jobInfoPath)) {
        $jobInfo = [IO.File]::ReadAllText($jobInfoPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
        $jobInfo.Status = '이미지 완료'
        $jobInfo | Add-Member -NotePropertyName ImageCompletedAt -NotePropertyValue ((Get-Date).ToString('o')) -Force
        Write-JsonAtomic $jobInfoPath $jobInfo 5
        $backupInfo = Join-Path (Get-ArticleBackupPath $articleFolder) '작업정보.json'
        Write-JsonAtomic $backupInfo $jobInfo 5
    }
    return $targetDir
}

function New-LocalPreview([string]$articleFolder) {
    $bodyPath = Join-Path $articleFolder '본문.html'
    if (-not [IO.File]::Exists($bodyPath)) { throw "본문 파일을 찾지 못했습니다: $bodyPath" }
    $html = [IO.File]::ReadAllText($bodyPath,[Text.Encoding]::UTF8)
    $matches = @([regex]::Matches($html,'(?is)<img\b[^>]*\bsrc\s*=\s*["''][^"'']*["''][^>]*>'))
    if ($matches.Count -ne 4) { throw '로컬 미리보기에는 이미지 위치가 정확히 4개 필요합니다.' }
    for ($i=3; $i -ge 0; $i--) {
        $tag = $matches[$i].Value
        $relative = '압축이미지/{0:D2}.webp' -f ($i+1)
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
    [IO.File]::WriteAllText($path,$preview,$script:Utf8)
    return $path
}

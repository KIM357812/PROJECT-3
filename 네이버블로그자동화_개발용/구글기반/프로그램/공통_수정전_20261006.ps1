$script:Root = Split-Path $PSScriptRoot -Parent
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:PromptDir = Join-Path $script:Root '프롬프트'
$script:PendingDir = Join-Path $script:Root '작업대기'
$script:CompleteDir = Join-Path $script:Root '작업완료'
$script:LogPath = Join-Path $script:Root '기록\오류기록.txt'
# 이 PC의 ChatGPT 로그인 모델 목록에서 확인한 모델을 프로그램 실행에만 지정합니다.
$script:CodexModel = 'gpt-5.6-sol'

function Write-ErrorLog([string]$message) {
    $line = '[{0}] {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message, [Environment]::NewLine
    [IO.File]::AppendAllText($script:LogPath, $line, $script:Utf8)
}

function New-RunDirectory([string]$prefix) {
    $path = Join-Path $script:PendingDir ($prefix + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
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

function Get-Selection([string]$inputText, [object[]]$candidates) {
    if ($inputText -notmatch '^\s*\d+(\s*,\s*\d+)*\s*$') { throw '번호는 1 또는 2,4,7처럼 입력하세요.' }
    $numbers = @($inputText -split ',' | ForEach-Object { [int]$_.Trim() } | Select-Object -Unique)
    $selected = @($candidates | Where-Object { $numbers -contains $_.Number })
    if ($selected.Count -ne $numbers.Count) { throw '목록에 없는 번호가 포함되어 있습니다.' }
    return $selected
}

function Split-Article([string]$response, [string]$expectedSourceSite='') {
    $normalized = $response.Trim().Replace("`r`n", "`n")
    $match = [regex]::Match($normalized, '\A```html\n(?<html>[\s\S]+?)\n```\n\n(?<meta>## 1\. SEO 키워드 분석[\s\S]+)\z')
    if (-not $match.Success) { throw 'HTML 코드 블록과 일반 Markdown 메타데이터가 정확히 분리되지 않았습니다.' }
    $html = $match.Groups['html'].Value.Trim()
    $meta = $match.Groups['meta'].Value.Trim()
    $expectedSourceSite = $expectedSourceSite.Trim()
    if (-not $expectedSourceSite) { throw '선택한 소재의 출처 사이트명이 없습니다.' }
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
    # 모델의 출처 표기 여부나 서식에 의존하지 않고, 사용자가 선택한 소재의
    # 사이트명을 본문 맨 끝에 일반 텍스트 한 줄로 확정합니다.
    $sourceParagraphPattern = '(?is)\s*<p\b[^>]*>\s*(?:<strong>\s*)?출처\s*사이트:\s*(?:</strong>\s*)?[^<]*</p>\s*'
    $html = [regex]::Replace($html,$sourceParagraphPattern,"`n")
    $closingIndex = $html.LastIndexOf('</div>')
    if ($closingIndex -lt 0) { throw '본문 HTML의 마지막 닫는 div를 찾을 수 없습니다.' }
    $sourceLine = '<p>출처 사이트: ' + [Net.WebUtility]::HtmlEncode($expectedSourceSite) + '</p>'
    $html = $html.Substring(0,$closingIndex).TrimEnd()+"`n"+$sourceLine+"`n"+$html.Substring($closingIndex)

    $sourceMatches = [regex]::Matches($html,'(?is)<p\b[^>]*>\s*출처\s*사이트:\s*(?<site>[^<]+?)\s*</p>\s*</div>\s*\z')
    if ($sourceMatches.Count -ne 1) { throw '본문 맨 끝에 출처 사이트가 정확히 한 번 표시되지 않았습니다.' }
    $sourceSite = [Net.WebUtility]::HtmlDecode($sourceMatches[0].Groups['site'].Value).Trim()
    if (-not $sourceSite) { throw '출처 사이트명이 비어 있습니다.' }
    if ($sourceSite -match '(?i)https?://|www\.|[/\\]') {
        throw '출처 사이트에는 URL이 아니라 사이트명만 표시해야 합니다.'
    }
    if ($sourceSite -cne $expectedSourceSite) {
        throw ("출처 사이트명이 선택한 소재의 사이트명과 다릅니다. 예상: {0}, 결과: {1}" -f $expectedSourceSite,$sourceSite)
    }
    $headings = @([regex]::Matches($meta,'(?m)^## [1-5]\. .+$') | ForEach-Object Value)
    $expected = @('## 1. SEO 키워드 분석','## 2. SEO 최적화 제목','## 3. 메타 디스크립션','## 4. 이미지 프롬프트 팩','## 5. 해시태그')
    if (($headings -join '|') -ne ($expected -join '|')) { throw '메타데이터 5개 제목이나 순서가 맞지 않습니다.' }
    if ($meta -match '<[^>]+>') { throw '메타데이터에 HTML 태그가 들어 있습니다.' }
    $imagePart = [regex]::Match($meta,'(?s)## 4\. 이미지 프롬프트 팩\n(?<content>.*?)\n## 5\. 해시태그').Groups['content'].Value
    $prompts = [regex]::Matches($imagePart,'(?m)^\s*(?:#{1,4}\s*)?[1-4][\.)]\s*.+$')
    if ($prompts.Count -ne 4 -or [regex]::Matches($imagePart,'상세 영문 프롬프트').Count -ne 4) {
        throw '이미지 프롬프트가 정확히 4개로 분리되지 않았습니다.'
    }
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
    $imageGuide = [IO.File]::ReadAllText((Join-Path $script:PromptDir '03_이미지_생성_프롬프트.md'),[Text.Encoding]::UTF8)
    $imageSections = [regex]::Matches($article.ImagePrompts,'(?ms)^###\s*(?<number>[1-4])\.\s*(?<title>[^\r\n]+)\r?\n(?<body>.*?)(?=^###\s*[1-4]\.|\z)')
    if ($imageSections.Count -ne 4) { throw 'Gemini 개별 생성용 이미지 프롬프트를 4개로 나누지 못했습니다.' }
    foreach ($section in $imageSections) {
        $number = [int]$section.Groups['number'].Value
        $singlePrompt = $imageGuide.TrimEnd()+"`n`n# 이번 입력자료`n`n"+$section.Value.Trim()+"`n"
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
    return $path
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
 const scale=Math.min(1,1600/Math.max(image.naturalWidth,image.naturalHeight));
 const canvas=document.createElement('canvas');
 canvas.width=Math.max(1,Math.round(image.naturalWidth*scale));
 canvas.height=Math.max(1,Math.round(image.naturalHeight*scale));
 canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);
 document.body.textContent='DATA:'+canvas.toDataURL('image/webp',0.86);
};
image.onerror=()=>{document.body.textContent='ERROR:IMAGE';};
image.src='DATA_URI';
</script></body>
'@
    $html = $html.Replace('DATA_URI', 'data:'+$mime+';base64,'+$data)
    $run = New-RunDirectory '이미지변환'
    $htmlPath = Join-Path $run '입력.html'
    [IO.File]::WriteAllText($htmlPath,$html,$script:Utf8)
    $profile = Join-Path $run '브라우저설정'
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Get-ChromePath
    $psi.Arguments = '--headless=new --disable-gpu --disable-background-networking --disable-extensions --no-first-run --no-default-browser-check --no-proxy-server --user-data-dir="' + $profile + '" --virtual-time-budget=10000 --dump-dom "' + ([uri]$htmlPath).AbsoluteUri + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($psi)
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
    } finally { $process.Dispose() }
}

function Process-Images([string]$articleFolder) {
    $sourceDir = Join-Path $articleFolder '원본이미지'
    $targetDir = Join-Path $articleFolder '압축이미지'
    $images = @(Get-ChildItem -LiteralPath $sourceDir -File | Where-Object Extension -Match '^\.(jpg|jpeg|png|webp)$' | Sort-Object Name)
    if ($images.Count -ne 4) { throw "이미지는 정확히 4장이 필요합니다. 현재 $($images.Count)장: $(if($images.Count -lt 4){'부족 '+(4-$images.Count)+'장'}else{'초과 '+($images.Count-4)+'장'})" }
    $existing = @(Get-ChildItem -LiteralPath $targetDir -File -Filter '*.webp')
    if ($existing.Count -gt 0) { throw "압축이미지 폴더에 기존 WebP $($existing.Count)장이 있어 덮어쓰지 않습니다." }
    for ($i=0; $i -lt 4; $i++) {
        $destination = Join-Path $targetDir ('{0:D2}.webp' -f ($i+1))
        Convert-ToWebp $images[$i].FullName $destination
    }
    return $targetDir
}

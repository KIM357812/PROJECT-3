#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceArticlePath,

    [Parameter(Mandatory = $true)]
    [string]$WorkRoot,

    [string]$ContentId = ('NTE-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),

    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '네이버통합설정.json')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$imagePreparePath = Join-Path $PSScriptRoot '이미지작업준비.ps1'
$requiredFiles = @(
    'Blogger에_붙여넣을_본문.html',
    '메타데이터.txt',
    '사실검증표.md',
    '이미지_프롬프트.txt',
    '작업정보.json'
)

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Get-FileFingerprint([string]$Path) {
    $file = Get-Item -LiteralPath $Path -Force
    return [pscustomobject]@{
        length = [long]$file.Length
        sha256 = [string](Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}

function Get-ImagePromptSections([string]$Text) {
    $headings = @([regex]::Matches($Text, '(?m)^[ \t]*(?:#{1,4}[ \t]*)?(?<number>[1-4])[\.)][ \t]+[^\r\n]+[ \t]*$'))
    if ($headings.Count -ne 4) { throw 'Google 기준 이미지 지시문이 정확히 4개가 아닙니다.' }
    $result = New-Object 'System.Collections.Generic.List[object]'
    for ($index = 0; $index -lt 4; $index++) {
        $number = [int]$headings[$index].Groups['number'].Value
        if ($number -ne ($index + 1)) { throw '이미지 지시문 번호가 1~4 순서가 아닙니다.' }
        $end = if ($index -lt 3) { $headings[$index + 1].Index } else { $Text.Length }
        $section = $Text.Substring($headings[$index].Index, $end - $headings[$index].Index).Trim()
        $prompt = [regex]::Match($section, '(?m)^[ \t]*-[ \t]*상세 영문 프롬프트[ \t]*:[ \t]*(?<value>[^\r\n]+)').Groups['value'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($prompt)) { throw "$number 번 이미지의 상세 영문 프롬프트가 없습니다." }
        $result.Add([pscustomobject]@{ number = $number; section = $section; prompt = $prompt })
    }
    return @($result.ToArray())
}

function Get-Tags([string]$Metadata) {
    $match = [regex]::Match($Metadata, '(?s)## 5\. 해시태그\s*(?<tags>.*?)(?:\r?\n## 6\.|\z)')
    if (-not $match.Success) { throw 'Google 메타데이터에서 해시태그를 찾지 못했습니다.' }
    return @($match.Groups['tags'].Value.Trim() -split '\s*,\s*' |
        ForEach-Object { $_.Trim().TrimStart('#') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique)
}

function ConvertTo-NaverHtml([string]$Fragment, [object]$Formatting) {
    $result = [regex]::Replace($Fragment, '(?is)<style\b[^>]*>.*?</style>', '')
    $result = [regex]::Replace($result, '(?is)<h2\b[^>]*>(?<text>.*?)</h2>', {
        param($match)
        '<div data-naver-role="section-heading" style="width:100%;margin:{0}px 0 {1}px 0;box-sizing:border-box;"><p style="margin:0;font-size:{2}px;line-height:27px;font-weight:700;color:#111;text-align:left;word-break:keep-all;">{3}</p></div>' -f
            [int]$Formatting.SectionHeadingTopPx,
            [int]$Formatting.SectionHeadingBottomPx,
            [int]$Formatting.SectionHeadingFontSizePx,
            $match.Groups['text'].Value
    })
    $result = [regex]::Replace($result, '(?is)<h3\b[^>]*>(?<text>.*?)</h3>', {
        param($match)
        '<div data-naver-role="subheading" style="width:100%;margin:28px 0 18px 0;box-sizing:border-box;"><p style="margin:0;font-size:{0}px;line-height:27px;font-weight:700;color:#222;text-align:left;word-break:keep-all;">{1}</p></div>' -f
            [int]$Formatting.SubheadingFontSizePx,
            $match.Groups['text'].Value
    })
    $result = [regex]::Replace($result, '(?i)font-size\s*:\s*16px', ('font-size:{0}px' -f [int]$Formatting.BodyFontSizePx))
    $result = [regex]::Replace($result, '(?i)line-height\s*:\s*1\.75', ('line-height:{0}px' -f [int]$Formatting.BodyLineHeightPx))
    $result = [regex]::Replace($result, '(?i)line-height\s*:\s*1\.6', ('line-height:{0}px' -f [int]$Formatting.CalloutLineHeightPx))
    $result = [regex]::Replace($result, '(?i)text-align\s*:\s*justify', 'text-align:left')
    $result = [regex]::Replace($result, '(?i)text-align-last\s*:\s*left\s*;?', '')
    $result = [regex]::Replace($result, '(?i)margin\s*:\s*0\s+0\s+18px\s+0', ('margin:0 0 {0}px 0' -f [int]$Formatting.ParagraphBottomPx))
    $result = [regex]::Replace($result, '(?i)margin\s*:\s*0\s+0\s+(?:8|15)px\s+0(?=[;"''])', ('margin:0 0 {0}px 0' -f [int]$Formatting.CalloutTitleBottomPx))
    $result = [regex]::Replace($result, '(?i)margin-bottom\s*:\s*10px', ('margin-bottom:{0}px' -f [int]$Formatting.CalloutParagraphBottomPx))
    $result = [regex]::Replace($result, '(?i)>\s*출처\s*:\s*<', ('>{0}<' -f [string]$Formatting.ReferenceLabel))
    $result = [regex]::Replace($result, '(?is)<div\s+data-blog-sources="true"\s+style="(?<style>[^"]*)">', {
        param($match)
        $style = [regex]::Replace($match.Groups['style'].Value, '(?i)margin(?:-top)?\s*:[^;]+;?', '')
        '<div data-blog-sources="true" data-naver-role="references" style="margin:{0}px 0 0 0;{1}">' -f [int]$Formatting.ReferenceTopPx, $style
    })
    return $result.Trim()
}

function Assert-NaverSegment([string]$Fragment, [int]$Index) {
    if ($Fragment -match '(?is)<h[23]\b') { throw "네이버 구간 $Index 에 변환되지 않은 소제목이 있습니다." }
    if ($Fragment -match '(?i)>\s*출처\s*:\s*<') { throw "네이버 구간 $Index 의 참고자료 표기가 변환되지 않았습니다." }
    if ($Fragment -match '(?i)text-align\s*:\s*justify') { throw "네이버 구간 $Index 에 모바일 자간을 벌리는 양쪽 정렬이 남아 있습니다." }
}

function New-SegmentFiles([string]$Html, [string]$Directory, [object]$Formatting) {
    $wrapperPattern = '(?is)<div\b(?=[^>]*\bdata-blog-image-wrap\s*=\s*["'']true["''])[^>]*>\s*<img\b[^>]*>\s*</div>'
    $matches = @([regex]::Matches($Html, $wrapperPattern))
    if ($matches.Count -eq 0) {
        $wrapperPattern = '(?is)<div\b[^>]*>\s*<img\b[^>]*>\s*</div>'
        $matches = @([regex]::Matches($Html, $wrapperPattern))
    }
    if ($matches.Count -ne 4) { throw 'Google 본문 이미지 영역이 정확히 4개가 아닙니다.' }
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $segments = New-Object 'System.Collections.Generic.List[object]'
    $cursor = 0
    for ($index = 0; $index -le $matches.Count; $index++) {
        $end = if ($index -lt $matches.Count) { $matches[$index].Index } else { $Html.Length }
        $fragment = $Html.Substring($cursor, $end - $cursor)
        if ($index -eq 0) { $fragment = [regex]::Replace($fragment, '(?is)\A\s*<div\b[^>]*>', '', 1) }
        if ($index -eq $matches.Count) { $fragment = [regex]::Replace($fragment, '(?is)</div>\s*\z', '', 1) }
        $fragment = ConvertTo-NaverHtml -Fragment $fragment -Formatting $Formatting
        Assert-NaverSegment -Fragment $fragment -Index ($index + 1)
        $segmentPath = Join-Path $Directory ('{0:D2}.html' -f ($index + 1))
        $document = @"
<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>네이버 입력 구간 $($index + 1)</title></head><body style="margin:0;background:#fff;">
<div style="width:100%;max-width:800px;margin:0 auto;padding:20px;font-family:'Apple SD Gothic Neo','Malgun Gothic',sans-serif;color:#222;box-sizing:border-box;">$fragment</div>
</body></html>
"@
        [IO.File]::WriteAllText($segmentPath, $document, (New-Object Text.UTF8Encoding($false)))
        $segments.Add([pscustomobject]@{ order = $index + 1; path = $segmentPath })
        if ($index -lt $matches.Count) { $cursor = $matches[$index].Index + $matches[$index].Length }
    }
    return @($segments.ToArray())
}

foreach ($path in @($SourceArticlePath, $WorkRoot)) {
    if ([string]::IsNullOrWhiteSpace($path)) { throw '입력 경로가 비어 있습니다.' }
}
$sourceFull = Get-FullPath $SourceArticlePath
if (-not (Test-Path -LiteralPath $sourceFull -PathType Container)) { throw "Google 글 폴더를 찾을 수 없습니다: $sourceFull" }
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "네이버 통합 설정을 찾을 수 없습니다: $ConfigPath" }
foreach ($name in $requiredFiles) {
    $path = Join-Path $sourceFull $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Google 글 필수 파일을 찾을 수 없습니다: $name" }
}
if (-not (Test-Path -LiteralPath $imagePreparePath -PathType Leaf)) { throw '기존 네이버 이미지 준비 기능을 찾을 수 없습니다.' }

$sourceFingerprint = @{}
foreach ($name in $requiredFiles) { $sourceFingerprint[$name] = Get-FileFingerprint (Join-Path $sourceFull $name) }
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$config.Workflow.StopPoint -ne 'BeforePublicationSettings' -or
    [bool]$config.Workflow.OpenPublicationSettings -or
    [bool]$config.Workflow.AllowPublicPublish -or
    [bool]$config.Workflow.AllowPrivatePublish) {
    throw '발행 전 정지 설정이 안전하지 않습니다.'
}

$outputRoot = Join-Path (Get-FullPath $WorkRoot) $ContentId
if (Test-Path -LiteralPath $outputRoot) { throw "기존 작업을 덮어쓰지 않습니다: $outputRoot" }
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$sourceCopyRoot = Join-Path $outputRoot 'google-source-copy'
[IO.Directory]::CreateDirectory($sourceCopyRoot) | Out-Null
foreach ($name in $requiredFiles) {
    [IO.File]::Copy((Join-Path $sourceFull $name), (Join-Path $sourceCopyRoot $name), $false)
}

$html = [IO.File]::ReadAllText((Join-Path $sourceFull 'Blogger에_붙여넣을_본문.html'), [Text.Encoding]::UTF8)
$metadata = [IO.File]::ReadAllText((Join-Path $sourceFull '메타데이터.txt'), [Text.Encoding]::UTF8)
$imagePromptText = [IO.File]::ReadAllText((Join-Path $sourceFull '이미지_프롬프트.txt'), [Text.Encoding]::UTF8)
$job = Get-Content -LiteralPath (Join-Path $sourceFull '작업정보.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$promptSections = @(Get-ImagePromptSections $imagePromptText)
$tags = @(Get-Tags $metadata)
if ($tags.Count -lt [int]$config.Naver.MinimumTags) {
    $fallbackTags = @('인공지능','글로벌기술동향','미래기술','데이터센터','에너지전환')
    foreach ($tag in $fallbackTags) { if ($tags.Count -lt [int]$config.Naver.MinimumTags -and $tags -notcontains $tag) { $tags += $tag } }
}
if ($tags.Count -gt [int]$config.Naver.MaximumTags) { $tags = @($tags | Select-Object -First ([int]$config.Naver.MaximumTags)) }

$draftPath = Join-Path $outputRoot '네이버초안.json'
$draft = [pscustomobject]@{
    schemaVersion = 1
    contentId = $ContentId
    title = [string]$job.RecommendedTitle
    source = [pscustomobject]@{ site = [string]$job.Site; url = [string]$job.Url; originalTitle = [string]$job.Title }
    tags = @($tags)
    htmlPath = (Join-Path $sourceCopyRoot 'Blogger에_붙여넣을_본문.html')
    imagePrompts = @($promptSections | ForEach-Object prompt)
}
$draft | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $draftPath -Encoding UTF8

$imageRoot = Join-Path $outputRoot 'images'
$imageManifestPath = Join-Path $outputRoot '이미지작업계획.json'
$null = & $imagePreparePath -DraftPath $draftPath -ImageRoot $imageRoot -OutputPath $imageManifestPath -ConfigPath $ConfigPath
$segments = @(New-SegmentFiles -Html $html -Directory (Join-Path $outputRoot 'segments') -Formatting $config.EditorFormatting)

$actions = New-Object 'System.Collections.Generic.List[object]'
$actions.Add([pscustomobject]@{ order = 1; type = 'OpenNewPost'; url = [string]$config.Naver.WriteUrl })
$actions.Add([pscustomobject]@{ order = 2; type = 'SetTitle'; text = [string]$job.RecommendedTitle })
$order = 3
for ($index = 0; $index -lt 4; $index++) {
    $actions.Add([pscustomobject]@{ order = $order++; type = 'PasteRenderedSegment'; path = [string]$segments[$index].path })
    $role = @($config.ImageAutomation.Roles | Sort-Object Order)[$index]
    $actions.Add([pscustomobject]@{ order = $order++; type = 'UploadImage'; path = (Join-Path (Join-Path $imageRoot 'optimized') ([string]$role.OutputFileName)); alignment = 'center'; displayWidth = [int]$config.ImageAutomation.EditorDisplayWidth })
}
$actions.Add([pscustomobject]@{ order = $order++; type = 'PasteRenderedSegment'; path = [string]$segments[4].path })
$actions.Add([pscustomobject]@{ order = $order++; type = 'SetTags'; values = @($tags) })
$actions.Add([pscustomobject]@{ order = $order++; type = 'StopBeforePublicationSettings' })

$planPath = Join-Path $outputRoot '네이버편집계획.json'
$plan = [pscustomobject]@{
    schemaVersion = 1
    contentId = $ContentId
    sourceMode = 'GoogleAutomationCopy'
    reusedExistingNaverFeatures = @('ImagePlan','ImageOptimization','ImageValidation')
    title = [string]$job.RecommendedTitle
    category = [string]$config.Naver.DefaultCategory
    tags = @($tags)
    imageManifest = $imageManifestPath
    actions = @($actions.ToArray())
    stopPoint = 'BeforePublicationSettings'
    publicationSettingsOpened = $false
    publicPublishPerformed = $false
    privatePublishPerformed = $false
}
$plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding UTF8

foreach ($name in $requiredFiles) {
    $after = Get-FileFingerprint (Join-Path $sourceFull $name)
    $before = $sourceFingerprint[$name]
    if ($after.length -ne $before.length -or $after.sha256 -ne $before.sha256) {
        throw "Google 글 원본이 변경되었습니다: $name"
    }
}

[pscustomobject]@{
    outputRoot = $outputRoot
    draft = $draftPath
    imageManifest = $imageManifestPath
    editorPlan = $planPath
    title = [string]$job.RecommendedTitle
    tagCount = $tags.Count
    segmentCount = $segments.Count
    imageCount = $promptSections.Count
    stopPoint = 'BeforePublicationSettings'
} | ConvertTo-Json -Depth 5

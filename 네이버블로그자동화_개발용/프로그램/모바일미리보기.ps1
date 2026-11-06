#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DraftPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $PSScriptRoot '초안검증.ps1'
. $validatorPath -Path 'unused'

if (-not (Test-Path -LiteralPath $DraftPath -PathType Leaf)) {
    throw "네이버 초안 파일을 찾을 수 없습니다: $DraftPath"
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "기존 모바일 미리보기를 덮어쓰지 않습니다: $OutputPath"
}
if ([IO.Path]::GetExtension($OutputPath) -ne '.html') {
    throw '모바일 미리보기 OutputPath는 .html 파일이어야 합니다.'
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $projectRoot '설정.json'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$draft = Get-Content -LiteralPath $DraftPath -Raw -Encoding UTF8 | ConvertFrom-Json
$validation = Test-NaverDraft -Draft $draft -Rules $config.NaverDraft
if (-not $validation.IsValid) {
    throw ('검증된 초안만 모바일 미리보기를 만들 수 있습니다: ' + (@($validation.Issues) -join '; '))
}

function ConvertTo-HtmlText {
    param([AllowEmptyString()][string]$Value)
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

$paragraphs = @([string]$draft.body -split "(`r?`n){2,}" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$headingLookup = @{}
foreach ($sectionHeading in @($draft.sectionHeadings)) {
    $headingLookup[[string]$sectionHeading] = $true
}
$paragraphHtml = @($paragraphs | ForEach-Object {
    $paragraphText = $_.Trim()
    $encoded = ConvertTo-HtmlText $paragraphText
    if ($headingLookup.ContainsKey($paragraphText)) {
        '<h2 class="section-heading">' + $encoded + '</h2>'
    }
    else {
        '<p>' + ($encoded -replace "`r?`n", '<br>') + '</p>'
    }
}) -join "`r`n"

$sourceHtml = @($draft.sources | ForEach-Object {
    $name = ConvertTo-HtmlText ([string]$_.name)
    $title = ConvertTo-HtmlText ([string]$_.title)
    $date = ConvertTo-HtmlText ([string]$_.publishedDate)
    $url = ConvertTo-HtmlText ([string]$_.url)
    '<li>' + $name + ' — ' + $title + ' — ' + $date + '<br><a href="' + $url + '" target="_blank" rel="noopener noreferrer">' + $url + '</a></li>'
}) -join "`r`n"
$sourceSectionHtml = if (@($draft.sources).Count -gt 0) {
    "<h2>출처</h2>`r`n<ul>$sourceHtml</ul>"
} else {
    ''
}
$tagHtml = @($draft.tags | ForEach-Object { '<span>#' + (ConvertTo-HtmlText ([string]$_)) + '</span>' }) -join ''
$title = ConvertTo-HtmlText ([string]$draft.title)
$bodyLength = ([string]$draft.body).Length
$generatedAt = ConvertTo-HtmlText ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
$titleMobileFontSize = [int]$config.NaverDraft.PostTitleMobileFontSize
$sectionHeadingFontSize = [int]$config.NaverDraft.SectionHeadingFontSize
$bodyFontSize = [int]$config.NaverDraft.BodyFontSize
$bodyLineHeight = [double]$config.NaverDraft.BodyLineHeight
$bodyLineHeightPx = [int]$config.NaverDraft.BodyLineHeightPx
$paragraphMarginBottom = [int]$config.NaverDraft.ParagraphMarginBottomPx
$headingMarginTop = [int]$config.NaverDraft.SectionHeadingMarginTopPx
$headingMarginBottom = [int]$config.NaverDraft.SectionHeadingMarginBottomPx
$calloutTitleMarginBottom = [int]$config.NaverDraft.CalloutDesign.TitleMarginBottomPx
$calloutBodyLineHeight = [double]$config.NaverDraft.CalloutDesign.BodyLineHeight
$calloutParagraphMarginBottom = [int]$config.NaverDraft.CalloutDesign.ParagraphMarginBottomPx
$calloutPaddingVertical = [int]$config.NaverDraft.CalloutDesign.InnerPaddingVerticalPx
$calloutPaddingHorizontal = [int]$config.NaverDraft.CalloutDesign.InnerPaddingHorizontalPx
$calloutMarginTop = [int]$config.NaverDraft.CalloutDesign.OuterMarginTopPx
$calloutMarginBottom = [int]$config.NaverDraft.CalloutDesign.OuterMarginBottomPx
$calloutBorderRadius = [int]$config.NaverDraft.CalloutDesign.BorderRadiusPx
$calloutTitleFontSize = [int]$config.NaverDraft.CalloutDesign.TitleFontSizePx
$calloutSummaryStyle = @($config.NaverDraft.CalloutDesign.Styles | Where-Object { $_.Name -eq '육하원칙·핵심요약' })[0]
$calloutJudgmentStyle = @($config.NaverDraft.CalloutDesign.Styles | Where-Object { $_.Name -eq '운영자판단·결론' })[0]
$calloutSummaryMarginTop = [int]$calloutSummaryStyle.OuterMarginTopPx
$calloutSummaryMarginBottom = [int]$calloutSummaryStyle.OuterMarginBottomPx
$calloutJudgmentMarginTop = [int]$calloutJudgmentStyle.OuterMarginTopPx
$calloutJudgmentMarginBottom = [int]$calloutJudgmentStyle.OuterMarginBottomPx
$headingDividerColor = ConvertTo-HtmlText ([string]$config.NaverDraft.SectionHeadingDividerColor)
$headingDividerThickness = [int]$config.NaverDraft.SectionHeadingDividerThicknessPx
$imageDisplayWidth = [int]$config.ImageAutomation.EditorDisplayWidth

$html = @"
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title - 모바일 미리보기</title>
<style>
html { background:#eef2f6; color:#172033; font-family:"Malgun Gothic",sans-serif; }
body { margin:0; padding:24px 12px; }
.phone { box-sizing:border-box; width:390px; max-width:100%; margin:0 auto; padding:28px 20px; background:#fff; border:1px solid #d9e0e8; border-radius:20px; box-shadow:0 12px 32px rgba(22,32,51,.12); }
h1 { margin:0 0 22px; font-size:${titleMobileFontSize}px; line-height:1.38; letter-spacing:-.04em; overflow-wrap:anywhere; }
p { margin:0 0 ${paragraphMarginBottom}px; font-size:${bodyFontSize}px; line-height:${bodyLineHeightPx}px; letter-spacing:-.015em; overflow-wrap:anywhere; }
h2 { margin:30px 0 14px; font-size:18px; }
.section-heading { margin:${headingMarginTop}px 0 ${headingMarginBottom}px; padding-bottom:6px; border-bottom:${headingDividerThickness}px solid $headingDividerColor; font-size:${sectionHeadingFontSize}px; line-height:1.55; font-weight:700; letter-spacing:-.02em; }
.callout { box-sizing:border-box; width:100%; margin:${calloutMarginTop}px 0 ${calloutMarginBottom}px; padding:${calloutPaddingVertical}px ${calloutPaddingHorizontal}px; border:0; border-left:4px solid; border-radius:${calloutBorderRadius}px; font-size:${bodyFontSize}px; line-height:$calloutBodyLineHeight; overflow-wrap:anywhere; white-space:normal; }
.callout-context { background:#f7f7f7; border-left-color:#777777; }
.callout-summary { background:#e3fdc8; border-left-color:#66a33b; }
.callout-judgment { background:#ffe3c8; border-left-color:#ff9800; }
.callout-title { display:block; margin:0 0 ${calloutTitleMarginBottom}px; color:inherit; font-size:${calloutTitleFontSize}px; font-weight:700; }
.callout-context .callout-title { color:#555555; }
.callout-summary { margin-top:${calloutSummaryMarginTop}px; margin-bottom:${calloutSummaryMarginBottom}px; }
.callout-summary .callout-title { margin-bottom:10px; color:#36851e; }
.callout-judgment { margin-top:${calloutJudgmentMarginTop}px; margin-bottom:${calloutJudgmentMarginBottom}px; }
.callout-judgment .callout-title { margin-bottom:8px; color:#b85c00; }
.callout p { margin:0 0 ${calloutParagraphMarginBottom}px; line-height:$calloutBodyLineHeight; }
.callout p:last-child { margin-bottom:0; }
.five-w-one-h-label { font-weight:700; }
.content-image { display:block; width:${imageDisplayWidth}px; max-width:100%; height:auto; margin:22px auto; }
ul { padding-left:20px; }
li { margin-bottom:14px; font-size:14px; line-height:1.65; overflow-wrap:anywhere; }
a { color:#0b63ce; }
.tags { display:flex; flex-wrap:wrap; gap:8px; margin-top:28px; }
.tags span { padding:7px 10px; background:#eef7f6; border-radius:999px; color:#087c6a; font-size:14px; }
.meta { margin-top:26px; padding-top:16px; border-top:1px solid #e7ebf0; color:#667085; font-size:12px; line-height:1.6; }
</style>
</head>
<body>
<main class="phone">
<article>
<h1>$title</h1>
$paragraphHtml
$sourceSectionHtml
<div class="tags">$tagHtml</div>
<div class="meta">로컬 검토용 · 본문 $bodyLength 자 · 생성 $generatedAt<br>네이버 실제 모바일 화면과 동일함을 보장하지 않습니다.</div>
</article>
</main>
</body>
</html>
"@

$directory = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($directory)) { throw 'OutputPath는 상위 폴더를 포함해야 합니다.' }
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $directory
}
$html | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    output = [IO.Path]::GetFullPath($OutputPath)
    viewportWidth = 390
    bodyLength = $bodyLength
    paragraphCount = $paragraphs.Count
    headingCount = @($draft.sectionHeadings).Count
    externalTransmission = $false
    disclaimer = '로컬 미리보기이며 네이버 실제 모바일 렌더링은 비공개 초안에서 별도 확인해야 합니다.'
} | ConvertTo-Json -Depth 4

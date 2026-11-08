#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceArticlePath,

    [Parameter(Mandatory = $true)]
    [string]$WorkRoot,

    [string]$ContentId = ('NTE-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),

    [string]$ConfigPath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $projectRoot '네이버통합설정.json' }
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
    $result = [regex]::Replace($result, '(?is)<div(?<attrs>[^>]*)>(?<lead>\s*<p[^>]*>\s*이 글에서 다루는 내용\s*</p>)', '<div data-naver-role="overview-box"${attrs}>${lead}')
    $result = [regex]::Replace($result, '(?i)font-size\s*:\s*16px', ('font-size:{0}px' -f [int]$Formatting.BodyFontSizePx))
    $result = [regex]::Replace($result, '(?is)<h2\b[^>]*>(?<text>.*?)</h2>', {
        param($match)
        '<div data-naver-role="section-heading" style="width:100%;margin:{0}px 0 {1}px 0;box-sizing:border-box;"><p style="margin:0;font-size:{2}px;line-height:27px;font-weight:700;text-align:left;word-break:keep-all;"><span style="color:{5};">{6}</span></p></div>' -f
            [int]$Formatting.SectionHeadingTopPx,
            [int]$Formatting.SectionHeadingBottomPx,
            [int]$Formatting.SectionHeadingFontSizePx,
            [int]$Formatting.SectionHeadingUnderlineOffsetPx,
            [int]$Formatting.SectionHeadingUnderlineThicknessPx,
            [string]$Formatting.SectionHeadingColor,
            $match.Groups['text'].Value
    })
    $result = [regex]::Replace($result, '(?is)<h3\b[^>]*>(?<text>.*?)</h3>', {
        param($match)
        '<div data-naver-role="subheading" style="width:100%;margin:{0}px 0 {1}px 0;box-sizing:border-box;"><p style="margin:0;font-size:{2}px;line-height:27px;font-weight:700;color:#222;text-align:left;word-break:keep-all;">{3}</p></div>' -f
            [int]$Formatting.SubheadingTopPx,
            [int]$Formatting.SubheadingBottomPx,
            [int]$Formatting.SubheadingFontSizePx,
            $match.Groups['text'].Value
    })
    $result = [regex]::Replace($result, '(?i)line-height\s*:\s*1\.75', ('line-height:{0}px' -f [int]$Formatting.BodyLineHeightPx))
    $result = [regex]::Replace($result, '(?i)line-height\s*:\s*1\.6', ('line-height:{0}px' -f [int]$Formatting.CalloutLineHeightPx))
    $result = [regex]::Replace($result, '(?i)margin\s*:\s*0\s+0\s+18px\s+0', ('margin:0 0 {0}px 0' -f [int]$Formatting.ParagraphBottomPx))
    $result = [regex]::Replace($result, '(?i)margin\s*:\s*0\s+0\s+(?:8|15)px\s+0(?=[;"''])', ('margin:0 0 {0}px 0' -f [int]$Formatting.CalloutTitleBottomPx))
    $result = [regex]::Replace($result, '(?i)margin-bottom\s*:\s*10px', ('margin-bottom:{0}px' -f [int]$Formatting.CalloutParagraphBottomPx))
    $result = [regex]::Replace($result, '(?i)>\s*출처\s*:\s*<', ('>{0}<' -f [string]$Formatting.ReferenceLabel))
    $result = [regex]::Replace($result, '(?is)<div\s+data-blog-sources="true"\s+style="(?<style>[^"]*)">', {
        param($match)
        $style = [regex]::Replace($match.Groups['style'].Value, '(?i)margin(?:-top)?\s*:[^;]+;?', '')
        '<div data-blog-sources="true" data-naver-role="references" style="margin:{0}px 0 0 0;{1}">' -f [int]$Formatting.ReferenceTopPx, $style
    })
    $result = [regex]::Replace($result, '(?is)<div\b(?=[^>]*\bclass\s*=\s*["''][^"'']*\bsolidb-responsive-table\b)[^>]*>', {
        param($match)
        $tag = $match.Value
        if ($tag -match '(?i)style\s*=\s*"(?<style>[^"]*)"') {
            $style = [regex]::Replace($Matches['style'], '(?i)margin\s*:[^;]+;?', '')
            return [regex]::Replace($tag, '(?i)style\s*=\s*"[^"]*"', ('style="margin:25px 0 0 0;{0}"' -f $style))
        }
        return $tag.TrimEnd('>') + ' style="margin:25px 0 0 0;">'
    })
    $result = [regex]::Replace($result, '(?is)<div\s+data-blog-related="true"\s+style="(?<style>[^"]*)">', {
        param($match)
        $style = [regex]::Replace($match.Groups['style'].Value, '(?i)margin(?:-top)?\s*:[^;]+;?', '')
        '<div data-blog-related="true" data-naver-role="related" style="margin:{0}px 0 0 0;{1}">' -f [int]$Formatting.ReferenceToRelatedPx, $style
    })
    $result = [regex]::Replace($result, '(?is)(?<sources><div\b(?=[^>]*\bdata-blog-sources="true")[^>]*>\s*<p\b[^>]*>[\s\S]*?</p>\s*</div>)\s*(?<related><div\b(?=[^>]*\bdata-blog-related="true")[^>]*>[\s\S]*?</div>)', {
        param($match)
        $sources = [regex]::Replace($match.Groups['sources'].Value, '(?is)(<div\b(?=[^>]*\bdata-blog-sources="true")[^>]*?)style\s*=\s*"[^"]*"', '$1style="margin:0;padding:0;border:0;background:transparent;width:100%;box-sizing:border-box;"')
        $related = [regex]::Replace($match.Groups['related'].Value, '(?is)(<div\b(?=[^>]*\bdata-blog-related="true")[^>]*?)style\s*=\s*"[^"]*"', '$1style="margin:0;padding:0;border:0;background:transparent;width:100%;box-sizing:border-box;"')
        $related = [regex]::Replace($related, '(?is)(<div\b[^>]*\bdata-blog-related="true"[^>]*>)', ('$1<span data-nte-reference-gap="true" style="display:block;height:{0}px;line-height:{0}px;font-size:1px;color:transparent;">&nbsp;</span>' -f [int]$Formatting.ReferenceToRelatedPx), 1)
        '<table data-naver-role="reference-group" border="1" bordercolor="#CDD2D9" style="width:100%;margin:{0}px 0 0 0;border-collapse:collapse;border:1px solid #CDD2D9;background:#fff;box-sizing:border-box;"><tbody><tr><td style="padding:12px 14px;border:1px solid #CDD2D9;background:#fff;">{1}{2}</td></tr></tbody></table>' -f [int]$Formatting.ReferenceTopPx, $sources, $related
    })
    return $result.Trim()
}

function Apply-NaverReaderTermRules([string]$Html) {
    $result = $Html
    $metrPattern = [regex]::new('(?:비영리\s+(?:AI\s+)?평가기관\s+)?<strong>\s*METR\s*</strong>|(?:비영리\s+(?:AI\s+)?평가기관\s+)?METR', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $result = $metrPattern.Replace($result, '<strong data-primary-source-identity="true" data-reader-term="METR">METR(비영리 AI 평가기관)</strong>', 1)
    $aeciPattern = [regex]::new('(?:앤트로픽의\s+)?(?:내부\s+역량\s+지수(?:인|인\s+)?\s*)?<strong>\s*AECI\s*</strong>|(?:앤트로픽의\s+)?(?:내부\s+역량\s+지수(?:인|인\s+)?\s*)?AECI', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $result = $aeciPattern.Replace($result, '앤트로픽의 <strong data-reader-term="AECI">AECI(내부 역량 지수)</strong>', 1)
    return $result
}

function Assert-NaverReaderTerms([string]$Html, [object]$Formatting) {
    $withoutEnding = [regex]::Replace($Html, '(?is)<div\b(?=[^>]*\bdata-blog-(?:sources|related)\s*=)[\s\S]*\z', '')
    $plain = ConvertFrom-HtmlText $withoutEnding
    $allow = @($Formatting.KnownAcronymAllowlist | ForEach-Object { [string]$_ })
    $acronyms = @([regex]::Matches($plain, '(?<![A-Za-z0-9])(?<term>[A-Z][A-Z0-9-]{2,})(?![A-Za-z0-9])') | ForEach-Object { $_.Groups['term'].Value } | Select-Object -Unique)
    foreach ($term in $acronyms) {
        if ($allow -contains $term) { continue }
        $pattern = '(?<![A-Za-z0-9])' + [regex]::Escape($term) + '\((?<explanation>[^)]*[가-힣][^)]*)\)'
        $matches = @([regex]::Matches($plain, $pattern))
        if ($matches.Count -ne 1) { throw "낯선 약어 $term 은 본문 첫 등장 한 곳에만 쉬운 한글 설명이 있어야 합니다." }
        if ($plain.IndexOf($matches[0].Value, [StringComparison]::Ordinal) -ne $plain.IndexOf($term, [StringComparison]::Ordinal)) {
            throw "낯선 약어 $term 의 쉬운 한글 설명이 첫 등장에 없습니다."
        }
    }
    $declared = @([regex]::Matches($Html, '(?is)data-reader-term="(?<term>[^"]+)"[^>]*>(?<value>.*?)</(?:strong|span)>'))
    foreach ($item in $declared) {
        $term = $item.Groups['term'].Value
        $value = ConvertFrom-HtmlText $item.Groups['value'].Value
        if ($value -notmatch ('^' + [regex]::Escape($term) + '\([^)]*[가-힣][^)]*\)$')) { throw "독자 용어 $term 의 한글 설명 형식이 올바르지 않습니다." }
        if (@([regex]::Matches($plain, [regex]::Escape($term) + '\(')).Count -ne 1) { throw "독자 용어 $term 의 설명은 첫 등장 한 번만 허용됩니다." }
    }
    if (@([regex]::Matches($Html, '(?is)data-primary-source-identity="true"')).Count -gt 1) { throw '핵심 근거기관의 첫 등장 굵은 표시는 한 번만 허용됩니다.' }
}

function Normalize-NaverImagePlacement([string]$Html) {
    $wrapper = '(?is)<div\b(?=[^>]*\bdata-blog-image-wrap\s*=\s*["'']true["''])[^>]*>\s*<img\b[^>]*>\s*</div>'
    $result = $Html
    for ($pass = 0; $pass -lt 4; $pass++) {
        $orphan = [regex]::Match($result, '(?is)(?<before>[\s\S]*?</p>)\s*(?<image>' + $wrapper + ')\s*(?<next><h[23]\b)')
        if (-not $orphan.Success) { break }
        $before = $orphan.Groups['before'].Value
        $headings = @([regex]::Matches($before, '(?is)<h[23]\b[^>]*>[\s\S]*?</h[23]>'))
        if ($headings.Count -eq 0) { break }
        $heading = $headings[-1]
        $prefix = $before.Substring(0, $heading.Index)
        $suffix = $before.Substring($heading.Index + $heading.Length)
        $result = $prefix + $heading.Value + $orphan.Groups['image'].Value + $suffix + $result.Substring($orphan.Groups['next'].Index)
    }
    return $result
}

function Assert-NaverSegment([string]$Fragment, [int]$Index) {
    if ($Fragment -match '(?is)<h[23]\b') { throw "네이버 구간 $Index 에 변환되지 않은 소제목이 있습니다." }
    if ($Fragment -match '(?i)>\s*출처\s*:\s*<') { throw "네이버 구간 $Index 의 참고자료 표기가 변환되지 않았습니다." }
}

function ConvertFrom-HtmlText([string]$Html) {
    $withoutTags = [regex]::Replace($Html, '(?is)<[^>]+>', '')
    return [Net.WebUtility]::HtmlDecode($withoutTags).Trim()
}

function Split-TopLevelHtmlBlocks([string]$Fragment) {
    $blocks = New-Object 'System.Collections.Generic.List[string]'
    $tagMatches = @([regex]::Matches($Fragment, '(?is)<!--.*?-->|<![^>]*>|</?[a-z][^>]*>'))
    $depth = 0
    $start = -1
    $voidNames = @('area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr')
    foreach ($tagMatch in $tagMatches) {
        $token = $tagMatch.Value
        if ($token -match '^<!--' -or $token -match '^<!') { continue }
        $nameMatch = [regex]::Match($token, '(?is)^</?\s*(?<name>[a-z0-9]+)')
        if (-not $nameMatch.Success) { continue }
        $name = $nameMatch.Groups['name'].Value.ToLowerInvariant()
        $isClose = $token -match '^</'
        $isVoid = $token -match '/>\s*$' -or $voidNames -contains $name
        if (-not $isClose -and $depth -eq 0) { $start = $tagMatch.Index }
        if ($isClose) {
            $depth--
            if ($depth -eq 0 -and $start -ge 0) {
                $blocks.Add($Fragment.Substring($start, ($tagMatch.Index + $tagMatch.Length) - $start).Trim())
                $start = -1
            }
        }
        elseif ($isVoid) {
            if ($depth -eq 0 -and $start -ge 0) {
                $blocks.Add($Fragment.Substring($start, ($tagMatch.Index + $tagMatch.Length) - $start).Trim())
                $start = -1
            }
        }
        else { $depth++ }
        if ($depth -lt 0) { throw '네이버 블록 분리 중 HTML 닫는 태그 순서가 잘못되었습니다.' }
    }
    if ($depth -ne 0) { throw '네이버 블록 분리 중 닫히지 않은 HTML 태그가 있습니다.' }
    return @($blocks.ToArray())
}

function Write-NaverBlockFile([string]$Block, [string]$Directory, [int]$Sequence) {
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $path = Join-Path $Directory ('block-{0:D3}.html' -f $Sequence)
    $document = @"
<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>네이버 독립 입력 블록 $Sequence</title></head><body style="margin:0;background:#fff;">
<div data-naver-atomic-block="true" style="width:100%;font-family:'Apple SD Gothic Neo','Malgun Gothic',sans-serif;color:#222;box-sizing:border-box;">$Block</div>
</body></html>
"@
    [IO.File]::WriteAllText($path, $document, (New-Object Text.UTF8Encoding($false)))
    return $path
}

function Add-AtomicSegmentActions([object]$Actions, [ref]$Order, [object]$Segment, [string]$BlockDirectory, [object]$Formatting, [ref]$BlockSequence) {
    $blocks = @(Split-TopLevelHtmlBlocks -Fragment ([string]$Segment.fragment))
    foreach ($block in $blocks) {
        if ([string]::IsNullOrWhiteSpace((ConvertFrom-HtmlText $block))) { continue }
        $heading = [regex]::Match($block, '(?is)^<div\s+data-naver-role="(?<role>section-heading|subheading)"[^>]*>\s*<p[^>]*>(?<text>.*?)</p>\s*</div>$')
        if ($heading.Success) {
            $role = $heading.Groups['role'].Value
            $level = if ($role -eq 'section-heading') { 2 } else { 3 }
            $fontSize = if ($level -eq 2) { [int]$Formatting.SectionHeadingFontSizePx } else { [int]$Formatting.SubheadingFontSizePx }
            $topPx = if ($level -eq 2) { [int]$Formatting.SectionHeadingTopPx } else { [int]$Formatting.SubheadingTopPx }
            $bottomPx = if ($level -eq 2) { [int]$Formatting.SectionHeadingBottomPx } else { [int]$Formatting.SubheadingBottomPx }
            $topNativeFontPx = if ($level -eq 2) { 16 } else { 15 }
            $topNativeLineHeightPercent = if ($level -eq 2) { 200 } else { 160 }
            $bottomNativeFontPx = if ($level -eq 2) { 13 } else { 12 }
            $bottomNativeLineHeightPercent = if ($level -eq 2) { 160 } else { 100 }
            $underline = if ($level -eq 2) { [bool]$Formatting.SectionHeadingUnderline } else { [bool]$Formatting.SubheadingUnderline }
            $underlineOffset = if ($level -eq 2) { [int]$Formatting.SectionHeadingUnderlineOffsetPx } else { 0 }
            $underlineThickness = if ($level -eq 2) { [int]$Formatting.SectionHeadingUnderlineThicknessPx } else { 0 }
            $underlineColor = if ($level -eq 2) { [string]$Formatting.SectionHeadingUnderlineColor } else { '' }
            $textColor = if ($level -eq 2) { [string]$Formatting.SectionHeadingColor } else { '#111111' }
            $parentAdjacent = $false
            if ($level -eq 3 -and $Actions.Count -ge 2) {
                $previousSpacer = $Actions[$Actions.Count - 1]
                $previousHeading = $Actions[$Actions.Count - 2]
                if ([string]$previousSpacer.type -eq 'InsertVerticalSpacer' -and [string]$previousSpacer.purpose -eq 'HeadingBottom' -and
                    [string]$previousHeading.type -eq 'InsertStandaloneHeading' -and [int]$previousHeading.level -eq 2) {
                    $previousSpacer.purpose = 'ParentHeadingToSubheading'
                    $previousSpacer.heightPx = [int]$Formatting.ParentHeadingToSubheadingPx
                    $previousSpacer.mobileHeightPx = [int]$Formatting.MobileParentHeadingToSubheadingPx
                    $previousSpacer.naverFontSizePx = 12
                    $previousSpacer.naverLineHeightPercent = 100
                    $previousSpacer.postcondition.measuredHeightPx = [int]$Formatting.ParentHeadingToSubheadingPx
                    $parentAdjacent = $true
                }
            }
            $tableAdjacent = $false
            if ($level -eq 2 -and $Actions.Count -ge 1) {
                $previousBlock = $Actions[$Actions.Count - 1]
                if ([string]$previousBlock.type -eq 'PasteRenderedAtomicBlock' -and [string]$previousBlock.blockRole -in @('DataTable','OverviewBox')) {
                    $previousBlock.postcondition | Add-Member -NotePropertyName requireDirectlyBeforeHeadingWhenApplicable -NotePropertyValue $true -Force
                    $previousBlock.postcondition | Add-Member -NotePropertyName maximumRenderedHeadingGapPx -NotePropertyValue ([int]$Formatting.TableToHeadingPx) -Force
                    $tableAdjacent = $true
                }
            }
            if (-not $parentAdjacent -and -not $tableAdjacent) {
                $Actions.Add([pscustomobject]@{
                    order=$Order.Value++; type='InsertVerticalSpacer'; purpose='HeadingTop'; headingLevel=$level
                    heightPx=$topPx; naverFontSizePx=$topNativeFontPx; naverLineHeightPercent=$topNativeLineHeightPercent
                    postcondition=[pscustomobject]@{ requireStandaloneBlankParagraph=$true; measuredHeightPx=$topPx }
                })
            }
            $Actions.Add([pscustomobject]@{
                order=$Order.Value++; type='InsertStandaloneHeading'; level=$level
                text=(ConvertFrom-HtmlText $heading.Groups['text'].Value); fontFamily=[string]$Formatting.HeadingFontFamily
                fontSizePx=$fontSize; bold=$true; textColor=$textColor; underline=$underline; underlineOffsetPx=$underlineOffset; underlineThicknessPx=$underlineThickness; underlineColor=$underlineColor; resetInlineFormattingBefore=$true; lineHeightPx=[int]$Formatting.BodyLineHeightPx; mobileLineHeightPx=$(if ($level -eq 2) { [int]$Formatting.MobileSectionHeadingLineHeightPx } else { [int]$Formatting.MobileSubheadingLineHeightPx }); alignment='left'
                postcondition=[pscustomobject]@{ requireStandaloneParagraph=$true; forbidMergedPreviousText=$true; forbidMergedNextText=$true; requireNativeFontFamily=[string]$Formatting.HeadingFontFamily }
            })
            $Actions.Add([pscustomobject]@{
                order=$Order.Value++; type='InsertVerticalSpacer'; purpose='HeadingBottom'; headingLevel=$level
                heightPx=$bottomPx; mobileHeightPx=$(if ($level -eq 3) { [int]$Formatting.MobileSubheadingBottomPx } else { $bottomPx }); naverFontSizePx=$bottomNativeFontPx; naverLineHeightPercent=$bottomNativeLineHeightPercent
                postcondition=[pscustomobject]@{ requireStandaloneBlankParagraph=$true; measuredHeightPx=$bottomPx; tolerancePx=0.5 }
            })
            continue
        }
        $type = if ($block -match '(?is)^<p\b') { 'PasteStandaloneParagraphBlock' } else { 'PasteRenderedAtomicBlock' }
        $isCallout = ($block -match '(?is)(?:data-blog-six-facts|background(?:-color)?\s*:)')
        $blockRole = if ($block -match '(?is)\bsolidb-responsive-table\b') { 'DataTable' } elseif ($block -match '(?is)data-naver-role="overview-box"') { 'OverviewBox' } elseif ($block -match '(?is)data-naver-role="reference-group"') { 'ReferenceGroup' } else { '' }
        if ($type -eq 'PasteStandaloneParagraphBlock') {
            $block = [regex]::Replace($block, '(?i)text-align\s*:\s*(?:left|justify)(?:\s*;\s*text-align-last\s*:\s*left)?', 'text-align:justify;text-align-last:left')
        }
        $BlockSequence.Value++
        $path = Write-NaverBlockFile -Block $block -Directory $BlockDirectory -Sequence $BlockSequence.Value
        $Actions.Add([pscustomobject]@{
            order=$Order.Value++; type=$type; path=$path; blockRole=$blockRole
            formatting=[pscustomobject]@{
                fontFamily=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [string]$Formatting.BodyFontFamily } else { $null })
                fontSizePx=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [int]$Formatting.BodyFontSizePx } else { $null })
                lineHeightPx=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [int]$Formatting.BodyLineHeightPx } else { $null })
                alignment=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [string]$Formatting.TextAlignment } else { $null })
                lastLineAlignment=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [string]$Formatting.LastLineAlignment } else { $null })
                applyWithNativeToolbar=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [bool]$Formatting.RequireNativeFontApplication } else { $false })
                bold=$(if ($type -eq 'PasteStandaloneParagraphBlock') { $false } else { $null })
                resetInlineFormattingBefore=$(if ($type -eq 'PasteStandaloneParagraphBlock') { $true } else { $false })
                applyToCalloutBody=$isCallout
                calloutBodyFontFamily=$(if ($isCallout) { [string]$Formatting.BodyFontFamily } else { $null })
                calloutBodyAlignment=$(if ($isCallout) { [string]$Formatting.TextAlignment } else { $null })
                calloutLastLineAlignment=$(if ($isCallout) { [string]$Formatting.LastLineAlignment } else { $null })
                calloutBodyBold=$(if ($isCallout) { $false } else { $null })
                preserveCalloutTitleLeft=$isCallout
            }
            postcondition=[pscustomobject]@{
                requireSingleTopLevelBlock=$true
                requireStandaloneParagraph=($type -eq 'PasteStandaloneParagraphBlock')
                paragraphBottomPx=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [int]$Formatting.ParagraphBottomPx } else { $null })
                requireNativeFontFamily=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [string]$Formatting.BodyFontFamily } else { $null })
                requireRightEdgeAlignment=($type -eq 'PasteStandaloneParagraphBlock')
                requireLastLineLeft=($type -eq 'PasteStandaloneParagraphBlock')
                requireCalloutBodyRightEdgeAlignment=$isCallout
                requireCalloutNativeFont=$isCallout
            }
        })
    }
}

function Assert-AtomicEditorPlan([object[]]$Actions, [object]$Formatting) {
    if (@($Actions | Where-Object type -eq 'PasteRenderedSegment').Count -gt 0) {
        throw '네이버 편집 계획에 제목과 본문을 합치는 구간 붙여넣기가 포함되어 있습니다.'
    }

    $headingCount = 0
    $anchors = @($Actions | Where-Object type -eq 'InsertImageAnchor')
    $uploads = @($Actions | Where-Object type -eq 'UploadImageAtAnchor')
    if ($anchors.Count -ne 4 -or $uploads.Count -ne 4) {
        throw '이미지 앵커와 최종 업로드 동작은 각각 정확히 4개여야 합니다.'
    }
    $firstUploadIndex = [array]::IndexOf($Actions, $uploads[0])
    if (@($Actions[($firstUploadIndex + 1)..($Actions.Count - 1)] | Where-Object type -in @('PasteStandaloneParagraphBlock','PasteRenderedAtomicBlock','InsertStandaloneHeading','InsertVerticalSpacer')).Count -gt 0) {
        throw '첫 이미지 업로드 뒤에는 본문·소제목·간격 붙여넣기 동작이 올 수 없습니다.'
    }
    $anchorIds = @($anchors | ForEach-Object { [string]$_.anchorId })
    $uploadAnchorIds = @($uploads | ForEach-Object { [string]$_.anchorId })
    [array]::Reverse($anchorIds)
    if (($anchorIds -join '|') -ne ($uploadAnchorIds -join '|')) {
        throw '이미지는 문서 뒤쪽 앵커부터 역순으로 업로드해야 합니다.'
    }
    for ($index = 0; $index -lt $Actions.Count; $index++) {
        $action = $Actions[$index]
        if ([string]$action.type -eq 'InsertStandaloneHeading') {
            $headingCount++
            if ($index -eq 0 -or $index -eq ($Actions.Count - 1)) {
                throw '독립 소제목 앞뒤에 간격 동작이 없습니다.'
            }
            $before = $Actions[$index - 1]
            $after = $Actions[$index + 1]
            $level = [int]$action.level
            $expectedTop = if ($level -eq 2) { [int]$Formatting.SectionHeadingTopPx } else { [int]$Formatting.SubheadingTopPx }
            $expectedBottom = if ($level -eq 2) { [int]$Formatting.SectionHeadingBottomPx } else { [int]$Formatting.SubheadingBottomPx }
            $validTop = ([string]$before.type -eq 'InsertVerticalSpacer' -and [string]$before.purpose -eq 'HeadingTop' -and [int]$before.heightPx -eq $expectedTop)
            if ($level -eq 2 -and [string]$before.type -eq 'PasteRenderedAtomicBlock' -and [string]$before.blockRole -in @('DataTable','OverviewBox')) {
                $validTop = ([bool]$before.postcondition.requireDirectlyBeforeHeadingWhenApplicable -and [int]$before.postcondition.maximumRenderedHeadingGapPx -eq [int]$Formatting.TableToHeadingPx)
            }
            if ($level -eq 3 -and [string]$before.purpose -eq 'ParentHeadingToSubheading') {
                $validTop = ([int]$before.heightPx -eq [int]$Formatting.ParentHeadingToSubheadingPx)
            }
            if (-not $validTop) { throw "독립 H$level 소제목 위 간격 동작이 올바르지 않습니다." }
            $validBottom = ([string]$after.type -eq 'InsertVerticalSpacer' -and [string]$after.purpose -eq 'HeadingBottom' -and [int]$after.heightPx -eq $expectedBottom)
            if ([string]$after.purpose -eq 'HeadingToImage') { $validBottom = ([int]$after.heightPx -eq [int]$Formatting.HeadingToImagePx) }
            if ($level -eq 2 -and [string]$after.purpose -eq 'ParentHeadingToSubheading') { $validBottom = ([int]$after.heightPx -eq [int]$Formatting.ParentHeadingToSubheadingPx) }
            if ([string]$after.type -eq 'InsertImageAnchor' -and [bool]$after.postcondition.requireDirectlyAfterHeadingWhenApplicable) { $validBottom = $true }
            if (-not $validBottom) { throw "독립 H$level 소제목 아래 간격 동작이 올바르지 않습니다." }
            if ([string]::IsNullOrWhiteSpace([string]$action.text) -or
                -not [bool]$action.bold -or
                ($level -eq 2 -and [bool]$action.underline) -or
                ($level -eq 3 -and [bool]$action.underline) -or
                ($level -eq 2 -and [int]$action.underlineOffsetPx -ne [int]$Formatting.SectionHeadingUnderlineOffsetPx) -or
                ($level -eq 2 -and [int]$action.underlineThicknessPx -ne [int]$Formatting.SectionHeadingUnderlineThicknessPx) -or
                ($level -eq 2 -and [string]$action.underlineColor -ne [string]$Formatting.SectionHeadingUnderlineColor) -or
                ($level -eq 2 -and [string]$action.textColor -ne [string]$Formatting.SectionHeadingColor) -or
                ($level -eq 3 -and [string]$action.textColor -ne '#111111') -or
                ($level -eq 2 -and [int]$action.fontSizePx -ne [int]$Formatting.SectionHeadingFontSizePx) -or
                ($level -eq 3 -and [int]$action.fontSizePx -ne [int]$Formatting.SubheadingFontSizePx) -or
                -not [bool]$action.resetInlineFormattingBefore -or
                -not [bool]$action.postcondition.requireStandaloneParagraph -or
                -not [bool]$action.postcondition.forbidMergedPreviousText -or
                -not [bool]$action.postcondition.forbidMergedNextText) {
                throw '독립 소제목의 텍스트 또는 합침 금지 사후조건이 올바르지 않습니다.'
            }
        }

        if ([string]$action.type -eq 'PasteStandaloneParagraphBlock') {
            if (-not [bool]$action.postcondition.requireSingleTopLevelBlock -or
                -not [bool]$action.postcondition.requireStandaloneParagraph -or
                [int]$action.postcondition.paragraphBottomPx -ne [int]$Formatting.ParagraphBottomPx -or
                [string]$action.formatting.fontFamily -ne [string]$Formatting.BodyFontFamily -or
                [string]$action.formatting.alignment -ne 'justify' -or
                [bool]$action.formatting.bold -or
                -not [bool]$action.formatting.resetInlineFormattingBefore -or
                -not [bool]$action.postcondition.requireRightEdgeAlignment -or
                -not [bool]$action.postcondition.requireLastLineLeft) {
                throw '일반 문단의 독립 블록·글꼴·양쪽 정렬 또는 문단 뒤 18px 사후조건이 올바르지 않습니다.'
            }
        }

        if ([string]$action.type -eq 'PasteRenderedAtomicBlock') {
            $blockHtml = [IO.File]::ReadAllText([string]$action.path, [Text.Encoding]::UTF8)
            if ($blockHtml -match 'data-naver-role="(?:section-heading|subheading)"') {
                throw '본문 원자 블록 안에 소제목이 포함되어 있습니다.'
            }
            if ([bool]$action.formatting.applyToCalloutBody -and
                ([string]$action.formatting.calloutBodyFontFamily -ne [string]$Formatting.BodyFontFamily -or
                 [string]$action.formatting.calloutBodyAlignment -ne 'justify' -or
                 [bool]$action.formatting.calloutBodyBold -or
                 -not [bool]$action.postcondition.requireCalloutBodyRightEdgeAlignment)) {
                throw '강조 상자 본문의 기본서체 또는 양쪽 정렬 실행 조건이 올바르지 않습니다.'
            }
        }
    }
    if ($headingCount -eq 0) { throw '네이버 편집 계획에 독립 소제목이 없습니다.' }
}

function New-ComputerUseExecutionContract([object]$Plan) {
    $supportedTypes = @(
        'OpenNewPost','ClearEditorBody','SetTitle','NormalizeBodyDefaults','InsertVerticalSpacer','InsertStandaloneHeading',
        'PasteStandaloneParagraphBlock','PasteRenderedAtomicBlock','InsertImageAnchor','UploadImageAtAnchor',
        'VerifyWholeEditor','SetTags','StopBeforePublicationSettings'
    )
    $steps = New-Object 'System.Collections.Generic.List[object]'
    foreach ($action in @($Plan.actions | Sort-Object order)) {
        if ($supportedTypes -notcontains [string]$action.type) {
            throw "컴퓨터 사용 실행기가 지원하지 않는 편집 동작입니다: $($action.type)"
        }
        $steps.Add([pscustomobject]@{
            stepId = ('step-{0:D3}' -f [int]$action.order)
            action = [string]$action.type
            payload = $action
            precondition = [pscustomobject]@{
                requireNewPostEditor = $true
                forbidExistingPostEdit = $true
                requireEditorBodyFocus = (@('ClearEditorBody','NormalizeBodyDefaults','InsertVerticalSpacer','InsertStandaloneHeading','PasteStandaloneParagraphBlock','PasteRenderedAtomicBlock','InsertImageAnchor','UploadImageAtAnchor') -contains [string]$action.type)
            }
            postcondition = [pscustomobject]@{
                requireActionSuccess = $true
                requireIndependentEditorComponent = (@('InsertStandaloneHeading','PasteStandaloneParagraphBlock','PasteRenderedAtomicBlock','InsertImageAnchor','UploadImageAtAnchor') -contains [string]$action.type)
                requireMeasuredSpacing = ([string]$action.type -eq 'InsertVerticalSpacer')
                requireNativeFontVerification = ((@('InsertStandaloneHeading','PasteStandaloneParagraphBlock') -contains [string]$action.type) -or [bool]$action.formatting.applyToCalloutBody)
                requireRightEdgeAlignmentVerification = (([string]$action.type -eq 'PasteStandaloneParagraphBlock') -or [bool]$action.formatting.applyToCalloutBody)
                stopImmediatelyOnMismatch = $true
            }
        })
    }
    return [pscustomobject]@{
        schemaVersion = 4
        contentId = [string]$Plan.contentId
        executionMode = 'ComputerUseNewPostOnly'
        executionStatus = 'NotExecuted'
        completionClaimAllowed = $false
        guards = [pscustomobject]@{
            existingPostModificationForbidden = $true
            publicationSettingsForbidden = $true
            publicOrPrivatePublishForbidden = $true
            requireActionByActionObservation = $true
            requirePcAndMobileResultValidation = $true
            requireWholeEditorAuditBeforeStop = $true
            rejectInheritedBoldBody = $true
            forbidGlobalMixedSelectionBoldToggle = $true
            requireExactParagraphSelection = $true
            requireSetStateNotToggle = $true
            requireToolbarPostconditionAfterEveryTextBlock = $true
            preserveListedInlineBoldLabels = $true
            browserBinding = 'ChromeDevToolsDedicatedProfile'
            forbidWindowsAppWindowBinding = $true
            requireOuterAndInnerUrlMatch = $true
            requireSingleReusableEditorTab = $true
            computerUseUrlInspectionRequired = $false
            directCdpUrlVerificationRequired = $true
            failClosedWhenUrlUncertain = $true
            selectionMode = 'NativeTripleClickRenderedParagraph'
            scrollMode = 'CenterVisibleOutsideFixedToolbar'
            forbidAccessibilitySelectText = $true
            requireRenderedDomPostcondition = $true
            rejectToolbarOnlyAudit = $true
            requiredBodyFontClass = 'se-fs15'
            forbiddenBodyFontClass = 'se-fs30'
            requiredBodyBoldElementCount = 0
            maxRepairPasses = 2
            imageConstructionMode = 'TextFirstThenReverseAnchorUpload'
            forbidFormattedPasteAfterFirstImageUpload = $true
            requireAllPriorImageUrlsAfterEveryUpload = $true
        }
        steps = @($steps.ToArray())
    }
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
        $segments.Add([pscustomobject]@{ order = $index + 1; path = $segmentPath; fragment = $fragment })
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
$html = Apply-NaverReaderTermRules -Html $html
$html = Normalize-NaverImagePlacement -Html $html
Assert-NaverReaderTerms -Html $html -Formatting $config.EditorFormatting
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
$actions.Add([pscustomobject]@{ order = 2; type = 'ClearEditorBody'; preserveTitle = $false; requireNewPostEditor = $true })
$actions.Add([pscustomobject]@{ order = 3; type = 'SetTitle'; text = [string]$job.RecommendedTitle })
$actions.Add([pscustomobject]@{
    order = 4; type = 'NormalizeBodyDefaults'; fontFamily = [string]$config.EditorFormatting.BodyFontFamily
    fontSizePx = [int]$config.EditorFormatting.BodyFontSizePx; lineHeightPx = [int]$config.EditorFormatting.BodyLineHeightPx
    alignment = [string]$config.EditorFormatting.TextAlignment; lastLineAlignment = [string]$config.EditorFormatting.LastLineAlignment
    bold = $false; italic = $false; underline = $false; strike = $false
})
$order = 5
$blockSequence = 0
$blockDirectory = Join-Path $outputRoot 'blocks'
for ($index = 0; $index -lt 4; $index++) {
    Add-AtomicSegmentActions -Actions $actions -Order ([ref]$order) -Segment $segments[$index] -BlockDirectory $blockDirectory -Formatting $config.EditorFormatting -BlockSequence ([ref]$blockSequence)
    if ($actions.Count -gt 0) {
        $lastTextAction = $actions[$actions.Count - 1]
        if ([string]$lastTextAction.type -eq 'InsertVerticalSpacer' -and [string]$lastTextAction.purpose -eq 'HeadingBottom') {
            # 네이버는 제목과 이미지 구성요소 사이에 자체 간격을 만듭니다. 별도 빈 문단을
            # 추가하면 목표값과 기본 간격이 합산되므로 제목 바로 아래 이미지는 빈 문단 없이 붙입니다.
            $actions.RemoveAt($actions.Count - 1)
        }
    }
    $role = @($config.ImageAutomation.Roles | Sort-Object Order)[$index]
    $anchorId = ('NTE_IMAGE_{0:D2}' -f ($index + 1))
    $actions.Add([pscustomobject]@{
        order = $order++; type = 'InsertImageAnchor'; anchorId = $anchorId; text = ('[[' + $anchorId + ']]')
        postcondition = [pscustomobject]@{ requireStandaloneParagraph = $true; requireUniqueExactText = $true; forbidVisibleAfterUpload = $true; requireDirectlyAfterHeadingWhenApplicable = $true; maximumRenderedHeadingGapPx = 24 }
    })
}
Add-AtomicSegmentActions -Actions $actions -Order ([ref]$order) -Segment $segments[4] -BlockDirectory $blockDirectory -Formatting $config.EditorFormatting -BlockSequence ([ref]$blockSequence)
$actions.Add([pscustomobject]@{ order = $order++; type = 'SetTags'; values = @($tags) })
for ($index = 3; $index -ge 0; $index--) {
    $role = @($config.ImageAutomation.Roles | Sort-Object Order)[$index]
    $anchorId = ('NTE_IMAGE_{0:D2}' -f ($index + 1))
    $actions.Add([pscustomobject]@{
        order = $order++; type = 'UploadImageAtAnchor'; anchorId = $anchorId; anchorText = ('[[' + $anchorId + ']]')
        path = (Join-Path (Join-Path $imageRoot 'optimized') ([string]$role.OutputFileName)); alignment = 'center'
        displayWidth = [int]$config.ImageAutomation.EditorDisplayWidth; documentOrder = ($index + 1)
        requireServerUrl = 'https://blogfiles.pstatic.net/'; requirePriorImagesStable = $true
    })
}
$expectedHeadings = @($actions | Where-Object type -eq 'InsertStandaloneHeading' | ForEach-Object { [string]$_.text })
$expectedParagraphCount = @($actions | Where-Object type -eq 'PasteStandaloneParagraphBlock').Count
$actions.Add([pscustomobject]@{
    order = $order++; type = 'VerifyWholeEditor'; expectedHeadingTexts = @($expectedHeadings)
    expectedHeadingCount = $expectedHeadings.Count; expectedParagraphCount = $expectedParagraphCount
    requireStandaloneHeadings = $true; requireBodyBoldFalse = $true; requireCalloutBodyBoldFalse = $true
    requireNativeBodyFont = [string]$config.EditorFormatting.BodyFontFamily
    requireBodyFontSizePx = [int]$config.EditorFormatting.BodyFontSizePx
    requireBodyLineHeightPx = [int]$config.EditorFormatting.BodyLineHeightPx
    requireHeadingTopPx = [int]$config.EditorFormatting.SectionHeadingTopPx
    requireHeadingBottomPx = [int]$config.EditorFormatting.SectionHeadingBottomPx
    requireParagraphBottomPx = [int]$config.EditorFormatting.ParagraphBottomPx
    rejectMergedHeadingBody = $true; rejectUnexpectedBoldParagraphs = $true
})
$actions.Add([pscustomobject]@{ order = $order++; type = 'StopBeforePublicationSettings' })
Assert-AtomicEditorPlan -Actions @($actions.ToArray()) -Formatting $config.EditorFormatting

$planPath = Join-Path $outputRoot '네이버편집계획.json'
$plan = [pscustomobject]@{
    schemaVersion = 3
    contentId = $ContentId
    sourceMode = 'GoogleAutomationCopy'
    reusedExistingNaverFeatures = @('ImagePlan','ImageOptimization','ImageValidation')
    title = [string]$job.RecommendedTitle
    category = [string]$config.Naver.DefaultCategory
    tags = @($tags)
    imageManifest = $imageManifestPath
    actions = @($actions.ToArray())
    atomicBlockCount = $blockSequence
    headingInsertionMode = 'StandaloneParagraphWithMeasuredSpacers'
    mobileHeadingSpacing = [pscustomobject]@{
        required = [bool]$config.EditorFormatting.RequireMobileHeadingGapValidation
        tolerancePx = [int]$config.EditorFormatting.MobileHeadingGapTolerancePx
        dominancePx = [int]$config.EditorFormatting.MobileHeadingGapDominancePx
        sectionTopPx = [int]$config.EditorFormatting.SectionHeadingTopPx
        sectionBottomPx = [int]$config.EditorFormatting.SectionHeadingBottomPx
        subheadingTopPx = [int]$config.EditorFormatting.SubheadingTopPx
        subheadingBottomPx = [int]$config.EditorFormatting.SubheadingBottomPx
        parentToSubheadingPx = [int]$config.EditorFormatting.ParentHeadingToSubheadingPx
        mobileParentToSubheadingPx = [int]$config.EditorFormatting.MobileParentHeadingToSubheadingPx
        mobileSubheadingBottomPx = [int]$config.EditorFormatting.MobileSubheadingBottomPx
        mobileSectionLineHeightPx = [int]$config.EditorFormatting.MobileSectionHeadingLineHeightPx
        mobileSubheadingLineHeightPx = [int]$config.EditorFormatting.MobileSubheadingLineHeightPx
        wrappedLineHeightTolerancePx = [int]$config.EditorFormatting.MobileWrappedHeadingLineHeightTolerancePx
    }
    stopPoint = 'BeforePublicationSettings'
    publicationSettingsOpened = $false
    publicPublishPerformed = $false
    privatePublishPerformed = $false
}
$plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding UTF8
$executionContractPath = Join-Path $outputRoot '네이버편집실행계약.json'
$executionContract = New-ComputerUseExecutionContract -Plan $plan
$executionContract | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $executionContractPath -Encoding UTF8

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
    executionContract = $executionContractPath
    executionStatus = 'NotExecuted'
    completionClaimAllowed = $false
    title = [string]$job.RecommendedTitle
    tagCount = $tags.Count
    segmentCount = $segments.Count
    imageCount = $promptSections.Count
    stopPoint = 'BeforePublicationSettings'
} | ConvertTo-Json -Depth 5

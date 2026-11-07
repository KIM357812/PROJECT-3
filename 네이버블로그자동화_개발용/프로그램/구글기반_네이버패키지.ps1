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
        '<div data-naver-role="subheading" style="width:100%;margin:{0}px 0 {1}px 0;box-sizing:border-box;"><p style="margin:0;font-size:{2}px;line-height:27px;font-weight:700;color:#222;text-align:left;word-break:keep-all;">{3}</p></div>' -f
            [int]$Formatting.SectionHeadingTopPx,
            [int]$Formatting.SectionHeadingBottomPx,
            [int]$Formatting.SubheadingFontSizePx,
            $match.Groups['text'].Value
    })
    $result = [regex]::Replace($result, '(?i)font-size\s*:\s*16px', ('font-size:{0}px' -f [int]$Formatting.BodyFontSizePx))
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
    return $result.Trim()
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
            $fontSize = if ($role -eq 'section-heading') { [int]$Formatting.SectionHeadingFontSizePx } else { [int]$Formatting.SubheadingFontSizePx }
            $Actions.Add([pscustomobject]@{
                order=$Order.Value++; type='InsertVerticalSpacer'; purpose='HeadingTop'
                heightPx=[int]$Formatting.SectionHeadingTopPx; naverFontSizePx=16; naverLineHeightPercent=200
                postcondition=[pscustomobject]@{ requireStandaloneBlankParagraph=$true; measuredHeightPx=[int]$Formatting.SectionHeadingTopPx }
            })
            $Actions.Add([pscustomobject]@{
                order=$Order.Value++; type='InsertStandaloneHeading'; level=($(if ($role -eq 'section-heading') { 2 } else { 3 }))
                text=(ConvertFrom-HtmlText $heading.Groups['text'].Value); fontFamily=[string]$Formatting.HeadingFontFamily
                fontSizePx=$fontSize; bold=$true; lineHeightPx=[int]$Formatting.BodyLineHeightPx; alignment='left'
                postcondition=[pscustomobject]@{ requireStandaloneParagraph=$true; forbidMergedPreviousText=$true; forbidMergedNextText=$true; requireNativeFontFamily=[string]$Formatting.HeadingFontFamily }
            })
            $Actions.Add([pscustomobject]@{
                order=$Order.Value++; type='InsertVerticalSpacer'; purpose='HeadingBottom'
                heightPx=[int]$Formatting.SectionHeadingBottomPx; naverFontSizePx=13; naverLineHeightPercent=160
                postcondition=[pscustomobject]@{ requireStandaloneBlankParagraph=$true; measuredHeightPx=[int]$Formatting.SectionHeadingBottomPx; tolerancePx=0.5 }
            })
            continue
        }
        $type = if ($block -match '(?is)^<p\b') { 'PasteStandaloneParagraphBlock' } else { 'PasteRenderedAtomicBlock' }
        $isCallout = ($block -match '(?is)(?:data-blog-six-facts|background(?:-color)?\s*:)')
        if ($type -eq 'PasteStandaloneParagraphBlock') {
            $block = [regex]::Replace($block, '(?i)text-align\s*:\s*(?:left|justify)(?:\s*;\s*text-align-last\s*:\s*left)?', 'text-align:justify;text-align-last:left')
        }
        $BlockSequence.Value++
        $path = Write-NaverBlockFile -Block $block -Directory $BlockDirectory -Sequence $BlockSequence.Value
        $Actions.Add([pscustomobject]@{
            order=$Order.Value++; type=$type; path=$path
            formatting=[pscustomobject]@{
                fontFamily=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [string]$Formatting.BodyFontFamily } else { $null })
                fontSizePx=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [int]$Formatting.BodyFontSizePx } else { $null })
                lineHeightPx=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [int]$Formatting.BodyLineHeightPx } else { $null })
                alignment=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [string]$Formatting.TextAlignment } else { $null })
                lastLineAlignment=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [string]$Formatting.LastLineAlignment } else { $null })
                applyWithNativeToolbar=$(if ($type -eq 'PasteStandaloneParagraphBlock') { [bool]$Formatting.RequireNativeFontApplication } else { $false })
                applyToCalloutBody=$isCallout
                calloutBodyFontFamily=$(if ($isCallout) { [string]$Formatting.BodyFontFamily } else { $null })
                calloutBodyAlignment=$(if ($isCallout) { [string]$Formatting.TextAlignment } else { $null })
                calloutLastLineAlignment=$(if ($isCallout) { [string]$Formatting.LastLineAlignment } else { $null })
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
    for ($index = 0; $index -lt $Actions.Count; $index++) {
        $action = $Actions[$index]
        if ([string]$action.type -eq 'InsertStandaloneHeading') {
            $headingCount++
            if ($index -eq 0 -or $index -eq ($Actions.Count - 1)) {
                throw '독립 소제목 앞뒤에 간격 동작이 없습니다.'
            }
            $before = $Actions[$index - 1]
            $after = $Actions[$index + 1]
            if ([string]$before.type -ne 'InsertVerticalSpacer' -or [string]$before.purpose -ne 'HeadingTop' -or
                [int]$before.heightPx -ne [int]$Formatting.SectionHeadingTopPx) {
                throw '독립 소제목 위 32px 간격 동작이 올바르지 않습니다.'
            }
            if ([string]$after.type -ne 'InsertVerticalSpacer' -or [string]$after.purpose -ne 'HeadingBottom' -or
                [int]$after.heightPx -ne [int]$Formatting.SectionHeadingBottomPx) {
                throw '독립 소제목 아래 21px 간격 동작이 올바르지 않습니다.'
            }
            if ([string]::IsNullOrWhiteSpace([string]$action.text) -or
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
                 -not [bool]$action.postcondition.requireCalloutBodyRightEdgeAlignment)) {
                throw '강조 상자 본문의 기본서체 또는 양쪽 정렬 실행 조건이 올바르지 않습니다.'
            }
        }
    }
    if ($headingCount -eq 0) { throw '네이버 편집 계획에 독립 소제목이 없습니다.' }
}

function New-ComputerUseExecutionContract([object]$Plan) {
    $supportedTypes = @(
        'OpenNewPost','SetTitle','InsertVerticalSpacer','InsertStandaloneHeading',
        'PasteStandaloneParagraphBlock','PasteRenderedAtomicBlock','UploadImage',
        'SetTags','StopBeforePublicationSettings'
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
                requireEditorBodyFocus = (@('InsertVerticalSpacer','InsertStandaloneHeading','PasteStandaloneParagraphBlock','PasteRenderedAtomicBlock','UploadImage') -contains [string]$action.type)
            }
            postcondition = [pscustomobject]@{
                requireActionSuccess = $true
                requireIndependentEditorComponent = (@('InsertStandaloneHeading','PasteStandaloneParagraphBlock','PasteRenderedAtomicBlock') -contains [string]$action.type)
                requireMeasuredSpacing = ([string]$action.type -eq 'InsertVerticalSpacer')
                requireNativeFontVerification = ((@('InsertStandaloneHeading','PasteStandaloneParagraphBlock') -contains [string]$action.type) -or [bool]$action.formatting.applyToCalloutBody)
                requireRightEdgeAlignmentVerification = (([string]$action.type -eq 'PasteStandaloneParagraphBlock') -or [bool]$action.formatting.applyToCalloutBody)
                stopImmediatelyOnMismatch = $true
            }
        })
    }
    return [pscustomobject]@{
        schemaVersion = 1
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
$blockSequence = 0
$blockDirectory = Join-Path $outputRoot 'blocks'
for ($index = 0; $index -lt 4; $index++) {
    Add-AtomicSegmentActions -Actions $actions -Order ([ref]$order) -Segment $segments[$index] -BlockDirectory $blockDirectory -Formatting $config.EditorFormatting -BlockSequence ([ref]$blockSequence)
    $role = @($config.ImageAutomation.Roles | Sort-Object Order)[$index]
    $actions.Add([pscustomobject]@{ order = $order++; type = 'UploadImage'; path = (Join-Path (Join-Path $imageRoot 'optimized') ([string]$role.OutputFileName)); alignment = 'center'; displayWidth = [int]$config.ImageAutomation.EditorDisplayWidth })
}
Add-AtomicSegmentActions -Actions $actions -Order ([ref]$order) -Segment $segments[4] -BlockDirectory $blockDirectory -Formatting $config.EditorFormatting -BlockSequence ([ref]$blockSequence)
$actions.Add([pscustomobject]@{ order = $order++; type = 'SetTags'; values = @($tags) })
$actions.Add([pscustomobject]@{ order = $order++; type = 'StopBeforePublicationSettings' })
Assert-AtomicEditorPlan -Actions @($actions.ToArray()) -Formatting $config.EditorFormatting

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
    atomicBlockCount = $blockSequence
    headingInsertionMode = 'StandaloneParagraphWithMeasuredSpacers'
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

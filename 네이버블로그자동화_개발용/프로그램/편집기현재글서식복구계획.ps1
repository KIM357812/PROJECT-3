#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EditorPlanPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $EditorPlanPath -PathType Leaf)) {
    throw "편집 계획을 찾을 수 없습니다: $EditorPlanPath"
}
$plan = Get-Content -LiteralPath $EditorPlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$plan.stopPoint -ne 'BeforePublicationSettings' -or [bool]$plan.publicationSettingsOpened) {
    throw '발행 설정 전 정지 새 글 계획만 복구할 수 있습니다.'
}

$headings = @($plan.actions | Where-Object type -eq 'InsertStandaloneHeading' | Sort-Object order)
$paragraphs = @($plan.actions | Where-Object type -eq 'PasteStandaloneParagraphBlock')
$callouts = @($plan.actions | Where-Object { $_.type -eq 'PasteRenderedAtomicBlock' -and $_.formatting.applyToCalloutBody })
if ($headings.Count -eq 0 -or $paragraphs.Count -eq 0) { throw '복구할 소제목 또는 일반 문단이 없습니다.' }

$bodyParagraphTexts = New-Object 'System.Collections.Generic.List[string]'
foreach ($paragraph in $paragraphs) {
    $html = Get-Content -LiteralPath ([string]$paragraph.path) -Raw -Encoding UTF8
    $html = [regex]::Replace($html, '(?is)<head\b[^>]*>.*?</head>', '')
    $bodyText = [Net.WebUtility]::HtmlDecode([regex]::Replace($html, '(?is)<[^>]+>', ''))
    $bodyText = [regex]::Replace($bodyText, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($bodyText)) { throw '일반 문단 블록에서 정확 문자열을 추출하지 못했습니다.' }
    $bodyParagraphTexts.Add($bodyText)
}

$calloutTitles = New-Object 'System.Collections.Generic.List[string]'
$calloutBodyTexts = New-Object 'System.Collections.Generic.List[string]'
$mixedCalloutParagraphs = New-Object 'System.Collections.Generic.List[object]'
foreach ($callout in $callouts) {
    $html = Get-Content -LiteralPath ([string]$callout.path) -Raw -Encoding UTF8
    $matches = @([regex]::Matches($html, '(?is)<p\b(?<attributes>[^>]*)>(?<text>.*?)</p>'))
    # Six-fact rows from the source are leaf divs, not paragraphs.
    $matches += @([regex]::Matches($html, '(?is)<div\b(?<attributes>[^>]*)>(?<text>\s*<strong\b[^>]*>.*?</strong>(?:(?!</?div\b).)*?)</div>'))
    foreach ($match in $matches) {
        $text = [Net.WebUtility]::HtmlDecode([regex]::Replace($match.Groups['text'].Value, '(?is)<[^>]+>', ' '))
        $text = [regex]::Replace($text, '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($match.Groups['attributes'].Value -match '(?i)font-weight\s*:\s*700') {
            $calloutTitles.Add($text)
        } else {
            $boldLabels = New-Object 'System.Collections.Generic.List[string]'
            foreach ($labelMatch in @([regex]::Matches($match.Groups['text'].Value, '(?is)<(?:strong|b)\b[^>]*>(?<label>.*?)</(?:strong|b)>|<span\b(?=[^>]*font-weight\s*:\s*700)[^>]*>(?<label>.*?)</span>'))) {
                $label = [Net.WebUtility]::HtmlDecode([regex]::Replace($labelMatch.Groups['label'].Value, '(?is)<[^>]+>', ' '))
                $label = [regex]::Replace($label, '\s+', ' ').Trim()
                if ($label) { $boldLabels.Add($label) }
            }
            if ($boldLabels.Count -gt 0) {
                $mixedCalloutParagraphs.Add([pscustomobject]@{ text=$text; boldLabels=@($boldLabels.ToArray()) })
            } else {
                $calloutBodyTexts.Add($text)
            }
        }
    }
}

$actions = New-Object 'System.Collections.Generic.List[object]'
$sequence = 1
$actions.Add([pscustomobject]@{
    sequence=$sequence++; action='VerifyNewPostEditor'; forbidExistingPost=$true
    browserBinding='ChromeDevToolsDedicatedProfile'; forbidWindowsAppWindowBinding=$true
    requireSingleReusableEditorTab=$true; computerUseUrlInspectionRequired=$false; directCdpUrlVerificationRequired=$true
    outerUrl='https://blog.naver.com/ij1128?Redirect=Write&'; innerFrameUrlPattern='https://blog.naver.com/*/postwrite*'
    requireOuterAndInnerUrlMatch=$true; failClosedWhenUrlUncertain=$true
})
foreach ($text in @($bodyParagraphTexts.ToArray())) {
    $actions.Add([pscustomobject]@{
        sequence=$sequence++; action='ApplyBodyParagraphByExactText'; text=$text; expectedOccurrence=1
        selectionMode='NativeTripleClickRenderedParagraph'; mutationMode='SetStateNotToggle'
        scrollMode='CenterVisibleOutsideFixedToolbar'; forbidAccessibilitySelectText=$true
        fontFamily='기본서체'; fontSizePx=15; lineHeightPx=27; alignment='justify'; lastLineAlignment='left'
        bold=$false; italic=$false; underline=$false; strike=$false
        postcondition=[pscustomobject]@{
            paragraphStyle='본문'; requireStandaloneParagraph=$true
            requireRenderedDom=$true; requiredFontClass='se-fs15'; forbiddenFontClass='se-fs30'
            requiredFontFamilyClass='se-ff-system'; expectedBoldElementCount=0
            expectedLineHeight='1.8'; expectedAlignment='justify'
        }
    })
}
foreach ($text in @($calloutBodyTexts.ToArray())) {
    $actions.Add([pscustomobject]@{
        sequence=$sequence++; action='ApplyCalloutBodyByExactText'; text=$text; expectedOccurrence=1
        selectionMode='NativeTripleClickRenderedParagraph'; mutationMode='SetStateNotToggle'
        scrollMode='CenterVisibleOutsideFixedToolbar'; forbidAccessibilitySelectText=$true
        fontFamily='기본서체'; fontSizePx=15; lineHeightPx=24; alignment='justify'
        bold=$false; italic=$false; underline=$false; strike=$false
        postcondition=[pscustomobject]@{
            requireCalloutBody=$true; requireRenderedDom=$true; requiredFontClass='se-fs15'
            forbiddenFontClass='se-fs30'; requiredFontFamilyClass='se-ff-system'
            expectedBoldElementCount=0; expectedLineHeight='1.6'; expectedAlignment='justify'
        }
    })
}
foreach ($paragraph in @($mixedCalloutParagraphs.ToArray())) {
    $actions.Add([pscustomobject]@{
        sequence=$sequence++; action='ApplyMixedCalloutParagraphByExactText'; text=[string]$paragraph.text; expectedOccurrence=1
        selectionMode='NativeTripleClickRenderedParagraph'; mutationMode='ResetThenApplyInlineRanges'
        scrollMode='CenterVisibleOutsideFixedToolbar'; forbidAccessibilitySelectText=$true
        fontFamily='기본서체'; fontSizePx=15; lineHeightPx=24; alignment='justify'; defaultBold=$false
        boldLabels=@($paragraph.boldLabels)
        postcondition=[pscustomobject]@{
            requireDefaultBodyBoldFalse=$true; requireOnlyListedLabelsBold=$true; requireCalloutBody=$true
            requireRenderedDom=$true; requiredFontClass='se-fs15'; forbiddenFontClass='se-fs30'
            expectedBoldElementCount=@($paragraph.boldLabels).Count; expectedLineHeight='1.6'; expectedAlignment='justify'
        }
    })
}
foreach ($heading in $headings) {
    if ([int]$heading.fontSizePx -notin @(17,19)) {
        throw '소제목 크기가 검증된 17/19px 기준을 벗어났습니다. 계획을 수정해야 합니다.'
    }
    $actions.Add([pscustomobject]@{
        sequence=$sequence++; action='ApplyHeadingByExactText'; text=[string]$heading.text
        expectedOccurrence=1; fontFamily='기본서체'; fontSizePx=[int]$heading.fontSizePx
        selectionMode='NativeTripleClickRenderedParagraph'; mutationMode='SetStateNotToggle'
        scrollMode='CenterVisibleOutsideFixedToolbar'; forbidAccessibilitySelectText=$true
        bold=$true; alignment='left'; topPx=32; bottomPx=21; requireStandaloneParagraph=$true
        postcondition=[pscustomobject]@{
            paragraphStyle='소제목'; nativeComponentClass='se-sectionTitle'
            requireNativeSectionTitleComponent=$true
            requireStandaloneParagraph=$true; requireRenderedDom=$true
            requiredFontClass=('se-fs' + [int]$heading.fontSizePx); forbiddenFontClass='se-fs30'
            requiredFontFamilyClass='se-ff-system'; expectedBoldElementCount=1
            computedFontSizePx=[int]$heading.fontSizePx
            minimumGapDifferencePx=6; requireGapBeforeGreaterThanAfter=$true
            requireEveryTextRunFontSize=$true; rejectInheritedFontSize=$true
        }
    })
}
foreach ($title in $calloutTitles) {
    $actions.Add([pscustomobject]@{
        sequence=$sequence++; action='ApplyCalloutTitleByExactText'; text=$title; expectedOccurrence=1
        selectionMode='NativeTripleClickRenderedParagraph'; mutationMode='SetStateNotToggle'
        scrollMode='CenterVisibleOutsideFixedToolbar'; forbidAccessibilitySelectText=$true
        fontFamily='기본서체'; fontSizePx=15; bold=$true; alignment='left'
        postcondition=[pscustomobject]@{
            requireCalloutTitle=$true; requireRenderedDom=$true; requiredFontClass='se-fs15'
            forbiddenFontClass='se-fs30'; expectedBoldElementCount=1
        }
    })
}
$actions.Add([pscustomobject]@{
    sequence=$sequence++; action='AuditWholeEditor'; expectedHeadingTexts=@($headings | ForEach-Object { [string]$_.text })
    expectedBodyParagraphTexts=@($bodyParagraphTexts.ToArray()); expectedCalloutBodyTexts=@($calloutBodyTexts.ToArray())
    expectedMixedCalloutParagraphs=@($mixedCalloutParagraphs.ToArray())
    expectedHeadingCount=$headings.Count; expectedParagraphCount=$paragraphs.Count
    requireBodyBoldFalse=$true; requireStandaloneHeadings=$true; rejectMergedHeadingBody=$true
    requireHeadingTopPx=32; requireHeadingBottomPx=21; requireParagraphBottomPx=18
    requirePerParagraphRenderedDomAudit=$true; rejectToolbarOnlyAudit=$true
    rejectAccessibilitySelectText=$true; rejectGlobalBoldToggle=$true; requireZeroUnverifiedTextBlocks=$true
    requiredBodyFontClass='se-fs15'; forbiddenBodyFontClass='se-fs30'; requiredBodyBoldElementCount=0
    maxRepairPasses=2; failClosedAfterRepairLimit=$true
})
$actions.Add([pscustomobject]@{ sequence=$sequence++; action='StopBeforePublicationSettings' })

$result = [pscustomobject]@{
    schemaVersion=3; contentId=[string]$plan.contentId; mode='RepairUnsavedNewPostFormatting'
    publicationForbidden=$true; actions=@($actions.ToArray())
    executionStatus='NotExecuted'; liveEditorVerified=$false
    executor=[pscustomobject]@{
        modulePath=(Join-Path $PSScriptRoot '편집기실행기.mjs')
        factory='createEditorRunner'; method='run'; host='AuthorizedChromeTabRuntime'
        scope='HeadingsAndSixFacts'; standaloneDesktopExecution=$false
    }
}
$parent = Split-Path -Parent $OutputPath
if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 8

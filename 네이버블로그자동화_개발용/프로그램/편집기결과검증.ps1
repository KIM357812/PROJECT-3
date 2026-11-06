#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('BeforeSave', 'AfterSave')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath,

    [Parameter(Mandatory = $true)]
    [string]$ObservationPath
)

$ErrorActionPreference = 'Stop'

function Add-EditorIssue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Message
    )
    $Issues.Add($Message)
}

function Normalize-EditorText {
    param([AllowEmptyString()][string]$Value)
    return (($Value -replace "`r`n", "`n") -replace "`r", "`n").Trim()
}

function Test-ObservedNumberEquals {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [object]$Observed,
        [double]$Expected,
        [string]$Name
    )
    $number = 0.0
    if ($null -eq $Observed -or -not [double]::TryParse(
        [string]$Observed,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )) {
        Add-EditorIssue $Issues "Observed numeric layout value is required: $Name"
        return
    }
    if ([Math]::Abs($number - $Expected) -gt 0.01) {
        Add-EditorIssue $Issues "Observed layout value does not match the plan: $Name"
    }
}

function Test-ObservedNumberWithinTolerance {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [object]$Observed,
        [double]$Expected,
        [double]$Tolerance,
        [string]$Name
    )
    $number = 0.0
    if ($null -eq $Observed -or -not [double]::TryParse(
        [string]$Observed,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )) {
        Add-EditorIssue $Issues "Observed numeric layout value is required: $Name"
        return
    }
    if ([Math]::Abs($number - $Expected) -gt $Tolerance) {
        Add-EditorIssue $Issues "Observed layout value is outside the allowed tolerance: $Name"
    }
}

function Test-HeadingLayoutSet {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [object[]]$ObservedLayouts,
        [string[]]$PlannedHeadings,
        [object]$SectionFormatting,
        [string]$Prefix
    )
    if ($ObservedLayouts.Count -ne $PlannedHeadings.Count) {
        Add-EditorIssue $Issues "Every planned section heading requires one measured $Prefix Naver layout record."
        return
    }
    for ($i = 0; $i -lt $PlannedHeadings.Count; $i++) {
        $headingLayout = $ObservedLayouts[$i]
        if ([string]$headingLayout.text -ne $PlannedHeadings[$i]) {
            Add-EditorIssue $Issues "Observed $Prefix heading order or text does not match the plan at index $i."
        }
        if (-not [bool]$headingLayout.standaloneParagraph) {
            Add-EditorIssue $Issues "$Prefix section heading must be a standalone paragraph: $($PlannedHeadings[$i])"
        }
        Test-ObservedNumberEquals $Issues $headingLayout.fontSizePx `
            ([double]$SectionFormatting.headingFontSize) "$Prefix heading[$i].fontSizePx"
        Test-ObservedNumberEquals $Issues $headingLayout.marginTopPx `
            ([double]$SectionFormatting.headingMarginTopPx) "$Prefix heading[$i].marginTopPx"
        Test-ObservedNumberEquals $Issues $headingLayout.marginBottomPx `
            ([double]$SectionFormatting.headingMarginBottomPx) "$Prefix heading[$i].marginBottomPx"
    }
}

function Test-ParagraphGapLayoutSet {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [object[]]$ObservedLayouts,
        [object]$ObservedPairCount,
        [object]$ParagraphGapFormatting,
        [string]$Prefix
    )
    $pairCount = 0
    if ($null -eq $ObservedPairCount -or -not [int]::TryParse([string]$ObservedPairCount, [ref]$pairCount)) {
        Add-EditorIssue $Issues "Observed ordinary body paragraph pair count is required: $Prefix"
        return
    }
    if ($pairCount -lt 1) {
        Add-EditorIssue $Issues "At least one ordinary body paragraph pair must be measured: $Prefix"
        return
    }
    if ($ObservedLayouts.Count -ne $pairCount) {
        Add-EditorIssue $Issues "Every ordinary body paragraph pair requires one measured $Prefix gap record."
        return
    }
    for ($i = 0; $i -lt $ObservedLayouts.Count; $i++) {
        $layout = $ObservedLayouts[$i]
        if ([string]$layout.context -ne 'OrdinaryBodyToOrdinaryBody') {
            Add-EditorIssue $Issues "$Prefix paragraphGap[$i] must describe two ordinary body paragraphs."
        }
        if ([bool]$layout.adjacentToSectionHeading -or [bool]$layout.adjacentToCallout) {
            Add-EditorIssue $Issues "$Prefix paragraphGap[$i] must not be adjacent to a heading or callout."
        }
        Test-ObservedNumberWithinTolerance $Issues $layout.gapPx `
            ([double]$ParagraphGapFormatting.gapPx) `
            ([double]$ParagraphGapFormatting.gapTolerancePx) "$Prefix paragraphGap[$i].gapPx"
        Test-ObservedNumberEquals $Issues $layout.spacerParagraphCount `
            ([double]$ParagraphGapFormatting.spacerParagraphCount) "$Prefix paragraphGap[$i].spacerParagraphCount"
        Test-ObservedNumberWithinTolerance $Issues $layout.spacerHeightPx `
            ([double]$ParagraphGapFormatting.gapPx) `
            ([double]$ParagraphGapFormatting.gapTolerancePx) "$Prefix paragraphGap[$i].spacerHeightPx"
        Test-ObservedNumberEquals $Issues $layout.spacerFontSizePx `
            ([double]$ParagraphGapFormatting.spacerFontSizePx) "$Prefix paragraphGap[$i].spacerFontSizePx"
        Test-ObservedNumberEquals $Issues $layout.spacerLineHeight `
            ([double]$ParagraphGapFormatting.spacerLineHeight) "$Prefix paragraphGap[$i].spacerLineHeight"
    }
}

function Test-QuestionToReferenceGapLayout {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [object]$ObservedLayout,
        [object]$GapFormatting,
        [string]$Prefix
    )
    if ($null -eq $ObservedLayout) {
        Add-EditorIssue $Issues "The final reader-question to reference gap requires one measured $Prefix layout record."
        return
    }
    if ([string]$ObservedLayout.order -ne [string]$GapFormatting.order) {
        Add-EditorIssue $Issues "$Prefix reader-question to reference order does not match the plan."
    }
    Test-ObservedNumberWithinTolerance $Issues $ObservedLayout.gapPx `
        ([double]$GapFormatting.gapPx) ([double]$GapFormatting.gapTolerancePx) `
        "$Prefix questionToReferenceGap.gapPx"
    Test-ObservedNumberEquals $Issues $ObservedLayout.spacerParagraphCount `
        ([double]$GapFormatting.spacerParagraphCount) `
        "$Prefix questionToReferenceGap.spacerParagraphCount"
    Test-ObservedNumberWithinTolerance $Issues $ObservedLayout.spacerHeightPx `
        ([double]$GapFormatting.gapPx) ([double]$GapFormatting.gapTolerancePx) `
        "$Prefix questionToReferenceGap.spacerHeightPx"
    Test-ObservedNumberEquals $Issues $ObservedLayout.spacerFontSizePx `
        ([double]$GapFormatting.spacerFontSizePx) `
        "$Prefix questionToReferenceGap.spacerFontSizePx"
    Test-ObservedNumberEquals $Issues $ObservedLayout.spacerLineHeight `
        ([double]$GapFormatting.spacerLineHeight) `
        "$Prefix questionToReferenceGap.spacerLineHeight"
}

function Test-CalloutLayoutSet {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [object[]]$ObservedCallouts,
        [object[]]$PlannedCallouts,
        [object]$CalloutFormatting,
        [object]$SectionFormatting,
        [string]$Prefix
    )
    if ($ObservedCallouts.Count -ne $PlannedCallouts.Count) {
        Add-EditorIssue $Issues "Every planned callout style requires one measured $Prefix Naver layout record."
        return
    }
    for ($i = 0; $i -lt $PlannedCallouts.Count; $i++) {
        $callout = $ObservedCallouts[$i]
        $plannedCallout = $PlannedCallouts[$i]
        if ([string]$callout.name -ne [string]$plannedCallout.name) {
            Add-EditorIssue $Issues "Observed $Prefix callout order or name does not match the plan at index $i."
        }
        Test-ObservedNumberEquals $Issues $callout.titleFontSizePx `
            ([double]$CalloutFormatting.titleFontSizePx) "$Prefix callout[$i].titleFontSizePx"
        Test-ObservedNumberEquals $Issues $callout.titleMarginBottomPx `
            ([double]$plannedCallout.titleMarginBottomPx) "$Prefix callout[$i].titleMarginBottomPx"
        Test-ObservedNumberEquals $Issues $callout.bodyFontSizePx `
            ([double]$SectionFormatting.bodyFontSize) "$Prefix callout[$i].bodyFontSizePx"
        Test-ObservedNumberEquals $Issues $callout.bodyLineHeight `
            ([double]$CalloutFormatting.bodyLineHeight) "$Prefix callout[$i].bodyLineHeight"
        Test-ObservedNumberEquals $Issues $callout.paragraphMarginBottomPx `
            ([double]$CalloutFormatting.paragraphMarginBottomPx) "$Prefix callout[$i].paragraphMarginBottomPx"
        Test-ObservedNumberEquals $Issues $callout.outerMarginTopPx `
            ([double]$plannedCallout.outerMarginTopPx) "$Prefix callout[$i].outerMarginTopPx"
        Test-ObservedNumberEquals $Issues $callout.outerMarginBottomPx `
            ([double]$plannedCallout.outerMarginBottomPx) "$Prefix callout[$i].outerMarginBottomPx"
        Test-ObservedNumberEquals $Issues $callout.blankParagraphCountBefore `
            0 "$Prefix callout[$i].blankParagraphCountBefore"
        Test-ObservedNumberEquals $Issues $callout.blankParagraphCountAfter `
            0 "$Prefix callout[$i].blankParagraphCountAfter"
    }
}

if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) {
    throw "편집기 계획을 찾을 수 없습니다: $PlanPath"
}
if (-not (Test-Path -LiteralPath $ObservationPath -PathType Leaf)) {
    throw "편집기 관찰 결과를 찾을 수 없습니다: $ObservationPath"
}

$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
$observation = Get-Content -LiteralPath $ObservationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$issues = New-Object 'System.Collections.Generic.List[string]'

foreach ($booleanField in @(
    'registerAsNotice',
    'publicPublishAttempted',
    'externalSavePerformed',
    'savedAsPrivate',
    'publicUrlCreated'
)) {
    if ($observation.PSObject.Properties.Name -notcontains $booleanField -or
        $null -eq $observation.$booleanField) {
        Add-EditorIssue $issues "Observed boolean value is required: $booleanField"
    }
}

$isTechnicalArticle = ([string]$plan.draftType -eq 'TechnicalArticle')
if ($isTechnicalArticle) {
    foreach ($booleanField in @(
        'imageOrderVerified',
        'imageServerUploadVerified',
        'pcLayoutVerified',
        'mobileLayoutVerified',
        'publishDelayObserved'
    )) {
        if ($observation.PSObject.Properties.Name -notcontains $booleanField -or
            $null -eq $observation.$booleanField) {
            Add-EditorIssue $issues "Observed technical-article value is required: $booleanField"
        }
    }

    $plannedImageCount = [int]$plan.imageSpecification.count
    if ([int]$observation.imageCount -ne $plannedImageCount) {
        Add-EditorIssue $issues 'Observed image count does not match the editor plan.'
    }
    $plannedImageNames = @($plan.imagePlacements | Sort-Object order | ForEach-Object { [string]$_.fileName })
    $observedImageNames = @($observation.imageFileNames | ForEach-Object { [string]$_ })
    if (($plannedImageNames -join "`n") -ne ($observedImageNames -join "`n")) {
        Add-EditorIssue $issues 'Observed image names or order do not match the editor plan.'
    }
    if (-not [bool]$observation.imageOrderVerified -or
        -not [bool]$observation.imageServerUploadVerified -or
        -not [bool]$observation.pcLayoutVerified) {
        Add-EditorIssue $issues 'Technical article images require verified order, Naver server upload, and PC layout.'
    }
    if ([int]$observation.saveAttemptCount -lt 1 -or [int]$observation.saveAttemptCount -gt 2) {
        Add-EditorIssue $issues 'saveAttemptCount must be 1 or 2.'
    }
    if ([bool]$observation.publishDelayObserved -and
        [string]::IsNullOrWhiteSpace([string]$observation.recoveryAction)) {
        Add-EditorIssue $issues 'A delayed publish requires a recorded recovery action.'
    }

    if ([string]$observation.layoutMeasurementSource -ne 'RenderedNaverDomAndScreen') {
        Add-EditorIssue $issues 'Technical article layout must be measured from the rendered Naver DOM and screen.'
    }
    Test-ObservedNumberEquals $issues $observation.bodyFontSizePx `
        ([double]$plan.sectionFormatting.bodyFontSize) 'bodyFontSizePx'
    Test-ObservedNumberEquals $issues $observation.bodyLineHeightPx `
        ([double]$plan.sectionFormatting.bodyLineHeightPx) 'bodyLineHeightPx'
    Test-ObservedNumberEquals $issues $observation.paragraphMarginBottomPx `
        ([double]$plan.sectionFormatting.paragraphMarginBottomPx) 'paragraphMarginBottomPx'
    Test-ObservedNumberEquals $issues $observation.mobileBodyFontSizePx `
        ([double]$plan.sectionFormatting.bodyFontSize) 'mobileBodyFontSizePx'
    Test-ObservedNumberEquals $issues $observation.mobileBodyLineHeightPx `
        ([double]$plan.sectionFormatting.bodyLineHeightPx) 'mobileBodyLineHeightPx'
    Test-ObservedNumberEquals $issues $observation.mobileParagraphMarginBottomPx `
        ([double]$plan.sectionFormatting.paragraphMarginBottomPx) 'mobileParagraphMarginBottomPx'

    Test-ParagraphGapLayoutSet $issues @($observation.paragraphGapLayouts) `
        $observation.bodyParagraphPairCount $plan.paragraphGapFormatting 'PC'
    Test-ParagraphGapLayoutSet $issues @($observation.mobileParagraphGapLayouts) `
        $observation.mobileBodyParagraphPairCount $plan.paragraphGapFormatting 'mobile'

    Test-QuestionToReferenceGapLayout $issues $observation.questionToReferenceGapLayout `
        $plan.referenceFormatting.questionToReferenceGap 'PC'
    Test-QuestionToReferenceGapLayout $issues $observation.mobileQuestionToReferenceGapLayout `
        $plan.referenceFormatting.questionToReferenceGap 'mobile'

    $plannedHeadings = @($plan.sectionHeadings | ForEach-Object { [string]$_ })
    Test-HeadingLayoutSet $issues @($observation.headingLayouts) $plannedHeadings `
        $plan.sectionFormatting 'PC'
    Test-HeadingLayoutSet $issues @($observation.mobileHeadingLayouts) $plannedHeadings `
        $plan.sectionFormatting 'mobile'

    $plannedCallouts = @($plan.calloutFormatting.styles)
    Test-CalloutLayoutSet $issues @($observation.calloutLayouts) $plannedCallouts `
        $plan.calloutFormatting $plan.sectionFormatting 'PC'
    Test-CalloutLayoutSet $issues @($observation.mobileCalloutLayouts) $plannedCallouts `
        $plan.calloutFormatting $plan.sectionFormatting 'mobile'
}

$observedAt = [DateTimeOffset]::MinValue
$observedAtValue = $observation.observedAt
$observedAtValid = ($observedAtValue -is [DateTime] -or $observedAtValue -is [DateTimeOffset])
if (-not $observedAtValid) {
    $observedAtText = [string]$observedAtValue
    $observedAtFormat = if ($observedAtText.EndsWith('Z')) {
        "yyyy-MM-ddTHH:mm:ss'Z'"
    } else {
        'yyyy-MM-ddTHH:mm:sszzz'
    }
    $observedAtValid = (
        $observedAtText -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$' -and
        [DateTimeOffset]::TryParseExact(
            $observedAtText,
            $observedAtFormat,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$observedAt
        )
    )
}
if (-not $observedAtValid) {
    Add-EditorIssue $issues 'observedAt must use yyyy-MM-ddTHH:mm:ssK.'
}

$editorUri = $null
if (-not [Uri]::TryCreate([string]$observation.editorUrl, [UriKind]::Absolute, [ref]$editorUri) -or
    $editorUri.Scheme -ne 'https' -or $editorUri.Host -ne 'blog.naver.com') {
    Add-EditorIssue $issues 'editorUrl must be an HTTPS blog.naver.com URL.'
}

if ([string]$observation.contentId -ne [string]$plan.contentId) {
    Add-EditorIssue $issues 'Observed contentId does not match the editor plan.'
}
if ([string]$observation.title -ne [string]$plan.title) {
    Add-EditorIssue $issues 'Observed title does not exactly match the editor plan.'
}
if ((Normalize-EditorText ([string]$observation.body)) -ne
    (Normalize-EditorText ([string]$plan.body))) {
    Add-EditorIssue $issues 'Observed body does not exactly match the editor plan.'
}

$plannedTags = @($plan.tags | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$observedTags = @($observation.tags | ForEach-Object { [string]$_ } | Sort-Object -Unique)
if (($plannedTags -join "`n") -ne ($observedTags -join "`n")) {
    Add-EditorIssue $issues 'Observed tags do not match the editor plan.'
}
if ([string]$observation.category -ne [string]$plan.category) {
    Add-EditorIssue $issues 'Observed category does not match the editor plan.'
}
if ([string]$observation.visibility -ne '비공개' -or
    [string]$plan.visibility -ne '비공개') {
    Add-EditorIssue $issues 'Both plan and observation must use private visibility.'
}
if ([bool]$observation.registerAsNotice -or [bool]$plan.registerAsNotice) {
    Add-EditorIssue $issues 'Notice registration must remain disabled.'
}
if ([bool]$observation.publicPublishAttempted) {
    Add-EditorIssue $issues 'A public publish attempt was observed.'
}

if ($Mode -eq 'BeforeSave') {
    if ([bool]$observation.externalSavePerformed -or [bool]$observation.savedAsPrivate) {
        Add-EditorIssue $issues 'BeforeSave observation must occur before any external save.'
    }
}
else {
    if (-not [bool]$observation.externalSavePerformed -or
        -not [bool]$observation.savedAsPrivate) {
        Add-EditorIssue $issues 'AfterSave observation must confirm an external private save.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$observation.savedDraftIndicator)) {
        Add-EditorIssue $issues 'AfterSave observation requires a visible saved-draft indicator.'
    }
    if ([bool]$observation.publicUrlCreated) {
        Add-EditorIssue $issues 'A public URL must not be created during private draft validation.'
    }
    if ($isTechnicalArticle -and -not [bool]$observation.imageServerUploadVerified) {
        Add-EditorIssue $issues 'AfterSave technical article must confirm Naver-hosted image URLs.'
    }
    if ($isTechnicalArticle -and -not [bool]$observation.mobileLayoutVerified) {
        Add-EditorIssue $issues 'AfterSave technical article must confirm the actual mobile layout.'
    }
}

$result = [pscustomobject]@{
    IsValid = ($issues.Count -eq 0)
    Mode = $Mode
    ContentId = [string]$plan.contentId
    Visibility = [string]$observation.visibility
    ExternalSavePerformed = [bool]$observation.externalSavePerformed
    Issues = @($issues)
}
$result | ConvertTo-Json -Depth 5

if ($issues.Count -gt 0) {
    throw ('편집기 결과 검증 실패: ' + (@($issues) -join '; '))
}

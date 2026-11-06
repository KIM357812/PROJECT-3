#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DraftPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '설정.json')
)

$ErrorActionPreference = 'Stop'

foreach ($path in @($DraftPath, $ConfigPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "필수 파일을 찾을 수 없습니다: $path"
    }
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "기존 편집기 재구성 계획을 덮어쓰지 않습니다: $OutputPath"
}

$draft = Get-Content -LiteralPath $DraftPath -Raw -Encoding UTF8 | ConvertFrom-Json
$settings = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$rules = $settings.NaverDraft
$blocks = @($draft.editorBlocks)
$rebuildScope = if ($draft.PSObject.Properties.Name -contains 'rebuildScope' -and
    -not [string]::IsNullOrWhiteSpace([string]$draft.rebuildScope)) {
    [string]$draft.rebuildScope
} else { 'EntireBody' }
$targetSectionHeading = if ($draft.PSObject.Properties.Name -contains 'targetSectionHeading') {
    [string]$draft.targetSectionHeading
} else { '' }
$issues = New-Object 'System.Collections.Generic.List[string]'

if (-not [bool]$rules.RequireStructuredEditorBlocks) {
    $issues.Add('Structured editor blocks must be required by configuration.')
}
if ($blocks.Count -lt 1) {
    $issues.Add('editorBlocks must contain the complete editor body structure.')
}
if (@('EntireBody', 'NamedSection') -notcontains $rebuildScope) {
    $issues.Add('rebuildScope must be EntireBody or NamedSection.')
}
if ($rebuildScope -eq 'NamedSection') {
    if ([string]::IsNullOrWhiteSpace($targetSectionHeading) -or
        $blocks.Count -lt 1 -or [string]$blocks[0].type -ne 'SectionHeading' -or
        [string]$blocks[0].text -ne $targetSectionHeading) {
        $issues.Add('NamedSection rebuild requires the first SectionHeading block to match targetSectionHeading.')
    }
}

$allowedTypes = @($rules.AllowedEditorBlockTypes | ForEach-Object { [string]$_ })
$ids = New-Object 'System.Collections.Generic.List[string]'
$readerQuestionCount = 0
$referenceLineCount = 0

for ($i = 0; $i -lt $blocks.Count; $i++) {
    $block = $blocks[$i]
    $id = ([string]$block.id).Trim()
    $type = ([string]$block.type).Trim()
    if ([string]::IsNullOrWhiteSpace($id) -or $ids.Contains($id)) {
        $issues.Add("Every editor block requires a unique id: index $i")
    } else { $ids.Add($id) }
    if ($allowedTypes -notcontains $type) {
        $issues.Add("Unsupported editor block type at index ${i}: $type")
    }
    if ($type -ne 'Image' -and [string]::IsNullOrWhiteSpace([string]$block.text)) {
        $issues.Add("Editor block text is required at index $i.")
    }
    if ($type -eq 'ReferenceLine') {
        $links = @($block.links)
        if ($links.Count -lt 1 -or $links.Count -gt 3) {
            $issues.Add('ReferenceLine requires 1 to 3 linked source names.')
        }
        foreach ($link in $links) {
            $uri = $null
            if ([string]::IsNullOrWhiteSpace([string]$link.text) -or
                -not [Uri]::TryCreate([string]$link.url, [UriKind]::Absolute, [ref]$uri) -or
                $uri.Scheme -ne 'https') {
                $issues.Add('Every ReferenceLine link requires text and an HTTPS URL.')
            }
        }
    }
    if ($type -eq 'ReaderQuestion') { $readerQuestionCount++ }
    if ($type -eq 'ReferenceLine') { $referenceLineCount++ }
}

if ($readerQuestionCount -ne 1 -or $referenceLineCount -ne 1) {
    $issues.Add('Exactly one ReaderQuestion and one ReferenceLine are required.')
}

$questionIndex = -1
$referenceIndex = -1
for ($i = 0; $i -lt $blocks.Count; $i++) {
    if ([string]$blocks[$i].type -eq 'ReaderQuestion') { $questionIndex = $i }
    if ([string]$blocks[$i].type -eq 'ReferenceLine') { $referenceIndex = $i }
}
if ($questionIndex -lt 0 -or $referenceIndex -ne ($questionIndex + 1) -or
    $referenceIndex -ne ($blocks.Count - 1)) {
    $issues.Add('ReaderQuestion must be immediately followed by the final ReferenceLine logical block.')
}

if ($issues.Count -gt 0) {
    throw ('편집기 재구성 계획 생성 실패: ' + (@($issues) -join '; '))
}

$ordinaryGap = $rules.ParagraphGapDesign
$referenceGap = $rules.ReferenceGapDesign
$actions = New-Object 'System.Collections.Generic.List[object]'
$sequence = 1

for ($i = 0; $i -lt $blocks.Count; $i++) {
    $block = $blocks[$i]
    $insertAction = [pscustomobject]@{
        sequence = $sequence++
        action = 'InsertBlock'
        blockId = [string]$block.id
        blockType = [string]$block.type
        text = [string]$block.text
        source = 'ValidatedDraftEditorBlocks'
        precondition = [pscustomobject]@{
            requireEditorBodyFocus = $true
            forbidToolbarOrDialogFocus = $true
        }
        postcondition = [pscustomobject]@{
            requireExactInsertedText = $true
            requireStandaloneParagraph = $true
            forbidMergeWithPreviousOrNextBlock = $true
            stopExecutionOnMismatch = $true
        }
    }
    if ([string]$block.type -eq 'SectionHeading') {
        $insertAction | Add-Member -NotePropertyName formatting -NotePropertyValue ([pscustomobject]@{
            fontSizePx=[int]$rules.SectionHeadingFontSize
            bold=[bool]$rules.SectionHeadingBold
            marginTopPx=[int]$rules.SectionHeadingMarginTopPx
            marginBottomPx=[int]$rules.SectionHeadingMarginBottomPx
            dividerEnabled=[bool]$rules.SectionHeadingDividerEnabled
        })
    }
    elseif (@('BodyParagraph', 'ReaderQuestion', 'ReferenceLine') -contains [string]$block.type) {
        $insertAction | Add-Member -NotePropertyName formatting -NotePropertyValue ([pscustomobject]@{
            fontSizePx=[int]$rules.BodyFontSize
            lineHeight=[double]$rules.BodyLineHeight
        })
    }
    if ([string]$block.type -eq 'ReferenceLine') {
        $insertAction | Add-Member -NotePropertyName links -NotePropertyValue @($block.links)
    }
    $actions.Add($insertAction)

    if ($i -ge ($blocks.Count - 1)) { continue }
    $nextBlock = $blocks[$i + 1]
    $ordinaryLikeTypes = @('BodyParagraph', 'ReaderQuestion')
    if ($ordinaryLikeTypes -contains [string]$block.type -and
        $ordinaryLikeTypes -contains [string]$nextBlock.type) {
        $actions.Add([pscustomobject]@{
            sequence = $sequence++
            action = 'InsertMeasuredSpacer'
            context = 'OrdinaryBodyToOrdinaryBody'
            expectedGapPx = [int]$ordinaryGap.GapPx
            tolerancePx = [double]$ordinaryGap.GapTolerancePx
            paragraphCount = [int]$ordinaryGap.SpacerParagraphCount
            fontSizePx = [int]$ordinaryGap.SpacerFontSizePx
            lineHeight = [double]$ordinaryGap.SpacerLineHeight
            source = 'NaverDraft.ParagraphGapDesign'
            precondition = [pscustomobject]@{
                requireEditorBodyFocus = $true
                forbidToolbarOrDialogFocus = $true
            }
            postcondition = [pscustomobject]@{
                requireEmptyStandaloneParagraph = $true
                requireRenderedHeightMeasurement = $true
                stopExecutionOnMismatch = $true
            }
        })
    }
    elseif ([string]$block.type -eq 'ReaderQuestion' -and
        [string]$nextBlock.type -eq 'ReferenceLine') {
        $actions.Add([pscustomobject]@{
            sequence = $sequence++
            action = 'InsertMeasuredSpacer'
            context = [string]$referenceGap.Order
            expectedGapPx = [int]$referenceGap.GapPx
            tolerancePx = [double]$referenceGap.GapTolerancePx
            paragraphCount = [int]$referenceGap.SpacerParagraphCount
            fontSizePx = [int]$referenceGap.SpacerFontSizePx
            lineHeight = [double]$referenceGap.SpacerLineHeight
            source = 'NaverDraft.ReferenceGapDesign'
            precondition = [pscustomobject]@{
                requireEditorBodyFocus = $true
                forbidToolbarOrDialogFocus = $true
            }
            postcondition = [pscustomobject]@{
                requireEmptyStandaloneParagraph = $true
                requireRenderedHeightMeasurement = $true
                stopExecutionOnMismatch = $true
            }
        })
    }
}

$plan = [pscustomobject]@{
    schemaVersion = 1
    contentId = [string]$draft.contentId
    title = [string]$draft.title
    mode = if ($rebuildScope -eq 'NamedSection') {
        'RebuildNamedSectionFromValidatedBlocks'
    } else { 'RebuildEntireEditorBodyFromValidatedBlocks' }
    rebuildScope = $rebuildScope
    targetSectionHeading = $targetSectionHeading
    forbidAdHocPatch = $true
    forbidPromptAuthoredSpacerBlocks = $true
    allowPublicPublish = $false
    allowExternalSave = $false
    requirePrivateSaveForPersistenceTest = $true
    requireReloadVerification = $true
    requirePcAndMobileMeasurement = $true
    executionGuards = [pscustomobject]@{
        refocusEditorBodyAfterEveryToolbarAction = $true
        verifyBlockCountAfterEveryAction = $true
        verifyExactTextAfterEveryInsertBlock = $true
        rejectMergedLogicalBlocks = $true
        rejectMissingLogicalBlocks = $true
        stopBeforeSaveOnAnyMismatch = $true
    }
    actions = $actions.ToArray()
}

$directory = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($directory)) { throw 'OutputPath는 상위 폴더를 포함해야 합니다.' }
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $directory
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$plan | ConvertTo-Json -Depth 8

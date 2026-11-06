#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '설정.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "설정 파일을 찾을 수 없습니다: $ConfigPath"
}

$settings = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$paragraphGap = $settings.NaverDraft.ParagraphGapDesign
$referenceGap = $settings.NaverDraft.ReferenceGapDesign

$plan = [pscustomobject]@{
    schemaVersion = 1
    actionType = 'NaverEditorFormatting'
    target = '현재 열려 있는 네이버 블로그 편집 글'
    generatedAt = [DateTimeOffset]::Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
    safety = [pscustomobject]@{
        allowPublicPublish = $false
        allowExternalSave = $false
        changeOnlyFormatting = $true
        requireRenderedPcAndMobileVerification = $true
    }
    actions = @(
        [pscustomobject]@{
            id = 'ordinary-body-paragraph-gap'
            selectorStrategy = 'EveryEmptyParagraphBetweenTwoOrdinaryBodyParagraphs'
            context = 'OrdinaryBodyToOrdinaryBody'
            expectedGapPx = [int]$paragraphGap.GapPx
            tolerancePx = [double]$paragraphGap.GapTolerancePx
            spacerParagraphCount = [int]$paragraphGap.SpacerParagraphCount
            spacerFontSizePx = [int]$paragraphGap.SpacerFontSizePx
            spacerLineHeight = [double]$paragraphGap.SpacerLineHeight
            excludeAdjacentSectionHeadings = [bool]$paragraphGap.ForbidAdjacentToSectionHeadings
            excludeAdjacentCallouts = [bool]$paragraphGap.ForbidAdjacentToCallouts
        },
        [pscustomobject]@{
            id = 'reader-question-to-reference-gap'
            selectorStrategy = 'SingleEmptyParagraphBetweenFinalReaderQuestionAndReferenceLine'
            context = [string]$referenceGap.Order
            expectedGapPx = [int]$referenceGap.GapPx
            tolerancePx = [double]$referenceGap.GapTolerancePx
            spacerParagraphCount = [int]$referenceGap.SpacerParagraphCount
            spacerFontSizePx = [int]$referenceGap.SpacerFontSizePx
            spacerLineHeight = [double]$referenceGap.SpacerLineHeight
            referenceLineLabel = [string]$settings.NaverDraft.ReferenceLineLabel
        }
    )
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and
    -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory
}

$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$plan | ConvertTo-Json -Depth 8

#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot '프로그램\편집기서식적용계획.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('네이버 편집기 서식 계획 ' + [guid]::NewGuid().ToString('N'))
$outputPath = Join-Path $testRoot 'formatting-actions.json'

try {
    $created = & $scriptPath -OutputPath $outputPath | ConvertFrom-Json
    $saved = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $ordinary = @($saved.actions | Where-Object id -eq 'ordinary-body-paragraph-gap')[0]
    $reference = @($saved.actions | Where-Object id -eq 'reader-question-to-reference-gap')[0]
    $bodyStyle = @($saved.actions | Where-Object id -eq 'ordinary-body-native-style')[0]
    $headingStyle = @($saved.actions | Where-Object id -eq 'section-heading-native-style')[0]

    if ($created.actionType -ne 'NaverEditorFormatting' -or
        $saved.safety.allowPublicPublish -or $saved.safety.allowExternalSave -or
        -not $saved.safety.changeOnlyFormatting -or -not $saved.safety.forbidExistingPostEdit -or @($saved.actions).Count -ne 4 -or
        $bodyStyle.fontFamily -ne '기본서체' -or $bodyStyle.fontSizePx -ne 15 -or
        $bodyStyle.lineHeightPx -ne 27 -or $bodyStyle.alignment -ne 'justify' -or
        $bodyStyle.lastLineAlignment -ne 'left' -or -not $bodyStyle.requireRightEdgeAlignment -or
        $headingStyle.fontFamily -ne '기본서체' -or $headingStyle.fontSizePx -ne 19 -or
        $headingStyle.marginTopPx -ne 32 -or $headingStyle.marginBottomPx -ne 21 -or
        $ordinary.expectedGapPx -ne 18 -or $ordinary.spacerFontSizePx -ne 11 -or
        $ordinary.spacerLineHeight -ne 1.6 -or
        $reference.context -ne 'ReaderQuestionToReferenceLine' -or
        $reference.expectedGapPx -ne 32 -or $reference.tolerancePx -ne 0.5 -or
        $reference.spacerParagraphCount -ne 1 -or
        $reference.spacerFontSizePx -ne 16 -or $reference.spacerLineHeight -ne 2.0 -or
        $reference.referenceLineLabel -ne '참고자료 : ') {
        throw 'The tool-generated Naver editor formatting action plan is incorrect.'
    }
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Output 'Editor formatting action-plan tests passed.'

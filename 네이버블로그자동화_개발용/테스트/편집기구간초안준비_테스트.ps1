#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot '프로그램\편집기구간초안준비.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('네이버 구간 초안 ' + [guid]::NewGuid().ToString('N'))
$outputPath = Join-Path $testRoot 'section.json'
try {
    $created = & $scriptPath -ContentId 'NTE-SECTION-001' -Title '시험 제목' `
        -SectionHeading '국내에서 먼저 물어야 할 질문' `
        -BodyParagraphs @('첫 문단', '두 번째 문단') `
        -ReaderQuestion '독자 질문입니까?' `
        -ReferenceLine '참고자료 : POWER Magazine' `
        -ReferenceNames @('POWER Magazine') -ReferenceUrls @('https://example.com/article') `
        -OutputPath $outputPath | ConvertFrom-Json
    if ($created.rebuildScope -ne 'NamedSection' -or
        $created.targetSectionHeading -ne '국내에서 먼저 물어야 할 질문' -or
        @($created.editorBlocks).Count -ne 5 -or
        @($created.editorBlocks | Where-Object type -eq 'BodyParagraph').Count -ne 2 -or
        [string]$created.editorBlocks[-2].type -ne 'ReaderQuestion' -or
        [string]$created.editorBlocks[-1].type -ne 'ReferenceLine' -or
        @($created.editorBlocks[-1].links).Count -ne 1) {
        throw 'The named-section draft preparation result is incorrect.'
    }
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
Write-Output 'Editor named-section draft preparation tests passed.'

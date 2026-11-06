#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$tracePath = Join-Path $projectRoot '요구사항_대조표.md'
if (-not (Test-Path -LiteralPath $tracePath -PathType Leaf)) {
    throw 'The requirements traceability report was not found.'
}
$trace = Get-Content -LiteralPath $tracePath -Raw -Encoding UTF8
foreach ($section in 1..10) {
    if ($trace.IndexOf("## $section.", [StringComparison]::Ordinal) -lt 0) {
        throw "The requirements traceability report is missing section $section."
    }
}
foreach ($requiredText in @(
    '구현·검증',
    '부분 구현',
    '미구현',
    '승인 대기',
    '보류',
    '현재 완료를 막는 필수 항목',
    '실제 네이버 PC·모바일 비공개 화면',
    'Google Blogger 운영본 변경'
)) {
    if ($trace.IndexOf($requiredText, [StringComparison]::Ordinal) -lt 0) {
        throw "The requirements traceability report is missing required text: $requiredText"
    }
}

Write-Output 'Requirements traceability tests passed.'

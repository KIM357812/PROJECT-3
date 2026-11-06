#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $projectRoot '프로그램\네이버자동화.ps1'
$selfTest = & $uiScript -SelfTest
if ($selfTest -notcontains 'Naver integrated automation self-test passed.') { throw '통합 자동화 자체 검사가 실패했습니다.' }
$layoutTest = & $uiScript -LayoutSelfTest
if ($layoutTest -notcontains 'Naver integrated automation layout self-test passed.') { throw '통합 자동화 화면 배치 검사가 실패했습니다.' }
$text = Get-Content -LiteralPath $uiScript -Raw -Encoding UTF8
foreach ($required in @(
    'Google 자동화 사본을 본체로 사용',
    '기존 네이버 개발본에서는 이미지 기능만 사용',
    '최신 기사로 새 글 만들기',
    'Google 완성 글 가져오기',
    '발행 설정을 열기 전',
    '구글기반_새글생성.ps1',
    '구글기반_네이버패키지.ps1',
    '이미지작업준비.ps1',
    '이미지최적화.ps1',
    '이미지검증.ps1'
)) {
    if ($text.IndexOf($required,[StringComparison]::Ordinal) -lt 0) { throw "사용자 화면 필수 항목이 없습니다: $required" }
}
if ($text -match '편집기결과검증|벤치마크선정|독자반응분석|초안준비') { throw '기존 네이버 비이미지 기능을 새 사용자 화면이 참조합니다.' }
Write-Output 'Integrated user interface tests passed.'

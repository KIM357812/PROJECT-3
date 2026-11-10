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
    '최근 7일 기사를 확인',
    '최신 기사로 새 글 만들기',
    '완성 글 편집기 입력 계속',
    '선택한 글을 준비하고 있습니다.',
    '모두 완성되었습니다',
    '준비된 글',
    '선택한 글 편집기에 넣기',
    '편집기입력완료.json',
    '발행 설정을 열기 전',
    '구글기반_새글생성.ps1',
    '구글기반_네이버패키지.ps1',
    '이미지작업준비.ps1',
    '이미지최적화.ps1',
    '이미지검증.ps1',
    '크롬직접연결.ps1',
    '크롬네이티브입력.ps1',
    'ChatGPT 영문 요청 없음'
)) {
    if ($text.IndexOf($required,[StringComparison]::Ordinal) -lt 0) { throw "사용자 화면 필수 항목이 없습니다: $required" }
}
foreach ($removed in @('Google 완성 글 가져오기','Google 완성 글 폴더를 선택하세요.','실패한 글만 다시 작성','retryButton','RetryLatest','재시도 필요','기사 다시 선택','전체 작업 다시 시작','내부 사실검증표 부족','소재 실패')) {
    if ($text.IndexOf($removed,[StringComparison]::Ordinal) -ge 0) { throw "제거 대상 화면 문구가 남아 있습니다: $removed" }
}
foreach($removed in @('데스크톱연결요청.ps1','DesktopConnectionSettingsPath','codex queue')){
    if($text.IndexOf($removed,[StringComparison]::OrdinalIgnoreCase)-ge 0){throw "ChatGPT 중계 문구가 사용자 실행 경로에 남아 있습니다: $removed"}
}
if ($text -match '편집기결과검증|벤치마크선정|독자반응분석|초안준비') { throw '기존 네이버 비이미지 기능을 새 사용자 화면이 참조합니다.' }
Write-Output 'Integrated user interface tests passed.'

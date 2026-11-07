#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root '프로그램\구글기반_새글생성.ps1'
$googleCommon = Join-Path $root '구글기반\프로그램\공통.ps1'
$googleStart = Join-Path $root '구글기반\프로그램\시작.ps1'
$packagePath = Join-Path $root '프로그램\구글기반_네이버패키지.ps1'
$text = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
$commonText = Get-Content -LiteralPath $googleCommon -Raw -Encoding UTF8
$startText = Get-Content -LiteralPath $googleStart -Raw -Encoding UTF8
$packageText = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8
if ($text -notmatch '구글기반_네이버패키지\.ps1') { throw 'Google 결과의 네이버 패키지 변환 연결이 없습니다.' }
if ($text -notmatch 'NAVER_AUTOMATION_AUTO_SELECT_TOP') { throw '자동 추천 한 건 선택이 없습니다.' }
if ($commonText -notmatch 'NAVER_AUTOMATION_RUNTIME_ROOT') { throw '실행 자료를 저장소 밖에 두는 설정이 없습니다.' }
if ($startText -notmatch 'NAVER_AUTOMATION_AUTO_SELECT_TOP') { throw 'Google 기반 시작 흐름에 자동 선택 옵션이 없습니다.' }
if ($text -match '(?i)publish|비공개\s*발행|공개\s*발행') { throw '새 글 생성기에 게시 동작이 포함되어 있습니다.' }
foreach ($atomicAction in @('InsertStandaloneHeading','InsertVerticalSpacer','PasteStandaloneParagraphBlock','Assert-AtomicEditorPlan')) {
    if (-not $packageText.Contains($atomicAction)) { throw "네이버 독립 편집 동작 또는 검증기가 없습니다: $atomicAction" }
}
if ($packageText -match "type\s*=\s*'PasteRenderedSegment'") { throw '제목과 본문을 합치는 구간 붙여넣기가 다시 추가되었습니다.' }
Write-Output 'Google 기반 새 글 생성 정적 테스트 통과'

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
$candidatePreparationText = Get-Content -LiteralPath (Join-Path $root '구글기반\프로그램\후보준비.ps1') -Raw -Encoding UTF8
if ($text -notmatch '구글기반_네이버패키지\.ps1') { throw 'Google 결과의 네이버 패키지 변환 연결이 없습니다.' }
if ($text -match 'NAVER_AUTOMATION_AUTO_SELECT_TOP') { throw '자동 추천 첫 항목 선택이 남아 있습니다.' }
if ($commonText -notmatch 'NAVER_AUTOMATION_RUNTIME_ROOT') { throw '실행 자료를 저장소 밖에 두는 설정이 없습니다.' }
if ($startText -match 'NAVER_AUTOMATION_AUTO_SELECT_TOP|Select-Object\s+-First\s+\$autoSelectTop') { throw 'Google 기반 시작 흐름에 자동 선택이 남아 있습니다.' }
if ($startText -notmatch 'Read-CandidateSelection') { throw 'PowerShell 사용자 기사 선택 연결이 없습니다.' }
if ($text -notmatch 'Get-NaverGenerationResult' -or $text -notmatch 'selectedCount' -or $text -notmatch 'PartiallyCompleted' -or $text -notmatch 'RetryLatest') { throw '1~3건 독립 패키지·부분 성공·실패 재시도 연결이 없습니다.' }
if ($text -notmatch '작업대기_' -or $text -notmatch '실행패키지\.json') { throw '복수 글 작업 대기 또는 재개 자료 저장 연결이 없습니다.' }
$candidatePrompt = Get-Content -LiteralPath (Join-Path $root '구글기반\프롬프트\01_소재_URL_프롬프트.md') -Raw -Encoding UTF8
if ($candidatePrompt -match '20일|30일|7→20') { throw '최근 7일을 넘기는 후보 확장 규칙이 남아 있습니다.' }
if ($candidatePrompt -notmatch '최근 \*\*7일 이내\*\*' -or $candidatePrompt -notmatch '게시일을 원문에서 확인할 수 없는 기사는 선정하지') { throw '최근 7일과 게시일 확인 강제 기준이 없습니다.' }
if ($candidatePreparationText -notmatch '\$age -gt 7' -or $candidatePreparationText -notmatch "Date -eq '게시일 확인 불가'\) \{ continue \}") { throw '코드의 최근 7일·게시일 확인 강제 검사가 없습니다.' }
if ($candidatePreparationText -match '이미 작성한 URL:|and -not \$used\.Contains\(\$url\)') { throw '이전 작성 URL 자동 제외가 남아 있습니다.' }
if ($text -match '(?i)publish|비공개\s*발행|공개\s*발행') { throw '새 글 생성기에 게시 동작이 포함되어 있습니다.' }
foreach ($atomicAction in @('InsertStandaloneHeading','InsertVerticalSpacer','PasteStandaloneParagraphBlock','Assert-AtomicEditorPlan')) {
    if (-not $packageText.Contains($atomicAction)) { throw "네이버 독립 편집 동작 또는 검증기가 없습니다: $atomicAction" }
}
if ($packageText -match "type\s*=\s*'PasteRenderedSegment'") { throw '제목과 본문을 합치는 구간 붙여넣기가 다시 추가되었습니다.' }
Write-Output 'Google 기반 새 글 생성 정적 테스트 통과'

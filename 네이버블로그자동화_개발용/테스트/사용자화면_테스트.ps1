#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $projectRoot '프로그램\네이버자동화.ps1'
$result = & $uiScript -SelfTest
if ($result -notcontains 'Naver automation UI self-test passed.') {
    throw 'The Naver automation UI self-test did not complete.'
}

$layoutResult = & $uiScript -LayoutSelfTest
if ($layoutResult -notcontains 'Naver automation UI layout self-test passed.') {
    throw 'The Naver automation UI layout self-test did not complete.'
}

$uiText = Get-Content -LiteralPath $uiScript -Raw -Encoding UTF8
foreach ($requiredText in @(
    '새 작업 만들기',
    '소재 수집 검사',
    '기사 선택 준비',
    'articleSelectorPath',
    '-Mode Show',
    '추천 순위:',
    '사실검증 검사',
    '초안 작업 준비',
    '비공개 편집기 계획',
    'editorRebuildPlanPath',
    '전체 편집기 재구성 계획',
    '재구성 동작 수:',
    '네이버 초안 검사',
    '독자 반응 분석',
    '최소 14일·게시물 5개·조회 100회',
    'readerAnalyticsPath',
    '독자 반응 분석 JSON을 이번 초안에 연결',
    'ReaderAnalysisPath',
    'mobilePreviewPath',
    '390px 로컬 모바일 미리보기',
    'benchmarkSelectorPath',
    '유사 블로그 선정',
    '프롤로그 준비',
    'introPreparePath',
    'WorkType Introduction',
    '네이버에는 아직 입력하거나 저장하지 않았습니다',
    '6. 재구성 실행 검사',
    'editorExecutionValidatorPath',
    '본문 포커스·문단 수·정확한 문자열·문단 합침·간격 높이',
    '7. 편집기 결과 검사',
    'editorResultValidatorPath',
    '비공개 저장 후 검증입니까',
    '공개 발행 시도와 공지 등록은 없어야 합니다',
    'LayoutSelfTest',
    'Assert-ControlWithinParent',
    'Assert-NoControlOverlap',
    '문장·제목·이미지·표는 복사하지 않고',
    'requiredFocusTopics',
    'requiredConvergenceDomains',
    'RequireClearAIConnection',
    'RequireIndustryImpact',
    'TreatAsConnectedSystem',
    'PrioritizeGlobalProfessionalMedia',
    'Set-StageButtons',
    'nextStage',
    '공개 게시 기능은 포함하지 않습니다'
)) {
    if ($uiText.IndexOf($requiredText, [System.StringComparison]::Ordinal) -lt 0) {
        throw "The user interface is missing required text: $requiredText"
    }
}

$draftStageIndex = $uiText.IndexOf('-Stage NaverDraft', [System.StringComparison]::Ordinal)
$editorPlanIndex = $uiText.IndexOf('비공개 편집기 계획', [System.StringComparison]::Ordinal)
if ($draftStageIndex -lt 0 -or $editorPlanIndex -lt $draftStageIndex) {
    throw 'The private editor plan is not created after Naver draft validation.'
}

Write-Output 'User interface tests passed.'

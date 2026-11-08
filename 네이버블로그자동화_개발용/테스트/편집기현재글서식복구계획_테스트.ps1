#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$script=Join-Path $root '프로그램\편집기현재글서식복구계획.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('naver-repair-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    $block=Join-Path $temp 'callout.html'
    $paragraphBlock=Join-Path $temp 'paragraph.html'
    Set-Content -LiteralPath $paragraphBlock -Encoding UTF8 -Value '<html><head><title>입력 블록 제목</title></head><body><div><p style="font-weight:400">일반 <b>본문</b> 문단</p></div></body></html>'
    Set-Content -LiteralPath $block -Encoding UTF8 -Value '<div><p style="font-weight:700">강조 제목</p><p style="font-weight:400">강조 본문</p><div style="margin-bottom:18px"><strong>누가 (Who) : </strong>실제 주체</div></div>'
    $planPath=Join-Path $temp 'plan.json'; $outPath=Join-Path $temp 'repair.json'
    [pscustomobject]@{
        contentId='TEST'; stopPoint='BeforePublicationSettings'; publicationSettingsOpened=$false
        actions=@(
            [pscustomobject]@{order=1;type='PasteStandaloneParagraphBlock';path=$paragraphBlock},
            [pscustomobject]@{order=2;type='InsertStandaloneHeading';text='대제목';fontSizePx=19},
            [pscustomobject]@{order=3;type='InsertStandaloneHeading';text='소제목';fontSizePx=17},
            [pscustomobject]@{order=4;type='PasteRenderedAtomicBlock';path=$block;formatting=[pscustomobject]@{applyToCalloutBody=$true}}
        )
    } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $planPath -Encoding UTF8
    $result=& $script -EditorPlanPath $planPath -OutputPath $outPath | ConvertFrom-Json
    if ($result.schemaVersion -ne 3) { throw '복구 계약 스키마 버전 오류' }
    if (-not (Test-Path -LiteralPath $result.executor.modulePath) -or $result.executor.method -ne 'run') { throw '실제 실행 모듈 연결 누락' }
    $verifyEditor=@($result.actions | Where-Object action -eq 'VerifyNewPostEditor')
    if ($verifyEditor.Count -ne 1 -or $verifyEditor[0].browserBinding -ne 'ChromeExtensionTab' -or -not $verifyEditor[0].forbidWindowsAppWindowBinding -or -not $verifyEditor[0].requireOuterAndInnerUrlMatch) { throw 'Chrome 확장 탭 URL 이중 검증 가드 누락' }
    if (@($result.actions | Where-Object action -eq 'NormalizeAllBodyText').Count -ne 0) { throw '혼합 서식에서 위험한 전체 굵기 토글이 남아 있습니다.' }
    $body=@($result.actions | Where-Object action -eq 'ApplyBodyParagraphByExactText')
    if ($body.Count -ne 1 -or $body[0].text -ne '일반 본문 문단' -or $body[0].mutationMode -ne 'SetStateNotToggle' -or $body[0].selectionMode -ne 'NativeTripleClickRenderedParagraph' -or -not $body[0].forbidAccessibilitySelectText -or $body[0].postcondition.requiredFontClass -ne 'se-fs15' -or $body[0].postcondition.forbiddenFontClass -ne 'se-fs30' -or $body[0].postcondition.expectedBoldElementCount -ne 0) { throw '일반 문단 네이티브 선택·DOM 서식 복구 동작 누락' }
    $calloutBody=@($result.actions | Where-Object action -eq 'ApplyCalloutBodyByExactText')
    if ($calloutBody.Count -ne 1 -or $calloutBody[0].text -ne '강조 본문' -or $calloutBody[0].postcondition.expectedBoldElementCount -ne 0 -or $calloutBody[0].postcondition.expectedLineHeight -ne '1.6') { throw '강조 본문 DOM 굵기 해제 검증 누락' }
    $mixed=@($result.actions | Where-Object action -eq 'ApplyMixedCalloutParagraphByExactText')
    if ($mixed.Count -ne 1 -or $mixed[0].text -ne '누가 (Who) : 실제 주체' -or @($mixed[0].boldLabels).Count -ne 1 -or $mixed[0].boldLabels[0] -ne '누가 (Who) :' -or $mixed[0].postcondition.expectedBoldElementCount -ne 1) { throw '육하원칙 굵은 라벨 보존 동작 누락' }
    if (@($result.actions | Where-Object action -eq 'ApplyHeadingByExactText').Count -ne 2) { throw '소제목 복구 동작 누락' }
    if (@($result.actions | Where-Object action -eq 'ApplyCalloutTitleByExactText').Count -ne 1) { throw '강조 제목 복구 동작 누락' }
    $audit=@($result.actions | Where-Object action -eq 'AuditWholeEditor')
    if ($audit.Count -ne 1 -or -not $audit[0].requireBodyBoldFalse -or -not $audit[0].rejectMergedHeadingBody -or -not $audit[0].rejectGlobalBoldToggle -or -not $audit[0].requirePerParagraphRenderedDomAudit -or -not $audit[0].rejectToolbarOnlyAudit -or -not $audit[0].rejectAccessibilitySelectText -or $audit[0].maxRepairPasses -ne 2) { throw '전체 DOM 감사·재시도 제한 동작 누락' }
    if (-not (Test-Path -LiteralPath $outPath)) { throw '복구 계약 파일 미생성' }
    if ($result.executionStatus -ne 'NotExecuted' -or $result.liveEditorVerified) { throw '계획 생성은 실제 적용 완료가 아닙니다.' }
    foreach ($item in @($calloutBody) + @($mixed)) {
        if ($item.lineHeightPx -ne ($item.fontSizePx * 1.6)) { throw '상자 줄높이 실행값과 검증값 모순' }
    }
    $invalidPlan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    $invalidPlan.actions[1].fontSizePx=30
    $invalidPlan | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $planPath -Encoding UTF8
    $rejected=$false
    try { $null=& $script -EditorPlanPath $planPath -OutputPath $outPath } catch { $rejected=$true }
    if (-not $rejected) { throw '30px 소제목 계획을 거부하지 않았습니다.' }
    'Current editor formatting repair-plan tests passed.'
}
finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force} }

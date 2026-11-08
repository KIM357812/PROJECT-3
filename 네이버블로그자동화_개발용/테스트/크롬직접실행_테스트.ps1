#requires -Version 5.1
$ErrorActionPreference='Stop'
$node=(Get-Command node -ErrorAction Stop).Source
$test=Join-Path $PSScriptRoot '크롬직접실행.test.mjs'
& $node --test $test
if($LASTEXITCODE -ne 0){throw 'Chrome direct runner Node tests failed.'}
$runnerText=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) '프로그램\크롬직접실행.mjs') -Raw -Encoding UTF8
if($runnerText -notmatch 'se-set-rep-image-button' -or $runnerText -notmatch 'representativeImageVerified'){throw '첫 번째 이미지 대표 지정·검증 코드가 없습니다.'}
foreach($required in @('Browser.getWindowForTarget','preferredTargetId','isolatedFromDuplicates','DedicatedChromeDevTools')){
    if(-not $runnerText.Contains($required)){throw "Chrome URL·창 고정 복구 코드 누락: $required"}
}
if($runnerText.Contains('MULTIPLE_EDITOR_TABS_REQUIRE_SINGLE_TAB')){throw '중복 편집기 탭 강제 중단 코드가 남았습니다.'}
$nativeText=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) '프로그램\크롬네이티브입력.ps1') -Raw -Encoding UTF8
foreach($required in @('ExpectedLeft','ExpectedTop','ExpectedWidth','ExpectedHeight','NATIVE_INPUT_TARGET_WINDOW_AMBIGUOUS')){
    if(-not $nativeText.Contains($required)){throw "CDP 창 경계 기반 선택 코드 누락: $required"}
}
$directText=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) '프로그램\크롬직접연결.ps1') -Raw -Encoding UTF8
foreach($required in @('RecoveryRetryCount','browser-recovery-attempts.json','TargetId')){
    if(-not $directText.Contains($required)){throw "Chrome 자동 복구 코드 누락: $required"}
}
Write-Output 'Chrome direct runner tests passed.'

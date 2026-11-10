#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$paths=@(
    (Join-Path $root '프로그램\네이버자동화.ps1'),
    (Join-Path $root '프로그램\구글기반_새글생성.ps1'),
    (Join-Path $root '구글기반\프로그램\시작.ps1'),
    (Join-Path $root '구글기반\프로그램\공통.ps1'),
    (Join-Path $root '구글기반\프로그램\선택글_생성작업.ps1')
)
$texts=@{}
foreach($path in $paths){$texts[$path]=Get-Content -LiteralPath $path -Raw -Encoding UTF8}
$combined=($texts.Values -join "`n")
foreach($forbidden in @('RetryLatest','Retry-LatestRun','Get-LatestRetryableRun','실패한 글만 다시 작성','retryButton','재시도 필요','기사 다시 선택','전체 작업 다시 시작','소재 실패','내부 사실검증표 부족')){
    if($combined.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase)-ge 0){throw "수동 재시도 또는 중간 실패 표시가 활성 코드에 남아 있습니다: $forbidden"}
}
$start=$texts[(Join-Path $root '구글기반\프로그램\시작.ps1')]
$worker=$texts[(Join-Path $root '구글기반\프로그램\선택글_생성작업.ps1')]
$wrapper=$texts[(Join-Path $root '프로그램\구글기반_새글생성.ps1')]
$ui=$texts[(Join-Path $root '프로그램\네이버자동화.ps1')]
if($start -match '\$maximumParallel=2|\$maximumAutomaticRecoveryPasses=3|Start-Job\s+-FilePath\s+\$workerPath'){throw '병렬 일괄 완료 또는 외부 중첩 재시도가 남아 있습니다.'}
if($start -notmatch 'foreach\(\$item in \$pending\)' -or $start -notmatch '번 글이 준비되었습니다'){throw '입력 순서별 한 건 생성·즉시 완료 흐름이 없습니다.'}
if($worker -notmatch 'RecoveryStatePath' -or $worker -notmatch "'Recovering'" -or $worker -notmatch "'Completed'"){throw '글별 단계 복구 상태가 기록되지 않습니다.'}
if($wrapper -notmatch 'for\(\$packageAttempt=1;\$packageAttempt -le 3' -or $wrapper -notmatch 'schemaVersion\s*=\s*3' -or $wrapper -notmatch 'Get-InterruptedGenerationState'){throw '패키지 단계 내부 자동복구·자동 재개 또는 새 큐 스키마가 없습니다.'}
if($ui -notmatch '선택한 글을 준비하고 있습니다\.' -or $ui -notmatch '모두 완성되었습니다'){throw '사용자 화면의 최종 상태 문구가 없습니다.'}
'Automatic recovery and manual retry removal tests passed.'

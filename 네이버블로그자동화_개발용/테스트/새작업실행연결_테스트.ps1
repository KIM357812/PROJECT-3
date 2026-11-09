#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Join-Path $env:TEMP ('naver-wrapper-'+[guid]::NewGuid())
$oldRuntime=$env:NAVER_AUTOMATION_RUNTIME_ROOT
try {
    $program=Join-Path $root '프로그램'
    $source=Join-Path $root '구글기반/프로그램'
    $null=New-Item -ItemType Directory -Path $program,$source -Force
    foreach($name in @('구글기반_새글생성.ps1','새글생성결과검증.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('../프로그램/'+$name)) -Destination $program
    }
    @'
param([switch]$NoWatcher,[switch]$AutoStart,[switch]$CachedOnly,[string]$SearchResponsePath,[switch]$RetryLatest,[string]$RetryStatePath='')
$run=Join-Path $env:NAVER_AUTOMATION_RUNTIME_ROOT '작업대기/current'
$null=New-Item -ItemType Directory -Path $run -Force
$statePath=Join-Path $run '작업상태.json'
if($RetryLatest){
    if([IO.Path]::GetFullPath($RetryStatePath) -ne [IO.Path]::GetFullPath($statePath)){throw 'Exact retry state was not forwarded'}
    $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json
    $candidate=@($state.Failed)[0].Candidate
    $article=Join-Path $env:NAVER_AUTOMATION_RUNTIME_ROOT ('작업완료/'+[string]$candidate.Slug)
    $null=New-Item -ItemType Directory -Path $article -Force
    'fixture retry'|Set-Content -LiteralPath (Join-Path $article 'Blogger에_붙여넣을_본문.html')
    $completed=@($state.Completed)+@(@{Path=$article;Candidate=$candidate})
    @{Status='글 작성 완료';Failed=@();Completed=$completed}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $statePath -Encoding UTF8
    return
}
if(-not $NoWatcher -or -not $AutoStart -or -not $CachedOnly -or $SearchResponsePath -ne 'fixture'){throw 'Named parameter binding failed'}
$articles=@()
foreach($name in @('third','first')){
    $article=Join-Path $env:NAVER_AUTOMATION_RUNTIME_ROOT ('작업완료/'+$name)
    $null=New-Item -ItemType Directory -Path $article -Force
    'fixture'|Set-Content -LiteralPath (Join-Path $article 'Blogger에_붙여넣을_본문.html')
    $articles+=@{Path=$article;Candidate=@{Number=1;Title=$name;Slug=$name}}
}
@{Status='부분 완료';Failed=@(@{Candidate=@{Number=12;Title='second';Slug='second'};Message='fixture failure'});Completed=$articles}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $statePath -Encoding UTF8
'@ | Set-Content -LiteralPath (Join-Path $source '시작.ps1') -Encoding UTF8
    @'
param($SourceArticlePath,$WorkRoot,$ContentId)
$outputRoot=Join-Path $WorkRoot $ContentId
$null=New-Item -ItemType Directory -Path $outputRoot -Force
$leaf=Split-Path $SourceArticlePath -Leaf
$failureMarker=Join-Path $WorkRoot 'first-package-failed-once.marker'
if($leaf -eq 'first' -and -not(Test-Path -LiteralPath $failureMarker)){
    'failed once'|Set-Content -LiteralPath $failureMarker
    throw 'fixture package failure'
}
@{source=$SourceArticlePath;outputRoot=$outputRoot;contentId=$ContentId;title=(Split-Path $SourceArticlePath -Leaf)}|ConvertTo-Json
'@ | Set-Content -LiteralPath (Join-Path $program '구글기반_네이버패키지.ps1') -Encoding UTF8

    $work=Join-Path $root '한글 작업'
    $result=& (Join-Path $program '구글기반_새글생성.ps1') -WorkRoot $work -CachedOnly -SearchResponsePath fixture|ConvertFrom-Json
    $packages=@($result.packages)
    if($result.status -ne 'PartiallyCompleted' -or $result.completedCount -ne 1 -or $result.failedCount -ne 2 -or -not $result.canRetryFailed){throw 'Partial result was rejected'}
    if($packages.Count -ne 1 -or $packages[0].source -notlike '*작업완료*third'){throw 'Completed package order was not preserved'}
    foreach($package in $packages){if($package.contentId -notlike 'NTE-*' -or -not(Test-Path -LiteralPath (Join-Path $package.outputRoot '실행패키지.json'))){throw 'Independent execution package was not saved'}}
    $initialRoots=@($packages|ForEach-Object outputRoot)
    if(-not(Test-Path -LiteralPath $result.queueManifest)){throw 'Queue manifest was not saved'}

    $retry=& (Join-Path $program '구글기반_새글생성.ps1') -WorkRoot $work -RetryLatest|ConvertFrom-Json
    $retryPackages=@($retry.packages)
    if($retry.status -ne 'Completed' -or $retry.completedCount -ne 3 -or $retry.failedCount -ne 0 -or $retry.canRetryFailed){throw 'Retry did not complete only the preserved failure'}
    if($retryPackages.Count -ne 3 -or $retryPackages[1].source -notlike '*작업완료*first' -or $retryPackages[2].source -notlike '*작업완료*second'){throw 'Generation and package failures were not both retried'}
    if($retryPackages[0].outputRoot -ne $initialRoots[0]){throw 'Completed packages were duplicated during retry'}
    if($retry.runStatePath -ne $result.runStatePath){throw 'Retry created a new search run instead of resuming the failed state'}
    if($env:NAVER_AUTOMATION_RUNTIME_ROOT -ne $oldRuntime){throw 'Runtime environment leaked'}
    'New-work wrapper integration tests: PASS (partial success and failed-only retry, no browser)'
} finally {
    if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}

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
param([switch]$NoWatcher,[switch]$AutoStart,[switch]$CachedOnly,[string]$SearchResponsePath,[string]$ResumeStatePath='')
if(-not $NoWatcher){throw 'Named parameter binding failed'}
if($ResumeStatePath){
    $state=Get-Content -LiteralPath $ResumeStatePath -Raw -Encoding UTF8|ConvertFrom-Json
    $candidate=@($state.Candidates|Where-Object Number -eq 7)[0]
    $article=Join-Path $env:NAVER_AUTOMATION_RUNTIME_ROOT '작업완료/resumed'
    $null=New-Item -ItemType Directory -Path $article -Force
    'resumed fixture'|Set-Content -LiteralPath (Join-Path $article 'Blogger에_붙여넣을_본문.html')
    $state.Status='글 작성 완료';$state.Completed=@(@{Number=7;Path=$article;Candidate=$candidate});$state.Failed=@()
    $state|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $ResumeStatePath -Encoding UTF8
    return
}
if(-not $AutoStart -or -not $CachedOnly -or $SearchResponsePath -ne 'fixture'){throw 'New-work named parameter binding failed'}
$run=Join-Path $env:NAVER_AUTOMATION_RUNTIME_ROOT '작업대기/current'
$null=New-Item -ItemType Directory -Path $run -Force
$statePath=Join-Path $run '작업상태.json'
$articles=@()
foreach($entry in @(@{name='third';number=3},@{name='first';number=10},@{name='second';number=12})){
    $article=Join-Path $env:NAVER_AUTOMATION_RUNTIME_ROOT ('작업완료/'+$entry.name)
    $null=New-Item -ItemType Directory -Path $article -Force
    'fixture'|Set-Content -LiteralPath (Join-Path $article 'Blogger에_붙여넣을_본문.html')
    $articles+=@{Path=$article;Candidate=@{Number=$entry.number;Title=$entry.name;Slug=$entry.name}}
}
@{Status='글 작성 완료';Failed=@();Completed=$articles}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $statePath -Encoding UTF8
'@ | Set-Content -LiteralPath (Join-Path $source '시작.ps1') -Encoding UTF8
    @'
param($SourceArticlePath,$WorkRoot,$ContentId)
$outputRoot=Join-Path $WorkRoot $ContentId
$leaf=Split-Path $SourceArticlePath -Leaf
$failureMarker=Join-Path $WorkRoot 'first-package-failed-once.marker'
if($leaf -eq 'first' -and -not(Test-Path -LiteralPath $failureMarker)){
    $null=New-Item -ItemType Directory -Path $WorkRoot -Force
    'failed once'|Set-Content -LiteralPath $failureMarker
    throw 'fixture package failure'
}
$null=New-Item -ItemType Directory -Path $outputRoot -Force
@{source=$SourceArticlePath;outputRoot=$outputRoot;contentId=$ContentId;title=$leaf}|ConvertTo-Json
'@ | Set-Content -LiteralPath (Join-Path $program '구글기반_네이버패키지.ps1') -Encoding UTF8

    $work=Join-Path $root '한글 작업'
    $result=& (Join-Path $program '구글기반_새글생성.ps1') -WorkRoot $work -CachedOnly -SearchResponsePath fixture|ConvertFrom-Json
    $packages=@($result.packages)
    if($result.status -ne 'Completed' -or $result.completedCount -ne 3 -or $result.failedCount -ne 0){throw 'Automatic package recovery did not complete all articles'}
    if($null -ne $result.PSObject.Properties['canRetryFailed']){throw 'Manual retry property remains in the result'}
    if($packages.Count -ne 3 -or $packages[0].source -notlike '*작업완료*third' -or $packages[1].source -notlike '*작업완료*first' -or $packages[2].source -notlike '*작업완료*second'){throw 'Selected article order was not preserved'}
    if(-not(Test-Path -LiteralPath (Join-Path $work 'naver-editor-packages\first-package-failed-once.marker'))){throw 'Package recovery fixture did not fail once'}
    foreach($package in $packages){if($package.contentId -notlike 'NTE-*' -or -not(Test-Path -LiteralPath (Join-Path $package.outputRoot '실행패키지.json'))){throw 'Independent execution package was not saved'}}
    if(-not(Test-Path -LiteralPath $result.queueManifest)){throw 'Queue manifest was not saved'}
    $queue=Get-Content -LiteralPath $result.queueManifest -Raw -Encoding UTF8|ConvertFrom-Json
    if($queue.schemaVersion -ne 3 -or @($queue.packages).Count -ne 3){throw 'Automatic recovery queue manifest is invalid'}
    $interruptedRoot=Join-Path $work 'google-runtime\작업대기\interrupted'
    $null=New-Item -ItemType Directory -Path $interruptedRoot -Force
    $interruptedPath=Join-Path $interruptedRoot '작업상태.json'
    @{Status='글 작성 중';SelectedNumbers=@(7);Candidates=@(@{Number=7;Title='resumed';Slug='resumed'});Completed=@();Failed=@()}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $interruptedPath -Encoding UTF8
    $resumed=& (Join-Path $program '구글기반_새글생성.ps1') -WorkRoot $work -CachedOnly -SearchResponsePath fixture|ConvertFrom-Json
    if($resumed.status -ne 'Completed' -or $resumed.completedCount -ne 1 -or @($resumed.packages)[0].source -notlike '*작업완료*resumed'){throw 'Interrupted run did not resume from its saved state'}
    if($env:NAVER_AUTOMATION_RUNTIME_ROOT -ne $oldRuntime){throw 'Runtime environment leaked'}
    'New-work wrapper integration tests: PASS (automatic failed-stage recovery, no manual retry, no browser)'
} finally {
    if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}

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
param([switch]$NoWatcher,[switch]$AutoStart,[switch]$CachedOnly,[string]$SearchResponsePath)
if(-not $NoWatcher -or -not $AutoStart -or -not $CachedOnly -or $SearchResponsePath -ne 'fixture'){throw 'Named parameter binding failed'}
$run=Join-Path $env:NAVER_AUTOMATION_RUNTIME_ROOT '작업대기/current'
$null=New-Item -ItemType Directory -Path $run -Force
$articles=@()
foreach($name in @('third','first','second')){
    $article=Join-Path $env:NAVER_AUTOMATION_RUNTIME_ROOT ('작업완료/'+$name)
    $null=New-Item -ItemType Directory -Path $article -Force
    'fixture' | Set-Content -LiteralPath (Join-Path $article 'Blogger에_붙여넣을_본문.html')
    $articles+=@{Path=$article}
}
@{Status='글 작성 완료';Failed=@();Completed=$articles} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run '작업상태.json') -Encoding UTF8
'@ | Set-Content -LiteralPath (Join-Path $source '시작.ps1') -Encoding UTF8
    @'
param($SourceArticlePath,$WorkRoot,$ContentId)
$outputRoot=Join-Path $WorkRoot $ContentId
$null=New-Item -ItemType Directory -Path $outputRoot -Force
@{source=$SourceArticlePath;outputRoot=$outputRoot;contentId=$ContentId;title=(Split-Path $SourceArticlePath -Leaf)} | ConvertTo-Json
'@ | Set-Content -LiteralPath (Join-Path $program '구글기반_네이버패키지.ps1') -Encoding UTF8
    $result=& (Join-Path $program '구글기반_새글생성.ps1') -WorkRoot (Join-Path $root '한글 작업') -CachedOnly -SearchResponsePath fixture | ConvertFrom-Json
    $packages=@($result.packages)
    if($result.selectedCount -ne 3 -or $packages.Count -ne 3 -or $packages[0].source -notlike '*작업완료*third' -or $packages[1].source -notlike '*작업완료*first' -or $packages[2].source -notlike '*작업완료*second'){throw 'Selected article order was not forwarded to adapters'}
    foreach($package in $packages){if($package.contentId -notlike 'NTE-*' -or -not(Test-Path -LiteralPath (Join-Path $package.outputRoot '실행패키지.json'))){throw 'Independent execution package was not saved'}}
    if(-not(Test-Path -LiteralPath $result.queueManifest)){throw 'Queue manifest was not saved'}
    if($env:NAVER_AUTOMATION_RUNTIME_ROOT -ne $oldRuntime){throw 'Runtime environment leaked'}
    'New-work wrapper integration tests: PASS (fixture generator, no browser)'
} finally {
    if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}

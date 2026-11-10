#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceArticlePath,
    [Parameter(Mandatory=$true)][string]$WorkRoot,
    [Parameter(Mandatory=$true)][string]$ProgressDirectory,
    [Parameter(Mandatory=$true)][int]$Sequence,
    [Parameter(Mandatory=$true)][int]$Number
)
$ErrorActionPreference='Stop'
$adapterPath=Join-Path $PSScriptRoot '구글기반_네이버패키지.ps1'
if(-not(Test-Path -LiteralPath $adapterPath -PathType Leaf)){throw '네이버 패키지 변환기를 찾을 수 없습니다.'}
[IO.Directory]::CreateDirectory($WorkRoot)|Out-Null
[IO.Directory]::CreateDirectory($ProgressDirectory)|Out-Null
$contentId='NTE-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')+('-{0:D2}-' -f $Sequence)+[guid]::NewGuid().ToString('N').Substring(0,6)
$package=& $adapterPath -SourceArticlePath ([IO.Path]::GetFullPath($SourceArticlePath)) -WorkRoot ([IO.Path]::GetFullPath($WorkRoot)) -ContentId $contentId|ConvertFrom-Json
$package|Add-Member -NotePropertyName sourceArticlePath -NotePropertyValue ([IO.Path]::GetFullPath($SourceArticlePath)) -Force
$executionPackagePath=Join-Path ([string]$package.outputRoot) '실행패키지.json'
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($executionPackagePath,($package|ConvertTo-Json -Depth 15),$utf8)
$record=[pscustomobject]@{sequence=$Sequence;number=$Number;path=[IO.Path]::GetFullPath($SourceArticlePath);completedAt=(Get-Date).ToString('o');package=$package}
$finalPath=Join-Path $ProgressDirectory ('completed-{0:D2}-{1}.json' -f $Sequence,$Number)
$temporary=$finalPath+'.tmp-'+[guid]::NewGuid().ToString('N')
[IO.File]::WriteAllText($temporary,($record|ConvertTo-Json -Depth 18),$utf8)
[IO.File]::Move($temporary,$finalPath)
$record|ConvertTo-Json -Depth 18

param([switch]$NoWatcher,[switch]$Console)
$ErrorActionPreference='Stop'
$entry=if($Console){Join-Path $PSScriptRoot '프로그램\시작.ps1'}else{Join-Path $PSScriptRoot '직원용_실행.ps1'}
if(-not [IO.File]::Exists($entry)){throw "실행 프로그램을 찾지 못했습니다: $entry"}
if($Console){& $entry -NoWatcher:$NoWatcher}else{& $entry}

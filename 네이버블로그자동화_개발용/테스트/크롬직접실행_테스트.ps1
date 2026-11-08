#requires -Version 5.1
$ErrorActionPreference='Stop'
$node=(Get-Command node -ErrorAction Stop).Source
$test=Join-Path $PSScriptRoot '크롬직접실행.test.mjs'
& $node --test $test
if($LASTEXITCODE -ne 0){throw 'Chrome direct runner Node tests failed.'}
$runnerText=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) '프로그램\크롬직접실행.mjs') -Raw -Encoding UTF8
if($runnerText -notmatch 'se-set-rep-image-button' -or $runnerText -notmatch 'representativeImageVerified'){throw '첫 번째 이미지 대표 지정·검증 코드가 없습니다.'}
Write-Output 'Chrome direct runner tests passed.'

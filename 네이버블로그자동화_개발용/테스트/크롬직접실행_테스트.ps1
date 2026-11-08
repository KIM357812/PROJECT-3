#requires -Version 5.1
$ErrorActionPreference='Stop'
$node=(Get-Command node -ErrorAction Stop).Source
$test=Join-Path $PSScriptRoot '크롬직접실행.test.mjs'
& $node --test $test
if($LASTEXITCODE -ne 0){throw 'Chrome direct runner Node tests failed.'}
Write-Output 'Chrome direct runner tests passed.'

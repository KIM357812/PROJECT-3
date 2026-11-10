#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dispatcherPath=Join-Path $root '프로그램\이미지ChatGPT실행부.ps1'
$generationPath=Join-Path $root '프로그램\구글기반_새글생성.ps1'
$configPath=Join-Path $root '네이버통합설정.json'
foreach($path in @($dispatcherPath,$generationPath,$configPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "필수 파일이 없습니다: $path"}}
$dispatcher=Get-Content -LiteralPath $dispatcherPath -Raw -Encoding UTF8
$generation=Get-Content -LiteralPath $generationPath -Raw -Encoding UTF8
$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json
if($dispatcher -notmatch 'image_gen\.imagegen' -or $dispatcher -notmatch 'installed imagegen skill'){throw 'ChatGPT 내장 imagegen 호출 지시가 없습니다.'}
if($dispatcher -notmatch 'MaximumParallel=2' -or $dispatcher -notmatch 'while\(\$queue\.Count -gt 0 -or \$active\.Count -gt 0\)'){throw '이미지 최대 2장 병렬 실행부가 없습니다.'}
if($dispatcher -notmatch 'Find-GeneratedImage' -or $dispatcher -notmatch 'Pending' -or $dispatcher -notmatch 'Completed'){throw '완성 원본 재사용 및 상태 저장 기능이 없습니다.'}
if($dispatcher -notmatch 'Do not add captions' -or $dispatcher -notmatch 'Do not draw or invent a company logo'){throw '문자·가짜 로고 방지 지시가 없습니다.'}
if($generation -notmatch 'NAVER_AUTOMATION_IMAGE_DISPATCHER' -or $generation -notmatch '이미지ChatGPT실행부\.ps1'){throw '새 글 실행 흐름에 기본 이미지 실행부가 연결되지 않았습니다.'}
if([int]$config.ImageGenerationPerformance.MaximumParallelImages -ne 2 -or -not[bool]$config.ImageGenerationPerformance.StartBeforeArticleDraft){throw '이미지 선행·병렬 설정이 올바르지 않습니다.'}
Write-Output 'ChatGPT image dispatcher test passed.'

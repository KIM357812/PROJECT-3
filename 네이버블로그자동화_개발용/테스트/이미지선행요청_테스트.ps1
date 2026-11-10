#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$scriptPath=Join-Path $root '프로그램\이미지선행요청.ps1'
$configPath=Join-Path $root '네이버통합설정.json'
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('NTE-image-request-'+[guid]::NewGuid().ToString('N'))
try{
    [IO.Directory]::CreateDirectory($tempRoot)|Out-Null
    $itemPath=Join-Path $tempRoot 'item.json'
    [pscustomobject]@{
        Number=7;Title='AI 데이터센터 전력망 시험 기사';Site='Test Media';Url='https://example.com/article';Date='2026-11-10'
        Details='데이터센터 부하와 전력망 운영 변화, 실제 변전소와 운영 인력의 대응을 다룬 기사입니다.'
    }|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $itemPath -Encoding UTF8
    $result=& $scriptPath -ItemPath $itemPath -RunPath $tempRoot -ConfigPath $configPath -NoDispatch|ConvertFrom-Json
    if(-not(Test-Path -LiteralPath ([string]$result.requestPath) -PathType Leaf)){throw '기사 선택 직후 이미지 요청 파일이 생성되지 않았습니다.'}
    $request=Get-Content -LiteralPath ([string]$result.requestPath) -Raw -Encoding UTF8|ConvertFrom-Json
    if(@($request.assets).Count -ne 4){throw '대표·현황·구조·전망 이미지 요청 네 건이 생성되지 않았습니다.'}
    if(-not[bool]$request.execution.startImmediately -or -not[bool]$request.execution.runInParallelWithArticleDraft){throw '본문보다 먼저 시작하는 병렬 이미지 요청 설정이 없습니다.'}
    if(-not[bool]$request.specification.preserveOriginals -or [int]$request.specification.maximumKilobytes -ne 450){throw '원본 보존 또는 게시용 450KB 압축 계약이 없습니다.'}
    if(-not[bool]$request.specification.allowVerifiedOfficialLogos -or -not[bool]$request.specification.forbidAiRenderedLogos){throw '검증된 공식 로고만 허용하는 정책이 없습니다.'}
    $allPrompts=@($request.assets|ForEach-Object{[string]$_.prompt}) -join "`n"
    foreach($required in @('photorealistic','textless','no text','no watermark','no AI-generated logos','cause, action, and consequence')){
        if($allPrompts.IndexOf($required,[StringComparison]::OrdinalIgnoreCase)-lt 0){throw "이미지 선행 프롬프트 필수 문구가 없습니다: $required"}
    }
    $second=& $scriptPath -ItemPath $itemPath -RunPath $tempRoot -ConfigPath $configPath -NoDispatch|ConvertFrom-Json
    if(-not[bool]$second.reused -or [string]$second.requestPath -ne [string]$result.requestPath){throw '같은 기사 재개 시 이미지 요청이 중복 생성되었습니다.'}
    Write-Output '이미지 선행 요청 테스트 통과'
}finally{
    if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force}
}

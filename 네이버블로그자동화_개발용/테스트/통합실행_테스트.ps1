#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../프로그램/통합실행결과검증.ps1')
$root=Join-Path $env:TEMP ('naver-run-test-'+[guid]::NewGuid())
$null=New-Item -ItemType Directory -Path $root
try {
    $runnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../프로그램/통합실행.ps1') -Raw -Encoding UTF8
    foreach($requiredInstruction in @('크롬직접연결.ps1','ChatGPT 중계 없이 전용 Chrome 연결','ConnectionTestOnly','-TargetId ([string]$preflight.tabId)')){
        if(-not$runnerText.Contains($requiredInstruction)){throw "통합 실행 직접 연결 누락: $requiredInstruction"}
    }
    $directRunnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../프로그램/크롬직접실행.mjs') -Raw -Encoding UTF8
    foreach($requiredInstruction in @(
        '크롬네이티브입력.ps1','nativePaste','body-all',
        "document.querySelector('#tag-input')?.value",'Input.dispatchKeyEvent',
        'Page.setInterceptFileChooserDialog','DOM.setFileInputFiles',
        'blogfiles\.pstatic\.net','se-section-align-center',
        'displayWidth||400','publicationSettingsOpened:false','published:false'
    )){
        if(-not$directRunnerText.Contains($requiredInstruction)){throw "직접 입력 실행부 누락: $requiredInstruction"}
    }
    foreach($forbidden in @('Send-NaverDesktopTask','Wait-NaverDesktopTask','desktop task: read the local request')){
        if($runnerText.Contains($forbidden)){throw "통합 실행에 채팅 중계가 남았습니다: $forbidden"}
    }
    $direct=[pscustomobject]@{runId='test';status='Ready';errorCode='';reason='';extensionConnected=$false;directChromeConnected=$true;connectionPath='DedicatedChromeDevTools';ownerLoginVerified=$true;naverTabReadVerified=$true;browserId='cdp:9225';tabId='target';url='https://blog.naver.com/ij1128?Redirect=Write&'}
    Assert-NaverBrowserPreflight $direct 'test'
    foreach($case in @(
        @{field='errorCode';value='LOCAL_BROWSER_DISABLED'},
        @{field='runId';value='old-run'},
        @{field='status';value='Failed'},
        @{field='directChromeConnected';value=$false},
        @{field='connectionPath';value='GenericComputerUse'},
        @{field='ownerLoginVerified';value=$false},
        @{field='naverTabReadVerified';value='true'},
        @{field='tabId';value=''},
        @{field='url';value='https://blog.naver.com.evil.test/ij1128'},
        @{field='url';value='https://nid.naver.com/'}
    )) {
        $candidate=$direct|ConvertTo-Json|ConvertFrom-Json
        $candidate.($case.field)=$case.value
        $rejected=$false
        try{Assert-NaverBrowserPreflight $candidate 'test'}catch{$rejected=$true}
        if(-not $rejected){throw "사전검사 오류 허용: $($case.field)"}
    }
    $extensionOnly=$direct|ConvertTo-Json|ConvertFrom-Json
    $extensionOnly.directChromeConnected=$false
    $extensionOnly.extensionConnected=$true
    $rejected=$false;try{Assert-NaverBrowserPreflight $extensionOnly 'test'}catch{$rejected=$true}
    if(-not $rejected){throw '일반 확장 연결이 전용 Chrome 직접 연결을 대신했습니다.'}
    $posted=$direct|ConvertTo-Json|ConvertFrom-Json
    $posted.url='https://blog.naver.com/ij1128/224469188866'
    $rejected=$false;try{Assert-NaverBrowserPreflight $posted 'test'}catch{$rejected=$true}
    if(-not $rejected){throw '기존 게시물 URL을 새 글 편집기로 허용했습니다.'}
    $planPath=Join-Path $root 'editor-plan.json'
    @{actions=@(
        @{order=1;type='UploadImage';path=(Join-Path $root '01.jpg')},
        @{order=2;type='UploadImage';path=(Join-Path $root '02.jpg')}
    )} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planPath -Encoding UTF8
    $measurementPath=Join-Path $root 'measurementFile'
    $mode=@{
        horizontalOverflow=$false
        imageFileNames=@('01.jpg','02.jpg')
        imageServerUrls=@('https://blogfiles.pstatic.net/a/01.jpg','https://blogfiles.pstatic.net/a/02.jpg')
        rawUrlVisible=$false
    }
    $pc=@{}+$mode
    $pc.sourceLinks=@(@{text='원문';href='https://example.com/article'})
    @{schemaVersion=1;measurementSource='RenderedNaverDomAndScreen';pc=$pc;mobile=$mode;secondPass=@{
        wholeArticleFromStart=$true;titleVerified=$true;bodyVerified=$true;headingsVerified=$true;imagesVerified=$true;linksVerified=$true
    }} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $measurementPath -Encoding UTF8
    $r=[pscustomobject]@{runId='test';status='Verified';reason='';publicationSettingsOpened=$false;published=$false;editorUrl='https://blog.naver.com/ij1128?Redirect=Write&'}
    foreach($n in @('imagesGenerated','imagesOptimized','imagesUploaded','titleVerified','bodyVerified','linksVerified','tagsVerified','formatVerified','mobileVerified','secondPassVerified')){$r|Add-Member $n $true}
    foreach($n in @('pcScreenshot','mobileScreenshot')){$p=Join-Path $root $n;'fixture'|Set-Content $p;$r|Add-Member $n $p}
    $r|Add-Member measurementFile $measurementPath
    Assert-NaverRunResult $r 'test' $root $planPath
    $r|Add-Member publicationSettingsEverOpenedForTags $true
    $r|Add-Member publicationSettingsPurpose 'TagsOnly'
    $r|Add-Member visibilityChanged $false
    $r|Add-Member scheduleChanged $false
    $r|Add-Member publishButtonClicked $false
    Assert-NaverRunResult $r 'test' $root $planPath $true
    $r.publishButtonClicked=$true;$rejected=$false
    try{Assert-NaverRunResult $r 'test' $root $planPath $true}catch{$rejected=$true}
    if(-not $rejected){throw '태그 전용 실행의 발행 클릭 차단 실패'};$r.publishButtonClicked=$false
    foreach($n in @('imagesGenerated','imagesOptimized','imagesUploaded','titleVerified','bodyVerified','linksVerified','tagsVerified','formatVerified','mobileVerified','secondPassVerified')) {
        $r.$n=$false;$rejected=$false
        try {Assert-NaverRunResult $r 'test' $root $planPath}catch{$rejected=$true}
        if(-not $rejected){throw "누락 통과 오류: $n"};$r.$n=$true
    }
    $r.published=$true;$rejected=$false
    try{Assert-NaverRunResult $r 'test' $root $planPath}catch{$rejected=$true}
    if(-not $rejected){throw '발행 상태 차단 실패'};$r.published=$false
    $r.editorUrl='https://blog.naver.com/PostWriteForm.naver?blogId=ij1128&logNo=123'
    $rejected=$false;try{Assert-NaverRunResult $r 'test' $root $planPath}catch{$rejected=$true}
    if(-not $rejected){throw '기존 게시글 차단 실패'}
    $r.editorUrl='https://blog.naver.com/ij1128?Redirect=Write&'
    $measurement=Get-Content -LiteralPath $measurementPath -Raw|ConvertFrom-Json
    $measurement.pc.rawUrlVisible=$true
    $measurement|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $measurementPath -Encoding UTF8
    $rejected=$false;try{Assert-NaverRunResult $r 'test' $root $planPath}catch{$rejected=$true}
    if(-not $rejected){throw 'URL 문자열 노출 차단 실패'}
    $measurement.pc.rawUrlVisible=$false
    $measurement.mobile.imageFileNames=@('02.jpg','01.jpg')
    $measurement|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $measurementPath -Encoding UTF8
    $rejected=$false;try{Assert-NaverRunResult $r 'test' $root $planPath}catch{$rejected=$true}
    if(-not $rejected){throw '모바일 이미지 순서 오류 차단 실패'}
    '통합 실행 완료 게이트 테스트 통과 (실제 브라우저 검증과 별도)'
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'naver-run-test-*') {Remove-Item -LiteralPath $resolved -Recurse -Force}
}

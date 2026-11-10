#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ItemPath,
    [Parameter(Mandatory=$true)][string]$RunPath,
    [string]$ConfigPath,
    [switch]$NoDispatch
)

$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($ConfigPath)){$ConfigPath=Join-Path $projectRoot '네이버통합설정.json'}
foreach($required in @($ItemPath,$ConfigPath)){
    if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "필수 파일을 찾을 수 없습니다: $required"}
}
$item=Get-Content -LiteralPath $ItemPath -Raw -Encoding UTF8|ConvertFrom-Json
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$rules=$config.ImageAutomation
$performance=$config.ImageGenerationPerformance
if(-not[bool]$rules.Enabled){throw '이미지 자동화가 비활성화되어 있습니다.'}
if(-not[bool]$performance.StartImmediatelyAfterArticleSelection){throw '기사 선택 직후 이미지 선행 요청이 비활성화되어 있습니다.'}

$requestRoot=Join-Path $RunPath 'image-requests'
$articleRoot=Join-Path $requestRoot ('article-{0:D2}' -f [int]$item.Number)
$promptRoot=Join-Path $articleRoot 'prompts'
$originalRoot=Join-Path $articleRoot 'original'
foreach($directory in @($requestRoot,$articleRoot,$promptRoot,$originalRoot)){
    if(-not(Test-Path -LiteralPath $directory -PathType Container)){[IO.Directory]::CreateDirectory($directory)|Out-Null}
}
$requestPath=Join-Path $articleRoot 'request.json'
if(Test-Path -LiteralPath $requestPath -PathType Leaf){
    $existing=Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8|ConvertFrom-Json
    [pscustomobject]@{requestPath=[IO.Path]::GetFullPath($requestPath);status=[string]$existing.status;reused=$true}|ConvertTo-Json -Depth 5
    return
}

$title=[string]$item.Title
$details=[string]$item.Details
$site=[string]$item.Site
$roleScenes=@(
    [pscustomobject]@{role='대표';scene='기사의 핵심 사건을 한눈에 보여 주는 넓은 환경 장면. 핵심 인물 또는 장비가 실제 장소에서 행동하고, 원인과 결과가 한 프레임 안에서 자연스럽게 연결되어야 한다.';camera='wide editorial establishing shot'},
    [pscustomobject]@{role='현황';scene='현재 발생한 문제나 변화가 현장 운영에 미치는 영향을 보여 주는 중간 거리 장면. 실제 작업자와 핵심 장비의 상호작용을 분명하게 보여 준다.';camera='medium documentary shot'},
    [pscustomobject]@{role='구조';scene='기술·전력·비용·정책의 연결 구조를 실제 설비와 사람의 업무 흐름으로 설명하는 근접 장면. 추상 아이콘이나 글자 대신 물리적 연결과 행동을 사용한다.';camera='close operational detail shot'},
    [pscustomobject]@{role='전망';scene='기사의 향후 영향과 국내 독자가 주목할 변화를 현실적으로 보여 주는 다른 장소·다른 시간대의 장면. 공상과학적 연출 없이 구현 가능한 미래 운영 모습을 보여 준다.';camera='realistic forward-looking environmental shot'}
)
$roles=@($rules.Roles|Sort-Object Order)
if($roles.Count -ne $roleScenes.Count){throw '이미지 역할 수가 선행 이미지 장면 수와 일치하지 않습니다.'}
$assets=New-Object 'System.Collections.Generic.List[object]'
for($index=0;$index -lt $roles.Count;$index++){
    $role=$roles[$index]
    $scene=$roleScenes[$index]
    $prompt=@"
Create one photorealistic 3:2 editorial photograph for a Korean technology news analysis article.
Article: $title
Publisher: $site
Verified article context: $details
Visual role: $($scene.role) — $($scene.scene)
Camera and composition: $($scene.camera), natural lighting, high detail, professional composition, realistic scale and perspective.
Make the cause, action, and consequence understandable from the scene alone. Use real equipment, a credible location, and purposeful human activity. This image must be visually distinct from the other article images.
textless, no text, no letters, no numbers, no captions, no watermark, no AI-generated logos, no invented logos, no collage, no split screen, no generic neon holograms.
If an official organization or company logo is later required, leave a physically plausible clean surface for a separately verified official logo asset; do not draw or imitate the logo.
"@.Trim()
    $promptPath=Join-Path $promptRoot ('{0:D2}-{1}.txt' -f [int]$role.Order,[string]$role.Name)
    [IO.File]::WriteAllText($promptPath,$prompt,(New-Object Text.UTF8Encoding($true)))
    $assets.Add([pscustomobject]@{
        order=[int]$role.Order;role=[string]$role.Name;purpose=[string]$role.Purpose;placement=[string]$role.Placement
        promptPath=[IO.Path]::GetFullPath($promptPath);prompt=$prompt
        originalBaseName=[string]$role.OriginalBaseName;expectedOutputDirectory=[IO.Path]::GetFullPath($originalRoot)
        status='Pending'
    })
}
$request=[pscustomobject]@{
    schemaVersion=1;requestType='ChatGPTImageGeneration';runId=[guid]::NewGuid().ToString();createdAt=(Get-Date).ToString('o')
    status='Pending';article=[pscustomobject]@{number=[int]$item.Number;title=$title;site=$site;url=[string]$item.Url;date=[string]$item.Date}
    execution=[pscustomobject]@{startImmediately=$true;runInParallelWithArticleDraft=$true;generateEachAssetIndependently=$true;retryFailedImageOnly=$true}
    specification=[pscustomobject]@{
        count=[int]$rules.TargetCount;width=[int]$rules.Width;height=[int]$rules.Height;aspectRatio=[string]$rules.AspectRatio
        finalFormat=[string]$rules.OutputFormat;maximumKilobytes=[int]$rules.MaximumKilobytes;preserveOriginals=$true
        forbidEmbeddedText=$true;forbidWatermarks=$true;allowVerifiedOfficialLogos=$true;requireOfficialLogoAsset=$true;forbidAiRenderedLogos=$true
    }
    assets=@($assets.ToArray());originalDirectory=[IO.Path]::GetFullPath($originalRoot)
}
$temporaryPath=$requestPath+'.tmp-'+[guid]::NewGuid().ToString('N')
$json=$request|ConvertTo-Json -Depth 12
[IO.File]::WriteAllText($temporaryPath,$json,(New-Object Text.UTF8Encoding($true)))
try{
    Move-Item -LiteralPath $temporaryPath -Destination $requestPath -ErrorAction Stop
}catch [System.UnauthorizedAccessException]{
    # Windows AppContainer의 가상 Temp는 같은 폴더 안 이름 변경을 거부할 수 있다.
    # 내용이 완전히 기록된 임시 파일만 최종 이름으로 복사한 뒤 임시 파일을 지운다.
    Copy-Item -LiteralPath $temporaryPath -Destination $requestPath -ErrorAction Stop
    Remove-Item -LiteralPath $temporaryPath -Force
}

$dispatcher=[string]$env:NAVER_AUTOMATION_IMAGE_DISPATCHER
$dispatchStarted=$false
if(-not $NoDispatch -and -not[string]::IsNullOrWhiteSpace($dispatcher) -and (Test-Path -LiteralPath $dispatcher -PathType Leaf)){
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$dispatcher+'"'),'-RequestPath',('"'+$requestPath+'"')) -WindowStyle Hidden|Out-Null
    $dispatchStarted=$true
}
[pscustomobject]@{requestPath=[IO.Path]::GetFullPath($requestPath);status='Pending';reused=$false;dispatchStarted=$dispatchStarted;assetCount=$assets.Count}|ConvertTo-Json -Depth 5

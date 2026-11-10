#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [string]$SourceArticlePath='',
    [int]$RecoveryPass=0
)

$ErrorActionPreference='Stop'
$manifest=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
$assets=@($manifest.assets|Sort-Object order)
function Write-ChatGptRecoveryRequest([object[]]$MissingAssets,[string]$Reason){
    $requestPath=Join-Path (Split-Path -Parent $ManifestPath) 'ChatGPT-이미지-복구요청.json'
    $request=[pscustomobject]@{
        schemaVersion=1;requestType='ChatGPTImageGenerationRecovery';createdAt=(Get-Date).ToString('o');status='Pending'
        reason=$Reason;manifestPath=[IO.Path]::GetFullPath($ManifestPath);originalDirectory=[string]$manifest.originalDirectory
        specification=$manifest.specification
        assets=@($MissingAssets|ForEach-Object{[pscustomobject]@{
            order=[int]$_.order;role=[string]$_.role;prompt=[string]$_.prompt
            originalBaseName=[string]$_.originalBaseName;outputFileName=[string]$_.outputFileName
        }})
    }
    $temporary=$requestPath+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($request|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($true)))
    if(Test-Path -LiteralPath $requestPath -PathType Leaf){Remove-Item -LiteralPath $requestPath -Force}
    try{[IO.File]::Move($temporary,$requestPath)}catch [System.UnauthorizedAccessException]{
        Copy-Item -LiteralPath $temporary -Destination $requestPath -ErrorAction Stop
        Remove-Item -LiteralPath $temporary -Force
    }
    return $requestPath
}
function Invoke-ChatGptRecovery([object[]]$MissingAssets,[string]$Reason){
    $requestPath=Write-ChatGptRecoveryRequest $MissingAssets $Reason
    $dispatcher=[string]$env:NAVER_AUTOMATION_IMAGE_DISPATCHER
    if([string]::IsNullOrWhiteSpace($dispatcher) -or -not(Test-Path -LiteralPath $dispatcher -PathType Leaf)){
        throw "ChatGPT 이미지 생성 실행부가 연결되지 않았습니다. 요청 파일: $requestPath"
    }
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$dispatcher+'"'),'-RequestPath',('"'+$requestPath+'"')) -WindowStyle Hidden|Out-Null
    $waitSeconds=900
    if(-not[string]::IsNullOrWhiteSpace($env:NAVER_AUTOMATION_IMAGE_WAIT_SECONDS)){
        $parsed=0
        if([int]::TryParse($env:NAVER_AUTOMATION_IMAGE_WAIT_SECONDS,[ref]$parsed) -and $parsed -ge 5){$waitSeconds=$parsed}
    }
    $deadline=(Get-Date).AddSeconds($waitSeconds)
    do{
        $remaining=@($MissingAssets|Where-Object{-not(Test-OriginalExists $_)})
        if($remaining.Count -eq 0){return}
        Start-Sleep -Milliseconds 500
    }while((Get-Date) -lt $deadline)
    throw "ChatGPT 이미지 생성 제한시간 안에 원본이 도착하지 않았습니다. 요청 파일: $requestPath"
}
function Test-OriginalExists([object]$Asset){
    $base=[string]$Asset.originalBaseName
    return (@(Get-ChildItem -LiteralPath ([string]$manifest.originalDirectory) -File -ErrorAction SilentlyContinue|Where-Object {$_.BaseName -eq $base}).Count -eq 1)
}
$optimizedMissing=@($assets|Where-Object {-not(Test-Path -LiteralPath (Join-Path ([string]$manifest.optimizedDirectory) ([string]$_.outputFileName)) -PathType Leaf)})
if($optimizedMissing.Count -eq 0){
    $report=& (Join-Path $PSScriptRoot '이미지검증.ps1') -ManifestPath $ManifestPath -ReportOnly|ConvertFrom-Json
    if($report.isValid){$report|ConvertTo-Json -Depth 8;return}
    $repairOrders=@($report.perceptualDuplicatePairs|ForEach-Object {[int]$_.rightOrder}|Sort-Object -Unique)
    if($repairOrders.Count -eq 0){throw ('이미지 자동복구 대상이 아닌 오류입니다: '+(@($report.issues)-join '; '))}
    foreach($order in $repairOrders){
        $asset=@($assets|Where-Object {[int]$_.order -eq $order})[0]
        if($null -eq $asset){continue}
        @(Get-ChildItem -LiteralPath ([string]$manifest.originalDirectory) -File -ErrorAction SilentlyContinue|Where-Object {$_.BaseName -eq [string]$asset.originalBaseName})|ForEach-Object {Remove-Item -LiteralPath $_.FullName -Force}
        $optimizedPath=Join-Path ([string]$manifest.optimizedDirectory) ([string]$asset.outputFileName)
        if(Test-Path -LiteralPath $optimizedPath -PathType Leaf){Remove-Item -LiteralPath $optimizedPath -Force}
        $asset.PSObject.Properties.Remove('sourceSha256')
        $asset.PSObject.Properties.Remove('optimizedSha256')
        $asset.PSObject.Properties.Remove('generationRegisteredAt')
    }
    $manifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    $assets=@($manifest.assets|Sort-Object order)
    $optimizedMissing=@($assets|Where-Object {-not(Test-Path -LiteralPath (Join-Path ([string]$manifest.optimizedDirectory) ([string]$_.outputFileName)) -PathType Leaf)})
    Invoke-ChatGptRecovery @($assets|Where-Object{[int]$_.order -in $repairOrders}) 'PerceptualDuplicate'
}

$originalMissing=@($assets|Where-Object {-not(Test-OriginalExists $_)})
if($originalMissing.Count -gt 0 -and $SourceArticlePath -and (Test-Path -LiteralPath $SourceArticlePath -PathType Container)){
    $sourceFiles=@()
    foreach($name in @('원본이미지','압축이미지')){
        $candidate=Join-Path $SourceArticlePath $name
        if(Test-Path -LiteralPath $candidate -PathType Container){
            $sourceFiles=@(Get-ChildItem -LiteralPath $candidate -File|Where-Object Extension -Match '^\.(jpg|jpeg|png|webp)$'|Sort-Object Name)
            if($sourceFiles.Count -eq $assets.Count){break}
        }
    }
    if($sourceFiles.Count -eq $assets.Count){
        for($index=0;$index -lt $assets.Count;$index++){
            $asset=$assets[$index]
            if(Test-OriginalExists $asset){continue}
            $extension=$sourceFiles[$index].Extension.ToLowerInvariant()
            Copy-Item -LiteralPath $sourceFiles[$index].FullName -Destination (Join-Path ([string]$manifest.originalDirectory) (([string]$asset.originalBaseName)+$extension))
        }
    }
}

$stillMissing=@($assets|Where-Object {-not(Test-OriginalExists $_)})
if($stillMissing.Count -gt 0){
    Invoke-ChatGptRecovery $stillMissing 'MissingOriginal'
    $stillMissing=@($assets|Where-Object {-not(Test-OriginalExists $_)})
}
if($stillMissing.Count -gt 0){throw ('원본 이미지 자동 생성이 완료되지 않았습니다: '+(@($stillMissing|ForEach-Object originalBaseName)-join ', '))}

$null=& (Join-Path $PSScriptRoot '이미지최적화.ps1') -ManifestPath $ManifestPath -RepairMissing|ConvertFrom-Json
$finalReport=& (Join-Path $PSScriptRoot '이미지검증.ps1') -ManifestPath $ManifestPath -ReportOnly|ConvertFrom-Json
if($finalReport.isValid){$finalReport|ConvertTo-Json -Depth 8;return}
if(@($finalReport.perceptualDuplicatePairs).Count -gt 0 -and $RecoveryPass -lt 3){
    return & $PSCommandPath -ManifestPath $ManifestPath -SourceArticlePath $SourceArticlePath -RecoveryPass ($RecoveryPass+1)
}
throw ('이미지 자동복구 후 검증에 실패했습니다: '+(@($finalReport.issues)-join '; '))

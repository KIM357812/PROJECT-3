#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkRoot,
    [switch]$CachedOnly,
    [string]$SearchResponsePath,
    [string]$ProgressDirectory,
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$googleRoot = Join-Path $projectRoot '구글기반'
$startPath = Join-Path $googleRoot '프로그램\시작.ps1'
$adapterPath = Join-Path $PSScriptRoot '구글기반_네이버패키지.ps1'
$validatorPath = Join-Path $PSScriptRoot '새글생성결과검증.ps1'
foreach ($path in @($startPath,$adapterPath,$validatorPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "필수 실행 파일을 찾을 수 없습니다: $path" }
}
. $validatorPath

function Write-JsonAtomic([string]$path,[object]$value,[int]$depth=15) {
    $temporary = $path + '.tmp-' + [guid]::NewGuid().ToString('N')
    $backup = $path + '.replace-' + [guid]::NewGuid().ToString('N')
    try {
        $json = $value | ConvertTo-Json -Depth $depth
        [IO.File]::WriteAllText($temporary,$json,(New-Object Text.UTF8Encoding($false)))
        try {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                [IO.File]::Replace($temporary,$path,$backup)
                [IO.File]::Delete($backup)
            } else {
                [IO.File]::Move($temporary,$path)
            }
        } catch {
            # 일부 제한된 Windows 임시 폴더는 같은 폴더 안의 원자적 이름 변경도
            # 차단하거나 OneDrive 동기화가 Replace를 일시 거부합니다.
            # 이때만 완성된 JSON 문자열을 직접 기록합니다.
            [IO.File]::WriteAllText($path,$json,(New-Object Text.UTF8Encoding($false)))
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
}

function Get-InterruptedGenerationState([string]$RuntimeRoot) {
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $RuntimeRoot '작업대기') -Filter '작업상태.json' -Recurse -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending)){
        try{
            $state=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json
            if([string]$state.Status -in @('글 작성 중','실패','일부 실패') -and @($state.SelectedNumbers).Count -gt @($state.Completed).Count){return $file.FullName}
        }catch{}
    }
    return ''
}

function Get-ExistingPackage([string]$root,[string]$sourceArticlePath) {
    $target = [IO.Path]::GetFullPath($sourceArticlePath)
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '실행패키지.json' -Recurse -File -ErrorAction SilentlyContinue)) {
        try {
            $package = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($package.sourceArticlePath -and [IO.Path]::GetFullPath([string]$package.sourceArticlePath) -eq $target) { return $package }
        } catch { }
    }
    return $null
}

$workFull = [IO.Path]::GetFullPath($WorkRoot)
if (-not (Test-Path -LiteralPath $workFull -PathType Container)) { New-Item -ItemType Directory -Path $workFull | Out-Null }
$runtimeRoot = Join-Path $workFull 'google-runtime'
$naverWorkRoot = Join-Path $workFull 'naver-editor-packages'
foreach ($directory in @($runtimeRoot,$naverWorkRoot)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory | Out-Null }
}

$previousRuntime = $env:NAVER_AUTOMATION_RUNTIME_ROOT
$previousNoOpen = $env:NAVER_AUTOMATION_NO_OPEN
$previousCompletionDirectory = $env:NAVER_AUTOMATION_COMPLETION_DIRECTORY
$previousCompletionPackager = $env:NAVER_AUTOMATION_COMPLETION_PACKAGER
$previousNaverWorkRoot = $env:NAVER_AUTOMATION_NAVER_WORK_ROOT
$previousImageDispatcher = $env:NAVER_AUTOMATION_IMAGE_DISPATCHER
$defaultImageDispatcher=Join-Path $PSScriptRoot '이미지ChatGPT실행부.ps1'
$interruptedStatePath=Get-InterruptedGenerationState $runtimeRoot
$previousRuns = @(Get-ChildItem -LiteralPath (Join-Path $runtimeRoot '작업대기') -Filter '작업상태.json' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
try {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $runtimeRoot
    $env:NAVER_AUTOMATION_NO_OPEN = '1'
    $env:NAVER_AUTOMATION_COMPLETION_DIRECTORY = if([string]::IsNullOrWhiteSpace($ProgressDirectory)){''}else{[IO.Path]::GetFullPath($ProgressDirectory)}
    $env:NAVER_AUTOMATION_COMPLETION_PACKAGER = if([string]::IsNullOrWhiteSpace($ProgressDirectory)){''}else{Join-Path $PSScriptRoot '완성글_증분패키지.ps1'}
    $env:NAVER_AUTOMATION_NAVER_WORK_ROOT = $naverWorkRoot
    if([string]::IsNullOrWhiteSpace($env:NAVER_AUTOMATION_IMAGE_DISPATCHER)){
        $env:NAVER_AUTOMATION_IMAGE_DISPATCHER=$defaultImageDispatcher
    }
    $arguments = @{NoWatcher=$true}
    if($interruptedStatePath){$arguments.ResumeStatePath=$interruptedStatePath}else{$arguments.AutoStart=$true}
    if ($CachedOnly -and -not $interruptedStatePath) { $arguments.CachedOnly = $true }
    if (-not [string]::IsNullOrWhiteSpace($SearchResponsePath) -and -not $interruptedStatePath) { $arguments.SearchResponsePath = $SearchResponsePath }
    & $startPath @arguments
}
finally {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $previousRuntime
    $env:NAVER_AUTOMATION_NO_OPEN = $previousNoOpen
    $env:NAVER_AUTOMATION_COMPLETION_DIRECTORY = $previousCompletionDirectory
    $env:NAVER_AUTOMATION_COMPLETION_PACKAGER = $previousCompletionPackager
    $env:NAVER_AUTOMATION_NAVER_WORK_ROOT = $previousNaverWorkRoot
}

$generation = if($interruptedStatePath){Get-NaverGenerationResult -RuntimeRoot $runtimeRoot -StatePath $interruptedStatePath}else{Get-NaverGenerationResult -RuntimeRoot $runtimeRoot -PreviousRuns $previousRuns}

$packages = New-Object System.Collections.ArrayList
$packageFailures = New-Object System.Collections.ArrayList
$packageRecoveryRoot=Join-Path $naverWorkRoot '자동복구상태'
if(-not(Test-Path -LiteralPath $packageRecoveryRoot -PathType Container)){New-Item -ItemType Directory -Path $packageRecoveryRoot -Force|Out-Null}
$sequence = 0
foreach ($articlePath in @($generation.completedPaths)) {
    $sequence++
    $package=$null
    $lastPackageError=''
    $packageStatePath=Join-Path $naverWorkRoot ('자동복구상태\패키지_{0}.json' -f $sequence)
    for($packageAttempt=1;$packageAttempt -le 3;$packageAttempt++){
        try {
            Write-JsonAtomic $packageStatePath ([pscustomobject]@{currentStage=5;passedStages=@(1,2,3,4);stageName='NaverPackage';sourceArticlePath=$articlePath;status='Recovering';errorCode='';automaticRecoveryAttempt=$packageAttempt;lastValidationMessage=$lastPackageError;updatedAt=(Get-Date).ToString('o')}) 8
            $package = Get-ExistingPackage $naverWorkRoot $articlePath
            if ($null -eq $package) {
                $contentId = 'NTE-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + ('-{0:D2}-' -f $sequence) + [guid]::NewGuid().ToString('N').Substring(0,6)
                $package = & $adapterPath -SourceArticlePath $articlePath -WorkRoot $naverWorkRoot -ContentId $contentId | ConvertFrom-Json
                $package | Add-Member -NotePropertyName sourceArticlePath -NotePropertyValue ([IO.Path]::GetFullPath($articlePath)) -Force
                $executionPackagePath = Join-Path ([string]$package.outputRoot) '실행패키지.json'
                Write-JsonAtomic $executionPackagePath $package 15
            }
            Write-JsonAtomic $packageStatePath ([pscustomobject]@{currentStage=9;passedStages=@(1,2,3,4,5,6,7,8,9);stageName='EditorInputPackage';sourceArticlePath=$articlePath;status='Completed';errorCode='';automaticRecoveryAttempt=$packageAttempt;lastValidationMessage='';completedPackagePath=(Join-Path ([string]$package.outputRoot) '실행패키지.json');updatedAt=(Get-Date).ToString('o')}) 8
            break
        } catch {
            $lastPackageError=$_.Exception.Message
            $package=$null
        }
    }
    if($null -ne $package){
        [void]$packages.Add($package)
    }else{
        Write-JsonAtomic $packageStatePath ([pscustomobject]@{currentStage=5;passedStages=@(1,2,3,4);stageName='NaverPackage';sourceArticlePath=$articlePath;status='Unresolved';automaticRecoveryAttempt=3;errorCode='PackageRecoveryExhausted';lastValidationMessage=$lastPackageError;updatedAt=(Get-Date).ToString('o')}) 8
        [void]$packageFailures.Add([pscustomobject]@{
            stage='NaverPackage'; sourceArticlePath=$articlePath; title=(Split-Path $articlePath -Leaf)
            message=$lastPackageError
        })
    }
}

$generationFailures = @($generation.failed | ForEach-Object {
    [pscustomobject]@{
        stage='ArticleGeneration'; number=[int]$_.Candidate.Number; title=[string]$_.Candidate.Title
        message=[string]$_.Message
    }
})
$failures = @($generationFailures) + @($packageFailures.ToArray())
$queue = [pscustomobject]@{
    schemaVersion = 3
    status = if ($packages.Count -gt 0 -and $failures.Count -gt 0) {'PartiallyCompleted'} elseif ($packages.Count -gt 0) {'Completed'} else {'Failed'}
    selectedCount = $packages.Count + $failures.Count
    completedCount = $packages.Count
    failedCount = $failures.Count
    runStatePath = $generation.statePath
    createdAt = (Get-Date).ToString('o')
    packages = @($packages.ToArray())
    failures = @($failures)
}
$queuePath = Join-Path $naverWorkRoot ('작업대기_{0}_{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'),[guid]::NewGuid().ToString('N').Substring(0,6))
Write-JsonAtomic $queuePath $queue 15
$queue | Add-Member -NotePropertyName queueManifest -NotePropertyValue $queuePath
$queueJson=$queue | ConvertTo-Json -Depth 15
if(-not [string]::IsNullOrWhiteSpace($ResultPath)){
    $resultFull=[IO.Path]::GetFullPath($ResultPath)
    $resultParent=Split-Path -Parent $resultFull
    if(-not(Test-Path -LiteralPath $resultParent -PathType Container)){New-Item -ItemType Directory -Path $resultParent -Force|Out-Null}
    [IO.File]::WriteAllText($resultFull,$queueJson,(New-Object Text.UTF8Encoding($false)))
}
$env:NAVER_AUTOMATION_IMAGE_DISPATCHER=$previousImageDispatcher
$queueJson

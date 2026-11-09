#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkRoot,
    [switch]$CachedOnly,
    [string]$SearchResponsePath,
    [switch]$RetryLatest
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

function Get-LatestRetryStatePath([string]$runtimeRoot) {
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $runtimeRoot '작업대기') -Filter '작업상태.json' -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $state = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if (@($state.Failed | Where-Object { $null -ne $_.Candidate }).Count -gt 0) { return $file.FullName }
        } catch { }
    }
    return ''
}

function Get-LatestRetryManifest([string]$packageRoot) {
    $seenRuns = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @(Get-ChildItem -LiteralPath $packageRoot -Filter '작업대기_*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $manifest = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $manifest.runStatePath) { continue }
            $runKey = [IO.Path]::GetFullPath([string]$manifest.runStatePath)
            if (-not $seenRuns.Add($runKey)) { continue }
            if ([int]$manifest.failedCount -gt 0 -and $manifest.runStatePath -and (Test-Path -LiteralPath ([string]$manifest.runStatePath) -PathType Leaf)) { return $manifest }
        } catch { }
    }
    return $null
}

function Assert-PathUnderRoot([string]$path,[string]$root,[string]$message) {
    $full = [IO.Path]::GetFullPath($path)
    $allowed = [IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
    if (-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw $message }
    return $full
}

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
        } catch [System.UnauthorizedAccessException] {
            # 일부 제한된 Windows 임시 폴더는 같은 폴더 안의 원자적 이름 변경도
            # 차단합니다. 이때만 완성된 JSON 문자열을 직접 기록합니다.
            [IO.File]::WriteAllText($path,$json,(New-Object Text.UTF8Encoding($false)))
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
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
$previousRuns = @()
$retryStatePath = ''
$retryGenerationFailures = 0
if ($RetryLatest) {
    $retryManifest = Get-LatestRetryManifest $naverWorkRoot
    if ($null -ne $retryManifest) { $retryStatePath = [string]$retryManifest.runStatePath }
    if (-not $retryStatePath) { $retryStatePath = Get-LatestRetryStatePath $runtimeRoot }
    if (-not $retryStatePath) { throw '재시도할 실패 글이 없습니다. 기사 재검색은 실행하지 않았습니다.' }
    $retryStatePath = Assert-PathUnderRoot $retryStatePath (Join-Path $runtimeRoot '작업대기') '재시도 상태가 현재 네이버 작업 폴더 밖을 가리킵니다.'
    $retryState = Get-Content -LiteralPath $retryStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $retryGenerationFailures = @($retryState.Failed | Where-Object { $null -ne $_.Candidate }).Count
} else {
    $previousRuns = @(Get-ChildItem -LiteralPath (Join-Path $runtimeRoot '작업대기') -Filter '작업상태.json' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
}
try {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $runtimeRoot
    $env:NAVER_AUTOMATION_NO_OPEN = '1'
    if ($RetryLatest -and $retryGenerationFailures -gt 0) {
        & $startPath -NoWatcher -RetryLatest -RetryStatePath $retryStatePath
    } elseif (-not $RetryLatest) {
        $arguments = @{NoWatcher=$true;AutoStart=$true}
        if ($CachedOnly) { $arguments.CachedOnly = $true }
        if (-not [string]::IsNullOrWhiteSpace($SearchResponsePath)) { $arguments.SearchResponsePath = $SearchResponsePath }
        & $startPath @arguments
    }
}
finally {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $previousRuntime
    $env:NAVER_AUTOMATION_NO_OPEN = $previousNoOpen
}

$generation = if ($RetryLatest) {
    Get-NaverGenerationResult -RuntimeRoot $runtimeRoot -StatePath $retryStatePath
} else {
    Get-NaverGenerationResult -RuntimeRoot $runtimeRoot -PreviousRuns $previousRuns
}

$packages = New-Object System.Collections.ArrayList
$packageFailures = New-Object System.Collections.ArrayList
$sequence = 0
foreach ($articlePath in @($generation.completedPaths)) {
    $sequence++
    try {
        $package = Get-ExistingPackage $naverWorkRoot $articlePath
        if ($null -eq $package) {
            $contentId = 'NTE-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + ('-{0:D2}-' -f $sequence) + [guid]::NewGuid().ToString('N').Substring(0,6)
            $package = & $adapterPath -SourceArticlePath $articlePath -WorkRoot $naverWorkRoot -ContentId $contentId | ConvertFrom-Json
            $package | Add-Member -NotePropertyName sourceArticlePath -NotePropertyValue ([IO.Path]::GetFullPath($articlePath)) -Force
            $executionPackagePath = Join-Path ([string]$package.outputRoot) '실행패키지.json'
            Write-JsonAtomic $executionPackagePath $package 15
        }
        [void]$packages.Add($package)
    } catch {
        [void]$packageFailures.Add([pscustomobject]@{
            stage='NaverPackage'; sourceArticlePath=$articlePath; title=(Split-Path $articlePath -Leaf)
            message=$_.Exception.Message
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
    schemaVersion = 2
    status = if ($packages.Count -gt 0 -and $failures.Count -gt 0) {'PartiallyCompleted'} elseif ($packages.Count -gt 0) {'Completed'} else {'Failed'}
    selectedCount = $packages.Count + $failures.Count
    completedCount = $packages.Count
    failedCount = $failures.Count
    canRetryFailed = (($generation.failedCount -gt 0) -or ($packageFailures.Count -gt 0))
    runStatePath = $generation.statePath
    createdAt = (Get-Date).ToString('o')
    packages = @($packages.ToArray())
    failures = @($failures)
}
$queuePath = Join-Path $naverWorkRoot ('작업대기_{0}_{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'),[guid]::NewGuid().ToString('N').Substring(0,6))
Write-JsonAtomic $queuePath $queue 15
$queue | Add-Member -NotePropertyName queueManifest -NotePropertyValue $queuePath
$queue | ConvertTo-Json -Depth 15

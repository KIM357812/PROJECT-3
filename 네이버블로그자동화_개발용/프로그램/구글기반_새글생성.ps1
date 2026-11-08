#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkRoot,
    [switch]$CachedOnly,
    [string]$SearchResponsePath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$googleRoot = Join-Path $projectRoot '구글기반'
$startPath = Join-Path $googleRoot '프로그램\시작.ps1'
$adapterPath = Join-Path $PSScriptRoot '구글기반_네이버패키지.ps1'
foreach ($path in @($startPath, $adapterPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "필수 실행 파일을 찾을 수 없습니다: $path" }
}

$workFull = [IO.Path]::GetFullPath($WorkRoot)
if (-not (Test-Path -LiteralPath $workFull -PathType Container)) { New-Item -ItemType Directory -Path $workFull | Out-Null }
$runtimeRoot = Join-Path $workFull 'google-runtime'
$naverWorkRoot = Join-Path $workFull 'naver-editor-packages'
foreach ($directory in @($runtimeRoot, $naverWorkRoot)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory | Out-Null }
}

$previousRuntime = $env:NAVER_AUTOMATION_RUNTIME_ROOT
$previousNoOpen = $env:NAVER_AUTOMATION_NO_OPEN
$previousRuns = @(Get-ChildItem -LiteralPath (Join-Path $runtimeRoot '작업대기') -Filter '작업상태.json' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
try {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $runtimeRoot
    $env:NAVER_AUTOMATION_NO_OPEN = '1'
    # PowerShell script switches require named splatting; string arrays do not bind them.
    $arguments = @{NoWatcher=$true; AutoStart=$true}
    if ($CachedOnly) { $arguments.CachedOnly = $true }
    if (-not [string]::IsNullOrWhiteSpace($SearchResponsePath)) { $arguments.SearchResponsePath = $SearchResponsePath }
    & $startPath @arguments
}
finally {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $previousRuntime
    $env:NAVER_AUTOMATION_NO_OPEN = $previousNoOpen
}

. (Join-Path $PSScriptRoot '새글생성결과검증.ps1')
$articlePaths = @(Get-NaverGeneratedArticles -RuntimeRoot $runtimeRoot -PreviousRuns $previousRuns)
$packages = New-Object System.Collections.ArrayList
$sequence = 0
foreach ($articlePath in $articlePaths) {
    $sequence++
    $contentId = 'NTE-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + ('-{0:D2}' -f $sequence)
    $package = & $adapterPath -SourceArticlePath $articlePath -WorkRoot $naverWorkRoot -ContentId $contentId | ConvertFrom-Json
    $executionPackagePath = Join-Path ([string]$package.outputRoot) '실행패키지.json'
    $package | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $executionPackagePath -Encoding UTF8
    [void]$packages.Add($package)
}
$queue = [pscustomobject]@{
    schemaVersion = 1
    selectedCount = $packages.Count
    createdAt = (Get-Date).ToString('o')
    packages = @($packages.ToArray())
}
$queuePath = Join-Path $naverWorkRoot ('작업대기_{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$queue | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $queuePath -Encoding UTF8
$queue | Add-Member -NotePropertyName queueManifest -NotePropertyValue $queuePath
$queue | ConvertTo-Json -Depth 15

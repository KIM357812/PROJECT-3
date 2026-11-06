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
$previousAutoSelect = $env:NAVER_AUTOMATION_AUTO_SELECT_TOP
$previousModel = $env:BLOG_AUTOMATION_CODEX_MODEL
try {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $runtimeRoot
    $env:NAVER_AUTOMATION_NO_OPEN = '1'
    $env:NAVER_AUTOMATION_AUTO_SELECT_TOP = '1'
    $env:BLOG_AUTOMATION_CODEX_MODEL = 'gpt-6.1-sol'
    $arguments = @('-NoWatcher', '-AutoStart')
    if ($CachedOnly) { $arguments += '-CachedOnly' }
    if (-not [string]::IsNullOrWhiteSpace($SearchResponsePath)) { $arguments += @('-SearchResponsePath', $SearchResponsePath) }
    & $startPath @arguments
}
finally {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $previousRuntime
    $env:NAVER_AUTOMATION_NO_OPEN = $previousNoOpen
    $env:NAVER_AUTOMATION_AUTO_SELECT_TOP = $previousAutoSelect
    $env:BLOG_AUTOMATION_CODEX_MODEL = $previousModel
}

$latestArticle = Get-ChildItem -LiteralPath (Join-Path $runtimeRoot '작업완료') -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Blogger에_붙여넣을_본문.html') } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $latestArticle) { throw 'Google 기반 자동화가 완성 글 폴더를 만들지 못했습니다.' }

$contentId = 'NTE-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
& $adapterPath -SourceArticlePath $latestArticle.FullName -WorkRoot $naverWorkRoot -ContentId $contentId

#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Capture', 'Verify')]
    [string]$Mode,
    [string]$SourceRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '블로그통합자동화_개발용'),
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'

function Get-NormalizedFullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Get-ReferenceSnapshot([string]$Root) {
    $rootFull = Get-NormalizedFullPath $Root
    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in Get-ChildItem -LiteralPath $rootFull -Recurse -File | Sort-Object FullName) {
        $relative = $file.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
        $items.Add([pscustomobject]@{
            path = $relative
            length = [long]$file.Length
            sha256 = [string](Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        })
    }
    return $items.ToArray()
}

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "구글 자동화 참조 폴더를 찾을 수 없습니다: $SourceRoot"
}
$sourceFull = Get-NormalizedFullPath $SourceRoot
$manifestFull = [IO.Path]::GetFullPath($ManifestPath)
if ($manifestFull.StartsWith($sourceFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    $manifestFull.Equals($sourceFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw '무결성 기록은 구글 자동화 참조 폴더 안에 만들 수 없습니다.'
}

if ($Mode -eq 'Capture') {
    if (Test-Path -LiteralPath $ManifestPath) { throw "기존 무결성 기록을 덮어쓰지 않습니다: $ManifestPath" }
    $parent = Split-Path -Parent $ManifestPath
    if ([string]::IsNullOrWhiteSpace($parent)) { throw 'ManifestPath는 상위 폴더를 포함해야 합니다.' }
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { $null = New-Item -ItemType Directory -Path $parent }
    $snapshot = Get-ReferenceSnapshot $sourceFull
    [pscustomobject]@{
        schemaVersion = 1
        sourceRoot = $sourceFull
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        fileCount = $snapshot.Count
        files = $snapshot
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    Write-Output "Google reference integrity baseline captured: $($snapshot.Count) files."
    return
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "무결성 기록을 찾을 수 없습니다: $ManifestPath" }
$baseline = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not ([string]$baseline.sourceRoot).Equals($sourceFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw '무결성 기록의 구글 참조 폴더가 현재 대상과 다릅니다.'
}
$current = Get-ReferenceSnapshot $sourceFull
$expectedByPath = @{}
foreach ($item in @($baseline.files)) { $expectedByPath[[string]$item.path] = $item }
$currentByPath = @{}
foreach ($item in $current) { $currentByPath[[string]$item.path] = $item }
$changes = New-Object 'System.Collections.Generic.List[string]'
foreach ($path in @($expectedByPath.Keys | Sort-Object)) {
    if (-not $currentByPath.ContainsKey($path)) { $changes.Add("삭제됨: $path"); continue }
    $before = $expectedByPath[$path]
    $after = $currentByPath[$path]
    if ([long]$before.length -ne [long]$after.length -or
        -not ([string]$before.sha256).Equals([string]$after.sha256, [StringComparison]::OrdinalIgnoreCase)) {
        $changes.Add("변경됨: $path")
    }
}
foreach ($path in @($currentByPath.Keys | Sort-Object)) {
    if (-not $expectedByPath.ContainsKey($path)) { $changes.Add("추가됨: $path") }
}
if ($changes.Count -gt 0) { throw ('구글 자동화 원본 무결성 검사 실패: ' + (@($changes) -join '; ')) }
Write-Output "Google reference integrity verified: $($current.Count) files unchanged."

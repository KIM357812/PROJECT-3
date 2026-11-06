#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$destination = [System.IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
$sourcePrefix = $sourceRoot + [System.IO.Path]::DirectorySeparatorChar

if ($destination.Equals($sourceRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
    $destination.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw '백업 폴더는 네이버 개발 소스 폴더 밖에 지정해야 합니다.'
}

if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $destination
}

$forbiddenFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object {
    $_.Name -match '(?i)(token|cookie|session|password|credential)' -or
    $_.Name -eq 'state.json' -or
    $_.Extension -in @('.log', '.tmp')
})
if ($forbiddenFiles.Count -gt 0) {
    throw ('백업에서 제외해야 할 운영·보안 파일이 소스 폴더에 있습니다: ' +
        (($forbiddenFiles | Select-Object -ExpandProperty FullName) -join '; '))
}

$archiveName = '네이버블로그자동화_개발백업_{0}_{1}.zip' -f `
    (Get-Date -Format 'yyyyMMdd_HHmmss'),
    [guid]::NewGuid().ToString('N').Substring(0, 6)
$archivePath = Join-Path $destination $archiveName
if (Test-Path -LiteralPath $archivePath) {
    throw "기존 백업을 덮어쓰지 않습니다: $archivePath"
}

Compress-Archive -LiteralPath $sourceRoot -DestinationPath $archivePath -CompressionLevel Optimal
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw '백업 압축파일 생성 결과를 확인할 수 없습니다.'
}

[pscustomobject]@{
    source = $sourceRoot
    archive = $archivePath
    createdAt = [datetime]::UtcNow.ToString('o')
} | ConvertTo-Json -Depth 3

#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$backupScript = Join-Path $projectRoot '백업내보내기.ps1'
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('백업 테스트 ' + [guid]::NewGuid().ToString('N'))

try {
    $result = & $backupScript -DestinationRoot $testRoot | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $result.archive -PathType Leaf)) {
        throw 'The recovery archive was not created.'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead([string]$result.archive)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
        foreach ($requiredName in @('설정.json', '프로그램/네이버자동화.ps1', 'README.md')) {
            if (@($entryNames | Where-Object { $_.Replace('\','/').EndsWith($requiredName) }).Count -lt 1) {
                throw "The recovery archive is missing: $requiredName"
            }
        }
        if (@($entryNames | Where-Object { $_ -match '(?i)(state\.json|cookie|session|\.log$|\.tmp$)' }).Count -gt 0) {
            throw 'The recovery archive contains operational or sensitive files.'
        }
    }
    finally {
        $archive.Dispose()
    }
    Write-Output 'Backup export tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $tempPrefix = $systemTemp + [System.IO.Path]::DirectorySeparatorChar
        if (-not $resolvedTestRoot.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean a test path outside the system temp directory: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

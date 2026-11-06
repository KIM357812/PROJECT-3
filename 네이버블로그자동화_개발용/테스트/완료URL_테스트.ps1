#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$historyScript = Join-Path $projectRoot '프로그램\완료URL.ps1'
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('완료 URL 테스트 ' + [guid]::NewGuid().ToString('N'))
$registryPath = Join-Path $testRoot 'completed-urls.json'
$testUrl = 'https://techcrunch.com/example-completed-article'

try {
    $added = & $historyScript -Action Add -RegistryPath $registryPath -Url $testUrl `
        -ContentId 'NTE-TEST-001' | ConvertFrom-Json
    if ($added.completedUrls.Count -ne 1 -or -not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
        throw 'A completed URL was not registered.'
    }

    $checked = & $historyScript -Action Check -RegistryPath $registryPath -Url $testUrl |
        ConvertFrom-Json
    if (-not $checked.isCompleted -or $checked.entry.contentId -ne 'NTE-TEST-001') {
        throw 'A completed URL was not found.'
    }

    $duplicateWasBlocked = $false
    try {
        $null = & $historyScript -Action Add -RegistryPath $registryPath -Url $testUrl `
            -ContentId 'NTE-TEST-002'
    }
    catch {
        $duplicateWasBlocked = $true
    }
    if (-not $duplicateWasBlocked) {
        throw 'A duplicate completed URL was accepted.'
    }

    $secondUrl = 'https://www.powermag.com/example-completed-article'
    $null = & $historyScript -Action Add -RegistryPath $registryPath -Url $secondUrl `
        -ContentId 'NTE-TEST-002'
    $backups = @(Get-ChildItem -LiteralPath $testRoot -File -Filter '*.backup.json')
    if ($backups.Count -lt 1) {
        throw 'The completed URL registry was updated without a backup.'
    }

    Write-Output 'Completed URL tests passed.'
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

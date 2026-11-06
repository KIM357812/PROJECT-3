#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot '설치준비.ps1'
$result = & $installerPath -SelfTest
if ($result -notcontains 'Naver automation installer self-test passed.') {
    throw 'The installer self-test did not complete.'
}

$installerText = Get-Content -LiteralPath $installerPath -Raw -Encoding UTF8
foreach ($requiredText in @(
    'WindowsPowerShell\v1.0\powershell.exe',
    'CreateShortcut',
    '기존 바로가기를 덮어쓰지 않습니다',
    '네이버자동화.ps1'
)) {
    if ($installerText.IndexOf($requiredText, [System.StringComparison]::Ordinal) -lt 0) {
        throw "The installer is missing required text: $requiredText"
    }
}

$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('바로가기 테스트 ' + [guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $shortcutPath = Join-Path $testRoot '네이버 자동화.lnk'
    $null = & $installerPath -Install -ShortcutPath $shortcutPath
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        throw 'The installer did not create a shortcut.'
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ([System.IO.Path]::GetFileName($shortcut.TargetPath) -ne 'powershell.exe' -or
        $shortcut.Arguments.IndexOf('네이버자동화.ps1', [System.StringComparison]::Ordinal) -lt 0) {
        throw 'The created shortcut does not point to the Naver automation launcher.'
    }

    $overwriteWasBlocked = $false
    try { $null = & $installerPath -Install -ShortcutPath $shortcutPath }
    catch { $overwriteWasBlocked = $true }
    if (-not $overwriteWasBlocked) { throw 'An existing shortcut was overwritten.' }
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

Write-Output 'Installer preparation tests passed.'

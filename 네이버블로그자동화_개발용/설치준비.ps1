#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName = 'SelfTest')]
param(
    [Parameter(ParameterSetName = 'Install', Mandatory = $true)]
    [switch]$Install,

    [Parameter(ParameterSetName = 'Install', Mandatory = $true)]
    [string]$ShortcutPath,

    [Parameter(ParameterSetName = 'SelfTest')]
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$launcherPath = Join-Path $projectRoot '프로그램\네이버자동화.ps1'
$settingsPath = Join-Path $projectRoot '네이버통합설정.json'

foreach ($requiredPath in @($launcherPath, $settingsPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "설치에 필요한 파일을 찾을 수 없습니다: $requiredPath"
    }
}

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw "Windows PowerShell 5.1 실행 파일을 찾을 수 없습니다: $windowsPowerShell"
}

if ($PSCmdlet.ParameterSetName -eq 'SelfTest') {
    $selfTestResult = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $launcherPath -SelfTest
    if ($selfTestResult -notcontains 'Naver integrated automation self-test passed.') {
        throw '네이버 자동화 화면 자체 검사를 통과하지 못했습니다.'
    }
    Write-Output 'Naver automation installer self-test passed.'
    return
}

$shortcutFullPath = [System.IO.Path]::GetFullPath($ShortcutPath)
if ([System.IO.Path]::GetExtension($shortcutFullPath) -ne '.lnk') {
    throw '바로가기 경로는 .lnk 확장자를 사용해야 합니다.'
}
$shortcutDirectory = Split-Path -Parent $shortcutFullPath
if (-not (Test-Path -LiteralPath $shortcutDirectory -PathType Container)) {
    throw "바로가기를 만들 폴더가 존재하지 않습니다: $shortcutDirectory"
}
if (Test-Path -LiteralPath $shortcutFullPath) {
    throw "기존 바로가기를 덮어쓰지 않습니다: $shortcutFullPath"
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutFullPath)
$shortcut.TargetPath = $windowsPowerShell
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $launcherPath
$shortcut.WorkingDirectory = $projectRoot
$shortcut.Description = '넥스트 테크 에너지 네이버 블로그 반자동화'
$shortcut.IconLocation = "$windowsPowerShell,0"
$shortcut.Save()

if (-not (Test-Path -LiteralPath $shortcutFullPath -PathType Leaf)) {
    throw '바로가기 생성 결과를 확인할 수 없습니다.'
}

Write-Output "바로가기를 만들었습니다: $shortcutFullPath"

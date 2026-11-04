param([switch]$Repair)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$nearbyDesktop = Split-Path (Split-Path $root -Parent) -Parent
$desktop = if ((Split-Path $nearbyDesktop -Leaf) -eq '바탕 화면') { $nearbyDesktop } else { [Environment]::GetFolderPath('DesktopDirectory') }
if (-not $desktop) { throw '바탕화면 경로를 찾지 못했습니다.' }
$entry = Join-Path $root 'launch.ps1'
$shortcutPath = Join-Path $desktop '블로그통합자동화.lnk'
if (-not [IO.File]::Exists($entry)) { throw "실행 파일을 찾지 못했습니다: $entry" }
if ([IO.File]::Exists($shortcutPath) -and -not $Repair) { throw "기존 바로가기를 덮어쓸 수 없습니다: $shortcutPath" }

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not [IO.File]::Exists($powershell)) { throw "PowerShell을 찾지 못했습니다: $powershell" }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershell
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $entry + '"'
$shortcut.WorkingDirectory = $root
$shortcut.Description = '블로그 통합 자동화 실행'
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,70"
$shortcut.Save()
$check = $shell.CreateShortcut($shortcutPath)
if ($check.TargetPath -ne $powershell -or $check.Arguments -ne $shortcut.Arguments) {
    throw '바로가기 실행 대상 검증에 실패했습니다.'
}
Write-Host "바탕화면 바로가기를 만들었습니다: $shortcutPath"

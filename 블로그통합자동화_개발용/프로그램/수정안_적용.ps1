$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$desktop = Split-Path (Split-Path $root -Parent) -Parent
$currentCmd = Join-Path $root '블로그통합자동화_실행.cmd'
$newCmd = Join-Path $root '블로그통합자동화_실행_수정안.cmd'
$currentCreator = Join-Path $root '바탕화면_바로가기_만들기.ps1'
$newCreator = Join-Path $root '바탕화면_바로가기_수정안.ps1'
$shortcutPath = Join-Path $desktop '블로그통합자동화.lnk'

$expected = @{
    $currentCmd = '7D0F42A1BE519166BD5DEAD785453AE6ED65F45D8F5CBDDB6D25898924F1D9EA'
    $currentCreator = '2ED935388B4467C1E1BE4519BA1A93AF4E3F20CBCF714EE39011062632E66439'
    $shortcutPath = '3560501587C9392EA698E8071653BB296DC69E4739BF075EFBFBACC9B35A3908'
}
foreach ($path in $expected.Keys) {
    if (-not [IO.File]::Exists($path)) { throw "교체 대상이 없습니다: $path" }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected[$path]) {
        throw "교체 대상이 확인 이후 변경되어 중단합니다: $path"
    }
}

[IO.File]::Copy($newCmd,$currentCmd,$true)
[IO.File]::Copy($newCreator,$currentCreator,$true)
& $currentCreator -Repair

$bytes = [IO.File]::ReadAllBytes($currentCmd)
if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) { throw '배치 파일에 비 ASCII 문자가 있습니다.' }
$batchText = [Text.Encoding]::ASCII.GetString($bytes)
if ($batchText -match '(?<!\r)\n') { throw '배치 파일에 LF 단독 줄바꿈이 있습니다.' }

function Test-Launch([string]$fileName,[string]$arguments,[string]$workingDirectory) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $fileName
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = $workingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::GetEncoding(949)
    $psi.StandardErrorEncoding = [Text.Encoding]::GetEncoding(949)
    $psi.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($psi)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(15000)) { $process.Kill(); throw '시험 실행 시간이 초과되었습니다.' }
        $result = $stdout.Result + $stderr.Result
        if ($process.ExitCode -ne 0 -or -not $result.Contains('블로그 통합 자동화') -or $result -match '내부 또는 외부 명령|ㄱ\.exe|l\.exe') {
            throw "시험 실행 실패: $result"
        }
        return '메뉴 정상 표시, 명령 오류 없음'
    } finally { $process.Dispose() }
}

$batchResult = Test-Launch 'cmd.exe' ('/d /s /c ""'+$currentCmd+'" -NoWatcher"') $root
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
$shortcutResult = Test-Launch $shortcut.TargetPath ($shortcut.Arguments+' -NoWatcher') $shortcut.WorkingDirectory
Write-Host "배치 실행 시험: $batchResult"
Write-Host "바탕화면 바로가기 시험: $shortcutResult"

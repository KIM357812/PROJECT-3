#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][double]$ViewportX,
    [Parameter(Mandatory=$true)][double]$ViewportY,
    [Parameter(Mandatory=$true)][double]$ViewportWidth,
    [Parameter(Mandatory=$true)][double]$ViewportHeight,
    [Parameter(Mandatory=$true)][double]$DeviceScaleFactor,
    [Parameter(Mandatory=$true)][int]$ExpectedLeft,
    [Parameter(Mandatory=$true)][int]$ExpectedTop,
    [Parameter(Mandatory=$true)][int]$ExpectedWidth,
    [Parameter(Mandatory=$true)][int]$ExpectedHeight,
    [Parameter(Mandatory=$true)][ValidateSet('Text','Html','Click')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$PayloadPath,
    [switch]$SelectAll,
    [ValidateRange(1,3)][int]$SelectAllCount=1,
    [switch]$SkipClick
)
$ErrorActionPreference='Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NteNativeInput {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
  [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr value);
}
'@
$dpiResult=[NteNativeInput]::SetProcessDpiAwarenessContext([IntPtr](-4))
Add-Type -AssemblyName System.Windows.Forms

function Set-NteForegroundWindow([IntPtr]$Handle) {
    $null=[NteNativeInput]::ShowWindowAsync($Handle,9)
    $null=[NteNativeInput]::ShowWindow($Handle,9)
    if([NteNativeInput]::SetForegroundWindow($Handle) -and [NteNativeInput]::GetForegroundWindow() -eq $Handle){ return $true }

    # Windows는 백그라운드 프로세스의 포커스 탈취를 제한합니다. 현재 전경 창의
    # 입력 스레드에 잠시 연결해, 사용자 소유의 단일 네이버 Chrome 창만 활성화합니다.
    $foreground=[NteNativeInput]::GetForegroundWindow()
    $currentThread=[NteNativeInput]::GetCurrentThreadId()
    $foregroundThread=if($foreground -ne [IntPtr]::Zero){[NteNativeInput]::GetWindowThreadProcessId($foreground,[IntPtr]::Zero)}else{0}
    $attached=$false
    try {
        if($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread){
            $attached=[NteNativeInput]::AttachThreadInput($currentThread,$foregroundThread,$true)
        }
        $null=[NteNativeInput]::BringWindowToTop($Handle)
        $null=[NteNativeInput]::SetActiveWindow($Handle)
        $null=[NteNativeInput]::SetFocus($Handle)
        $null=[NteNativeInput]::SetForegroundWindow($Handle)
    }
    finally {
        if($attached){$null=[NteNativeInput]::AttachThreadInput($currentThread,$foregroundThread,$false)}
    }
    Start-Sleep -Milliseconds 120
    return ([NteNativeInput]::GetForegroundWindow() -eq $Handle)
}

function New-CfHtml([string]$Fragment) {
    $prefix='<html><body><!--StartFragment-->'
    $suffix='<!--EndFragment--></body></html>'
    $html=$prefix+$Fragment+$suffix
    $headerTemplate="Version:0.9`r`nStartHTML:{0:D10}`r`nEndHTML:{1:D10}`r`nStartFragment:{2:D10}`r`nEndFragment:{3:D10}`r`n"
    $header=[string]::Format($headerTemplate,0,0,0,0)
    $utf8=[Text.Encoding]::UTF8
    $startHtml=$utf8.GetByteCount($header)
    $startFragment=$startHtml+$utf8.GetByteCount($prefix)
    $endFragment=$startFragment+$utf8.GetByteCount($Fragment)
    $endHtml=$startHtml+$utf8.GetByteCount($html)
    return [string]::Format($headerTemplate,$startHtml,$endHtml,$startFragment,$endFragment)+$html
}

if($Mode -ne 'Click' -and -not(Test-Path -LiteralPath $PayloadPath -PathType Leaf)){throw 'NATIVE_INPUT_PAYLOAD_MISSING'}
$windows=@(Get-Process chrome -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 })
if($windows.Count -lt 1){throw 'NATIVE_INPUT_CHROME_WINDOW_COUNT:0'}

# CDP가 돌려준 대상 탭의 창 경계와 실제 Windows Chrome 창 경계를 대조한다.
# 일반 Chrome 창이 여러 개여도 제목을 추측하지 않고 목표 탭이 속한 창 하나만 고른다.
$matches=@()
foreach($candidate in $windows){
    $candidateRect=New-Object NteNativeInput+RECT
    if(-not[NteNativeInput]::GetWindowRect([IntPtr]$candidate.MainWindowHandle,[ref]$candidateRect)){continue}
    $actualWidth=$candidateRect.Right-$candidateRect.Left
    $actualHeight=$candidateRect.Bottom-$candidateRect.Top
    $rawDistance=[math]::Abs($candidateRect.Left-$ExpectedLeft)+[math]::Abs($candidateRect.Top-$ExpectedTop)+[math]::Abs($actualWidth-$ExpectedWidth)+[math]::Abs($actualHeight-$ExpectedHeight)
    $scaledDistance=[math]::Abs($candidateRect.Left-[math]::Round($ExpectedLeft*$DeviceScaleFactor))+[math]::Abs($candidateRect.Top-[math]::Round($ExpectedTop*$DeviceScaleFactor))+[math]::Abs($actualWidth-[math]::Round($ExpectedWidth*$DeviceScaleFactor))+[math]::Abs($actualHeight-[math]::Round($ExpectedHeight*$DeviceScaleFactor))
    $matches += [pscustomobject]@{Process=$candidate;Rect=$candidateRect;Distance=[math]::Min($rawDistance,$scaledDistance)}
}
$best=@($matches|Sort-Object Distance,{$_.Process.Id})
if($best.Count -lt 1 -or $best[0].Distance -gt 120){
    $summary=($best|Select-Object -First 4|ForEach-Object{"$($_.Process.Id):$($_.Distance)"}) -join ','
    throw "NATIVE_INPUT_TARGET_WINDOW_NOT_FOUND:$summary"
}
if($best.Count -gt 1 -and $best[0].Distance -eq $best[1].Distance){throw "NATIVE_INPUT_TARGET_WINDOW_AMBIGUOUS:$($best[0].Distance)"}
$window=$best[0].Process
$handle=[IntPtr]$window.MainWindowHandle
$rect=New-Object NteNativeInput+RECT
if(-not[NteNativeInput]::GetWindowRect($handle,[ref]$rect)){throw 'NATIVE_INPUT_WINDOW_RECT_FAILED'}
$physicalViewportWidth=[math]::Round($ViewportWidth*$DeviceScaleFactor)
$physicalViewportHeight=[math]::Round($ViewportHeight*$DeviceScaleFactor)
$windowWidth=$rect.Right-$rect.Left
$windowHeight=$rect.Bottom-$rect.Top
$contentLeft=$rect.Left+[math]::Max(0,[math]::Round(($windowWidth-$physicalViewportWidth)/2))
$contentTop=$rect.Top+[math]::Max(0,$windowHeight-$physicalViewportHeight)
$screenX=[int][math]::Round($contentLeft+$ViewportX*$DeviceScaleFactor)
$screenY=[int][math]::Round($contentTop+$ViewportY*$DeviceScaleFactor)

$null=[NteNativeInput]::ShowWindow($handle,9)
if(-not(Set-NteForegroundWindow $handle)){throw 'NATIVE_INPUT_ACTIVATE_FAILED'}
Start-Sleep -Milliseconds 250
if(-not $SkipClick){
    if(-not[NteNativeInput]::SetCursorPos($screenX,$screenY)){throw 'NATIVE_INPUT_CURSOR_FAILED'}
    1..3|ForEach-Object {
        [NteNativeInput]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
        [NteNativeInput]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 55
    }
}
if($SelectAll){
    1..$SelectAllCount|ForEach-Object {[Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 80}
    [Windows.Forms.SendKeys]::SendWait('{BACKSPACE}')
}

if($Mode -ne 'Click'){
    $payload=[IO.File]::ReadAllText($PayloadPath,[Text.Encoding]::UTF8)
    $data=New-Object Windows.Forms.DataObject
    $data.SetData([Windows.Forms.DataFormats]::UnicodeText,$payload)
    if($Mode -eq 'Html'){
        $cfHtml=New-CfHtml $payload
        $bytes=[Text.Encoding]::UTF8.GetBytes($cfHtml+[char]0)
        $stream=New-Object IO.MemoryStream(,$bytes)
        $data.SetData([Windows.Forms.DataFormats]::Html,$stream)
    }
    [Windows.Forms.Clipboard]::SetDataObject($data,$true)
    [Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 250
}
$point=New-Object NteNativeInput+POINT
$null=[NteNativeInput]::GetCursorPos([ref]$point)
[pscustomobject]@{status='InputSent';windowTitle=$window.MainWindowTitle;windowHandle=[long]$handle;windowMatchDistance=$best[0].Distance;foregroundHandle=[long][NteNativeInput]::GetForegroundWindow();dpiAwarenessSet=([long]$dpiResult -ne 0);x=$screenX;y=$screenY;cursorX=$point.X;cursorY=$point.Y;mode=$Mode;windowRect=@{left=$rect.Left;top=$rect.Top;right=$rect.Right;bottom=$rect.Bottom};contentOrigin=@{left=$contentLeft;top=$contentTop};viewport=@{width=$ViewportWidth;height=$ViewportHeight;scale=$DeviceScaleFactor}}|ConvertTo-Json -Compress -Depth 4

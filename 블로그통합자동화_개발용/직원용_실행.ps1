$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root=$PSScriptRoot
$entry=Join-Path $root '프로그램\시작.ps1'
function Start-Task([string[]]$arguments,[switch]$KeepOpen){
    $all=@('-NoProfile','-ExecutionPolicy','Bypass')
    if($KeepOpen){$all += '-NoExit'}
    $all+=@('-File',('"'+$entry+'"'))+$arguments
    Start-Process -FilePath 'powershell.exe' -ArgumentList $all -WorkingDirectory $root
    if($KeepOpen){$form.WindowState=[Windows.Forms.FormWindowState]::Minimized}
}
$form=New-Object Windows.Forms.Form
$form.Text='블로그 통합 자동화';$form.Size=New-Object Drawing.Size(560,455);$form.StartPosition='CenterScreen';$form.Font=New-Object Drawing.Font('맑은 고딕',10);$form.MaximizeBox=$false
$title=New-Object Windows.Forms.Label;$title.Text='블로그 글 작성 도우미';$title.Font=New-Object Drawing.Font('맑은 고딕',16,[Drawing.FontStyle]::Bold);$title.AutoSize=$true;$title.Location=New-Object Drawing.Point(28,22);$form.Controls.Add($title)
$guide=New-Object Windows.Forms.Label;$guide.Text="새 글 작성은 소재를 고른 뒤 글 폴더를 만듭니다.`r`nGemini에서 만든 이미지 4장은 해당 글의 '원본이미지' 폴더에 넣으세요.";$guide.AutoSize=$true;$guide.Location=New-Object Drawing.Point(30,62);$form.Controls.Add($guide)
$specs=@(
 @('새 글 작성 시작',30,120,{Start-Task @('-AutoStart')}),
 @('최근 실패 작업 재시도',285,120,{Start-Task @('-RetryLatest')}),
 @('이미지 준비 상태 확인',30,185,{Start-Task -arguments @('-ImageStatusOnly') -KeepOpen}),
 @('실행 환경 점검',285,185,{Start-Task -arguments @('-PreflightOnly') -KeepOpen}),
 @('완성 글 폴더 열기',30,250,{Start-Process explorer.exe -ArgumentList ('"'+(Join-Path $root '작업완료')+'"')}),
 @('전체 기능 검증',285,250,{Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',('"'+(Join-Path $root '프로그램\검증.ps1')+'"')) -WorkingDirectory $root;$form.WindowState=[Windows.Forms.FormWindowState]::Minimized})
)
foreach($spec in $specs){$button=New-Object Windows.Forms.Button;$button.Text=$spec[0];$button.Size=New-Object Drawing.Size(225,48);$button.Location=New-Object Drawing.Point($spec[1],$spec[2]);$button.Add_Click($spec[3]);$form.Controls.Add($button)}
$note=New-Object Windows.Forms.Label;$note.Text="※ 기존 게시물은 수정하지 않습니다. 실제 Blogger 게시와 API 연동은 이번 개발 범위에 포함되지 않습니다.";$note.AutoSize=$false;$note.Size=New-Object Drawing.Size(490,50);$note.Location=New-Object Drawing.Point(30,325);$note.ForeColor=[Drawing.Color]::DimGray;$form.Controls.Add($note)
[void]$form.ShowDialog()

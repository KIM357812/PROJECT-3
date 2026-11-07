#requires -Version 5.1
[CmdletBinding()]
param([switch]$SelfTest,[switch]$LayoutSelfTest,[string]$SourceArticlePath,[string]$WorkRoot)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot '네이버통합설정.json'
$googleRoot = Join-Path $projectRoot '구글기반'
$newArticlePath = Join-Path $PSScriptRoot '구글기반_새글생성.ps1'
$packagePath = Join-Path $PSScriptRoot '구글기반_네이버패키지.ps1'
$requiredPaths = @(
    $configPath,
    (Join-Path $googleRoot '프로그램\공통.ps1'),
    (Join-Path $googleRoot '프로그램\시작.ps1'),
    (Join-Path $googleRoot '프롬프트\01_소재_URL_프롬프트.md'),
    (Join-Path $googleRoot '프롬프트\02_최종_글쓰기_프롬프트.md'),
    (Join-Path $googleRoot '프롬프트\03_이미지_생성_프롬프트.md'),
    $newArticlePath,$packagePath,
    (Join-Path $PSScriptRoot '이미지작업준비.ps1'),
    (Join-Path $PSScriptRoot '이미지최적화.ps1'),
    (Join-Path $PSScriptRoot '이미지검증.ps1')
)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "필수 파일을 찾을 수 없습니다: $path" }
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$config.Workflow.Source -ne '구글기반') { throw 'Google 자동화 사본이 본체로 지정되지 않았습니다.' }
if (@($config.Workflow.ReuseExistingNaverModules).Count -ne 3) { throw '기존 네이버 개발본은 이미지 기능 세 개만 재사용해야 합니다.' }
if ([string]$config.Workflow.StopPoint -ne 'BeforePublicationSettings' -or [bool]$config.Workflow.OpenPublicationSettings -or [bool]$config.Workflow.AllowPublicPublish -or [bool]$config.Workflow.AllowPrivatePublish) { throw '공개·비공개 선택 전 정지 설정이 올바르지 않습니다.' }

if ($SelfTest) { Write-Output 'Naver integrated automation self-test passed.'; return }
if (-not [string]::IsNullOrWhiteSpace($SourceArticlePath)) {
    if ([string]::IsNullOrWhiteSpace($WorkRoot)) { throw 'WorkRoot가 필요합니다.' }
    & $packagePath -SourceArticlePath $SourceArticlePath -WorkRoot $WorkRoot
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

function Select-Folder([string]$Description) {
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
    return ''
}
function Show-Error([string]$Message) {
    [Windows.Forms.MessageBox]::Show($Message,'네이버 블로그 통합 자동화','OK','Error') | Out-Null
}

$form = New-Object Windows.Forms.Form
$form.Text = '네이버 블로그 통합 자동화'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(820,560)
$form.MinimumSize = New-Object Drawing.Size(840,600)
$form.Font = New-Object Drawing.Font('맑은 고딕',10)

$title = New-Object Windows.Forms.Label
$title.Text = '네이버 블로그 새 글 자동화'
$title.Font = New-Object Drawing.Font('맑은 고딕',16,[Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object Drawing.Point(24,20)
$form.Controls.Add($title)

$notice = New-Object Windows.Forms.Label
$notice.Text = 'Google 자동화 사본을 본체로 사용하고 기존 네이버 개발본에서는 이미지 기능만 사용합니다.'
$notice.AutoSize = $true
$notice.Location = New-Object Drawing.Point(27,60)
$form.Controls.Add($notice)

$stopNotice = New-Object Windows.Forms.Label
$stopNotice.Text = '종료 지점: 제목·본문·이미지·링크·태그 입력 완료 후, 발행 설정을 열기 전'
$stopNotice.AutoSize = $true
$stopNotice.ForeColor = [Drawing.Color]::DarkGreen
$stopNotice.Location = New-Object Drawing.Point(27,86)
$form.Controls.Add($stopNotice)

$workLabel = New-Object Windows.Forms.Label
$workLabel.Text = '작업 폴더'
$workLabel.AutoSize = $true
$workLabel.Location = New-Object Drawing.Point(27,135)
$form.Controls.Add($workLabel)
$workText = New-Object Windows.Forms.TextBox
$workText.Location = New-Object Drawing.Point(130,130)
$workText.Size = New-Object Drawing.Size(545,28)
$workText.Text = if ($WorkRoot) { $WorkRoot } else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) '네이버블로그자동화_작업' }
$form.Controls.Add($workText)
$workBrowse = New-Object Windows.Forms.Button
$workBrowse.Text = '찾아보기'
$workBrowse.Location = New-Object Drawing.Point(690,128)
$workBrowse.Size = New-Object Drawing.Size(100,32)
$form.Controls.Add($workBrowse)

$sourceLabel = New-Object Windows.Forms.Label
$sourceLabel.Text = 'Google 완성 글'
$sourceLabel.AutoSize = $true
$sourceLabel.Location = New-Object Drawing.Point(27,180)
$form.Controls.Add($sourceLabel)
$sourceText = New-Object Windows.Forms.TextBox
$sourceText.Location = New-Object Drawing.Point(130,175)
$sourceText.Size = New-Object Drawing.Size(545,28)
$form.Controls.Add($sourceText)
$sourceBrowse = New-Object Windows.Forms.Button
$sourceBrowse.Text = '찾아보기'
$sourceBrowse.Location = New-Object Drawing.Point(690,173)
$sourceBrowse.Size = New-Object Drawing.Size(100,32)
$form.Controls.Add($sourceBrowse)

$generateButton = New-Object Windows.Forms.Button
$generateButton.Text = '최신 기사로 새 글 만들기'
$generateButton.Location = New-Object Drawing.Point(25,225)
$generateButton.Size = New-Object Drawing.Size(240,42)
$form.Controls.Add($generateButton)
$convertButton = New-Object Windows.Forms.Button
$convertButton.Text = 'Google 완성 글 가져오기'
$convertButton.Location = New-Object Drawing.Point(280,225)
$convertButton.Size = New-Object Drawing.Size(240,42)
$form.Controls.Add($convertButton)

$resultLabel = New-Object Windows.Forms.Label
$resultLabel.Text = '작업 결과'
$resultLabel.AutoSize = $true
$resultLabel.Location = New-Object Drawing.Point(27,292)
$form.Controls.Add($resultLabel)
$result = New-Object Windows.Forms.RichTextBox
$result.Location = New-Object Drawing.Point(25,320)
$result.Size = New-Object Drawing.Size(765,210)
$result.ReadOnly = $true
$result.BackColor = [Drawing.Color]::White
$form.Controls.Add($result)

$workBrowse.Add_Click({ $selected=Select-Folder '저장소 밖의 네이버 작업 폴더를 선택하세요.'; if($selected){$workText.Text=$selected} })
$sourceBrowse.Add_Click({ $selected=Select-Folder 'Google 자동화가 만든 완성 글 폴더를 선택하세요.'; if($selected){$sourceText.Text=$selected} })
$convertButton.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($sourceText.Text)) { throw 'Google 완성 글 폴더를 선택하세요.' }
        $output = & $packagePath -SourceArticlePath $sourceText.Text -WorkRoot $workText.Text | ConvertFrom-Json
        $result.Text = "네이버 편집 패키지를 만들었습니다.`r`n제목: $($output.title)`r`n이미지: $($output.imageCount)장`r`n입력 구간: $($output.segmentCount)개`r`n편집 계획: $($output.editorPlan)`r`n컴퓨터 사용 실행 계약: $($output.executionContract)`r`n실행 상태: 실행 전(완료 아님)`r`n`r`n기존 글과 발행 설정은 건드리지 않습니다."
    } catch { Show-Error $_.Exception.Message }
})
$generateButton.Add_Click({
    try {
        $result.Text='Google 기반 기사 수집·선정·사실검증·글 생성을 실행하고 있습니다.';$form.Refresh()
        $output = & $newArticlePath -WorkRoot $workText.Text | ConvertFrom-Json
        $result.Text = "새 네이버 편집 패키지를 만들었습니다.`r`n제목: $($output.title)`r`n이미지: $($output.imageCount)장`r`n편집 계획: $($output.editorPlan)`r`n컴퓨터 사용 실행 계약: $($output.executionContract)`r`n실행 상태: 실행 전(완료 아님)`r`n`r`n원자 동작 실행과 PC·모바일 검증 후에만 완료로 판정합니다."
    } catch { Show-Error $_.Exception.Message }
})

if ($LayoutSelfTest) {
    $form.PerformLayout()
    foreach($control in @($title,$notice,$stopNotice,$workLabel,$workText,$workBrowse,$sourceLabel,$sourceText,$sourceBrowse,$generateButton,$convertButton,$resultLabel,$result)) {
        if(-not $form.ClientRectangle.Contains($control.Bounds)){throw "화면 요소가 창을 벗어났습니다: $($control.Text)"}
    }
    $form.Dispose();Write-Output 'Naver integrated automation layout self-test passed.';return
}
[void]$form.ShowDialog()

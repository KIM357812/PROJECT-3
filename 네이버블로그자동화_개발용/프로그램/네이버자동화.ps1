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
    $newArticlePath,$packagePath,(Join-Path $PSScriptRoot '통합실행.ps1'),(Join-Path $PSScriptRoot '통합실행결과검증.ps1'),
    (Join-Path $PSScriptRoot '이미지작업준비.ps1'),
    (Join-Path $PSScriptRoot '이미지최적화.ps1'),
    (Join-Path $PSScriptRoot '이미지검증.ps1'),
    (Join-Path $PSScriptRoot '이미지자동복구.ps1'),
    (Join-Path $PSScriptRoot '이미지로컬생성.ps1'),
    (Join-Path $PSScriptRoot '크롬직접연결.ps1'),
    (Join-Path $PSScriptRoot '크롬직접실행.mjs'),
    (Join-Path $PSScriptRoot '크롬네이티브입력.ps1')
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
function Invoke-EditorPipeline($Package) {
    $manifest=Join-Path $Package.outputRoot '실행패키지.json'
    $completionMarker=Join-Path $Package.outputRoot '편집기입력완료.json'
    if (Test-Path -LiteralPath $completionMarker -PathType Leaf) { throw '이 글은 이미 네이버 편집기에 입력·검증되었습니다. 중복 입력하지 않습니다.' }
    $Package | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $manifest -Encoding UTF8
    $result.Text='글 작성 자료 생성 완료. 이미지 생성·최적화·네이버 새 글 입력·실제 화면 검증을 실행합니다.'
    $form.Refresh()
    $verified = & (Join-Path $PSScriptRoot '통합실행.ps1') -PackagePath $manifest | ConvertFrom-Json
    [pscustomobject]@{ completedAt=(Get-Date).ToString('o'); editorUrl=[string]$verified.editorUrl; measurementFile=[string]$verified.measurementFile } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $completionMarker -Encoding UTF8
    $result.Text="새 글 편집창 입력 및 재검증 통과.`r`n주소: $($verified.editorUrl)`r`n발행 설정은 열지 않았습니다.`r`n검증 자료: $($verified.measurementFile)"
}
function Set-GenerationQueue($Generated) {
    $queueList.Items.Clear()
    $packages = @($Generated.packages)
    $failures = @($Generated.failures)
    $order = 0
    foreach ($package in $packages) {
        $order++
        [void]$queueList.Items.Add([pscustomobject]@{
            display = ('완성 {0}/{1} | {2}' -f $order,$packages.Count,[string]$package.title)
            package = $package
            retryRequired = $false
        })
    }
    foreach ($failure in $failures) {
        $number = if ($null -ne $failure.number) { [string]$failure.number } else { '-' }
        $titleText = if ([string]::IsNullOrWhiteSpace([string]$failure.title)) { '제목 확인 불가' } else { [string]$failure.title }
        [void]$queueList.Items.Add([pscustomobject]@{
            display = ('재시도 필요 | {0}번 | {1}' -f $number,$titleText)
            package = $null
            retryRequired = $true
        })
    }
    if ($queueList.Items.Count -gt 0) { $queueList.SelectedIndex = 0 }
    $queueRunButton.Enabled = ($null -ne $queueList.SelectedItem -and $null -ne $queueList.SelectedItem.package)
    if ($packages.Count -gt 0 -and $failures.Count -gt 0) {
        $result.Text = "부분 완료: 완성 글 $($packages.Count)건은 바로 사용할 수 있고, 실패 글 $($failures.Count)건은 별도 재시도할 수 있습니다.`r`n기사 재검색이나 번호 재선택은 필요하지 않습니다."
    } elseif ($packages.Count -gt 0) {
        $result.Text = "완성 글 $($packages.Count)건을 준비했습니다. 원하는 글부터 편집기에 넣으세요.`r`n발행 설정은 열지 않습니다."
    } else {
        $result.Text = "완성 글은 없고 실패 글 $($failures.Count)건이 보존되었습니다. '실패한 글만 다시 작성'을 누르세요.`r`n기사 재검색이나 번호 재선택은 필요하지 않습니다."
    }
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
$notice.Text = '최근 7일 기사를 확인하고 사용자가 선택한 1~3건을 네이버 새 글로 준비합니다.'
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

$generateButton = New-Object Windows.Forms.Button
$generateButton.Text = '최신 기사로 새 글 만들기'
$generateButton.Location = New-Object Drawing.Point(25,180)
$generateButton.Size = New-Object Drawing.Size(240,42)
$form.Controls.Add($generateButton)
$retryButton = New-Object Windows.Forms.Button
$retryButton.Text = '실패한 글만 다시 작성'
$retryButton.Location = New-Object Drawing.Point(290,180)
$retryButton.Size = New-Object Drawing.Size(240,42)
$form.Controls.Add($retryButton)
$resumeButton = New-Object Windows.Forms.Button
$resumeButton.Text = '완성 글 편집기 입력 계속'
$resumeButton.Location = New-Object Drawing.Point(555,180)
$resumeButton.Size = New-Object Drawing.Size(220,42)
$form.Controls.Add($resumeButton)
$resumeButton.Add_Click({
    $dialog=New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter='실행패키지.json|실행패키지.json'
    $dialog.Title='이어서 실행할 네이버 작업 자료 선택'
    try {
        if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}
        $generateButton.Enabled=$false;$retryButton.Enabled=$false;$resumeButton.Enabled=$false;$queueRunButton.Enabled=$false
        $package=Get-Content -LiteralPath $dialog.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        Invoke-EditorPipeline $package
    } catch {$result.Text='미완료: '+$_.Exception.Message;Show-Error $_.Exception.Message}
    finally {$generateButton.Enabled=$true;$retryButton.Enabled=$true;$resumeButton.Enabled=$true;$queueRunButton.Enabled=($null -ne $queueList.SelectedItem -and $null -ne $queueList.SelectedItem.package);$dialog.Dispose()}
})

$queueLabel = New-Object Windows.Forms.Label
$queueLabel.Text = '준비된 글 — 원하는 글을 선택해 편집기에 한 건씩 입력'
$queueLabel.AutoSize = $true
$queueLabel.Location = New-Object Drawing.Point(27,238)
$form.Controls.Add($queueLabel)
$queueList = New-Object Windows.Forms.ListBox
$queueList.Location = New-Object Drawing.Point(25,263)
$queueList.Size = New-Object Drawing.Size(610,88)
$queueList.DisplayMember = 'display'
$form.Controls.Add($queueList)
$queueRunButton = New-Object Windows.Forms.Button
$queueRunButton.Text = '선택한 글 편집기에 넣기'
$queueRunButton.Location = New-Object Drawing.Point(650,263)
$queueRunButton.Size = New-Object Drawing.Size(140,88)
$queueRunButton.Enabled = $false
$form.Controls.Add($queueRunButton)
$queueList.Add_SelectedIndexChanged({ $queueRunButton.Enabled = ($null -ne $queueList.SelectedItem -and $null -ne $queueList.SelectedItem.package) })
$queueRunButton.Add_Click({
    if ($null -eq $queueList.SelectedItem) { return }
    $entry = $queueList.SelectedItem
    try {
        if ($null -eq $entry.package) { throw "이 항목은 아직 완성되지 않았습니다. '실패한 글만 다시 작성'을 먼저 누르세요." }
        $generateButton.Enabled=$false;$retryButton.Enabled=$false;$resumeButton.Enabled=$false;$queueRunButton.Enabled=$false
        Invoke-EditorPipeline $entry.package
        $index = $queueList.SelectedIndex
        $queueList.Items.RemoveAt($index)
        if ($queueList.Items.Count -gt 0) { $queueList.SelectedIndex = [Math]::Min($index,$queueList.Items.Count-1) }
    } catch { $result.Text='미완료: '+$_.Exception.Message;Show-Error $_.Exception.Message }
    finally {$generateButton.Enabled=$true;$retryButton.Enabled=$true;$resumeButton.Enabled=$true;$queueRunButton.Enabled=($null -ne $queueList.SelectedItem -and $null -ne $queueList.SelectedItem.package)}
})

$resultLabel = New-Object Windows.Forms.Label
$resultLabel.Text = '작업 결과'
$resultLabel.AutoSize = $true
$resultLabel.Location = New-Object Drawing.Point(27,410)
$form.Controls.Add($resultLabel)
$result = New-Object Windows.Forms.RichTextBox
$result.Location = New-Object Drawing.Point(25,435)
$result.Size = New-Object Drawing.Size(765,95)
$result.ReadOnly = $true
$result.BackColor = [Drawing.Color]::White
$form.Controls.Add($result)

$connectionButton = New-Object Windows.Forms.Button
$connectionButton.Text = 'Chrome 연결만 검사 (글 변경 없음)'
$connectionButton.Location = New-Object Drawing.Point(25,365)
$connectionButton.Size = New-Object Drawing.Size(370,34)
$form.Controls.Add($connectionButton)
$connectionButton.Add_Click({
    try {
        $connectionButton.Enabled = $false
        $result.Text = '자동화 전용 Chrome을 열고 직접 연결을 검사합니다. ChatGPT 대화는 사용하지 않습니다.'
        $form.Refresh()
        $run=Join-Path $workText.Text ('connection-'+[guid]::NewGuid().ToString())
        $receipt=& (Join-Path $PSScriptRoot '크롬직접연결.ps1') -RunDirectory $run -ConnectionTestOnly|ConvertFrom-Json
        if($receipt.status -ne 'Ready'){throw ([string]$receipt.reason)}
        $result.Text="Chrome 직접 연결 검사 통과`r`n주소: $($receipt.url)`r`nChatGPT 영문 요청 없음`r`n글 작성·수정·발행 없음"
    } catch {
        $connectionButton.Enabled = $true
        $result.Text = '연결 요청 실패: ' + $_.Exception.Message
    } finally {$connectionButton.Enabled=$true}
})

$workBrowse.Add_Click({ $selected=Select-Folder '저장소 밖의 네이버 작업 폴더를 선택하세요.'; if($selected){$workText.Text=$selected} })
$retryButton.Add_Click({
    try {
        $generateButton.Enabled=$false;$retryButton.Enabled=$false;$resumeButton.Enabled=$false;$queueRunButton.Enabled=$false
        $result.Text='보존된 실패 글만 다시 작성합니다. 기사 재검색과 번호 재선택은 실행하지 않습니다.';$form.Refresh()
        $generated = & $newArticlePath -WorkRoot $workText.Text -RetryLatest | ConvertFrom-Json
        Set-GenerationQueue $generated
    } catch { $result.Text='재시도 미완료: '+$_.Exception.Message; Show-Error $_.Exception.Message }
    finally { $generateButton.Enabled=$true;$retryButton.Enabled=$true;$resumeButton.Enabled=$true;$queueRunButton.Enabled=($null -ne $queueList.SelectedItem -and $null -ne $queueList.SelectedItem.package) }
})
$generateButton.Add_Click({
    try {
        $generateButton.Enabled=$false;$retryButton.Enabled=$false;$resumeButton.Enabled=$false;$queueRunButton.Enabled=$false
        $result.Text='최근 7일 기사 수집 후 PowerShell에서 선택한 1~3건을 작성합니다.';$form.Refresh()
        $generated = & $newArticlePath -WorkRoot $workText.Text | ConvertFrom-Json
        if (@($generated.packages).Count -gt 3) { throw '이번 작업에서 준비된 글 수가 최대 3건을 초과했습니다.' }
        Set-GenerationQueue $generated
    } catch { $result.Text='미완료: '+$_.Exception.Message; Show-Error $_.Exception.Message }
    finally { $generateButton.Enabled=$true;$retryButton.Enabled=$true;$resumeButton.Enabled=$true;$queueRunButton.Enabled=($null -ne $queueList.SelectedItem -and $null -ne $queueList.SelectedItem.package) }
})

if ($LayoutSelfTest) {
    $form.PerformLayout()
    foreach($control in @($title,$notice,$stopNotice,$workLabel,$workText,$workBrowse,$generateButton,$retryButton,$resumeButton,$queueLabel,$queueList,$queueRunButton,$connectionButton,$resultLabel,$result)) {
        if(-not $form.ClientRectangle.Contains($control.Bounds)){throw "화면 요소가 창을 벗어났습니다: $($control.Text)"}
    }
    $form.Dispose();Write-Output 'Naver integrated automation layout self-test passed.';return
}
[void]$form.ShowDialog()

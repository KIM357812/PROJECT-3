#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$LayoutSelfTest
)

$ErrorActionPreference = 'Stop'
$programRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $programRoot
$settingsPath = Join-Path $projectRoot '설정.json'
$workDataValidatorPath = Join-Path $programRoot '작업자료검증.ps1'
$draftValidatorPath = Join-Path $programRoot '초안검증.ps1'
$workStatePath = Join-Path $programRoot '작업상태.ps1'
$factPreparePath = Join-Path $programRoot '사실검증준비.ps1'
$draftPreparePath = Join-Path $programRoot '초안준비.ps1'
$editorPlanPath = Join-Path $programRoot '편집기계획.ps1'
$editorRebuildPlanPath = Join-Path $programRoot '편집기재구성계획.ps1'
$readerAnalyticsPath = Join-Path $programRoot '독자반응분석.ps1'
$mobilePreviewPath = Join-Path $programRoot '모바일미리보기.ps1'
$benchmarkSelectorPath = Join-Path $programRoot '벤치마크선정.ps1'
$introPreparePath = Join-Path $programRoot '프롤로그초안준비.ps1'
$introSourcePath = Join-Path $projectRoot '콘텐츠기준\네이버_소개_및_정책_초안.md'
$editorResultValidatorPath = Join-Path $programRoot '편집기결과검증.ps1'
$editorExecutionValidatorPath = Join-Path $programRoot '편집기재구성실행검증.ps1'
$articleSelectorPath = Join-Path $programRoot '기사선택.ps1'

foreach ($requiredPath in @(
    $settingsPath, $workDataValidatorPath, $draftValidatorPath, $workStatePath,
    $factPreparePath, $draftPreparePath, $editorPlanPath, $editorRebuildPlanPath, $readerAnalyticsPath,
    $mobilePreviewPath, $benchmarkSelectorPath, $introPreparePath, $introSourcePath,
    $editorResultValidatorPath, $editorExecutionValidatorPath, $articleSelectorPath
)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "필수 파일을 찾을 수 없습니다: $requiredPath"
    }
}

if ($SelfTest) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($settings.Collection.Sources).Count -ne 8) {
        throw '설정 파일의 전문 매체 수가 8개가 아닙니다.'
    }
    if ([int]$settings.ReaderAnalytics.MinimumPosts -lt 5 -or
        [bool]$settings.ReaderAnalytics.RankingGuarantee) {
        throw '독자 반응 분석의 최소 표본 또는 검색 노출 비보장 설정이 올바르지 않습니다.'
    }
    $requiredFocusTopics = @('AI', '데이터센터', '전력', '에너지', '온실가스')
    foreach ($topic in $requiredFocusTopics) {
        if (@($settings.EditorialFocus.CoreTopics) -notcontains $topic) {
            throw "핵심 편집 주제가 누락되었습니다: $topic"
        }
    }
    $requiredConvergenceDomains = @('AI·IT·소프트웨어', '반도체·컴퓨팅', 'NT·나노·첨단소재', 'ET·환경·에너지', 'ST·우주', '로봇·제조', '모빌리티', '바이오')
    foreach ($domain in $requiredConvergenceDomains) {
        if (@($settings.EditorialFocus.AIConvergenceDomains) -notcontains $domain) {
            throw "AI 융합기술 범위가 누락되었습니다: $domain"
        }
    }
    if (-not [bool]$settings.EditorialFocus.TreatAsConnectedSystem -or
        -not [bool]$settings.EditorialFocus.PrioritizeGlobalProfessionalMedia -or
        -not [bool]$settings.EditorialFocus.RequireDomesticRelevance -or
        -not [bool]$settings.EditorialFocus.RequireFactAnalysisSeparation -or
        -not [bool]$settings.EditorialFocus.ForbidForcedConnections -or
        -not [bool]$settings.EditorialFocus.RequireClearAIConnection -or
        -not [bool]$settings.EditorialFocus.RequireIndustryImpact) {
        throw '글로벌 최신 이슈의 연결 해설 원칙 설정이 올바르지 않습니다.'
    }
    Write-Output 'Naver automation UI self-test passed.'
    return
}

. $workDataValidatorPath -Mode CandidateCollection -Path 'unused'
. $draftValidatorPath -Path 'unused'
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-ErrorMessage {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        '넥스트 테크 에너지',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Select-JsonFile {
    param([string]$Title)
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = 'JSON 파일 (*.json)|*.json|모든 파일 (*.*)|*.*'
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Select-NewJsonFile {
    param([string]$Title)
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = $Title
    $dialog.Filter = 'JSON 파일 (*.json)|*.json'
    $dialog.OverwritePrompt = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if (Test-Path -LiteralPath $dialog.FileName) {
            throw '기존 파일을 덮어쓰지 않습니다. 새 파일 이름을 선택하세요.'
        }
        return $dialog.FileName
    }
    return $null
}

function Format-ValidationResult {
    param([psobject]$Result)
    if ($Result.IsValid) {
        return '검증을 통과했습니다.'
    }
    return "검증 오류:`r`n- " + (@($Result.Issues) -join "`r`n- ")
}

function Set-StageButtons {
    param([psobject]$State)
    $candidateButton.Enabled = ($State.currentStage -eq 'CandidateCollection' -or
        $State.nextStage -eq 'CandidateCollection')
    $factCheckButton.Enabled = ($State.currentStage -eq 'FactCheck' -or
        $State.nextStage -eq 'FactCheck')
    $draftButton.Enabled = ($State.currentStage -eq 'NaverDraft' -or
        $State.nextStage -eq 'NaverDraft')
    $factPrepareButton.Enabled = ($State.currentStage -eq 'CandidateCollection' -or
        $State.nextStage -eq 'FactCheck')
    $draftPrepareButton.Enabled = ($State.currentStage -eq 'FactCheck' -or
        $State.nextStage -eq 'NaverDraft')
}

$form = New-Object System.Windows.Forms.Form
$form.Text = '넥스트 테크 에너지 - 네이버 블로그 반자동화'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(820, 680)
$form.MinimumSize = New-Object System.Drawing.Size(840, 720)
$form.Font = New-Object System.Drawing.Font('맑은 고딕', 10)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = '네이버 블로그 새 글 작업'
$titleLabel.Font = New-Object System.Drawing.Font('맑은 고딕', 15, [System.Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(24, 20)
$form.Controls.Add($titleLabel)

$noticeLabel = New-Object System.Windows.Forms.Label
$noticeLabel.Text = '공개 게시 기능은 포함하지 않습니다. 작업자료는 저장소 밖의 선택한 폴더에 보관합니다.'
$noticeLabel.AutoSize = $true
$noticeLabel.ForeColor = [System.Drawing.Color]::DarkSlateGray
$noticeLabel.Location = New-Object System.Drawing.Point(27, 57)
$form.Controls.Add($noticeLabel)

$workRootLabel = New-Object System.Windows.Forms.Label
$workRootLabel.Text = '작업 폴더'
$workRootLabel.AutoSize = $true
$workRootLabel.Location = New-Object System.Drawing.Point(27, 99)
$form.Controls.Add($workRootLabel)

$workRootText = New-Object System.Windows.Forms.TextBox
$workRootText.Location = New-Object System.Drawing.Point(120, 95)
$workRootText.Size = New-Object System.Drawing.Size(570, 28)
$form.Controls.Add($workRootText)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = '찾아보기'
$browseButton.Location = New-Object System.Drawing.Point(700, 93)
$browseButton.Size = New-Object System.Drawing.Size(90, 32)
$form.Controls.Add($browseButton)

$contentIdLabel = New-Object System.Windows.Forms.Label
$contentIdLabel.Text = '콘텐츠 번호'
$contentIdLabel.AutoSize = $true
$contentIdLabel.Location = New-Object System.Drawing.Point(27, 144)
$form.Controls.Add($contentIdLabel)

$contentIdText = New-Object System.Windows.Forms.TextBox
$contentIdText.Location = New-Object System.Drawing.Point(120, 140)
$contentIdText.Size = New-Object System.Drawing.Size(260, 28)
$contentIdText.Text = 'NTE-' + (Get-Date -Format 'yyyyMMdd') + '-001'
$form.Controls.Add($contentIdText)

$newButton = New-Object System.Windows.Forms.Button
$newButton.Text = '새 작업 만들기'
$newButton.Location = New-Object System.Drawing.Point(400, 138)
$newButton.Size = New-Object System.Drawing.Size(130, 32)
$form.Controls.Add($newButton)

$statusButton = New-Object System.Windows.Forms.Button
$statusButton.Text = '진행 상태 확인'
$statusButton.Location = New-Object System.Drawing.Point(540, 138)
$statusButton.Size = New-Object System.Drawing.Size(130, 32)
$form.Controls.Add($statusButton)

$introButton = New-Object System.Windows.Forms.Button
$introButton.Text = '프롤로그 준비'
$introButton.Location = New-Object System.Drawing.Point(680, 138)
$introButton.Size = New-Object System.Drawing.Size(110, 32)
$form.Controls.Add($introButton)

$stepGroup = New-Object System.Windows.Forms.GroupBox
$stepGroup.Text = '단계별 자료 검사 및 보관'
$stepGroup.Location = New-Object System.Drawing.Point(25, 190)
$stepGroup.Size = New-Object System.Drawing.Size(765, 145)
$form.Controls.Add($stepGroup)

$candidateButton = New-Object System.Windows.Forms.Button
$candidateButton.Text = '1. 소재 수집 검사'
$candidateButton.Location = New-Object System.Drawing.Point(12, 38)
$candidateButton.Size = New-Object System.Drawing.Size(140, 38)
$stepGroup.Controls.Add($candidateButton)

$factPrepareButton = New-Object System.Windows.Forms.Button
$factPrepareButton.Text = '2. 기사 선택 준비'
$factPrepareButton.Location = New-Object System.Drawing.Point(160, 38)
$factPrepareButton.Size = New-Object System.Drawing.Size(140, 38)
$stepGroup.Controls.Add($factPrepareButton)

$factCheckButton = New-Object System.Windows.Forms.Button
$factCheckButton.Text = '3. 사실검증 검사'
$factCheckButton.Location = New-Object System.Drawing.Point(308, 38)
$factCheckButton.Size = New-Object System.Drawing.Size(140, 38)
$stepGroup.Controls.Add($factCheckButton)

$draftPrepareButton = New-Object System.Windows.Forms.Button
$draftPrepareButton.Text = '4. 초안 작업 준비'
$draftPrepareButton.Location = New-Object System.Drawing.Point(456, 38)
$draftPrepareButton.Size = New-Object System.Drawing.Size(140, 38)
$stepGroup.Controls.Add($draftPrepareButton)

$draftButton = New-Object System.Windows.Forms.Button
$draftButton.Text = '5. 네이버 초안 검사'
$draftButton.Location = New-Object System.Drawing.Point(604, 38)
$draftButton.Size = New-Object System.Drawing.Size(148, 38)
$stepGroup.Controls.Add($draftButton)
$factCheckButton.Enabled = $false
$factPrepareButton.Enabled = $false
$draftPrepareButton.Enabled = $false
$draftButton.Enabled = $false

$editorExecutionButton = New-Object System.Windows.Forms.Button
$editorExecutionButton.Text = '6. 재구성 실행 검사'
$editorExecutionButton.Location = New-Object System.Drawing.Point(12, 92)
$editorExecutionButton.Size = New-Object System.Drawing.Size(180, 32)
$stepGroup.Controls.Add($editorExecutionButton)

$editorVerifyButton = New-Object System.Windows.Forms.Button
$editorVerifyButton.Text = '7. 편집기 결과 검사'
$editorVerifyButton.Location = New-Object System.Drawing.Point(200, 92)
$editorVerifyButton.Size = New-Object System.Drawing.Size(180, 32)
$stepGroup.Controls.Add($editorVerifyButton)

$editorVerifyNotice = New-Object System.Windows.Forms.Label
$editorVerifyNotice.Text = '동작별 검사 통과 후에만 비공개 저장 결과를 확인합니다.'
$editorVerifyNotice.AutoSize = $true
$editorVerifyNotice.Location = New-Object System.Drawing.Point(395, 99)
$stepGroup.Controls.Add($editorVerifyNotice)

$readerGroup = New-Object System.Windows.Forms.GroupBox
$readerGroup.Text = '일반 구독자 근거와 운영 후 보완'
$readerGroup.Location = New-Object System.Drawing.Point(25, 345)
$readerGroup.Size = New-Object System.Drawing.Size(765, 68)
$form.Controls.Add($readerGroup)

$readerButton = New-Object System.Windows.Forms.Button
$readerButton.Text = '독자 반응 분석'
$readerButton.Location = New-Object System.Drawing.Point(12, 24)
$readerButton.Size = New-Object System.Drawing.Size(150, 32)
$readerGroup.Controls.Add($readerButton)

$benchmarkButton = New-Object System.Windows.Forms.Button
$benchmarkButton.Text = '유사 블로그 선정'
$benchmarkButton.Location = New-Object System.Drawing.Point(170, 24)
$benchmarkButton.Size = New-Object System.Drawing.Size(160, 32)
$readerGroup.Controls.Add($benchmarkButton)

$readerNotice = New-Object System.Windows.Forms.Label
$readerNotice.Text = '유사 블로그 우선 · 반응 분석은 최소 14일·게시물 5개·조회 100회'
$readerNotice.AutoSize = $true
$readerNotice.Location = New-Object System.Drawing.Point(345, 31)
$readerGroup.Controls.Add($readerNotice)

$resultLabel = New-Object System.Windows.Forms.Label
$resultLabel.Text = '검사 결과'
$resultLabel.AutoSize = $true
$resultLabel.Location = New-Object System.Drawing.Point(27, 430)
$form.Controls.Add($resultLabel)

$resultText = New-Object System.Windows.Forms.RichTextBox
$resultText.Location = New-Object System.Drawing.Point(25, 458)
$resultText.Size = New-Object System.Drawing.Size(765, 195)
$resultText.ReadOnly = $true
$resultText.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($resultText)

$browseButton.Add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = '저장소 밖의 네이버 블로그 작업 폴더를 선택하세요.'
    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $workRootText.Text = $folderDialog.SelectedPath
    }
})

$newButton.Add_Click({
    try {
        $state = & $workStatePath -Action New -WorkRoot $workRootText.Text -ContentId $contentIdText.Text |
            ConvertFrom-Json
        Set-StageButtons $state
        $resultText.Text = "새 작업을 만들었습니다.`r`n콘텐츠 번호: $($state.contentId)`r`n상태: $($state.status)"
    }
    catch {
        Show-ErrorMessage $_.Exception.Message
    }
})

$statusButton.Add_Click({
    try {
        $state = & $workStatePath -Action Status -WorkRoot $workRootText.Text -ContentId $contentIdText.Text |
            ConvertFrom-Json
        Set-StageButtons $state
        $resultText.Text = @"
콘텐츠 번호: $($state.contentId)
현재 단계: $($state.currentStage)
다음 단계: $($state.nextStage)
상태: $($state.status)
재시도 횟수: $($state.retryCount)
최근 결과: $($state.latestArtifact)
마지막 오류: $($state.lastError)
"@
    }
    catch {
        Show-ErrorMessage $_.Exception.Message
    }
})

$introButton.Add_Click({
    $stateCreated = $false
    try {
        $state = & $workStatePath -Action New -WorkRoot $workRootText.Text `
            -ContentId $contentIdText.Text -WorkType Introduction | ConvertFrom-Json
        $stateCreated = $true
        $itemRoot = Join-Path $workRootText.Text $contentIdText.Text
        $outputRoot = Join-Path $itemRoot 'output'
        $introDraftPath = Join-Path $outputRoot 'introduction-draft.json'
        $introPreviewPath = Join-Path $outputRoot 'introduction-mobile-preview.html'
        $introPlanPath = Join-Path $outputRoot 'introduction-editor-plan.json'

        $prepared = & $introPreparePath -SourcePath $introSourcePath `
            -OutputPath $introDraftPath -ContentId $contentIdText.Text | ConvertFrom-Json
        $preview = & $mobilePreviewPath -DraftPath $introDraftPath `
            -OutputPath $introPreviewPath | ConvertFrom-Json
        $plan = & $editorPlanPath -DraftPath $introDraftPath -OutputPath $introPlanPath |
            ConvertFrom-Json
        $state = & $workStatePath -Action SaveStage -WorkRoot $workRootText.Text `
            -ContentId $contentIdText.Text -Stage NaverDraft -SourcePath $introDraftPath |
            ConvertFrom-Json
        Set-StageButtons $state
        $resultText.Text = @"
프롤로그 초안을 준비했습니다.
본문 길이: $($prepared.bodyLength)자
태그: $($prepared.tagCount)개
공개 범위 계획: $($plan.visibility)
정지 지점: $($plan.stopPoint)
390px 로컬 미리보기: $($preview.output)
편집기 계획: $($plan.output)
네이버에는 아직 입력하거나 저장하지 않았습니다.
"@
    }
    catch {
        $originalMessage = $_.Exception.Message
        if ($stateCreated) {
            try {
                $null = & $workStatePath -Action Fail -WorkRoot $workRootText.Text `
                    -ContentId $contentIdText.Text -Message $originalMessage
            }
            catch { }
        }
        Show-ErrorMessage $originalMessage
    }
})

$factPrepareButton.Add_Click({
    try {
        $collectionFile = Select-JsonFile '확정된 소재 수집 JSON 선택'
        if ([string]::IsNullOrWhiteSpace($collectionFile)) { return }
        $choiceJson = & $articleSelectorPath -Mode Show -CollectionPath $collectionFile `
            -ConfigPath $settingsPath
        if ([string]::IsNullOrWhiteSpace([string]$choiceJson)) { return }
        $choice = $choiceJson | ConvertFrom-Json
        $selectedUrl = [string]$choice.url
        $outputFile = Select-NewJsonFile '새 사실검증 JSON 저장 위치'
        if ([string]::IsNullOrWhiteSpace($outputFile)) { return }
        $prepared = & $factPreparePath -CollectionPath $collectionFile -ArticleUrl $selectedUrl `
            -ContentId $contentIdText.Text -OutputPath $outputFile | ConvertFrom-Json
        $resultText.Text = "사실검증 작업을 준비했습니다.`r`n선택 매체: $($choice.siteName)`r`n추천 순위: $($choice.recommendationRank)`r`n원문: $($prepared.sourceTitle)`r`n파일: $($prepared.output)"
    }
    catch { Show-ErrorMessage $_.Exception.Message }
})

$candidateButton.Add_Click({
    try {
        $selectedPath = Select-JsonFile '소재 수집 JSON 파일 선택'
        if ([string]::IsNullOrWhiteSpace($selectedPath)) { return }
        $data = Get-Content -LiteralPath $selectedPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $completedUrls = @()
        $completedUrlRegistry = Join-Path $workRootText.Text 'completed-urls.json'
        if (Test-Path -LiteralPath $completedUrlRegistry -PathType Leaf) {
            $history = Get-Content -LiteralPath $completedUrlRegistry -Raw -Encoding UTF8 |
                ConvertFrom-Json
            $completedUrls = @($history.completedUrls | ForEach-Object { [string]$_.url })
        }
        $validation = Test-CandidateCollection -Collection $data -Rules $settings.Collection `
            -EditorialFocus $settings.EditorialFocus `
            -CompletedUrls $completedUrls
        $resultText.Text = Format-ValidationResult $validation
        if ($validation.IsValid) {
            $state = & $workStatePath -Action SaveStage -WorkRoot $workRootText.Text `
                -ContentId $contentIdText.Text -Stage CandidateCollection -SourcePath $selectedPath |
                ConvertFrom-Json
            Set-StageButtons $state
            $resultText.AppendText("`r`n보관 위치: $($state.latestArtifact)")
        }
    }
    catch {
        Show-ErrorMessage $_.Exception.Message
    }
})

$draftPrepareButton.Add_Click({
    try {
        $factFile = Select-JsonFile '검증을 통과한 사실검증 JSON 선택'
        if ([string]::IsNullOrWhiteSpace($factFile)) { return }
        $readerAnalysisFile = $null
        $useReaderAnalysis = [System.Windows.Forms.MessageBox]::Show(
            '운영 후 생성한 독자 반응 분석 JSON을 이번 초안에 연결하시겠습니까?',
            '독자 반응 연결',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($useReaderAnalysis -eq [System.Windows.Forms.DialogResult]::Yes) {
            $readerAnalysisFile = Select-JsonFile '독자 반응 분석 JSON 선택'
            if ([string]::IsNullOrWhiteSpace($readerAnalysisFile)) { return }
        }
        $outputFile = Select-NewJsonFile '새 네이버 초안 JSON 저장 위치'
        if ([string]::IsNullOrWhiteSpace($outputFile)) { return }
        $prepareArguments = @{
            FactCheckPath = $factFile
            OutputPath = $outputFile
        }
        if ($readerAnalysisFile) { $prepareArguments.ReaderAnalysisPath = $readerAnalysisFile }
        $prepared = & $draftPreparePath @prepareArguments |
            ConvertFrom-Json
        $resultText.Text = "네이버 초안 작업을 준비했습니다.`r`n콘텐츠 번호: $($prepared.contentId)`r`n독자 반응 연결: $($prepared.readerEvidenceStatus)`r`n파일: $($prepared.output)"
    }
    catch { Show-ErrorMessage $_.Exception.Message }
})

$factCheckButton.Add_Click({
    try {
        $selectedPath = Select-JsonFile '사실검증 JSON 파일 선택'
        if ([string]::IsNullOrWhiteSpace($selectedPath)) { return }
        $data = Get-Content -LiteralPath $selectedPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $validation = Test-FactCheckRecord -Record $data
        $resultText.Text = Format-ValidationResult $validation
        if ($validation.IsValid) {
            $state = & $workStatePath -Action SaveStage -WorkRoot $workRootText.Text `
                -ContentId $contentIdText.Text -Stage FactCheck -SourcePath $selectedPath |
                ConvertFrom-Json
            Set-StageButtons $state
            $resultText.AppendText("`r`n보관 위치: $($state.latestArtifact)")
        }
    }
    catch {
        Show-ErrorMessage $_.Exception.Message
    }
})

$draftButton.Add_Click({
    try {
        $selectedPath = Select-JsonFile '네이버 초안 JSON 파일 선택'
        if ([string]::IsNullOrWhiteSpace($selectedPath)) { return }
        $data = Get-Content -LiteralPath $selectedPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $validation = Test-NaverDraft -Draft $data -Rules $settings.NaverDraft
        $resultText.Text = Format-ValidationResult $validation
        if ($validation.IsValid) {
            $state = & $workStatePath -Action SaveStage -WorkRoot $workRootText.Text `
                -ContentId $contentIdText.Text -Stage NaverDraft -SourcePath $selectedPath |
                ConvertFrom-Json
            Set-StageButtons $state
            $resultText.AppendText("`r`n보관 위치: $($state.latestArtifact)")
            $planFileName = [System.IO.Path]::GetFileNameWithoutExtension($selectedPath) + '.editor-plan.json'
            $planOutputPath = Join-Path (Split-Path -Parent $selectedPath) $planFileName
            if (Test-Path -LiteralPath $planOutputPath) {
                $resultText.AppendText("`r`n기존 편집기 계획을 덮어쓰지 않았습니다: $planOutputPath")
            }
            else {
                $editorPlan = & $editorPlanPath -DraftPath $selectedPath -OutputPath $planOutputPath |
                    ConvertFrom-Json
                $resultText.AppendText("`r`n비공개 편집기 계획: $($editorPlan.output)")
            }
            $rebuildFileName = [System.IO.Path]::GetFileNameWithoutExtension($selectedPath) + '.editor-rebuild-plan.json'
            $rebuildOutputPath = Join-Path (Split-Path -Parent $selectedPath) $rebuildFileName
            if (Test-Path -LiteralPath $rebuildOutputPath) {
                $resultText.AppendText("`r`n기존 편집기 재구성 계획을 덮어쓰지 않았습니다: $rebuildOutputPath")
            }
            else {
                $rebuildPlan = & $editorRebuildPlanPath -DraftPath $selectedPath `
                    -OutputPath $rebuildOutputPath -ConfigPath $settingsPath | ConvertFrom-Json
                $resultText.AppendText("`r`n전체 편집기 재구성 계획: $rebuildOutputPath")
                $resultText.AppendText("`r`n재구성 동작 수: $(@($rebuildPlan.actions).Count)")
            }
            $mobileFileName = [System.IO.Path]::GetFileNameWithoutExtension($selectedPath) + '.mobile-preview.html'
            $mobileOutputPath = Join-Path (Split-Path -Parent $selectedPath) $mobileFileName
            if (Test-Path -LiteralPath $mobileOutputPath) {
                $resultText.AppendText("`r`n기존 모바일 미리보기를 덮어쓰지 않았습니다: $mobileOutputPath")
            }
            else {
                $mobilePreview = & $mobilePreviewPath -DraftPath $selectedPath `
                    -OutputPath $mobileOutputPath -ConfigPath $settingsPath | ConvertFrom-Json
                $resultText.AppendText("`r`n390px 로컬 모바일 미리보기: $($mobilePreview.output)")
            }
        }
    }
    catch {
        Show-ErrorMessage $_.Exception.Message
    }
})

$readerButton.Add_Click({
    try {
        $metricsPath = Select-JsonFile '네이버 독자 반응 집계 JSON 선택'
        if ([string]::IsNullOrWhiteSpace($metricsPath)) { return }
        $outputPath = Select-NewJsonFile '새 독자 반응 분석 JSON 저장 위치'
        if ([string]::IsNullOrWhiteSpace($outputPath)) { return }
        $analysis = & $readerAnalyticsPath -Mode Analyze -Path $metricsPath `
            -OutputPath $outputPath -ConfigPath $settingsPath
        $reasonText = if (@($analysis.evidence.insufficientReasons).Count -gt 0) {
            @($analysis.evidence.insufficientReasons) -join ', '
        } else { '충분한 집계 표본' }
        $resultText.Text = @"
독자 반응 분석을 마쳤습니다.
근거 상태: $($analysis.evidenceStatus) ($reasonText)
권장 본문 범위: $($analysis.recommendedBodyLength.minimum)~$($analysis.recommendedBodyLength.maximum)자
모바일 우선 신호: $($analysis.mobileFirst)
결과 파일: $outputPath

$($analysis.notice)
"@
    }
    catch { Show-ErrorMessage $_.Exception.Message }
})

$benchmarkButton.Add_Click({
    try {
        $inputPath = Select-JsonFile '유사 네이버 블로그 공개 지표 JSON 선택'
        if ([string]::IsNullOrWhiteSpace($inputPath)) { return }
        $outputPath = Select-NewJsonFile '새 벤치마크 검토 JSON 저장 위치'
        if ([string]::IsNullOrWhiteSpace($outputPath)) { return }
        $review = & $benchmarkSelectorPath -Path $inputPath -OutputPath $outputPath `
            -ConfigPath $settingsPath
        $resultText.Text = @"
유사 블로그 비교를 마쳤습니다.
주제: $($review.topic)
비교 후보: $($review.candidateCount)개
활성 후보: $($review.activeReferenceCount)개
주 참고 블로그: $($review.primaryBlogId)
공개 이웃 수: $($review.primaryPublicNeighbors)
선정 이유: $($review.selectionReason)
결과 파일: $outputPath

문장·제목·이미지·표는 복사하지 않고 구조만 참고합니다.
"@
    }
    catch { Show-ErrorMessage $_.Exception.Message }
})

$editorExecutionButton.Add_Click({
    try {
        $planPath = Select-JsonFile '편집기 재구성 실행 계획 JSON 선택'
        if ([string]::IsNullOrWhiteSpace($planPath)) { return }
        $observationPath = Select-JsonFile '동작별 편집기 실행 관찰 JSON 선택'
        if ([string]::IsNullOrWhiteSpace($observationPath)) { return }
        $verification = & $editorExecutionValidatorPath -PlanPath $planPath `
            -ObservationPath $observationPath | ConvertFrom-Json
        $resultText.Text = @"
편집기 재구성 실행 검사를 통과했습니다.
콘텐츠 번호: $($verification.ContentId)
검사 동작 수: $($verification.ActionCount)
비공개 저장 허용: $($verification.SaveAllowed)

본문 포커스·문단 수·정확한 문자열·문단 합침·간격 높이를 모두 확인했습니다.
"@
    }
    catch { Show-ErrorMessage $_.Exception.Message }
})

$editorVerifyButton.Add_Click({
    try {
        $planPath = Select-JsonFile '비공개 편집기 계획 JSON 선택'
        if ([string]::IsNullOrWhiteSpace($planPath)) { return }
        $observationPath = Select-JsonFile '컴퓨터 사용 편집기 관찰 JSON 선택'
        if ([string]::IsNullOrWhiteSpace($observationPath)) { return }
        $stageChoice = [System.Windows.Forms.MessageBox]::Show(
            "비공개 저장 후 검증입니까?`r`n예: 저장 후 / 아니오: 저장 전 / 취소: 중단",
            '편집기 검증 단계',
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($stageChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
        $mode = if ($stageChoice -eq [System.Windows.Forms.DialogResult]::Yes) {
            'AfterSave'
        } else {
            'BeforeSave'
        }
        $verification = & $editorResultValidatorPath -Mode $mode -PlanPath $planPath `
            -ObservationPath $observationPath | ConvertFrom-Json
        $resultText.Text = @"
편집기 결과 검사를 통과했습니다.
검사 단계: $($verification.Mode)
콘텐츠 번호: $($verification.ContentId)
공개 범위: $($verification.Visibility)
외부 저장 실행: $($verification.ExternalSavePerformed)

공개 발행 시도와 공지 등록은 없어야 합니다.
"@
    }
    catch { Show-ErrorMessage $_.Exception.Message }
})

if ($LayoutSelfTest) {
    $form.PerformLayout()

    function Assert-ControlWithinParent {
        param(
            [System.Windows.Forms.Control]$Control,
            [System.Windows.Forms.Control]$Parent,
            [string]$Label
        )
        $bounds = $Control.Bounds
        $client = $Parent.ClientRectangle
        if ($bounds.Left -lt 0 -or $bounds.Top -lt 0 -or
            $bounds.Right -gt $client.Width -or $bounds.Bottom -gt $client.Height) {
            throw "화면 요소가 부모 영역을 벗어났습니다: $Label"
        }
    }

    function Assert-NoControlOverlap {
        param(
            [System.Windows.Forms.Control[]]$Controls,
            [string]$GroupLabel
        )
        for ($leftIndex = 0; $leftIndex -lt $Controls.Count; $leftIndex++) {
            for ($rightIndex = $leftIndex + 1; $rightIndex -lt $Controls.Count; $rightIndex++) {
                if ($Controls[$leftIndex].Bounds.IntersectsWith($Controls[$rightIndex].Bounds)) {
                    throw "화면 요소가 겹칩니다: $GroupLabel ($($Controls[$leftIndex].Text), $($Controls[$rightIndex].Text))"
                }
            }
        }
    }

    foreach ($entry in @(
        @{ Control=$titleLabel; Label='제목' },
        @{ Control=$noticeLabel; Label='안내' },
        @{ Control=$workRootLabel; Label='작업 폴더 라벨' },
        @{ Control=$workRootText; Label='작업 폴더 입력' },
        @{ Control=$browseButton; Label='찾아보기' },
        @{ Control=$contentIdLabel; Label='콘텐츠 번호 라벨' },
        @{ Control=$contentIdText; Label='콘텐츠 번호 입력' },
        @{ Control=$newButton; Label='새 작업 만들기' },
        @{ Control=$statusButton; Label='진행 상태 확인' },
        @{ Control=$introButton; Label='프롤로그 준비' },
        @{ Control=$stepGroup; Label='단계별 검사 그룹' },
        @{ Control=$readerGroup; Label='독자 근거 그룹' },
        @{ Control=$resultLabel; Label='검사 결과 라벨' },
        @{ Control=$resultText; Label='검사 결과 본문' }
    )) {
        Assert-ControlWithinParent -Control $entry.Control -Parent $form -Label $entry.Label
    }
    foreach ($control in @($candidateButton, $factPrepareButton, $factCheckButton, $draftPrepareButton, $draftButton)) {
        Assert-ControlWithinParent -Control $control -Parent $stepGroup -Label $control.Text
    }
    foreach ($control in @($editorExecutionButton, $editorVerifyButton, $editorVerifyNotice)) {
        Assert-ControlWithinParent -Control $control -Parent $stepGroup -Label $control.Text
    }
    foreach ($control in @($readerButton, $benchmarkButton, $readerNotice)) {
        Assert-ControlWithinParent -Control $control -Parent $readerGroup -Label $control.Text
    }
    Assert-NoControlOverlap -Controls @($newButton, $statusButton, $introButton) -GroupLabel '상단 작업 버튼'
    Assert-NoControlOverlap -Controls @($candidateButton, $factPrepareButton, $factCheckButton, $draftPrepareButton, $draftButton) -GroupLabel '단계 버튼'
    Assert-NoControlOverlap -Controls @($editorExecutionButton, $editorVerifyButton, $editorVerifyNotice) -GroupLabel '편집기 검증 버튼'
    Assert-NoControlOverlap -Controls @($readerButton, $benchmarkButton, $readerNotice) -GroupLabel '독자 근거 버튼'

    $form.Dispose()
    Write-Output 'Naver automation UI layout self-test passed.'
    return
}

[void]$form.ShowDialog()

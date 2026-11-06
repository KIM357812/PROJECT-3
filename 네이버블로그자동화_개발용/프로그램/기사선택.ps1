#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('List', 'Show')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$CollectionPath,

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $PSScriptRoot '작업자료검증.ps1'
$selectorMode = $Mode
$requestedConfigPath = $ConfigPath
. $validatorPath -Mode CandidateCollection -Path 'unused'
$ConfigPath = $requestedConfigPath

if (-not (Test-Path -LiteralPath $CollectionPath -PathType Leaf)) {
    throw "소재 수집 결과를 찾을 수 없습니다: $CollectionPath"
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $projectRoot '설정.json'
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "설정 파일을 찾을 수 없습니다: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$collection = Get-Content -LiteralPath $CollectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$validation = Test-CandidateCollection -Collection $collection -Rules $config.Collection `
    -EditorialFocus $config.EditorialFocus
if (-not $validation.IsValid) {
    throw ('검증된 소재 수집 결과만 선택할 수 있습니다: ' + (@($validation.Issues) -join '; '))
}

$recommendationLookup = @{}
$recommendationRank = 0
foreach ($recommendation in @($collection.recommendations)) {
    $recommendationRank++
    $recommendationLookup[[string]$recommendation.url] = [pscustomobject]@{
        rank = $recommendationRank
        reason = [string]$recommendation.reason
    }
}

$choices = @()
foreach ($site in @($collection.sites)) {
    foreach ($article in @($site.articles)) {
        $url = [string]$article.url
        $recommendation = if ($recommendationLookup.ContainsKey($url)) {
            $recommendationLookup[$url]
        } else {
            [pscustomobject]@{ rank=0; reason='' }
        }
        $rankLabel = if ([int]$recommendation.rank -gt 0) {
            "추천 $($recommendation.rank)순위"
        } else {
            '일반 후보'
        }
        $choices += [pscustomobject]@{
            display = "$rankLabel | $($site.name) | $($article.title)"
            recommendationRank = [int]$recommendation.rank
            recommendationReason = [string]$recommendation.reason
            siteName = [string]$site.name
            title = [string]$article.title
            url = $url
            publishedDate = [string]$article.publishedDate
            factSummary = [string]$article.summary[0]
            importanceSummary = [string]$article.summary[1]
            convergenceDomains = @($article.convergenceDomains)
            coreAnalysisAxes = @($article.coreAnalysisAxes)
            connectionContext = [string]$article.connectionContext
            domesticRelevance = [string]$article.domesticRelevance
        }
    }
}
$choices = @($choices | Sort-Object `
    @{Expression={ if ($_.recommendationRank -gt 0) { $_.recommendationRank } else { 999 } }},
    siteName, title)

if ($selectorMode -eq 'List') {
    [pscustomobject]@{
        count = $choices.Count
        choices = $choices
    } | ConvertTo-Json -Depth 8
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$selectionForm = New-Object System.Windows.Forms.Form
$selectionForm.Text = '검증된 기사 선택'
$selectionForm.StartPosition = 'CenterParent'
$selectionForm.ClientSize = New-Object System.Drawing.Size(780, 500)
$selectionForm.MinimumSize = New-Object System.Drawing.Size(800, 540)
$selectionForm.Font = New-Object System.Drawing.Font('맑은 고딕', 10)

$guide = New-Object System.Windows.Forms.Label
$guide.Text = '추천 순위와 설명을 확인한 뒤 기사 한 건을 선택하세요. 선택만 하며 네이버나 외부 사이트에는 전송하지 않습니다.'
$guide.AutoSize = $true
$guide.Location = New-Object System.Drawing.Point(18, 16)
$selectionForm.Controls.Add($guide)

$list = New-Object System.Windows.Forms.ListBox
$list.Location = New-Object System.Drawing.Point(18, 48)
$list.Size = New-Object System.Drawing.Size(744, 150)
$list.DisplayMember = 'display'
foreach ($choice in $choices) { $null = $list.Items.Add($choice) }
$selectionForm.Controls.Add($list)

$details = New-Object System.Windows.Forms.TextBox
$details.Location = New-Object System.Drawing.Point(18, 215)
$details.Size = New-Object System.Drawing.Size(744, 220)
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$selectionForm.Controls.Add($details)

$selectButton = New-Object System.Windows.Forms.Button
$selectButton.Text = '이 기사 선택'
$selectButton.Location = New-Object System.Drawing.Point(552, 452)
$selectButton.Size = New-Object System.Drawing.Size(100, 32)
$selectButton.Enabled = $false
$selectionForm.Controls.Add($selectButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = '취소'
$cancelButton.Location = New-Object System.Drawing.Point(662, 452)
$cancelButton.Size = New-Object System.Drawing.Size(100, 32)
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$selectionForm.Controls.Add($cancelButton)
$selectionForm.CancelButton = $cancelButton

$list.Add_SelectedIndexChanged({
    if ($null -eq $list.SelectedItem) {
        $details.Text = ''
        $selectButton.Enabled = $false
        return
    }
    $selected = $list.SelectedItem
    $details.Text = @"
매체: $($selected.siteName)
원문 제목: $($selected.title)
게시일: $($selected.publishedDate)
URL: $($selected.url)

추천 이유: $($selected.recommendationReason)
핵심 사실: $($selected.factSummary)
중요한 이유: $($selected.importanceSummary)
AI 융합 분야: $(@($selected.convergenceDomains) -join ', ')
핵심 분석축: $(@($selected.coreAnalysisAxes) -join ', ')
연결 맥락: $($selected.connectionContext)
국내 연관성: $($selected.domesticRelevance)
"@
    $selectButton.Enabled = $true
})

$selectButton.Add_Click({
    if ($null -ne $list.SelectedItem) {
        $selectionForm.Tag = $list.SelectedItem
        $selectionForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $selectionForm.Close()
    }
})

if ($choices.Count -gt 0) { $list.SelectedIndex = 0 }
$dialogResult = $selectionForm.ShowDialog()
if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK -and $null -ne $selectionForm.Tag) {
    $selectionForm.Tag | ConvertTo-Json -Depth 7
}
$selectionForm.Dispose()

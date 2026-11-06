#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [Parameter(Mandatory = $true)][string]$ObservationPath
)

$ErrorActionPreference = 'Stop'
foreach ($path in @($PlanPath, $ObservationPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "필수 파일을 찾을 수 없습니다: $path"
    }
}

$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
$observation = Get-Content -LiteralPath $ObservationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$actions = @($plan.actions | Sort-Object sequence)
$records = @($observation.records | Sort-Object sequence)
$issues = New-Object 'System.Collections.Generic.List[string]'

if ([string]$observation.contentId -ne [string]$plan.contentId) {
    $issues.Add('실행 관찰 contentId가 재구성 계획과 다릅니다.')
}
if ($records.Count -ne $actions.Count) {
    $issues.Add('모든 재구성 동작에는 정확히 한 개의 실행 관찰 기록이 필요합니다.')
}
if ([bool]$observation.saveAttempted) {
    $issues.Add('재구성 실행 검증 전에는 비공개 저장을 시도할 수 없습니다.')
}

$limit = [Math]::Min($actions.Count, $records.Count)
for ($i = 0; $i -lt $limit; $i++) {
    $action = $actions[$i]
    $record = $records[$i]
    $label = "sequence $($action.sequence)"
    if ([int]$record.sequence -ne [int]$action.sequence) {
        $issues.Add("동작과 관찰 순서가 일치하지 않습니다: $label")
    }
    if (-not [bool]$record.editorBodyFocusedBefore -or [bool]$record.toolbarOrDialogFocusedBefore) {
        $issues.Add("본문 편집 문단 포커스가 확인되지 않았습니다: $label")
    }
    $logicalCount = if ($record.PSObject.Properties.Name -contains 'editorLogicalBlockCountAfter') {
        [int]$record.editorLogicalBlockCountAfter
    } else { [int]$record.editorParagraphCountAfter }
    if ($logicalCount -ne ($i + 1)) {
        $issues.Add("동작 직후 편집기 논리 블록 수가 예상값과 다릅니다: $label")
    }

    if ([string]$action.action -eq 'InsertBlock') {
        if ([string]$record.observedText -ne [string]$action.text) {
            $issues.Add("입력 문자열이 구조화 블록과 정확히 일치하지 않습니다: $label")
        }
        if (-not [bool]$record.standaloneParagraph) {
            $issues.Add("논리 블록이 독립 문단이 아닙니다: $label")
        }
        if ([bool]$record.mergedWithAdjacentBlock) {
            $issues.Add("논리 블록이 앞뒤 문단과 합쳐졌습니다: $label")
        }
    }
    elseif ([string]$action.action -eq 'InsertMeasuredSpacer') {
        if (-not [string]::IsNullOrEmpty([string]$record.observedText) -or
            -not [bool]$record.emptyStandaloneParagraph) {
            $issues.Add("간격 동작은 비어 있는 독립 문단이어야 합니다: $label")
        }
        $height = 0.0
        $heightValid = [double]::TryParse(
            [string]$record.renderedHeightPx,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$height
        )
        if (-not $heightValid -or
            [Math]::Abs($height - [double]$action.expectedGapPx) -gt [double]$action.tolerancePx) {
            $issues.Add("간격 문단의 실제 높이가 허용 범위를 벗어났습니다: $label")
        }
        if ([int]$record.fontSizePx -ne [int]$action.fontSizePx -or
            [Math]::Abs([double]$record.lineHeight - [double]$action.lineHeight) -gt 0.001) {
            $issues.Add("간격 문단의 글자 크기 또는 줄높이가 계획과 다릅니다: $label")
        }
    }
    elseif ([string]$action.action -eq 'InsertCalloutTable') {
        if ([string]$record.observedText -ne [string]$action.text) {
            $issues.Add("강조 상자 문자열이 구조화 블록과 정확히 일치하지 않습니다: $label")
        }
        if (-not [bool]$record.standaloneComponent -or -not [bool]$record.singleCellTable) {
            $issues.Add("강조 상자는 독립된 1열 표 구성요소여야 합니다: $label")
        }
        if ([bool]$record.horizontalOverflow -or [int]$record.blankParagraphCountBefore -ne 0 -or
            [int]$record.blankParagraphCountAfter -ne 0) {
            $issues.Add("강조 상자 가로 넘침 또는 인접 빈 문단이 발견됐습니다: $label")
        }
        if ([string]$record.calloutKind -ne [string]$action.calloutKind -or
            [string]$record.backgroundColor -ne [string]$action.formatting.backgroundColor -or
            [string]$record.accentColor -ne [string]$action.formatting.accentColor -or
            [int]$record.accentWidthPx -ne [int]$action.formatting.accentWidthPx -or
            [string]$record.titleColor -ne [string]$action.formatting.titleColor) {
            $issues.Add("강조 상자 종류·배경·왼쪽 바·제목색이 계획과 다릅니다: $label")
        }
    }
    elseif ([string]$action.action -eq 'InsertImage') {
        if ([string]$record.fileName -ne [string]$action.fileName -or
            [string]$record.role -ne [string]$action.role) {
            $issues.Add("이미지 파일명 또는 역할이 계획과 다릅니다: $label")
        }
        if (-not [bool]$record.standaloneComponent -or -not [bool]$record.naverHostedImage -or
            [string]$record.alignment -ne [string]$action.formatting.alignment -or
            [int]$record.displayWidthPx -ne [int]$action.formatting.displayWidthPx) {
            $issues.Add("이미지 업로드·가운데 정렬·표시 폭이 계획과 다릅니다: $label")
        }
    }
    else {
        $issues.Add("지원하지 않는 재구성 동작입니다: $label")
    }
}

$result = [pscustomobject]@{
    IsValid = ($issues.Count -eq 0)
    ContentId = [string]$plan.contentId
    ActionCount = $actions.Count
    SaveAllowed = ($issues.Count -eq 0)
    Issues = @($issues)
}
$result | ConvertTo-Json -Depth 5
if ($issues.Count -gt 0) {
    throw ('편집기 재구성 실행 검증 실패: ' + (@($issues) -join '; '))
}

#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('BeforeSave', 'AfterSave')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) {
    throw "편집기 계획을 찾을 수 없습니다: $PlanPath"
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "기존 편집기 관찰 양식을 덮어쓰지 않습니다: $OutputPath"
}

$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$plan.visibility -ne '비공개' -or [bool]$plan.allowPublicPublish) {
    throw '비공개 전용 편집기 계획만 관찰 양식을 만들 수 있습니다.'
}

$template = [pscustomobject]@{
    mode = $Mode
    contentId = [string]$plan.contentId
    observedAt = ''
    editorUrl = ''
    title = ''
    body = ''
    tags = @()
    category = ''
    visibility = ''
    registerAsNotice = $null
    publicPublishAttempted = $null
    externalSavePerformed = $null
    savedAsPrivate = $null
    publicUrlCreated = $null
    savedDraftIndicator = ''
    imageCount = $null
    imageFileNames = @()
    imageOrderVerified = $null
    imageServerUploadVerified = $null
    pcLayoutVerified = $null
    mobileLayoutVerified = $null
    layoutMeasurementSource = ''
    bodyFontSizePx = $null
    bodyFontFamily = ''
    bodyTextAlignment = ''
    bodyLastLineAlignment = ''
    bodyLineHeightPx = $null
    paragraphMarginBottomPx = $null
    bodyParagraphPairCount = $null
    paragraphGapLayouts = @()
    questionToReferenceGapLayout = $null
    headingLayouts = @()
    calloutLayouts = @()
    mobileBodyFontSizePx = $null
    mobileBodyFontFamily = ''
    mobileBodyTextAlignment = ''
    mobileBodyLastLineAlignment = ''
    mobileBodyLineHeightPx = $null
    mobileParagraphMarginBottomPx = $null
    mobileBodyParagraphPairCount = $null
    mobileParagraphGapLayouts = @()
    mobileQuestionToReferenceGapLayout = $null
    mobileHeadingLayouts = @()
    mobileCalloutLayouts = @()
    saveAttemptCount = $null
    publishDelayObserved = $null
    recoveryAction = ''
    evidenceNote = '컴퓨터 사용으로 실제 네이버 렌더링 DOM과 PC·모바일 화면에서 읽은 값만 기록한다. 계획값을 복사해 확인을 대신하지 않는다. 기본서체·양쪽 정렬·마지막 줄 왼쪽 정렬, 모든 일반 본문 문단 쌍과 마지막 독자 질문→참고자료 구간의 실제 간격·간격 문단 수·높이, 모든 소제목·강조 상자의 실제 글자 크기·위아래 간격·줄높이 및 상자 앞뒤 빈 문단 수를 측정하지 않으면 완료로 처리하지 않는다.'
}

$directory = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($directory)) { throw 'OutputPath는 상위 폴더를 포함해야 합니다.' }
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $directory
}
$template | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    output = [IO.Path]::GetFullPath($OutputPath)
    mode = $Mode
    contentId = [string]$plan.contentId
    requiresActualObservation = $true
} | ConvertTo-Json -Depth 4

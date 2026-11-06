#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DraftPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $projectRoot '설정.json'
$validatorPath = Join-Path $PSScriptRoot '초안검증.ps1'
. $validatorPath -Path 'unused'

if (-not (Test-Path -LiteralPath $DraftPath -PathType Leaf)) {
    throw "네이버 초안 파일을 찾을 수 없습니다: $DraftPath"
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "기존 편집기 계획을 덮어쓰지 않습니다: $OutputPath"
}

$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$draft = Get-Content -LiteralPath $DraftPath -Raw -Encoding UTF8 | ConvertFrom-Json
$validation = Test-NaverDraft -Draft $draft -Rules $settings.NaverDraft
if (-not $validation.IsValid) {
    throw ('초안을 먼저 보완해야 합니다: ' + (@($validation.Issues) -join '; '))
}
if ([bool]$settings.NaverEditor.AllowPublicPublish) {
    throw '개발 설정에서 공개 게시를 허용할 수 없습니다.'
}
if ([string]$settings.NaverEditor.TestVisibility -ne '비공개') {
    throw '테스트 편집기 계획은 비공개만 허용합니다.'
}

$plan = [pscustomobject]@{
    contentId = [string]$draft.contentId
    draftType = [string]$draft.draftType
    editorUrl = [string]$settings.Brand.NaverBlogUrl
    title = [string]$draft.title
    body = [string]$draft.body
    sectionHeadings = @($draft.sectionHeadings | ForEach-Object { [string]$_ })
    sectionFormatting = [pscustomobject]@{
        titleFontSize = [int]$settings.NaverDraft.PostTitleFontSize
        titleMobileFontSize = [int]$settings.NaverDraft.PostTitleMobileFontSize
        bold = [bool]$settings.NaverDraft.SectionHeadingBold
        headingFontSize = [int]$settings.NaverDraft.SectionHeadingFontSize
        bodyFontSize = [int]$settings.NaverDraft.BodyFontSize
        bodyLineHeight = [double]$settings.NaverDraft.BodyLineHeight
        bodyLineHeightPx = [int]$settings.NaverDraft.BodyLineHeightPx
        paragraphMarginBottomPx = [int]$settings.NaverDraft.ParagraphMarginBottomPx
        headingMarginTopPx = [int]$settings.NaverDraft.SectionHeadingMarginTopPx
        headingMarginBottomPx = [int]$settings.NaverDraft.SectionHeadingMarginBottomPx
        dividerEnabled = [bool]$settings.NaverDraft.SectionHeadingDividerEnabled
        dividerColor = [string]$settings.NaverDraft.SectionHeadingDividerColor
        dividerThicknessPx = [int]$settings.NaverDraft.SectionHeadingDividerThicknessPx
        blankLineBeforeAndAfter = $false
        forbidSpacingBlankParagraphs = $true
        mobilePurpose = '네이버 편집기 지원값에 맞춰 소제목 19px·위 35px·아래 15px, 일반 본문 16px·줄높이 1.75(28px), 일반 문단 사이 실제 18px를 적용해 PC와 모바일에서 소속 관계를 빠르게 파악하게 한다.'
    }
    paragraphGapFormatting = [pscustomobject]@{
        mode = [string]$settings.NaverDraft.ParagraphGapDesign.Mode
        gapPx = [int]$settings.NaverDraft.ParagraphGapDesign.GapPx
        gapTolerancePx = [double]$settings.NaverDraft.ParagraphGapDesign.GapTolerancePx
        spacerParagraphCount = [int]$settings.NaverDraft.ParagraphGapDesign.SpacerParagraphCount
        spacerFontSizePx = [int]$settings.NaverDraft.ParagraphGapDesign.SpacerFontSizePx
        spacerLineHeight = [double]$settings.NaverDraft.ParagraphGapDesign.SpacerLineHeight
        applyOnlyBetweenOrdinaryBodyParagraphs = [bool]$settings.NaverDraft.ParagraphGapDesign.ApplyOnlyBetweenOrdinaryBodyParagraphs
        forbidAdjacentToSectionHeadings = [bool]$settings.NaverDraft.ParagraphGapDesign.ForbidAdjacentToSectionHeadings
        forbidAdjacentToCallouts = [bool]$settings.NaverDraft.ParagraphGapDesign.ForbidAdjacentToCallouts
        requirePcAndMobileMeasurement = [bool]$settings.NaverDraft.ParagraphGapDesign.RequirePcAndMobileMeasurement
    }
    calloutFormatting = [pscustomobject]@{
        requireFiveWOneHSummary = [bool]$settings.NaverDraft.RequireFiveWOneHSummary
        enabled = [bool]$settings.NaverDraft.CalloutDesign.Enabled
        renderMode = [string]$settings.NaverDraft.CalloutDesign.RenderMode
        defaultCount = [int]$settings.NaverDraft.CalloutDesign.DefaultCount
        maximumCount = [int]$settings.NaverDraft.CalloutDesign.MaximumCount
        fourthBlockMinimumBodyChars = [int]$settings.NaverDraft.CalloutDesign.FourthBlockMinimumBodyChars
        fourthBlockUse = [string]$settings.NaverDraft.CalloutDesign.FourthBlockUse
        innerPaddingVerticalPx = [int]$settings.NaverDraft.CalloutDesign.InnerPaddingVerticalPx
        innerPaddingHorizontalPx = [int]$settings.NaverDraft.CalloutDesign.InnerPaddingHorizontalPx
        outerMarginTopPx = [int]$settings.NaverDraft.CalloutDesign.OuterMarginTopPx
        outerMarginBottomPx = [int]$settings.NaverDraft.CalloutDesign.OuterMarginBottomPx
        borderRadiusPx = [int]$settings.NaverDraft.CalloutDesign.BorderRadiusPx
        leftAccentEnabled = [bool]$settings.NaverDraft.CalloutDesign.LeftAccentEnabled
        leftAccentWidthPx = [int]$settings.NaverDraft.CalloutDesign.LeftAccentWidthPx
        titleFontSizePx = [int]$settings.NaverDraft.CalloutDesign.TitleFontSizePx
        titleFontWeight = [int]$settings.NaverDraft.CalloutDesign.TitleFontWeight
        titleMarginBottomPx = [int]$settings.NaverDraft.CalloutDesign.TitleMarginBottomPx
        bodyLineHeight = [double]$settings.NaverDraft.CalloutDesign.BodyLineHeight
        paragraphMarginBottomPx = [int]$settings.NaverDraft.CalloutDesign.ParagraphMarginBottomPx
        calloutParagraphSpacerEnabled = [bool]$settings.NaverDraft.CalloutDesign.CalloutParagraphSpacerEnabled
        calloutParagraphSpacerLineHeightPercent = [int]$settings.NaverDraft.CalloutDesign.CalloutParagraphSpacerLineHeightPercent
        forbidAdjacentBlankParagraphs = [bool]$settings.NaverDraft.CalloutDesign.ForbidAdjacentBlankParagraphs
        fiveWOneHLabelBold = [bool]$settings.NaverDraft.CalloutDesign.FiveWOneHLabelBold
        labelSeparator = [string]$settings.NaverDraft.CalloutDesign.LabelSeparator
        fixedPlacementOrder = @($settings.NaverDraft.CalloutDesign.FixedPlacementOrder | ForEach-Object { [string]$_ })
        requireSourceOutletInFiveWOneH = [bool]$settings.NaverDraft.CalloutDesign.RequireSourceOutletInFiveWOneH
        requireConcreteEventDate = [bool]$settings.NaverDraft.CalloutDesign.RequireConcreteEventDate
        requireOfficialVerificationLinks = [bool]$settings.NaverDraft.CalloutDesign.RequireOfficialVerificationLinks
        judgmentEvidenceLabels = @($settings.NaverDraft.CalloutDesign.JudgmentEvidenceLabels | ForEach-Object { [string]$_ })
        styles = @($settings.NaverDraft.CalloutDesign.Styles | ForEach-Object {
            [pscustomobject]@{
                name = [string]$_.Name
                kind = [string]$_.Kind
                backgroundColor = [string]$_.BackgroundColor
                accentColor = [string]$_.AccentColor
                titleColor = [string]$_.TitleColor
                titleMarginBottomPx = [int]$_.TitleMarginBottomPx
                outerMarginTopPx = [int]$_.OuterMarginTopPx
                outerMarginBottomPx = [int]$_.OuterMarginBottomPx
            }
        })
        usage = @('육하원칙', '핵심요약', '운영자판단')
    }
    tags = @($draft.tags)
    sources = @($draft.sources)
    referenceFormatting = [pscustomobject]@{
        label = [string]$settings.NaverDraft.ReferenceLineLabel
        placement = [string]$settings.NaverDraft.ReferencePlacement
        displayMode = [string]$settings.NaverDraft.ReferenceDisplayMode
        questionToReferenceGap = [pscustomobject]@{
            order = [string]$settings.NaverDraft.ReferenceGapDesign.Order
            mode = [string]$settings.NaverDraft.ReferenceGapDesign.Mode
            gapPx = [int]$settings.NaverDraft.ReferenceGapDesign.GapPx
            gapTolerancePx = [double]$settings.NaverDraft.ReferenceGapDesign.GapTolerancePx
            spacerParagraphCount = [int]$settings.NaverDraft.ReferenceGapDesign.SpacerParagraphCount
            spacerFontSizePx = [int]$settings.NaverDraft.ReferenceGapDesign.SpacerFontSizePx
            spacerLineHeight = [double]$settings.NaverDraft.ReferenceGapDesign.SpacerLineHeight
            requirePcAndMobileMeasurement = [bool]$settings.NaverDraft.ReferenceGapDesign.RequirePcAndMobileMeasurement
        }
        hideRawUrls = $true
        separator = ', '
        links = @($draft.sources | ForEach-Object {
            [pscustomobject]@{
                text = [string]$_.name
                url = [string]$_.url
                role = if ($_.PSObject.Properties.Name -contains 'role') { [string]$_.role } else { '참고자료' }
            }
        })
    }
    bodyLinks = if ($draft.PSObject.Properties.Name -contains 'bodyLinks' -and $null -ne $draft.bodyLinks) {
        @($draft.bodyLinks)
    } else { @() }
    boldHighlights = if ($draft.PSObject.Properties.Name -contains 'boldHighlights' -and $null -ne $draft.boldHighlights) {
        @($draft.boldHighlights | ForEach-Object { [string]$_ })
    } else { @() }
    inlineFormatting = [pscustomobject]@{
        maximumBodyLinks = [int]$settings.NaverDraft.MaximumBodyLinks
        bodyLinkMaximumWords = [int]$settings.NaverDraft.BodyLinkMaximumWords
        maximumBoldHighlights = [int]$settings.NaverDraft.MaximumBoldHighlights
        excludeHeadingsAndCalloutLabelsFromBoldCount = $true
        unfamiliarAcronymFirstUseFormat = '약어(한글 설명)'
        unfamiliarAcronymScanOrder = '제목·태그·참고자료 제외, 도입부→바탕글→일반 본문→운영자 판단의 실제 화면 표시 순서'
        stopBeforeEditorOnAcronymFailure = $true
    }
    imagePrompts = @($draft.imagePrompts)
    imageSpecification = [pscustomobject]@{
        count = [int]$settings.ImageAutomation.TargetCount
        width = [int]$settings.ImageAutomation.Width
        height = [int]$settings.ImageAutomation.Height
        aspectRatio = [string]$settings.ImageAutomation.AspectRatio
        format = [string]$settings.ImageAutomation.OutputFormat
        maximumKilobytes = [int]$settings.ImageAutomation.MaximumKilobytes
        editorDisplayWidth = [int]$settings.ImageAutomation.EditorDisplayWidth
        editorAlignment = [string]$settings.ImageAutomation.EditorAlignment
    }
    imagePlacements = @($settings.ImageAutomation.Roles | ForEach-Object {
        [pscustomobject]@{
            order = [int]$_.Order
            name = [string]$_.Name
            fileName = [string]$_.OutputFileName
            placement = [string]$_.Placement
            purpose = [string]$_.Purpose
        }
    })
    editorialContext = $draft.editorialContext
    benchmarkReview = $draft.benchmarkReview
    officialCompliance = $draft.officialCompliance
    readerDesign = $draft.readerDesign
    category = if ([string]::IsNullOrWhiteSpace([string]$draft.requestedCategory)) {
        [string]$settings.NaverEditor.DefaultCategory
    } else {
        [string]$draft.requestedCategory
    }
    visibility = [string]$settings.NaverEditor.TestVisibility
    registerAsNotice = [bool]$settings.NaverEditor.RegisterAsNotice
    allowPublicPublish = $false
    requiresApprovalBeforeExternalSave = [bool]$settings.NaverEditor.RequireApprovalBeforeExternalSave
    stopPoint = '외부 저장 버튼 클릭 직전'
    verificationSteps = @(
        'mainFrame과 제목·본문 컴포넌트 각각 한 개 확인',
        '제목과 본문 입력 후 실제 문자열 재확인',
        '제목을 PC 26pt·모바일 24pt로 확인하고 모든 소제목을 굵게·19px·하단 구분선으로 적용한 뒤 일반 본문 16px·줄높이 1.75(28px), 소제목 위 35px·아래 15px, 일반 문단 뒤 18px를 빈 문단 없이 적용했는지 확인',
        '연속된 일반 본문 문단 사이에만 네이버 지원값 11px·줄높이 1.6의 간격 문단 1개로 화면상 18px(렌더링 17.6px, 허용 오차 0.5px)을 만들고, 소제목·강조 상자 앞뒤에는 간격 문단을 넣지 않았는지 PC·모바일 렌더링에서 모든 문단 쌍을 측정',
        '완결된 도입부→육하원칙→연결 문장→핵심요약→첫 소제목 순서를 확인하고 육하원칙 여섯 값이 선정 기사 기반 articleFiveWOneH와 정확히 일치하며 출처 URL도 첫 번째 기사 URL과 같은지 확인',
        '육하원칙은 완성 본문을 다시 요약하지 않고 실제 주체·사건일·장소·방식·이유를 선정 기사에서 추출했는지, 기사에 없는 항목을 확인되지 않음으로 남겼는지 확인',
        '운영자 판단에 확인된 사실·주의할 표현·판단과 공식 링크가 있는지 확인',
        '제목·태그·참고자료를 제외한 실제 화면 표시 순서로 도입부·바탕글·일반 본문·운영자 판단을 검사해, 한국 일반 독자에게 낯선 핵심 영문 약어의 첫 출현이 약어(한글 설명) 형식이고 이후에는 약어만 사용되는지 확인하며 실패 시 편집기 입력·비공개 저장 중단',
        '육하원칙·핵심요약·운영자판단을 모바일 가로 이동이 없는 1열 반응형 배경 상자로 적용하고 왼쪽에 4px 포인트선을 두며, 네이버 표 구성요소 상자 앞 30px·인접 빈 문단 0개, 제목은 15px·700 굵기로 표시하고 제목 아래 회색·주황 8px/육하원칙 녹색 10px, 본문 줄높이 1.75·문단 뒤 18px, 내부 여백 16px 18px와 4px 모서리를 적용했는지 확인',
        '동일한 3:2 이미지 3장을 원본 1200×800으로 생성하고 네이버 표시 폭 340px·가운데 정렬과 각 삽입 위치 확인',
        '카테고리와 태그 확인',
        '네이버 공식 기준 준수와 독자용 구조 확인',
        'AI 융합 연결·국내 영향·사실과 판단 구분 확인',
        '마지막 독자 질문과 참고자료 사이에 16px·줄높이 2.0의 간격 문단 1개로 정확히 32px을 만들고 PC·모바일에서 측정한 뒤, 참고자료 : 매체명 형식으로 배치하고 원문을 첫 번째로 두며 각 매체명에 상세 URL을 연결하되 URL 문자열은 숨겼는지 확인',
        '본문 링크 문구가 최대 3단어이고 같은 URL을 반복하지 않았으며, 소제목·강조 상자 제목을 제외한 굵은 핵심 표현이 최대 3개인지 확인',
        '비공개 라디오 선택 상태 확인',
        '사용자 승인 전 저장·발행 버튼 클릭 금지'
    )
}

$directory = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($directory)) { throw 'OutputPath는 상위 폴더를 포함해야 합니다.' }
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $directory
}
$plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    output = [System.IO.Path]::GetFullPath($OutputPath)
    contentId = $plan.contentId
    visibility = $plan.visibility
    stopPoint = $plan.stopPoint
} | ConvertTo-Json -Depth 4

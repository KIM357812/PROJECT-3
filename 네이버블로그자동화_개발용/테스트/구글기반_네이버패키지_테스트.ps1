#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root '프로그램\구글기반_네이버패키지.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('naver-google-package-test-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $temporaryRoot 'source'
$work = Join-Path $temporaryRoot 'work'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "검증 실패: $Message" }
}

try {
    New-Item -ItemType Directory -Path $source,$work -Force | Out-Null
    $image = '<div data-blog-image-wrap="true" style="text-align:center;margin:28px 0 28px 0"><img src="data:image/svg+xml;base64,PHN2Zy8+" alt="장면" title="장면"></div>'
    $table = '<div class="solidb-responsive-table" style="margin:25px 0"><table><thead><tr><th>항목</th><th>값</th></tr></thead><tbody><tr><td data-label="항목">시험</td><td data-label="값">1</td></tr></tbody></table></div>'
    $overview = '<div style="background-color:#eef3fb;border:1px solid #d3e0f5;padding:14px 18px;margin:20px 0"><p style="font-weight:700">이 글에서 다루는 내용</p><p>핵심 내용 안내</p></div>'
    $related = '<div data-blog-related="true" style="margin:14px 0 0 0"><p>관련 글</p><p><a href="https://blog.naver.com/ij1128/1">이전 글</a></p></div>'
    $html = '<div style="width:100%;max-width:800px;margin:0 auto"><p style="font-size:16px;line-height:1.75;margin:0 0 18px 0;text-align:justify;text-align-last:left">도입 첫 문단</p><p style="font-size:16px;line-height:1.75;margin:0 0 18px 0;text-align:justify;text-align-last:left">도입 둘째 문단</p>' + $image + $table + '<h2 style="font-size:22px;border-bottom:2px solid #000">현황</h2>' + $overview + '<h2>측정</h2><div style="background:#eee"><p style="line-height:1.6;margin:0 0 8px 0;font-weight:700">강조 제목</p><p style="line-height:1.6">강조 본문</p></div>' + $image + '<h3>분석</h3>' + $image + '<p>전망</p>' + $image + '<div data-blog-sources="true" style="margin:20px 0"><p><strong>출처 :</strong> 링크</p></div>' + $related + '</div>'
    Set-Content -LiteralPath (Join-Path $source 'Blogger에_붙여넣을_본문.html') -Value $html -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $source '메타데이터.txt') -Value "## 5. 해시태그`nAI, 데이터센터, 전력망, 에너지, 기술동향`n## 6. 내부 사실검증표" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $source '사실검증표.md') -Value '검증 완료' -Encoding UTF8
    $prompts = 1..4 | ForEach-Object { "### $_. 이미지 $_`n- 상세 영문 프롬프트: photorealistic editorial technology scene $_, textless, no text, no letters, no numbers, no watermark, no logo" }
    Set-Content -LiteralPath (Join-Path $source '이미지_프롬프트.txt') -Value ($prompts -join "`n`n") -Encoding UTF8
    [pscustomobject]@{ RecommendedTitle='시험 제목'; Site='POWER Magazine'; Url='https://example.com/article'; Title='원문 제목' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $source '작업정보.json') -Encoding UTF8
    $before = Get-ChildItem -LiteralPath $source -File | Sort-Object Name | Get-FileHash -Algorithm SHA256

    $result = & $scriptPath -SourceArticlePath $source -WorkRoot $work -ContentId 'NTE-TEST-001' | ConvertFrom-Json
    Assert-True ($result.segmentCount -eq 5) '이미지 사이 입력 구간 5개'
    Assert-True ($result.imageCount -eq 4) 'Google 기준 이미지 4개'
    Assert-True ($result.tagCount -ge 5 -and $result.tagCount -le 10) '네이버 태그 5~10개'
    Assert-True ($result.stopPoint -eq 'BeforePublicationSettings') '발행 설정 전 정지'

    $plan = Get-Content -LiteralPath $result.editorPlan -Raw -Encoding UTF8 | ConvertFrom-Json
    $contract = Get-Content -LiteralPath $result.executionContract -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($plan.actions | Where-Object type -eq 'InsertImageAnchor').Count -eq 4) '이미지 앵커 4개'
    Assert-True (@($plan.actions | Where-Object type -eq 'UploadImageAtAnchor').Count -eq 4) '앵커 이미지 삽입 동작 4개'
    Assert-True (@($plan.actions | Where-Object type -match 'Publish|Save').Count -eq 0) '공개·비공개 발행 동작 없음'
    Assert-True ($result.executionStatus -eq 'NotExecuted' -and -not [bool]$result.completionClaimAllowed) '실행 전 패키지를 완료로 표시하지 않음'
    Assert-True ($contract.executionMode -eq 'ComputerUseNewPostOnly') '컴퓨터 사용 새 글 전용 실행 계약'
    Assert-True ($plan.schemaVersion -eq 3 -and $contract.schemaVersion -eq 4) '강화된 편집 실행 계약 버전'
    Assert-True ([bool]$contract.guards.existingPostModificationForbidden) '기존 글 수정 금지 실행 가드'
    Assert-True ([bool]$contract.guards.publicationSettingsForbidden -and [bool]$contract.guards.publicOrPrivatePublishForbidden) '발행 설정·게시 금지 실행 가드'
    Assert-True (@($contract.steps).Count -eq @($plan.actions).Count) '편집 계획 전체 동작이 실행 계약에 연결됨'
    Assert-True (@($contract.steps | Where-Object { -not $_.postcondition.stopImmediatelyOnMismatch }).Count -eq 0) '동작 불일치 즉시 중단'
    Assert-True ($contract.guards.imageConstructionMode -eq 'TextFirstThenReverseAnchorUpload' -and [bool]$contract.guards.forbidFormattedPasteAfterFirstImageUpload -and [bool]$contract.guards.requireAllPriorImageUrlsAfterEveryUpload) '본문 완성 후 이미지 역순 삽입 가드'
    $uploadActions = @($plan.actions | Where-Object type -eq 'UploadImageAtAnchor')
    Assert-True (($uploadActions.documentOrder -join ',') -eq '4,3,2,1') '이미지 문서 역순 업로드'
    $firstUploadPosition = [array]::IndexOf(@($plan.actions), $uploadActions[0])
    $lateTextActions = @(@($plan.actions)[($firstUploadPosition + 1)..(@($plan.actions).Count - 1)] | Where-Object type -match 'Paste|Heading|Spacer')
    Assert-True ($lateTextActions.Count -eq 0) '첫 이미지 업로드 이후 본문 붙여넣기 금지'
    Assert-True (@($plan.actions | Where-Object type -eq 'ClearEditorBody').Count -eq 1) '이전 편집 내용 제거 후 전체 재구성'
    $normalize = @($plan.actions | Where-Object type -eq 'NormalizeBodyDefaults')
    Assert-True ($normalize.Count -eq 1 -and -not [bool]$normalize[0].bold -and $normalize[0].fontFamily -eq '기본서체' -and $normalize[0].fontSizePx -eq 15) '본문 기본서식과 굵기 해제 선행'
    Assert-True (@($contract.steps | Where-Object { $_.action -eq 'InsertStandaloneHeading' -and -not $_.postcondition.requireIndependentEditorComponent }).Count -eq 0) '소제목 독립 구성요소 실행 조건'
    Assert-True (@($plan.reusedExistingNaverFeatures).Count -eq 3) '기존 네이버 이미지 기능만 재사용'
    Assert-True (@($plan.actions | Where-Object type -eq 'PasteRenderedSegment').Count -eq 0) '여러 제목·본문을 한 번에 붙여 넣는 구간 동작 금지'
    $headingActions = @($plan.actions | Where-Object type -eq 'InsertStandaloneHeading')
    Assert-True ($headingActions.Count -eq 3) 'H2·H3 독립 소제목 동작 수'
    Assert-True ($plan.headingInsertionMode -eq 'StandaloneParagraphWithMeasuredSpacers') '독립 소제목 삽입 모드'
    Assert-True ([bool]$plan.mobileHeadingSpacing.required -and $plan.mobileHeadingSpacing.sectionTopPx -eq 32 -and $plan.mobileHeadingSpacing.sectionBottomPx -eq 21 -and $plan.mobileHeadingSpacing.subheadingTopPx -eq 24 -and $plan.mobileHeadingSpacing.subheadingBottomPx -eq 12 -and $plan.mobileHeadingSpacing.mobileParentToSubheadingPx -eq 8 -and $plan.mobileHeadingSpacing.mobileSubheadingBottomPx -eq 8 -and $plan.mobileHeadingSpacing.mobileSectionLineHeightPx -eq 23 -and $plan.mobileHeadingSpacing.mobileSubheadingLineHeightPx -eq 22) 'PC 기준 유지와 모바일 전용 소제목 간격·줄높이 기준'
    foreach ($headingAction in $headingActions) {
        $position = [array]::IndexOf(@($plan.actions), $headingAction)
        Assert-True ($position -gt 0 -and $position -lt (@($plan.actions).Count - 1)) '소제목 앞뒤 동작 존재'
        $beforeAction = @($plan.actions)[$position - 1]
        $afterHeading = @($plan.actions)[$position + 1]
        $expectedTop = if ($headingAction.level -eq 2) { 32 } else { 24 }
        $expectedBottom = if ($headingAction.level -eq 2) { 21 } else { 12 }
        $validBefore = ($beforeAction.type -eq 'InsertVerticalSpacer' -and $beforeAction.purpose -eq 'HeadingTop' -and $beforeAction.heightPx -eq $expectedTop) -or ($headingAction.level -eq 2 -and $beforeAction.blockRole -in @('DataTable','OverviewBox') -and $beforeAction.postcondition.maximumRenderedHeadingGapPx -eq 30)
        Assert-True $validBefore "H$($headingAction.level) 위 독립 간격"
        $validAfter = ($afterHeading.type -eq 'InsertVerticalSpacer' -and $afterHeading.purpose -eq 'HeadingBottom' -and $afterHeading.heightPx -eq $expectedBottom) -or ($afterHeading.type -eq 'InsertImageAnchor' -and [bool]$afterHeading.postcondition.requireDirectlyAfterHeadingWhenApplicable)
        Assert-True $validAfter "H$($headingAction.level) 아래 간격 또는 직접 이미지 연결"
        if($beforeAction.type -eq 'InsertVerticalSpacer' -and $beforeAction.purpose -eq 'HeadingTop'){
            $expectedTopNative = if($headingAction.level -eq 2){@(16,200)}else{@(15,160)}
            Assert-True ($beforeAction.naverFontSizePx -eq $expectedTopNative[0] -and $beforeAction.naverLineHeightPercent -eq $expectedTopNative[1]) "H$($headingAction.level) 모바일 위 간격 네이티브 표현"
        }
        if($afterHeading.type -eq 'InsertVerticalSpacer' -and $afterHeading.purpose -eq 'HeadingBottom'){
            $expectedBottomNative = if($headingAction.level -eq 2){@(13,160)}else{@(12,100)}
            Assert-True ($afterHeading.naverFontSizePx -eq $expectedBottomNative[0] -and $afterHeading.naverLineHeightPercent -eq $expectedBottomNative[1]) "H$($headingAction.level) 모바일 아래 간격 네이티브 표현"
            if($headingAction.level -eq 3){ Assert-True ($afterHeading.mobileHeightPx -eq 8) 'H3 모바일 아래 간격 8px' }
        }
        Assert-True (($headingAction.level -eq 2 -and $headingAction.mobileLineHeightPx -eq 23) -or ($headingAction.level -eq 3 -and $headingAction.mobileLineHeightPx -eq 22)) '모바일 여러 줄 소제목 줄높이'
        Assert-True (($headingAction.level -eq 2 -and $headingAction.fontSizePx -eq 19 -and -not [bool]$headingAction.underline -and $headingAction.textColor -eq '#4A78E0') -or ($headingAction.level -eq 3 -and $headingAction.fontSizePx -eq 16 -and -not [bool]$headingAction.underline -and $headingAction.textColor -eq '#111111')) 'H2/H3 크기·색상·밑줄 없음 계층'
        Assert-True ([bool]$headingAction.postcondition.requireStandaloneParagraph) '소제목 독립 문단 사후조건'
        Assert-True ([bool]$headingAction.postcondition.forbidMergedPreviousText -and [bool]$headingAction.postcondition.forbidMergedNextText) '소제목 앞뒤 본문 합침 금지'
    }
    $paragraphActions = @($plan.actions | Where-Object type -eq 'PasteStandaloneParagraphBlock')
    Assert-True ($paragraphActions.Count -ge 3) '일반 본문을 독립 문단 블록으로 분리'
    Assert-True (@($paragraphActions | Where-Object { $_.postcondition.paragraphBottomPx -ne 18 }).Count -eq 0) '일반 문단 뒤 18px 사후조건'
    Assert-True (@($paragraphActions | Where-Object { $_.formatting.fontFamily -ne '기본서체' -or $_.formatting.alignment -ne 'justify' -or $_.formatting.lastLineAlignment -ne 'left' }).Count -eq 0) '본문 기본서체·양쪽 정렬·마지막 줄 왼쪽 기준'
    Assert-True (@($paragraphActions | Where-Object { [bool]$_.formatting.bold -or -not [bool]$_.formatting.resetInlineFormattingBefore }).Count -eq 0) '본문마다 상속 굵기 제거 후 입력'
    Assert-True (@($headingActions | Where-Object { $_.fontFamily -ne '기본서체' }).Count -eq 0) '소제목 기본서체 기준'
    Assert-True (@($headingActions | Where-Object { -not [bool]$_.bold -or -not [bool]$_.resetInlineFormattingBefore }).Count -eq 0) '소제목마다 인라인 서식 초기화 후 굵기 적용'
    $calloutActions = @($plan.actions | Where-Object { $_.type -eq 'PasteRenderedAtomicBlock' -and $_.formatting.applyToCalloutBody })
    Assert-True ($calloutActions.Count -ge 1 -and @($calloutActions | Where-Object { $_.formatting.calloutBodyFontFamily -ne '기본서체' -or $_.formatting.calloutBodyAlignment -ne 'justify' -or -not $_.postcondition.requireCalloutBodyRightEdgeAlignment }).Count -eq 0) '강조 상자 본문 기본서체·양쪽 정렬 기준'
    Assert-True (@($calloutActions | Where-Object { [bool]$_.formatting.calloutBodyBold }).Count -eq 0) '강조 상자 본문 굵기 상속 차단'
    $audit = @($plan.actions | Where-Object type -eq 'VerifyWholeEditor')
    Assert-True ($audit.Count -eq 1 -and $audit[0].expectedHeadingCount -eq $headingActions.Count -and [bool]$audit[0].requireBodyBoldFalse -and [bool]$audit[0].rejectMergedHeadingBody) '종료 전 전체 문서 소제목·본문 굵기·합침 감사'
    Assert-True ([bool]$contract.guards.requireWholeEditorAuditBeforeStop -and [bool]$contract.guards.rejectInheritedBoldBody) '전체 감사와 굵기 상속 차단 실행 가드'
    Assert-True ([bool]$contract.guards.forbidGlobalMixedSelectionBoldToggle -and [bool]$contract.guards.requireExactParagraphSelection -and [bool]$contract.guards.requireSetStateNotToggle -and [bool]$contract.guards.requireToolbarPostconditionAfterEveryTextBlock) '문단별 멱등 서식 실행 가드'
    Assert-True ([bool]$contract.guards.preserveListedInlineBoldLabels) '육하원칙 등 부분 굵기 라벨 보존 가드'
    Assert-True ($contract.guards.browserBinding -eq 'ChromeDevToolsDedicatedProfile' -and [bool]$contract.guards.forbidWindowsAppWindowBinding -and [bool]$contract.guards.requireOuterAndInnerUrlMatch -and [bool]$contract.guards.requireSingleReusableEditorTab -and -not [bool]$contract.guards.computerUseUrlInspectionRequired -and [bool]$contract.guards.directCdpUrlVerificationRequired) 'Chrome 직접 연결·단일 편집 탭 재사용 가드'
    Assert-True ($contract.guards.selectionMode -eq 'NativeTripleClickRenderedParagraph' -and [bool]$contract.guards.forbidAccessibilitySelectText -and [bool]$contract.guards.requireRenderedDomPostcondition -and [bool]$contract.guards.rejectToolbarOnlyAudit) '실제 문단 선택·DOM 사후검증 가드'
    Assert-True ($contract.guards.requiredBodyFontClass -eq 'se-fs15' -and $contract.guards.forbiddenBodyFontClass -eq 'se-fs30' -and $contract.guards.requiredBodyBoldElementCount -eq 0 -and $contract.guards.maxRepairPasses -eq 2) '본문 글자 크기·굵기·복구 횟수 가드'
    $blockFiles = @(Get-ChildItem -LiteralPath (Join-Path $result.outputRoot 'blocks') -Filter '*.html')
    Assert-True ($blockFiles.Count -eq [int]$plan.atomicBlockCount -and $blockFiles.Count -gt 0) '원자 입력 블록 파일 수'
    $blockText = ($blockFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
    Assert-True ($blockText -notmatch 'data-naver-role="(?:section-heading|subheading)"') '본문 붙여넣기 블록에 소제목 미포함'
    $segmentText = (Get-ChildItem -LiteralPath (Join-Path $result.outputRoot 'segments') -Filter '*.html' | Sort-Object Name | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
    Assert-True ($segmentText -notmatch '<h[23]\b') '네이버 소제목을 안정적인 블록으로 변환'
    Assert-True ($segmentText -match 'data-naver-role="section-heading"') '소제목 역할 표식'
    Assert-True ($segmentText -match 'margin:32px 0 21px 0') 'H2 위·아래 여백 기준'
    Assert-True ($segmentText -match 'margin:24px 0 12px 0') 'H3 위·아래 여백 기준'
    Assert-True ($segmentText -match 'font-size:15px') '본문 15px 기준'
    Assert-True ($segmentText -match 'line-height:27px') '본문 27px 줄높이 기준'
    Assert-True ($segmentText -match 'line-height:24px') '바탕색 상자 24px 줄높이 기준'
    Assert-True ($segmentText -match 'margin:32px 0 0 0') '참고자료 위 32px 기준'
    Assert-True ($segmentText -match 'color:#4A78E0' -and $segmentText -notmatch 'text-decoration|border-bottom') 'H2 밝은 블루·밑줄 없음 기준'
    Assert-True ($segmentText -match '<table data-naver-role="reference-group" border="1" bordercolor="#CDD2D9"' -and ([regex]::Matches($segmentText, 'border:1px solid #CDD2D9')).Count -ge 2 -and $segmentText -match 'data-nte-reference-gap="true" style="display:block;height:6px;' -and $segmentText -notmatch 'aria-hidden="true"') '참고자료·관련 글 항상 표시되는 단일 무배경 회색 테두리 상자와 6px 내부 간격'
    $referenceGroupText = [regex]::Match($segmentText, '(?is)<table\s+data-naver-role="reference-group"[\s\S]*?</table>').Value
    Assert-True (([regex]::Matches($referenceGroupText, 'background:transparent;width:100%;box-sizing:border-box;')).Count -ge 2 -and $referenceGroupText -notmatch 'background-color:\s*#eef3fb|background-color:\s*#f8f9fa') '참고자료·관련 글 내부 색상 배경 제거'
    $tableActions = @($plan.actions | Where-Object blockRole -eq 'DataTable')
    Assert-True ($tableActions.Count -eq 1 -and [bool]$tableActions[0].postcondition.requireDirectlyBeforeHeadingWhenApplicable -and $tableActions[0].postcondition.maximumRenderedHeadingGapPx -eq 30) '표 다음 H2 실제 간격 30px 이하 실행 조건'
    $overviewActions = @($plan.actions | Where-Object blockRole -eq 'OverviewBox')
    Assert-True ($overviewActions.Count -eq 1 -and [bool]$overviewActions[0].postcondition.requireDirectlyBeforeHeadingWhenApplicable -and $overviewActions[0].postcondition.maximumRenderedHeadingGapPx -eq 30) '이 글에서 다루는 내용 상자 다음 H2 실제 간격 30px 이하 실행 조건'
    Assert-True ($segmentText -match '참고자료 :') '참고자료 표기 기준'
    Assert-True ($blockText -match 'text-align\s*:\s*justify' -and $blockText -match 'text-align-last\s*:\s*left') '본문 오른쪽 끝 양쪽 정렬과 마지막 줄 왼쪽 정렬'
    $promptPath = Join-Path $root '구글기반\프롬프트\02_최종_글쓰기_프롬프트.md'
    $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    foreach ($requiredPromptRule in @('InsertStandaloneHeading','InsertVerticalSpacer','PasteStandaloneParagraphBlock','H2는 19px','H3는 16px','각각 8px','줄높이 23px','H3는 22px','문단 뒤 18px','PasteRenderedSegment','data-reader-term','제목 바로 아래 이미지','밑줄 없음','표-다음 H2 30px 이하','참고자료-관련 글 6px','1px 연회색 외곽선','첫 번째 이미지에만 네이버 `대표` 지정')) {
        Assert-True ($promptText.Contains($requiredPromptRule)) "네이버 프롬프트 구조 규칙: $requiredPromptRule"
    }
    Assert-True ($promptText -match '(?i)text-align:\s*justify\s*;\s*text-align-last:\s*left') '프롬프트 본문 양쪽 정렬과 마지막 줄 왼쪽 정렬'
    Assert-True ($promptText -notmatch '<h[23][^>]+margin:\s*(?:35px\s+0\s+15px|20px\s+0\s+10px)') '프롬프트 소제목의 과거 여백 기준 제거'
    Assert-True (@([regex]::Matches($promptText, '<h2[^>]+font-size:\s*19px')).Count -ge 4) '프롬프트 H2 19px 기준'
    Assert-True (@([regex]::Matches($promptText, '<h3[^>]+font-size:\s*16px')).Count -ge 3) '프롬프트 H3 16px 기준'
    $after = Get-ChildItem -LiteralPath $source -File | Sort-Object Name | Get-FileHash -Algorithm SHA256
    Assert-True (($before.Hash -join '|') -eq ($after.Hash -join '|')) 'Google 입력 자료 무변경'
    Write-Output 'Google 기반 네이버 패키지 테스트 통과'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}

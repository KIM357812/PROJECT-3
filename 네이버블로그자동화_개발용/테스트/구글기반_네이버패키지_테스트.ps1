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
    $html = '<div style="width:100%;max-width:800px;margin:0 auto"><p style="font-size:16px;line-height:1.75;margin:0 0 18px 0;text-align:justify;text-align-last:left">도입 첫 문단</p><p style="font-size:16px;line-height:1.75;margin:0 0 18px 0;text-align:justify;text-align-last:left">도입 둘째 문단</p>' + $image + '<h2 style="font-size:22px;border-bottom:2px solid #000">현황</h2><div style="background:#eee"><p style="line-height:1.6;margin:0 0 8px 0;font-weight:700">강조 제목</p><p style="line-height:1.6">강조 본문</p></div>' + $image + '<h3>분석</h3>' + $image + '<p>전망</p>' + $image + '<div data-blog-sources="true" style="margin:20px 0"><p><strong>출처 :</strong> 링크</p></div></div>'
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
    Assert-True (@($plan.actions | Where-Object type -eq 'UploadImage').Count -eq 4) '이미지 삽입 동작 4개'
    Assert-True (@($plan.actions | Where-Object type -match 'Publish|Save').Count -eq 0) '공개·비공개 발행 동작 없음'
    Assert-True ($result.executionStatus -eq 'NotExecuted' -and -not [bool]$result.completionClaimAllowed) '실행 전 패키지를 완료로 표시하지 않음'
    Assert-True ($contract.executionMode -eq 'ComputerUseNewPostOnly') '컴퓨터 사용 새 글 전용 실행 계약'
    Assert-True ([bool]$contract.guards.existingPostModificationForbidden) '기존 글 수정 금지 실행 가드'
    Assert-True ([bool]$contract.guards.publicationSettingsForbidden -and [bool]$contract.guards.publicOrPrivatePublishForbidden) '발행 설정·게시 금지 실행 가드'
    Assert-True (@($contract.steps).Count -eq @($plan.actions).Count) '편집 계획 전체 동작이 실행 계약에 연결됨'
    Assert-True (@($contract.steps | Where-Object { -not $_.postcondition.stopImmediatelyOnMismatch }).Count -eq 0) '동작 불일치 즉시 중단'
    Assert-True (@($contract.steps | Where-Object { $_.action -eq 'InsertStandaloneHeading' -and -not $_.postcondition.requireIndependentEditorComponent }).Count -eq 0) '소제목 독립 구성요소 실행 조건'
    Assert-True (@($plan.reusedExistingNaverFeatures).Count -eq 3) '기존 네이버 이미지 기능만 재사용'
    Assert-True (@($plan.actions | Where-Object type -eq 'PasteRenderedSegment').Count -eq 0) '여러 제목·본문을 한 번에 붙여 넣는 구간 동작 금지'
    $headingActions = @($plan.actions | Where-Object type -eq 'InsertStandaloneHeading')
    Assert-True ($headingActions.Count -eq 2) 'H2·H3 독립 소제목 동작 수'
    Assert-True ($plan.headingInsertionMode -eq 'StandaloneParagraphWithMeasuredSpacers') '독립 소제목 삽입 모드'
    foreach ($headingAction in $headingActions) {
        $position = [array]::IndexOf(@($plan.actions), $headingAction)
        Assert-True ($position -gt 0 -and $position -lt (@($plan.actions).Count - 1)) '소제목 앞뒤 동작 존재'
        $beforeAction = @($plan.actions)[$position - 1]
        $afterHeading = @($plan.actions)[$position + 1]
        Assert-True ($beforeAction.type -eq 'InsertVerticalSpacer' -and $beforeAction.purpose -eq 'HeadingTop' -and $beforeAction.heightPx -eq 32) '소제목 위 독립 32px 간격'
        Assert-True ($afterHeading.type -eq 'InsertVerticalSpacer' -and $afterHeading.purpose -eq 'HeadingBottom' -and $afterHeading.heightPx -eq 21) '소제목 아래 독립 21px 간격'
        Assert-True ([bool]$headingAction.postcondition.requireStandaloneParagraph) '소제목 독립 문단 사후조건'
        Assert-True ([bool]$headingAction.postcondition.forbidMergedPreviousText -and [bool]$headingAction.postcondition.forbidMergedNextText) '소제목 앞뒤 본문 합침 금지'
    }
    $paragraphActions = @($plan.actions | Where-Object type -eq 'PasteStandaloneParagraphBlock')
    Assert-True ($paragraphActions.Count -ge 3) '일반 본문을 독립 문단 블록으로 분리'
    Assert-True (@($paragraphActions | Where-Object { $_.postcondition.paragraphBottomPx -ne 18 }).Count -eq 0) '일반 문단 뒤 18px 사후조건'
    Assert-True (@($paragraphActions | Where-Object { $_.formatting.fontFamily -ne '기본서체' -or $_.formatting.alignment -ne 'justify' -or $_.formatting.lastLineAlignment -ne 'left' }).Count -eq 0) '본문 기본서체·양쪽 정렬·마지막 줄 왼쪽 기준'
    Assert-True (@($headingActions | Where-Object { $_.fontFamily -ne '기본서체' }).Count -eq 0) '소제목 기본서체 기준'
    $calloutActions = @($plan.actions | Where-Object { $_.type -eq 'PasteRenderedAtomicBlock' -and $_.formatting.applyToCalloutBody })
    Assert-True ($calloutActions.Count -ge 1 -and @($calloutActions | Where-Object { $_.formatting.calloutBodyFontFamily -ne '기본서체' -or $_.formatting.calloutBodyAlignment -ne 'justify' -or -not $_.postcondition.requireCalloutBodyRightEdgeAlignment }).Count -eq 0) '강조 상자 본문 기본서체·양쪽 정렬 기준'
    $blockFiles = @(Get-ChildItem -LiteralPath (Join-Path $result.outputRoot 'blocks') -Filter '*.html')
    Assert-True ($blockFiles.Count -eq [int]$plan.atomicBlockCount -and $blockFiles.Count -gt 0) '원자 입력 블록 파일 수'
    $blockText = ($blockFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
    Assert-True ($blockText -notmatch 'data-naver-role="(?:section-heading|subheading)"') '본문 붙여넣기 블록에 소제목 미포함'
    $segmentText = (Get-ChildItem -LiteralPath (Join-Path $result.outputRoot 'segments') -Filter '*.html' | Sort-Object Name | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
    Assert-True ($segmentText -notmatch '<h[23]\b') '네이버 소제목을 안정적인 블록으로 변환'
    Assert-True ($segmentText -match 'data-naver-role="section-heading"') '소제목 역할 표식'
    Assert-True ($segmentText -match 'margin:32px 0 21px 0') '소제목 위·아래 여백 기준'
    Assert-True ($segmentText -match 'font-size:15px') '본문 15px 기준'
    Assert-True ($segmentText -match 'line-height:27px') '본문 27px 줄높이 기준'
    Assert-True ($segmentText -match 'line-height:24px') '바탕색 상자 24px 줄높이 기준'
    Assert-True ($segmentText -match 'margin:32px 0 0 0') '참고자료 위 32px 기준'
    Assert-True ($segmentText -match '참고자료 :') '참고자료 표기 기준'
    Assert-True ($blockText -match 'text-align\s*:\s*justify' -and $blockText -match 'text-align-last\s*:\s*left') '본문 오른쪽 끝 양쪽 정렬과 마지막 줄 왼쪽 정렬'
    $promptPath = Join-Path $root '구글기반\프롬프트\02_최종_글쓰기_프롬프트.md'
    $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    foreach ($requiredPromptRule in @('InsertStandaloneHeading','InsertVerticalSpacer','PasteStandaloneParagraphBlock','앞 32px','뒤 21px','문단 뒤 18px','PasteRenderedSegment')) {
        Assert-True ($promptText.Contains($requiredPromptRule)) "네이버 프롬프트 구조 규칙: $requiredPromptRule"
    }
    Assert-True ($promptText -match '(?i)text-align:\s*justify\s*;\s*text-align-last:\s*left') '프롬프트 본문 양쪽 정렬과 마지막 줄 왼쪽 정렬'
    Assert-True ($promptText -notmatch '<h[23][^>]+margin:\s*(?:35px\s+0\s+15px|20px\s+0\s+10px)') '프롬프트 소제목의 과거 여백 기준 제거'
    Assert-True (@([regex]::Matches($promptText, '<h[23][^>]+margin:\s*32px\s+0\s+21px')).Count -ge 7) '프롬프트 소제목 32px/21px 기준'
    $after = Get-ChildItem -LiteralPath $source -File | Sort-Object Name | Get-FileHash -Algorithm SHA256
    Assert-True (($before.Hash -join '|') -eq ($after.Hash -join '|')) 'Google 입력 자료 무변경'
    Write-Output 'Google 기반 네이버 패키지 테스트 통과'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}

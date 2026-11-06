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
    $html = '<div style="width:100%;max-width:800px;margin:0 auto"><p style="font-size:16px;line-height:1.75;margin:0 0 18px 0;text-align:justify;text-align-last:left">도입</p>' + $image + '<h2 style="font-size:22px;border-bottom:2px solid #000">현황</h2><div style="background:#eee"><p style="line-height:1.6;margin:0 0 8px 0;font-weight:700">강조 제목</p><p style="line-height:1.6">강조 본문</p></div>' + $image + '<h3>분석</h3>' + $image + '<p>전망</p>' + $image + '<div data-blog-sources="true" style="margin:20px 0"><p><strong>출처 :</strong> 링크</p></div></div>'
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
    Assert-True (@($plan.actions | Where-Object type -eq 'UploadImage').Count -eq 4) '이미지 삽입 동작 4개'
    Assert-True (@($plan.actions | Where-Object type -match 'Publish|Save').Count -eq 0) '공개·비공개 발행 동작 없음'
    Assert-True (@($plan.reusedExistingNaverFeatures).Count -eq 3) '기존 네이버 이미지 기능만 재사용'
    $segmentText = (Get-ChildItem -LiteralPath (Join-Path $result.outputRoot 'segments') -Filter '*.html' | Sort-Object Name | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
    Assert-True ($segmentText -notmatch '<h[23]\b') '네이버 소제목을 안정적인 블록으로 변환'
    Assert-True ($segmentText -match 'data-naver-role="section-heading"') '소제목 역할 표식'
    Assert-True ($segmentText -match 'margin:32px 0 21px 0') '소제목 위·아래 여백 기준'
    Assert-True ($segmentText -match 'font-size:15px') '본문 15px 기준'
    Assert-True ($segmentText -match 'line-height:27px') '본문 27px 줄높이 기준'
    Assert-True ($segmentText -match 'line-height:24px') '바탕색 상자 24px 줄높이 기준'
    Assert-True ($segmentText -match 'margin:32px 0 0 0') '참고자료 위 32px 기준'
    Assert-True ($segmentText -match '참고자료 :') '참고자료 표기 기준'
    Assert-True ($segmentText -notmatch 'text-align\s*:\s*justify') '모바일 본문 왼쪽 정렬'
    $after = Get-ChildItem -LiteralPath $source -File | Sort-Object Name | Get-FileHash -Algorithm SHA256
    Assert-True (($before.Hash -join '|') -eq ($after.Hash -join '|')) 'Google 입력 자료 무변경'
    Write-Output 'Google 기반 네이버 패키지 테스트 통과'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}

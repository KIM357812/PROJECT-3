$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '공통.ps1')
Add-Type -AssemblyName System.Drawing

function Assert([bool]$condition,[string]$message) { if (-not $condition) { throw "검증 실패: $message" } }
$run = New-RunDirectory '검증'
$results = New-Object System.Collections.Generic.List[string]

foreach ($name in @('프롬프트','프로그램','작업대기','작업완료','기록','설명서','백업','임시파일')) {
    Assert ([IO.Directory]::Exists((Join-Path $script:Root $name))) "폴더 $name"
}
$results.Add('폴더 자동 생성: 통과')

$stateRun=New-RunDirectory '글작성'
$state=[pscustomobject]@{Status='작성 중';UpdatedAt='';Completed=@();Failed=@([pscustomobject]@{Candidate=[pscustomobject]@{Number=1;Title='재시도 시험';Site='TechCrunch';Url='https://techcrunch.com/2026/09/30/retry-test/';Details='시험'};Message='의도한 시험 실패'})}
Save-RunState $stateRun $state
$state.Status='일부 실패';Save-RunState $stateRun $state
$loaded=Read-RunState $stateRun
Assert ($loaded.Status -eq '일부 실패' -and @($loaded.Failed).Count -eq 1) '작업상태 원자 저장·읽기'
Assert ((Get-LatestRetryableRun) -eq $stateRun) '최근 실패 작업 찾기'
$searchFailureRun=New-RunDirectory '글작성'
$searchFailureState=[pscustomobject]@{Status='실패';UpdatedAt='';Completed=@();Failed=@([pscustomobject]@{Candidate=$null;Message='소재 검색 시험 실패'})}
Save-RunState $searchFailureRun $searchFailureState
Assert ((Get-LatestRetryableRun) -eq $stateRun) '후보 없는 소재 검색 실패를 글 재시도에서 제외'
$results.Add('작업상태 저장·실패 재시도 대상 탐색: 통과')

$sample = @'
1번. 한글 소재 하나
사이트: TechCrunch
게시일: 2026-09-30
URL: https://techcrunch.com/2026/09/30/example-one/
선정 이유: 최신 기술 동향을 다룹니다.
주요 내용:
첫 번째 주요 사실입니다.
두 번째 주요 사실입니다.

2번. 한글 소재 둘
사이트: The Verge
게시일: 2026-09-30
URL: https://www.theverge.com/2026/09/30/example-two
선정 이유: 현장 적용 가능성을 살펴볼 수 있습니다.
주요 내용:
첫 번째 주요 사실입니다.
두 번째 주요 사실입니다.
'@
$candidates = @(Get-Candidates $sample)
Assert ($candidates.Count -eq 2) '소재 파싱'
Assert (@(Get-Selection '1' $candidates).Count -eq 1) '한 개 선택'
Assert (@(Get-Selection '1,2' $candidates).Count -eq 2) '여러 개 선택'
Assert (@(Get-Selection 'Canary Media 1,2' $candidates).Count -eq 2) '앞에 섞인 사이트명 제거'
Assert (@(Get-Selection '1;2;' $candidates).Count -eq 2) '세미콜론 입력 보정'
$results.Add('한 개·여러 개 소재 선택: 통과')

$articleUrl = 'https://techcrunch.com/2026/09/30/example-one/'
$imageStyle = 'width: 100%; max-width: 400px; height: auto; display: block; margin: 0 auto; border-radius: 4px;'
$firstImage = '<img src="placeholder" alt="첫 번째 시험 이미지" title="첫 번째 시험 이미지" width="800" height="120" style="'+$imageStyle+'" loading="eager" fetchpriority="high">'
$lazyImage = '<img src="placeholder" alt="시험 이미지 NUMBER" title="시험 이미지 NUMBER" width="800" height="120" style="'+$imageStyle+'" loading="lazy">'
$paragraphStyle = 'font-weight: 400; width: 100%; margin: 0 0 18px 0; line-height: 1.75; font-size: 16px; text-align: left; word-break: keep-all; overflow-wrap: anywhere; box-sizing: border-box;'
$filler = ('검증 가능한 기술 정보와 사업 조건을 독자가 추가 검색 없이 이해하도록 사실과 분석을 구분하여 설명합니다. ' * 6).Trim()
$html = @'
<div style="width: 100%; max-width: 800px; margin: 0 auto; padding: 20px; font-family: 'Apple SD Gothic Neo', 'Malgun Gothic', sans-serif; color: #222; box-sizing: border-box; clear: both;">
FIRST_IMAGE
<p style="PARAGRAPH_STYLE">FILLER <a href="ARTICLE_URL">중요한 원문 확인</a></p>
<h2>현황과 핵심 쟁점</h2>
LAZY_IMAGE_2
<p style="PARAGRAPH_STYLE">FILLER</p>
<h2>기술 원리와 도입 배경</h2>
<p style="PARAGRAPH_STYLE">FILLER</p>
<div style="font-weight: 400;"><strong>누가 (Who) : </strong>시험 기업<br><strong>무엇을 (What) : </strong>기술 검증<br><strong>언제 (When) : </strong>2026-09-30<br><strong>어디서 (Where) : </strong>시험 지역<br><strong>어떻게 (How) : </strong>검증 절차<br><strong>왜 (Why) : </strong>품질 향상</div>
<h2>시장 영향과 다음 단계</h2>
LAZY_IMAGE_3
<h3>사업화 조건</h3>
<p style="PARAGRAPH_STYLE">FILLER</p>
LAZY_IMAGE_4
<h3>종합 판단</h3>
<p style="PARAGRAPH_STYLE">FILLER</p>
<div style="background:#fff3e0"><p>다음 선택</p><p>이 기술을 장기적으로 도입할 때 가장 먼저 해결해야 할 비용과 인프라 문제는 무엇일까요?</p></div>
<div data-blog-sources="true"><p><strong>출처</strong></p><p><a href="ARTICLE_URL">TechCrunch</a></p></div>
</div>
'@
$html = $html.Replace('FIRST_IMAGE',$firstImage).Replace('LAZY_IMAGE_2',$lazyImage.Replace('NUMBER','2')).Replace('LAZY_IMAGE_3',$lazyImage.Replace('NUMBER','3')).Replace('LAZY_IMAGE_4',$lazyImage.Replace('NUMBER','4')).Replace('PARAGRAPH_STYLE',$paragraphStyle).Replace('FILLER',$filler).Replace('ARTICLE_URL',$articleUrl).Trim()
$promptTerms = 'photorealistic, realistic editorial photography, natural lighting, high detail, professional composition, textless, no text, no letters, no numbers, no watermark, no logo'
$metadata = @'
## 1. SEO 키워드 분석
- 메인 키워드: 기술 검증
- 핵심 키워드: 자동화, 사실검증, Blogger
- 서브 키워드: 이미지 SEO, 관련 글, 모바일 가독성
## 2. SEO 최적화 제목
최종 권장 제목: 기술 검증이 바꾸는 Blogger 자동화의 핵심
대체 제목 1: Blogger 자동화, 사실검증이 중요한 이유
대체 제목 2: 이미지와 출처까지 점검하는 기술 자동화
## 3. 메타 디스크립션
기술 검증과 사실 확인, 이미지 SEO, 관련 글 연결을 함께 적용해 Blogger 자동화 품질을 높이는 방법을 구체적으로 설명합니다.
## 4. 이미지 프롬프트 팩
### 1. 대표 썸네일
- 삽입 위치·역할: 도입부 대표 이미지
- 간략한 한글 장면 설명: 기술 검증 장면
- 핵심 시각 요소: 데이터센터와 전력 설비
- 권장 파일명: 01-blogger-automation.webp
- 상세 영문 프롬프트: PROMPT_TERMS
- 금지 요소: 잘못된 문자와 로고
### 2. 핵심 기술
- 삽입 위치·역할: 핵심 기술 이미지
- 간략한 한글 장면 설명: 검증 시스템
- 핵심 시각 요소: 서버와 검증 화면
- 권장 파일명: 02-fact-check-system.webp
- 상세 영문 프롬프트: PROMPT_TERMS
- 금지 요소: 잘못된 문자와 로고
### 3. 시장
- 삽입 위치·역할: 시장 분석 이미지
- 간략한 한글 장면 설명: 기술 시장 현장
- 핵심 시각 요소: 산업 설비와 전문가
- 권장 파일명: 03-technology-market.webp
- 상세 영문 프롬프트: PROMPT_TERMS
- 금지 요소: 잘못된 문자와 로고
### 4. 전망
- 삽입 위치·역할: 미래 전망 이미지
- 간략한 한글 장면 설명: 운영 개선 현장
- 핵심 시각 요소: 제어실과 운영자
- 권장 파일명: 04-future-operation.webp
- 상세 영문 프롬프트: PROMPT_TERMS
- 금지 요소: 잘못된 문자와 로고
## 5. 해시태그
기술검증, Blogger자동화, 사실검증, 이미지SEO
## 6. 내부 사실검증표
짧은 글 예외 사유: 해당 없음
기존 글 중복 점검: 중복 없음
### 검증 1
- 핵심 주장: 선택 기사 확인
- 구분: 원문 사실
- 확인 URL: https://techcrunch.com/2026/09/30/example-one/
- 확인일: 2026-11-05
- 검증 결과: 일치
- 정정 내용: 없음
### 검증 2
- 핵심 주장: 공식 보완 자료 확인
- 구분: 보완 자료
- 확인 URL: https://www.iea.org/reports/energy-and-ai
- 확인일: 2026-11-05
- 검증 결과: 일치
- 정정 내용: 없음
### 검증 3
- 핵심 주장: 작성자 분석 구분
- 구분: 작성자 분석
- 확인 URL: 해당 없음
- 확인일: 2026-11-05
- 검증 결과: 분석
- 정정 내용: 없음
'@
$metadata = $metadata.Replace('PROMPT_TERMS',$promptTerms)
$response = '```html'+"`n"+$html+"`n"+'```'+"`n`n"+$metadata
$article = Split-Article $response 'TechCrunch' $articleUrl
Assert ($article.ImagePrompts -match '4\. 전망') '이미지 프롬프트 분리'
Assert ($article.FactCheck -match '### 검증 3') '내부 사실검증표 분리'
Assert ($article.RecommendedTitle -eq '기술 검증이 바꾸는 Blogger 자동화의 핵심') '최종 권장 제목 분리'
Assert ($article.VisibleTextLength -ge 1300 -and $article.VisibleTextLength -le 4800) '본문 편집 기준 글자 수'
Assert (($article.ImageFiles -join ',') -eq '01-blogger-automation.webp,02-fact-check-system.webp,03-technology-market.webp,04-future-operation.webp') '이미지 SEO 파일명 분리'
Assert ($article.Html -match 'data-blog-sources="true"') '질문 아래 출처 영역'
Assert ([regex]::Matches($article.Html,'https://techcrunch\.com/2026/09/30/example-one/').Count -eq 2) '본문 링크와 출처 URL 일치'
try {
    $shortQuestion=$response.Replace('이 기술을 장기적으로 도입할 때 가장 먼저 해결해야 할 비용과 인프라 문제는 무엇일까요?','짧은 질문인가요?')
    Split-Article $shortQuestion 'TechCrunch' $articleUrl | Out-Null
    throw '내용이 부족한 짧은 질문을 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '45~90자') '질문 길이·한 문장 형식 검사' }
$officialUrl = 'https://www.iea.org/reports/energy-and-ai'
$companyUrl = 'https://www.proenergyservices.com/news/example-announcement'
$supportingSources = '>TechCrunch</a>, <a href="'+$officialUrl+'">International Energy Agency</a>, <a href="'+$companyUrl+'">PROENERGY</a></p>'
$multiSourceHtml = $html.Replace('>TechCrunch</a></p>',$supportingSources)
$multiSourceResponse = '```html'+"`n"+$multiSourceHtml+"`n"+'```'+"`n`n"+$metadata
$multiSourceArticle = Split-Article $multiSourceResponse 'TechCrunch' $articleUrl
Assert ([regex]::Matches($multiSourceArticle.Html,'(?is)<a\b[^>]*href=').Count -eq 4) '선택 기사와 서로 다른 공식 보조 출처 허용'
$relatedUrl = 'https://nexttechenergy.blogspot.com/2026/10/related-post.html'
$relatedBlock = '<div data-blog-related="true"><p>관련 글</p><p><a href="'+$relatedUrl+'">기술 자동화의 이전 분석</a></p></div>'
$sourceEnd = '<div data-blog-sources="true"><p><strong>출처</strong></p><p><a href="'+$articleUrl+'">TechCrunch</a></p></div>'
$relatedHtml = $html.Replace($sourceEnd+"`n</div>",$sourceEnd+"`n"+$relatedBlock+"`n</div>")
$relatedResponse = '```html'+"`n"+$relatedHtml+"`n"+'```'+"`n`n"+$metadata
$relatedArticle = Split-Article $relatedResponse 'TechCrunch' $articleUrl @($relatedUrl)
Assert ($relatedArticle.Html -match 'data-blog-related="true"') '관련 기존 글 선택 영역 허용'
$unlistedRelatedRejected = $false
try { [void](Split-Article $relatedResponse 'TechCrunch' $articleUrl @()) } catch { $unlistedRelatedRejected = $true }
Assert $unlistedRelatedRejected '공개 기존 글 목록에 없는 관련 링크 차단'
try {
    $badResponse=$response.Replace('<a href="'+$articleUrl+'">중요한 원문 확인</a>','<a href="https://example.com/not-listed">중요한 원문 확인</a>')
    Split-Article $badResponse 'TechCrunch' $articleUrl | Out-Null
    throw '출처에 없는 본문 URL을 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '하단 출처') '출처에 없는 본문 링크 차단' }
try {
    $extra='>TechCrunch</a>, <a href="https://example.com/two">Example Two</a>, <a href="https://example.com/three">Example Three</a>, <a href="https://example.com/four">Example Four</a></p>'
    $badResponse=$response.Replace('>TechCrunch</a></p>',$extra)
    Split-Article $badResponse 'TechCrunch' $articleUrl | Out-Null
    throw '출처 링크 4개를 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '1~3개') '출처 링크 최대 3개 제한' }
try {
    $vertical=$multiSourceResponse.Replace('</a>, <a href="'+$officialUrl+'">','</a></p><p><a href="'+$officialUrl+'">')
    Split-Article $vertical 'TechCrunch' $articleUrl | Out-Null
    throw '출처 세로 나열을 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '한 줄') '출처 한 줄·쉼표 구분 검사' }
try {
    $badResponse=$response.Replace('>TechCrunch</a>','>TechCrunch — Example One</a>')
    Split-Article $badResponse 'TechCrunch' $articleUrl | Out-Null
    throw '출처에 기사 제목 표시를 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '매체명·기관명만') '출처 화면에는 매체명·기관명만 허용' }
$results.Add('HTML·메타데이터·이미지 프롬프트 분리: 통과')

$baseShortHtml = $html.Replace($filler,'')
try {
    $tooShortResponse='```html'+"`n"+$baseShortHtml+"`n"+'```'+"`n`n"+$metadata
    Split-Article $tooShortResponse 'TechCrunch' $articleUrl | Out-Null
    throw '1,000자 미만 글을 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '1,000~4,800자') '1,000자 미만 차단' }
$baseLength=(Get-ArticleVisibleText $baseShortHtml).Length
$targetLength=1150
$padding='가' * [Math]::Max(1,($targetLength-$baseLength))
$exceptionHtml=$baseShortHtml.Replace('중요한 원문 확인',($padding+' 중요한 원문 확인'))
$exceptionMetadata=$metadata.Replace('짧은 글 예외 사유: 해당 없음','짧은 글 예외 사유: 원문 정보가 제한되어 반복 없이 핵심 기술과 사업 조건만 완결성 있게 설명함')
$exceptionResponse='```html'+"`n"+$exceptionHtml+"`n"+'```'+"`n`n"+$exceptionMetadata
$exceptionArticle=Split-Article $exceptionResponse 'TechCrunch' $articleUrl
Assert ($exceptionArticle.VisibleTextLength -ge 1000 -and $exceptionArticle.VisibleTextLength -lt 1300) '1,000~1,299자 사유 있는 예외 허용'
try {
    $badLoading=$response.Replace('loading="eager" fetchpriority="high"','loading="lazy"')
    Split-Article $badLoading 'TechCrunch' $articleUrl | Out-Null
    throw '대표 이미지 lazy 로딩을 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '첫 번째 대표 이미지') '대표 이미지 eager·우선순위 검사' }
try {
    $badTitle=$response.Replace('최종 권장 제목: 기술 검증이 바꾸는 Blogger 자동화의 핵심','최종 권장 제목: 전혀 관계없는 요리와 여행 이야기')
    Split-Article $badTitle 'TechCrunch' $articleUrl | Out-Null
    throw '본문과 무관한 제목을 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '제목이 본문 핵심') '최종 제목과 본문 핵심 일치 검사' }
$results.Add('글자 수 예외·대표 이미지 성능·제목 일치 자동 검증: 통과')

$saved = Save-Article ([PSCustomObject]@{ Number=99; Title='검증용 한글 소재'; Site='TechCrunch'; Url=$articleUrl }) $article
foreach ($name in @('본문.html','Blogger에_붙여넣을_본문.html','메타데이터.txt','사실검증표.md','이미지_프롬프트.txt','이미지_생성용_전체프롬프트.txt','Gemini_이미지_01.txt','Gemini_이미지_02.txt','Gemini_이미지_03.txt','Gemini_이미지_04.txt')) {
    Assert ([IO.File]::Exists((Join-Path $saved $name))) "결과 파일 $name"
}
Assert ([IO.File]::ReadAllText((Join-Path $saved '메타데이터.txt'),[Text.Encoding]::UTF8).StartsWith('## 1. SEO 키워드 분석')) '분리 저장'
$bloggerHtml = [IO.File]::ReadAllText((Join-Path $saved 'Blogger에_붙여넣을_본문.html'),[Text.Encoding]::UTF8)
Assert ($bloggerHtml -match '(?is)\A<div style="width: 100%; max-width: 800px; margin: 0 auto; padding: 20px; font-family:') 'Blogger 본문 최대 800px·가운데 정렬·기존 디자인 유지'
Assert ([regex]::Matches($bloggerHtml,'(?is)<img\b[^>]*max-width:\s*400px[^>]*>').Count -eq 4) 'Blogger 이미지 최대 400px·모바일 자동 조절'
Assert ((Get-BloggerHostedImageCount $saved) -eq 0) '업로드 전에는 Blogger 실제 이미지 주소 없음'
foreach ($name in @('본문.html','사실검증표.md','이미지_프롬프트.txt','이미지_생성용_전체프롬프트.txt','작업정보.json')) {
    Assert (([IO.File]::GetAttributes((Join-Path $saved $name)) -band [IO.FileAttributes]::Hidden) -ne 0) "내부 파일 숨김 $name"
}
Assert (([IO.File]::GetAttributes((Join-Path $saved 'Blogger에_붙여넣을_본문.html')) -band [IO.FileAttributes]::Hidden) -eq 0) 'Blogger 게시용 본문 표시'
foreach ($number in 1..4) {
    $single = [IO.File]::ReadAllText((Join-Path $saved ('Gemini_이미지_{0:D2}.txt' -f $number)),[Text.Encoding]::UTF8)
    Assert ([regex]::Matches($single,'(?m)^###\s*[1-4]\.').Count -eq 1) "Gemini 이미지 $number 개별 분리"
}
$results.Add('Blogger 게시용 본문 표시·800px 본문·400px 이미지: 통과')

$testFolder = $saved
Assert ([IO.File]::ReadAllText((Join-Path $testFolder '본문.html'),[Text.Encoding]::UTF8).Contains('placeholder')) 'UTF-8 저장'
$results.Add('한글 파일명·UTF-8: 통과')

try { Split-Article '형식 오류' 'TechCrunch' $articleUrl | Out-Null; throw '형식 오류를 통과시켰습니다.' } catch {
    Assert ($_.Exception.Message -match '분리되지 않았습니다') '오류 안전 중단'
    Write-ErrorLog '샘플 검증: 의도한 형식 오류를 안전하게 차단함'
}
$results.Add('형식 오류 안전 중단: 통과')

for ($i=1; $i -le 4; $i++) {
    $bitmap = New-Object Drawing.Bitmap(1800,900)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try { $graphics.Clear([Drawing.Color]::FromArgb(40*$i,60,100)) ; $bitmap.Save((Join-Path $testFolder ('원본이미지\{0:D2}.png' -f $i)),[Drawing.Imaging.ImageFormat]::Png) }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
}
$three = @(Get-ChildItem -LiteralPath (Join-Path $testFolder '원본이미지') -File | Sort-Object Name | Select-Object -First 3)
try {
    $shortFolder = Join-Path $run '부족_검증'
    [IO.Directory]::CreateDirectory($shortFolder) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $shortFolder '원본이미지')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $shortFolder '압축이미지')) | Out-Null
    foreach ($file in $three) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $shortFolder '원본이미지') }
    Process-Images $shortFolder | Out-Null
    throw '이미지 부족을 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '부족 1장') '이미지 부족 정확한 알림' }
$results.Add('이미지 부족 안전 중단: 통과')
$before = @(Get-ChildItem -LiteralPath (Join-Path $testFolder '원본이미지') -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
$destination = Process-Images $testFolder
$outputs = @(Get-ChildItem -LiteralPath $destination -File -Filter '*.webp' | Sort-Object Name)
Assert ($outputs.Count -eq 4) 'WebP 네 장'
Assert (($outputs | ForEach-Object Name) -join ',' -eq '01-blogger-automation.webp,02-fact-check-system.webp,03-technology-market.webp,04-future-operation.webp') '설명형 이미지 파일명과 순서'
$after = @(Get-ChildItem -LiteralPath (Join-Path $testFolder '원본이미지') -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
Assert (($before -join ',') -eq ($after -join ',')) '원본 보존'
Assert ([IO.File]::Exists((Join-Path $testFolder '미리보기.html'))) '로컬 미리보기 생성'
Assert (([IO.File]::GetAttributes((Join-Path $testFolder '미리보기.html')) -band [IO.FileAttributes]::Hidden) -ne 0) '미리보기 내부 파일 숨김'
$preview=[IO.File]::ReadAllText((Join-Path $testFolder '미리보기.html'),[Text.Encoding]::UTF8)
foreach($name in @($article.ImageFiles)){Assert ($preview -match [regex]::Escape(('압축이미지/'+$name))) "미리보기 이미지 $name 연결"}
Assert ([IO.Directory]::Exists((Join-Path (Get-ArticleBackupPath $testFolder) '원본이미지'))) '원본 이미지 백업'
Assert (@(Get-ChildItem -LiteralPath $script:TemporaryDir -Directory).Count -eq 0) '성공한 이미지 변환 임시 폴더 정리'
$results.Add('이미지 4장 WebP 변환·순서·원본 보존·백업·미리보기: 통과')

# 검증 중 의도적으로 만든 실패 상태가 실제 직원용 '최근 실패 작업 재시도'에
# 섞이지 않도록 시험 작업을 완료 상태로 정리한다.
$state.Status = '검증 완료'
$state.Failed = @()
Save-RunState $stateRun $state
$searchFailureState.Status = '검증 완료'
$searchFailureState.Failed = @()
Save-RunState $searchFailureRun $searchFailureState

$testBackup = Get-ArticleBackupPath $testFolder
if ([IO.Directory]::Exists($testFolder)) { Remove-Item -LiteralPath $testFolder -Recurse -Force }
if ([IO.Directory]::Exists($testBackup)) { Remove-Item -LiteralPath $testBackup -Recurse -Force }
$results.Add('검증용 결과 파일 정리: 통과')
$report = ($results.ToArray() -join "`n")+"`n"
[IO.File]::WriteAllText((Join-Path $run '검증결과.txt'),$report,$script:Utf8)
Write-Output $report

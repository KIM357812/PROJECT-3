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
$html = '<div style="max-width: 800px; margin: 0 auto; padding: 20px; box-sizing: border-box;">'+"`n"+(('<img src="placeholder">'+"`n")*4)+'<p><a href="'+$articleUrl+'">중요한 원문 확인</a></p>'+"`n"+'<div style="background:#fff3e0"><p>독자 질문입니까?</p></div>'+"`n"+'<div data-blog-sources="true"><p><strong>출처</strong></p><p><a href="'+$articleUrl+'">TechCrunch — Example One</a></p></div>'+"`n"+'</div>'
$metadata = @'
## 1. SEO 키워드 분석
키워드
## 2. SEO 최적화 제목
제목
## 3. 메타 디스크립션
설명
## 4. 이미지 프롬프트 팩
### 1. 대표 썸네일
- 상세 영문 프롬프트: photorealistic
### 2. 핵심 기술
- 상세 영문 프롬프트: photorealistic
### 3. 시장
- 상세 영문 프롬프트: photorealistic
### 4. 전망
- 상세 영문 프롬프트: photorealistic
## 5. 해시태그
태그
'@
$response = '```html'+"`n"+$html+"`n"+'```'+"`n`n"+$metadata
$article = Split-Article $response 'TechCrunch' $articleUrl
Assert ($article.ImagePrompts -match '4\. 전망') '이미지 프롬프트 분리'
Assert ($article.Html -match 'data-blog-sources="true"') '질문 아래 출처 영역'
Assert ([regex]::Matches($article.Html,'https://techcrunch\.com/2026/09/30/example-one/').Count -eq 2) '본문 링크와 출처 URL 일치'
$officialUrl = 'https://www.iea.org/reports/energy-and-ai'
$companyUrl = 'https://www.proenergyservices.com/news/example-announcement'
$supportingSources = '<p><a href="'+$officialUrl+'">IEA — Energy and AI</a></p><p><a href="'+$companyUrl+'">PROENERGY — Example Announcement</a></p>'
$multiSourceHtml = $html.Replace('</div>'+"`n"+'</div>',$supportingSources+'</div>'+"`n"+'</div>')
$multiSourceResponse = '```html'+"`n"+$multiSourceHtml+"`n"+'```'+"`n`n"+$metadata
$multiSourceArticle = Split-Article $multiSourceResponse 'TechCrunch' $articleUrl
Assert ([regex]::Matches($multiSourceArticle.Html,'(?is)<a\b[^>]*href=').Count -eq 4) '선택 기사와 서로 다른 공식 보조 출처 허용'
try {
    $badResponse=$response.Replace('<p><a href="'+$articleUrl+'">중요한 원문 확인</a></p>','<p><a href="https://example.com/not-listed">중요한 원문 확인</a></p>')
    Split-Article $badResponse 'TechCrunch' $articleUrl | Out-Null
    throw '출처에 없는 본문 URL을 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '하단 출처') '출처에 없는 본문 링크 차단' }
try {
    $extra='<p><a href="https://example.com/two">Example — Two</a></p><p><a href="https://example.com/three">Example — Three</a></p><p><a href="https://example.com/four">Example — Four</a></p>'
    $badResponse=$response.Replace('</div>'+"`n"+'</div>',$extra+'</div>'+"`n"+'</div>')
    Split-Article $badResponse 'TechCrunch' $articleUrl | Out-Null
    throw '출처 링크 4개를 통과시켰습니다.'
} catch { Assert ($_.Exception.Message -match '1~3개') '출처 링크 최대 3개 제한' }
$results.Add('HTML·메타데이터·이미지 프롬프트 분리: 통과')

$saved = Save-Article ([PSCustomObject]@{ Number=99; Title='검증용 한글 소재'; Site='TechCrunch'; Url=$articleUrl }) $article
foreach ($name in @('본문.html','Blogger에_붙여넣을_본문.html','메타데이터.txt','이미지_프롬프트.txt','이미지_생성용_전체프롬프트.txt','Gemini_이미지_01.txt','Gemini_이미지_02.txt','Gemini_이미지_03.txt','Gemini_이미지_04.txt')) {
    Assert ([IO.File]::Exists((Join-Path $saved $name))) "결과 파일 $name"
}
Assert ([IO.File]::ReadAllText((Join-Path $saved '메타데이터.txt'),[Text.Encoding]::UTF8).StartsWith('## 1. SEO 키워드 분석')) '분리 저장'
Assert ([IO.File]::ReadAllText((Join-Path $saved '본문.html'),[Text.Encoding]::UTF8) -eq [IO.File]::ReadAllText((Join-Path $saved 'Blogger에_붙여넣을_본문.html'),[Text.Encoding]::UTF8)) 'Blogger 붙여넣기용 본문 동일성'
foreach ($number in 1..4) {
    $single = [IO.File]::ReadAllText((Join-Path $saved ('Gemini_이미지_{0:D2}.txt' -f $number)),[Text.Encoding]::UTF8)
    Assert ([regex]::Matches($single,'(?m)^###\s*[1-4]\.').Count -eq 1) "Gemini 이미지 $number 개별 분리"
}
$results.Add('글별 폴더·결과 파일 저장: 통과')

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
Assert (($outputs | ForEach-Object Name) -join ',' -eq '01.webp,02.webp,03.webp,04.webp') '이미지 순서'
$after = @(Get-ChildItem -LiteralPath (Join-Path $testFolder '원본이미지') -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
Assert (($before -join ',') -eq ($after -join ',')) '원본 보존'
Assert ([IO.File]::Exists((Join-Path $testFolder '미리보기.html'))) '로컬 미리보기 생성'
$preview=[IO.File]::ReadAllText((Join-Path $testFolder '미리보기.html'),[Text.Encoding]::UTF8)
foreach($number in 1..4){Assert ($preview -match ('압축이미지/{0:D2}\.webp' -f $number)) "미리보기 이미지 $number 연결"}
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

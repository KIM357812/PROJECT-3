$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '공통.ps1')
. (Join-Path $PSScriptRoot '후보준비.ps1')
$script:Checks=0
function Assert([bool]$ok,[string]$message) {
    if (-not $ok) { throw "파싱 시험 실패: $message" }
    $script:Checks++
}
$url='https://techcrunch.com/2026/09/29/tesla-secures-30b-in-new-credit-lines-as-it-looks-to-scale-cybercab-optimus/'
$sample=@'
1번. 시험 기사
사이트: TechCrunch
게시일: 2026-09-29
URL: ARTICLE_URL
선정 이유: 기술의 현장 적용을 설명합니다.
주요 내용:
첫 번째 한국어 주요 내용입니다.
두 번째 한국어 주요 내용입니다.
'@.Replace('ARTICLE_URL',$url)
foreach($link in @($url, "[$url]($url)", "[기사 원문]($url)", "<$url>", ('`'+$url+'`'))) {
    $parsed=@(Get-Candidates $sample.Replace($url,$link))
    Assert ($parsed.Count -eq 1 -and $parsed[0].Url -eq $url) "URL 형식: $link"
}
foreach($header in @('1번. 시험 기사','1. 시험 기사','1) 시험 기사','## **1번. 시험 기사**')) {
    Assert (@(Get-Candidates $sample.Replace('1번. 시험 기사',$header)).Count -eq 1) "번호 형식: $header"
}
foreach($title in @("1번. [시험 기사]($url)","1번. 시험 기사 $url")) {
    $text=$sample.Replace('1번. 시험 기사',$title).Replace("URL: $url`n",'').Replace("URL: $url`r`n",'')
    $parsed=@(Get-Candidates $text)
    Assert ($parsed.Count -eq 1 -and $parsed[0].Title -eq '시험 기사' -and $parsed[0].Url -eq $url) '제목 URL 추출 및 제목 정리'
}
$bold=$sample.Replace('사이트:', '- **사이트명:**').Replace('게시일:', '**게시일:**').Replace('URL:', '**최종 원문 URL:**').Replace('선정 이유:', '**선정 이유:**').Replace('주요 내용:', '**주요 내용:**')
Assert (@(Get-Candidates $bold).Count -eq 1) '강조 및 필드 이름 변형'
foreach($bad in @(
    'https://example.com/story', 'https://techcrunch.com.evil.test/2026/09/29/story',
    'https://evil.techcrunch.com/2026/09/29/story', 'http://techcrunch.com/2026/09/29/story',
    'https://techcrunch.com/', 'https://techcrunch.com/category/ai', 'https://techcrunch.com/search?q=ai',
    'https://techcrunch.com/2026/09/29/story?utm_source=test', 'https://techcrunch.com/2026/09/29/story#ref',
    'https://user@techcrunch.com/2026/09/29/story', 'https://techcrunch.com:8443/2026/09/29/story',
    'https://techcrunch.com/2026/09/29/photo.jpg', "[$url](https://example.com/story)"
)) {
    Assert (@(Get-Candidates $sample.Replace($url,$bad)).Count -eq 0) "부적합 URL 차단: $bad"
}
Assert (@(Get-Candidates $sample.Replace("URL: $url","URL: $url https://techcrunch.com/2026/09/29/another")).Count -eq 0) '모호한 URL 2개 차단'
Assert (@(Get-Candidates $sample.Replace('1번. 시험 기사',"1번. [시험 기사]($url)").Replace("URL: $url",'URL: https://example.com/story')).Count -eq 0) '잘못된 명시 URL을 제목 URL로 대체하지 않음'
Assert (@(Get-Candidates $sample.Replace('TechCrunch','Electrek')).Count -eq 0) '사이트 불일치 차단'
Assert (@(Get-Candidates $sample.Replace('2026-09-29','2026-02-30')).Count -eq 0) '존재하지 않는 날짜 차단'
Assert (@(Get-Candidates $sample.Replace('사이트: TechCrunch','')).Count -eq 0) '사이트 필수'
Assert (@(Get-Candidates $sample.Replace('선정 이유: 기술의 현장 적용을 설명합니다.','')).Count -eq 0) '선정 이유 필수'
Assert (@(Get-Candidates $sample.Replace('두 번째 한국어 주요 내용입니다.','')).Count -eq 0) '요약 1줄 차단'
Assert (@(Get-Candidates ($sample+"`n세 번째 내용입니다.`n네 번째 내용입니다.")).Count -eq 0) '요약 4줄 차단'
Assert (@(Get-Candidates $sample.Replace('두 번째 한국어 주요 내용입니다.','English only.')).Count -eq 0) '영어만 있는 요약 차단'
Assert (@(Get-Candidates ($sample+"`n`n"+$sample)).Count -eq 0) '중복 번호 차단'
$other=$sample.Replace('1번.','2번.').Replace($url,'https://techcrunch.com/2026/09/29/second-article/')
$parsed=@(Get-Candidates ($sample+"`n`n"+$other+"`n`nSpaceNews`n미확보: 2건`n확보 결과: 총 2/16건"))
Assert ($parsed.Count -eq 2) '마지막 소재 뒤 안내를 요약에서 분리'
$display=Format-CandidateList $parsed
Assert ([regex]::Matches($display,"`n`n").Count -eq 1 -and $display -notmatch "`n{3}") '소재 사이 빈 줄 정확히 1줄'
Assert (@(Get-Selection '1' $parsed).Count -eq 1) '단일 번호 선택'
Assert (@(Get-Selection '1,2' $parsed).Count -eq 2) '복수 번호 선택'
Assert (@(Get-Selection '2,2' $parsed).Count -eq 1) '선택 번호 중복 제거'
foreach($badSelection in @('3','1,9','abc')) {
    $rejected=$false
    try { $null=Get-Selection $badSelection $parsed } catch { $rejected=$true }
    Assert $rejected "잘못된 선택: $badSelection"
}
Assert ($script:MaximumCandidates -eq 16) '전체 소재 최대 16건 설정'
Assert ($script:MaximumCandidatesPerSite -eq 2) '사이트별 소재 최대 2건 설정'
Assert ($parsed[0].Url.EndsWith('/')) '최종 원문 URL의 끝 슬래시 보존'
foreach($listUrl in @('https://www.canarymedia.com/articles','https://www.canarymedia.com/articles/geothermal','https://www.space.com/space-exploration','https://www.space.com/space-exploration/launches-spacecraft')) {
    Assert (-not (Get-ArticleSite $listUrl)) "기사처럼 보이는 목록 경로 차단: $listUrl"
}
Write-Output ("파싱 단위 테스트 통과: {0}개 검증" -f $script:Checks)

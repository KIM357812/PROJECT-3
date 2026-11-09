#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root '프로그램\관련글선정.ps1')

function Assert-True([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "관련 글 검증 실패: $Message" }
}
function New-Post([string]$Title,[string]$LogNo,[DateTimeOffset]$Published,[string[]]$Labels,[string]$Content,[string[]]$RelatedUrls=@(),[string]$BlogId='ij1128') {
    [pscustomobject]@{Title=$Title;Url="https://blog.naver.com/$BlogId/$LogNo";Published=$Published.ToString('o');Labels=$Labels;Content=$Content;RelatedUrls=$RelatedUrls}
}

$now = [DateTimeOffset]::Parse('2026-11-09T12:00:00+09:00')
$posts = @(
    (New-Post 'AI 데이터센터 전력망 배터리 비용 구조' '101' $now.AddDays(-20) @('AI','데이터센터','전력망') '배터리와 전력 비용을 분석한다.'),
    (New-Post 'AI 데이터센터 전력망 투자' '102' $now.AddDays(-1) @('AI') '데이터센터 전력망 투자 분석'),
    (New-Post 'AI 데이터센터 전력망 정책' '103' $now.AddDays(-2) @('AI','전력망') '데이터센터 전력망 정책과 비용'),
    (New-Post 'AI 데이터센터 전력망 미래 글' '104' $now.AddDays(1) @('AI','전력망') '미래 게시물'),
    (New-Post 'AI 데이터센터 전력망 오래된 글' '105' $now.AddDays(-61) @('AI','전력망') '오래된 게시물'),
    (New-Post 'AI 데이터센터 전력망 다른 블로그' '106' $now.AddDays(-3) @('AI','전력망') '다른 블로그' @() 'someoneelse'),
    (New-Post '현재 작성 글' '999' $now.AddDays(-1) @('AI') '현재 글'),
    (New-Post '완전히 다른 생활 소식' '107' $now.AddDays(-1) @('AI') '일상과 여행'),
    (New-Post 'AI 데이터센터 전력 비용 점검' '108' $now.AddDays(-4) @('AI','데이터센터') '전력망 배터리 비용 점검')
)
$selected = @(Select-NaverRelatedPosts -CurrentTitle 'AI 데이터센터 전력망 배터리 분석' -CurrentSummary '데이터센터 전력망과 배터리 비용을 설명한다.' -CurrentLabels @('AI','데이터센터','전력망') -CurrentUrl 'https://blog.naver.com/ij1128/999' -ScheduledAt $now -Posts $posts)
Assert-True ($selected.Count -eq 3) '관련 후보 최대 3개'
Assert-True ($selected[0].Url -eq 'https://blog.naver.com/ij1128/101') '최신 날짜보다 관련성 우선'
Assert-True ($selected.Url -notcontains 'https://blog.naver.com/ij1128/104') '미래 게시물 제외'
Assert-True ($selected.Url -notcontains 'https://blog.naver.com/ij1128/105') '60일 초과 게시물 제외'
Assert-True ($selected.Url -notcontains 'https://blog.naver.com/ij1128/999') '현재 글 자신 제외'
Assert-True ($selected.Url -notcontains 'https://blog.naver.com/someoneelse/106') '다른 블로그 제외'
Assert-True ($selected.Url -notcontains 'https://blog.naver.com/ij1128/107') '태그 하나만 같은 무관한 글 제외'
$deduplicated = @(Select-NaverRelatedPosts -CurrentTitle 'AI 데이터센터 전력망 배터리 분석' -CurrentSummary '배터리 비용' -CurrentLabels @('AI') -ScheduledAt $now -Posts @($posts[0],$posts[0],(New-Post $posts[0].Title '109' $now.AddDays(-3) @('AI','전력망') '중복 제목')))
Assert-True ($deduplicated.Count -eq 1) '동일 URL과 동일 제목 중복 제거'

$few = @(Select-NaverRelatedPosts -CurrentTitle 'AI 데이터센터 전력망 배터리 분석' -CurrentSummary '배터리 비용' -CurrentLabels @('AI') -ScheduledAt $now -Posts @($posts[0],$posts[7]))
Assert-True ($few.Count -eq 1) '후보가 한 건이면 한 건만 표시'
$none = @(Select-NaverRelatedPosts -CurrentTitle '양자 바이오 의료 연구' -CurrentSummary '신약 후보' -CurrentLabels @('바이오') -ScheduledAt $now -Posts $posts)
Assert-True ($none.Count -eq 0) '후보가 없으면 빈 결과'

$repeatPosts = @(
    (New-Post 'AI 전력망 배터리 운영 기준' '201' $now.AddDays(-5) @('AI','전력망') '배터리 운영 기준'),
    (New-Post 'AI 전력망 배터리 운영 원칙' '202' $now.AddDays(-5) @('AI','전력망') '배터리 운영 기준'),
    (New-Post '반복 기록 하나' '290' $now.AddDays(-3) @('기록') '과거 관련 링크' @('https://blog.naver.com/ij1128/201')),
    (New-Post '반복 기록 둘' '291' $now.AddDays(-2) @('기록') '과거 관련 링크' @('https://blog.naver.com/ij1128/201'))
)
$repeatSelected = @(Select-NaverRelatedPosts -CurrentTitle 'AI 전력망 배터리 운영 분석' -CurrentSummary '배터리 운영 기준' -CurrentLabels @('AI','전력망') -ScheduledAt $now -Posts $repeatPosts)
Assert-True ($repeatSelected[0].Url -eq 'https://blog.naver.com/ij1128/202') '반복 사용 링크 감점'
Assert-True ($repeatSelected[0].RepeatCount -eq 0 -and @($repeatSelected | Where-Object Url -eq 'https://blog.naver.com/ij1128/201')[0].RepeatCount -eq 2) '반복 횟수 계산'

$comboPosts = @(
    (New-Post 'AI 데이터센터 전력망 비용 분석' '301' $now.AddDays(-8) @('AI','전력망') '데이터센터 비용 분석'),
    (New-Post 'AI 데이터센터 전력망 투자 분석' '302' $now.AddDays(-7) @('AI','전력망') '데이터센터 투자 분석'),
    (New-Post 'AI 데이터센터 전력망 정책 분석' '303' $now.AddDays(-6) @('AI','전력망') '데이터센터 정책 분석'),
    (New-Post 'AI 데이터센터 전력 운영 점검' '304' $now.AddDays(-5) @('AI','전력망') '데이터센터 전력 운영 분석'),
    (New-Post '이전 조합 기록' '390' $now.AddDays(-1) @('기록') '과거 조합' @('https://blog.naver.com/ij1128/301','https://blog.naver.com/ij1128/302','https://blog.naver.com/ij1128/303'))
)
$comboSelected = @(Select-NaverRelatedPosts -CurrentTitle 'AI 데이터센터 전력망 분석' -CurrentSummary '전력망 비용 투자 정책 운영' -CurrentLabels @('AI','전력망') -ScheduledAt $now -Posts $comboPosts)
$comboKey = @($comboSelected.Url | Sort-Object) -join '|'
$oldKey = @('https://blog.naver.com/ij1128/301','https://blog.naver.com/ij1128/302','https://blog.naver.com/ij1128/303' | Sort-Object) -join '|'
Assert-True ($comboSelected.Count -eq 3 -and $comboKey -ne $oldKey) '동일 세 링크 조합을 충분히 관련된 차순위로 교체'

$unrelatedReplacementPosts = @(
    $comboPosts[0],$comboPosts[1],$comboPosts[2],$comboPosts[4],
    (New-Post '여행 식당 추천' '305' $now.AddDays(-4) @('여행') '맛집과 관광')
)
$unrelatedSelected = @(Select-NaverRelatedPosts -CurrentTitle 'AI 데이터센터 전력망 분석' -CurrentSummary '전력망 비용 투자 정책 운영' -CurrentLabels @('AI','전력망') -ScheduledAt $now -Posts $unrelatedReplacementPosts)
Assert-True ($unrelatedSelected.Url -notcontains 'https://blog.naver.com/ij1128/305') '무관한 대체 후보를 억지로 사용하지 않음'

$withRelated = '<div><div data-blog-sources="true"><p><strong>참고자료 :</strong> 링크</p></div><div data-blog-related="true"><p>관련 글</p><p><a href="https://old.example/">기존 링크</a></p></div></div>'
$without = Set-NaverRelatedPostsHtml $withRelated @()
Assert-True ($without -notmatch 'data-blog-related|관련 글|old\.example') '관련 글이 없으면 영역 전체 제거'
$rendered = Set-NaverRelatedPostsHtml $withRelated @($selected[0],$selected[1])
Assert-True ([regex]::Matches($rendered,'data-blog-related="true"').Count -eq 1) '관련 글 영역 한 번만 출력'
Assert-True ([regex]::Matches($rendered,'<a href=').Count -eq 2) '선정된 수만큼 제목 링크 출력'
Assert-True ((ConvertTo-RelatedPlainText $rendered) -notmatch 'https?://|www\.') 'URL 문자열 화면 노출 금지'
Assert-True ($rendered -match [regex]::Escape($selected[0].Title)) '실제 제목과 링크 표시'

Write-Output 'Naver related-post selection tests passed.'

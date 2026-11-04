$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '공통.ps1')

$sample = @'
1번. 첫 번째 기사
사이트: TechCrunch
게시일: 2026-09-30
URL: https://techcrunch.com/2026/09/30/first-article/
선정 이유: 새 기술의 현장 적용 사례로 블로그 독자에게 유용합니다.
주요 내용:
첫 번째 핵심 사실입니다.
두 번째 핵심 사실입니다.

2번. 두 번째 기사
사이트: The Verge
게시일: 게시일 확인 불가
URL: https://www.theverge.com/2026/09/30/second-article
선정 이유: 기술 변화가 독자의 선택에 미치는 영향을 설명할 수 있습니다.
주요 내용:
첫 번째 핵심 사실입니다.
두 번째 핵심 사실입니다.
세 번째 핵심 사실입니다.
'@
$candidates = @(Get-Candidates $sample)
if ($candidates.Count -ne 2) { throw '기사 2건 파싱에 실패했습니다.' }
$actual = Format-CandidateList $candidates
$expected = $sample.TrimEnd("`r", "`n").Replace("`r`n", "`n")
if ($actual -cne $expected) { throw '소재 목록의 항목 순서 또는 빈 줄 수가 다릅니다.' }
if ($actual -notmatch '(?m)^게시일: 게시일 확인 불가$') { throw '게시일 미확인 표시가 없습니다.' }
if ([regex]::Matches($actual, "`n`n").Count -ne 1) { throw '기사 사이의 빈 줄이 정확히 1줄이 아닙니다.' }
Write-Output '소재 목록 검증 통과: 필수 항목, 한국어 요약 2~3줄, 게시일 미확인 표시, 기사 사이 빈 줄 1줄'

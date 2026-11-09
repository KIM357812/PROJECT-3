#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot '구글기반\프로그램\공통.ps1')

function Assert-True([bool]$condition,[string]$message) {
    if (-not $condition) { throw "반응형 표 보정 테스트 실패: $message" }
}

$style = '<style>@media (max-width: 600px) { .solidb-responsive-table td::before { content: attr(data-label); } }</style>'
$missing = $style + '<div class="solidb-responsive-table"><table><thead><tr><th>항목</th><th><span>기간</span></th></tr></thead><tbody><tr><td class="name">시험 기술</td><td data-label="잘못된 제목">24개월</td></tr><tr><td>운영</td><td>12개월</td></tr></tbody></table></div>'
$repaired = Repair-ResponsiveTableDataLabels $missing
Assert-ResponsiveTableDataLabels $repaired
Assert-True ([regex]::Matches($repaired,'data-label="항목"').Count -eq 2) '첫째 열 제목이 모든 행에 자동 삽입되어야 함'
Assert-True ([regex]::Matches($repaired,'data-label="기간"').Count -eq 2) '둘째 열 제목이 모든 행에 자동 삽입되어야 함'
Assert-True ($repaired -notmatch '잘못된 제목') '기존의 잘못된 data-label을 열 제목으로 교정해야 함'

$accent = '<table data-naver-role="accent"><tbody><tr><td>강조 상자</td></tr></tbody></table>'
Assert-True ((Repair-ResponsiveTableDataLabels $accent) -eq $accent) '강조 상자·참고자료 표는 변경하지 않아야 함'
Assert-ResponsiveTableDataLabels $accent
$mixed = Repair-ResponsiveTableDataLabels ($accent + $missing)
Assert-ResponsiveTableDataLabels $mixed
Assert-True ($mixed -match [regex]::Escape($accent)) '데이터 표와 함께 있어도 강조 상자는 변경하지 않아야 함'

$mismatch = $style + '<div class="solidb-responsive-table"><table><thead><tr><th>항목</th><th>기간</th></tr></thead><tbody><tr><td>시험</td></tr></tbody></table></div>'
$threw = $false
try { $null = Repair-ResponsiveTableDataLabels $mismatch } catch { $threw = $_.Exception.Message -match '열 제목 수' }
Assert-True $threw '헤더와 셀 개수가 다르면 자동 통과시키지 않아야 함'

$outsideWrapper = $style + '<table><thead><tr><th>항목</th></tr></thead><tbody><tr><td data-label="항목">시험</td></tr></tbody></table>'
$threw = $false
try { Assert-ResponsiveTableDataLabels $outsideWrapper } catch { $threw = $_.Exception.Message -match '모바일 세로형 변환 영역' }
Assert-True $threw '데이터 표가 반응형 영역 밖에 있으면 실패해야 함'

$styleHtml = '<div data-blog-sources="true" style="background:#fff; border-left:4px solid red; padding:1px; color:#222"><p>출처</p></div><div data-blog-related="true" style="background:#fff"><p>관련 글</p></div>'
$styleRepaired = Repair-NaverDeterministicStyles $styleHtml
Assert-True ($styleRepaired -match 'data-blog-sources="true"[^>]*background-color:\s*#f8f9fa') '출처 배경을 확정 회색으로 자동 교정해야 함'
Assert-True ($styleRepaired -match 'data-blog-sources="true"[^>]*padding:\s*8px 12px') '출처 여백을 자동 교정해야 함'
Assert-True ($styleRepaired -notmatch 'border-left') '출처 왼쪽 장식선을 제거해야 함'
Assert-True ($styleRepaired -match 'data-blog-related="true"[^>]*background-color:\s*#eef3fb') '관련 글 배경을 확정 파란색으로 자동 교정해야 함'

Write-Output 'Responsive table repair tests passed.'

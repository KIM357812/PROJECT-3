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

Write-Output 'Responsive table repair tests passed.'

#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$commonPath = Join-Path $projectRoot '구글기반\프로그램\공통.ps1'
$startPath = Join-Path $projectRoot '구글기반\프로그램\시작.ps1'
$runtimeRoot = Join-Path ([IO.Path]::GetTempPath()) ('naver-source-repair-' + [guid]::NewGuid().ToString('N'))
$previousRuntimeRoot = $env:NAVER_AUTOMATION_RUNTIME_ROOT

function Assert-True([bool]$condition,[string]$message) {
    if (-not $condition) { throw "검증 실패: $message" }
}

try {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $runtimeRoot
    . $commonPath

    $nested = @'
<div class="root"><div data-blog-sources="true"><p><strong>출처 :</strong> <a href="https://example.com/article">Example</a></p><div data-blog-related="true"><p>관련 글</p><p><a href="https://example.com/related">관련 분석</a></p></div></div></div>
'@
    $repaired = Repair-SourceRelatedStructure $nested.Trim()
    Assert-True ($repaired -match '(?is)data-blog-sources="true"[\s\S]*?</div>\s*<div\b(?=[^>]*data-blog-related="true")') '관련 글을 출처의 형제 영역으로 복구'
    $sourceContent = [regex]::Match($repaired,'(?is)<div\b(?=[^>]*data-blog-sources="true")[^>]*>(?<content>[\s\S]*?)</div>').Groups['content'].Value
    Assert-True ([regex]::Matches($sourceContent,'(?is)<a\b').Count -eq 1) '관련 글 링크를 출처 링크 수에서 제외'
    Assert-True ([regex]::Matches($repaired,'data-blog-related="true"').Count -eq 1) '관련 글 영역 중복 없음'

    $commonSource = [IO.File]::ReadAllText($commonPath,[Text.Encoding]::UTF8)
    $startSource = [IO.File]::ReadAllText($startPath,[Text.Encoding]::UTF8)
    Assert-True ($commonSource -notmatch "Write-Host '내부 사실검증표가 부족") '내부 사실검증 보완 문구를 사용자 화면에 표시하지 않음'
    Assert-True ($commonSource -match 'for \(\$attempt=0; \$attempt -le 3; \$attempt\+\+\)') '내부 사실검증 반복 보완'
    Assert-True ($commonSource -match '\$currentResponse = \$originalPublic \+ "`n`n" \+ \$repairedFact') '보완 결과에서 공개 영역을 원문으로 강제 보존'
    Assert-True ($startSource -match 'for \(\$generationAttempt=1; \$generationAttempt -le 3; \$generationAttempt\+\+\)') '유효 기사 전체 생성 반복 검증'
    Assert-True ($startSource -match '소재를 버리지 말고 정해진 출력 구조를 정확히 고쳐') '형식 실패 시 기사 폐기 대신 재생성'

    Write-Output 'Source structure and silent internal repair regression tests passed.'
} finally {
    $env:NAVER_AUTOMATION_RUNTIME_ROOT = $previousRuntimeRoot
    if ([IO.Directory]::Exists($runtimeRoot)) { Remove-Item -LiteralPath $runtimeRoot -Recurse -Force }
}

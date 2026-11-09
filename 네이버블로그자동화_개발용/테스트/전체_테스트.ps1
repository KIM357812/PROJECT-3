#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$testRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $testRoot
$integrityValidator = Join-Path $projectRoot '프로그램\구글참조무결성검증.ps1'
$integrityManifest = Join-Path $projectRoot '보호기준\google-reference-integrity.json'
& $integrityValidator -Mode Verify -ManifestPath $integrityManifest
$testFiles = @(
    '개발범위_테스트.ps1',
    '구글기반_네이버패키지_테스트.ps1',
    '구글기반_새글생성_정적테스트.ps1',
    '새글생성결과_테스트.ps1',
    '새작업실행연결_테스트.ps1',
    '크롬직접실행_테스트.ps1',
    '통합실행_테스트.ps1',
    '구글참조무결성검증_테스트.ps1',
    '요구사항대조_테스트.ps1',
    '백업내보내기_테스트.ps1',
    '사실검증준비_테스트.ps1',
    '설치준비_테스트.ps1',
    '수집작업_테스트.ps1',
    '기사선택_테스트.ps1',
    '관련글선정_테스트.ps1',
    '반응형표보정_테스트.ps1',
    '출처구조_내부복구_테스트.ps1',
    '작업자료검증_테스트.ps1',
    '작업상태_테스트.ps1',
    '완료URL_테스트.ps1',
    '초안검증기_테스트.ps1',
    '초안준비_테스트.ps1',
    '프롤로그초안준비_테스트.ps1',
    '편집기계획_테스트.ps1',
    '편집기구간초안준비_테스트.ps1',
    '편집기재구성계획_테스트.ps1',
    '편집기재구성실행검증_테스트.ps1',
    '편집기현재글서식복구계획_테스트.ps1',
    '편집기서식적용계획_테스트.ps1',
    '편집기결과검증_테스트.ps1',
    '편집기관찰준비_테스트.ps1',
    '벤치마크선정_테스트.ps1',
    '모바일미리보기_테스트.ps1',
    '이미지자동화_테스트.ps1',
    '독자반응분석_테스트.ps1',
    '사용자화면_테스트.ps1'
)

foreach ($testFile in $testFiles) {
    $testPath = Join-Path $testRoot $testFile
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
        throw "Test file was not found: $testPath"
    }
    & $testPath
}

$parseErrors = @()
foreach ($scriptFile in Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.ps1') {
    $tokens = $null
    $fileErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$fileErrors
    )
    if ($fileErrors) {
        $parseErrors += $fileErrors
    }

    $bytes = [System.IO.File]::ReadAllBytes($scriptFile.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        throw "PowerShell 5.1 UTF-8 BOM is missing: $($scriptFile.FullName)"
    }
}

if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object {
        Write-Error "$($_.Message) [$($_.Extent.File):$($_.Extent.StartLineNumber)]"
    }
    throw 'PowerShell syntax validation failed.'
}

Write-Output 'All Naver automation tests passed.'

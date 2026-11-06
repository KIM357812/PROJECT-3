#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$prepareScript = Join-Path $projectRoot '프로그램\프롤로그초안준비.ps1'
$previewScript = Join-Path $projectRoot '프로그램\모바일미리보기.ps1'
$sourcePath = Join-Path $projectRoot '콘텐츠기준\네이버_소개_및_정책_초안.md'
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('프롤로그 초안 테스트 ' + [guid]::NewGuid().ToString('N'))
$draftPath = Join-Path $testRoot 'intro.json'
$previewPath = Join-Path $testRoot 'intro-mobile.html'
$settingsPath = Join-Path $projectRoot '설정.json'

try {
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$settings.NaverEditor.IntroductionCategory -ne '공지·운영안내') {
        throw 'The introduction category does not match the category verified in the live Naver editor.'
    }

    $null = New-Item -ItemType Directory -Path $testRoot
    $result = & $prepareScript -SourcePath $sourcePath -OutputPath $draftPath `
        -ContentId 'NTE-INTRO-TEST' -AnalyzedDate (Get-Date -Format 'yyyy-MM-dd') |
        ConvertFrom-Json
    if (-not $result.isValid -or $result.draftType -ne 'Introduction' -or
        $result.bodyLength -lt 1700 -or $result.bodyLength -gt 3300 -or
        $result.tagCount -lt 5 -or $result.sourceCount -ne 0) {
        throw 'The introduction draft did not satisfy its validated output contract.'
    }

    $draft = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($draft.body -match '[`]|^###' -or
        $draft.body.IndexOf('AI가 다른 기술·산업과 결합', [StringComparison]::Ordinal) -lt 0 -or
        $draft.sectionHeadings.Count -lt 3 -or
        $draft.sectionHeadings -notcontains '정보가 넘치는 시대, 무엇을 봐야 할지가 더 중요합니다' -or
        -not $draft.allowImagePromptException -or
        $draft.editorialContext.coreAnalysisAxes -notcontains '온실가스') {
        throw 'The introduction draft lost required plain-text or editorial content.'
    }

    $preview = & $previewScript -DraftPath $draftPath -OutputPath $previewPath | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $preview.output -PathType Leaf) -or $preview.viewportWidth -ne 390) {
        throw 'The introduction mobile preview was not created.'
    }
    $previewHtml = Get-Content -LiteralPath $previewPath -Raw -Encoding UTF8
    if ($previewHtml.IndexOf('<h2>출처</h2>', [StringComparison]::Ordinal) -ge 0) {
        throw 'An empty source section was shown for the introduction draft.'
    }

    $overwriteBlocked = $false
    try { & $prepareScript -SourcePath $sourcePath -OutputPath $draftPath | Out-Null }
    catch { $overwriteBlocked = $true }
    if (-not $overwriteBlocked) { throw 'An existing introduction draft was overwritten.' }

    Write-Output 'Introduction draft preparation tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        if (-not $resolved.StartsWith($systemTemp + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean outside the system temp directory: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

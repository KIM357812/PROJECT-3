$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $projectRoot
$agentsPath = Join-Path $repositoryRoot 'AGENTS.md'
$requirementsPath = Join-Path $repositoryRoot 'DEVELOPMENT_REQUIREMENTS.md'
$introductionPath = Join-Path $projectRoot '콘텐츠기준\네이버_소개_및_정책_초안.md'
$priorityPath = Join-Path $projectRoot '콘텐츠기준\네이버_작성_우선순위.md'
$settingsPath = Join-Path $projectRoot '설정.json'

if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
    throw 'AGENTS.md was not found at the repository root.'
}

if (-not (Test-Path -LiteralPath $requirementsPath -PathType Leaf)) {
    throw 'DEVELOPMENT_REQUIREMENTS.md was not found at the repository root.'
}

if (-not (Test-Path -LiteralPath $introductionPath -PathType Leaf)) {
    throw 'The Naver introduction draft was not found.'
}
if (-not (Test-Path -LiteralPath $priorityPath -PathType Leaf)) {
    throw 'The Naver writing priority document was not found.'
}
if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw 'The Naver settings file was not found.'
}

$agents = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8
$requirements = Get-Content -LiteralPath $requirementsPath -Raw -Encoding UTF8
$introduction = Get-Content -LiteralPath $introductionPath -Raw -Encoding UTF8
$priority = Get-Content -LiteralPath $priorityPath -Raw -Encoding UTF8
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($settings.NaverDraft.PostTitleFontSize -ne 26 -or
    $settings.NaverDraft.PostTitleMobileFontSize -ne 24 -or
    $settings.NaverDraft.SectionHeadingFontSize -ne 19 -or
    $settings.NaverDraft.BodyFontSize -ne 16 -or
    $settings.ImageAutomation.EditorDisplayWidth -ne 340) {
    throw 'The verified Naver title, heading, body, or image display defaults changed unexpectedly.'
}

$requiredAgentText = @(
    'Google Blogger',
    'Windows PowerShell 5.1',
    'codex/naver-blog-semi-automation',
    'DEVELOPMENT_REQUIREMENTS.md'
)

foreach ($text in $requiredAgentText) {
    if ($agents.IndexOf($text, [System.StringComparison]::Ordinal) -lt 0) {
        throw "AGENTS.md is missing required text: $text"
    }
}

$requiredRequirementText = @(
    'TechCrunch',
    'https://techcrunch.com',
    'https://www.theverge.com',
    'https://electrek.co',
    'https://www.powermag.com',
    'https://cleantechnica.com',
    'https://www.canarymedia.com',
    'https://www.space.com',
    'https://spacenews.com',
    'SpaceNews',
    'Google Blogger',
    'Windows PowerShell 5.1',
    '네이버 공식 블로그·검색·스마트에디터 기준',
    '구독자 가독성과 재방문성',
    'AI·데이터센터·전력·에너지·온실가스',
    '공신력 있는 글로벌 전문 매체',
    '모든 주제를 억지로 연결하지 않고',
    'AI 융합기술',
    '나노·첨단소재(NT)',
    '우주(ST)',
    '로봇·제조·모빌리티·바이오'
)

foreach ($text in $requiredRequirementText) {
    if ($requirements.IndexOf($text, [System.StringComparison]::Ordinal) -lt 0) {
        throw "DEVELOPMENT_REQUIREMENTS.md is missing required text: $text"
    }
}

$requiredPriorityText = @(
    '1순위: 네이버 공식 기준',
    '2순위: 구독자 선호와 재방문성',
    'https://help.naver.com/service/5593/contents/10582',
    'https://help.naver.com/service/5593/contents/10586',
    'https://help.naver.com/service/5601/contents/12251',
    '네이버 공식 최적 글자 수가 아니며',
    '검색 순위, 상위 노출과 방문자 수를 보장'
)

foreach ($text in $requiredPriorityText) {
    if ($priority.IndexOf($text, [System.StringComparison]::Ordinal) -lt 0) {
        throw "The Naver writing priority document is missing required text: $text"
    }
}

$requiredIntroductionText = @(
    '같은 운영자',
    '국내 독자',
    '원문을 단순히 번역',
    '운영자의 해설',
    '판단을 구분',
    'TechCrunch',
    'The Verge',
    'Electrek',
    'POWER Magazine',
    'CleanTechnica',
    'Canary Media',
    'Space.com',
    'SpaceNews'
)

foreach ($text in $requiredIntroductionText) {
    if ($introduction.IndexOf($text, [System.StringComparison]::Ordinal) -lt 0) {
        throw "The Naver introduction draft is missing required text: $text"
    }
}

$googleBaseRoot = Join-Path $projectRoot '구글기반'
$projectTextFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
    Where-Object {
        ($_.Extension -eq '.md' -or $_.Extension -eq '.ps1') -and
        -not $_.FullName.StartsWith($googleBaseRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }
$forbiddenPhrases = @(
    ('30' + [char]0xB144),
    ('25' + [char]0xB144),
    ('10' + [char]0xB144),
    ([string]([char]0xC9C1) + [char]0xC6D0)
)

foreach ($file in $projectTextFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    foreach ($phrase in $forbiddenPhrases) {
        if ($content.IndexOf($phrase, [System.StringComparison]::Ordinal) -ge 0) {
            throw "A forbidden phrase was found in $($file.FullName)."
        }
    }
}

Write-Output 'Development scope document test passed.'

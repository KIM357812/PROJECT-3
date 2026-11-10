#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DraftPath,

    [Parameter(Mandatory = $true)]
    [string]$ImageRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $projectRoot '설정.json'
}

foreach ($requiredPath in @($DraftPath, $ConfigPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "필수 파일을 찾을 수 없습니다: $requiredPath"
    }
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "기존 이미지 작업 계획을 덮어쓰지 않습니다: $OutputPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$draft = Get-Content -LiteralPath $DraftPath -Raw -Encoding UTF8 | ConvertFrom-Json
$rules = $config.ImageAutomation
if (-not [bool]$rules.Enabled) {
    throw '설정에서 이미지 자동화가 비활성화되어 있습니다.'
}

$prompts = @($draft.imagePrompts)
$roles = @($rules.Roles | Sort-Object Order)
if ($prompts.Count -ne [int]$rules.TargetCount -or $roles.Count -ne [int]$rules.TargetCount) {
    throw "이미지 지시문과 역할은 각각 $($rules.TargetCount)개여야 합니다."
}
if ([int]$rules.Width * 2 -ne [int]$rules.Height * 3) {
    throw '이미지 설정의 가로·세로 크기가 3:2 비율이 아닙니다.'
}

$resolvedImageRoot = [IO.Path]::GetFullPath($ImageRoot)
$originalDirectory = Join-Path $resolvedImageRoot 'original'
$optimizedDirectory = Join-Path $resolvedImageRoot 'optimized'
foreach ($directory in @($resolvedImageRoot, $originalDirectory, $optimizedDirectory, (Split-Path -Parent $OutputPath))) {
    if ([string]::IsNullOrWhiteSpace($directory)) { throw '출력 경로에는 상위 폴더가 필요합니다.' }
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory
    }
}

$assets = for ($index = 0; $index -lt $roles.Count; $index++) {
    $role = $roles[$index]
    [pscustomobject]@{
        order = [int]$role.Order
        role = [string]$role.Name
        prompt = [string]$prompts[$index]
        purpose = [string]$role.Purpose
        placement = [string]$role.Placement
        originalBaseName = [string]$role.OriginalBaseName
        outputFileName = [string]$role.OutputFileName
    }
}

$manifest = [pscustomobject]@{
    schemaVersion = 1
    contentId = [string]$draft.contentId
    createdAt = (Get-Date).ToString('o')
    generationMode = 'ChatGPT 실사 이미지 생성 결과를 원본 입력으로 사용'
    paidApiConnected = $false
    specification = [pscustomobject]@{
        count = [int]$rules.TargetCount
        width = [int]$rules.Width
        height = [int]$rules.Height
        aspectRatio = [string]$rules.AspectRatio
        format = [string]$rules.OutputFormat
        initialJpegQuality = [int]$rules.InitialJpegQuality
        minimumJpegQuality = [int]$rules.MinimumJpegQuality
        maximumKilobytes = [int]$rules.MaximumKilobytes
        maximumPerceptualSimilarityPercent = if ($null -ne $rules.MaximumPerceptualSimilarityPercent) { [double]$rules.MaximumPerceptualSimilarityPercent } else { 68.0 }
        requireCentralSquareSafeArea = [bool]$rules.RequireCentralSquareSafeArea
        forbidEmbeddedText = [bool]$rules.ForbidEmbeddedText
        forbidWatermarks = if ($null -ne $rules.ForbidWatermarks) { [bool]$rules.ForbidWatermarks } else { $true }
        allowVerifiedOfficialLogos = if ($null -ne $rules.AllowVerifiedOfficialLogos) { [bool]$rules.AllowVerifiedOfficialLogos } else { $false }
        requireOfficialLogoAsset = if ($null -ne $rules.RequireOfficialLogoAsset) { [bool]$rules.RequireOfficialLogoAsset } else { $true }
        forbidAiRenderedLogos = if ($null -ne $rules.ForbidAiRenderedLogos) { [bool]$rules.ForbidAiRenderedLogos } else { $true }
        requireDistinctRoleComposition = $true
        preserveOriginals = $true
    }
    originalDirectory = $originalDirectory
    optimizedDirectory = $optimizedDirectory
    assets = @($assets)
}

$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
[pscustomobject]@{
    output = [IO.Path]::GetFullPath($OutputPath)
    imageCount = $assets.Count
    size = "$($rules.Width)x$($rules.Height)"
    originalDirectory = $originalDirectory
    optimizedDirectory = $optimizedDirectory
} | ConvertTo-Json -Depth 4

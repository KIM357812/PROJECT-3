#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,
    [switch]$ReportOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "이미지 작업 계획을 찾을 수 없습니다: $ManifestPath"
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$spec = $manifest.specification
$assets = @($manifest.assets | Sort-Object order)
$issues = @()

if ($assets.Count -ne [int]$spec.count) { $issues += '이미지 역할 개수가 설정과 다릅니다.' }
if ([IO.Path]::GetFullPath([string]$manifest.originalDirectory) -eq [IO.Path]::GetFullPath([string]$manifest.optimizedDirectory)) {
    $issues += '원본 폴더와 변환본 폴더가 같습니다.'
}

$checked = @()
$optimizedHashes = @{}
$perceptualSignatures = @{}

function Get-DifferenceHash([string]$Path) {
    $source = $null
    $sample = $null
    $graphics = $null
    try {
        $source = [Drawing.Image]::FromFile($Path)
        $sample = New-Object Drawing.Bitmap(17, 16, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [Drawing.Graphics]::FromImage($sample)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($source, 0, 0, 17, 16)
        $bits = New-Object 'System.Collections.Generic.List[bool]'
        for ($y = 0; $y -lt 16; $y++) {
            for ($x = 0; $x -lt 16; $x++) {
                $left = $sample.GetPixel($x, $y)
                $right = $sample.GetPixel($x + 1, $y)
                $leftLuma = ($left.R * 299) + ($left.G * 587) + ($left.B * 114)
                $rightLuma = ($right.R * 299) + ($right.G * 587) + ($right.B * 114)
                $bits.Add($leftLuma -gt $rightLuma)
            }
        }
        return ,$bits.ToArray()
    } finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $sample) { $sample.Dispose() }
        if ($null -ne $source) { $source.Dispose() }
    }
}

function Get-PerceptualSimilarity([bool[]]$Left, [bool[]]$Right) {
    if ($Left.Count -ne $Right.Count -or $Left.Count -eq 0) { return 0.0 }
    $different = 0
    for ($index = 0; $index -lt $Left.Count; $index++) {
        if ($Left[$index] -ne $Right[$index]) { $different++ }
    }
    return [Math]::Round((1.0 - ($different / [double]$Left.Count)) * 100.0, 1)
}
foreach ($asset in $assets) {
    $path = Join-Path ([string]$manifest.optimizedDirectory) ([string]$asset.outputFileName)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $issues += "변환 이미지를 찾을 수 없습니다: $($asset.outputFileName)"
        continue
    }
    if ([IO.Path]::GetExtension($path).ToLowerInvariant() -notin @('.jpg', '.jpeg')) {
        $issues += "JPEG 형식이 아닙니다: $($asset.outputFileName)"
        continue
    }
    if ([string]::IsNullOrWhiteSpace([string]$asset.sourceSha256) -or [string]::IsNullOrWhiteSpace([string]$asset.optimizedSha256)) {
        $issues += "이미지 생성·최적화 출처 증거가 없습니다: $($asset.outputFileName)"
        continue
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actualHash -ne [string]$asset.optimizedSha256) {
        $issues += "최적화 이미지가 생성 후 변경되었습니다: $($asset.outputFileName)"
        continue
    }
    if ($optimizedHashes.ContainsKey($actualHash)) {
        $issues += "동일한 이미지를 여러 위치에 재사용했습니다: $($asset.outputFileName)"
        continue
    }
    $optimizedHashes[$actualHash] = $true

    $image = $null
    try {
        $image = [Drawing.Image]::FromFile($path)
        if ($image.Width -ne [int]$spec.width -or $image.Height -ne [int]$spec.height) {
            $issues += "이미지 크기가 $($spec.width)x$($spec.height)가 아닙니다: $($asset.outputFileName)"
        }
        $kilobytes = [Math]::Round((Get-Item -LiteralPath $path).Length / 1KB, 1)
        if ($kilobytes -gt [int]$spec.maximumKilobytes) {
            $issues += "이미지 용량이 $($spec.maximumKilobytes)KB를 넘습니다: $($asset.outputFileName)"
        }
        $checked += [pscustomobject]@{
            order = [int]$asset.order
            role = [string]$asset.role
            path = $path
            width = $image.Width
            height = $image.Height
            kilobytes = $kilobytes
            placement = [string]$asset.placement
            sourceSha256 = [string]$asset.sourceSha256
            optimizedSha256 = $actualHash
        }
        $perceptualSignatures[[string]$asset.outputFileName] = Get-DifferenceHash $path
    } finally {
        if ($null -ne $image) { $image.Dispose() }
    }
}

$maximumSimilarity = if ($null -ne $spec.maximumPerceptualSimilarityPercent) {
    [double]$spec.maximumPerceptualSimilarityPercent
} else { 68.0 }
$duplicatePairs = New-Object 'System.Collections.Generic.List[object]'
$perceptualComparisons = New-Object 'System.Collections.Generic.List[object]'
for ($leftIndex = 0; $leftIndex -lt $checked.Count; $leftIndex++) {
    for ($rightIndex = $leftIndex + 1; $rightIndex -lt $checked.Count; $rightIndex++) {
        $left = $checked[$leftIndex]
        $right = $checked[$rightIndex]
        $leftName = [IO.Path]::GetFileName([string]$left.path)
        $rightName = [IO.Path]::GetFileName([string]$right.path)
        $leftSignature = [bool[]]$perceptualSignatures[$leftName]
        $rightSignature = [bool[]]$perceptualSignatures[$rightName]
        $similarity = Get-PerceptualSimilarity -Left $leftSignature -Right $rightSignature
        $perceptualComparisons.Add([pscustomobject]@{
            leftOrder = [int]$left.order
            rightOrder = [int]$right.order
            similarityPercent = $similarity
        })
        if ($similarity -gt $maximumSimilarity) {
            $duplicatePairs.Add([pscustomobject]@{
                leftOrder = [int]$left.order
                rightOrder = [int]$right.order
                leftRole = [string]$left.role
                rightRole = [string]$right.role
                similarityPercent = $similarity
            })
            $issues += "역할이 다른 이미지가 시각적으로 지나치게 유사합니다: $($left.role)/$($right.role) ($similarity%)"
        }
    }
}

$result = [pscustomobject]@{
    isValid = ($issues.Count -eq 0 -and $checked.Count -eq [int]$spec.count)
    issues = @($issues)
    checkedImages = @($checked)
    maximumPerceptualSimilarityPercent = $maximumSimilarity
    perceptualComparisons = @($perceptualComparisons.ToArray())
    perceptualDuplicatePairs = @($duplicatePairs.ToArray())
}
$result | ConvertTo-Json -Depth 6
if (-not $result.isValid -and -not $ReportOnly) {
    throw ('이미지 검증에 실패했습니다: ' + (@($issues) -join '; '))
}

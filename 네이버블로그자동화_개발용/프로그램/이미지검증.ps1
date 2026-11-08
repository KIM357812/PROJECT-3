#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath
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
            role = [string]$asset.role
            path = $path
            width = $image.Width
            height = $image.Height
            kilobytes = $kilobytes
            placement = [string]$asset.placement
            sourceSha256 = [string]$asset.sourceSha256
            optimizedSha256 = $actualHash
        }
    } finally {
        if ($null -ne $image) { $image.Dispose() }
    }
}

$result = [pscustomobject]@{
    isValid = ($issues.Count -eq 0 -and $checked.Count -eq [int]$spec.count)
    issues = @($issues)
    checkedImages = @($checked)
}
$result | ConvertTo-Json -Depth 6
if (-not $result.isValid) {
    throw ('이미지 검증에 실패했습니다: ' + (@($issues) -join '; '))
}

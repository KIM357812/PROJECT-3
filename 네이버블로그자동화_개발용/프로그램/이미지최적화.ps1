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
if ($assets.Count -ne [int]$spec.count) {
    throw '이미지 작업 계획의 개수와 자산 개수가 다릅니다.'
}
if ([IO.Path]::GetFullPath([string]$manifest.originalDirectory) -eq [IO.Path]::GetFullPath([string]$manifest.optimizedDirectory)) {
    throw '원본 폴더와 변환본 폴더는 달라야 합니다.'
}

foreach ($directory in @([string]$manifest.originalDirectory, [string]$manifest.optimizedDirectory)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "이미지 폴더를 찾을 수 없습니다: $directory"
    }
}

$jpegEncoder = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq 'image/jpeg' } |
    Select-Object -First 1
if ($null -eq $jpegEncoder) { throw 'Windows JPEG 인코더를 찾을 수 없습니다.' }

$results = @()
foreach ($asset in $assets) {
    $matches = @(Get-ChildItem -LiteralPath ([string]$manifest.originalDirectory) -File |
        Where-Object { $_.BaseName -eq [string]$asset.originalBaseName })
    if ($matches.Count -ne 1) {
        throw "원본 이미지는 역할별로 정확히 한 개여야 합니다: $($asset.originalBaseName)"
    }

    $sourcePath = $matches[0].FullName
    $outputPath = Join-Path ([string]$manifest.optimizedDirectory) ([string]$asset.outputFileName)
    if (Test-Path -LiteralPath $outputPath) {
        throw "기존 변환 이미지를 덮어쓰지 않습니다: $outputPath"
    }

    $source = $null
    $canvas = $null
    $graphics = $null
    $encodedBytes = $null
    try {
        $source = [Drawing.Image]::FromFile($sourcePath)
        $targetWidth = [int]$spec.width
        $targetHeight = [int]$spec.height
        $targetRatio = $targetWidth / [double]$targetHeight
        $sourceRatio = $source.Width / [double]$source.Height

        if ($sourceRatio -gt $targetRatio) {
            $cropHeight = $source.Height
            $cropWidth = [int][Math]::Round($cropHeight * $targetRatio)
            $cropX = [int][Math]::Round(($source.Width - $cropWidth) / 2)
            $cropY = 0
        } else {
            $cropWidth = $source.Width
            $cropHeight = [int][Math]::Round($cropWidth / $targetRatio)
            $cropX = 0
            $cropY = [int][Math]::Round(($source.Height - $cropHeight) / 2)
        }

        $canvas = New-Object Drawing.Bitmap($targetWidth, $targetHeight, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [Drawing.Graphics]::FromImage($canvas)
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage(
            $source,
            (New-Object Drawing.Rectangle(0, 0, $targetWidth, $targetHeight)),
            $cropX, $cropY, $cropWidth, $cropHeight,
            [Drawing.GraphicsUnit]::Pixel
        )

        $quality = [int]$spec.initialJpegQuality
        $minimumQuality = [int]$spec.minimumJpegQuality
        $maximumBytes = [int64]$spec.maximumKilobytes * 1024
        do {
            $encoderParameters = New-Object Drawing.Imaging.EncoderParameters(1)
            $encoderParameters.Param[0] = New-Object Drawing.Imaging.EncoderParameter(
                [Drawing.Imaging.Encoder]::Quality,
                [int64]$quality
            )
            $memory = New-Object IO.MemoryStream
            try {
                $canvas.Save($memory, $jpegEncoder, $encoderParameters)
                $encodedBytes = $memory.ToArray()
            } finally {
                $memory.Dispose()
                $encoderParameters.Dispose()
            }
            $byteLength = $encodedBytes.Length
            if ($byteLength -le $maximumBytes -or $quality -le $minimumQuality) { break }
            $quality = [Math]::Max($minimumQuality, $quality - 4)
        } while ($true)

        if ($byteLength -gt $maximumBytes) {
            throw "최저 품질에서도 이미지가 허용 용량을 넘습니다: $sourcePath"
        }
        $graphics.Dispose()
        $graphics = $null
        $canvas.Dispose()
        $canvas = $null
        $source.Dispose()
        $source = $null
        [IO.File]::WriteAllBytes($outputPath, $encodedBytes)
        $results += [pscustomobject]@{
            role = [string]$asset.role
            source = $sourcePath
            output = $outputPath
            width = $targetWidth
            height = $targetHeight
            quality = $quality
            kilobytes = [Math]::Round($byteLength / 1KB, 1)
        }
    } finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $canvas) { $canvas.Dispose() }
        if ($null -ne $source) { $source.Dispose() }
    }
}

@($results) | ConvertTo-Json -Depth 5

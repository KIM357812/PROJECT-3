#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$optimizer = Join-Path $projectRoot '프로그램\이미지최적화.ps1'
$validator = Join-Path $projectRoot '프로그램\이미지검증.ps1'
$repairer = Join-Path $projectRoot '프로그램\이미지자동복구.ps1'
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('네이버 이미지 자동화 테스트 ' + [guid]::NewGuid().ToString('N'))
$originalDirectory = Join-Path $testRoot 'original'
$optimizedDirectory = Join-Path $testRoot 'optimized'
$manifestPath = Join-Path $testRoot 'image-manifest.json'

try {
    $null = New-Item -ItemType Directory -Path $originalDirectory
    $null = New-Item -ItemType Directory -Path $optimizedDirectory
    $roles = @(
        @{Order=1;Role='대표';Base='01-대표';Output='01-대표.jpg';Placement='제목 아래'},
        @{Order=2;Role='비용경로';Base='02-비용경로';Output='02-비용경로.jpg';Placement='설명 뒤'},
        @{Order=3;Role='비용분담';Base='03-비용분담';Output='03-비용분담.jpg';Placement='판단 앞'}
    )
    $roleIndex = 0
    foreach ($role in $roles) {
        $roleIndex++
        $path = Join-Path $originalDirectory ($role.Base + '.png')
        $bitmap = New-Object Drawing.Bitmap(900, 600)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([Drawing.Color]::FromArgb(15, 54, 82))
            $color = [Drawing.Color]::FromArgb(30 * $roleIndex, 80 + (20 * $roleIndex), 140 + (20 * $roleIndex))
            $brush = New-Object Drawing.SolidBrush($color)
            try { $graphics.FillRectangle($brush, 250, 150, 400, 300) } finally { $brush.Dispose() }
            $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
    $hashesBefore = @(Get-ChildItem -LiteralPath $originalDirectory -File | Sort-Object Name | Get-FileHash | Select-Object -ExpandProperty Hash)

    [pscustomobject]@{
        schemaVersion=1; contentId='TEST-IMAGE-001'; originalDirectory=$originalDirectory; optimizedDirectory=$optimizedDirectory
        specification=[pscustomobject]@{count=3;width=1200;height=800;aspectRatio='3:2';format='JPEG';initialJpegQuality=84;minimumJpegQuality=68;maximumKilobytes=450}
        assets=@($roles | ForEach-Object {[pscustomobject]@{order=$_.Order;role=$_.Role;originalBaseName=$_.Base;outputFileName=$_.Output;placement=$_.Placement}})
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $null = & $optimizer -ManifestPath $manifestPath | ConvertFrom-Json
    $optimizedFiles = @(Get-ChildItem -LiteralPath $optimizedDirectory -File -Filter '*.jpg')
    if ($optimizedFiles.Count -ne 3) { throw 'The optimizer did not produce three images.' }
    $validation = & $validator -ManifestPath $manifestPath | ConvertFrom-Json
    if (-not $validation.isValid -or $validation.checkedImages.Count -ne 3) {
        throw 'The optimized images did not pass validation.'
    }
    foreach ($image in $validation.checkedImages) {
        if ($image.width -ne 1200 -or $image.height -ne 800 -or $image.kilobytes -gt 450) {
            throw 'An optimized image does not meet the shared size or capacity rule.'
        }
    }
    $hashesAfter = @(Get-ChildItem -LiteralPath $originalDirectory -File | Sort-Object Name | Get-FileHash | Select-Object -ExpandProperty Hash)
    if ((Compare-Object $hashesBefore $hashesAfter).Count -ne 0) {
        throw 'The image optimizer changed an original image.'
    }
    $overwriteWasBlocked = $false
    try { & $optimizer -ManifestPath $manifestPath | Out-Null } catch { $overwriteWasBlocked = $true }
    if (-not $overwriteWasBlocked) { throw 'The optimizer overwrote existing outputs.' }

    $missingOutput=Join-Path $optimizedDirectory $roles[1].Output
    Remove-Item -LiteralPath $missingOutput -Force
    $repaired=& $repairer -ManifestPath $manifestPath|ConvertFrom-Json
    if(-not $repaired.isValid -or -not(Test-Path -LiteralPath $missingOutput -PathType Leaf)){throw 'A missing optimized image was not repaired from its original.'}

    $fallbackRoot=Join-Path $testRoot 'fallback'
    $fallbackOriginal=Join-Path $fallbackRoot 'original'
    $fallbackOptimized=Join-Path $fallbackRoot 'optimized'
    $null=New-Item -ItemType Directory -Path $fallbackOriginal
    $null=New-Item -ItemType Directory -Path $fallbackOptimized
    $fallbackManifest=Join-Path $fallbackRoot 'manifest.json'
    [pscustomobject]@{
        schemaVersion=1;contentId='TEST-FALLBACK';originalDirectory=$fallbackOriginal;optimizedDirectory=$fallbackOptimized
        specification=[pscustomobject]@{count=3;width=1200;height=800;aspectRatio='3:2';format='JPEG';initialJpegQuality=84;minimumJpegQuality=68;maximumKilobytes=450}
        assets=@($roles|ForEach-Object {[pscustomobject]@{order=$_.Order;role=$_.Role;prompt=('기술 시각화 '+$_.Role);originalBaseName=$_.Base;outputFileName=$_.Output;placement=$_.Placement}})
    }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $fallbackManifest -Encoding UTF8
    $fallback=& $repairer -ManifestPath $fallbackManifest|ConvertFrom-Json
    if(-not $fallback.isValid -or @(Get-ChildItem -LiteralPath $fallbackOptimized -File -Filter '*.jpg').Count -ne 3){throw 'Missing source images were not generated and optimized automatically.'}

    Write-Output 'Image automation tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $prefix = $systemTemp + [IO.Path]::DirectorySeparatorChar
        if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean a test path outside the system temp directory: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

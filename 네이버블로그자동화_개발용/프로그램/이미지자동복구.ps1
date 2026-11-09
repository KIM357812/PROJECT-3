#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [string]$SourceArticlePath=''
)

$ErrorActionPreference='Stop'
$manifest=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
$assets=@($manifest.assets|Sort-Object order)
function Test-OriginalExists([object]$Asset){
    $base=[string]$Asset.originalBaseName
    return (@(Get-ChildItem -LiteralPath ([string]$manifest.originalDirectory) -File -ErrorAction SilentlyContinue|Where-Object {$_.BaseName -eq $base}).Count -eq 1)
}
$optimizedMissing=@($assets|Where-Object {-not(Test-Path -LiteralPath (Join-Path ([string]$manifest.optimizedDirectory) ([string]$_.outputFileName)) -PathType Leaf)})
if($optimizedMissing.Count -eq 0){
    & (Join-Path $PSScriptRoot '이미지검증.ps1') -ManifestPath $ManifestPath
    return
}

$originalMissing=@($assets|Where-Object {-not(Test-OriginalExists $_)})
if($originalMissing.Count -gt 0 -and $SourceArticlePath -and (Test-Path -LiteralPath $SourceArticlePath -PathType Container)){
    $sourceFiles=@()
    foreach($name in @('원본이미지','압축이미지')){
        $candidate=Join-Path $SourceArticlePath $name
        if(Test-Path -LiteralPath $candidate -PathType Container){
            $sourceFiles=@(Get-ChildItem -LiteralPath $candidate -File|Where-Object Extension -Match '^\.(jpg|jpeg|png|webp)$'|Sort-Object Name)
            if($sourceFiles.Count -eq $assets.Count){break}
        }
    }
    if($sourceFiles.Count -eq $assets.Count){
        for($index=0;$index -lt $assets.Count;$index++){
            $asset=$assets[$index]
            if(Test-OriginalExists $asset){continue}
            $extension=$sourceFiles[$index].Extension.ToLowerInvariant()
            Copy-Item -LiteralPath $sourceFiles[$index].FullName -Destination (Join-Path ([string]$manifest.originalDirectory) (([string]$asset.originalBaseName)+$extension))
        }
    }
}

$stillMissing=@($assets|Where-Object {-not(Test-OriginalExists $_)})
if($stillMissing.Count -gt 0){
    $null=& (Join-Path $PSScriptRoot '이미지로컬생성.ps1') -ManifestPath $ManifestPath|ConvertFrom-Json
    $stillMissing=@($assets|Where-Object {-not(Test-OriginalExists $_)})
}
if($stillMissing.Count -gt 0){throw ('원본 이미지 자동 생성이 완료되지 않았습니다: '+(@($stillMissing|ForEach-Object originalBaseName)-join ', '))}

$null=& (Join-Path $PSScriptRoot '이미지최적화.ps1') -ManifestPath $ManifestPath -RepairMissing|ConvertFrom-Json
& (Join-Path $PSScriptRoot '이미지검증.ps1') -ManifestPath $ManifestPath

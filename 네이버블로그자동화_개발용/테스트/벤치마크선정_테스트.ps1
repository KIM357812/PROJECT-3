#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot '프로그램\벤치마크선정.ps1'
$configPath = Join-Path $projectRoot '설정.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('NaverBenchmark-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $inputPath = Join-Path $tempRoot 'benchmark-input.json'
    $outputPath = Join-Path $tempRoot 'benchmark-review.json'
    [pscustomobject]@{
        analyzedDate = (Get-Date).ToString('yyyy-MM-dd')
        topic = 'AI 데이터센터와 전력 인프라'
        candidates = @(
            [pscustomobject]@{
                blogId='tech-plus'; blogUrl='https://blog.naver.com/tech-plus'; publicNeighbors=42711
                latestPostDays=783; topicSimilarity=4; generalAudienceFit=5; sourceQuality=3
                publicMetricsOnly=$true; adoptedPatterns=@('large-scale topic archive')
            },
            [pscustomobject]@{
                blogId='hec_pr'; blogUrl='https://blog.naver.com/hec_pr'; publicNeighbors=6150
                latestPostDays=2; topicSimilarity=5; generalAudienceFit=3; sourceQuality=4
                publicMetricsOnly=$true; adoptedPatterns=@('summary','analogy','subheadings')
            },
            [pscustomobject]@{
                blogId='backeclub'; blogUrl='https://blog.naver.com/backeclub'; publicNeighbors=2066
                latestPostDays=0; topicSimilarity=5; generalAudienceFit=5; sourceQuality=4
                publicMetricsOnly=$true; adoptedPatterns=@('three-line summary','event-led opening','critical counterview')
            },
            [pscustomobject]@{
                blogId='hye8431'; blogUrl='https://blog.naver.com/hye8431'; publicNeighbors=3554
                latestPostDays=0; topicSimilarity=3; generalAudienceFit=5; sourceQuality=3
                publicMetricsOnly=$true; adoptedPatterns=@('question title','FAQ','key points')
            }
        )
        rejectedPatterns = @('excessive length','event-driven engagement','keyword repetition')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inputPath -Encoding UTF8

    $result = & $scriptPath -Path $inputPath -OutputPath $outputPath -ConfigPath $configPath
    if ($result.primaryBlogId -ne 'backeclub' -or -not $result.primaryHasHighestQualifiedReach -or
        $result.candidateCount -ne 4 -or $result.activeReferenceCount -ne 3) {
        throw 'The benchmark selector did not apply relevance, audience, activity, and public reach in order.'
    }
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'Benchmark review was not saved.' }

    $overwriteBlocked = $false
    try { & $scriptPath -Path $inputPath -OutputPath $outputPath -ConfigPath $configPath | Out-Null }
    catch { $overwriteBlocked = $true }
    if (-not $overwriteBlocked) { throw 'Existing benchmark review was overwritten.' }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Output 'Benchmark selector tests passed.'

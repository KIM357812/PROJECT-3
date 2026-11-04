$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '공통.ps1')
$mutex = New-Object Threading.Mutex($false, 'Local\BlogUnifiedImageWatcher')
if (-not $mutex.WaitOne(0)) { exit 0 }
$reported = @{}
try {
    while ($true) {
        foreach ($dateFolder in @(Get-ChildItem -LiteralPath $script:CompleteDir -Directory)) {
            foreach ($article in @(Get-ChildItem -LiteralPath $dateFolder.FullName -Directory)) {
                $source = Join-Path $article.FullName '원본이미지'
                $target = Join-Path $article.FullName '압축이미지'
                if (-not [IO.Directory]::Exists($source) -or -not [IO.Directory]::Exists($target)) { continue }
                $images = @(Get-ChildItem -LiteralPath $source -File | Where-Object Extension -Match '^\.(jpg|jpeg|png|webp)$')
                if ($images.Count -ne 4 -or @(Get-ChildItem -LiteralPath $target -File -Filter '*.webp').Count -gt 0) { continue }
                $signature = ($images | Sort-Object Name | ForEach-Object { $_.Name+':'+$_.Length+':'+$_.LastWriteTimeUtc.Ticks }) -join '|'
                if ($reported[$article.FullName] -eq $signature) { continue }
                $reported[$article.FullName] = $signature
                try {
                    $destination = Process-Images $article.FullName
                    [IO.File]::WriteAllText((Join-Path $article.FullName '이미지_완료.txt'),"WebP 4장 완료: $destination`n",$script:Utf8)
                    Hide-ArticleInternalFiles $article.FullName
                } catch { Write-ErrorLog ("이미지 변환 실패 [$($article.FullName)]: $($_.Exception.Message)") }
            }
        }
        Start-Sleep -Seconds 5
    }
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }

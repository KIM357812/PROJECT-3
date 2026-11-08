#requires -Version 5.1
function Get-NaverGeneratedArticles {
    param([string]$RuntimeRoot, [string[]]$PreviousRuns=@())
    $states = @(Get-ChildItem -LiteralPath (Join-Path $RuntimeRoot '작업대기') -Filter '작업상태.json' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notin $PreviousRuns })
    if ($states.Count -ne 1) { throw '이번 실행의 작업상태를 하나로 확인할 수 없습니다. 이전 글을 사용하지 않습니다.' }
    $state = Get-Content -LiteralPath $states[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.Status -ne '글 작성 완료' -or @($state.Failed).Count -gt 0 -or @($state.Completed).Count -lt 1 -or @($state.Completed).Count -gt 3) {
        throw '이번 새 글 생성이 완료되지 않았습니다. 이전 완성 글을 대신 사용하지 않습니다.'
    }
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $RuntimeRoot '작업완료')).TrimEnd('\')+'\'
    $paths = New-Object System.Collections.ArrayList
    foreach ($completed in @($state.Completed)) {
        $articlePath = [IO.Path]::GetFullPath([string]$completed.Path)
        if (-not $articlePath.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw '완성 글 경로가 네이버 실행 폴더 밖입니다.' }
        if (-not (Test-Path -LiteralPath (Join-Path $articlePath 'Blogger에_붙여넣을_본문.html') -PathType Leaf)) { throw '이번 완성 본문 파일이 없습니다.' }
        [void]$paths.Add($articlePath)
    }
    return @($paths.ToArray())
}

function Get-NaverGeneratedArticle {
    param([string]$RuntimeRoot, [string[]]$PreviousRuns=@())
    $paths = @(Get-NaverGeneratedArticles -RuntimeRoot $RuntimeRoot -PreviousRuns $PreviousRuns)
    if ($paths.Count -ne 1) { throw '단일 완성 글이 필요한 검사에서 결과가 한 건이 아닙니다.' }
    return $paths[0]
}

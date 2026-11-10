#requires -Version 5.1
function Get-NaverGenerationResult {
    param([string]$RuntimeRoot, [string[]]$PreviousRuns=@(), [string]$StatePath='')
    if ($StatePath) {
        $stateFile = Get-Item -LiteralPath $StatePath -ErrorAction Stop
    } else {
        $states = @(Get-ChildItem -LiteralPath (Join-Path $RuntimeRoot '작업대기') -Filter '작업상태.json' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notin $PreviousRuns })
        if ($states.Count -ne 1) { throw '이번 실행의 작업상태를 하나로 확인할 수 없습니다. 이전 글을 사용하지 않습니다.' }
        $stateFile = $states[0]
    }
    $state = Get-Content -LiteralPath $stateFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $completed = @($state.Completed)
    $failed = @($state.Failed | Where-Object { $null -ne $_.Candidate })
    if ($completed.Count -gt 3) { throw '이번 실행의 완성 글이 최대 선택 개수 3건을 초과했습니다.' }
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $RuntimeRoot '작업완료')).TrimEnd('\')+'\'
    $paths = New-Object System.Collections.ArrayList
    foreach ($item in $completed) {
        $articlePath = [IO.Path]::GetFullPath([string]$item.Path)
        if (-not $articlePath.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw '완성 글 경로가 네이버 실행 폴더 밖입니다.' }
        if (-not (Test-Path -LiteralPath (Join-Path $articlePath 'Blogger에_붙여넣을_본문.html') -PathType Leaf)) { throw '이번 완성 본문 파일이 없습니다.' }
        [void]$paths.Add($articlePath)
    }
    [pscustomobject]@{
        statePath = $stateFile.FullName
        status = [string]$state.Status
        completedPaths = @($paths.ToArray())
        completedCount = $paths.Count
        failed = @($failed)
        failedCount = $failed.Count
    }
}

function Get-NaverGeneratedArticles {
    param([string]$RuntimeRoot, [string[]]$PreviousRuns=@(), [string]$StatePath='')
    $result = Get-NaverGenerationResult -RuntimeRoot $RuntimeRoot -PreviousRuns $PreviousRuns -StatePath $StatePath
    if ($result.completedCount -lt 1) { throw '이번 새 글 생성에서 완성된 글이 없습니다. 자동복구 불가 원인을 확인하십시오.' }
    return @($result.completedPaths)
}

function Get-NaverGeneratedArticle {
    param([string]$RuntimeRoot, [string[]]$PreviousRuns=@(), [string]$StatePath='')
    $paths = @(Get-NaverGeneratedArticles -RuntimeRoot $RuntimeRoot -PreviousRuns $PreviousRuns -StatePath $StatePath)
    if ($paths.Count -ne 1) { throw '단일 완성 글이 필요한 검사에서 결과가 한 건이 아닙니다.' }
    return $paths[0]
}

#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$stateScript = Join-Path $projectRoot '프로그램\작업상태.ps1'
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ('네이버 자동화 테스트 ' + [guid]::NewGuid().ToString('N'))
$contentId = 'NTE-20261105-001'

try {
    $created = & $stateScript -Action New -WorkRoot $testRoot -ContentId $contentId | ConvertFrom-Json
    if ($created.status -ne 'Ready' -or $created.currentStage -ne 'Initialized' -or
        $created.nextStage -ne 'CandidateCollection') {
        throw 'A new work item did not receive the expected initial state.'
    }

    $skippedStageWasBlocked = $false
    $skipSourcePath = Join-Path $testRoot '건너뛰기.json'
    '{"test":true}' | Set-Content -LiteralPath $skipSourcePath -Encoding UTF8
    try {
        $null = & $stateScript -Action SaveStage -WorkRoot $testRoot -ContentId $contentId `
            -Stage FactCheck -SourcePath $skipSourcePath
    }
    catch {
        $skippedStageWasBlocked = $true
    }
    if (-not $skippedStageWasBlocked) {
        throw 'A work stage was allowed to skip the candidate collection stage.'
    }

    $duplicateWasBlocked = $false
    try {
        $null = & $stateScript -Action New -WorkRoot $testRoot -ContentId $contentId
    }
    catch {
        $duplicateWasBlocked = $true
    }
    if (-not $duplicateWasBlocked) {
        throw 'An existing work item was overwritten.'
    }

    $sourcePath = Join-Path $testRoot '후보 자료.json'
    '{"test":true}' | Set-Content -LiteralPath $sourcePath -Encoding UTF8
    $saved = & $stateScript -Action SaveStage -WorkRoot $testRoot -ContentId $contentId `
        -Stage CandidateCollection -SourcePath $sourcePath | ConvertFrom-Json
    if ($saved.status -ne 'Completed' -or $saved.nextStage -ne 'FactCheck' -or
        -not (Test-Path -LiteralPath $saved.latestArtifact -PathType Leaf)) {
        throw 'A stage artifact was not saved correctly.'
    }
    $firstArtifact = [string]$saved.latestArtifact

    $savedAgain = & $stateScript -Action SaveStage -WorkRoot $testRoot -ContentId $contentId `
        -Stage CandidateCollection -SourcePath $sourcePath | ConvertFrom-Json
    if ([string]$savedAgain.latestArtifact -eq $firstArtifact -or
        -not (Test-Path -LiteralPath $firstArtifact -PathType Leaf)) {
        throw 'A previous stage artifact was overwritten.'
    }

    $failed = & $stateScript -Action Fail -WorkRoot $testRoot -ContentId $contentId `
        -Message '재시도 가능한 테스트 오류' | ConvertFrom-Json
    if ($failed.status -ne 'Failed' -or $failed.retryCount -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$failed.lastError)) {
        throw 'Failure and retry information was not recorded.'
    }

    $status = & $stateScript -Action Status -WorkRoot $testRoot -ContentId $contentId | ConvertFrom-Json
    if ($status.history.Count -lt 4 -or $status.retryCount -ne 1) {
        throw 'Work history was not preserved.'
    }

    $introId = 'NTE-INTRO-001'
    $introCreated = & $stateScript -Action New -WorkRoot $testRoot -ContentId $introId `
        -WorkType Introduction | ConvertFrom-Json
    if ($introCreated.workType -ne 'Introduction' -or $introCreated.nextStage -ne 'NaverDraft') {
        throw 'An introduction work item did not start at the Naver draft stage.'
    }
    $introSourcePath = Join-Path $testRoot '소개 초안.json'
    '{"draftType":"Introduction"}' | Set-Content -LiteralPath $introSourcePath -Encoding UTF8
    $introSaved = & $stateScript -Action SaveStage -WorkRoot $testRoot -ContentId $introId `
        -Stage NaverDraft -SourcePath $introSourcePath | ConvertFrom-Json
    if ($introSaved.nextStage -ne 'ReadyForEditor' -or
        -not (Test-Path -LiteralPath $introSaved.latestArtifact -PathType Leaf)) {
        throw 'An introduction draft could not be saved directly.'
    }

    $repositoryPathWasBlocked = $false
    try {
        $null = & $stateScript -Action New -WorkRoot (Join-Path $projectRoot '운영자료') -ContentId 'BLOCKED'
    }
    catch {
        $repositoryPathWasBlocked = $true
    }
    if (-not $repositoryPathWasBlocked) {
        throw 'Operational work data was allowed inside the source repository.'
    }

    Write-Output 'Work state tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $tempPrefix = $systemTemp + [System.IO.Path]::DirectorySeparatorChar
        if (-not $resolvedTestRoot.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean a test path outside the system temp directory: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

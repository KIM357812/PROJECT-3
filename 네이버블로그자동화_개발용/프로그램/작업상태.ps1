#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('New', 'SaveStage', 'Fail', 'Status')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$WorkRoot,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$ContentId,

    [ValidateSet('TechnicalArticle', 'Introduction', 'OperatorProfile', 'Policy')]
    [string]$WorkType = 'TechnicalArticle',

    [ValidateSet('CandidateCollection', 'FactCheck', 'NaverDraft')]
    [string]$Stage,

    [string]$SourcePath,

    [string]$Message
)

$ErrorActionPreference = 'Stop'

function Get-NormalizedFullPath {
    param([string]$LiteralPath)
    return [System.IO.Path]::GetFullPath($LiteralPath).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Assert-ExternalWorkRoot {
    param([string]$LiteralPath)
    if ([string]::IsNullOrWhiteSpace($LiteralPath)) {
        throw 'A work root is required.'
    }
    $projectRoot = Get-NormalizedFullPath (Split-Path -Parent $PSScriptRoot)
    $workRootPath = Get-NormalizedFullPath $LiteralPath
    $projectPrefix = $projectRoot + [System.IO.Path]::DirectorySeparatorChar
    if ($workRootPath.Equals($projectRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $workRootPath.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Operational work files must be stored outside the source repository.'
    }
    return $workRootPath
}

function Get-WorkItemPath {
    param(
        [string]$Root,
        [string]$Id
    )
    return Join-Path $Root $Id
}

function Get-StatePath {
    param([string]$ItemPath)
    return Join-Path $ItemPath 'state.json'
}

function Read-WorkState {
    param([string]$ItemPath)
    $statePath = Get-StatePath $ItemPath
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Work state was not found: $statePath"
    }
    return Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-WorkState {
    param(
        [string]$ItemPath,
        [psobject]$State
    )
    $statePath = Get-StatePath $ItemPath
    $State.updatedAt = [datetime]::UtcNow.ToString('o')
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $backupDirectory = Join-Path $ItemPath 'backup'
        $backupName = 'state_{0}_{1}.json' -f `
            [datetime]::UtcNow.ToString('yyyyMMdd_HHmmss_fff'),
            [guid]::NewGuid().ToString('N').Substring(0, 8)
        $backupPath = Join-Path $backupDirectory $backupName
        Copy-Item -LiteralPath $statePath -Destination $backupPath
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Add-StateHistory {
    param(
        [psobject]$State,
        [string]$Event,
        [string]$Detail,
        [string]$Artifact
    )
    $history = @($State.history)
    $history += [pscustomobject]@{
        time = [datetime]::UtcNow.ToString('o')
        event = $Event
        detail = $Detail
        artifact = $Artifact
    }
    $State.history = $history
}

function New-WorkItem {
    param(
        [string]$Root,
        [string]$Id,
        [string]$Type
    )
    $itemPath = Get-WorkItemPath -Root $Root -Id $Id
    if (Test-Path -LiteralPath $itemPath) {
        throw "A work item already exists and will not be overwritten: $itemPath"
    }
    $null = New-Item -ItemType Directory -Path $itemPath
    $null = New-Item -ItemType Directory -Path (Join-Path $itemPath 'output')
    $null = New-Item -ItemType Directory -Path (Join-Path $itemPath 'backup')

    $state = [pscustomobject]@{
        version = 1
        contentId = $Id
        workType = $Type
        status = 'Ready'
        currentStage = 'Initialized'
        nextStage = if ($Type -eq 'TechnicalArticle') { 'CandidateCollection' } else { 'NaverDraft' }
        retryCount = 0
        lastError = ''
        latestArtifact = ''
        createdAt = [datetime]::UtcNow.ToString('o')
        updatedAt = [datetime]::UtcNow.ToString('o')
        history = @()
    }
    Add-StateHistory -State $state -Event 'Created' -Detail 'Work item initialized.' -Artifact ''
    Write-WorkState -ItemPath $itemPath -State $state
    return $state
}

function Save-StageArtifact {
    param(
        [string]$ItemPath,
        [string]$StageName,
        [string]$InputPath
    )
    if ([string]::IsNullOrWhiteSpace($StageName)) {
        throw 'Stage is required for SaveStage.'
    }
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
        throw "Stage source file was not found: $InputPath"
    }

    $state = Read-WorkState -ItemPath $ItemPath
    $stateWorkType = if ($state.PSObject.Properties.Name -contains 'workType') {
        [string]$state.workType
    } else {
        'TechnicalArticle'
    }
    $stageOrder = @{
        'CandidateCollection' = 1
        'FactCheck' = 2
        'NaverDraft' = 3
    }
    $currentOrder = 0
    if ($state.currentStage -ne 'Initialized') {
        if (-not $stageOrder.ContainsKey([string]$state.currentStage)) {
            throw "Unknown current stage: $($state.currentStage)"
        }
        $currentOrder = [int]$stageOrder[[string]$state.currentStage]
    }
    $requestedOrder = [int]$stageOrder[$StageName]
    $nonTechnicalDraftStart = ($stateWorkType -ne 'TechnicalArticle' -and
        $state.currentStage -eq 'Initialized' -and $StageName -eq 'NaverDraft')
    if (-not $nonTechnicalDraftStart -and
        ($requestedOrder -lt $currentOrder -or $requestedOrder -gt ($currentOrder + 1))) {
        throw "Stage order is invalid. Current: $($state.currentStage), requested: $StageName"
    }
    if ($stateWorkType -ne 'TechnicalArticle' -and $StageName -ne 'NaverDraft') {
        throw "Non-technical work items can save only the NaverDraft stage: $stateWorkType"
    }
    $sequence = @($state.history).Count + 1
    $extension = [System.IO.Path]::GetExtension($InputPath)
    if ([string]::IsNullOrWhiteSpace($extension)) {
        $extension = '.json'
    }
    $artifactName = '{0:D3}_{1}{2}' -f $sequence, $StageName, $extension
    $artifactPath = Join-Path (Join-Path $ItemPath 'output') $artifactName
    if (Test-Path -LiteralPath $artifactPath) {
        throw "A stage artifact already exists and will not be overwritten: $artifactPath"
    }
    Copy-Item -LiteralPath $InputPath -Destination $artifactPath

    $state.status = 'Completed'
    $state.currentStage = $StageName
    switch ($StageName) {
        'CandidateCollection' { $state.nextStage = 'FactCheck' }
        'FactCheck' { $state.nextStage = 'NaverDraft' }
        'NaverDraft' { $state.nextStage = 'ReadyForEditor' }
    }
    $state.lastError = ''
    $state.latestArtifact = $artifactPath
    Add-StateHistory -State $state -Event 'StageSaved' -Detail $StageName -Artifact $artifactPath
    Write-WorkState -ItemPath $ItemPath -State $state
    return $state
}

function Set-WorkFailure {
    param(
        [string]$ItemPath,
        [string]$FailureMessage
    )
    if ([string]::IsNullOrWhiteSpace($FailureMessage)) {
        throw 'A failure message is required.'
    }
    $state = Read-WorkState -ItemPath $ItemPath
    $state.status = 'Failed'
    $state.retryCount = [int]$state.retryCount + 1
    $state.lastError = $FailureMessage
    Add-StateHistory -State $state -Event 'Failed' -Detail $FailureMessage -Artifact ''
    Write-WorkState -ItemPath $ItemPath -State $state
    return $state
}

$resolvedWorkRoot = Assert-ExternalWorkRoot $WorkRoot
if (-not (Test-Path -LiteralPath $resolvedWorkRoot -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $resolvedWorkRoot
}
$workItemPath = Get-WorkItemPath -Root $resolvedWorkRoot -Id $ContentId

switch ($Action) {
    'New' {
        $result = New-WorkItem -Root $resolvedWorkRoot -Id $ContentId -Type $WorkType
    }
    'SaveStage' {
        $result = Save-StageArtifact -ItemPath $workItemPath -StageName $Stage -InputPath $SourcePath
    }
    'Fail' {
        $result = Set-WorkFailure -ItemPath $workItemPath -FailureMessage $Message
    }
    'Status' {
        $result = Read-WorkState -ItemPath $workItemPath
    }
}

$result | ConvertTo-Json -Depth 8

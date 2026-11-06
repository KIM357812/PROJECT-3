#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Add', 'Check', 'List')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$RegistryPath,

    [string]$Url,

    [string]$ContentId
)

$ErrorActionPreference = 'Stop'

function Test-AbsoluteHttpsUrl {
    param([string]$Value)
    $uri = $null
    return [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -and
        $uri.Scheme -eq 'https'
}

function Read-CompletedUrlRegistry {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        return [pscustomobject]@{
            version = 1
            completedUrls = @()
        }
    }
    $registry = Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $registry.completedUrls) {
        $registry | Add-Member -NotePropertyName completedUrls -NotePropertyValue @()
    }
    return $registry
}

function Write-CompletedUrlRegistry {
    param(
        [string]$LiteralPath,
        [psobject]$Registry
    )
    $directory = Split-Path -Parent $LiteralPath
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw 'RegistryPath must include a parent directory.'
    }
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory
    }
    if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
        $backupName = '{0}.{1}.backup.json' -f `
            [System.IO.Path]::GetFileNameWithoutExtension($LiteralPath),
            [datetime]::UtcNow.ToString('yyyyMMdd_HHmmss_fff')
        $backupPath = Join-Path $directory $backupName
        Copy-Item -LiteralPath $LiteralPath -Destination $backupPath
    }
    $Registry | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $LiteralPath -Encoding UTF8
}

$registry = Read-CompletedUrlRegistry $RegistryPath
$entries = @($registry.completedUrls)

switch ($Action) {
    'List' {
        $result = $registry
    }
    'Check' {
        if (-not (Test-AbsoluteHttpsUrl $Url)) {
            throw 'Check requires an absolute HTTPS URL.'
        }
        $match = @($entries | Where-Object { [string]$_.url -eq $Url })
        $result = [pscustomobject]@{
            url = $Url
            isCompleted = ($match.Count -gt 0)
            entry = if ($match.Count -gt 0) { $match[0] } else { $null }
        }
    }
    'Add' {
        if (-not (Test-AbsoluteHttpsUrl $Url)) {
            throw 'Add requires an absolute HTTPS URL.'
        }
        if ([string]::IsNullOrWhiteSpace($ContentId)) {
            throw 'Add requires a content ID.'
        }
        if (@($entries | Where-Object { [string]$_.url -eq $Url }).Count -gt 0) {
            throw "The completed URL is already registered: $Url"
        }
        $entries += [pscustomobject]@{
            url = $Url
            contentId = $ContentId
            completedAt = [datetime]::UtcNow.ToString('o')
        }
        $registry.completedUrls = $entries
        Write-CompletedUrlRegistry -LiteralPath $RegistryPath -Registry $registry
        $result = $registry
    }
}

$result | ConvertTo-Json -Depth 6

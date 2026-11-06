$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '공통.ps1')
. (Join-Path $PSScriptRoot '후보준비.ps1')
$prepared = Get-LocalCandidates -Refresh
Write-Host ('오늘의 공개 자료 후보 {0}건을 새로 수집했습니다. {1}' -f @($prepared.Candidates).Count,$prepared.CachePath)

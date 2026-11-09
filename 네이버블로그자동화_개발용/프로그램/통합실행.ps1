#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PackagePath,[switch]$ConnectionTestOnly,[switch]$AllowTagOnlyPublicationSettings)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '통합실행결과검증.ps1')
$package=Get-Content -LiteralPath $PackagePath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($name in @('editorPlan','imageManifest','executionContract')){
    if(-not(Test-Path -LiteralPath ([string]$package.$name) -PathType Leaf)){throw "실행 입력 누락: $name"}
}
$runId=[guid]::NewGuid().ToString()
$root=Join-Path ([IO.Path]::GetDirectoryName($PackagePath)) ('execution-'+$runId)
$null=New-Item -ItemType Directory -Path $root
$statusPath=Join-Path $root 'status.json'
function Set-RunStatus([string]$State,[string]$Message){
    @{runId=$runId;state=$State;message=$Message;updatedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $statusPath -Encoding UTF8
}
$mutex=New-Object Threading.Mutex($false,'Local\NTE-NaverEditorAutomation')
$ownsMutex=$false
try{
    try{$ownsMutex=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$ownsMutex=$true}
    if(-not $ownsMutex){throw '다른 네이버 편집기 자동화가 실행 중입니다.'}
    Set-RunStatus 'CheckingImages' '기사 전용 이미지와 작업 계획을 동기화하고 출처·고유성·크기·용량을 검사합니다.'
    $sourceArticlePath=if($package.sourceArticlePath){[string]$package.sourceArticlePath}else{''}
    $imageCheck=& (Join-Path $PSScriptRoot '이미지자동복구.ps1') -ManifestPath $package.imageManifest -SourceArticlePath $sourceArticlePath|ConvertFrom-Json
    if(-not $imageCheck.isValid){throw '최종 이미지 파일 독립 검사 실패'}
    Set-RunStatus 'CheckingBrowser' '자동화 전용 Chrome 직접 연결을 확인합니다.'
    $preflight=& (Join-Path $PSScriptRoot '크롬직접연결.ps1') -PackagePath $PackagePath -RunDirectory $root -ConnectionTestOnly|ConvertFrom-Json
    $preflight|Add-Member -NotePropertyName runId -NotePropertyValue $runId -Force
    Assert-NaverBrowserPreflight $preflight $runId
    if($ConnectionTestOnly){
        Set-RunStatus 'ConnectionVerified' 'ChatGPT 중계 없이 전용 Chrome 연결을 확인했습니다.'
        $preflight|ConvertTo-Json -Depth 10
        return
    }
    Set-RunStatus 'Executing' '전용 Chrome에서 새 네이버 편집기를 열고 계획을 입력합니다.'
    $out=& (Join-Path $PSScriptRoot '크롬직접연결.ps1') -PackagePath $PackagePath -RunDirectory $root -TargetId ([string]$preflight.tabId) -AllowTagOnlyPublicationSettings:$AllowTagOnlyPublicationSettings|ConvertFrom-Json
    $out|Add-Member -NotePropertyName runId -NotePropertyValue $runId -Force
    if($out.status -eq 'Blocked'){
        Set-RunStatus 'Blocked' ([string]$out.reason)
        $out|ConvertTo-Json -Depth 10
        return
    }
    Assert-NaverRunResult $out $runId $root ([string]$package.editorPlan) ([bool]$AllowTagOnlyPublicationSettings)
    Set-RunStatus 'Verified' '새 글 편집창 입력 및 두 번째 검증 통과'
    $out|ConvertTo-Json -Depth 10
}catch{
    Set-RunStatus 'Blocked' $_.Exception.Message
    throw
}finally{
    if($ownsMutex){$mutex.ReleaseMutex()};$mutex.Dispose()
}

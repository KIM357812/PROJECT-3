#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CommonPath,
    [Parameter(Mandatory=$true)][string]$PromptPath,
    [Parameter(Mandatory=$true)][string]$ItemPath,
    [Parameter(Mandatory=$true)][string]$ExistingContextPath,
    [Parameter(Mandatory=$true)][string]$AllowedRelatedUrlsPath,
    [Parameter(Mandatory=$true)][string]$RunPath,
    [Parameter(Mandatory=$true)][string]$ResultPath,
    [Parameter(Mandatory=$true)][string]$RecoveryStatePath
)

$ErrorActionPreference='Stop'
. $CommonPath
$item=Get-Content -LiteralPath $ItemPath -Raw -Encoding UTF8|ConvertFrom-Json
$writePrompt=[IO.File]::ReadAllText($PromptPath,[Text.Encoding]::UTF8)
$existingContext=[IO.File]::ReadAllText($ExistingContextPath,[Text.Encoding]::UTF8)
$allowedRelatedUrls=@(Get-Content -LiteralPath $AllowedRelatedUrlsPath -Raw -Encoding UTF8|ConvertFrom-Json)
$prompt=$writePrompt.TrimEnd()+"`n`n"+$existingContext+"`n`n"+$item.Details+"`n`n기사 원문 URL: "+$item.Url+"`n"
$article=$null
$lastValidationMessage=''
function Get-RecoveryErrorCode([string]$Message){
    if($Message -match '사실|수치|날짜|기관|근거'){return 'FactValidation'}
    if($Message -match '출처|링크|URL|관련 글'){return 'SourceLinkStructure'}
    if($Message -match 'HTML|태그|블록|구조|소제목|강조'){return 'DocumentStructure'}
    return 'ArticleGeneration'
}
function Save-RecoveryState([int]$Stage,[string]$Status,[int]$Attempt,[string]$ErrorCode='',[string]$Message=''){
    $passedStages=if($Stage -gt 1){@(1..($Stage-1))}else{@()}
    Write-JsonAtomic $RecoveryStatePath ([pscustomobject]@{
        schemaVersion=1;number=[int]$item.Number;url=[string]$item.Url;currentStage=$Stage
        passedStages=$passedStages
        status=$Status;automaticRecoveryAttempt=$Attempt;errorCode=$ErrorCode
        lastValidationMessage=$Message;updatedAt=(Get-Date).ToString('o')
    }) 8
}
Save-RecoveryState 4 'Running' 0
for($generationAttempt=1;$generationAttempt -le 3;$generationAttempt++){
    Save-RecoveryState 4 'Recovering' $generationAttempt (Get-RecoveryErrorCode $lastValidationMessage) $lastValidationMessage
    $attemptPrompt=$prompt
    if($lastValidationMessage){
        $attemptPrompt+="`n이전 생성 결과는 다음 자동 검증을 통과하지 못했습니다: $lastValidationMessage`n기사와 원문은 유효하므로 소재를 버리지 말고 정해진 출력 구조를 정확히 고쳐 전체 글을 다시 생성하세요.`n"
    }
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $rawPath=Join-Path $RunPath ('{0:D2}_글쓰기_원본_{1}_{2}.txt' -f ([int]$item.Number),$stamp,$generationAttempt)
    $response=Invoke-Codex $attemptPrompt $rawPath
    $repairPath=Join-Path $RunPath ('{0:D2}_사실검증보완_{1}_{2}.txt' -f ([int]$item.Number),$stamp,$generationAttempt)
    try{
        $article=Resolve-ArticleWithFactCheckRepair $response $item.Site $item.Url $allowedRelatedUrls $repairPath
        break
    }catch{
        $lastValidationMessage=$_.Exception.Message
        Write-ErrorLog ("{0}번 글 내부 자동복구 {1}/3: {2}" -f $item.Number,$generationAttempt,$lastValidationMessage)
        if($generationAttempt -ge 3){
            Save-RecoveryState 4 'Unresolved' $generationAttempt (Get-RecoveryErrorCode $lastValidationMessage) $lastValidationMessage
            throw
        }
    }
}
if($null -eq $article){throw '유효한 기사 글의 자동 생성과 재검증을 완료하지 못했습니다.'}
$article|Export-Clixml -LiteralPath $ResultPath -Depth 20 -Encoding UTF8
Save-RecoveryState 4 'Completed' $generationAttempt
[pscustomobject]@{Number=[int]$item.Number;ResultPath=$ResultPath;Succeeded=$true}

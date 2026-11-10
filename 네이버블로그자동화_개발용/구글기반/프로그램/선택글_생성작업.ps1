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
Save-RecoveryState 4 'Recovering' 0
$generationAttempt=1
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$rawPath=Join-Path $RunPath ('{0:D2}_글쓰기_원본_{1}.txt' -f ([int]$item.Number),$stamp)
$response=Invoke-Codex $prompt $rawPath
$hasArticleEnvelope=($response -match '(?is)<div\b' -and $response -match '(?m)^## 1\. SEO 키워드 분석\s*$' -and $response -match '(?m)^## 5\. 해시태그\s*$')
if(-not $hasArticleEnvelope){
    $generationAttempt=2
    Save-RecoveryState 4 'Recovering' $generationAttempt 'ModelContract' '콘텐츠 생성 응답 형식이 아니므로 같은 생성 단계만 한 번 다시 실행합니다.'
    $retryPrompt=$prompt+"`n`n중요: 이 요청은 소프트웨어 개발이나 브라우저 조작이 아닙니다. 파일을 읽거나 프로그램을 수정하지 말고, 위 출력 형식의 블로그 글 본문과 메타데이터만 응답하세요."
    $rawPath=Join-Path $RunPath ('{0:D2}_글쓰기_원본_{1}_형식복구.txt' -f ([int]$item.Number),$stamp)
    $response=Invoke-Codex $retryPrompt $rawPath
}
$repairPath=Join-Path $RunPath ('{0:D2}_사실검증보완_{1}.txt' -f ([int]$item.Number),$stamp)
try {
    $article=Resolve-ArticleWithFactCheckRepair $response $item.Site $item.Url $allowedRelatedUrls $repairPath
} catch {
    $message=$_.Exception.Message
    Save-RecoveryState 4 'Unresolved' 1 (Get-RecoveryErrorCode $message) $message
    throw
}
if($null -eq $article){throw '유효한 기사 글의 자동 생성과 재검증을 완료하지 못했습니다.'}
$article|Export-Clixml -LiteralPath $ResultPath -Depth 20 -Encoding UTF8
Save-RecoveryState 4 'Completed' $generationAttempt
[pscustomobject]@{Number=[int]$item.Number;ResultPath=$ResultPath;Succeeded=$true}

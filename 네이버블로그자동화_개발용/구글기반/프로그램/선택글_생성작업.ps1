#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CommonPath,
    [Parameter(Mandatory=$true)][string]$PromptPath,
    [Parameter(Mandatory=$true)][string]$ItemPath,
    [Parameter(Mandatory=$true)][string]$ExistingContextPath,
    [Parameter(Mandatory=$true)][string]$AllowedRelatedUrlsPath,
    [Parameter(Mandatory=$true)][string]$RunPath,
    [Parameter(Mandatory=$true)][string]$ResultPath
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
for($generationAttempt=1;$generationAttempt -le 3;$generationAttempt++){
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
        if($generationAttempt -ge 3){throw}
    }
}
if($null -eq $article){throw '유효한 기사 글의 자동 생성과 재검증을 완료하지 못했습니다.'}
$article|Export-Clixml -LiteralPath $ResultPath -Depth 20 -Encoding UTF8
[pscustomobject]@{Number=[int]$item.Number;ResultPath=$ResultPath;Succeeded=$true}

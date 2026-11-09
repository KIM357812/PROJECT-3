#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath (Join-Path $root '네이버통합설정.json') -Raw -Encoding UTF8|ConvertFrom-Json
$workflow=$config.Workflow
foreach($name in @('ModifyExistingPosts','DeleteExistingPosts','ModifyBlogSettings','ChangePublicationState','RequireExactTargetSelection','RequireOperatorConfirmation','RequireDeleteOrPublishReconfirmation')){
    if(-not [bool]$workflow.$name){throw "Operator capability policy is missing: $name"}
}
$requirements=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $root) 'DEVELOPMENT_REQUIREMENTS.md') -Raw -Encoding UTF8
if($requirements -notmatch '기존 공개·비공개 글 수정·재작성·삭제' -or $requirements -notmatch '선택하지 않은 다른 글과 설정은 변경하지 않는다'){throw 'Operator capability requirements are incomplete.'}
'Operator capability policy tests passed.'

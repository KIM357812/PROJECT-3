#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../프로그램/새글생성결과검증.ps1')
$root=Join-Path $env:TEMP ('naver-newarticle-test-'+[guid]::NewGuid())
try {
    $article=Join-Path $root '작업완료/old';$run=Join-Path $root '작업대기/new'
    $null=New-Item -ItemType Directory -Path $article,$run -Force
    'old article' | Set-Content -LiteralPath (Join-Path $article 'Blogger에_붙여넣을_본문.html')
    $rejected=$false;try{$null=Get-NaverGeneratedArticle $root}catch{$rejected=$true}
    if(-not $rejected){throw 'Old article accepted without current run'}
    $statePath=Join-Path $run '작업상태.json'
    @{Status='실패';Failed=@(@{Candidate=@{Number=1;Title='실패 글'};Message='error'});Completed=@()} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    $rejected=$false;try{$null=Get-NaverGeneratedArticle $root}catch{$rejected=$true}
    if(-not $rejected){throw 'Failed run accepted'}
    $newArticle=Join-Path $root '작업완료/new';$null=New-Item -ItemType Directory -Path $newArticle
    'new article' | Set-Content -LiteralPath (Join-Path $newArticle 'Blogger에_붙여넣을_본문.html')
    @{Status='글 작성 완료';Failed=@();Completed=@(@{Path=$newArticle})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    if((Get-NaverGeneratedArticle $root) -ne $newArticle){throw 'Wrong article returned'}
    $secondArticle=Join-Path $root '작업완료/second';$null=New-Item -ItemType Directory -Path $secondArticle
    'second article' | Set-Content -LiteralPath (Join-Path $secondArticle 'Blogger에_붙여넣을_본문.html')
    @{Status='글 작성 완료';Failed=@();Completed=@(@{Path=$newArticle},@{Path=$secondArticle})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    $multiple=@(Get-NaverGeneratedArticles $root)
    if($multiple.Count -ne 2 -or $multiple[0] -ne $newArticle -or $multiple[1] -ne $secondArticle){throw 'Multiple articles or selection order was not preserved'}
    $rejected=$false;try{$null=Get-NaverGeneratedArticle $root @($statePath)}catch{$rejected=$true}
    if(-not $rejected){throw 'Previous run accepted as new'}
    @{Status='부분 완료';Failed=@(@{Candidate=@{Number=2;Title='다시 작성할 글'};Message='fixture failure'});Completed=@(@{Path=$newArticle})} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
    $partial=Get-NaverGenerationResult -RuntimeRoot $root -StatePath $statePath
    if($partial.completedCount -ne 1 -or $partial.failedCount -ne 1 -or $partial.completedPaths[0] -ne $newArticle){throw 'Partial success was not preserved'}
    if((Get-NaverGeneratedArticle -RuntimeRoot $root -StatePath $statePath) -ne $newArticle){throw 'Completed article in partial run was rejected'}
    @{Status='글 작성 완료';Failed=@();Completed=@(@{Path=$env:TEMP})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    $rejected=$false;try{$null=Get-NaverGeneratedArticle $root}catch{$rejected=$true}
    if(-not $rejected){throw 'Outside path accepted'}
    'New article result regression tests: PASS'
} finally {
    if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}

#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '구글기반\프로그램\선택글_생성작업.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('NTE-Parallel-'+[guid]::NewGuid().ToString('N'))
try{
    $null=New-Item -ItemType Directory -Path $temp
    $common=Join-Path $temp '공통.ps1'
    @'
$script:Utf8=New-Object Text.UTF8Encoding($false)
function Invoke-Codex([string]$prompt,[string]$path){[IO.File]::WriteAllText($path,'mock',$script:Utf8);return 'mock'}
function Resolve-ArticleWithFactCheckRepair([string]$response,[string]$site,[string]$url,[object[]]$allowed,[string]$path){return [pscustomobject]@{Html='<div>ok</div>';Metadata='ok';FactCheck='ok';ImagePrompts='ok';ImageFiles=@('a.jpg');RecommendedTitle=('완성 '+$site);VisibleTextLength=100}}
function Write-ErrorLog([string]$message){}
'@|Set-Content -LiteralPath $common -Encoding UTF8
    $prompt=Join-Path $temp 'prompt.md';'prompt'|Set-Content -LiteralPath $prompt -Encoding UTF8
    $context=Join-Path $temp 'context.txt';'context'|Set-Content -LiteralPath $context -Encoding UTF8
    $urls=Join-Path $temp 'urls.json';'[]'|Set-Content -LiteralPath $urls -Encoding UTF8
    $jobs=@()
    foreach($number in 1,2){
        $item=Join-Path $temp ("item-$number.json")
        @{Number=$number;Site="Site$number";Url="https://example.com/$number";Details='details'}|ConvertTo-Json|Set-Content -LiteralPath $item -Encoding UTF8
        $result=Join-Path $temp ("result-$number.clixml")
        $jobs+=Start-Job -FilePath $worker -ArgumentList @($common,$prompt,$item,$context,$urls,$temp,$result)
    }
    $null=$jobs|Wait-Job
    foreach($job in $jobs){$null=Receive-Job $job -ErrorAction Stop;if($job.State -ne 'Completed'){throw 'Parallel article worker did not complete.'}}
    if(@(Get-ChildItem -LiteralPath $temp -Filter 'result-*.clixml').Count -ne 2){throw 'Parallel article results were not preserved independently.'}
    'Selected article parallel generation tests passed.'
}finally{
    if($jobs){$jobs|Remove-Job -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}

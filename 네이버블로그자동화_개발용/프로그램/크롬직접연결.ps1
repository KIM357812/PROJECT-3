#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PackagePath,
    [Parameter(Mandatory=$true)][string]$RunDirectory,
    [switch]$ConnectionTestOnly,
    [switch]$AllowTagOnlyPublicationSettings
)
$ErrorActionPreference='Stop'

function Get-ChromeExecutable {
    $pf86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $candidates=@(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        $(if($pf86){Join-Path $pf86 'Google\Chrome\Application\chrome.exe'}),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
    if(@($candidates).Count -lt 1){throw 'CHROME_NOT_INSTALLED: Google Chrome을 찾을 수 없습니다.'}
    return [IO.Path]::GetFullPath([string](@($candidates)[0]))
}

function Test-DevTools([int]$Port) {
    try {
        $null=Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/json/version" -f $Port) -TimeoutSec 2
        return $true
    } catch { return $false }
}

if(-not $ConnectionTestOnly -and ([string]::IsNullOrWhiteSpace($PackagePath) -or -not(Test-Path -LiteralPath $PackagePath -PathType Leaf))){throw 'PACKAGE_PATH_REQUIRED'}
$configPath=Join-Path (Split-Path -Parent $PSScriptRoot) '네이버통합설정.json'
$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json
$browser=$config.BrowserAutomation
if($null -eq $browser -or [string]$browser.Mode -ne 'ChromeDevTools'){throw 'BROWSER_AUTOMATION_CONFIGURATION_MISSING'}
$port=[int]$browser.DebugPort
$profileRoot=[Environment]::ExpandEnvironmentVariables([string]$browser.ProfileRoot)
if([string]::IsNullOrWhiteSpace($profileRoot)){throw 'CHROME_PROFILE_ROOT_MISSING'}
$profileRoot=[IO.Path]::GetFullPath($profileRoot)
$repoRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')+'\'
if(($profileRoot.TrimEnd('\')+'\').StartsWith($repoRoot,[StringComparison]::OrdinalIgnoreCase)){
    throw 'CHROME_PROFILE_MUST_BE_OUTSIDE_REPOSITORY'
}
$null=New-Item -ItemType Directory -Path $profileRoot -Force
$null=New-Item -ItemType Directory -Path $RunDirectory -Force

if(-not(Test-DevTools $port)){
    $chrome=Get-ChromeExecutable
    $arguments=@(
        "--remote-debugging-port=$port",
        "--user-data-dir=$profileRoot",
        '--profile-directory=Default',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-session-crashed-bubble',
        '--remote-allow-origins=*',
        [string]$config.Naver.BlogUrl
    )
    Start-Process -FilePath $chrome -ArgumentList $arguments | Out-Null
    $deadline=(Get-Date).AddSeconds(25)
    while((Get-Date)-lt $deadline -and -not(Test-DevTools $port)){Start-Sleep -Milliseconds 250}
    if(-not(Test-DevTools $port)){throw 'CHROME_DEVTOOLS_START_FAILED'}
}

$node=(Get-Command node -ErrorAction Stop).Source
$runner=Join-Path $PSScriptRoot '크롬직접실행.mjs'
$resultPath=Join-Path $RunDirectory $(if($ConnectionTestOnly){'browser-preflight.json'}else{'result.json'})
$args=@($runner,'--mode',$(if($ConnectionTestOnly){'preflight'}else{'execute'}),'--port',[string]$port,'--package',$(if($PackagePath){$PackagePath}else{'-'}),'--run-dir',$RunDirectory,'--result',$resultPath,'--blog-id',[string]$config.Naver.BlogId,'--blog-url',[string]$config.Naver.BlogUrl,'--write-url',[string]$config.Naver.WriteUrl)
if($AllowTagOnlyPublicationSettings){$args+=@('--allow-tag-only-publication-settings','true')}
& $node @args
if($LASTEXITCODE -ne 0){throw "CHROME_DIRECT_RUNNER_FAILED: 종료 코드 $LASTEXITCODE"}
if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'CHROME_DIRECT_RESULT_MISSING'}
Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8

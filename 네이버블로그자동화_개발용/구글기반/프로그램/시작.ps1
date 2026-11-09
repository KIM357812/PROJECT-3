param([switch]$NoWatcher,[switch]$CandidatePreview,[switch]$CachedOnly,[string]$SearchResponsePath,[switch]$AutoStart,[switch]$ImageStatusOnly,[switch]$PreflightOnly,[switch]$RetryLatest,[string]$RetryStatePath='')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '공통.ps1')
. (Join-Path $PSScriptRoot '후보준비.ps1')

function Show-Preflight {
    $checks = @(Test-ProgramEnvironment -RequireBrowser)
    foreach ($check in $checks) {
        $mark = if ($check.Ok) { '[정상]' } else { '[확인 필요]' }
        Write-Host ("{0} {1}: {2}" -f $mark,$check.Name,$check.Detail) -ForegroundColor $(if($check.Ok){'Green'}else{'Red'})
    }
    if (@($checks | Where-Object { -not $_.Ok }).Count) { throw '실행 전 점검에서 확인이 필요한 항목이 있습니다.' }
}

function Invoke-SelectedArticles([string]$run,[object[]]$selected,[object]$state) {
    $writePrompt = [IO.File]::ReadAllText((Join-Path $script:PromptDir '02_최종_글쓰기_프롬프트.md'),[Text.Encoding]::UTF8)
    $existingPosts = @(Get-ExistingPosts)
    $existingPostContext = Format-ExistingPostContext $existingPosts
    $allowedRelatedUrls = @($existingPosts | ForEach-Object Url)
    Write-Host ("기존 게시글 {0}건을 중복·관련 글 점검에 사용합니다." -f $existingPosts.Count)
    $completed = New-Object System.Collections.ArrayList
    foreach ($old in @($state.Completed)) { [void]$completed.Add($old) }
    $failed = New-Object System.Collections.ArrayList
    $commonPath=Join-Path $PSScriptRoot '공통.ps1'
    $workerPath=Join-Path $PSScriptRoot '선택글_생성작업.ps1'
    $promptPath=Join-Path $script:PromptDir '02_최종_글쓰기_프롬프트.md'
    $sharedPath=Join-Path $run '공통실행자료'
    [IO.Directory]::CreateDirectory($sharedPath)|Out-Null
    [IO.File]::WriteAllText((Join-Path $sharedPath '기존글문맥.txt'),$existingPostContext,$script:Utf8)
    Write-JsonAtomic (Join-Path $sharedPath '관련글허용주소.json') @($allowedRelatedUrls) 5
    $pending=@($selected)
    $maximumParallel=2
    for($offset=0;$offset -lt $pending.Count;$offset+=$maximumParallel){
        $batch=@($pending[$offset..([Math]::Min($offset+$maximumParallel-1,$pending.Count-1))])
        $jobs=New-Object System.Collections.ArrayList
        foreach($item in $batch){
            Write-Host ("{0}번 글을 작성하고 있습니다." -f $item.Number)
            $itemPath=Join-Path $sharedPath ('선택기사_{0}.json' -f [int]$item.Number)
            $resultPath=Join-Path $sharedPath ('생성결과_{0}.clixml' -f [int]$item.Number)
            Write-JsonAtomic $itemPath $item 12
            $job=Start-Job -FilePath $workerPath -ArgumentList @($commonPath,$promptPath,$itemPath,(Join-Path $sharedPath '기존글문맥.txt'),(Join-Path $sharedPath '관련글허용주소.json'),$run,$resultPath)
            [void]$jobs.Add([pscustomobject]@{Job=$job;Item=$item;ResultPath=$resultPath})
        }
        foreach($entry in @($jobs)){
            $item=$entry.Item
            try{
                $null=Wait-Job -Job $entry.Job
                $jobOutput=@(Receive-Job -Job $entry.Job -ErrorAction Stop)
                if($entry.Job.State -ne 'Completed' -or -not(Test-Path -LiteralPath $entry.ResultPath -PathType Leaf)){
                    $reason=if($entry.Job.ChildJobs[0].JobStateInfo.Reason){$entry.Job.ChildJobs[0].JobStateInfo.Reason.Message}else{'병렬 글 생성 결과가 없습니다.'}
                    throw $reason
                }
                $article=Import-Clixml -LiteralPath $entry.ResultPath
                $path=Save-Article $item $article
                Add-UsedUrl $item.Url
                [void]$completed.Add([pscustomobject]@{Number=$item.Number;Path=$path;CompletedAt=(Get-Date).ToString('o')})
                Write-Host "완료: $path"
            }catch{
                $message="$($item.Number)번 소재 실패: $($_.Exception.Message)"
                [void]$failed.Add([pscustomobject]@{Candidate=$item;Message=$message;FailedAt=(Get-Date).ToString('o')})
                Write-ErrorLog $message
            }finally{
                if($null -ne $entry.Job){Remove-Job -Job $entry.Job -Force -ErrorAction SilentlyContinue}
            }
            $state.Completed=@($completed);$state.Failed=@($failed)
            $state.Status=if($failed.Count){'일부 실패'}else{'작성 중'}
            Save-RunState $run $state
        }
    }
    $state.Status = if ($failed.Count -eq 0) { '글 작성 완료' } elseif ($completed.Count) { '일부 실패' } else { '실패' }
    Save-RunState $run $state
    if ($completed.Count) {
        $lastPath = [string]$completed[$completed.Count-1].Path
        if (-not $env:NAVER_AUTOMATION_NO_OPEN) { Invoke-Item (Split-Path $lastPath -Parent) }
        Write-Host ("글 작성 결과: 완료 {0}건, 실패 {1}건. 각 글의 원본이미지 폴더에 이미지 4장을 넣으세요." -f $completed.Count,$failed.Count)
    } else { Write-Host '완료된 글이 없습니다. 오류기록을 확인하세요.' -ForegroundColor Red }
}

function Start-Workflow {
    Assert-ProgramEnvironment | Out-Null
    $run = New-RunDirectory '글작성'
    $state = [pscustomobject]@{ Version=1; Status='소재 검색 중'; CreatedAt=(Get-Date).ToString('o'); UpdatedAt=(Get-Date).ToString('o'); Candidates=@(); SelectedNumbers=@(); Completed=@(); Failed=@() }
    Save-RunState $run $state
    $searchPrompt = [IO.File]::ReadAllText((Join-Path $script:PromptDir '01_소재_URL_프롬프트.md'),[Text.Encoding]::UTF8)
    Write-Host '최신 소재를 찾고 있습니다. 잠시 기다려 주세요.'
    try {
        try {
            $prepared = Get-LocalCandidates -CachedOnly:$CachedOnly
            $searchPrompt = New-CandidateSearchPrompt $searchPrompt $prepared
            Write-Host ('공개 자료 후보 {0}건 준비{1}. 원문 검증을 시작합니다.' -f @($prepared.Candidates).Count,$(if($prepared.Cached){' (오늘 저장 목록 사용)'}else{''}))
        } catch {
            if ($CachedOnly) { throw }
            Write-ErrorLog ('로컬 후보 수집 실패, 기존 검색 사용: '+$_.Exception.Message)
            $searchPrompt = New-CandidateSearchPrompt $searchPrompt $null
        }
        if ($SearchResponsePath) {
            if (-not $CandidatePreview) { throw '저장 응답 재생은 소재 목록 시험에서만 사용할 수 있습니다.' }
            $searchResponse = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $SearchResponsePath).Path,[Text.Encoding]::UTF8)
            [IO.File]::WriteAllText((Join-Path $run '소재검색_원본.txt'),$searchResponse,$script:Utf8)
        } else { $searchResponse = Invoke-Codex $searchPrompt (Join-Path $run '소재검색_원본.txt') }
        $candidates = @(Select-ValidCandidates @(Get-Candidates $searchResponse))
        if (-not $candidates.Count) { throw '검증 가능한 소재 번호와 기사 URL을 찾지 못했습니다.' }
        $state.Candidates=$candidates; $state.Status='소재 선택 대기'; Save-RunState $run $state
        Write-Host (Format-CandidateList $candidates)
        if ($CandidatePreview) { Write-Host ('소재 목록 시험 성공: {0}건. 기록: {1}' -f $candidates.Count,$run); return }
        $selected = @(Read-CandidateSelection $candidates)
        if (-not $selected.Count) { $state.Status='사용자 취소'; Save-RunState $run $state; return }
        $state.SelectedNumbers=@($selected|ForEach-Object Number); $state.Status='글 작성 중'; Save-RunState $run $state
        Invoke-SelectedArticles $run $selected $state
    } catch {
        $state.Status='실패'; $state.Failed=@([pscustomobject]@{Candidate=$null;Message=$_.Exception.Message;FailedAt=(Get-Date).ToString('o')}); Save-RunState $run $state
        Write-ErrorLog ('소재 검색 또는 선택 실패: '+$_.Exception.Message)
        Write-Host ('소재 검색 또는 선택 실패: '+$_.Exception.Message) -ForegroundColor Red
        if ($CandidatePreview) { throw }
    }
}

function Retry-LatestRun([string]$StatePath='') {
    Assert-ProgramEnvironment | Out-Null
    $run=if($StatePath){Split-Path -Parent ([IO.Path]::GetFullPath($StatePath))}else{Get-LatestRetryableRun}
    if (-not $run) { Write-Host '재시도할 실패 작업이 없습니다.'; return }
    if($StatePath -and -not(Test-Path -LiteralPath (Join-Path $run '작업상태.json') -PathType Leaf)){throw '지정한 실패 작업 상태를 찾을 수 없습니다.'}
    $state=Read-RunState $run
    $selected=@($state.Failed|Where-Object {$null -ne $_.Candidate}|ForEach-Object Candidate)
    if (-not $selected.Count) { Write-Host '글 작성 단계에서 재시도할 소재가 없습니다.'; return }
    $state.Failed=@();$state.Status='재시도 중';Save-RunState $run $state
    Invoke-SelectedArticles $run $selected $state
}

function Show-ImageStatus {
    $folders=@(Get-ChildItem -LiteralPath $script:CompleteDir -Directory|ForEach-Object {Get-ChildItem -LiteralPath $_.FullName -Directory})
    if (-not $folders.Count) { Write-Host '작성된 글이 아직 없습니다.'; return }
    foreach($folder in $folders){
        $source=Join-Path $folder.FullName '원본이미지';$target=Join-Path $folder.FullName '압축이미지'
        $count=@(Get-ChildItem -LiteralPath $source -File|Where-Object Extension -Match '^\.(jpg|jpeg|png|webp)$').Count
        $done=@(Get-ChildItem -LiteralPath $target -File -Filter '*.webp').Count
        if($count -eq 4 -and $done -eq 0){
            try {
                Write-Host ("{0}: 원본 4장을 확인했습니다. WebP 변환을 시작합니다." -f $folder.Name)
                Process-Images $folder.FullName | Out-Null
                $done=@(Get-ChildItem -LiteralPath $target -File -Filter '*.webp').Count
                Write-Host ("{0}: WebP {1}장 자동 변환 완료" -f $folder.Name,$done) -ForegroundColor Green
            } catch {
                Write-ErrorLog ("이미지 수동 확인 변환 실패 [$($folder.FullName)]: $($_.Exception.Message)")
                Write-Host ("{0}: 이미지 변환 실패 — {1}" -f $folder.Name,$_.Exception.Message) -ForegroundColor Red
            }
        }
        $difference=if($count -lt 4){'부족 '+(4-$count)+'장'}elseif($count -gt 4){'초과 '+($count-4)+'장'}else{'4장 확인'}
        $bloggerImages=Get-BloggerHostedImageCount $folder.FullName
        Write-Host ("{0}: 원본 {1}장 ({2}), WebP {3}장, Blogger 실제 이미지 {4}/4" -f $folder.Name,$count,$difference,$done,$bloggerImages)
    }
}

if($PreflightOnly){Show-Preflight;return};if($ImageStatusOnly){Show-ImageStatus;return};if($RetryLatest){Retry-LatestRun $RetryStatePath;return};if($CandidatePreview -or $AutoStart){Start-Workflow;return}
if(-not $NoWatcher){$watcher=Join-Path $PSScriptRoot '이미지_감시.ps1';Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$watcher+'"')) -WindowStyle Hidden|Out-Null}
Write-Host '블로그 통합 자동화';Write-Host '명령: 시작 / 재시도 / 이미지 / 점검 / 종료'
while($true){$answer=Read-Host '명령';if($null -eq $answer){break};$command=$answer.Trim();switch($command){'시작'{Start-Workflow};'재시도'{Retry-LatestRun};'이미지'{Show-ImageStatus};'점검'{Show-Preflight};'종료'{break};default{Write-Host '시작, 재시도, 이미지, 점검, 종료 중 하나를 입력하세요.'}};if($command -eq '종료'){break}}

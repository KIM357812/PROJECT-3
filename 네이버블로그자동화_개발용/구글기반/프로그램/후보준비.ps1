. (Join-Path $PSScriptRoot '후보수집.ps1')

$script:CandidateLog = Join-Path $script:RuntimeRoot '기록\후보수집_로그.txt'
$script:UsedUrlPath = Join-Path $script:RuntimeRoot '기록\작성한_URL.txt'

function Get-UsedUrls {
    $used = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if ([IO.File]::Exists($script:UsedUrlPath)) {
        foreach ($line in [IO.File]::ReadAllLines($script:UsedUrlPath,[Text.Encoding]::UTF8)) {
            $url = Normalize-ArticleUrl $line 'https://example.com'
            if ($url) { [void]$used.Add($url) }
        }
    }
    # URL 기록 직전 프로그램이 중단되어도 이미 저장된 글은 다시 선택하지 않습니다.
    foreach ($infoPath in @(Get-ChildItem -LiteralPath $script:CompleteDir -File -Filter '작업정보.json' -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)) {
        try {
            $info = [IO.File]::ReadAllText($infoPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
            $url = Normalize-ArticleUrl ([string]$info.Url) 'https://example.com'
            if ($url) { [void]$used.Add($url) }
        } catch { Write-ErrorLog ('작업정보 URL 읽기 실패: '+$infoPath+' / '+$_.Exception.Message) }
    }
    return ,$used
}

function Add-UsedUrl([string]$url) {
    $clean = Normalize-ArticleUrl $url 'https://example.com'
    if (-not $clean) { throw '작성한 기사 URL을 기록할 수 없습니다.' }
    $used = Get-UsedUrls
    if (-not $used.Contains($clean)) { [IO.File]::AppendAllText($script:UsedUrlPath,$clean+[Environment]::NewLine,$script:Utf8) }
}

function Write-CandidateLog([object[]]$results,[bool]$cached) {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($result in $results) {
        $lines.Add(('[{0}] 사이트={1} 상태={2} 소요초={3} 후보수={4} 출처={5} 캐시={6} 오류={7}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$result.Site,$result.Status,$result.Seconds,$result.Count,$result.Method,$cached,$result.Error))
    }
    [IO.File]::AppendAllText($script:CandidateLog,($lines -join [Environment]::NewLine)+[Environment]::NewLine,$script:Utf8)
}

function Get-LocalCandidates([switch]$Refresh, [switch]$CachedOnly) {
    $today = Get-Date
    $cachePath = Join-Path $script:RuntimeRoot ('기록\후보목록_{0}.json' -f $today.ToString('yyyy-MM-dd'))
    $cached = $false
    $results = @()
    $previous = @()
    if ([IO.File]::Exists($cachePath)) {
        try {
            $cache = [IO.File]::ReadAllText($cachePath,[Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($cache.Date -eq $today.ToString('yyyy-MM-dd') -and @($cache.Results).Count -eq 8) {
                $previous = @($cache.Results)
                if (-not $Refresh -and @($previous | Where-Object { $_.Count -gt 0 }).Count -gt 0) { $results = $previous; $cached = $true }
            }
        } catch { Write-ErrorLog ('후보 캐시 읽기 실패: '+$_.Exception.Message) }
    }
    if ($CachedOnly -and -not $cached) { throw '오늘 저장된 후보 캐시가 없어 시험을 중단합니다. 재수집하지 않습니다.' }
    if (-not $cached) {
        $jobs = New-Object System.Collections.ArrayList
        $collectorPath = Join-Path $PSScriptRoot '후보수집.ps1'
        foreach ($site in $script:Sources) {
            $job = Start-Job -ScriptBlock {
                param($path,$source,$day)
                $ErrorActionPreference='Stop'
                $workerWatch = [Diagnostics.Stopwatch]::StartNew()
                try {
                    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
                    . $path
                    Invoke-SiteCollect $source ([datetime]$day)
                } catch {
                    [pscustomobject]@{Site=$source.Name;Status='실패';Seconds=[math]::Round($workerWatch.Elapsed.TotalSeconds,2);Count=0;Method='';Error=$_.Exception.Message;Candidates=@()}
                }
            } -ArgumentList $collectorPath,$site,$today.ToString('yyyy-MM-dd')
            [void]$jobs.Add([pscustomobject]@{Job=$job;Site=$site.Name})
        }
        $allJobs = @($jobs | ForEach-Object Job)
        $null = Wait-Job -Job $allJobs -Timeout 18
        foreach ($entry in $jobs) {
            if ($entry.Job.State -eq 'Running') {
                Stop-Job -Job $entry.Job
                $results += [pscustomobject]@{Site=$entry.Site;Status='시간 초과';Seconds=18;Count=0;Method='';Error='18초 제한';Candidates=@()}
            } else {
                $received = @(Receive-Job -Job $entry.Job -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['Candidates'] })
                if ($received.Count) { $results += $received[0] }
                else {
                    $reason = if ($entry.Job.ChildJobs.Count -and $entry.Job.ChildJobs[0].JobStateInfo.Reason) { $entry.Job.ChildJobs[0].JobStateInfo.Reason.Message } else { '수집 작업이 결과를 반환하지 않았습니다.' }
                    $results += [pscustomobject]@{Site=$entry.Site;Status='실패';Seconds=0;Count=0;Method='';Error=$reason;Candidates=@()}
                }
            }
            Remove-Job -Job $entry.Job -Force
        }
        foreach ($result in $results) {
            if ($result.Count -gt 0) { continue }
            $old = @($previous | Where-Object Site -eq $result.Site | Select-Object -First 1)
            if ($old.Count -and $old[0].Count -gt 0) {
                $result.Status = '재수집 실패·캐시 사용'
                $result.Method = $old[0].Method
                $result.Count = $old[0].Count
                $result.Candidates = @($old[0].Candidates)
            }
        }
        if (@($results | Where-Object { $_.Count -gt 0 }).Count -gt 0) {
            $json = @{Date=$today.ToString('yyyy-MM-dd');Results=@($results)} | ConvertTo-Json -Depth 8
            [IO.File]::WriteAllText($cachePath,$json,$script:Utf8)
        }
    }
    Write-CandidateLog $results $cached
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $candidates = New-Object System.Collections.ArrayList
    foreach ($result in $results) {
        $definition = @($script:Sources | Where-Object Name -eq $result.Site | Select-Object -First 1)
        if (-not $definition.Count) { continue }
        foreach ($item in @($result.Candidates)) {
            $url = Normalize-ArticleUrl $item.Url 'https://example.com'
            if ($url -and (Test-ArticleDefinition $url $definition[0]) -and $seen.Add($url)) { [void]$candidates.Add($item) }
        }
    }
    return [pscustomobject]@{ Cached=$cached; Results=@($results); Candidates=@($candidates.ToArray()); CachePath=$cachePath }
}

function New-CandidateSearchPrompt([string]$basePrompt,[object]$prepared) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('')
    $lines.Add('## 이번 실행에서 설정된 전문 매체 목록')
    $lines.Add(('아래 {0}개 매체가 이번 실행의 유일한 지정 매체입니다. 프롬프트 본문의 예시 목록과 다르면 이 목록을 우선하십시오.' -f @($script:Sources).Count))
    foreach ($source in $script:Sources) { $lines.Add(('- {0}: {1}' -f $source.Name,$source.Home)) }
    if (-not $prepared -or @($prepared.Candidates).Count -eq 0) {
        $lines.Add('공개 자료 후보가 없어 기존 웹 검색으로 부족한 소재를 찾으십시오.')
        return $basePrompt.TrimEnd()+"`n`n"+($lines -join "`n")+"`n"
    }
    $lines.Add('')
    $lines.Add('## Windows PC가 먼저 수집한 후보 — 이 목록을 우선 검증')
    $lines.Add('다음 URL은 공개 피드·사이트맵·최신 페이지에서 수집한 미검증 후보입니다. 각 기사 원문을 직접 확인하고 게시일이 실행일 기준 최근 7일 이내인 기사만 선정하세요. 게시일을 확인할 수 없는 기사는 제외하세요.')
    $lines.Add('후보에서 사이트별 2건을 확보하지 못하면 기간을 늘리지 말고 해당 사이트의 최신 페이지·공개 피드·사이트맵·내부 검색·분야별 검색어 순으로 다시 찾으세요. 이전 작성 여부는 후보 제외 조건이 아닙니다.')
    foreach ($source in $script:Sources) {
        $siteItems = @($prepared.Candidates | Where-Object Site -eq $source.Name)
        $lines.Add(('### {0} — 후보 {1}건' -f $source.Name,$siteItems.Count))
        foreach ($item in $siteItems) { $lines.Add(('- {0} | {1} | {2}' -f $item.Date,$item.Title,$item.Url)) }
    }
    return $basePrompt.TrimEnd()+"`n"+($lines -join "`n")+"`n"
}

function Select-ValidCandidates([object[]]$candidates) {
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $counts = @{}
    $accepted = New-Object System.Collections.ArrayList
    foreach ($candidate in $candidates) {
        $url = Normalize-ArticleUrl $candidate.Url 'https://example.com'
        if (-not $url -or -not $seen.Add($url)) { continue }
        if (-not $counts.ContainsKey($candidate.Site)) { $counts[$candidate.Site] = 0 }
        if ($counts[$candidate.Site] -ge $script:MaximumCandidatesPerSite) { continue }
        if ($candidate.Date -eq '게시일 확인 불가') { continue }
        try { $age = ((Get-Date).Date - [datetime]::ParseExact($candidate.Date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture).Date).Days }
        catch { continue }
        if ($age -lt 0 -or $age -gt 7) { continue }
        # 중복 비교에는 정규화 주소를 쓰고 화면에는 원문에서 확인한 최종 주소를 보존합니다.
        $candidate.Url = ([uri]$candidate.Url).AbsoluteUri
        [void]$accepted.Add($candidate)
        $counts[$candidate.Site]++
        if ($accepted.Count -eq $script:MaximumCandidates) { break }
    }
    return @($accepted.ToArray())
}

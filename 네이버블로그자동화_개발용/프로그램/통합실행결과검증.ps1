#requires -Version 5.1
function Assert-NaverBrowserPreflight($Result, [string]$RunId) {
    if ($Result.runId -ne $RunId) { throw '브라우저 사전검사 실행 번호 불일치' }
    if ($Result.errorCode -eq 'LOCAL_BROWSER_DISABLED') {
        throw 'BROWSER_HOST_PERMISSION: 별도 실행 엔진에서 로컬 브라우저 사용이 거부되었습니다. 네이버 로그인 실패나 Chrome 창 개수 문제로 판정하지 않습니다.'
    }
    if ($Result.status -ne 'Ready') { throw "BROWSER_PREFLIGHT_FAILED: $($Result.errorCode) $($Result.reason)" }
    if($Result.naverTabReadVerified -isnot [bool] -or $Result.naverTabReadVerified -ne $true){throw '브라우저 사전검사 증거 누락: naverTabReadVerified'}
    $directOk=($Result.directChromeConnected -is [bool] -and $Result.directChromeConnected)
    if(-not $directOk -or [string]$Result.connectionPath -ne 'DedicatedChromeDevTools'){throw '자동화 전용 Chrome 직접 연결 증거 누락'}
    if($Result.ownerLoginVerified -isnot [bool] -or -not $Result.ownerLoginVerified){throw '자동화 전용 Chrome의 네이버 로그인 확인 실패'}
    if ([string]::IsNullOrWhiteSpace([string]$Result.browserId) -or [string]::IsNullOrWhiteSpace([string]$Result.tabId)) { throw '실제 브라우저/탭 식별자 누락' }
    $uri = $null
    if (-not [uri]::TryCreate([string]$Result.url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'blog.naver.com') { throw '네이버 블로그 탭 확인 실패' }
    if($uri.Query -match '(^|[?&])(logNo|postNo)=' -or $uri.AbsoluteUri -notmatch '(Redirect=Write|PostWriteForm)'){throw '새 글 편집기 URL 확인 실패'}
    if($uri.AbsolutePath -ne '/ij1128' -and $uri.Query -notmatch '(^|[?&])blogId=ij1128(&|$)'){throw '대상 네이버 블로그 ID 확인 실패'}
}
function Assert-NaverRunResult($Result, [string]$RunId, [string]$Root, [string]$EditorPlanPath, [bool]$AllowTagOnlyPublicationSettings=$false) {
    if ($Result.runId -ne $RunId) { throw '다른 실행의 검증 결과입니다.' }
    if ($Result.status -ne 'Verified') { throw "실행 미완료: $($Result.reason)" }
    if ($Result.publicationSettingsOpened -ne $false -or $Result.published -ne $false) { throw '발행 전 종료 조건 위반입니다.' }
    if ($AllowTagOnlyPublicationSettings) {
        if ($Result.publicationSettingsEverOpenedForTags -ne $true -or
            [string]$Result.publicationSettingsPurpose -ne 'TagsOnly' -or
            $Result.visibilityChanged -ne $false -or $Result.scheduleChanged -ne $false -or
            $Result.publishButtonClicked -ne $false) {
            throw '태그 전용 발행 설정 사용 증거가 올바르지 않습니다.'
        }
    } elseif ($Result.publicationSettingsEverOpenedForTags -eq $true) {
        throw '승인되지 않은 발행 설정 진입입니다.'
    }
    foreach ($name in @('imagesGenerated','imagesOptimized','imagesUploaded','titleVerified','bodyVerified','linksVerified','tagsVerified','formatVerified','mobileVerified','secondPassVerified')) {
        if ($Result.$name -ne $true) { throw "검증 누락: $name" }
    }
    $uri = [uri]$Result.editorUrl
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'blog.naver.com' -or $uri.AbsoluteUri -notmatch '(Redirect=Write|PostWriteForm)' -or $uri.Query -match '(logNo|postNo)=') { throw '새 글 편집창 주소가 아닙니다.' }
    if ($uri.AbsolutePath -ne '/ij1128' -and $uri.Query -notmatch '(^|[?&])blogId=ij1128(&|$)') { throw '대상 블로그 계정이 아닙니다.' }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    foreach ($name in @('pcScreenshot','mobileScreenshot','measurementFile')) {
        $path = [IO.Path]::GetFullPath([string]$Result.$name)
        if (-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) { throw "검증 증거 누락: $name" }
    }
    if ([string]::IsNullOrWhiteSpace($EditorPlanPath) -or -not (Test-Path -LiteralPath $EditorPlanPath -PathType Leaf)) {
        throw '편집기 계획 증거가 없습니다.'
    }
    $plan = Get-Content -LiteralPath $EditorPlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $measurement = Get-Content -LiteralPath ([string]$Result.measurementFile) -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$measurement.schemaVersion -ne 1 -or [string]$measurement.measurementSource -ne 'RenderedNaverDomAndScreen') {
        throw '실제 네이버 DOM·화면 측정 증거 형식이 아닙니다.'
    }
    $imageActions = @($plan.actions | Where-Object type -in @('UploadImage','UploadImageAtAnchor'))
    if (@($imageActions | Where-Object { $null -ne $_.documentOrder }).Count -eq $imageActions.Count) {
        $imageActions = @($imageActions | Sort-Object documentOrder)
    } else {
        $imageActions = @($imageActions | Sort-Object order)
    }
    $expectedImageNames = @($imageActions | ForEach-Object { [IO.Path]::GetFileName([string]$_.path) })
    if ($expectedImageNames.Count -lt 1) { throw '편집기 계획의 이미지 순서가 없습니다.' }
    foreach ($modeName in @('pc','mobile')) {
        $mode = $measurement.$modeName
        if ($null -eq $mode) { throw "화면 측정 증거 누락: $modeName" }
        if ($mode.horizontalOverflow -isnot [bool] -or [bool]$mode.horizontalOverflow) {
            throw "가로 넘침 검증 실패: $modeName"
        }
        if($mode.headingSpacingVerified -isnot [bool] -or -not [bool]$mode.headingSpacingVerified){
            throw "소제목 위아래 간격 검증 실패: $modeName"
        }
        $observedNames = @($mode.imageFileNames | ForEach-Object { [string]$_ })
        if (($expectedImageNames -join "`n") -ne ($observedNames -join "`n")) {
            throw "이미지 개수·순서 검증 실패: $modeName"
        }
        $serverUrls = @($mode.imageServerUrls | ForEach-Object { [string]$_ })
        if ($serverUrls.Count -ne $expectedImageNames.Count -or
            @($serverUrls | Where-Object { $_ -notmatch '^https://blogfiles\.pstatic\.net/' }).Count -gt 0) {
            throw "네이버 이미지 서버 주소 검증 실패: $modeName"
        }
        if ($mode.rawUrlVisible -isnot [bool] -or [bool]$mode.rawUrlVisible) {
            throw "본문 URL 문자열 노출 검증 실패: $modeName"
        }
    }
    $links = @($measurement.pc.sourceLinks)
    if ($links.Count -lt 1) { throw '출처 하이퍼링크 측정 증거가 없습니다.' }
    foreach ($link in $links) {
        $linkUri = $null
        if ([string]::IsNullOrWhiteSpace([string]$link.text) -or
            -not [Uri]::TryCreate([string]$link.href,[UriKind]::Absolute,[ref]$linkUri) -or
            $linkUri.Scheme -ne 'https') {
            throw '출처 하이퍼링크 측정값이 올바르지 않습니다.'
        }
    }
    $second = $measurement.secondPass
    foreach ($name in @('wholeArticleFromStart','titleVerified','bodyVerified','headingsVerified','headingSpacingVerified','imagesVerified','linksVerified')) {
        if ($second.$name -isnot [bool] -or $second.$name -ne $true) {
            throw "전체 2차 검증 증거 누락: $name"
        }
    }
}

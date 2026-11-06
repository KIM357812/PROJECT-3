#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CandidateCollection', 'FactCheck')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$ConfigPath,

    [string]$HistoryPath
)

$ErrorActionPreference = 'Stop'

function Add-WorkIssue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Message
    )
    $Issues.Add($Message)
}

function Test-RequiredText {
    param(
        [object]$Value
    )
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Test-HttpsUrl {
    param(
        [object]$Value
    )
    $uri = $null
    return [System.Uri]::TryCreate([string]$Value, [System.UriKind]::Absolute, [ref]$uri) -and
        $uri.Scheme -eq 'https'
}

function ConvertTo-DateOnly {
    param(
        [object]$Value,
        [ref]$Result
    )
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        [string]$Value,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
    if ($ok) {
        $Result.Value = $parsed.Date
    }
    return $ok
}

function Get-NormalizedHost {
    param(
        [string]$Url
    )
    $uri = [System.Uri]$Url
    return ($uri.Host -replace '^www\.', '').ToLowerInvariant()
}

function Test-CandidateCollection {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Collection,

        [Parameter(Mandatory = $true)]
        [psobject]$Rules,

        [Parameter(Mandatory = $true)]
        [psobject]$EditorialFocus,

        [string[]]$CompletedUrls = @()
    )

    $issues = New-Object 'System.Collections.Generic.List[string]'
    $collectedDate = [datetime]::MinValue
    if (-not (ConvertTo-DateOnly -Value $Collection.collectedDate -Result ([ref]$collectedDate))) {
        Add-WorkIssue $issues 'collectedDate must use yyyy-MM-dd.'
    }

    $configuredSources = @($Rules.Sources)
    $sites = @($Collection.sites)
    if ($sites.Count -ne $configuredSources.Count) {
        Add-WorkIssue $issues 'Every configured source must appear exactly once.'
    }

    $siteNames = @{}
    $articleUrls = @{}
    $completedUrlLookup = @{}
    foreach ($completedUrl in @($CompletedUrls)) {
        if (Test-RequiredText $completedUrl) {
            $completedUrlLookup[[string]$completedUrl] = $true
        }
    }
    $articleCount = 0
    $allowedConvergenceDomains = @($EditorialFocus.AIConvergenceDomains | ForEach-Object { [string]$_ })
    $allowedCoreAxes = @($EditorialFocus.CoreTopics | ForEach-Object { [string]$_ })

    foreach ($site in $sites) {
        $siteName = [string]$site.name
        if (-not (Test-RequiredText $siteName)) {
            Add-WorkIssue $issues 'Every site requires a name.'
            continue
        }
        if ($siteNames.ContainsKey($siteName)) {
            Add-WorkIssue $issues "Duplicate site entry: $siteName"
        }
        else {
            $siteNames[$siteName] = $true
        }

        $configured = @($configuredSources | Where-Object { $_.Name -eq $siteName })
        if ($configured.Count -ne 1) {
            Add-WorkIssue $issues "Unknown or duplicated configured site: $siteName"
            continue
        }
        if ([string]$site.baseUrl -ne [string]$configured[0].Url) {
            Add-WorkIssue $issues "Base URL does not match the configuration: $siteName"
        }

        $articles = @($site.articles)
        if ($articles.Count -gt [int]$Rules.MaxPerSite) {
            Add-WorkIssue $issues "Too many articles for site: $siteName"
        }

        $expectedMissing = [int]$Rules.MaxPerSite - $articles.Count
        if ([int]$site.missingCount -ne $expectedMissing) {
            Add-WorkIssue $issues "missingCount is incorrect for site: $siteName"
        }

        foreach ($article in $articles) {
            $articleCount++
            if (-not (Test-RequiredText $article.title)) {
                Add-WorkIssue $issues "An article title is missing for site: $siteName"
            }
            if (-not (Test-RequiredText $article.selectionReason)) {
                Add-WorkIssue $issues "An article selection reason is missing for site: $siteName"
            }

            $url = [string]$article.url
            if (-not (Test-HttpsUrl $url)) {
                Add-WorkIssue $issues "An article URL is not an absolute HTTPS URL: $siteName"
            }
            else {
                if ($articleUrls.ContainsKey($url)) {
                    Add-WorkIssue $issues "Duplicate article URL: $url"
                }
                else {
                    $articleUrls[$url] = $true
                }
                if ($completedUrlLookup.ContainsKey($url)) {
                    Add-WorkIssue $issues "Article URL was already completed: $url"
                }
                if ((Get-NormalizedHost $url) -ne (Get-NormalizedHost ([string]$configured[0].Url))) {
                    Add-WorkIssue $issues "Article host does not match its configured site: $url"
                }
                if (([System.Uri]$url).AbsolutePath -eq '/') {
                    Add-WorkIssue $issues "Article URL must be a detail page: $url"
                }
            }

            $publishedDate = [datetime]::MinValue
            if (-not (ConvertTo-DateOnly -Value $article.publishedDate -Result ([ref]$publishedDate))) {
                Add-WorkIssue $issues "publishedDate must use yyyy-MM-dd: $url"
            }
            elseif ($collectedDate -ne [datetime]::MinValue) {
                $age = ($collectedDate - $publishedDate).TotalDays
                if ($age -lt 0 -or $age -gt [int]$Rules.LookbackDays) {
                    Add-WorkIssue $issues "Article date is outside the configured lookback window: $url"
                }
            }

            $summary = @($article.summary)
            if ($summary.Count -ne 2 -or -not (Test-RequiredText $summary[0]) -or -not (Test-RequiredText $summary[1])) {
                Add-WorkIssue $issues "Every article requires exactly two non-empty Korean summary sentences: $url"
            }

            $convergenceDomains = @($article.convergenceDomains | ForEach-Object { [string]$_ })
            if ($convergenceDomains.Count -lt 1) {
                Add-WorkIssue $issues "Every article requires at least one AI convergence domain: $url"
            }
            foreach ($domain in $convergenceDomains) {
                if ($allowedConvergenceDomains -notcontains $domain) {
                    Add-WorkIssue $issues "Unknown AI convergence domain '$domain': $url"
                }
            }

            $coreAnalysisAxes = @($article.coreAnalysisAxes | ForEach-Object { [string]$_ })
            if ($coreAnalysisAxes.Count -lt 1) {
                Add-WorkIssue $issues "Every article requires at least one core analysis axis: $url"
            }
            foreach ($axis in $coreAnalysisAxes) {
                if ($allowedCoreAxes -notcontains $axis) {
                    Add-WorkIssue $issues "Unknown core analysis axis '$axis': $url"
                }
            }
            if ([bool]$EditorialFocus.RequireClearAIConnection -and $coreAnalysisAxes -notcontains 'AI') {
                Add-WorkIssue $issues "Every candidate must have a clear AI connection: $url"
            }
            if (-not (Test-RequiredText $article.connectionContext)) {
                Add-WorkIssue $issues "Every article requires a cross-field connection context: $url"
            }
            if ([bool]$EditorialFocus.RequireDomesticRelevance -and
                -not (Test-RequiredText $article.domesticRelevance)) {
                Add-WorkIssue $issues "Every article requires domestic relevance: $url"
            }
        }
    }

    if ($articleCount -gt [int]$Rules.MaxTotal) {
        Add-WorkIssue $issues 'The total article count exceeds the configured maximum.'
    }

    foreach ($configuredSource in $configuredSources) {
        if (-not $siteNames.ContainsKey([string]$configuredSource.Name)) {
            Add-WorkIssue $issues "Configured source is missing: $($configuredSource.Name)"
        }
    }

    $recommendations = @($Collection.recommendations)
    $expectedRecommendationCount = [Math]::Min([int]$Rules.RecommendationCount, $articleCount)
    if ($recommendations.Count -ne $expectedRecommendationCount) {
        Add-WorkIssue $issues 'The recommendation count is incorrect.'
    }
    $recommendedUrls = @{}
    foreach ($recommendation in $recommendations) {
        $recommendationUrl = [string]$recommendation.url
        if (-not $articleUrls.ContainsKey($recommendationUrl)) {
            Add-WorkIssue $issues "A recommendation does not reference a collected article: $recommendationUrl"
        }
        if ($recommendedUrls.ContainsKey($recommendationUrl)) {
            Add-WorkIssue $issues "Duplicate recommendation URL: $recommendationUrl"
        }
        else {
            $recommendedUrls[$recommendationUrl] = $true
        }
        if (-not (Test-RequiredText $recommendation.reason)) {
            Add-WorkIssue $issues "A recommendation reason is missing: $recommendationUrl"
        }
    }

    [pscustomobject]@{
        IsValid = ($issues.Count -eq 0)
        ArticleCount = $articleCount
        Issues = @($issues)
    }
}

function Test-FactCheckRecord {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Record
    )

    $issues = New-Object 'System.Collections.Generic.List[string]'
    if (-not (Test-RequiredText $Record.contentId)) {
        Add-WorkIssue $issues 'contentId is required.'
    }

    $editorialContext = $Record.editorialContext
    if ($null -eq $editorialContext) {
        Add-WorkIssue $issues 'editorialContext is required.'
    }
    else {
        if (@($editorialContext.convergenceDomains).Count -lt 1) {
            Add-WorkIssue $issues 'editorialContext.convergenceDomains requires at least one value.'
        }
        if (@($editorialContext.coreAnalysisAxes).Count -lt 1 -or
            @($editorialContext.coreAnalysisAxes) -notcontains 'AI') {
            Add-WorkIssue $issues 'editorialContext.coreAnalysisAxes must include AI.'
        }
        foreach ($field in @('connectionContext', 'domesticRelevance')) {
            if (-not (Test-RequiredText $editorialContext.$field)) {
                Add-WorkIssue $issues "editorialContext.$field is required."
            }
        }
    }

    $source = $Record.primarySource
    if ($null -eq $source) {
        Add-WorkIssue $issues 'primarySource is required.'
    }
    else {
        foreach ($field in @('name', 'title', 'publishedDate', 'checkedDate')) {
            if (-not (Test-RequiredText $source.$field)) {
                Add-WorkIssue $issues "primarySource.$field is required."
            }
        }
        if (-not (Test-HttpsUrl $source.url)) {
            Add-WorkIssue $issues 'primarySource.url must be an absolute HTTPS URL.'
        }
        foreach ($dateField in @('publishedDate', 'checkedDate')) {
            $dateValue = [datetime]::MinValue
            if (-not (ConvertTo-DateOnly -Value $source.$dateField -Result ([ref]$dateValue))) {
                Add-WorkIssue $issues "primarySource.$dateField must use yyyy-MM-dd."
            }
        }
    }

    $articleFiveWOneH = $Record.articleFiveWOneH
    if ($null -eq $articleFiveWOneH) {
        Add-WorkIssue $issues 'articleFiveWOneH is required.'
    }
    else {
        if ([string]$articleFiveWOneH.provenance -ne 'selectedArticle') {
            Add-WorkIssue $issues 'articleFiveWOneH.provenance must be selectedArticle.'
        }
        if (-not (Test-HttpsUrl $articleFiveWOneH.sourceUrl)) {
            Add-WorkIssue $issues 'articleFiveWOneH.sourceUrl must be an absolute HTTPS URL.'
        }
        elseif ($null -ne $source -and [string]$articleFiveWOneH.sourceUrl -ne [string]$source.url) {
            Add-WorkIssue $issues 'articleFiveWOneH.sourceUrl must match primarySource.url.'
        }
        foreach ($field in @('who', 'what', 'when', 'where', 'how', 'why')) {
            $item = $articleFiveWOneH.$field
            if ($null -eq $item -or -not (Test-RequiredText $item.value)) {
                Add-WorkIssue $issues "articleFiveWOneH.$field.value is required."
            }
            if ($null -eq $item -or -not (Test-RequiredText $item.evidence)) {
                Add-WorkIssue $issues "articleFiveWOneH.$field.evidence is required."
            }
        }
    }

    $coreFacts = @($Record.coreFacts)
    if ($coreFacts.Count -lt 1) {
        Add-WorkIssue $issues 'At least one core fact is required.'
    }
    foreach ($fact in $coreFacts) {
        if (-not (Test-RequiredText $fact.claim)) {
            Add-WorkIssue $issues 'Every core fact requires a claim.'
        }
        $factSources = @($fact.sourceUrls)
        if ($factSources.Count -lt 1) {
            Add-WorkIssue $issues 'Every core fact requires at least one source URL.'
        }
        foreach ($factSource in $factSources) {
            if (-not (Test-HttpsUrl $factSource)) {
                Add-WorkIssue $issues 'Every core fact source must be an absolute HTTPS URL.'
            }
        }
    }

    $allowedStages = @('발표', '계획', '투자', '실증', '상용화', '실적')
    $stages = @($Record.lifecycleStages)
    if ($stages.Count -lt 1) {
        Add-WorkIssue $issues 'At least one lifecycle stage is required.'
    }
    foreach ($stage in $stages) {
        if ($allowedStages -notcontains [string]$stage) {
            Add-WorkIssue $issues "Unknown lifecycle stage: $stage"
        }
    }

    if (-not (Test-RequiredText $Record.sourceFindings)) {
        Add-WorkIssue $issues 'sourceFindings is required.'
    }
    if (-not (Test-RequiredText $Record.authorAnalysis)) {
        Add-WorkIssue $issues 'authorAnalysis is required.'
    }
    if ((Test-RequiredText $Record.sourceFindings) -and
        [string]$Record.sourceFindings -eq [string]$Record.authorAnalysis) {
        Add-WorkIssue $issues 'Source findings and author analysis must be separated.'
    }

    foreach ($propertyName in @('discrepancies', 'uncertainties', 'correctionSources')) {
        if ($Record.PSObject.Properties.Name -notcontains $propertyName) {
            Add-WorkIssue $issues "$propertyName must be present, even when empty."
        }
    }
    foreach ($correctionSource in @($Record.correctionSources)) {
        if (-not (Test-HttpsUrl $correctionSource)) {
            Add-WorkIssue $issues 'Every correction source must be an absolute HTTPS URL.'
        }
    }

    $allowedValueTypes = @('목표', '실적', '최대', '평균', '예상')
    foreach ($numericClaim in @($Record.numericClaims)) {
        if (-not (Test-RequiredText $numericClaim.value) -or -not (Test-RequiredText $numericClaim.unit)) {
            Add-WorkIssue $issues 'Every numeric claim requires a value and unit.'
        }
        if ($allowedValueTypes -notcontains [string]$numericClaim.valueType) {
            Add-WorkIssue $issues "Unknown numeric value type: $($numericClaim.valueType)"
        }
        if (-not (Test-HttpsUrl $numericClaim.sourceUrl)) {
            Add-WorkIssue $issues 'Every numeric claim requires an absolute HTTPS source URL.'
        }
    }

    [pscustomobject]@{
        IsValid = ($issues.Count -eq 0)
        Issues = @($issues)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Input file was not found: $Path"
    }
    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($Mode -eq 'CandidateCollection') {
        if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
            $ConfigPath = Get-ChildItem -LiteralPath (Split-Path -Parent $PSScriptRoot) -File -Filter '*.json' |
                Select-Object -First 1 -ExpandProperty FullName
        }
        if ([string]::IsNullOrWhiteSpace($ConfigPath) -or -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
            throw "Configuration file was not found: $ConfigPath"
        }
        $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $completedUrls = @()
        if (-not [string]::IsNullOrWhiteSpace($HistoryPath)) {
            if (-not (Test-Path -LiteralPath $HistoryPath -PathType Leaf)) {
                throw "Completed URL history file was not found: $HistoryPath"
            }
            $history = Get-Content -LiteralPath $HistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $completedUrls = @($history.completedUrls | ForEach-Object { [string]$_.url })
        }
        $result = Test-CandidateCollection -Collection $data -Rules $config.Collection `
            -EditorialFocus $config.EditorialFocus `
            -CompletedUrls $completedUrls
    }
    else {
        $result = Test-FactCheckRecord -Record $data
    }

    $result | ConvertTo-Json -Depth 6
    if (-not $result.IsValid) { exit 1 }
}

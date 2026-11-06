#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

function Add-Issue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Message
    )
    $Issues.Add($Message)
}

function Test-NaverDraft {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Draft,

        [Parameter(Mandatory = $true)]
        [psobject]$Rules
    )

    $issues = New-Object 'System.Collections.Generic.List[string]'
    $title = [string]$Draft.title
    $body = [string]$Draft.body
    $tags = @($Draft.tags)
    $sources = @($Draft.sources)
    $bodyLinks = @()
    if ($Draft.PSObject.Properties.Name -contains 'bodyLinks' -and $null -ne $Draft.bodyLinks) {
        $bodyLinks = @($Draft.bodyLinks)
    }
    $boldHighlights = @()
    if ($Draft.PSObject.Properties.Name -contains 'boldHighlights' -and $null -ne $Draft.boldHighlights) {
        $boldHighlights = @($Draft.boldHighlights | ForEach-Object { [string]$_ })
    }
    $imagePrompts = @($Draft.imagePrompts)
    $sectionHeadings = @($Draft.sectionHeadings | ForEach-Object { [string]$_ })
    $draftType = [string]$Draft.draftType

    if (@($Rules.AllowedDraftTypes) -notcontains $draftType) {
        Add-Issue $issues 'Draft type is missing or not allowed.'
    }

    if ([bool]$Rules.RequireEditorialFocusReview) {
        $editorialContext = $Draft.editorialContext
        if ($null -eq $editorialContext) {
            Add-Issue $issues 'AI convergence editorial context is required.'
        }
        else {
            if (@($editorialContext.convergenceDomains).Count -lt 1) {
                Add-Issue $issues 'At least one AI convergence domain is required.'
            }
            if (@($editorialContext.coreAnalysisAxes).Count -lt 1 -or
                @($editorialContext.coreAnalysisAxes) -notcontains 'AI') {
                Add-Issue $issues 'Core analysis axes must include AI.'
            }
            foreach ($field in @('connectionContext', 'domesticRelevance')) {
                if ([string]::IsNullOrWhiteSpace([string]$editorialContext.$field)) {
                    Add-Issue $issues "Editorial context requires $field."
                }
            }
            foreach ($flag in @(
                'aiConnectionExplained',
                'crossFieldImpactExplained',
                'domesticRelevanceExplained',
                'factAnalysisSeparated',
                'forcedConnectionsExcluded'
            )) {
                if ($editorialContext.PSObject.Properties.Name -notcontains $flag -or
                    -not [bool]$editorialContext.$flag) {
                    Add-Issue $issues "Editorial focus confirmation is required: $flag"
                }
            }
        }
    }

    if ([bool]$Rules.RequireBenchmarkReview) {
        $benchmark = $Draft.benchmarkReview
        if ($null -eq $benchmark) {
            Add-Issue $issues 'A comparable Naver blog benchmark review is required.'
        }
        else {
            $benchmarkDate = [datetime]::MinValue
            if (-not [datetime]::TryParseExact(
                [string]$benchmark.analyzedDate,
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None,
                [ref]$benchmarkDate
            )) {
                Add-Issue $issues 'Benchmark analyzedDate must use yyyy-MM-dd.'
            }
            elseif ($benchmarkDate -gt (Get-Date).Date -or
                ((Get-Date).Date - $benchmarkDate).TotalDays -gt [int]$Rules.MaximumBenchmarkAgeDays) {
                Add-Issue $issues 'Benchmark evidence is future-dated or too old.'
            }
            if ([int]$benchmark.candidateCount -lt [int]$Rules.MinimumBenchmarkCandidates) {
                Add-Issue $issues 'Not enough comparable Naver blogs were reviewed.'
            }
            if ([int]$benchmark.activeReferenceCount -lt [int]$Rules.MinimumActiveBenchmarkReferences) {
                Add-Issue $issues 'Not enough active benchmark blogs were reviewed.'
            }
            if ([string]::IsNullOrWhiteSpace([string]$benchmark.primaryBlogId) -or
                [string]::IsNullOrWhiteSpace([string]$benchmark.selectionReason)) {
                Add-Issue $issues 'Benchmark primaryBlogId and selectionReason are required.'
            }
            if (@($benchmark.adoptedPatterns).Count -lt [int]$Rules.MinimumAdoptedBenchmarkPatterns) {
                Add-Issue $issues 'Benchmark adoptedPatterns count is too small.'
            }
            if (@($benchmark.rejectedPatterns).Count -lt [int]$Rules.MinimumRejectedBenchmarkPatterns) {
                Add-Issue $issues 'Benchmark rejectedPatterns count is too small.'
            }
            foreach ($flag in @('noCopy', 'generalAudienceFirst', 'publicMetricsOnly', 'primaryHasHighestQualifiedReach')) {
                if ($benchmark.PSObject.Properties.Name -notcontains $flag -or -not [bool]$benchmark.$flag) {
                    Add-Issue $issues "Benchmark confirmation is required: $flag"
                }
            }
        }
    }

    $officialCompliance = $Draft.officialCompliance
    $requiredCompliance = @(
        'searchIntentMatched',
        'originalStructureAndAnalysis',
        'noKeywordStuffing',
        'noHiddenTextOrLinks',
        'noMechanicalMassProduction'
    )
    if ($null -eq $officialCompliance) {
        Add-Issue $issues 'Official Naver compliance confirmation is required.'
    }
    else {
        foreach ($propertyName in $requiredCompliance) {
            if ($officialCompliance.PSObject.Properties.Name -notcontains $propertyName -or
                -not [bool]$officialCompliance.$propertyName) {
                Add-Issue $issues "Official Naver compliance must be confirmed: $propertyName"
            }
        }
    }

    $readerDesign = $Draft.readerDesign
    if ($null -eq $readerDesign) {
        Add-Issue $issues 'Reader-friendly structure confirmation is required.'
    }
    else {
        $leadCount = [int]$readerDesign.leadSentenceCount
        if ($leadCount -lt [int]$Rules.LeadSentenceCountMinimum -or
            $leadCount -gt [int]$Rules.LeadSentenceCountMaximum) {
            Add-Issue $issues 'Lead sentence count is outside the configured reader range.'
        }
        if ([int]$readerDesign.keySummaryCount -ne [int]$Rules.KeySummaryCount) {
            Add-Issue $issues 'Key summary count is incorrect.'
        }
        if ([int]$readerDesign.readerQuestionCount -ne [int]$Rules.ReaderQuestionCount) {
            Add-Issue $issues 'Reader question count is incorrect.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($title)) {
        Add-Issue $issues 'Title is required.'
    }
    elseif ($title.Length -gt [int]$Rules.MaximumTitleLength) {
        Add-Issue $issues 'Title is longer than the configured maximum.'
    }

    if ($body.Length -lt [int]$Rules.MinimumBodyLength) {
        Add-Issue $issues 'Body is shorter than the configured minimum.'
    }
    if ($body.Length -gt [int]$Rules.MaximumBodyLength) {
        Add-Issue $issues 'Body is longer than the configured maximum.'
    }
    $paragraphs = @($body -split "(`r?`n){2,}" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($paragraph in $paragraphs) {
        if ($paragraph.Trim().Length -gt [int]$Rules.MaximumParagraphLength) {
            Add-Issue $issues 'A body paragraph is longer than the configured mobile maximum.'
            break
        }
    }
    if ([bool]$Rules.ForbidHtmlTags -and
        $body -match '<\s*/?\s*(html|body|div|p|span|br|script|style|h[1-6]|ul|ol|li|a)\b[^>]*>') {
        Add-Issue $issues 'HTML tags are not allowed in a Naver editor draft.'
    }
    if ([bool]$Rules.RequireUniqueParagraphs) {
        $repeatedParagraphs = @($paragraphs |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_.Length -ge 40 } |
            Group-Object |
            Where-Object { $_.Count -gt 1 })
        if ($repeatedParagraphs.Count -gt 0) {
            Add-Issue $issues 'Repeated body paragraphs are not allowed.'
        }
    }

    if ($sectionHeadings.Count -lt [int]$Rules.MinimumSectionHeadings -or
        $sectionHeadings.Count -gt [int]$Rules.MaximumSectionHeadings) {
        Add-Issue $issues 'Section heading count is outside the configured range.'
    }
    if (@($sectionHeadings | Select-Object -Unique).Count -ne $sectionHeadings.Count) {
        Add-Issue $issues 'Section headings must be unique.'
    }
    $normalizedParagraphs = @($paragraphs | ForEach-Object { $_.Trim() })
    foreach ($heading in $sectionHeadings) {
        if ([string]::IsNullOrWhiteSpace($heading) -or $normalizedParagraphs -notcontains $heading.Trim()) {
            Add-Issue $issues 'Every section heading must appear as its own body paragraph.'
            break
        }
    }

    if ($tags.Count -lt [int]$Rules.MinimumTags -or $tags.Count -gt [int]$Rules.MaximumTags) {
        Add-Issue $issues 'Tag count is outside the configured range.'
    }
    if (@($tags | Select-Object -Unique).Count -ne $tags.Count) {
        Add-Issue $issues 'Tags must be unique.'
    }
    foreach ($tag in $tags) {
        if ([string]$tag -notmatch [string]$Rules.TagPattern) {
            Add-Issue $issues 'Tags cannot contain #, spaces, or special characters.'
            break
        }
    }

    $minimumSources = if ($draftType -eq 'TechnicalArticle') { [int]$Rules.MinimumSources } else { 0 }
    if ($sources.Count -lt $minimumSources -or $sources.Count -gt [int]$Rules.MaximumSources) {
        Add-Issue $issues 'Source count is outside the configured range.'
    }
    foreach ($source in $sources) {
        foreach ($field in @('name', 'title', 'publishedDate')) {
            if ([string]::IsNullOrWhiteSpace([string]$source.$field)) {
                Add-Issue $issues "Every source requires $field."
            }
        }
        $uri = $null
        if (-not [System.Uri]::TryCreate([string]$source.url, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
            Add-Issue $issues 'Every source URL must be an absolute HTTPS URL.'
        }
        $publishedDate = [datetime]::MinValue
        if (-not [datetime]::TryParseExact(
            [string]$source.publishedDate,
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$publishedDate
        )) {
            Add-Issue $issues 'Every source publishedDate must use yyyy-MM-dd.'
        }
    }

    if ($draftType -eq 'TechnicalArticle' -and [bool]$Rules.RequireFiveWOneHSummary) {
        $articleFiveWOneH = $Draft.articleFiveWOneH
        if ($null -eq $articleFiveWOneH) {
            Add-Issue $issues 'Selected-article five-W-one-H evidence is required.'
        }
        else {
            if ([string]$articleFiveWOneH.provenance -ne 'selectedArticle') {
                Add-Issue $issues 'Five-W-one-H provenance must be selectedArticle.'
            }
            $fiveWOneHUrl = [string]$articleFiveWOneH.sourceUrl
            $primaryDraftSourceUrl = if ($sources.Count -gt 0) { [string]$sources[0].url } else { '' }
            if ([string]::IsNullOrWhiteSpace($fiveWOneHUrl) -or $fiveWOneHUrl -ne $primaryDraftSourceUrl) {
                Add-Issue $issues 'Five-W-one-H source URL must match the selected primary article.'
            }
            foreach ($field in @('who', 'what', 'when', 'where', 'how', 'why')) {
                $item = $articleFiveWOneH.$field
                $value = if ($null -eq $item) { '' } else { ([string]$item.value).Trim() }
                $evidence = if ($null -eq $item) { '' } else { ([string]$item.evidence).Trim() }
                if ([string]::IsNullOrWhiteSpace($value) -or [string]::IsNullOrWhiteSpace($evidence)) {
                    Add-Issue $issues "Five-W-one-H $field requires an article-derived value and evidence."
                }
                elseif ($body.IndexOf($value, [System.StringComparison]::Ordinal) -lt 0) {
                    Add-Issue $issues "Five-W-one-H $field value must appear unchanged in the body."
                }
            }
        }
    }

    if ($bodyLinks.Count -gt [int]$Rules.MaximumBodyLinks) {
        Add-Issue $issues 'Body link count exceeds the configured maximum.'
    }
    $bodyLinkUrls = New-Object 'System.Collections.Generic.List[string]'
    foreach ($bodyLink in $bodyLinks) {
        $linkText = ([string]$bodyLink.text).Trim()
        $linkWords = @([regex]::Matches($linkText, '\S+'))
        if ([string]::IsNullOrWhiteSpace($linkText) -or
            $linkWords.Count -gt [int]$Rules.BodyLinkMaximumWords) {
            Add-Issue $issues 'Body link text must contain one to the configured maximum number of words.'
        }
        elseif ($body.IndexOf($linkText, [System.StringComparison]::Ordinal) -lt 0) {
            Add-Issue $issues 'Every body link text must appear in the body.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$bodyLink.purpose)) {
            Add-Issue $issues 'Every body link requires a purpose.'
        }
        $bodyLinkUri = $null
        if (-not [System.Uri]::TryCreate([string]$bodyLink.url, [System.UriKind]::Absolute, [ref]$bodyLinkUri) -or
            $bodyLinkUri.Scheme -ne 'https') {
            Add-Issue $issues 'Every body link URL must be an absolute HTTPS URL.'
        }
        elseif ($bodyLinkUrls.Contains($bodyLinkUri.AbsoluteUri)) {
            Add-Issue $issues 'Body link URLs must not be repeated.'
        }
        else {
            $bodyLinkUrls.Add($bodyLinkUri.AbsoluteUri)
        }
    }

    if ($boldHighlights.Count -gt [int]$Rules.MaximumBoldHighlights) {
        Add-Issue $issues 'Bold highlight count exceeds the configured maximum.'
    }
    if (@($boldHighlights | Select-Object -Unique).Count -ne $boldHighlights.Count) {
        Add-Issue $issues 'Bold highlights must be unique.'
    }
    foreach ($highlight in $boldHighlights) {
        if ([string]::IsNullOrWhiteSpace($highlight) -or
            $body.IndexOf($highlight.Trim(), [System.StringComparison]::Ordinal) -lt 0) {
            Add-Issue $issues 'Every bold highlight must appear in the body.'
            break
        }
        if ($sectionHeadings -contains $highlight.Trim()) {
            Add-Issue $issues 'Section headings must not be repeated as body bold highlights.'
            break
        }
    }

    if ($draftType -eq 'TechnicalArticle' -and [bool]$Draft.allowImagePromptException) {
        Add-Issue $issues 'Technical articles cannot bypass image prompt requirements.'
    }
    if (-not [bool]$Draft.allowImagePromptException -and $imagePrompts.Count -ne [int]$Rules.TechnicalArticleImagePrompts) {
        Add-Issue $issues 'Technical articles require the configured image prompt count.'
    }

    $yearCharacter = [char]0xB144
    $forbiddenCareerYearPattern = '(?<!\d)(?:30|25|10)' + $yearCharacter + '(?!\d)'
    if ($body -match $forbiddenCareerYearPattern) {
        Add-Issue $issues 'Specific career-year claims are not allowed.'
    }

    [pscustomobject]@{
        IsValid = ($issues.Count -eq 0)
        Issues = @($issues)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Draft file was not found: $Path"
    }
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Get-ChildItem -LiteralPath (Split-Path -Parent $PSScriptRoot) -File -Filter '*.json' |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if ([string]::IsNullOrWhiteSpace($ConfigPath) -or -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Configuration file was not found: $ConfigPath"
    }

    $draft = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = Test-NaverDraft -Draft $draft -Rules $config.NaverDraft
    $result | ConvertTo-Json -Depth 5
    if (-not $result.IsValid) { exit 1 }
}

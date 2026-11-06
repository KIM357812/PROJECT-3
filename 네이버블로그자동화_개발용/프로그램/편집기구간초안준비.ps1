#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ContentId,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$SectionHeading,
    [Parameter(Mandatory = $true)][string[]]$BodyParagraphs,
    [Parameter(Mandatory = $true)][string]$ReaderQuestion,
    [Parameter(Mandatory = $true)][string]$ReferenceLine,
    [Parameter(Mandatory = $true)][string[]]$ReferenceNames,
    [Parameter(Mandatory = $true)][string[]]$ReferenceUrls,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPath) {
    throw "기존 구간 초안을 덮어쓰지 않습니다: $OutputPath"
}
if (@($BodyParagraphs).Count -lt 1 -or
    @($BodyParagraphs | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw '본문 문단은 한 개 이상이며 빈 값이 없어야 합니다.'
}
if ($ReferenceNames.Count -lt 1 -or $ReferenceNames.Count -gt 3 -or
    $ReferenceNames.Count -ne $ReferenceUrls.Count) {
    throw '참고자료 이름과 URL은 같은 개수로 1~3개여야 합니다.'
}
$referenceLinks = New-Object 'System.Collections.Generic.List[object]'
for ($i = 0; $i -lt $ReferenceNames.Count; $i++) {
    $uri = $null
    if ([string]::IsNullOrWhiteSpace($ReferenceNames[$i]) -or
        -not [Uri]::TryCreate($ReferenceUrls[$i], [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https') {
        throw "참고자료 이름과 HTTPS URL을 확인하세요: index $i"
    }
    $referenceLinks.Add([pscustomobject]@{ text=$ReferenceNames[$i]; url=$uri.AbsoluteUri })
}

$blocks = New-Object 'System.Collections.Generic.List[object]'
$blocks.Add([pscustomobject]@{ id='section-heading'; type='SectionHeading'; text=$SectionHeading })
for ($i = 0; $i -lt $BodyParagraphs.Count; $i++) {
    $blocks.Add([pscustomobject]@{ id="body-$($i + 1)"; type='BodyParagraph'; text=[string]$BodyParagraphs[$i] })
}
$blocks.Add([pscustomobject]@{ id='reader-question'; type='ReaderQuestion'; text=$ReaderQuestion })
$blocks.Add([pscustomobject]@{
    id='reference-line'; type='ReferenceLine'; text=$ReferenceLine
    links=$referenceLinks.ToArray()
})

$draft = [pscustomobject]@{
    contentId = $ContentId
    title = $Title
    rebuildScope = 'NamedSection'
    targetSectionHeading = $SectionHeading
    editorBlocks = $blocks.ToArray()
}

$directory = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($directory)) { throw 'OutputPath는 상위 폴더를 포함해야 합니다.' }
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $directory
}
$draft | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$draft | ConvertTo-Json -Depth 8

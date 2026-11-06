param(
    [string]$SourceDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '..\프롬프트'),
    [string]$TargetDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '프롬프트')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
$targetDirectory = [IO.Path]::GetFullPath($TargetDirectory)
[IO.Directory]::CreateDirectory($targetDirectory) | Out-Null

foreach ($file in @(Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.hwpx' -File)) {
    $target = Join-Path $targetDirectory ($file.BaseName + '.md')
    if ([IO.File]::Exists($target)) { throw "기존 사본을 덮어쓸 수 없습니다: $target" }
    $archive = [IO.Compression.ZipFile]::OpenRead($file.FullName)
    try {
        $sections = @($archive.Entries | Where-Object { $_.FullName -match '^Contents/section\d+\.xml$' } | Sort-Object FullName)
        if ($sections.Count -eq 0) { throw "본문 XML이 없습니다: $($file.Name)" }
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($section in $sections) {
            $reader = New-Object IO.StreamReader($section.Open(), [Text.Encoding]::UTF8)
            try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
            foreach ($paragraph in $xml.SelectNodes('//*[local-name()="p"]')) {
                $text = ($paragraph.SelectNodes('.//*[local-name()="t"]') | ForEach-Object { $_.InnerText }) -join ''
                $lines.Add($text)
            }
        }
        $result = (($lines.ToArray()) -join "`n").Trim() + "`n"
        if ($result.Length -lt 1000 -or $result.Contains([char]0xFFFD)) {
            throw "추출 결과가 비어 있거나 깨졌습니다: $($file.Name)"
        }
        [IO.File]::WriteAllText($target, $result, $utf8)
        Write-Output "추출 완료: $target ($($result.Length)자)"
    } finally { $archive.Dispose() }
}

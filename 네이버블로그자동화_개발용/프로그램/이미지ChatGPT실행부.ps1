#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RequestPath,
    [int]$MaximumParallel=2,
    [int]$TimeoutSecondsPerImage=900
)

$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $RequestPath -PathType Leaf)){throw "이미지 요청 파일을 찾을 수 없습니다: $RequestPath"}
if($MaximumParallel -lt 1){$MaximumParallel=1}
if($MaximumParallel -gt 2){$MaximumParallel=2}

function Write-JsonAtomic([string]$Path,[object]$Value){
    $temporary=$Path+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 15),(New-Object Text.UTF8Encoding($true)))
    try{
        if(Test-Path -LiteralPath $Path -PathType Leaf){
            $backup=$Path+'.replace-'+[guid]::NewGuid().ToString('N')
            try{[IO.File]::Replace($temporary,$Path,$backup);if(Test-Path -LiteralPath $backup){Remove-Item -LiteralPath $backup -Force}}
            catch{Copy-Item -LiteralPath $temporary -Destination $Path -Force;Remove-Item -LiteralPath $temporary -Force}
        }else{[IO.File]::Move($temporary,$Path)}
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}
function Find-GeneratedImage([string]$Directory,[string]$BaseName){
    $matches=@(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue|Where-Object{$_.BaseName -eq $BaseName -and $_.Extension -match '^\.(png|jpg|jpeg|webp)$'})
    if($matches.Count -eq 1){return $matches[0].FullName}
    return ''
}
function Start-ImageProcess([object]$Asset,[string]$RequestRoot,[string]$OriginalRoot,[string]$CodexPath){
    $baseName=[string]$Asset.originalBaseName
    $targetPath=Join-Path $OriginalRoot ($baseName+'.png')
    $responsePath=Join-Path $RequestRoot ('codex-'+('{0:D2}' -f [int]$Asset.order)+'.txt')
    $stdoutPath=$responsePath+'.stdout.log'
    $stderrPath=$responsePath+'.stderr.log'
    $prompt=@"
Use the installed imagegen skill and the image_gen.imagegen tool. Generate exactly ONE brand-new bitmap image from the visual prompt below.

Required output rules:
- Save the actual generated bitmap at this exact Windows path: $targetPath
- The finished file must be PNG, 3:2 landscape, and must open as a valid raster image.
- Do not create a substitute diagram with PowerShell, Python, SVG, HTML, canvas, or stock-image search.
- Do not draw or invent a company logo. Do not add captions, letters, numbers, watermarks, UI labels, or split-screen collage.
- If imagegen returns a generated local file at another path, copy that actual generated bitmap to the exact target path.
- Do not modify any repository source file or any file outside the target image and these execution logs.
- When the target file exists, reply with only: IMAGE_READY

Visual prompt:
$([string]$Asset.prompt)
"@
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$CodexPath
    $psi.Arguments='exec --ephemeral --skip-git-repo-check --sandbox workspace-write -C "'+$RequestRoot+'" --add-dir "'+$OriginalRoot+'" -o "'+$responsePath+'" -'
    $psi.WorkingDirectory=$RequestRoot
    $psi.UseShellExecute=$false
    $psi.RedirectStandardInput=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $psi.CreateNoWindow=$true
    $process=[Diagnostics.Process]::Start($psi)
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($prompt)
    $process.StandardInput.BaseStream.Write($bytes,0,$bytes.Length)
    $process.StandardInput.BaseStream.Flush()
    $process.StandardInput.Close()
    return [pscustomobject]@{
        Process=$process;Asset=$Asset;TargetPath=$targetPath;ResponsePath=$responsePath
        StdoutPath=$stdoutPath;StderrPath=$stderrPath;StdoutTask=$process.StandardOutput.ReadToEndAsync()
        StderrTask=$process.StandardError.ReadToEndAsync();StartedAt=Get-Date
    }
}
function Complete-ImageProcess([object]$Job){
    $job.Process.WaitForExit()
    $stdout=$job.StdoutTask.Result
    $stderr=$job.StderrTask.Result
    [IO.File]::WriteAllText($job.StdoutPath,$stdout,(New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText($job.StderrPath,$stderr,(New-Object Text.UTF8Encoding($true)))
    $exitCode=$job.Process.ExitCode
    $job.Process.Dispose()
    $actual=Find-GeneratedImage (Split-Path -Parent $job.TargetPath) ([IO.Path]::GetFileNameWithoutExtension($job.TargetPath))
    if($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($actual)){
        return [pscustomobject]@{Succeeded=$false;Order=[int]$job.Asset.order;Message="Codex 이미지 생성 실패(종료 코드 $exitCode): $($job.StderrPath)"}
    }
    return [pscustomobject]@{Succeeded=$true;Order=[int]$job.Asset.order;Path=$actual;Message=''}
}

$requestFull=[IO.Path]::GetFullPath($RequestPath)
$requestRoot=Split-Path -Parent $requestFull
$request=Get-Content -LiteralPath $requestFull -Raw -Encoding UTF8|ConvertFrom-Json
$originalRoot=[IO.Path]::GetFullPath([string]$request.originalDirectory)
if(-not(Test-Path -LiteralPath $originalRoot -PathType Container)){[IO.Directory]::CreateDirectory($originalRoot)|Out-Null}
$codex=(Get-Command codex -ErrorAction Stop).Source
$pending=@($request.assets|Sort-Object order|Where-Object{[string]::IsNullOrWhiteSpace((Find-GeneratedImage $originalRoot ([string]$_.originalBaseName)))})
if($pending.Count -eq 0){
    $request.status='Completed';$request|Add-Member -NotePropertyName completedAt -NotePropertyValue ((Get-Date).ToString('o')) -Force;Write-JsonAtomic $requestFull $request
    return
}
$request.status='Generating';$request|Add-Member -NotePropertyName startedAt -NotePropertyValue ((Get-Date).ToString('o')) -Force;Write-JsonAtomic $requestFull $request

$queue=New-Object Collections.Queue
foreach($asset in $pending){$queue.Enqueue($asset)}
$active=New-Object Collections.ArrayList
$results=New-Object Collections.ArrayList
while($queue.Count -gt 0 -or $active.Count -gt 0){
    while($queue.Count -gt 0 -and $active.Count -lt $MaximumParallel){[void]$active.Add((Start-ImageProcess $queue.Dequeue() $requestRoot $originalRoot $codex))}
    foreach($job in @($active)){
        $timedOut=((Get-Date)-$job.StartedAt).TotalSeconds -gt $TimeoutSecondsPerImage
        if($timedOut -and -not $job.Process.HasExited){try{$job.Process.Kill()}catch{}}
        if($job.Process.HasExited){
            [void]$results.Add((Complete-ImageProcess $job))
            [void]$active.Remove($job)
        }
    }
    if($active.Count -gt 0){Start-Sleep -Milliseconds 250}
}

$failures=@($results|Where-Object{-not $_.Succeeded})
foreach($asset in @($request.assets)){
    $found=Find-GeneratedImage $originalRoot ([string]$asset.originalBaseName)
    $asset.status=if($found){'Completed'}else{'Failed'}
    if($found){$asset|Add-Member -NotePropertyName generatedPath -NotePropertyValue $found -Force}
}
$request.status=if($failures.Count -eq 0){'Completed'}else{'Failed'}
$request|Add-Member -NotePropertyName completedAt -NotePropertyValue ((Get-Date).ToString('o')) -Force
$request|Add-Member -NotePropertyName failures -NotePropertyValue @($failures) -Force
Write-JsonAtomic $requestFull $request
if($failures.Count -gt 0){throw ('ChatGPT 이미지 생성에 실패했습니다: '+(@($failures|ForEach-Object Message)-join ' / '))}

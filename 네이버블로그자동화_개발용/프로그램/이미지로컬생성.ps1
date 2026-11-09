#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ManifestPath)

$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$manifest=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
$assets=@($manifest.assets|Sort-Object order)
$width=[int]$manifest.specification.width
$height=[int]$manifest.specification.height

foreach($asset in $assets){
    $base=[string]$asset.originalBaseName
    $existing=@(Get-ChildItem -LiteralPath ([string]$manifest.originalDirectory) -File -ErrorAction SilentlyContinue|Where-Object {$_.BaseName -eq $base})
    if($existing.Count -eq 1){continue}
    $seed=[Math]::Abs(([string]$asset.prompt).GetHashCode())+[int]$asset.order
    $random=New-Object Random($seed)
    $path=Join-Path ([string]$manifest.originalDirectory) ($base+'.png')
    $bitmap=New-Object Drawing.Bitmap($width,$height)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::HighQuality
        $background=New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Rectangle(0,0,$width,$height)),[Drawing.Color]::FromArgb(8,24,48),[Drawing.Color]::FromArgb(20,88,105),25)
        try{$graphics.FillRectangle($background,0,0,$width,$height)}finally{$background.Dispose()}
        $gridPen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(45,120,220,235),2)
        try{
            for($x=0;$x -lt $width;$x+=80){$graphics.DrawLine($gridPen,$x,0,$x,$height)}
            for($y=0;$y -lt $height;$y+=80){$graphics.DrawLine($gridPen,0,$y,$width,$y)}
        }finally{$gridPen.Dispose()}
        $nodes=New-Object 'System.Collections.Generic.List[Drawing.Point]'
        for($i=0;$i -lt 12;$i++){$nodes.Add((New-Object Drawing.Point($random.Next(90,$width-90),$random.Next(90,$height-90))))}
        $linkPen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(150,53,220,205),5)
        try{for($i=1;$i -lt $nodes.Count;$i++){$graphics.DrawLine($linkPen,$nodes[$i-1],$nodes[$i])}}finally{$linkPen.Dispose()}
        for($i=0;$i -lt $nodes.Count;$i++){
            $radius=18+($i%4)*7
            $brush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(225,80+($i*11)%150,210,170+($i*7)%80))
            try{$graphics.FillEllipse($brush,$nodes[$i].X-$radius,$nodes[$i].Y-$radius,$radius*2,$radius*2)}finally{$brush.Dispose()}
        }
        $panelBrush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(170,5,18,35))
        $accentPen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(220,111,244,223),6)
        try{
            for($rack=0;$rack -lt 4;$rack++){
                $rx=100+$rack*150;$ry=430-($rack%2)*35
                $graphics.FillRectangle($panelBrush,$rx,$ry,110,250)
                $graphics.DrawRectangle($accentPen,$rx,$ry,110,250)
                for($slot=1;$slot -le 5;$slot++){$graphics.DrawLine($accentPen,$rx+18,$ry+$slot*38,$rx+92,$ry+$slot*38)}
            }
            $graphics.DrawArc($accentPen,690,180,360,360,205,275)
            $graphics.DrawEllipse($accentPen,780,270,180,180)
        }finally{$panelBrush.Dispose();$accentPen.Dispose()}
        $bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)
    }finally{$graphics.Dispose();$bitmap.Dispose()}
}
[pscustomobject]@{generated=$assets.Count;mode='LocalTechnicalIllustration';originalDirectory=[string]$manifest.originalDirectory}|ConvertTo-Json

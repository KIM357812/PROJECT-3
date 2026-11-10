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
        $backgroundSchemes=@(
            @([Drawing.Color]::FromArgb(8,24,48),[Drawing.Color]::FromArgb(20,88,105),25),
            @([Drawing.Color]::FromArgb(35,18,52),[Drawing.Color]::FromArgb(9,93,92),90),
            @([Drawing.Color]::FromArgb(13,48,34),[Drawing.Color]::FromArgb(36,54,112),155),
            @([Drawing.Color]::FromArgb(58,29,20),[Drawing.Color]::FromArgb(18,76,118),5)
        )
        $scheme=$backgroundSchemes[([int]$asset.order-1)%$backgroundSchemes.Count]
        $background=New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Rectangle(0,0,$width,$height)),$scheme[0],$scheme[1],[single]$scheme[2])
        try{$graphics.FillRectangle($background,0,0,$width,$height)}finally{$background.Dispose()}
        $accentPen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(225,111,244,223),7)
        $softPen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(155,88,180,235),4)
        $panelBrush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(190,5,18,35))
        $lightBrush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(220,121,224,205))
        try{
            switch([int]$asset.order){
                1 {
                    # 대표: 데이터센터와 전력망을 한 화면에 담은 넓은 전경
                    for($rack=0;$rack -lt 4;$rack++){
                        $rx=70+$rack*145;$ry=400-($rack%2)*30
                        $graphics.FillRectangle($panelBrush,$rx,$ry,110,280)
                        $graphics.DrawRectangle($accentPen,$rx,$ry,110,280)
                        for($slot=1;$slot -le 5;$slot++){$graphics.DrawLine($softPen,$rx+18,$ry+$slot*42,$rx+92,$ry+$slot*42)}
                    }
                    $graphics.DrawLine($accentPen,720,610,905,220);$graphics.DrawLine($accentPen,905,220,1080,610)
                    $graphics.DrawLine($softPen,770,500,1030,500);$graphics.DrawLine($softPen,810,410,990,410)
                    $graphics.DrawLine($softPen,565,535,880,400)
                }
                2 {
                    # 현황: 배터리 자가점검과 짧은 전류 피크를 보여주는 근접 계측 장면
                    $graphics.FillRectangle($panelBrush,400,220,400,430)
                    $graphics.DrawRectangle($accentPen,400,220,400,430)
                    for($cell=0;$cell -lt 4;$cell++){$graphics.DrawRectangle($softPen,445+$cell*82,470,62,120)}
                    $points=New-Object 'System.Collections.Generic.List[Drawing.Point]'
                    for($x=80;$x -le 1120;$x+=40){
                        $y=180+[int](55*[Math]::Sin($x/75.0));if($x -gt 560 -and $x -lt 650){$y-=120}
                        $points.Add((New-Object Drawing.Point($x,$y)))
                    }
                    for($i=1;$i -lt $points.Count;$i++){$graphics.DrawLine($accentPen,$points[$i-1],$points[$i])}
                    $graphics.DrawEllipse($softPen,90,410,230,230);$graphics.DrawLine($accentPen,205,525,285,455)
                }
                3 {
                    # 구조: 설비·제어·계통을 서로 다른 세 구역과 화살표로 분리
                    $boxes=@((New-Object Drawing.Rectangle(70,260,260,310)),(New-Object Drawing.Rectangle(470,170,260,400)),(New-Object Drawing.Rectangle(870,260,260,310)))
                    foreach($box in $boxes){$graphics.FillRectangle($panelBrush,$box);$graphics.DrawRectangle($accentPen,$box)}
                    for($row=0;$row -lt 4;$row++){$graphics.DrawLine($softPen,105,330+$row*55,295,330+$row*55)}
                    for($cell=0;$cell -lt 3;$cell++){$graphics.DrawEllipse($softPen,525,245+$cell*95,150,65)}
                    $graphics.DrawLine($softPen,930,500,930,335);$graphics.DrawLine($softPen,930,335,1000,405);$graphics.DrawLine($softPen,1000,405,1080,315)
                    $graphics.DrawLine($accentPen,330,415,470,370);$graphics.DrawLine($accentPen,730,370,870,415)
                    $graphics.FillPolygon($lightBrush,@((New-Object Drawing.Point(460,370)),(New-Object Drawing.Point(430,350)),(New-Object Drawing.Point(432,385))))
                    $graphics.FillPolygon($lightBrush,@((New-Object Drawing.Point(860,415)),(New-Object Drawing.Point(830,395)),(New-Object Drawing.Point(832,430))))
                }
                default {
                    # 전망: 현재 설비에서 미래 저탄소 전력망으로 이어지는 원근감 있는 장면
                    $graphics.FillRectangle($panelBrush,0,560,$width,240)
                    $graphics.DrawLine($accentPen,40,560,1160,560)
                    for($tower=0;$tower -lt 3;$tower++){
                        $tx=140+$tower*210;$graphics.DrawLine($softPen,$tx,560,$tx+70,260);$graphics.DrawLine($softPen,$tx+140,560,$tx+70,260)
                        $graphics.DrawLine($softPen,$tx+20,470,$tx+120,470);$graphics.DrawLine($softPen,$tx+38,390,$tx+102,390)
                    }
                    $graphics.DrawArc($accentPen,600,80,500,500,190,150)
                    $graphics.DrawLine($accentPen,750,480,870,350);$graphics.DrawLine($accentPen,870,350,1020,210)
                    for($i=0;$i -lt 4;$i++){$graphics.FillEllipse($lightBrush,690+$i*115,500-$i*95,34,34)}
                }
            }
        }finally{$panelBrush.Dispose();$lightBrush.Dispose();$accentPen.Dispose();$softPen.Dispose()}
        $bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)
    }finally{$graphics.Dispose();$bitmap.Dispose()}
}
[pscustomobject]@{generated=$assets.Count;mode='LocalTechnicalIllustration';originalDirectory=[string]$manifest.originalDirectory}|ConvertTo-Json

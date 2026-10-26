param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\42\media\ui\ThreatAlert"),
    [string]$TestOutputPath = (Join-Path $PSScriptRoot "..\assets\rear_zombie_indicator_test.png")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$radii = @(128, 176, 224)
$arcDegrees = 18
$strokeWidth = 5.25
$arrowLength = 12
$arrowHalfWidth = 6
$colours = @{
    red = "#FF3030"
    yellow = "#FFD11F"
    white = "#FFFFFF"
}

function Format-Number([double]$value) {
    return $value.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
}

function Get-PolarPoint([double]$center, [double]$radius, [double]$degrees) {
    $radians = $degrees * [Math]::PI / 180
    return [pscustomobject]@{
        X = $center + $radius * [Math]::Cos($radians)
        Y = $center + $radius * [Math]::Sin($radians)
    }
}

function New-Svg([int]$radius, [string]$colour, [string]$path) {
    $canvasRadius = $radius + 16
    $center = $canvasRadius
    $start = Get-PolarPoint $center $radius (90 - $arcDegrees / 2)
    $finish = Get-PolarPoint $center $radius (90 + $arcDegrees / 2)
    $tip = Get-PolarPoint $center ($radius + $arrowLength) 90
    $baseLeft = [pscustomobject]@{ X = $center - $arrowHalfWidth; Y = $center + $radius - 3 }
    $baseRight = [pscustomobject]@{ X = $center + $arrowHalfWidth; Y = $center + $radius - 3 }
    $size = $canvasRadius * 2
    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" viewBox="0 0 $size $size">
  <path d="M $(Format-Number $start.X) $(Format-Number $start.Y) A $radius $radius 0 0 1 $(Format-Number $finish.X) $(Format-Number $finish.Y)" fill="none" stroke="$colour" stroke-width="$strokeWidth" stroke-linecap="round"/>
  <path d="M $(Format-Number $tip.X) $(Format-Number $tip.Y) L $(Format-Number $baseRight.X) $(Format-Number $baseRight.Y) L $(Format-Number $baseLeft.X) $(Format-Number $baseLeft.Y) Z" fill="$colour"/>
</svg>
"@
    [IO.File]::WriteAllText($path, $svg.Trim() + [Environment]::NewLine, [Text.Encoding]::UTF8)
}

function New-Png([int]$radius, [string]$colour, [string]$path, [double]$iconScale = 1) {
    $arcDegrees = 18 * $iconScale
    $strokeWidth = 5.25 * $iconScale
    $arrowLength = 12 * $iconScale
    $arrowHalfWidth = 6 * $iconScale
    $canvasRadius = $radius + [int][Math]::Ceiling(16 * $iconScale)
    $size = $canvasRadius * 2
    $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($colour), [float]$strokeWidth)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawArc($pen, $canvasRadius - $radius, $canvasRadius - $radius,
        $radius * 2, $radius * 2, (90 - $arcDegrees / 2), $arcDegrees)

    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colour))
    $points = New-Object System.Drawing.PointF[] 3
    $points[0] = [System.Drawing.PointF]::new([float]$canvasRadius, [float]($canvasRadius + $radius + $arrowLength))
    $points[1] = [System.Drawing.PointF]::new([float]($canvasRadius + $arrowHalfWidth), [float]($canvasRadius + $radius - 3))
    $points[2] = [System.Drawing.PointF]::new([float]($canvasRadius - $arrowHalfWidth), [float]($canvasRadius + $radius - 3))
    $graphics.FillPolygon($brush, $points)

    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $brush.Dispose()
    $pen.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

function New-TestImage([string]$path) {
    $width = 1200
    $height = 720
    $bitmap = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::FromArgb(18, 18, 18))

    $font = New-Object System.Drawing.Font("Segoe UI", 16)
    $smallFont = New-Object System.Drawing.Font("Segoe UI", 12)
    $labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $mutedBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::LightGray)
    $checkerA = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(42, 42, 42))
    $checkerB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(74, 74, 74))

    for ($y = 0; $y -lt 300; $y += 16) {
        for ($x = 0; $x -lt 320; $x += 16) {
            $brush = (($x / 16 + $y / 16) % 2 -eq 0) ? $checkerA : $checkerB
            $graphics.FillRectangle($brush, $x, $y, 16, 16)
        }
    }
    $graphics.DrawString("1. Isolated transparent asset", $font, $labelBrush, 16, 320)

    $redAsset = [System.Drawing.Bitmap]::FromFile((Join-Path $OutputDirectory "rear_zombie_indicator_red_128.png"))
    $graphics.DrawImageUnscaled($redAsset, 16, 24)
    $graphics.DrawString("2. Asset centered at the bottom", $font, $labelBrush, 300, 320)
    $referencePen = New-Object System.Drawing.Pen([System.Drawing.Color]::RoyalBlue, 3)
    $graphics.DrawEllipse($referencePen, 304, 52, 256, 256)
    $graphics.DrawImageUnscaled($redAsset, 288, 36)
    $graphics.DrawString("3. Sample 18° sectors sharing one center", $font, $labelBrush, 680, 410)
    $centerX = 850
    $centerY = 200
    $circleRadius = 176
    $redLargeAsset = [System.Drawing.Bitmap]::FromFile((Join-Path $OutputDirectory "rear_zombie_indicator_red_176.png"))
    $graphics.DrawEllipse($referencePen, $centerX - $circleRadius, $centerY - $circleRadius,
        $circleRadius * 2, $circleRadius * 2)
    for ($index = 0; $index -lt 10; $index++) {
        $graphics.TranslateTransform([float]$centerX, [float]$centerY)
        $graphics.RotateTransform([float]($index * 36))
        $graphics.DrawImageUnscaled($redLargeAsset, -$redLargeAsset.Width / 2, -$redLargeAsset.Height / 2)
        $graphics.ResetTransform()
    }
    $graphics.DrawString("Same radius and centered rotation", $smallFont, $mutedBrush, 690, 390)

    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $referencePen.Dispose()
    $checkerA.Dispose()
    $checkerB.Dispose()
    $labelBrush.Dispose()
    $mutedBrush.Dispose()
    $font.Dispose()
    $smallFont.Dispose()
    $redAsset.Dispose()
    $redLargeAsset.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
foreach ($radius in $radii) {
    foreach ($name in $colours.Keys) {
        $colour = $colours[$name]
        New-Png $radius $colour (Join-Path $OutputDirectory "rear_zombie_indicator_${name}_$radius.png")
    }
}

for ($radius = 96; $radius -le 320; $radius += 16) {
    foreach ($iconSize in @(75, 100, 125)) {
        $iconScale = $iconSize / 100.0
        $path = Join-Path $OutputDirectory "rear_zombie_indicator_white_${radius}_${iconSize}.png"
        New-Png $radius $colours.white $path $iconScale
    }
}

$assetDirectory = Join-Path $PSScriptRoot "..\assets"
New-Item -ItemType Directory -Force -Path $assetDirectory | Out-Null
New-Svg 96 $colours.red (Join-Path $assetDirectory "rear_zombie_indicator.svg")
New-Svg 96 $colours.yellow (Join-Path $assetDirectory "rear_zombie_indicator_yellow.svg")
New-TestImage $TestOutputPath

Write-Output "Generated rear zombie indicator assets in $OutputDirectory"

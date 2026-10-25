param([string]$Img, [int]$X = 915, [int]$Y0 = 230, [int]$Y1 = 310, [int]$Step = 2)
# 沿垂直线采样 RGB 值（结算按钮判定式校准用）
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap $Img
for ($y = $Y0; $y -le $Y1; $y += $Step) {
    $c = $bmp.GetPixel($X, $y)
    $old = if ($c.R -gt 100 -and ($c.R - $c.B) -gt 50 -and $c.G -gt 22 -and $c.G -lt 78) { "OLD-HIT" } else { "-------" }
    "y=$y R=$($c.R) G=$($c.G) B=$($c.B) $old"
}
$bmp.Dispose()

param([string]$Img, [int]$X0 = 185, [int]$Y0 = 120, [int]$X1 = 290, [int]$Y1 = 205)
# 按钮区像素签名诊断（自动战斗开关状态标定用）
# 判定源=左上角按钮（用户 2026-10-23 定论：唯一可靠判据）：
#   关闭态=橙红圆形图标+「自动战斗」  开启态=蓝色晶体图标+「取消自动」
# 输出 blue/warm/white 三种像素计数，用于设定/校验 AUTO_ON/AUTO_OFF 阈值
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap $Img
$blue = 0; $warm = 0; $white = 0; $total = 0
for ($y = $Y0; $y -le $Y1; $y += 2) { for ($x = $X0; $x -le $X1; $x += 2) {
    $c = $bmp.GetPixel($x, $y); $total++
    if ($c.B -gt 130 -and ($c.B - $c.R) -gt 40 -and ($c.B - $c.G) -gt 30) { $blue++ }
    elseif ($c.R -gt 140 -and ($c.R - $c.B) -gt 60) { $warm++ }
    if ($c.R -gt 215 -and $c.G -gt 215 -and $c.B -gt 215) { $white++ }
} }
"img=$Img region=($X0,$Y0)-($X1,$Y1)"
"blue=$blue warm=$warm white=$white total=$total"
$bmp.Dispose()

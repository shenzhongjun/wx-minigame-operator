param([string]$Img, [int]$X0 = 150, [int]$Y0 = 140, [int]$X1 = 310, [int]$Y1 = 210, [int]$Thresh = 170, [ValidateSet('white','gold')][string]$Mode = 'white')
# 像素包围盒诊断（2026-10-25 体系重打磨新增）：区域包围盒+计数，杜绝目测缩放图（事件19）
#   white 模式：R,G,B>Thresh 白色像素（模板文字区重标定）
#   gold   模式：R>200 G>140 B<110 R-B>90 金色像素（金框/金标签检测标定，选角卡/副本tab/练习tab）
# 用法：wxwhitebox.ps1 -Img <png> [-X0 -Y0 -X1 -Y1 -Thresh -Mode]
# 输入图非设计尺寸会自动最近邻归一化到 1138x708，bbox 输出即设计坐标
. (Join-Path $PSScriptRoot '_wxcommon.ps1')
$bmp = New-Object System.Drawing.Bitmap $Img
if ($bmp.Width -ne $WX_DESIGN_W -or $bmp.Height -ne $WX_DESIGN_H) {
    $norm = Resize-WxBitmapNearest $bmp $WX_DESIGN_W $WX_DESIGN_H
    if (-not [object]::ReferenceEquals($norm, $bmp)) { $bmp.Dispose() }
    $bmp = $norm
}
$minX = 999999; $minY = 999999; $maxX = -1; $maxY = -1; $n = 0
for ($y = $Y0; $y -le $Y1; $y++) { for ($x = $X0; $x -le $X1; $x++) {
    $c = $bmp.GetPixel($x, $y)
    $hit = $false
    if ($Mode -eq 'white') { $hit = ($c.R -gt $Thresh -and $c.G -gt $Thresh -and $c.B -gt $Thresh) }
    else { $hit = ($c.R -gt 200 -and $c.G -gt 140 -and $c.B -lt 110 -and ($c.R - $c.B) -gt 90) }
    if ($hit) {
        $n++
        if ($x -lt $minX) { $minX = $x }
        if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }
        if ($y -gt $maxY) { $maxY = $y }
    }
} }
$bmp.Dispose()
"mode=$Mode bbox=($minX,$minY)-($maxX,$maxY) count=$n region=($X0,$Y0)-($X1,$Y1) thresh=$Thresh"

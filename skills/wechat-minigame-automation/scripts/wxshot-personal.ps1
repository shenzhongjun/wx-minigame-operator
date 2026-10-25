param([string]$Out = "$env:TEMP\wrx\shot.png", [int]$OX = -1, [int]$OY = 180, [int]$W = -1, [int]$H = -1, [int]$Pid2 = 0, [switch]$Grid)
# 个人电脑版客户端区截图（DPI-aware 物理像素），供视觉确认画面状态
# 两种定位模式：
#   -OX >= 0：绝对屏幕坐标模式（OX/OY/W/H = 屏幕绝对值，窗口挪动后过期——不推荐）
#   -OX  < 0：窗口锚定模式（推荐）——按标题「勇士之心」匹配窗口，自动取客户区原点与尺寸
#            （2026-10-25 根因更正：历史"H=怪值"真凶=PowerShell 变量大小写不敏感，$h 句柄与 $H 参数同名冲突；
#              并非「多窗口选错」——wxenumwin 实测该 pid 仅一个可见窗口。修法=句柄改名 $hwnd）
# 纯色画面警告：最小化/遮挡/锁屏时 CopyFromScreen 抓到整屏纯色（事件4/15），打 WARN 提示先 wxrestore
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

if ($OX -lt 0) {
    $hwnd = Find-GameWindow -Pid2 $Pid2
    if ($hwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $geo = Get-ClientGeometry $hwnd -NoAssert   # 诊断工具：只报尺寸不强断言
    $OX = $geo.OX; $OY = $geo.OY
    if ($W -le 0) { $W = $geo.W }
    if ($H -le 0) { $H = $geo.H }
    "anchored origin=$OX,$OY size=${W}x$H"
}
$b = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($b)
$g.CopyFromScreen($OX, $OY, 0, 0, (New-Object System.Drawing.Size $W, $H))
$g.Dispose()
# 纯色守卫（事件4/15）：整屏同色=画面不可信
$distinct = @{}
for ($yy = 0; $yy -lt $b.Height; $yy += 40) { for ($xx = 0; $xx -lt $b.Width; $xx += 40) {
  $distinct[$b.GetPixel($xx,$yy).ToArgb()] = $true
}}
$flat = ($distinct.Count -le 2)
# -Grid：叠加 100px 网格与坐标刻度（读图免心算缩放换算）
if ($Grid) {
    $g2 = [System.Drawing.Graphics]::FromImage($b)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 1
    $font = New-Object System.Drawing.Font 'Arial', 10
    $brush = [System.Drawing.Brushes]::Red
    for ($gx = 0; $gx -lt $W; $gx += 100) { $g2.DrawLine($pen, $gx, 0, $gx, $H); $g2.DrawString("$gx", $font, $brush, $gx + 2, 2) }
    for ($gy = 100; $gy -lt $H; $gy += 100) { $g2.DrawLine($pen, 0, $gy, $W, $gy); $g2.DrawString("$gy", $font, $brush, 2, $gy + 2) }
    $g2.Dispose()
}
$dir = Split-Path $Out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$b.Save($Out)
$b.Dispose()
"saved=$Out"
if ($flat) { "WARN: 截图为纯色画面（最小化/遮挡/锁屏），内容不可信，先跑 wxrestore-personal.ps1 再重截" }

param([string]$Out = "$env:TEMP\wrx\shot.png", [int]$OX = -1, [int]$OY = 180, [int]$W = -1, [int]$H = -1, [int]$Pid2 = 0, [switch]$Grid, [switch]$Raw)
# 客户端区截图（设计坐标，基准 1138x708），供视觉确认画面状态
# 两种定位模式：
#   -OX >= 0：绝对屏幕坐标模式（OX/OY/W/H = 屏幕绝对值，窗口挪动后过期——不推荐）
#   -OX  < 0：窗口锚定模式（推荐）——按标题匹配窗口，抓图并归一化到设计尺寸；
#            输出图内坐标=设计坐标，可与 coords.md 直接对照。
#            ⚠️ -Raw 警示（2026-10-27 23:2x 用户令）：-Raw 输出=仅画布实时尺寸，**没有标题栏、图内坐标≠设计坐标**——
#            图上量出的 y 是画布相对值，换算 design_y = 55 + y/S、design_x = x/S（严禁手算，走 ConvertFrom-ScreenPoint；
#            语义详见 coords.md「三种抓图的坐标语义」表）。看图量坐标前先确认自己拿的是哪种图。
#            （2026-10-25 根因更正：历史"H=怪值"真凶=PowerShell 变量大小写不敏感，$h 句柄与 $H 参数同名冲突；
#              并非「多窗口选错」——wxenumwin 实测该 pid 仅一个可见窗口。修法=句柄改名 $hwnd）
# 纯色画面警告：最小化/遮挡/锁屏时 CopyFromScreen 抓到整屏纯色（事件4/15），打 WARN 提示先 wxrestore
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

if ($OX -lt 0) {
    $hwnd = Find-GameWindow -Pid2 $Pid2
    if ($hwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    # 前台守卫（todo 第3项，2026-10-27 接线）：不在前台先拉回，防抓到旧画面
    if (-not (Confirm-WxForeground $hwnd 'shot')) { "ERR: game not foreground，抓图拒绝（防假数据）"; exit 7 }
    $geo = Get-ClientGeometry $hwnd
    $b = Get-DesignBitmap $geo -Raw:$Raw
    $W = $b.Width; $H = $b.Height
    "anchored origin=$($geo.OX),$($geo.OY) size=${W}x$H scale=$([math]::Round($geo.S,4))$(if ($Raw) { ' raw' } else { ' design' })"
} else {
    $b = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($OX, $OY, 0, 0, (New-Object System.Drawing.Size $W, $H))
    $g.Dispose()
}
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
if ($flat) { "WARN: 截图为纯色画面（最小化/遮挡/锁屏），内容不可信，先跑 wxrestore.ps1 再重截" }

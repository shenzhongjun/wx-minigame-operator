param([int]$Pid2 = 0, [switch]$SkipStart)
# wxnav-tower.ps1 - 毁灭之塔练习模式导航链（2026-10-25 体系重打磨新增）
# 前提：当前在主城（或用 -SkipStart 跳过 冒险/副本 两段——已在副本页时使用）
# 链路：冒险(936,664) → 副本(843,563) → 毁灭之塔卡(880,212) → 练习模式(444,163) → 出战(957,633)
# 每段后内嵌像素断言（阈值来自 wx-verify 标注截图实测），断言失败=截图留证+exit 非零，绝不盲点：
#   A 副本页：日常副本 tab 金色 ≥150（实测 261；选角页杂金 41）
#   B 塔页：结算带红色 ≥10（塔页红月实测 16-22；副本页 0）
#   C 练习已选：练习说明框白色大字块 ≥400（区域 (395,195)-(625,268)，阈值220实测正样本990、
#     正常模式无说明框≈0；标定件 冒烟测试\calib-practice-white-2026-10-27.ps1。旧「tab下划线
#     金≥50」判据作废——细金线在 S≈1.035 缩放下亚像素化，实测金=2 误报失败，2026-10-27 用户裁定）
# 出战后自动战斗由调用方 wxclick auto / wxgrind 负责
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$hwnd = Find-GameWindow -Pid2 $Pid2
if ($hwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
[WXCommon]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 400
# 前台守卫（2026-10-27 16:5x 用户定版）：不在前台→log 留痕+拉回，重试 2 次仍失败才 STOP
if (-not (Confirm-WxForeground $hwnd)) { "ERR: game not foreground (拉回重试后仍不在前台)，拒绝导航"; exit 7 }
$geo = Get-ClientGeometry $hwnd
if (-not (Test-WxMinClientW $geo.W)) { "ERR: window too small ($($geo.W)x$($geo.H))，拒绝导航"; exit 7 }
"client=$($geo.W)x$($geo.H) origin=$($geo.OX),$($geo.OY) scale=$([math]::Round($geo.S,4))"
$shot = "C:\Users\zhouyijie\WorkBuddy\游戏\wx-verify\nav_tower_fail.png"

function Invoke-NavClick([int]$x, [int]$y, [int]$delayMs) {
    # 每段点击前重读几何：进塔转场会重申客户区尺寸（1138→1135），避免用过期换算
    $g = Get-ClientGeometry $hwnd
    $p = ConvertTo-ScreenPoint $g $x $y
    Start-Sleep -Milliseconds 250
    [WXCommon]::SetCursorPos($p.X, $p.Y) | Out-Null
    Start-Sleep -Milliseconds 100
    [WXCommon]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [WXCommon]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    "click $x,$y -> $($p.X),$($p.Y)"
    Start-Sleep -Milliseconds $delayMs
}
function Get-LiveCount([int]$x0, [int]$y0, [int]$x1, [int]$y1, [string]$mode) {
    $g = Get-ClientGeometry $hwnd
    $bmp = Get-DesignRegion $g $x0 $y0 $x1 $y1
    $w = $bmp.Width; $h = $bmp.Height
    $n = 0
    for ($y = 0; $y -lt $h; $y++) { for ($x = 0; $x -lt $w; $x++) {
        $c = $bmp.GetPixel($x, $y)
        if ($mode -eq 'gold' -and $c.R -gt 200 -and $c.G -gt 140 -and $c.B -lt 110 -and ($c.R - $c.B) -gt 90) { $n++ }
        elseif ($mode -eq 'white' -and $c.R -ge 220 -and $c.G -ge 220 -and $c.B -ge 220) { $n++ }
        elseif ($mode -eq 'red' -and $c.R -gt 100 -and ($c.R - $c.B) -gt 50 -and $c.G -gt 22 -and $c.G -lt 78) { $n++ }
    } }
    $bmp.Dispose()
    return $n
}
function Stop-NavFail([string]$step, [string]$detail) {
    "NAV_FAIL: $step ($detail)"
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\wxshot.ps1" -Out $shot -Pid2 $Pid2 | Select-Object -Last 1
    "fail screenshot=$shot"
    exit 9
}

# --- A段：主城 → 副本页 ---
if (-not $SkipStart) {
    Invoke-NavClick 936 664 1800   # 冒险
    Invoke-NavClick 843 563 2200   # 副本
}
$a = Get-LiveCount 30 140 160 205 'gold'
"checkA dungeon-tab gold=$a (need >=150)"
if ($a -lt 150) { Stop-NavFail 'A 副本页' "gold=$a" }

# --- B段：进塔 ---
Invoke-NavClick 880 212 2200   # 毁灭之塔卡
$b = Get-LiveCount 890 225 940 445 'red'
"checkB tower-page red=$b (need >=100)"
if ($b -lt 100) { Stop-NavFail 'B 塔页' "red=$b" }

# --- C段：切练习模式 ---
Invoke-NavClick 444 163 1800   # 练习模式 tab
$c = Get-LiveCount 395 195 625 268 'white'
"checkC practice-tip white=$c (need >=400)"
if ($c -lt 400) { Stop-NavFail 'C 练习模式' "white=$c" }

# --- 出战 ---
Invoke-NavClick 957 633 4000
"NAV_OK: tower practice battle entered"
exit 0

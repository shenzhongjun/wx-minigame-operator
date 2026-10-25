param([int]$Pid2 = 0, [int]$ClientW = 0, [int]$ClientH = 0)
# wxresize-personal.ps1 - 强制客户区回定版尺寸（2026-10-25 新增，简报-窗口尺寸调整 实现）
# 用途：WeChatAppEx 最小化恢复/系统行为会导致客户区 ±1px 级漂移（1138→1139 实测），
#       本脚本把客户区强制设回定版尺寸，尺寸断言恢复放行，无需任何重标定。
# 原理：定位窗口 → 最小化/最大化先还原 → AdjustWindowRect 客户区→外框换算 → SetWindowPos → 回读校验
# 参数：-Pid2 0=按标题自动发现；-ClientW/-ClientH 缺省用 _wxcommon 定版值
# 注意：只允许设回定版尺寸（±2px 内算成功）；改到其它尺寸=模板/坐标全失效，禁止
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$hwnd = Find-GameWindow -Pid2 $Pid2
if ($hwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
$geo = Get-ClientGeometry $hwnd -NoAssert
"before: client=$($geo.W)x$($geo.H) origin=$($geo.OX),$($geo.OY)"

$tw = if ($ClientW -gt 0) { $ClientW } else { $WX_CLIENT_W }
$th = if ($ClientH -gt 0) { $ClientH } else { $WX_CLIENT_H }
if ($tw -ne $WX_CLIENT_W -or $th -ne $WX_CLIENT_H) {
    "ERR: 目标尺寸 ${tw}x${th} ≠ 定版 $($WX_CLIENT_W)x$($WX_CLIENT_H)，改其它尺寸=全套标定作废，禁止。退出"
    exit 3
}
if ($geo.W -eq $tw -and $geo.H -eq $th) { "ALREADY: 客户区已是定版尺寸，无需调整"; exit 0 }

if ([WXCommon]::IsIconic($hwnd)) { [WXCommon]::ShowWindow($hwnd, 9) | Out-Null; Start-Sleep -Milliseconds 500; "restored from minimized" }
if ([WXCommon]::IsZoomed($hwnd)) { [WXCommon]::ShowWindow($hwnd, 9) | Out-Null; Start-Sleep -Milliseconds 500; "restored from maximized" }

# 客户区→外框换算：不用 AdjustWindowRect（WeChatAppEx 是自绘边框窗口，实测 chrome 仅细边框，
# AdjustWindowRect 会多加 37px 标题栏致高度超差——实测教训）。改用实测 chrome 差值：
$wr = New-Object WXCommon+RECT
[WXCommon]::GetWindowRect($hwnd, [ref]$wr) | Out-Null
$chromeW = ($wr.R - $wr.L) - $geo.W
$chromeH = ($wr.B - $wr.T) - $geo.H
$winW = $tw + $chromeW
$winH = $th + $chromeH
"chrome=${chromeW}x${chromeH} -> outer ${winW}x${winH}"
$ok = [WXCommon]::SetWindowPos($hwnd, [IntPtr]::Zero, $wr.L, $wr.T, $winW, $winH, 0x0004)  # SWP_NOZORDER
if (-not $ok) { "ERR: SetWindowPos failed"; exit 2 }
Start-Sleep -Milliseconds 800

$geo2 = Get-ClientGeometry $hwnd -NoAssert
"after: client=$($geo2.W)x$($geo2.H) origin=$($geo2.OX),$($geo2.OY) (target ${tw}x${th})"
if ([math]::Abs($geo2.W - $tw) -le 2 -and [math]::Abs($geo2.H - $th) -le 2) {
    "RESIZE_OK: 客户区已回到定版尺寸±2px，尺寸断言恢复放行，无需重标定"
    exit 0
}
"RESIZE_MISMATCH: 回读 $($geo2.W)x$($geo2.H) 与目标 ${tw}x${th} 差超 2px（DPI 取整/窗口样式异常），人工检查"
exit 2

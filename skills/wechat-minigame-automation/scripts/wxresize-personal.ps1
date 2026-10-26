param([int]$Pid2 = 0, [int]$ClientW = 0, [int]$ClientH = 0)
# wxresize-personal.ps1 - 把客户区复位到设计基准尺寸（2026-10-25 新增；2026-10-26 改为可选工具）
# 用途：相对坐标体系下已支持等比缩放，本脚本仅用于异常恢复/人工想回到 1138x708 时使用。
#       也可指定其它同比例尺寸（例如 1252x779）做缩放验证。
# 原理：定位窗口 → 最小化/最大化先还原 → 实测 chrome 差值 → SetWindowPos → 回读校验
# 参数：-Pid2 0=按标题自动发现；-ClientW/-ClientH 缺省用设计基准值
# 注意：目标尺寸必须与设计基准同长宽比（±1.2%），否则坐标换算不成立
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$hwnd = Find-GameWindow -Pid2 $Pid2
if ($hwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
$geo = Get-ClientGeometry $hwnd -NoAssert
"before: client=$($geo.W)x$($geo.H) origin=$($geo.OX),$($geo.OY)"

$tw = if ($ClientW -gt 0) { $ClientW } else { $WX_CLIENT_W }
$th = if ($ClientH -gt 0) { $ClientH } else { $WX_CLIENT_H }
if ([math]::Abs(($tw / $WX_DESIGN_W) - ($th / $WX_DESIGN_H)) -gt 0.012) {
    "ERR: 目标尺寸 ${tw}x${th} 与设计基准 $($WX_DESIGN_W)x$($WX_DESIGN_H) 长宽比不符，坐标换算不成立。退出"
    exit 3
}
if ($geo.W -eq $tw -and $geo.H -eq $th) { "ALREADY: 客户区已是目标尺寸，无需调整"; exit 0 }

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
    "RESIZE_OK: 客户区已回到目标尺寸±2px（相对坐标自动换算，无需重标定）"
    exit 0
}
"RESIZE_MISMATCH: 回读 $($geo2.W)x$($geo2.H) 与目标 ${tw}x${th} 差超 2px（DPI 取整/窗口样式异常），人工检查"
exit 2

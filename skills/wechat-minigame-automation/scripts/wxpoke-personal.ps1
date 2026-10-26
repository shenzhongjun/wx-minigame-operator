param([int]$Pid2 = 0, [int]$CX = 210, [int]$CY = 558, [int]$DX = 45, [int]$DY = 0, [int]$HoldMs = 150)
# 移动轮盘保活戳（2026-10-24 用户方案：左下角轮盘在任何画面都绝对安全）
# 动作 = 按下 → 增量拖到 (CX+DX, CY+DY) → 拖回中心 → 松开，全程 ~0.6s
# 轮盘标定：中心 (210,558)（设计坐标，基准 1138x708），外环半径 ~70px —— 拖动幅度 ≤45 必在环内
# 用途：批间/长思考前戳一下，重置游戏挂机计时，防「长时间未操作」弹窗
# 窗口查找/前台守卫/尺寸断言由 _wxcommon.ps1 单源提供；pid 0=按标题自动发现
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$h = Find-GameWindow -Pid2 $Pid2
if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
[WXCommon]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 350
if ([WXCommon]::GetForegroundWindow() -ne $h) {
    [WXCommon]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 600
    if ([WXCommon]::GetForegroundWindow() -ne $h) { "ERR: game not foreground，拒绝戳"; "DONE"; exit 7 }
}
$geo = Get-ClientGeometry $h

# 按下
$p = ConvertTo-ScreenPoint $geo $CX $CY
[WXCommon]::SetCursorPos($p.X, $p.Y) | Out-Null
Start-Sleep -Milliseconds 100
[WXCommon]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)      # LEFTDOWN
Start-Sleep -Milliseconds 80
# 拖出
$steps = 6
for ($i = 1; $i -le $steps; $i++) {
    $p = ConvertTo-ScreenPoint $geo ($CX + [int]($DX * $i / $steps)) ($CY + [int]($DY * $i / $steps))
    [WXCommon]::SetCursorPos($p.X, $p.Y) | Out-Null
    Start-Sleep -Milliseconds 30
}
Start-Sleep -Milliseconds $HoldMs
# 拖回中心
for ($i = $steps; $i -ge 0; $i--) {
    $p = ConvertTo-ScreenPoint $geo ($CX + [int]($DX * $i / $steps)) ($CY + [int]($DY * $i / $steps))
    [WXCommon]::SetCursorPos($p.X, $p.Y) | Out-Null
    Start-Sleep -Milliseconds 30
}
[WXCommon]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)      # LEFTUP
Start-Sleep -Milliseconds 100
$p = ConvertTo-ScreenPoint $geo $CX $CY
[WXCommon]::SetCursorPos($p.X, $p.Y) | Out-Null
"POKED c=($CX,$CY) d=($DX,$DY) scale=$([math]::Round($geo.S,4))"
"DONE"

param([int]$Pid2 = 0, [int]$X = 570, [int]$Y = 400, [int]$Notches = -3)
# 个人电脑版滚轮滚动（DPI-aware 客户区物理坐标）
# -Notches 负数=向下滚，正数=向上滚（一格=120）
# 窗口查找/尺寸断言由 _wxcommon.ps1 单源提供；pid 0=按标题自动发现
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$h = Find-GameWindow -Pid2 $Pid2
if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
[WXCommon]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 300
$geo = Get-ClientGeometry $h
"client=$($geo.W)x$($geo.H) origin=$($geo.OX),$($geo.OY)"
[WXCommon]::SetCursorPos($geo.OX + $X, $geo.OY + $Y) | Out-Null
Start-Sleep -Milliseconds 250
$delta = $Notches * 120
if ($delta -lt 0) { $udelta = [uint32]($delta + 4294967296) } else { $udelta = [uint32]$delta }
[WXCommon]::mouse_event(0x0800, 0, 0, $udelta, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 400
[WXCommon]::mouse_event(0x0800, 0, 0, $udelta, [UIntPtr]::Zero)
"scrolled at $X,$Y notches=$Notches (sent 2x, actual total $($Notches * 2))"

param([int]$Pid2 = 0)
# 恢复游戏窗口：最小化则还原 + 拉前台（CopyFromScreen 抓到桌面纯色=窗口被最小化/遮挡的特征）
# 窗口查找由 _wxcommon.ps1 单源提供；pid 0=按标题自动发现
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$h = Find-GameWindow -Pid2 $Pid2
if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
$mini = [WXCommon]::IsIconic($h)
"minimized=$mini"
if ($mini) { [WXCommon]::ShowWindow($h, 9) | Out-Null; "restored" }   # 9 = SW_RESTORE
[WXCommon]::SetForegroundWindow($h) | Out-Null
"foreground set"

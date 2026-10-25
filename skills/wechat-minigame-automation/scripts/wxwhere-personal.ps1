param([int]$Pid2 = 0)
# 查询游戏窗口位置与状态（窗口被移动/遮挡时定位用）
# 窗口查找由 _wxcommon.ps1 单源提供（标题优先匹配）；pid 0=按标题自动发现
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$h = Find-GameWindow -Pid2 $Pid2
if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
$r = New-Object WXCommon+RECT
[WXCommon]::GetWindowRect($h, [ref]$r) | Out-Null
$fg = [WXCommon]::GetForegroundWindow()
$wpid = 0; [WXCommon]::GetWindowThreadProcessId($h, [ref]$wpid) | Out-Null
"pid=$wpid"
"window rect L=$($r.L) T=$($r.T) R=$($r.R) B=$($r.B)"
"minimized=$([WXCommon]::IsIconic($h))"
"foreground is game=$($fg -eq $h)"

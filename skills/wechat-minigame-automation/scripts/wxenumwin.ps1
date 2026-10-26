param([int]$Pid2 = 0)
# 枚举目标进程全部可见窗口（标题+客户区几何）——多窗口诊断用（wxshot 选错窗口问题的排查工具）
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

if ($Pid2 -le 0) {
    $proc = Get-Process WeChatAppEx -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -like "*$WX_WINDOW_TITLE*" } | Select-Object -First 1
    if (-not $proc) { "ERR: no WeChatAppEx with title ~ $WX_WINDOW_TITLE"; exit 1 }
    $Pid2 = $proc.Id
}
"target pid=$Pid2 (MainWindowTitle='$((Get-Process -Id $Pid2).MainWindowTitle)')"
[WXCommon]::SetProcessDPIAware() | Out-Null
[WXCommon]::TargetPid = $Pid2
[WXCommon]::Needle = ""
[WXCommon]::Found = [IntPtr]::Zero
[WXCommon]::Fallback = [IntPtr]::Zero
$list = New-Object System.Collections.ArrayList
$cb = [WXCommon+EnumProc]{ param($h,$l)
    if ([WXCommon]::IsWindowVisible($h)) {
        $wpid = 0; [WXCommon]::GetWindowThreadProcessId($h, [ref]$wpid) | Out-Null
        if ($wpid -eq [WXCommon]::TargetPid) {
            $sb = New-Object System.Text.StringBuilder 256
            [WXCommon]::GetWindowTextW($h, $sb, 256) | Out-Null
            $cr = New-Object WXCommon+RECT; [WXCommon]::GetClientRect($h, [ref]$cr) | Out-Null
            $pt = New-Object WXCommon+POINT; $pt.X = 0; $pt.Y = 0; [WXCommon]::ClientToScreen($h, [ref]$pt) | Out-Null
            [void]$list.Add([pscustomobject]@{ H = $h; Title = $sb.ToString(); Client = "$($cr.R)x$($cr.B)"; Origin = "$($pt.X),$($pt.Y)" })
        }
    }
    return $true
}
[WXCommon]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$list | ForEach-Object { "hwnd=$($_.H) client=$($_.Client) origin=$($_.Origin) title='$($_.Title)'" }
"total=$($list.Count)"

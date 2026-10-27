# wxautoensure.ps1 v2.1 - 自动战斗快速确保（2026-10-28 晨，性能重构版）
# 用户需求原话：1.进图要等4、5秒才开，太慢了！2.有可能因为窗口大小变动或其他原因开不起来！必须稳定开起来才行！
#   OCR必须用；模板匹配做不做辅助看冒烟实测结果（v2 未引入模板，冒烟见 冒烟测试\smoke-autoensure10-*）
# v2.1 性能重构（v2 首测 6.5s 瓶颈=每次 OCR/点击都新开 powershell 子进程 ~1.5s）：
#   OCR 改**进程内调用** wxocr.ps1（& 调用，exit 语义已实测安全 2026-10-28：不终止调用方）；
#   点击改**进程内** mouse_event+ConvertTo-ScreenPoint（与 wxnav-tower 同款），每次点击前重读几何。
# 判定不变：wxocr -Task autobtn（区域 (175,158)-(275,195) F=12，取消自动=ON / 自动战斗=OFF，N=3 容错）
#   OFF → 点按钮锚点 (215,172)（两态同位，1178×744 素材图红框目验定版）→ 重读验证；ON → 成功。
#   UNKNOWN/读空（转场黑屏）→ 继续轮询。超时 TimeoutSec → FAIL exit 3；点击超 3 次 → FAIL exit 4。
# 安全（事件11 教训）：每次点击前必须有 fresh OCR=OFF；ON 优先判定，杜绝把已开的点关。
param([int]$Pid2 = 0, [int]$TimeoutSec = 12, [int]$StartDelayMs = 300, [int]$PollMs = 150, [int]$ClickWaitMs = 500)
$scripts = $PSScriptRoot
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$hwnd = Find-GameWindow -Pid2 $Pid2
if ($hwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
if (-not (Confirm-WxForeground $hwnd)) { "ERR: game not foreground (拉回重试后仍不在前台)"; exit 7 }
$geo = Get-ClientGeometry $hwnd
if (-not (Test-WxMinClientW $geo.W)) { "ERR: window too small ($($geo.W)x$($geo.H))"; exit 7 }
"client=$($geo.W)x$($geo.H) scale=$([math]::Round($geo.S,4))"

function Invoke-InlineClick([int]$x, [int]$y) {
    $g = Get-ClientGeometry $hwnd
    $p = ConvertTo-ScreenPoint $g $x $y
    [WXCommon]::SetCursorPos($p.X, $p.Y) | Out-Null
    Start-Sleep -Milliseconds 80
    [WXCommon]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [WXCommon]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Milliseconds $StartDelayMs
$clicks = 0
$lastCls = ""
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    $out = & (Join-Path $scripts 'wxocr.ps1') -Task autobtn -Pid2 $Pid2 2>&1
    $joined = ($out | ForEach-Object { "$_" }) -join ' '
    $cls = "UNKNOWN"
    if ($joined -match 'OCR=autobtn=(\w+)') { $cls = $Matches[1] }
    $raw = ""
    if ($joined -match 'raw=\[(.*?)\]') { $raw = $Matches[1] }
    if ($cls -ne $lastCls) { Write-Host ("t={0,5:F1}s autobtn={1} raw=[{2}]" -f $sw.Elapsed.TotalSeconds, $cls, $raw); $lastCls = $cls }
    if ($cls -eq "ON") {
        ("AUTO_ENSURED elapsed={0:F1}s clicks={1}" -f $sw.Elapsed.TotalSeconds, $clicks)
        exit 0
    }
    if ($cls -eq "OFF") {
        if ($clicks -ge 3) { "AUTO_ENSURE_FAIL reason=clicks>=3 still OFF"; exit 4 }
        $clicks++
        Write-Host ("t={0,5:F1}s click auto-btn #{1} at 215,172" -f $sw.Elapsed.TotalSeconds, $clicks)
        Invoke-InlineClick 215 172
        Start-Sleep -Milliseconds $ClickWaitMs
        continue
    }
    Start-Sleep -Milliseconds $PollMs
}
"AUTO_ENSURE_FAIL reason=timeout ($TimeoutSec s) last=$lastCls"
exit 3

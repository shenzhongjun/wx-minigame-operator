param([string]$Steps = "", [int]$J = 4, [int]$Pid2 = 0)
# 个人电脑版点击器（DPI-aware 客户区物理坐标体系，与公司电脑版 wxclick.ps1 并存）
# Steps: "x:y:delayAfterMs;x:y:delayAfterMs;w:waitMs;auto"
#   x:y:d  点击客户区物理坐标 (x,y)，delayAfterMs 为点击后等待
#   w:ms   纯等待
#   auto   内联确保自动战斗开启（模板匹配判定，见下）
# 坐标 = 游戏窗口客户区物理像素（1:1 无补偿）；窗口查找/尺寸断言/模板匹配由 _wxcommon.ps1 单源提供
# pid：-Pid2 传 0 或不传 = 按窗口标题「勇士之心」自动发现
#
# auto 步骤机制（2026-10-25 铁律修订，事故教训见 incidents 事件10/11/19）：
#   判定源=左上角按钮文字模板匹配：「自动战斗」(关,▶图标) /「取消自动」(开,⏸图标)
#   · 与血量/按钮底色/中央白字 tip 零关系（tip 判定代码已彻底删除）
#   · 同进程点击上限 2 次；每次点击需 gated 证据：模板明确 OFF + 连续 5 轮(~1.5s)读数一致
#   · AUTO_ENSURE_FAIL 后接续协议见 SKILL.md 执行规则2：立即截图人工核对按钮 →
#     视觉确认 OFF 则新进程重试（最多2轮）；结算屏点击会延迟生效且像素不变，至多点一次
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$h = Find-GameWindow -Pid2 $Pid2
if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
[WXCommon]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 350
# 前台守卫（2026-10-24 事故）：mouse_event 是全局点击，前台≠游戏时拒绝，防点进用户窗口
if ([WXCommon]::GetForegroundWindow() -ne $h) {
    [WXCommon]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 600
    if ([WXCommon]::GetForegroundWindow() -ne $h) { "ERR: game not foreground (被其它窗口抢占)，拒绝点击"; "DONE"; exit 7 }
}
$geo = Get-ClientGeometry $h
$OX = $geo.OX; $OY = $geo.OY
"client=$($geo.W)x$($geo.H) origin=$OX,$OY"

# ---- 内联确保自动战斗开启（唯一判据=按钮文字模板 / gated点击上限2 / 35s 窗口 / 全程日志）----
function Ensure-Auto {
    $tpl = Import-WxBtnTemplates
    $aw = $WX_BTN_X1 - $WX_BTN_X0 + 1; $ah = $WX_BTN_Y1 - $WX_BTN_Y0 + 1
    $liveBmp = New-Object System.Drawing.Bitmap $aw, $ah
    $liveG = [System.Drawing.Graphics]::FromImage($liveBmp)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $clicks = 0
    $lastLog = -1.0
    $offStreak = 0
    try {
        while ($sw.Elapsed.TotalSeconds -lt 35) {
            $liveG.CopyFromScreen(($OX + $WX_BTN_X0), ($OY + $WX_BTN_Y0), 0, 0, $liveBmp.Size)
            $live = Get-WxBmpMask $liveBmp 0 0
            $dOn = [math]::Round((Get-WxJaccard $live $tpl.On), 3)
            $dOff = [math]::Round((Get-WxJaccard $live $tpl.Off), 3)
            $t = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            if ($t - $lastLog -ge 1.0) { "scan t=${t}s dist_on=$dOn dist_off=$dOff clicks=$clicks streak=$offStreak"; $lastLog = $t }
            $onMatch = ($dOn -le 0.60 -and ($dOff - $dOn) -ge 0.10)
            # 开启证据：仅按钮文字模板 ON（铁律第2条：唯一判据；模板失灵→FAIL 人工核对，绝不推断）
            if ($onMatch) {
                "AUTO_ENSURED(ms=$([int]$sw.ElapsedMilliseconds) clicks=$clicks evidence=template)"
                return
            }
            # 点击闸门：模板明确 OFF，连续 5 轮(~1.5s)一致
            $offCand = ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10)
            if ($offCand) { $offStreak++ } else { $offStreak = 0 }
            if ($offStreak -ge 5) {
                if ($clicks -lt 2) {
                    $clicks++
                    $offStreak = 0
                    $ax = $OX + $WX_BTN_CLICK_X + (Get-Random -Minimum -4 -Maximum 5)
                    $ay = $OY + $WX_BTN_CLICK_Y + (Get-Random -Minimum -3 -Maximum 4)
                    [WXCommon]::SetCursorPos($ax, $ay) | Out-Null
                    Start-Sleep -Milliseconds 120
                    [WXCommon]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
                    Start-Sleep -Milliseconds 60
                    [WXCommon]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
                    "click auto-button t=${t}s (click $clicks of 2, gated)"
                    Start-Sleep -Milliseconds 3000
                } else {
                    # 两次 gated 点击后仍明确 OFF = 点击被游戏吞掉 → 停机，走截图接续协议
                    "AUTO_ENSURE_FAIL(ms=$([int]$sw.ElapsedMilliseconds) clicks=$clicks reason=two_gated_clicks_failed)"
                    "DONE"; exit 3
                }
            } else {
                Start-Sleep -Milliseconds 300   # UNKNOWN / 未达确认轮数：继续观察
            }
        }
    } finally {
        $liveG.Dispose(); $liveBmp.Dispose()
    }
    "AUTO_ENSURE_FAIL(ms=$([int]$sw.ElapsedMilliseconds) clicks=$clicks reason=timeout)"
    "DONE"; exit 3
}

foreach ($step in $Steps.Split(";")) {
  if ($step.Trim() -eq "") { continue }
  if ($step.StartsWith("w:")) { Start-Sleep -Milliseconds ([int]$step.Substring(2)); continue }
  if ($step.Trim() -eq "auto") { Ensure-Auto; continue }
  if ($step.Trim() -eq "autonow") { Ensure-Auto; continue }   # 已合并：判定可靠后无需区分快慢模式
  $parts = $step.Split(":")
  $x = [int]$parts[0]; $y = [int]$parts[1]
  $d = 250
  if ($parts.Length -gt 2) { $d = [int]$parts[2] }
  $ax = $OX + $x + (Get-Random -Minimum (-$J) -Maximum ($J + 1))
  $ay = $OY + $y + (Get-Random -Minimum (-$J) -Maximum ($J + 1))
  Start-Sleep -Milliseconds (Get-Random -Minimum 180 -Maximum 320)
  [WXCommon]::SetCursorPos($ax, $ay) | Out-Null
  Start-Sleep -Milliseconds (Get-Random -Minimum 80 -Maximum 150)
  [WXCommon]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 100)
  [WXCommon]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  "click=$x,$y -> $ax,$ay"
  if ($d -gt 0) { Start-Sleep -Milliseconds $d }
}
"DONE"

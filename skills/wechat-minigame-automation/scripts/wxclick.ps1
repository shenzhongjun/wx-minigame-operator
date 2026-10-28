param([string]$Steps = "", [int]$Pid2 = 0)
# 点击器（DPI-aware 客户区物理坐标体系）
# Steps: "x:y:delayAfterMs;x:y:delayAfterMs;w:waitMs;auto"
#   x:y:d  点击设计坐标 (x,y)（基准 1138x708），delayAfterMs 为点击后等待
#   w:ms   纯等待
#   auto   确保自动战斗开启（v1.1.12 起=委托 wxautoensure.ps1 OCR 单判据；autonow 同义已合并）
# 坐标 = 设计坐标（基准 1138x708）；运行时由 _wxcommon 换算到实时客户区，支持等比缩放/副本间微变
# pid：-Pid2 传 0 或不传 = 按窗口标题「勇士之心」自动发现
#
# auto 步骤机制（v1.1.12 修订）：委托 wxautoensure.ps1——OCR 读 autobtn 区 (175,158)-(275,195)，
#   「取消自动」=ON 优先判定不误关 /「自动战斗」=OFF 点 (215,172)→重读验证 / UNKNOWN 轮询；
#   超时(默认12s)/点击超3次 FAIL → 本脚本整体 exit 3（与旧模板路径语义一致）。
#   FAIL 接续协议见 SKILL.md 执行规则2：立即截图人工核对按钮 → 视觉确认 OFF 则新进程重试
#   （最多2轮）；结算屏点击会延迟生效且像素不变，至多点一次。
#   旧模板 gated 循环已退役（布局常量/锚点被 v1.1.10/11 甩下）；模板资产/wxautostate/wxprobe AUTO 态仅存诊断用途。
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$h = Find-GameWindow -Pid2 $Pid2
if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
[WXCommon]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 350
# 前台守卫（2026-10-24 事故；2026-10-27 16:5x 用户定版）：不在前台→log 留痕+拉回，重试 2 次仍失败才 STOP
if (-not (Confirm-WxForeground $h)) { "ERR: game not foreground (拉回重试后仍不在前台)，拒绝点击"; "DONE"; exit 7 }
$geo = Get-ClientGeometry $h
if (-not (Test-WxMinClientW $geo.W)) { "ERR: window too small ($($geo.W)x$($geo.H) < ${WX_MIN_CLIENT_W} width)，拒绝点击"; "DONE"; exit 7 }
"client=$($geo.W)x$($geo.H) origin=$($geo.OX),$($geo.OY) scale=$([math]::Round($geo.S,4))"

# ---- 自动战斗确保（v1.1.12：唯一入口=wxautoensure，OCR 单判据；本脚本 auto/autonow 步骤=委托）----
# 旧模板 gated 循环已退役：其布局常量 (195,175)-(253,187)/锚点 (224,181) 已被 v1.1.10/11 两次
# 布局变更甩下（现行：文字带 y164-184、锚点 (215,172)），模板资产/wxautostate/wxprobe AUTO 态仅存诊断用途。
# FAIL 时整体退出码 3（与旧语义一致），输出含 AUTO_ENSURED/AUTO_ENSURE_FAIL 字样兼容 wxgrind 检测。

foreach ($step in $Steps.Split(";")) {
  if ($step.Trim() -eq "") { continue }
  if ($step.StartsWith("w:")) { Start-Sleep -Milliseconds ([int]$step.Substring(2)); continue }
  if ($step.Trim() -eq "auto" -or $step.Trim() -eq "autonow") {
      $ens = & (Join-Path $PSScriptRoot 'wxautoensure.ps1') -Pid2 $Pid2 2>&1
      $ens | ForEach-Object { "$_" }
      if (($ens -join "`n") -notmatch 'AUTO_ENSURED') { "AUTO_ENSURE_FAIL(delegated to wxautoensure)"; "DONE"; exit 3 }
      continue
  }
  $parts = $step.Split(":")
  $x = [int]$parts[0]; $y = [int]$parts[1]
  $d = 250
  if ($parts.Length -gt 2) { $d = [int]$parts[2] }
  # 每步点击前重读几何：窗口在多次点击间可能被移动/改尺寸
  $g = Get-ClientGeometry $h
  $p = ConvertTo-ScreenPoint $g $x $y
  $ax = $p.X; $ay = $p.Y
  Start-Sleep -Milliseconds 250
  [WXCommon]::SetCursorPos($ax, $ay) | Out-Null
  Start-Sleep -Milliseconds 100
  [WXCommon]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 70
  [WXCommon]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  "click=$x,$y -> $ax,$ay"
  if ($d -gt 0) { Start-Sleep -Milliseconds $d }
}
"DONE"

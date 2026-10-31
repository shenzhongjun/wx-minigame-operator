param([string]$Steps = "", [int]$Pid2 = 0)
# wxclick.ps1 — 点击器（薄壳，2026-10-31 主体迁入 _wxcore.ps1 的 Invoke-WxClick）
# Steps: "x:y:delayAfterMs;x:y:delayAfterMs;w:waitMs;auto"（语法与语义零改动）
#   x:y:d  点击设计坐标 (x,y)（基准 1138x708），delayAfterMs 为点击后等待
#   w:ms   纯等待
#   auto   确保自动战斗开启（委托 wxautoensure.ps1，OCR 单判据；失败 exit 3）
# 坐标 = 设计坐标，运行时由 _wxcommon 换算到实时客户区（支持等比缩放/副本间微变）。
# 每步点击前重读窗口几何；前台/最小窗守卫拒绝时 exit 7。
# 迁入收益（2026-10-31）：链路内同进程调用省掉每次约 1.3s 的进程启动，重登链全程 6 次点击。
. (Join-Path $PSScriptRoot '_wxcommon.ps1')
. (Join-Path $PSScriptRoot '_wxcore.ps1')

$r = Invoke-WxClick -Steps $Steps -Pid2 $Pid2
if ($r.Err) { "ERR: $($r.Err)" }
if ($r.Log) { $r.Log | ForEach-Object { "$_" } }
exit $r.ExitCode

param([int]$Pid2 = 0)
# 固化商城每日领取链（2026-10-24 新增，语法0错误未实战；坐标 2026-10-23 角色1 实测有效）
# 前提：当前在主城。链路：商城 → 礼包 → 体力·免费 → 空白关弹窗 → 羽毛·免费 → 空白关弹窗 → 返回
# 注意：不校验是否已领（重复领取会被「已售罄/角色日限」挡住，无害）；结束自动截图供人工核对
$scripts = $PSScriptRoot
# 注意：本链**禁盲跑**（事件16：礼包页布局随领取状态变化，见 references/features/daily-claim.md）
& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxclick.ps1" -Pid2 $Pid2 -Steps "876:103:2500;89:281:2000;484:375:2000;200:500:1500;324:375:2000;200:500:1500;39:86:2000"
# 验证截图：窗口锚定模式（-OX<0 自动取客户区，窗口挪动不会截错区域；旧版硬编码 OX/OY 已废弃）
& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxshot.ps1" -Out "$env:TEMP\wx-verify\claim_last.png" -OX -1 -Pid2 $Pid2
"claim chain done, screenshot=claim_last.png（体力应+10、羽毛应已售罄）"

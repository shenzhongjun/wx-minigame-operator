param([int]$Pid2 = 0, [switch]$Debug, [string]$Img = "", [switch]$Quick)
# wxprobe.ps1 — 状态探针（薄壳，2026-10-31 模块化试点）
# 主体已迁入 _wxcore.ps1 的 Invoke-WxProbe（区域/阈值/判定顺序零改动），本文件只做三件事：
#   解析参数 → 调函数 → 按原格式打印文本与返回退出码。
# 契约见 管理新规.md §七（薄壳原则）。识别与调试细节见 Invoke-WxProbe 头注。
# 输出（与迁移前完全一致）：client=...（仅实时模式）/ STATE=<枚举> / PAGE=<枚举> / -Debug 追加像素计数
# 退出码：0=正常探测；1=窗口未找到；4=-Img 输入不合规；7=前台/最小窗守卫拒绝
. (Join-Path $PSScriptRoot '_wxcommon.ps1')
. (Join-Path $PSScriptRoot '_wxcore.ps1')

$r = Invoke-WxProbe -Pid2 $Pid2 -Debug:$Debug -Img $Img -Quick:$Quick

if ($r.Err) { "ERR: $($r.Err)"; exit $r.ExitCode }
if ($r.Client) { $r.Client }
"STATE=$($r.State)"
if ($r.Note) { "debug: $($r.Note)" }
if ($r.State -eq "OCCLUDED") { exit 0 }

if ($Quick) {
    if ($Debug) { "debug: gold=$($r.Gold) stamina=$($r.Stam) settle=$($r.Settle)" }
    exit 0
}

"PAGE=$($r.Page)"
if ($Debug) {
    "debug: gold=$($r.Gold) stamina=$($r.Stam) settle=$($r.Settle) side=$($r.Side) dist_on=$($r.DistOn) dist_off=$($r.DistOff) hp=$($r.Hp) power=$($r.Power) welfare=$($r.Welfare) shop=$($r.Shop) townvotes=$($r.TownVotes)"
}
exit 0

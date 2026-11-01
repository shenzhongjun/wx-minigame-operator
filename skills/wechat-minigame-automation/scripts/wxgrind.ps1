param([int]$Rounds = 1, [int]$Pid2 = 0, [int]$RetryX = 936, [int]$RetryY = 269, [int]$SettleWaitSec = 90, [int]$EnterWaitSec = 25, [int]$RetryAttempts = 1, [switch]$AutoRetry, [bool]$Revive = $true, [int]$ReviveMax = 2)
# 固化刷本循环（2026-10-24 新增，替代 wxfarm 的通用扫描方案，语法0错误未实战）
# 思路：不再扫描按钮位置——结算「再来一次」用固定坐标（圣殿两行布局实测 (936,269)），
#       每步用 wxprobe 验证状态，异常即停。依赖 wxprobe/wxclick 同目录。
# 流程/轮：等结算 → 点再来一次 → 验证离场 → (AUTO_OFF 时 gated 开自动) → 等下一结算
# 退出码（管理新规 §七 三档契约，2026-11-01 校正）：
#   0=本轮目标达成且已自证 | 2=未达成但画面干净可原地重试（结算超时 / 点击未进图）
#   其它一律 STOP 禁止重试，细分码仅供诊断：3=自动战斗确保失败 5=体力弹窗 6=金弹窗未消(死亡/顶号/未知)
#   7=被踢回登录页(交操作员重登) 9=探针故障
#   ⚠ 2026-11-01 修正：原「两次点击未进图」错报 exit 0（老口径 0=完成/重试失败），
#     会导致编排层把失败当成功继续跑下一轮，已改 exit 2。
# 复活（2026-11-01 第二层，用户定版）：-Revive **默认开**，-ReviveMax 默认 2。段1 遇 POPUP_REVIVE 自动点
#   「立即复活」→ 重开自动战斗 → 继续等；次数用尽则该轮按红线 exit 6 交人工。`-Revive $false` 完全关闭。
#   理由：复活消耗羽毛（每天免费领 1 个），属不可逆动作，故必须封顶 + 可关。
$scripts = $PSScriptRoot
# 模块化 P3（2026-11-01）：引入策略层，金弹窗处置单源。
#   原 wxgrind.Invoke-PopupGuard 与 wxrelogin 阶段1/阶段4 三处各写一份，现收敛为 _wxflow.Invoke-WxGoldGuard。
#   _wxcommon 的 Add-Type 有 'WXCommon' -as [type] 保护，重复 dot-source 安全，故 -AutoRetry 分支不再单独加载。
#   代价：一次性加载约 0.5-1s（Add-Type 编译）；收益：Guard 内 OCR 引擎进程内复用（单次 3s → 0.25s）。
. (Join-Path $PSScriptRoot '_wxcommon.ps1')
. (Join-Path $PSScriptRoot '_wxcore.ps1')
. (Join-Path $PSScriptRoot '_wxflow.ps1')
# -RetryAttempts（2026-11-01 新增，默认 1）：段2「点再来一次」的内部重试次数。默认只点 1 次，
#   失败 exit 2 交编排层按 §七 重试（重试权归编排层，避免内部×外部次数相乘误触）。
# -AutoRetry（2026-10-25 新增）：每轮点击前自动扫描结算暗红按钮位置（复用 wxfarm 扫描带算法），
#   替代人工按副本/布局传 RetryX/Y；扫描失败回退固定坐标。扫描带 BX=915±38, y225-445（设计坐标）。
if ($AutoRetry) {
    # 预检：提前暴露窗口丢失/尺寸异常（扫描逻辑本身已固化进 _wxcore，不再需要本地状态）
    $script:grindHwnd = Find-GameWindow -Pid2 $Pid2
    if ($script:grindHwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $null = Get-ClientGeometry $script:grindHwnd
}
# ---- 结算按钮扫描（2026-11-01 P4 固化入 _wxcore）----
# 原 Find-RetryY / Resolve-RetryCoords（本文件私有，依赖 $script:grindHwnd）已删除。
# 现用 _wxcore.Find-WxRetryY（纯算法）/ Resolve-WxRetryCoords（取图+回退，支持 -Img 离线验图）。
# 判据、扫描带（BX=915±25 / y225-444 / 连续段>=10px）、回退逻辑全部逐字照搬，零漂移。
# 原 Invoke-Probe（子进程调 wxprobe.ps1 的字符串版）于 P5b 删除——改薄后已无调用者。
# 探针统一走 _wxcore.Invoke-WxProbe（同进程）与 Invoke-WxProbeHeal（带自愈）。
# ⚠ P5a 实测结论（重要，别按旧估计做规划）：
#   单次 wxprobe 子进程实际约 **1.2s**（早先估的 0.3-0.5s 明显偏低）——因为每次都要
#   dot-source _wxcommon（含 Add-Type 编译）+ 抓图 + 全区扫描。
#   ⇒ 段1 名义上「1s 轮询」，实际每轮约 2.2s；切同进程后降到约 1.2s，等结算页近乎提速一倍。
#   ⇒ 冒烟（两次探针）从 5.2s 降到 2.7s。
function Invoke-ProbeHeal {
    param([switch]$Quick)
    # 2026-11-01 P5b：自愈逻辑已固化到 _wxcore.Invoke-WxProbeHeal（返回对象，D1 口径：不 wxresize）。
    #   这里只做「对象 → 状态字符串」适配，供段2/段3/final 等仍按字符串比较的调用点使用。
    #   保持字符串接口是为了不动那些调用点，减少一次改动的波及面。
    $r = Invoke-WxProbeHeal -Pid2 $Pid2 -Quick:$Quick
    if ($r.Err) { return "ERR" }
    return $r.State
}
# ---- 轮盘保活 poke（2026-11-01 用户定版：**已废止**）----
# 原 Invoke-Poke / Invoke-PokeIfDue（115s 节流，后改 240s）全部删除。废止依据（用户原话归纳）：
#   ① poke 无法重置游戏挂机计时——2026-10-26 实测 115s 间隔下挂机弹窗照样复现；
#   ② 自动战斗期间 poke 点了没有反应；
#   ③ 非战斗场景（领体力等界面）本来也不需要戳。
#   ⇒ 净效果只有每 2 分钟一次的 1.5-1.8s 子进程开销 + 抢前台，无任何收益。
# 挂机弹窗改由段1/段3 的单源守卫 Invoke-WxGoldGuard 正常处置（分类 POPUP_IDLE → 点确定 → 复验）。
# wxpoke.ps1 脚本本身保留为人工工具，链路不再调用。
function Invoke-Click([string]$steps) {
    & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxclick.ps1" -Pid2 $Pid2 -Steps $steps 2>&1 | ForEach-Object { "$_" }
}
# 自动战斗确保（v1.1.12 起唯一入口=wxautoensure）。段3 入场与段1 复活后共用一处。
# 返回 $true=已确保 ON。
function Invoke-EnsureAuto {
    $out = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxautoensure.ps1" -Pid2 $Pid2 -TimeoutSec 30 2>&1
    $out | ForEach-Object { "$_" }
    return (($out -join "`n") -match 'AUTO_ENSURED')
}
# ---- 金弹窗处置（2026-11-01 P3 单源化）----
# 原 Invoke-PopupGuard（本文件私有，70 行）已删除，改用 _wxflow.Invoke-WxGoldGuard。
# 迁移对照（行为零改动）：
#   POPUP_NONE（probe 假金，事件20）        → Verdict="NONE"  继续等
#   POPUP_IDLE（挂机弹窗）                  → 点 (700,513) → 等 2s → server OCR 复验 → "OK" / "LOGIN"
#   顶号/扩展券/未知                        → Verdict="STOP"  红线停机
# 差异（均为纯收益）：① 同进程调用省 1.3s/次进程启动；② OCR 引擎复用 3s→0.25s；
#   ③ 去掉一次 Invoke-ProbeHeal 无用调用（原代码取了 $after 却从未使用）。
for ($i = 1; $i -le $Rounds; $i++) {
    "=== round $i/$Rounds ==="
    # 1) 等结算页（2026-11-01 P5b：内联 while → _wxflow.Wait-WxState 状态机）
    #    原手工 while + goldStreak/unkStreak 两个计数器 + 四处 exit 已下沉；
    #    GOLD 三连确认、UNKNOWN 十连全探、体力弹窗、超时的判据与计数行为逐行照搬，零漂移。
    $w = $null
    # 复活重入（2026-11-01 第二层，用户定版）：状态机遇 `POPUP_REVIVE` 且授权时会点「立即复活」并返回 REVIVED。
    #   复活后画面回到战斗，但**自动战斗是关着的**——不重开就是接着站桩连环死，把羽毛烧光。故此时必须
    #   ensure auto 后重新等待。封顶 `-ReviveMax`（默认 2）：用完则不再授权，该轮遇复活弹窗直接红线 STOP。
    #   ⚠ 复活是消耗资源（羽毛，每天免费领 1 个）的不可逆动作，默认开着，`-Revive $false` 可关。
    $reviveLeft = 0
    if ($Revive) { $reviveLeft = $ReviveMax }
    while ($true) {
        $w = Wait-WxState -Pid2 $Pid2 -Target "SETTLE_PAGE" -TimeoutSec $SettleWaitSec -GoldGuard -VerifyLogin -AllowRevive:($reviveLeft -gt 0)
        if ($w.Result -ne "REVIVED") { break }
        $reviveLeft--
        "round ${i}: REVIVED (left=$reviveLeft) -> re-ensure auto"
        if (-not (Invoke-EnsureAuto)) { "STOP: auto ensure failed after revive"; exit 3 }
    }
    switch ($w.Result) {
        "OK"      { }
        "TIMEOUT" { "STOP: settle wait timeout ($SettleWaitSec s), last=$($w.State)"; exit 2 }
        "ERR"     { "STOP: probe error (wxprobe failed - 窗口丢失或尺寸不符，见 wxprobe 输出)"; exit 9 }
        "LOGIN"   { "STOP: kicked to login page (exit 7)"; exit 7 }
        "GOLD"    { "STOP: persistent gold dialog (death/idle/login), $($w.Detail)"; exit 6 }
        "STAMINA" { "STOP: stamina popup"; exit 5 }
        default   { "STOP: unexpected wait result=$($w.Result)"; exit 9 }
    }
    $st = $w.State
    # 2) 点再来一次
    #    D2/D3（2026-11-01 用户定版）：点击后只等 800ms 让点击生效，就绪判定全交给紧随其后的
    #      EnterWaitSec 轮询；若要多试一次，第二次也**不重复硬等**——第一次失败说明点击没生效，不是等得不够。
    #    D4（选 A）：重试权归编排层。内部默认只点 1 次，失败 exit 2 交外部按 §七 最多重试 3 次，
    #      避免「内部 2 次 × 外部 3 次 = 连续 6 次点击」误触。需要内部多试请显式 -RetryAttempts N。
    $entered = $false
    #    注意：用 for 而非 foreach (1..$RetryAttempts)——PS 的 1..0 会展开成 (1,0) 两元素，
    #    传 0 反而点两次。for 在 <=0 时天然不循环，直接落到 exit 2。
    for ($attempt = 1; $attempt -le $RetryAttempts; $attempt++) {
        $rc = Resolve-WxRetryCoords -Pid2 $Pid2 -EnableScan:$AutoRetry -FallbackX $RetryX -FallbackY $RetryY
        if ($rc.Err) { Write-Host "retry scan: $($rc.Err)" }
        if (-not $rc.Auto -and $AutoRetry) { Write-Host "retry autoscan failed, fallback fixed ($($rc.X),$($rc.Y))" }
        "round ${i}: click retry (attempt $attempt/$RetryAttempts, target=$($rc.X),$($rc.Y)$(if ($rc.Auto) { ' (auto)' } else { '' }))"
        Invoke-Click "$($rc.X):$($rc.Y):800" | Out-Null
        $t = 0; $st = Invoke-ProbeHeal
        while ($st -eq "SETTLE_PAGE" -and $t -lt $EnterWaitSec) {
            Start-Sleep -Seconds 1; $t += 1; $st = Invoke-ProbeHeal
        }
        if ($st -ne "SETTLE_PAGE") { $entered = $true; break }
        "round ${i}: still settle after attempt $attempt (waited ${EnterWaitSec}s)"
    }
    if (-not $entered) { "STOP: retry click not entered ($RetryAttempts attempt(s), round $i) -> exit 2 (交编排层重试)"; exit 2 }
    # 3) 入场确认 + 自动战斗
    "round ${i}: entered, state=$st"
    if ($st -eq "ERR") { "STOP: probe error after enter"; exit 9 }
    if ($st -eq "GOLD_DIALOG") {
        # 入场即 GOLD：多为挂机弹窗压屏（wxpoke 无法重置挂机计时，2026-10-26 实锤）。
        # 2026-11-01 P3：与段1 共用单源守卫，逻辑完全一致（原先此处重复写了一遍三连+分流）。
        $g = Invoke-WxGoldGuard -Pid2 $Pid2 -VerifyLogin
        if ($g.Verdict -eq "LOGIN") { "STOP: kicked to login page (exit 7)"; exit 7 }
        if ($g.Verdict -ne "OK" -and $g.Verdict -ne "NONE") { "STOP: gold dialog after enter, cls=$($g.Cls)"; exit 6 }
        $st = Invoke-ProbeHeal
        "round ${i}: after guard state=$st"
        if ($st -eq "ERR") { "STOP: probe error after enter"; exit 9 }
    }
    if ($st -eq "STAMINA_POP") { "STOP: stamina popup after enter"; exit 5 }
    # 3.5) 自动战斗确保（v1.1.12 起唯一入口=wxautoensure，OCR 单判据；旧模板 gated 路径退役——
    #      其布局常量/锚点已被 v1.1.10/11 两次变更甩下，wxprobe AUTO 态仅存诊断用途）。
    #      无条件每场必调：ON 优先判定（已开 ~1s 返回 0 点击），不再依赖 probe AUTO_OFF 触发。
    #      2026-11-01：抽成 Invoke-EnsureAuto，与段1 复活后重开共用一处，避免两份逻辑漂移。
    "round ${i}: ensure auto (wxautoensure)"
    if (-not (Invoke-EnsureAuto)) { "STOP: auto ensure failed"; exit 3 }
    # 4) 等战斗结束（下一轮的等结算负责等待）
}
"LOOP: $Rounds rounds completed"
$st = Invoke-ProbeHeal
"final state=$st"

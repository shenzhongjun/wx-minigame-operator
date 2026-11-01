param([int]$Rounds = 1, [int]$Pid2 = 0, [int]$RetryX = 936, [int]$RetryY = 269, [int]$SettleWaitSec = 90, [int]$EnterWaitSec = 25, [int]$RetryAttempts = 1, [switch]$AutoRetry)
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
$scripts = $PSScriptRoot
# -RetryAttempts（2026-11-01 新增，默认 1）：段2「点再来一次」的内部重试次数。默认只点 1 次，
#   失败 exit 2 交编排层按 §七 重试（重试权归编排层，避免内部×外部次数相乘误触）。
# -AutoRetry（2026-10-25 新增）：每轮点击前自动扫描结算暗红按钮位置（复用 wxfarm 扫描带算法），
#   替代人工按副本/布局传 RetryX/Y；扫描失败回退固定坐标。扫描带 BX=915±38, y225-445（设计坐标）。
$script:AutoRetryReady = $false
if ($AutoRetry) {
    . (Join-Path $PSScriptRoot '_wxcommon.ps1')
    $script:grindHwnd = Find-GameWindow -Pid2 $Pid2
    if ($script:grindHwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $null = Get-ClientGeometry $script:grindHwnd   # 提前暴露尺寸/比例异常
    $script:AutoRetryReady = $true
}
function Find-RetryY {
    if (-not $script:AutoRetryReady) { return -1 }
    $bx = 915; $y0 = 225; $scanH = 220
    # 归一化整图后扫描：设计坐标常量零改动，客户区微变由 Get-DesignBitmap 吸收
    $g = Get-ClientGeometry $script:grindHwnd
    $bmp = Get-DesignBitmap $g
    $hits = New-Object bool[] $scanH
    for ($i = 0; $i -lt $scanH; $i++) {
        $n = 0
        foreach ($dx in @(-25, 0, 25)) {
            $c = $bmp.GetPixel($bx + $dx, $y0 + $i)
            if ($c.R -gt 100 -and ($c.R - $c.B) -gt 50 -and $c.G -gt 22 -and $c.G -lt 78) { $n++ }
        }
        $hits[$i] = ($n -ge 2)
    }
    $bmp.Dispose()
    $i = 0
    while ($i -lt $scanH) {
        if (-not $hits[$i]) { $i++; continue }
        $s = $i; $e = $i; $gap = 0
        $j = $i + 1
        while ($j -lt $scanH) {
            if ($hits[$j]) { $e = $j; $gap = 0 }
            else { $gap++; if ($gap -gt 6) { break } }
            $j++
        }
        if (($e - $s + 1) -ge 10) { return ($y0 + $s + 20) }
        $i = $e + 1
    }
    return -1
}
function Resolve-RetryCoords {
    if ($script:AutoRetryReady) {
        $fy = Find-RetryY
        if ($fy -ge 0) { return "915,$fy(auto)" }
        Write-Host "retry autoscan failed, fallback fixed ($RetryX,$RetryY)"
    }
    return "$RetryX,$RetryY"
}
function Invoke-Probe {
    param([switch]$Quick)
    # 2026-10-26 修复：原 @q 字符串展开把 "-Quick"/"" 绑定到 wxprobe 首位置参数 [int]$Pid2 → 绑定错误秒退 → ERR 停机；
    # -Quick:$Quick 经 -File 传参 bool 字符串化也炸。数组 splat 中 "-Quick" 会被当参数名，是唯一可靠传法。
    $xargs = @(); if ($Quick) { $xargs += "-Quick" }
    $out = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxprobe.ps1" -Pid2 $Pid2 @xargs 2>&1
    $state = "ERR"
    foreach ($line in $out) { if ($line -match '^STATE=(\w+)') { $state = $Matches[1] } }
    return $state
}
function Invoke-ProbeHeal {
    param([switch]$Quick)
    # 2026-11-01 定版（用户口径，D1 批准）：**不再自动 wxresize**。
    #   理由：几何层 Get-DesignBitmap 已把任意尺寸归一化到设计基准，只要客户区宽 >=800 任何窗口都能用；
    #         wxresize 只能救「宽<800」这一种，而那恰是用户主动缩小的结果——自动拉回属越权，
    #         且每次多付 1.3s+（子进程启动 + 800ms 硬等 + resize 动作）。
    #   ERR 后只原地重探一次，覆盖前台抖动 / 子进程偶发异常；仍 ERR 交调用方停机，不掩盖真故障。
    $st = Invoke-Probe -Quick:$Quick
    if ($st -eq "ERR") {
        # ⚠ 必须 Write-Host：裸字符串会被 $st = Invoke-ProbeHeal 吸收进返回值，污染状态值
        #   （2026-11-01 冒烟实测：原写法导致 HEAL 提示不输出，且 $st 变成数组）
        Write-Host "HEAL: probe ERR -> reprobe once (no resize)"
        Start-Sleep -Milliseconds 1000
        $st = Invoke-Probe -Quick:$Quick
        if ($st -eq "ERR") { Write-Host "HEAL: reprobe still ERR -> give up (交调用方停机)" }
    }
    return $st
}
function Invoke-Poke {
    # 轮盘保活戳（用户方案：左下角轮盘任何画面绝对安全——用户在玩时戳一下也无妨，无需探测）
    & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxpoke.ps1" -Pid2 $Pid2 2>&1 | Select-Object -Last 2
}
# 240s 节流（2026-11-01 用户定版，原 120s）：poke 本就无法重置游戏挂机计时（10-26 实锤，
#   115s 间隔下挂机弹窗照样复现），加频无收益，拉长到 240s 纯降开销。
#   阈值 235 = 标称 240s 留 5s 余量（原 115/120 同比例），抵消循环间隔与探针耗时。
$script:PokeIntervalSec = 235
$script:lastPoke = Get-Date
function Invoke-PokeIfDue {
    if (((Get-Date) - $script:lastPoke).TotalSeconds -ge $script:PokeIntervalSec) {
        Invoke-Poke
        $script:lastPoke = Get-Date
    }
}
function Invoke-Click([string]$steps) {
    & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxclick.ps1" -Pid2 $Pid2 -Steps $steps 2>&1 | ForEach-Object { "$_" }
}
function Invoke-PopupGuard {
    # 2026-10-26 新增：GOLD_DIALOG 持续时用 wxpopup 分类——
    # POPUP_IDLE（挂机弹窗，红线必须点确定）→ 自动点 (700,513) 消掉；
    #   然后**必须全量重探**：登录页会被 wxpopup 误分类为 IDLE（金色「进入游戏」钮污染签名，2026-10-26 实锤），
    #   dismiss 后若是 LOGIN_PAGE = 会话已被踢 → 返回 "LOGIN"，调用方 exit 7 交操作员重登。
    # 其余（顶号/扩展券/未知）→ 返回 "STOP"，调用方按红线停机。
    # 返回：OK=已消弹窗可继续 / LOGIN=已被踢登录页 / STOP=红线停机
    # 依据：wxpoke 实测无法重置游戏挂机计时（2026-10-26 圣殿挂机弹窗 115s 戳间隔下仍复现）。
    $out = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxpopup.ps1" -Pid2 $Pid2 2>&1
    $joined = ($out -join " ")
    # 2026-10-28（事件20 移植）：wxpopup 判 NONE=画面无真弹窗（probe 被金边装饰提示框欺骗的假 GOLD）
    #   → 返回 "NONE"，调用方继续等待/重探，不停机不点击。
    if ($joined -match 'POPUP_NONE') { Write-Host "GUARD: wxpopup NONE (probe false gold, event20) -> continue"; return "NONE" }
    if ($joined -match 'POPUP_IDLE') {
        Write-Host "GUARD: POPUP_IDLE -> dismiss (700,513) then verify page"
        Invoke-Click "700:513:600" | Out-Null
        Start-Sleep -Seconds 2
        $after = Invoke-ProbeHeal
        # 2026-10-27：LOGIN_PAGE 探针退役，登录页身份=wxocr server 任务（用户定版 OCR 优先）
        $loginOut = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxocr.ps1" -Pid2 $Pid2 -Task server 2>&1 | Out-String
        if ($loginOut -match 'OCR=server=HIT') { Write-Host "GUARD: login page behind popup (wxocr server HIT) -> kicked"; return "LOGIN" }
        return "OK"
    }
    Write-Host "GUARD: not idle popup ($($joined.Trim())) -> stop"
    return "STOP"
}
for ($i = 1; $i -le $Rounds; $i++) {
    "=== round $i/$Rounds ==="
    Invoke-PokeIfDue   # 覆盖上一场战斗期间的等待时间
    # 1) 等结算页（Quick 轻量探针 1s 轮询；GOLD 需连续 3 次确认——战斗结束金色爆闪瞬时误报）
    $t = 0; $st = Invoke-ProbeHeal -Quick; $goldStreak = 0; $unkStreak = 0
    while ($st -ne "SETTLE_PAGE") {
        if ($st -eq "ERR") { "STOP: probe error (wxprobe failed - 窗口丢失或尺寸不符，见 wxprobe 输出)"; exit 9 }
        if ($st -eq "GOLD_DIALOG") {
            $goldStreak++
            if ($goldStreak -ge 3) {
                $g = Invoke-PopupGuard
                if ($g -eq "OK") {
                    $goldStreak = 0; $t += 3
                    # 不 continue：落回循环底部重探（dismiss 后画面已变，$st 需刷新）
                } elseif ($g -eq "LOGIN") { "STOP: kicked to login page (exit 7)"; exit 7 }
                elseif ($g -eq "NONE") { $goldStreak = 0; $t += 1
                    # 事件20：probe 假金（装饰提示框），wxpopup 证实无真弹窗 → 继续等，不停机
                }
                else { "STOP: persistent gold dialog (death/idle/login)"; exit 6 }
            }
            Start-Sleep -Seconds 1; $t += 1
        } elseif ($st -eq "STAMINA_POP") { "STOP: stamina popup"; exit 5 }
        else {
            $goldStreak = 0
            if ($st -eq "UNKNOWN") {
                $unkStreak++
                if ($unkStreak -ge 10) {
                    # Quick 模式认不出登录页——UNKNOWN 持续 ~40s 时全量探针验踢线（战斗中误触发仅多花一次全探）
                    $full = Invoke-ProbeHeal
                    if ($full -eq "LOGIN_PAGE") { "STOP: kicked to login page (exit 7)"; exit 7 }
                    $unkStreak = 0
                }
            } else { $unkStreak = 0 }
            Start-Sleep -Seconds 1; $t += 1
        }
        if ($t -ge $SettleWaitSec) { "STOP: settle wait timeout ($SettleWaitSec s), last=$st"; exit 2 }
        Invoke-PokeIfDue
        $st = Invoke-ProbeHeal -Quick
    }
    # 2) 点再来一次
    #    D2/D3（2026-11-01 用户定版）：点击后只等 800ms 让点击生效，就绪判定全交给紧随其后的
    #      EnterWaitSec 轮询；若要多试一次，第二次也**不重复硬等**——第一次失败说明点击没生效，不是等得不够。
    #    D4（选 A）：重试权归编排层。内部默认只点 1 次，失败 exit 2 交外部按 §七 最多重试 3 次，
    #      避免「内部 2 次 × 外部 3 次 = 连续 6 次点击」误触。需要内部多试请显式 -RetryAttempts N。
    $entered = $false
    #    注意：用 for 而非 foreach (1..$RetryAttempts)——PS 的 1..0 会展开成 (1,0) 两元素，
    #    传 0 反而点两次。for 在 <=0 时天然不循环，直接落到 exit 2。
    for ($attempt = 1; $attempt -le $RetryAttempts; $attempt++) {
        $rc = Resolve-RetryCoords
        "round ${i}: click retry (attempt $attempt/$RetryAttempts, target=$rc)"
        $rcParts = $rc.Split(',')
        Invoke-Click "$($rcParts[0]):$($rcParts[1]):800" | Out-Null
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
        # IDLE → 自动 dismiss 后重探续跑；LOGIN=被踢 → exit 7；顶号/扩展券/未知 → 红线停机。
        $g = Invoke-PopupGuard
        if ($g -eq "LOGIN") { "STOP: kicked to login page (exit 7)"; exit 7 }
        if ($g -ne "OK" -and $g -ne "NONE") { "STOP: gold dialog after enter"; exit 6 }
        $st = Invoke-ProbeHeal
        "round ${i}: after guard state=$st"
        if ($st -eq "ERR") { "STOP: probe error after enter"; exit 9 }
    }
    if ($st -eq "STAMINA_POP") { "STOP: stamina popup after enter"; exit 5 }
    # 3.5) 自动战斗确保（v1.1.12 起唯一入口=wxautoensure，OCR 单判据；旧模板 gated 路径退役——
    #      其布局常量/锚点已被 v1.1.10/11 两次变更甩下，wxprobe AUTO 态仅存诊断用途）。
    #      无条件每场必调：ON 优先判定（已开 ~1s 返回 0 点击），不再依赖 probe AUTO_OFF 触发。
    "round ${i}: ensure auto (wxautoensure)"
    $ens = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxautoensure.ps1" -Pid2 $Pid2 -TimeoutSec 30 2>&1
    $ens | ForEach-Object { "$_" }
    if (($ens -join "`n") -notmatch 'AUTO_ENSURED') { "STOP: auto ensure failed"; exit 3 }
    # 4) 等战斗结束（下一轮的等结算负责等待）
}
"LOOP: $Rounds rounds completed"
$st = Invoke-ProbeHeal
"final state=$st"

param([int]$Rounds = 1, [int]$Pid2 = 0, [int]$RetryX = 936, [int]$RetryY = 269, [int]$SettleWaitSec = 90, [int]$EnterWaitSec = 25, [switch]$AutoRetry)
# 固化刷本循环（2026-10-24 新增，替代 wxfarm 的通用扫描方案，语法0错误未实战）
# 思路：不再扫描按钮位置——结算「再来一次」用固定坐标（圣殿两行布局实测 (936,269)），
#       每步用 wxprobe 验证状态，异常即停。依赖 wxprobe/wxclick 同目录。
# 流程/轮：等结算 → 点再来一次 → 验证离场 → (AUTO_OFF 时 gated 开自动) → 等下一结算
# 退出码：0=完成/重试失败  2=结算等待超时  5=体力弹窗  6=金色弹窗(复活/挂机/登录)  3=自动战斗确保失败  7=会话被踢回登录页(操作员重登后续跑)
$scripts = $PSScriptRoot
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
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxprobe.ps1" -Pid2 $Pid2 @xargs 2>&1
    $state = "ERR"
    foreach ($line in $out) { if ($line -match '^STATE=(\w+)') { $state = $Matches[1] } }
    return $state
}
function Invoke-ProbeHeal {
    param([switch]$Quick)
    # 2026-10-26 更新：客户区 1-3px 级漂移已由设计坐标换算吸收，探针不再因尺寸微变 ERR。
    # 保留 ERR 自愈，仅兜底长宽比异常/窗口抖动；真实丢窗时 wxresize 也会失败 → 复测仍 ERR → 调用方停机，不掩盖真故障。
    $st = Invoke-Probe -Quick:$Quick
    if ($st -eq "ERR") {
        "HEAL: probe ERR -> wxresize -> reprobe"
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxresize.ps1" -Pid2 $Pid2 2>&1 | Select-Object -Last 1
        Start-Sleep -Milliseconds 800
        $st = Invoke-Probe -Quick:$Quick
    }
    return $st
}
function Invoke-Poke {
    # 轮盘保活戳（用户方案：左下角轮盘任何画面绝对安全——用户在玩时戳一下也无妨，无需探测）
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxpoke.ps1" -Pid2 $Pid2 2>&1 | Select-Object -Last 2
}
# 120s 节流（用户 2026-10-24 定版：120s 一戳足够避开挂机弹窗，无需更频）
$script:lastPoke = Get-Date
function Invoke-PokeIfDue {
    if (((Get-Date) - $script:lastPoke).TotalSeconds -ge 115) {
        Invoke-Poke
        $script:lastPoke = Get-Date
    }
}
function Invoke-Click([string]$steps) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxclick.ps1" -Pid2 $Pid2 -Steps $steps 2>&1 | ForEach-Object { "$_" }
}
function Invoke-PopupGuard {
    # 2026-10-26 新增：GOLD_DIALOG 持续时用 wxpopup 分类——
    # POPUP_IDLE（挂机弹窗，红线必须点确定）→ 自动点 (700,513) 消掉；
    #   然后**必须全量重探**：登录页会被 wxpopup 误分类为 IDLE（金色「进入游戏」钮污染签名，2026-10-26 实锤），
    #   dismiss 后若是 LOGIN_PAGE = 会话已被踢 → 返回 "LOGIN"，调用方 exit 7 交操作员重登。
    # 其余（顶号/扩展券/未知）→ 返回 "STOP"，调用方按红线停机。
    # 返回：OK=已消弹窗可继续 / LOGIN=已被踢登录页 / STOP=红线停机
    # 依据：wxpoke 实测无法重置游戏挂机计时（2026-10-26 圣殿挂机弹窗 115s 戳间隔下仍复现）。
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxpopup.ps1" -Pid2 $Pid2 2>&1
    $joined = ($out -join " ")
    if ($joined -match 'POPUP_IDLE') {
        Write-Host "GUARD: POPUP_IDLE -> dismiss (700,513) then verify page"
        Invoke-Click "700:513:600" | Out-Null
        Start-Sleep -Seconds 2
        $after = Invoke-ProbeHeal
        # 2026-10-27：LOGIN_PAGE 探针退役，登录页身份=wxocr server 任务（用户定版 OCR 优先）
        $loginOut = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxocr.ps1" -Pid2 $Pid2 -Task server 2>&1 | Out-String
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
    # 2) 点再来一次（两次机会）
    $entered = $false
    foreach ($attempt in 1..2) {
        $rc = Resolve-RetryCoords
        "round ${i}: click retry (attempt $attempt, target=$rc)"
        $rcParts = $rc.Split(',')
        Invoke-Click "$($rcParts[0]):$($rcParts[1]):6000" | Out-Null
        $t = 0; $st = Invoke-ProbeHeal
        while ($st -eq "SETTLE_PAGE" -and $t -lt $EnterWaitSec) {
            Start-Sleep -Seconds 1; $t += 1; $st = Invoke-ProbeHeal
        }
        if ($st -ne "SETTLE_PAGE") { $entered = $true; break }
        "round ${i}: still settle after attempt $attempt"
    }
    if (-not $entered) { "STOP: retry clicks failed twice (round $i)"; exit 0 }
    # 3) 入场确认 + 自动战斗
    "round ${i}: entered, state=$st"
    if ($st -eq "ERR") { "STOP: probe error after enter"; exit 9 }
    if ($st -eq "GOLD_DIALOG") {
        # 入场即 GOLD：多为挂机弹窗压屏（wxpoke 无法重置挂机计时，2026-10-26 实锤）。
        # IDLE → 自动 dismiss 后重探续跑；LOGIN=被踢 → exit 7；顶号/扩展券/未知 → 红线停机。
        $g = Invoke-PopupGuard
        if ($g -eq "LOGIN") { "STOP: kicked to login page (exit 7)"; exit 7 }
        if ($g -ne "OK") { "STOP: gold dialog after enter"; exit 6 }
        $st = Invoke-ProbeHeal
        "round ${i}: after guard state=$st"
        if ($st -eq "ERR") { "STOP: probe error after enter"; exit 9 }
    }
    if ($st -eq "STAMINA_POP") { "STOP: stamina popup after enter"; exit 5 }
    if ($st -eq "AUTO_OFF") {
        $out = Invoke-Click "auto"
        $out | ForEach-Object { "$_" }
        $joined = ($out -join "`n")
        if ($joined -match 'AUTO_ENSURE_FAIL') { "STOP: auto ensure failed"; exit 3 }
    }
    # 4) 等战斗结束（下一轮的等结算负责等待）
}
"LOOP: $Rounds rounds completed"
$st = Invoke-ProbeHeal
"final state=$st"

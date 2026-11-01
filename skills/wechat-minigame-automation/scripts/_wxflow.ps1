# _wxflow.ps1 — 跨链路策略层（模块化 P3，2026-11-01）
# 定位：模块层（_wxcore）回答「画面是什么状态」，本层回答「拿到这个状态该怎么办」。
# 契约：同 _wxcore —— 函数**只返回对象、不输出裸字符串**。裸字符串会被 $x = Func 吸收进返回值，
#       且「数组 -eq 字符串」在 PS 里是过滤不是全等，会掩盖故障（2026-11-01 冒烟实证，见 run-environment-pitfalls §2）。
# 依赖：调用方必须先 dot-source _wxcommon.ps1 与 _wxcore.ps1（同 _wxcore 约定）。
# 迁移原则：坐标/分类顺序/判定阈值一律零改动，只把各链内联逻辑收敛成函数。

# ---- 挂机弹窗「确定」按钮（设计坐标 1138x708）----
# 来源：wxgrind.Invoke-PopupGuard 与 wxrelogin 阶段1/阶段4 三处内联值，实测一致。
$WX_GOLD_CONFIRM_X = 700
$WX_GOLD_CONFIRM_Y = 513
# ---- 复活弹窗「立即复活」按钮（2026-11-01 实机核对）----
# 与挂机弹窗「确定」同位（同一面板槽位）；v1.1.22 起 coords.md 记的就是 (700,513)，
# 旧值 (722,516) 已作废。实机该弹窗 goldbtn=1277、正文「确定复活吗？」。
$WX_REVIVE_X = 700
$WX_REVIVE_Y = 513

function New-WxGuardResult {
    param([string]$Verdict = "STOP", [string]$Cls = "POPUP_UNKNOWN", [bool]$Dismissed = $false, [bool]$Revived = $false, [string]$Err = "")
    [pscustomobject]@{ Verdict = $Verdict; Cls = $Cls; Dismissed = $Dismissed; Revived = $Revived; Err = $Err }
}

# 金弹窗处置（单源）
# IN : 调用方已探到 State=GOLD_DIALOG。**本函数不自己首判探针**，首判由调用方给，避免重复探。
# OUT: Verdict = OK     已消弹窗（或授权点击），可继续
#              = NONE   probe 假金（金边装饰框欺骗，事件20），不停机不点击，调用方继续等
#              = REVIVE 已点「立即复活」（仅 -AllowRevive 时出现），调用方**必须重开自动战斗**再继续
#              = LOGIN  点击后复验为登录页 → 会话已被踢，调用方 exit 7 交操作员重登
#              = STOP   红线（顶号/涉钱/扩展券/未知/分类失败/未授权的复活），调用方按红线停机
function Invoke-WxGoldGuard {
    param(
        [int]$Pid2 = 0,
        [string]$Cls = "",      # 调用方已探到的分类。非空则跳过 Invoke-WxPopup，避免重复探（约 0.3s）
        [switch]$AssumeGold,    # 顶号弹窗：用户授权后对非 IDLE 分类也放行点击（wxrelogin 阶段1 语义）
        [switch]$VerifyLogin,   # 点完复验是否被踢登录页（wxgrind 需要；wxrelogin 靠后续阶段判，不用）
        [switch]$AllowRevive,   # 允许点「立即复活」。**由调用方按次数封顶决定**，本函数不计数
        [int]$SettleMs = 2000   # 复验前等待（保留 wxgrind 原 2s，零漂移）
    )
    $cls = $Cls
    if ($cls -eq "") {
        $pi = $null
        try { $pi = Invoke-WxPopup -Pid2 $Pid2 } catch { $pi = $null }
        if (-not $pi -or $pi.Err) {
            # 分类失败 → 保守红线（语义同 wxrelogin Get-PopupInfo 的默认 POPUP_UNKNOWN）
            return (New-WxGuardResult -Verdict "STOP" -Cls "POPUP_UNKNOWN")
        }
        $cls = $pi.Popup
    }

    # 假金：probe 被金边装饰提示框欺骗（事件20）→ 继续等待，不停机不点击
    if ($cls -eq "POPUP_NONE") { return (New-WxGuardResult -Verdict "NONE" -Cls $cls) }

    # 复活弹窗（2026-11-01 第二层）：只在调用方显式授权时点「立即复活」。
    #   为什么单独一个分支而不并进 IDLE：复活**消耗资源**（羽毛，每天免费领 1 个），属不可逆动作，
    #   必须由调用方按次数封顶（用户定版：封顶 2 次）+ 开关控制，本函数不做次数判断。
    #   点完返回 REVIVE 而非 OK：调用方拿到后**必须重开自动战斗**，否则角色继续站桩连环死。
    if ($cls -eq "POPUP_REVIVE") {
        if (-not $AllowRevive) { return (New-WxGuardResult -Verdict "STOP" -Cls $cls) }
        # ⚠ 2026-11-01 v1.1.27（开发侧待办 9）：原为 `$null = Invoke-WxClick ...`，返回值被丢弃。
        #   点击被前台/最小窗守卫拒（ExitCode=7）或窗口丢失（ExitCode=1）时，原样返回 REVIVE，
        #   调用方以为"已复活"→ 去重开自动战斗 + **扣掉一次复活配额**，而角色还躺在地上。
        #   ⇒ 点击不成立时**不得**返回 REVIVE。
        # ⚠⚠ 但也不能判 STOP（2026-11-01 22:2x 用户当场纠正，我第一版就是错在这里）：
        #   管理新规 §七 三档契约——「0=达成 / 2=未达成但画面干净可原地重试 / 其它=STOP」。
        #   点击被前台守卫拒是**暂时的、下一秒就可能恢复**（用户切窗口、窗口被抢焦点），
        #   属于「可原地重试」，绝不是「红线停机」。判 STOP 的后果是：挂机时前台被抢一下，
        #   整条 wxgrind 直接 exit 6 停掉——这是把自愈能力改没了。
        #   ⇒ 返回 NONE（=弹窗没消掉，调用方继续等，下一轮探针会再判再点），Err 留痕供诊断。
        $c = $null
        try { $c = Invoke-WxClick -Steps "$($WX_REVIVE_X):$($WX_REVIVE_Y):1200" -Pid2 $Pid2 } catch { $c = $null }
        if (-not $c -or $c.ExitCode -ne 0) {
            $d = if ($c) { "exit=$($c.ExitCode) $($c.Err)" } else { "click returned null" }
            return (New-WxGuardResult -Verdict "NONE" -Cls $cls -Err "revive click not effective: $d")
        }
        return (New-WxGuardResult -Verdict "REVIVE" -Cls $cls -Dismissed $true -Revived $true)
    }

    # 只有挂机弹窗 POPUP_IDLE 才自动点「确定」；其余一律红线，除非用户显式授权 AssumeGold
    if ($cls -ne "POPUP_IDLE" -and -not $AssumeGold) {
        return (New-WxGuardResult -Verdict "STOP" -Cls $cls)
    }

    # ⚠ 2026-11-01 v1.1.27（开发侧待办 9）：同上，点击返回值必须检查。
    #   原来丢了返回值：守卫拒点（ExitCode=7，游戏不在前台且拉回失败）时仍返回 OK，
    #   调用方（wxgrind 段1/段3、wxrelogin 阶段4）会以为弹窗已消。
    # ⚠⚠ 但**不能**因为点击失败就判 STOP（用户 2026-11-01 22:2x 当场纠正）：
    #   §七 三档契约里「点击未生效」属「可原地重试」，不属红线。前台被抢是暂时状态，
    #   下轮探针会重判、重试点击；判 STOP 只会把一次可自愈的抖动升级成整链停机。
    #   ⇒ 返回 NONE（=弹窗没消掉，继续等），Err 留痕供诊断。
    $c = $null
    try { $c = Invoke-WxClick -Steps "$($WX_GOLD_CONFIRM_X):$($WX_GOLD_CONFIRM_Y):800" -Pid2 $Pid2 } catch { $c = $null }
    if (-not $c -or $c.ExitCode -ne 0) {
        $d = if ($c) { "exit=$($c.ExitCode) $($c.Err)" } else { "click returned null" }
        return (New-WxGuardResult -Verdict "NONE" -Cls $cls -Err "confirm click not effective: $d")
    }

    if (-not $VerifyLogin) { return (New-WxGuardResult -Verdict "OK" -Cls $cls -Dismissed $true) }

    # 复验：dismiss 后画面可能是登录页（会话被踢）。登录页身份 = server OCR 单判据（v1.1.5 定版）。
    # 注：原 wxgrind 此处还多做一次 Invoke-ProbeHeal 但返回值从未使用（纯浪费一次探针），单源化时去掉。
    Start-Sleep -Milliseconds $SettleMs
    $o = $null
    try { $o = Invoke-WxOcr -Pid2 $Pid2 -Task server } catch { $o = $null }
    if ($o -and -not $o.Err -and $o.Hit) {
        return (New-WxGuardResult -Verdict "LOGIN" -Cls $cls -Dismissed $true)
    }
    return (New-WxGuardResult -Verdict "OK" -Cls $cls -Dismissed $true)
}

# ================= 等状态状态机（P5b，2026-11-01 从 wxgrind 段1 内联循环抽象）=================
# 原 wxgrind 段1：手工 while + goldStreak/unkStreak 两个计数器 + 四处出口。
# 抽象后判据与计数器行为**逐行照搬**，只是把「exit 码」换成返回 Result 交调用方决定。
# Result 取值：
#   OK      已到目标状态
#   TIMEOUT 超时（画面干净，可重试）
#   ERR     探针故障（STOP）
#   LOGIN   被踢回登录页（需重登）
#   GOLD    金弹窗未消/红线（STOP）
#   STAMINA 体力弹窗（STOP）
#   REVIVED 已点「立即复活」（仅 -AllowRevive）。**调用方必须重开自动战斗后重新等待**，
#           本层不负责重开——autoensure 是独立脚本，策略层不跨进程调它（保分层，也免注入盲区）。
function New-WxWaitResult {
    param([string]$Result = "OK", [string]$State = "", [string]$Detail = "")
    [pscustomobject]@{ Result = $Result; State = $State; Detail = $Detail }
}

function Wait-WxState {
    param(
        [int]$Pid2 = 0,
        [string]$Target = "SETTLE_PAGE",
        [int]$TimeoutSec = 90,
        [switch]$GoldGuard,          # GOLD 连击达阈值后走单源守卫
        [switch]$VerifyLogin,        # 守卫点完复验登录页
        [int]$GoldConfirmN = 3,      # GOLD 连击确认次数（战斗结束金闪瞬时误报）
        [int]$StaminaConfirmN = 3,   # 体力弹窗连击确认次数（战斗中绿色特效瞬时误报，2026-11-01 实机撞上）
        [int]$UnknownDeepN = 10,     # UNKNOWN 连续多少次后做一次全量探针验踢线
        [switch]$NoSleep,            # 测试用：跳过 sleep
        [switch]$AllowRevive,        # 允许守卫点「立即复活」（次数封顶由调用方管）
        [scriptblock]$Probe = $null  # 测试用：注入探针（签名 { param($quick) -> 状态字符串 }）
    )
    # ⚠ 严禁在此处加 .GetNewClosure()（事件23，2026-11-01，v1.1.22 实战炸链）：
    #   GetNewClosure 会把脚本块绑定到一个新的动态模块，命令解析会话状态随之更换，
    #   **看不见调用方「脚本作用域」里 dot-source 进来的函数**——只有全局注册的函数它才认。
    #   表现为 Invoke-WxProbeHeal : 无法识别 → $r 恒空 → $st 永远不等于目标态 → 空转到超时。
    #   实测对照：withClosure=MISSING / withoutClosure=FOUND（同一脚本作用域内同函数）。
    #   注意可见性分界：交互式 -Command 运行时 dot-source 落全局作用域，加了闭包也正常，
    #   只有 wxgrind 这种 -File 跑（脚本作用域）才暴露——所以此 bug 在交互式排查时看不见。
    # 约束：本脚本块**只允许在 Wait-WxState 栈内用 & 调用**（下三处），
    #   不加闭包时 $Probe / $Pid2 靠作用域链动态解析照常可见；一旦传出函数体外使用，变量会失解析。
    $probeCall = {
        param($q)
        if ($Probe) { return (& $Probe $q) }
        $r = Invoke-WxProbeHeal -Pid2 $Pid2 -Quick:$q
        if ($r.Err) { return "ERR" }
        return $r.State
    }

    $t = 0; $goldStreak = 0; $unkStreak = 0; $staminaStreak = 0
    $st = & $probeCall $true
    while ($st -ne $Target) {
        if ($st -eq "ERR") { return (New-WxWaitResult -Result "ERR" -State $st -Detail "probe failed") }

        if ($st -eq "GOLD_DIALOG") {
            $staminaStreak = 0
            $goldStreak++
            if ($goldStreak -ge $GoldConfirmN) {
                if (-not $GoldGuard) { return (New-WxWaitResult -Result "GOLD" -State $st -Detail "gold dialog, guard disabled") }
                $g = Invoke-WxGoldGuard -Pid2 $Pid2 -VerifyLogin:$VerifyLogin -AllowRevive:$AllowRevive
                if ($g.Verdict -eq "OK") { $goldStreak = 0; $t += 3 }
                elseif ($g.Verdict -eq "LOGIN") { return (New-WxWaitResult -Result "LOGIN" -State $st -Detail "cls=$($g.Cls)") }
                elseif ($g.Verdict -eq "REVIVE") { return (New-WxWaitResult -Result "REVIVED" -State $st -Detail "cls=$($g.Cls)") }
                elseif ($g.Verdict -eq "NONE") { $goldStreak = 0; $t += 1 }
                else { return (New-WxWaitResult -Result "GOLD" -State $st -Detail "cls=$($g.Cls)$(if ($g.Err) { " err=$($g.Err)" })") }
            }
            if (-not $NoSleep) { Start-Sleep -Seconds 1 }
            $t += 1
        } elseif ($st -eq "STAMINA_POP") {
            # 2026-11-01：体力弹窗要求**连续 N 次确认**才停。
            #   原实现见一次就 return STAMINA，导致战斗中绿色技能特效/光环闪过一帧即误停机（圣殿-1 实机撞上，
            #   截图复核该帧 STAM=0，属瞬时命中）。真体力弹窗是持久状态，连击必然成立；瞬时特效则会被过滤。
            #   同 GOLD 三连确认思路（过滤战斗结束金色爆闪）。
            #   ⚠ 2026-11-01 补 $goldStreak = 0（代码审查二档）：原先只有 GOLD 分支清 $staminaStreak、
            #     STAMINA 分支不清 $goldStreak，两者不对称。画面在 GOLD_DIALOG 与 STAMINA_POP 之间来回闪
            #     （金色爆闪 + 绿色特效同时存在）时，序列 GOLD,STAMINA,GOLD,STAMINA,GOLD 会凑够"三连"
            #     误触守卫去点 (700,513)。真正的"连击"要求连续，任何一次别的状态都必须归零。
            $goldStreak = 0
            $staminaStreak++
            if ($staminaStreak -ge $StaminaConfirmN) {
                return (New-WxWaitResult -Result "STAMINA" -State $st -Detail "confirmed x$staminaStreak")
            }
            if (-not $NoSleep) { Start-Sleep -Seconds 1 }
            $t += 1
        } else {
            $goldStreak = 0
            $staminaStreak = 0
            if ($st -eq "UNKNOWN") {
                $unkStreak++
                if ($unkStreak -ge $UnknownDeepN) {
                    # 深探：Quick 认不出登录页，UNKNOWN 持续 ~40s 才做一次深判（战斗中误触发只多花一次 OCR）
                    # ⚠ 2026-11-01 修死分支（代码审查一档）：原实现读 `$full -eq "LOGIN_PAGE"`，但
                    #   **Invoke-WxProbe 从不产出该状态**——登录页像素判据 2026-10-27 已退役，
                    #   "LOGIN_PAGE" 这个字符串在 _wxcore 里根本不存在。所以那个 if 永远不成立：
                    #   被踢登录页时只会一路 UNKNOWN 耗满 SettleWaitSec(90s) 再 exit 2，编排层还会当"可重试"。
                    #   现改为 **server OCR 单判据**（登录页身份 = 「巨龙山脉」，v1.1.5 定版），
                    #   与 Invoke-WxGoldGuard 复验登录页用的是同一个判据。
                    $isLogin = $false
                    if ($Probe) {
                        # 测试注入路径：由注入探针返回 "LOGIN_PAGE" 表示登录页（保持离线可测）
                        $full = & $Probe $false
                        if ($full -eq "LOGIN_PAGE") { $isLogin = $true }
                    } else {
                        $o = $null
                        try { $o = Invoke-WxOcr -Pid2 $Pid2 -Task server } catch { $o = $null }
                        if ($o -and -not $o.Err -and $o.Hit) { $isLogin = $true }
                    }
                    if ($isLogin) { return (New-WxWaitResult -Result "LOGIN" -State "LOGIN_PAGE" -Detail "deep probe: server OCR hit") }
                    $unkStreak = 0
                }
            } else { $unkStreak = 0 }
            if (-not $NoSleep) { Start-Sleep -Seconds 1 }
            $t += 1
        }

        if ($t -ge $TimeoutSec) { return (New-WxWaitResult -Result "TIMEOUT" -State $st) }
        $st = & $probeCall $true
    }
    return (New-WxWaitResult -Result "OK" -State $st)
}
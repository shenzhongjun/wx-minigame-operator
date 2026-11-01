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

function New-WxGuardResult {
    param([string]$Verdict = "STOP", [string]$Cls = "POPUP_UNKNOWN", [bool]$Dismissed = $false)
    [pscustomobject]@{ Verdict = $Verdict; Cls = $Cls; Dismissed = $Dismissed }
}

# 金弹窗处置（单源）
# IN : 调用方已探到 State=GOLD_DIALOG。**本函数不自己首判探针**，首判由调用方给，避免重复探。
# OUT: Verdict = OK    已消弹窗（或授权点击），可继续
#              = NONE  probe 假金（金边装饰框欺骗，事件20），不停机不点击，调用方继续等
#              = LOGIN 点击后复验为登录页 → 会话已被踢，调用方 exit 7 交操作员重登
#              = STOP  红线（顶号/涉钱/扩展券/未知/分类失败），调用方按红线停机
function Invoke-WxGoldGuard {
    param(
        [int]$Pid2 = 0,
        [string]$Cls = "",      # 调用方已探到的分类。非空则跳过 Invoke-WxPopup，避免重复探（约 0.3s）
        [switch]$AssumeGold,    # 顶号弹窗：用户授权后对非 IDLE 分类也放行点击（wxrelogin 阶段1 语义）
        [switch]$VerifyLogin,   # 点完复验是否被踢登录页（wxgrind 需要；wxrelogin 靠后续阶段判，不用）
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

    # 只有挂机弹窗 POPUP_IDLE 才自动点「确定」；其余一律红线，除非用户显式授权 AssumeGold
    if ($cls -ne "POPUP_IDLE" -and -not $AssumeGold) {
        return (New-WxGuardResult -Verdict "STOP" -Cls $cls)
    }

    $null = Invoke-WxClick -Steps "$($WX_GOLD_CONFIRM_X):$($WX_GOLD_CONFIRM_Y):800" -Pid2 $Pid2

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
        [int]$UnknownDeepN = 10,     # UNKNOWN 连续多少次后做一次全量探针验踢线
        [switch]$NoSleep,            # 测试用：跳过 sleep
        [scriptblock]$Probe = $null  # 测试用：注入探针（签名 { param($quick) -> 状态字符串 }）
    )
    $probeCall = {
        param($q)
        if ($Probe) { return (& $Probe $q) }
        $r = Invoke-WxProbeHeal -Pid2 $Pid2 -Quick:$q
        if ($r.Err) { return "ERR" }
        return $r.State
    }.GetNewClosure()

    $t = 0; $goldStreak = 0; $unkStreak = 0
    $st = & $probeCall $true
    while ($st -ne $Target) {
        if ($st -eq "ERR") { return (New-WxWaitResult -Result "ERR" -State $st -Detail "probe failed") }

        if ($st -eq "GOLD_DIALOG") {
            $goldStreak++
            if ($goldStreak -ge $GoldConfirmN) {
                if (-not $GoldGuard) { return (New-WxWaitResult -Result "GOLD" -State $st -Detail "gold dialog, guard disabled") }
                $g = Invoke-WxGoldGuard -Pid2 $Pid2 -VerifyLogin:$VerifyLogin
                if ($g.Verdict -eq "OK") { $goldStreak = 0; $t += 3 }
                elseif ($g.Verdict -eq "LOGIN") { return (New-WxWaitResult -Result "LOGIN" -State $st -Detail "cls=$($g.Cls)") }
                elseif ($g.Verdict -eq "NONE") { $goldStreak = 0; $t += 1 }
                else { return (New-WxWaitResult -Result "GOLD" -State $st -Detail "cls=$($g.Cls)") }
            }
            if (-not $NoSleep) { Start-Sleep -Seconds 1 }
            $t += 1
        } elseif ($st -eq "STAMINA_POP") {
            return (New-WxWaitResult -Result "STAMINA" -State $st)
        } else {
            $goldStreak = 0
            if ($st -eq "UNKNOWN") {
                $unkStreak++
                if ($unkStreak -ge $UnknownDeepN) {
                    # Quick 认不出登录页：UNKNOWN 持续 ~40s 才做一次全量探针（战斗中误触发仅多花一次全探）
                    $full = & $probeCall $false
                    if ($full -eq "LOGIN_PAGE") { return (New-WxWaitResult -Result "LOGIN" -State $full -Detail "deep probe") }
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
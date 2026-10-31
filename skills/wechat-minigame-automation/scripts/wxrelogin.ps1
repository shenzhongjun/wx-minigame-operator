# wxrelogin.ps1 — 组合重登链 v1（2026-10-31，交接文档 §五待办2 落地）
# 流程：金弹窗处理(仅 POPUP_IDLE 自动点 700,513) → server OCR 轮询等登录页 → 点进入游戏(571,527)
#       → charsel OCR 确认 → wxcharsel -Char N -StartGame → 终态轮询：POPUP_PACK 点红叉关闭 /
#       TOWN_PAGE(三探针, v1.1.17) 即成功。B1(town OCR 背景 MISS) 已由三探针根治，本链终态=三探针权威。
# 红线（沿用 wxlogin v1.1.6 固化）：GOLD_DIALOG 先 wxpopup OCR 分类——POPUP_IDLE→自动点确定；
#       其余（顶号/涉钱/未知）停机 exit 9，绝不自动点。-AssumeGold=人工强制放行（透传）。
# 复用单源：**wxprobe / wxpopup 自 2026-10-31 起同进程调用**（dot-source _wxcore.ps1 的 Invoke-WxProbe /
#       Invoke-WxPopup，不再起子进程，模块化试点）；wxocr / wxclick / wxcharsel 仍走子进程。
#       本脚本零像素逻辑零坐标卡表（唯一自有动作=红叉 (160,192)，与 coords.md「新手礼包弹窗」行一致；
#       礼包判据 2026-10-31 起来自 wxpopup POPUP_PACK，probe 不再判弹窗）。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File wxrelogin.ps1 [-Pid2 N] [-Char 1] [-TownTimeoutSec 90] [-AssumeGold] [-Perf]
# 退出码：0=RELOGIN_OK（三探针确认到主城）｜ALREADY_TOWN（本来就在主城，未执行任何点击）；9=STOP（红线/超时/异常，人工核对）。
# -Perf：输出分段计时（t=Ns）与调用统计（perf: ...），用于性能复测；默认关，不影响任何逻辑与耗时。
# 等待策略（2026-10-31 晚改）：点击后只等 800ms 让点击生效、画面开始切换，随后一律靠 OCR/探针轮询判定，
#   **不再硬等固定秒数**。原「点确定等 4s / 进游戏等 5s / 点开始游戏等 5s」是链路耗时大头——
#   游戏侧实际 2~3s 就绪，多等的是纯浪费（用户 2026-10-31 现场观察指出）。超时上限不变，只提前退出。
# 唯一的例外：关礼包弹窗后等 1200ms（等关闭动画+背景回正再判场景），以及翻页动画 900ms。
param([int]$Pid2 = 0, [int]$Char = 1, [int]$TownTimeoutSec = 90, [switch]$AssumeGold, [switch]$Perf)
$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$ps = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
# 分段计时（2026-10-31 性能体检落地，2026-10-31 晚改 -Perf 开关控制输出）
$T0 = Get-Date
$SubMs = 0; $SubN = 0; $CallN = 0
function TS { if ($Perf) { return " t=$([int]((Get-Date) - $T0).TotalSeconds)s" } return "" }
# 模块化试点（2026-10-31）：probe/popup 同进程调用，省掉每次 0.5~0.9s 的进程启动。
. (Join-Path $PSScriptRoot '_wxcommon.ps1')
. (Join-Path $PSScriptRoot '_wxcore.ps1')

function Invoke-Sub([string]$script, [string[]]$argList) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = & $ps -NoProfile -ExecutionPolicy Bypass -File "$scripts\$script" @argList 2>&1 | ForEach-Object { "$_" }
    $sw.Stop(); $script:SubMs += $sw.ElapsedMilliseconds; $script:SubN++; $script:CallN++
    $r
}
function Get-State {
    # 同进程调用（原为 wxprobe.ps1 子进程 + 正则解析 STATE 行）。异常与探测错误统一回 ERR，语义同旧版。
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try { $r = Invoke-WxProbe -Pid2 $Pid2 } catch { $sw.Stop(); $script:SubMs += $sw.ElapsedMilliseconds; $script:CallN++; return "ERR" }
    $sw.Stop(); $script:SubMs += $sw.ElapsedMilliseconds; $script:CallN++
    if ($r.Err) { return "ERR" }
    return $r.State
}
function Test-OcrTask([string]$task) {
    $out = Invoke-Sub 'wxocr.ps1' @('-Pid2', $Pid2, '-Task', $task)
    $joined = $out -join ' '
    return ($joined -match "OCR=$task=HIT")
}
function Get-PopupInfo {
    # 同进程调用 Invoke-WxPopup（原为 wxpopup.ps1 子进程 + 正则解析）。出错时保持旧默认值 POPUP_UNKNOWN → 走红线停机。
    $i = @{ Cls = 'POPUP_UNKNOWN'; CloseX = 0; CloseY = 0; UncheckX = 0; UncheckY = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try { $r = Invoke-WxPopup -Pid2 $Pid2 } catch { $sw.Stop(); $script:SubMs += $sw.ElapsedMilliseconds; $script:CallN++; return $i }
    $sw.Stop(); $script:SubMs += $sw.ElapsedMilliseconds; $script:CallN++
    if ($r.Err) { return $i }
    $i.Cls = $r.Popup; $i.CloseX = [int]$r.CloseX; $i.CloseY = [int]$r.CloseY
    $i.UncheckX = [int]$r.UncheckX; $i.UncheckY = [int]$r.UncheckY
    return $i
}
function Invoke-Click([string]$steps) {
    Invoke-Sub 'wxclick.ps1' @('-Pid2', $Pid2, '-Steps', $steps) | Out-Null
}

# ---- 阶段1：金弹窗处理（红线分类）----
$st = Get-State
"phase1 start state=$st$(TS)"
if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
# 弹窗优先（2026-10-31 定版：弹窗一律归 wxpopup 判）。礼包弹窗压屏时 probe 只能报 UNKNOWN，
# 必须先关掉再判场景——否则后面 server/charsel OCR 全被弹窗挡住，白等 50 秒才失败。
$pi = Get-PopupInfo
if ($pi.Cls -eq "POPUP_PACK") {
    "phase1 POPUP_PACK -> uncheck/close"
    if ($pi.UncheckX -gt 0) { Invoke-Click "$($pi.UncheckX):$($pi.UncheckY):900"; "phase1 uncheck clicked ($($pi.UncheckX),$($pi.UncheckY))" }
    Invoke-Click "$($pi.CloseX):$($pi.CloseY):1200"
    $st = Get-State
    $pi = Get-PopupInfo
    "phase1 after close state=$st popup=$($pi.Cls)"
}
if ($st -eq "TOWN_PAGE") { "ALREADY_TOWN: 已在主城，重登链不适用（未执行任何点击）"; exit 0 }
if ($st -in @("TOWER_PAGE", "SETTLE_PAGE", "AUTO_ON", "AUTO_OFF")) { "STOP: state=$st 已在游戏内，重登链不适用"; exit 9 }
if ($st -eq "GOLD_DIALOG") {
    "phase1 popup=$($pi.Cls)$(TS)"
    if ($pi.Cls -ne "POPUP_IDLE" -and -not $AssumeGold) {
        "STOP: GOLD_DIALOG 分类=$($pi.Cls)（顶号/涉钱/未知弹窗红线，绝不自动点）"; exit 9
    }
    Invoke-Click "700:513:800"
    "phase1 confirm clicked cls=$($pi.Cls)$(if ($AssumeGold) { ' (AssumeGold)' } else { '' })"
}

# ---- 阶段2：server OCR 轮询等登录页 → 点进入游戏 ----
$loginHit = $false
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    if (Test-OcrTask "server") { $loginHit = $true; break }
    Start-Sleep -Milliseconds 600
}
if ($loginHit) {
    "phase2 login page confirmed (server OCR)$(TS)"
    Invoke-Click "571:527:800"
    "phase2 enter-game clicked$(TS)"
} else {
    "phase2: 30s 未见登录页（可能已在选角页/加载中），继续按后续阶段判定$(TS)"
}

# ---- 阶段3：选角（OCR 确认后委托 wxcharsel 幂等链）----
$charselHit = $false
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    if (Test-OcrTask "charsel") { $charselHit = $true; break }
    Start-Sleep -Milliseconds 600
}
if (-not $charselHit) { "STOP: 20s 内未确认选角页（「选择角色」标题未命中），截图人工核对"; exit 9 }
"phase3 charsel confirmed -> wxcharsel char$Char startgame$(TS)"
$chOut = Invoke-Sub 'wxcharsel.ps1' @('-Char', $Char, '-StartGame', '-Pid2', $Pid2)
$chOut | ForEach-Object { "charsel| $_" }
$chExit = $LASTEXITCODE
"phase3 wxcharsel done$(TS) exit=$chExit"
if ($chExit -ne 0) { "STOP: wxcharsel exit=$chExit"; exit 9 }

# ---- 阶段4：终态轮询（礼包弹窗关闭 / TOWN_PAGE 成功）----
# 2026-10-31 用户定版：弹窗一律归 wxpopup 判（POPUP_PACK），probe 只出场景状态、不再报 NEWBIE_PACK。
# 顺序：先探状态——已是主城直接成功（省一次 OCR 与一次子进程），非主城才查弹窗分类。
$packClosed = 0; $idleReclicked = 0
$deadline = (Get-Date).AddSeconds($TownTimeoutSec)
while ((Get-Date) -lt $deadline) {
    $st = Get-State
    if ($st -eq "TOWN_PAGE") { "RELOGIN_OK state=TOWN_PAGE char=$Char packClosed=$packClosed$(TS)"; if ($Perf) { "perf: calls=$CallN (subproc=$SubN) module_ms=$SubMs" }; exit 0 }
    $pi = Get-PopupInfo
    if ($pi.Cls -eq "POPUP_PACK") {
        if ($packClosed -ge 3) { "STOP: 礼包弹窗红叉已点 3 次仍未清除，截图人工核对"; exit 9 }
        $packClosed++
        "phase4 POPUP_PACK -> uncheck/close attempt=$packClosed$(TS)"
        if ($pi.UncheckX -gt 0) { Invoke-Click "$($pi.UncheckX):$($pi.UncheckY):900" }
        Invoke-Click "$($pi.CloseX):$($pi.CloseY):1200"
        continue
    }
    if ($st -eq "GOLD_DIALOG") {
        if ($idleReclicked -ge 2) { "STOP: 金弹窗反复在屏（分类后仍无法清除），截图人工核对"; exit 9 }
        "phase4 GOLD_DIALOG popup=$($pi.Cls)"
        if ($pi.Cls -eq "POPUP_IDLE") { $idleReclicked++; Invoke-Click "700:513:800"; continue }
        "STOP: GOLD_DIALOG 分类=$($pi.Cls)（红线，绝不自动点）"; exit 9
    }
    Start-Sleep -Milliseconds 1000
}
"STOP: ${TownTimeoutSec}s 内未到 TOWN_PAGE 终态（加载慢/异常弹窗），截图人工核对"; exit 9

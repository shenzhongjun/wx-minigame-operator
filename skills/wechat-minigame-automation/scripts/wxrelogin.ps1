# wxrelogin.ps1 — 组合重登链 v1（2026-10-31，交接文档 §五待办2 落地）
# 流程：金弹窗处理(仅 POPUP_IDLE 自动点 700,513) → server OCR 轮询等登录页 → 点进入游戏(571,527)
#       → charsel OCR 确认 → wxcharsel -Char N -StartGame → 终态轮询：POPUP_PACK 点红叉关闭 /
#       TOWN_PAGE(三探针, v1.1.17) 即成功。B1(town OCR 背景 MISS) 已由三探针根治，本链终态=三探针权威。
# 红线（沿用 wxlogin v1.1.6 固化）：GOLD_DIALOG 先 wxpopup OCR 分类——POPUP_IDLE→自动点确定；
#       其余（顶号/涉钱/未知）停机 exit 9，绝不自动点。-AssumeGold=人工强制放行（透传）。
# 复用单源：wxprobe/wxpopup/wxocr/wxclick/wxcharsel 均子进程调用，本脚本零像素逻辑零坐标卡表
#       （唯一自有动作=红叉 (160,192)，与 coords.md「新手礼包弹窗」行一致；礼包判据 2026-10-31 起来自
#        wxpopup POPUP_PACK，probe 不再判弹窗。本脚本无 dot-source，红叉坐标硬编码与档案同源。）
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File wxrelogin.ps1 [-Pid2 N] [-Char 1] [-TownTimeoutSec 90] [-AssumeGold]
# 退出码：0=RELOGIN_OK（TOWN_PAGE 三探针确认）；9=STOP（红线/超时/异常，人工核对）。
param([int]$Pid2 = 0, [int]$Char = 1, [int]$TownTimeoutSec = 90, [switch]$AssumeGold)
$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$ps = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
# 分段计时（2026-10-31 性能体检，纯输出不影响逻辑，可整段删）
$T0 = Get-Date
$SubMs = 0; $SubN = 0
function Now-S { [int]((Get-Date) - $T0).TotalSeconds }

function Invoke-Sub([string]$script, [string[]]$argList) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = & $ps -NoProfile -ExecutionPolicy Bypass -File "$scripts\$script" @argList 2>&1 | ForEach-Object { "$_" }
    $sw.Stop(); $script:SubMs += $sw.ElapsedMilliseconds; $script:SubN++
    $r
}
function Get-State {
    $out = Invoke-Sub 'wxprobe.ps1' @('-Pid2', $Pid2)
    foreach ($line in $out) { if ($line -match '^STATE=(\w+)') { return $Matches[1] } }
    return "ERR"
}
function Test-OcrTask([string]$task) {
    $out = Invoke-Sub 'wxocr.ps1' @('-Pid2', $Pid2, '-Task', $task)
    $joined = $out -join ' '
    return ($joined -match "OCR=$task=HIT")
}
function Get-PopupClass {
    $out = Invoke-Sub 'wxpopup.ps1' @('-Pid2', $Pid2)
    foreach ($line in $out) { if ("$line" -match 'POPUP=(POPUP_\w+)') { return $Matches[1] } }
    return "POPUP_UNKNOWN"
}
function Invoke-Click([string]$steps) {
    Invoke-Sub 'wxclick.ps1' @('-Pid2', $Pid2, '-Steps', $steps) | Out-Null
}

# ---- 阶段1：金弹窗处理（红线分类）----
$st = Get-State
"phase1 start state=$st t=$(Now-S)s"
if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
# 弹窗优先（2026-10-31 定版：弹窗一律归 wxpopup 判）。礼包弹窗压屏时 probe 只能报 UNKNOWN，
# 必须先关掉再判场景——否则后面 server/charsel OCR 全被弹窗挡住，白等 50 秒才失败。
$cls = Get-PopupClass
if ($cls -eq "POPUP_PACK") {
    "phase1 POPUP_PACK -> close X"
    Invoke-Click "160:192:2500"
    $st = Get-State
    $cls = Get-PopupClass
    "phase1 after close state=$st popup=$cls"
}
if ($st -in @("TOWER_PAGE", "SETTLE_PAGE", "AUTO_ON", "AUTO_OFF")) { "STOP: state=$st 已在游戏内，重登链不适用"; exit 9 }
if ($st -eq "GOLD_DIALOG") {
    "phase1 popup=$cls t=$(Now-S)s"
    if ($cls -ne "POPUP_IDLE" -and -not $AssumeGold) {
        "STOP: GOLD_DIALOG 分类=$cls（顶号/涉钱/未知弹窗红线，绝不自动点）"; exit 9
    }
    Invoke-Click "700:513:4000"
    "phase1 idle-confirm clicked"
}

# ---- 阶段2：server OCR 轮询等登录页 → 点进入游戏 ----
$loginHit = $false
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    if (Test-OcrTask "server") { $loginHit = $true; break }
    Start-Sleep -Seconds 2
}
if ($loginHit) {
    "phase2 login page confirmed (server OCR) t=$(Now-S)s"
    Invoke-Click "571:527:5000"
    "phase2 enter-game clicked t=$(Now-S)s"
} else {
    "phase2: 30s 未见登录页（可能已在选角页/加载中），继续按后续阶段判定 t=$(Now-S)s"
}

# ---- 阶段3：选角（OCR 确认后委托 wxcharsel 幂等链）----
$charselHit = $false
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    if (Test-OcrTask "charsel") { $charselHit = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $charselHit) { "STOP: 20s 内未确认选角页（「选择角色」标题未命中），截图人工核对"; exit 9 }
"phase3 charsel confirmed -> wxcharsel char$Char startgame t=$(Now-S)s"
$chOut = Invoke-Sub 'wxcharsel.ps1' @('-Char', $Char, '-StartGame', '-Pid2', $Pid2)
$chOut | ForEach-Object { "charsel| $_" }
$chExit = $LASTEXITCODE
"phase3 wxcharsel done t=$(Now-S)s exit=$chExit"
if ($chExit -ne 0) { "STOP: wxcharsel exit=$chExit"; exit 9 }

# ---- 阶段4：终态轮询（礼包弹窗关闭 / TOWN_PAGE 成功）----
# 2026-10-31 用户定版：弹窗一律归 wxpopup 判（POPUP_PACK），probe 只出场景状态、不再报 NEWBIE_PACK。
# 顺序：先探状态——已是主城直接成功（省一次 OCR 与一次子进程），非主城才查弹窗分类。
$packClosed = 0; $idleReclicked = 0
$deadline = (Get-Date).AddSeconds($TownTimeoutSec)
while ((Get-Date) -lt $deadline) {
    $st = Get-State
    if ($st -eq "TOWN_PAGE") { "RELOGIN_OK state=TOWN_PAGE char=$Char packClosed=$packClosed t=$(Now-S)s"; "perf: subprocess=$SubN calls / $([int]($SubMs/1000))s"; exit 0 }
    $cls = Get-PopupClass
    if ($cls -eq "POPUP_PACK") {
        if ($packClosed -ge 3) { "STOP: 礼包红叉已点 3 次仍未清除，截图人工核对"; exit 9 }
        $packClosed++
        "phase4 POPUP_PACK -> close X attempt=$packClosed"
        Invoke-Click "160:192:2500"
        continue
    }
    if ($st -eq "GOLD_DIALOG") {
        if ($idleReclicked -ge 2) { "STOP: 金弹窗反复在屏（分类后仍无法清除），截图人工核对"; exit 9 }
        "phase4 GOLD_DIALOG popup=$cls"
        if ($cls -eq "POPUP_IDLE") { $idleReclicked++; Invoke-Click "700:513:4000"; continue }
        "STOP: GOLD_DIALOG 分类=$cls（红线，绝不自动点）"; exit 9
    }
    Start-Sleep -Seconds 3
}
"STOP: ${TownTimeoutSec}s 内未到 TOWN_PAGE 终态（加载慢/异常弹窗），截图人工核对"; exit 9

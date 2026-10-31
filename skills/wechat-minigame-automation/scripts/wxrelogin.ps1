# wxrelogin.ps1 — 组合重登链 v1（2026-10-31，交接文档 §五待办2 落地）
# 流程：金弹窗处理(仅 POPUP_IDLE 自动点 700,513) → server OCR 轮询等登录页 → 点进入游戏(571,527)
#       → charsel OCR 确认 → wxcharsel -Char N -StartGame → 终态轮询：NEWBIE_PACK 点红叉关闭 /
#       TOWN_PAGE(三探针, v1.1.17) 即成功。B1(town OCR 背景 MISS) 已由三探针根治，本链终态=三探针权威。
# 红线（沿用 wxlogin v1.1.6 固化）：GOLD_DIALOG 先 wxpopup OCR 分类——POPUP_IDLE→自动点确定；
#       其余（顶号/涉钱/未知）停机 exit 9，绝不自动点。-AssumeGold=人工强制放行（透传）。
# 复用单源：wxprobe/wxpopup/wxocr/wxclick/wxcharsel 均子进程调用，本脚本零像素逻辑零坐标卡表
#       （唯一自有动作=红叉 (160,192)，与 coords.md「新手礼包弹窗」行一致；判据来自 wxprobe NEWBIE_PACK 双条件）。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File wxrelogin.ps1 [-Pid2 N] [-Char 1] [-TownTimeoutSec 90] [-AssumeGold]
# 退出码：0=RELOGIN_OK（TOWN_PAGE 三探针确认）；9=STOP（红线/超时/异常，人工核对）。
param([int]$Pid2 = 0, [int]$Char = 1, [int]$TownTimeoutSec = 90, [switch]$AssumeGold)
$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$ps = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

function Invoke-Sub([string]$script, [string[]]$argList) {
    & $ps -NoProfile -ExecutionPolicy Bypass -File "$scripts\$script" @argList 2>&1 | ForEach-Object { "$_" }
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
"phase1 start state=$st"
if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
if ($st -in @("TOWER_PAGE", "SETTLE_PAGE", "AUTO_ON", "AUTO_OFF")) { "STOP: state=$st 已在游戏内，重登链不适用"; exit 9 }
if ($st -eq "GOLD_DIALOG") {
    $cls = Get-PopupClass
    "phase1 popup=$cls"
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
    "phase2 login page confirmed (server OCR)"
    Invoke-Click "571:527:5000"
} else {
    "phase2: 30s 未见登录页（可能已在选角页/加载中），继续按后续阶段判定"
}

# ---- 阶段3：选角（OCR 确认后委托 wxcharsel 幂等链）----
$charselHit = $false
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    if (Test-OcrTask "charsel") { $charselHit = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $charselHit) { "STOP: 20s 内未确认选角页（「选择角色」标题未命中），截图人工核对"; exit 9 }
"phase3 charsel confirmed -> wxcharsel char$Char startgame"
$chOut = Invoke-Sub 'wxcharsel.ps1' @('-Char', $Char, '-StartGame', '-Pid2', $Pid2)
$chOut | ForEach-Object { "charsel| $_" }
$chExit = $LASTEXITCODE
if ($chExit -ne 0) { "STOP: wxcharsel exit=$chExit"; exit 9 }

# ---- 阶段4：终态轮询（NEWBIE_PACK 关闭 / TOWN_PAGE 成功）----
$packClosed = 0; $idleReclicked = 0
$deadline = (Get-Date).AddSeconds($TownTimeoutSec)
while ((Get-Date) -lt $deadline) {
    $st = Get-State
    if ($st -eq "TOWN_PAGE") { "RELOGIN_OK state=TOWN_PAGE char=$Char packClosed=$packClosed"; exit 0 }
    if ($st -eq "NEWBIE_PACK") {
        if ($packClosed -ge 3) { "STOP: 礼包红叉已点 3 次仍未清除，截图人工核对"; exit 9 }
        $packClosed++
        "phase4 NEWBIE_PACK -> close X attempt=$packClosed"
        Invoke-Click "160:192:2500"
        continue
    }
    if ($st -eq "GOLD_DIALOG") {
        if ($idleReclicked -ge 2) { "STOP: 金弹窗反复在屏（分类后仍无法清除），截图人工核对"; exit 9 }
        $cls = Get-PopupClass
        "phase4 GOLD_DIALOG popup=$cls"
        if ($cls -eq "POPUP_IDLE") { $idleReclicked++; Invoke-Click "700:513:4000"; continue }
        "STOP: GOLD_DIALOG 分类=$cls（红线，绝不自动点）"; exit 9
    }
    Start-Sleep -Seconds 3
}
"STOP: ${TownTimeoutSec}s 内未到 TOWN_PAGE 终态（加载慢/异常弹窗），截图人工核对"; exit 9

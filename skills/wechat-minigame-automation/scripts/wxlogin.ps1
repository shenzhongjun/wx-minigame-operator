param([int]$Char = 1, [int]$Pid2 = 0, [switch]$AssumeGold)
# 固化登录链（2026-10-25 升级：接入 wxprobe CHAR1-6 金框检测，选角验证全自动）
# 流程：金色弹窗确定(700,513) → 登录页进入游戏(571,527) → 探针确认 CHAR* → 点目标角色卡
#       → 探针确认金框在目标卡 → 开始游戏(1018,634)
# 红线：GOLD_DIALOG 可能是顶号弹窗「账号在其他设备登录」（绝不自动点）——
#       默认停机退出，请示用户；用户授权后加 -AssumeGold 重跑才点确定。
# 角色卡坐标：1(138,342) 2(421,342) 3(697,342) 4(971,342) 5(139,536) 6(414,536)
$scripts = $PSScriptRoot
function Get-State {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxprobe.ps1" -Pid2 $Pid2 2>&1
    foreach ($line in $out) { if ($line -match '^STATE=(\w+)') { return $Matches[1] } }
    return "ERR"
}
function Invoke-Click([string]$steps) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxclick.ps1" -Pid2 $Pid2 -Steps $steps 2>&1 | ForEach-Object { "$_" }
}
$card = @{ 1 = "138:342"; 2 = "421:342"; 3 = "697:342"; 4 = "971:342"; 5 = "139:536"; 6 = "414:536" }
if (-not $card.ContainsKey($Char)) { "ERR: Char must be 1-6"; exit 1 }

$st = Get-State
"start state=$st"
if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
if ($st -eq "GOLD_DIALOG") {
    if (-not $AssumeGold) {
        "STOP: GOLD_DIALOG（挂机弹窗/顶号弹窗/登录页金钮需区分）。若目验为挂机或已获用户授权，加 -AssumeGold 重跑"
        exit 9
    }
    Invoke-Click "700:513:4000"
    $st = Get-State
    "after gold-confirm state=$st"
    if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
}
if ($st -eq "LOGIN_PAGE") {
    Invoke-Click "571:527:5000"
    $st = Get-State
    "after login state=$st"
    if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
}
if ($st -notlike "CHAR*") {
    "STOP: state=$st 非选角页（期望 CHAR*），截图人工核对"; exit 9
}
if ($st -ne "CHAR$Char") {
    # 金框不在目标角色上（重登默认选中第1个）→ 点目标卡后探针复验
    Invoke-Click "$($card[$Char]):1500"
    $st = Get-State
    "after char click state=$st"
    if ($st -ne "CHAR$Char") { "STOP: 金框未落到角色$Char（state=$st），截图人工核对"; exit 9 }
}
"char$Char selected verified"
Invoke-Click "1018:634:5000"
$st = Get-State
"login chain done (final state=$st)；主城可能报 GOLD_DIALOG(金图标误报)/UNKNOWN，异常请截图核对"

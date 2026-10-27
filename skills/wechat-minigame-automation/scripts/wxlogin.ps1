param([int]$Pid2 = 0, [switch]$AssumeGold)
# 固化登录链 v3（2026-10-27 用户定版拆分：登录链归 wxlogin，选角归 wxcharsel）
# 流程：金色弹窗处理(700,513) → 登录页进入游戏(571,527) → OCR 验证选角页(「选择角色」标题) → 到此即止
# 角色选择请跑 wxcharsel.ps1 -Char N [-StartGame]（卡表单源在 wxcharsel，判屏切屏幂等双击齐全）
# 历史教训：本脚本旧版卡表 5/6=(139/414,536) 系滚动单页时代旧值，(139,536) 实为翻页按钮——
#   -Char 5 会翻页而非选卡，该路径从未被实测（冒烟件自带正确卡表不依赖本脚本）。v1.1.8 起删除卡表。
# 验证哲学：选角页身份=wxocr -Task charsel（OCR「选择角色」标题，粗字形抗缩放）；
#   不再做金框像素回读（细描边小窗混色不可靠，2026-10-26 退役）；点卡操作幂等（双击无副作用，纯冗余兜底）。
#   ⚠️ 残余风险（用户知情接受）：点击未命中目标卡热区且当前选中≠目标角色 → 带错角色进游戏；
#   （2026-10-27 用户定版：链路健壮，身份确认永久不做，勿再提验证方案。）
# 红线（v1.1.6 更新，用户 2026-10-27 裁决固化）：GOLD_DIALOG 先 wxpopup OCR 分类——
#       POPUP_IDLE（挂机「重新登录」）→ 自动点确定 (700,513) 重登，两轮实战零异常后固化；
#       其余类别（顶号「其他设备」/扩展券/正文读不出）红线不变：停机请示，绝不自动点。
#       -AssumeGold 保留为人工强制放行开关（跳过分类直接点）。
$scripts = $PSScriptRoot
function Get-State {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxprobe.ps1" -Pid2 $Pid2 2>&1
    foreach ($line in $out) { if ($line -match '^STATE=(\w+)') { return $Matches[1] } }
    return "ERR"
}
function Invoke-Click([string]$steps) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxclick.ps1" -Pid2 $Pid2 -Steps $steps 2>&1 | ForEach-Object { "$_" }
}
function Test-CharSel {
    # OCR 验证选角页（转场/加载容忍：15s 轮询）
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxocr.ps1" -Pid2 $Pid2 -Task charsel 2>&1
        $joined = ($out | ForEach-Object { "$_" }) -join ' '
        if ($joined -match 'OCR=charsel=HIT') { return $true }
        if ($joined -match 'ERR:') { return $false }
        Start-Sleep -Seconds 2
    }
    return $false
}
function Test-TownOcr {
    # 主城身份权威判定（2026-10-27：wxprobe TOWN_PAGE 退役，OCR 为准）
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxocr.ps1" -Pid2 $Pid2 -Task town 2>&1
    $joined = ($out | ForEach-Object { "$_" }) -join ' '
    return ($joined -match 'OCR=town=HIT')
}
function Test-LoginOcr {
    # 登录页身份权威判定（2026-10-27 用户定版：探针退役，OCR 为准，唯一判据=server 任务）
    # 「进入游戏」为风格化美术字 OCR 读不动，用户裁定不设任务
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxocr.ps1" -Pid2 $Pid2 -Task server 2>&1
    $joined = ($out | ForEach-Object { "$_" }) -join ' '
    return ($joined -match 'OCR=server=HIT')
}
function Get-PopupClass {
    # v1.1.6：GOLD_DIALOG 弹窗 OCR 分类（wxpopup v2），挂机类自动放行的判据源
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxpopup.ps1" -Pid2 $Pid2 2>&1
    foreach ($line in $out) { if ("$line" -match 'POPUP=(POPUP_\w+)') { return $Matches[1] } }
    return "POPUP_UNKNOWN"
}
$st = Get-State
"start state=$st"
if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
if ($st -eq "GOLD_DIALOG") {
    $cls = Get-PopupClass
    "popup classified=$cls"
    # v1.1.6 固化：挂机弹窗（POPUP_IDLE）自动点确定；其余红线停机。-AssumeGold=人工强制放行
    if ($cls -ne "POPUP_IDLE" -and -not $AssumeGold) {
        "STOP: GOLD_DIALOG 分类=$cls（顶号/涉钱/未知弹窗红线，绝不自动点）。确认安全可加 -AssumeGold 重跑"
        exit 9
    }
    Invoke-Click "700:513:4000"
    $st = Get-State
    "after gold-confirm state=$st"
    if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
}
if (Test-LoginOcr) {
    Invoke-Click "571:527:5000"
    $st = Get-State
    "after login state=$st"
    if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
}
if ($st -in @("TOWER_PAGE", "SETTLE_PAGE", "AUTO_ON", "AUTO_OFF")) {
    "STOP: state=$st 疑似已在游戏内，重登链不适用，人工核对"; exit 9
}
if (Test-TownOcr) {
    "STOP: 已在主城（wxocr town HIT），重登链不适用，人工核对"; exit 9
}
if (-not (Test-CharSel)) {
    "STOP: OCR 15s 内未确认选角页（「选择角色」标题未命中），截图人工核对 (last state=$st)"; exit 9
}
"charsel confirmed by OCR —— 登录链到此即止；角色选择请跑 wxcharsel.ps1 -Char N [-StartGame]"

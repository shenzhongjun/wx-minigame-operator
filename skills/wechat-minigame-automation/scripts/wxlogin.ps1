param([int]$Char = 1, [int]$Pid2 = 0, [switch]$AssumeGold)
# 固化登录链 v2（2026-10-26 OCR 优先改造，用户定版：验证一律 OCR 优先）
# 流程：金色弹窗处理(700,513) → 登录页进入游戏(571,527) → OCR 验证选角页(「选择角色」标题)
#       → 双击目标角色卡(幂等，防点击被吞) → 开始游戏(1018,634)
# 验证哲学：选角页身份=wxocr -Task charsel（OCR「选择角色」标题，粗字形抗缩放）；
#   不再做金框像素回读（细描边小窗混色不可靠，2026-10-26 退役）；点卡操作幂等，双击兜住静默失败。
#   ⚠️ 残余风险（用户知情接受）：极端情况下两次点击均被吞且当前选中≠目标角色 → 带错角色进游戏；
#   双吞无实战前科；必要时未来可用 wxocr 读卡片角色名做二次验证。
# 红线（v1.1.6 更新，用户 2026-10-27 裁决固化）：GOLD_DIALOG 先 wxpopup OCR 分类——
#       POPUP_IDLE（挂机「重新登录」）→ 自动点确定 (700,513) 重登，两轮实战零异常后固化；
#       其余类别（顶号「其他设备」/扩展券/正文读不出）红线不变：停机请示，绝不自动点。
#       -AssumeGold 保留为人工强制放行开关（跳过分类直接点）。
# 角色卡坐标（未滚动态直点）：1(138,342) 2(421,342) 3(704,340) 4(987,340)（3/4 于 2026-10-26 实测重标：按卡1→2 间距 283 等距外推） 5(139,536) 6(414,536)
# 选角页共三屏：默认第一屏(1-4)；点 (139,536) 切第二屏(5-8，行 y=370)；7/8 槽位=锁图标严禁点击（建角色弹窗红线）。详见 coords.md
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
$card = @{ 1 = "138:342"; 2 = "421:342"; 3 = "704:340"; 4 = "987:340"; 5 = "139:536"; 6 = "414:536" }
if (-not $card.ContainsKey($Char)) { "ERR: Char must be 1-6"; exit 1 }

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
"charsel confirmed by OCR"
# 双击目标卡（幂等；无金框回读——用户定版，残余风险见头部注释）
Invoke-Click "$($card[$Char]):1500"
Invoke-Click "$($card[$Char]):1500"
"char$Char card clicked (double, idempotent)"
Invoke-Click "1018:634:5000"
$st = Get-State
$townHit = if (Test-TownOcr) { "HIT" } else { "MISS" }
"login chain done (final state=$st town_ocr=$townHit)；主城可能报 GOLD_DIALOG(金图标误报)/UNKNOWN，异常请截图核对"

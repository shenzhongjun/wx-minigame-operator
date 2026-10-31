param([int]$Char = 0, [int]$Pid2 = 0, [switch]$StartGame)
# 选角专职脚本（2026-10-27 用户定版拆分：登录链归 wxrelogin，选角归 wxcharsel，卡表单源在此）
# 流程：状态守卫 → 起始态自适应进选角页（主城点「选角」/已在选角页直进，其余 STOP）
#       → scr1w/scr2w 判屏 → 按需切屏 (139,536)/(138,180) 复核 → 幂等双击目标卡
#       → -StartGame 时点开始游戏(1018,634) 并 town OCR 终态确认；默认停在选角页
# 卡表（唯一权威，坐标语言 1138x708）：
#   1(138,342) 2(421,342) 3(704,340) 4(987,340)   第一屏
#   5(138,370) 6(421,370) 7(704,370)               第二屏（行 y=370，比第一屏低 28px）
#   8(987,370) 未创建=锁槽，点了会弹「创建角色」弹窗 → 暂不开放（建号后加表项并同步 coords 红线）
#   ⚠️ 7/8 槽位=锁图标红线严禁点击（点=建角色弹窗）
#   ⚠️ (139,536)=翻页按钮≠卡5（2026-10-27 定论，旧档案「直点选5/6」已证伪，见 coords.md）
# 判据：选角页=wxocr charsel；屏号=scr1w/scr2w（kw+kw2 合并任意3字命中）；主城=wxocr town。
# OCR 判不了选中态（金框描边）——选卡靠幂等双击（用户定版，勿再提选中态验证）。
# 前台/最小窗口守卫由 wxclick/wxocr 内置（Confirm-WxForeground / Test-WxMinClientW）。
$scripts = $PSScriptRoot

if ($Char -lt 1 -or $Char -gt 7) { "ERR: Char must be 1-7（8 号槽未创建，开放前会点出创建角色弹窗）"; exit 1 }
$card = @{ 1 = "138:342"; 2 = "421:342"; 3 = "704:340"; 4 = "987:340"; 5 = "138:370"; 6 = "421:370"; 7 = "704:370" }
$targetScreen = if ($Char -le 4) { 1 } else { 2 }

function Invoke-Click([string]$steps) {
    & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxclick.ps1" -Pid2 $Pid2 -Steps $steps 2>&1 | ForEach-Object { "$_" }
}
function Test-OcrTask([string]$task) {
    $out = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxocr.ps1" -Pid2 $Pid2 -Task $task 2>&1
    $joined = ($out | ForEach-Object { "$_" }) -join ' '
    return ($joined -match "OCR=$task=HIT")
}
function Get-ScreenNo {
    if (Test-OcrTask "scr1w") { return 1 }
    if (Test-OcrTask "scr2w") { return 2 }
    return 0
}
function Enter-Charsel {
    # 点选角 (196,179) -> charsel OCR 确认，未中再点（点击落空=过渡未就绪/热区偏差，2026-10-27 定版口径）
    for ($a = 1; $a -le 3; $a++) {
        $null = Invoke-Click "196:179:3000"
        if (Test-OcrTask "charsel") { Write-Host "enter-charsel attempt=$a HIT"; return $true }
        Write-Host "enter-charsel attempt=$a MISS, retry"
    }
    return $false
}
function Switch-Screen([int]$need) {
    for ($a = 1; $a -le 3; $a++) {
        if ($need -eq 2) { $null = Invoke-Click "139:536:600" }   # 切第二屏
        else            { $null = Invoke-Click "138:180:600" }   # 回第一屏
        Start-Sleep -Milliseconds 900        # 等翻页动画落定再 OCR
        $s = Get-ScreenNo
        if ($s -eq $need) { Write-Host "switch->scr$need attempt=$a ocr=HIT"; return $true }
    }
    return $false
}

# ---- 起始态守卫 ----
$probe = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxprobe.ps1" -Pid2 $Pid2 2>&1
$st = "ERR"
foreach ($line in $probe) { if ("$line" -match '^STATE=(\w+)') { $st = $Matches[1]; break } }
"start state=$st"
if ($st -eq "ERR") { "STOP: probe error"; exit 9 }
if ($st -eq "GOLD_DIALOG") { "STOP: GOLD_DIALOG 弹窗在场，先走 wxrelogin.ps1 处理（弹窗分类红线在重登链）"; exit 9 }
if ($st -in @("TOWER_PAGE", "SETTLE_PAGE", "AUTO_ON", "AUTO_OFF")) { "STOP: 已在游戏内(state=$st)，选角链不适用"; exit 9 }

# ---- 进选角页（起始态自适应）----
if (-not (Test-OcrTask "charsel")) {
    if (Test-OcrTask "town") {
        if (-not (Enter-Charsel)) { "STOP: 点选角 3 次未确认（charsel OCR 未命中），截图人工核对"; exit 9 }
    } else {
        "STOP: 不在主城也不在选角页(state=$st)，先 wxrelogin 或人工核对"; exit 9
    }
}
"charsel confirmed"

# ---- 判屏 + 切屏（选角页进入时停在「上次选中角色所在屏」，实证机制 2026-10-27）----
$cur = Get-ScreenNo
"current screen=$cur target=scr$targetScreen"
if ($cur -eq 0) { "STOP: scr1w/scr2w 均未命中（屏号判定失败），截图人工核对"; exit 9 }
if ($cur -ne $targetScreen) {
    if (-not (Switch-Screen $targetScreen)) { "STOP: 切屏 3 次复核未中(target=scr$targetScreen)"; exit 9 }
}

# ---- 幂等双击选卡（无选中态回读——用户定版）----
Invoke-Click "$($card[$Char]):1500"
Invoke-Click "$($card[$Char]):1500"
"char$Char card clicked (double, idempotent) at $($card[$Char])"

# ---- 出口：默认停选角页；-StartGame 进游戏 ----
if (-not $StartGame) {
    "charsel done (stopped at charsel page, no start)；进游戏请加 -StartGame"
    exit 0
}
Invoke-Click "1018:634:800"
$deadline = (Get-Date).AddSeconds(15)
$townHit = $false
while ((Get-Date) -lt $deadline) {
    if (Test-OcrTask "town") { $townHit = $true; break }
    Start-Sleep -Milliseconds 600
}
if ($townHit) { "START ok: town_ocr=HIT (char$Char in town)" }
else { "WARN: 开始游戏后 15s town 未确认（可能加载慢/弹窗），截图人工核对" }

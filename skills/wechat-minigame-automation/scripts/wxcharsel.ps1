param([int]$Char = 0, [int]$Pid2 = 0, [switch]$StartGame, [switch]$Perf, [switch]$SkipGuard)
# 选角专职脚本（2026-10-27 用户定版拆分；2026-10-31 晚重构等待策略）
# 流程：状态守卫 → 起始态自适应进选角页（主城点「选角」/已在选角页直进，其余 STOP）
#       → scr1w/scr2w 判屏 → 按需切屏 (139,536)/(138,180) 复核 → 幂等双击目标卡
#       → -StartGame 时点开始游戏(1018,634) 并 town OCR 终态确认；默认停在选角页
# 卡表（唯一权威，坐标语言 1138x708）：
#   1(138,342) 2(421,342) 3(704,340) 4(987,340)   第一屏
#   5(138,370) 6(421,370) 7(704,370)               第二屏（行 y=370，比第一屏低 28px）
#   8(987,370) 未创建=锁槽，点了会弹「创建角色」弹窗 → 暂不开放（建号后加表项并同步 coords 红线）
#   ⚠️ (139,536)=翻页按钮≠卡5（2026-10-27 定论，旧档案「直点选5/6」已证伪，见 coords.md）
# 判据：选角页=wxocr charsel；屏号=scr1w/scr2w（kw+kw2 合并任意3字命中）；主城=wxocr town。
# OCR 判不了选中态（金框描边）——选卡靠幂等双击（用户定版，勿再提选中态验证）。
# 前台/最小窗口守卫由 wxclick/wxocr 内置（Confirm-WxForeground / Test-WxMinClientW）。
# ⚠️ 等待策略（2026-10-31 晚，用户现场观察驱动）：点击后只等 400~600ms 让点击生效，随后一律
#    **轮询 OCR 判定就绪即走**，禁止再硬等固定秒数。原「点选角等 3s / 切屏后等 0.9s 再串行测两屏 /
#    双击各等 1.5s」是选角段 34s 的主要来源（用户原话：点进游戏后停半天才切屏、切完又过好几秒才点角色）。
# -Perf：输出各段累计计时（t=Ns），用于定位慢在哪一步；默认关，不影响逻辑。
$scripts = $PSScriptRoot
# 同进程模块库（2026-10-31 晚）：OCR 引擎在进程内缓存，本脚本 4 次 OCR 从各约 3s 降到首次 1s + 后续 0.25s。
. (Join-Path $scripts '_wxcommon.ps1')
. (Join-Path $scripts '_wxcore.ps1')
$T0 = Get-Date
function TS { if ($Perf) { return " t=$([int]((Get-Date) - $T0).TotalSeconds)s" } return "" }

if ($Char -lt 1 -or $Char -gt 7) { "ERR: Char must be 1-7（8 号槽未创建，开放前会点出创建角色弹窗）"; exit 1 }
$card = @{ 1 = "138:342"; 2 = "421:342"; 3 = "704:340"; 4 = "987:340"; 5 = "138:370"; 6 = "421:370"; 7 = "704:370" }
$targetScreen = if ($Char -le 4) { 1 } else { 2 }

function Invoke-Click([string]$steps) {
    & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxclick.ps1" -Pid2 $Pid2 -Steps $steps 2>&1 | ForEach-Object { "$_" }
}
function Test-OcrTask([string]$task) {
    # 同进程调用（原为 wxocr.ps1 子进程）；引擎缓存后每次约 0.25s
    try { $o = Invoke-WxOcr -Pid2 $Pid2 -Task $task } catch { return $false }
    if ($o.Err) { return $false }
    return [bool]$o.Hit
}
# 屏号判定。$prefer 指定先测哪一屏——切屏后目标已知，先测目标可省掉一次必然 MISS 的 OCR（约 1.5s）。
function Get-ScreenNo([int]$prefer = 0) {
    if ($prefer -eq 2) {
        if (Test-OcrTask "scr2w") { return 2 }
        if (Test-OcrTask "scr1w") { return 1 }
        return 0
    }
    if ($prefer -eq 1) {
        if (Test-OcrTask "scr1w") { return 1 }
        if (Test-OcrTask "scr2w") { return 2 }
        return 0
    }
    if (Test-OcrTask "scr1w") { return 1 }
    if (Test-OcrTask "scr2w") { return 2 }
    return 0
}
function Enter-Charsel {
    # 点选角 (196,179) -> 轮询 charsel OCR，命中即走（原为点后硬等 3s 再判）
    for ($a = 1; $a -le 3; $a++) {
        $null = Invoke-Click "196:179:600"
        $deadline = (Get-Date).AddSeconds(4)
        while ((Get-Date) -lt $deadline) {
            if (Test-OcrTask "charsel") { Write-Host "enter-charsel attempt=$a HIT$(TS)"; return $true }
        }
        Write-Host "enter-charsel attempt=$a MISS, retry$(TS)"
    }
    return $false
}
function Switch-Screen([int]$need) {
    $task = if ($need -eq 2) { "scr2w" } else { "scr1w" }
    for ($a = 1; $a -le 3; $a++) {
        if ($need -eq 2) { $null = Invoke-Click "139:536:400" }   # 切第二屏
        else { $null = Invoke-Click "138:180:400" }               # 回第一屏
        # 轮询目标屏：翻页动画约 0.5s，OCR 本身约 1.5s/轮，天然覆盖动画时间，不再硬等 900ms
        $deadline = (Get-Date).AddSeconds(6)
        while ((Get-Date) -lt $deadline) {
            if (Test-OcrTask $task) { Write-Host "switch->scr$need attempt=$a ocr=HIT$(TS)"; return $true }
        }
    }
    return $false
}

# ---- 起始态守卫（-SkipGuard 时整段跳过：调用方 wxrelogin 已用 charsel OCR 确认在选角页，
#      再 probe + OCR 复核一遍是重复开销，实测白花 5s）----
if ($SkipGuard) {
    "guard skipped (caller confirmed charsel page)$(TS)"
} else {
    # 同进程 probe（原为子进程），异常/错误统一回 ERR，语义同旧版
    $pr = $null
    try { $pr = Invoke-WxProbe -Pid2 $Pid2 } catch { }
    $st = if ($null -eq $pr -or $pr.Err) { "ERR" } else { $pr.State }
    "start state=$st$(TS)"
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
    "charsel confirmed$(TS)"
}

# ---- 判屏 + 切屏（选角页进入时停在「上次选中角色所在屏」，实证机制 2026-10-27）----
$cur = Get-ScreenNo
"current screen=$cur target=scr$targetScreen$(TS)"
if ($cur -eq 0) { "STOP: scr1w/scr2w 均未命中（屏号判定失败），截图人工核对"; exit 9 }
if ($cur -ne $targetScreen) {
    if (-not (Switch-Screen $targetScreen)) { "STOP: 切屏 3 次复核未中(target=scr$targetScreen)"; exit 9 }
}

# ---- 幂等双击选卡（无选中态回读——用户定版）----
# 两次独立点击各等 600ms（原 1500ms）：目的只是确保「选中已生效 + 不被识别成误触」，用户实测
# 点完角色后进游戏本就很快，无需每次等 1.5s。合并成一次 wxclick 多步调用，省一次子进程启动。
Invoke-Click "$($card[$Char]):600;$($card[$Char]):600"
"char$Char card clicked (double, idempotent) at $($card[$Char])$(TS)"

# ---- 出口：默认停选角页；-StartGame 进游戏 ----
if (-not $StartGame) {
    "charsel done (stopped at charsel page, no start)；进游戏请加 -StartGame"
    exit 0
}
Invoke-Click "1018:634:600"
$deadline = (Get-Date).AddSeconds(15)
$townHit = $false
while ((Get-Date) -lt $deadline) {
    if (Test-OcrTask "town") { $townHit = $true; break }
    Start-Sleep -Milliseconds 500
}
if ($townHit) { "START ok: town_ocr=HIT (char$Char in town)$(TS)" }
else { "WARN: 开始游戏后 15s town 未确认（可能加载慢/弹窗），截图人工核对$(TS)" }

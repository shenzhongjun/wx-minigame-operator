param([int]$Rounds = 1, [int]$Pid2 = 0, [int]$RetryX = 936, [int]$RetryY = 269, [int]$SettleWaitSec = 90, [int]$EnterWaitSec = 25, [switch]$AutoRetry)
# 固化刷本循环（2026-10-24 新增，替代 wxfarm 的通用扫描方案，语法0错误未实战）
# 思路：不再扫描按钮位置——结算「再来一次」用固定坐标（圣殿两行布局实测 (936,269)），
#       每步用 wxprobe 验证状态，异常即停。依赖 wxprobe/wxclick-personal 同目录。
# 流程/轮：等结算 → 点再来一次 → 验证离场 → (AUTO_OFF 时 gated 开自动) → 等下一结算
# 退出码：0=完成/重试失败  2=结算等待超时  5=体力弹窗  6=金色弹窗(复活/挂机/登录)  3=自动战斗确保失败
$scripts = $PSScriptRoot
# -AutoRetry（2026-10-25 新增）：每轮点击前自动扫描结算暗红按钮位置（复用 wxfarm 扫描带算法），
#   替代人工按副本/布局传 RetryX/Y；扫描失败回退固定坐标。扫描带 BX=915±38, y225-445。
$script:AutoRetryReady = $false
if ($AutoRetry) {
    . (Join-Path $PSScriptRoot '_wxcommon.ps1')
    $grindHwnd = Find-GameWindow -Pid2 $Pid2
    if ($grindHwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $script:grindGeo = Get-ClientGeometry $grindHwnd
    $script:AutoRetryReady = $true
}
function Find-RetryY {
    if (-not $script:AutoRetryReady) { return -1 }
    $bx = 915; $y0 = 225; $scanH = 220; $hw = 38
    $bmp = New-Object System.Drawing.Bitmap (2 * $hw + 1), $scanH
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(($script:grindGeo.OX + $bx - $hw), ($script:grindGeo.OY + $y0), 0, 0, (New-Object System.Drawing.Size (2 * $hw + 1), $scanH))
    $g.Dispose()
    $hits = New-Object bool[] $scanH
    for ($i = 0; $i -lt $scanH; $i++) {
        $n = 0
        foreach ($dx in @(-25, 0, 25)) {
            $c = $bmp.GetPixel($hw + $dx, $i)
            if ($c.R -gt 100 -and ($c.R - $c.B) -gt 50 -and $c.G -gt 22 -and $c.G -lt 78) { $n++ }
        }
        $hits[$i] = ($n -ge 2)
    }
    $bmp.Dispose()
    $i = 0
    while ($i -lt $scanH) {
        if (-not $hits[$i]) { $i++; continue }
        $s = $i; $e = $i; $gap = 0
        $j = $i + 1
        while ($j -lt $scanH) {
            if ($hits[$j]) { $e = $j; $gap = 0 }
            else { $gap++; if ($gap -gt 6) { break } }
            $j++
        }
        if (($e - $s + 1) -ge 10) { return ($y0 + $s + 20) }
        $i = $e + 1
    }
    return -1
}
function Resolve-RetryCoords {
    if ($script:AutoRetryReady) {
        $fy = Find-RetryY
        if ($fy -ge 0) { return "915,$fy(auto)" }
        Write-Host "retry autoscan failed, fallback fixed ($RetryX,$RetryY)"
    }
    return "$RetryX,$RetryY"
}
function Invoke-Probe {
    param([switch]$Quick)
    $q = if ($Quick) { "-Quick" } else { "" }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxprobe-personal.ps1" -Pid2 $Pid2 @q 2>&1
    $state = "ERR"
    foreach ($line in $out) { if ($line -match '^STATE=(\w+)') { $state = $Matches[1] } }
    return $state
}
function Invoke-Poke {
    # 轮盘保活戳（用户方案：左下角轮盘任何画面绝对安全——用户在玩时戳一下也无妨，无需探测）
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxpoke-personal.ps1" -Pid2 $Pid2 2>&1 | Select-Object -Last 2
}
# 120s 节流（用户 2026-10-24 定版：120s 一戳足够避开挂机弹窗，无需更频）
$script:lastPoke = Get-Date
function Invoke-PokeIfDue {
    if (((Get-Date) - $script:lastPoke).TotalSeconds -ge 115) {
        Invoke-Poke
        $script:lastPoke = Get-Date
    }
}
function Invoke-Click([string]$steps) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxclick-personal.ps1" -Pid2 $Pid2 -Steps $steps 2>&1 | ForEach-Object { "$_" }
}
for ($i = 1; $i -le $Rounds; $i++) {
    "=== round $i/$Rounds ==="
    Invoke-PokeIfDue   # 覆盖上一场战斗期间的等待时间
    # 1) 等结算页（Quick 轻量探针 1s 轮询；GOLD 需连续 3 次确认——战斗结束金色爆闪瞬时误报）
    $t = 0; $st = Invoke-Probe -Quick; $goldStreak = 0
    while ($st -ne "SETTLE_PAGE") {
        if ($st -eq "ERR") { "STOP: probe error (wxprobe failed - 窗口丢失或尺寸不符，见 wxprobe 输出)"; exit 9 }
        if ($st -eq "GOLD_DIALOG") {
            $goldStreak++
            if ($goldStreak -ge 3) { "STOP: persistent gold dialog (death/idle/login)"; exit 6 }
            Start-Sleep -Seconds 1; $t += 1
        } elseif ($st -eq "STAMINA_POP") { "STOP: stamina popup"; exit 5 }
        else { $goldStreak = 0; Start-Sleep -Seconds 1; $t += 1 }
        if ($t -ge $SettleWaitSec) { "STOP: settle wait timeout ($SettleWaitSec s), last=$st"; exit 2 }
        Invoke-PokeIfDue
        $st = Invoke-Probe -Quick
    }
    # 2) 点再来一次（两次机会）
    $entered = $false
    foreach ($attempt in 1..2) {
        $rc = Resolve-RetryCoords
        "round ${i}: click retry (attempt $attempt, target=$rc)"
        $rcParts = $rc.Split(',')
        Invoke-Click "$($rcParts[0]):$($rcParts[1]):6000" | Out-Null
        $t = 0; $st = Invoke-Probe
        while ($st -eq "SETTLE_PAGE" -and $t -lt $EnterWaitSec) {
            Start-Sleep -Seconds 1; $t += 1; $st = Invoke-Probe
        }
        if ($st -ne "SETTLE_PAGE") { $entered = $true; break }
        "round ${i}: still settle after attempt $attempt"
    }
    if (-not $entered) { "STOP: retry clicks failed twice (round $i)"; exit 0 }
    # 3) 入场确认 + 自动战斗
    "round ${i}: entered, state=$st"
    if ($st -eq "ERR") { "STOP: probe error after enter"; exit 9 }
    if ($st -eq "AUTO_OFF") {
        $out = Invoke-Click "auto"
        $out | ForEach-Object { "$_" }
        $joined = ($out -join "`n")
        if ($joined -match 'AUTO_ENSURE_FAIL') { "STOP: auto ensure failed"; exit 3 }
    } elseif ($st -eq "GOLD_DIALOG") { "STOP: gold dialog after enter"; exit 6 }
    elseif ($st -eq "STAMINA_POP") { "STOP: stamina popup after enter"; exit 5 }
    # 4) 等战斗结束（下一轮的等结算负责等待）
}
"LOOP: $Rounds rounds completed"
$st = Invoke-Probe
"final state=$st"

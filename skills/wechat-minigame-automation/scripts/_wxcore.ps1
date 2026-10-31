# _wxcore.ps1 — 同进程模块库（模块化试点，2026-10-31）
# 契约：见 管理新规.md §七。函数**只返回对象、不输出裸字符串**（裸字符串会污染返回值，环境坑 §2）；
#       文本格式化与退出码由薄壳脚本负责。
# 依赖：调用方必须先 dot-source _wxcommon.ps1（几何换算/像素缓冲/匹配函数都在那里）。
# 已迁入：Invoke-WxProbe（原 wxprobe.ps1 主体）、Invoke-WxPopup（原 wxpopup.ps1 主体）
# 未迁入：wxocr / wxclick / wxcharsel —— 仍走子进程，下一批处理。
# ⚠️ 迁移原则：区域常量、阈值、判定顺序、输出文案**一律零改动**，只把 exit 改成 return 对象。

# ================= 结果对象构造 =================
function New-WxProbeResult {
    param(
        [int]$ExitCode = 0, [string]$Err = "", [string]$Client = "",
        [string]$State = "UNKNOWN", [string]$Page = "", [string]$Note = "",
        [int]$Gold = 0, [int]$Stam = 0, [int]$Settle = 0, [int]$Side = 0,
        [double]$DistOn = 0, [double]$DistOff = 0, [int]$Hp = 0,
        [int]$Power = 0, [int]$Welfare = 0, [int]$Shop = 0, [int]$TownVotes = 0
    )
    [pscustomobject]@{
        ExitCode = $ExitCode; Err = $Err; Client = $Client; State = $State; Page = $Page; Note = $Note
        Gold = $Gold; Stam = $Stam; Settle = $Settle; Side = $Side; DistOn = $DistOn; DistOff = $DistOff
        Hp = $Hp; Power = $Power; Welfare = $Welfare; Shop = $Shop; TownVotes = $TownVotes
    }
}

function New-WxPopupResult {
    param(
        [int]$ExitCode = 0, [string]$Err = "", [string]$Popup = "POPUP_UNKNOWN",
        [string]$Kind = "", [int]$Pack = 0, [int]$GoldBtn = 0, [string]$OcrRaw = "",
        [int]$CloseX = 0, [int]$CloseY = 0, [int]$UncheckX = 0, [int]$UncheckY = 0
    )
    [pscustomobject]@{
        ExitCode = $ExitCode; Err = $Err; Popup = $Popup; Kind = $Kind; Pack = $Pack
        GoldBtn = $GoldBtn; OcrRaw = $OcrRaw
        CloseX = $CloseX; CloseY = $CloseY; UncheckX = $UncheckX; UncheckY = $UncheckY
    }
}

# ================= probe 私有像素计数（原 wxprobe.ps1 内联函数，逻辑零改动）=================
# 谓词整数 id：1=金按钮 2=绿字 3=白字 4=暗红战力 5=town金色 6=hp混合
function Get-WxPxCount([int]$x0, [int]$y0, [int]$x1, [int]$y1, [int]$pred) {
    $buf = $script:PxBuf; $st = $script:PxStride; $bp = $script:PxBpp; $n = 0
    for ($y = $y0; $y -le $y1; $y += 2) {
        $row = $y * $st
        for ($x = $x0; $x -le $x1; $x += 2) {
            $i = $row + ($x * $bp)
            $b = $buf[$i]; $g = $buf[$i + 1]; $r = $buf[$i + 2]
            if ($pred -eq 1) { if ($r -gt 200 -and $g -gt 140 -and $b -lt 110 -and ($r - $b) -gt 90) { $n++ } }
            elseif ($pred -eq 2) { if ($g -gt 170 -and ($g - $r) -gt 50 -and ($g - $b) -gt 50) { $n++ } }
            elseif ($pred -eq 3) { if ($r -gt 215 -and $g -gt 215 -and $b -gt 215) { $n++ } }
            elseif ($pred -eq 4) { if ($r -ge 100 -and $r -le 235 -and $g -lt 80 -and $b -lt 80 -and ($r - $g) -gt 60) { $n++ } }
            elseif ($pred -eq 5) { if ($r -ge 170 -and $g -ge 120 -and $b -le 140 -and ($r - $b) -ge 60) { $n++ } }
            else { if ((($g -gt 140 -and ($g - $r) -gt 40 -and ($g - $b) -gt 40)) -or ($r -gt 170 -and ($r - $g) -gt 60)) { $n++ } }
        }
    }
    return $n
}
# town 探针专用：只隔列采样（x+=2，y 逐行）。阈值=全分辨率标定值÷2。
function Get-WxPxCountX2([int]$x0, [int]$y0, [int]$x1, [int]$y1, [int]$pred) {
    $buf = $script:PxBuf; $st = $script:PxStride; $bp = $script:PxBpp; $n = 0
    for ($y = $y0; $y -le $y1; $y++) {
        $row = $y * $st
        for ($x = $x0; $x -le $x1; $x += 2) {
            $i = $row + ($x * $bp)
            $b = $buf[$i]; $g = $buf[$i + 1]; $r = $buf[$i + 2]
            if ($pred -eq 4) { if ($r -ge 100 -and $r -le 235 -and $g -lt 80 -and $b -lt 80 -and ($r - $g) -gt 60) { $n++ } }
            else { if ($r -ge 170 -and $g -ge 120 -and $b -le 140 -and ($r - $b) -ge 60) { $n++ } }
        }
    }
    return $n
}

# ================= 状态探针 =================
# IN : 游戏窗口在前台（或 -Img 传入完整客户区截图），画面状态未知
# OUT: State 为 GOLD_DIALOG / SETTLE_PAGE / TOWER_PAGE / AUTO_ON / AUTO_OFF / STAMINA_POP /
#      TOWN_PAGE / OCCLUDED / UNKNOWN 之一，且各区域像素计数一并返回
function Invoke-WxProbe {
    param([int]$Pid2 = 0, [switch]$Debug, [string]$Img = "", [switch]$Quick)

    $clientStr = ""
    if ($Img -ne "") {
        if (-not (Test-Path $Img)) { return (New-WxProbeResult -ExitCode 4 -Err "image not found: $Img") }
        $bmp = New-Object System.Drawing.Bitmap $Img
        $iw = $bmp.Width; $ih = $bmp.Height
        if (-not (Test-WxMinClientW $iw)) {
            $bmp.Dispose()
            return (New-WxProbeResult -ExitCode 4 -Err "image ${iw}x${ih} 过小（宽须>=$($WX_MIN_CLIENT_W)），-Img 需传完整客户端区截图")
        }
        if ($bmp.Width -ne $WX_DESIGN_W -or $bmp.Height -ne $WX_DESIGN_H) {
            $norm = Resize-WxBitmapNearest $bmp $WX_DESIGN_W $WX_DESIGN_H
            if (-not [object]::ReferenceEquals($norm, $bmp)) { $bmp.Dispose() }
            $bmp = $norm
        }
    } else {
        $h = Find-GameWindow -Pid2 $Pid2
        if ($h -eq [IntPtr]::Zero) { return (New-WxProbeResult -ExitCode 1 -Err "window not found (pid=$Pid2)") }
        if (-not (Confirm-WxForeground $h 'probe')) { return (New-WxProbeResult -ExitCode 7 -Err "game not foreground，探测拒绝（防假数据）") }
        $geo = Get-ClientGeometry $h
        if (-not (Test-WxMinClientW $geo.W)) { return (New-WxProbeResult -ExitCode 7 -Err "window too small ($($geo.W)x$($geo.H) < ${WX_MIN_CLIENT_W} width)，探测拒读") }
        $clientStr = "client=$($geo.W)x$($geo.H) origin=$($geo.OX),$($geo.OY) scale=$([math]::Round($geo.S,4))"
        $bmp = Get-DesignBitmap $geo
        # 遮挡守卫（事件4/15）：网格采样色彩多样性，整屏纯色=最小化/遮挡/锁屏
        $distinct = @{}
        for ($yy = 0; $yy -lt $bmp.Height; $yy += 40) {
            for ($xx = 0; $xx -lt $bmp.Width; $xx += 40) {
                $distinct[$bmp.GetPixel($xx, $yy).ToArgb()] = $true
            }
        }
        if ($distinct.Count -le 2) {
            $bmp.Dispose()
            return (New-WxProbeResult -ExitCode 0 -Client $clientStr -State "OCCLUDED" -Note "flat screenshot (最小化/遮挡/锁屏)，画面不可信，先 wxrestore")
        }
    }

    # --- 区域定义（设计坐标 1138x708；抓图已归一化到设计尺寸）---
    $RX0 = 440; $RY0 = 470; $RX1 = 800; $RY1 = 560      # 金色主按钮区
    $SX0 = 420; $SY0 = 380; $SX1 = 760; $SY1 = 540      # 体力弹窗绿色文字区
    $BX = 900; $BY0 = 225; $BH = 220                     # 结算暗红按钮扫描带
    $HX0 = 440; $HY0 = 655; $HX1 = 700; $HY1 = 680      # 底部血条区
    $NX0 = 30; $NY0 = 130; $NX1 = 160; $NY1 = 520       # 左侧分类栏白字区
    $TPX0 = 230; $TPY0 = 132; $TPX1 = 370; $TPY1 = 172  # town 战力条暗红
    $TWX0 = 658; $TWY0 = 60; $TWX1 = 735; $TWY1 = 155   # town 福利暗金
    $TSX0 = 848; $TSY0 = 80; $TSX1 = 895; $TSY1 = 115   # town 商城金

    Init-PxBuf $bmp

    $nGold = Get-WxPxCount $RX0 $RY0 $RX1 $RY1 1
    $nStam = Get-WxPxCount $SX0 $SY0 $SX1 $SY1 2
    # 结算暗红块（三点采样取二）
    $nSettle = 0
    for ($y = $BY0; $y -lt ($BY0 + $BH); $y += 3) {
        $hit = 0
        foreach ($dx in @(-25, 0, 25)) {
            $i = ($y * $script:PxStride) + (($BX + $dx) * $script:PxBpp)
            $b = $script:PxBuf[$i]; $g = $script:PxBuf[$i + 1]; $r = $script:PxBuf[$i + 2]
            if ($r -gt 100 -and ($r - $b) -gt 50 -and $g -gt 22 -and $g -lt 78) { $hit++ }
        }
        if ($hit -ge 2) { $nSettle++ }
    }

    if ($Quick) {
        $bmp.Dispose()
        $qstate = "UNKNOWN"
        if ($nGold -ge 450) { $qstate = "GOLD_DIALOG" }
        elseif ($nSettle -ge 10) { $qstate = "SETTLE_PAGE" }
        elseif ($nStam -ge 60) { $qstate = "STAMINA_POP" }
        return (New-WxProbeResult -ExitCode 0 -Client $clientStr -State $qstate -Gold $nGold -Stam $nStam -Settle $nSettle)
    }

    $nHp = Get-WxPxCount $HX0 $HY0 $HX1 $HY1 6
    $nSide = Get-WxPxCount $NX0 $NY0 $NX1 $NY1 3
    $nPower = Get-WxPxCountX2 $TPX0 $TPY0 $TPX1 $TPY1 4
    $nTownW = Get-WxPxCountX2 $TWX0 $TWY0 $TWX1 $TWY1 5
    $nShop = Get-WxPxCountX2 $TSX0 $TSY0 $TSX1 $TSY1 5
    $townVotes = ($nPower -ge 150) + ($nTownW -ge 50) + ($nShop -ge 30)

    # 左上角按钮文字模板匹配（AUTO_ON/AUTO_OFF 判定唯一来源）
    $tpl = Import-WxBtnTemplates
    $live = Get-WxBmpMask $bmp $WX_BTN_X0 $WX_BTN_Y0
    $dOn = [math]::Round((Get-WxJaccard $live $tpl.On), 3)
    $dOff = [math]::Round((Get-WxJaccard $live $tpl.Off), 3)
    $btnMatch = (($dOn -le 0.60 -and ($dOff - $dOn) -ge 0.10) -or ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10))

    $bmp.Dispose()
    $state = "UNKNOWN"
    if (-not $btnMatch -and $nGold -ge 450) { $state = "GOLD_DIALOG" }
    elseif ($nSettle -ge 10 -and $btnMatch) { $state = "SETTLE_PAGE" }
    elseif ($nSettle -ge 10 -and $nGold -lt 100) { $state = "TOWER_PAGE" }
    elseif ($dOn -le 0.60 -and ($dOff - $dOn) -ge 0.10) { $state = "AUTO_ON" }
    elseif ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10) { $state = "AUTO_OFF" }
    elseif ($nStam -ge 60) { $state = "STAMINA_POP" }
    elseif ($townVotes -ge 2) { $state = "TOWN_PAGE" }

    $page = switch -regex ($state) {
        "SETTLE_PAGE|AUTO_ON|AUTO_OFF" { if ($nSettle -ge 10) { "SETTLE" } else { "BATTLE" } }
        "TOWER_PAGE" { "TOWER" }
        "TOWN_PAGE" { "TOWN" }
        default {
            if ($nSide -ge 400) { "CHARSEL" }
            elseif (($nSide -lt 50) -and ($nGold -lt 50) -and ($nSettle -lt 5)) { "WORLD_MAP" }
            else { "UNKNOWN" }
        }
    }

    return (New-WxProbeResult -ExitCode 0 -Client $clientStr -State $state -Page $page `
            -Gold $nGold -Stam $nStam -Settle $nSettle -Side $nSide -DistOn $dOn -DistOff $dOff `
            -Hp $nHp -Power $nPower -Welfare $nTownW -Shop $nShop -TownVotes $townVotes)
}

# ================= 弹窗分类器 =================
# IN : 游戏窗口在前台（或 -Img），画面可能是任意场景
# OUT: Popup 为 POPUP_NONE / POPUP_PACK / POPUP_RELOGIN / POPUP_IDLE / POPUP_EXTEND / POPUP_REVIVE / POPUP_UNKNOWN
#      礼包类不在此处置（CloseX/UncheckX 一并返回，处置权在调用方）
function Invoke-WxPopup {
    param([int]$Pid2 = 0, [string]$Img = "", [switch]$Debug)

    $GOLDX0 = 600; $GOLDY0 = 488; $GOLDX1 = 780; $GOLDY1 = 532   # 金确定钮守卫带
    $BX0 = 350; $BY0 = 348; $BX1 = 800; $BY1 = 408               # 正文带

    if ($Img -ne "") {
        if (-not (Test-Path $Img)) { return (New-WxPopupResult -ExitCode 4 -Err "image not found: $Img") }
        $bmp = New-Object System.Drawing.Bitmap $Img
        $iw = $bmp.Width; $ih = $bmp.Height
        if (-not (Test-WxMinClientW $iw) -or $ih -lt 550) {
            $bmp.Dispose()
            return (New-WxPopupResult -ExitCode 4 -Err "image ${iw}x${ih} 过小（宽须>=$($WX_MIN_CLIENT_W)、高须>=550），-Img 需传完整客户端区截图")
        }
        if ($bmp.Width -ne $WX_DESIGN_W -or $bmp.Height -ne $WX_DESIGN_H) {
            $norm = Resize-WxBitmapNearest $bmp $WX_DESIGN_W $WX_DESIGN_H
            if (-not [object]::ReferenceEquals($norm, $bmp)) { $bmp.Dispose() }
            $bmp = $norm
        }
    } else {
        $h = Find-GameWindow -Pid2 $Pid2
        if ($h -eq [IntPtr]::Zero) { return (New-WxPopupResult -ExitCode 1 -Err "window not found (pid=$Pid2)") }
        $geo = Get-ClientGeometry $h
        if (-not (Test-WxMinClientW $geo.W)) { return (New-WxPopupResult -ExitCode 7 -Err "window too small ($($geo.W)x$($geo.H) < ${WX_MIN_CLIENT_W} width)，弹窗分类拒读") }
        $bmp = Get-DesignBitmap $geo
    }

    Init-PxBuf $bmp

    # 礼包弹窗（表驱动 $WX_PACK_PROBES，必须先于金确定钮判：金钮区只擦 8px 窄边）
    foreach ($pk in $WX_PACK_PROBES) {
        $nPk = Count-PxBox $pk.X0 $pk.Y0 $pk.X1 $pk.Y1 5 2 1
        if ($nPk -lt $pk.MinHit) { continue }
        if ($pk.TagMin -gt 0) {
            $nTag = Count-PxBox $pk.TagX0 $pk.TagY0 $pk.TagX1 $pk.TagY1 3 1 1
            if ($nTag -lt $pk.TagMin) { continue }
        }
        $bmp.Dispose()
        return (New-WxPopupResult -ExitCode 0 -Popup "POPUP_PACK" -Kind $pk.Kind -Pack $nPk `
                -CloseX $pk.CloseX -CloseY $pk.CloseY -UncheckX $pk.UncheckX -UncheckY $pk.UncheckY)
    }

    $goldBtn = Count-PxBox $GOLDX0 $GOLDY0 $GOLDX1 $GOLDY1 1 2 2

    # OCR 正文带（有金钮才扫）。⚠️ 仍走 wxocr 子进程（本轮未函数化），落临时盘复用 -Img 避免二次抓屏竞态
    $raw = ""
    if ($goldBtn -ge 400) {
        $tmpPng = $Img
        if ($tmpPng -eq "") {
            $tmpPng = Join-Path $env:TEMP ("wrx_popup_" + [guid]::NewGuid().ToString('N') + ".png")
            $bmp.Save($tmpPng, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        $out = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'wxocr.ps1') -Img $tmpPng -X0 $BX0 -Y0 $BY0 -X1 $BX1 -Y1 $BY1 2>&1
        $joined = ($out | ForEach-Object { "$_" }) -join ' '
        if ($joined -match 'OCR_RAW=\[(.*)\]') { $raw = $Matches[1] }
        if ($Img -eq "" -and (Test-Path $tmpPng)) { Remove-Item $tmpPng -Force }
    }
    $bmp.Dispose()

    $cls = "POPUP_UNKNOWN"
    if ($goldBtn -lt 400) { $cls = "POPUP_NONE" }
    elseif (Test-WxKwHit $raw '其他设备') { $cls = "POPUP_RELOGIN" }
    elseif ((Test-WxKwHit $raw '未操作') -or (Test-WxKwHit $raw '重新登录')) { $cls = "POPUP_IDLE" }
    elseif (Test-WxKwHit $raw '扩展券') { $cls = "POPUP_EXTEND" }
    elseif (Test-WxKwHit $raw '羽毛') { $cls = "POPUP_REVIVE" }

    $exitCode = 0
    if ($cls -eq "POPUP_RELOGIN" -or $cls -eq "POPUP_UNKNOWN") { $exitCode = 3 }
    return (New-WxPopupResult -ExitCode $exitCode -Popup $cls -GoldBtn $goldBtn -OcrRaw $raw)
}

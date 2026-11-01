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
        # 同进程 OCR（原为 wxocr.ps1 子进程）：引擎已缓存，这里只需 ~0.25s
        $ocr = Invoke-WxOcr -Img $tmpPng -X0 $BX0 -Y0 $BY0 -X1 $BX1 -Y1 $BY1
        if (-not $ocr.Err) { $raw = "$($ocr.Raw)" }
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

# ================= OCR（2026-10-31 迁入，带引擎缓存）=================
# 原理不变：设计坐标裁剪 → 灰度反相 → 双三次放大 F 倍 → Windows.Media.Ocr(zh-Hans)。
# ⚠️ 关键优化：OcrEngine 创建（加载 zh-Hans 模型）+ WinRT 程序集加载约 2~2.5s，原实现每次子进程
#    都重建 → 单次 wxocr 实测约 3s（注释里的「~250ms」只是识别本身）。改为进程内缓存引擎后，
#    只有第一次付这个成本，后续每次 <1s。这是重登链最大的单点优化。
$script:WxOcrEngine = $null
$script:WxOcrAsTask = $null
$script:WxOcrAvailable = $null

$script:WxOcrTasks = @{
    autobtn = @{ x0 = 175; y0 = 158; x1 = 275; y1 = 195; kind = 'auto'; f = 12 }
    charsel = @{ x0 = 0; y0 = 56; x1 = 200; y1 = 115; kind = 'kw'; kw = '选择角色' }
    scr1w = @{ x0 = 36; y0 = 130; x1 = 215; y1 = 204; kind = 'kw'; kw = '早睡早起身体好'; minhit = 3; kw2 = '圣骑士' }
    scr2w = @{ x0 = 36; y0 = 234; x1 = 215; y1 = 290; kind = 'kw'; kw = '豁达自在乐逍遥'; minhit = 3; kw2 = '重装机兵' }
    town = @{ x0 = 140; y0 = 150; x1 = 270; y1 = 205; kind = 'kw'; kw = '选角'; minhit = 2; retry = 2 }
    server = @{ x0 = 488; y0 = 447; x1 = 638; y1 = 492; kind = 'kw'; kw = '巨龙山脉'; minhit = 3 }
}

function New-WxOcrResult {
    param([int]$ExitCode = 0, [string]$Err = "", [string]$Task = "", [string]$Kind = "raw",
        [bool]$Hit = $false, [string]$Raw = "", [string]$Class = "", [string]$DebugLine = "")
    [pscustomobject]@{ ExitCode = $ExitCode; Err = $Err; Task = $Task; Kind = $Kind; Hit = $Hit; Raw = $Raw; Class = $Class; DebugLine = $DebugLine }
}

function Initialize-WxOcrEngine {
    if ($null -ne $script:WxOcrAvailable) { return $script:WxOcrAvailable }
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.DataWriter, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $script:WxOcrAsTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('zh-Hans-CN'))
    if ($null -eq $engine) { $script:WxOcrAvailable = $false; return $false }
    $script:WxOcrEngine = $engine
    $script:WxOcrAvailable = $true
    return $true
}

function Invoke-WxOcrAwait($op, $type) {
    $t = $script:WxOcrAsTask.MakeGenericMethod($type).Invoke($null, @($op))
    $t.Wait(-1) | Out-Null
    return $t.Result
}

# 单次取图 + 识别（不做 retry，retry 由 Invoke-WxOcr 外层循环处理）
function Invoke-WxOcrOnce {
    param([int]$Pid2 = 0, [string]$Img = "", [string]$Task = "", [int]$X0 = 0, [int]$Y0 = 56,
        [int]$X1 = 200, [int]$Y1 = 115, [int]$F = 8, [switch]$NoInvert, [string]$Kind = "raw",
        $TaskDef = $null, [switch]$Debug)

    if ($Img -ne "") {
        if (-not (Test-Path $Img)) { return (New-WxOcrResult -ExitCode 4 -Err "image not found: $Img" -Task $Task -Kind $Kind) }
        $bmp = New-Object System.Drawing.Bitmap $Img
        if ($bmp.Width -lt 200 -or $bmp.Height -lt 150) {
            $bmp.Dispose()
            return (New-WxOcrResult -ExitCode 4 -Err "image $($bmp.Width)x$($bmp.Height) 过小，-Img 需传完整客户区截图" -Task $Task -Kind $Kind)
        }
        if ($bmp.Width -ne $WX_DESIGN_W -or $bmp.Height -ne $WX_DESIGN_H) {
            $norm = Resize-WxBitmapNearest $bmp $WX_DESIGN_W $WX_DESIGN_H
            if (-not [object]::ReferenceEquals($norm, $bmp)) { $bmp.Dispose() }
            $bmp = $norm
        }
    } else {
        $hwnd = Find-GameWindow -Pid2 $Pid2
        if ($hwnd -eq [IntPtr]::Zero) { return (New-WxOcrResult -ExitCode 1 -Err "window not found (pid=$Pid2)" -Task $Task -Kind $Kind) }
        $geo = Get-ClientGeometry $hwnd
        if (-not (Test-WxMinClientW $geo.W)) {
            return (New-WxOcrResult -ExitCode 7 -Err "window too small ($($geo.W)x$($geo.H) < ${WX_MIN_CLIENT_W} width)，OCR 拒读" -Task $Task -Kind $Kind)
        }
        $bmp = Get-DesignBitmap $geo
    }

    if ($X1 -ge $bmp.Width -or $Y1 -ge $bmp.Height -or $X0 -lt 0 -or $Y0 -lt 0 -or $X0 -gt $X1 -or $Y0 -gt $Y1) {
        $bmp.Dispose()
        return (New-WxOcrResult -ExitCode 4 -Err "OCR 区域非法 ($X0,$Y0)-($X1,$Y1)" -Task $Task -Kind $Kind)
    }

    $bw = $X1 - $X0 + 1; $bh = $Y1 - $Y0 + 1
    $gs = New-Object System.Drawing.Bitmap $bw, $bh
    for ($y = 0; $y -lt $bh; $y++) {
        for ($x = 0; $x -lt $bw; $x++) {
            $c = $bmp.GetPixel($X0 + $x, $Y0 + $y)
            if ($NoInvert) { $gray = [int](0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B) }
            else { $gray = 245 - [int](0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B) }
            if ($gray -lt 0) { $gray = 0 }
            if ($gray -gt 255) { $gray = 255 }
            $gs.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($gray, $gray, $gray))
        }
    }
    $bmp.Dispose()
    $big = New-Object System.Drawing.Bitmap ($bw * $F), ($bh * $F)
    $gr = [System.Drawing.Graphics]::FromImage($big)
    $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gr.DrawImage($gs, 0, 0, $big.Width, $big.Height)
    $gr.Dispose()
    $gs.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $big.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $big.Dispose()
    $bytes = $ms.ToArray()
    $ms.Dispose()

    if (-not (Initialize-WxOcrEngine)) {
        return (New-WxOcrResult -ExitCode 0 -Task $Task -Kind "unavailable" -Raw "UNAVAILABLE")
    }

    $ras = [Windows.Storage.Streams.InMemoryRandomAccessStream]::new()
    $dw = [Windows.Storage.Streams.DataWriter]::new($ras)
    $dw.WriteBytes($bytes)
    Invoke-WxOcrAwait ($dw.StoreAsync()) ([uint32]) | Out-Null
    $dw.DetachStream() | Out-Null
    $ras.Seek(0)
    $decoder = Invoke-WxOcrAwait ([Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $sb = Invoke-WxOcrAwait ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $res = Invoke-WxOcrAwait ($script:WxOcrEngine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
    $ras.Dispose()

    $text = ($res.Text -replace '\s+', '')
    $hit = $false; $cls = ""
    if ($Kind -eq 'auto') {
        $cls = "UNKNOWN"
        if (Test-WxKwHit $text '取消自动') { $cls = "ON" }
        elseif (Test-WxKwHit $text '自动战斗') { $cls = "OFF" }
    } elseif ($Kind -eq 'kw') {
        $kw = $TaskDef.kw
        $minhit = 0; if ($TaskDef -and $TaskDef.Contains('minhit')) { $minhit = $TaskDef.minhit }
        $pool = $kw
        $kw2 = ''
        if ($TaskDef -and $TaskDef.Contains('kw2')) { $kw2 = $TaskDef.kw2; $pool = "$kw$kw2" }
        $hit = $text.Contains($kw) -or ($kw2 -ne '' -and $text.Contains($kw2))
        if (-not $hit) { $hit = Test-WxKwHit $text $pool $minhit }
    }
    $dbg = ""
    if ($Debug) { $dbg = "debug: task=$Task region=($X0,$Y0)-($X1,$Y1) scale=$F lines=$($res.Lines.Count) invert=$(-not $NoInvert)" }
    return (New-WxOcrResult -ExitCode 0 -Task $Task -Kind $Kind -Hit $hit -Raw $text -Class $cls -DebugLine $dbg)
}

# IN : 画面任意（或 -Img 传完整客户区截图），不假设任何前置状态
# OUT: Hit=关键字是否命中（kind=kw）/ Class=ON|OFF|UNKNOWN（kind=auto）/ Raw=识别原文（kind=raw）
function Invoke-WxOcr {
    param([int]$Pid2 = 0, [string]$Img = "", [string]$Task = "", [int]$X0 = 0, [int]$Y0 = 56,
        [int]$X1 = 200, [int]$Y1 = 115, [int]$F = 8, [switch]$NoInvert, [switch]$Debug, [int]$RetryLeft = -1)

    $kind = 'raw'
    $t = $null
    if ($Task -ne "") {
        if (-not $script:WxOcrTasks.ContainsKey($Task)) {
            return (New-WxOcrResult -ExitCode 4 -Err "unknown task '$Task'（可用: $($script:WxOcrTasks.Keys -join ', ')）")
        }
        $t = $script:WxOcrTasks[$Task]
        $X0 = $t.x0; $Y0 = $t.y0; $X1 = $t.x1; $Y1 = $t.y1
        $kind = $t.kind
        if ($t.Contains('f')) { $F = $t.f }
    }

    # MISS 重扫：仅实时路径 + 任务配了 retry 才生效（-Img 离线同图恒定，重扫无意义）
    $attempts = 1
    if ($Img -eq "" -and $Task -ne "" -and $null -ne $t -and $t.Contains('retry')) {
        $retryN = if ($RetryLeft -ge 0) { $RetryLeft } else { [int]$t.retry }
        $attempts = $retryN + 1
    }

    $last = $null
    for ($a = 1; $a -le $attempts; $a++) {
        $current = Invoke-WxOcrOnce -Pid2 $Pid2 -Img $Img -Task $Task -X0 $X0 -Y0 $Y0 -X1 $X1 -Y1 $Y1 -F $F -NoInvert:$NoInvert -Kind $kind -TaskDef $t -Debug:$Debug
        if ($current.Err) { return $current }
        $last = $current
        if ($current.Hit) { return $current }
        if ($Task -eq "" -or $current.Kind -eq 'unavailable') { return $current }
        if ($a -lt $attempts) { Start-Sleep -Milliseconds 800 }
    }
    return $last
}

# ================= 点击器（2026-10-31 迁入）=================
# Steps 语法与语义零改动：x:y:delayMs 点击并等待 / w:ms 纯等待 / auto 委托 wxautoensure。
# 迁入收益：链路内每次点击省一次子进程启动（约 1.3s）；重登链全程 6 次点击。
function New-WxClickResult {
    param([int]$ExitCode = 0, [string]$Err = "", [string[]]$Log = @())
    [pscustomobject]@{ ExitCode = $ExitCode; Err = $Err; Log = $Log }
}

# IN : 游戏窗口存在（可被拉前台）
# OUT: Log 内逐条为实际点击落点；ExitCode 0=全部执行完，7=前台/最小窗守卫拒绝，3=auto 步骤失败，1=窗口未找到
function Invoke-WxClick {
    param([string]$Steps = "", [int]$Pid2 = 0)

    $log = New-Object System.Collections.ArrayList
    $h = Find-GameWindow -Pid2 $Pid2
    if ($h -eq [IntPtr]::Zero) { return (New-WxClickResult -ExitCode 1 -Err "window not found (pid=$Pid2)") }
    [WXCommon]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 350
    if (-not (Confirm-WxForeground $h)) {
        return (New-WxClickResult -ExitCode 7 -Err "game not foreground (拉回重试后仍不在前台)，拒绝点击" -Log @("DONE"))
    }
    $geo = Get-ClientGeometry $h
    if (-not (Test-WxMinClientW $geo.W)) {
        return (New-WxClickResult -ExitCode 7 -Err "window too small ($($geo.W)x$($geo.H) < ${WX_MIN_CLIENT_W} width)，拒绝点击" -Log @("DONE"))
    }
    [void]$log.Add("client=$($geo.W)x$($geo.H) origin=$($geo.OX),$($geo.OY) scale=$([math]::Round($geo.S,4))")

    foreach ($step in $Steps.Split(";")) {
        if ($step.Trim() -eq "") { continue }
        if ($step.StartsWith("w:")) { Start-Sleep -Milliseconds ([int]$step.Substring(2)); continue }
        if ($step.Trim() -eq "auto" -or $step.Trim() -eq "autonow") {
            $ens = & (Join-Path $PSScriptRoot 'wxautoensure.ps1') -Pid2 $Pid2 2>&1
            foreach ($l in $ens) { [void]$log.Add("$l") }
            if (($ens -join "`n") -notmatch 'AUTO_ENSURED') {
                [void]$log.Add("AUTO_ENSURE_FAIL(delegated to wxautoensure)")
                [void]$log.Add("DONE")
                return (New-WxClickResult -ExitCode 3 -Log $log.ToArray())
            }
            continue
        }
        $parts = $step.Split(":")
        $x = [int]$parts[0]; $y = [int]$parts[1]
        $d = 250
        if ($parts.Length -gt 2) { $d = [int]$parts[2] }
        # 每步点击前重读几何：窗口在多次点击间可能被移动/改尺寸
        $g = Get-ClientGeometry $h
        $p = ConvertTo-ScreenPoint $g $x $y
        $ax = $p.X; $ay = $p.Y
        Start-Sleep -Milliseconds 250
        [WXCommon]::SetCursorPos($ax, $ay) | Out-Null
        Start-Sleep -Milliseconds 100
        [WXCommon]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 70
        [WXCommon]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        [void]$log.Add("click=$x,$y -> $ax,$ay")
        if ($d -gt 0) { Start-Sleep -Milliseconds $d }
    }
    [void]$log.Add("DONE")
    return (New-WxClickResult -ExitCode 0 -Log $log.ToArray())
}

# ================= 结算「再来一次」按钮扫描（P4，2026-11-01 从 wxgrind 私有实现固化）=================
# 原 wxgrind.Find-RetryY / Resolve-RetryCoords（私有，依赖 $script:grindHwnd）。
# 拆两层：Find-WxRetryY 纯算法（不碰窗口、不管资源），Resolve-WxRetryCoords 负责取图+回退。
# 判据与常量**零改动**：扫描带 BX=915（三点采样 ±25），y 225..444，连续段 >=10px。
# 新增 -Img 支持：可对历史截图离线验扫描结果，不必实机。

function Find-WxRetryY {
    # IN : Bitmap，须已归一化到设计尺寸 1138x708（调用方负责 Dispose，本函数不释放）
    # OUT: 暗红按钮中心 y（设计坐标）；未找到返回 -1
    param([System.Drawing.Bitmap]$Bitmap)
    $bx = 915; $y0 = 225; $scanH = 220
    $hits = New-Object bool[] $scanH
    for ($i = 0; $i -lt $scanH; $i++) {
        $n = 0
        foreach ($dx in @(-25, 0, 25)) {
            $c = $Bitmap.GetPixel($bx + $dx, $y0 + $i)
            if ($c.R -gt 100 -and ($c.R - $c.B) -gt 50 -and $c.G -gt 22 -and $c.G -lt 78) { $n++ }
        }
        $hits[$i] = ($n -ge 2)
    }
    # 找连续命中段：允许 <=6px 断裂，段长 >=10px 才算按钮（过滤细小杂色）
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

function New-WxRetryCoordResult {
    param([int]$X = 936, [int]$Y = 269, [bool]$Auto = $false, [string]$Err = "")
    [pscustomobject]@{ X = $X; Y = $Y; Auto = $Auto; Err = $Err }
}

function Resolve-WxRetryCoords {
    # IN : -Img 离线图（隐含扫描）；或 -Pid2 + -EnableScan 实时抓图扫描
    # OUT: @{ X; Y; Auto }  —— Auto=$true 表示坐标来自自动扫描，否则是固定回退值
    # 注：不传 -EnableScan 且无 -Img 时直接返回固定坐标，不起抓图（保持原 wxgrind 默认行为，零漂移）
    param([int]$Pid2 = 0, [string]$Img = "", [switch]$EnableScan,
          [int]$FallbackX = 936, [int]$FallbackY = 269)
    if (-not $EnableScan -and $Img -eq "") { return (New-WxRetryCoordResult -X $FallbackX -Y $FallbackY) }
    $bmp = $null
    try {
        if ($Img -ne "") {
            if (-not (Test-Path $Img)) { return (New-WxRetryCoordResult -X $FallbackX -Y $FallbackY -Err "image not found: $Img") }
            $src = New-Object System.Drawing.Bitmap $Img
            if ($src.Width -ne $WX_DESIGN_W -or $src.Height -ne $WX_DESIGN_H) {
                $bmp = Resize-WxBitmapNearest $src $WX_DESIGN_W $WX_DESIGN_H
                if (-not [object]::ReferenceEquals($bmp, $src)) { $src.Dispose() }
            } else { $bmp = $src }
        } else {
            $h = Find-GameWindow -Pid2 $Pid2
            if ($h -eq [IntPtr]::Zero) { return (New-WxRetryCoordResult -X $FallbackX -Y $FallbackY -Err "window not found (pid=$Pid2)") }
            $geo = Get-ClientGeometry $h
            $bmp = Get-DesignBitmap $geo
        }
        $fy = Find-WxRetryY -Bitmap $bmp
        if ($fy -ge 0) { return (New-WxRetryCoordResult -X 915 -Y $fy -Auto $true) }
        return (New-WxRetryCoordResult -X $FallbackX -Y $FallbackY)
    } catch {
        return (New-WxRetryCoordResult -X $FallbackX -Y $FallbackY -Err "$_")
    } finally {
        if ($bmp) { $bmp.Dispose() }
    }
}
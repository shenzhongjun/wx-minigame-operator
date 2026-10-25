param([int]$Pid2 = 0, [string]$Img = "", [switch]$Debug)
# 弹窗正文分类器（2026-10-25 新增，消灭 GOLD_DIALOG 人工目验）
# 原理：三类已知弹窗共用同一面板几何（提示标题+正文+双按钮），
#   抓正文区 (423,356)-(752,392) 掩码与 assets\popup_idle/relogin/extend.png 模板做 Jaccard 距离，
#   距离小者胜；差距不足或距离≥0.55 → POPUP_UNKNOWN（宁可不知，不可误判）
# 分类与处置（红线规则，处置权在调用方）：
#   POPUP_IDLE    挂机「长时间未操作，请重新登录」→ 可点确定 (700,513)
#   POPUP_RELOGIN 顶号「账号在其他设备登录」      → 红线：停手请示用户
#   POPUP_EXTEND  角色栏扩展券（涉商城）          → 只点取消 (471,502)
#   POPUP_NONE    正文区无文字（无弹窗/背景干扰）
#   POPUP_UNKNOWN 未知弹窗                        → 红线：停手请示用户
# -Img 离线模式供标定/回归；默认实时截屏（-Pid2 0=按标题自动发现）
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$PX0 = 423; $PY0 = 356; $PX1 = 752; $PY1 = 392   # 正文区（三弹窗实测公共覆盖）
$GOLDX0 = 600; $GOLDY0 = 488; $GOLDX1 = 780; $GOLDY1 = 532   # 金确定钮守卫带
$pw = $PX1 - $PX0 + 1; $ph = $PY1 - $PY0 + 1

# 米黄正文 + 金色关键词双适配掩码（区别于按钮纯白掩码）
function Get-PopupMask([System.Drawing.Bitmap]$b, [int]$ox, [int]$oy) {
    $m = New-Object bool[] ($pw * $ph)
    for ($y = 0; $y -lt $ph; $y++) { for ($x = 0; $x -lt $pw; $x++) {
        $c = $b.GetPixel($ox + $x, $oy + $y)
        if (($c.R -gt 170 -and $c.G -gt 150 -and $c.B -gt 110) -or ($c.R -gt 190 -and $c.G -gt 150 -and ($c.R - $c.B) -gt 60)) { $m[$y * $pw + $x] = $true }
    } }
    return $m
}

function Import-PopupTemplates {
    $a = Get-WxAssetsDir
    @{
        Idle    = Get-PopupMask (New-Object System.Drawing.Bitmap "$a\popup_idle.png") 0 0
        Relogin = Get-PopupMask (New-Object System.Drawing.Bitmap "$a\popup_relogin.png") 0 0
        Extend  = Get-PopupMask (New-Object System.Drawing.Bitmap "$a\popup_extend.png") 0 0
    }
}

if ($Img -ne "") {
    if (-not (Test-Path $Img)) { "ERR: image not found: $Img"; exit 4 }
    $bmp = New-Object System.Drawing.Bitmap $Img
    if ($bmp.Width -lt ($PX1 + 1) -or $bmp.Height -lt ($PY1 + 1)) {
        "ERR: image $($bmp.Width)x$($bmp.Height) 小于弹窗区 ($PX1,$PY1)，-Img 需传完整客户端区截图"; exit 4
    }
    $live = Get-PopupMask $bmp $PX0 $PY0
} else {
    $h = Find-GameWindow -Pid2 $Pid2
    if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $geo = Get-ClientGeometry $h   # 尺寸断言
    # 截联合区域：正文区+金确定钮带 (423,356)-(780,532)
    $fw = $GOLDX1 - $PX0 + 1; $fh = $GOLDY1 - $PY0 + 1
    $bmp = New-Object System.Drawing.Bitmap $fw, $fh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(($geo.OX + $PX0), ($geo.OY + $PY0), 0, 0, (New-Object System.Drawing.Size $fw, $fh))
    $g.Dispose()
    $live = Get-PopupMask $bmp 0 0
}

$tpl = Import-PopupTemplates
$dIdle = [math]::Round((Get-WxJaccard $live $tpl.Idle), 3)
$dRel  = [math]::Round((Get-WxJaccard $live $tpl.Relogin), 3)
$dExt  = [math]::Round((Get-WxJaccard $live $tpl.Extend), 3)

# 面板守卫：三类弹窗都有金色确定按钮（带 (600,488)-(780,532) 金像素标定，步长2 计数：
# 弹窗 788-1066 / 战斗·选角 0 / 主城 128 → 阈值 400 六倍边际）。
# 无金确定钮=无弹窗面板 → POPUP_NONE；有钮但正文不匹配 → POPUP_UNKNOWN（未知弹窗，红线请示）
$goldBtn = 0
if ($Img -ne "") {
    for ($y = $GOLDY0; $y -le $GOLDY1; $y += 2) { for ($x = $GOLDX0; $x -le $GOLDX1; $x += 2) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 200 -and $c.G -gt 140 -and $c.B -lt 110 -and ($c.R - $c.B) -gt 90) { $goldBtn++ }
    } }
} else {
    for ($y = $GOLDY0 - $PY0; $y -le $GOLDY1 - $PY0; $y += 2) { for ($x = $GOLDX0 - $PX0; $x -le $GOLDX1 - $PX0; $x += 2) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 200 -and $c.G -gt 140 -and $c.B -lt 110 -and ($c.R - $c.B) -gt 90) { $goldBtn++ }
    } }
}
$bmp.Dispose()

$nLive = 0; foreach ($v in $live) { if ($v) { $nLive++ } }
$cls = "POPUP_UNKNOWN"
if ($goldBtn -lt 400) {
    $cls = "POPUP_NONE"
} elseif ($nLive -lt 15) {
    $cls = "POPUP_NONE"
} else {
    $pairs = @(@('POPUP_IDLE', $dIdle), @('POPUP_RELOGIN', $dRel), @('POPUP_EXTEND', $dExt)) | Sort-Object { $_[1] }
    if ($pairs[0][1] -le 0.55 -and ($pairs[1][1] - $pairs[0][1]) -ge 0.08) { $cls = $pairs[0][0] }
}
"POPUP=$cls d_idle=$dIdle d_relogin=$dRel d_extend=$dExt pixels=$nLive goldbtn=$goldBtn"
if ($cls -eq "POPUP_RELOGIN" -or $cls -eq "POPUP_UNKNOWN") { exit 3 }

param([int]$Pid2 = 0, [string]$Img = "", [switch]$Debug)
# wxpopup.ps1 v2 - 弹窗分类器 OCR 化（2026-10-27，用户定版：结合 OCR 升级弹窗判断体系）
# 背景：v1 正文区像素模板匹配对正文行位置浮动脆弱——「长时间未操作，请重新登录」弹窗正文
#   较模板下移 ~16px 即 d_idle=0.939 全灭误报 UNKNOWN（2026-10-27 实战复盘）。
#   正文是米黄大字、稳定可读 → OCR 读文字免疫位置浮动，模板子系统退役。
# 原理：金确定钮守卫带 (600,488)-(780,532) 像素计数判「弹窗在屏」（阈值 400，标定：
#   弹窗 788-1066 / 战斗·选角 0 / 主城 128）→ wxocr 自由扫描正文带 (350,348)-(800,408)
#   （v1 正文区 356-392 的 ±20px+ 浮动加宽容）→ 关键字分类（N 字命中容错，见第 4 步注释）。
# 分类与处置（红线规则，处置权在调用方）：
#   POPUP_NONE    无金确定钮（无弹窗；登录页金钮在带内计数不足亦 NONE/UNKNOWN，不再误判 IDLE）
#   POPUP_RELOGIN 顶号「账号在其他设备登录」        → 红线：停手请示用户（涉账号安全）
#   POPUP_IDLE    挂机「长时间未操作，请重新登录」  → 可点确定 (700,513)
#   POPUP_EXTEND  角色栏扩展券（涉商城）            → 只点取消 (471,502)
#   POPUP_REVIVE  死亡「…不死鸟羽毛…」             → 可点确定（用户已授权羽毛复活）
#   POPUP_UNKNOWN 有金钮但正文不认识/读不出        → 红线：停手请示用户
# 输出: POPUP=<cls> ocr_raw=[..] goldbtn=N；RELOGIN/UNKNOWN exit 3（wxgrind 按 POPUP_IDLE 子串分流，兼容 v1）
# -Img 离线模式供标定/回归（传完整客户区截图）；默认实时截屏（-Pid2 0=按标题自动发现）
. (Join-Path $PSScriptRoot '_wxcommon.ps1')
$scripts = $PSScriptRoot

$GOLDX0 = 600; $GOLDY0 = 488; $GOLDX1 = 780; $GOLDY1 = 532   # 金确定钮守卫带
$BX0 = 350; $BY0 = 348; $BX1 = 800; $BY1 = 408               # 正文带（容忍正文行位置浮动）

# ---- 1) 取设计坐标位图（离线 -Img / 实时抓屏统一到 1138x708）----
if ($Img -ne "") {
    if (-not (Test-Path $Img)) { "ERR: image not found: $Img"; exit 4 }
    $bmp = New-Object System.Drawing.Bitmap $Img
    if ($bmp.Width -lt 800 -or $bmp.Height -lt 550) {
        $bmp.Dispose(); "ERR: image $($bmp.Width)x$($bmp.Height) 过小，-Img 需传完整客户端区截图"; exit 4
    }
    if ($bmp.Width -ne $WX_DESIGN_W -or $bmp.Height -ne $WX_DESIGN_H) {
        $norm = Resize-WxBitmapNearest $bmp $WX_DESIGN_W $WX_DESIGN_H
        if (-not [object]::ReferenceEquals($norm, $bmp)) { $bmp.Dispose() }
        $bmp = $norm
    }
} else {
    $h = Find-GameWindow -Pid2 $Pid2
    if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $geo = Get-ClientGeometry $h
    $bmp = Get-DesignBitmap $geo
}

# ---- 2) 金确定钮计数 ----
$goldBtn = 0
for ($y = $GOLDY0; $y -le $GOLDY1; $y += 2) { for ($x = $GOLDX0; $x -le $GOLDX1; $x += 2) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.R -gt 200 -and $c.G -gt 140 -and $c.B -lt 110 -and ($c.R - $c.B) -gt 90) { $goldBtn++ }
} }

# ---- 3) OCR 正文带（有金钮才扫；实时模式把设计位图落临时盘复用 wxocr -Img，避免二次抓屏竞态）----
$raw = ""
if ($goldBtn -ge 400) {
    $tmpPng = $Img
    if ($tmpPng -eq "") {
        $tmpPng = Join-Path $env:TEMP ("wrx_popup_" + [guid]::NewGuid().ToString('N') + ".png")
        $bmp.Save($tmpPng, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "$scripts\wxocr.ps1" -Img $tmpPng -X0 $BX0 -Y0 $BY0 -X1 $BX1 -Y1 $BY1 2>&1
    $joined = ($out | ForEach-Object { "$_" }) -join ' '
    if ($joined -match 'OCR_RAW=\[(.*)\]') { $raw = $Matches[1] }
    if ($Img -eq "" -and (Test-Path $tmpPng)) { Remove-Item $tmpPng -Force }
}
$bmp.Dispose()

# ---- 4) 分类（顺序=优先级；2026-10-27 20:3x 用户定版：OCR 全面 N 字命中容错——
#      原 Contains 精确子串零容差作废，实机「重→谲」漏判 POPUP_IDLE 即根因。
#      N 随关键字长度自动定（_wxcommon Get-WxAutoMinHit）：其他设备/重新登录 4字→3，
#      未操作/扩展券 3字→2，羽毛 2字→2（2字无法再宽）。交叉检查：RELOGIN 正文含
#      「登录」2字 < 3 不会漏进 IDLE，优先级序保底）----
$cls = "POPUP_UNKNOWN"
if ($goldBtn -lt 400) { $cls = "POPUP_NONE" }
elseif (Test-WxKwHit $raw '其他设备') { $cls = "POPUP_RELOGIN" }
elseif ((Test-WxKwHit $raw '未操作') -or (Test-WxKwHit $raw '重新登录')) { $cls = "POPUP_IDLE" }
elseif (Test-WxKwHit $raw '扩展券') { $cls = "POPUP_EXTEND" }
elseif (Test-WxKwHit $raw '羽毛') { $cls = "POPUP_REVIVE" }
"POPUP=$cls ocr_raw=[$raw] goldbtn=$goldBtn"
if ($cls -eq "POPUP_RELOGIN" -or $cls -eq "POPUP_UNKNOWN") { exit 3 }

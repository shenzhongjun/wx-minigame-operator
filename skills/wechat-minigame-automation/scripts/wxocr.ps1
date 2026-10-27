param([int]$Pid2 = 0, [string]$Img = "", [string]$Task = "", [int]$X0 = 0, [int]$Y0 = 56, [int]$X1 = 200, [int]$Y1 = 115, [int]$F = 8, [switch]$NoInvert, [switch]$Debug)
# wxocr.ps1 - 通用 OCR 引擎（2026-10-26，合并 wxocrbtn.ps1 并任务化；用户定版：验证一律 OCR 优先）
# 两种用法：
#   1) -Task <name>  跑任务预设（区域+关键字判定内置），输出 OCR=<task>=<RESULT> raw=[文本]
#   2) 不带 -Task    自由扫描，-X0/-Y0/-X1/-Y1 指定设计坐标区域，输出原文 OCR_RAW=[文本]
# 任务预设表（新增任务=加一行；区域均为设计坐标 1138x708，含 55px 内嵌标题栏）：
#   autobtn  自动战斗按钮四字区 (184,169)-(272,193)：取消自动=ON / 自动战斗=OFF（原 wxocrbtn 锁定行为原样迁移，零容差）
#   charsel  选角页标题 (0,56)-(200,115)：含「选择角色」=HIT（选角页身份权威判定）
#   scr1     第一屏判据 (40,140)-(210,175)：卡1名字区，含「早睡早起身体好」任意3字=HIT（用户红框区域）
#   scr2     第二屏判据 (40,238)-(210,264)：卡5名字区（实测名字行 y≈241-259），含「豁达自在乐逍遥」任意3字=HIT；x 与 scr1 同宽窄条，上距横幅(232)6px、下距职业行(269)5px
# 匹配规则（2026-10-27 用户定版）：名字唯一，kw 任意 3 字命中即 HIT（漏字/错字/乱序免疫）；autobtn 零容差不变
# ⚠️ 公告横幅污染区 y≈206-232（橙色滚动公告，临时元素）——OCR 区域严禁跨入，scr1/scr2 已避开；
#    2026-10-27 实测教训：盲扫 195-255 被横幅「…龙脊战魔护腿…」搅成乱码
# 原理：设计坐标裁剪 → 灰度反相（白字→黑字深底→浅底，-NoInvert 关闭）→ 双三次放大 F 倍
#       → Windows.Media.Ocr(zh-Hans，零第三方依赖) → 关键字/原文输出。单次 ~250ms，Token 消耗与探针同量级。
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$tasks = @{
    autobtn = @{ x0 = 184; y0 = 169; x1 = 272; y1 = 193; kind = 'auto' }
    charsel = @{ x0 = 0;   y0 = 56;  x1 = 200; y1 = 115; kind = 'kw'; kw = '选择角色'; tol = 1 }
    scr1    = @{ x0 = 40;  y0 = 140; x1 = 210; y1 = 175; kind = 'kw'; kw = '早睡早起身体好'; minhit = 3 }
    scr2    = @{ x0 = 40;  y0 = 238; x1 = 210; y1 = 264; kind = 'kw'; kw = '豁达自在乐逍遥'; minhit = 3 }
}

$kind = 'raw'
if ($Task -ne "") {
    if (-not $tasks.ContainsKey($Task)) { "ERR: unknown task '$Task'（可用: $($tasks.Keys -join ', '))"; exit 4 }
    $t = $tasks[$Task]
    $X0 = $t.x0; $Y0 = $t.y0; $X1 = $t.x1; $Y1 = $t.y1
    $kind = $t.kind
}

if ($Img -ne "") {
    if (-not (Test-Path $Img)) { "ERR: image not found: $Img"; exit 4 }
    $bmp = New-Object System.Drawing.Bitmap $Img
    if ($bmp.Width -lt 200 -or $bmp.Height -lt 150) {
        "ERR: image $($bmp.Width)x$($bmp.Height) 过小，-Img 需传完整客户区截图"; exit 4
    }
    if ($bmp.Width -ne $WX_DESIGN_W -or $bmp.Height -ne $WX_DESIGN_H) {
        $norm = Resize-WxBitmapNearest $bmp $WX_DESIGN_W $WX_DESIGN_H
        if (-not [object]::ReferenceEquals($norm, $bmp)) { $bmp.Dispose() }
        $bmp = $norm
    }
} else {
    $hwnd = Find-GameWindow -Pid2 $Pid2
    if ($hwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $geo = Get-ClientGeometry $hwnd
    $bmp = Get-DesignBitmap $geo
}
if ($X1 -ge $bmp.Width -or $Y1 -ge $bmp.Height -or $X0 -lt 0 -or $Y0 -lt 0 -or $X0 -gt $X1 -or $Y0 -gt $Y1) {
    $bmp.Dispose(); "ERR: OCR 区域非法 ($X0,$Y0)-($X1,$Y1)"; exit 4
}

$bw = $X1 - $X0 + 1; $bh = $Y1 - $Y0 + 1
$gs = New-Object System.Drawing.Bitmap $bw, $bh
for ($y = 0; $y -lt $bh; $y++) {
    for ($x = 0; $x -lt $bw; $x++) {
        $c = $bmp.GetPixel($X0 + $x, $Y0 + $y)
        if ($NoInvert) {
            $gray = [int](0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B)
        } else {
            $gray = 245 - [int](0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B)
        }
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

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.DataWriter, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function Await($op, $type) {
    $t = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
    $t.Wait(-1) | Out-Null
    return $t.Result
}

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('zh-Hans-CN'))
if (-not $engine) { "OCR=UNAVAILABLE"; exit 0 }

$ras = [Windows.Storage.Streams.InMemoryRandomAccessStream]::new()
$dw = [Windows.Storage.Streams.DataWriter]::new($ras)
$dw.WriteBytes($bytes)
Await ($dw.StoreAsync()) ([uint32]) | Out-Null
$dw.DetachStream() | Out-Null
$ras.Seek(0)
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
$sb = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$res = Await ($engine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
$ras.Dispose()

# 容差规则（用户 2026-10-26 定版）：页面身份类任务（kind=kw）允许 1 字替换容差
#   （实测 0.476× 小窗「选择角色」被 OCR 误读为「选捧角色」，精确匹配 MISS）；增删字不在容差内。
#   autobtn ON/OFF 判定保持零容差（有模板匹配主判定兜底，误判代价不对等）。
function Test-FuzzyText([string]$text, [string]$kw, [int]$maxDiff) {
    if ($text.Length -lt $kw.Length) { return $false }
    for ($i = 0; $i -le $text.Length - $kw.Length; $i++) {
        $diff = 0
        for ($j = 0; $j -lt $kw.Length; $j++) { if ($text[$i + $j] -cne $kw[$j]) { $diff++ } }
        if ($diff -le $maxDiff) { return $true }
    }
    return $false
}

$text = ($res.Text -replace '\s+', '')
if ($kind -eq 'auto') {
    # 原 wxocrbtn 锁定行为：只认明确关键字，宁可 UNKNOWN 不可误判（零容差）
    $cls = "UNKNOWN"
    if ($text.Contains('取消自动')) { $cls = "ON" }
    elseif ($text.Contains('自动战斗')) { $cls = "OFF" }
    "OCR=autobtn=$cls raw=[$text]"
} elseif ($kind -eq 'kw') {
    # 匹配规则（用户 2026-10-27 定版）：名字唯一，容错从宽——关键字任意 3 个字（去重）出现在
    # OCR 文本即 HIT（漏字/错字/乱序全免疫，如「早睡早起身体好」被吞成「早早起身体好」仍命中）。
    # tol 子序列替换匹配保留作次级兜底；autobtn 不走此分支（零容差）。
    $kw = $tasks[$Task].kw
    $minhit = 3; if ($t -and $t.Contains('minhit')) { $minhit = $t.minhit }
    $tol = 1; if ($t -and $t.Contains('tol')) { $tol = $t.tol }
    $hit = $text.Contains($kw)
    if (-not $hit -and $minhit -gt 0) {
        $cnt = 0
        foreach ($ch in ($kw.ToCharArray() | Select-Object -Unique)) { if ($text.Contains([string]$ch)) { $cnt++ } }
        $hit = ($cnt -ge $minhit)
    }
    if (-not $hit) { $hit = Test-FuzzyText $text $kw $tol }
    "OCR=$Task=$(if ($hit) { 'HIT' } else { 'MISS' }) raw=[$text]"
} else {
    if ($text -eq "") { "OCR_RAW=EMPTY" } else { "OCR_RAW=[$text]" }
}
if ($Debug) { "debug: task=$Task region=($X0,$Y0)-($X1,$Y1) scale=$F lines=$($res.Lines.Count) invert=$(-not $NoInvert)" }

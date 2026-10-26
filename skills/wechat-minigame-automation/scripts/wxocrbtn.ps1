param([int]$Pid2 = 0, [string]$Img = "", [int]$F = 8, [switch]$Debug)
# 自动战斗按钮 OCR 二次意见（2026-10-26 新增）
# 定位：只做兜底，不取代模板匹配。模板匹配 10ms 且回归锁定；OCR 仅在 Jaccard 判 UNKNOWN 时确认文字。
# 原理：裁完整四字区 (184,169)-(272,193)（模板区 195-253 会裁掉首尾字）→ 灰度反相
#       （白字→黑字、深底→浅底）→ 双三次放大 F 倍 → Windows.Media.Ocr(zh-Hans) → 关键字包含匹配。
# 实测（2026-10-26，4 张实拍，F=6/8/10 结果一致）：关态读「自动战斗」（末尾可能残留一个「一」），
#   开态读「取消自动」；二值化预处理会误读成「乩二」甚至空白，故必须走灰度反相。
#   主城/塔页/选角页该区域无文字 → 返回空 → UNKNOWN（无假阳性）。
# 输出：BTN_OCR=ON|OFF|UNKNOWN|UNAVAILABLE ocr=[识别文本]
#   ON=含「取消自动」  OFF=含「自动战斗」  其余一律 UNKNOWN（宁可不知，不可误判）
# -Img 离线模式（任意尺寸自动归一化到 1138x708）；默认实时截屏（-Pid2 0=按标题自动发现）
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$RX0 = 184; $RY0 = 169; $RX1 = 272; $RY1 = 193   # 完整四字区（设计坐标）

if ($Img -ne "") {
    if (-not (Test-Path $Img)) { "ERR: image not found: $Img"; exit 4 }
    $bmp = New-Object System.Drawing.Bitmap $Img
    if ($bmp.Width -lt 200 -or $bmp.Height -lt 150) {
        "ERR: image $($bmp.Width)x$($bmp.Height) 过小，-Img 需传完整客户端区截图"; exit 4
    }
    if ($bmp.Width -ne $WX_DESIGN_W -or $bmp.Height -ne $WX_DESIGN_H) {
        $norm = Resize-WxBitmapNearest $bmp $WX_DESIGN_W $WX_DESIGN_H
        if (-not [object]::ReferenceEquals($norm, $bmp)) { $bmp.Dispose() }
        $bmp = $norm
    }
} else {
    $hwnd = Find-GameWindow -Pid2 $Pid2   # 句柄名避开 $H，历史事件：$h 与 $H 大小写不敏感冲突
    if ($hwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $geo = Get-ClientGeometry $hwnd
    $bmp = Get-DesignBitmap $geo
}
if ($RX1 -ge $bmp.Width -or $RY1 -ge $bmp.Height) { $bmp.Dispose(); "ERR: OCR 区域超出画面"; exit 4 }

# 灰度反相预处理：lum → 245-lum，白字变黑字，深色按钮底变浅色，符合 OCR 偏好的黑字白底
$bw = $RX1 - $RX0 + 1; $bh = $RY1 - $RY0 + 1
$gs = New-Object System.Drawing.Bitmap $bw, $bh
for ($y = 0; $y -lt $bh; $y++) {
    for ($x = 0; $x -lt $bw; $x++) {
        $c = $bmp.GetPixel($RX0 + $x, $RY0 + $y)
        $gray = 245 - [int](0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B)
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
if (-not $engine) { "BTN_OCR=UNAVAILABLE ocr=[]"; exit 0 }

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

$text = ($res.Text -replace '\s+', '')
$cls = "UNKNOWN"
if ($text.Contains('取消自动')) { $cls = "ON" }
elseif ($text.Contains('自动战斗')) { $cls = "OFF" }
"BTN_OCR=$cls ocr=[$text]"
if ($Debug) { "debug: region=($RX0,$RY0)-($RX1,$RY1) scale=$F lines=$($res.Lines.Count)" }

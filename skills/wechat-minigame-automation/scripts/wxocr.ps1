param([int]$Pid2 = 0, [string]$Img = "", [string]$Task = "", [int]$X0 = 0, [int]$Y0 = 56, [int]$X1 = 200, [int]$Y1 = 115, [int]$F = 8, [switch]$NoInvert, [switch]$Debug)
# wxocr.ps1 - 通用 OCR 引擎（2026-10-26，合并 wxocrbtn.ps1 并任务化；用户定版：验证一律 OCR 优先）
# 两种用法：
#   1) -Task <name>  跑任务预设（区域+关键字判定内置），输出 OCR=<task>=<RESULT> raw=[文本]
#   2) 不带 -Task    自由扫描，-X0/-Y0/-X1/-Y1 指定设计坐标区域，输出原文 OCR_RAW=[文本]
# 任务预设表（新增任务=加一行；区域均为设计坐标 1138x708，含 55px 内嵌标题栏）：
#   autobtn  自动战斗按钮四字区 (175,158)-(275,195)：取消自动=ON / 自动战斗=OFF（v2 扩边定版
#            2026-10-27 深夜：用户素材图 1178×744 实测文字带=设计 y164-184（两态同位，红框裁剪
#            目验+像素画像），旧区 (184,169)-(272,193) 上缘贴字易读空，扩边后覆盖 158-195。
#            战斗页无公告横幅，下界 195 无污染风险。点击锚点=按钮中心 (215,172) 见 coords.md。
#            N 字命中容错（4字→3，两词共享「自动」2字<3 无交叉误判）不变）
#   charsel  选角页标题 (0,56)-(200,115)：含「选择角色」=HIT（选角页身份权威判定）
#   scr1     第一屏判据 (40,140)-(210,175)：卡1名字区，含「早睡早起身体好」任意3字=HIT（用户红框区域）
#   scr2     第二屏判据 (40,238)-(210,264)：卡5名字区（实测名字行 y≈241-259），含「豁达自在乐逍遥」任意3字=HIT；x 与 scr1 同宽窄条，上距横幅(232)6px、下距职业行(269)5px
#   scr1w    第一屏升级判据 (36,130)-(215,204)：卡1名字+职业信息条整块（2026-10-27 用户红框定版），
#            kw「早睡早起身体好」+ kw2「圣骑士」合并任意3字命中=HIT。宽区域带上下文，解决窄条
#            在 S≈1.043 大窗下 OCR 读空问题（用户裁定「既然条小了不好判断，那就放大」）；
#            下界 204 收在公告横幅污染区(206-232)之外，勿跨入。
#   scr2w    第二屏升级判据 (36,234)-(215,290)：卡5名字+职业信息条整块（2026-10-27 用户红框定版），
#            kw「豁达自在乐逍遥」+ kw2「重装机兵」合并任意3字=HIT；上界 234 避横幅(232)，
#            下界 290 收在职业行(269-288)之下、体力行之上，勿随意扩大。
#   town     主城判据 (140,158)-(270,192)：左上「◀ 选角」按钮整块+周围一圈边距（2026-10-27 22:5x
#            用户定版「不能只扫一小块区域，必须连周围一圈也包括在内」），kw「选角」minhit=2=HIT。
#            「选角」仅2字，N 字命中规则下 2字→N=2（1字命中必撞车选角页标题「选择角色」），等效零容差。
#            边界依据（2026-10-27 22:4x 实测隔离）：上界 158=头像下缘、下界 192=公告横幅顶缘
#            （⚠️ 横幅顶缘实测 ~193，旧档案「206-232」证伪更正——下界 196/200 会整区读空），
#            横向 ±18/20px 边距容忍窗口尺寸变化的位置微移。区域 (140,158)-(270,192)。
#   server   登录页判据 (488,455)-(638,492)：深蓝横条白字服务器名，kw「巨龙山脉」（数字区号可变不含），
#            minhit=3（2026-10-27 晚修正：原零容差被单字误读击穿——888×574 下「脉→豚」raw=[巨龙山豚17]
#            MISS 致登录页漏判；该区域仅登录页有此字样、无撞车风险，按用户匹配哲学改任意3字命中）。
#            2026-10-27 用户定版：登录页身份唯一判据（「进入游戏」为风格化美术字 OCR 读不动，
#            已放弃不做任务；旧区域 (440,505)-(735,556) 切字底缘曾致「透人游咙」误读，勿再尝试）。
# 匹配规则（2026-10-27 20:3x 用户定版·全面 N 字命中；23:0x 补铁律）：所有 OCR 关键字匹配统一
#   N 字命中（宁宽勿严），N 随关键字长度自动定：2字=2、3-4字=N-1、5-7字=3、8字+=4
#   （见 _wxcommon Get-WxAutoMinHit）；任务可显式 minhit 覆盖（scr1w/scr2w 合并池 3 字为用户定版值）。
# ⚠️ 2 字关键字=N=2=零容差（用户 23:0x 定版铁律：「选角」读成「选鱼」=1 命中=必须 MISS，
#   错一个字都不行，1 字命中必撞车选角页标题「选择角色」）。宁宽勿严只对 ≥3 字生效。
# ⚠️ 2026-10-27 23:0x 事故修复：旧「1 字替换容差 Test-FuzzyText」兜底已彻底删除——
#   残留兜底曾使「选鱼」对「选角」diff=1 被放行，直接击穿 2 字零容差（用户怒斥定版）。
#   N 字命中本身已覆盖替换类误读（N-1 字命中在容差内），任何形式的二次兜底严禁再加。
# kw2（可选，2026-10-27 16:1x 用户定版）：第二关键字**并入字符池**，与 kw 合并去重后任意 minhit 字命中
#   即 HIT（用户纠正原话：「kw+kw2 一共任意 3 字命中就行了」，不是 kw2 全字命中）
# ⚠️ 公告横幅污染区：实测顶缘 ~193（2026-10-27 22:4x 隔离定版：下界 192 能读、196 读空；
#    旧档案「206-232」证伪更正）——OCR 区域下界严禁 ≥193；横幅为临时滚动元素，时有时无。
#    2026-10-27 实测教训：盲扫 195-255 被横幅「…龙脊战魔护腿…」搅成乱码
# 原理：设计坐标裁剪 → 灰度反相（白字→黑字深底→浅底，-NoInvert 关闭）→ 双三次放大 F 倍
#       → Windows.Media.Ocr(zh-Hans，零第三方依赖) → 关键字/原文输出。单次 ~250ms，Token 消耗与探针同量级。
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$tasks = @{
    autobtn = @{ x0 = 175; y0 = 158; x1 = 275; y1 = 195; kind = 'auto'; f = 12 }
    charsel = @{ x0 = 0;   y0 = 56;  x1 = 200; y1 = 115; kind = 'kw'; kw = '选择角色' }
    scr1    = @{ x0 = 40;  y0 = 140; x1 = 210; y1 = 175; kind = 'kw'; kw = '早睡早起身体好'; minhit = 3 }
    scr2    = @{ x0 = 40;  y0 = 238; x1 = 210; y1 = 264; kind = 'kw'; kw = '豁达自在乐逍遥'; minhit = 3 }
    scr1w   = @{ x0 = 36;  y0 = 130; x1 = 215; y1 = 204; kind = 'kw'; kw = '早睡早起身体好'; minhit = 3; kw2 = '圣骑士' }
    scr2w   = @{ x0 = 36;  y0 = 234; x1 = 215; y1 = 290; kind = 'kw'; kw = '豁达自在乐逍遥'; minhit = 3; kw2 = '重装机兵' }
    town    = @{ x0 = 140; y0 = 158; x1 = 270; y1 = 192; kind = 'kw'; kw = '选角'; minhit = 2 }
    server  = @{ x0 = 488; y0 = 455; x1 = 638; y1 = 492; kind = 'kw'; kw = '巨龙山脉'; minhit = 3 }
}

$kind = 'raw'
if ($Task -ne "") {
    if (-not $tasks.ContainsKey($Task)) { "ERR: unknown task '$Task'（可用: $($tasks.Keys -join ', '))"; exit 4 }
    $t = $tasks[$Task]
    $X0 = $t.x0; $Y0 = $t.y0; $X1 = $t.x1; $Y1 = $t.y1
    $kind = $t.kind
    if ($t.Contains('f')) { $F = $t.f }   # 任务级放大倍数覆盖（autobtn F=12 离线扫参定版 2026-10-27 深夜）
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
    # 小窗守卫（2026-10-27 17:4x 用户定版）：宽 <800 实测 OCR 全读空（S≈0.609 数据），直接停机
    if (-not (Test-WxMinClientW $geo.W)) { "ERR: window too small ($($geo.W)x$($geo.H) < ${WX_MIN_CLIENT_W} width)，OCR 拒读"; exit 7 }
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

$text = ($res.Text -replace '\s+', '')
if ($kind -eq 'auto') {
    # 2026-10-27 20:3x 用户定版：OCR 全面 N 字命中——autobtn 原零容差作废（4字→N=3，
    # 两词共享「自动」2字<3 无交叉误判）；ON 优先判定不变。模板匹配主判定兜底不变。
    $cls = "UNKNOWN"
    if (Test-WxKwHit $text '取消自动') { $cls = "ON" }
    elseif (Test-WxKwHit $text '自动战斗') { $cls = "OFF" }
    "OCR=autobtn=$cls raw=[$text]"
} elseif ($kind -eq 'kw') {
    # 匹配规则（2026-10-27 20:3x 用户定版·全面 N 字命中，宁宽勿严；23:0x 铁律补）：字符池去重后
    # 命中数达 N 即 HIT（漏字/错字/乱序全免疫）。N 默认按关键字长度自动定（Get-WxAutoMinHit），
    # 任务显式 minhit 可覆盖。⚠️ 2 字关键字 N=2 零容差，错一字即 MISS；无任何二次兜底。
    $kw = $tasks[$Task].kw
    $minhit = 0; if ($t -and $t.Contains('minhit')) { $minhit = $t.minhit }
    # kw2（可选）：第二关键字并入字符池，与 kw 合并去重后任意 N 字命中即 HIT
    $pool = $kw
    $kw2 = ''
    if ($t -and $t.Contains('kw2')) { $kw2 = $t.kw2; $pool = "$kw$kw2" }
    $hit = $text.Contains($kw) -or ($kw2 -ne '' -and $text.Contains($kw2))
    if (-not $hit) { $hit = Test-WxKwHit $text $pool $minhit }
    "OCR=$Task=$(if ($hit) { 'HIT' } else { 'MISS' }) raw=[$text]"
} else {
    if ($text -eq "") { "OCR_RAW=EMPTY" } else { "OCR_RAW=[$text]" }
}
if ($Debug) { "debug: task=$Task region=($X0,$Y0)-($X1,$Y1) scale=$F lines=$($res.Lines.Count) invert=$(-not $NoInvert)" }

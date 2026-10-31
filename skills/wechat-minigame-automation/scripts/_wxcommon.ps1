# _wxcommon.ps1 - 公共库（体系重打磨 P1，2026-10-25）
# 单一真相源：客户端尺寸、按钮模板区、窗口查找、尺寸断言、模板匹配。
# 所有画面交互脚本 dot-source 本文件，禁止再在脚本内复制 P/Invoke 样板或区域常量。
# 修改本文件 = 修改全部脚本的共同行为；改动后必须跑 wxregress.ps1 离线回归。
# ⚠️ 2026-10-26 用户裁定：wxregress 清单系 AI 标注未经人工核验，暂停使用；恢复前改动验证以实机探针+截图目验替代。

# ---- 配置区（设计坐标系，改动须用户确认并同步 coords.md）----
# 设计坐标系：文档/区域常量/模板均以 1138x708 为基准，运行时由 Get-ClientGeometry 换算到实时屏幕。
$WX_DESIGN_W = 1138                 # 设计基准尺寸（2026-10-25 用户定版，布局严格等比）
$WX_DESIGN_H = 708
$WX_CLIENT_W = $WX_DESIGN_W         # 兼容旧名，含义等同设计基准
$WX_CLIENT_H = $WX_DESIGN_H
$WX_WINDOW_TITLE = '勇士之心'        # 窗口标题匹配针
$WX_BTN_X0 = 196; $WX_BTN_Y0 = 143  # 自动战斗按钮文字+图标区（v1.1.14 新管线重标定 2026-10-28，
$WX_BTN_X1 = 252; $WX_BTN_Y1 = 187  #    用户 9 状态截图离线实测；旧区 (195,175)-(253,187) 只框住笔画
                                    #    稀疏底部已作废。实离线验证: battleOFF dOff=0/dOn=0.46, battleON 反之）
$WX_BTN_CLICK_X = 224; $WX_BTN_CLICK_Y = 181   # ⚠️ 已作废（v1.1.10 锚点=(215,172)）；仅存留勿用
# 微信小游戏内嵌标题栏（客户区顶部白条「勇士之心」+胶囊按钮）：固定高度，不随窗口缩放。
# 2026-10-26 wxcanvas.ps1 实测两尺寸（650x431 / 1967x1192）chrome 均=55px 坐实。
# 设计基准 1138x708 的 0-54 行即此标题栏；游戏画布=设计 55-707 行（653px 高，等比缩放）。
# 审计工具：wxcanvas.ps1（chrome/bars 实测，与常量不符时更新本值）。
$WX_CHROME_H = 55

if (-not ('WXCommon' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WXCommon {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool AdjustWindowRect(ref RECT r, uint style, bool menu);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int nIndex);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Found = IntPtr.Zero;      // 标题匹配命中的窗口
  public static IntPtr Fallback = IntPtr.Zero;   // pid 下第一个可见窗口（兜底）
  public static int TargetPid = 0;
  public static string Needle = "";
  public static bool Cb(IntPtr h, IntPtr l) {
    if (!IsWindowVisible(h)) return true;
    uint pid; GetWindowThreadProcessId(h, out pid);
    if ((int)pid != TargetPid) return true;
    if (Found != IntPtr.Zero) return false;
    StringBuilder sb = new StringBuilder(256);
    GetWindowTextW(h, sb, 256);
    string t = sb.ToString();
    if (Needle.Length > 0 && t.Contains(Needle)) { Found = h; return false; }
    if (Fallback == IntPtr.Zero) Fallback = h;
    return true;
  }
}
'@
}
if (-not ('System.Drawing.Bitmap' -as [type])) { Add-Type -AssemblyName System.Drawing }

# ---- 窗口查找：Pid2>0 时在该进程内标题优先匹配；Pid2<=0 时按标题自动发现进程（P4 修复 wxshot 选错窗口 bug）----
function Find-GameWindow {
    param([int]$Pid2 = 0)
    [WXCommon]::SetProcessDPIAware() | Out-Null
    [WXCommon]::Found = [IntPtr]::Zero
    [WXCommon]::Fallback = [IntPtr]::Zero
    if ($Pid2 -gt 0) {
        $proc = Get-Process -Id $Pid2 -ErrorAction SilentlyContinue
        if (-not $proc) { return [IntPtr]::Zero }
        [WXCommon]::TargetPid = $Pid2
        [WXCommon]::Needle = $WX_WINDOW_TITLE
    } else {
        $proc = Get-Process WeChatAppEx -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle -like "*$WX_WINDOW_TITLE*" } | Select-Object -First 1
        if (-not $proc) { return [IntPtr]::Zero }
        [WXCommon]::TargetPid = $proc.Id
        [WXCommon]::Needle = $proc.MainWindowTitle
    }
    [WXCommon]::EnumWindows([WXCommon+EnumProc]{ param($h,$l) [WXCommon]::Cb($h,$l) }, [IntPtr]::Zero) | Out-Null
    if ([WXCommon]::Found -ne [IntPtr]::Zero) { return [WXCommon]::Found }
    return [WXCommon]::Fallback
}

# ---- 客户区几何：读尺寸+原点，并给出设计坐标→屏幕的换算参数 ----
# ═══════════════════════════════════════════════════════════════════
# 55px 内嵌标题栏模型（唯一权威表述，2026-10-26 wxcanvas 两尺寸实测定版）：
#   客户区物理结构 = [顶部 55 物理px 微信内嵌标题栏（白条「勇士之心」+胶囊按钮，固定不缩放）]
#                    + [游戏画布（随窗口等比缩放；横向居中留边 + **垂直居中留边，上下黑条等宽**，
#                       2026-10-28 用户定版——旧版漏记垂直居中，曾致 OCR 区域随窗口缩放漂移读空）]
#   设计坐标系 1138x708 = 虚拟截图坐标系：0-54 行「占位」表示标题栏（不属于游戏画面），
#   游戏内容全部在 设计 55-707 行（1138x653）。coords.md/模板/OCR 区域全部用设计坐标。
#   画布缩放 S = min(W/1138, (H-55)/653)——55 只出现在「减去」这一处，S 与标题栏无关。
# 换算公式（双向）：
#   正向(点击)  screen_x = OX + OFFX + x*S
#               screen_y = OY + 55 + (y-55)*S        ← 先减 55 再乘 S 再加回 55
#   反向(标定)  design_x = (screen_x - OX - OFFX)/S
#               design_y = 55 + (screen_y - OY - 55)/S  ← ⚠️ 漏掉内层 55 就会偏约 55*S 像素
#   实算例（客户区 1187x748 → S=1.043，设 OY=180）：设计(196,179) →
#     screen_y = 180 + 55 + (179-55)*1.043 = 180+55+129 = 364；
#     反向 364 → 55 + (364-180-55)/1.043 = 55 + 124 = 179 ✓ 闭环。
#   **运行时/标定一律调 ConvertTo-ScreenPoint / ConvertFrom-ScreenPoint，严禁手算**（铁律）。
# 基准 1138x708 时 S=1，与旧全客户区模型重合，已验证坐标零失效。任意窗口尺寸（含非等比/缩小窗）可换算。
# ⚠️ 三种抓图的坐标语义（混淆高发点，2026-10-27 23:0x 用户令固化）：
#   wxshot（无 -Raw）→ 1138x708 设计位图，量出来的坐标=设计坐标，直接对照 coords.md；
#   wxshot -Raw     → 仅画布实时尺寸（无标题栏），量出的 y 是画布相对值，design_y = 55 + y/S；
#   wxocr -Task     → 在归一化设计位图上裁剪，任务区域=设计坐标，无需任何换算。
# ═══════════════════════════════════════════════════════════════════
function Get-ClientGeometry {
    param([IntPtr]$h, [switch]$NoAssert, [switch]$Exact)
    $cr = New-Object WXCommon+RECT; [WXCommon]::GetClientRect($h, [ref]$cr) | Out-Null
    $pt = New-Object WXCommon+POINT; $pt.X = 0; $pt.Y = 0; [WXCommon]::ClientToScreen($h, [ref]$pt) | Out-Null
    $W = $cr.R; $H = $cr.B; $ch = $WX_CHROME_H
    $sx = $W / $WX_DESIGN_W
    $sy = ($H - $ch) / ($WX_DESIGN_H - $ch)
    $s = [math]::Min($sx, $sy)
    if (-not $NoAssert) {
        if ($Exact -and ($W -ne $WX_DESIGN_W -or $H -ne $WX_DESIGN_H)) {
            Write-Output "ERR: client=$($W)x$($H) 需精确等于设计尺寸 $($WX_DESIGN_W)x$($WX_DESIGN_H)（维护工具请先跑 wxresize.ps1）"
            exit 8
        }
        if ($s -lt 0.40 -or $s -gt 2.0) {
            Write-Output "ERR: client=$($W)x$($H) 缩放系数 $([math]::Round($s,3)) 超出 0.40-2.0，停机请用户核对窗口"
            exit 8
        }
    }
    $offX = ($W - $WX_DESIGN_W * $s) / 2
    # 画布物理顶边（2026-10-28 用户定版：游戏画布在标题栏下方区域**垂直居中**，上下黑条等宽）。
    # 垂直富余 = (H-55) - 653*S，恒 >=0（S 取 min 保证）；画布顶 = 55 + 富余/2。
    # ⚠️ OFFY 保持 = chrome(55)：历史档案坐标体系以「顶贴模型」语言标定，点击换算沿用旧语义
    #    （标定偏差与换算偏差互相抵消，实测准确，禁动）；CANVASTOP 仅供抓图归一化使用，
    #    保证归一化位图内容与窗口尺寸无关（根治 OCR 区域随缩放漂移）。
    $canvasTop = $ch + (($H - $ch) - ($WX_DESIGN_H - $ch) * $s) / 2
    [pscustomobject]@{ W = $W; H = $H; OX = $pt.X; OY = $pt.Y; S = $s; SX = $sx; SY = $sy; OFFX = $offX; OFFY = $ch; CANVASTOP = $canvasTop; CHROME = $ch }
}

# ---- 设计坐标 → 屏幕坐标（点击/采样前调用）----
# ⚠️ 唯一换算入口：设计坐标→屏幕一律走本函数，严禁在调用方手算 55px 偏移（见上方模型注释）
# 纵向：设计 0-54 行=标题栏（固定 55px 不缩放），画布行自设计 55 起以 S 缩放
function ConvertTo-ScreenPoint {
    param($g, [int]$x, [int]$y)
    [pscustomobject]@{
        X = [int][math]::Round($g.OX + $g.OFFX + $x * $g.S)
        Y = [int][math]::Round($g.OY + $g.OFFY + ($y - $g.OFFY) * $g.S)
    }
}

# ---- 屏幕坐标 → 设计坐标（诊断/截图标定用）----
# ⚠️ 唯一换算入口：屏幕坐标→设计一律走本函数（标定脚本也必须调它），严禁手算（见上方模型注释）
function ConvertFrom-ScreenPoint {
    param($g, [int]$x, [int]$y)
    [pscustomobject]@{
        X = [int][math]::Round(($x - $g.OX - $g.OFFX) / $g.S)
        Y = [int][math]::Round($g.OFFY + ($y - $g.OY - $g.OFFY) / $g.S)
    }
}

# ---- 前台守卫共享逻辑（2026-10-27 16:5x 用户定版）：检测到不在前台→log 留痕并拉回前台，
#      首拉 + 最多 2 次重试仍不在前台才判失败（是否 STOP 由调用方决定）；最小化先 SW_RESTORE。
#      log 走 Write-Host（信息流），不污染返回值管道。----
function Confirm-WxForeground([IntPtr]$h, [string]$label = 'game') {
    if ([WXCommon]::GetForegroundWindow() -eq $h) { return $true }
    Write-Host "WARN: $(Get-Date -Format 'HH:mm:ss') 检测到 $label 不在前台，拉回前台"
    if ([WXCommon]::IsIconic($h)) {
        [WXCommon]::ShowWindow($h, 9) | Out-Null    # SW_RESTORE
        Write-Host "WARN: $(Get-Date -Format 'HH:mm:ss') 窗口最小化中，已 SW_RESTORE"
    }
    for ($i = 1; $i -le 3; $i++) {                  # 首拉 + 2 次重试
        [WXCommon]::SetForegroundWindow($h) | Out-Null
        Start-Sleep -Milliseconds 600
        if ([WXCommon]::GetForegroundWindow() -eq $h) {
            Write-Host "WARN: $(Get-Date -Format 'HH:mm:ss') 第 $i 次拉回前台成功"
            return $true
        }
        Write-Host "WARN: $(Get-Date -Format 'HH:mm:ss') 第 $i 次拉回失败，仍不在前台"
    }
    return $false
}

# ---- 最小窗口宽度守卫（2026-10-27 17:4x 用户定版）：客户区宽 < 800 判失败（exit 7 由调用方定）。
#      依据：S≈0.609 (693x460) 实测 town/charsel OCR 全读空（数据见 tasks.md 17:3x 节），
#      小窗判定不可靠，宁可停机。wxocr -Img 离线路径不受此限（不涉实时窗口）。----
$WX_MIN_CLIENT_W = 800
function Test-WxMinClientW([int]$clientW) {
    if ($clientW -lt $WX_MIN_CLIENT_W) {
        Write-Host "WARN: client width $clientW < $WX_MIN_CLIENT_W（小窗 OCR 读空敏感区，用户定版停机线）"
        return $false
    }
    return $true
}

# ---- 礼包弹窗探测配置（2026-10-31 用户定版：弹窗一律归 wxpopup 判，wxprobe 只管场景状态）----
# 表驱动：以后遇到新礼包弹窗，标定完在这里追加一行即可，禁止在各脚本里散落坐标/阈值（单源）。
# 采样口径固定 x+=2 / y 逐行，阈值 = 全分辨率标定值 ÷ 2。
# 匹配顺序=数组顺序，先特异后兜底：带 Tag 的（如金卡，靠底部「今日不再弹出」白字区分）必须排在无 Tag 的前面。
#   CloseX/Y  = 关闭按钮（newbie 左上红叉 / jinka 左上金叉）
#   UncheckX/Y= 关闭前要点的勾选框（0,0 = 无）
#   Tag*      = 区分信号区与最小命中（TagMin=0 表示不判）
$WX_PACK_PROBES = @(
    # 金卡特权 ¥68：金钮区与 newbie 重合（实测宽谓词 5287 / 严谓词 4888），靠底部「今日不再弹出」白字区分（实测 309，新手礼包同区 0）
    # 金叉实测 bbox (273,201)-(295,221) → 中心 (284,211)；勾选框 (568,622) 为文字左界 585 左移推算
    # 2026-10-31 实机验证：金叉坐标点击后弹窗正确关闭 ✓；勾选已执行，能否生效需次日观察
    @{ Kind = 'jinka';  X0 = 529; Y0 = 520; X1 = 763; Y1 = 603; MinHit = 3000
       CloseX = 284; CloseY = 211; UncheckX = 568; UncheckY = 622
       TagX0 = 585; TagY0 = 612; TagX1 = 665; TagY1 = 635; TagMin = 150 }
    # 勇士启程 ¥30：全分辨率实测 9622 / 关闭后 2754；红叉 (160,192)
    # MinHit 1500→3000（2026-10-31 实机）：主城酒馆背景金钮区实测 1545 会误报，真弹窗 5101 仍有 1.7 倍余量
    @{ Kind = 'newbie'; X0 = 529; Y0 = 520; X1 = 763; Y1 = 603; MinHit = 3000
       CloseX = 160; CloseY = 192; UncheckX = 0; UncheckY = 0
       TagX0 = 0; TagY0 = 0; TagX1 = 0; TagY1 = 0; TagMin = 0 }
)
$WX_PRED_GOLD = { param($c) $c.R -ge 170 -and $c.G -ge 120 -and $c.B -le 140 -and ($c.R - $c.B) -ge 60 }
$WX_PACK_CLOSE_X = 160; $WX_PACK_CLOSE_Y = 192   # 兼容旧引用（新手礼包红叉）

# ---- 位图像素缓冲（2026-10-31 性能重写，wxprobe / wxpopup 共用）----
# 逐像素 $bmp.GetPixel() 单次 ~0.2ms，一笔 probe 4.3 万次 ≈ 9s；改 LockBits 一次取整图字节后按索引读。
# 锁位用图像自身 PixelFormat（24bpp=Rgb / 32bpp=Argb 都是 BGR 顺序），不做格式转换，避免 ±1 色彩漂移。
$script:PxBuf = $null; $script:PxStride = 0; $script:PxBpp = 4
function Init-PxBuf([System.Drawing.Bitmap]$bmp) {
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $bpp = [int]([System.Drawing.Image]::GetPixelFormatSize($bmp.PixelFormat) / 8)
    $work = $bmp; $disposeWork = $false
    if ($bpp -lt 3) {
        $work = New-Object System.Drawing.Bitmap $bmp.Width, $bmp.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gg = [System.Drawing.Graphics]::FromImage($work)
        $gg.DrawImage($bmp, 0, 0, $bmp.Width, $bmp.Height); $gg.Dispose()
        $bpp = 4; $disposeWork = $true
    }
    $data = $work.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $work.PixelFormat)
    $script:PxStride = $data.Stride
    $script:PxBpp = $bpp
    $script:PxBuf = New-Object byte[] ($data.Stride * $bmp.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $script:PxBuf, 0, $script:PxBuf.Length)
    $work.UnlockBits($data)
    if ($disposeWork) { $work.Dispose() }
}
# 区域内计数：stepX/stepY 采样步长；pred: 1=金按钮 3=白 5=town金 7=严金(gold2)
function Count-PxBox([int]$x0, [int]$y0, [int]$x1, [int]$y1, [int]$pred, [int]$stepX = 1, [int]$stepY = 1) {
    $buf = $script:PxBuf; $st = $script:PxStride; $bp = $script:PxBpp; $n = 0
    for ($y = $y0; $y -le $y1; $y += $stepY) {
        $row = $y * $st
        for ($x = $x0; $x -le $x1; $x += $stepX) {
            $i = $row + ($x * $bp)
            $b = $buf[$i]; $g = $buf[$i+1]; $r = $buf[$i+2]
            if ($pred -eq 1) { if ($r -gt 200 -and $g -gt 140 -and $b -lt 110 -and ($r-$b) -gt 90) { $n++ } }
            elseif ($pred -eq 3) { if ($r -ge 205 -and $g -ge 205 -and $b -ge 205) { $n++ } }
            elseif ($pred -eq 7) { if ($r -ge 215 -and $g -ge 185 -and $b -le 120 -and ($r-$b) -ge 100) { $n++ } }
            else { if ($r -ge 170 -and $g -ge 120 -and $b -le 140 -and ($r-$b) -ge 60) { $n++ } }
        }
    }
    return $n
}

# ---- OCR 关键字 N 字命中容错（2026-10-27 20:3x 用户定版：所有 OCR 匹配点统一 N 字命中，宁宽勿严）----
# N 按关键字长度自动定：2字=2（无法再宽，1字必撞车）；3-4字=N-1（容1错字）；5-7字=3；8字+=4
# 依据：不同字段重复概率很小（用户原话）；autobtn 两词共享「自动」2字 < 3，N=3 无交叉误判
function Get-WxAutoMinHit([string]$kw) {
    $n = ($kw.ToCharArray() | Select-Object -Unique).Count
    if ($n -le 2) { return $n }
    if ($n -le 4) { return $n - 1 }
    if ($n -le 7) { return 3 }
    return 4
}
# 字符池命中判定：pool 去重字符在 text 中命中数 >= minhit 即 $true；minhit<=0 时按长度自动定
function Test-WxKwHit([string]$text, [string]$pool, [int]$minhit = 0) {
    if ($minhit -lt 1) { $minhit = Get-WxAutoMinHit $pool }
    $cnt = 0
    foreach ($ch in ($pool.ToCharArray() | Select-Object -Unique)) { if ($text.Contains([string]$ch)) { $cnt++ } }
    return ($cnt -ge $minhit)
}

# ---- 最近邻缩放：保留原始 RGB，避免插值灰度污染色彩阈值与白掩码 ----
function Resize-WxBitmapNearest {
    param([System.Drawing.Bitmap]$src, [int]$w, [int]$h)
    if ($src.Width -eq $w -and $src.Height -eq $h) { return $src }
    $dst = New-Object System.Drawing.Bitmap $w, $h
    $gr = [System.Drawing.Graphics]::FromImage($dst)
    $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $gr.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $gr.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $w, $h))
    $gr.Dispose()
    return $dst
}

# ---- 实时抓图并归一化回设计尺寸：后续像素判定/模板匹配零改动 ----
# 只抓游戏画布区（客户区去掉 55px 标题栏），归一化到 1138x653 后贴回 1138x708 画布、
# 顶部 0-54 行填白（模拟标题栏）——输出即标准设计坐标位图，所有区域常量零改动。
# -Raw 保留画布实时尺寸（诊断缩放用；不含标题栏）。
function Get-DesignBitmap {
    param($g, [switch]$Raw)
    $vw = [int][math]::Round($WX_DESIGN_W * $g.S)
    $vh = [int][math]::Round(($WX_DESIGN_H - $g.CHROME) * $g.S)
    $cx = [int][math]::Round($g.OFFX)
    $src = New-Object System.Drawing.Bitmap $vw, $vh
    $gr = [System.Drawing.Graphics]::FromImage($src)
    # 从画布真实顶边（垂直居中位置）抓取，归一化后内容与窗口尺寸无关（2026-10-28 根治）
    $gr.CopyFromScreen($g.OX + $cx, $g.OY + $g.CANVASTOP, 0, 0, (New-Object System.Drawing.Size $vw, $vh))
    $gr.Dispose()
    if ($Raw) { return $src }
    $canvas = Resize-WxBitmapNearest $src $WX_DESIGN_W ($WX_DESIGN_H - $g.CHROME)
    if (-not [object]::ReferenceEquals($canvas, $src)) { $src.Dispose() }
    $dst = New-Object System.Drawing.Bitmap $WX_DESIGN_W, $WX_DESIGN_H
    $g2 = [System.Drawing.Graphics]::FromImage($dst)
    $g2.Clear([System.Drawing.Color]::White)
    $g2.DrawImage($canvas, 0, $g.CHROME)
    $g2.Dispose()
    if (-not [object]::ReferenceEquals($canvas, $dst)) { $canvas.Dispose() }
    return $dst
}

# ---- 抓取设计坐标区域并归一化到该区域设计尺寸（自动战斗按钮等小区域用）----
# 纵向按画布映射：screen_y = OY + 画布顶(垂直居中) + (design_y-55)*S（区域恒在设计 55 行以下）
function Get-DesignRegion {
    param($g, [int]$x0, [int]$y0, [int]$x1, [int]$y1)
    $dw = $x1 - $x0 + 1; $dh = $y1 - $y0 + 1
    $sw = [math]::Max(1, [int][math]::Round($dw * $g.S))
    $sh = [math]::Max(1, [int][math]::Round($dh * $g.S))
    $sx = [int][math]::Round($g.OFFX + $x0 * $g.S)
    $sy = [int][math]::Round($g.CANVASTOP + ($y0 - $g.CHROME) * $g.S)
    $src = New-Object System.Drawing.Bitmap $sw, $sh
    $gr = [System.Drawing.Graphics]::FromImage($src)
    $gr.CopyFromScreen($g.OX + $sx, $g.OY + $sy, 0, 0, (New-Object System.Drawing.Size $sw, $sh))
    $gr.Dispose()
    $dst = Resize-WxBitmapNearest $src $dw $dh
    if (-not [object]::ReferenceEquals($dst, $src)) { $src.Dispose() }
    return $dst
}

# ---- 资产目录（包内相对定位，禁止绝对路径）----
function Get-WxAssetsDir { Join-Path (Split-Path -Parent $PSScriptRoot) 'assets' }

# ---- 自动战斗按钮模板匹配（唯一判据=按钮文字；与血量/tip/底色零关系）----
function Get-WxBmpMask([System.Drawing.Bitmap]$b, [int]$ox, [int]$oy) {
    $w = $WX_BTN_X1 - $WX_BTN_X0 + 1; $h = $WX_BTN_Y1 - $WX_BTN_Y0 + 1
    $m = New-Object bool[] ($w * $h)
    for ($y = 0; $y -lt $h; $y++) { for ($x = 0; $x -lt $w; $x++) {
        $c = $b.GetPixel($ox + $x, $oy + $y)
        if ($c.R -gt 170 -and $c.G -gt 170 -and $c.B -gt 170) { $m[$y * $w + $x] = $true }
    } }
    return $m
}
function Get-WxJaccard($a, $b) {
    $inter = 0; $uni = 0
    for ($i = 0; $i -lt $a.Count; $i++) {
        if ($a[$i] -or $b[$i]) { $uni++ }
        if ($a[$i] -and $b[$i]) { $inter++ }
    }
    if ($uni -eq 0) { return 1.0 }
    return 1.0 - ($inter / $uni)
}
function Import-WxBtnTemplates {
    $a = Get-WxAssetsDir
    @{
        Off = Get-WxBmpMask (New-Object System.Drawing.Bitmap "$a\btn_auto_off.png") 0 0
        On  = Get-WxBmpMask (New-Object System.Drawing.Bitmap "$a\btn_auto_on.png") 0 0
    }
}

# _wxcommon.ps1 - 公共库（体系重打磨 P1，2026-10-25）
# 单一真相源：客户端尺寸、按钮模板区、窗口查找、尺寸断言、模板匹配。
# 所有画面交互脚本 dot-source 本文件，禁止再在脚本内复制 P/Invoke 样板或区域常量。
# 修改本文件 = 修改全部脚本的共同行为；改动后必须跑 wxregress-personal.ps1 离线回归。

# ---- 配置区（设计坐标系，改动须用户确认并同步 coords-personal.md）----
# 设计坐标系：文档/区域常量/模板均以 1138x708 为基准，运行时由 Get-ClientGeometry 换算到实时屏幕。
$WX_DESIGN_W = 1138                 # 设计基准尺寸（2026-10-25 用户定版，布局严格等比）
$WX_DESIGN_H = 708
$WX_CLIENT_W = $WX_DESIGN_W         # 兼容旧名，含义等同设计基准
$WX_CLIENT_H = $WX_DESIGN_H
$WX_WINDOW_TITLE = '勇士之心'        # 窗口标题匹配针
$WX_BTN_X0 = 195; $WX_BTN_Y0 = 175  # 自动战斗按钮文字区（wxwhitebox 实测，设计坐标）
$WX_BTN_X1 = 253; $WX_BTN_Y1 = 187
$WX_BTN_CLICK_X = 224; $WX_BTN_CLICK_Y = 181   # 按钮点击点（设计坐标）

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
# 设计基准 1138x708；游戏布局严格等比（用户 2026-10-26 确认）。换副本时客户区会有 1-3px 级变化，
# 由 S（统一缩放）与 OFFX/OFFY（居中留边）吸收，不再要求精确复位。
# 仅当长宽比偏差 >1.2% 或缩放越界时停机（防窗口异常/非等比拉伸）；维护工具传 -Exact 要求精确定版。
function Get-ClientGeometry {
    param([IntPtr]$h, [switch]$NoAssert, [switch]$Exact)
    $cr = New-Object WXCommon+RECT; [WXCommon]::GetClientRect($h, [ref]$cr) | Out-Null
    $pt = New-Object WXCommon+POINT; $pt.X = 0; $pt.Y = 0; [WXCommon]::ClientToScreen($h, [ref]$pt) | Out-Null
    $sx = $cr.R / $WX_DESIGN_W
    $sy = $cr.B / $WX_DESIGN_H
    $s = [math]::Min($sx, $sy)
    if (-not $NoAssert) {
        if ($Exact -and ($cr.R -ne $WX_DESIGN_W -or $cr.B -ne $WX_DESIGN_H)) {
            Write-Output "ERR: client=$($cr.R)x$($cr.B) 需精确等于设计尺寸 $($WX_DESIGN_W)x$($WX_DESIGN_H)（维护工具请先跑 wxresize-personal.ps1）"
            exit 8
        }
        if ([math]::Abs($sx - $sy) -gt 0.012) {
            Write-Output "ERR: client=$($cr.R)x$($cr.B) 长宽比与设计基准偏差过大，停机请用户核对窗口"
            exit 8
        }
        if ($s -lt 0.75 -or $s -gt 2.0) {
            Write-Output "ERR: client=$($cr.R)x$($cr.B) 缩放系数 $([math]::Round($s,3)) 超出 0.75-2.0，停机请用户核对窗口"
            exit 8
        }
    }
    $offX = ($cr.R - $WX_DESIGN_W * $s) / 2
    $offY = ($cr.B - $WX_DESIGN_H * $s) / 2
    [pscustomobject]@{ W = $cr.R; H = $cr.B; OX = $pt.X; OY = $pt.Y; S = $s; SX = $sx; SY = $sy; OFFX = $offX; OFFY = $offY }
}

# ---- 设计坐标 → 屏幕坐标（点击/采样前调用）----
function ConvertTo-ScreenPoint {
    param($g, [int]$x, [int]$y)
    [pscustomobject]@{
        X = [int][math]::Round($g.OX + $g.OFFX + $x * $g.S)
        Y = [int][math]::Round($g.OY + $g.OFFY + $y * $g.S)
    }
}

# ---- 屏幕坐标 → 设计坐标（诊断/截图标定用）----
function ConvertFrom-ScreenPoint {
    param($g, [int]$x, [int]$y)
    [pscustomobject]@{
        X = [int][math]::Round(($x - $g.OX - $g.OFFX) / $g.S)
        Y = [int][math]::Round(($y - $g.OY - $g.OFFY) / $g.S)
    }
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
function Get-DesignBitmap {
    param($g, [switch]$Raw)
    $vw = [int][math]::Round($WX_DESIGN_W * $g.S)
    $vh = [int][math]::Round($WX_DESIGN_H * $g.S)
    $cx = [int][math]::Round($g.OFFX)
    $cy = [int][math]::Round($g.OFFY)
    $src = New-Object System.Drawing.Bitmap $vw, $vh
    $gr = [System.Drawing.Graphics]::FromImage($src)
    $gr.CopyFromScreen($g.OX + $cx, $g.OY + $cy, 0, 0, (New-Object System.Drawing.Size $vw, $vh))
    $gr.Dispose()
    if ($Raw) { return $src }
    $dst = Resize-WxBitmapNearest $src $WX_DESIGN_W $WX_DESIGN_H
    if (-not [object]::ReferenceEquals($dst, $src)) { $src.Dispose() }
    return $dst
}

# ---- 抓取设计坐标区域并归一化到该区域设计尺寸（自动战斗按钮等小区域用）----
function Get-DesignRegion {
    param($g, [int]$x0, [int]$y0, [int]$x1, [int]$y1)
    $dw = $x1 - $x0 + 1; $dh = $y1 - $y0 + 1
    $sw = [math]::Max(1, [int][math]::Round($dw * $g.S))
    $sh = [math]::Max(1, [int][math]::Round($dh * $g.S))
    $sx = [int][math]::Round($g.OFFX + $x0 * $g.S)
    $sy = [int][math]::Round($g.OFFY + $y0 * $g.S)
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
# 判定：返回 'ON'/'OFF'/'UNKNOWN'（距离≤0.60 且交叉差≥0.10 才定论，宁可不知不可误判）
function Get-WxBtnState([System.Drawing.Bitmap]$b, [int]$ox, [int]$oy, $tplOff, $tplOn) {
    $live = Get-WxBmpMask $b $ox $oy
    $dOn = Get-WxJaccard $live $tplOn
    $dOff = Get-WxJaccard $live $tplOff
    if (($dOn -le 0.60 -and ($dOff - $dOn) -ge 0.10)) { return 'ON' }
    if (($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10)) { return 'OFF' }
    return 'UNKNOWN'
}

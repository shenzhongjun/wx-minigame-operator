param([int]$Pid2 = 0, [string]$Img = "", [ValidateSet("row1", "row2", "both")][string]$Mode = "row1")
# 体力读数器（2026-10-25 新增，零模板方案）
# 原理：每日循环决策只问「体力≥10？」（10 体力/场，个位数体力跑不了任何本）。
#   数字为白色紧排文本，起点固定（图标右侧 ~9px），位数越多右边缘越靠右（每 +1 位 ≈ +11px）：
#   实测 1 位数（0/100、5/100）宽 55-61px，3 位数（110/100）宽 70px → 阈值 66 区分 <10 / ≥10。
#   不识别具体数值——只需要"够不够一场"，字形分组误差不影响该二元决策。
# 标定（c4_scroll/c5_selected 实测）：row1 顶态 y207-227 起点 93/385/677/969；row2 滚动态 y292-310 起点 93/385。
# 输出：STAM=1:LOW 2:LOW 3:LOW 4:LOW （LOW=<10 不可跑 / OK=≥10 / NO_READ=区域无文本）
# -Img 离线模式供标定/回归；默认实时截屏（-Pid2 0=按标题自动发现，须在选角页顶态/滚动态对应 Mode 下使用）
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$bands = @()
if ($Mode -in @("row1", "both")) {
    $bands += @(
        @{ n = 1; x0 = 93;  x1 = 195; y0 = 203; y1 = 232 },
        @{ n = 2; x0 = 385; x1 = 487; y0 = 203; y1 = 232 },
        @{ n = 3; x0 = 677; x1 = 779; y0 = 203; y1 = 232 },
        @{ n = 4; x0 = 969; x1 = 1071; y0 = 203; y1 = 232 }
    )
}
if ($Mode -in @("row2", "both")) {
    $bands += @(
        @{ n = 5; x0 = 93;  x1 = 195; y0 = 288; y1 = 316 },
        @{ n = 6; x0 = 385; x1 = 487; y0 = 288; y1 = 316 }
    )
}

if ($Img -ne "") {
    if (-not (Test-Path $Img)) { "ERR: image not found: $Img"; exit 4 }
    $bmp = New-Object System.Drawing.Bitmap $Img
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

$out = @()
foreach ($b in $bands) {
    $right = -1; $left = -1
    for ($x = $b.x0; $x -le $b.x1; $x++) {
        $colHit = $false
        for ($y = $b.y0; $y -le $b.y1; $y++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) { $colHit = $true; break }
        }
        if ($colHit) { if ($left -lt 0) { $left = $x }; $right = $x }
    }
    if ($left -lt 0) { $out += "$($b.n):NO_READ"; continue }
    $width = $right - $b.x0   # 文本起点固定，宽度即位数指示
    $cls = if ($width -ge 66) { "OK" } else { "LOW" }
    $out += "$($b.n):$cls"
}
$bmp.Dispose()
"STAM=$($out -join ' ')"

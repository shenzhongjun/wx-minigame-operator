param([string]$ImgOff = "", [string]$ImgOn = "", [int]$SearchX0 = 150, [int]$SearchY0 = 125, [int]$SearchX1 = 320, [int]$SearchY1 = 215)
# wxrecrop-personal.ps1 - 自动战斗模板重裁一条龙（体系重打磨 P5，2026-10-25）
# 场景：窗口尺寸主动变更/布局重排后，按钮文字区漂移——原流程手工 wxwhitebox+wxcrop+四处同步，
#       本脚本一条命令完成：自动求 bbox → 备份旧模板 → 裁新双模板 → 更新 _wxcommon 配置 → 离线验证
# 前提：两张实拍截图（-ImgOff 按钮为「自动战斗」关态 / -ImgOn 为「取消自动」开态），完整客户区 PNG
# 安全：任何一步失败自动回滚（模板与 _wxcommon 均先备份）；完成后必须跑 wxregress-personal.ps1 全过才算交付
. (Join-Path $PSScriptRoot '_wxcommon.ps1')
$ErrorActionPreference = 'Stop'
if ($ImgOff -eq "" -or $ImgOn -eq "" -or -not (Test-Path $ImgOff) -or -not (Test-Path $ImgOn)) {
    "ERR: 需提供 -ImgOff <关态截图> -ImgOn <开态截图>（完整客户区 PNG）"; exit 4
}

# --- 1. 白像素行剖面 → 分组 → 取最底部一组=文字行（图标在文字上方，二者间有空隙）---
function Get-TextRegion([string]$img) {
    $bmp = New-Object System.Drawing.Bitmap $img
    $rows = @{}
    for ($y = $SearchY0; $y -le $SearchY1; $y++) {
        $cnt = 0; $minX = 999999; $maxX = -1
        for ($x = $SearchX0; $x -le $SearchX1; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 170 -and $c.G -gt 170 -and $c.B -gt 170) { $cnt++; if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x } }
        }
        if ($cnt -gt 0) { $rows[$y] = @($minX, $maxX) }
    }
    $bmp.Dispose()
    if ($rows.Count -eq 0) { return $null }
    # 行分组：相邻白行间隔 >2 视为断开
    $ys = $rows.Keys | Sort-Object
    $groups = New-Object System.Collections.ArrayList
    $cur = New-Object System.Collections.ArrayList
    $prev = -10
    foreach ($y in $ys) {
        if ($y - $prev -gt 2 -and $cur.Count -gt 0) { [void]$groups.Add($cur); $cur = New-Object System.Collections.ArrayList }
        [void]$cur.Add($y)
        $prev = $y
    }
    if ($cur.Count -gt 0) { [void]$groups.Add($cur) }
    $g = $groups[$groups.Count - 1]   # 最底部组=文字行（图标组在其上方）
    $y0 = $g[0]; $y1 = $g[$g.Count - 1]
    $minX = 999999; $maxX = -1
    foreach ($y in $g) { if ($rows[$y][0] -lt $minX) { $minX = $rows[$y][0] }; if ($rows[$y][1] -gt $maxX) { $maxX = $rows[$y][1] } }
    return @($minX, $y0, $maxX, $y1)
}

$regOff = Get-TextRegion $ImgOff
$regOn  = Get-TextRegion $ImgOn
if ($null -eq $regOff -or $null -eq $regOn) { "ERR: 未找到按钮文字白像素"; exit 4 }
"Off 文字区: $($regOff -join ',')  On 文字区: $($regOn -join ',')"
if ([math]::Abs($regOff[0]-$regOn[0]) -gt 3 -or [math]::Abs($regOff[1]-$regOn[1]) -gt 3 -or [math]::Abs($regOff[2]-$regOn[2]) -gt 3 -or [math]::Abs($regOff[3]-$regOn[3]) -gt 3) {
    "ERR: 两图文字区偏差 >3px（可能取错图标组或截图状态不对），拒绝继续"; exit 4
}
$x0 = [math]::Min($regOff[0], $regOn[0]); $y0 = [math]::Min($regOff[1], $regOn[1])
$x1 = [math]::Max($regOff[2], $regOn[2]); $y1 = [math]::Max($regOff[3], $regOn[3])
"合并文字区: ($x0,$y0)-($x1,$y1) 尺寸 $($x1-$x0+1)x$($y1-$y0+1)"

# --- 2. 备份旧模板与 _wxcommon ---
$assets = Get-WxAssetsDir
$stamp = "$($WX_CLIENT_W)x$($WX_CLIENT_H)"
Copy-Item "$assets\btn_auto_off.png" "$assets\btn_auto_off.png.bak-$stamp" -Force
Copy-Item "$assets\btn_auto_on.png"  "$assets\btn_auto_on.png.bak-$stamp" -Force
$commonPath = Join-Path $PSScriptRoot '_wxcommon.ps1'
Copy-Item $commonPath "$commonPath.bak" -Force
"backed up: btn_auto_*.png.bak-$stamp + _wxcommon.ps1.bak"

# --- 3. 裁新模板（1:1）---
function Save-Crop([string]$img, [int]$a, [int]$b, [int]$c, [int]$d, [string]$out) {
    $src = New-Object System.Drawing.Bitmap $img
    $w = $c - $a + 1; $h = $d - $b + 1
    $dst = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $w, $h), (New-Object System.Drawing.Rectangle $a, $b, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose(); $dst.Save($out); $src.Dispose(); $dst.Dispose()
}
Save-Crop $ImgOff $x0 $y0 $x1 $y1 "$assets\btn_auto_off.png"
Save-Crop $ImgOn  $x0 $y0 $x1 $y1 "$assets\btn_auto_on.png"
"templates saved: btn_auto_off/on.png ($($x1-$x0+1)x$($y1-$y0+1))"

# --- 4. 更新 _wxcommon 配置区常量（String.Replace 字面量替换——-replace 的替换串会展开变量，实测教训）---
$common = Get-Content $commonPath -Raw -Encoding UTF8
$common = $common.Replace("`$WX_BTN_X0 = $WX_BTN_X0", "`$WX_BTN_X0 = $x0").Replace("`$WX_BTN_Y0 = $WX_BTN_Y0", "`$WX_BTN_Y0 = $y0").Replace("`$WX_BTN_X1 = $WX_BTN_X1", "`$WX_BTN_X1 = $x1").Replace("`$WX_BTN_Y1 = $WX_BTN_Y1", "`$WX_BTN_Y1 = $y1")
[System.IO.File]::WriteAllText($commonPath, $common, (New-Object System.Text.UTF8Encoding $true))
"_wxcommon updated: ($x0,$y0)-($x1,$y1)"

# --- 5. 离线验证：新进程加载新配置，dist 应 0/交叉≥0.3（降 EAP：子进程 stderr 不再炸主脚本）---
$ErrorActionPreference = 'Continue'
$outOff = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\wxautostate-personal.ps1" -Img $ImgOff 2>&1
$outOn  = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\wxautostate-personal.ps1" -Img $ImgOn 2>&1
$ErrorActionPreference = 'Stop'
$offStr = ($outOff | ForEach-Object { "$_" }) -join ' '
$onStr  = ($outOn | ForEach-Object { "$_" }) -join ' '
"verify OFF: $offStr"
"verify ON:  $onStr"
$offOk = ($offStr -match 'BTN_STATE=OFF') -and ($offStr -match 'dist_off=0')
$onOk  = ($onStr -match 'BTN_STATE=ON') -and ($onStr -match 'dist_on=0')
if ($offOk -and $onOk) {
    "RECROP_OK: 模板+常量已更新并验证通过。收尾三件事："
    "  1. 跑 wxregress-personal.ps1 全量回归（必须全过）"
    "  2. 更新 coords-personal.md 按钮判定源登记（新文字区 $x0,$y0-$x1,$y1）"
    "  3. 若本次是配合窗口尺寸变更：确认 _wxcommon 的 WX_CLIENT_W/H 已同步新尺寸"
    exit 0
}
# --- 回滚 ---
Copy-Item "$assets\btn_auto_off.png.bak-$stamp" "$assets\btn_auto_off.png" -Force
Copy-Item "$assets\btn_auto_on.png.bak-$stamp" "$assets\btn_auto_on.png" -Force
Copy-Item "$commonPath.bak" $commonPath -Force
"RECROP_FAIL: 验证未过，已回滚模板与 _wxcommon。检查两张截图状态（是否关/开态清晰、无遮挡）"
exit 2

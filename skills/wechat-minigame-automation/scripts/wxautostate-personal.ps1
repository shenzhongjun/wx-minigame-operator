param([int]$Pid2 = 0, [string]$Img = "")
# 自动战斗按钮状态判定（模板匹配版）——区域/模板/距离算法由 _wxcommon.ps1 单源提供
# 判定源=左上角按钮文字「自动战斗」(关) /「取消自动」(开) —— 用户定论：唯一可靠判据
#   · 与血量/按钮底色/中央白字 tip 零关系（tip 判定代码已彻底删除）
# 原理：抓按钮文字区（_wxcommon 配置），提白色文字掩码（R,G,B>170），
#   与 assets\btn_auto_off.png / btn_auto_on.png 的掩码做 Jaccard 距离，
#   距离小者胜；差距不足 0.1 或距离≥0.60 → UNKNOWN（宁可不知，不可误判）
# 输出：BTN_STATE=ON|OFF|UNKNOWN + dist_on/dist_off 诊断值
# -Img 模式：离线分析指定截图（标定/验证用）；默认实时截屏（-Pid2 0=按标题自动发现）
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

if ($Img -ne "") {
    if (-not (Test-Path $Img)) { "ERR: image not found: $Img"; exit 4 }
    $bmp = New-Object System.Drawing.Bitmap $Img
    # 尺寸守卫：-Img 需要完整客户端区截图；小图（如直接喂模板 png）会越界，明确报错
    if ($bmp.Width -lt ($WX_BTN_X1 + 1) -or $bmp.Height -lt ($WX_BTN_Y1 + 1)) {
        "ERR: image $($bmp.Width)x$($bmp.Height) 小于按钮区 ($WX_BTN_X1,$WX_BTN_Y1)，-Img 需传完整客户端区截图"; exit 4
    }
    $live = Get-WxBmpMask $bmp $WX_BTN_X0 $WX_BTN_Y0      # 整图，加区域偏移
} else {
    $h = Find-GameWindow -Pid2 $Pid2
    if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $geo = Get-ClientGeometry $h   # 尺寸断言
    $aw = $WX_BTN_X1 - $WX_BTN_X0 + 1; $ah = $WX_BTN_Y1 - $WX_BTN_Y0 + 1
    $bmp = New-Object System.Drawing.Bitmap $aw, $ah
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(($geo.OX + $WX_BTN_X0), ($geo.OY + $WX_BTN_Y0), 0, 0, (New-Object System.Drawing.Size $aw, $ah))
    $g.Dispose()
    $live = Get-WxBmpMask $bmp 0 0                        # 位图本身就是裁剪区，零偏移
}

$tpl = Import-WxBtnTemplates
$dOff = [math]::Round((Get-WxJaccard $live $tpl.Off), 3)
$dOn  = [math]::Round((Get-WxJaccard $live $tpl.On), 3)
$bmp.Dispose()
$state = "UNKNOWN"
if (($dOff -le 0.60 -or $dOn -le 0.60) -and ([math]::Abs($dOff - $dOn) -ge 0.10)) {
    if ($dOn -lt $dOff) { $state = "ON" } else { $state = "OFF" }
}
"BTN_STATE=$state dist_on=$dOn dist_off=$dOff"

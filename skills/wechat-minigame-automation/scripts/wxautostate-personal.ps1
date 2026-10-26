param([int]$Pid2 = 0, [string]$Img = "", [switch]$NoOcr)
# 自动战斗按钮状态判定（模板匹配版 + OCR 兜底）——区域/模板/距离算法由 _wxcommon.ps1 单源提供
# 判定源=左上角按钮文字「自动战斗」(关) /「取消自动」(开) —— 用户定论：唯一可靠判据
#   · 与血量/按钮底色/中央白字 tip 零关系（tip 判定代码已彻底删除）
# 原理：抓按钮文字区（_wxcommon 配置），提白色文字掩码（R,G,B>170），
#   与 assets\btn_auto_off.png / btn_auto_on.png 的掩码做 Jaccard 距离，
#   距离小者胜；差距不足 0.1 或距离≥0.60 → UNKNOWN（宁可不知，不可误判）
# OCR 兜底（2026-10-26 新增）：仅当 Jaccard 判 UNKNOWN 且掩码像素≥60（该区确有文字）时，
#   调 wxocrbtn-personal.ps1 用 Windows OCR 读完整四字区；OCR 明确给出 ON/OFF 才采纳。
#   目的是救「按钮换皮/文字被特效遮挡」等模板失配场景，不改变已锁定行为。-NoOcr 关闭兜底。
# 输出：BTN_STATE=ON|OFF|UNKNOWN + dist_on/dist_off 诊断值（OCR 生效时追加 ocr=[文本](兜底)）
# -Img 模式：离线分析指定截图（标定/验证用）；默认实时截屏（-Pid2 0=按标题自动发现）
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

if ($Img -ne "") {
    if (-not (Test-Path $Img)) { "ERR: image not found: $Img"; exit 4 }
    $bmp = New-Object System.Drawing.Bitmap $Img
    # -Img 允许任意尺寸客户端截图，统一归一化到设计基准后再取按钮区
    if ($bmp.Width -lt 200 -or $bmp.Height -lt 200) {
        "ERR: image $($bmp.Width)x$($bmp.Height) 过小，-Img 需传完整客户端区截图"; exit 4
    }
    if ($bmp.Width -ne $WX_DESIGN_W -or $bmp.Height -ne $WX_DESIGN_H) {
        $norm = Resize-WxBitmapNearest $bmp $WX_DESIGN_W $WX_DESIGN_H
        if (-not [object]::ReferenceEquals($norm, $bmp)) { $bmp.Dispose() }
        $bmp = $norm
    }
    $live = Get-WxBmpMask $bmp $WX_BTN_X0 $WX_BTN_Y0      # 整图，加区域偏移
} else {
    $h = Find-GameWindow -Pid2 $Pid2
    if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $geo = Get-ClientGeometry $h
    $bmp = Get-DesignRegion $geo $WX_BTN_X0 $WX_BTN_Y0 $WX_BTN_X1 $WX_BTN_Y1
    $live = Get-WxBmpMask $bmp 0 0                        # 位图本身就是裁剪区，零偏移
}

$tpl = Import-WxBtnTemplates
$dOff = [math]::Round((Get-WxJaccard $live $tpl.Off), 3)
$dOn  = [math]::Round((Get-WxJaccard $live $tpl.On), 3)
$maskPx = 0; foreach ($v in $live) { if ($v) { $maskPx++ } }
$bmp.Dispose()
$state = "UNKNOWN"
if (($dOff -le 0.60 -or $dOn -le 0.60) -and ([math]::Abs($dOff - $dOn) -ge 0.10)) {
    if ($dOn -lt $dOff) { $state = "ON" } else { $state = "OFF" }
}

# OCR 兜底：模板失配但该区确实有文字时才触发，OCR 只认明确关键字，其余保持 UNKNOWN
$ocrNote = ""
if ($state -eq "UNKNOWN" -and $maskPx -ge 60 -and -not $NoOcr) {
    $ocrFile = Join-Path $PSScriptRoot 'wxocrbtn-personal.ps1'
    if (Test-Path $ocrFile) {
        $ocrArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ocrFile)
        if ($Img -ne "") { $ocrArgs += @('-Img', $Img) } else { $ocrArgs += @('-Pid2', "$Pid2") }
        $os = "UNKNOWN"; $ot = ""
        foreach ($line in (& powershell @ocrArgs 2>&1)) {
            if ($line -match '^BTN_OCR=(\w+)') { $os = $Matches[1] }
            if ($line -match 'ocr=\[(.*)\]') { $ot = $Matches[1] }
        }
        if ($os -eq "ON" -or $os -eq "OFF") { $state = $os; $ocrNote = " ocr=[$ot](兜底)" }
    }
}
"BTN_STATE=$state dist_on=$dOn dist_off=$dOff" + $ocrNote

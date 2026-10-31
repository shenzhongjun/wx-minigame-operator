param([int]$Pid2 = 0, [string]$Img = "", [switch]$Debug)
# wxpopup.ps1 — 弹窗分类器（薄壳，2026-10-31 模块化试点）
# 主体已迁入 _wxcore.ps1 的 Invoke-WxPopup（判据/顺序/阈值零改动），本文件只做参数解析、格式化、退出码。
# 输出（与迁移前一致）：POPUP=<cls> ocr_raw=[..] goldbtn=N
#   礼包类：POPUP=POPUP_PACK kind=<k> pack=N ocr_raw=[] close=x,y uncheck=x,y
# 退出码：0=正常；3=POPUP_RELOGIN / POPUP_UNKNOWN（红线类，调用方须停机）；1=窗口未找到；4=-Img 不合规；7=最小窗守卫拒绝
. (Join-Path $PSScriptRoot '_wxcommon.ps1')
. (Join-Path $PSScriptRoot '_wxcore.ps1')

$r = Invoke-WxPopup -Pid2 $Pid2 -Img $Img -Debug:$Debug

if ($r.Err) { "ERR: $($r.Err)"; exit $r.ExitCode }
if ($r.Popup -eq "POPUP_PACK") {
    "POPUP=POPUP_PACK kind=$($r.Kind) pack=$($r.Pack) ocr_raw=[] close=$($r.CloseX),$($r.CloseY) uncheck=$($r.UncheckX),$($r.UncheckY)"
    exit 0
}
"POPUP=$($r.Popup) ocr_raw=[$($r.OcrRaw)] goldbtn=$($r.GoldBtn)"
exit $r.ExitCode

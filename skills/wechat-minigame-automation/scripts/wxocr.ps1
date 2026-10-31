param([int]$Pid2 = 0, [string]$Img = "", [string]$Task = "", [int]$X0 = 0, [int]$Y0 = 56, [int]$X1 = 200, [int]$Y1 = 115, [int]$F = 8, [switch]$NoInvert, [switch]$Debug, [int]$RetryLeft = -1)
# wxocr.ps1 — 通用 OCR 引擎（薄壳，2026-10-31 模块化迁入 _wxcore.ps1）
# 主体已迁入 _wxcore.ps1 的 Invoke-WxOcr / Invoke-WxOcrOnce（任务表、区域、判定规则零改动）。
# 本文件只做参数解析、文本格式化、退出码。
# ⚠️ 关键收益：引擎实例在进程内缓存，只有第一次建（约 2s），链路内后续每次 <1s（原来每次约 3s）。
# 两种用法：
#   1) -Task <name>  任务预设（区域+关键字内置）→ OCR=<task>=HIT|MISS raw=[文本]
#   2) 不带 -Task   自由扫描 -X0/-Y0/-X1/-Y1 → OCR_RAW=[文本]
# 任务表与匹配规则（N 字命中/2字零容差/kw2 合并池）见 _wxcore.ps1 $script:WxOcrTasks 与 Invoke-WxOcrOnce。
. (Join-Path $PSScriptRoot '_wxcommon.ps1')
. (Join-Path $PSScriptRoot '_wxcore.ps1')

$o = Invoke-WxOcr -Pid2 $Pid2 -Img $Img -Task $Task -X0 $X0 -Y0 $Y0 -X1 $X1 -Y1 $Y1 -F $F -NoInvert:$NoInvert -Debug:$Debug -RetryLeft $RetryLeft

if ($o.Err) { "ERR: $($o.Err)"; exit $o.ExitCode }

switch ($o.Kind) {
    'unavailable' { "OCR=UNAVAILABLE" }
    'auto'        { "OCR=autobtn=$($o.Class) raw=[$($o.Raw)]" }
    'kw'          { "OCR=$Task=$(if ($o.Hit) { 'HIT' } else { 'MISS' }) raw=[$($o.Raw)]" }
    default       { if ($o.Raw -eq "") { "OCR_RAW=EMPTY" } else { "OCR_RAW=[$($o.Raw)]" } }
}
if ($Debug -and $o.DebugLine) { $o.DebugLine }
exit 0

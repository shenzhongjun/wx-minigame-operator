param([string]$Manifest = "", [string]$ImgDir = "C:\Users\zhouyijie\WorkBuddy\游戏\wx-verify")
# wxregress.ps1 - 离线回归测试（体系重打磨 P2，2026-10-25）
# ⚠️ 2026-10-26 用户裁定：清单 _regress-manifest.csv 系 AI 标注未经人工核验（含命名/断言矛盾行、UNKNOWN 误报锁定行），
#    本回归体系【暂停使用】；恢复前脚本改动验证以实机探针+截图目验替代，本脚本输出不作为改动门槛。
# 用途：对标注截图批量断言 wxautostate BTN_STATE 与 wxprobe STATE（-Img 离线模式）。
#   重裁模板 / 改判定阈值 / 改公共库 / 换尺寸重标后，必须跑本脚本：
#   全 PASS 才算改动成立；FAIL 先查改动，不允许"下次实战再看"。
# 清单：_regress-manifest.csv（file,btn,state；空列=跳过该项断言）。
#   其中主城 GOLD_DIALOG / 塔页 SETTLE_PAGE 为已知探针误报，当前行为被锁定，
#   若未来这两行变 PASS（误报消失）也属行为变化，需人工确认后更新清单。
# 退出码：0=全过；1=有 FAIL 或清单/图片缺失。
$ErrorActionPreference = 'Stop'
if ($Manifest -eq "") { $Manifest = Join-Path $PSScriptRoot '_regress-manifest.csv' }
$autostate = Join-Path $PSScriptRoot 'wxautostate.ps1'
$probe = Join-Path $PSScriptRoot 'wxprobe.ps1'
if (-not (Test-Path $Manifest)) { "ERR: manifest not found: $Manifest"; exit 1 }

$rows = Import-Csv -LiteralPath $Manifest
$pass = 0; $fail = 0; $skip = 0
foreach ($r in $rows) {
    $img = Join-Path $ImgDir $r.file
    if (-not (Test-Path $img)) { "[SKIP] $($r.file) 图片不存在"; $skip++; continue }
    if ($r.btn -ne "") {
        $out = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $autostate -Img $img 2>&1
        $got = ""
        foreach ($line in $out) { if ($line -match '^BTN_STATE=(\w+)') { $got = $Matches[1] } }
        if ($got -eq $r.btn) { "[PASS] btn $($r.file) = $got"; $pass++ }
        else { "[FAIL] btn $($r.file) 期望=$($r.btn) 实际=$got ($out)"; $fail++ }
    }
    if ($r.state -ne "") {
        $out = & "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $probe -Img $img 2>&1
        $got = ""
        foreach ($line in $out) { if ($line -match '^STATE=(\w+)') { $got = $Matches[1] } }
        if ($got -eq $r.state) { "[PASS] state $($r.file) = $got"; $pass++ }
        else { "[FAIL] state $($r.file) 期望=$($r.state) 实际=$got ($out)"; $fail++ }
    }
}
"=== 回归结果: PASS=$pass FAIL=$fail SKIP=$skip ==="
if ($fail -gt 0) { exit 1 }
exit 0

# wxpreflight.ps1 — 开局协议预检（2026-10-24 新增，配合 SKILL.md §A）
# 用途：任务开始后、任何画面交互之前运行。校验 skill 档案齐全并打印各文件要点摘要，
#       作为《开局自检报告》的硬凭证。退出码：0=全部就绪；1=有缺失（禁止开工）。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File wxpreflight.ps1

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot   # skill 根目录（本脚本位于 scripts/ 下一级即根）

$required = @(
  'SKILL.md',
  '管理新规.md',
  'references\tasks.md',
  'references\coords.md',
  'references\incidents.md',
  'references\game-mechanics.md',
  'references\todo-scripts.md',
  'references\update-log.md',
  'assets\btn_auto_off.png',
  'assets\btn_auto_on.png'
)

$missing = @()
Write-Host '=== wxpreflight 开局预检 ==='
Write-Host '坐标系：设计坐标 1138x708（含 55px 内嵌标题栏，画布 1138x653）；运行时 S=min(W/1138,(H-55)/653) 等比换算（coords 文档数字可直接使用）'
foreach ($f in $required) {
  $p = Join-Path $base $f
  if (Test-Path -LiteralPath $p) {
    Write-Host "[OK  ] $f"
  } else {
    Write-Host "[MISS] $f" -ForegroundColor Red
    $missing += $f
  }
}

Write-Host ''
Write-Host '--- scripts/ 清单 ---'
Get-ChildItem (Join-Path $base 'scripts') -Filter *.ps1 | ForEach-Object { Write-Host "  $($_.Name)" }

Write-Host ''
Write-Host '--- 各档案要点摘要（前 12 行）---'
foreach ($f in ($required | Where-Object { $_ -like '*.md' })) {
  $p = Join-Path $base $f
  if (Test-Path -LiteralPath $p) {
    Write-Host "[$f]"
    Get-Content -LiteralPath $p -TotalCount 12 -Encoding UTF8 | ForEach-Object { Write-Host "  $_" }
    Write-Host ''
  }
}

Write-Host ''
Write-Host '--- live 几何审计（窗口已开时；wxcanvas 实测 chrome vs 常量）---'
$canvasOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'scripts\wxcanvas.ps1') 2>&1
$canvasJoined = ($canvasOut | ForEach-Object { "$_" }) -join "`n"
if ($canvasJoined -match 'window not found') {
  Write-Host '[SKIP] 游戏窗口未开，跳过 chrome 审计（开局开窗后请补跑 wxcanvas.ps1）'
} elseif ($canvasJoined -match 'chrome=(\d+)') {
  $chromeLive = [int]$Matches[1]
  $chromeExpect = 55
  $commonRaw = Get-Content (Join-Path $base 'scripts\_wxcommon.ps1') -Raw -Encoding UTF8
  if ($commonRaw -match '\$WX_CHROME_H\s*=\s*(\d+)') { $chromeExpect = [int]$Matches[1] }
  if ($chromeLive -eq $chromeExpect) {
    Write-Host "[OK  ] chrome=$chromeLive 与 _wxcommon 常量一致（客户区结构未变）"
  } else {
    Write-Host "[FAIL] chrome 实测=$chromeLive 常量=$chromeExpect 不一致！几何换算将整体偏移，禁止开工。核实后更新 _wxcommon.ps1 的 WX_CHROME_H" -ForegroundColor Red
    exit 1
  }
} else {
  Write-Host "[WARN] wxcanvas 输出异常，chrome 未定（首行：$($canvasJoined.Split("`n")[0]))"
}

if ($missing.Count -gt 0) {
  Write-Host "预检失败：缺失 $($missing.Count) 个文件，禁止开工：" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host "  - $_" }
  exit 1
}
Write-Host '预检通过：档案齐全。请继续逐文件阅读并输出《开局自检报告》，报告未输出前禁止任何画面交互。'
exit 0

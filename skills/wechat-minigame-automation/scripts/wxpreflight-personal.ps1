# wxpreflight-personal.ps1 — 开局协议预检（2026-10-24 新增，配合 SKILL.md §A）
# 用途：任务开始后、任何画面交互之前运行。校验 skill 档案齐全并打印各文件要点摘要，
#       作为《开局自检报告》的硬凭证。退出码：0=全部就绪；1=有缺失（禁止开工）。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File wxpreflight-personal.ps1

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot   # skill 根目录（本脚本位于 scripts/ 下一级即根）

$required = @(
  'SKILL.md',
  '管理新规.md',
  'references\tasks.md',
  'references\coords-personal.md',
  'references\incidents.md',
  'references\game-mechanics.md',
  'references\todo-scripts.md',
  'references\update-log.md',
  'assets\btn_auto_off.png',
  'assets\btn_auto_on.png'
)

$missing = @()
Write-Host '=== wxpreflight 开局预检 ==='
Write-Host '坐标系：设计坐标 1138x708；运行时按客户区长宽比等比换算（coords 文档数字可直接使用）'
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

if ($missing.Count -gt 0) {
  Write-Host "预检失败：缺失 $($missing.Count) 个文件，禁止开工：" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host "  - $_" }
  exit 1
}
Write-Host '预检通过：档案齐全。请继续逐文件阅读并输出《开局自检报告》，报告未输出前禁止任何画面交互。'
exit 0

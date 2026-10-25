# wxdoclint-personal.ps1 — skill 文档结构校验（2026-10-24 新增，配合 管理新规.md v2 第三节）
# 用途：维护 SKILL.md / references 后运行，机器验证防臃肿规则是否守住。
# 校验项：① SKILL.md 行数 ≤200（≥180 警戒）② 路由完整性：每个 references 档案（含 features/）
#         必须在 SKILL.md 正文被提及 ③ 输出行数摘要。
# 退出码：0=通过；1=有违规（先修复再交付）。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File wxdoclint-personal.ps1

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot   # skill 根目录

$fail = @()
Write-Host '=== wxdoclint 文档结构校验 ==='

# --- 1. SKILL.md 行数 ---
$skillPath = Join-Path $base 'SKILL.md'
$skillLines = (Get-Content -LiteralPath $skillPath -Encoding UTF8).Count
$skillText = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
if ($skillLines -gt 200) {
  Write-Host "[FAIL] SKILL.md = $skillLines 行（上限 200）" -ForegroundColor Red
  $fail += 'line-limit'
} elseif ($skillLines -ge 180) {
  Write-Host "[WARN] SKILL.md = $skillLines 行（已过 180 警戒线，优先降级内联段落再收新内容）" -ForegroundColor Yellow
} else {
  Write-Host "[OK  ] SKILL.md = $skillLines 行（上限 200，警戒 180）"
}

# --- 2. 路由完整性：references 每个文件必须在 SKILL.md 被提及 ---
$refDir = Join-Path $base 'references'
$refFiles = @()
if (Test-Path $refDir) {
  $refFiles = Get-ChildItem $refDir -Recurse -File | ForEach-Object { $_.Name }
}
$unrouted = @()
foreach ($f in $refFiles) {
  if ($skillText -notlike "*$f*") { $unrouted += $f }
}
if ($unrouted.Count -gt 0) {
  foreach ($u in $unrouted) {
    Write-Host "[FAIL] references\$u 未在 SKILL.md 任何路由表/指针中被提及（孤儿文件，用户读不到入口）" -ForegroundColor Red
  }
  $fail += 'routing'
} else {
  Write-Host "[OK  ] 路由完整性：references $($refFiles.Count) 个文件全部在 SKILL.md 有入口"
}

# --- 3. 摘要 ---
Write-Host ''
Write-Host '--- references 清单 ---'
foreach ($f in $refFiles) { Write-Host "  $f" }
Write-Host ''
Write-Host ('--- 结果：' + $(if ($fail.Count -eq 0) { 'PASS' } else { 'FAIL: ' + ($fail -join ', ') }) + ' ---')
if ($fail.Count -gt 0) { exit 1 } else { exit 0 }

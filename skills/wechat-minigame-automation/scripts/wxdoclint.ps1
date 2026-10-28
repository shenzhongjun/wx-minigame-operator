# wxdoclint.ps1 — skill 文档结构校验（2026-10-24 新增，配合 管理新规.md v2 第三节）
# 用途：维护 SKILL.md / references 后运行，机器验证防臃肿规则是否守住。
# 校验项：① SKILL.md 行数 ≤200（≥180 警戒）② 路由完整性：每个 references 档案（含 features/）
#         必须在 SKILL.md 正文被提及 ③ 输出行数摘要。
# 退出码：0=通过；1=有违规（先修复再交付）。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File wxdoclint.ps1

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

# --- 2.5 坐标泄漏检测（2026-10-28 用户定版，管理新规 一之二；WARN 不阻断，观察期后升格 FAIL） ---
# 唯一坐标入口=coords.md；非坐标文档（SKILL.md/game-mechanics/features）出现 (x,y) 坐标模式即告警。
# 豁免行：删除线(~~)、含「作废/已删/旧坐标/旧值/历史」警示行、含 coords.md 指针语义行（见 coords/坐标见）。
$leakFiles = @(Join-Path $base 'SKILL.md') + @(Get-ChildItem (Join-Path $base 'references') -Recurse -File -Filter '*.md' | Where-Object { $_.Name -in @('game-mechanics.md') -or $_.DirectoryName -like '*features' } | ForEach-Object { $_.FullName })
$leakCount = 0
foreach ($lf in $leakFiles) {
  $ln = 0
  foreach ($line in (Get-Content -LiteralPath $lf -Encoding UTF8)) {
    $ln++
    if ($line -match '\(\d{1,4}\s*,\s*\d{1,4}\)') {
      if ($line -match '~~|作废|已删|旧坐标|旧值|历史|coords\.md|坐标见') { continue }
      $rel = Resolve-Path -LiteralPath $lf -Relative
      Write-Host "[WARN] 疑似坐标泄漏：$rel :${ln} → $((($line).Trim().Substring(0, [Math]::Min(60, $line.Trim().Length))))" -ForegroundColor Yellow
      $leakCount++
    }
  }
}
if ($leakCount -eq 0) {
  Write-Host '[OK  ] 坐标泄漏检测：非坐标文档 0 命中（唯一入口=coords.md）'
} else {
  Write-Host "[WARN] 坐标泄漏检测：$leakCount 行疑似坐标出现在非坐标文档（唯一入口=coords.md，改指针或补豁免标注）" -ForegroundColor Yellow
}

# --- 3. 摘要 ---
Write-Host ''
Write-Host '--- references 清单 ---'
foreach ($f in $refFiles) { Write-Host "  $f" }
Write-Host ''
Write-Host ('--- 结果：' + $(if ($fail.Count -eq 0) { 'PASS' } else { 'FAIL: ' + ($fail -join ', ') }) + ' ---')
if ($fail.Count -gt 0) { exit 1 } else { exit 0 }

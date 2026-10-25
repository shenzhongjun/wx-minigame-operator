param([int]$Pid2 = 0, [string]$Want = "SETTLE_PAGE", [int]$MaxSec = 180)
# 轮询等待画面达到指定状态（复用 wxprobe-personal.ps1 判定）
# 输出最终探针 STATE 行；达到目标 exit 0，超时 exit 1
$probe = Join-Path $PSScriptRoot "wxprobe-personal.ps1"
$deadline = (Get-Date).AddSeconds($MaxSec)
$state = ""
while ($true) {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $probe -Pid2 $Pid2 2>&1
  $line = ($out | Where-Object { $_ -match "^STATE=" } | Select-Object -First 1)
  if ($line) { $state = "$line" } else { $state = "STATE=ERR($out)" }
  if ($state -match "^STATE=$Want(,|$)") { "$state (waited)"; exit 0 }
  if ((Get-Date) -gt $deadline) { "$state (TIMEOUT waiting $Want)"; exit 1 }
  Start-Sleep -Seconds 1
}

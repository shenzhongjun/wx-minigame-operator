param([string]$Steps = "", [int]$J = 3, [int]$Pid2 = 40400)
# Steps format: "x:y:delayAfterMs;x:y:delayAfterMs"  window-relative coords
# Adds offset (+8,+11) and +/-J jitter; focuses the window only once at the start
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class U { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,UIntPtr e); public struct RECT { public int Left, Top, Right, Bottom; } }'

$p = Get-Process -Id $Pid2 -ErrorAction SilentlyContinue
if (-not $p) { "ERR: pid not found"; exit 1 }
$h = $p.MainWindowHandle
if ($h -eq 0) { "ERR: no main window"; exit 1 }
[U]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 200
$r = New-Object U+RECT
[U]::GetWindowRect($h, [ref]$r) | Out-Null
$OX = $r.Left + 8
$OY = $r.Top + 11
"rect=$($r.Left),$($r.Top) size=$($r.Right-$r.Left)x$($r.Bottom-$r.Top)"

foreach ($step in $Steps.Split(";")) {
  if ($step.Trim() -eq "") { continue }
  if ($step.StartsWith("w:")) { Start-Sleep -Milliseconds ([int]$step.Substring(2)); continue }
  $parts = $step.Split(":")
  $x = [int]$parts[0]
  $y = [int]$parts[1]
  $d = 250
  if ($parts.Length -gt 2) { $d = [int]$parts[2] }
  $ax = $OX + $x + (Get-Random -Minimum (-$J) -Maximum ($J + 1))
  $ay = $OY + $y + (Get-Random -Minimum (-$J) -Maximum ($J + 1))
  [U]::SetCursorPos($ax, $ay) | Out-Null
  Start-Sleep -Milliseconds 180
  [U]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [U]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  "click=$x,$y -> $ax,$ay"
  if ($d -gt 0) { Start-Sleep -Milliseconds $d }
}

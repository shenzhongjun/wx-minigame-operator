param([int]$Pid2 = 40400, [int]$MaxRounds = 30, [int]$BX = 640, [switch]$Debug)
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class W { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,UIntPtr e); public struct RECT { public int Left, Top, Right, Bottom; } }'
Add-Type -AssemblyName System.Drawing

$p = Get-Process -Id $Pid2 -ErrorAction SilentlyContinue
if (-not $p) { "ERR: pid not found"; exit 1 }
$h = $p.MainWindowHandle
if ($h -eq 0) { "ERR: no main window"; exit 1 }
[W]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 250
$r = New-Object W+RECT
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$OX = $r.Left + 8
$OY = $r.Top + 11
"rect=$($r.Left),$($r.Top) size=$($r.Right-$r.Left)x$($r.Bottom-$r.Top)"

function IsRed($c) {
  if ($c.R -gt 100 -and ($c.R - $c.B) -gt 50 -and $c.G -gt 22 -and $c.G -lt 78) { return $true }
  return $false
}

function FindBtnY {
  $Y0 = 188
  $H = 98
  $bmp = New-Object System.Drawing.Bitmap 60, $H
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(($OX + $BX - 30), ($OY + $Y0), 0, 0, (New-Object System.Drawing.Size 60, $H))
  $g.Dispose()
  $hits = New-Object bool[] $H
  for ($i = 0; $i -lt $H; $i++) {
    $n = 0
    foreach ($dx in @(-25, 0, 25)) {
      $c = $bmp.GetPixel(30 + $dx, $i)
      if (IsRed $c) { $n++ }
    }
    $hits[$i] = ($n -ge 2)
  }
  $bmp.Dispose()
  $i = 0
  while ($i -lt $H) {
    if (-not $hits[$i]) { $i++; continue }
    $s = $i
    $e = $i
    $gap = 0
    $j = $i + 1
    while ($j -lt $H) {
      if ($hits[$j]) { $e = $j; $gap = 0 }
      else { $gap++; if ($gap -gt 6) { break } }
      $j++
    }
    $len = $e - $s + 1
    if ($Debug) { Write-Host "band y=$($Y0+$s)..$($Y0+$e) len=$len" }
    if ($len -ge 10) { return ($Y0 + $s + 20) }
    $i = $e + 1
  }
  return -1
}

function DoClick([int]$x, [int]$y) {
  $ax = $OX + $x + (Get-Random -Minimum -4 -Maximum 5)
  $ay = $OY + $y + (Get-Random -Minimum -3 -Maximum 4)
  [W]::SetCursorPos($ax, $ay) | Out-Null
  Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 450)
  [W]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 110)
  [W]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

"initial scan: y=$(FindBtnY)"

for ($i = 1; $i -le $MaxRounds; $i++) {
  $t = 0
  $by = FindBtnY
  while ($by -lt 0) {
    Start-Sleep -Seconds 3
    $t += 3
    if ($t -ge 120) { "TIMEOUT waiting settle round $i"; exit 2 }
    $by = FindBtnY
  }
  Start-Sleep -Milliseconds (Get-Random -Minimum 500 -Maximum 1300)
  $by = FindBtnY
  if ($by -lt 0) { "round ${i}: band vanished, rescan"; $i-- ; continue }
  DoClick $BX $by
  "round ${i}: clicked at y=$by"
  Start-Sleep -Milliseconds (Get-Random -Minimum 7000 -Maximum 8800)
  $by2 = FindBtnY
  if ($by2 -ge 0) {
    "round ${i}: still settle (y=$by2), retry"
    DoClick $BX $by2
    Start-Sleep -Milliseconds (Get-Random -Minimum 7000 -Maximum 8800)
    if ((FindBtnY) -ge 0) { "STOP: retry failed -> no stamina left"; exit 0 }
  }
  "round ${i}: battle entered"
}
"LOOP: max rounds reached"

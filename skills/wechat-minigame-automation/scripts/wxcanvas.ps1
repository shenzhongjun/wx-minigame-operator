param([int]$Pid2 = 0, [string]$Out = "$env:TEMP\wrx\canvas_raw.png")
# wxcanvas.ps1 - measure the game's internal letterbox black bars (2026-10-26, chrome-aware 2026-10-27)
# Purpose: verify the v1.1.2 geometry model (client = fixed WeChat chrome strip + uniformly
#          scaled game canvas 1138x653) inside an arbitrary client rect.
# Method: CopyFromScreen the whole client rect (raw, no normalize); detect chrome strip
#         (white band from top); scan rows/columns BELOW the chrome for near-black uniform
#         bands (R,G,B < 16, >=98% of samples) to locate the game canvas.
# Output: chrome height, client size, game-canvas rect (chrome excluded), four letterbox bar
#         widths (bar_top measured within the game area below chrome), canvas aspect vs design
#         canvas aspect (1138/653), scale_w/scale_h, and the v1.1.2 centered-assumption
#         prediction for comparison. Raw capture saved to -Out for visual audit.
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$hwnd = Find-GameWindow -Pid2 $Pid2
if ($hwnd -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
$cr = New-Object WXCommon+RECT
[WXCommon]::GetClientRect($hwnd, [ref]$cr) | Out-Null
$pt = New-Object WXCommon+POINT; $pt.X = 0; $pt.Y = 0
[WXCommon]::ClientToScreen($hwnd, [ref]$pt) | Out-Null
$W = $cr.R; $H = $cr.B

$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($pt.X, $pt.Y, 0, 0, (New-Object System.Drawing.Size $W, $H))
$g.Dispose()

# flat-screen guard (occluded / minimized): whole capture same color -> untrustworthy
$distinct = @{}
for ($yy = 0; $yy -lt $H; $yy += 20) { for ($xx = 0; $xx -lt $W; $xx += 20) {
  $distinct[$bmp.GetPixel($xx, $yy).ToArgb()] = $true
}}
if ($distinct.Count -le 2) { $bmp.Dispose(); "ERR: flat screenshot (occluded/minimized), content untrustworthy"; exit 2 }

$dir = Split-Path $Out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$bmp.Save($Out)

# chrome strip scan: WeChatAppEx draws its own title bar INSIDE the client rect.
# chrome bottom = first row (from top) whose white-pixel fraction < 0.5.
# (v2 fix 2026-10-26: the old ">=90% white rows" rule broke early on narrow windows
#  because the dark title text "勇士之心" pushed white fraction below 90% mid-chrome;
#  text rows are still >50% white while game art rows are far below 50%.)
$chromeH = 0
for ($y = 0; $y -lt [Math]::Min($H, 200); $y++) {
  $n = 0; $tot = 0
  for ($x = 0; $x -lt $W; $x += 2) {
    $tot++
    $c = $bmp.GetPixel($x, $y)
    if ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) { $n++ }
  }
  if (($n / $tot) -lt 0.5) { $chromeH = $y; break }
  $chromeH = $y + 1
}
if ($chromeH -ge 200) { Write-Output "WARN: chrome band exceeds 200px scan cap - white game top? audit manually" }

# row scan (game area only, below chrome): a row is "black" if >=98% of sampled pixels are near-black.
# Chrome rows are excluded so the canvas rect is pure game content (chrome-aware fix 2026-10-27).
$rowBlack = New-Object bool[] $H
for ($y = $chromeH; $y -lt $H; $y++) {
  $n = 0; $tot = 0
  for ($x = 0; $x -lt $W; $x += 2) {
    $tot++
    $c = $bmp.GetPixel($x, $y)
    if ($c.R -lt 16 -and $c.G -lt 16 -and $c.B -lt 16) { $n++ }
  }
  $rowBlack[$y] = ($n -ge ($tot * 0.98))
}
$top = $chromeH; while ($top -lt $H -and $rowBlack[$top]) { $top++ }
$bot = $H - 1; while ($bot -ge $chromeH -and $rowBlack[$bot]) { $bot-- }

# column scan inside the canvas rows only
$L = -1; $R = -1
if ($top -le $bot) {
  for ($x = 0; $x -lt $W; $x++) {
    $n = 0; $tot = 0
    for ($y = $top; $y -le $bot; $y += 2) {
      $tot++
      $c = $bmp.GetPixel($x, $y)
      if ($c.R -lt 16 -and $c.G -lt 16 -and $c.B -lt 16) { $n++ }
    }
    if ($n -lt ($tot * 0.98)) { if ($L -lt 0) { $L = $x }; $R = $x }
  }
}
if ($L -lt 0) { $bmp.Dispose(); "ERR: no canvas found (whole client black?)"; exit 3 }

$cw = $R - $L + 1; $ch = $bot - $top + 1
"chrome=$chromeH"
"client=${W}x${H}"
"canvas=($L,$top)-($R,$bot) size=${cw}x${ch}"
"bar_top=$($top - $chromeH) bar_bottom=$($H - 1 - $bot) bar_left=$L bar_right=$($W - 1 - $R)"
"canvas_aspect=$([math]::Round($cw / [double]$ch, 4)) design_canvas_aspect=$([math]::Round(1138 / 653.0, 4))"
"scale_w=$([math]::Round($cw / 1138.0, 4)) scale_h=$([math]::Round($ch / 653.0, 4))"
$predS = [math]::Min($W / 1138.0, ($H - $chromeH) / 653.0)
$predW = [int][math]::Round(1138 * $predS); $predH = [int][math]::Round(653 * $predS)
$predTop = $chromeH + [int][math]::Round((($H - $chromeH) - $predH) / 2.0); $predLeft = [int][math]::Round(($W - $predW) / 2.0)
"model_prediction(S=min(W/1138,(H-chrome)/653)): canvas=${predW}x${predH} top=$predTop left=$predLeft"
"hint: pure-black art edges read as bars (charsel top/bottom fade) - bars/canvas fuzzy by ~5px on dark pages; geometry truth = click accuracy, not this scan"
"saved=$Out"
$bmp.Dispose()

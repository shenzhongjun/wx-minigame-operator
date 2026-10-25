param([int]$Pid2 = 0, [int]$MaxRounds = 1, [int]$BX = 915, [int]$FirstWaitSec = 0, [switch]$NoAuto, [switch]$Debug)
# 个人电脑版像素探针刷本循环（已被 wxgrind 替代为主力，仍保留扫描式结算判定能力）
# 等待结算页 -> 扫描暗红「再来一次」按钮 -> 点击 -> 等待 -> 复查
# 结算按钮 x 实测约 901（有浮动，BX 取扫描中心）
# 每轮进图后内联 Ensure-Auto：同进程扫描（无子进程开销），确认自动战斗状态
# 机制（2026-10-23 晚重写）：判定源=左上角按钮文字模板匹配「取消自动」(开)/「自动战斗」(关)
#   · 与血量/按钮底色/中央白字 tip 均零关系
#   · 换图场景零点击只确认：ON → AUTO_CONFIRMED 继续；明确 OFF → AUTO_OFF_SEEN 停机
#     （换图保持开启是定论，明确见到 OFF=定论被推翻，停机报告，绝不自行补点）
#   · UNKNOWN（特效扫过）→ 继续观察到 15s 超时
# 窗口查找/尺寸断言/模板匹配由 _wxcommon.ps1 单源提供；pid 0=按标题自动发现
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

$h = Find-GameWindow -Pid2 $Pid2
if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
[WXCommon]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
$geo = Get-ClientGeometry $h
$OX = $geo.OX; $OY = $geo.OY
"client=$($geo.W)x$($geo.H) origin=$OX,$OY"

try {
    $tpl = Import-WxBtnTemplates
    $tplOff = $tpl.Off; $tplOn = $tpl.On
} catch {
    "ERR: template load failed: $_"; "DONE"; exit 4
}
$AW = $WX_BTN_X1 - $WX_BTN_X0 + 1; $AH = $WX_BTN_Y1 - $WX_BTN_Y0 + 1
$liveBmp = New-Object System.Drawing.Bitmap $AW, $AH
$liveG = [System.Drawing.Graphics]::FromImage($liveBmp)

# 扫描带：个人电脑结算按钮 y 实测约 240-300，面板位置浮动 ±50
# （注意：扫描高度用 $ScanH——PowerShell 变量大小写不敏感，$H 会与窗口句柄 $h 冲突，wxshot 教训）
$Y0 = 225
$ScanH = 220
$HW = 38   # 扫描半宽

function IsRed($c) {
  if ($c.R -gt 100 -and ($c.R - $c.B) -gt 50 -and $c.G -gt 22 -and $c.G -lt 78) { return $true }
  return $false
}

function FindBtnY {
  $bmp = New-Object System.Drawing.Bitmap (2 * $HW + 1), $ScanH
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(($OX + $BX - $HW), ($OY + $Y0), 0, 0, (New-Object System.Drawing.Size (2 * $HW + 1), $ScanH))
  $g.Dispose()
  $hits = New-Object bool[] $ScanH
  for ($i = 0; $i -lt $ScanH; $i++) {
    $n = 0
    foreach ($dx in @(-25, 0, 25)) {
      $c = $bmp.GetPixel($HW + $dx, $i)
      if (IsRed $c) { $n++ }
    }
    $hits[$i] = ($n -ge 2)
  }
  $bmp.Dispose()
  $i = 0
  while ($i -lt $ScanH) {
    if (-not $hits[$i]) { $i++; continue }
    $s = $i; $e = $i; $gap = 0
    $j = $i + 1
    while ($j -lt $ScanH) {
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
  [WXCommon]::SetCursorPos($ax, $ay) | Out-Null
  Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 450)
  [WXCommon]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 110)
  [WXCommon]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

# ---- 内联确认自动战斗状态（换图场景：同角色登录期间保持开启=用户定论，零点击！）----
# 只观察不干预：按钮模板=ON → AUTO_CONFIRMED 继续；明确 OFF → AUTO_OFF_SEEN 停机报告；
# UNKNOWN（特效扫过按钮区）继续观察；15s 超时仍无定论 → AUTO_UNKNOWN_TIMEOUT 停机
function Ensure-Auto {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastLog = -1.0
    try {
        while ($sw.Elapsed.TotalSeconds -lt 15) {
            $liveG.CopyFromScreen(($OX + $WX_BTN_X0), ($OY + $WX_BTN_Y0), 0, 0, $liveBmp.Size)
            $live = Get-WxBmpMask $liveBmp 0 0
            $dOn = [math]::Round((Get-WxJaccard $live $tplOn), 3)
            $dOff = [math]::Round((Get-WxJaccard $live $tplOff), 3)
            $t = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            if ($t - $lastLog -ge 1.0) { Write-Host "scan t=${t}s dist_on=$dOn dist_off=$dOff"; $lastLog = $t }
            if ($dOn -le 0.60 -and ($dOff - $dOn) -ge 0.10) {
                Write-Host "AUTO_CONFIRMED(ms=$([int]$sw.ElapsedMilliseconds))"
                return 1
            }
            if ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10) {
                # 明确见到「自动战斗」(关) = 换图保持开启的定论被推翻或脚本误点过关
                # 这是实验数据不是 bug：停机报告，由用户裁决，严禁自行补点
                Write-Host "AUTO_OFF_SEEN(ms=$([int]$sw.ElapsedMilliseconds)) - 换图后按钮=自动战斗(关)，与定论矛盾，停机问用户"
                return -1
            }
            Start-Sleep -Milliseconds 300
        }
    } finally {
        $liveG.Dispose(); $liveBmp.Dispose()
    }
    Write-Host "AUTO_UNKNOWN_TIMEOUT(ms=$([int]$sw.ElapsedMilliseconds)) - 15s 内按钮状态不定论，停机人工检查"
    return -1
}

if ($FirstWaitSec -gt 0) { "first wait ${FirstWaitSec}s"; Start-Sleep -Seconds $FirstWaitSec }

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
  if ($by -lt 0) { "round ${i}: band vanished, rescan"; $i--; continue }
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
  if (-not $NoAuto) {
    $ems = Ensure-Auto
    if ($ems -lt 0) { "STOP: auto ensure failed"; exit 3 }
  }
}
"LOOP: max rounds reached"

param([int]$Pid2 = 0, [switch]$Debug, [string]$Img = "", [switch]$Quick)
# 个人电脑版状态探针（DPI-aware 客户区物理坐标体系）
# 用途：扫像素返回画面状态枚举，替代「截图->模型读图」确认，省 token
# 输出: client=...(仅实时模式首行) / STATE=<枚举>
#   GOLD_DIALOG   金色主按钮弹窗（登录页「进入游戏」/ 复活面板「立即复活」/ 挂机弹窗「确定」
#                 三者按钮位置重叠，动作统一：点 (700,513) —— 对三种弹窗都安全且正确）
#   STAMINA_POP   「体力 数量:N」弹窗（体力不足停止信号，点空白关闭）
#   SETTLE_PAGE   结算页（可点「再来一次」）
#   LOGIN_PAGE    登录页（点「进入游戏」571,527）
#   AUTO_ON       按钮模板匹配=「取消自动」→ 已开启（勿再点）
#   AUTO_OFF      按钮模板匹配=「自动战斗」→ 未开启（需点 224,181）
#                 （2026-10-23 晚重写：模板匹配判定，与血量/tip/底色全部无关）
#   OCCLUDED      纯色画面（最小化/遮挡/锁屏），先 wxrestore（事件4/15）
#   UNKNOWN       以上都不是（需人工截图确认）
# -Img <png>：离线分析整客户端区截图（回归测试/标定用，跳过窗口查找与纯色守卫）
# -Quick：轻量模式（等待结算轮询用）——只算 金弹窗/结算带/体力弹窗 三个廉价特征，
#         跳过 模板/CHAR/血条/登录侧栏（省 ~60% 像素扫描）；输出状态限定 GOLD_DIALOG/SETTLE_PAGE/STAMINA_POP/UNKNOWN
# -Debug 输出各区域命中像素数，用于现场校准阈值/区域
# 已知误报（2026-10-25 实测，回归清单已锁行为）：主城金色图标致 GOLD_DIALOG；毁灭之塔红月背景致 SETTLE_PAGE；
#   战斗中红色怪/特效进入结算扫描带可瞬态误报 SETTLE_PAGE（s1_state_check 案例）——与战败结算面板四信号同签名
#   （btnMatch/hp/gold/settle 全同），无法修正不误伤；wxgrind 影响=一次空点后自恢复，无害。
# 校准记录 2026-10-23：金按钮/绿字/暗红/血条/登录白字阈值见 coords-personal.md 探针校准记录
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

if ($Img -ne "") {
    if (-not (Test-Path $Img)) { "ERR: image not found: $Img"; exit 4 }
    $bmp = New-Object System.Drawing.Bitmap $Img
} else {
    $h = Find-GameWindow -Pid2 $Pid2
    if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    $geo = Get-ClientGeometry $h
    "client=$($geo.W)x$($geo.H) origin=$($geo.OX),$($geo.OY)"
    $bmp = New-Object System.Drawing.Bitmap $geo.W, $geo.H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($geo.OX, $geo.OY, 0, 0, (New-Object System.Drawing.Size $geo.W, $geo.H))
    $g.Dispose()
    # 遮挡守卫（事件4/15）：网格采样色彩多样性，整屏纯色=最小化/遮挡/锁屏，像素不可信 → 报 OCCLUDED
    $distinct = @{}
    for ($yy = 0; $yy -lt $bmp.Height; $yy += 40) { for ($xx = 0; $xx -lt $bmp.Width; $xx += 40) {
      $distinct[$bmp.GetPixel($xx,$yy).ToArgb()] = $true
    }}
    if ($distinct.Count -le 2) { $bmp.Dispose(); "STATE=OCCLUDED"; "debug: flat screenshot (最小化/遮挡/锁屏)，画面不可信，先 wxrestore"; exit 0 }
}

# --- 区域定义（客户区物理坐标；绑定 1138x708 布局，尺寸变更须重标） ---
# 金色主按钮区：登录「进入游戏」+ 复活「立即复活」/挂机「确定」的并集
$RX0=440; $RY0=470; $RX1=800; $RY1=560
# 体力弹窗绿色文字区
$SX0=420; $SY0=380; $SX1=760; $SY1=540
# 结算暗红按钮扫描带
$BX=915; $BY0=225; $BH=220
# 底部血条区 —— AUTO_* 的必要条件（排除非战斗页白字干扰）
$HX0=480; $HY0=655; $HX1=700; $HY1=680
# 登录页「进入游戏」白色大字区
$LX0=440; $LY0=505; $LX1=735; $LY1=556
# 左侧分类栏白字区（排除登录页误报）
$NX0=30; $NY0=130; $NX1=160; $NY1=520

function CountPixels([int]$x0,[int]$y0,[int]$x1,[int]$y1,[scriptblock]$pred) {
  $n = 0
  for ($y=$y0; $y -le $y1; $y+=2) { for ($x=$x0; $x -le $x1; $x+=2) {
    $c = $bmp.GetPixel($x,$y)
    if (& $pred $c) { $n++ }
  }}
  return $n
}

# 金色大按钮: R>200 G>140 B<110 R-B>90
$nGold = CountPixels $RX0 $RY0 $RX1 $RY1 { param($c) $c.R -gt 200 -and $c.G -gt 140 -and $c.B -lt 110 -and ($c.R-$c.B) -gt 90 }
# 绿色文字: G>170 G-R>50 G-B>50
$nStam   = CountPixels $SX0 $SY0 $SX1 $SY1 { param($c) $c.G -gt 170 -and ($c.G-$c.R) -gt 50 -and ($c.G-$c.B) -gt 50 }
# 结算暗红块（三点采样取二）
$nSettle = 0
for ($y=$BY0; $y -lt ($BY0+$BH); $y+=3) {
  $hit = 0
  foreach ($dx in @(-25,0,25)) {
    $c = $bmp.GetPixel($BX+$dx,$y)
    if ($c.R -gt 100 -and ($c.R-$c.B) -gt 50 -and $c.G -gt 22 -and $c.G -lt 78) { $hit++ }
  }
  if ($hit -ge 2) { $nSettle++ }
}

if ($Quick) {
    $bmp.Dispose()
    $qstate = "UNKNOWN"
    if     ($nGold -ge 450)  { $qstate = "GOLD_DIALOG" }
    elseif ($nSettle -ge 10) { $qstate = "SETTLE_PAGE" }
    elseif ($nStam  -ge 60)  { $qstate = "STAMINA_POP" }
    "STATE=$qstate"
    if ($Debug) { "debug: gold=$nGold stamina=$nStam settle=$nSettle" }
    exit 0
}

# 血条: 绿或红
$nHp = CountPixels $HX0 $HY0 $HX1 $HY1 { param($c) (($c.G -gt 140 -and ($c.G-$c.R) -gt 40 -and ($c.G-$c.B) -gt 40)) -or ($c.R -gt 170 -and ($c.R-$c.G) -gt 60) }
# 登录页白色大字: R,G,B 均>215
$nLogin = CountPixels $LX0 $LY0 $LX1 $LY1 { param($c) $c.R -gt 215 -and $c.G -gt 215 -and $c.B -gt 215 }
# 左侧分类栏白字
$nSide = CountPixels $NX0 $NY0 $NX1 $NY1 { param($c) $c.R -gt 215 -and $c.G -gt 215 -and $c.B -gt 215 }

# 左上角按钮文字模板匹配（AUTO_ON/AUTO_OFF 判定唯一来源；区域/模板由 _wxcommon 单源提供）
$tpl = Import-WxBtnTemplates
$live = Get-WxBmpMask $bmp $WX_BTN_X0 $WX_BTN_Y0
$dOn  = [math]::Round((Get-WxJaccard $live $tpl.On), 3)
$dOff = [math]::Round((Get-WxJaccard $live $tpl.Off), 3)
$btnMatch = (($dOn -le 0.60 -and ($dOff - $dOn) -ge 0.10) -or ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10))

# 选角页金框检测（惰性计算 2026-10-25 晚）：仅非战斗(无按钮匹配)/非结算/非金弹窗页才算，
# 战斗与结算页跳过 ~3.5 万次 GetPixel，探针耗时降 ~70%（提频轮询的前提）。
# 标定：选中卡条带 61~117/未选 0，阈值 40+唯一性；副本页金 tab 门控（步长2 ≥40）防卡面金饰误触发
# 卡5/6（2026-10-25 22:2x 实战校准）：点第二排卡后选角页自动上滚一屏，金框底边 y≈581（wxwhitebox 实测 244 像素），
# 条带取 (10,572)-(250,590)/(300,572)-(530,590)。⚠️ 仅适配"点卡后滚动"状态；若未来出现不滚动场景需按滚动状态双条带重标
$charState = "CHAR_NONE"
$charCounts = @(0,0,0,0,0,0)
if (-not $btnMatch -and $nSettle -lt 10 -and $nGold -lt 150) {
    $charStrips = @(
        @(10,130,105,168), @(300,130,530,168), @(595,130,825,168), @(885,130,1130,168),
        @(10,572,250,590), @(300,572,530,590)
    )
    for ($ci = 0; $ci -lt 6; $ci++) {
        $s = $charStrips[$ci]
        $n = 0
        for ($y = $s[1]; $y -le $s[3]; $y++) { for ($x = $s[0]; $x -le $s[2]; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 200 -and $c.G -gt 140 -and $c.B -lt 110 -and ($c.R - $c.B) -gt 90) { $n++ }
        } }
        $charCounts[$ci] = $n
    }
    $dungeonTabGold = 0
    for ($y = 140; $y -le 205; $y += 2) { for ($x = 30; $x -le 160; $x += 2) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 200 -and $c.G -gt 140 -and $c.B -lt 110 -and ($c.R - $c.B) -gt 90) { $dungeonTabGold++ }
    } }
    if ($dungeonTabGold -ge 40) { $charCounts = @(0,0,0,0,0,0) }   # 步长2计数：副本页tab~65，选角页~10
    $charBest = 0; $charIdx = 0
    for ($ci = 0; $ci -lt 6; $ci++) { if ($charCounts[$ci] -gt $charBest) { $charBest = $charCounts[$ci]; $charIdx = $ci + 1 } }
    $charSecond = 0
    for ($ci = 0; $ci -lt 6; $ci++) { if (($ci + 1) -ne $charIdx -and $charCounts[$ci] -gt $charSecond) { $charSecond = $charCounts[$ci] } }
    if ($charBest -ge 40 -and $charSecond -lt 40) { $charState = "CHAR$charIdx" }
}
$bmp.Dispose()
$state = "UNKNOWN"
# 状态机（2026-10-25 晚 PAGE 重标定）：
#  GOLD 阈值 150→450：真弹窗金确定钮 gold≈1066，主城金图标 gold=193-206 —— 一刀切开
#  SETTLE_PAGE 加 btnMatch 门控：毁灭之塔红月背景 settle=16-22 但无按钮（dist=1），真结算面板按钮可见
if     (-not $btnMatch -and $nGold -ge 450)                            { $state = "GOLD_DIALOG" } # 金确定钮弹窗（挂机/顶号/死亡，gold≈1066；用 wxpopup 细分）
elseif ($nGold -ge 100 -and $nSide -ge 100 -and $nSettle -lt 10)       { $state = "TOWN_PAGE" }   # 主城：金图标 193-206 + 左侧栏 186-217
elseif ($nSettle -ge 10 -and $btnMatch)                                { $state = "SETTLE_PAGE" } # 真结算：面板按钮可见（战斗中红怪入带误报仍不可修，见档案）
elseif ($nSettle -ge 10)                                               { $state = "TOWER_PAGE" }  # 塔页红月：settle 命中但无按钮
elseif ($nLogin  -ge 400 -and $nHp -lt 30 -and $nSide -lt 20)          { $state = "LOGIN_PAGE" }
elseif ($dOn  -le 0.60 -and ($dOff - $dOn) -ge 0.10)                   { $state = "AUTO_ON" }
elseif ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10)                   { $state = "AUTO_OFF" }   # 按钮=「自动战斗」(关)
elseif ($charState -ne "CHAR_NONE")                                    { $state = $charState }   # 选角页金框（选中卡条带唯一≥40）
elseif ($nStam   -ge 60)                                               { $state = "STAMINA_POP" } # 最后判：战斗画面绿色特效会污染 stamina 区
"STATE=$state"
# PAGE 附加行（信息用，页面身份签名标定 2026-10-25：主城 193/186、副本 side=461、选角 side=486+、塔页 16-22/17-23、世界地图全 0）
$page = switch -regex ($state) {
    "SETTLE_PAGE|AUTO_ON|AUTO_OFF" { if ($nSettle -ge 10) { "SETTLE" } else { "BATTLE" } }
    "TOWER_PAGE" { "TOWER" }
    "TOWN_PAGE" { "TOWN" }
    "LOGIN_PAGE" { "LOGIN" }
    "CHAR\d" { "CHARSEL" }
    default {
        if ($dungeonTabGold -ge 40) { "DUNGEON" }
        elseif ($nSide -ge 400) { "CHARSEL" }
        elseif (($nSide -lt 50) -and ($nGold -lt 50) -and ($nSettle -lt 5) -and ($nLogin -lt 50)) { "WORLD_MAP" }
        else { "UNKNOWN" }
    }
}
"PAGE=$page"
if ($Debug) { "debug: gold=$nGold stamina=$nStam settle=$nSettle login=$nLogin side=$nSide dist_on=$dOn dist_off=$dOff hp=$nHp char=$($charCounts -join ',')" }

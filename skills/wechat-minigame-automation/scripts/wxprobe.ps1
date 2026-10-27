param([int]$Pid2 = 0, [switch]$Debug, [string]$Img = "", [switch]$Quick)
# 状态探针（设计坐标体系 1138x708；抓图自动等比换算+归一化）
# 用途：扫像素返回画面状态枚举，替代「截图->模型读图」确认，省 token
# 输出: client=...(仅实时模式首行) / STATE=<枚举>
#   GOLD_DIALOG   金色主按钮弹窗（登录页「进入游戏」/ 复活面板「立即复活」/ 挂机弹窗「确定」
#                 三者按钮位置重叠，动作统一：点 (700,513) —— 对三种弹窗都安全且正确）
#   STAMINA_POP   「体力 数量:N」弹窗（体力不足停止信号，点空白关闭）
#   SETTLE_PAGE   结算页（可点「再来一次」）
#   AUTO_ON       按钮模板匹配=「取消自动」→ 已开启（勿再点）
#   AUTO_OFF      按钮模板匹配=「自动战斗」→ 未开启（需点 224,181）
#                 （2026-10-23 晚重写：模板匹配判定，与血量/tip/底色全部无关）
#   OCCLUDED      纯色画面（最小化/遮挡/锁屏），先 wxrestore（事件4/15）
#   UNKNOWN       以上都不是（需人工截图确认）
#                 ⚠️ 2026-10-27 起 主城/登录页均报 UNKNOWN：TOWN_PAGE+LOGIN_PAGE 像素判据退役，
#                 页面身份以 OCR 为准——主城=wxocr -Task town，登录页=wxocr -Task server
# -Img <png>：离线分析整客户端区截图（任意尺寸自动归一化到 1138x708；回归/标定用，跳过窗口查找与纯色守卫）
# -Quick：轻量模式（等待结算轮询用）——只算 金弹窗/结算带/体力弹窗 三个廉价特征，
#         跳过 模板/CHAR/血条/登录侧栏（省 ~60% 像素扫描）；输出状态限定 GOLD_DIALOG/SETTLE_PAGE/STAMINA_POP/UNKNOWN
# -Debug 输出各区域命中像素数，用于现场校准阈值/区域
# 已知误报（2026-10-25 实测，回归清单已锁行为）：主城金色图标致 GOLD_DIALOG；毁灭之塔红月背景致 SETTLE_PAGE；
#   战斗中红色怪/特效进入结算扫描带可瞬态误报 SETTLE_PAGE（s1_state_check 案例）——与战败结算面板四信号同签名
#   （btnMatch/hp/gold/settle 全同），无法修正不误伤；wxgrind 影响=一次空点后自恢复，无害。
# 校准记录 2026-10-23：金按钮/绿字/暗红/血条/登录白字阈值见 coords.md 探针校准记录
. (Join-Path $PSScriptRoot '_wxcommon.ps1')

if ($Img -ne "") {
    if (-not (Test-Path $Img)) { "ERR: image not found: $Img"; exit 4 }
    $bmp = New-Object System.Drawing.Bitmap $Img
    if ($bmp.Width -ne $WX_DESIGN_W -or $bmp.Height -ne $WX_DESIGN_H) {
        $norm = Resize-WxBitmapNearest $bmp $WX_DESIGN_W $WX_DESIGN_H
        if (-not [object]::ReferenceEquals($norm, $bmp)) { $bmp.Dispose() }
        $bmp = $norm
    }
} else {
    $h = Find-GameWindow -Pid2 $Pid2
    if ($h -eq [IntPtr]::Zero) { "ERR: window not found (pid=$Pid2)"; exit 1 }
    # 前台守卫（todo 第3项，2026-10-27 接线）：不在前台先拉回，防读到旧画面假数据
    if (-not (Confirm-WxForeground $h 'probe')) { "ERR: game not foreground，探测拒绝（防假数据）"; exit 7 }
    $geo = Get-ClientGeometry $h
    "client=$($geo.W)x$($geo.H) origin=$($geo.OX),$($geo.OY) scale=$([math]::Round($geo.S,4))"
    $bmp = Get-DesignBitmap $geo
    # 遮挡守卫（事件4/15）：网格采样色彩多样性，整屏纯色=最小化/遮挡/锁屏，像素不可信 → 报 OCCLUDED
    $distinct = @{}
    for ($yy = 0; $yy -lt $bmp.Height; $yy += 40) { for ($xx = 0; $xx -lt $bmp.Width; $xx += 40) {
      $distinct[$bmp.GetPixel($xx,$yy).ToArgb()] = $true
    }}
    if ($distinct.Count -le 2) { $bmp.Dispose(); "STATE=OCCLUDED"; "debug: flat screenshot (最小化/遮挡/锁屏)，画面不可信，先 wxrestore"; exit 0 }
}

# --- 区域定义（设计坐标 1138x708；抓图已归一化到设计尺寸，客户区等比变化无需重标） ---
# 金色主按钮区：登录「进入游戏」+ 复活「立即复活」/挂机「确定」的并集
$RX0=440; $RY0=470; $RX1=800; $RY1=560
# 体力弹窗绿色文字区
$SX0=420; $SY0=380; $SX1=760; $SY1=540
# 结算暗红按钮扫描带
$BX=915; $BY0=225; $BH=220
# 底部血条区 —— AUTO_* 的必要条件（排除非战斗页白字干扰）
$HX0=480; $HY0=655; $HX1=700; $HY1=680
# 登录页「进入游戏」白色大字区（LX0-LY1 常量已随 LOGIN_PAGE 退役删除，2026-10-27；OCR 判据=wxocr server 任务）
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
# 左侧分类栏白字（nLogin 已随 LOGIN_PAGE 退役删除，2026-10-27）
$nSide = CountPixels $NX0 $NY0 $NX1 $NY1 { param($c) $c.R -gt 215 -and $c.G -gt 215 -and $c.B -gt 215 }

# 左上角按钮文字模板匹配（AUTO_ON/AUTO_OFF 判定唯一来源；区域/模板由 _wxcommon 单源提供）
$tpl = Import-WxBtnTemplates
$live = Get-WxBmpMask $bmp $WX_BTN_X0 $WX_BTN_Y0
$dOn  = [math]::Round((Get-WxJaccard $live $tpl.On), 3)
$dOff = [math]::Round((Get-WxJaccard $live $tpl.Off), 3)
$btnMatch = (($dOn -le 0.60 -and ($dOff - $dOn) -ge 0.10) -or ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10))

# 副本页金 tab 检测（PAGE=DUNGEON 判据；惰性计算：仅非战斗/非结算/非金弹窗页才算，省 ~3.5 万次 GetPixel）
# ⚠️ 选角页金框检测（CHAR1-6）已于 2026-10-26 整体退役（用户定版：验证一律 OCR 优先）——
#   金框细描边在缩小窗（S≈0.5）下抗锯齿混色致阈值全灭，且曾引发放宽阈值→tab 门控误报连锁；
#   选角页身份改由 wxocr.ps1 -Task charsel 权威判定（读「选择角色」标题，粗字形抗缩放）。
$dungeonTabGold = 0
if (-not $btnMatch -and $nSettle -lt 10 -and $nGold -lt 150) {
    for ($y = 140; $y -le 205; $y += 2) { for ($x = 30; $x -le 160; $x += 2) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 200 -and $c.G -gt 140 -and $c.B -lt 110 -and ($c.R - $c.B) -gt 90) { $dungeonTabGold++ }
    } }
}
$bmp.Dispose()
$state = "UNKNOWN"
# 状态机（2026-10-25 晚 PAGE 重标定；2026-10-27 TOWN_PAGE+LOGIN_PAGE 退役——
#   主城像素签名对背景脆弱（三背景实测中下金带 snow/crowd=0），登录页 nLogin 美术改版后 389 卡阈值 400 边缘拉跨；
#   用户定版：页面身份一律 OCR。主城=wxocr -Task town，登录页=wxocr -Task server。
#   wxprobe 在主城/登录页将报 UNKNOWN，属预期。）
#  GOLD 阈值 150→450：真弹窗金确定钮 gold≈1066，主城金图标 gold=193-206 —— 一刀切开
#  SETTLE_PAGE 加 btnMatch 门控：毁灭之塔红月背景 settle=16-22 但无按钮（dist=1），真结算面板按钮可见
if     (-not $btnMatch -and $nGold -ge 450)                            { $state = "GOLD_DIALOG" } # 金确定钮弹窗（挂机/顶号/死亡，gold≈1066；用 wxpopup 细分）
elseif ($nSettle -ge 10 -and $btnMatch)                                { $state = "SETTLE_PAGE" } # 真结算：面板按钮可见（战斗中红怪入带误报仍不可修，见档案）
elseif ($nSettle -ge 10)                                               { $state = "TOWER_PAGE" }  # 塔页红月：settle 命中但无按钮
elseif ($dOn  -le 0.60 -and ($dOff - $dOn) -ge 0.10)                   { $state = "AUTO_ON" }
elseif ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10)                   { $state = "AUTO_OFF" }   # 按钮=「自动战斗」(关)
elseif ($nStam   -ge 60)                                               { $state = "STAMINA_POP" } # 最后判：战斗画面绿色特效会污染 stamina 区
"STATE=$state"
# PAGE 附加行（信息用，页面身份签名标定 2026-10-25：主城 193/186、副本 side=461、选角 side=486+、塔页 16-22/17-23、世界地图全 0）
# ⚠️ 选角页权威判定=wxocr -Task charsel（OCR「选择角色」标题）；此处 side 兜底仅作粗信号，副本页 side=461 也会过线，
#    区分靠 dungeonTabGold 抢跑——小窗下若金 tab 亦混色衰减，PAGE 可能误报 CHARSEL，关键流程以 OCR 为准（2026-10-26 用户定版）
$page = switch -regex ($state) {
    "SETTLE_PAGE|AUTO_ON|AUTO_OFF" { if ($nSettle -ge 10) { "SETTLE" } else { "BATTLE" } }
    "TOWER_PAGE" { "TOWER" }
    default {
        if ($dungeonTabGold -ge 40) { "DUNGEON" }
        elseif ($nSide -ge 400) { "CHARSEL" }
        elseif (($nSide -lt 50) -and ($nGold -lt 50) -and ($nSettle -lt 5)) { "WORLD_MAP" }
        else { "UNKNOWN" }
    }
}
"PAGE=$page"
if ($Debug) { "debug: gold=$nGold stamina=$nStam settle=$nSettle side=$nSide dist_on=$dOn dist_off=$dOff hp=$nHp dungeonTab=$dungeonTabGold" }

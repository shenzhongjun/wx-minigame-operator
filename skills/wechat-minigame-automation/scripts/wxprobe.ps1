param([int]$Pid2 = 0, [switch]$Debug, [string]$Img = "", [switch]$Quick)
# 状态探针（设计坐标体系 1138x708；抓图自动等比换算+归一化）
# 用途：扫像素返回画面状态枚举，替代「截图->模型读图」确认，省 token
# 输出: client=...(仅实时模式首行) / STATE=<枚举>
#   GOLD_DIALOG   金色主按钮弹窗（登录页「进入游戏」/ 复活面板「立即复活」/ 挂机弹窗「确定」
#                 三者按钮位置重叠，动作统一：点 (700,513) —— 对三种弹窗都安全且正确）
#   STAMINA_POP   「体力 数量:N」弹窗（体力不足停止信号，点空白关闭）
#   SETTLE_PAGE   结算页（可点「再来一次」）
#   AUTO_ON       按钮模板匹配=「取消自动」→ 已开启（勿再点）
#   AUTO_OFF      按钮模板匹配=「自动战斗」→ 未开启（补开唯一入口=wxautoensure，勿手点坐标）
#                 （2026-10-23 晚重写：模板匹配判定，与血量/tip/底色全部无关）
#   OCCLUDED      纯色画面（最小化/遮挡/锁屏），先 wxrestore（事件4/15）
#   TOWN_PAGE     主城（2026-10-31 恢复：战力条/福利/商城 三探针 ≥2 阳性，用户定版；选角/主城 OCR 判据弃用）
#   （NEWBIE_PACK 已于 2026-10-31 迁出：弹窗一律归 wxpopup 判 POPUP_PACK，probe 只出场景状态）
#   UNKNOWN       以上都不是（需人工截图确认）
#                 ⚠️ 登录页仍报 UNKNOWN：LOGIN_PAGE 像素判据已退役（2026-10-27），登录页身份=wxocr -Task server
#                 （旧「主城报 UNKNOWN」约定 2026-10-31 随三探针恢复而废止，主城不再依赖 OCR）
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
    # 离线图守卫（2026-10-31 用户定版：-Img 不再豁免小窗线，与实时路径统一走 800 公共守卫）
    $iw = $bmp.Width; $ih = $bmp.Height
    if (-not (Test-WxMinClientW $iw)) {
        $bmp.Dispose(); "ERR: image ${iw}x${ih} 过小（宽须>=$($WX_MIN_CLIENT_W)），-Img 需传完整客户端区截图"; exit 4
    }
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
    # 最小窗口守卫（2026-10-31 补齐单源，此前 probe 是唯一漏网的实时路径）：
    # 窄条窗归一化后像素仍会给出「看似正常」的 STATE，属静默错判，比报错更危险 → 拒绝探测。
    if (-not (Test-WxMinClientW $geo.W)) { "ERR: window too small ($($geo.W)x$($geo.H) < ${WX_MIN_CLIENT_W} width)，探测拒读"; exit 7 }
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
# 结算暗红按钮扫描带（v1.1.14 重标定 2026-10-28：按钮面板主体 x849-971 实测，BX 915→900；
#   离线 9 状态: settle2col=16 / settle3col=19 / tower=25(锁定 TOWER 行为) / 其余 0）
$BX=900; $BY0=225; $BH=220
# 底部血条区 —— AUTO_* 的必要条件（排除非战斗页白字干扰）（v1.1.14: x0 480→440 实测条体 451-677）
$HX0=440; $HY0=655; $HX1=700; $HY1=680
# 登录页「进入游戏」白色大字区（LX0-LY1 常量已随 LOGIN_PAGE 退役删除，2026-10-27；OCR 判据=wxocr server 任务）
# 左侧分类栏白字区（排除登录页误报）
$NX0=30; $NY0=130; $NX1=160; $NY1=520
# town 三探针区（v1.1.17 接线 2026-10-31 用户定版：三探针 ≥2 阳性=主城）
$TPX0=230; $TPY0=132; $TPX1=370; $TPY1=172   # 战力条暗红
$TWX0=658; $TWY0=60;  $TWX1=735; $TWY1=155   # 福利暗金
$TSX0=848; $TSY0=80;  $TSX1=895; $TSY1=115   # 商城金
# 礼包 ¥30 金钮区 (529,520)-(763,603) 已于 2026-10-31 迁至 _wxcommon.ps1 $WX_PACK_PROBES（归 wxpopup）

function CountPixels([int]$x0,[int]$y0,[int]$x1,[int]$y1,[scriptblock]$pred) {
  $n = 0
  for ($y=$y0; $y -le $y1; $y+=2) { for ($x=$x0; $x -le $x1; $x+=2) {
    $c = $bmp.GetPixel($x,$y)
    if (& $pred $c) { $n++ }
  }}
  return $n
}
# town 探针专用：只隔列采样（x+=2，y 逐行）。阈值=蓝本 town4-probe.ps1 全分辨率标定值÷2；
#   2×2 隔行对 pack 区细纹理走样风险大（9610/4=2402 距 750 仅 3.4% 余量）故弃，逐行无此问题。
function CountPixelsX2([int]$x0,[int]$y0,[int]$x1,[int]$y1,[scriptblock]$pred) {
  $n = 0
  for ($y=$y0; $y -le $y1; $y++) { for ($x=$x0; $x -le $x1; $x+=2) {
    if (& $pred $bmp.GetPixel($x,$y)) { $n++ }
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

# town 三探针 + 新手礼包 ¥30（v1.1.17；区域/谓词/阈值权威=coords.md「town 探针判据」节）
$predTownGold = { param($c) $c.R -ge 170 -and $c.G -ge 120 -and $c.B -le 140 -and ($c.R-$c.B) -ge 60 }
$nPower = CountPixelsX2 $TPX0 $TPY0 $TPX1 $TPY1 { param($c) $c.R -ge 100 -and $c.R -le 235 -and $c.G -lt 80 -and $c.B -lt 80 -and ($c.R-$c.G) -gt 60 }
$nTownW = CountPixelsX2 $TWX0 $TWY0 $TWX1 $TWY1 $predTownGold
$nShop  = CountPixelsX2 $TSX0 $TSY0 $TSX1 $TSY1 $predTownGold
# 礼包像素计数已随弹窗判定迁至 wxpopup（2026-10-31），probe 不再采样 pack 区
# 阈值（全分辨率标定÷2）：power 300→150 / welfare 100→50 / shop 60→30 / pack 3000→1500
$townVotes = ($nPower -ge 150) + ($nTownW -ge 50) + ($nShop -ge 30)

# 左上角按钮文字模板匹配（AUTO_ON/AUTO_OFF 判定唯一来源；区域/模板由 _wxcommon 单源提供）
$tpl = Import-WxBtnTemplates
$live = Get-WxBmpMask $bmp $WX_BTN_X0 $WX_BTN_Y0
$dOn  = [math]::Round((Get-WxJaccard $live $tpl.On), 3)
$dOff = [math]::Round((Get-WxJaccard $live $tpl.Off), 3)
$btnMatch = (($dOn -le 0.60 -and ($dOff - $dOn) -ge 0.10) -or ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10))

# 副本页金 tab 检测（PAGE=DUNGEON 判据）已退役（2026-10-28 用户裁决）：归一化根治后判据失效
#   （塔页金元素 y159-260，本区仅 8 hits；扩区则主城金 79 vs 塔页 21 无法阈值切分），且无外部消费方，
#   页面身份一律 OCR 优先（2026-10-27 定版）。详录 incidents 事件21 同期 CHANGELOG [1.1.14]。
# ⚠️ 选角页金框检测（CHAR1-6）已于 2026-10-26 整体退役（用户定版：验证一律 OCR 优先）——
#   金框细描边在缩小窗（S≈0.5）下抗锯齿混色致阈值全灭，且曾引发放宽阈值→tab 门控误报连锁；
#   选角页身份改由 wxocr.ps1 -Task charsel 权威判定（读「选择角色」标题，粗字形抗缩放）。
$bmp.Dispose()
$state = "UNKNOWN"
# 状态机（2026-10-25 晚 PAGE 重标定；2026-10-27 TOWN_PAGE+LOGIN_PAGE 像素判据退役，页面身份一律 OCR；
#   2026-10-31 TOWN_PAGE 以三探针判据恢复（对背景鲁棒，4 正 6 负全分对+实机验证），选角/主城 OCR 判据弃用；
#   登录页仍报 UNKNOWN 属预期，身份=wxocr -Task server。）
#  GOLD 阈值 150→450：真弹窗金确定钮 gold≈1066，主城金图标 gold=193-206 —— 一刀切开
#  SETTLE_PAGE 加 btnMatch 门控：毁灭之塔红月背景 settle=16-22 但无按钮（dist=1），真结算面板按钮可见
#  礼包弹窗自 2026-10-31 起归 wxpopup 判（POPUP_PACK），probe 只管场景状态、不再出弹窗态
if     (-not $btnMatch -and $nGold -ge 450)                            { $state = "GOLD_DIALOG" } # 金确定钮弹窗（挂机/顶号/死亡，gold≈1066；用 wxpopup 细分）
elseif ($nSettle -ge 10 -and $btnMatch)                                { $state = "SETTLE_PAGE" } # 真结算：面板按钮可见（战斗中红怪入带误报仍不可修，见档案）
elseif ($nSettle -ge 10 -and $nGold -lt 100)                           { $state = "TOWER_PAGE" }  # 塔页红月：settle 命中但无按钮。gold 门控（2026-10-31）：礼包弹窗 settle=50 但 gold=447 会把遮挡画面错说成塔页；塔页 4 样本实测 gold=0，余量极大
elseif ($dOn  -le 0.60 -and ($dOff - $dOn) -ge 0.10)                   { $state = "AUTO_ON" }
elseif ($dOff -le 0.60 -and ($dOn - $dOff) -ge 0.10)                   { $state = "AUTO_OFF" }   # 按钮=「自动战斗」(关)
elseif ($nStam   -ge 60)                                               { $state = "STAMINA_POP" } # 最后判：战斗画面绿色特效会污染 stamina 区
elseif ($townVotes -ge 2)                                              { $state = "TOWN_PAGE" }   # 主城三探针 2/3 阳性（2026-10-31 用户定版）
"STATE=$state"
# PAGE 附加行（信息用，页面身份签名标定 2026-10-25：主城 193/186、副本 side=461、选角 side=486+、塔页 16-22/17-23、世界地图全 0）
# ⚠️ 选角页权威判定=wxocr -Task charsel（OCR「选择角色」标题）；此处 side 兜底仅作粗信号，副本页 side=461 也会过线
#    （DUNGEON 抢跑已退役），副本页可能报 CHARSEL，关键流程以 OCR 为准（2026-10-26 用户定版）
$page = switch -regex ($state) {
    "SETTLE_PAGE|AUTO_ON|AUTO_OFF" { if ($nSettle -ge 10) { "SETTLE" } else { "BATTLE" } }
    "TOWER_PAGE" { "TOWER" }
    "TOWN_PAGE" { "TOWN" }
    default {
        if ($nSide -ge 400) { "CHARSEL" }
        elseif (($nSide -lt 50) -and ($nGold -lt 50) -and ($nSettle -lt 5)) { "WORLD_MAP" }
        else { "UNKNOWN" }
    }
}
"PAGE=$page"
if ($Debug) { "debug: gold=$nGold stamina=$nStam settle=$nSettle side=$nSide dist_on=$dOn dist_off=$dOff hp=$nHp power=$nPower welfare=$nTownW shop=$nShop townvotes=$townVotes" }

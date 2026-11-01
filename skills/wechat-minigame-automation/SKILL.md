---
name: wechat-minigame-automation
description: 勇士之心自动化作业手册（操作方法与排错知识源）。由专家 wx-minigame-operator 在开局协议下读取调用；涵盖脚本用法、坐标体系、状态判定、停止条件与故障排查。不直接作为任务入口——入口是专家 wx-minigame-operator。
---

# 微信小游戏桌面自动化 · 作业手册

腾讯系小游戏跑在 `WeChatAppEx.exe` 宿主里，画面全是 canvas：UI 自动化树只有一个 document 加一堆无标签 image，**没有任何可读按钮**。所有交互只能「点击/探针脚本 → 像素判定状态」。

> **🚨 铁律：任何 .ps1（含一次性脚本）落盘后必须 BOM（前3字节=EF BB BF）+ Parser 0 错误双校验，过了才准执行，无例外。补 BOM 严禁 `Get-Content -Raw`（固化乱码）。做法见 `run-environment-pitfalls.md` §2。**


## 档案路由索引（执行用；结构定义与归属规则唯一权威源 = `管理新规.md`）

| 要找什么 | 去哪 |
|---|---|
| 本文件 | 跨版本稳定核心：机制、脚本清单与用法、坐标体系、排错 |
| `管理新规.md` | 治理规则（文件分工/增长管理/三态路由），优先级最高 |
| `references/tasks.md` | 角色-副本任务档案与每日任务分配 |
| `references/coords.md` | 纯坐标与标定（坐标表/缩放/像素判定/探针校准） |
| `references/ui-map.md` | 界面按钮语义/判据/红线地图（普查产出；坐标一律见 coords.md） |
| `references/features/dungeon-runs.md` | 副本刷取流程（冥渊/圣殿/航路） |
| `references/features/daily-claim.md` | 每日领体力流程 |
| `references/game-mechanics.md` | 游戏数值与机制（体力/邀请函/钻石/免费首把；每日标准循环看 tasks.md；角色分工看 tasks.md） |
| `references/incidents.md` | 事件根因档案（索引版，事件1-22） |
| `references/run-environment-pitfalls.md` | **运行环境坑全集**（执行方式/编码语法/输出捕获/桌面窗口；拉子进程必带 `-WindowStyle Hidden`） |
| `scripts/` `assets/` | 全部自动化脚本；自动战斗模板图 |
| 专家包 `wx-minigame-operator` | 角色纪律：开局协议/致命五坑/熔断/红线/收尾 |

> 本包独立封闭：包内文档、代码不引用包外任何文件或路径；开发/标定类事务不属操作员职责，发现即上报用户裁决。

## 执行规则

1. **坐标一律是设计坐标（基准 1138×708），详见 coords.md（权威表述唯一版本）**。禁止把 Read 显示图上量出的像素直接当点击坐标——显示的截图是缩放图，缩放比例随窗口大小变化，不是固定值；换算一律走函数严禁手算（见 §0 客户区结构）。
2. **自动战斗开启唯一入口=wxautoensure.ps1（OCR 单判据，v1.1.12 起全链统一）**：OCR 读左上角按钮文字（区域/锚点见 coords.md「自动战斗按钮」节）。文字=「自动战斗」=还没开（OFF），点锚点开启；文字=「取消自动」=已开（ON），别碰；读不出来（多半是转场黑屏）继续轮询。点完必须重读验证已变 ON；ON 优先判定，绝不把已开的点关。超时或点击超 3 次 → FAIL 截图人工核对。自动战斗与血量、白字 tip、按钮底色零关系（事件10/11，见 incidents.md）。同角色登录期间换图保持，切角色必重置。wxclick 的 auto/autonow 步骤=内部委托 wxautoensure（FAIL 整体 exit 3，语义不变）；**旧模板匹配 gated 循环已退役**：wxautostate 与 wxprobe 的 AUTO_ON/AUTO_OFF 输出态仅存诊断用途（wxautostate 消费方=wxrecrop/wxregress 离线）；**但 wxprobe 全量模式以 btnMatch 模板可见性作结算门控（区分塔页红月），属现役——wxwait 等结算轮询在用**。
3. 「开启冥渊」点击后必须确认按钮文字已变「冥渊模式」。
4. 重登/重开后选中角色**重置为第1个**（事件5）；同会话再进选角页则停在「上次选中角色所在屏」（2026-10-27 实证）。选中态 OCR 判不了——选卡一律走 wxcharsel 幂等双击。
5. 角色死亡弹「是否使用不死鸟羽毛」→ 点「立即复活」（坐标见 `coords.md`「死亡弹窗」行；已授权）。**统一口径：最多复活两次；复活两次仍打不过 = 任务安排有问题，停手上报用户。**

## 0. 运行环境（单机）

- **仅支持当前这台电脑**（用户 2026-10-26 定版：公司机/双机支持废止，公司代码与档案已删除；跨机器移植不在范围内）。
- 屏幕/DPI：2560×1440 @125%；坐标体系：设计坐标 1138×708 + 运行时等比换算（DPI-aware）。

- **客户区结构（2026-10-26 实测定版；**权威表述唯一版本=coords.md 头部「坐标体系权威表述」+「画布垂直居中」两节，换算公式/双语义/居中规则一律以彼处为准，本文件不重复**）**：`[微信内嵌标题栏 固定 55px，不随窗口缩放] + [游戏画布 等比缩放+居中]`。chrome 常量 `$WX_CHROME_H=55` 由 preflight 自动审计（wxcanvas.ps1 实测比对），不符即停机。**⚠️ 铁律：换算严禁手算——正向 `ConvertTo-ScreenPoint`、反向 `ConvertFrom-ScreenPoint`，标定脚本同样必须调函数；wxshot `-Raw` 截图≠设计坐标。**

## 1. 定位目标窗口

1. 一个游戏一个 `WeChatAppEx.exe` 进程，用窗口标题匹配：`Get-Process WeChatAppEx | Select Id,MainWindowTitle`，pid 传 `-Pid2`。
2. 报 `ERR: window not found` → 重查进程列表确认窗口标题还在。
3. URL 形如 `https://servicewechat.com/<appid>/<version>/page-frame.html`（appid/区服/appVersion 等游戏标识唯一出处=coords.md 头部）。

## 2. 坐标校准

档案/坐标表数字直接传入脚本，`_wxcommon` 按实时客户区等比换算（含居中留边），误差 ≤1px——换算规则与客户区结构见 §0 与 coords.md，此处不重复。截图（`wxshot` 锚定模式）已归一化到设计尺寸，图内像素可直接与坐标表对照；Read 显示图是缩放图（比例随窗口大小变化），严禁直接量取（陷阱实测数据见 coords.md「显示图缩放陷阱」）。

## 3. 按钮热区偏移

点了没反应 → 按 +30~50px 下移再试。命中后固化进档案。连续两次不中 → 按专家熔断纪律处理，请用户帮忙，不盲点。

## 4. 点击规范（2026-10-27 用户裁定：防检测扰动体系整体删除）

~~时间与位置随机扰动~~（点击坐标偏移 ±J、随机停顿/按压时长）——用户裁定防第三方检测属多虑，**已全部删除**：点击一律精确落在设计坐标，随机 sleep 改固定值。
战斗等待不变：以 features 档案实测单场时长为准（`features/dungeon-runs.md`），**wxgrind 用探针轮询等结算（上限 90s）**。
点击落空元凶：过渡未就绪/坐标偏差（小热区按钮偏 1px 即失）/布局不符/前台丢失/弹窗遮挡（incidents.md）。

## 5. 状态判定与循环

**优先探针枚举，只在 UNKNOWN 时人工截图**——省 token 的关键。

| 画面特征 | 状态 |
|---|---|
| 按钮模板=「取消自动」(ON) | 已开启，别碰 |
| 按钮模板=「自动战斗」(OFF) | wxautoensure 开启（锚点见 coords.md） |
| 「再来一次」+「返回城镇」 | 结算页（按钮坐标见 coords.md「结算页」行；「再来一次」两栏/三栏同位不变，待验证后固化写死，见开发待办） |
| 血条 + 连击数 | 战斗中 |
| 点完仍在结算页/副本列表 | 次数或体力耗尽 |

标准循环：开自动一次 → 等一场时长 → 探针确认结算 → 点「再来一次」→ 确认进图 → 未进图即停。停止条件用**行为**判断（详见 §9 与 game-mechanics.md）。

## 6. 脚本清单（全部在 `scripts/`，禁止写往其它目录；参数详见各脚本头部注释）

| 脚本 | 用途 | 关键参数 |
|---|---|---|
| `wxdoclint.ps1` | **文档维护后校验**（§13 维护流程必跑） | 见脚本头 |
| `wxpreflight.ps1` | **开局协议预检：校验档案齐全+打印要点摘要** | 无参数 |
| `wxgrind.ps1` | **固化刷本循环（主力，实战 39 轮零异常）**：探针验证+轮盘保活+GOLD 连续3次确认；`-AutoRetry` 自动扫描「再来一次」位置免传参 | `-Rounds -AutoRetry -SettleWaitSec` |
| `wxclick.ps1` | 点击连招：`-Steps "x:y:延迟;w:ms;auto"`；auto/autonow=委托 wxautoensure（OCR，v1.1.12 旧模板 gated 循环退役）；主体已并入 `_wxcore.Invoke-WxClick`，本脚本为薄壳（单次 1.5s→0.9s） | `-Pid2` |
| `wxprobe.ps1` | 状态探针（战斗/结算/主城三探针/遮挡粗信号；2026-10-31 主城 TOWN_PAGE 三探针恢复；**礼包弹窗已迁出，弹窗一律看 wxpopup**，登录页仍 OCR `server`） | `-Pid2 -Debug` |
| `wxrelogin.ps1` | **组合重登链（登录链唯一入口，`wxlogin` 已于 2026-10-31 退役并入本脚本）**：礼包弹窗先清场 → GOLD_DIALOG 经 wxpopup 分类（POPUP_IDLE 挂机自动点确定，其余顶号/涉钱/未知红线停机）→ server OCR 轮询登录页 → 进游戏 → 委托 wxcharsel 选角 → 三探针确认主城；已站主城直接返回 `ALREADY_TOWN`（不白等）。登录/选角阶段不弹礼包 | `-Char N -TownTimeoutSec -AssumeGold -Perf` |
| `wxcharsel.ps1` | **选角专职（2026-10-27 新增，卡表单源）**：起始态自适应进选角页（主城点「选角」带3次重试）→ scr1w/scr2w 判屏 → 按需切屏复核 → 幂等双击目标卡；`-StartGame` 进游戏+town 终态确认，默认停选角页。卡表坐标见 coords.md「角色卡」行（脚本内单源）；**7/8 锁槽红线禁点** | `-Char 1..6 -StartGame` |
| `wxclaim.ps1` | 商城领奖链（**禁盲跑**，见 incidents 事件16） | `-Pid2` |
| `wxpoke.ps1` | 轮盘保活戳（按下→拖→回→松；轮盘中心 210,558）。**⚠️ 2026-11-01 已从所有链路废止**：poke 无法重置挂机计时（10-26 实锤），战斗中点无反应、非战斗场景也无必要，净耗 1.5-1.8s/次且抢前台。仅保留为人工工具，链路不再调用；挂机弹窗改由 `_wxflow.Invoke-WxGoldGuard` 处置 | `-Pid2 -CX/-CY/-DX/-DY` |
| `wxautostate.ps1` | 按钮状态判定器（模板匹配核心，-Img 离线；UNKNOWN 且该区有文字时自动调 wxocr autobtn 任务 OCR 兜底，`-NoOcr` 关闭） | `-Pid2 -Img -NoOcr` |
| `_wxcommon.ps1` | **公共库（单一真相源）**：设计坐标常量（1138×708/按钮区/点击点）、标题优先窗口查找（pid 0=自动发现）、等比换算（`Get-ClientGeometry`/`ConvertTo-ScreenPoint`）、截图归一化（`Get-DesignBitmap`/`Get-DesignRegion`）、长宽比断言、模板加载/掩码/Jaccard；交互脚本全部 dot-source，禁再复制样板 | 改后必跑 wxregress ⚠️暂停中（2026-10-26 用户裁定：清单 AI 标注待人工核验） |
| `_wxcore.ps1` | **同进程模块库（2026-10-31 模块化）**：`Invoke-WxProbe`（状态探针）/ `Invoke-WxPopup`（弹窗分类）/ `Invoke-WxOcr`（OCR）/ `Invoke-WxClick`（点击）的函数本体，只返回对象不打印文本。链路 dot-source 后直接调函数，**不再起子进程**；`wxprobe/wxpopup/wxocr/wxclick` 四个 .ps1 已降为薄壳。**⚠️ OCR 引擎在进程内缓存，是全项目最大性能点：单次 3s→0.25s**（原实现每次子进程都重建 OcrEngine 加载中文模型约 2s；注释里的「250ms」只是识别本身）。接口契约见 `管理新规.md` §七；区域/阈值/判定顺序/Steps 语法与原脚本逐字一致，迁移前后离线逐图对比零漂移 | 改任一函数须同步核对对应薄壳 |
| `_wxflow.ps1` | **策略层（2026-11-01 模块化 P3/P5）**：回答「拿到这个状态该怎么办」，与 `_wxcore`（回答「画面是什么状态」）分层。含 ①`Invoke-WxGoldGuard` 金弹窗处置单源（取代 wxgrind 私有 Guard 与 wxrelogin 阶段1/阶段4 两份内联），返回 `Verdict`=OK/NONE/LOGIN/STOP，**不自判探针**，`-Cls` 可传已知分类避免重复探；②`Wait-WxState` 等状态状态机，取代 wxgrind 段1 的 `goldStreak`/`unkStreak` 手工计数器，返回 `Result`=OK/TIMEOUT/ERR/LOGIN/GOLD/STAMINA，内置 GOLD 三连确认、UNKNOWN 十连全量深探、超时 | 依赖先 dot-source `_wxcommon` + `_wxcore` |
| `wxregress.ps1` | **离线回归测试**：按 `_regress-manifest.csv` 对标注截图库（`-ImgDir` 传入）断言 BTN_STATE/STATE（已知误报锁行为）；重裁模板/改阈值/改公共库后必跑，⚠️ **暂停使用**（2026-10-26 用户裁定：清单 AI 标注未经人工核验，恢复前以实机探针+截图目验替代），全过才算改动成立 | `-Manifest -ImgDir` |
| `wxwhitebox.ps1` | 白色像素包围盒诊断（模板文字区重标定用，杜绝目测缩放图） | `-Img -X0..` |
| `wxenumwin.ps1` | 枚举进程全部可见窗口（标题/客户区/原点）——多窗口/尺寸异常排查 | `-Pid2` |
| `wxpopup.ps1` | **弹窗分类器 v2（OCR 化，薄壳，主体在 `_wxcore` 的 `Invoke-WxPopup`）**：金确定钮守卫+正文带 OCR（区域见 coords.md「弹窗」行）关键字分类——挂机(可点确定)/顶号(红线停)/扩展券(只点取消)/羽毛复活(可点确定)/无/未知(红线停)；v1 像素模板退役（正文位置浮动即全灭，2026-10-27 实战） | `-Pid2 -Img` |
| `wxstam.ps1` | **体力读数器**（选角页）：输出 LOW(<10 不可跑)/OK(≥10)，Mode=row1 顶态/row2 滚动态 | `-Pid2 -Mode` |
| `wxresize.ps1` | **尺寸复位（可选工具）**：窗口明显异常时拉回设计尺寸 1138×708；日常开局不再强制调用。目标尺寸须与设计基准同长宽比 | `-Pid2 -ClientW -ClientH` |
| `wxrecrop.ps1` | **模板重裁一条龙**：布局重排后从关/开双实拍自动求 bbox→裁模板→更新 _wxcommon 常量→离线验证，失败自动回滚；完成后必跑 wxregress ⚠️暂停中（同 wxregress 条目） `-ImgOff -ImgOn` |
| `wxautoensure.ps1` | **自动战斗快速确保 v2（v1.1.10 新增）**：出战后立即调用，轮询 OCR autobtn（OFF→点锚点（见 coords.md）→重读验证；ON 优先判定不误关），进程内调用实测 2.0s 开启（旧链 4-5s）；超时/点击超3次 FAIL | `-Pid2 -TimeoutSec` |
| `wxnav-tower.ps1` | **塔练习导航链**：主城→副本→塔→练习模式→出战，三段断言（A 副本tab金≥150 / B 塔页红≥100 / **C 练习说明框白字块≥400**，断言区域见 coords.md「毁灭之塔」节）失败即截图停机 | `-Pid2 -SkipStart` |
| `wxshot/wxcrop/wxbtnsig/wxrgbcol/wxwhere/wxrestore/wxscroll/wxwait/wxenumwin/wxdoclint` | 截图（锚定模式已归一化到设计尺寸）/裁剪放大/签名计数/RGB采样/窗口位置/恢复前台/滚轮滚动/轮询等待指定状态/枚举窗口/文档规则校验（~~wxocrbtn~~ 已删，v1.1.3 并入 wxocr） | 见脚本头 |

探针状态动作：`GOLD_DIALOG`→按专家红线处理（先 `wxpopup` 分类再决定）；`STAMINA_POP`→停（点空白关）；`SETTLE_PAGE`→点「再来一次」；`AUTO_ON` 勿点；`AUTO_OFF`→auto 点；`TOWN_PAGE`→主城，正常流程；`UNKNOWN`→人工截图（登录页/选角页 UNKNOWN 属预期——页面身份以 OCR 为准；主城自 2026-10-31 起由三探针判 TOWN_PAGE，不再依赖 OCR）。

**弹窗一律归 `wxpopup` 判**（2026-10-31 用户定版：probe 是状态探针，不再出弹窗态）：`POPUP_PACK`→点关闭红叉关礼包弹窗（🚨涉钱红线：绝不点 ¥30 金钮，红叉 (160,192) 见 coords.md）关后重探；`POPUP_IDLE`→点确定；`POPUP_EXTEND`→只点取消；`POPUP_REVIVE`→点确定；`POPUP_RELOGIN`/`POPUP_UNKNOWN`→红线停机请示用户。

**硬性路径约束：本 skill 随专家包安装，所有脚本只准写进本 skill 目录下的 `scripts\`（实际安装路径未知时，先跑 preflight 或 Glob 搜 `wxpreflight.ps1` 定位，绝不凭记忆猜路径），严禁 Temp/临时目录**

## 7. 像素探针原理

结算页「再来一次」按钮是暗红底，认色就够：红要亮（R>100）、红要比蓝深得多（R-B>50）、绿在中间档（22<G<78）。扫描带 BX=900、y 225~445（v1.1.14 重标定，细节见 coords.md）；扫到红块后从红块顶部往下 20px 点下去。**「再来一次」位置固定不变**：两栏/三栏结算里它都在第一栏、位置一样（旧「面板 Y 浮动 ±45px」说法系当年两栏/三栏没分清所致，作废）——待实机验证后坐标固化写死（开发待办），验证前扫描取点兜底。自动战斗开关不认色，只认按钮文字（OCR，唯一入口见 §执行规则2）。模板匹配只剩一个现役用途：wxprobe 全量模式用模板是否可见做结算门控（区分塔页红月），wxwait 等结算在用；模板持续 UNKNOWN 且窗口同比例，才说明真重排了，才走 wxrecrop 重裁。改阈值前先 `wxautostate -Debug`/`-Img` 采样；按钮 RGB 实测数据见 `coords.md`。

## 8. 低延迟执行

「开始战斗→等加载→开自动」绝不拆成多次工具往返——进图后 5~10 秒最脆弱（不开自动战斗容易被怪打死）。用 wxclick `-Steps` 一次进程连点，聚焦只做一次。

| 场景 | 等待策略 |
|---|---|
| 进图后开自动 | 点完进图立即调 wxautoensure（UNKNOWN 转场黑屏自动继续轮询，不用等加载；实测 2.0s 开启） |
| 循环「再来一次」 | 间隔 1~2s |
| 一场战斗时长 | 以 features 档案实测时长为准（§4），首轮 +3~5s 兜底 |

## 9. 停止条件

| 信号 | 含义 |
|---|---|
| 点「再来一次」后仍在结算页 | 材料或体力不足，停 |
| 结算后退回副本列表页 | 体力不够下一场，停 |
| 弹「体力 数量:N」（N<单场消耗） | 停 |
| 弹「冥渊邀请函 数量:0」 | 停 |
| 连点两次「再来一次」不进图 | 停，不要反复硬试 |

**每日标准循环（唯一全文）→ `references/tasks.md`；资源机制（体力/邀请函/钻石/免费首把）→ `references/game-mechanics.md`，本文件不重复。**

## 10. 顶号弹窗处置（红线摘要，全文见专家包协作红线）

「长时间未操作」→ 必须点「确定」（坐标见 coords.md「弹窗」行），禁点「取消」；「账号在其他设备登录」= 用户顶号 → 停手等指令；**角色首次登录的充值/礼包弹窗（样式可能不止一种）→ 点「X」直接关闭，绝不碰购买按钮**；其余金钱/验证码类弹窗一律停手交用户。

## 11. 故障排查

| 症状 | 原因 | 处理 |
|---|---|---|
| **刷图中频繁死亡/被秒** | **自动战斗未开启（铁律第2条）** | **第一优先核对按钮文字=「取消自动」（wxocr autobtn）；未开→唯一入口 wxautoensure 开启并验证，再查其它原因。日常自动刷的图不存在开自动打不过** |
| 「在此系统上禁止运行脚本」 | WorkBuddy PowerShell 会话 Restricted | 环境坑唯一归属=`run-environment-pitfalls.md` §1（Bypass 子进程 + `-WindowStyle Hidden` 等执行铁律） |
| CopyFromScreen 报「句柄无效」 | 屏幕锁定/会话切走 | 详见 `run-environment-pitfalls.md` §4；停手，用户解锁后自愈 |
| 截图是纯色 4~5KB | 锁屏/遮挡/最小化（事件14 定论，非渲染假死） | 详见 `run-environment-pitfalls.md` §4；解锁+wxrestore 后重截，仍异常停手问用户 |
| 点击落进用户其它窗口 | SetForegroundWindow 被前台锁拦截 | wxclick/wxpoke 已带前台守卫（拒点）；复现→停手 |
| 按钮模板全 UNKNOWN（dist 双高） | 按钮被遮挡/特效扫过/真实布局重排 | wxshot 人工核对；同比例尺寸下仍持续 UNKNOWN 才重裁模板（单纯尺寸变化已由换算吸收） |
| **OCR 任务区整区读空（raw=[]），页面内容目视正常** | **画布垂直居中漂移/区域边距过紧（事件21）** | 同图宽带扫描定位文字真实位置再重标区域；根治机制（CANVASTOP）见 coords.md 权威表述 |
| 脚本报 `ERR: client=… 长宽比/缩放系数不符` | 窗口被拉成非设计比例、过大过小或尺寸读取异常 | 跑 `wxresize.ps1` 复位（同比例任意尺寸均可，日常无需复位）；仍异常→停止问用户，不要改设计基准常量迁就窗口 |
| 点了没反应、光标不在预期位置 | delta 失效/窗口被移动 | 重新校准（读最新 origin） |
| 光标在按钮上没反应 | 热区偏移 | 下移 +30~50px 重试一次 |
| 首点无效之后正常 | 首点只激活窗口 | 先点标题栏聚焦 |
| 新量坐标点击全落空 | 显示图缩放陷阱 | 探针扫色块边界取真实坐标 |
| 探针全零但画面确有目标 | 用了缩放截图/扫描带不符 | PowerShell 物理截图；`-Debug` 重采样 |
| 窗口挪屏幕中间+跳重登 | 点了挂机弹窗「取消」 | 该弹窗必须点「确定」；重走登录流程 |
| `ERR: window not found` | 窗口被关/收回 | 重查 `Get-Process WeChatAppEx` 拿新 pid |
| 换模型/新会话首次执行自创方法踩坑 | 未读 references 档案 | 专家开局协议强制自检报告（事件18） |

## 12. 新增副本/任务的标准动作

1. 查 `coords.md`：有记录直接照跑；没有 → 截图定位入口，wxclick 连招进图，探针确认状态，坐标流程写入档案。
2. 用户原话的任务分配先写入 `tasks.md` 再执行。
3. 任务结束回报场次/体力/邀请函/金币；踩坑按性质入 `incidents.md`（事故类）或 `run-environment-pitfalls.md`（环境类）归档。

## 13. 维护与流水（详见 `管理新规.md`）

- 文档维护规则（文件分工/唯一入口/落笔原则/增长管理/机器校验/发版引用扫描/废弃清单）**唯一权威源 = `管理新规.md`**，本文件不重复；维护后跑 wxdoclint 校验。

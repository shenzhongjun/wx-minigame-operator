# Changelog — wx-minigame-operator

格式参考 Keep a Changelog，版本号遵循 SemVer（主版本.功能.修复）。
**发版流程定版**：改根目录文件 → 更新本文件（新增版本段落）→ `git commit` → `git tag -a vX.Y.Z -m "主题摘要"`。
快捷查看：`git tag -n`（列出版本+主题）｜`git log v1.0.0..v1.1.0 --oneline`（两版间提交）｜`git diff v1.0.0 v1.1.1 --stat`（两版间文件差异）。

## [1.1.7] - 2026-10-27

**主题：选角页宽区域判据 scr1w/scr2w + 前台守卫拉回重试 + 最小窗口 800 线 + 点击扰动体系删除**

### 新增（wxocr.ps1）
- `scr1w` 任务：卡1「角色名+职业」信息条整块 (36,130)-(215,204)，kw「早睡早起身体好」+ kw2「圣骑士」**合并任意3字命中**=HIT（用户定版：kw+kw2 一共任意 3 字命中就行，非 kw2 全字）。宽区域带上下文，解决 scr1 窄条在 S≈1.043 大窗下 OCR 读空问题。
- `scr2w` 任务：卡5同款 (36,234)-(215,290)，kw「豁达自在乐逍遥」+ kw2「重装机兵」合并任意3字=HIT；上界 234 避横幅污染区(206-232)、下界 290 收职业行(269-288)下。
- kw2 机制：第二关键字并入字符池（合并去重后计 minhit），kw 分支重写，旧单池逻辑清除。
- 验收（窗口 1187×748 S≈1.0431）：用户两张红框截图离线全过（jpg1=[早地早起身体好Lv.圣骑士]、jpg5=[豁达自在乐逍遥Lv.50装机兵]）；实机 scr2w=HIT、**scr1w=MISS（负样本判别正确）**、charsel=HIT。
- 标定件（冒烟测试目录，非包组件）：`calib-charsel-redbox-2026-10-27.ps1`（红框 design≈(46,139)-(208,209)）、`calib-charsel-redbox5-2026-10-27.ps1`（红框5 design≈(48,222)-(206,304)，上缘跨横幅区已规避）。

### 新增（_wxcommon.ps1 共享守卫）
- `Confirm-WxForeground`（用户定版）：检测到不在前台 → WARN 时间戳留痕 → 拉回前台（最小化先 SW_RESTORE）→ 首拉+最多 2 次重试 → 仍失败才由调用方 STOP。接线 wxclick / wxnav-tower / wxpoke 及冒烟件。定向测试件 `test-foreground-guard-2026-10-27.ps1` 实弹验证拉回+留痕路径（before=False → WARN 留痕 → 第 1 次拉回成功 → after=True）。
- `Test-WxMinClientW`（用户定版）：**客户区宽 <800 直接 STOP**（WARN 留痕）。依据实测：S≈0.609 (693×460) 时 town/charsel OCR 全读空（raw=[]），而 S≈0.598 与 S≈1.037 均正常——读空与窗口尺寸非单调，存在敏感区间，小窗判定不可靠故宁停不猜。接线 wxclick / wxnav-tower / wxpoke / wxocr 实时抓屏路径（**-Img 离线路径不受限**，标定诊断照常）及两冒烟件启动期检查。

### 删除（用户裁定：点击扰动体系全删）
- wxclick / wxnav-tower 的 ±J 点击偏移与随机 sleep 全部移除——点击一律精确设计坐标，「合成点击被吞」理论作废，落空=坐标/热区偏差。SKILL.md / coords.md / wxlogin 注释同步清理。

### 冒烟实测（脚本在 `游戏\冒烟测试\`，非包组件）
- `wxsmoke-charsel10.ps1`（随机 1-6 选卡，scr1w/scr2w 判屏）：大窗 1187×748 **10/10 PASS**；缩窗 681×453 (S≈0.598) **10/10 PASS**——宽判据对窗口尺寸稳健（wxocr 归一化设计坐标，scale 无关实测证实）。
- `wxsmoke-charswitch10.ps1`（整链：主城→点选角(196,179)→判屏切屏→双击选卡→开始游戏(1018,634)→town 复核，随机 -Count / 固定 -SeqList）：大窗 10/10 PASS；888×574 (S≈0.780) 固定序列 5-3-6-1-5-2 **6/6 PASS**。点选角带「点击→OCR→未中再点」3 次重试。
- 实证机制：**选角页进入时停在「上次选中角色所在屏」**，判屏+切屏逻辑已覆盖。
- PS 陷阱教训：布尔函数内裸字符串日志混入输出流被 `if(-not fn)` 捕获后，失败分支永不触发——函数日志一律 Write-Host（Switch-Screen / Enter-Charsel 已修）。


## [1.1.6] - 2026-10-27

**主题：挂机弹窗自动重登固化（用户 2026-10-27 裁决：OCR 判 POPUP_IDLE 自动点确定）**

### 变更（wxlogin.ps1）
- GOLD_DIALOG 分支改自动分流：先 wxpopup v2 OCR 分类——`POPUP_IDLE`（挂机「重新登录」）→ 自动点确定 (700,513) 继续登录链；其余类别（顶号「其他设备」/扩展券/正文读不出）红线不变：停机请示，绝不自动点。
- `-AssumeGold` 保留为人工强制放行开关（跳过分类直接点），语义从「目验后重跑」降级为兜底。
- 实机验收（2026-10-27 13:2x，窗口 1187×748 S≈1.043）：轮询 60s 内挂机弹窗出现（goldbtn=1046, OCR「重新登录」命中）→ wxlogin **未加 -AssumeGold** 自动分类 POPUP_IDLE → 点确定 → 整链一次通过（server→charsel OCR→双击卡1→town_ocr=HIT）。此前该处置链已人工带跑两轮零异常。
- 守卫回归：已在主城时 `wxlogin -Char 1` 正确 STOP（重登链不适用），未受改动影响。
- BOM ✓ Parser 0 错误 ✓。SKILL.md wxlogin 行为描述同步。

## [1.1.5] - 2026-10-27

**主题：页面身份判断全面 OCR 化（用户定版：OCR 能判的一律替代像素判定）**

### 新增（wxocr.ps1）
- `town` 任务：主城判据，区域 (158,162)-(250,200) kw「选角」零容差。三背景（酒馆/雪地/人流特效）HIT raw=[选角]，选角页×2/战斗页负样本 MISS（用户三图离线验证）。
- `server` 任务：登录页判据（唯一），(488,455)-(638,492)「巨龙山脉」白字深底，稳定 HIT raw=[巨龙山脉17]。「进入游戏」为风格化美术字 OCR 读不动（正确区域下仍误读），用户裁定放弃不做任务。

### 退役
- wxprobe `TOWN_PAGE`：主城像素签名对背景脆弱（三背景实测中下金带 snow/crowd=0，旧校准 193-206 系当时背景巧合）；主城身份=wxocr `town`。
- wxprobe `LOGIN_PAGE`：美术改版后 nLogin=389 卡阈值 400 边缘拉跨；登录页身份=wxocr `server`/`login`。两态退役后 wxprobe 在主城/登录页报 UNKNOWN（属预期），nLogin/LX0-LY1 计算与常量一并删除，回归清单两行期望值同步 UNKNOWN。
- wxpopup v1 正文像素模板：正文行位置浮动 ~16px 即 d=0.939 全灭（「长时间未操作，请重新登录」实战误报 UNKNOWN）；v2 改金确定钮守卫(≥400)+正文带 OCR (350,348)-(800,408) 关键字分类（其他设备=顶号停/未操作·重新登录=挂机可点确定/扩展券=只点取消/羽毛=复活可点确定/未知=红线停）。输出保持 POPUP= 前缀，wxgrind 兼容。

### 变更（wxlogin.ps1）
- 守卫链：LOGIN_PAGE/TOWN_PAGE 探针分支改 Test-LoginOcr/Test-TownOcr（OCR 权威）；终态追加 town_ocr=HIT/MISS。
- 实测：挂机重登弹窗→确定(700,513)→登录页→`wxlogin -Char 1` 整链一次通过（server HIT→进游戏→charsel OCR→双击卡1→town_ocr=HIT）。

### 实录（2026-10-27 上午）
- 选角环节冒烟 50/50 通过（脚本在包外 工作空间\冒烟测试\，用户裁定冒烟件不进包）。
- 挂机「长时间未操作」弹窗 wxpopup v1 误报 UNKNOWN→红线停手请示（行为正确）→OCR 化后正确分类 POPUP_IDLE。


## [1.1.4] - 2026-10-27

**主题：wxcanvas 诊断输出 chrome 感知修正（v1.1.2 重构的收尾，纯诊断层，无行为变更）**

### 修正（wxcanvas.ps1）
- 黑条/画布扫描从 chrome 底边起算（原从 y=0 起，白色 chrome 行被计入画布，`bar_top` 失真）。
- `canvas_aspect` 对照对象改为设计画布 1138/653（原错比 1138/708 全图）；`scale_h` 分母同步改 653。
- `centered_prediction` 由 v1.1.1 旧模型 `min(W/1138,H/708)` 升级为 v1.1.2 模型 `min(W/1138,(H-chrome)/653)`（预测行原本会误导诊断）。
- wxpreflight L24 坐标系说明同步 v1.1.2 模型措辞。
- 排查结论：全脚本库旧几何数学仅 wxcanvas 一处（已清零），其余脚本均引用 `_wxcommon` 的 `S`。

### 实测新知（842×547 选角页）
- 量出画布 842×475 vs 模型 842×483，差 8 行 = **letterbox 上下各 ~4px 居中 + 选角页画面上下边缘纯黑渐变被扫黑扫描计入**——两者叠加完全对账，几何模型被点击精度（卡 6 中心命中）再次反证成立。输出新增 hint 行防误读。

### 观察通道备忘（非本包问题）
- 会话中发现工具管道偶发在行尾追加 `X` 字符（括号包裹测试定位在进程流之外、同一代码两次运行位置不同、纯 echo 复现）——为执行沙箱控制台捕获伪影，wxcanvas 脚本本身从未输出 X。读取脚本输出时行尾孤立 `X` 应忽略。

## [1.1.3] - 2026-10-27

**主题：OCR 化改造——页面身份判定全面转 OCR 优先，金框像素子系统退役**

### 新增
- **`wxocr.ps1` 合并版通用 OCR 工具**：Windows 自带 zh-Hans 引擎（零第三方依赖），双模式——任务预设（`-Task autobtn|charsel|scr1|scr2`）与自由扫描（`-X0 -Y0 -X1 -Y1 [-F 倍率] [-NoInvert] [-Img 路径]`）。kw 类任务采用**「任意 minhit 字命中」匹配**（用户定版：名字不可能重复，漏字/错字/乱序全免疫）；autobtn 保持零容差关键字锁定。
- 屏号判别任务：`scr1`（第一屏，卡 1 名字区 40,140-210,175）✓ 3/3 实测；`scr2`（第二屏，卡 5 名字区 40,238-210,264）✓ 一次命中 7 字全对。公告横幅污染区（y≈206-232）已避开。

### 变更
- `wxautostate.ps1`：OCR 兜底由 wxocrbtn 子进程改为 `wxocr.ps1 -Task autobtn`（集成实测通过）。
- `wxprobe.ps1`：**金框检测子系统整体拆除**（CHARn 状态/6 条带/小窗放宽金）——0.476× 小窗下 1px 金描边抗锯齿混色全灭（strict=0/relax=192），且放宽阈值引发副本页 tab 门控误报。小窗下选角页身份由 PAGE=CHARSEL（侧栏白字签名，实测 526/511 稳定）+ wxocr charsel 任务承担；大窗金框逻辑亦不再作为流程门。
- `wxlogin.ps1` v2：登录链选卡验证由金框断言改为 **wxocr charsel 验证 + 双击幂等选卡**（幂等兜底）；角色卡坐标表更新。
- `coords.md`：选角页三屏结构定版——卡 3/4 重标 (704/987,340)（按卡 1→2 实测间距 283 等距外推）；第二屏 5-8 (138/421/704/987,370)；**7/8 锁槽红线：运行严禁点击**（未创建，点=建角色弹窗）；翻页坐标：切第二屏 (139,536)、回第一屏 (138,180)。

### 移除
- `wxocrbtn.ps1`（并入 wxocr.ps1）。

### 待实机（诚实标注）
- wxlogin v2 整链未跑过（组成件各自实测通过）；建议首跑人盯。
- 弹窗识别迁 OCR（顶号弹窗正文/按钮已实测逐字命中）——wxpopup 模板匹配退役，挂 todo。

### 实测记录（2026-10-26 晚-27 晨）
- 顶号弹窗 OCR 辨认：正文「账号在其他设备登录，重新登录？」+「取消/确定」逐字命中（S=0.69）。
- 角色卡点击实测：1-4 四击落点用户目验通过（重标后）；5→6 两屏切换+选中一次成功；卡 1 脚部条带 (138,180) 回第一屏一击双效（截图验证）。
- 建角色弹窗取消位 (471,502) 实测有效——双按钮弹窗（建角色/商城/顶号）面板几何共用的结论加强。

## [1.1.2] - 2026-10-26

**主题：几何层重构——微信内嵌标题栏模型，任意窗口尺寸（含缩小窗/非等比）全支持**

### 根因（v1.1.1 实测发现）
- 客户区顶部有**微信小游戏内嵌标题栏（白底「勇士之心」+胶囊按钮，固定 55px，不随窗口缩放）**，旧几何层把整个客户区当游戏画面：基准附近误差可忽略，窗口一小（如 650×431、574×387）标题栏占比暴涨致坐标整体偏移 + 长宽比断言拦停。
- 实测工具 `wxcanvas.ps1`（新增）：原始抓客户区→逐行/列扫纯黑带+白色标题栏带，输出画布矩形/四边黑条/chrome 高度。650×431 与 1967×1192 两尺寸实测 chrome 均=55、画布等比（宽高比 1.7520 vs 1.7516），模型坐实。

### 变更（_wxcommon.ps1）
- 新常量 `$WX_CHROME_H = 55`（固定值不搞运行时检测：单机定版后为 OS 固定值，检测有白底页面误判风险；wxcanvas.ps1 随时审计）。
- `Get-ClientGeometry`：`S=min(W/1138,(H-55)/653)`，纵向 `screen_y=OY+55+(design_y-55)*S`；**基准 1138×708 时 S=1 与旧模型完全重合，已验证坐标零失效**。删除长宽比断言（被标题栏模型取代），S 范围放宽 **0.75–2.0 → 0.40–2.0**。
- `Get-DesignBitmap`：只抓画布区，归一化 1138×653 贴回 1138×708、顶部 55 行填白（模拟标题栏）——所有区域常量/模板零改动。
- `Get-DesignRegion`/`ConvertTo-ScreenPoint`/`ConvertFrom-ScreenPoint` 同步画布映射。
- `wxpreflight.ps1` 新增 live 几何审计：窗口已开时自动跑 wxcanvas 实测 chrome 与常量比对，不符即禁止开工（防微信改版带病运行）。

### 实测验证（2026-10-26 18:0x-18:1x）
- 大窗 1967×1192（S=1.7285）：STATE=LOGIN_PAGE ✓（login=436，连带修复 1142×715 时 388<400 压线误判）
- 小窗 579×390（S=0.5088，旧模型必死尺寸）：STATE=LOGIN_PAGE ✓（login=412），与大窗判定一致
- 坐标体系裁决（用户问询）：**维持 1138×708 设计坐标语言不变**（653 仅几何层内部概念）——设计坐标+运行时换算即相对坐标体系；重标 653/重做百分比体系均否（零收益高错漏风险）。

## [1.1.1] - 2026-10-26

**主题：v1.1.0 代码审查清理 + 单机化重构（脚本去 -personal 后缀、删除公司机代码）**

### 移除
- **wxfarm.ps1（原 wxfarm-personal）删除（用户裁决）**：未迁移设计坐标体系（FindBtnY/DoClick/Ensure-Auto 三处裸屏幕数学，窗口≠1138×708 必错位），且扫描能力已被 wxgrind -AutoRetry 归一化版覆盖。「wxfarm 失灵悬案」随之作废。
- `_wxcommon.ps1` 删除 `Get-WxBtnState` 死代码（零调用者；判定逻辑实际由 wxprobe/wxautostate/wxclick 各自内联）+ 陈旧 `_wxcommon.ps1.bak`。
- **公司机代码与双机档案删除（用户 2026-10-26 令）**：公司版 `wxclick.ps1`/`wxfarm.ps1`、`references/coords-company.md`。双机支持废止，**仅支持当前这台电脑**（2560×1440 @125%）。

### 变更（重命名）
- **全部脚本去除 `-personal` 后缀**：`wxprobe-personal.ps1`→`wxprobe.ps1` 等 26 个；历史记录（incidents/update-log 等）中的 `*-personal` 即现同名无后缀脚本。
- `references/coords-personal.md` → `references/coords.md`；所有文档/脚本内引用同步。
- 脚本头注释与 SKILL.md「双机环境」章节改写为单机口径（「个人电脑版/公司电脑」叙述清除）。

### 文档
- tasks.md 存档本次审查任务与用户裁决；todo-scripts.md 新增「wxrecrop 未同步 wxocrbtn OCR 区」待办（挂账）；SKILL.md/dungeon-runs.md 同步 wxfarm 状态。

### 审查结论（2026-10-26）
- 主链 12 脚本（wxprobe/wxclick/wxgrind/wxpopup/wxstam/wxlogin/wxpoke/wxscroll/wxshot/wxautostate/wxrecrop/wxnav）设计坐标换算一致，无运行 bug；wxlogin 零命中=正常（坐标全走 wxclick/wxprobe 换算）。
- 重构后校验：27 个 .ps1 全部 Parser 0 错误 + UTF-8 BOM 保留。

## [1.1.0] - 2026-10-26

**主题：设计坐标体系（相对坐标）+ OCR 识别补充**

### 新增
- **设计坐标适配层（本版核心）**：`_wxcommon.ps1` 新增 `$WX_DESIGN_W/H=1138/708`、`Get-ClientGeometry`（S=min(W/1138,H/708)+居中留边，长宽比偏差>1.2% 停机，缩放范围 0.75–2.0）、`ConvertTo-ScreenPoint`/`ConvertFrom-ScreenPoint`、`Get-DesignBitmap`/`Get-DesignRegion`（NearestNeighbor 归一化，保留原始 RGB 供色彩阈值/白掩码）。**效果：换副本客户区 1138→1135/1139 漂移不再需要 wxresize/±2px 止血，文档与区域常量零改动**。已迁移 12 个脚本：wxprobe/wxclick/wxgrind/wxpopup/wxstam/wxnav/wxlogin/wxpoke/wxscroll/wxshot/wxautostate/wxrecrop。
- **`wxocrbtn-personal.ps1`（OCR 兜底）**：Windows 自带 OCR（zh-Hans，零新依赖）对自动战斗按钮二次识别——裁 (184,169)-(272,193) → 灰度反相 → 放大 8× → OCR → 关键字判定（含「取消自动」=ON / 含「自动战斗」=OFF）。`wxautostate` 在 Jaccard=UNKNOWN 且掩码≥60 时自动兜底（`-NoOcr` 关闭）。实测 4 张实拍 × 3 倍率无假阳性；单次 225ms，快于 Python 方案（641ms），判定"改 Python 无必要"。
- `wxshot` 锚定模式默认输出设计尺寸图（`-Raw` 保留实时尺寸）；`wxrecrop` 输入自动归一化、输出固定设计尺寸模板。

### 变更
- `wxresize` 降级为可选工具；尺寸断言从「精确 1138×708」改为「长宽比 + 缩放范围」。
- `plugin.json` version 1.0.0 → 1.1.0；agents/SKILL/references 同步（共 26 文件，+530/-217）。

### 验证状态
- 离线：6 张基线图 × 1135/1139/1252 三尺寸，wxprobe STATE 与 wxautostate BTN_STATE 全部一致；22/22 回归通过。
- ⚠️ 待实机：换副本转场/最大化还原的同比例换算冒烟；OCR 兜底 live 未测。

## [1.0.0] - 2026-10-25

**主题：初始版本——执行骨架 + 自动战斗判定体系**

- 专家包三件套：agents（开局协议/熔断/红线铁律）+ skills/wechat-minigame-automation + plugin.json。
- 自动战斗判定定版：唯一判据=按钮文字模板匹配（白掩码 Jaccard≤0.60），血量/tip 代码全删（历史事故定论）。
- 公共库 `_wxcommon.ps1` 单源化（窗口查找/尺寸断言/模板匹配），9 脚本重构 dot-source。
- 离线回归 `wxregress` + `_regress-manifest.csv`（19 图 22 断言）。
- 工具链：wxprobe 探针（STATE/CHAR/PAGE）、wxpopup 弹窗分类器（挂机/顶号/扩展券）、wxstam 体力二元读数、wxnav-tower 导航链、wxgrind 自动重试刷图、wxlogin 全自动选角、wxresize 尺寸复位、wxrecrop 模板重裁一条龙。
- 1138×708 模板体系 + 事件19（尺寸漂移致模板全盲）根治，旧模板备份 .bak-*。

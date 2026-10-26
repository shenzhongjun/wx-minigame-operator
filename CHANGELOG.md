# Changelog — wx-minigame-operator

格式参考 Keep a Changelog，版本号遵循 SemVer（主版本.功能.修复）。
**发版流程定版**：改根目录文件 → 更新本文件（新增版本段落）→ `git commit` → `git tag -a vX.Y.Z -m "主题摘要"`。
快捷查看：`git tag -n`（列出版本+主题）｜`git log v1.0.0..v1.1.0 --oneline`（两版间提交）｜`git diff v1.0.0 v1.1.0 --stat`（两版间文件差异）。

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

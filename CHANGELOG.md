# Changelog — wx-minigame-operator

格式参考 Keep a Changelog，版本号遵循 SemVer（主版本.功能.修复）。
**发版流程定版**：改根目录文件 → 更新本文件（新增版本段落）→ `git commit` → `git tag -a vX.Y.Z -m "主题摘要"`。
快捷查看：`git tag -n`（列出版本+主题）｜`git log v1.0.0..v1.1.0 --oneline`（两版间提交）｜`git diff v1.0.0 v1.1.0 --stat`（两版间文件差异）。

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

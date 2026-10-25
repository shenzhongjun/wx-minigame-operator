# wx-minigame-operator 专家包

勇士之心（微信小游戏）桌面自动化**操作员专家**——单角色专家 + 内置技能的一体化包（expertType: agent），格式与 `experts/` 市场里的 gongyi-expert 完全一致：**agent + 自带 skill 装在一起，随包装卸、随包移植，只维护这一个目录。**

## 包结构

```
.codebuddy-plugin/plugin.json        注册声明（agents + skills 数组，仿 gongyi-expert）
agents/wx-minigame-operator.md       角色纪律（常驻）
skills/wechat-minigame-automation/   内置作业手册（按需读）
  ├ SKILL.md                         操作手册正文（精简版，≤200 行）
  ├ 管理新规.md                       skill 知识管理规则
  ├ references/                      tasks/coords/incidents/game-mechanics/update-log/todo-scripts
  ├ scripts/                         16 个自动化脚本 + preflight（$PSScriptRoot 相对定位，可移植）
  └ assets/                          模板判定图
```

## 职责切分（agent vs 内置 skill）

| 内容 | 位置 | 理由 |
|---|---|---|
| 开局协议、致命五坑、熔断纪律、冒烟测试制、协作红线、任务收尾 | **agents/*.md** | 角色纪律，常驻该角色 |
| 机制、脚本清单、坐标体系、状态判定、停止条件、排错 | **内置 skill** SKILL.md | 操作知识，按需读，开局协议强制读 |
| 任务/坐标/事件/数值/踩坑档案 | **内置 skill** references/ | 领域知识，单一事实源 |

## 安装

1. 打开 WorkBuddy 插件/专家管理面板 → **添加本地插件目录** → 指向本文件夹；
2. 专家列表出现「勇士之心自动化操作员」即装好，直接对话即用（内置快捷指令：每日标准循环 / 全角色状态体检 / 异常体检）。

## 从旧位置迁移（一次性，装好即做）

本包把原 `~\.workbuddy\skills\wechat-minigame-automation\` **整体收编为内置技能**（含全部档案与脚本，2026-10-24 快照）。安装并验证后：

1. 新开会话说"按每日标准循环执行今天的任务"，确认专家走开局协议（跑 preflight + 输出《开局自检报告》后才动手）；
2. **删除旧目录** `~\.workbuddy\skills\wechat-minigame-automation\`——此后手册只在本包内维护，无双源；
3. 旧目录里的 `SKILL.md`（旧版）、`SKILL-修改版-2026-10-24.md` 为历史存档，删除前如需留存自行拷走。

## 维护约定

- 角色纪律条款（红线/熔断/开局协议）：改 `agents/wx-minigame-operator.md`，**须用户确认**；
- 操作知识：改本包内 `skills/wechat-minigame-automation/`，照常走 update-log 三态路由与管理新规；
- 本包即唯一目录：备份/搬移/分享 = 拷走整个文件夹；
- agent 与手册冲突：停下问用户，禁止自行取舍（已写入 agent 文件）。

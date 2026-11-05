---
name: tmux-claude-coord
description: >-
  一行命令搭建本地多 Claude Code 会话工作区：创建 tmux 工作区、命名启动 coord 大总管， 生成只协调不执行的运行规约，以及
  Top4+Top3 看板、待定清单、派活与交接文件；不自动铺 worker、不自动巡检。 Triggers：大总管、多会话工作区、协调多个 Claude
  Code 会话、搭建 tmux 工作区、tmux-claude-coord。
argument-hint: '[项目目录，默认当前目录] [工作区名，默认 aiw]'
disable-model-invocation: true
user-invocable: true
metadata:
  author: qrq
  title: 大总管工作区
  description_zh: 一键创建 tmux 工作区与 coord 大总管，并落好派活、交接、看板和就绪验证。
  version: 1.0.1
  license: MIT
---

# tmux-claude-coord · 只面对一个入口

> tmux 管驻留，coord 管协调，文件管交接。**会话是可替换的执行者，不是状态的真相源。**

这个技能只做两件事：把 `coord` 真正起起来；给它一套能持续使用的工作合同。它不是另一个 Super-agent 平台。

## 什么时候用

- 在当前项目建立一个只与用户对话的「大总管」。
- 把多个 Claude Code 会话收进一个 tmux 工作区。
- 为派活、交接、待决策和重资源互斥立下最小规约。

**不要用于：**一次性小任务（直接做或用 subagent）、无人值守自动运维、自动合并/发布、跨机器事件总线。

## 用法

```bash
/tmux-claude-coord
/tmux-claude-coord /absolute/path/to/project
/tmux-claude-coord /absolute/path/to/project aiw-minicpm
```

省略项目目录时使用当前目录；省略工作区名时使用 `aiw`。工作区名只接受小写字母、数字和连字符，必须以字母或数字开头，最长 32 字符。

默认只建 `coord`，不建 worker；状态写入项目的 `.aiw/` 并加入 `.gitignore`。已有文件不覆盖，已有会话不顶替。

## 执行流程

### 1. 预检

确认命令运行在安装 Claude Code 与 tmux 的宿主机上，并检查：

- `tmux`、`claude` 可用；缺依赖就停止，不擅自安装。
- 项目目录存在，并转为物理绝对路径。
- 若工作区或 `coord` 窗口已存在，核对归属；归属不明就停止，绝不 kill 或重用陌生窗口。

Ghostty 是推荐终端，不是硬依赖。技能不修改权限、信任或危险模式设置。

### 2. 初始化并启动 coord

将两个参数分别安全引用后运行，不得把用户输入拼成未引用的 shell 字符串：

```bash
bash "$HOME/.claude/skills/tmux-claude-coord/scripts/init.sh" "$PWD" "aiw"
```

脚本会从 `templates/` 实际读取并渲染模板，不凭记忆重写。它会：

1. 生成 `.aiw/` 的工作合同、看板、待定清单、派活模板和 `coord` 交接页。
2. 以 detached 方式创建 `<工作区>:coord`，不 attach、不 select-window、不抢焦点。
3. 用 `claude --name <工作区>-coord --append-system-prompt ... "<开场提示>"` 启动，避免粘贴竞态。
4. 要求 `coord` 在交接页写回本次唯一 ready 标记。

### 3. 验证，不替它宣布成功

脚本会验证 session、window、cwd、Claude 启动命令与存活状态，以及 ready 标记和状态行。新建 coord 必须完成本次唯一 nonce 握手；复用时只声称既有 ready 标记仍然有效，不冒充当前会话重新握手。只有全部通过才报告「大总管已就位」。

- **超时或失败：**保留现场，报告失败阶段；用 `tmux capture-pane -p -t <工作区>:coord` 看信任、登录或权限提示。不要重复启动第二个 coord，不要自动清理。**运行期同样适用**：coord 长时间无回报时，先 capture-pane 查是否卡在交互弹窗（无人值守窗格里弹窗 = 无人应答的死锁）。
- **重跑：**已存在且健康的 coord 直接复用；已有交接与看板不覆盖。
- **交付入口：**成功后只给用户 attach 命令和一句下一步。需要用户亲手运行时，建议输入 `! tmux attach -t <工作区>`，或在终端运行同一命令。

**验证边界：**当前已通过 Bash 语法检查和隔离 tmux 假进程测试；真实 Claude 的启动/握手、实际 worktree 创建及原生跨会话传话仍待首次正式调用做端到端验收，不把替身测试当成这些能力已验证。

第一句工作指令可以是：

> 先只派一个只读 worker，读一个我指定的小问题并写回报告；你独立核验后再汇总。

## coord 后续怎么派 worker

用户之后的任务只交给 coord。coord 必须遵守 `.aiw/coord.md`，先写完整 brief，再调用：

```bash
bash "$HOME/.claude/skills/tmux-claude-coord/scripts/spawn.sh" \
  --project "/absolute/path/to/project" \
  --session "aiw" \
  --worker "issue-123" \
  --brief "/absolute/path/to/project/.aiw/briefs/issue-123.md"
```

并行写代码时加 `--worktree`；用户明确给定执行模型时才加 `--model "<已确认模型>"`。不得自行替换模型或评审链。

worker 同样要完成 ready 握手。`SendMessage` 成功不等于对方已读；关键状态必须同时落在 handoff 或报告中。

## 入口会话怎么等回报

「发出指令后被动等回报」不够——coord 卡死在弹窗里时不会回报，也不会触发 idle（turn 挂起不算空闲）。等回报期间：

1. 向 coord 挂一次性 idle 订阅（`SendMessage` 带 `notify_when_idle: true`），收到通知做一次核查，需要继续等就再挂一次。
2. 核查动作各做一次、不轮询：`ListAgents` 看 coord 状态 + `tmux capture-pane -p -t <工作区>:coord` 看是否卡弹窗。
3. 速查判据：`waiting` ≈ 弹窗在等键盘；`idle` 但 handoff 无更新 ≈ 消息未消化或异常退出。

这是死锁探测，不是巡检——本技能不装定时器，探测由入口会话在等待期间顺手做。

## 硬边界

- **coord 不亲自实现、修 bug 或代 worker 修复评审意见。**它只拆解、派活、独立验收、协调评审与记录。
- 默认最多两个活跃 worker；有依赖或写入交集就串行，并行写代码必须隔离 worktree。
- 不装定时器或守护进程做自动巡检（入口会话等回报时的 idle 订阅与核查见上节）；不自动 PR 合并、push、部署或对外发消息；授权只作用于用户明确批准的那一次。
- 不用 `--dangerously-skip-permissions`，不替用户接受信任弹窗。
- 失败保留现场；清理既有 session、window、worktree 或状态文件必须另行获得用户同意。
- 本技能不管事件过滤、Thread 订阅、Watchdog、云端持久化；需要这些时应另做系统，而不是往初始化脚本里塞。

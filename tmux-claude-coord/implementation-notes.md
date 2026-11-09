# implementation-notes · tmux-claude-coord 批次 1（2026-11-09）

范围：报告项 1-4 + bash 5.2 `&` 渲染修复。

## Deviations

1. **接班旧窗口只保留、不改名**（原报告提过 rename）。保留原名可减少对正在排查现场的干扰；窗口清理由用户点名。
2. **coord.md 的本地改写不自动合并进新模板**。`upgrade.sh --apply` 只写 `coord.md.new`；`succeed.sh` 握手成功后替换并备份旧文件为 `coord.md.gen<N>.prev`。私有条款应迁到 `coord.local.md`（永不覆盖）。自动三方合并合同文本风险大于收益。
3. **`init.sh` 也支持 `--timeout`**（默认 90），不只 spawn；新建 coord 与 worker 共用同一等待逻辑。
4. **新增 UTF-8 locale 前置检查**：bash 3.2 的 `printf %q` 在 C locale 会把中文转义成字节串，曾使 coord.md 命令从约 6KB 膨胀到约 20KB，超过 tmux 约 16KB 命令上限。非 UTF-8 直接拒绝并提示，不静默发坏命令。
5. **复用不再要求 handoff 为 ready**：只看窗口存活 + `exec claude` + cwd + workspace.md 身份；handoff 状态打印为参考。死窗格检查移到 cwd 之前（死窗格可能读不到 cwd）。
6. **`--recheck` 接受任意非 none 的 AIW_READY、非 booting 状态**：补验时拿不到上次 nonce，且 worker 可能已从 working 进入 ready/waiting；仍核对该 worker 自己的窗口与 handoff。
7. **新增 `scripts/lib.sh` 与 `tests/run.sh`**：消除四个脚本的渲染/tmux/握手重复逻辑；测试用私有 socket + 假 claude，失败用例保留沙盒现场。
8. 仓库基线先补同步了已安装副本独有的「信任链」条款（提交 `58f5d2d`），否则新渲染会丢条款。

## 验证记录

- 旧版快照 `/tmp/aiw-old-skill`：7 通过 / 13 失败（复现 &、前缀误匹配、复用误判、无 --timeout/--recheck、无 succeed/upgrade、死窗格提示顺序）。
- 新版：37 通过 / 0 失败，bash 5.2.37 与 /bin/bash 3.2.57 各跑一遍。
- 真实 `.aiw` 的 /tmp 副本 upgrade diff-only：g4a worker.md 恰好补 8 行无人值守；afm/rejev worker.md 无差异；coord.md 差异只落 `.new` 语义，不改原文件。

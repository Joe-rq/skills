#!/usr/bin/env bash
# tmux-claude-coord · coord 派活后启动一个命名 worker；不覆盖旧 handoff，不切换焦点。
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
用法：spawn.sh --project DIR --session NAME --worker NAME --brief FILE [--worktree] [--model MODEL]
EOF
  exit 2
}

fail() {
  printf 'tmux-claude-coord worker: %s\n' "$1" >&2
  exit 1
}

safe_name() {
  case "$1" in ''|*[!a-z0-9-]*|-*) return 1 ;; esac
  [ "${#1}" -le 32 ]
}

PROJECT_INPUT=''
SESSION=''
WORKER=''
BRIEF_INPUT=''
MODEL=''
USE_WORKTREE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || usage; PROJECT_INPUT="$2"; shift 2 ;;
    --session) [ "$#" -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
    --worker) [ "$#" -ge 2 ] || usage; WORKER="$2"; shift 2 ;;
    --brief) [ "$#" -ge 2 ] || usage; BRIEF_INPUT="$2"; shift 2 ;;
    --model) [ "$#" -ge 2 ] || usage; MODEL="$2"; shift 2 ;;
    --worktree) USE_WORKTREE=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$PROJECT_INPUT" ] && [ -n "$SESSION" ] && [ -n "$WORKER" ] && [ -n "$BRIEF_INPUT" ] || usage
safe_name "$SESSION" || fail '工作区名不合法。'
safe_name "$WORKER" || fail 'worker 名只能含小写字母、数字和连字符，须以字母或数字开头，最长 32 字符。'
case "$PROJECT_INPUT$BRIEF_INPUT$MODEL" in *$'\n'*|*$'\r'*) fail '路径与模型名不能含换行。' ;; esac
for cmd in tmux claude; do command -v "$cmd" >/dev/null 2>&1 || fail "缺少依赖：$cmd。"; done

PROJECT="$(cd "$PROJECT_INPUT" 2>/dev/null && pwd -P)" || fail "项目目录不存在：$PROJECT_INPUT"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE="$PROJECT/.aiw"
COORD_NAME="$SESSION-coord"
WORKER_NAME="$SESSION-$WORKER"
HANDOFF="$STATE/handoffs/$WORKER.md"
[ -f "$STATE/worker.md" ] || fail "工作区尚未初始化：$STATE/worker.md 不存在。"
grep -Fqx -- "- 项目根目录：$PROJECT" "$STATE/workspace.md" 2>/dev/null || fail 'workspace.md 与项目不匹配。'
grep -Fqx -- "- tmux 工作区：$SESSION" "$STATE/workspace.md" 2>/dev/null || fail 'workspace.md 与工作区不匹配。'
tmux has-session -t "$SESSION" 2>/dev/null || fail "tmux 工作区不存在：$SESSION。"
tmux list-windows -t "$SESSION" -F '#W' | grep -Fxq 'coord' || fail "coord 窗口不存在：$SESSION:coord。"
if tmux list-windows -t "$SESSION" -F '#W' | grep -Fxq "$WORKER"; then
  fail "worker 窗口已存在：${SESSION}:${WORKER}；不重复启动。"
fi
[ ! -e "$HANDOFF" ] || fail "handoff 已存在：${HANDOFF}；换一个新 worker 名，保留历史交接。"
[ -f "$SKILL_DIR/templates/handoff.md" ] || fail 'worker handoff 模板缺失。'

case "$BRIEF_INPUT" in
  /*) BRIEF_PATH="$BRIEF_INPUT" ;;
  *) BRIEF_PATH="$PROJECT/$BRIEF_INPUT" ;;
esac
[ -f "$BRIEF_PATH" ] || fail "brief 不存在：$BRIEF_PATH"
BRIEF_DIR="$(cd "$(dirname "$BRIEF_PATH")" && pwd -P)"
BRIEF="$BRIEF_DIR/$(basename "$BRIEF_PATH")"
[ "$BRIEF_DIR" = "$STATE/briefs" ] || fail "brief 必须放在 $STATE/briefs/，避免任务来源不清。"

c="$(cat "$SKILL_DIR/templates/handoff.md")"
c="${c//\{\{WORKER\}\}/$WORKER}"
c="${c//\{\{BRIEF\}\}/$BRIEF}"
printf '%s\n' "$c" > "$HANDOFF"
printf '  建 %s\n' "$HANDOFF"

NONCE="$(date +%Y%m%d%H%M%S)-$$"
BOOT="你是 ${COORD_NAME} 的 worker ${WORKER}。先读 ${STATE}/worker.md、${BRIEF} 和 ${HANDOFF}，并完整遵守 brief。保留 handoff 既有内容，把 AIW_READY 改为 ${NONCE}、AIW_STATUS 改为 working；向 ${COORD_NAME} 报到后再开始任务。不要直接联系用户。"
SYSTEM_PROMPT="$(cat "$STATE/worker.md")"
printf -v CLAUDE_CMD 'exec claude --name %q --append-system-prompt %q' "$WORKER_NAME" "$SYSTEM_PROMPT"
if [ "$USE_WORKTREE" = '1' ]; then
  printf -v EXTRA ' --worktree %q --add-dir %q' "$WORKER" "$PROJECT"
  CLAUDE_CMD="$CLAUDE_CMD$EXTRA"
fi
if [ -n "$MODEL" ]; then
  printf -v EXTRA ' --model %q' "$MODEL"
  CLAUDE_CMD="$CLAUDE_CMD$EXTRA"
fi
printf -v EXTRA ' %q' "$BOOT"
CLAUDE_CMD="$CLAUDE_CMD$EXTRA"

show_pane() {
  printf '%s\n' "--- $WORKER 窗格末尾（仅用于诊断） ---" >&2
  tmux capture-pane -p -t "$SESSION:$WORKER" 2>/dev/null | tail -n 30 >&2 || true
  printf '%s\n' '--- 保留现场，不自动清理 ---' >&2
}

printf '▸ 启动 %s:%s（detached，不切换焦点）\n' "$SESSION" "$WORKER"
tmux new-window -d -t "$SESSION" -n "$WORKER" -c "$PROJECT" "$CLAUDE_CMD"
if ! tmux set-window-option -t "$SESSION:$WORKER" remain-on-exit on >/dev/null; then
  show_pane
  fail 'worker 窗口在启动后立即消失；未能保留现场。'
fi

attempts=30
while [ "$attempts" -gt 0 ]; do
  if [ "$(tmux display-message -p -t "$SESSION:$WORKER" '#{pane_dead}' 2>/dev/null || printf '1')" != '0' ]; then
    show_pane
    fail 'worker 进程已退出；未就绪。'
  fi
  if grep -Fqx "AIW_READY: $NONCE" "$HANDOFF" 2>/dev/null &&
    grep -Fqx 'AIW_STATUS: working' "$HANDOFF" 2>/dev/null; then
    break
  fi
  attempts=$((attempts - 1))
  [ "$attempts" -eq 0 ] || sleep 1
done
if [ "$attempts" -eq 0 ]; then
  show_pane
  fail 'worker 未在 30 秒内完成 ready 握手；窗口与 handoff 已保留。'
fi

WORKER_START="$(tmux display-message -p -t "$SESSION:$WORKER" '#{pane_start_command}')"
WORKER_START="${WORKER_START#\"}"
WORKER_START="${WORKER_START%\"}"
case "$WORKER_START" in
  exec\ claude\ *) ;;
  *) show_pane; fail "验证失败：worker 窗格启动命令不是 exec claude。" ;;
esac

cat <<EOF

━━ worker 已就位 ━━
  tmux：$SESSION:$WORKER
  会话名：$WORKER_NAME
  brief：$BRIEF
  handoff：$HANDOFF
  worktree：$([ "$USE_WORKTREE" = '1' ] && printf '启用' || printf '未启用')
  验证：window + Claude 启动命令与存活 + 本次 ready 握手均通过

coord 现在可以更新 board.md，并等待 worker 的实际任务报告。
EOF

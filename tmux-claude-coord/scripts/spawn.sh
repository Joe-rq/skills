#!/usr/bin/env bash
# tmux-claude-coord · coord 派活后启动一个命名 worker；不覆盖旧 handoff，不切换焦点。
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
用法：spawn.sh --project DIR --session NAME --worker NAME --brief FILE [--worktree] [--model MODEL]
               [--timeout 秒，默认 90] [--recheck]
  --recheck：不新建窗口、不覆盖 handoff，只补验既有 worker 的握手（用于上次超时后）。
EOF
  exit 2
}

fail() {
  printf 'tmux-claude-coord worker: %s\n' "$1" >&2
  exit 1
}

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=lib.sh
. "$SKILL_DIR/scripts/lib.sh"

PROJECT_INPUT=''
SESSION=''
WORKER=''
BRIEF_INPUT=''
MODEL=''
USE_WORKTREE=0
TIMEOUT=90
RECHECK=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || usage; PROJECT_INPUT="$2"; shift 2 ;;
    --session) [ "$#" -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
    --worker) [ "$#" -ge 2 ] || usage; WORKER="$2"; shift 2 ;;
    --brief) [ "$#" -ge 2 ] || usage; BRIEF_INPUT="$2"; shift 2 ;;
    --model) [ "$#" -ge 2 ] || usage; MODEL="$2"; shift 2 ;;
    --timeout)
      [ "$#" -ge 2 ] || usage
      case "$2" in ''|*[!0-9]*) fail '--timeout 必须是正整数秒。' ;; esac
      [ "$2" -gt 0 ] || fail '--timeout 必须是正整数秒。'
      TIMEOUT="$2"; shift 2 ;;
    --recheck) RECHECK=1; shift ;;
    --worktree) USE_WORKTREE=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$PROJECT_INPUT" ] && [ -n "$SESSION" ] && [ -n "$WORKER" ] && [ -n "$BRIEF_INPUT" ] || usage
aiw_safe_name "$SESSION" || fail '工作区名不合法。'
aiw_safe_name "$WORKER" || fail 'worker 名只能含小写字母、数字和连字符，须以字母或数字开头，最长 32 字符。'
case "$PROJECT_INPUT$BRIEF_INPUT$MODEL" in *$'\n'*|*$'\r'*) fail '路径与模型名不能含换行。' ;; esac
for cmd in tmux claude; do command -v "$cmd" >/dev/null 2>&1 || fail "缺少依赖：$cmd。"; done
aiw_require_utf8

PROJECT="$(cd "$PROJECT_INPUT" 2>/dev/null && pwd -P)" || fail "项目目录不存在：$PROJECT_INPUT"
STATE="$PROJECT/.aiw"
WORKER_NAME="$SESSION-$WORKER"
HANDOFF="$STATE/handoffs/$WORKER.md"
DATE="$(date +%Y-%m-%d)"
[ -f "$STATE/worker.md" ] || fail "工作区尚未初始化：$STATE/worker.md 不存在。"
grep -Fqx -- "- 项目根目录：$PROJECT" "$STATE/workspace.md" 2>/dev/null || fail 'workspace.md 与项目不匹配。'
grep -Fqx -- "- tmux 工作区：$SESSION" "$STATE/workspace.md" 2>/dev/null || fail 'workspace.md 与工作区不匹配。'
# 当前 coord 从 workspace.md 指针解析，不再要求窗口必须叫 coord。
aiw_load_coord_identity "$STATE/workspace.md"
tmux has-session -t "=$SESSION" 2>/dev/null || fail "tmux 工作区不存在：$SESSION。"
COORD_ID="$(aiw_window_id "$SESSION" "$COORD_WINDOW")"
[ -n "$COORD_ID" ] || fail "当前 coord 窗口不存在：${SESSION}:${COORD_WINDOW}；若已换班，请先更新 workspace.md 指针。"
WORKER_ID="$(aiw_window_id "$SESSION" "$WORKER")"
if [ "$RECHECK" = '0' ]; then
  [ -z "$WORKER_ID" ] || fail "worker 窗口已存在：${SESSION}:${WORKER}；不重复启动。若只是要补验握手，用 --recheck。"
  [ ! -e "$HANDOFF" ] || fail "handoff 已存在：${HANDOFF}；换一个新 worker 名，保留历史交接。"
else
  [ -n "$WORKER_ID" ] || fail "--recheck 需要既有 worker 窗口：${SESSION}:${WORKER} 不存在。"
  [ -f "$HANDOFF" ] || fail "--recheck 需要既有 handoff：${HANDOFF} 不存在。"
fi
[ -f "$SKILL_DIR/templates/handoff.md" ] || fail 'worker handoff 模板缺失。'

case "$BRIEF_INPUT" in
  /*) BRIEF_PATH="$BRIEF_INPUT" ;;
  *) BRIEF_PATH="$PROJECT/$BRIEF_INPUT" ;;
esac
[ -f "$BRIEF_PATH" ] || fail "brief 不存在：$BRIEF_PATH"
BRIEF_DIR="$(cd "$(dirname "$BRIEF_PATH")" && pwd -P)"
BRIEF="$BRIEF_DIR/$(basename "$BRIEF_PATH")"
[ "$BRIEF_DIR" = "$STATE/briefs" ] || fail "brief 必须放在 $STATE/briefs/，避免任务来源不清。"

if [ "$RECHECK" = '1' ]; then
  printf '▸ 补验 %s:%s（不新建窗口、不覆盖 handoff）\n' "$SESSION" "$WORKER"
else
  aiw_render_file "$SKILL_DIR/templates/handoff.md" "$HANDOFF"
  printf '  建 %s\n' "$HANDOFF"

  NONCE="$(date +%Y%m%d%H%M%S)-$$"
  BOOT="你是 ${COORD_NAME} 的 worker ${WORKER}。先读 ${STATE}/worker.md、${BRIEF} 和 ${HANDOFF}，并完整遵守 brief。保留 handoff 既有内容，把 AIW_READY 改为 ${NONCE}、AIW_STATUS 改为 working；向 ${COORD_NAME} 报到后再开始任务。不要直接联系用户。"
  aiw_load_prompt "$STATE/worker.md" "$STATE/worker.local.md"
  printf -v CLAUDE_CMD 'exec claude --name %q --append-system-prompt %q' "$WORKER_NAME" "$AIW_PROMPT"
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

  printf '▸ 启动 %s:%s（detached，不切换焦点）\n' "$SESSION" "$WORKER"
  WORKER_ID="$(tmux new-window -d -P -F '#{window_id}' -t "=$SESSION" -n "$WORKER" -c "$PROJECT" "$CLAUDE_CMD")"
  if ! tmux set-window-option -t "$WORKER_ID" remain-on-exit on >/dev/null; then
    aiw_show_pane "$WORKER_ID" "$WORKER"
    fail 'worker 窗口在启动后立即消失；未能保留现场。'
  fi
fi

# 补验时不知道上次 nonce，接受任意已写回的握手标记，且状态可以已离开 working。
wait_rc=0
if [ "$RECHECK" = '1' ]; then
  aiw_wait_ready "$WORKER_ID" "$HANDOFF" any any "$TIMEOUT" || wait_rc=$?
else
  aiw_wait_ready "$WORKER_ID" "$HANDOFF" "$NONCE" working "$TIMEOUT" || wait_rc=$?
fi
if [ "$wait_rc" = '2' ]; then
  aiw_show_pane "$WORKER_ID" "$WORKER"
  fail 'worker 进程已退出；未就绪。'
elif [ "$wait_rc" != '0' ]; then
  aiw_show_pane "$WORKER_ID" "$WORKER"
  fail "worker 未在 ${TIMEOUT} 秒内完成 ready 握手；窗口与 handoff 已保留。稍后可用同一命令加 --recheck 补验，不要重复 spawn。"
fi

case "$(aiw_start_command "$WORKER_ID")" in
  exec\ claude\ *) ;;
  *) aiw_show_pane "$WORKER_ID" "$WORKER"; fail "验证失败：worker 窗格启动命令不是 exec claude。" ;;
esac

cat <<EOF

━━ worker 已就位 ━━
  tmux：$SESSION:$WORKER
  会话名：$WORKER_NAME
  brief：$BRIEF
  handoff：$HANDOFF
  worktree：$([ "$USE_WORKTREE" = '1' ] && printf '启用' || printf '未启用')
  验证：window + Claude 启动命令与存活 + ready 握手（$([ "$RECHECK" = '1' ] && printf '补验' || printf '本次 nonce')）

coord 现在可以更新 board.md，并等待 worker 的实际任务报告。
EOF

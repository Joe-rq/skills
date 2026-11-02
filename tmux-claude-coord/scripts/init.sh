#!/usr/bin/env bash
# tmux-claude-coord · 初始化 tmux 工作区与 coord，只增不删，不切换用户焦点。
set -euo pipefail

usage() {
  printf '用法：init.sh [项目目录=当前目录] [工作区名=aiw]\n' >&2
  exit 2
}

fail() {
  printf 'tmux-claude-coord: %s\n' "$1" >&2
  exit 1
}

safe_name() {
  case "$1" in
    ''|*[!a-z0-9-]*) return 1 ;;
  esac
  case "$1" in
    -*) return 1 ;;
  esac
  [ "${#1}" -le 32 ]
}

[ "$#" -le 2 ] || usage
PROJECT_INPUT="${1:-$PWD}"
SESSION="${2:-aiw}"
safe_name "$SESSION" || fail '工作区名只能含小写字母、数字和连字符，须以字母或数字开头，最长 32 字符。'
case "$PROJECT_INPUT" in *$'\n'*|*$'\r'*) fail '项目路径不能含换行。' ;; esac
for cmd in tmux claude; do
  command -v "$cmd" >/dev/null 2>&1 || fail "缺少依赖：$cmd。未做任何修改，请先安装。"
done
PROJECT="$(cd "$PROJECT_INPUT" 2>/dev/null && pwd -P)" || fail "项目目录不存在：$PROJECT_INPUT"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE="$PROJECT/.aiw"
META="$STATE/workspace.md"
HANDOFF="$STATE/handoffs/coord.md"
COORD_NAME="$SESSION-coord"
DATE="$(date +%Y-%m-%d)"

for tpl in coord worker workspace board pending brief handoff; do
  [ -f "$SKILL_DIR/templates/$tpl.md" ] || fail "技能模板缺失：$SKILL_DIR/templates/$tpl.md"
done
[ ! -e "$STATE" ] || [ -d "$STATE" ] || fail ".aiw 已存在但不是目录：$STATE"

metadata_matches() {
  [ -f "$META" ] || return 1
  grep -Fqx -- "- 项目根目录：$PROJECT" "$META" &&
    grep -Fqx -- "- tmux 工作区：$SESSION" "$META" &&
    grep -Fqx -- "- coord 会话名：$COORD_NAME" "$META"
}

# 在任何写入之前排除同名但属于其他项目的工作区。
SESSION_EXISTED=0
COORD_EXISTED=0
if tmux has-session -t "$SESSION" 2>/dev/null; then
  SESSION_EXISTED=1
  if tmux list-windows -t "$SESSION" -F '#W' 2>/dev/null | grep -Fxq 'coord'; then
    COORD_EXISTED=1
    COORD_CWD="$(tmux display-message -p -t "$SESSION:coord" '#{pane_current_path}')"
    [ "$COORD_CWD" = "$PROJECT" ] || fail "${SESSION}:coord 属于 ${COORD_CWD}，不是 ${PROJECT}；未做任何修改，请换工作区名。"
    metadata_matches || fail '现有 coord 缺少匹配的 .aiw/workspace.md，不能静默接管；未做任何修改。'
    [ "$(tmux display-message -p -t "$SESSION:coord" '#{pane_dead}')" = '0' ] || fail "$SESSION:coord 已是死窗格；保留现场，请 attach 检查。"
    COORD_START="$(tmux display-message -p -t "$SESSION:coord" '#{pane_start_command}')"
    COORD_START="${COORD_START#\"}"
    COORD_START="${COORD_START%\"}"
    case "$COORD_START" in
      exec\ claude\ *) ;;
      *) fail "$SESSION:coord 不是由 exec claude 启动的窗格，不能静默顶替；未做任何修改。" ;;
    esac
  elif [ -e "$META" ]; then
    metadata_matches || fail "$SESSION 已存在且 .aiw 身份不匹配；未做任何修改。"
  else
    fail "tmux 工作区 $SESSION 已存在但没有可核对身份的 coord；未做任何修改，请换工作区名。"
  fi
elif [ -e "$META" ]; then
  metadata_matches || fail '.aiw/workspace.md 属于另一个项目或工作区；未做任何修改。'
fi

render() {
  local tpl="$1" dest="$2" worker="${3:-coord}" brief="${4:-初始化}" c
  if [ -e "$dest" ]; then
    printf '  跳过 %s（已存在）\n' "$dest"
    return 0
  fi
  c="$(cat "$SKILL_DIR/templates/$tpl")"
  c="${c//\{\{PROJECT\}\}/$PROJECT}"
  c="${c//\{\{SESSION\}\}/$SESSION}"
  c="${c//\{\{COORD_NAME\}\}/$COORD_NAME}"
  c="${c//\{\{SKILL_DIR\}\}/$SKILL_DIR}"
  c="${c//\{\{DATE\}\}/$DATE}"
  c="${c//\{\{WORKER\}\}/$worker}"
  c="${c//\{\{BRIEF\}\}/$brief}"
  printf '%s\n' "$c" > "$dest"
  printf '  建 %s\n' "$dest"
}

printf '▸ 写入本地状态与运行规约\n'
mkdir -p "$STATE/briefs" "$STATE/handoffs" "$STATE/inbox"
render workspace.md "$META"
render coord.md "$STATE/coord.md"
render worker.md "$STATE/worker.md"
render board.md "$STATE/board.md"
render pending.md "$STATE/pending.md"
render brief.md "$STATE/brief-template.md"
render handoff.md "$HANDOFF" coord '等待用户交代第一项任务'

if [ -f "$PROJECT/.gitignore" ]; then
  if ! grep -Eq '^/?\.aiw/?$' "$PROJECT/.gitignore"; then
    printf '\n.aiw/\n' >> "$PROJECT/.gitignore"
    printf '  追加 .gitignore：.aiw/\n'
  else
    printf '  跳过 .gitignore（已忽略 .aiw）\n'
  fi
else
  printf '.aiw/\n' > "$PROJECT/.gitignore"
  printf '  建 .gitignore\n'
fi

show_pane() {
  printf '%s\n' '--- coord 窗格末尾（仅用于诊断） ---' >&2
  tmux capture-pane -p -t "$SESSION:coord" 2>/dev/null | tail -n 30 >&2 || true
  printf '%s\n' '--- 保留现场，不自动清理；可运行：tmux attach -t '"$SESSION"' ---' >&2
}

wait_ready() {
  local expected="$1" attempts=30
  while [ "$attempts" -gt 0 ]; do
    tmux has-session -t "$SESSION" 2>/dev/null || { show_pane; fail 'tmux 工作区在启动期间消失。'; }
    if [ "$(tmux display-message -p -t "$SESSION:coord" '#{pane_dead}' 2>/dev/null || printf '1')" != '0' ]; then
      show_pane
      fail 'coord 进程已退出；未就绪。'
    fi
    if ! grep -Fqx 'AIW_STATUS: ready' "$HANDOFF" 2>/dev/null; then
      :
    elif [ "$expected" = 'any' ]; then
      grep -Eq '^AIW_READY: [0-9][0-9-]*$' "$HANDOFF" 2>/dev/null && return 0
    else
      grep -Fqx "AIW_READY: $expected" "$HANDOFF" 2>/dev/null && return 0
    fi
    attempts=$((attempts - 1))
    [ "$attempts" -eq 0 ] || sleep 1
  done
  return 1
}

READY_EVIDENCE='本次 ready 握手'
if [ "$COORD_EXISTED" = '1' ]; then
  READY_EVIDENCE='既有 ready 标记（未重新握手）'
  printf '▸ 复用现有 %s:coord，不重复启动\n' "$SESSION"
  if ! wait_ready any; then
    show_pane
    fail '现有 coord 尚未写回 ready；不重复启动，请检查信任、权限或登录提示。'
  fi
else
  NONCE="$(date +%Y%m%d%H%M%S)-$$"
  BOOT="你是 ${COORD_NAME}，只负责协调，不亲自实现。先读 ${STATE}/coord.md、${STATE}/board.md、${STATE}/pending.md 和 ${HANDOFF}。保留 handoff 既有内容，把其中 AIW_READY 改为 ${NONCE}、AIW_STATUS 改为 ready；不要创建 worker，不要开始其他任务。完成后只回复：大总管已就位，请交代第一件事。"
  SYSTEM_PROMPT="$(cat "$STATE/coord.md")"
  printf -v CLAUDE_CMD 'exec claude --name %q --append-system-prompt %q %q' "$COORD_NAME" "$SYSTEM_PROMPT" "$BOOT"

  printf '▸ 启动 %s:coord（detached，不切换焦点）\n' "$SESSION"
  if [ "$SESSION_EXISTED" = '0' ]; then
    tmux new-session -d -s "$SESSION" -n coord -c "$PROJECT" "$CLAUDE_CMD"
  else
    tmux new-window -d -t "$SESSION" -n coord -c "$PROJECT" "$CLAUDE_CMD"
  fi
  if ! tmux set-window-option -t "$SESSION:coord" remain-on-exit on >/dev/null; then
    show_pane
    fail 'coord 窗口在启动后立即消失；未能保留现场。'
  fi
  if ! wait_ready "$NONCE"; then
    show_pane
    fail 'coord 未在 30 秒内完成 ready 握手；窗口已保留，不能视为成功。'
  fi
fi

COORD_CWD="$(tmux display-message -p -t "$SESSION:coord" '#{pane_current_path}')"
COORD_START="$(tmux display-message -p -t "$SESSION:coord" '#{pane_start_command}')"
COORD_START="${COORD_START#\"}"
COORD_START="${COORD_START%\"}"
[ "$COORD_CWD" = "$PROJECT" ] || fail "验证失败：coord cwd 是 $COORD_CWD。"
case "$COORD_START" in
  exec\ claude\ *) ;;
  *) show_pane; fail '验证失败：coord 窗格启动命令不是 exec claude。' ;;
esac
if grep -R -n -E '\{\{(PROJECT|SESSION|COORD_NAME|SKILL_DIR|DATE|WORKER|BRIEF)\}\}' \
  "$META" "$STATE/coord.md" "$STATE/worker.md" "$HANDOFF" >/dev/null; then
  fail '验证失败：生成物仍有未替换的模板占位符。'
fi

cat <<EOF

━━ 大总管已就位 ━━
  tmux：$SESSION:coord
  会话名：$COORD_NAME
  项目：$PROJECT
  状态：${STATE}（本地忽略）
  验证：window + cwd + Claude 启动命令与存活 + ${READY_EVIDENCE}

进入工作区：tmux attach -t $SESSION
下一步：只派一个只读 worker 做小事，让 coord 独立核验后再放量。
EOF

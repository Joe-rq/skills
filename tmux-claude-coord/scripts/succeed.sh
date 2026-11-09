#!/usr/bin/env bash
# tmux-claude-coord · 接班：从 handoff 的「下一步」启动新一代 coord；旧窗口保留，不 kill、不改名。
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
用法：succeed.sh --project DIR --session NAME [--window 新窗口名] [--name 新会话名]
                 [--model MODEL] [--timeout 秒，默认 90]
  若存在 .aiw/coord.md.new（upgrade.sh 生成），接班握手成功后让它生效；
  旧 coord.md 备份为 coord.md.gen<N>.prev，本地私有条款请放 coord.local.md。
EOF
  exit 2
}

fail() {
  printf 'tmux-claude-coord succeed: %s\n' "$1" >&2
  exit 1
}

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=lib.sh
. "$SKILL_DIR/scripts/lib.sh"

PROJECT_INPUT=''
SESSION=''
NEW_WINDOW=''
NEW_NAME=''
MODEL=''
TIMEOUT=90
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || usage; PROJECT_INPUT="$2"; shift 2 ;;
    --session) [ "$#" -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
    --window) [ "$#" -ge 2 ] || usage; NEW_WINDOW="$2"; shift 2 ;;
    --name) [ "$#" -ge 2 ] || usage; NEW_NAME="$2"; shift 2 ;;
    --model) [ "$#" -ge 2 ] || usage; MODEL="$2"; shift 2 ;;
    --timeout)
      [ "$#" -ge 2 ] || usage
      case "$2" in ''|*[!0-9]*) fail '--timeout 必须是正整数秒。' ;; esac
      [ "$2" -gt 0 ] || fail '--timeout 必须是正整数秒。'
      TIMEOUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$PROJECT_INPUT" ] && [ -n "$SESSION" ] || usage
aiw_safe_name "$SESSION" || fail '工作区名不合法。'
for cmd in tmux claude; do command -v "$cmd" >/dev/null 2>&1 || fail "缺少依赖：$cmd。"; done
aiw_require_utf8

PROJECT="$(cd "$PROJECT_INPUT" 2>/dev/null && pwd -P)" || fail "项目目录不存在：$PROJECT_INPUT"
STATE="$PROJECT/.aiw"
META="$STATE/workspace.md"
HANDOFF="$STATE/handoffs/coord.md"
[ -f "$META" ] || fail '工作区尚未初始化：workspace.md 不存在。'
grep -Fqx -- "- 项目根目录：$PROJECT" "$META" || fail 'workspace.md 与项目不匹配。'
grep -Fqx -- "- tmux 工作区：$SESSION" "$META" || fail 'workspace.md 与工作区不匹配。'
[ -f "$HANDOFF" ] || fail "coord handoff 不存在：$HANDOFF；先让旧 coord 写好交接。"
[ -f "$STATE/coord.md" ] || fail 'coord 工作合同不存在。'
tmux has-session -t "=$SESSION" 2>/dev/null || fail "tmux 工作区不存在：$SESSION。"
aiw_load_coord_identity "$META"
NEW_GEN=$((COORD_GEN + 1))

if [ -z "$NEW_WINDOW" ]; then
  # coord → coord2；coord4b → coord4b2；已被占用就继续自增。
  suffix="$(printf '%s' "$COORD_WINDOW" | sed -n 's/^.*[^0-9]\([0-9][0-9]*\)$/\1/p')"
  if [ -n "$suffix" ]; then
    NEW_WINDOW="${COORD_WINDOW%"$suffix"}$((suffix + 1))"
  else
    NEW_WINDOW="${COORD_WINDOW}2"
  fi
  while [ -n "$(aiw_window_id "$SESSION" "$NEW_WINDOW")" ]; do
    suffix="$(printf '%s' "$NEW_WINDOW" | sed -n 's/^.*[^0-9]\([0-9][0-9]*\)$/\1/p')"
    if [ -n "$suffix" ]; then
      NEW_WINDOW="${NEW_WINDOW%"$suffix"}$((suffix + 1))"
    else
      NEW_WINDOW="${NEW_WINDOW}2"
    fi
  done
fi
aiw_safe_name "$NEW_WINDOW" || fail '新窗口名只能含小写字母、数字和连字符，最长 32 字符；可用 --window 指定。'
[ -z "$(aiw_window_id "$SESSION" "$NEW_WINDOW")" ] || fail "新窗口已存在：${SESSION}:${NEW_WINDOW}。"
[ -n "$NEW_NAME" ] || NEW_NAME="$SESSION-$NEW_WINDOW"
case "$NEW_NAME$MODEL" in *$'\n'*|*$'\r'*) fail '会话名与模型名不能含换行。' ;; esac

# 接班上下文：handoff 的「下一步」章节原文。
NEXT="$(awk '/^## 下一步/{flag=1; next} /^## /{flag=0} flag' "$HANDOFF")"
[ -n "${NEXT//[[:space:]]/}" ] || NEXT='按 handoff 与 board.md 恢复上下文，等待用户交代下一步。'

NONCE="$(date +%Y%m%d%H%M%S)-$$"
BOOT="你是 ${NEW_NAME}，第 ${NEW_GEN} 代 coord，只负责协调，不亲自实现。先读 ${STATE}/coord.md、${STATE}/board.md、${STATE}/pending.md 和 ${HANDOFF}。保留 handoff 既有内容，把其中 AIW_READY 改为 ${NONCE}、AIW_STATUS 改为 ready。然后接着执行 handoff 中的「下一步」：
${NEXT}
旧 coord 窗口保留作证据，不要 kill、不要改名，不要重复执行已完成事项。不要创建 worker，除非下一步明确要求。完成后只回复：接班就位，已恢复上下文。"
if [ -f "$STATE/coord.md.new" ]; then
  aiw_load_prompt "$STATE/coord.md.new" "$STATE/coord.local.md"
else
  aiw_load_prompt "$STATE/coord.md" "$STATE/coord.local.md"
fi
printf -v CLAUDE_CMD 'exec claude --name %q --append-system-prompt %q' "$NEW_NAME" "$AIW_PROMPT"
if [ -n "$MODEL" ]; then
  printf -v EXTRA ' --model %q' "$MODEL"
  CLAUDE_CMD="$CLAUDE_CMD$EXTRA"
fi
printf -v EXTRA ' %q' "$BOOT"
CLAUDE_CMD="$CLAUDE_CMD$EXTRA"

printf '▸ 启动接班 coord %s:%s（旧窗口 %s 保留，不切换焦点）\n' "$SESSION" "$NEW_WINDOW" "$COORD_WINDOW"
NEW_ID="$(tmux new-window -d -P -F '#{window_id}' -t "=$SESSION" -n "$NEW_WINDOW" -c "$PROJECT" "$CLAUDE_CMD")"
if ! tmux set-window-option -t "$NEW_ID" remain-on-exit on >/dev/null; then
  aiw_show_pane "$NEW_ID" "$NEW_WINDOW"
  fail '接班窗口在启动后立即消失；未能保留现场。'
fi
wait_rc=0
aiw_wait_ready "$NEW_ID" "$HANDOFF" "$NONCE" ready "$TIMEOUT" || wait_rc=$?
if [ "$wait_rc" = '2' ]; then
  aiw_show_pane "$NEW_ID" "$NEW_WINDOW"
  fail '接班 coord 进程已退出；workspace.md 指针未改，仍指向上一代。'
elif [ "$wait_rc" != '0' ]; then
  aiw_show_pane "$NEW_ID" "$NEW_WINDOW"
  fail "接班 coord 未在 ${TIMEOUT} 秒内完成 ready 握手；窗口已保留，workspace.md 指针未改。"
fi

# 握手成功后才切换身份与合同，避免半失败状态。
if [ -f "$STATE/coord.md.new" ]; then
  cp "$STATE/coord.md" "$STATE/coord.md.gen${COORD_GEN}.prev"
  mv "$STATE/coord.md.new" "$STATE/coord.md"
  printf '  coord.md.new 已生效；旧合同备份：%s\n' "$STATE/coord.md.gen${COORD_GEN}.prev"
fi
sed -i '' \
  -e "s|^- coord 窗口：.*|- coord 窗口：$NEW_WINDOW|" \
  -e "s|^- coord 会话名：.*|- coord 会话名：$NEW_NAME|" \
  -e "s|^- coord 代数：.*|- coord 代数：$NEW_GEN|" "$META"
if ! grep -Fqx -- "- coord 代数：$NEW_GEN" "$META"; then
  sed -i '' -e '/^- coord 会话名：/a\' -e "- coord 代数：$NEW_GEN" "$META"
fi

cat <<EOF

━━ 接班完成 ━━
  新 coord：${SESSION}:${NEW_WINDOW}（第 ${NEW_GEN} 代，会话名 ${NEW_NAME}）
  旧 coord：${SESSION}:${COORD_WINDOW} 保留未动；确认接班正常后可由用户决定是否清理
  workspace.md：coord 窗口 / 会话名 / 代数已更新
  验证：新窗口存活 + exec claude + 本次 nonce ready 握手
EOF

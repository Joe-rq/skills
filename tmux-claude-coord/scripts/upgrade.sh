#!/usr/bin/env bash
# tmux-claude-coord · 把项目 .aiw 的工作合同升级到当前技能模板。默认只显示 diff，不写任何文件。
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
用法：upgrade.sh --project DIR [--apply] [--skill-dir DIR]
  默认 diff-only。--apply 时：
    worker.md 只含新增行才直接更新（旧文件备份为 worker.md.bak），否则落到 worker.md.new；
    coord.md 永不覆盖，更新落到 coord.md.new，由 succeed.sh 接班时生效；
    coord.local.md / worker.local.md 永不创建、永不覆盖。
EOF
  exit 2
}

fail() {
  printf 'tmux-claude-coord upgrade: %s\n' "$1" >&2
  exit 1
}

DEFAULT_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=lib.sh
. "$DEFAULT_SKILL_DIR/scripts/lib.sh"

PROJECT_INPUT=''
SKILL_DIR="$DEFAULT_SKILL_DIR"
APPLY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || usage; PROJECT_INPUT="$2"; shift 2 ;;
    --skill-dir) [ "$#" -ge 2 ] || usage; SKILL_DIR="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$PROJECT_INPUT" ] || usage
PROJECT="$(cd "$PROJECT_INPUT" 2>/dev/null && pwd -P)" || fail "项目目录不存在：$PROJECT_INPUT"
SKILL_DIR="$(cd "$SKILL_DIR" 2>/dev/null && pwd -P)" || fail "技能目录不存在。"
STATE="$PROJECT/.aiw"
META="$STATE/workspace.md"
[ -f "$META" ] || fail '工作区尚未初始化：workspace.md 不存在。'
grep -Fqx -- "- 项目根目录：$PROJECT" "$META" || fail 'workspace.md 与项目不匹配。'
SESSION="$(aiw_meta_value 'tmux 工作区' "$META")"
[ -n "$SESSION" ] || fail 'workspace.md 缺少 tmux 工作区。'
aiw_load_coord_identity "$META"
DATE="$(date +%Y-%m-%d)"
WORKER='coord'
BRIEF='初始化'

TMP="$(mktemp -d /tmp/aiw-upgrade.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

show_diff() { # <role> <current> <rendered>；有差异返回 0
  local role="$1" cur="$2" new="$3"
  if [ -f "$cur" ] && cmp -s "$cur" "$new"; then
    printf '== %s：已是最新，无差异\n' "$role"
    return 1
  fi
  printf '== %s 差异（左=现有，右=新模板渲染）\n' "$role"
  if [ -f "$cur" ]; then
    diff -u --label "a/$role" --label "b/$role" "$cur" "$new" || true
  else
    diff -u --label 'a/不存在' --label "b/$role" /dev/null "$new" || true
  fi
  return 0
}

for role in worker coord; do
  [ -f "$SKILL_DIR/templates/$role.md" ] || fail "技能模板缺失：$role.md"
  aiw_render_file "$SKILL_DIR/templates/$role.md" "$TMP/$role.md"
  CUR="$STATE/$role.md"
  if show_diff "$role.md" "$CUR" "$TMP/$role.md"; then
    if [ "$APPLY" = '1' ]; then
      if [ "$role" = 'worker' ] && { [ ! -f "$CUR" ] || ! diff "$CUR" "$TMP/$role.md" | grep -q '^<'; }; then
        # 无损更新（只有新增行）才直接覆盖 worker.md；有删除/改写就同样走 .new。
        [ ! -f "$CUR" ] || cp "$CUR" "$STATE/worker.md.bak"
        cp "$TMP/$role.md" "$CUR"
        printf '  已更新 %s（备份：%s）\n' "$CUR" "$STATE/worker.md.bak"
      else
        cp "$TMP/$role.md" "$STATE/$role.md.new"
        if [ "$role" = 'coord' ]; then
          printf '  已写 %s；现有 coord.md 未动，succeed.sh 接班时生效\n' "$STATE/$role.md.new"
        else
          printf '  worker.md 含本地删除/改写，已写 %s；请人工合并\n' "$STATE/$role.md.new"
        fi
      fi
    fi
  fi
done

if [ "$APPLY" = '0' ]; then
  printf '\n（diff-only，未写任何文件；确认后加 --apply）\n'
else
  printf '\nlocal 文件未触碰：%s / %s\n' "$STATE/coord.local.md" "$STATE/worker.local.md"
fi

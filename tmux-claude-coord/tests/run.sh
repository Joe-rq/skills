#!/usr/bin/env bash
# tmux-claude-coord · 隔离夹具回归测试。
# 私有 tmux socket + 假 claude，不碰真实工作区与真实会话。
# 用法：bash tests/run.sh            测当前技能目录
#       AIW_SKILL_DIR=/path bash tests/run.sh   测指定技能副本（如旧版快照，复现红）
#       AIW_TEST_BASH=/bin/bash bash tests/run.sh   用 bash 3.2 跑
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="${AIW_SKILL_DIR:-$(cd "$HERE/.." && pwd -P)}"
TEST_BASH="${AIW_TEST_BASH:-bash}"
REAL_TMUX="$(command -v tmux)"
PASS=0
FAIL=0
CURRENT=''

say() { printf '%s\n' "$*"; }
ok() { PASS=$((PASS + 1)); say "  ✓ $1"; }
bad() { FAIL=$((FAIL + 1)); say "  ✗ $1"; }
check() { # check <描述> <命令...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}
assert_contains() { # assert_contains <文件> <固定字符串> <描述>
  if grep -Fq -- "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3（在 $1 中找不到：$2）"; fi
}
assert_not_contains() {
  if grep -Fq -- "$2" "$1" 2>/dev/null; then bad "$3（$1 不应包含：$2）"; else ok "$3"; fi
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1（期望 [$3]，实际 [$2]）"; fi
}

# 每个用例一个沙盒：fake-bin/claude、fake-bin/tmux、mode 文件、argv.log、prompts/
setup_sandbox() {
  SB="$(mktemp -d /tmp/aiw-fixture.XXXXXX)"
  mkdir -p "$SB/fake-bin" "$SB/prompts"
  printf 'aiwtest-%s-%s\n' "$$" "$CURRENT" > "$SB/socket-name"
  printf 'normal\n' > "$SB/mode"
  cat > "$SB/fake-bin/tmux" <<TMUX_EOF
#!/usr/bin/env bash
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd -P)"
exec "$REAL_TMUX" -L "\$(cat "\$ROOT/socket-name")" -f /dev/null "\$@"
TMUX_EOF
  # 用文件而非环境变量传配置：tmux server 不继承调用者的自定义 env。
  cat > "$SB/fake-bin/claude" <<'CLAUDE_EOF'
#!/usr/bin/env bash
# 假 claude：记录 argv 与 system prompt，按 mode 文件模拟握手行为。
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
name=''; prompt=''; boot=''
{ printf 'CALL'; printf ' %s' "$@"; printf '\n'; } >> "$ROOT/argv.log"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) name="$2"; shift 2 ;;
    --append-system-prompt) prompt="$2"; shift 2 ;;
    --add-dir|--model) shift 2 ;;
    --worktree) shift; if [ "$#" -gt 0 ]; then case "$1" in -*) ;; *) shift ;; esac; fi ;;
    *) boot="$1"; shift ;;
  esac
done
printf '%s\n' "$prompt" > "$ROOT/prompts/$name.md"
printf '%s\n' "$boot" > "$ROOT/prompts/$name.boot"
mode="$(cat "$ROOT/mode" 2>/dev/null || printf normal)"
[ -f "$ROOT/mode.$name" ] && mode="$(cat "$ROOT/mode.$name")"
[ "$mode" = 'exit' ] && exit 1
handshake() {
  local handoff nonce status
  handoff="$(printf '%s' "$boot" | grep -oE '/[^ ，。、]*handoffs/[^ ，。、]*\.md' | head -n 1)"
  nonce="$(printf '%s' "$boot" | sed -n 's/.*AIW_READY 改为 \([0-9A-Za-z-]*\).*/\1/p')"
  status="$(printf '%s' "$boot" | sed -n 's/.*AIW_STATUS 改为 \([a-z]*\).*/\1/p')"
  [ -n "$handoff" ] && [ -n "$nonce" ] && [ -n "$status" ] || return 0
  sed -i '' -e "s/^AIW_READY:.*/AIW_READY: $nonce/" -e "s/^AIW_STATUS:.*/AIW_STATUS: $status/" "$handoff"
}
case "$mode" in
  normal) handshake ;;
  slow) ( sleep "$(cat "$ROOT/delay" 2>/dev/null || printf 3)"; handshake ) & ;;
  silent) : ;;
esac
exec sleep 300
CLAUDE_EOF
  chmod +x "$SB/fake-bin/tmux" "$SB/fake-bin/claude"
  PATH="$SB/fake-bin:$PATH"
  export PATH
}
teardown_sandbox() {
  tmux kill-server 2>/dev/null
  if [ "$KEEP_FAILED" = '1' ]; then
    say "  现场保留：$SB"
  else
    rm -rf "$SB"
  fi
}
run_case() { # run_case <编号> <函数名>
  CURRENT="$1"
  KEEP_FAILED=0
  local fail_before="$FAIL"
  say "▸ 用例 $1"
  setup_sandbox
  "$2"
  [ "$FAIL" -gt "$fail_before" ] && KEEP_FAILED=1
  teardown_sandbox
}
new_project() { # new_project <名字> → 全局 PROJECT（物理路径，/tmp 在 macOS 是符号链接）
  PROJECT="$SB/$1"
  mkdir -p "$PROJECT"
  PROJECT="$(cd "$PROJECT" && pwd -P)"
}
init_skill() { # init_skill [额外参数...]
  "$TEST_BASH" "$SKILL/scripts/init.sh" "$PROJECT" aiw "$@" > "$SB/init.out" 2>&1
}

# ── 用例 1：& 渲染安全 + local 附加 ─────────────────────────────
case_amp() {
  new_project 'a&b'
  mkdir -p "$PROJECT/.aiw"
  printf 'R&D 私有条款\n' > "$PROJECT/.aiw/coord.local.md"
  if ! init_skill; then bad 'init 成功'; return; fi
  ok 'init 成功'
  assert_contains "$PROJECT/.aiw/workspace.md" "- 项目根目录：$PROJECT" '项目路径含 & 时原样写入 workspace.md'
  assert_contains "$PROJECT/.aiw/coord.md" "$PROJECT" 'coord.md 含真实项目路径'
  assert_not_contains "$PROJECT/.aiw/coord.md" '{{PROJECT}}' 'coord.md 无占位符残留'
  assert_contains "$SB/prompts/aiw-coord.md" 'R&D 私有条款' 'coord.local.md 附加进 system prompt'
}

# ── 用例 2：session 名前缀不得误匹配 ────────────────────────────
case_exact_session() {
  new_project proj-b
  if ! "$TEST_BASH" "$SKILL/scripts/init.sh" "$PROJECT" aiw-fixture > /dev/null 2>&1; then
    bad '夹具：项目 B 的 aiw-fixture 初始化'
  fi
  new_project proj-a
  if init_skill; then ok '短名 aiw 不被已有 aiw-fixture 劫持，init 成功'; else
    bad '短名 aiw 不被已有 aiw-fixture 劫持，init 成功'; return
  fi
  check '存在精确的 aiw session' tmux has-session -t '=aiw'
  assert_eq 'proj-a 的 coord cwd 正确' \
    "$(tmux display-message -p -t '=aiw:=coord' '#{pane_current_path}' 2>/dev/null)" "$PROJECT"
}

# ── 用例 3：复用只看窗口存活与身份，handoff 状态作参考 ──────────
case_reuse_reference() {
  new_project proj
  if ! init_skill; then bad '首次 init'; return; fi
  # 模拟 g4a 现场：自定义 nonce + 非 ready 状态
  sed -i '' -e 's/^AIW_READY:.*/AIW_READY: 20261105170500-gseq/' \
    -e 's/^AIW_STATUS:.*/AIW_STATUS: waiting/' "$PROJECT/.aiw/handoffs/coord.md"
  if init_skill; then ok 'waiting + 自定义 nonce 的存活 coord 可复用'; else bad 'waiting + 自定义 nonce 的存活 coord 可复用'; fi
  assert_eq '复用不新建窗口' "$(tmux list-windows -t '=aiw' -F '#W' | wc -l | tr -d ' ')" '1'
}

# ── 用例 4：spawn --timeout 与 --recheck ────────────────────────
case_spawn_timeout() {
  new_project proj
  if ! init_skill; then bad '首次 init'; return; fi
  printf '# brief\n' > "$PROJECT/.aiw/briefs/w1.md"
  printf 'slow\n' > "$SB/mode.aiw-w1"
  printf '3\n' > "$SB/delay"
  if "$TEST_BASH" "$SKILL/scripts/spawn.sh" --project "$PROJECT" --session aiw \
      --worker w1 --brief "$PROJECT/.aiw/briefs/w1.md" --timeout 1 > "$SB/spawn1.out" 2>&1; then
    bad '慢握手 + --timeout 1 应超时失败'
  else
    ok '慢握手 + --timeout 1 超时失败（保留现场）'
  fi
  sleep 4
  if "$TEST_BASH" "$SKILL/scripts/spawn.sh" --project "$PROJECT" --session aiw \
      --worker w1 --brief "$PROJECT/.aiw/briefs/w1.md" --recheck > "$SB/spawn2.out" 2>&1; then
    ok '--recheck 补验成功'
  else
    bad '--recheck 补验成功'
  fi
  assert_eq '--recheck 不新建窗口' "$(tmux list-windows -t '=aiw' -F '#W' | wc -l | tr -d ' ')" '2'
  if grep -Fq 'AIW_READY: none' "$PROJECT/.aiw/handoffs/w1.md"; then
    bad '--recheck 未覆盖既有 handoff'
  else
    ok '--recheck 未覆盖既有 handoff'
  fi
}

# ── 用例 5：succeed 接班 ────────────────────────────────────────
case_succeed() {
  new_project proj
  if ! init_skill; then bad '首次 init'; return; fi
  cat >> "$PROJECT/.aiw/handoffs/coord.md" <<'EOF'

## 下一步

1. 继续处理 issue-42 的验收。
EOF
  if "$TEST_BASH" "$SKILL/scripts/succeed.sh" --project "$PROJECT" --session aiw \
      --model test-model > "$SB/succeed.out" 2>&1; then
    ok 'succeed 成功'
  else
    bad 'succeed 成功'; return
  fi
  assert_eq '旧窗口 coord 保留未改名' \
    "$(tmux list-windows -t '=aiw' -F '#W' | grep -cx coord)" '1'
  assert_eq '新窗口 coord2 存在' \
    "$(tmux list-windows -t '=aiw' -F '#W' | grep -cx coord2)" '1'
  assert_contains "$PROJECT/.aiw/workspace.md" '- coord 窗口：coord2' 'workspace.md 指向新 coord 窗口'
  assert_contains "$PROJECT/.aiw/workspace.md" '- coord 会话名：aiw-coord2' 'workspace.md 记录新会话名'
  assert_contains "$SB/argv.log" '--model test-model' 'succeed 传递 --model'
  assert_contains "$SB/prompts/aiw-coord2.boot" 'issue-42' '接班 BOOT 含 handoff 的下一步'
  # 旧窗口被人工清理/改名后，spawn 不得再要求名为 coord 的窗口
  tmux rename-window -t '=aiw:=coord' coord-retired
  printf '# brief\n' > "$PROJECT/.aiw/briefs/w1.md"
  if "$TEST_BASH" "$SKILL/scripts/spawn.sh" --project "$PROJECT" --session aiw \
      --worker w1 --brief "$PROJECT/.aiw/briefs/w1.md" > "$SB/spawn.out" 2>&1; then
    ok 'coord 窗口不叫 coord 时 spawn 仍工作'
  else
    bad 'coord 窗口不叫 coord 时 spawn 仍工作'
  fi
  assert_contains "$SB/prompts/aiw-w1.boot" 'aiw-coord2' 'worker 向当前代 coord 报到'
}

# ── 用例 6：upgrade diff/apply/local 保护 ───────────────────────
case_upgrade() {
  new_project proj
  if ! init_skill; then bad '首次 init'; return; fi
  # 模拟 g4a：worker.md 是旧渲染（去掉无人值守 8 行），coord.md 有本地改写
  "$TEST_BASH" -c '
    f="$1"; n=$(wc -l < "$f" | tr -d " ")
    head -n $((n - 8)) "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  ' _ "$PROJECT/.aiw/worker.md"
  printf '\n本地改写：完工即清理。\n' >> "$PROJECT/.aiw/coord.md"
  printf '私有条款：禁止弹窗之外另加规则\n' > "$PROJECT/.aiw/coord.local.md"
  if "$TEST_BASH" "$SKILL/scripts/upgrade.sh" --project "$PROJECT" > "$SB/up1.out" 2>&1; then
    ok 'upgrade 默认 diff-only 退出 0'
  else
    bad 'upgrade 默认 diff-only 退出 0'
  fi
  assert_contains "$SB/up1.out" '无人值守' 'diff 显示 worker.md 缺失内容'
  if [ -f "$PROJECT/.aiw/coord.md.new" ]; then bad 'diff-only 不写 coord.md.new'; else ok 'diff-only 不写 coord.md.new'; fi
  if "$TEST_BASH" "$SKILL/scripts/upgrade.sh" --project "$PROJECT" --apply > "$SB/up2.out" 2>&1; then
    ok 'upgrade --apply 成功'
  else
    bad 'upgrade --apply 成功'
  fi
  assert_contains "$PROJECT/.aiw/worker.md" '无人值守纪律' 'apply 后 worker.md 补齐'
  assert_contains "$PROJECT/.aiw/coord.md" '本地改写：完工即清理。' 'apply 不覆盖 coord.md'
  if [ -f "$PROJECT/.aiw/coord.md.new" ]; then ok 'coord.md 落到 coord.md.new'; else bad 'coord.md 落到 coord.md.new'; fi
  assert_contains "$PROJECT/.aiw/coord.local.md" '私有条款' 'coord.local.md 不被覆盖'
  # 接班时 coord.md.new 生效，且 local 仍附加
  if "$TEST_BASH" "$SKILL/scripts/succeed.sh" --project "$PROJECT" --session aiw > "$SB/succeed.out" 2>&1; then
    ok 'upgrade 后 succeed 成功'
  else
    bad 'upgrade 后 succeed 成功'; return
  fi
  assert_contains "$PROJECT/.aiw/coord.md.gen1.prev" '本地改写：完工即清理。' '旧 coord.md 本地改写留在接班备份'
  assert_contains "$PROJECT/.aiw/coord.md" '无人值守纪律' '接班后 coord.md.new 生效'
  assert_contains "$SB/prompts/aiw-coord2.md" '私有条款' '接班 prompt 附加 coord.local.md'
}

# ── 用例 7：死窗格保留现场 ──────────────────────────────────────
case_dead_pane() {
  new_project proj
  if ! init_skill; then bad '首次 init'; return; fi
  pid="$(tmux display-message -p -t '=aiw:=coord' '#{pane_pid}')"
  kill -9 "$pid" 2>/dev/null
  sleep 1
  if init_skill; then bad '死窗格应拒绝复用'; else ok '死窗格拒绝复用并保留现场'; fi
  assert_contains "$SB/init.out" '死窗格' '报错指出死窗格'
}

run_case 1 case_amp
run_case 2 case_exact_session
run_case 3 case_reuse_reference
run_case 4 case_spawn_timeout
run_case 5 case_succeed
run_case 6 case_upgrade
run_case 7 case_dead_pane

say ''
say "══ 结果：${PASS} 通过 / ${FAIL} 失败（技能：${SKILL}；bash：${TEST_BASH}）"
[ "$FAIL" -eq 0 ]

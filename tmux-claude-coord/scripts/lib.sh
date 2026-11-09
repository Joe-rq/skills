#!/usr/bin/env bash
# tmux-claude-coord · 内部共用函数；由 init/spawn/succeed/upgrade source，不单独执行。
# 兼容 bash 3.2：不用关联数组、mapfile、|&。

# bash 5.2 的 patsub_replacement 会把替换文本里的 & 当成「整个匹配」，渲染前关掉。
shopt -u patsub_replacement 2>/dev/null || true

aiw_safe_name() {
  case "$1" in ''|*[!a-z0-9-]*|-*) return 1 ;; esac
  [ "${#1}" -le 32 ]
}

# 模板渲染。调用前设置全局 PROJECT/SESSION/COORD_NAME/SKILL_DIR/DATE/WORKER/BRIEF。
aiw_render_file() {
  local tpl="$1" out="$2" c k v
  c="$(cat "$tpl")"
  for k in PROJECT SESSION COORD_NAME SKILL_DIR DATE WORKER BRIEF; do
    eval "v=\"\${$k-}\""
    c="${c//"{{$k}}"/$v}"
  done
  printf '%s\n' "$c" > "$out"
}

# 读 workspace.md 的「- <键>：<值>」。
aiw_meta_value() {
  [ -f "$2" ] || return 0
  sed -n "s/^- $1：//p" "$2" 2>/dev/null | head -n 1 || true
}

# 当前 coord 窗口/会话名/代数；老工作区缺字段时回退到初代约定。
aiw_load_coord_identity() { # 参数：workspace.md；设置 COORD_WINDOW/COORD_NAME/COORD_GEN
  local meta="$1"
  COORD_WINDOW="$(aiw_meta_value 'coord 窗口' "$meta")"
  COORD_NAME="$(aiw_meta_value 'coord 会话名' "$meta")"
  COORD_GEN="$(aiw_meta_value 'coord 代数' "$meta")"
  [ -n "$COORD_WINDOW" ] || COORD_WINDOW='coord'
  [ -n "$COORD_NAME" ] || COORD_NAME="$SESSION-coord"
  case "$COORD_GEN" in ''|*[!0-9]*) COORD_GEN=1 ;; esac
}

# 精确窗口名 → 窗口 ID。display-message 对不存在的目标可能静默成功，身份判断一律走 ID。
aiw_window_id() { # <session> <window-name>
  tmux list-windows -t "=$1" -F '#{window_id} #{window_name}' 2>/dev/null |
    while read -r id name; do
      if [ "$name" = "$2" ]; then printf '%s\n' "$id"; break; fi
    done || true
}

aiw_pane_field() { # <window-id> <format>
  tmux display-message -p -t "$1" "$2" 2>/dev/null
}

aiw_start_command() { # <window-id>；去掉 tmux 返回的外层引号
  local s
  s="$(aiw_pane_field "$1" '#{pane_start_command}')"
  s="${s#\"}"
  s="${s%\"}"
  printf '%s\n' "$s"
}

aiw_show_pane() { # <window-id> <标题>
  printf '%s\n' "--- $2 窗格末尾（仅用于诊断） ---" >&2
  tmux capture-pane -p -t "$1" 2>/dev/null | tail -n 30 >&2 || true
  printf '%s\n' '--- 保留现场，不自动清理 ---' >&2
}

# 组装 system prompt：合同 + 可选项目私有条款（local 永不随升级覆盖）。
aiw_load_prompt() { # <base.md> <local.md>；设置 AIW_PROMPT
  AIW_PROMPT="$(cat "$1")"
  if [ -f "$2" ]; then
    AIW_PROMPT="$AIW_PROMPT

## 项目私有条款（$2；升级不覆盖）

$(cat "$2")"
  fi
}

# bash 3.2 的 printf %q 在非 UTF-8 locale 会把中文转成转义字节，且可能超出 tmux 命令长度上限。
aiw_require_utf8() {
  local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  case "$loc" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) ;;
    *) printf 'tmux-claude-coord: 当前 locale（%s）不是 UTF-8，无法安全传递中文启动提示；请设置 LANG=en_US.UTF-8 后重试。\n' "$loc" >&2; exit 1 ;;
  esac
}

# 等待握手。nonce=any 接受任意非 none 标记；status=any 接受 booting 之外的状态。
# 返回 0 就绪 / 1 超时 / 2 窗格已死或消失。
aiw_wait_ready() { # <window-id> <handoff> <nonce|any> <status|any> <timeout-sec>
  local wid="$1" handoff="$2" nonce="$3" status="$4" timeout="$5"
  local elapsed=0 dead ready cur_status
  while [ "$elapsed" -lt "$timeout" ]; do
    dead="$(aiw_pane_field "$wid" '#{pane_dead}')"
    [ "$dead" = '0' ] || return 2
    if [ -f "$handoff" ]; then
      ready="$(sed -n 's/^AIW_READY: //p' "$handoff" | head -n 1)"
      cur_status="$(sed -n 's/^AIW_STATUS: //p' "$handoff" | head -n 1)"
      if { [ "$nonce" = 'any' ] && [ -n "$ready" ] && [ "$ready" != 'none' ]; } ||
         [ "$ready" = "$nonce" ]; then
        if { [ "$status" = 'any' ] && [ -n "$cur_status" ] && [ "$cur_status" != 'booting' ]; } ||
           [ "$cur_status" = "$status" ]; then
          return 0
        fi
      fi
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

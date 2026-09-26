#!/usr/bin/env bash
# ai-dev-flow · 记录型 hook —— 与每个拦截型 hook **并联**
#
# 它永不返回决策，永远 exit 0，只做一件事：把触碰受管表面的事件追加到
# .claude/.state/audit.jsonl。
#
# 为什么必须有它（这不是"加个日志"那种可选项）：
#   拦截型 hook 有三种静默失效的方式——超时（不阻断）、路径写错（不阻断）、
#   退出码用成 1（多数事件只有 exit 2 才拦）。三者合起来正好构成本方法论最忌讳的
#   那种失败：**看起来有效果**。
#
#   并联记录之后，拦截失效时事件仍然留痕。于是 rule-manager 的证据来源是
#   这份记录，而不是"hook 没拦，所以应该没问题"。
#
# 为什么用追加写而不是"读-改-写"：同一事件的多个 hook 是**并行**执行的，
# 读-改-写会丢更新。一行一个 JSON + flock，不需要锁住整个文件。
#
# 为什么它也必须走 _lib.sh 的解析层，而不是自己调 python3：
#   一个"缺 python3 就什么都不记"的记录器，恰好就是它自己要防的那种失败。
#   其余 hook 缺依赖时会经 aidf_deps 显式报警（stderr）——记录器不能例外。
#   于是这里用 jget 取字段，用 case 做受管表面的判定（纯字符串匹配，
#   不需要在 python 和 jq 里各写一份过滤逻辑，避免两边漂移）。

set -uo pipefail

_lib="$(dirname "$0")/_lib.sh"
if [ ! -f "$_lib" ]; then exit 0; fi
. "$_lib"
# 缺依赖时 aidf_deps 会往 stderr 报警并 exit 0——记录器不阻断，但也绝不假装记过了
aidf_deps

input=$(cat)

tool=$(jget tool_name "$input")
target=$(jget tool_input.command "$input")
[ -z "$target" ] && target=$(jget tool_input.file_path "$input")
[ -z "$target" ] && target=$(jget tool_input.notebook_path "$input")

# 只记录触碰受管表面的事件。全量记录会把有用信号淹掉——
# 而这个文件的唯一用途是"事后能问出发生过什么"。
# 判定与 python 版逐字等价（"/code/" 不写成 "code/"，否则 mycode/ 会被误算）。
guarded=0
case "$tool" in
  Bash)
    case "$target" in
      *"git commit"*|*"git merge"*|*"git checkout"*|*"git switch"*|*"git branch"*|*"git push"*)
        guarded=1 ;;
    esac ;;
esac
if [ "$guarded" -eq 0 ]; then
  case "$target" in
    *"doc/决策约束/"*|*"/doc/待裁/"*|*"/doc/待批/"*|doc/待裁/*|doc/待批/*|*"/code/"*|code/*)
      guarded=1 ;;
  esac
fi
[ "$guarded" -eq 1 ] || exit 0

state="${CLAUDE_PROJECT_DIR:-.}/.claude/.state"
mkdir -p "$state" 2>/dev/null || exit 0
out="$state/audit.jsonl"

# 手拼 JSON 要求转义：反斜杠在前，引号其次，换行最后。顺序反了会二次转义。
esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
line=$(printf '{"ts":"%s","tool":"%s","target":"%s","agent_id":"%s","agent_type":"%s","session_id":"%s"}' \
  "$ts" "$(esc "$tool")" "$(esc "$(printf '%s' "$target" | cut -c1-500)")" \
  "$(esc "$(jget agent_id "$input")")" "$(esc "$(jget agent_type "$input")")" \
  "$(esc "$(jget session_id "$input")")")

# flock 保证多 hook 并行时不写坏行。没有 flock 就退化成裸追加——
# 单行且短于 PIPE_BUF 的写入在 Linux 上本身是原子的。
if command -v flock >/dev/null 2>&1; then
  ( flock 9; printf '%s\n' "$line" >> "$out" ) 9>>"$out" 2>/dev/null || exit 0
else
  printf '%s\n' "$line" >> "$out" 2>/dev/null || exit 0
fi

# 永不放行失败之外的东西：exit 0，无 stdout，无决策
exit 0
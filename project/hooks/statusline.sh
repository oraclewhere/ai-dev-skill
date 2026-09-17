#!/usr/bin/env bash
# ai-dev-flow · 状态栏 —— 「预测离职」的仪表盘
#
# 方法论原文：AI 不会突然离职，我们可以通过它的上下文来预测它什么时候会离职。
# 状态栏就是把这句话变成肉眼可见的东西：上下文百分比 + 当前任务 + 未结任务数。
#
# 注意 context_window.current_usage 在首次 API 调用前、以及 /compact 之后会是 null，
# used_percentage 早期也可能为 null——都要兜住，否则状态栏会显示 NaN 或报错。

set -uo pipefail

_lib="$(dirname "$0")/_lib.sh"
if [ -f "$_lib" ]; then . "$_lib"; fi

input=$(cat)
cwd=$(jget workspace.project_dir "$input")
[ -z "$cwd" ] && cwd=$(jget cwd "$input")
[ -z "$cwd" ] && cwd="."

pct=$(jget context_window.used_percentage "$input")
case "$pct" in
  ''|null|*[!0-9.]*) pct="" ;;
  *)
    # 截断而不是四舍五入：宁可少报，也不要让 69.6 显示成 70 而误触发交接警告
    pct=${pct%%.*}
    [ -z "$pct" ] && pct=0
    ;;
esac

# 当前任务：SessionStart 写入；读不到就留空
task=""
if [ -f "$cwd/.claude/.state/current-task" ]; then
  task=$(head -1 "$cwd/.claude/.state/current-task" 2>/dev/null | tr -d '\r\n')
fi

# 未结任务：直接数文件状态，不依赖索引是否被维护（索引会漂，文件不会）
open=0
if [ -d "$cwd/doc/任务记录" ]; then
  for f in "$cwd"/doc/任务记录/task-*.md; do
    [ -f "$f" ] || continue
    st=$(awk -F': *' '/^status:/{print $2; exit}' "$f" 2>/dev/null | tr -d '\r')
    case "$st" in todo|doing|review) open=$((open + 1)) ;; esac
  done
fi

branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
      || git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)

# 上下文越接近上限越需要提醒——默认 handoff_at 是 70%
if [ -z "$pct" ]; then
  ctx_part="上下文 ·"
elif [ "$pct" -ge 70 ]; then
  ctx_part="上下文 ${pct}% ⚠"
else
  ctx_part="上下文 ${pct}%"
fi

printf '%s · %s · 未结 %d' "$ctx_part" "${task:-无任务}" "$open"
[ -n "$branch" ] && printf ' · %s' "$branch"
printf '\n'

exit 0
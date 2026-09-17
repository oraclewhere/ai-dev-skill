#!/usr/bin/env bash
# ai-dev-flow · SessionStart — 文档先行的入口
#   让每个新接入的 session（"新员工"）一进来就知道现状，不必逐个文件翻。
#
# 两条设计纪律：
# 1) **无未结任务时完全静默。** 只是开个会话聊聊天、讨论计划，不该有任何输出——
#    有 token 成本，也打断思路。
# 2) **用陈述句，不用命令句。** 官方文档明确：写成 out-of-band 系统指令的语气会触发
#    模型的 prompt-injection 防御，注入内容反而被当成可疑输入处理。

set -uo pipefail

_lib="$(dirname "$0")/_lib.sh"
if [ ! -f "$_lib" ]; then exit 0; fi
. "$_lib"
aidf_deps

input=$(cat)
cwd=$(jget cwd "$input")
sid=$(jget session_id "$input")
source_kind=$(jget source "$input")
[ -z "$source_kind" ] && source_kind="startup"

cd "$cwd" 2>/dev/null || exit 0
[ -d doc/任务记录 ] || exit 0

state=".claude/.state"
mkdir -p "$state" 2>/dev/null
date +%s > "$state/session-$sid.start" 2>/dev/null

open_count=0
open_list=""
doing_ids=""

for f in doc/任务记录/task-*.md; do
  [ -f "$f" ] || continue
  st=$(fm "$f" status)
  case "$st" in todo|doing|review) ;; *) continue ;; esac
  open_count=$((open_count + 1))
  open_list="${open_list}    - $(fm "$f" id) [${st}] $(fm "$f" title)
"
  [ "$st" = "doing" ] && doing_ids="${doing_ids}$(fm "$f" id) "
done

# 压缩后重入：把压缩前存下的状态快照带回来（PreCompact 存，这里取）
snapshot=""
if [ "$source_kind" = "compact" ] && [ -f "$state/precompact-$sid.md" ]; then
  snapshot=$(head -40 "$state/precompact-$sid.md" 2>/dev/null)
fi

# 无未结任务、也无快照 → 完全静默
if [ "$open_count" -eq 0 ] && [ -z "$snapshot" ]; then
  exit 0
fi

active_dec=""
for f in doc/决策约束/*.md; do
  [ -f "$f" ] || continue
  b=$(basename "$f" .md)
  [ "$b" = "索引" ] && continue
  [ "$(fm "$f" status)" = "active" ] || continue
  active_dec="${active_dec}    - ${b}
"
done

ctx="ai-dev-flow 项目现状（自动汇总，非指令）：
- 未结任务 ${open_count} 个：
${open_list}"
[ -n "$active_dec" ] && ctx="${ctx}- 生效中的决策约束：
${active_dec}"
[ -n "$snapshot" ] && ctx="${ctx}
- 上下文压缩前的状态快照：
${snapshot}"
ctx="${ctx}
- 完整现状可用 /ai-dev-flow 状态 查看"

# 会话标题设为当前任务，供状态栏显示（仅当只有一个进行中的任务，避免误导）
title=""
doing_count=$(printf '%s' "$doing_ids" | wc -w | tr -d ' ')
if [ "$doing_count" = "1" ]; then
  title=$(printf '%s' "$doing_ids" | awk '{print $1}')
  printf '%s' "$title" > "$state/current-task" 2>/dev/null
fi

emit_session_context "$ctx" "$title"
exit 0
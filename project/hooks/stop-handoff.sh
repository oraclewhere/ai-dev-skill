#!/usr/bin/env bash
# ai-dev-flow · Stop — 会话结束前的交接催办
#
# 为什么交接挂在 Stop 上：
#   PreCompact 无法让模型产出文档（只能阻断压缩，有风险），SessionStart 只能在事后补救。
#   **Stop 是唯一能让模型继续一次、从而真的把交接文档写出来的机制。**
#
# 为什么必须节流：
#   每轮都拦的 hook 会训练用户关掉它。所以本 hook 每个 session 最多触发一次（marker 文件），
#   且触发条件必须是客观事实，不是"感觉差不多该交接了"。
#
# 触发条件（三条同时成立）：
#   1. 本次会话有提交触及 code/
#   2. 该提交引用的任务记录，「交接说明」一节为空
#   3. 本 session 尚未催办过

set -uo pipefail

_lib="$(dirname "$0")/_lib.sh"
if [ ! -f "$_lib" ]; then exit 0; fi
. "$_lib"
aidf_deps

input=$(cat)
cwd=$(jget cwd "$input")
sid=$(jget session_id "$input")
already=$(jget stop_hook_active "$input")

# 已在续跑中就不重复催办，避免与 Claude Code 的 8 次上限保护打架
[ "$already" = "true" ] && exit 0

cd "$cwd" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

state=".claude/.state"
marker="$state/handoff-prompted-$sid"
[ -f "$marker" ] && exit 0

start_file="$state/session-$sid.start"
[ -f "$start_file" ] || exit 0
started=$(cat "$start_file" 2>/dev/null)
case "$started" in ''|*[!0-9]*) exit 0 ;; esac

# 条件 1：本会话有提交触及 code/
# --since 用 started-1：会话开始时写时间戳、紧接着就提交的同一秒内，
# 严格比较会把刚产生的提交漏掉，交接催办就永远不会触发。
commits=$(git log --since="@$((started - 1))" --format=%H -- code/ 2>/dev/null | head -20)
[ -z "$commits" ] && exit 0

# 找最近一条引用了任务记录的提交
id=""
for sha in $commits; do
  m=$(git log -1 --format=%B "$sha" 2>/dev/null)
  cand=$(printf '%s' "$m" | grep -oE 'task-[0-9]{4}' | head -1)
  if [ -n "$cand" ]; then id="$cand"; break; fi
done
[ -z "$id" ] && exit 0

tf=$(task_file "$id")
[ -z "$tf" ] && exit 0

# 条件 2：交接说明为空
if section_empty "$tf" "交接说明"; then
  touch "$marker" 2>/dev/null
  reason="本次会话已经在 code/ 下提交了改动，但 ${id} 的「交接说明」一节还是空的。

规范要求：session 是高离职率的员工，交接不是离职前的临时整理，而是默认工作方式。
下一个 session 是新人——它读不到本次对话，只能读文档。现在不写，这次会话积累的上下文
（试过哪些路、卡在哪、下一步该做什么）就随上下文一起消失了。

请现在填写 ${tf} 的「交接说明」一节，四个字段都要：
  - 当前进度
  - 已完成
  - 未完成 / 下一步（可直接执行的具体动作）
  - 踩过的坑（试过但走不通的路，避免下一个人重走）

写完后直接结束即可，本次不会再提醒。也可以直接说\"跳过\"，本次会话不再催办。

（这是每个 session 最多触发一次的提醒。）"

  if [ -n "$AIDF_PY" ]; then
    "$AIDF_PY" -c 'import json,sys
print(json.dumps({"decision":"block","reason":sys.argv[1]}, ensure_ascii=False))' "$reason"
  else
    "$AIDF_JQ" -n --arg r "$reason" '{decision:"block", reason:$r}'
  fi
  exit 0
fi

exit 0
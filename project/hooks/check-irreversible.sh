#!/usr/bin/env bash
# ai-dev-flow · PreToolUse(Bash) — 团队模式：不可逆动作
#
# 判据是「这个动作在不在清单里」，不是「这次改动大不大」。
# 门槛是判断（"大到就停"），清单是查表（"在集合里就停"）——集合有限、预先写、客观。
#
# 只拦 subagent（有 agent_id 的那种）。主会话不拦，因为主会话是人所在的地方。
# 这个划分是刻意的：无人值守跑的角色不能 push，而人自己要 push 时不该被挡。
#
# 一处诚实说明：
#   清单里的动作只有一部分能被稳定地机械识别（push、删数据、动凭证）。
#   像"调用真实支付网关"这种，detect 信号依赖项目自己的知识，本脚本把它交给
#   决策约束里的 detect 字段（固定字符串匹配）。写不出来的那些，
#   只能靠"保守默认 = 不做"这条软规则——这是能力的边界，不假装。

set -uo pipefail

_lib="$(dirname "$0")/_lib.sh"
if [ ! -f "$_lib" ]; then exit 0; fi
. "$_lib"
aidf_deps

input=$(cat)

# 只对 subagent 生效
agent_id=$(jget agent_id "$input")
[ -z "$agent_id" ] && exit 0
agent_type=$(jget agent_type "$input")

cmd=$(jget tool_input.command "$input")
[ -z "$cmd" ] && exit 0

cwd=$(jget cwd "$input")
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null && { [ -d doc/任务记录 ] || exit 0; }

hit=""

# 内置：push 是清单里最无争议的一个，且零误判
case "$cmd" in
  *"git push"*|*"git "*"push"*) hit="git push（推送远端）" ;;
esac

# 项目自己在决策约束里写的 detect 信号。固定字符串匹配——
# 不当作正则，避免人写的模式意外匹配到一切。
if [ -z "$hit" ] && [ -d doc/决策约束 ]; then
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    # detect 的值可能带引号或行尾注释，取第一段
    p=$(printf '%s' "$pat" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr -d '"')
    [ -z "$p" ] && continue
    case "$cmd" in *"$p"*) hit="$p（决策约束里登记的不可逆动作）"; break ;; esac
  done <<EOF
$(cat doc/决策约束/*.md 2>/dev/null | awk '
  /^[[:space:]]*detect:[[:space:]]*/ {
    d = $0; sub(/^[[:space:]]*detect:[[:space:]]*/, "", d); print d
  }')
EOF
fi

[ -z "$hit" ] && exit 0

emit_deny "【不可逆动作】${agent_type:-本角色} 试图执行：${hit}

规范：不可逆动作必须由人触发。团队运行时（无人值守）遇到它就保守默认**不做**，
入队等人回来。

为什么用清单而不是门槛：门槛是"改动大到就停"，那是个判断，要么由 AI 判
（等于让它划自己的监管边界），要么由人判（人还是得在场）。
清单是"在不在这个集合里"，集合有限、预先写、客观——查表，不是判断。

请这样做：
  1. 若这是任务真的需要的 → 记一条待批项（doc/待批/），人回来时批
  2. 若只是验证用途 → 用 mock / dry-run / 本地环境替代
  3. 若你确信人已经授权了这一步 → 交回主会话，由人自己执行

命令：${cmd}"

exit 0
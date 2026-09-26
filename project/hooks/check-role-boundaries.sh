#!/usr/bin/env bash
# ai-dev-flow · PreToolUse(Write|Edit) — 团队模式：角色边界
#
# 两条边界，均由 agent_type 与路径决定，不含判断：
#   1. code/ 的写权限是**白名单**：只有 impl-* 能写（主会话不受限）
#   2. doc/决策约束/ 的 draft → active 只有人能翻（硬规则 4）
#
# 关于第 1 条为什么是白名单而不是黑名单：
#   黑名单只能枚举"谁不能写"，而派发出来的工人是动态的——
#   manager 可以派任意名字的 subagent，黑名单永远列不全，
#   于是"能写码"这件事会静默地扩散到所有没被列进去的角色身上。
#   白名单把问题反过来：**卡名以 impl- 开头才是可写的唯一凭据**，
#   于是"谁在写码"变成一次前缀查表，角色边界才真正机械可查。
#
#   它有代价，代价是刻意的：随便派个通用 subagent 去改代码会被拦。
#   正确做法是派 impl-* 卡——这也正是"每个角色一张卡"的意义。
#
# 关于第 2 条的一条诚实说明：
#   agent_id 只在 subagent 调用里存在，所以这道检查拦的是**subagent**。
#   主会话没有 agent_id，因此不被拦——这是刻意的：主会话是人所在的地方。
#   残留缺口是"主会话自己把 status 翻成 active"，它由两件事兜住：
#   团队声明卡明令禁止，以及 log-event.sh 把每一次对决策约束的写入都记下来。
#   ——不是禁止判断，而是禁止不可见的判断。

set -uo pipefail

_lib="$(dirname "$0")/_lib.sh"
if [ ! -f "$_lib" ]; then exit 0; fi
. "$_lib"
aidf_deps

input=$(cat)
fp=$(jget tool_input.file_path "$input")
[ -z "$fp" ] && fp=$(jget tool_input.notebook_path "$input")
[ -z "$fp" ] && exit 0

cwd=$(jget cwd "$input")
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

agent_id=$(jget agent_id "$input")
agent_type=$(jget agent_type "$input")

case "$fp" in
  */code/*|code/*) in_code=1 ;;
  *)               in_code=0 ;;
esac
case "$fp" in
  */doc/决策约束/*|doc/决策约束/*) in_adr=1 ;;
  *) in_adr=0 ;;
esac

# ---- 1. code/ 白名单 ---------------------------------------------------------
# 只在 subagent 调用上生效：主会话是人所在的地方，人要能自己改代码。
if [ "$in_code" -eq 1 ] && [ -n "$agent_id" ]; then
  case "$agent_type" in
    impl-*) exit 0 ;;
    test-manager|test-worker|test-*)
      emit_deny "${agent_type} 不得写 code/ 下的文件：${fp}

规范：测试角色是裁判，不能兼运动员。发现代码有问题 → 写进报告 + 走「决策记录」，
由 develop-manager 退回给对应的 impl-worker 改。

为什么这条是硬限制：让测试通过的最快路径永远是改代码，而这条路径会
把"测试发现问题"这个信号直接抹掉——报告一片绿，问题进了下游。

测试产物请写在 tests/ 下（测试与源码分开，这条边界才机械可查）。"
      exit 0 ;;
    develop-manager)
      emit_deny "develop-manager 不得写 code/ 下的文件：${fp}

规范：你不直接负责写代码——这是结构，不是纪律。
code/ 的写权限白名单里只有 impl-*，所以你写不了；这正是设计意图：
把"它不再直接负责写代码"从承诺变成做不到的事。

该你做的是：先把接口文档写清楚（doc/交付件/<task>-接口.md），
再派 impl-* 工人去实现，然后按接口文档对接它们的结果。

若你认为这里必须由你亲手改，通常说明有一件事没被切分成可派发的部分——
走「决策记录」，说明为什么切不开。"
      exit 0 ;;
    requirements-analyst|rule-manager|designer|secretary)
      emit_deny "${agent_type} 不得写 code/ 下的文件：${fp}

规范：每个角色的产出边界由它的身份卡定义——
  需求分析师 → 尽调文档与决策约束草稿
  rule-manager → 裁决记录与监护报告
  设计师     → 设计交付件
  秘书       → 队列与索引
  develop-manager → 接口文档与交付件（派 impl-* 去写码）
  impl-*     → code/ 与交付件（唯一可写 code/ 的角色）
  test-*     → tests/ 与测试证据

${agent_type} 的产物是文档，不是代码。若你认为这里必须改代码，
说明有一件事没被分派到正确的角色——走「决策记录」，不要越界动手。"
      exit 0 ;;
    *)
      emit_deny "角色「${agent_type:-（无 agent_type）}」不在 code/ 的写权限白名单里：${fp}

规范：code/ 只有 impl-* 卡能写（主会话不受限）。

这不是"漏配了权限"，而是这套边界能成立的前提：
派发出来的工人名字是动态的，若不用「卡名前缀」做凭据，
"谁在写码"就不可机械判定，角色边界只能退回写在纸上的承诺。

请这样做（任选）：
  1. 把这次改动派给 impl-worker（或你已定义的 impl-<域> 卡）——推荐
  2. 若这确实需要一张新的专用工人卡，建一张名为 impl-<域> 的卡（放进 .claude/agents/）
  3. 若你认为这条边界本身有问题 → 走「决策记录」，由 rule-manager 或人定
     （不要靠改卡名绕过去：卡名是这条边界的全部凭据，改名等于关掉检查。）
  4. 若这是人自己在改 → 由人在主会话里改，主会话不受此限制。"
      exit 0 ;;
  esac
fi

# ---- 2. 决策约束：只有人能翻 draft -> active ---------------------------------
if [ "$in_adr" -eq 1 ] && [ -n "$agent_id" ]; then
  new=$(jget tool_input.content "$input")
  [ -z "$new" ] && new=$(jget tool_input.new_string "$input")

  # 只有"新内容里出现 status: active"时才继续查，避免无关编辑被误伤
  if printf '%s\n' "$new" | grep -qE '^status:[[:space:]]*active'; then
    cur=""
    [ -f "$fp" ] && cur=$(fm "$fp" status)
    if [ "$cur" = "draft" ]; then
      emit_deny "试图把 ${fp} 的 status 从 draft 改成 active。

规范（硬规则 4）：doc/决策约束/ 由人维护，AI 只读；status 由 draft 翻成 active
必须由人来做。

理由：决策约束是授权与约束的唯一来源，而 check-queue.sh 只认 active 的授权。
如果 AI 能自己把草稿改成生效，那它就能给自己发授权——
"冻结"这个动作和尽调期的所有确认会一起失去意义。

请这样做：把这份草稿和它的待确认点整理好交给人（经主会话），由人翻。
人翻过之后，本 hook 不再拦。
（若你确信是人让你翻的，也请让人自己执行——这一步的存在本身就是它的价值。）"
      exit 0
    fi
  fi
fi

exit 0
#!/usr/bin/env bash
# ai-dev-flow · PreToolUse(Bash) — 团队模式：分支粒度 = 任务粒度
#   新建分支时，分支名必须含 task-NNNN，且该任务记录真实存在。
#
# 为什么必须有这条：
#   团队模式要求"开发变动必须走分支，且每个分支要有它实现的需求的描述"。
#   分支名带 task-NNNN 之后，"这个分支实现了什么需求"就有了唯一答案，
#   而且能直接复用 check-commit.sh 已有的 ID 提取与伪引用检查，不引入新格式。
#
# 关键词是**一个分支一个任务**：跨任务的分支会让上面那个问题不可判定。

set -uo pipefail

_lib="$(dirname "$0")/_lib.sh"
if [ ! -f "$_lib" ]; then exit 0; fi
. "$_lib"
aidf_deps

input=$(cat)
cmd=$(jget tool_input.command "$input")
cwd=$(jget cwd "$input")

# 归一化 git -C <路径>，必须在守卫之前（同 check-commit.sh 的理由：
# `git -C /repo checkout -b x` 里不含 "git checkout" 这个子串，先守卫就是死代码）
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+-C[[:space:]]'; then
  cwd=$(printf '%s' "$cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+("[^"]+"|[^[:space:]]+).*/\1/p' | head -1 | tr -d '"')
fi
cmdx=$(printf '%s' "$cmd" | sed -E 's/git[[:space:]]+-C[[:space:]]+("[^"]+"|[^[:space:]]+)/git/')

case "$cmdx" in
  *"git checkout"*|*"git switch"*|*"git branch"*) ;;
  *) exit 0 ;;
esac

[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 只对"启用了规范的项目"生效。没跑过 install.sh project 的项目里没有 doc/任务记录/，
# 不该被这套规则拦——否则在别人的仓库里随手建个分支都会被拒。
[ -d "doc/任务记录" ] || exit 0

# 提取新分支名。三种写法：checkout -b/-B、switch -c/--create、branch <name>
nb=$(printf '%s' "$cmdx" | sed -nE 's/.*git[[:space:]]+(checkout|switch)[[:space:]]+(-b|-B|-c|--create)[[:space:]]+("[^"]+"|[^[:space:]]+).*/\3/p' | head -1 | tr -d '"')
if [ -z "$nb" ]; then
  nb=$(printf '%s' "$cmdx" | sed -nE 's/.*git[[:space:]]+branch[[:space:]]+("[^"]+"|[^[:space:]]+).*/\1/p' | head -1 | tr -d '"')
fi

# 空 = 只切换/列举，不是新建；以 - 开头 = 是选项（git branch -a / -d x），不是分支名
[ -z "$nb" ] && exit 0
case "$nb" in -*) exit 0 ;; esac

id=$(printf '%s' "$nb" | grep -oE 'task-[0-9]{4}' | head -1)

if [ -z "$id" ]; then
  emit_deny "分支名「${nb}」未包含任务记录 ID。

规范：开发变动必须走分支，且分支名必须含 task-NNNN（一个分支一个任务）。
理由：分支名带 ID 之后，「这个分支实现了什么需求」有了唯一答案，
合并时也能直接查到这个任务的交付件——这是硬规则 3 的第一道铺垫。

请这样做：
  1. 若这是新需求 → 先建任务记录，拿到 task-NNNN，再用 task-NNNN-<简短描述> 建分支
  2. 若属于既有任务 → 查 doc/任务记录/索引.md 用正确的 ID
  3. 若只是临时试一下、不属于交付链 → 在 code/ 之外做，或先在工作区验证再建分支"
  exit 0
fi

# 伪引用检查：ID 有，但任务记录不存在。
# 与 check-commit.sh 同款理由——用一个不存在的 ID 通过校验不叫遵守规范，叫绕过校验。
tf=$(task_file "$id")
if [ -z "$tf" ]; then
  emit_deny "分支名引用了 ${id}，但 doc/任务记录/ 下不存在这个任务记录。

这属于伪引用——用一个不存在的 ID 通过校验。

请这样做：
  1. 若 ${id} 是临时编的 → 先真创建一个任务记录
  2. 若记错了 ID → 查 doc/任务记录/索引.md 用正确的 ID 重试"
  exit 0
fi

exit 0
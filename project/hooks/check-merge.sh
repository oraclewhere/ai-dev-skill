#!/usr/bin/env bash
# ai-dev-flow · PreToolUse(Bash) — 硬规则 3
#   合并到发布分支时，必须关联到 doc/决策约束/ 或 doc/交付件/ 下的文件。
#
# 判定有两条通路，满足其一即可：
#   A. merge message（或命令本身）引用了 doc/决策约束/… 或 doc/交付件/… 下的文件
#   B. 被合入的提交里，至少有一个引用的任务记录的 deliverables 字段非空
#
# 通路 B 存在的原因：人常常只写 `git merge feature --no-edit`，此时没有可检查的 message，
# 而"这条分支上的工作确实产出了交付件"本身就是一个合理的合规证据。

set -uo pipefail

_lib="$(dirname "$0")/_lib.sh"
if [ ! -f "$_lib" ]; then
  printf 'ai-dev-flow: 缺少 %s，规范未完整安装，本次校验跳过。\n' "$_lib" >&2
  exit 0
fi
. "$_lib"
aidf_deps

input=$(cat)
cmd=$(jget tool_input.command "$input")
cwd=$(jget cwd "$input")

# 归一化 git -C <路径>，必须在下面那道守卫**之前**做。
# 守卫匹配的是字面量 "git merge"，而 `git -C /repo merge x` 里不含这个子串——
# 先守卫就等于把 -C 分支写成死代码。这个顺序问题是自测里那条 -C 用例抓出来的：
# 它在第一次运行时就红了，而代码读起来完全正常。
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+-C[[:space:]]'; then
  cwd=$(printf '%s' "$cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+("[^"]+"|[^[:space:]]+).*/\1/p' | head -1 | tr -d '"')
fi
cmdx=$(printf '%s' "$cmd" | sed -E 's/git[[:space:]]+-C[[:space:]]+("[^"]+"|[^[:space:]]+)/git/')

case "$cmdx" in
  *"git merge"*) ;;
  *) exit 0 ;;
esac

[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

branch=$(current_branch)
is_release_branch "$branch" || exit 0

# 通路 A：message 直接引用 doc 文件
if printf '%s' "$cmdx" | grep -qE 'doc/(决策约束|交付件)/'; then
  exit 0
fi

# 提取被合入的分支/引用（跳过选项参数）
src=$(printf '%s' "$cmdx" | sed -nE 's/.*git[[:space:]]+merge[[:space:]]+((-[^[:space:]]+[[:space:]]+)*)([^[:space:]]+).*/\3/p' | head -1)
src=${src%%[\;\&\|]*}

# 通路 B：被合入的提交引用的任务有交付件
if [ -n "$src" ] && git rev-parse --verify --quiet "$src" >/dev/null 2>&1; then
  for sha in $(git rev-list "HEAD..$src" 2>/dev/null | head -50); do
    m=$(git log -1 --format=%B "$sha" 2>/dev/null)
    tid=$(printf '%s' "$m" | grep -oE 'task-[0-9]{4}' | head -1)
    [ -z "$tid" ] && continue
    tf=$(task_file "$tid")
    [ -z "$tf" ] && continue
    # deliverables 非空即算数。要同时支持两种写法：
    #   同行：  deliverables: [a, b]
    #   块状：  deliverables:\n  - a\n  - b
    if awk '
         /^deliverables:/ {
           v = $0; sub(/^deliverables:[[:space:]]*/, "", v)
           if (v != "") { print v; exit }   # 同行写法
           d = 1; next
         }
         d && /^[a-zA-Z_]+:/ { exit }
         d { print }
       ' "$tf" | tr -d '[] ' | grep -q '[^ ]'; then
      exit 0
    fi
  done
fi

emit_deny "即将把改动合并进发布分支 ${branch}，但未能确认它关联到决策约束或交付件。

规范（硬规则 3）：code 的每次合并到发布分支，必须关联到 doc/决策约束/ 或 doc/交付件/ 下的文件。
理由：合并到发布分支是最后一道节点，偏差一旦过去就进入下游了。这里必须能回答
「这批改动对应哪份交付件」和「依据哪条决策」。

请这样做其中一件：
  1. 在 merge message 里引用对应的文档，例如：
     git merge ${src:-<branch>} -m \"合并 <功能> — 见 doc/交付件/<xxx>.md\"
  2. 若被合入的提交引用的任务还没有交付件 → 先执行 /ai-dev-flow 验收 并补上交付件文档
  3. 若这不是发布分支合并 → 确认分支命名，当前被判定为发布分支的是：${branch}

当前分支：${branch}"

exit 0
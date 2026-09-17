#!/usr/bin/env bash
# ai-dev-flow · PreToolUse(Bash) — 硬规则 2
#   向 code/ 的每次提交，commit message 必须含 task-NNNN，且该任务记录真实存在。
#
# 三个设计要点：
# 1) 不依赖 settings.json 里 if 字段的匹配。官方文档明确 if 是 best-effort 且 fails open
#    （无法判断命令内容时会放行），所以匹配必须在本脚本内再做一次精确检查。
# 2) 用 git 自己判断"本次提交是否触及 code/"，而不是解析命令字符串。
# 3) 同时校验任务记录是否存在。只查 ID 格式不够：模型完全可能写一个不存在的 ID
#    来通过校验——那不叫遵守规范，叫绕过校验。

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

case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# 支持 git -C <path> commit
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+-C[[:space:]]'; then
  cwd=$(printf '%s' "$cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+("[^"]+"|[^[:space:]]+).*/\1/p' | head -1 | tr -d '"')
fi
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 本次提交是否触及交付链
staged=$(git diff --cached --name-only 2>/dev/null)
printf '%s\n' "$staged" | grep -qE '^code/' || exit 0

# 提取提交信息：heredoc > -m 参数 > 整条命令
msg=""
if printf '%s' "$cmd" | grep -q '<<'; then
  msg=$(printf '%s' "$cmd" | sed -n '/<</,$p')
fi
if [ -z "$msg" ]; then
  msg=$(printf '%s' "$cmd" | grep -oE '\-m[[:space:]]+.*' || true)
fi
[ -z "$msg" ] && msg="$cmd"

id=$(printf '%s' "$msg" | grep -oE 'task-[0-9]{4}' | head -1)

if [ -z "$id" ]; then
  files=$(printf '%s\n' "$staged" | grep -E '^code/' | head -10 | sed 's/^/    /')
  emit_deny "本次提交改动了 code/ 下的文件，但 commit message 未引用任务记录 ID。

规范（硬规则 2）：向 code/ 的每一次提交，必须关联到一个存在的任务记录。

请这样做其中一件：
  1. 若这是一个新需求 → 先用 /ai-dev-flow 启动 <需求描述> 创建任务记录，拿到 task-NNNN
  2. 若属于某个既有任务 → 先查 doc/任务记录/索引.md，用正确的 ID 重试
  3. 若这批改动其实不属于交付链（临时脚本、验证用代码）→ 把它们移到 scripts/ 下。
     规范按目录路径豁免，code/ 之外不需要关联任务。

本次 staged 且位于 code/ 的文件：
${files}"
  exit 0
fi

# 伪引用检查：ID 有，但任务记录不存在
tf=$(task_file "$id")
if [ -z "$tf" ]; then
  emit_deny "commit 引用了 ${id}，但 doc/任务记录/ 下不存在这个任务记录。

这属于伪引用——用一个不存在的 ID 通过校验。校验机制不能靠\"看起来对\"来满足。

请这样做其中一件：
  1. 若 ${id} 是临时编的 → 用 /ai-dev-flow 启动 真创建一个任务记录
  2. 若记错了 ID → 查 doc/任务记录/索引.md 用正确的 ID 重试"
  exit 0
fi

exit 0
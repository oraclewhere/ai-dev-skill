#!/usr/bin/env bash
# ai-dev-flow · PreCompact — 压缩前把机器可读的状态落盘
#
# 为什么不是"强制生成交接文档"：
#   官方文档确认 PreCompact **无法注入指令或摘要引导**，只能阻断压缩（decision:"block" / exit 2）。
#   而阻断压缩有真实风险：若压缩是为恢复上下文超限错误而触发的，阻断会让当前请求直接失败。
#   所以本 hook 不阻断，只做它真正做得到的事——在上下文丢失前把外部状态写到磁盘，
#   由 SessionStart(source=compact) 在压缩后重新注入。
#
# 这样即使交接文档没来得及写，会话的关键状态也不会随上下文一起蒸发。

set -uo pipefail

_lib="$(dirname "$0")/_lib.sh"
if [ ! -f "$_lib" ]; then exit 0; fi
. "$_lib"
aidf_deps

input=$(cat)
cwd=$(jget cwd "$input")
sid=$(jget session_id "$input")
trigger=$(jget trigger "$input")
[ -z "$trigger" ] && trigger="unknown"

cd "$cwd" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

state=".claude/.state"
mkdir -p "$state" 2>/dev/null

{
  echo "# 压缩前状态快照"
  echo "时间：$(date -Iseconds)"
  echo "触发方式：${trigger}"
  echo
  echo "## 工作区未提交改动"
  git status --porcelain 2>/dev/null | head -30
  echo
  echo "## 最近提交"
  git log --oneline -10 2>/dev/null
  echo
  echo "## 未结任务"
  for f in doc/任务记录/task-*.md; do
    [ -f "$f" ] || continue
    st=$(fm "$f" status)
    case "$st" in todo|doing|review) ;; *) continue ;; esac
    echo "  - $(fm "$f" id) [${st}] $(fm "$f" title)"
  done
  echo
  echo "## 参考资料"
  echo "压缩前的完整对话在 transcript 中：$(jget transcript_path "$input")"
} > "$state/precompact-$sid.md" 2>/dev/null

# 不阻断压缩，不输出任何决定
exit 0
#!/usr/bin/env bash
# ai-dev-flow · hook 共享库
#
# 存在的理由：hook 需要解析输入 JSON，而 jq **不是**每台机器都有（本机就没有）。
# 原来只用 jq 的写法会让所有校验静默失效——规范在纸上存在、在运行时不存在，
# 这是本方法论最不能接受的一种失败。所以这里做两件事：
#   1. 依赖探测：python3 优先，jq 回退，二者都无则**显式报警**而不是静默跳过
#   2. 把 JSON 读写和文档解析收在一处，避免同一处修五次

# ---- 依赖探测 -------------------------------------------------------------
AIDF_PY="$(command -v python3 || command -v python || true)"
AIDF_JQ="$(command -v jq || true)"

aidf_deps() {
  if [ -z "$AIDF_PY" ] && [ -z "$AIDF_JQ" ]; then
    printf 'ai-dev-flow: 需要 python3 或 jq 之一来解析 hook 输入，两者都没找到。\n' >&2
    printf 'ai-dev-flow: 本次校验跳过——注意这意味着规则暂时没有生效。\n' >&2
    exit 0
  fi
}

# ---- JSON 读 --------------------------------------------------------------
# jget <点号路径> <json字符串>
jget() {
  if [ -n "$AIDF_PY" ]; then
    printf '%s' "$2" | "$AIDF_PY" -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
for k in sys.argv[1].split("."):
    d = d.get(k) if isinstance(d, dict) else None
    if d is None:
        break
print("" if d is None else d)
' "$1" 2>/dev/null
  else
    printf '%s' "$2" | "$AIDF_JQ" -r ".$1 // \"\"" 2>/dev/null
  fi
}

# ---- JSON 写 --------------------------------------------------------------
# aidf_json <python风格的对象字面量> —— 交给解释器做转义，避免手拼 JSON 出错
aidf_json() {
  if [ -n "$AIDF_PY" ]; then
    "$AIDF_PY" -c "import json,sys; print(json.dumps($1))" 2>/dev/null
  else
    "$AIDF_JQ" -n "$1" 2>/dev/null
  fi
}

# 拒绝一次工具调用（reason 会被 Claude 看到，这是放纠正指令的地方）
# ensure_ascii=False：中文直接输出 UTF-8，便于人直接看懂 hook 日志与调试输出
emit_deny() {
  if [ -n "$AIDF_PY" ]; then
    "$AIDF_PY" -c 'import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.argv[1]}}, ensure_ascii=False))' "$1"
  else
    "$AIDF_JQ" -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  fi
}

# 会话开始注入上下文；$2 为可选会话标题
emit_session_context() {
  if [ -n "$AIDF_PY" ]; then
    "$AIDF_PY" -c 'import json,sys
o={"hookEventName":"SessionStart","additionalContext":sys.argv[1]}
if len(sys.argv)>2 and sys.argv[2]:
    o["sessionTitle"]=sys.argv[2]
print(json.dumps({"hookSpecificOutput":o}, ensure_ascii=False))' "$1" "${2:-}"
  else
    if [ -n "${2:-}" ]; then
      "$AIDF_JQ" -n --arg c "$1" --arg t "$2" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c,sessionTitle:$t}}'
    else
      "$AIDF_JQ" -n --arg c "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
    fi
  fi
}

# ---- 文档解析 -------------------------------------------------------------
# fm <文件> <字段> —— 取 frontmatter 里某个顶层字段的值
fm() {
  awk -F': *' -v k="$2" '$0 ~ "^"k":" {print $2; exit}' "$1" 2>/dev/null | tr -d '\r'
}

# section_empty <文件> <小节标题> —— 返回真（0）表示该小节为空
# 判定规则：忽略空行、引用行、以及模板留下的 `**字段**：` 占位行
#
# 注意 END 的返回值方向：found=1 表示"有内容"，此时要返回**假**（非 0）。
# 这里曾经写反过——结果是交接说明写好之后才催办、没写的时候放行，
# 恰好只在人做对的时候打扰人。自测套件里有对应用例。
section_empty() {
  awk -v sec="$2" '
    $0 ~ "^##[[:space:]]+"sec { inb = 1; next }
    inb && /^##[[:space:]]/ { exit }
    inb {
      l = $0
      gsub(/^[[:space:]]+/, "", l)
      if (l == "") next
      if (l ~ /^>/) next
      if (l ~ /^[-*]?[[:space:]]*\*\*[^*]+\*\*[：:][[:space:]]*$/) next
      found = 1
    }
    END { exit(found ? 1 : 0) }
  ' "$1"
}

# task_file <task-0001> —— 找出对应的任务记录文件
task_file() {
  ls "doc/任务记录/${1}-"*.md "doc/任务记录/${1}.md" 2>/dev/null | head -1
}

# current_branch —— 当前分支名
# 注意：不能用 `git rev-parse --abbrev-ref HEAD`。在还没有任何提交的仓库里（unborn HEAD）
# 它会失败并把字面量 "HEAD" 打到 stdout，导致调用方把 "HEAD" 当成分支名而静默放行。
# symbolic-ref 在 unborn 分支上也能正确返回分支名。
current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# is_release_branch <分支名>
is_release_branch() {
  case "$1" in
    main|master|release/*|release-*|prod|production) return 0 ;;
    *) return 1 ;;
  esac
}
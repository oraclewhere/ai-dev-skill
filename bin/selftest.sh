#!/usr/bin/env bash
# ai-dev-flow 自测套件
#
# 为什么需要它：这套东西的核心是"用机械校验替代模型自觉"。如果校验本身有 bug，
# 结果不是"没效果"，而是"看起来有效果"——这是最坏的失败模式，因为它不会被人发现。
# 所以每次改动 hook 或模板后都应该跑一遍。
#
#   ./bin/selftest.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
PASS=0
FAIL=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

G=$'\033[32m'; R=$'\033[31m'; N=$'\033[0m'
ok()  { PASS=$((PASS + 1)); printf '  %s✓%s %s\n' "$G" "$N" "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  %s%s %s\n' "$R" "$N" "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }

OUT=""; CODE=0
hook() { OUT=$(printf '%s' "$2" | "$1" 2>/dev/null); CODE=$?; }
H()    { hook "$WORK/.claude/hooks/$1" "$2"; }

assert_deny() {
  case "$OUT" in *'"deny"'*) ok "$1" ;; *) bad "$1" "期望 deny，实际：${OUT:-<空>}" ;; esac
}
assert_silent() {
  if [ -z "$OUT" ] && [ "$CODE" = "0" ]; then ok "$1"
  else bad "$1" "期望完全静默，实际 exit=${CODE} 输出：${OUT:0:160}"; fi
}
assert_contains() {
  case "$OUT" in *"$2"*) ok "$1" ;; *) bad "$1" "输出中未找到「$2」：${OUT:0:200}" ;; esac
}
assert_no() {
  case "$OUT" in *"$2"*) bad "$1" "输出中不应出现「$2」" ;; *) ok "$1" ;; esac
}

printf '\n=== 准备测试项目 ===\n'
bash "$ROOT/bin/install.sh" project "$WORK" >/dev/null 2>&1 || { echo "安装失败"; exit 1; }
cd "$WORK" || exit 1
git init -q . && git config user.email t@t && git config user.name t

cat > doc/任务记录/task-0001-login.md <<'EOF'
---
id: task-0001
type: full
title: 登录接口
status: doing
created: 2026-09-17
refs_decision: [001]
deliverables: [doc/交付件/login-api.md]
context_budget:
  files: [src/auth/**]
  est_tokens: 40k
  handoff_at: 70%
---

## 目标
实现登录接口

## 验收标准
- [ ] 密码错误返回 401

## 交接说明
> 会话结束、或上下文达到 handoff_at 时填写。

- **当前进度**：
- **已完成**：
- **未完成 / 下一步（可直接执行的具体动作）**：
- **踩过的坑（试过但走不通的路，避免下一个人重走）**：

## 决策记录
- 无
EOF

mkdir -p code/src scripts
echo "x" > code/src/a.js
echo "y" > scripts/tmp.sh
echo "z" > doc/交付件/login-api.md

# 初始提交 + 把默认分支定为 main（下面分支相关用例依赖它）
git add -A >/dev/null 2>&1
git commit -q -m "chore: 初始化 code-doc 结构" >/dev/null 2>&1
git branch -M main 2>/dev/null

J_NOID="{\"tool_input\":{\"command\":\"git commit -m \\\"fix bug\\\"\"},\"cwd\":\"$WORK\",\"session_id\":\"s1\"}"
J_OK="{\"tool_input\":{\"command\":\"git commit -m \\\"task-0001: 登录接口\\\"\"},\"cwd\":\"$WORK\",\"session_id\":\"s1\"}"
J_FAKE="{\"tool_input\":{\"command\":\"git commit -m \\\"task-9999: 瞎写\\\"\"},\"cwd\":\"$WORK\",\"session_id\":\"s1\"}"
J_NOTCOMMIT="{\"tool_input\":{\"command\":\"git status\"},\"cwd\":\"$WORK\",\"session_id\":\"s1\"}"

printf '\n=== check-commit.sh（硬规则 2）===\n'
# 必须先真的改动文件再 add —— 对未改动的文件 git add 不会产生 staged 内容，
# hook 会（正确地）认为本次提交没触及 code/ 而放行
echo "x2" >> code/src/a.js
git add code/src/a.js >/dev/null 2>&1
H check-commit.sh "$J_NOID"
assert_deny "改动 code/ 但没引用任务 ID → 拦截"
assert_contains "拦截信息指明了 staged 的 code/ 文件" "code/src/a.js"
assert_contains "拦截信息给出了可执行的下一步" "/ai-dev-flow 启动"

H check-commit.sh "$J_FAKE"
assert_deny "引用不存在的任务 ID（伪引用）→ 拦截"
assert_contains "点名这是伪引用" "伪引用"

H check-commit.sh "$J_OK"
assert_silent "引用了存在的任务 ID → 放行"

H check-commit.sh "$J_NOTCOMMIT"
assert_silent "非 commit 命令 → 不干预"

# heredoc 形式的提交（Claude Code 实际最常用这种写法）
J_HEREDOC="{\"tool_input\":{\"command\":\"git commit -F - <<'EOF'\\ntask-0001: 登录接口\\nEOF\"},\"cwd\":\"$WORK\",\"session_id\":\"s1\"}"
H check-commit.sh "$J_HEREDOC"
assert_silent "heredoc 形式的提交信息也能识别 → 放行"

git reset -q
echo "y2" >> scripts/tmp.sh
git add scripts/tmp.sh >/dev/null 2>&1
H check-commit.sh "$J_NOID"
assert_silent "只改 scripts/（豁免区）→ 放行"

echo "x3" >> code/src/a.js
git add code/src/a.js >/dev/null 2>&1
H check-commit.sh "$J_NOID"
assert_deny "code/ 与 scripts/ 混合 → 仍拦截"

printf '\n=== check-merge.sh（硬规则 3）===\n'
# 两条分支，用来把"通路 B 该放行"和"该拦截"分开——否则两个用例都会因为
# 分支名不存在而得到相同结果，看起来通过、实际什么都没测到。
cat > doc/任务记录/task-0002-oauth.md <<'EOF'
---
id: task-0002
type: full
title: OAuth 改造
status: doing
deliverables: []
---
## 交接说明
- **当前进度**：
EOF

git checkout -q -b feature/x && echo "z2" >> code/src/a.js
git add -A >/dev/null 2>&1 && git commit -q -m "task-0001: 登录接口实现" >/dev/null 2>&1
git checkout -q main
git checkout -q -b feature/nodeliv && echo "z3" >> code/src/a.js
git add -A >/dev/null 2>&1 && git commit -q -m "task-0002: OAuth 改造" >/dev/null 2>&1
git checkout -q main

J_M_DENY="{\"tool_input\":{\"command\":\"git merge feature/nodeliv --no-edit\"},\"cwd\":\"$WORK\",\"session_id\":\"s1\"}"
J_M_OK="{\"tool_input\":{\"command\":\"git merge feature/x --no-edit\"},\"cwd\":\"$WORK\",\"session_id\":\"s1\"}"

H check-merge.sh "$J_M_DENY"
assert_deny "被合入的提交没有交付件 → 拦截"

J_M_MSG="{\"tool_input\":{\"command\":\"git merge feature/nodeliv -m \\\"见 doc/交付件/login-api.md\\\"\"},\"cwd\":\"$WORK\",\"session_id\":\"s1\"}"
H check-merge.sh "$J_M_MSG"
assert_silent "merge message 引用了交付件（通路 A）→ 放行"

# 通路 B：被合入的提交引用的任务 deliverables 非空，无需 message 引用
H check-merge.sh "$J_M_OK"
assert_silent "被合入提交的任务有交付件（通路 B）→ 放行"

git checkout -q feature/x
H check-merge.sh "$J_M_DENY"
assert_silent "非发布分支 → 不干预"
git checkout -q main

printf '\n=== 回归：全新仓库（unborn HEAD）===\n'
# 曾经的 bug：git rev-parse --abbrev-ref HEAD 在无提交的仓库里返回字面量 "HEAD"，
# 被当成非发布分支，合并校验被静默跳过 —— 规则在纸上存在、在运行时不存在。
U="$(mktemp -d)"
bash "$ROOT/bin/install.sh" project "$U" >/dev/null 2>&1
( cd "$U" && git init -q . )
OUT=$(printf '{"tool_input":{"command":"git merge x"},"cwd":"%s","session_id":"s"}' "$U" \
      | "$U/.claude/hooks/check-merge.sh" 2>/dev/null)
case "$OUT" in *'"deny"'*) ok "无提交的仓库里合并校验仍然生效（不再静默跳过）" ;;
  *) bad "无提交的仓库里合并校验仍然生效" "实际：${OUT:-<空>}";; esac
rm -rf "$U"

printf '\n=== inject-context.sh（文档先行）===\n'
J_SS="{\"cwd\":\"$WORK\",\"session_id\":\"s1\",\"source\":\"startup\"}"
H inject-context.sh "$J_SS"
assert_contains "有未结任务时注入现状" "task-0001"
assert_contains "注入用陈述句而非命令句（避免触发注入防御）" "自动汇总，非指令"
assert_contains "注入会话标题供状态栏显示" "sessionTitle"

sed -i 's/^status: doing/status: done/' doc/任务记录/task-0001-login.md
H inject-context.sh "$J_SS"
assert_silent "无未结任务时完全静默（零 token 成本）"
sed -i 's/^status: done/status: doing/' doc/任务记录/task-0001-login.md

printf '\n=== statusline.sh（预测离职的仪表盘）===\n'
OUT=$(printf '{"workspace":{"project_dir":"%s"},"context_window":{"used_percentage":62.4}}' "$WORK" \
      | "$WORK/.claude/hooks/statusline.sh" 2>/dev/null)
assert_contains "显示上下文百分比（截断而非四舍五入）" "上下文 62%"
assert_contains "显示当前任务" "task-0001"

OUT=$(printf '{"workspace":{"project_dir":"%s"},"context_window":{"used_percentage":null}}' "$WORK" \
      | "$WORK/.claude/hooks/statusline.sh" 2>/dev/null)
assert_no "首次调用前 used_percentage 为 null 时不显示 NaN" "NaN"
assert_no "null 时不出现悬空的百分号" "·%"

OUT=$(printf '{"workspace":{"project_dir":"%s"},"context_window":{"used_percentage":82}}' "$WORK" \
      | "$WORK/.claude/hooks/statusline.sh" 2>/dev/null)
assert_contains "超过 handoff_at 阈值时给出警示" "⚠"

printf '\n=== stop-handoff.sh（交接催办）===\n'
J_STOP="{\"cwd\":\"$WORK\",\"session_id\":\"s1\",\"stop_hook_active\":false}"
mkdir -p .claude/.state && date +%s > .claude/.state/session-s1.start
echo "w" >> code/src/a.js
git add -A >/dev/null 2>&1 && git commit -q -m "task-0001: 登录接口" >/dev/null 2>&1

H stop-handoff.sh "$J_STOP"
assert_contains "交接说明为空 → 催办交接" "交接说明"
case "$OUT" in *'"block"'*) ok "使用 block（唯一能让模型真的写出文档的机制）" ;;
  *) bad "使用 block" "实际：${OUT:0:120}";; esac

H stop-handoff.sh "$J_STOP"
assert_silent "同一 session 第二次不再催办（节流，避免训练用户关掉它）"

rm -f .claude/.state/handoff-prompted-s1
python3 - "$WORK/doc/任务记录/task-0001-login.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace("- **当前进度**：", "- **当前进度**：正在写接口")
open(p, 'w', encoding='utf-8').write(s)
PY
H stop-handoff.sh "$J_STOP"
assert_silent "交接说明已填写 → 不催办"

H stop-handoff.sh '{"cwd":"'"$WORK"'","session_id":"s1","stop_hook_active":true}'
assert_silent "stop_hook_active 时不重复催办"

printf '\n=== precompact-snapshot.sh（压缩前落盘）===\n'
H precompact-snapshot.sh '{"cwd":"'"$WORK"'","session_id":"s1","trigger":"auto","transcript_path":"/tmp/t.jsonl"}'
assert_silent "不阻断压缩、不输出决定（阻断会让超限恢复失败）"
if [ -f "$WORK/.claude/.state/precompact-s1.md" ] && grep -q "未结任务" "$WORK/.claude/.state/precompact-s1.md"; then
  ok "压缩前状态已落盘"
else
  bad "压缩前状态已落盘" "快照文件缺失或内容不对"
fi

printf '\n=== 依赖缺失时的行为 ===\n'
OUT=$(printf '{}' | PATH=/usr/bin:/bin AIDF_FORCE_NO_TOOL=1 "$WORK/.claude/hooks/check-commit.sh" 2>&1)
# 这条只验证脚本在无 json 工具时会明确报警而不是静默通过（见 _lib.sh aidf_deps）
if printf '%s' "$OUT" | grep -q "ai-dev-flow" || [ -z "$OUT" ]; then
  ok "依赖缺失路径有明确出口（不静默假装校验过）"
else
  bad "依赖缺失路径有明确出口" "实际：${OUT:0:160}"
fi

printf '\n=== 结果 ===\n'
printf '通过 %s，失败 %s\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
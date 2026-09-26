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

# 本套件要能在两种布局下跑：源码仓库（bin/install.sh）与已安装的 skill（assets/install.sh）。
# 理由和 install.sh 自带一份是同一个：改完 hook 之后，人会想在**用得着的那个位置**验证，
# 而不是 cd 回源码仓库。布局探测漏了的话，装完后跑它就是一句"安装失败"，没人会去查为什么。
if   [ -f "$ROOT/bin/install.sh" ];    then INSTALL="$ROOT/bin/install.sh"
elif [ -f "$ROOT/assets/install.sh" ]; then INSTALL="$ROOT/assets/install.sh"
else printf '错误：找不到 install.sh（bin/ 与 assets/ 下都没有），安装包不完整。\n' >&2; exit 1
fi

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
bash "$INSTALL" project "$WORK" >/dev/null 2>&1 || { echo "安装失败"; exit 1; }
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

# git -C <路径>：cwd 字段不可信，脚本必须自己解析 -C。同上，cwd 指向非仓库目录，
# 没解析 -C 的话它会 cd 过去、rev-parse 失败、静默放行。
NONREPO_C="$(mktemp -d)"
J_C_DENY="{\"tool_input\":{\"command\":\"git -C $WORK commit -m \\\"fix bug\\\"\"},\"cwd\":\"$NONREPO_C\",\"session_id\":\"s1\"}"
J_C_OK="{\"tool_input\":{\"command\":\"git -C $WORK commit -m \\\"task-0001: 登录接口\\\"\"},\"cwd\":\"$NONREPO_C\",\"session_id\":\"s1\"}"

echo "x4" >> code/src/a.js
git add code/src/a.js >/dev/null 2>&1
H check-commit.sh "$J_C_DENY"
assert_deny "git -C <路径> commit 且没引用任务 ID → 仍然拦截"

H check-commit.sh "$J_C_OK"
assert_silent "git -C <路径> commit 引用了任务 ID → 放行"
rm -rf "$NONREPO_C"

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

# git -C <路径> merge：命令自己带了仓库路径，所以 cwd 字段是不可信的。
# 这里刻意把 cwd 指到一个**不是仓库**的目录：如果脚本没解析 -C，它会 cd 过去、
# rev-parse 失败、静默 exit 0——两条用例会双双"通过"，而通路 B 永远不生效。
# 这正是要用一个假 cwd 来验的原因，不能只测 cwd 正确的情况。
NONREPO="$(mktemp -d)"
J_M_C="{\"tool_input\":{\"command\":\"git -C $WORK merge feature/nodeliv --no-edit\"},\"cwd\":\"$NONREPO\",\"session_id\":\"s1\"}"
J_M_C_OK="{\"tool_input\":{\"command\":\"git -C $WORK merge feature/x --no-edit\"},\"cwd\":\"$NONREPO\",\"session_id\":\"s1\"}"

H check-merge.sh "$J_M_C"
assert_deny "git -C <路径> merge 且没有交付件 → 仍然拦截"

H check-merge.sh "$J_M_C_OK"
assert_silent "git -C <路径> merge 时通路 B 仍然生效"
rm -rf "$NONREPO"

git checkout -q feature/x
H check-merge.sh "$J_M_DENY"
assert_silent "非发布分支 → 不干预"
git checkout -q main

printf '\n=== 回归：全新仓库（unborn HEAD）===\n'
# 曾经的 bug：git rev-parse --abbrev-ref HEAD 在无提交的仓库里返回字面量 "HEAD"，
# 被当成非发布分支，合并校验被静默跳过 —— 规则在纸上存在、在运行时不存在。
U="$(mktemp -d)"
bash "$INSTALL" project "$U" >/dev/null 2>&1
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

printf '\n=== 安装产物：索引由模板渲染 ===\n'
# 模板里的占位符没被替换掉的话，发到项目里的是个半成品；而 {{...}} 这种东西
# 在编辑器里不显眼，很容易就这么进版本库。所以断言两件事：文件在、占位符没了。
for d in 决策约束 交付件 任务记录 error; do
  idx="$WORK/doc/$d/索引.md"
  if [ ! -f "$idx" ]; then
    bad "doc/$d/索引.md 由模板生成" "文件不存在"
  elif grep -q '{{' "$idx"; then
    bad "doc/$d/索引.md 占位符已替换" "仍含 {{...}}：$(grep -m1 '{{' "$idx")"
  else
    ok "doc/$d/索引.md 由模板生成且占位符已替换"
  fi
done

printf '\n=== 安装产物：团队模式新增件 ===\n'
# tests/ 与 code/ 分开是「裁判不能兼运动员」能机械校验的前提（team/DESIGN.md §2.6）。
# 目录没建出来的话，test-* 写测试会被白名单拦在 code/ 外、又没地方去，
# 结果是它开始"想别的办法"——这正是要用目录消灭的那种判断。
if [ -d "$WORK/tests" ]; then ok "tests/ 已创建（测试与源码分开）"
else bad "tests/ 已创建" "不存在：test-* 无处可写"; fi

# 接口文档模板被 aidf-deliver §1 与 develop-manager 卡引用，缺了就是死引用。
for t in "doc/交付件/_接口模板.md" "doc/技能装配.md"; do
  if [ ! -f "$WORK/$t" ]; then
    bad "$t 已生成" "文件不存在"
  elif grep -q '{{' "$WORK/$t"; then
    bad "$t 无残留占位符" "仍含 {{...}}：$(grep -m1 '{{' "$WORK/$t")"
  else
    ok "$t 已生成且无残留占位符"
  fi
done

# 技能装配清单是人维护的数据文件，团队只查不写。--force 重装若能静默盖掉人的编辑，
# 这份清单会在某次"重装一下"之后变成模板——而没人会去复查一张表是不是被清空了。
printf '人补的行\n' >> "$WORK/doc/技能装配.md"
# 这里**故意用前置的 --force**：曾经 install.sh 按位置取参，`--force project X`
# 会把 "--force" 当成 MODE，整条命令走空——而走空之后下面的断言会因为
# "清单没被覆盖"而假通过。前置写法把那次修复钉住了。
bash "$INSTALL" --force project "$WORK" >/dev/null 2>&1
if grep -q '人补的行' "$WORK/doc/技能装配.md"; then
  bad "--force 重装确实覆盖了技能装配清单（前置条件）" \
      "清单仍是旧内容：--force 没生效（含前置写法），下面的备份断言会假通过"
else
  n_bak=$(ls -1 "$WORK"/doc/技能装配.md.bak-* 2>/dev/null | wc -l)
  if [ "$n_bak" -gt 0 ]; then
    ok "--force 重装覆盖清单前先备份，人工补的行有去处"
  else
    bad "--force 重装覆盖清单前先备份" "被覆盖且找不到 .bak：人工补的行静默丢失"
  fi
fi

printf '\n=== 依赖缺失时的行为 ===\n'
# 用 _lib.sh 的 AIDF_TEST_NO_TOOL 接缝，而不是收窄 PATH。
# 曾经写的是 PATH=/usr/bin:/bin，但本机 python3 在 /usr/bin 下还有一份，
# 校验照常跑完、没有任何输出，断言却靠着 `|| [ -z "$OUT" ]` 这个兜底通过了——
# 它一直在测空气，而那个兜底恰好就是它声称要防的"静默通过"。
OUT=$(printf '{}' | AIDF_TEST_NO_TOOL=1 "$WORK/.claude/hooks/check-commit.sh" 2>&1); CODE=$?
if [ "$CODE" != "0" ]; then
  bad "依赖缺失时以 exit 0 退出（而非阻断会话）" "实际 exit=$CODE"
elif ! printf '%s' "$OUT" | grep -q "本次校验跳过"; then
  bad "依赖缺失时明确报警" "期望警告文本，实际：${OUT:-<空——正是它声称要防的静默通过>}"
elif ! printf '%s' "$OUT" | grep -q "规则暂时没有生效"; then
  bad "报警说明了规则此刻未生效" "实际：${OUT:0:200}"
else
  ok "依赖缺失时明确报警、且说明规则此刻未生效"
fi

printf '\n=== 团队模式：check-branch.sh（分支粒度 = 任务粒度）===\n'
bj() { # 命令里的引号必须转义：不转义就不是合法 JSON，hook 解析失败后静默不动作，用例会假通过
  local c; c=$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s","session_id":"s1","agent_id":"%s","agent_type":"%s"}' \
    "$c" "$WORK" "${2:-}" "${3:-}"; }
H check-branch.sh "$(bj 'git checkout -b task-0001-login')"
assert_silent "分支名带存在的 task → 放行"

H check-branch.sh "$(bj 'git checkout -b experiments')"
assert_deny "分支名不含 task-NNNN → 拦截"
assert_contains "拦截信息给出可执行下一步" "doc/任务记录/索引.md"

H check-branch.sh "$(bj 'git checkout -b task-9999-x')"
assert_deny "分支名伪引用 → 拦截"
assert_contains "点名这是伪引用" "伪引用"

# 这三条防的是"守卫写成死代码"：只有新建分支才该校验，切换与列举不该被误伤。
# 尤其 `git branch -a`：提取分支名的 sed 曾经把 \1 写成 \2，
# sed 报错 → 输出为空 → 判定成"不是新建分支"→ 静默放行。
# 也就是说 git branch <name> 这条创建路径一次都没被校验过，而且它不会自己喊。
H check-branch.sh "$(bj 'git checkout main')"
assert_silent "仅切换到已有分支 → 不干预"
H check-branch.sh "$(bj 'git branch -a')"
assert_silent "git branch -a（列举）→ 不误伤"
H check-branch.sh "$(bj 'git branch task-9999-x')"
assert_deny "git branch <name> 创建分支 → 同样拦截"

H check-branch.sh "$(bj "git -C $WORK checkout -b experiments")"
assert_deny "git -C <路径> 建分支 → 仍然拦截"

printf '\n=== 团队模式：check-queue.sh（队列完整性与越权）===\n'
# 给测试项目一份带总授权的决策约束。check-queue 的越权校验读它。
cat > "$WORK/doc/决策约束/d-0001-deps.md" <<'EOF'
---
id: d-0001
status: active
---

## 授权

授权:
  - type: 第三方依赖版本冲突
    paths: code/order/, code/pay/
EOF
mkdir -p "$WORK/code/order"

qj() { # qj <文件名> <内容（真实换行）>
  local c; c=$(printf '%s' "$2" | sed ':a;N;$!ba;s/\n/\\n/g')
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"},"cwd":"%s","session_id":"s1"}' \
    "$WORK/doc/待裁/$1" "$c" "$WORK"
}
QFULL="id: escal-0001
type: 第三方依赖版本冲突
paths: [code/order/]
dissents: 无
anchor: doc/交付件/login-api.md
blocks: [task-0001#验收标准-1]
default_if_unanswered: 不做"
qdrop() { printf '%s' "$QFULL" | grep -v "^$1:"; }
qsub()  { printf '%s' "$QFULL" | sed "s|$1|$2|"; }

H check-queue.sh "$(qj escal-0001.md "$QFULL")"
assert_silent "待裁项字段齐备且未越权 → 放行"

H check-queue.sh "$(qj escal-0001.md "$(qdrop default_if_unanswered)")"
assert_deny "缺保守默认 → 拦截"
assert_contains "说清了为什么这条是硬限制" "责任转移"

H check-queue.sh "$(qj escal-0001.md "$(qdrop anchor)")"
assert_deny "缺事实锚点 → 拦截"

# 这一条是"事实锚点"这个名字的全部意义：锚必须指向**已存在**的产物。
# 否则 agent 可以凭想象列一堆疑问，而人无从判断哪些是真问题。
H check-queue.sh "$(qj escal-0001.md "$(qsub login-api.md del-9999.md)")"
assert_deny "anchor 指向不存在的文件 → 拦截"

H check-queue.sh "$(qj escal-0001.md "$(qsub 第三方依赖版本冲突 我自己发明的类型)")"
assert_deny "type 不在总授权类型集合里 → 拦截"
assert_contains "列出了已授权的类型，便于自服务" "第三方依赖版本冲突"
assert_contains "明令禁止改字段迁就授权" "换了个壳"

H check-queue.sh "$(qj escal-0001.md "$(qsub 'code/order/' 'code/billing/')")"
assert_deny "paths 超出授权前缀 → 拦截"
assert_contains "越权信息里点名了超出范围的具体路径" "code/billing/"

# 授权只在 active 的决策约束里算数。draft 是人还没批的稿子，
# 若拿它当授权依据，rule-manager 第一次裁决就可能是无授权的。
mv "$WORK/doc/决策约束/d-0001-deps.md" "$WORK/d-0001.bak"
printf -- '---\nid: d-0001\nstatus: draft\n---\n\n授权:\n  - type: 第三方依赖版本冲突\n    paths: code/order/\n' > "$WORK/doc/决策约束/d-0001-deps.md"
H check-queue.sh "$(qj escal-0001.md "$QFULL")"
assert_deny "授权写在 status: draft 的文件里 → 不算数，拦截"
assert_contains "指明授权只能来自 active" "硬规则 4"
mv "$WORK/d-0001.bak" "$WORK/doc/决策约束/d-0001-deps.md"

H check-queue.sh "$(qj escal-0001.md "$(qsub '\[task-0001#验收标准-1\]' '[]')")"
assert_deny "blocks 为空却放在 doc/待裁/ → 拦截（轨道由字段决定）"

H check-queue.sh "$(qj escal-0001.md "$(qdrop dissents)")"
assert_deny "缺 dissents 字段 → 拦截"
assert_contains "说明了为什么字段缺失不能等同于无异议" "只需要删掉字段"

H check-queue.sh "$(qj 索引.md "$QFULL")"
assert_silent "自动生成的索引不参与校验"

printf '\n=== 团队模式：check-role-boundaries.sh（角色边界）===\n'
rj() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"},"cwd":"%s","session_id":"s1","agent_id":"%s","agent_type":"%s"}' \
        "$1" "$2" "$WORK" "$3" "$4"; }
# code/ 是**白名单**：只有 impl-* 能写。这几条一起定义了"角色边界"的全部含义。
H check-role-boundaries.sh "$(rj "$WORK/code/order/x.ts" "x" a1 test-worker)"
assert_deny "test-worker 写 code/ → 拦截（裁判不能兼运动员）"
assert_contains "给出了正确的出口" "决策记录"

H check-role-boundaries.sh "$(rj "$WORK/code/order/x.ts" "x" a2 impl-worker)"
assert_silent "impl-worker 写 code/ → 放行（唯一可写 code/ 的角色）"

H check-role-boundaries.sh "$(rj "$WORK/code/order/x.ts" "x" a3 impl-backend)"
assert_silent "impl-<域> 专用工人卡 → 按前缀放行（卡名即凭据）"

# manager 化从"承诺"变"做不到"的那一条：它写 code/ 会被拦，
# 于是"不再直接负责写代码"不是纪律要求，是机械事实。
H check-role-boundaries.sh "$(rj "$WORK/code/order/x.ts" "x" a4 develop-manager)"
assert_deny "develop-manager 写 code/ → 拦截"
assert_contains "把出口指向它真正该做的事" "接口文档"

H check-role-boundaries.sh "$(rj "$WORK/code/order/x.ts" "x" a5 test-manager)"
assert_deny "test-manager 写 code/ → 拦截"

H check-role-boundaries.sh "$(rj "$WORK/code/order/x.ts" "x" a6 requirements-analyst)"
assert_deny "需求分析师写 code/ → 拦截"

# 黑名单永远列不全动态派发出来的工人名；这一条正是改白名单的理由。
H check-role-boundaries.sh "$(rj "$WORK/code/order/x.ts" "x" a7 general-purpose)"
assert_deny "无身份的通用 subagent 写 code/ → 拦截（黑名单列不到它）"
assert_contains "说明白名单的凭据是卡名前缀" "impl-"

H check-role-boundaries.sh "$(rj "$WORK/tests/order.spec.ts" "x" a8 test-worker)"
assert_silent "test-worker 写 tests/ → 放行（测试与源码分开）"

# 人自己改代码不该被拦：主会话是人所在的地方。
H check-role-boundaries.sh "$(rj "$WORK/code/order/x.ts" "x" "" "")"
assert_silent "主会话（人）写 code/ → 放行，不受白名单限制"

# 硬规则 4 的机械检查点。用 agent_id 区分 subagent 与主会话：
# subagent 无人值守，主会话是人所在的地方。
# 用 draft 文件做靶子：靶子本身若已是 active，"翻 active"就不是翻，用例会假通过。
printf -- '---\nid: d-0002\nstatus: draft\n---\n' > "$WORK/doc/决策约束/d-0002-draft.md"

H check-role-boundaries.sh "$(rj "$WORK/doc/决策约束/d-0002-draft.md" "status: active" a4 rule-manager)"
assert_deny "subagent 把决策约束从 draft 翻成 active → 拦截"
assert_contains "点明 draft→active 必须由人做" "必须由人来做"

H check-role-boundaries.sh "$(rj "$WORK/doc/决策约束/d-0002-draft.md" "改个错别字" a9 develop-manager)"
assert_silent "subagent 改决策约束但没翻 status → 放行（不误伤）"

H check-role-boundaries.sh "$(rj "$WORK/doc/决策约束/d-0002-draft.md" "status: active" "" "")"
assert_silent "主会话（人所在处）翻 active → 放行"

H check-role-boundaries.sh "$(rj "$WORK/doc/决策约束/d-0001-deps.md" "status: active" "" "")"
assert_silent "主会话改已是 active 的文件 → 放行（不误伤）"

printf '\n=== 团队模式：check-irreversible.sh（不可逆动作）===\n'
ij() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s","session_id":"s1","agent_id":"%s","agent_type":"%s"}' \
        "$1" "$WORK" "$2" "$3"; }
H check-irreversible.sh "$(ij 'git push origin main' a1 impl-worker)"
assert_deny "subagent 执行 push → 拦截"
assert_contains "点明这是不可逆动作" "不可逆动作"

H check-irreversible.sh "$(ij 'git push origin main' "" "")"
assert_silent "主会话 push → 放行（人要自己推时不拦）"

H check-irreversible.sh "$(ij 'git status' a1 impl-worker)"
assert_silent "subagent 执行普通命令 → 不干预"

printf '\n=== 团队模式：log-event.sh（拦截失效时的留痕）===\n'
# 这一组用例的存在理由，就是这条设计要防的那个失败模式：
# 拦截型 hook 会超时、会因路径写错而静默失效、会在误用 exit 1 时不拦。
# 三者都不会自己喊。所以每个拦截点都并联一个只记录不决策的 hook——
# **拦截失效时，事件必须仍然留痕**，否则"没被拦"会被误读成"没问题"。
AUDIT="$WORK/.claude/.state/audit.jsonl"
rm -f "$AUDIT"
OUT=$(printf '%s' "$(bj 'git commit -m "task-0001: x"' impl-1 impl-worker)" \
      | CLAUDE_PROJECT_DIR="$WORK" "$WORK/.claude/hooks/log-event.sh" 2>&1); CODE=$?
assert_silent "记录 hook 自身必须完全静默（永不影响决策）"
if [ -s "$AUDIT" ] && grep -q 'git commit' "$AUDIT"; then
  ok "受管事件被留痕（拦截失效时可追溯）"
else
  bad "受管事件被留痕" "audit.jsonl 缺失或无内容"
fi
n1=$(wc -l < "$AUDIT" 2>/dev/null || echo 0)
# 留痕必须能归因到具体是谁干的（subagent 无人值守，事后只能靠这条追）。
if grep -q '"agent_id":"impl-1"' "$AUDIT" 2>/dev/null; then
  ok "留痕带上了 agent_id/agent_type，可归因到具体 subagent"
else
  bad "留痕带上了 agent_id/agent_type" "audit.jsonl 里没有 agent_id 字段"
fi
if [ -s "$AUDIT" ] && python3 -c 'import json,sys;[json.loads(l) for l in open(sys.argv[1])]' "$AUDIT" 2>/dev/null; then
  ok "每行都是合法 JSON（事后可被脚本消费，而不是只能肉眼读）"
else
  bad "每行都是合法 JSON" "解析失败——手拼 JSON 的转义写错了"
fi
OUT=$(printf '%s' "$(bj 'ls -la' impl-1 impl-worker)" \
      | CLAUDE_PROJECT_DIR="$WORK" "$WORK/.claude/hooks/log-event.sh" 2>&1); CODE=$?
n2=$(wc -l < "$AUDIT" 2>/dev/null || echo 0)
# 基线必须 >0，否则"没变化"是拿 0 跟 0 比 —— 记录器彻底坏掉时这条也会 ✓
if [ "$n1" -gt 0 ] && [ "$n1" = "$n2" ]; then ok "不受管事件不记录（避免淹掉有用信号）"
else bad "不受管事件不记录" "行数 $n1 → $n2（基线必须 >0，否则这是假通过）"; fi

# 记录器也要走共享库的依赖降级：缺 python3/jq 时它绝不能"静默地什么都没记"。
# 其余 hook 缺依赖会经 aidf_deps 报警；记录器若例外，就正好退化成它自己要防的那种失败。
OUT=$(printf '%s' "$(bj 'git push origin main' impl-1 impl-worker)" \
      | AIDF_TEST_NO_TOOL=1 CLAUDE_PROJECT_DIR="$WORK" "$WORK/.claude/hooks/log-event.sh" 2>&1); CODE=$?
if [ -z "$OUT" ] && [ "$CODE" = "0" ]; then
  bad "缺依赖时记录器必须报警而不是静默" "完全静默——这条失败正是「看起来有效果」"
else ok "缺依赖时记录器明确报警（stderr），不静默失效"; fi

printf '\n=== 团队模式：inject-context 的静默条件已扩展 ===\n'
# 原来只数未结任务。团队模式下"有待批项"同样是"该回来看一眼"的客观信号，
# 此时必须开口，不然人回来时看不到积压。
# 先清掉上面几条用例留在队列里的 open 项，否则"完全静默"这条会因残留而假失败。
rm -f "$WORK/doc/待裁/"*.md "$WORK/doc/待批/"*.md
sed -i 's/^status: doing/status: done/' "$WORK/doc/任务记录/task-0001-login.md"
OUT=$(printf '{"session_id":"s9","source":"startup","cwd":"%s"}' "$WORK" | "$WORK/.claude/hooks/inject-context.sh" 2>/dev/null); CODE=$?
assert_silent "无未结任务且无队列 → 完全静默"

printf -- '---\nid: appr-0001\nstatus: open\ndefault_if_unanswered: 不做\nanchor: doc/交付件/login-api.md\nblocks: []\n---\n' > "$WORK/doc/待批/appr-0001.md"
OUT=$(printf '{"session_id":"s9","source":"startup","cwd":"%s"}' "$WORK" | "$WORK/.claude/hooks/inject-context.sh" 2>/dev/null); CODE=$?
assert_contains "只有待批项时也会开口" "待审批项 1 条"
assert_contains "并说明它是提示而非门槛" "不阻塞任何推进"

# 已裁定的项不该再算积压，否则队列越用越长、信号越用越钝。
sed -i 's/^status: open/status: decided/' "$WORK/doc/待批/appr-0001.md"
OUT=$(printf '{"session_id":"s9","source":"startup","cwd":"%s"}' "$WORK" | "$WORK/.claude/hooks/inject-context.sh" 2>/dev/null); CODE=$?
assert_silent "队列项已裁定 → 不计入积压，回到静默"

rm -f "$WORK/doc/待批/appr-0001.md"
sed -i 's/^status: done/status: doing/' "$WORK/doc/任务记录/task-0001-login.md"

printf '\n=== 结果 ===\n'
printf '通过 %s，失败 %s\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
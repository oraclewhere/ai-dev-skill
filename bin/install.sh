#!/usr/bin/env bash
# ai-dev-flow 安装脚本
#
#   ./bin/install.sh skill                  装到 ~/.claude/skills/ai-dev-flow/（用户级，全局可用）
#   ./bin/install.sh project [项目路径]       在项目里启用规范             （项目级）
#   ./bin/install.sh project <路径> --force   覆盖已存在的文件
#
# 为什么拆开装（刻意的设计，不是遗留）：
#   skill 无副作用——不调用它什么都不做，装全局零风险，且方法论迭代时改一处全生效。
#   hook 有副作用——它会拦你，必须只在明确启用规范的项目里生效。
#
# 关于已有文件：默认跳过并报告，不覆盖。脚本里做交互式询问在非交互环境下会挂住，
# 所以宁可保守——需要覆盖时显式加 --force。
#
# 本脚本要能在两种布局下工作：
#   源码仓库：   <root>/skill/{SKILL.md,references,assets/templates} + <root>/project + <root>/bin
#   已安装 skill：~/.claude/skills/ai-dev-flow/{SKILL.md,references,assets/templates,assets/project}
# 所以下面不硬编码路径，而是探测布局。

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"

if [ -d "$ROOT/skill/assets/templates" ]; then
  SKILL_SRC="$ROOT/skill"
  PROJ_SRC="$ROOT/project"
  TEAM_SRC="$ROOT/team"
elif [ -d "$ROOT/assets/templates" ]; then
  SKILL_SRC="$ROOT"
  PROJ_SRC="$ROOT/assets/project"
  TEAM_SRC="$ROOT/assets/team"
else
  printf '错误：找不到模板目录，安装包不完整。\n' >&2
  exit 1
fi
TPL_SRC="$SKILL_SRC/assets/templates"
# 团队资产是可选的：老版本的安装包里没有 team/，此时 team 模式给出明确提示而不是静默做一半
[ -d "$TEAM_SRC/agents" ] || TEAM_SRC=""

# --force 取任意位置：曾经只按 $1/$2 取参，于是 `install.sh --force project X`
# 会把 "--force" 当成 MODE，落到 *) 分支——它至少会报用法；但如果只写
# `install.sh project X --force` 之外的顺序，多一个位置参数同样会被静默忽略。
# 位置敏感的参数解析在"改配置"这种命令上是纯负担，直接按名字摘出来。
FORCE=0
_args=()
for a in "$@"; do
  if [ "$a" = "--force" ]; then FORCE=1; else _args+=("$a"); fi
done
MODE="${_args[0]:-}"
# 空数组下标在 set -u 下会炸（`${_args[1]:.}` 也救不了），所以显式判长度
TARGET="."
if [ "${#_args[@]}" -ge 2 ]; then TARGET="${_args[1]}"; fi
if [ "${#_args[@]}" -gt 2 ]; then
  # 这里用 printf 而不是 say：say 在下一节才定义，此处调用会 command not found。
  printf '错误：多余的参数：%s\n      用法见 %s（不带参数）\n' "$*" "$0" >&2
  exit 1
fi

say()  { printf '%s\n' "$*"; }
skip() { printf '  跳过（已存在）：%s\n' "$*"; }

place() {
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ "$FORCE" -eq 0 ]; then skip "$dst"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst" && printf '  写入：%s\n' "$dst"
}

need_json_tool() {
  # hook 需要解析输入 JSON。python3 优先、jq 回退——很多机器没有 jq，
  # 只依赖 jq 会让整套校验静默失效，而"规则在纸上存在、在运行时不存在"
  # 是本方法论最不能接受的一种失败。
  if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1 \
     && ! command -v jq >/dev/null 2>&1; then
    say "错误：hook 需要 python3 或 jq 之一来解析输入 JSON，两者都没找到。"
    say "      请安装其一后重试（sudo apt install python3 或 sudo apt install jq）。"
    exit 1
  fi
  command -v git >/dev/null 2>&1 || \
    say "警告：未找到 git。规范依赖 git 判断提交内容，没有 git 时校验会全部跳过。"
}

# ---------------------------------------------------------------- skill

install_skill() {
  need_json_tool
  local dst="$HOME/.claude/skills/ai-dev-flow"
  say "安装 skill 到 $dst"
  mkdir -p "$dst/references" "$dst/assets/templates" "$dst/assets/project/hooks"

  place "$SKILL_SRC/SKILL.md" "$dst/SKILL.md"
  for f in "$SKILL_SRC"/references/*.md;   do place "$f" "$dst/references/$(basename "$f")"; done
  for f in "$TPL_SRC"/*.md;                do place "$f" "$dst/assets/templates/$(basename "$f")"; done
  for f in "$PROJ_SRC"/hooks/*.sh;         do place "$f" "$dst/assets/project/hooks/$(basename "$f")"; done
  place "$PROJ_SRC/settings.json"     "$dst/assets/project/settings.json"
  place "$PROJ_SRC/CLAUDE.md.template" "$dst/assets/project/CLAUDE.md.template"
  # 自带安装脚本，这样 skill 目录是自包含的——否则 /ai-dev-flow 初始化 在装完之后用不了
  place "$ROOT/bin/install.sh" "$dst/assets/install.sh"
  # 自测套件也一起走：改了 hook 之后要在**装完的位置**跑得动，否则没人会去源码仓库里跑它
  place "$ROOT/bin/selftest.sh" "$dst/assets/selftest.sh"
  # 团队资产也随 skill 走，这样安装包在别的机器上也能装团队模式。
  # 源在 ROOT/team（仓库布局）时复制；源已经在 assets/team（已装布局）时跳过，避免自己拷自己。
  if [ -n "$TEAM_SRC" ] && [ "$TEAM_SRC" = "$ROOT/team" ]; then
    for f in "$TEAM_SRC"/agents/*.md; do place "$f" "$dst/assets/team/agents/$(basename "$f")"; done
    for d in "$TEAM_SRC"/skills/*/; do
      [ -d "$d" ] || continue
      place "$d/SKILL.md" "$dst/assets/team/skills/$(basename "$d")/SKILL.md"
    done
  fi
  chmod +x "$dst/assets/install.sh" "$dst/assets/selftest.sh" "$dst/assets/project/hooks/"*.sh 2>/dev/null

  say ""
  say "完成。新开一个 session 后即可使用 /ai-dev-flow。"
  say "（skill 目录名决定命令名，所以目录必须叫 ai-dev-flow。）"
}

# ---------------------------------------------------------------- team

# 为什么团队身份卡也装用户级：它与 skill 同性质——无副作用，不调用它什么都不做。
# 硬限制（hook）不在这里装，因为 hook 会拦你，必须只在明确启用的项目里生效。
# 这与 README 里"skill 用户级 / hook 项目级"的拆分理由是同一个。
install_team() {
  need_json_tool
  if [ -z "$TEAM_SRC" ]; then
    say "错误：安装包里找不到 team/ 资产，无法安装团队模式。"
    say "      请从源码仓库运行 $0 team，或先重装 skill 让安装包完整。"
    exit 1
  fi

  local dst_agents="$HOME/.claude/agents"
  local dst_skills="$HOME/.claude/skills"

  say "安装团队身份卡到 $dst_agents"
  mkdir -p "$dst_agents"
  for f in "$TEAM_SRC"/agents/*.md; do
    [ -f "$f" ] || continue
    place "$f" "$dst_agents/$(basename "$f")"
  done

  say ""
  say "安装团队共享 skill 到 $dst_skills"
  for d in "$TEAM_SRC"/skills/*/; do
    [ -d "$d" ] || continue
    local name; name="$(basename "$d")"
    mkdir -p "$dst_skills/$name"
    place "$d/SKILL.md" "$dst_skills/$name/SKILL.md"
  done

  # 角色卡改名过。旧文件若不报出来，会与新卡并存——而按 agent_type 匹配的 hook
  # 只认新名，于是用旧卡启动的角色绕过全部角色边界检查，且不会自己喊。
  # 不自动删（删用户目录里的文件要人点头），但必须报到人眼前。
  local retired="developer tester" stale="" s
  for s in $retired; do
    [ -f "$TEAM_SRC/agents/$s.md" ] && continue   # 新版里仍有这个名字 → 不是废弃
    [ -f "$dst_agents/$s.md" ] && stale="$stale $s"
  done
  if [ -n "$stale" ]; then
    say ""
    say "警告：以下角色卡已被取代，但你机器上还留着旧文件："
    for s in $stale; do say "        $dst_agents/$s.md"; done
    say "      角色边界由 agent_type 匹配（hook 只认新名），旧卡启动的角色会绕过"
    say "      全部边界检查，而且不会报错。确认无用后请删除："
    s=""
    for s in $stale; do say "        rm $dst_agents/$s.md"; done
  fi

  say ""
  say "完成。身份卡与 skill 是用户级的，装全局零风险。"
  say ""
  say "接下来两步："
  say "  1. 在项目里启用硬限制（项目级，会拦你）："
  say "       $0 project <项目路径>"
  say "  2. 用团队声明卡启动整个会话："
  say "       claude --agent dev-team"
  say ""
  say "注意：main 会话用 --agent 启动后，整套流程由团队声明卡接管。"
  say "      AskUserQuestion 只有主会话有，所以所有角色对人都经主会话转达——这是设计的一部分。"
}

# ---------------------------------------------------------------- project

install_project() {
  need_json_tool
  mkdir -p "$TARGET" || { say "错误：无法创建目录 $TARGET"; exit 1; }
  cd "$TARGET" || { say "错误：找不到目录 $TARGET"; exit 1; }
  local P; P="$(pwd)"
  say "在 $P 启用 ai-dev-flow 规范"
  say ""

  # tests/ 与 code/ 分开是刻意的：test-* 能写 tests/ 写不了 code/，
  # 「裁判不能兼运动员」这条边界才是机械可查的（见 team/DESIGN.md §2.6）。
  mkdir -p code tests scripts doc/决策约束 doc/交付件 doc/任务记录 doc/error doc/待裁 doc/待批 .claude/hooks .claude/.state
  say "  目录：code/ tests/ scripts/ doc/{决策约束,交付件,任务记录,error,待裁,待批}/ .claude/{hooks,.state}/"

  # 索引由 assets/templates/索引.md 渲染，不再内联拼字符串。
  # 原因：模板里的「状态说明」是内联版没有的，两边各自漂移的话，发出去的模板就是个
  # 没人用的摆设——而模板才是单一事实来源。
  write_index() {
    local dir="$1" role="$2" states="$3" idx="doc/$1/索引.md"
    if [ -e "$idx" ] && [ "$FORCE" -eq 0 ]; then skip "$idx"; return 0; fi
    sed -e "s|{{目录名}}|$dir|" \
        -e "s|{{作用}}|$role|" \
        -e "s|{{状态说明}}|$states|" \
        "$TPL_SRC/索引.md" > "$idx"
    printf '  写入：%s\n' "$idx"
  }

  write_index 决策约束 \
    '人维护、AI 只读。当前生效的技术栈、需求拆分结果与限制条件。' \
    '- `draft` 草稿，等人批准 / `active` 生效中 / `superseded` 已被取代'
  write_index 交付件 \
    'AI 生成、人审阅。接口契约、实现结果、验证方法。' \
    '- `current` 当前有效 / `stale` 上游决策变更后待重验'
  write_index 任务记录 \
    'commit 的关联锚点，兼对话记录。工作量单位是"能否在一个 session 内闭环"。' \
    '- `todo` 未开始 / `doing` 进行中 / `review` 待验收 / `done` 已验收'
  write_index error \
    '复盘产出的违规报告，用于迭代方法论。每条归因到「执行违规」（→ 加 hook）或「规则歧义」（→ 改措辞）。' \
    '- `pass` 本次未发现违规 / `fail` 存在违规条目，详见报告正文'
  write_index 待裁 \
    '团队模式的核心轨裁决记录。blocks 非空的待裁项由 rule-manager 取证裁决后继续推进，人回来复核。' \
    '- `open` 待复核 / `decided` 已裁定 / `defaulted` 走了保守默认'
  write_index 待批 \
    '团队模式的非核心轨队列。blocks 为空，即当前没有任何验收标准依赖它，延后天然安全。' \
    '- `open` 待批 / `decided` 已批 / `defaulted` 走了保守默认'

  # doc/技能装配.md 是人维护的数据文件（团队只读）。它只在首次生成，
  # 但 --force 会拿模板盖掉人补的那些行 —— 所以先备份一份再说。
  local equip_backup=""
  if [ "$FORCE" -eq 1 ] && [ -f "doc/技能装配.md" ]; then
    equip_backup="doc/技能装配.md.bak-$(date +%Y%m%d%H%M%S)"
    cp "doc/技能装配.md" "$equip_backup"
  fi

  for f in "$TPL_SRC"/*.md; do
    local b; b="$(basename "$f")"
    [ "$b" = "索引.md" ] && continue
    case "$b" in
      任务记录.md) place "$f" "doc/任务记录/_模板.md" ;;
      决策约束.md) place "$f" "doc/决策约束/_模板.md" ;;
      交付件.md)   place "$f" "doc/交付件/_模板.md" ;;
      复盘报告.md) place "$f" "doc/error/_模板.md" ;;
      待裁项.md)   place "$f" "doc/待裁/_模板.md" ;;
      待批项.md)   place "$f" "doc/待批/_模板.md" ;;
      接口.md)     place "$f" "doc/交付件/_接口模板.md" ;;
      技能装配.md) place "$f" "doc/技能装配.md" ;;
    esac
  done

  if [ -n "$equip_backup" ]; then
    say "  备份：$equip_backup（--force 重装覆盖了 doc/技能装配.md，人工补的行在里面）"
  fi

  for f in "$PROJ_SRC"/hooks/*.sh; do place "$f" ".claude/hooks/$(basename "$f")"; done
  chmod +x .claude/hooks/*.sh 2>/dev/null
  place "$PROJ_SRC/settings.json" ".claude/settings.json"

  # 状态栏命令需要绝对路径，所以放 gitignore 掉的 local 文件，避免把机器路径提交进仓库
  local sl="$P/.claude/hooks/statusline.sh"
  cat > .claude/settings.local.json <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "$sl",
    "padding": 1
  }
}
EOF
  say "  写入：.claude/settings.local.json（状态栏，含机器绝对路径，已在 .gitignore 中）"

  place "$PROJ_SRC/CLAUDE.md.template" "CLAUDE.md"

  local gi=".gitignore"
  touch "$gi"
  for line in ".claude/.state/" ".claude/settings.local.json"; do
    grep -qxF "$line" "$gi" 2>/dev/null || printf '%s\n' "$line" >> "$gi"
  done
  say "  更新：.gitignore（忽略 .claude/.state/ 与 settings.local.json）"

  say ""
  say "完成。接下来："
  say "  1. 在 Claude Code 里打开本项目并接受工作区信任对话框（否则 hook 不会运行）"
  say "  2. /ai-dev-flow 启动 <你的第一个需求>"
  say ""
  say "提醒：hooks 会以你的完整用户权限执行 shell 命令。如果你把这个 .claude/ 提交进仓库，"
  say "别人在未信任的目录下用 claude -p 跑时，这些 hook 仍会执行——分享前先确认这一点。"
}

case "$MODE" in
  skill)   install_skill ;;
  team)    install_team ;;
  project) install_project ;;
  all)     install_skill; say ""; install_team; say ""; install_project ;;
  *) say "用法："
     say "  $0 skill                            装流程 skill 到 ~/.claude/skills/（用户级）"
     say "  $0 team                             装团队身份卡 + 共享 skill 到 ~/.claude/（用户级）"
     say "  $0 project [项目路径] [--force]       在项目里启用硬限制（项目级，会拦你）"
     say "  $0 all [项目路径] [--force]           上面三件事一次做完"
     say ""
     say "--force 可放在任意位置：它会覆盖已存在的文件（默认遇到已存在就跳过）。"
     say "--force 覆盖 doc/技能装配.md 前会先备份成 .bak-<时间戳>，那是人维护的文件。"
     exit 1 ;;
esac
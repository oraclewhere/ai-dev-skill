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
elif [ -d "$ROOT/assets/templates" ]; then
  SKILL_SRC="$ROOT"
  PROJ_SRC="$ROOT/assets/project"
else
  printf '错误：找不到模板目录，安装包不完整。\n' >&2
  exit 1
fi
TPL_SRC="$SKILL_SRC/assets/templates"

FORCE=0
MODE="${1:-}"
TARGET="${2:-.}"
for a in "$@"; do [ "$a" = "--force" ] && FORCE=1; done
[ "$TARGET" = "--force" ] && TARGET="."

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
  chmod +x "$dst/assets/install.sh" "$dst/assets/project/hooks/"*.sh 2>/dev/null

  say ""
  say "完成。新开一个 session 后即可使用 /ai-dev-flow。"
  say "（skill 目录名决定命令名，所以目录必须叫 ai-dev-flow。）"
}

# ---------------------------------------------------------------- project

install_project() {
  need_json_tool
  mkdir -p "$TARGET" || { say "错误：无法创建目录 $TARGET"; exit 1; }
  cd "$TARGET" || { say "错误：找不到目录 $TARGET"; exit 1; }
  local P; P="$(pwd)"
  say "在 $P 启用 ai-dev-flow 规范"
  say ""

  mkdir -p code scripts doc/决策约束 doc/交付件 doc/任务记录 doc/error .claude/hooks .claude/.state
  say "  目录：code/ scripts/ doc/{决策约束,交付件,任务记录,error}/ .claude/{hooks,.state}/"

  for d in 决策约束 交付件 任务记录; do
    local idx="doc/$d/索引.md"
    if [ -e "$idx" ] && [ "$FORCE" -eq 0 ]; then skip "$idx"; continue; fi
    { printf '# %s 索引\n\n' "$d"
      printf '> 本文件由 /ai-dev-flow 维护。新接入的 session 读这里了解现状，不要逐个文件翻。\n\n'
      printf '| ID | 标题 | 状态 | 更新日期 | 备注 |\n|---|---|---|---|---|\n| | | | | |\n'
    } > "$idx"
    printf '  写入：%s\n' "$idx"
  done

  for f in "$TPL_SRC"/*.md; do
    local b; b="$(basename "$f")"
    [ "$b" = "索引.md" ] && continue
    case "$b" in
      任务记录.md) place "$f" "doc/任务记录/_模板.md" ;;
      决策约束.md) place "$f" "doc/决策约束/_模板.md" ;;
      交付件.md)   place "$f" "doc/交付件/_模板.md" ;;
      复盘报告.md) place "$f" "doc/error/_模板.md" ;;
    esac
  done

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
  project) install_project ;;
  *) say "用法："; say "  $0 skill"; say "  $0 project [项目路径] [--force]"; exit 1 ;;
esac
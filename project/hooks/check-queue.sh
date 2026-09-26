#!/usr/bin/env bash
# ai-dev-flow · PreToolUse(Write|Edit) — 团队模式：队列项的完整性与越权校验
#
# 拦三类问题，全部是集合成员资格或字段存在性，不含任何判断：
#   A. 必填字段缺失            —— default_if_unanswered（保守默认）与 anchor（事实锚点）
#   B. anchor 指向的文件不存在 —— "事实锚点"必须是**已存在**的产物
#   C. 待裁项的 type / paths 越权，或轨道放错目录
#
# 为什么 A/B 是硬限制而不是身份卡里的一句话：
#   不强制这两条，agent 就有动机把所有事都列为"不确定"——将来做错了可以说
#   "我列过了，你没定"。那是**责任转移**。保守默认让"列举疑问"的成本上升，
#   事实锚点让它可被机械核查。

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

# 归一化成项目相对路径（hook 给的通常是绝对路径）
rel="$fp"
case "$rel" in
  */doc/待裁/*|*/doc/待批/*) rel="doc/${rel#*/doc/}" ;;
  doc/待裁/*|doc/待批/*) ;;
  *) exit 0 ;;
esac

base="$(basename "$rel")"
# 索引是自动生成的、模板不参与校验
[ "$base" = "索引.md" ] && exit 0
[ "$base" = "_模板.md" ] && exit 0

[ -d doc/任务记录 ] || exit 0

# 要校验的是**即将落地的这一版**，所以优先用 tool_input 里的内容
new=$(jget tool_input.content "$input")
[ -z "$new" ] && new=$(jget tool_input.new_string "$input")

field() {
  local k="$1" v=""
  if [ -n "$new" ]; then
    v=$(printf '%s\n' "$new" | awk -F': *' -v k="$k" '$0 ~ "^"k":" {print $2; exit}' | tr -d '\r')
  fi
  # Edit 只改局部时，新内容里没有该字段 → 回退到盘上的版本
  if [ -z "$v" ] && [ -f "$rel" ]; then v=$(fm "$rel" "$k"); fi
  printf '%s' "$v"
}

die() { emit_deny "$1"; exit 0; }

# ---- A. 必填字段 ------------------------------------------------------------
dflt=$(field default_if_unanswered)
if [ -z "$dflt" ]; then
  die "${rel} 缺少 default_if_unanswered（保守默认）。

规范：每条队列项必须写明"没人定的话我打算怎么做"，且必须是**可逆的、不阻塞其他推进的**那一个。

理由：不强制这一条，列举疑问的成本为零，agent 会把所有事都列为"不确定"——
将来做错了可以说"我列过了，你没定"。那是责任转移，不是尽职。

请补上，例如：
  default_if_unanswered: 不做（对该任务无阻塞）"
fi

anchor=$(field anchor)
if [ -z "$anchor" ]; then
  die "${rel} 缺少 anchor（事实锚点）。

规范：每条疑问必须锚定到一个**已存在**的产物（文件 / 交付件 / 验收标准），
不能是基于想象的提问。

理由：这一条把"根据当前进展提问"从一句要求落成了机械检查——
没有它，需求分析师可以凭想象列一堆问题，而人无从判断哪些是真问题。

请补上指向真实文件的路径，例如：
  anchor: doc/交付件/del-0003.md"
fi

anchor_path=$(printf '%s' "$anchor" | tr -d '"' | awk '{print $1}')
if [ ! -e "$anchor_path" ]; then
  die "${rel} 的 anchor 指向了一个不存在的文件：${anchor_path}

事实锚点必须是**已存在**的产物。指向不存在的路径，等于这条疑问没有依据。

请这样做：
  1. 若锚点写错了路径 → 改成真实存在的文件
  2. 若确实还没有可锚定的产物 → 这条疑问的前提还不成立，
     先降级为"不确定"档入 doc/待批/，等有产物了再升级"
fi

# ---- 轨道判定：只看 blocks 是不是空的 ----------------------------------------
blocks=$(field blocks)
blocks_empty=1
printf '%s' "$blocks" | tr -d '[] ' | grep -q '[^ ]' && blocks_empty=0

case "$rel" in
  doc/待裁/*)
    if [ "$blocks_empty" -eq 1 ]; then
      die "${rel} 放在 doc/待裁/ 下，但 blocks 为空。

规范：轨道由 blocks 是不是空的决定——
  blocks 非空 → 核心轨 → doc/待裁/，由 rule-manager 裁决后继续推进
  blocks 为空 → 非核心轨 → doc/待批/，等人回来统一批

判定不看内容、不看重要性，只看这个字段是不是空的。

请把它移到 doc/待批/，或补上它阻塞的验收标准。"
    fi
    ;;

  doc/待批/*)
    if [ "$blocks_empty" -eq 0 ]; then
      die "${rel} 放在 doc/待批/ 下，但 blocks 非空（阻塞了验收标准）。

规范：blocks 非空 = 核心轨，会卡住推进，必须走 doc/待裁/ 由 rule-manager 裁决，
不能躺在待批队列里等人——那会让整条需求停滞。

请把它移到 doc/待裁/。"
    fi
    exit 0
    ;;
esac

# ---- C. 待裁项：字段齐备 + 越权校验 -------------------------------------------
ty=$(field type)
[ -z "$ty" ] && die "${rel} 缺少 type 字段，无法做越权校验。

type 是越权校验的两个字段之一，必须有。"

# dissents 允许写"无"，但不允许整个字段缺失：
# 若"字段缺失"与"无异议"不可区分，抹掉异议就只需要删掉字段。
if ! printf '%s\n' "$new" | grep -qE '^dissents:'; then
  if [ ! -f "$rel" ] || ! grep -qE '^dissents:' "$rel"; then
    die "${rel} 缺少 dissents 字段。

规范：异议留痕，不可删除。没有反对意见也要显式写 dissents: 无。

理由：如果"字段缺失"和"无异议"不可区分，那么抹掉异议就只需要删掉字段。"
  fi
fi

# 总授权从 doc/决策约束/ 下扫出来，形如 "type|paths"。
# 只认 status: active 的文件——draft 是人还没批的稿子，拿它当授权依据，
# 等于 AI 用未经批准的授权给自己发许可，直接违反硬规则 4。
# （这不是洁癖：尽调阶段写的授权草稿在人多半还没看时就已落盘，
#   若把它算作生效，rule-manager 第一次裁决就可能是无授权的。）
_auth_of() {
  awk '
    /^[[:space:]]*-[[:space:]]*type:[[:space:]]*/ {
      t = $0; sub(/^[[:space:]]*-[[:space:]]*type:[[:space:]]*/, "", t); cur = t; next
    }
    /^[[:space:]]*paths:[[:space:]]*/ && cur != "" {
      p = $0; sub(/^[[:space:]]*paths:[[:space:]]*/, "", p)
      gsub(/[][]/, "", p)
      print cur "|" p
      cur = ""
    }' "$1"
}
auth=""
for _f in doc/决策约束/*.md; do
  [ -f "$_f" ] || continue
  case "$(basename "$_f")" in 索引.md|_模板.md) continue ;; esac
  [ "$(fm "$_f" status)" = "active" ] || continue
  _a=$(_auth_of "$_f")
  [ -n "$_a" ] && auth="${auth}${_a}
"
done

if [ -z "$auth" ]; then
  die "${rel} 是核心轨待裁项，但 doc/决策约束/ 下找不到生效中的总授权。

规范：授权是决策，由人在尽调阶段写在决策约束里，AI 只读（硬规则 4）。
rule-manager 的裁决权只能来自这份授权——没有授权就没有裁决权。
且只有 status: active 的决策约束算数：draft 是人还没批的稿子，
拿它当依据等于用未经批准的授权给自己发许可。

若你已经写了授权却没生效，先确认它所在文件的 status 是不是 active。
把 draft 改成 active 是人的动作，AI 不得代劳。

请在决策约束里补上总授权一节（格式见 aidf-intake），例如：

  授权:
    - type: 第三方依赖版本冲突
      paths: code/order/, code/pay/"
fi

# --- type 必须命中总授权的类型集合
ty_n=$(printf '%s' "$ty" | tr -d ' ')
types=$(printf '%s\n' "$auth" | cut -d'|' -f1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
printf '%s\n' "$types" | grep -qxF "$ty_n" || die "${rel} 的 type「${ty}」不在总授权的类型集合里，属于越权。

总授权里已有的类型：
$(printf '%s\n' "$types" | sed 's/^/    /')

请这样做其中一件：
  1. 若这条确实不属于任何已授权类型 → 降级到非核心轨（doc/待批/），等人来定
  2. 若认为它应该被授权 → 这本身是一个决策，需要人修改决策约束

注意：不要为了通过校验而改 type 去迁就授权——那是把
「被监管者选择监管规则」换了个壳，比越权本身更糟。"

# --- 每条改动路径必须是该 type 下某个授权路径的前缀子集
pth=$(field paths)
[ -z "$pth" ] && die "${rel} 缺少 paths 字段，无法做越权校验。

paths 是越权校验的另一个字段，必须写明这次实际改动到哪些路径。"

allow=$(printf '%s\n' "$auth" | awk -F'|' -v t="$ty_n" '
  { k = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
    if (k == t) print $2 }' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')

if [ -z "$allow" ]; then
  die "${rel} 的 type「${ty}」在总授权里没有配 paths，无法校验改动范围。

授权是「问题类型集合 × 路径范围」二维的，缺一维不成授权。"
fi

rec_paths=$(printf '%s' "$pth" | tr -d '[]"' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')

while IFS= read -r rp; do
  [ -z "$rp" ] && continue
  ok=0
  while IFS= read -r ap; do
    [ -z "$ap" ] && continue
    # 前缀判定：rp 以 ap 开头 ⇔ 去掉前缀后变短了
    if [ "${rp#"$ap"}" != "$rp" ]; then ok=1; break; fi
  done <<EOF
$allow
EOF
  if [ "$ok" -eq 0 ]; then
    die "${rel} 的改动路径「${rp}」超出了 type「${ty}」被授权的范围，属于越权。

该 type 下被授权的路径前缀：
$(printf '%s\n' "$allow" | sed 's/^/    /')

请这样做其中一件：
  1. 若这次确实要动授权范围外的路径 → 降级到非核心轨（doc/待批/），等人来定
  2. 若路径写错了 → 改成实际范围

不要改 paths 字段去迁就授权——那是把越权伪装成合规，比越权本身更糟。"
  fi
done <<EOF
$rec_paths
EOF

exit 0
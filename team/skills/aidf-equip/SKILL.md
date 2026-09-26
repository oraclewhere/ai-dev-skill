---
name: aidf-equip
description: aiDev-flow 团队模式的技能装配。分两层：启动时由人经结构化选项选定角色级技能，派发时由 manager 按映射表查表给 worker 配任务级技能。含双通道安装、装配后自检（查表而非判断）、推荐清单的数据形态、以及人不指定就跑时的风险声明。
---

# 技能装配

## 0. 一句话

**规则 skill 是团队自带的，能力 skill 是装配上去的。** 两者都不许假设存在。

区分这两者很重要，因为它们失败的后果不同：

| | 规则 skill（`aidf-*`） | 能力 skill（装配来的） |
|---|---|---|
| 装在哪 | 随团队一起装 | 启动时人选定 |
| 缺了会怎样 | 流程跑不动，立刻可见 | **流程照跑，产出悄悄不合框架惯例** |
| 所以 | 缺了就报错 | **缺了必须明说缺，不许假装有** |

第二种失败是本方法论最忌讳的那类：看起来有效果。所以本 skill 的重心不是"怎么装"，
是**"怎么如实报告装没装上"**。

## 1. 装配发生在两个时刻，不是一次

**这条是需求决定的，不是设计偏好**：启动时你不知道要用什么技术栈。

| 时刻 | 装配什么 | 谁定 | 依据 |
|---|---|---|---|
| **启动时** | **角色级**技能：与需求无关的能力 | 人，经结构化选项 | 这个角色要干哪类活是已知的 |
| **派发时** | **任务级**技能：语言 / 框架 / 测试方法 | manager 查表 | 尽调冻结后技术栈才确定 |

所以 develop-manager 给后端 python 的 worker 配 python 类技能，
这件事**不可能**在启动时完成——它依赖冻结后的需求。别把它硬塞进启动选项里。

## 2. 启动时：人的三档选择

用 `AskUserQuestion` 问，一次问完，每项都给推荐项。人三选一：

### 档一：装推荐项

推荐清单见 §5。它是**数据**（一张人可改的表），不是模型的目录知识——
模型不知道社区里有什么、哪些还活着、哪些和本仓库冲突。

### 档二：自定义

人给出 skill 名或来源（marketplace / git 仓库 / 本地路径）。**不要替人猜他要的是哪个。**

### 档三：什么都不装，直接跑

**允许，但必须当场给出风险，且写进装配记录。** 风险不是笼统的"质量可能下降"，
是具体的、可预期的：

> 本团队将在**没有任何领域技能**的情况下工作。具体意味着：
> - 设计与前端产出**不含框架惯例**（组件划分、无障碍、状态管理约定）
> - 后端产出**不含语言/框架的版本特定写法**，且这类缺陷**在验收标准里不会显形**
>   ——验收标准是人写的功能项，不含"符合框架惯例"
> - 测试产出**只覆盖验收标准写到的路径**，没有该技术栈的常规测试套路（边界、并发、超时）
>
> 结论：**能跑通，但返工概率更高，且返工点在收口时才暴露。**
> 你可以随时在不重启会话的前提下补装（见 §3 通道 A）。

最后一句是真话（有实测支撑）：角色级技能走通道 A 可以在**同一会话内**生效，
所以"先跑起来、缺了再补"是一个合法选项，不是错误选项。

## 3. 双通道：能立即生效的走 A，不能的走 B 并如实说

**硬事实**：`claude plugin install` 装好的插件，**当前会话看不到**。
`/reload-plugins` 是内置 CLI 命令，**模型无法代为调用**（逐字报错：它 is a built-in CLI command, not a skill）。
所以：

| | 通道 A：写 SKILL.md | 通道 B：插件 |
|---|---|---|
| 做法 | 把 `SKILL.md` 写进一个**会话启动时已存在**的 skills 目录 | `claude plugin install <p>@<marketplace> --json` |
| 同会话生效 | **是**（目录被监视，新增即被拾取） | **否** |
| 前提 | 该顶层 skills 目录**在会话启动时已存在** | 无（但 command 源插件需要人在终端接受） |
| 谁来收尾 | subagent 自己就能闭环 | **人敲 `/reload-plugins`**，或重启会话 |
| 用在哪 | 人自定义的、只在 skills 目录里的技能 | 官方 marketplace 里的插件 |

**通道 A 的那个前提必须查，不能假设**：若会话启动时那个 skills 目录还不存在，
同会话写入**不会**被拾取。`~/.claude/skills/` 通常已存在（团队自己就装在那儿），
但**首次安装**的机器上不一定——所以先 `[ -d ]` 查一下，不存在就走通道 B 或请人重启。

```bash
# 通道 A 落地前的第一件事：查目录在不在
[ -d "$HOME/.claude/skills" ] && echo "A 可用" || echo "A 不可用：本会话装了也不生效"
```

```bash
# 通道 B：--json 给出机器可读的结果，别去 grep 人话
claude plugin install security-guidance@claude-plugins-official --json
# → {"command":"install","outcome":"ok","plugin":"...","scope":"user",...}
# 失败时 outcome":"failed" + failureCode（如 not_found），退出码 1
```

`--json` 的 `outcome` 字段就是"装成功了吗"的**客观判据**，不要用模型读数判断。
注意 `claude plugin marketplace add` **不接受** `--json`。

**由 subagent 去装**（这是要求，不是优化）：装配动作会往上下文里灌一堆
安装日志、错误、目录枚举，这些对主会话是纯噪音。所以派一个 subagent 去做，
只让它带回一份结构化回执（装了什么 / outcome / 需要人做什么）。

## 4. 装配后自检：查表，不是判断

**装完必须真的调用一次。** 这是本 skill 最硬的一条。

```
对每个装配项：
  调用一次该 skill
    → 成功           → 记「已生效」
    → Unknown skill  → 记「未生效」，并写明走的是哪条通道、人需要做什么
    → 报错           → 记「装配失败」，附原文
```

**不许写"应该已生效""已安装，生效中"。** 只有"调用过一次且成功"才算生效。

为什么这条不能省：通道 B 会返回 `outcome:ok`，而本会话**用不了**。
只看安装结果就宣布成功，正是"看起来有效果"的标准形态。
自检是唯一能把它区分开的动作，而且它是**客观的**——调用结果只有三种，不含判断。

自检结果落到 `.claude/.state/equip.json`（机器状态，gitignore 掉）：

```json
{"checked": "2026-09-25T10:00:00Z",
 "items": [{"skill": "security-guidance", "role": "develop-manager",
            "channel": "plugin", "installed": true, "effective": false,
            "needs": "人敲 /reload-plugins"},
           {"skill": "py-standards", "role": "impl-worker",
            "channel": "skills-dir", "installed": true, "effective": true}]}
```

**角色在动手前必须查这张表**：`effective: false` 的技能当作**没有**。
不许"装了但没生效，先用着试试"——那会让产出看起来带了技能，实际没有。

## 5. 推荐清单：数据，不是模型的目录知识

清单存在 `doc/技能装配.md`（人维护、团队只读）。格式：

```markdown
| 角色 | skill | 来源 | 核实状态 | 说明 |
|---|---|---|---|---|
| develop-manager | pyright-lsp@claude-plugins-official | 官方 marketplace | 已核实存在 | Python 语言服务器；二进制需自行安装 |
| test-manager | security-guidance@claude-plugins-official | 官方 marketplace | 已核实存在 | 改文件前的安全审查 |
| designer | <你指定的设计类 skill> | 人指定 | 未核实 | 来源由人给 |
```

**`核实状态` 这一列是这张表的重点。** 三档，不许含糊：

- `已核实存在` —— 来自**可枚举的来源**（官方 marketplace 的注册条目）
- `人指定` —— 人给了名字或来源，团队不判断它好不好
- `未核实` —— **团队听说过的名字，但没验证过**。这一档允许存在（清单是给人改的），
  但**用它之前必须先试**，试不通就如实报"不存在"，不许因为它写在表里就当成存在

**为什么要有 `未核实` 这一档而不是直接不收**：如果只收能核实的，人就没法把
"我听说有个 X 挺好用"记下来；而如果收了却不标注，清单就退化成一份
**看起来有来源的猜测**——那比空清单更坏。

**官方 marketplace 的已核实事实**（可作为清单起点）：

- 名称 `claude-plugins-official`，源 GitHub `anthropics/claude-plugins-official`。
  首次**交互式**启动时自动添加；没有就 `claude plugin marketplace add anthropics/claude-plugins-official`
- 已核实的类别：代码智能 LSP（`pyright-lsp`、`typescript-lsp`、`gopls-lsp`、`rust-analyzer-lsp`、
  `clangd-lsp`、`jdtls-lsp`、`csharp-lsp`、`php-lsp`、`kotlin-lsp`、`lua-lsp`、`swift-lsp`）、
  外部集成（`github`、`gitlab`、`linear`、`notion`、`figma`、`vercel`、`supabase`、`sentry` 等）、
  安全审查（`security-guidance`）、开发工作流（`commit-commands`、`pr-review-toolkit`）
- **LSP 类插件的语言服务器二进制要自己先装**，插件本身不含二进制

**条目本身没有逐个枚举过**（只核实了 marketplace 的注册名与来源）——
所以清单里的具体条目仍按 `未核实` 处理，第一次用时先试。

## 6. 任务级：manager 查表，不判断

develop-manager / test-manager 在派发前，按**任务级映射表**给每个 worker 配技能：

```markdown
| 技术栈 / 能力 | skill |
|---|---|
| python | py-standards, pyright-lsp |
| typescript + react | ts-standards, frontend-design |
| 黑盒测试 | test-blackbox |
| 白盒测试 | test-whitebox |
| 反例 / 边界测试 | test-adversarial |
```

**这张表由人维护**（尽调时确定技术栈，顺手补表）。manager 只做匹配：
技术栈字段 → 表里查 → 抄 skill 名。**匹配不上就写"无匹配"，不许自己挑一个看起来像的。**

匹配不上也算正常结果：说明这个技术栈还没进表，如实报出去，
让人在回来时补一行。**这比 manager 猜一个强得多**——猜的那个会静默地生效。

### 技能怎么交给 worker

两种，按技能的确定性选：

| 情形 | 做法 | 为什么 |
|---|---|---|
| 技能**按卡固定**（如 `impl-python` 卡永远用 py-standards） | 卡里写 `skills:` 前置字段 | 正文在 worker 启动时注入它的上下文，**不经过主会话** |
| 技能**按次指定**（同一张 `impl-worker` 卡这次 python 下次 go） | 把 skill 名写进 spawn 的 prompt，让 worker 用 Skill 工具调用 | 卡的 frontmatter 是静态的，装不下每次不同的值 |

两种都**不污染主会话**：前者注入 worker 上下文，后者只传一个名字。

## 7. 关于"不污染上下文"的一条成本事实

skill 正文一旦被调用，就**作为一条消息留在对话里直到会话结束**；
自动压缩后只重新挂载最近各 skill 的**前 5,000 token**，共享 25,000 token 预算。
**调很多 skill 会让早的那些被丢掉。**

含义：**装配不是越多越好。** 装了但没调用的技能不占成本，
但一个 worker 一次调五个技能，最先调的那个可能已经不在上下文里了。
所以 §6 的映射表要窄——每个技术栈 1~2 个，不是全都要。

## 8. 你不能做的事

- **不许把"装了"说成"生效了"。** 只有 §4 的调用结果能作这个判断。
- **不许替人挑技能。** 档二由人给名字；manager 的任务级匹配是查表，不是挑选。
- **不许把清单当目录知识用。** 表里 `未核实` 的条目，用它之前先试。
- **不许改 `doc/技能装配.md`。** 那是人维护的（同硬规则 4 的道理）。

## 9. 相关

- 尽调时必须产出技术栈 → 任务级映射表的依据 → `aidf-intake`
- manager 派发与对接 → `aidf-deliver`、`aidf-verify`
- 流程状态机与装配步骤的位置 → `aidf-team`
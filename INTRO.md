# ai-dev-flow

> **把一个 AI 开发方法论，变成可以被机器执行的流程。**
> *Turning an AI-development methodology into a process a machine can enforce.*

[中文](#中文) · [English](#english) · [方法论原文](#附录方法论原文) · [Original article](#appendix-the-original-methodology)

---

# 中文

## 这个项目是什么

`ai-dev-flow` 是一个 Claude Code **skill**，配套一组**项目级 hook** 和一套**文档结构**。

它要解决的问题只有一个：**大模型的输出是概率性的，你要怎么在它身上稳定拿到符合预期的工程结果。**

它不是一套文档模板。模板只是其中最不重要的一层。真正起作用的是三个机制的组合：

| 机制 | 载体 | 作用 |
|---|---|---|
| **不变量** | 项目 `CLAUDE.md` | 常驻上下文，新 session 一进来就知道规矩 |
| **流程** | 本 skill | 可调用的标准动作 |
| **强制** | 项目 `.claude/hooks/` | 不依赖模型自觉的机械校验，**能真的拦下命令** |

关键立场：**「必须」这两个字不能交给模型自己记。** 指望概率性输出去遵守纪律，就是这套方法论要解决的那个问题本身。所以凡是能机械校验的规则，一律下沉到 hook；hook 管不了的，才写在文档里靠流程约束。

## 核心主张

> **大模型的输出是不可预测的，但通过流程管理，我们可以让它的输出保持在一个可控的需求区间内。**

大模型是概率系统。幻觉、注意力漂移、指令不遵从不是 bug，是概率性输出的必然伴生现象。消除它不可能，但在**交付节点上捕获并修正它**是可行的。

## 两类工作，两种态度

接到任何请求，第一步永远是判定它属于哪一类。分类错了，后面全错。

### 核心管理类 → 态度：完全质疑

**需求对接 / 需求分解 / 架构与技术栈 / 原型决策 / 上下文预算切分 / 最终验收。**

这类工作本质是在做决策。决策的核心不在于输出是否正确，而在于它是否基于全局上下文做出、以及是否有人能为后果负责——AI 在这两点上都不具备能力。

所以 **AI 的输出形态不是结论，是可审视的材料**：

- ✅ 输出「选项 A / B / C 对比 + 各自代价 + 影响范围 + 待决问题清单」
- ❌ 输出「我建议采用 A」（这已经是在替人做决策了）
- ✅ 把材料写进 `doc/决策约束/` 草稿，`status: draft`，等人确认后由**人**改成 `active`
- ❌ 自己把 `status` 改成 `active`

### 工程执行类 → 态度：有限怀疑

**UI 实现 / API 文档 / 测试用例 / 编码与单测 / 联调 / 评审 / 缺陷修复 / 部署。**

**不审查执行细节，只审查交付件是否满足验收标准。** 这是"有限怀疑"的全部含义：信任过程，但不信任结果会自动等于预期——每一次输出都可能带着微小偏移，不加审视会在上下游传递中堆积。

**因此有一个不可妥协的前提：验收标准必须在执行前存在，且由人写或人批准。** 不审过程就必须审标准，否则"有限怀疑"会退化成"完全不怀疑"。

## 上下文即资源

人的核心资源是时间，所以人的工作量按人/天排。**AI 的核心资源是上下文与注意力**，所以 AI 的工作量单位是：**这个任务的交付件能否在一个 session 的注意力周期内闭环。**

一个 session 的生命周期：

| 阶段 | 状态 | 对策 |
|---|---|---|
| 前段 | 注意力最好，快速进入状况 | 用它做需要理解全局的工作 |
| 中段 | 有偏移，但前文提供了场景，理解意图反而更强 | 适合执行已验证过的方案 |
| 后段 | 偏移 + 上下文混淆，意图理解变差 | 不要再开新战线 |
| 终止 | 上下文到极限，无法沟通 | 已交接完毕 |

**AI 不会突然离职，它的离职是可预测的。** 所以每个任务都必须声明上下文预算（`context_budget`），并且必须在到达 `handoff_at` 之前完成交接。

session 这个"员工"离职率极高、在职周期极短、工作能力很强——适合这种团队的工作方式只有一种：**文档先行**。交接不是离职前的临时整理，而是默认工作方式。

## 五条硬规则

1. 项目根目录必须包含 `code/` 与 `doc/`。`doc/` 下含 `决策约束/`、`交付件/`、`任务记录/`、`error/`。
2. **每一次向 `code/` 的提交，必须关联到一个存在的任务记录 ID**（commit message 中含 `task-NNNN`）。
3. **每一次合并到发布分支，必须关联到 `决策约束/` 或 `交付件/` 下的文件**。
4. `doc/决策约束/` 由人维护，AI 只读。AI 有异议只能在任务记录的「决策记录」一节提出。
5. `code/` 之外的文件（如 `scripts/`）不受规则 2 约束——**豁免由目录路径决定，不由判断决定**。

> 规则 5 的措辞是刻意的。豁免条件必须是机器一查就知的客观事实（文件在哪个目录），不能是"这算不算脚本"这类需要判断的问题。任何需要 AI 自行判断"我该不该被监管"的规则，都会在短期内退化成不存在。

规则 2 和 3 由 hook 机械校验，不是靠自觉。

## 文档结构

安装到目标项目后：

```
code/                    交付链内的代码，受硬规则约束
scripts/                 交付链外，整类豁免
doc/
  决策约束/               人维护，AI 只读。当前生效的技术栈、需求拆分结果、限制条件
  交付件/                 AI 生成，人审阅。接口契约、实现结果、测试结果
  任务记录/               commit 的关联锚点，兼对话记录
  error/                 复盘产出的违规报告，用于迭代方法论
CLAUDE.md                常驻不变量
.claude/hooks/           机械校验
```

三类 doc 的分工：

- **决策约束** —— 让新接入的 session 在遵循决策结论的前提下提供交付件
- **交付件** —— 告诉任何新接入的 session，当前已经做了哪些东西、怎么用、接口契约是什么
- **任务记录** —— 原文中"对话记录"非强制，但又要求每次提交必须关联它；非强制的东西无法作为强制的锚点，所以这里把它与工单合并成一个文件，同时充当两者

## 安装

**拆开装**，因为两者的副作用性质相反：

- **skill 装用户级**：它无副作用，不调用它什么都不做。装全局零风险，而且方法论迭代时改一处全生效。
- **hook 装项目级**：它会拦你，必须只在明确启用规范的项目里生效。

```bash
./bin/install.sh skill                     # → ~/.claude/skills/ai-dev-flow/
./bin/install.sh project /path/to/project  # → <项目>/.claude/ 与 doc 结构
```

**依赖**：`python3` 或 `jq` 之一（hook 用它解析输入 JSON），以及 `git`。很多机器没有 `jq`；只依赖 jq 的写法会让所有校验静默失效——"规则在纸上存在、在运行时不存在"是这套方法论最不能接受的一种失败，所以实现是 python3 优先、jq 回退。

**命令名由目录名决定**，不是 frontmatter 里的 `name`——所以安装目标必须叫 `ai-dev-flow/`。

装完后需要在 Claude Code 里**接受该目录的工作区信任对话框**，否则 hook 不会运行（`claude -p` 模式例外，它不检查信任）。

## 用法

```bash
/ai-dev-flow 初始化            # 生成 code-doc 结构、CLAUDE.md、项目级 hook
/ai-dev-flow 启动 <需求>        # 分类路由 → 建任务记录 / 吐决策待办
/ai-dev-flow 预算              # 把需求切成"一个 session 能闭环"的粒度
/ai-dev-flow 交接              # 生成交接说明并写回任务记录
/ai-dev-flow 验收              # 逐条对照验收标准
/ai-dev-flow 状态              # 一屏看现状
/ai-dev-flow 复盘              # 用全新上下文的 subagent 审计本次会话合规性
/ai-dev-flow 变更 <变更内容>     # 需求变更传播：升版本 + 标记 stale + 重验清单
```

自动触发**仅限已经启用本规范的项目**，判据是机器可查的客观事实：项目里存在 `doc/任务记录/` 与 `.claude/hooks/check-commit.sh`。不满足就不加载。这只是第一道闸门——上游过滤是尽力而为的，所以 skill 内部还会再查一遍。

## 强制层

| 文件 | 事件 | 做什么 |
|---|---|---|
| `check-commit.sh` | `PreToolUse` / Bash | 提交触及 `code/` 但没引用任务记录 → **拦截**；引用了不存在的 ID（伪引用）→ **拦截** |
| `check-merge.sh` | `PreToolUse` / Bash | 合并到发布分支但没关联决策约束或交付件 → **拦截** |
| `inject-context.sh` | `SessionStart` | 把决策约束、未结任务、压缩前快照送进新会话；**无未结任务时完全静默** |
| `stop-handoff.sh` | `Stop` | 有 `code/` 提交但交接说明为空 → 阻止会话结束一次，逼出交接文档 |
| `precompact-snapshot.sh` | `PreCompact` | 压缩前把状态快照落盘，供压缩后重注入。**不阻断** |
| `statusline.sh` | （状态栏配置，非 hook） | `上下文 62% · task-0001 · 未结 1 · main` |

`check-commit.sh` 的伪引用检查是刻意的：只查 ID 格式是不够的，因为模型可以编一个格式正确的 ID 来通过校验。所以它会去 `doc/任务记录/` 里找这个文件到底存不存在。

## 自测

```bash
./bin/selftest.sh      # 32 项，覆盖全部 hook 的正常与边界路径
```

**为什么自测套件是必需品而不是锦上添花**：这套东西的立论是"用机械校验替代模型自觉"。如果校验本身有 bug，结果不是"没效果"，而是**"看起来有效果"**——它不会被人发现。

自测套件搭起来的第一轮就抓出四个真实 bug，其中一个是：`section_empty` 的返回值写反了，它在"交接说明已经写好"时催办、在"没写"时放行——也就是说，**它只在你做对的时候打扰你**。上线后大概率的表现是"用户觉得烦然后关掉它"，而真正的问题一次都没被拦到。

> 一个会静默通过的校验，比没有校验更危险。

## 它做不到什么

这部分比上面的功能列表更重要，因为**知道自己能力的边界，是这套方法论自己的要求**。

- **`PreCompact` 无法注入指令、无法引导摘要**，只能阻断压缩。而阻断压缩有真实风险——若压缩是为恢复"上下文超限"错误而触发的，阻断会让当前请求直接失败。所以"压缩前强制写交接文档"**刻意没有实现**。真正能逼出交接文档的是 `Stop`，`PreCompact` 只负责不让状态蒸发。
- **机械校验只管 `commit` 和 `merge`，不管你怎么写代码。**
- **`SessionStart` 注入只是提供信息，不构成约束。**
- **流程不由 session 触发。** 触发点是 `commit` / `merge`。聊天、讨论计划、看代码不产生 commit，规范全程静默——唯一挂在 session 上的注入在没有未结任务时完全静默。
- **交接催办每个 session 最多触发一次**，且不代替判断。每轮都拦的 hook 会训练用户去关掉它。
- **最终验收判定由人做，不由 AI 做。**
- **`变更` 不自动修改任何交付件内容**，只产出清单给人看。
- **hooks 以完整用户权限执行 shell 命令。** 如果把 `.claude/` 提交进仓库，别人在未信任目录下用 `claude -p` 跑时这些 hook 仍会执行——分享前先确认这一点。
- **若运行时找不到 `python3` 也找不到 `jq`，校验会被跳过**（会明确警告，不会静默假装通过）。

## 许可证

Apache License 2.0，见 [LICENSE](LICENSE)。

---

# English

## What this is

`ai-dev-flow` is a Claude Code **skill**, together with a set of **project-level hooks** and a prescribed **document structure**.

It solves exactly one problem: **an LLM's output is probabilistic — how do you reliably get engineering results that match expectations out of it?**

This is not a collection of document templates. Templates are the least important layer. What actually does the work is the combination of three mechanisms:

| Mechanism | Carrier | Role |
|---|---|---|
| **Invariants** | Project `CLAUDE.md` | Resident context. A new session knows the rules on arrival. |
| **Process** | The skill | Callable standard procedures. |
| **Enforcement** | Project `.claude/hooks/` | Mechanical checks that do not depend on model self-discipline — and **can actually block a command**. |

The core stance: **the word "must" cannot be left for the model to remember.** Expecting probabilistic output to observe discipline *is* the problem this methodology exists to solve. So anything mechanically checkable is pushed down into a hook; only what a hook cannot check is left to prose.

## The core claim

> **LLM output is unpredictable, but through process management we can keep it within a controllable range of requirements.**

An LLM is a probabilistic system. Hallucination, attention drift, and instruction non-compliance are not bugs — they are inevitable side effects of probabilistic output. Eliminating them is impossible. **Catching and correcting them at delivery checkpoints** is not.

## Two kinds of work, two attitudes

On any request, the first step is always to decide which category it falls into. Get the category wrong and everything downstream is wrong.

### Core management work → attitude: complete distrust

**Requirement intake / decomposition / architecture and tech stack / prototype decisions / context budgeting / final acceptance.**

This work is decision-making. What matters about a decision is not whether the output is correct, but whether it was made with full context and whether someone can be held accountable for the consequences — and AI can do neither.

So **the AI's output is not a conclusion; it is reviewable material**:

- ✅ "Options A / B / C compared, each with its cost, blast radius, and open questions"
- ❌ "I recommend A" — that is already making the decision on someone's behalf
- ✅ Write the material into a `doc/决策约束/` draft with `status: draft`; a **human** flips it to `active`
- ❌ Flip `status` to `active` yourself

### Engineering execution work → attitude: limited suspicion

**UI implementation / API docs / test cases / coding and unit tests / integration / review / bug fixing / deployment.**

**Do not audit the execution details; audit only whether the deliverable meets its acceptance criteria.** That is the whole meaning of "limited suspicion": trust the process, but do not trust that the result will automatically equal the expectation — every output can carry a small drift, and unaudited drift accumulates across the pipeline.

**Which imposes a non-negotiable precondition: acceptance criteria must exist before execution, written or approved by a human.** If you will not audit the process, you must audit the criteria — otherwise "limited suspicion" degrades into "no suspicion at all".

## Context is the resource

For humans the scarce resource is time, so work is estimated in person-days. **For AI the scarce resource is context and attention**, so the unit of work is: **can this task's deliverable close the loop within one session's attention cycle?**

The lifecycle of a session:

| Phase | State | What to do with it |
|---|---|---|
| Early | Best attention, gets up to speed fast | Work that requires understanding the whole picture |
| Middle | Some drift, but prior context supplies the scene — intent comprehension is actually stronger | Execute approaches already validated |
| Late | Drift plus context confusion; intent comprehension degrades | Do not open a new front |
| End | Context limit reached, can no longer communicate | Handoff should already be done |

**AI does not resign abruptly — its departure is predictable.** Hence every task must declare a context budget (`context_budget`) and must complete its handoff before reaching `handoff_at`.

This "employee" has an extremely high turnover rate, a very short tenure, and strong ability. There is exactly one way of working that suits such a team: **documentation first.** Handoff is not a last-minute scramble before resignation; it is the default mode of work.

## The five hard rules

1. The project root must contain `code/` and `doc/`. `doc/` contains `决策约束/`, `交付件/`, `任务记录/`, `error/`.
2. **Every commit touching `code/` must be linked to an existing task-record ID** (`task-NNNN` in the commit message).
3. **Every merge to a release branch must be linked to a file under `决策约束/` or `交付件/`.**
4. `doc/决策约束/` is maintained by humans; AI is read-only. Objections go in the task record's 「决策记录」 section.
5. Files outside `code/` (e.g. `scripts/`) are exempt from rule 2 — **the exemption is decided by directory path, never by judgement.**

> Rule 5 is worded deliberately. The exemption condition must be an objective fact a machine can look up (which directory is the file in?), never a question requiring judgement ("does this count as a script?"). Any rule that requires the AI to judge whether it should be supervised will degrade into non-existence within weeks.

Rules 2 and 3 are enforced mechanically by hooks, not by good intentions.

## The document structure

After installation into a target project:

```
code/                    Code on the delivery chain — bound by the hard rules
scripts/                 Off the delivery chain — wholly exempt
doc/
  决策约束/               Human-maintained, AI read-only. Tech stack, decomposition results, constraints
  交付件/                 AI-generated, human-reviewed. API contracts, results, test output
  任务记录/               The anchor commits link to; doubles as the conversation record
  error/                  Compliance reports from retrospectives, used to iterate the methodology
CLAUDE.md                Resident invariants
.claude/hooks/           Mechanical enforcement
```

The division of labour between the three doc types:

- **Decision constraints** — so a newly attached session delivers *within* the decisions already made
- **Deliverables** — so any newly attached session knows what has been built, how to use it, and what the interface contract is
- **Task records** — the original article called a "conversation record" non-mandatory while also requiring every commit to link to one. Something non-mandatory cannot serve as an enforcement anchor, so here it is merged with the work ticket into a single file serving both roles.

## Install

**Install the two halves separately** — their side effects point in opposite directions:

- **The skill goes user-level**: it has no side effects; if you never invoke it, it does nothing. Global install is zero-risk, and iterating the methodology takes effect everywhere at once.
- **The hooks go project-level**: they will block you, so they must only be active in projects that have explicitly opted in.

```bash
./bin/install.sh skill                     # → ~/.claude/skills/ai-dev-flow/
./bin/install.sh project /path/to/project  # → <project>/.claude/ and the doc structure
```

**Dependencies**: `python3` or `jq` (the hooks use one to parse input JSON), plus `git`. Many machines lack `jq`, and a jq-only implementation would make every check **fail silently** — "the rule exists on paper but not at runtime" is the failure mode this methodology finds least acceptable. Hence python3-first with a jq fallback.

**The command name comes from the directory name**, not from frontmatter `name` — so the install target must be called `ai-dev-flow/`.

After installing, you must **accept the workspace-trust dialog** for that directory in Claude Code, or the hooks will not run (`claude -p` mode is the exception — it does not check trust).

## Usage

```bash
/ai-dev-flow 初始化            # Scaffold the code-doc structure, CLAUDE.md, project hooks
/ai-dev-flow 启动 <requirement> # Classify and route → task record, or a decision to-do
/ai-dev-flow 预算              # Split a requirement into "closes within one session" units
/ai-dev-flow 交接              # Write the handoff note back into the task record
/ai-dev-flow 验收              # Check each acceptance criterion item by item
/ai-dev-flow 状态              # One-screen status
/ai-dev-flow 复盘              # Audit this session's compliance via a fresh-context subagent
/ai-dev-flow 变更 <change>      # Propagate a requirement change: bump version, mark stale, re-verify list
```

Automatic triggering is **limited to projects where the spec is already enabled**, judged by machine-checkable facts: `doc/任务记录/` and `.claude/hooks/check-commit.sh` must exist. If they do not, the skill does not load. And that is only the first gate — upstream filtering is best-effort, so the skill re-checks internally.

## Enforcement

| File | Event | What it does |
|---|---|---|
| `check-commit.sh` | `PreToolUse` / Bash | Commit touches `code/` with no task reference → **blocked**; references a non-existent ID (fake reference) → **blocked** |
| `check-merge.sh` | `PreToolUse` / Bash | Merge to a release branch with no linked decision or deliverable doc → **blocked** |
| `inject-context.sh` | `SessionStart` | Injects decisions, open tasks, and any pre-compaction snapshot into a new session; **completely silent when there are no open tasks** |
| `stop-handoff.sh` | `Stop` | `code/` commits exist but the handoff section is empty → blocks session end once, to force the handoff note out |
| `precompact-snapshot.sh` | `PreCompact` | Writes a state snapshot to disk before compaction, for re-injection after. **Does not block.** |
| `statusline.sh` | (status line config, not a hook) | `上下文 62% · task-0001 · 未结 1 · main` |

`check-commit.sh`'s fake-reference check is deliberate: validating the ID's *format* is not enough, because a model can invent a well-formed ID to pass validation. So it goes and checks whether that task record actually exists on disk.

## Self-test

```bash
./bin/selftest.sh      # 32 assertions covering every hook's normal and boundary paths
```

**Why the suite is a necessity rather than a nicety**: the whole premise here is mechanical validation replacing model self-discipline. If the validator itself has a bug, the result is not "no effect" — it is **"the appearance of effect"**, and nobody will notice.

On its first run the suite caught four real bugs. One of them: `section_empty` returned its boolean inverted — it nagged when the handoff had been written and passed when it had not. In other words, **it only disturbed you when you had done it right.** Shipped, the likely outcome would have been "users find this annoying and turn it off", while the actual problem — the handoff never being written — was never once caught.

> A check that passes silently is more dangerous than no check at all.

## What it does not do

This section matters more than the feature list above, because **knowing the boundary of your own capability is a requirement of this methodology itself**.

- **`PreCompact` cannot inject instructions or guide summarization** — it can only block compaction. And blocking carries real risk: if compaction was triggered to recover a context-overflow error, blocking would fail the current request outright. So "force a handoff document before compaction" was **deliberately not implemented**. What actually forces the handoff out is `Stop`; `PreCompact` only stops state from evaporating.
- **Mechanical validation only covers `commit` and `merge` — it does not police how you write code.**
- **`SessionStart` injection only supplies information; it does not constitute a constraint.**
- **The process is not triggered by session.** The triggers are `commit` and `merge`. Chatting, discussing plans, and reading code produce no commits, so the spec is silent throughout — and the one session-attached injection is completely silent when there are no open tasks.
- **The handoff nudge fires at most once per session** and does not replace judgement. A hook that blocks every turn trains users to turn it off.
- **The final acceptance verdict is made by a human, not by AI.**
- **`变更` does not modify any deliverable content automatically** — it produces a list for a human to review first.
- **Hooks execute shell commands with the user's full permissions.** If you commit `.claude/` into a repository, others running `claude -p` in an untrusted directory will still have these hooks execute — verify this before sharing.
- **If neither `python3` nor `jq` is found at runtime, validation is skipped** (it warns explicitly rather than silently pretending to have checked).

## License

Apache License 2.0 — see [LICENSE](LICENSE).

---

# 附录：方法论原文

> 作者：[oraclewhere](https://github.com/oraclewhere) · 原文发表于掘金：<https://juejin.cn/post/7675911876917444618>
> 本仓库是该方法论的一个工程实现。下面收录原文全文，它是这套实现的依据。

# AI辅助开发？不，是管理AI开发

本人最近一年的高强度AI开发，最近想系统性的学一下AI开发的方法论，但我发现市面上现在的AI教程基本上就只有两类：

- 一类是演示用AI做一个实验性质的demo，整个教程中充满了大量的开发人员巧思，和针对性的提示词，通过多轮对话实现一个既定的功能
- 一类就是干脆只教你怎么把AI设置的更好用，怎么搞提示词，怎么构建一个agent智能体

这两类教程当然很好，但不是我想要的，我希望有一种能够从理论上接入当前的各种AI工具，同时基于它能够稳定达成预期的工程效果的方法论。

因此，既然这种方法论不存在，那我就自己造一个。

我打算写一个系列的AI开发的方法论文章，在这个系列的文章中我会遵循：

> **提出方法论** → **通过项目实际验证** → **完善方法论** → **引入项目风险（eg:需求变更）** → **验证方法论**

这样一个链条来完成我的文章系列。

---

## 方法论核心：

这里我先输出我方法论的核心：

> **大模型的输出是不可预测的，但通过流程管理，我们可以让它的输出保持在一个可控的需求区间内。**

大模型本质是一个概率系统，它的输出在预测空间中波动——这是它能力的来源，也是它不可靠的根源。幻觉、注意力漂移、指令不遵从，这些不是bug，而是概率性输出的必然伴生现象。试图用更精妙的提示词去彻底消除这种波动，就像日常工作中领导要求程序员不能写出任何bug一样可笑。

这其实和带团队一样。在真实的开发中，我们也没办法让员工不摸鱼、不自作主张。但一个成熟的项目并不会因此失控，因为我们的流程保证了一件事：**不管你在过程中干了什么，在Deadline之前，你必须给我一个能通过验收的输出件。** 只不过，AI的“摸鱼”无关态度，而是一种数学上的必然。所以，我们要为它设计的，是一套更精密、更无情的工程流程，让偏差在每一个交付节点上被捕获、被修正，而不是被带入下一个环节。

既然和带团队进行了类比，那么在讨论管理AI的开发流程前，我们就先从传统的开发流程看起。

---

## 传统开发流程的划分

整体上，我将传统的开发流程分为2个大类：

### 一、核心管理类

- 需求对接、需求分解与串讲
- 确认整体架构及技术栈
- 交互原型/线框图设计与评审
- 确认排期和工作量
- 产品验收/需求验收

**主要特征**：几乎都需要对整个项目进展担责的管理人员参与。

### 二、工程执行类

- UI 高保真设计及确认
- 接口 API 文档
- 测试用例设计与评审
- 前后端详细技术选型落地与模块拆分
- 前后端各模块开发与单元测试
- 前后端模块联调
- 代码评审与质量检查
- 测试执行与缺陷修复
- 部署上线与运维交接

**主要特征**：管理人员不在乎里面细节的实现，而是仅仅只对输出件进行校验判断。

---

## 使用AI时的处理原则

这里在使用AI时，我们在这2大类上的处理方式应该完全不同：

### 对于核心管理类的工作

我们对AI的输出应该持有的态度是 **“完全质疑”** ，即我们完全不信任模型的输出，对于这块工作，我们只能自己做或是充分审视AI的实现细节。

> 因为这类工作本质上是在做决策。决策的核心不在于输出本身是否正确，而在于它是否基于全局上下文做出，并且做出后是否有人能为后果负责。AI在这两点上都不具备能力——它无法真正理解全局，也无法为任何决策担责。因此，这块工作我们必须亲自把控，不能交给AI。

### 对于工程执行类的工作

我们对AI持有的态度应该是 **“有限怀疑”** ，即我们对于模型的细节工作保有一定程度的信任，不去审视AI的执行细节，而是仅仅只对交付件是否符合预期进行审视。

> 因为客观上讲，当前AI已经具备了执行具体任务的能力，尤其是在需求明确、边界清晰的场景下，这是它的强项。但为什么不能“完全相信”？因为大模型本质上是概率性预测。每一次输出都可能带着微小的偏移。单看一次可能无伤大雅，但如果不加审视，这些偏移会在上下游的传递中不断堆积，最终让整个项目偏离预期。所以，我们需要一套流程来持续修正这个堆积——不是盯着每一次输出审查，而是在关键节点上检查交付件，及时把偏移拉回来。

---

## 特别说明：确认排期和工作量

这个小类，在AI工作中我们应该进行因地制宜，我认为叫做 **“上下文注意力的生命周期管理”** 更合适。

我们知道，当模型上下文拉长后，模型会出现严重注意力漂移和指令不遵从的现象。这是客观事实，也是我所谓的管理AI的时候。

我认为，我们在给人分配工作的时候要考虑工作量是因为人力的核心资源是时间，所以我们才需要将任务拆分，并根据预期的平均工作水平估一个工作量，目的是为了分配每人的时间这个核心资源。

而AI的执行速度虽然很快，但是它的上下文和注意力是有限的，所以我们使用AI开发的时候，核心资源就从时间变成了**上下文与注意力**。

这里我们应该用管理人相同的方法，在分配工作量的时候，要保证这个需求的交付件尽可能的在一个预期的上下文就能得到结果，这就是AI版的工作量分配。

至此，我整个方法论的概述完成了。

---


了解上面方法论的概述，我们怎么基于方法论开始构建工程呢？

这里，我会提供一种基于方法论思想的开发规范，这个规范从工程生命周期开始，直至工程生命周期结束，都必须遵守，可以说是整套方法论的核心技巧。

首先，就像我们前文提到的，我们要把上下文理解为人力管理。

## 类比：AI Session = 员工

管理员工，除了人/天工作量排期之外还需要注意什么？**注意员工离职！**

如果一个员工突然离职，而他手下的项目既没有文档交接也没有口头交接，对于正在进展的项目来说，是非常危险的，甚至可能导致整个项目超期。

可是很不幸，AI就是很容易离职。

我们不妨把一个session视为一个员工：

- 在这个session的生命周期前段，AI的注意力是最好的，可以快速理解当前状况和完成工作。
- 到了session的生命周期中段，AI注意力会出现一定程度的偏移，但因为有前文提供场景，这个阶段它理解你意图的能力会比之前强。
- 而到了session的生命周期后期，也就是上下文长度快结束的时候，AI的注意力偏移和上下文混淆导致意图理解也变差，导致session很难用。
- 最后就是AI的“离职”，它的上下文到了极限，就会无法再沟通了。

不过幸运的是，AI不会突然离职，我们可以通过它的上下文来预测它什么时候会"离职"。

对于这种情况，当前的主流解决方案是在模型生命周期末期，生成交接文档，然后通过新的session接续工作。

可是，我认为，这种方法只不过是像人类离职前最后一个月，对工作进行口头交接，或是临时整理成一些文档。这种方法，对于在职周期较长，员工离职率低的团队当然够用。

但是，session员工在团队的表现是什么？它的的“离职率”很高，在职周期很短，但是工作能力很强！

那适合这种团队的工作方式是什么？

**没错，就是文档先行！**

我们必须保证“新人”接入后，能够通过文档快速理解现状。

---

## 规范设计：Code-Doc 交付件

为了保证文档先行，我认为vibing coding的项目交付件必须发生改变，我们不应该只交付一份代码，而是要交付一个 **code-doc 的集合**作为交付件。

这里，我根据自己的经验设计了一个规范：

1. 整个项目必须包含 `code` 和 `doc` 文件夹，其中 `code` 中存放的是我们的代码及其相关文件，而 `doc` 则必须包含：
   - **决策约束**
   - **对话记录**
   - **交付件文档**  
   三个文件夹。（我会在后面逐个解释这三个分类doc的作用）

2. 每次向 `code` 提交文件，必须关联到“对话记录”下的某个文件。

3. `code` 文件的每次合并到发布分支，必须关联到“决策约束”或“交付件文档”下的某个文件上。

---

## 三个doc文件夹的作用

### 决策约束
当前的决策现状，比如决策使用的技术栈，项目的需求拆分结果，等等。应当尽量包含你在当前时间点想让模型做的和不想做的限制，这个文档应该是项目管理人自己保持更新与维护的。  
**目的**：为了让新接入的session在遵循决策结论的前提下提供交付件。

### 交付件文档
包含模型所有的交付件文档，比如某个需求的实现结果，接口的调用方式，单元测试的结果等等，用于协助决策的文档，这些文档通常是模型自动生成的。  
**目的**：为了告诉任何一个新接入的session，当前已经做了哪些东西，怎么用，接口契约是什么。

### 对话记录
这个是非强制的，但我认为保存对话记录可以更好的保持溯源，方便人类理解和溯源，与优化流程。

---
以上，就是我对AI开发方法论的一些探索，欢迎大家一起讨论批评哦。
下一篇，我会遵循这个规范，开始我的第一个任务，并根据我的一个真实项目，完成**需求对接**、**需求分解**、**工作量分解**等工作，欢迎大家关注我~

---

# Appendix: The Original Methodology

> Author: [oraclewhere](https://github.com/oraclewhere) · Originally published on Juejin: <https://juejin.cn/post/7675911876917444618>
> This repository is one engineering implementation of that methodology. The full original text is reproduced above in Chinese — it is the source this implementation is answerable to.

*The original article is the author's own Chinese text and is reproduced verbatim rather than translated, so that the implementation can always be checked against the source without a layer of translation in between.*
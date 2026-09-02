# Architecture Contracts — 成品化持续开发

本文件只记录本轮要建立或修正的契约，以及与既有文档冲突时的决策。现状描述见 `codebase-audit.md`，长期真相见 `state/ARCHITECTURE.md`。

## 0. 约束继承

- iOS 18+、Swift 6、arm64、Native-First。Agent Runtime 为 Swift 原生实现，领域模型不依赖任何第三方 SDK。
- 副作用统一走 `Policy → Approval → Execute → Audit → Undo/Compensation`。既有实现已满足：`FamiliarExecutionPolicy.decide` 是纯 gate 且不接受授权参数（无法自我授权），持久授权只由 `FamiliarAuthorizationRuntime` 按 Project、工具版本、targetKey、参数 hash、期限匹配。本轮不改这条链的形状。
- 优先扩展既有实现，不新建平行的 Manager/Service/Model/Tool 体系。

## 1. Runtime 就绪契约（新增）

### 1.1 问题

Registry 与 iSH bridge 之间没有就绪协调：`prepareRuntime()` 在游离 Task 中注册 shell 工具，而 `performSend` 无条件读 `registry.manifests()` 并把结果冻结进 `FamiliarContextSnapshot`。preparing 期间发送的消息会静默失去 Shell 能力，且模型不被告知。

### 1.2 契约

统一 Runtime 生命周期为单一对外状态，取代当前两个互不同步的枚举：

- `cold`：未安装或未开始准备。
- `starting`：安装、解包、引导中。
- `ready`：全部声明能力可用。
- `degraded(reason)`：部分能力可用（例如只读 receipt 可用但 guest 未起）。

  **决策（2026-09-03）：不新增该 case。** 在 `environment_status` 解除 guest 门控之后，`failed(reason)` 已经恰好表示「guest 不可用但 receipt 仍可读」这一部分可用状态——该只读工具从来不依赖 guest。再加一个 `degraded` 只是重命名，没有任何与 `failed` 不同的产生路径，属于为抽象而抽象。真正缺的不是状态枚举，而是把 `reason` 暴露给用户的诊断界面（见 §1.3）。
- `failed(reason)`：准备失败，`reason` 必须是可读的具体原因，不是布尔。

规则：

1. Tool Registry 必须能等待就绪，或明确报告尚未就绪。发送路径不得在 `starting` 时静默产出缺工具的快照。
2. 动态注册必须幂等。`registerIfAbsent` 已满足，保持不变。
3. 工具不可用时必须暴露真实原因。`manifests()` 当前丢弃 `.unavailable(reason:)` 的 reason，必须保留并透出，而不是让工具静默消失。
4. Agent 不得调用尚未 ready 的工具。由「未 ready 则不出现在 manifests，且原因被显式告知」共同保证。
5. 不需要 guest 的工具不得被 guest 就绪门控。`environment_status` 只读磁盘 receipt，必须无条件注册。

### 1.3 Runtime Diagnostics

诊断必须机制化派生，不得硬编码文案：

- Shell 限制展示必须从 `FamiliarShellLimits` 派生，禁止字符串常量（当前 `FamiliarSettingsHubView.swift:394` 违反）。
- `maximumProcessCount` 与 `maximumMemoryBytes` 目前传入后被忽略，实际靠 guest 侧硬编码 `ulimit`（`FamiliarISHShellExecutor.swift:478`）。二者必须收敛到单一来源，否则限制展示与实际执行会漂移。

## 2. 执行状态契约（修正既有文档口径）

`state/CURRENT.md` 与 `state/ARCHITECTURE.md` 把「可恢复 Run 数据契约已接入」表述为能力就绪。代码事实是：`RunResumeCursorRecord` 与 `ToolInvocationRecord` 只写不读；`recoverInterruptedRuns` 做的是终结而非恢复。

决策：保留现有写入路径不动（它是有效的审计与防重复提交机制），但文档口径必须区分下表。

| 能力 | 状态 |
|---|---|
| 工具调用幂等防重复提交（跨重启） | 已实现（`idempotencyKey` + `invocationAlreadyCommitted`） |
| 执行审计（cursor/invocation 落盘） | 已实现 |
| 孤儿 Run 终结 | 已实现 |
| Run 暂停、恢复、跨重启续跑 | 未实现 |

统一执行状态词表中的 `paused` 与 `resumable` 当前没有任何真实产生路径。在真正实现续跑前，不得在 UI 或文档中出现这两个状态，否则构成虚假完成状态。

## 3. Memory 契约（新增）

三层 scope 的枚举已存在（`global` / `project` / `conversation`），但整条运行时链缺失。契约：

1. 写入必须经用户确认。`FamiliarMemoryCreator` 已区分 `user` 与 `agentConfirmed`。模型不得直接写入 confirmed memory；自动提议必须落为待确认状态，由用户接受后才生效。
2. 去重必须按 scope。当前 `insert` 用 `normalizedKey` 做全局匹配且该字段无唯一约束，不同 Project 的同名记忆会互相覆盖。去重键必须是 `(scope, projectID, conversationID, normalizedKey)`。
3. `lastUsedAt` 必须在实际被 Context Compiler 选中时写入。当前从不赋值却被用于排序，排序永久退化为 `updatedAt`。
4. 禁止把完整历史放入 Prompt。Context Compiler 只选与当前任务相关的记忆，并受显式字符预算约束；预算超限必须明确拒绝或截断可见，不得静默丢弃。
5. 敏感信息不得保存，需在写入边界拒绝，而不是事后清理。
6. 自动记忆可被用户关闭；关闭时不产生提议，也不读取。

`confidence` 当前硬编码为 1 且从不被读。本轮要么让它参与相关性排序，要么在文档中明确记录为未使用，不允许保留成看起来有意义的死字段。

## 4. Artifact 契约（扩展既有实现）

既有 `FamiliarArtifactValidator` 的校验链是本仓库最可信的部分之一（扩展名 + magic bytes + 真实解析 + 必需正文 + hash 一致性），不降低其严格性。扩展点：

1. DOCX 必须是合法 OOXML，已由 AnyDoc 真实解析保证，且该校验可在 arm64 Simulator 单测中真实执行（经 `TEST_HOST` / `BUNDLE_LOADER` 解析 app 二进制内的静态库）。已知薄弱点：docx magic 只查前 2 字节 `PK`，任何 ZIP 都能过签名检查，实质判定依赖 AnyDoc 解析失败。这是可接受的分层，但必须记录，不得声称 magic 检查已识别 Word 格式。
2. DOCX 生产当前只有一条路径：`environment_prepare`（装 `python-docx`，需公网）→ `shell_execute`（guest 内 Python 写 `Outputs/`）→ `artifact_publish`。仓库中没有原生 Swift OOXML writer，因此场景一的生产半程标记 `device-unverified`。
3. Agent 必须能回读已发布 Artifact。当前无 `artifact_read`，`workspace_read` 限 UTF-8 且 48 KB，DOCX 读不回来；发布后 Agent 无法自查产物，只能依赖 publish 时的 `requiredText`。
4. Artifact 版本。`FamiliarArtifact` 无版本字段（对比 `FamiliarResourceVersion` 确有 `version: Int`）；`artifact_edit` 只保留同会话内存 undo。「用户继续要求修改并生成新版本」要求真实版本表示。
5. Files 导出与分享统一走系统 ShareLink（仓库无 `fileExporter` 与 `UIDocumentPickerViewController`），这是刻意选择，不新增导出实现。

## 5. Settings 契约

1. 不允许死控件。判定标准：控件写入的值必须有运行时读取方，且该读取方不忽略它。当前违反项见 `codebase-audit.md` §5。
2. 不允许无可见控件的副作用。`FamiliarSettingsView.swift:355-364` 在一个不渲染任何通知控件的页面里静默 `setEnabled(false)`，这是 bug，不是配置。
3. 展示的限制值必须从代码派生，见 §1.3。
4. 预算必须可配置且真实生效。`maximumIterations`、`maximumToolCalls`、`maximumDuration` 与 Shell timeout 目前只有测试能覆写；UI 值必须能到达 `FamiliarAgentLoop` 初始化器（当前 `makeRuntime` 一个都不传）。
5. 每 Project 模型覆盖需要 schema、assembler、UI 三层同时新增；`FamiliarProjectContextAssembler` 当前无条件读全局 settings。

## 6. 工具定义契约（已满足，本轮维持）

每个工具必须有稳定 ID、名称、描述、输入 Schema、输出 Schema、side effect 类型、所需权限、availability、timeout、cancellation、错误类型与审计信息。既有实现已通过 `FamiliarToolManifest`、`FamiliarToolSchema` DSL、`FamiliarToolDefaults`、`FamiliarStructuredToolError` 与 `FamiliarCapabilityRequirement` 满足这一条，且合规测试从 `allCases` 机械反查。本轮不重构该层。

数组参数必须声明元素类型（`FamiliarJSONSchema` 已支持 `items`）。范围与默认值只在 `FamiliarToolDefaults` 声明一次，同时供 manifest 与 `execute` 使用，避免 schema 与行为漂移。

## 7. 冲突记录

| 冲突 | 决策 |
|---|---|
| `state/ARCHITECTURE.md:10` 称 36 实体，`:208` 称 37 实体 | 以 `Familiar/Persistence/FamiliarSchema.swift` 实际数量为准，后续更正文档 |
| `state/ARCHITECTURE.md:148` 称 Memory 有「显式搜索与写入基础」 | service 零调用方，属死代码；口径更正为「schema 已在，运行时未接线」 |
| `state/CURRENT.md` 关于可恢复 Run 的表述 | 见 §2，拆分为「审计已实现」与「续跑未实现」 |

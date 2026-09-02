# Codebase Audit — 成品化持续开发

审计日期：2026-09-02。方法：只读源码验证，不采信 `state/` 与 `docs/` 的既有描述。所有结论带 `file:line`。

## 0. 起点状态

- 分支：从 `main` 创建 `feature/familiar-product-completion`；`main` 上有 47 个已修改文件与 9 个未跟踪文件（用户在途工作），全部原样保留，未 reset、未覆盖、未清理。
- 工程：`familiar.xcodeproj`，target `Familiar` / `FamiliarMac` / `FamiliarTests` / `FamiliarUITests` / `FamiliarShareExtension` / `FamiliarWidgets`；scheme `Familiar`。
- iOS 18 最低部署目标，Swift 6，`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，`TARGETED_DEVICE_FAMILY = 1`。
- 构建/测试约束：`Vendor/ish-arm64` 只有 arm64 切片，必须使用具体 arm64 Simulator destination，不能用 `generic/platform=iOS Simulator`（见 `logs/arm64-simulator-destination-required-for-ish-linking.md`）。本机可用：`id:5E9F91D1-73AE-4236-AD61-9244CE4B3A63, OS:26.5, iPhone 17 Pro Max`。
- 测试入口：`Scripts/run-release-test-suites.sh <simulator-udid> <derived-data>`，25 个 suite 串行 + `FamiliarUITests`。

## 1. Agent Orchestrator

结论：**没有 Plan → Task → Step 状态机，只有一个扁平的工具调用迭代循环。**

- `FamiliarRunPhase`（`Familiar/Agent/FamiliarAgentLoop.swift:3-17`）有 13 个 case，但它是**展示标签**，不是状态变量：循环里没有任何 `FamiliarRunPhase` 类型的状态、没有转移表、没有转移校验。`phase(for:)`（`:1170-1175`）按工具名做字符串匹配推断阶段；`.planning` 仅因 `iteration == 0`（`:376-378`）。
- 实际控制流：`for iteration in 0..<maximumIterations`（`:348`）→ 可选上下文压缩（`:351-375`）→ 一次 provider round（`:403`）→ 无工具调用则结束（`:408-429`）→ 否则执行调用（`:436-522`）。
- 仓库中**不存在 Plan / Task / Step 领域类型**。唯一的“计划”表示是渲染用的 `FamiliarToolPresentationPayload.TaskList/.TaskItem/.TaskStatus`（`Familiar/Agent/FamiliarTool.swift:209-244`），由 `task_plan` 工具产出，**没有任何调度器读取它**。
- 唯一真正有状态的机制是交付物修复：`expectedDeliverables` / `publishedFormats` / `repairAttempts`（`:340-342`），最多 2 次修复（`:413`），交付物由**对最后一条用户消息做中英关键词匹配**推断（`inferredDeliverables`，`:1177-1189`）。
- 预算（默认值 `:273-276`）：`maximumIterations` 6、`maximumToolCalls` 24、`maximumAttemptsPerRound` 2、`maximumDuration` 600s。工具预算耗尽不再终结 Run，而是回结构化 `tool_budget_exhausted` 并对后续轮次收窄 tools（`:391`、`:463-475`）。单工具超时 `manifest.maximumExecutionDuration ?? 30`（`:766`）。
- 跨进程恢复：**不存在**。整个 Run 状态是 `run(...)` 的局部变量（`:330-347`），不序列化；`stream()` 每次新生成 `runID`（`:294`）；没有 `resume(runID:)` 入口。`FamiliarRunRecoveryService.beginCursor/updateCursor`（`Familiar/Persistence/FamiliarRunRecoveryService.swift:30-45`）写入 `nextIteration`/`phase`/`lastEventSequence`/`pendingToolCallID`，但**从未被读回用于重启 Run**；`recoverInterruptedRuns`（`:66-101`）做的是相反的事：把 running Run 一律终结为 `failed`。
- 已有的真实保护：`beginInvocation` 以 `idempotencyKey` 拒绝重复提交（`:47-56`，捕获于 `FamiliarChatController.swift:1441`）。这防重复，不等于恢复。
- Runtime 事件：`FamiliarRuntimeEventPayload`（`FamiliarAgentLoop.swift:162-181`）18 个 case，经 `FamiliarRuntimeEventEmitter` actor 单调排序（`:191-210`）。

判定：暂停 = 取消；恢复 = 缺失；检查点 = 仅审计；重试 = 仅单次内存流内。

## 2. Runtime 生命周期与 Tool Registry

### 2.1 两个互不同步的生命周期枚举，且没有 degraded

- UI 侧 `FamiliarShellRuntimeStatus.Phase`（`Familiar/Shell/FamiliarShellExecutor.swift:7-12`）：`unavailable` / `preparing` / `ready` / `failed(String)`。
- 内部 `private enum Phase`（`Familiar/Shell/FamiliarISHShellExecutor.swift:331-338`）：`notInstalled` / `installing` / `booting` / `ready` / `running(UUID)` / `failed(String)`。
- 两者没有任何同步代码路径；**都没有 `degraded`**（无部分能力表示）。

### 2.2 冷启动竞态（真实存在）

- Registry 在 `FamiliarAppDependencies.swift:109-121` 构造，**不含 shell 工具**。
- `prepareRuntime()` 在游离 `Task` 中执行（`:130-152`），包含 rootfs SHA-256 与 `ISHKernel.shared.boot`，**没有任何地方 await 它**。
- `FamiliarChatController.performSend` 在 `FamiliarChatController.swift:929` 直接 `await registry.manifests()`，**不检查就绪**；`FamiliarProjectsView.swift:695`、`FamiliarSettingsHubView.swift:849` 同样。
- `FamiliarToolRegistry` **没有任何等待就绪的原语**；`FamiliarShellRuntimeStatus.isReady`（`FamiliarShellExecutor.swift:22`）在发送路径上从未被读。
- 后果：preparing 期间发送的消息，其 `FamiliarContextSnapshot.toolManifests` 静默缺少 `shell_execute` / `environment_prepare` / `environment_status`；快照一次冻结并贯穿整个 Run（`FamiliarAgentLoop.swift:291-293`、`:330`），中途就绪也无法补入，**且不告知模型缺了什么**。

### 2.3 注册幂等性（已满足）

- `registerIfAbsent`（`FamiliarTool.swift:1031-1034`）名字已存在则静默返回；`init`/`register`（`:996`、`:1026`）重复名字 throw `duplicateTool`。字典以 name 为身份，结构上不可能重复。
- `FamiliarISHShellExecutor.prepare()`（`:61-66`）在 `.ready`/`.running` 时短路（`:362-363`），重复 retry 安全。
- 耦合缺陷：`environment_status` 是纯读磁盘 receipt 的只读工具（`FamiliarShellTool.swift:488-527`），**不需要 Linux runtime**，却被放在 `executor.prepare()` 成功之后才注册；若 bundled rootfs 缺失，`makeShellRuntime` 返回 `nil`（`FamiliarAppDependencies.swift:160`），该工具**永远不会注册**。

### 2.4 不可用原因（UI 有，模型没有）

- UI：`markFailed(error.localizedDescription)`（`FamiliarAppDependencies.swift:147`）→ `failed(String)` → `FamiliarSettingsHubView.swift:357,368` 展示 + Retry（`:404-408`）。
- 模型：不可用只表现为**工具消失**。`manifests()`（`FamiliarTool.swift:1004-1013`）过滤 `.unavailable` 时**丢弃了 reason**。能力门控类的原因确实会透出（`capabilityUnavailable(reason)`，`FamiliarAgentLoop.swift:634,673`），但那覆盖的是权限拒绝，不是 bridge 就绪。

### 2.5 Shell 限制（已实现）

值见 `FamiliarShellLimits.iOS`（`FamiliarShellExecutor.swift:138-151`）。timeout ≤180s 校验（`FamiliarISHShellExecutor.swift:75-77`）、取消（`:243,249-252,256-258`）、输出上限 1 MiB 含 512B 预留（`:122-123,169-183,203-205`）、文件/Workspace 配额 250ms 轮询（`:130-151`）、单任务串行（`:443`）、默认禁网与事后审计（`:206-222`）、每次调用 checkpoint/restore（`FamiliarShellTool.swift:282,306,352`）。

偏差：`maximumProcessCount` / `maximumMemoryBytes` 传入 `prepare(configuration:)` 后被忽略（`:361` 签名为 `configuration _:`），实际靠 guest 侧硬编码 `ulimit` 字符串（`:478`），与 `limits` 可能漂移。

### 2.6 Registry API 缺口

`actor FamiliarToolRegistry`（`FamiliarTool.swift:988-1089`）无 `unregister`/`remove`/`replace`，无 `waitUntilReady`，无 generation 计数或变更通知。这正是 2.2 竞态的直接原因。

## 3. Memory

结论：**活的 schema + 死的代码。**

- `FamiliarMemoryService`（`Familiar/Memory/FamiliarMemoryService.swift:8`）是唯一声明，**0 个调用方**。唯一的写入口 `insert`（`:18-25`）没有 caller。
- `FamiliarMemoryItem` 的 6 处引用全部是 schema 声明、typealias，或 `FamiliarProjectService.swift:202,222` 的项目删除级联。测试 `FamiliarProjectWorkspaceTests.swift:98,194` 直接构造实体、绕过 service。
- 没有 memory 工具（`memory_search|memory_write|memory_read|memory_add` 全仓库无匹配），没有 Settings 路由（`FamiliarSettingsHubView.swift:15-30` 无 memory case），`FamiliarProjectContextAssembler.swift` 中 `memory` 零匹配。
- `FamiliarMemoryItem`（`Familiar/Persistence/FamiliarSchemaV8.swift:33-52`）13 个存储属性：`id`（唯一）、`scopeRawValue`、`projectID`、`conversationID`、`content`、`normalizedKey`、`provenance`、`confidence`、`createdByRawValue`、`createdAt`、`updatedAt`、`lastUsedAt`、`isVisible`。
- 既有缺陷：`normalizedKey` 被当作去重键（`FamiliarMemoryService.swift:22`）但**没有唯一约束**，且去重**忽略 scope**（全局撞名）；`lastUsedAt` 从未被赋值，`search` 却按它排序（`:15`），排序实际退化为 `updatedAt`；`confidence` 硬编码为 1 且从不被读；`search` 先 fetch 全表再在 Swift 里过滤（`:11-14`）。

对照 P0 要求：三层 scope 的**枚举**存在，但自动提议、用户接受/拒绝、来源查看、编辑、删除、清空、导出、导入、敏感信息拒绝、自动记忆开关、Context Compiler 相关性选择与预算，**全部缺失**。

## 4. Artifact Pipeline

### 4.1 类型齐备度（名称不同但职责存在）

| 要求 | 实际 | 位置 |
|---|---|---|
| ArtifactDescriptor | `FamiliarArtifactDescriptor` | `Familiar/Artifacts/FamiliarArtifactService.swift:36` |
| ArtifactStore | `FamiliarArtifactStore` | `:99` |
| ArtifactWriter | `store.write` / `store.importFile` | `:109` / `:128` |
| ArtifactReader | `store.read` / `editableArtifact` / `service.read` | `:187` / `:204` / `:321` |
| Validator | `FamiliarArtifactValidator` | `:348-419` |
| Previewer | `FamiliarAttachmentPreviewView` + QuickLook | `Familiar/Presentation/FamiliarAttachmentQuickLookView.swift:5,55` |
| Exporter | `service.exportURL(for:)`（无独立类型） | `:342` |

缺失：无 `ArtifactVersion` 类型，无 `artifact_read` 工具。

### 4.2 DOCX 生成完全依赖 iSH guest

- 仓库中**没有任何原生 Swift OOXML writer**：`python-docx|docx.Document|from docx|openpyxl|OOXML|word/document.xml` 全仓库仅 5 处命中，全部是文档串或 schema 描述（如 `FamiliarShellTool.swift:581`）。无 ZIP 打包 OOXML 的代码；`PDFKit` 只用于读取。
- `artifact_write` 只接受 `content: String` 且 format 限 `markdown`/`plainText`（`Familiar/Artifacts/FamiliarArtifactTool.swift:4,19`）；`workspace_write` 同样只接受 UTF-8 文本（`FamiliarWorkspaceTools.swift:122,151`）。
- 唯一路径：`environment_prepare` 装 `python-docx`（`FamiliarShellTool.swift:665-669`，需公网、`destructiveWrite`、`risk: .high`、`undoPolicy: .unavailable`）→ `shell_execute` 跑 Python 写入 `Outputs/` → `artifact_publish` 校验入库。
- 因此**DOCX 生产步骤在 Simulator 上不可验证**：runtime 未 ready 时 executor 在 6 处 throw `unavailable`（`FamiliarISHShellExecutor.swift:263,275,370,424,442,496`）。

### 4.3 `artifact_publish` 校验链（真实且严格）

作用域校验（`FamiliarArtifactTool.swift:180-186`）：需 `projectID`、`workspaceID`，且 `workspaceID == .project(projectID)`；路径经 `resolveOutput` 规范化，强制 `Outputs/` 前缀、禁 `.`/`..`（`FamiliarOutputTools.swift:389-397`）。

`FamiliarArtifactValidator.validate`（`FamiliarArtifactService.swift:351-419`）：
1. `:357-358` 必须是 regular file 且非 symlink。
2. `:359-360` 大小 > 0。
3. `:361` ≤ 128 MiB。
4. `:362-364` 扩展名必须等于 `format.filenameExtension`。
5. `:371-379` docx/xlsx：`PK` magic bytes → `FamiliarAnyDocService.convert` 必须成功且产出 Markdown → checks `zip-signature` / `office-package-readable` / `extracted-text-non-empty`。pdf（`:380-386`）查 `%PDF` 后走 AnyDoc；html（`:387-393`）走 SwiftSoup；text（`:394-399`）只校 UTF-8。
6. `:401-402` 抽取正文 trim 后必须非空。
7. `:403-409` `requiredText` 去重、上限 16，逐条 `localizedCaseInsensitiveContains`。
8. `:410-418` 产出 receipt 含 `extractedTextHash`。

hash 一致性在 commit 时校验：`imported.hash == output.contentHash`（`FamiliarArtifactTool.swift:220-223`），不一致则删除目录并 throw。

缺陷：docx magic 只查前 2 字节 `PK`，任何 ZIP 都能过这一步，实际拒绝依赖 AnyDoc 解析失败。

### 4.4 AnyDoc 只读

唯一 API 是 `convert(data:filename:) -> FamiliarAnyDocConversion`（`Familiar/AnyDoc/FamiliarAnyDocService.swift:65`，返回 `:4-9`）。C 桥符号全部是 version/convert/free/error/markdown/format，**没有任何 write/render/serialize 入口**。`supportedExtensions`（`:52-59`）是输入白名单。

### 4.5 无版本、无回读

- `FamiliarArtifact`（`Familiar/Persistence/FamiliarSchemaV4.swift:12-53`）**没有 version 字段或版本关系**；对比 `FamiliarResourceVersion`（`FamiliarSchemaV3.swift:389,391`）确实有 `version: Int`。Resource 有版本，Artifact 没有。
- `store.write` 先删旧文件再移入（`FamiliarArtifactService.swift:119-120`）；`persist` 原位 upsert 只更新 `updatedAt`（`:271-285`）。`artifact_edit` 仅在内存保留旧字节供**同会话** undo（`FamiliarArtifactTool.swift:66,83,106`）——那是 undo，不是版本。
- **没有 `artifact_read` 工具**（已注册的只有 `artifact_write` / `artifact_edit` / `artifact_publish`，见 `FamiliarBaselineTests.swift:54-56`）。`workspace_read`（`FamiliarWorkspaceTools.swift:38-71`）读的是 Workspace 副本且限 UTF-8 与 48 KB，DOCX 根本读不回来。发布后 Agent 无法自查自己的 Word 文件，唯一内容证据是 publish 时的 `requiredText` 与 `extractedTextHash`。

### 4.6 预览 / 分享 / 导出

- Preview：`FamiliarAttachmentPreviewView`（`FamiliarAttachmentQuickLookView.swift:5,18`）html 走非持久化 WKWebView + CSP（`:38-50`），其余含 docx 走 `QLPreviewController`（`:55,73-87`）。入口 `FamiliarProjectsView.swift:521-523`、`FamiliarChatMessageViews.swift:2158-2159`。
- ShareLink 即 Files 导出路径（仓库无 `fileExporter`/`UIDocumentPickerViewController`）：`FamiliarProjectsView.swift:941`、`FamiliarChatMessageViews.swift:2168`。
- Agent 侧 `prepare_file_export`（`FamiliarOutputTools.swift:332-386`）只返回 `requiresUserAction: true`，不写文件，且操作 Workspace 副本而非已发布 Artifact。

### 4.7 DOCX 校验可在 Simulator 单测中真实执行

`AnyDocBridge.xcframework` 含 `ios-arm64-simulator` 静态切片（`Info.plist:13,18,23`）；它链接进 **app** target（`project.pbxproj:199,371`），`FamiliarTests` 的 Frameworks phase 为空（`:166-172`），但通过 `TEST_HOST`/`BUNDLE_LOADER`（`:600,609,616,625`）+ `@testable import Familiar` 解析到 app 二进制里的静态库。`FamiliarProjectWorkspaceTests.swift:209-239` 与 `:241-274` 真实调用 AnyDoc（断言 `office-package-readable`，该 check 只在 `convert` 返回后才追加），非 mock。

## 5. Settings 死控件

| 问题 | 位置 | 性质 |
|---|---|---|
| ~~4 个完整构建但永不渲染的 section~~ | 已删除（2026-09-03，`633deb6`） | 连同随之失效的状态、hook 与 UIKit import 一并移除 |
| ~~该页 `.task` 在未授权时静默关闭通知~~ | 已删除（2026-09-03，`633deb6`） | 该副作用随不可达 section 一并移除；Permissions 页的通知开关是唯一真实路径，未改动 |
| `Refresh models` 拉取结果不持久化，只存 `@State`（`:14,89-98,323-342`） | 同上 | 关页即丢 |
| `providerConfigurations[providerID]` 写入的是 UI 永不修改的值（`:265`，`@State` 仅 `:32` 播种） | 同上 | 恒等回写 |
| ~~Shell Limits 硬编码字符串~~ | 已修复（2026-09-03，`633deb6`） | 改为从 `FamiliarShellLimits.iOS` 派生，不再可能与执行器实际限制漂移 |
| Skill `allowedTools` 有数据契约与保留路径，但**没有任何控件**，新建恒为 `[]` | `FamiliarSettingsHubView.swift:585-586,636,699-700` | 能力无法配置 |

### P0 Settings 清单核对

| # | 项 | 判定 | 证据 |
|---|---|---|---|
| 1 | Provider 与 Model | 部分 | Model picker `FamiliarSettingsView.swift:82`；Provider 只读并强制 DeepSeek（`:71,262`、`FamiliarChatModels.swift:440`） |
| 2 | DeepSeek Key Keychain | 有 | 存 `:289`，删 `:346`，读 `FamiliarChatController.swift:222` |
| 3 | 连通性测试 | 有 | `:126-135,302-321`；搜索侧 `FamiliarSearchSettingsView.swift:64-73,180-196` |
| 4 | 默认模型 | 有（即唯一全局选择） | `FamiliarChatModels.swift:392-398,442` |
| 5 | 每 Project 模型配置 | 已补齐（2026-09-03） | `FamiliarProject.modelIDOverride`（`nil` 表示跟随全局）+ Project 编辑器 Model picker；覆盖在 `requestSettings` 固定前应用，未知 ID 在服务边界拒绝、过期 ID 回落全局 |
| 6 | Shell 超时 | 已补齐（2026-09-03） | `FamiliarShellTimeoutSettingsStore` 持久化，Shell Runtime 页 stepper；设置值同时是默认值与上限，模型只能请求更短 |
| 7 | 最大执行步数 | 已补齐（2026-09-03） | `FamiliarExecutionBudget` 持久化于 `FamiliarSettings`，经 `makeRuntime` 传入 `FamiliarAgentLoop`；设置页 stepper 范围与 `normalized` 的钳制一致 |
| 8 | 自动审批策略 | 部分 | 无策略控件；`FamiliarExecutionPolicy()` 零参构造（`FamiliarAppDependencies.swift:50`）；只有查看/撤销（`FamiliarSettingsHubView.swift:756,767`） |
| 9 | 网络策略 | 部分 | 每 Workspace shell 联网开关真实生效（`:381` → `FamiliarShellTool.swift:216` → `FamiliarISHShellExecutor.swift:466-470`）；`web_search`/`web_fetch` 与 provider 出站无控制 |
| 10 | Memory 开关与管理 | 已补齐（2026-09-03） | `.memory` 路由；自动记忆开关、按 scope 与来源列出、编辑、删除、全部删除 |
| 11 | Runtime 状态 | 已补齐（2026-09-03） | Shell runtime phase 之外，Diagnostics 页展示当前实际提供给模型的工具数与逐条不可用原因 |
| 12 | Diagnostics | 已补齐（2026-09-03） | `.diagnostics` 路由；复用 `registry.availabilityReport()` 逐条展示不可用能力与具体原因，另附 Shell Runtime phase 与当前可用工具数 |
| 13 | Logs | 部分 | Run History/Detail 只读（`:1126-1171,1188-1218`）；无原始日志捕获或导出 |
| 14 | 数据导出 | **Settings 内缺失** | ShareLink 仅存在于 chat/Projects 的单个 artifact/attachment |
| 15 | 数据清除 | **Settings 内缺失** | 仅能删 Skill、撤销授权；无「清除全部数据」 |
| 16 | 主题 | 有 | `FamiliarTheme.swift:8,32-52`；应用于 `FamiliarRootView.swift:6,15` |
| 17 | 动效开关 / Reduce Motion | 无控件，系统值已尊重 | 约 30 处 `accessibilityReduceMotion` |
| 18 | Dynamic Type | **缺失** | 全仓库 0 处 `dynamicTypeSize`/`ScaledMetric`/`sizeCategory`；同时存在固定点数与固定 frame（如 `FamiliarSettingsHubView.swift:214-219`） |
| 19 | 隐私说明 | 有 | `:172-177,1225-1241` |
| 20 | About 与许可证 | 有 | `:1243-1276,1324-1333`（6 个 bundled license 文件） |

## 6. 与既有文档的冲突（以代码为准）

- `state/ARCHITECTURE.md:208` 称 schema 37 实体，`:10` 称 36 实体，两处自相矛盾。以 `Familiar/Persistence/FamiliarSchema.swift` 为准。
- `state/CURRENT.md` 多处把「可恢复 Run 数据契约已接入」表述为能力就绪；实际只有审计写入，**没有任何读回恢复路径**（见 §1）。已在 `docs/product-completion/architecture-contracts.md` 记录决策。
- `state/ARCHITECTURE.md:148` 称 Memory「显式搜索与写入基础」；实际 service 零调用方（见 §3）。

## 7. 优先级结论

按「最小可交付垂直切片 + 修复真实缺陷优先」排序：

1. **Runtime 就绪契约**（P0-1）：Registry 增加就绪等待与不可用原因透出；把 `environment_status` 从 bridge 门控中解耦。这是唯一会导致「模型静默失去 Shell 能力」的竞态。
2. **Settings 死控件与预算接线**（P0-6/7）：删除 4 个不可达 section 及其静默禁用通知的副作用；把三个 Agent 预算与 Shell 超时接到真实持久化设置；Limits 文案改为从 `FamiliarShellLimits` 派生。
3. **Memory 三层运行时**（P0-4）：修 `normalizedKey` 唯一性/scope 去重/`lastUsedAt` 三个既有缺陷，加工具、Context Compiler 选择与预算、Settings 管理与开关。
4. **`artifact_read`**（P0-5）：让 Agent 能回读自己发布的 Artifact，闭合场景一的「继续修改并生成新版本」。
5. **Artifact 版本**（P0-5）：`FamiliarArtifact` 增加版本表示。
6. **每 Project 模型覆盖**（P0-3/6）：schema + assembler + UI 三层新增。
7. **Orchestrator 持久化执行状态**（P0-2）：把已写入的 cursor 真正读回，实现跨重启恢复。这是最大的一块，放在前述缺陷修完之后。

场景一（北京介绍 Word）的**校验、发布、预览、分享**半程可在 Simulator 单测中验证并已有覆盖；**DOCX 生产**半程依赖 iSH guest 真实启动与 `python-docx` 安装，标记 `device-unverified`，不得以任何方式伪造成功。

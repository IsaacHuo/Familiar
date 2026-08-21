# Architecture

基于当前代码验证。目标是回答"现在代码实际上长什么样"；设计目标见 `docs/02-system-architecture.md`。

## 1. 技术基线

| 领域 | 技术 |
|---|---|
| UI | SwiftUI |
| 数据模型 | SwiftData（单一当前 schema；开发阶段破坏性更新） |
| 网络 | URLSession + SSE（模型请求）；Network.framework 自研 HTTP/1.1（Web fetch） |
| 富文本 | WKWebView 非持久化 + 内置 Markdown-It、highlight.js、KaTeX、Mermaid、DOMPurify |
| 密钥 | Security.framework Keychain，`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| 日历/提醒 | EventKit full access（iOS 17+ API） |
| 文档转换 | AnyDoc Rust 引擎（`Vendor/AnyDocBridge.xcframework`，iOS arm64 + Simulator arm64） |
| PDF | PDFKit 文本层检查 + Vision OCR |
| 图片 | PhotosPicker、AVFoundation、UIKit、Vision；可选 FastVLM 0.5B（MLX + Core ML） |
| 语音 | Speech、AVAudioEngine |
| 网页解析 | SwiftSoup（SPM 2.13.7，仅 app target 链接） |

- 最低部署目标 iOS 18；FastVLM 安装路径额外要求 iOS 18.2+；`TARGETED_DEVICE_FAMILY = 1`（iPhone only）。
- Swift 6，`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。
- 唯一 entitlement：App Group `group.com.isaachuo.familiar`。
- Target：`Familiar`（app）、`FamiliarTests`（Swift Testing）、`FamiliarUITests`、`FamiliarShareExtension`（appex）、`FamiliarWidgets`（appex）。

## 2. App 入口与依赖注入

- **`Familiar/App/FamiliarApp.swift`** — `@main`。创建 `FamiliarAppDependencies`，经 `FamiliarModelContainer` 构建 `ModelContainer`：
  - store 目录 `<Application Support>/Familiar/Persistence/`（`.completeUntilFirstUserAuthentication`）。
  - store 文件名 `FamiliarDevelopment.store`。
  - 新 store 首次创建时清理旧开发 store（`FamiliarAgentV2.store`、`FamiliarAgentV1.store`、`default.store`）与失去元数据的附件、项目资源和 Artifact 目录。
  - 容器创建失败显示 `FamiliarStoreRecoveryView`，用户确认后删除当前 store、附件、项目资源与 Artifact，保留 Keychain。
- **`Familiar/App/FamiliarAppDependencies.swift`** — `@MainActor` DI 根。持有：`FamiliarToolRegistry`、`FamiliarExecutionPolicy`、`FamiliarToolConfirmationCoordinator`、`FamiliarUndoStore`、`FamiliarVisionProcessor`、`FamiliarLocalVisionModelManager`。`makeRuntime(for:)` 组装带 `FamiliarAuthorizationRuntime` 的 `FamiliarAgentLoop`。

## 3. 模块清单

### `Familiar/Agent/` — Agent 运行时
| 文件 | 职责 |
|---|---|
| `FamiliarTool.swift` | `FamiliarTool` 协议（类型化 Input）、`FamiliarToolManifest`、effect/risk/requirement、`FamiliarActionProposal`（延迟写入 + execute/undo）、`actor FamiliarToolRegistry` |
| `FamiliarAgentLoop.swift` | `struct FamiliarAgentLoop`（nonisolated）：最多 6 轮工具循环、幂等指纹、带 `effect` 与 `assistantTurnID` 的 Runtime event、真实授权查询/签发、有界重试、工具调用/总时长预算、`actor FamiliarUndoStore`、结果长度上限（48k） |
| `FamiliarRuntimeError.swift` | `FamiliarRuntimeFailure.kind(for:)` 错误分类（auth/限流/5xx/网络/上下文/参数/结果/取消等）与 `isRetryable` 判定 |
| `FamiliarModelProvider.swift` | `FamiliarModelProvider` 协议（`stream(request:apiKey:)`）、消息/内容/工具调用/Manifest 值类型 |
| `FamiliarExecutionPolicy.swift` | `FamiliarExecutionPolicy.decide(...)`：read 自动、destructive/high risk 确认、有效授权可执行；实际规则由 `FamiliarAuthorizationRuntime` 以 Project/工具版本/目标/精确参数 hash/期限匹配 |
| `FamiliarCapabilityContract.swift` | Manifest v2 字段、`FamiliarCapabilityCatalog/Resolver/Binding`、`FamiliarAuthorizationGrant`（共享规范化 arguments hash、single-use、expiry）；Capability snapshot/catalog 仍是契约层，实际免重复授权由 `FamiliarAuthorizationRuntime` 接线 |
| `FamiliarToolConfirmationCoordinator.swift` | `public actor`，`runID + toolCallID` 幂等确认，checked continuation 暂停 Agent Loop |
| `FamiliarAuthorizationRuntime.swift` | `@MainActor` SwiftData 授权查询、单次消费、session/长期授权签发与撤销范围匹配 |
| `FamiliarProjectContextAssembler.swift` | 从 Project seed + 消息快照 + 工具 manifest 组装不可变 `FamiliarContextSnapshot`；按 base→Project→本次显式选择的 Skill→安全策略注入，并以该 Skill 的 allowedTools 收窄 manifests；执行输入字符预算 |
| `FamiliarNativeTools.swift` | `current_date_time`、`app_information`（read/low） |

### `Familiar/App/` — 见 §2。

### `Familiar/Artifacts/`
- `FamiliarArtifactService.swift` — `FamiliarArtifactStore`（`<Application Support>/Familiar/Artifacts`，原子写入 + SHA-256）与 `@MainActor FamiliarArtifactService`（SwiftData `FamiliarArtifact` 事务 + 文件为真相源）。
- `FamiliarArtifactTool.swift` — `artifact_write` 工具（reversibleWrite/low），仅项目作用域，返回 `FamiliarActionProposal`。

### `Familiar/AnyDoc/`
- `FamiliarAnyDocService.swift` — Swift 到 Rust C ABI 的转换封装，返回 Markdown/格式/引擎版本/错误码，声明支持扩展名列表。

### `Familiar/Attachments/`
- `FamiliarAttachmentStore.swift` — 附件磁盘存储（`Drafts/`、`Messages/<messageID>/`）：25 MiB 上限、security-scoped 导入、路径穿越防护、草稿/提交副本、孤儿清理、OCR fallback 协调。
- `FamiliarSharedDraftImportService.swift` — 从共享收件箱取下一项导入为附件草稿。

### `Familiar/Data/` — Provider 与密钥
- `OpenAICompatibleClient.swift` — `OpenAICompatibleClient`（Chat Completions SSE）、`FamiliarProviderFactory`（协议分发）、`FamiliarProviderHTTP`（授权 URL/header/query、错误正文读取）。
- `FamiliarProviderAdapters.swift` — `AnthropicMessagesClient`、`GeminiGenerateContentClient`、`FamiliarJSONValue`。
- `FamiliarSSEParser.swift` — 仅测试 fixture 使用。
- `FamiliarKeychainStore.swift` — service `com.isaachuo.familiar.provider-api-keys.v2`，account = providerID，空 Key 删除。
- `FamiliarModelCatalogService.swift` — 模型列表拉取（30s）+ curated fallback。
- `FamiliarProviderConnectionValidator.swift` — Key/模型连接验证。

### `Familiar/Domain/` — 共享值类型
- `FamiliarChatModels.swift` — 消息/附件/来源/Run/Step 快照、设置（UserDefaults `familiar.chat.settings.v2`）。
- `FamiliarConversationMetadata.swift` — `FamiliarModelSwitchRecord`。
- `FamiliarDeepLink.swift` — `familiar://new?text=`、`familiar://conversation/<UUID>`、`familiar://run/<UUID>`。
- `FamiliarProviderCatalog.swift` — 12 内置 Provider + `custom-openai`，descriptor（endpoint/headers/auth/model catalog）。

### `Familiar/EventKit/`
- `FamiliarEventKitService.swift` — `public actor`，权限状态/请求、查询（limit 1–200）、幂等 commit、按持久 EventKit identifier undo，符合 `FamiliarCapabilityProviding`。
- `FamiliarEventKitTools.swift` — `calendar_events`、`create_calendar_event`、`reminders`、`create_reminder`。

### `Familiar/Persistence/` — SwiftData
- `FamiliarModels.swift` — 当前模型 typealias 与 `FamiliarModelContainer`；生产和测试容器直接打开单一当前 schema，不配置 migration plan。
- `FamiliarSchema.swift` — 当前 27 个实体集合与项目/会话统一置顶记录。
- `FamiliarProjectService.swift` — `@MainActor`，项目 CRUD（名称去除首尾空白并截断至 80 字符；创建/编辑时跨活跃与归档项目做不区分大小写的全局唯一检查）、指令（8k 上限）、归档、删除（运行中 Run 保护 + 资源/Artifact staged 删除/回滚；保留并解除 Conversation/Run，清理项目 Memory/授权）。
- `FamiliarRunPersistenceRecorder.swift` — `@MainActor`，**已接线**：ensureRun + ContextSnapshot/VisualEvidence 持久化、recordTool、finishRun。
- `FamiliarRunRecoveryService.swift` — `@MainActor`，capability/grant/cursor/tool-invocation 持久化 + `recoverInterruptedRuns`（启动时把遗留 running Run 终结为 failed、取消在途 invocation）；CapabilitySnapshot 与 RunResumeCursor 已接入，grant 创建/消费与字节级中断续跑仍未接入。

### `Familiar/Presentation/` — SwiftUI
- `FamiliarRootView.swift` — 首启 gate + Deep Link/Spotlight/App Intent handoff 路由。
- `FamiliarChatView.swift` — 统一 Chat Surface：顶栏依次提供设置、普通/活跃项目工作区、模型和新对话；切换工作区恢复该作用域最近更新的会话，无历史时建立未持久化空白会话。左缘手势打开的抽屉只保留搜索、置顶、可折叠项目、全部项目和普通最近会话；项目与普通最近会话按 20 条逐批展开。
- `FamiliarChatController.swift` — `@MainActor @Observable` 中央状态容器：`startSending`/`performSend` 编排整条 Agent Run。
- `FamiliarChatMessageViews.swift` — 时间线渲染；读取活动仅更新 `FamiliarAgentStatusRow`，写动作由稳定 `FamiliarToolActivityCard` 呈现，并按 `assistantTurnID` 使用横向 pager。
- `FamiliarSurfaceDescriptor.swift` — Surface Protocol：稳定 identity、effect、assistant turn group、已撤销 phase；reducer 忽略旧 sequence 防止终态被覆盖。
- `FamiliarComposerView.swift` — compact/expanded/fullscreen 输入器、附件/相机/相册、一次性 Slash Skill 选择与语音。
- `FamiliarSettingsHubView.swift` / `FamiliarSettingsView.swift` — 设置 hub 与模型服务设置；Skills 页只以右上角加号打开带默认 instructions 模板的创建表单，没有导入行，新建 Skill 的 allowedTools 为空。
- `FamiliarProjectsView.swift` — Project Context Workspace：项目列表/主页/编辑、文件/网页/文本资料与 Artifact；主页主动作回到 Chat，对话与 Runs 作为次级 Context 导航。
- `FamiliarSharedDestinationView.swift` — Share 收件箱目标选择（已有项目、新建项目、普通聊天草稿）。
- `FamiliarOnboardingView.swift` — 三步首启。
- `FamiliarMarkdownWebView.swift` — 非持久化 WKWebView 渲染 + 高度回传 + 首帧回退文本。
- `FamiliarCameraView.swift`、`FamiliarAttachmentQuickLookView.swift`、`FamiliarMarkdownNormalizer.swift`。

### `Familiar/Vision/` 与 `Familiar/LocalVision/`
- `FamiliarVisionProcessor.swift` — Apple Vision OCR、条码、图像分类，生成标记为不可信只读内容的 `FamiliarVisualEvidence`。
- `FamiliarLocalVisionModelManager.swift` — FastVLM 0.5B 的固定 manifest、设备准入、可恢复下载、SHA-256、ZIP 安全解包、Core ML 编译、基准、删除和 60 秒超时。
- `Vendor/ml-fastvlm` — Apple 官方源码的本地 Swift Package wrapper，动态从用户下载目录加载 Core ML visual encoder 与 MLX 权重。

### `Familiar/Skills/`、`Familiar/Memory/`
- `FamiliarSkillService.swift` — 严格 JSON instruction-only Skill parser、安装/更新/卸载、首次进入 Chat 时经 UserDefaults gate 一次性加入可删除示例，以及按安装 UUID 冻结确定性 Run snapshot；Composer 在普通或项目聊天中最多显式选择一个 Skill，只作用于下一次 Run，并收窄该次 Run 的工具范围。当前没有 `SkillBinding` 模型或项目自动注入路径。
- `FamiliarMemoryService.swift` — global/project/conversation 作用域的显式 Memory 搜索与写入基础；自动写入尚未开启。

### `Familiar/Resources/`
- `FamiliarProjectResourceStore.swift` — 项目资源磁盘（`<Application Support>/Familiar/ProjectResources/Projects/<projectID>/Resources/<resourceID>/Versions/<version>-<versionID>/`，SHA-256 校验、symlink/回滚安全删除）。
- `FamiliarProjectResourceService.swift` — 原子导入文档、公开 HTTPS 网页、粘贴文本与 Web capture 为 Resource + ResourceVersion。
- `FamiliarResourceTools.swift` — `resource_list/read/search`，只读取 Run 启动时冻结的 Resource 快照。

### `Familiar/Speech/`
- `FamiliarSpeechTranscriber.swift` — `@MainActor`，`SFSpeechRecognizer` + `AVAudioEngine` 流式转写（工作树已改 async/await + sessionID 失效保护）。

### `Familiar/Support/`
- `FamiliarTheme.swift` — 语义 spacing / typography / radius / icon / control tokens、基础 ButtonStyle，以及 iOS 26 `glassEffect`/material 回退 modifier。
- `FamiliarMotion.swift` — 集中 motion tokens（`micro/state/spatial/drawer`）与 `FamiliarHapticPolicy`（只标记 awaitingApproval/succeeded/failed 边界）。

### `Familiar/SystemEntry/`
- `FamiliarAppIntents.swift` — `AskFamiliar`/`ProcessWithFamiliar`/`OpenFamiliar`、`FamiliarAppIntentHandoff`（排队 system entry）。
- `FamiliarNotifications.swift` — `FamiliarNotificationService`、`FamiliarAppDelegate`（UNUserNotificationCenterDelegate）。
- `FamiliarSpotlight.swift` — `actor FamiliarSpotlightIndexer.shared`，CoreSpotlight 会话标题索引。

### `Familiar/Web/` — 只读 Web（自研受限 HTTP）
- `FamiliarWebContentService.swift` — DuckDuckGo 搜索（HTML + Lite fallback、SwiftSoup）与页面可读性抽取。
- `FamiliarRestrictedHTTPClient.swift` / `FamiliarPinnedConnection` / `FamiliarWebDNSResolver.swift` — 自研 Network.framework HTTP/1.1：getaddrinfo 公网校验、TLS SNI、手动请求/响应、重定向/大小/类型/超时限制。**刻意不用 URLSession**（避免 JS/Cookie 与系统级联行为）。
- `FamiliarWebURLPolicy.swift` — HTTPS-only、私网/保留地址拒绝。
- `FamiliarWebTools.swift` — `web_search`、`web_fetch`（read/sensitive）。
- `FamiliarWebModels.swift` — `FamiliarWebError`（16 cases）、capture、`FamiliarSourceIdentifier`。

### `Shared/`（app + 扩展共享）
- `FamiliarSharedInbox.swift` — App Group 共享收件箱（manifest + 校验）。
- `FamiliarControlIntent.swift` — `OpenFamiliarControlIntent`。

### `FamiliarWidgets/`、`FamiliarShareExtension/`
- Widget bundle（launcher + control）、`SLComposeServiceViewController` 分享面板（最多 3 文件、25 MiB）。

## 4. 启动时注册的工具（13 个）

注册位置：`FamiliarAppDependencies.init()`（`Familiar/App/FamiliarAppDependencies.swift:18`）。

| # | 工具名 | effect | risk | 权限要求 | 说明 |
|---|---|---|---|---|---|
| 1 | `current_date_time` | read | low | — | 本机时间 |
| 2 | `app_information` | read | low | — | App 信息 |
| 3 | `web_search` | read | sensitive | — | DuckDuckGo 搜索 |
| 4 | `web_fetch` | read | sensitive | — | 受限 HTTPS 抓取，可落为项目资源 |
| 5 | `resource_list` | read | low | 项目作用域 | 列出 Run 启动时冻结的 Resource |
| 6 | `resource_read` | read | low | 项目作用域 | 读取冻结 Resource 版本 |
| 7 | `resource_search` | read | low | 项目作用域 | 搜索冻结 Resource 文本 |
| 8 | `artifact_write` | reversibleWrite | low | 项目作用域 | 写入项目 Artifact，逐次确认 |
| 9 | `artifact_edit` | reversibleWrite | low | 项目作用域 | 编辑项目 Artifact，逐次确认，可在当前会话撤销 |
| 10 | `calendar_events` | read | sensitive | calendarFullAccess | 日历查询 |
| 11 | `create_calendar_event` | reversibleWrite | sensitive | calendarFullAccess | 创建事件，确认后执行 + 跨重启 EventKit undo |
| 12 | `reminders` | read | sensitive | remindersFullAccess | 提醒查询 |
| 13 | `create_reminder` | reversibleWrite | sensitive | remindersFullAccess | 创建提醒，确认后执行 + 跨重启 EventKit undo |

> 旧文档中的 8、9 或 12 个工具是加入 Resource 与 `artifact_edit` 前的历史口径。当前实际名称使用下划线形式 `resource_list/read/search`，仅 tool-capable 模型收到 manifest。

## 5. SwiftData Schema

store：`FamiliarDevelopment.store`。当前 27 个实体；开发阶段 schema 变化使用全新 store，不迁移测试数据：

| 实体 | 运行时是否写入 |
|---|---|
| Conversation, Message, SourceRecord, Attachment, ModelSwitchRecord, AgentRun, AgentStep | 是 |
| Project, ProjectInstruction | 是 |
| Resource, ResourceVersion, ContextSnapshotRecord, ContextResourceReference | 是（`FamiliarRunPersistenceRecorder` / `FamiliarProjectResourceService`） |
| Artifact | 是（`FamiliarArtifactService`） |
| CapabilitySnapshotRecord, AuthorizationGrantRecord | CapabilitySnapshot 是（Run 启动）；AuthorizationGrantRecord 否 |
| RunResumeCursorRecord, ToolInvocationRecord | 是（工具请求/审批/完成与终态 cursor；跨进程恢复未实现） |
| AuthorizationRuleRecord, EventKitUndoRecord, VisualEvidenceRecord | 是（真实授权、跨重启 Undo、视觉证据） |
| Skill, MemoryItem, MCPServerRecord, MCPBindingRecord | Skill 安装已写入；Memory 仅基础服务；MCP Runtime 尚未接线 |
| RunSkillSnapshotRecord | 是（Run 启动时冻结 Skill ID/版本/hash/allowedTools） |
| PinnedItemRecord | 是（项目/会话统一持久置顶） |

关系删除规则使用 cascade。附件文件由 Controller 显式清理；Resource 与 Artifact 文件经各自 Service 清理。单个 Artifact 删除同步删除元数据和文件；永久删除 Project 时先暂存 Resource 与 Artifact 项目目录，数据库提交后丢弃暂存目录，失败时恢复。新建开发 store 与用户确认的 store recovery 也会清理 Artifact 根目录。

## 6. 数据流（消息 → Agent → 持久化）

```text
Composer
  → FamiliarChatView.onSend
  → FamiliarChatController.startSending        // gate: 图片能力、文档能力、Key、上下文预算
      → 提交用户消息 + 附件
  → performSend
      → registry.manifests()（仅 tool-capable 模型）
      → SkillService.snapshot（Composer 最多显式选择一个；普通/项目聊天均可，仅下一次 Run）
      → FamiliarProjectContextAssembler.assemble（不可变 ContextSnapshot + Skill tool scope）
      → FamiliarAgentLoop.stream
          → provider.stream（SSE 增量 / 工具调用增量；transient/限流首字节前有界重试）
      → registry.availability + authorizationRuntime + policy.decide
          → 工具调用/总时长预算
          → toolInvocationRequested → ToolInvocationRecord requested
          → 写入工具：confirmationCoordinator 等待确认
              → approvalResolved(once/session/always) → ToolInvocationRecord approved + scoped rule (session/always)
              → 确认后执行 FamiliarActionProposal.execute + undoStore 注册
  → 事件回流 Controller
      → runRecorder.ensureRun/recordTool/finishRun（Run/Step + ContextSnapshot 持久化）
      → runRecovery（CapabilitySnapshot/Cursor/ToolInvocation 阶段记录；toolFinished → committed/cancelled/failed）
          → toolFinished → 工具终态、durable EventKit undo、Artifact 落盘、web capture → 项目资源
      → 终态 → 保存助手消息 + Sources + 可选本地通知
  → 启动时：recoverInterruptedRuns 把遗留 running Run 终结为 failed
```

主要 actors：`FamiliarToolRegistry`、`FamiliarToolConfirmationCoordinator`、`FamiliarUndoStore`、`FamiliarRuntimeEventEmitter`（private）、`FamiliarEventKitService`、`FamiliarSpotlightIndexer`。
MainActor 容器：`FamiliarChatController`、`FamiliarRunPersistenceRecorder`、`FamiliarProjectService`、`FamiliarArtifactService`、`FamiliarProjectResourceService`、`FamiliarAppIntentHandoff`、`FamiliarSpeechTranscriber`。

## 7. 存储位置

| 数据 | 位置 |
|---|---|
| SwiftData store | `<Application Support>/Familiar/Persistence/FamiliarDevelopment.store` |
| 附件 | `<Application Support>/Familiar/Attachments/{Drafts,Messages}/` |
| 项目资源 | `<Application Support>/Familiar/ProjectResources/Projects/<projectID>/...` |
| Artifact | `<Application Support>/Familiar/Artifacts` |
| FastVLM | `<Application Support>/Familiar/LocalModels/FastVLM/installed/` |
| API Key | Keychain（service `com.isaachuo.familiar.provider-api-keys.v2`） |
| Provider 设置/通知开关 | UserDefaults |
| 共享收件箱 | App Group `group.com.isaachuo.familiar` |

## 8. 已知缺口与未验证边界

- ToolInvocation/cursor、授权创建/消费均已接入；字节级中断续跑仍未实现。
- 通用 Project Capability Binding UI 未实现；Skill 使用 Composer 一次性显式调用，当前没有 Project Skill binding 或 Skill 导入 UI；Remote MCP 与 Memory Runtime 工具未实现。
- 后台承接（`BGContinuedProcessingTask`，iOS 26+）未实现；当前无后台 Run 保证。
- FastVLM、DeepSeek、EventKit 跨重启 Undo 与 Surface 视觉/无障碍仍缺真机验收；当前没有真实 Provider 冒烟结论。
- Skills 已完成显式一次性 Context 注入、工具收窄与 Run 审计快照；不支持 scripts/references/assets。Memory Runtime tools、Remote MCP 与可靠后台承接仍未实现。

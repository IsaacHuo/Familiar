# Architecture

基于当前代码（`main @ cc26ee5` + 工作树改动）验证。目标是回答"现在代码实际上长什么样"；设计目标见 `docs/02-system-architecture.md`。

## 1. 技术基线

| 领域 | 技术 |
|---|---|
| UI | SwiftUI |
| 数据模型 | SwiftData（VersionedSchema V1→V6，轻量迁移链） |
| 网络 | URLSession + SSE（模型请求）；Network.framework 自研 HTTP/1.1（Web fetch） |
| 富文本 | WKWebView 非持久化 + 内置 Markdown-It、highlight.js、KaTeX、Mermaid、DOMPurify |
| 密钥 | Security.framework Keychain，`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| 日历/提醒 | EventKit full access（iOS 17+ API） |
| 文档转换 | AnyDoc Rust 引擎（`Vendor/AnyDocBridge.xcframework`，iOS arm64 + Simulator arm64） |
| PDF | PDFKit 文本层检查 + Vision OCR |
| 图片 | PhotosPicker、AVFoundation、UIKit |
| 语音 | Speech、AVAudioEngine |
| 网页解析 | SwiftSoup（SPM 2.13.7，仅 app target 链接） |

- 最低部署目标 iOS 18；`TARGETED_DEVICE_FAMILY = 1`（iPhone only）。
- Swift 6，`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。
- 唯一 entitlement：App Group `group.com.isaachuo.familiar`。
- Target：`Familiar`（app）、`FamiliarTests`（Swift Testing）、`FamiliarUITests`、`FamiliarShareExtension`（appex）、`FamiliarWidgets`（appex）。

## 2. App 入口与依赖注入

- **`Familiar/App/FamiliarApp.swift`** — `@main`。创建 `FamiliarAppDependencies`，经 `FamiliarModelContainer` 构建 `ModelContainer`：
  - store 目录 `<Application Support>/Familiar/Persistence/`（`.completeUntilFirstUserAuthentication`）。
  - store 文件名 `FamiliarAgentV2.store`。
  - 新 store 首次创建时清理旧开发 store（`FamiliarAgentV1.store`、`default.store`）与旧附件目录。
  - 容器创建失败显示 `FamiliarStoreRecoveryView`，用户确认后删除当前 store、附件与项目资源，保留 Keychain。
- **`Familiar/App/FamiliarAppDependencies.swift`** — `@MainActor` DI 根。持有：`FamiliarToolRegistry`、`FamiliarExecutionPolicy`、`FamiliarToolConfirmationCoordinator`、`FamiliarUndoStore`。`makeRuntime(for:)` 组装 `FamiliarAgentLoop`（provider factory + registry + policy + confirmation coordinator + undo store）。

## 3. 模块清单

### `Familiar/Agent/` — Agent 运行时
| 文件 | 职责 |
|---|---|
| `FamiliarTool.swift` | `FamiliarTool` 协议（类型化 Input）、`FamiliarToolManifest`、effect/risk/requirement、`FamiliarActionProposal`（延迟写入 + execute/undo）、`actor FamiliarToolRegistry` |
| `FamiliarAgentLoop.swift` | `struct FamiliarAgentLoop`（nonisolated）：最多 6 轮工具循环、幂等指纹、`FamiliarRuntimeEventPayload`/事件流、`actor FamiliarUndoStore`、结果长度上限（48k） |
| `FamiliarModelProvider.swift` | `FamiliarModelProvider` 协议（`stream(request:apiKey:)`）、消息/内容/工具调用/Manifest 值类型 |
| `FamiliarExecutionPolicy.swift` | `FamiliarExecutionPolicy.decide(...)`：read 自动、destructive/high risk 确认、可申请读取确认；grant-aware 重载存在但未接入运行时 |
| `FamiliarCapabilityContract.swift` | Manifest v2 字段、`FamiliarCapabilityCatalog/Resolver/Binding`、`FamiliarAuthorizationGrant`（规范化 arguments hash、single-use、expiry）——契约代码，运行时未接线 |
| `FamiliarToolConfirmationCoordinator.swift` | `public actor`，`runID + toolCallID` 幂等确认，checked continuation 暂停 Agent Loop |
| `FamiliarProjectContextAssembler.swift` | 从 Project seed + 消息快照 + 工具 manifest 组装不可变 `FamiliarContextSnapshot`；注入项目指令与资源；执行输入字符预算 |
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
- `FamiliarEventKitService.swift` — `public actor`，权限状态/请求、查询（limit 1–200）、幂等 commit、undo，符合 `FamiliarCapabilityProviding`。
- `FamiliarEventKitTools.swift` — `calendar_events`、`create_calendar_event`、`reminders`、`create_reminder`。

### `Familiar/Persistence/` — SwiftData
- `FamiliarModels.swift` — `FamiliarSchemaV1`（7 实体）、typealias 映射、`FamiliarSchemaMigrationPlan`（5 个轻量 stage）、`FamiliarModelContainer`。
- `FamiliarSchemaV2..V6.swift` — 见 §4。
- `FamiliarProjectService.swift` — `@MainActor`，项目 CRUD、指令（8k 上限）、归档、删除（运行中 Run 保护 + 资源目录 staged 删除/回滚）。
- `FamiliarRunPersistenceRecorder.swift` — `@MainActor`，**已接线**：ensureRun + ContextSnapshot 持久化、recordTool、finishRun。
- `FamiliarRunRecoveryService.swift` — `@MainActor`，capability/grant/cursor/tool-invocation 持久化，**未接入运行时（仅测试）**。

### `Familiar/Presentation/` — SwiftUI
- `FamiliarRootView.swift` — 首启 gate + Deep Link/Spotlight/App Intent handoff 路由。
- `FamiliarChatView.swift` — 主界面：会话抽屉（含项目列表/最近）、聊天主体、顶栏、设置/项目 sheet、Web 浏览器入口。
- `FamiliarChatController.swift` — `@MainActor @Observable` 中央状态容器（约 900 行）：`startSending`/`performSend` 编排整条 Agent Run。
- `FamiliarChatMessageViews.swift` — 时间线渲染（消息、模型切换、工具记录、确认卡、Agent 活动、来源 disclosure）。
- `FamiliarComposerView.swift` — compact/expanded/fullscreen 输入器、附件/相机/相册、slash 命令、语音。
- `FamiliarSettingsHubView.swift` / `FamiliarSettingsView.swift` — 设置 hub 与模型服务设置。
- `FamiliarProjectsView.swift` — 项目列表/详情/编辑、资源导入。
- `FamiliarOnboardingView.swift` — 三步首启。
- `FamiliarMarkdownWebView.swift` — 非持久化 WKWebView 渲染 + 高度回传 + 首帧回退文本。
- `FamiliarCameraView.swift`、`FamiliarAttachmentQuickLookView.swift`、`FamiliarMarkdownNormalizer.swift`。

### `Familiar/Resources/`
- `FamiliarProjectResourceStore.swift` — 项目资源磁盘（`<Application Support>/Familiar/ProjectResources/Projects/<projectID>/Resources/<resourceID>/Versions/<version>-<versionID>/`，SHA-256 校验、symlink/回滚安全删除）。
- `FamiliarProjectResourceService.swift` — 导入文档/Web capture 为 Resource + ResourceVersion 记录。

### `Familiar/Speech/`
- `FamiliarSpeechTranscriber.swift` — `@MainActor`，`SFSpeechRecognizer` + `AVAudioEngine` 流式转写（工作树已改 async/await + sessionID 失效保护）。

### `Familiar/Support/`
- `FamiliarTheme.swift` — 设计令牌、iOS 26 `glassEffect`/material 回退 modifier。

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

## 4. 启动时注册的工具（9 个）

注册位置：`FamiliarAppDependencies.init()`（`Familiar/App/FamiliarAppDependencies.swift:18`）。

| # | 工具名 | effect | risk | 权限要求 | 说明 |
|---|---|---|---|---|---|
| 1 | `current_date_time` | read | low | — | 本机时间 |
| 2 | `app_information` | read | low | — | App 信息 |
| 3 | `web_search` | read | sensitive | — | DuckDuckGo 搜索 |
| 4 | `web_fetch` | read | sensitive | — | 受限 HTTPS 抓取，可落为项目资源 |
| 5 | `artifact_write` | reversibleWrite | low | 项目作用域 | 写入项目 Artifact，逐次确认 + undo |
| 6 | `calendar_events` | read | sensitive | calendarFullAccess | 日历查询 |
| 7 | `create_calendar_event` | reversibleWrite | sensitive | calendarFullAccess | 创建事件，确认后执行 + undo |
| 8 | `reminders` | read | sensitive | remindersFullAccess | 提醒查询 |
| 9 | `create_reminder` | reversibleWrite | sensitive | remindersFullAccess | 创建提醒，确认后执行 + undo |

> 文档中"8 个静态注册工具"是加入 `artifact_write` 前的旧口径；当前以本表为准（9 个）。仅 tool-capable 模型收到 manifest。

## 5. SwiftData Schema（V1→V6，当前 store 为 V6）

store：`FamiliarAgentV2.store`，`FamiliarSchemaMigrationPlan` 5 个轻量 stage（V1→V2→V3→V4→V5→V6）。当前 18 个实体：

| 实体 | 引入版本 | 运行时是否写入 |
|---|---|---|
| Conversation, Message, SourceRecord, Attachment, ModelSwitchRecord, AgentRun, AgentStep | V1 | 是 |
| Project, ProjectInstruction | V2 | 是 |
| Resource, ResourceVersion, ContextSnapshotRecord, ContextResourceReference | V3 | 是（`FamiliarRunPersistenceRecorder` / `FamiliarProjectResourceService`） |
| Artifact | V4 | 是（`FamiliarArtifactService`） |
| CapabilitySnapshotRecord, AuthorizationGrantRecord | V5 | 否（仅 schema/测试） |
| RunResumeCursorRecord, ToolInvocationRecord | V6 | 否（仅 schema/测试，`FamiliarRunRecoveryService` 未接线） |

关系删除规则使用 cascade；附件/资源文件由控制器显式清理。

## 6. 数据流（消息 → Agent → 持久化）

```text
Composer
  → FamiliarChatView.onSend
  → FamiliarChatController.startSending        // gate: 图片能力、文档能力、Key、上下文预算
      → 提交用户消息 + 附件
  → performSend
      → registry.manifests()（仅 tool-capable 模型）
      → FamiliarProjectContextAssembler.assemble（不可变 ContextSnapshot）
      → FamiliarAgentLoop.stream
          → provider.stream（SSE 增量 / 工具调用增量）
          → registry.availability + policy.decide
          → 写入工具：confirmationCoordinator 等待确认
              → 确认后执行 FamiliarActionProposal.execute + undoStore 注册
  → 事件回流 Controller
      → runRecorder.ensureRun/recordTool/finishRun（Run/Step + ContextSnapshot 持久化）
      → toolFinished → 工具终态、Artifact 落盘、web capture → 项目资源
      → 终态 → 保存助手消息 + Sources + 可选本地通知
```

主要 actors：`FamiliarToolRegistry`、`FamiliarToolConfirmationCoordinator`、`FamiliarUndoStore`、`FamiliarRuntimeEventEmitter`（private）、`FamiliarEventKitService`、`FamiliarSpotlightIndexer`。
MainActor 容器：`FamiliarChatController`、`FamiliarRunPersistenceRecorder`、`FamiliarProjectService`、`FamiliarArtifactService`、`FamiliarProjectResourceService`、`FamiliarAppIntentHandoff`、`FamiliarSpeechTranscriber`。

## 7. 存储位置

| 数据 | 位置 |
|---|---|
| SwiftData store | `<Application Support>/Familiar/Persistence/FamiliarAgentV2.store` |
| 附件 | `<Application Support>/Familiar/Attachments/{Drafts,Messages}/` |
| 项目资源 | `<Application Support>/Familiar/ProjectResources/Projects/<projectID>/...` |
| Artifact | `<Application Support>/Familiar/Artifacts` |
| API Key | Keychain（service `com.isaachuo.familiar.provider-api-keys.v2`） |
| Provider 设置/通知开关 | UserDefaults |
| 共享收件箱 | App Group `group.com.isaachuo.familiar` |

## 8. 已知缺口（与运行时未接线的部分）

- 授权/恢复数据契约已建模未接线：`FamiliarRunRecoveryService`、grant-aware policy、`FamiliarCapabilityResolver`。
- `resource.list/read/search` 工具未实现；Artifact/Binding 项目级 UI 未实现。
- Share 导入后的项目选择分流未实现。
- 后台承接（`BGContinuedProcessingTask`，iOS 26+）未实现；当前无后台 Run 保证。
- 图片输入路径为工作树未提交改动（见 `state/CURRENT.md`）。

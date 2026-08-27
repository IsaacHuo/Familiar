# Architecture

基于当前代码验证。目标是回答"现在代码实际上长什么样"；设计目标见 `docs/02-system-architecture.md`。

## 1. 技术基线

| 领域 | 技术 |
|---|---|
| UI | SwiftUI |
| 数据模型 | SwiftData（`FamiliarReleaseSchemaV1` 31 实体 + `FamiliarReleaseMigrationPlan`） |
| 网络 | URLSession + SSE（模型请求）；Network.framework 自研 HTTP/1.1（Web fetch） |
| 富文本 | WKWebView 非持久化 + 内置 Markdown-It、highlight.js、KaTeX、Mermaid、DOMPurify |
| 密钥 | Security.framework Keychain，`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| 日历/提醒 | EventKit full access（iOS 17+ API） |
| 文档转换 | AnyDoc Rust 引擎（`Vendor/AnyDocBridge.xcframework`，iOS arm64 + Simulator arm64） |
| PDF | PDFKit 文本层检查 + Vision OCR |
| 图片 | PhotosPicker、AVFoundation、UIKit、Vision；Apple Vision 生成本地只读证据，生产模型不接收图片 bytes |
| 本地文本模型 | Core AI adapter contract + ModelManager；真实 Xcode 27 Runtime/Qwen bundle 尚未接入 |
| 受控计算 | iOS iSH bridge contract；macOS Apple Containerization 0.33.4 direct Swift API |
| 语音 | Speech、AVAudioEngine |
| 网页解析 | SwiftSoup（SPM 2.13.7，仅 app target 链接） |

- iOS App 最低部署目标仍为 iOS 18；FastVLMRuntime/MLX 不在 iOS target 或 Package graph 中，研究源码仅保留在 `Vendor/`。`TARGETED_DEVICE_FAMILY = 1`（iPhone only）。
- Swift 6，`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。
- 唯一 entitlement：App Group `group.com.isaachuo.familiar`。
- Target：`Familiar`（iOS app）、`FamiliarMac`（原生 macOS app）、`FamiliarTests`（Swift Testing）、`FamiliarUITests`、`FamiliarShareExtension`（appex）、`FamiliarWidgets`（appex）。

## 2. App 入口与依赖注入

- **`Familiar/App/FamiliarApp.swift`** — `@main`。创建 `FamiliarAppDependencies`，经 `FamiliarModelContainer` 构建 `ModelContainer`：
  - store 目录 `<Application Support>/Familiar/Persistence/`（`.completeUntilFirstUserAuthentication`）。
  - Debug store 文件名 `FamiliarDevelopment.store`；Release store 文件名 `Familiar.store`。
  - 首次创建任何 store 都不自动清理旧 store 或文件目录。
  - 容器创建失败显示 `FamiliarStoreRecoveryView`，用户确认后删除当前 store、附件、项目资源与 Artifact，保留 Keychain。
  - **`Familiar/App/FamiliarAppDependencies.swift`** — `@MainActor` DI 根。持有 ToolRegistry、执行/审批/clarification/model-escalation coordinator、Workspace、原生 capability services、Web 与 Apple Vision。`makeRuntime(for:)` 以 `ModelRouter` 组合当前 descriptor 与将来的 Core AI Provider，再注入单一 `FamiliarAgentLoop`。当前 descriptor catalog 只有 DeepSeek；Runtime 不做供应商类型判断。

## 3. 模块清单

### `Familiar/Agent/` — Agent 运行时
| 文件 | 职责 |
|---|---|
| `FamiliarTool.swift` | `FamiliarTool` 协议（类型化 Input）、`FamiliarToolManifest`、effect/risk/requirement、`FamiliarToolResultEnvelope`（canonical model JSON + schema v3 typed scalar/search/document/context/records/mutation/artifact/diff/taskList/recommendation/insight/code/shareDraft payload）、有序 typed approval fields、纯预览 `FamiliarActionProposal` 与批准后 `FamiliarCommittedAction(result + undo)`、clarification proposal、`actor FamiliarToolRegistry` |
| `FamiliarAgentLoop.swift` | `struct FamiliarAgentLoop`（nonisolated）：唯一 typed Runtime event 集、`FamiliarRunOutcome` 单终态、最多 6 轮工具循环、规范化幂等指纹、read 失败内部重试一次、首字节前 Provider 重试 notice、整段 `ContinuousClock` hard deadline、最多 2 路并行独立 read、真实授权查询/签发、独立 clarification 暂停/恢复、结构化 tool failure、`actor FamiliarUndoStore`、结果长度上限（48k） |
| `FamiliarRuntimeError.swift` | `FamiliarRuntimeFailure.kind(for:)` 错误分类（auth/限流/5xx/网络/上下文/参数/结果/取消等）与 `isRetryable` 判定 |
| `FamiliarModelProvider.swift` | 无 API Key 参数的 `FamiliarModelProvider.stream(request:)` 与默认 `generate(request:)`、统一 `FamiliarToolCall`、reasoning delta、消息/内容/Manifest、`localOnly/preferLocal/cloud` 值类型 |
| `FamiliarExecutionPolicy.swift` | `FamiliarExecutionPolicy.decide(...)`：read 自动、destructive/high risk 确认、有效授权可执行；实际规则由 `FamiliarAuthorizationRuntime` 以 Project/工具版本/目标/精确参数 hash/期限匹配 |
| `FamiliarCapabilityContract.swift` | Manifest v2 字段、`FamiliarCapabilityCatalog/Resolver/Binding`、`FamiliarAuthorizationGrant`（共享规范化 arguments hash、single-use、expiry）；Capability snapshot/catalog 仍是契约层，实际免重复授权由 `FamiliarAuthorizationRuntime` 接线 |
| `FamiliarToolConfirmationCoordinator.swift` | `public actor`，`runID + toolCallID` 幂等确认，checked continuation 暂停 Agent Loop |
| `FamiliarClarificationCoordinator.swift` | `public actor`，独立于授权确认保存 pending clarification continuation；验证选项/自定义回答，支持按 Run 取消 |
| `FamiliarPresentationTools.swift` | `task_plan`、`present_recommendation`、`present_insight`、`ask_user` 四个显式只读 model-facing manifest |
| `FamiliarAuthorizationRuntime.swift` | `@MainActor` SwiftData 授权查询、单次消费、session/长期授权签发与撤销范围匹配 |
| `FamiliarProjectContextAssembler.swift` | 从 Project seed + 消息快照 + 工具 manifest 组装不可变 `FamiliarContextSnapshot`；除 Provider 输入外冻结去重后的 Attachment snapshot，供 Workspace 虚拟 Files 投影；按 base→Project→本次显式选择的 Skill→安全策略注入，并以该 Skill 的 allowedTools 收窄 manifests；执行输入字符预算 |
| `FamiliarNativeTools.swift` | `current_date_time`、`app_information`（read/low） |

### `Familiar/App/` — 见 §2。

### `Familiar/AI/Models/` — 模型生命周期与路由
- `FamiliarModelRouter.swift` — 三种路由策略；`preferLocal` 只在本地首字节前失败或不可用时请求云升级，拒绝不 fallback，已产生本地内容后不切 Provider。
- `FamiliarModelEscalationCoordinator.swift` — 与 Tool authorization 分离的 DeepSeek 出站确认 continuation 和 UI 更新流。
- `FamiliarModelManager.swift` — manifest、可恢复下载、大小/SHA-256 校验、runtime-specific prepare、原子版本目录、状态流与删除。
- `FamiliarCoreAIModelProvider.swift` — Core AI runtime adapter；当前仅有显式 unavailable adapter，真实 Xcode 27 `CoreAILanguageModel`/`LanguageModelSession` 尚未接入。

### `Familiar/Artifacts/`
- `FamiliarArtifactService.swift` — `FamiliarArtifactStore`（`<Application Support>/Familiar/Artifacts`，原子写入 + SHA-256）与 `@MainActor FamiliarArtifactService`（SwiftData `FamiliarArtifact` 事务 + 文件为真相源）。
- `FamiliarArtifactTool.swift` — `artifact_write` 工具（reversibleWrite/low），仅项目作用域，返回 `FamiliarActionProposal`。

### `Familiar/AnyDoc/`
- `FamiliarAnyDocService.swift` — Swift 到 Rust C ABI 的转换封装，返回 Markdown/格式/引擎版本/错误码，声明支持扩展名列表。

### `Familiar/Attachments/`
- `FamiliarAttachmentStore.swift` — 附件磁盘存储（`Drafts/`、`Messages/<messageID>/`）：25 MiB 上限、security-scoped 导入、路径穿越防护、草稿/提交副本、孤儿清理、OCR fallback 协调。
- `FamiliarSharedDraftImportService.swift` — 从共享收件箱取下一项导入为附件草稿。

### `Familiar/Data/` — Provider 与密钥
- `OpenAICompatibleClient.swift` — 通用 `FamiliarOpenAICompatibleModelProvider`（Chat Completions SSE）；当前 catalog/factory 只传入 DeepSeek descriptor，但 adapter、Tool Call、SSE 和错误合同不含 DeepSeek 专用分支。API Key 由 Provider 实例持有，不进入 Agent Runtime 合同。
- `FamiliarSSEParser.swift` — 仅测试 fixture 使用。
- `FamiliarKeychainStore.swift` — service `com.isaachuo.familiar.provider-api-keys.v2`，account = providerID，空 Key 删除。
- `FamiliarSearchKeychainStore.swift` — 独立 Search Provider service `com.isaachuo.familiar.search-provider-api-keys.v1`，account = Search Provider ID，不与模型 Key 共用。
- `FamiliarModelCatalogService.swift` — 模型列表拉取（30s），只返回正式 curated ID 与实时 `/models` 的交集；空交集明确失败。
- `FamiliarProviderConnectionValidator.swift` — Key/模型连接验证，要求所选模型真实出现在 `/models`。

### `Familiar/Domain/` — 共享值类型
- `FamiliarChatModels.swift` — 消息/附件/来源与只含 activities/approvals/toolResults/responseBlocks/context 的 Run 快照、设置（UserDefaults `familiar.chat.settings.v2`）。
- `FamiliarConversationMetadata.swift` — `FamiliarModelSwitchRecord`。
- `FamiliarDeepLink.swift` — `familiar://new?text=`、`familiar://conversation/<UUID>`、`familiar://run/<UUID>`。
- `FamiliarProviderCatalog.swift` — 对外只暴露 DeepSeek；旧第三方 Provider descriptor/fixture 已删除。

### `Familiar/Workspace/`、`Familiar/Native/`、`Familiar/Shell/`
- `FamiliarWorkspaceStore.swift` — Project/Conversation Workspace，Shell-visible Files/Outputs/Runtime/Work，Metadata/Tasks/Checkpoints 不挂载；路径穿越、symlink、配额、checkpoint/diff/restore。
- `FamiliarWorkspaceTools.swift` — `Files/Resources/<id>/...` 与 `Files/Attachments/<id>/...` 是当前 ContextSnapshot 的虚拟只读投影；`Outputs`/`Runtime/Work` 来自 Workspace Store。write 只允许 `Outputs`，批准后保存目标文件级旧值，Undo 不触碰其他路径；image list 只列当前会话显式附件图片。
- `FamiliarDeviceTools.swift` — Contacts 只读、单次前台 Location、Clipboard 双向确认/写入 undo、只准备 payload 的 Share；EventKit 继续独立 adapter，Spotlight 只查 Familiar 索引。
- `FamiliarShellExecutor.swift` / `FamiliarShellPolicy.swift` / `FamiliarShellTool.swift` — 统一 Shell 事件/typed result/取消/限制、危险命令确认、禁网/host path/后台/循环/编码绕过、执行前 checkpoint 与执行后 diff。真实 executor 未就绪前 `shell_execute` 不注册。
- `FamiliarISHShellExecutor.swift` — Workspace 三目录 allowlist、禁网 runtime config 和 iSH bridge contract；具体 GPL fork/bridge 尚未 vendored。
- `FamiliarContainerShellExecutor.swift` — 直接使用 LinuxContainer/exec/process API；无网络接口、三目录 VirtioFS、persistent writable layer 输入、2 vCPU/4 GiB、全局串行、取消与 idle stop。kernel/init/rootfs 下载准备尚未实现。

### `FamiliarMac/`
- `FamiliarMacApp.swift` — 原生 SwiftUI `WindowGroup + NavigationSplitView + inspector + Commands + Settings`；当前为 Codex 式桌面 shell，尚未接入共享 SwiftData/Agent Runtime。
- `FamiliarMac.entitlements` — App Sandbox、用户选择文件、Hardened Runtime 构建设置与 Virtualization entitlement。

### `Familiar/EventKit/`
- `FamiliarEventKitService.swift` — `public actor`，权限状态/请求、查询（limit 1–200）、幂等 commit、按持久 EventKit identifier undo，符合 `FamiliarCapabilityProviding`。
- `FamiliarEventKitTools.swift` — `calendar_events`、`create_calendar_event`、`reminders`、`create_reminder`。

### `Familiar/Persistence/` — SwiftData
- `FamiliarModels.swift` — 当前模型 typealias 与 `FamiliarModelContainer`；生产和测试容器直接打开单一当前 schema，不配置 migration plan。
- `FamiliarSchema.swift` — 当前 31 个实体集合与项目/会话统一置顶记录。
- `FamiliarProjectService.swift` — `@MainActor`，项目 CRUD（名称去除首尾空白并截断至 80 字符；创建/编辑时跨活跃与归档项目做不区分大小写的全局唯一检查）、指令（8k 上限）、归档、删除（运行中 Run 保护 + 资源/Artifact staged 删除/回滚；保留并解除 Conversation/Run，清理项目 Memory/授权）。
- `FamiliarRunPersistenceRecorder.swift` — `@MainActor`，**已接线**：ensureRun + ContextSnapshot/VisualEvidence、Activity/ToolResult/Approval/Clarification/ResponseBlock 持久化；tool/approval/clarification/result 在 Runtime 事件边界 upsert，task plan 按稳定 identity 更新 latest revision，最终回复一次写 block，失败/取消且无助手消息时写可重放 runtime notice recovery，text delta 不写 SwiftData。没有 AgentStep/checkpoint 投影。
- `FamiliarRunRecoveryService.swift` — `@MainActor`，capability/grant/cursor/tool-invocation 持久化 + `recoverInterruptedRuns`（启动时把遗留 running Run 终结为 failed、取消在途 invocation）；CapabilitySnapshot 与 RunResumeCursor 已接入，grant 创建/消费与字节级中断续跑仍未接入。

### `Familiar/Presentation/` — SwiftUI
- `FamiliarRootView.swift` — 首启 gate + Deep Link/Spotlight/App Intent handoff 路由。
- `FamiliarChatView.swift` — 统一 Chat Surface：顶栏依次提供设置、普通/活跃项目工作区、模型和新对话；切换工作区恢复该作用域最近更新的会话，无历史时建立未持久化空白会话。左缘手势打开的抽屉只保留搜索、置顶、可折叠项目、全部项目和普通最近会话；项目与普通最近会话按 20 条逐批展开。
- `FamiliarChatController.swift` — `@MainActor @Observable` 中央状态容器：`startSending`/`performSend` 编排整条 Agent Run。
- `FamiliarChatMessageViews.swift` — 唯一 Assistant Turn 时间线：无背景 Markdown 正文、Loading/Thinking rail、终态 Selection Actions、Task Rows、Recommendation、Swift Charts Insight、Clarification、typed Code、紧凑 Context chunks、纵向可筛选 Records、移动端 before/after Diff、紧凑 tool summary、默认折叠的来源簇、typed approval intervention、write receipt、failure recovery 与可展开 typed activity trace；Context 超过 2 条进入 sheet，Records 超过 3 条进入可搜索全屏，Diff 与长 Code 进入全屏。Selection/Recommendation 动作只填 Composer。Search trace 展示 query、结果数和已读取/仅发现统计，不逐结果生成顶级卡片。
- `FamiliarSurfaceDescriptor.swift` — 实时/历史共用的语义投影：runStatus/activityTrace/toolSummary/approval/taskList/recommendation/insight/clarification/code/search/context/records/diff/mutationReceipt/artifact/failure。scalar、searchResults、document 始终进入 trace；contextMatches、recordCollection、diff、taskList、recommendation、insight、code 进入正文后的 top-level accessory，写回执保持 top-level。
- `FamiliarComposerView.swift` — compact/expanded/fullscreen 输入器、附件/相机/相册、一次性 Slash Skill 选择与语音。
- `FamiliarSettingsHubView.swift` / `FamiliarSettingsView.swift` / `FamiliarSearchSettingsView.swift` — 设置 hub、模型服务与独立网页搜索设置；搜索页提供 Provider 选择、独立 Key 保存/删除、最小连接验证以及隐私/费用说明。Skills 页只以右上角加号打开带默认 instructions 模板的创建表单，没有导入行，新建 Skill 的 allowedTools 为空。
- `FamiliarProjectsView.swift` — Project Context Workspace：项目列表/主页/编辑、文件/网页/文本资料与 Artifact；主页主动作回到 Chat，对话与 Runs 作为次级 Context 导航。
- `FamiliarSharedDestinationView.swift` — Share 收件箱目标选择（已有项目、新建项目、普通聊天草稿）。
- `FamiliarOnboardingView.swift` — 三步首启。
- `FamiliarMarkdownWebView.swift` — 非持久化 WKWebView 渲染 + 高度回传 + 首帧回退文本；终态通过 `selectionChanged` bridge 回传最多 4000 字符纯文本，流式状态禁用并清空选择；长 Mermaid 通过 `previewMermaid` bridge 打开全屏，并复用同一 bundled renderer、非持久化 data store 与禁止远程连接的 CSP。
- `FamiliarCameraView.swift`、`FamiliarAttachmentQuickLookView.swift`、`FamiliarMarkdownNormalizer.swift`。

### `Familiar/Vision/` 与暂不提供的 `Familiar/LocalVision/`
- `FamiliarVisionProcessor.swift` — Apple Vision OCR、条码、图像分类，生成标记为不可信只读内容的 `FamiliarVisualEvidence`。
- `FamiliarLocalVisionModelManager.swift` / `Vendor/ml-fastvlm` — FastVLM 研究实现暂留，但设置入口、DI 和 Chat 自动路由已断开；当前产品不提供下载或推理入口。是否删除残留依赖另行清理。

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

### `Familiar/Web/` — 只读 Web
- `FamiliarSearchProvider.swift` / `FamiliarWebSearchService.swift` — 独立 Search Provider 契约、请求/响应、catalog/settings 与动态路由；默认 DuckDuckGo，选择保存在 `familiar.search.provider.v1`，所选服务失败不 fallback。
- `FamiliarSearchProviderAdapters.swift` — DuckDuckGo（复用 HTML + Lite SwiftSoup parser）、Brave normal web、Tavily basic（禁 answer/raw/images）、Exa fast + highlights-only；固定 HTTPS host，ephemeral URLSession 禁 Cookie/缓存/重定向，并限制超时与响应大小。
- `FamiliarWebContentService.swift` — `web_fetch` 页面读取与可读性抽取，并保留 DuckDuckGo HTML/Lite parser 供 adapter 使用。
- `FamiliarRestrictedHTTPClient.swift` / `FamiliarPinnedConnection` / `FamiliarWebDNSResolver.swift` — 自研 Network.framework HTTP/1.1：getaddrinfo 公网校验、TLS SNI、手动请求/响应、重定向/大小/类型/超时限制。**刻意不用 URLSession**（避免 JS/Cookie 与系统级联行为）。
- `FamiliarWebURLPolicy.swift` — HTTPS-only、私网/保留地址拒绝。
- `FamiliarWebTools.swift` — `web_search`、`web_fetch`（read/sensitive）。
- `FamiliarWebModels.swift` — `FamiliarWebError`（18 cases）、capture、`FamiliarSourceIdentifier`。

### `Shared/`（app + 扩展共享）
- `FamiliarSharedInbox.swift` — App Group 共享收件箱（manifest + 校验）。
- `FamiliarControlIntent.swift` — `OpenFamiliarControlIntent`。

### `FamiliarWidgets/`、`FamiliarShareExtension/`
- Widget bundle（launcher + control）、`SLComposeServiceViewController` 分享面板（最多 3 文件、25 MiB）。

## 4. 启动时注册的工具（28 个）

注册位置：`FamiliarAppDependencies.init()`。ToolRegistry 按 manifest 的 `.native / .specializedLocal / .shell` 分类保存；Agent Runtime 不硬编码具体工具。

| 分类 | 工具 |
|---|---|
| 设备原生 | `current_date_time`、`app_information`、`contacts_search`、`current_location`、`clipboard_read`、`clipboard_write`、`prepare_share`、`familiar_search` |
| EventKit | `calendar_events`、`create_calendar_event`、`reminders`、`create_reminder` |
| Workspace | `workspace_list`、`workspace_read`、`workspace_search`、`workspace_write`、`workspace_image_list` |
| Project/Artifact | `resource_list`、`resource_read`、`resource_search`、`artifact_write`、`artifact_edit` |
| Web | `web_search`、`web_fetch` |
| Presentation/interaction | `task_plan`、`present_recommendation`、`present_insight`、`ask_user` |

`shell_execute` 已实现 manifest、policy、checkpoint 和 executor contract，但在 iSH/Container runtime 资产与隔离完成验收前刻意不注册。App Intents 是系统入口，不作为模型可调用 Tool 注册。

## 5. SwiftData Schema

schema：`FamiliarReleaseSchemaV1`（version `1.0.0`），当前 31 个实体；`FamiliarReleaseMigrationPlan` 仅包含 V1，首版没有 migration stage：

| 实体 | 运行时是否写入 |
|---|---|
| Conversation, Message, SourceRecord, Attachment, ModelSwitchRecord, AgentRun | 是 |
| Project, ProjectInstruction | 是 |
| Resource, ResourceVersion, ContextSnapshotRecord, ContextResourceReference | 是（`FamiliarRunPersistenceRecorder` / `FamiliarProjectResourceService`） |
| Artifact | 是（`FamiliarArtifactService`） |
| CapabilitySnapshotRecord, AuthorizationGrantRecord | CapabilitySnapshot 是（Run 启动）；AuthorizationGrantRecord 否 |
| RunResumeCursorRecord, ToolInvocationRecord | 是（工具请求/审批/完成与终态 cursor；跨进程恢复未实现） |
| AuthorizationRuleRecord, EventKitUndoRecord, VisualEvidenceRecord | 是（真实授权、跨重启 Undo、视觉证据） |
| Skill, MemoryItem, MCPServerRecord, MCPBindingRecord | Skill 安装已写入；Memory 仅基础服务；MCP Runtime 尚未接线 |
| RunSkillSnapshotRecord | 是（Run 启动时冻结 Skill ID/版本/hash/allowedTools） |
| PinnedItemRecord | 是（项目/会话统一持久置顶） |
| ActivityRecord, ToolResultRecord, ApprovalRecord, ResponseBlockRecord | 是（Assistant Turn 的活动、结构化结果、审批审计与回复块投影） |
| ClarificationRecord | 是（typed requested/resolved/cancelled/interrupted；重启后 pending 只恢复为 interrupted 展示） |

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
          → provider.stream（正文/reasoning summary/工具调用增量；transient/限流首字节前发 typed retry notice 后有界重试）
          → 单一 ContinuousClock deadline 同时约束 provider stream、tool execute、approval wait、retry sleep
      → registry.availability + authorizationRuntime + policy.decide
          → 工具调用/总时长预算
          → toolInvocationRequested → ToolInvocationRecord requested
           → 写入工具：有序 typed fields + target/effect/risk/consequence/undo policy，经 confirmationCoordinator 等待确认
               → approvalResolved(once/session/always) → ToolInvocationRecord approved + scoped rule (session/always)
            → `ask_user`：clarificationRequested → 独立 coordinator 等待选项/自定义文本 → clarificationResolved → 回填模型继续同一 Run
           → 确认后准备 capability → FamiliarActionProposal.commit → 注册 commit 返回的 undo
           → supportsParallelism 的连续独立 read 最多并发 2 个，模型 tool result 按原 call 顺序回填；write/approval 串行
           → 成功结果封装 canonical model JSON + versioned typed presentation payload；失败结果为 code/retryable/message
  → 事件回流 Controller
      → runRecorder.ensureRun/recordActivity/recordToolResult/finishRun（Run + ContextSnapshot 持久化）
          → activity/approval/result 边界写 Activity、ToolResult、Approval；正文与 reasoning delta 不逐项写 Store
      → runRecovery（CapabilitySnapshot/Cursor/ToolInvocation 阶段记录；activityCompleted → committed/cancelled/failed）
          → toolResultProduced → typed result、Artifact 落盘、web capture → 项目资源；activityCompleted → durable EventKit undo
      → reasoningSummaryCompleted 在 Controller 内存汇总，回复完成时一次写 reasoningSummary ResponseBlock
      → runFinished(outcome) 是 Controller/Recorder/Surface 唯一 Run 终态；成功后保存 markdown ResponseBlock + Sources + 可选本地通知
          → failed/cancelled Run 写 runtime notice Activity + ResponseBlock
  → 启动时：recoverInterruptedRuns 把遗留 running Run 终结为 failed
```

主要 actors：`FamiliarToolRegistry`、`FamiliarToolConfirmationCoordinator`、`FamiliarUndoStore`、`FamiliarRuntimeEventEmitter`（private）、`FamiliarEventKitService`、`FamiliarSpotlightIndexer`。
MainActor 容器：`FamiliarChatController`、`FamiliarRunPersistenceRecorder`、`FamiliarProjectService`、`FamiliarArtifactService`、`FamiliarProjectResourceService`、`FamiliarAppIntentHandoff`、`FamiliarSpeechTranscriber`。

## 7. 存储位置

| 数据 | 位置 |
|---|---|
| SwiftData store | Debug：`<Application Support>/Familiar/Persistence/FamiliarDevelopment.store`；Release：`.../Familiar.store` |
| 附件 | `<Application Support>/Familiar/Attachments/{Drafts,Messages}/` |
| 项目资源 | `<Application Support>/Familiar/ProjectResources/Projects/<projectID>/...` |
| Artifact | `<Application Support>/Familiar/Artifacts` |
| FastVLM 残留研究资产 | `<Application Support>/Familiar/LocalModels/FastVLM/installed/`；当前无 UI/DI/自动路由入口 |
| Core AI 模型 | `<Application Support>/Familiar/Models/{Downloads,Installed,Staging}/`（当前无已配置 Qwen manifest asset） |
| Workspace | `<Application Support>/Familiar/Workspaces/{project-,conversation-}<UUID>/` |
| 模型 API Key | Keychain（service `com.isaachuo.familiar.provider-api-keys.v2`） |
| Search API Key | Keychain（service `com.isaachuo.familiar.search-provider-api-keys.v1`） |
| Provider 设置/Search Provider 选择/通知开关 | UserDefaults |
| 共享收件箱 | App Group `group.com.isaachuo.familiar` |

## 8. 已知缺口与未验证边界

- iOS 1.0 设置与 Onboarding 固定 `.cloud`，只显示 DeepSeek Flash/Pro；内部 `ModelRouter` 合同保留，但本地路由不进入生产 UI。
- 当前没有生产视觉模型。图片在本机经 Apple Vision 转成有限证据文本，原始 bytes 不发送到 DeepSeek。
- 当前开发机是 Xcode 26.6 / iOS 26.5 SDK；计划中的 Xcode 27 Core AI API、Qwen3-0.6B Core AI bundle、specialization 与真机断网流式对话尚不可编译/验收。`FamiliarCoreAIModelProvider` 目前只完成 SDK-neutral adapter contract。
- iSH 具体 GPL fork、固定上游 commit、Alpine rootfs 与 Familiar bridge 尚未加入仓库；iOS executor contract 已存在但返回 unavailable，Shell Tool 因此未注册。
- macOS 已直接编译链接 Containerization 0.33.4，并有可构造 networkless LinuxContainer 的 session/factory；Familiar runtime kernel/init/rootfs/persistent disk 的下载校验器与真实 VM 启动尚未完成。FamiliarMac 当前是原生 Codex 式 UI shell，未接入共享 SwiftData/Agent Runtime。
- Workspace 的 Files 以 Attachment/Project Resource ContextSnapshot 虚拟投影，Outputs/Runtime 保持独立目录；不做重复物理迁移。未公开的 development store 不迁入首个 Release store，也不会被自动删除。
- ToolInvocation/cursor、授权创建/消费均已接入；字节级中断续跑仍未实现。
- 通用 Project Capability Binding UI 未实现；Skill 使用 Composer 一次性显式调用，当前没有 Project Skill binding 或 Skill 导入 UI；Remote MCP 与 Memory Runtime 工具未实现。
- 后台承接（`BGContinuedProcessingTask`，iOS 26+）未实现；当前无后台 Run 保证。
- DeepSeek、Search Provider、EventKit 跨重启 Undo 与 Surface 视觉/无障碍仍缺真机验收；当前没有真实 Provider 冒烟结论。FastVLM 不进入当前验收范围。
- Skills 已完成显式一次性 Context 注入、工具收窄与 Run 审计快照；不支持 scripts/references/assets。Memory Runtime tools、Remote MCP 与可靠后台承接仍未实现。

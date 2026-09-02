# Architecture

基于当前代码验证。目标是回答"现在代码实际上长什么样"；设计目标见 `docs/02-system-architecture.md`。

## 1. 技术基线

| 领域 | 技术 |
|---|---|
| UI | SwiftUI |
| 数据模型 | SwiftData（单一 `FamiliarReleaseSchema`，37 实体，无 migration plan） |
| 网络 | URLSession + SSE（模型请求）；Network.framework 自研 HTTP/1.1（Web fetch） |
| 富文本 | WKWebView 非持久化 + 内置 Markdown-It、highlight.js、KaTeX、Mermaid、DOMPurify |
| 密钥 | Security.framework Keychain，`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| 日历/提醒 | EventKit full access（iOS 17+ API） |
| 地点 | MapKit `MKLocalSearch`（公开地点检索，返回可继续用于 WeatherKit 的坐标） |
| 天气 | WeatherKit（`com.apple.developer.weatherkit` entitlement，坐标发送给 Apple Weather） |
| 健康 | HealthKit 只读聚合（`com.apple.developer.healthkit` entitlement，仅 stepCount/activeEnergyBurned/distanceWalkingRunning） |
| 照片元数据 | PhotoKit `PHAsset` 只读元数据（时间/类型/尺寸/位置）与 add-only 保存，二者授权分离 |
| 音乐 | MusicKit 目录检索（只读元数据，不播放、不修改资料库） |
| 蓝牙 | CoreBluetooth 前台按显式 Service UUID 扫描，不连接、不读特征值 |
| 本地文本分析 | NaturalLanguage（语言识别、情感分数、命名实体，全部在设备上） |
| 本地通知 | UserNotifications（无 plist key，运行时授权） |
| 闹钟 | AlarmKit（iOS 26.1+ 门控，必须声明 `NSAlarmKitUsageDescription`，alert-only presentation） |
| 文档转换 | AnyDoc Rust 引擎（`Vendor/AnyDocBridge.xcframework`，iOS arm64 + Simulator arm64） |
| PDF | PDFKit 文本层检查 + Vision OCR |
| 图片 | PhotosPicker、AVFoundation、UIKit、Vision；Apple Vision 生成本地只读证据，生产模型不接收图片 bytes |
| 本地文本模型 | Core AI adapter contract + ModelManager；真实 Xcode 27 Runtime/Qwen bundle 尚未接入 |
| 受控计算 | iOS ARM64 iSH/Alpine headless runtime；macOS Apple Containerization 0.33.4 direct Swift API |
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
  - **`Familiar/App/FamiliarAppDependencies.swift`** — `@MainActor` DI 根。持有 ToolRegistry、执行/审批/clarification/model-escalation coordinator、Workspace、原生 capability services、Web 与 Apple Vision。`makeRuntime(for:)` 以 `ModelRouter` 组合当前 descriptor 与将来的 Core AI Provider，再注入单一 `FamiliarAgentLoop`，并把设置中持久化的 `FamiliarExecutionBudget`（步数/工具调用/时长）经 `normalized` 钳制后传入——此前这三个预算只是初始化器默认值，只有测试能覆写。当前 descriptor catalog 只有 DeepSeek；Runtime 不做供应商类型判断。

## 3. 模块清单

### `Familiar/Agent/` — Agent 运行时
| 文件 | 职责 |
|---|---|
| `FamiliarTool.swift` | `FamiliarTool` 协议（类型化 Input）、`FamiliarToolManifest`、effect/risk/requirement、`FamiliarToolResultEnvelope`（canonical model JSON + schema v3 typed scalar/search/document/context/records/mutation/artifact/diff/taskList/recommendation/insight/code/shareDraft payload）、有序 typed approval fields、纯预览 `FamiliarActionProposal` 与批准后 `FamiliarCommittedAction(result + undo)`、clarification proposal、`actor FamiliarToolRegistry`（`availabilityReport()` 保留 `.unavailable(reason:)` 的真实原因；`manifests()` 由它派生，因此不可用能力不再只是从工具列表中静默消失）、`FamiliarUnavailableTool`/`FamiliarToolAvailabilityReport`；`FamiliarStructuredToolError` 定义稳定 code/retryable 契约；`FamiliarToolAuthorizationAssessment` 可由 `preflight` 提供真实读取范围 fields/consequence/targetKey；`FamiliarCapabilityRequirement` 声明各能力所需的 plist key、entitlement 与 privacy 数据类型，供合规契约测试机械反查 |
| `FamiliarAgentLoop.swift` | `struct FamiliarAgentLoop`（nonisolated）：唯一 typed Runtime event 集、`FamiliarRunOutcome` 单终态、最多 6 轮工具循环、规范化幂等指纹、read 失败内部重试一次、首字节前 Provider 重试 notice、整段 `ContinuousClock` hard deadline、最多 2 路并行独立 read、独立 clarification 暂停/恢复、结构化 tool failure（任何 `FamiliarStructuredToolError` 直接透出 code）。工具调用预算耗尽与最后一轮迭代不再抛错终结 Run，而是把请求的 tools 收窄为空并追加系统消息要求立即基于已有信息作答（发 `budgetExhausted` notice 供审计）；迭代耗尽只在确实没有任何正文可交付时才失败、`actor FamiliarUndoStore`、结果长度上限（48k）。`preflight` 先于审批执行，敏感 read（health/photos/bluetooth）与写入分别接入 `authorizationRuntime`：read 只允许仅这次/本会话，命中既有授权时不再打断并记为自动授权 |
| `FamiliarRuntimeError.swift` | `FamiliarRuntimeFailure.kind(for:)` 错误分类（auth/限流/5xx/网络/上下文/参数/结果/取消等）与 `isRetryable` 判定 |
| `FamiliarModelProvider.swift` | 无 API Key 参数的 `FamiliarModelProvider.stream(request:)` 与默认 `generate(request:)`、统一 `FamiliarToolCall`、reasoning delta、消息/内容/Manifest、`localOnly/preferLocal/cloud` 值类型 |
| `FamiliarExecutionPolicy.swift` | 纯 gate `decide(manifest:availability:)`：unavailable 拒绝、destructive 或 high risk 必须确认、能力就绪的 read 直接执行、其余走审批。策略本身不接受任何授权参数，无法自我授权；持久授权只由 `FamiliarAuthorizationRuntime` 按 Project/工具版本/targetKey/精确参数 hash/期限匹配 |
| `FamiliarCapabilityContract.swift` | Manifest v2 字段、`FamiliarCapabilityCatalog/Resolver/Binding`、`FamiliarAuthorizationGrant`（共享规范化 arguments hash、single-use、expiry）；Capability snapshot/catalog 仍是契约层，实际免重复授权由 `FamiliarAuthorizationRuntime` 接线 |
| `FamiliarToolConfirmationCoordinator.swift` | `public actor`，`runID + toolCallID` 幂等确认，checked continuation 暂停 Agent Loop |
| `FamiliarClarificationCoordinator.swift` | `public actor`，独立于授权确认保存 pending clarification continuation；验证选项/自定义回答，支持按 Run 取消 |
| `FamiliarPresentationTools.swift` | `task_plan`、`present_recommendation`、`present_insight`、`ask_user` 四个显式只读 model-facing manifest |
| `FamiliarAuthorizationRuntime.swift` | `@MainActor` SwiftData 授权查询、单次消费、session/长期授权签发与撤销范围匹配 |
| `FamiliarProjectContextAssembler.swift` | 从 Project seed + 消息快照 + 工具 manifest 组装不可变 `FamiliarContextSnapshot`；除 Provider 输入外冻结去重后的 Attachment snapshot，供 Workspace 虚拟 Files 投影；按 base→Project→本次显式选择的 Skill→`<remembered>`→`<unavailable_capabilities>`→安全策略注入，并以该 Skill 的 allowedTools 收窄 manifests；Memory 只注入 Context Compiler 选中的条目并受 `maximumMemoryCharacters` 硬预算约束，超出的整条跳过而不截断（截断会让模型读到一个不同的事实），且明确声明记忆不是指令、不能创建授权、与当前消息冲突时以当前消息为准；不可用能力携带真实原因，要求模型报告缺失而不是静默改用其他手段猜测；执行输入字符预算 |
| `FamiliarNativeTools.swift` | `current_date_time`、`app_information`（read/low） |
| `FamiliarToolSchema.swift` | 共享 JSON Schema DSL（`object/string/boolean/integer/number/array/stringArray/objectArray`）与 `FamiliarToolDefaults`：范围和默认值只声明一次，同时供 manifest 与 `execute` 使用 |
| `FamiliarISO8601.swift` | 唯一 ISO8601 边界：解析同时接受带/不带小数秒，格式化统一输出小数秒；`validateRange` 返回 typed `FamiliarISO8601Error` |
| `FamiliarHash.swift` | 唯一 SHA-256 实现（Data/String/文件流式）。内容 hash 会持久化并跨启动比较，重复实现一旦分叉会静默失效既有 hash |

### `Familiar/App/` — 见 §2。

### `Familiar/AI/Models/` — 模型生命周期与路由
- `FamiliarModelRouter.swift` — 三种路由策略；`preferLocal` 只在本地首字节前失败或不可用时请求云升级，拒绝不 fallback，已产生本地内容后不切 Provider。
- `FamiliarModelEscalationCoordinator.swift` — 与 Tool authorization 分离的 DeepSeek 出站确认 continuation 和 UI 更新流。
- `FamiliarModelManager.swift` — manifest、可恢复下载、大小/SHA-256 校验、runtime-specific prepare、原子版本目录、状态流与删除。
- `FamiliarCoreAIModelProvider.swift` — Core AI runtime adapter；当前仅有显式 unavailable adapter，真实 Xcode 27 `CoreAILanguageModel`/`LanguageModelSession` 尚未接入。

### `Familiar/Artifacts/`
- `FamiliarArtifactService.swift` — `FamiliarArtifactStore`（`<Application Support>/Familiar/Artifacts`，流式原子导入 + SHA-256）与 `@MainActor FamiliarArtifactService`；`FamiliarArtifactValidator` 复用 AnyDoc/SwiftSoup 验证 Markdown/Text/DOCX/PDF/XLSX/HTML 并生成 versioned receipt。
- `FamiliarArtifactTool.swift` — 保留 `artifact_write/edit`；`artifact_read` 回读已发布 Artifact（Markdown/文本/HTML 原样返回，DOCX/PDF/XLSX 经 AnyDoc 解析，截断显式上报，因为以为读全了的模型会去修改一份它只看过一部分的文档）；`artifact_publish` 只从当前 Project Workspace Outputs 导入经过扩展名、文件签名、可解析正文、必需内容和 hash 校验的真实文件，并可通过可选 `supersedes` 把新文件登记为同一交付物的下一版本。Artifact 版本由 `lineageID` + `version` 表示：每个版本是独立的行与独立目录（store 按 artifact ID 存文件，原位覆盖会销毁上一版字节），谱系与版本号在 `FamiliarArtifactService` 解析而非由 descriptor 提供（工具 nonisolated、无法查询 store），`nextVersion` 取历史最大值加一，因此删除中间版本也不会让后续修订复用号码。

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
- `FamiliarWorkspaceStore.swift` — Project/Conversation Workspace，Shell-visible Files/Outputs/Work/Environment，Metadata/Tasks/Checkpoints 不挂载；Project Environment 持久，Conversation Environment 随 task view 删除；路径穿越、symlink、配额、checkpoint/diff/restore 与 Environment 原子替换。
- `FamiliarWorkspaceTools.swift` — `Files/Resources/<id>/...` 与 `Files/Attachments/<id>/...` 是当前 ContextSnapshot 的虚拟只读投影；`Outputs`/`Runtime/Work` 来自 Workspace Store。write 只允许 `Outputs`，批准后保存目标文件级旧值，Undo 不触碰其他路径；image list 只列当前会话显式附件图片。
- `FamiliarDeviceTools.swift` — Contacts 只读、单次前台 Location、Clipboard 双向确认/写入 undo、只准备 payload 的 Share；EventKit 继续独立 adapter，Spotlight 只查 Familiar 索引。末尾的 `FamiliarDeviceCapabilityProvider` 是唯一的 `FamiliarCapabilityProviding` 实现，把 11 个 `FamiliarCapabilityRequirement` 分发到各 Service 的 `availability()`/`requestAccess()`。`.weatherKit` 直接返回 `.available`：App 无法在运行时检查自身签名 entitlement 或 Apple Weather 配额，真实故障以 typed `FamiliarWeatherError` 暴露，而不是假装可用后让模型退回网页猜测。
- `FamiliarAppleNativeTools.swift` — `FamiliarMapService`（`@MainActor`，`MKLocalSearch`）与 `FamiliarWeatherService`（`actor`，`WeatherService.shared`，携带 Apple Weather attribution 作为 `FamiliarSource`）；出 `map_search`、`weather_forecast`、`weather_history`。历史查询在发起网络请求前校验覆盖起点、区间方向与 10 天上限，超限明确失败而不截断——静默截断会让模型以为拿到了并不存在的天数。坐标校验共用 `FamiliarAppleNativeValidation`。
- `FamiliarAppleDataTools.swift` — `FamiliarNaturalLanguageService`（设备内，输入截断 40k、实体上限 60）、`FamiliarHealthService`（`actor`，`HKStatisticsQueryDescriptor` 只读 3 个 quantity type；共享 `FamiliarHealthReadScope` 同时供工具与设置页使用。HealthKit 不揭示读取拒绝，因此设置页只显示“已请求/尚未请求”，空值不得解释为零）、`FamiliarMusicService`（`actor`，`MusicCatalogSearchRequest`，只读目录）。
- `FamiliarAppleDeviceTools.swift` — `FamiliarBluetoothService`（`@MainActor` `CBCentralManagerDelegate`，必须显式 1–8 个 Service UUID、2–10 秒前台扫描、不连接不读特征值）与 `notification_schedule`（`reversibleWrite`，commit 后可撤销待发送通知）。
- `FamiliarAlarmTools.swift` — `FamiliarAlarmService`（`actor`，无条件 façade + `@available(iOS 26.1, *)` 内部实现）出 `alarm_schedule`/`alarm_cancel`/`alarm_list`。只使用 alert-only `AlarmPresentation`：Apple 要求支持 countdown presentation 的 App 必须提供 widget extension，否则系统可能取消闹钟且不响铃。门控取 26.1 而非 26.0，因为非 deprecated 的 `AlarmPresentation.Alert` 初始化器自 26.1 起才存在。`alarm_list`/`alarm_cancel` 只能看到本 App 自己的闹钟，取消前先核验归属，幻觉 identifier 在确认卡出现前即失败。
- `FamiliarOutputTools.swift` — `FamiliarWorkspaceOutputResolver` 与 `FamiliarPhotoLibraryService`；后者同时实现 `FamiliarPhotoLibrarySaving`（add-only，`undoPolicy: .unavailable`、仅 `.once` 授权）与 `FamiliarPhotoLibraryReading`（只读元数据，尊重 limited 权限，最多 50 项），出 `photos_save_output`、`photos_recent_metadata`、`prepare_file_export`。
- `FamiliarShellExecutor.swift` / `FamiliarShellPolicy.swift` / `FamiliarShellTool.swift` — 统一 Shell 事件/typed result/取消/限制与动态 preflight；离线、Workspace-only、checkpointed 命令自动执行，联网/危险命令审批，包安装从 `shell_execute` 拒绝。`environment_prepare` 只接受 PyPI 声明依赖，由 Swift 使用设置中选择的官方 PyPI 或清华 TUNA HTTPS 索引构造命令，并把实际索引写入 Project Environment lock/receipt 后原子替换旧环境。
- `FamiliarISHShellExecutor.swift` — 全局串行 iSH actor、rootfs version/bundle hash/iSH commit/原子 marker 校验、显式安装/启动/运行/失败生命周期、四目录 mount、streaming、timeout/cancel 和网络计数。bridge 只有 `prepare()` 成功后才向 ToolRegistry 暴露 Environment/Shell tools。
- `Vendor/ish-arm64/` / `Vendor/ISHRuntime/` — 固定 commit 的 GPLv3 iSH ARM64 源码、Familiar headless bridge、网络 syscall policy、arm64 device/simulator XCFramework 与供应链 manifest。
- `FamiliarContainerShellExecutor.swift` — 直接使用 LinuxContainer/exec/process API；无网络接口、Files/Outputs/Work/Environment 四目录 VirtioFS、persistent writable layer 输入、2 vCPU/4 GiB、全局串行、取消与 idle stop。kernel/init/rootfs 下载准备尚未实现。

### `FamiliarMac/`
- `FamiliarMacApp.swift` — 原生 SwiftUI `WindowGroup + NavigationSplitView + inspector + Commands + Settings`；当前为 Codex 式桌面 shell，尚未接入共享 SwiftData/Agent Runtime。
- `FamiliarMac.entitlements` — App Sandbox、用户选择文件、Hardened Runtime 构建设置与 Virtualization entitlement。

### `Familiar/EventKit/`
- `FamiliarEventKitService.swift` — `public actor`，权限状态/请求、查询（limit 1–200）、幂等 commit、按持久 EventKit identifier undo，符合 `FamiliarCapabilityProviding`。
- `FamiliarEventKitTools.swift` — `calendar_events`、`create_calendar_event`、`update_calendar_event`、`delete_calendar_event`、`reminders`、`create_reminder`、`update_reminder`、`delete_reminder`（同一 Service 出 8 个 Tool）。

### `Familiar/Persistence/` — SwiftData
- `FamiliarModels.swift` — 当前模型 typealias 与 `FamiliarModelContainer`；生产和测试容器直接打开单一当前 schema，不配置 migration plan。
- `FamiliarSchema.swift` — 唯一当前 Release Schema，共 36 个实体；新增 ProjectEnvironment、ProjectSkillBinding 与 ProjectCapabilityBinding，不保留旧 Release schema 或 migration stage。
- `FamiliarProjectService.swift` — `@MainActor`，项目 CRUD（名称去除首尾空白并截断至 80 字符；创建/编辑时跨活跃与归档项目做不区分大小写的全局唯一检查）、指令（8k 上限）、可选模型覆盖（`updateModelOverride` 空值清除并回到全局选择，未知 ID 直接拒绝而不落盘，否则一个 Provider 已不提供的模型只会在发送时才暴露为失败）、归档、删除（运行中 Run 保护 + 资源/Artifact staged 删除/回滚；保留并解除 Conversation/Run，清理项目 Memory/授权）。
- `FamiliarRunPersistenceRecorder.swift` — `@MainActor`，**已接线**：ensureRun + ContextSnapshot/VisualEvidence、Activity/ToolResult/Approval/Clarification/ResponseBlock 持久化；tool/approval/clarification/result 在 Runtime 事件边界 upsert，task plan 按稳定 identity 更新 latest revision，最终回复一次写 block，失败/取消且无助手消息时写可重放 runtime notice recovery，text delta 不写 SwiftData。没有 AgentStep/checkpoint 投影。
- `FamiliarRunRecoveryService.swift` — `@MainActor`，capability/grant/cursor/tool-invocation 持久化 + `recoverInterruptedRuns`（启动时把遗留 running Run 终结为 failed、取消在途 invocation）；CapabilitySnapshot 与 RunResumeCursor 已接入，grant 创建/消费与字节级中断续跑仍未接入。

### `Familiar/Presentation/` — SwiftUI
- `FamiliarRootView.swift` — 直接进入 Chat，并承接 Deep Link/Spotlight/App Intent handoff 路由。
- `FamiliarChatView.swift` — 统一 Chat Surface：顶栏依次提供设置、普通/活跃项目工作区、模型和新对话；切换工作区恢复该作用域最近更新的会话，无历史时建立未持久化空白会话。左缘手势打开的抽屉只保留搜索、置顶、可折叠项目、全部项目和普通最近会话；项目与普通最近会话按 20 条逐批展开。
- `FamiliarChatController.swift` — `@MainActor @Observable` 中央状态容器：`startSending`/`performSend` 编排整条 Agent Run。
- `FamiliarChatMessageViews.swift` — 唯一 Assistant Turn 内容流：按 Runtime sequence 交错渲染每轮 Markdown ResponseBlock 与稳定工具执行块。工具调用在原位置从运行中 morph 为单页 Approval、typed result、receipt、failure 或 undone；只读结果默认一行折叠并从顶部锚点向下展开。Activity 只保留工具数与耗时摘要，完整审计进入 Project Runs。Context 超过 2 条进入 sheet，Records 超过 3 条进入可搜索全屏，Diff 与长 Code 进入全屏。
- `FamiliarSurfaceDescriptor.swift` — 实时/历史共用的语义投影，descriptor 保存 Runtime sequence、稳定 tool identity 和授权决定。scalar、searchResults、document、contextMatches、recordCollection 等不再按固定区域堆叠，而是在所属 Assistant Turn 的调用位置渲染。`FamiliarToolPresentationName` 同时持有 name→title 与 name→SF Symbol 两张显式表；图标不放进 manifest，因为所有调用点只拿到持久化的 `activity.toolName`，历史 Run 必须在对应工具已不再注册时渲染出同一图标。
- `FamiliarComposerView.swift` — compact/expanded/fullscreen 输入器、附件/相机/相册、一次性 Slash Skill 选择与语音。
- `FamiliarSettingsHubView.swift` / `FamiliarSettingsView.swift` / `FamiliarSearchSettingsView.swift` — 设置 hub、模型服务、执行限制、Memory、独立网页搜索设置和 Python 软件源设置。执行限制页用 stepper 暴露步数/工具调用/时长三个预算，范围与 `FamiliarExecutionBudget.normalized` 的钳制一致，因此控件无法表达一个 Runtime 会静默拒绝的值；Memory 页提供自动记忆开关、按 scope 与来源列出每条记忆、编辑、滑动删除与二次确认的全部删除，编辑会重写派生的去重键并复用同一套敏感内容拒绝规则。模型服务页此前有 4 个 `body` 从不渲染的 section（含重复的通知开关与重复的 system prompt 编辑器），且其 `.task` 会在未授权时静默关闭通知，已一并删除；Shell 限制展示改为从 `FamiliarShellLimits.iOS` 派生而非硬编码字符串。权限页覆盖日历、提醒、联系人、位置、照片添加、照片读取、健康活动、Apple Music、蓝牙、相机、麦克风、语音识别与通知，其中健康只显示“已请求/尚未请求”并在 footer 说明 HealthKit 从不揭示读取拒绝；软件源只允许选择内置校验的官方 PyPI 或清华 TUNA HTTPS 索引，不接受任意 URL。搜索页提供 Provider 选择、独立 Key 保存/删除、最小连接验证以及隐私/费用说明。Skills 页只以右上角加号打开带默认 instructions 模板的创建表单，没有导入行，新建 Skill 的 allowedTools 为空。
- `FamiliarProjectsView.swift` — Project Context Workspace：项目列表/主页/编辑、文件/网页/文本资料、真实 Artifact、Environment、按需 Skills、Capability 与 Runs；主页主动作仍回到 Chat。
- `FamiliarSharedDestinationView.swift` — Share 收件箱目标选择（已有项目、新建项目、普通聊天草稿）。
- `FamiliarMarkdownWebView.swift` — 非持久化 WKWebView 渲染 + 高度回传 + 首帧回退文本；终态通过 `selectionChanged` bridge 回传最多 4000 字符纯文本，流式状态禁用并清空选择；长 Mermaid 通过 `previewMermaid` bridge 打开全屏，并复用同一 bundled renderer、非持久化 data store 与禁止远程连接的 CSP。
- `FamiliarCameraView.swift`、`FamiliarAttachmentQuickLookView.swift`、`FamiliarMarkdownNormalizer.swift`。

### `Familiar/Vision/` 与暂不提供的 `Familiar/LocalVision/`
- `FamiliarVisionProcessor.swift` — Apple Vision OCR、条码、图像分类，生成标记为不可信只读内容的 `FamiliarVisualEvidence`。
- `FamiliarLocalVisionModelManager.swift` / `Vendor/ml-fastvlm` — FastVLM 研究源码暂留，但该文件被 iOS target 排除，FastVLMRuntime/MLX package product 不再链接；当前产品无下载或推理入口。

### `Familiar/Skills/`、`Familiar/Memory/`
- `FamiliarSkillService.swift` — 严格 JSON instruction-only Skill parser、安装/更新/卸载和确定性 Run snapshot；Composer 可显式选择一个 Skill，Project 也可绑定候选 Skill，仅 metadata 进入 planning prompt，`skill_read` 按需加载至多一个并收窄后续工具。Skill binding 不自动注入正文，也不能扩大 Capability。
- `FamiliarMemoryService.swift` / `FamiliarMemoryTools.swift` — 三层作用域（global/project/conversation）Memory 运行时。去重键按 scope 与其所有者派生，因此跨 Project 的同一句话是不同记忆；`lastUsedAt` 只在 search 实际选中该行时写入，含义是「确实被选为上下文」；`confidence` 真实存储并优先于时间参与排序。敏感内容在工具边界与持久化边界双重拒绝。`memory_search` 只读本次冻结的记忆；`memory_remember` 只返回审批提案，写入请求经 tool result 旁路由 `FamiliarChatController.persistToolOutputs` 落盘，模型无法自行写入。设置页提供开关、按 scope 与来源的列表、编辑、删除与全部删除。

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

## 4. 启动时注册的工具（无条件 53 个 + 条件 2 个 = 最多 55 个）

注册位置：`FamiliarAppDependencies.init()`。ToolRegistry 按 manifest 的 `.native / .specializedLocal / .shell` 分类保存；Agent Runtime 不硬编码具体工具。`manifests()` 会过滤掉 `availability == .unavailable` 的工具，因此权限被拒或设备不支持的能力不会出现在模型的工具列表里。

| 分类 | 工具 |
|---|---|
| 设备原生 | `current_date_time`、`app_information`、`contacts_search`、`current_location`、`clipboard_read`、`clipboard_write`、`prepare_share`、`familiar_search` |
| Apple Framework（地点/天气/文本） | `map_search`（MapKit）、`weather_forecast`（WeatherKit 未来预报）、`weather_history`（WeatherKit 历史区间，2021-08-01 起、单次最多 10 天、`endDate` 开区间）、`natural_language_analyze`（NaturalLanguage，设备内） |
| Apple Framework（个人数据） | `health_activity_summary`（HealthKit 只读聚合）、`photos_recent_metadata`（PhotoKit 只读元数据）、`music_catalog_search`（MusicKit 目录）、`bluetooth_scan`（CoreBluetooth 前台按 UUID）、`notification_schedule`（UserNotifications，可撤销写） |
| AlarmKit | `alarm_schedule`（durable undo）、`alarm_cancel`、`alarm_list`；iOS 26.1 以下 `availability` 返回 `.unavailable`，因此不进入模型工具列表 |
| EventKit | `calendar_events`、`create_calendar_event`、`update_calendar_event`、`delete_calendar_event`、`reminders`、`create_reminder`、`update_reminder`、`delete_reminder` |
| Workspace | `workspace_list`、`workspace_read`、`workspace_search`、`workspace_write`、`workspace_image_list`、`photos_save_output`、`prepare_file_export` |
| Project/Artifact | `resource_list`、`resource_read`、`resource_search`、`artifact_write`、`artifact_edit`、`artifact_read`（已发布 Artifact 回读：Markdown/文本/HTML 原样返回，DOCX/PDF/XLSX 经 AnyDoc 解析，截断显式上报）、`artifact_publish` |
| Web | `web_search`、`web_fetch` |
| Presentation/interaction | `task_plan`、`present_recommendation`、`present_insight`、`ask_user`、`skill_list`、`skill_read` |
| Memory | `memory_search`（只读本次运行冻结的记忆）、`memory_remember`（返回审批提案，仅 `.once` 授权，写入请求经 tool result 旁路由 Controller 落盘） |
| Shell/Environment | `environment_status`（**无条件注册**：只读磁盘 receipt，不需要 guest）、`environment_prepare`、`shell_execute`（后两个仅在 iSH bridge 和 bundled rootfs 准备成功后注册） |

一个 Apple Framework 只建一个 Service，可暴露多个 Tool：`FamiliarEventKitService` 出 8 个日历/提醒工具，`FamiliarWeatherService` 出 `weather_forecast` 与 `weather_history`，`FamiliarAlarmService` 出 3 个闹钟工具，`FamiliarPhotoLibraryService` 同时实现 add-only 保存与只读元数据两个协议、出 2 个工具，二者授权分离。

工具参数统一使用 `Familiar/Agent/FamiliarToolSchema.swift` 的共享 DSL；`FamiliarJSONSchema` 支持 `items`/`minimum`/`maximum`/`minItems`/`maxItems`/`default`，数组必须声明元素类型。范围与默认值取自 `FamiliarToolDefaults`，同一常量同时供 manifest 与 `execute` 使用，避免 schema 与实际行为漂移。工具错误实现 `FamiliarStructuredToolError` 即可向模型返回稳定 `code`/`retryable`，Agent Loop 不再按具体类型硬编码分支。

App Intents 是系统入口，不作为模型可调用 Tool 注册；iOS 没有公开 API 可枚举或执行第三方 App 的 AppIntent，因此不存在“让 Agent 调用 App Intents”的路径。ToolRegistry 只按 manifest 分类和可用性注册，Agent Runtime 不包含 iSH 或 Native Tool 的类型判断。

## 5. SwiftData Schema

schema：`FamiliarReleaseSchema`（version `1.0.0`），当前 37 个实体；测试阶段没有 migration plan，旧 store 不受支持：

| 实体 | 运行时是否写入 |
|---|---|
| Conversation, Message, SourceRecord, Attachment, ModelSwitchRecord, AgentRun | 是 |
| Project, ProjectInstruction | 是 |
| Resource, ResourceVersion, ContextSnapshotRecord, ContextResourceReference | 是（`FamiliarRunPersistenceRecorder` / `FamiliarProjectResourceService`） |
| Artifact | 是（`FamiliarArtifactService`） |
| CapabilitySnapshotRecord, AuthorizationGrantRecord | CapabilitySnapshot 是（Run 启动）；AuthorizationGrantRecord 否 |
| RunResumeCursorRecord, ToolInvocationRecord | 是（工具请求/审批/完成与终态 cursor；跨进程恢复未实现） |
| AuthorizationRuleRecord, EventKitUndoRecord, VisualEvidenceRecord | 是（真实授权、跨重启 Undo、视觉证据） |
| Skill, MemoryItem, MCPServerRecord, MCPBindingRecord | Skill 安装已写入；MemoryItem 由用户确认的 `memory_remember` 与设置页写入，并由 Context Compiler 读取；MCP Runtime 尚未接线 |
| RunSkillSnapshotRecord | 是（Run 启动时冻结 Skill ID/版本/hash/allowedTools） |
| PinnedItemRecord | 是（项目/会话统一持久置顶） |
| ActivityRecord, ToolResultRecord, ApprovalRecord, ResponseBlockRecord | 是（Assistant Turn 的活动、结构化结果、审批审计与回复块投影；ApprovalRecord 保存 allowedAuthorizationDurationsJSON，ActivityRecord 保存 failureCode/failureRetryable） |
| ClarificationRecord | 是（typed requested/resolved/cancelled/interrupted；重启后 pending 只恢复为 interrupted 展示） |
| ProjectEnvironmentRecord, ProjectSkillBindingRecord, ProjectCapabilityBindingRecord | 是（Environment receipt 与 Project-owned Skill/Capability scope） |
| AlarmUndoRecord | 是（`alarm_schedule` 的跨重启 undo；闹钟必然在未来触发，session 级 undo 会给出无法兑现的承诺） |

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
      → assistantTurnCompleted 在每轮工具边界写独立 Markdown ResponseBlock；Controller 以 Runtime sequence 保持正文与工具顺序
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
| Project Environment | `<Application Support>/Familiar/Workspaces/project-<UUID>/Runtime/Environment/`；普通 Chat 位于 task view 并在终态删除 |
| 模型 API Key | Keychain（service `com.isaachuo.familiar.provider-api-keys.v2`） |
| Search API Key | Keychain（service `com.isaachuo.familiar.search-provider-api-keys.v1`） |
| Provider 设置/Search Provider 选择/Python 软件源选择/通知开关 | UserDefaults |
| 共享收件箱 | App Group `group.com.isaachuo.familiar` |

## 8. 已知缺口与未验证边界

- iOS 1.0 设置固定 `.cloud`，只显示 DeepSeek Flash/Pro；App 直接进入 Chat，缺少 API Key 时由发送动作提示并提供设置入口。内部 `ModelRouter` 合同保留，但本地路由不进入生产 UI。
- 当前没有生产视觉模型。图片在本机经 Apple Vision 转成有限证据文本，原始 bytes 不发送到 DeepSeek。
- 当前开发机是 Xcode 26.6 / iOS 26.5 SDK；计划中的 Xcode 27 Core AI API、Qwen3-0.6B Core AI bundle、specialization 与真机断网流式对话尚不可编译/验收。`FamiliarCoreAIModelProvider` 目前只完成 SDK-neutral adapter contract。
- iSH fork 固定到 `54ca185b77f170e12fd353fcd7443232f6cb73fd`，Alpine 3.24.0 aarch64 fakefs、安装 identity、Project/Run Environment mount 与 headless bridge 已加入生产 target；真实 guest 冷启动、PyPI 安装、DOCX 生成和资源边界尚待 `hwf` 真机验收。
- macOS 已直接编译链接 Containerization 0.33.4，并有可构造 networkless LinuxContainer 的 session/factory；Familiar runtime kernel/init/rootfs/persistent disk 的下载校验器与真实 VM 启动尚未完成。FamiliarMac 当前是原生 Codex 式 UI shell，未接入共享 SwiftData/Agent Runtime。
- Workspace 的 Files 以 Attachment/Project Resource ContextSnapshot 虚拟投影，Outputs/Runtime 保持独立目录；不做重复物理迁移。未公开的 development store 不迁入首个 Release store，也不会被自动删除。
- ToolInvocation/cursor、授权创建/消费均已接入；字节级中断续跑仍未实现。
- Project Capability/Skill binding UI 已实现；Skill 仍为 instruction-only 且不支持目录导入、scripts/references/assets。Memory Runtime（工具、Context Compiler、设置页）已接线且有确定性测试，真机多轮任务的打断次数未人工验收。Remote MCP 未实现。
- 后台承接（`BGContinuedProcessingTask`，iOS 26+）未实现；当前无后台 Run 保证。
- DeepSeek、Search Provider、EventKit 跨重启 Undo 与 Surface 视觉/无障碍仍缺真机验收；当前没有真实 Provider 冒烟结论。FastVLM 不进入当前验收范围。
- WeatherKit、HealthKit、PhotoKit、MusicKit、CoreBluetooth、AlarmKit 全部只完成编译与 fake-service 契约测试。真实可用性额外依赖签名 entitlement 与 provisioning（WeatherKit）、真实系统授权（Health/Photos/Music/Bluetooth）与 iOS 26.1 设备（AlarmKit），Simulator 构建无法证明其中任何一项。`weather_history` 的历史覆盖范围与 Apple Weather 配额消耗未在真实账户上验证。
- `alarm_schedule` 的 durable undo 已写入 `FamiliarAlarmUndoRecord` 并可从记录重建取消动作，但跨重启撤销未真机验证；闹钟已响铃后取消的系统行为未验证。
- AlarmKit 只使用 alert-only presentation，因此不提供 countdown/paused 状态，也不新增 widget extension；重复闹钟、贪睡与 Live Activity 不在当前范围。
- 敏感 read（health/photos/bluetooth）的仅这次/本会话授权已接入 Agent Loop 并有确定性测试，但真机上多轮任务的实际打断次数未人工验收。
- Skills 已完成显式一次性 Context 注入、工具收窄与 Run 审计快照；不支持 scripts/references/assets。Memory Runtime tools 已实现；Remote MCP 与可靠后台承接仍未实现。

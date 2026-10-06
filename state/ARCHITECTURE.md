# Architecture

基于当前代码验证。目标是回答"现在代码实际上长什么样"；设计目标见 `docs/02-system-architecture.md`；当前收敛任务和验收清单见根目录 `PLAN.md`。

## OpenMinis import status (2026-09-27)

This import is partial. See [coverage and remaining work](../docs/13-openminis-import-matrix.md).

- Daily Chat uses `FamiliarProject.dailyProjectID`; initialization adopts only unassigned conversations. Project settings share the existing implementation. Historical Run/ContextSnapshot provenance is not rewritten.
- Conversation compaction stores a summary and sequence boundary while retaining original messages and attachment references. Editing/retrying invalidates the summary. Forks copy message content, source references and attachment files without copying approvals or executed actions.
- Provider instance configuration and model groups are local settings; API keys and OAuth tokens use independent Keychain identities. Per-run route instances freeze members and use one Agent loop; actual group request choices and reported usage are stored on the Run.
- HTTP MCP configurations use the existing MCP records; bindings resolve chat, project, then global enablement. The client discovers tools and the runtime snapshots a registry. All remote calls use high-risk one-time proposals regardless of server annotations.
- Voice adapter source is namespaced from OpenMinis and feeds the existing editable composer/speech interface. App locking uses a scene-owned window above presented sheets and defers system-entry navigation while locked.
- Native view colors use `FamiliarTheme`; radii use `FamiliarRadius`. No independent AI-surface palette remains. iOS 26 glass is availability-gated; iOS 18 and reduced transparency retain native fallback materials.

## Harness convergence (2026-10-03, B1/B2/B3/C1–C9/F1)

- One FamiliarAgentLoop executes both direct answers and natural multi-turn tool work. Project/Daily Chat no longer requires task_plan or tool evidence before answering.
- Runtime phases describe actual requestingModel/responding/executingActivities/awaitingApproval/awaitingClarification/compactingContext behavior. Fixed planning/environment/validation/repair/delivery phases and executionStateChanged snapshots are removed.
- task_plan is optional presentation only. File publication validates the actual file independently, with optional requiredText/minimumSources supplied directly on the call; there is no deliverableID or promised-deliverable scheduler.
- FamiliarRunState owns only admitted Skill snapshots and attempted-write fingerprints shared across tool calls. It does not contain a plan, step evidence, a delivery ledger or repair counter.
- willCommit journals each action invocation as committing before execution. Interrupted committing records are retained as uncertain. Exact attempted-write fingerprints prevent in-Run replay after failed/uncertain effects; destructive regeneration of affected history is blocked.
- Local CommittedAction rollback/finalize hooks restore bytes on save failure and clean backups only after persistence; external/native actions are never silently compensated. File edit creates independent successors.
- Native durable Undo and Environment receipts now persist before success events. Undo results remain cached until metadata saves, avoiding repeated native operations; persistent native Undo is marked unavailable before executing.
- Memory commit callback persists confirmed memory before successful runtime events. Save failures roll back pending SwiftData changes and return a tool failure; audit and model-facing failures use the same structured code/retryable/message.
- startSending freezes input and validates protected Project context plus the pending turn and base schemas before committing messages or attachment files. Vision evidence is validated again, older history can still compact, and performSend consumes the exact validated snapshot. A failed preparation/save keeps the draft; accepted message persistence precedes draft consumption.
- Memory candidates are read-only keyword matches. Only IDs admitted by the compiler receive lastUsedAt, staged in the accepted message save; rejected preparations and overflow candidates do not advance usage.
- web_fetch retains exact capture time/body hash in its canonical model output and existing persisted envelope. It creates no Project Resource automatically. The result's native Save to Project button resolves stored evidence and ownership, verifies the body hash and imports offline; repeat saves reuse the same Resource after verifying its bytes. Retained text carries URL/time/source ID/body hash/truncation metadata. No new persistent entity, tool schema or Agent write route is added.
- Lazy Tools uses one FamiliarToolGroup catalog for default eligibility, Project UI grouping and base exceptions. Initial schemas are current_date_time, ask_user and tools_load; the frozen availableToolManifests catalog remains separate. tools_load selects at most two groups and replaces extensions for the next request, never granting authorization.
- FamiliarToolLoader owns the Run-local permitted catalog and deferred discovery cache. MCP server groups carry configuration only inside discovery closures, page at 32 tool descriptions and require exact selection of at most 16 tools. Discovery and loading are inside the existing Loop deadline; no task Router is involved.
- Only names exposed in the current request can execute. Attempts, including loaders and rejected names, consume the tool budget. Successful-write fingerprints are checked immediately before execution, covering duplicate writes within one batch. Actual parameter schemas and load reports count toward the character budget.
- Guest setup is lazy. FamiliarISHPreparation shares one preparation flight; each Run waiter can cancel independently without cancelling shared setup or starting its command. notPrepared is the actual cold-start status. Native guest setup/cancellation remains device-unverified.
- B3 removes CapabilityCatalog/Resolver/Binding and runtime Grant issuance/consumption. Canonical argument hashing is independent of authorization. Historical GrantRecord's stored columns remain inert; only AuthorizationRuleRecord is consulted for exact active authorization. Lookup and save failures propagate before effects, invalid duration rows never grant access, and consumption/issuance save failures roll back.
- The selected ProviderFactory result feeds the one Loop directly. User-selected model groups retain member fallback before output; unfinished local/cloud routing, escalation state/coordinator/dialog/observer and the route-policy setting are removed. Core AI research adapters have no production routing entry. Existing bounded provider/read retry, two-read concurrency, write non-replay, budget closing and interrupted-run evidence retention remain.
- Default delivery is direct text, or Markdown/plain-text File when a file is requested. Complex file generation needs explicit workspace_write/file_publish/Shell eligibility; text tools reject complex formats before approval. Guest registration/preparation does not imply physical-device acceptance.
- Top-bar/configuration/send share effective Project model resolution. Project-pinned selection changes that Project, with a native menu action to follow the default. Historical conversation metadata does not overwrite the user's default. Run snapshot preserves requested selection; response provenance uses the last actual member and regeneration uses the original Run request.
- Both production wire adapters emit request identity; Group emits member identity once and suppresses the adapter duplicate. Recorder stores ordered attempts and reported nullable totals. Automatic compaction forwards model/usage events within the same Run. Manual compaction and provider setup are excluded from this view's scope; partial totals/attempted models are described honestly.
- ProviderFactory owns normalized credential availability for leaf providers and groups. Group credentials are valid only if a real member can be constructed; configuration/send/manual-compaction and construction share it. Send rechecks before formal submission. Existing token expiry/network failures remain runtime failures, not proof of local credential validity.
- Cancelled document import removes its owned draft if conversion/delivery returns after cancellation. Attachment copy refuses existing targets and never deletes them on file-exists errors. A reappearing Chat view neither recovers a live send/compaction nor scans its owned transient files as orphans.

## Design convergence (2026-10-03, D1–D3 implementation)

- Chat retains conversation/project/model/input actions and no longer has a Diagnostics shortcut. Project has a visible New Chat action, shared instructions/chats/resources/outputs and one Advanced entry. Archived Projects require unarchiving before this new-chat action.
- Project's Advanced List owns the existing Environment/Skills/MCP/Capabilities/history links. It stays in the existing NavigationStack, with the same Project ID, registry and live records; no capability binding or data is reset by navigation.
- Settings root groups Models & Responses, Appearance, Privacy & Data and Support. Advanced is one destination in the current route enum; model groups/search configuration/tools/budgets/Shell/package source/MCP/Skills and activity/diagnostics stay in the same destination mapping and editing bindings. Memory and authorization revocation remain direct root entries.
- Model-service settings and its provider chooser have no voice editing paths. Voice settings is the sole provider-management destination, with its original configurations/keys intact. Titles use response preferences/approved actions/outputs. File approvals show readable filename/format/size while opaque identity, validators and hashes remain in actual authorization/audit/file records.
- Existing List/NavigationLink/Menu, Theme/Typography/Spacing and native navigation are reused. Build/static evidence is not device/visual/accessibility acceptance.
- Presentation bodies use the shared semantic typography, spacing and radius scale; fixed decorative glyph/camera/chart geometry does not determine body text. FamiliarIconButtonStyle owns target/press/reduced-motion treatment for custom icon controls; FamiliarDismissButton standardizes modal closing. Shared-inbox presentation and output previews use Identifiable state, avoiding duplicate optional-model/Boolean presentation paths.
- FamiliarMarkdownStyle resolves native semantic colors, color scheme/contrast and Dynamic Type into sorted CSS variables. Render-state equality includes this presentation input, so appearance/text changes rerender and remeasure. CSS and Mermaid use those values, with system-color fallback; independent light/dark palettes are removed. JavaScript copy feedback uses native localization, keyboard focus and touch targets. Non-persistent WebKit/CSP/selection/streaming behavior remains.
- The obsolete FamiliarToolChips fixture-only renderer is deleted. Fixtures instantiate the production FamiliarExecutionBlock and other real content/approval/Thinking/Sources components. They are preview data, not verification of real service execution.
- D implementation, JavaScript/localization/static checks and arm64 test-target compilation are complete. The entirely pending owner checklist is `docs/14-design-system-device-acceptance.md`; no Simulator, UI screenshot, VoiceOver or physical-device visual pass is claimed.

## Streaming and renderer boundaries (2026-10-04, E source work)

- Chat does not subscribe to streaming strings in sending-state empty-view checks. FamiliarMessageTimeline receives the Controller identity; only its FamiliarLiveAssistantTurn subtree reads token blocks, reasoning and ordered live surfaces. Historical ordering/projection and Chat controls are not token inputs. Scroll-follow behavior and eager VStack remain; no measured lazy-layout decision or persistent cache exists.
- Historical Run association builds one local UUID index from the current input, preserving the first matching responseMessageID. It replaces per-message linear scans and is rebuilt with history inputs.
- FamiliarSurfaceStore.affectsPresentation excludes token/reasoning completion, usage/model identity and assistant-turn completion events. The Controller checks this before mutating observable surfaces; the store also guards direct event application. Persistence and actual activity/approval/terminal events retain their original paths.
- FamiliarAttachmentStore.importImage is @concurrent async: JPEG encoding/owned draft write occur off MainActor; cancellation is checked before/after encoding and after writing, cleaning only its own file. Controller awaits preparation and preserves the draft/version/submission guards. Document parsing already uses detached work; SwiftData mutation remains on MainActor.
- renderer.js increments renderVersion for each render. Mermaid async success/failure, subsequent diagrams and content decoration use that version to discard stale work; old previews cannot attach their source to new content. Native coordinator still coalesces streaming for 80ms and renders terminal input immediately. Node scheduling tests have a limited DOM double; actual WebKit layout/memory/rendering remain owner acceptance.
- Remaining source-audited MainActor I/O includes ContextCompiler image reads, recorder attachment hashing, Project resource copies/hash, bundled Skill installation and install manifest reads. Source presence is not a measured stall; further changes depend on device evidence. No schema, tool group or orchestration phase is added by this slice.

## 1. 技术基线

| 领域 | 技术 |
|---|---|
| UI | SwiftUI |
| 数据模型 | SwiftData（`FamiliarReleaseSchema` 3.0.0，38 实体；1.0.0 冻结基线与加法 migration plan，执行验收待完成） |
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
| 图片 | PhotosPicker、AVFoundation、UIKit、Vision；支持图片的所选模型接收图片 bytes，其他模型使用 Apple Vision 本地只读证据 |
| 本地文本模型 | Core AI adapter contract + ModelManager；真实 Xcode 27 Runtime/Qwen bundle 尚未接入 |
| 受控计算 | iOS ARM64 iSH/Alpine headless runtime；macOS Apple Containerization 0.33.4 direct Swift API |
| 语音 | Speech、AVAudioEngine |
| 网页解析 | SwiftSoup（SPM 2.13.7，仅 app target 链接） |

- iOS App 最低部署目标仍为 iOS 18；FastVLMRuntime/MLX 不在 iOS target 或 Package graph 中，研究源码仅保留在 `Vendor/`。`TARGETED_DEVICE_FAMILY = 1`（iPhone only）。
- Swift 6，`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。
- App entitlements：App Group `group.com.isaachuo.familiar`、WeatherKit 和 HealthKit；签名 provisioning 的真实支持仍需设备验证。
- Target：`Familiar`（iOS app）、`FamiliarMac`（原生 macOS app）、`FamiliarTests`（Swift Testing）、`FamiliarUITests`、`FamiliarShareExtension`（appex）、`FamiliarWidgets`（appex）。

## 2. App 入口与依赖注入

- **`Familiar/App/FamiliarApp.swift`** — `@main`。创建 `FamiliarAppDependencies`，经 `FamiliarModelContainer` 构建 `ModelContainer`：
  - store 目录 `<Application Support>/Familiar/Persistence/`（`.completeUntilFirstUserAuthentication`）。
  - Debug store 文件名 `FamiliarDevelopment.store`；Release store 文件名 `Familiar.store`。
  - 首次创建任何 store 都不自动清理旧 store 或文件目录。
  - 容器创建失败显示 `FamiliarStoreRecoveryView`，用户确认后删除当前 store、附件、项目资源与 File，保留 Keychain。
  - **`Familiar/App/FamiliarAppDependencies.swift`** — `@MainActor` DI 根。持有 ToolRegistry、执行/审批/clarification coordinator、Workspace、原生 capability services、Web 与 Apple Vision。`makeRuntime(for:)` 直接将所选 descriptor 的 ProviderFactory 结果注入单一 `FamiliarAgentLoop`，并把持久化的 `FamiliarExecutionBudget`（步数/工具调用/时长）经 `normalized` 钳制后传入。当前 descriptor catalog 包含独立供应商实例和冻结成员的模型分组；Runtime 不做供应商类型判断，也不组合未接通的本地模型。每次 Run 克隆 native 注册表；MCP 只在 tools_load 请求服务目录时发现，远程实现留在本 Run 注册表。App 初始化只检查 bundled asset 的存在，不启动 iSH。

## 3. 模块清单

### `Familiar/Agent/` — Agent 运行时
| 文件 | 职责 |
|---|---|
| `FamiliarTool.swift` | `FamiliarTool` 协议（类型化 Input）、`FamiliarToolManifest`、effect/risk/requirement、`FamiliarToolResultEnvelope`（canonical model JSON + schema v3 typed scalar/search/document/context/records/mutation/artifact/diff/taskList/recommendation/insight/code/shareDraft payload）、有序 typed approval fields、纯预览 `FamiliarActionProposal` 与批准后 `FamiliarCommittedAction(result + undo)`、clarification proposal、`actor FamiliarToolRegistry`（`availabilityReport()` 保留 `.unavailable(reason:)` 的真实原因；`manifests()` 由它派生，因此不可用能力不再只是从工具列表中静默消失）、`FamiliarUnavailableTool`/`FamiliarToolAvailabilityReport`；`FamiliarStructuredToolError` 定义稳定 code/retryable 契约；`FamiliarToolAuthorizationAssessment` 可由 `preflight` 提供真实读取范围 fields/consequence/targetKey；`FamiliarCapabilityRequirement` 声明各能力所需的 plist key、entitlement 与 privacy 数据类型，供合规契约测试机械反查 |
| `FamiliarAgentLoop.swift` | 唯一模型／工具循环及 typed Runtime events。允许首轮直接回答，不区分任务复杂度、不强制计划或工具证据。保留 ContinuousClock hard deadline、首字节前有界重试、最多两路独立 read、串行审批和 write、防重复写入、结构化失败、预算耗尽收尾及唯一 runFinished。task_plan 仅可选展示；文件校验留在 File 工具边界。 |
| `FamiliarRuntimeError.swift` | `FamiliarRuntimeFailure.kind(for:)` 错误分类（auth/限流/5xx/网络/上下文/参数/结果/取消等）与 `isRetryable` 判定 |
| `FamiliarModelProvider.swift` | 无 API Key 参数的 `FamiliarModelProvider.stream(request:)` 与默认 `generate(request:)`、统一 `FamiliarToolCall`、reasoning delta、消息/内容/Manifest、`localOnly/preferLocal/cloud` 值类型 |
| `FamiliarExecutionPolicy.swift` | 统一 allow/requireApproval/deny、Project/Skill/暴露范围、动态 preflight、可用性、精确授权匹配/保存与审批字段；确认后复核条件/权限/原生目标版本。Runtime 只传递确认并执行决策，不自行匹配或签发授权 |
| `FamiliarCapabilityContract.swift` | 来源与不可变 CapabilitySnapshot、CanonicalJSON 及规范化参数 hash；无另一个 Catalog/Resolver 或 Grant 授权路径。实际授权仅由 `FamiliarAuthorizationRuntime` 匹配真实 RuleRecord，读取／消费／签发失败抛回 Loop，未保存改动回滚 |
| `FamiliarToolConfirmationCoordinator.swift` | `public actor`，`runID + toolCallID` 幂等确认，checked continuation 暂停 Agent Loop |
| `FamiliarClarificationCoordinator.swift` | `public actor`，独立于授权确认保存 pending clarification continuation；验证选项/自定义回答，支持按 Run 取消 |
| `FamiliarPresentationTools.swift` | task_plan、present_recommendation、present_insight 的可选展示与 ask_user 澄清；task_plan 不再携带 expectedDeliverables 或触发执行状态机。 |
| `FamiliarRunState.swift` | Run-local actor，只保存本次安装／可用 Skill 与已尝试写入指纹，供并行读取和串行执行共享事实；不编排任务。 |
| `FamiliarToolGroups.swift` | 唯一工具组／默认能力／base 规则及 tools_load 定义；组加载只返回下一轮工具集合，不执行设备动作或授予权限。 |
| `FamiliarToolLoader.swift` | 每个 Run 的冻结 native catalog、deferred group 发现缓存、成员可用性、remote 精确选择与分页、schema/report 字符预算。 |
| `Persistence/FamiliarAuthorizationRuntime.swift` | `@MainActor` SwiftData 授权查询、单次消费、session/长期授权签发与撤销范围匹配 |
| `FamiliarContextCompiler.swift` | 从 Project seed + 消息快照 + 工具 manifest 组装不可变 `FamiliarContextSnapshot`；除 Provider 输入外冻结去重后的 Attachment snapshot，供 Workspace 虚拟 Files 投影；按 base／工具组摘要→Project→本次显式 Skill→`<remembered>`→安全策略组装；不可用原因主要在按需加载结果中报告（assembler 仍可接受显式 unavailableTools），并以该 Skill 的 allowedTools 收窄 frozen available catalog；base 三个工具保留，扩展集合由当前轮加载决定（未声明 allowedTools 即未声明限制、不收窄；把空列表当作「拒绝一切」会把整轮 Run 收窄到零个工具，而内置示例与设置中新建的 Skill 都是空列表）；Memory 只注入 Context Compiler 选中的条目并受 `maximumMemoryCharacters` 硬预算约束，超出的整条跳过而不截断（截断会让模型读到一个不同的事实），且明确声明记忆不是指令、不能创建授权、与当前消息冲突时以当前消息为准；不可用能力携带真实原因，要求模型报告缺失而不是静默改用其他手段猜测；执行输入字符预算 |
| `FamiliarNativeTools.swift` | `current_date_time`、`app_information`（read/low） |
| `FamiliarToolSchema.swift` | 共享 JSON Schema DSL（`object/string/boolean/integer/number/array/stringArray/objectArray`）与 `FamiliarToolDefaults`：范围和默认值只声明一次，同时供 manifest 与 `execute` 使用 |
| `FamiliarISO8601.swift` | 唯一 ISO8601 边界：解析同时接受带/不带小数秒，格式化统一输出小数秒；`validateRange` 返回 typed `FamiliarISO8601Error` |
| `FamiliarHash.swift` | 唯一 SHA-256 实现（Data/String/文件流式）。内容 hash 会持久化并跨启动比较，重复实现一旦分叉会静默失效既有 hash |

### `Familiar/App/` — 见 §2。

### `Familiar/AI/Models/` — 未接通的本地模型研究
- ModelRouter 与云升级 Coordinator 已移除；生产只使用用户所选 Provider，不提供本地／云任务路由。
- `FamiliarModelManager.swift` — manifest、可恢复下载、大小/SHA-256 校验、runtime-specific prepare、原子版本目录、状态流与删除。
- `FamiliarCoreAIModelProvider.swift` — Core AI runtime adapter；当前仅有显式 unavailable adapter，真实 Xcode 27 `CoreAILanguageModel`/`LanguageModelSession` 尚未接入。

### `Familiar/Files/`
- `Familiar/Files/FamiliarFileService.swift` — `FamiliarFileStore` 保留 `<Application Support>/Familiar/Artifacts` 旧字节目录，流式原子导入与 SHA-256；`FamiliarFileService` 只写 File/FileVersion。`FamiliarFileValidator` 复用 AnyDoc/SwiftSoup 验证 Markdown/Text/DOCX/PDF/XLSX/HTML。
- `FamiliarFileTool.swift` — file_write/edit/read 与 file_publish。读取已发布 File 时复用 AnyDoc 且明确截断。发布仅接受当前 Project Workspace 的真实 Outputs 文件，校验扩展名、签名、可解析正文、hash、可选 requiredText 和 minimumSources 引用要求，不要求预先计划。supersedes / file_edit 都登记为同一交付物的独立新版本，旧字节不被覆盖；保存失败补偿只删除新目录，删除／Undo 用目录暂存保护元数据失败恢复。

### `Familiar/AnyDoc/`
- `FamiliarAnyDocService.swift` — Swift 到 Rust C ABI 的转换封装，返回 Markdown/格式/引擎版本/错误码，声明支持扩展名列表。

### `Familiar/Attachments/`
- `FamiliarAttachmentStore.swift` — 文档解析 detached、图片 JPEG／草稿写入 @concurrent async；附件磁盘存储（`Drafts/`、`Messages/<messageID>/`）：25 MiB 上限、security-scoped 导入、路径穿越防护、草稿/提交副本、孤儿清理、OCR fallback 协调。解析与交付返回后都检查取消，仅清理本次拥有的草稿；正式复制遇到已存在目标直接拒绝，file-exists 失败不删既有文件。
- `FamiliarSharedDraftImportService.swift` — 从共享收件箱取下一项导入为附件草稿。

### `Familiar/Data/` — Provider 与密钥
- `OpenAICompatibleClient.swift` — 通用 `FamiliarOpenAICompatibleModelProvider`（Chat Completions SSE）；factory 支持 OpenAI Chat/Responses、Anthropic 与 Gemini 协议，Kimi Code/Codex 刷新凭据后进入相同适配器；Tool Call、SSE 和错误合同由现有 Runtime 消费。API Key 由 Provider 实例持有，不进入 Agent Runtime 合同。
- `FamiliarSSEParser.swift` — 仅测试 fixture 使用。
- `FamiliarKeychainStore.swift` — service `com.isaachuo.familiar.provider-api-keys.v2`，account = providerID，空 Key 删除。
- ProviderFactory.storedCredential/credential 统一 Keychain/OAuth 的非空 token 判断；组不使用组 ID 上的 key，而是至少一个可用成员。isConfigured、发送／手动压缩 preflight 和 Factory 成员构造共用它；credentials 不进入 Snapshot 或工具结果。
- `FamiliarSearchKeychainStore.swift` — 独立 Search Provider service `com.isaachuo.familiar.search-provider-api-keys.v1`，account = Search Provider ID，不与模型 Key 共用。
- `FamiliarModelCatalogService.swift` — 模型列表拉取（30s），只返回正式 curated ID 与实时 `/models` 的交集；空交集明确失败。
- `FamiliarProviderConnectionValidator.swift` — Key/模型连接验证，要求所选模型真实出现在 `/models`。

### `Familiar/Domain/` — 共享值类型
- `FamiliarChatModels.swift` — 消息/附件/来源与只含 activities/approvals/toolResults/responseBlocks/context 的 Run 快照、设置（UserDefaults `familiar.chat.settings.v2`）。
- `FamiliarConversationMetadata.swift` — `FamiliarModelSwitchRecord`。
- `FamiliarDeepLink.swift` — `familiar://new?text=`、`familiar://conversation/<UUID>`、`familiar://run/<UUID>`。
- `FamiliarProviderCatalog.swift` — 保存独立供应商实例与模型能力；保留原有 DeepSeek 实例 ID 和钥匙串项。模型分组根据成员共同支持的能力计算输入边界。

### `Familiar/Workspace/`、`Familiar/Native/`、`Familiar/Shell/`
- `FamiliarWorkspaceStore.swift` — Project/Conversation Workspace，Shell-visible Files/Outputs/Work/Environment，Metadata/Tasks/Checkpoints 不挂载；Project Environment 持久，Conversation Environment 随 task view 删除；路径穿越、symlink、配额、checkpoint/diff/restore 与 Environment 原子替换。
- `FamiliarWorkspaceTools.swift` — `Files/Resources/<id>/...` 与 `Files/Attachments/<id>/...` 是当前 ContextSnapshot 的虚拟只读投影；`Outputs`/`Runtime/Work` 来自 Workspace Store。write 只允许 `Outputs`，批准后保存目标文件级旧值，Undo 不触碰其他路径；image list 只列当前会话显式附件图片。
- `FamiliarDeviceTools.swift` — Contacts 只读、单次前台 Location、Clipboard 双向确认/写入 undo、只准备 payload 的 Share；EventKit 继续独立 adapter，Spotlight 只查 Familiar 索引。末尾的 `FamiliarDeviceCapabilityProvider` 是唯一的 `FamiliarCapabilityProviding` 实现，把 11 个 `FamiliarCapabilityRequirement` 分发到各 Service 的 `availability()`/`requestAccess()`。`.weatherKit` 直接返回 `.available`：App 无法在运行时检查自身签名 entitlement 或 Apple Weather 配额，真实故障以 typed `FamiliarWeatherError` 暴露，而不是假装可用后让模型退回网页猜测。
- `FamiliarAppleNativeTools.swift` — `FamiliarMapService`（`@MainActor`，`MKLocalSearch`）与 `FamiliarWeatherService`（`actor`，`WeatherService.shared`，携带 Apple Weather attribution 作为 `FamiliarSource`）；出 `map_search`、`weather_forecast`、`weather_history`。历史查询在发起网络请求前校验覆盖起点、区间方向与 10 天上限，超限明确失败而不截断——静默截断会让模型以为拿到了并不存在的天数。坐标校验共用 `FamiliarAppleNativeValidation`。
- `FamiliarAppleDataTools.swift` — `FamiliarNaturalLanguageService`（设备内，输入截断 40k、实体上限 60）、`FamiliarHealthService`（`actor`，`HKStatisticsQueryDescriptor` 只读 3 个 quantity type；共享 `FamiliarHealthReadScope` 同时供工具与设置页使用。HealthKit 不揭示读取拒绝，因此设置页只显示“已请求/尚未请求”，空值不得解释为零）、`FamiliarMusicService`（`actor`，`MusicCatalogSearchRequest`，只读目录）。
- `FamiliarAppleDeviceTools.swift` — `FamiliarBluetoothService`（`@MainActor` `CBCentralManagerDelegate`，必须显式 1–8 个 Service UUID、2–10 秒前台扫描、不连接不读特征值）与 `notification_schedule`（`reversibleWrite`，commit 后可撤销待发送通知）。
- `FamiliarAlarmTools.swift` — `FamiliarAlarmService`（`actor`，无条件 façade + `@available(iOS 26.1, *)` 内部实现）出 `alarm_schedule`/`alarm_cancel`/`alarm_list`。只使用 alert-only `AlarmPresentation`：Apple 要求支持 countdown presentation 的 App 必须提供 widget extension，否则系统可能取消闹钟且不响铃。门控取 26.1 而非 26.0，因为非 deprecated 的 `AlarmPresentation.Alert` 初始化器自 26.1 起才存在。`alarm_list`/`alarm_cancel` 只能看到本 App 自己的闹钟，取消前先核验归属，幻觉 identifier 在确认卡出现前即失败。
- `FamiliarOutputTools.swift` — `FamiliarWorkspaceOutputResolver` 与 `FamiliarPhotoLibraryService`；后者同时实现 `FamiliarPhotoLibrarySaving`（add-only，`undoPolicy: .unavailable`、仅 `.once` 授权）与 `FamiliarPhotoLibraryReading`（只读元数据，尊重 limited 权限，最多 50 项），出 `photos_save_output`、`photos_recent_metadata`、`prepare_file_export`。
- `FamiliarShellExecutor.swift` / `FamiliarShellPolicy.swift` / `FamiliarShellTool.swift` — 统一 Shell 事件/typed result/取消/限制与动态 preflight。命令超时由 `FamiliarShellTimeoutSettingsStore` 持久化，设置中的值同时是默认值与上限：模型只能请求更短的超时，不能更长；读与写两侧都做钳制，因为旧版本留下或手工编辑的 defaults 条目会绕过 `save()`。离线、Workspace-only、checkpointed 命令自动执行，联网/危险命令审批，包安装从 `shell_execute` 拒绝。`environment_prepare` 只接受 PyPI 声明依赖，由 Swift 使用设置中选择的官方 PyPI 或清华 TUNA HTTPS 索引构造命令，并把实际索引写入 Project Environment lock/receipt 后原子替换旧环境。
- `FamiliarISHShellExecutor.swift` — 全局串行 iSH actor、rootfs version/bundle hash/iSH commit/原子 marker 校验、显式安装/启动/运行/失败生命周期、四目录 mount、streaming、timeout/cancel 和网络计数。bundled assets 存在时登记 Environment/Shell 工具；登记和加载 Schema 都不启动 guest，实际操作按需准备。FamiliarISHPreparation 合并并发准备，并允许 Run 取消等待而不启动命令。
- `Vendor/ish-arm64/` / `Vendor/ISHRuntime/` — 固定 commit 的 GPLv3 iSH ARM64 源码、Familiar headless bridge、网络 syscall policy、arm64 device/simulator XCFramework 与供应链 manifest。
- `FamiliarContainerShellExecutor.swift` — 直接使用 LinuxContainer/exec/process API；无网络接口、Files/Outputs/Work/Environment 四目录 VirtioFS、persistent writable layer 输入、2 vCPU/4 GiB、全局串行、取消与 idle stop。kernel/init/rootfs 下载准备尚未实现。

### `FamiliarMac/`
- `FamiliarMacApp.swift` — 原生 SwiftUI `WindowGroup + NavigationSplitView + inspector + Commands + Settings`；当前为 Codex 式桌面 shell，尚未接入共享 SwiftData/Agent Runtime。
- `FamiliarMac.entitlements` — App Sandbox、用户选择文件、Hardened Runtime 构建设置与 Virtualization entitlement。

### `Familiar/EventKit/`
- `FamiliarEventKitService.swift` — `public actor`，权限状态/请求、查询（limit 1–200）、幂等 commit、按持久 EventKit identifier undo，符合 `FamiliarCapabilityProviding`。
- `FamiliarEventKitTools.swift` — `calendar_events`、`create_calendar_event`、`update_calendar_event`、`delete_calendar_event`、`reminders`、`create_reminder`、`update_reminder`、`delete_reminder`（同一 Service 出 8 个 Tool）。

### `Familiar/Persistence/` — SwiftData
- `FamiliarModels.swift` — 当前模型 typealias 与 `FamiliarModelContainer`；生产、磁盘测试与内存测试容器统一配置 `FamiliarSchemaMigrationPlan`。
- `FamiliarSchema.swift` — 当前 Release Schema 4.0.0，37 实体；V3–V11 仍组织存储声明。独立冻结原 37 实体 1.0.0，经加法 Files 桥接、Artifact 移除和 Grant 审计迁移/移除；Resource/Attachment 历史存储关系仍保留，无新 Resource 生产写入。
- `FamiliarProjectService.swift` — `@MainActor`，项目 CRUD（名称去除首尾空白并截断至 80 字符；创建/编辑时跨活跃与归档项目做不区分大小写的全局唯一检查）、指令（8k 上限）、可选模型覆盖（`updateModelOverride` 空值清除并回到全局选择，未知 ID 直接拒绝而不落盘，否则一个 Provider 已不提供的模型只会在发送时才暴露为失败）、归档、删除（运行中 Run 保护 + 资源/File staged 删除/回滚；保留并解除 Conversation/Run，清理项目 Memory/授权）。
- `FamiliarRunPersistenceRecorder.swift` — `@MainActor`，**已接线**：ensureRun + ContextSnapshot/VisualEvidence、Activity/ToolResult/Approval/Clarification/ResponseBlock 持久化；recordModelSelection 保存有序的实际请求尝试，recordUsage 仅累计已报告字段，nil 不转换为零，损坏 trace 不静默清空。tool/approval/clarification/result 在 Runtime 边界 upsert，task plan 按稳定 identity 更新 latest revision，最终回复一次写 block，失败/取消且无助手消息时写可重放 runtime notice recovery，text delta 不写 SwiftData。没有 AgentStep/checkpoint 投影。
- `FamiliarRunRecoveryService.swift` — `@MainActor`，capability snapshot/cursor/tool-invocation 持久化 + `recoverInterruptedRuns`（启动时终结遗留 running Run，取消未提交 invocation，保留已取得 Result 和 committing 不确定写入）。没有 Grant 签发／消费 API，不提供字节级中断续跑。

### `Familiar/Presentation/` — SwiftUI
- `FamiliarRootView.swift` — 直接进入 Chat，并承接 Deep Link/Spotlight/App Intent handoff 路由。
- `FamiliarChatView.swift` — 统一 Chat Surface：顶栏依次提供设置、普通/活跃项目工作区、模型和新对话；切换工作区恢复该作用域最近更新的会话，无历史时建立未持久化空白会话。左缘手势打开的抽屉只保留搜索、置顶、可折叠项目、全部项目和普通最近会话；项目与普通最近会话按 20 条逐批展开。
- `FamiliarChatController.swift` — `@MainActor @Observable` 中央状态容器：`startSending`/`performSend` 编排整条 Agent Run。Runtime 内容投影只在活动事件和首个非空正文边界更新；中断正文在终态通过现有 ResponseBlock 保存，消费流丢失终态时终结本地 Run／cursor。历史用已保存 File 关联输出，并从既有 journal／requiresInspection 读取不确定写入与重试边界。
- `effectiveSettings(for:)` 统一下次发送与顶栏的 Project override；选中历史不从 Conversation 的上次请求元数据改默认模型。顶栏在 Project 有 override 时修改 Project，可恢复跟随默认；设置页仍编辑默认选择，未改变生效模型时不写假的 ModelSwitch。回复保存实际成员 ID，重试读取原 Run ContextSnapshot 的请求 ID，保留模型组选项。
- `FamiliarUsageView.swift` — 汇总该聊天 Run 的服务商报告字段，包括自动压缩；全缺失显示未报告，部分 Run 缺失时标明部分用量。模型条目是请求尝试，不声明成功，不估算费用；手动压缩及供应商配置请求明确不计入。它不承担按请求／成员分摊费用或 tokenizer 估算。
- `FamiliarWebCaptureSaveButton.swift` — 展开的成功网页结果中的用户保存动作，复用 PillButtonStyle/Typography/Spacing。按真实 Run/Call 找已保存证据与所属 Project，保存完成后显示目标项目；截断页明确提示部分内容。当前保存回执只用于本地呈现，跨重开防重复由 Service 的文件／版本校验负责。
- `FamiliarChatMessageViews.swift` — 唯一 Assistant Turn 内容流按 Runtime sequence 保留每轮正文、区段 Runtime Card、Approval／Clarification、交付内容与回执。推理摘要不进入聊天呈现。FamiliarLiveMarkdownBlock 独立观察 token，FamiliarLiveReplyStatus 只显示真实等待；父回复消费 Controller 的活动投影。默认折叠的卡片在结束后显示低权重摘要，Timeline 持有独立的展开状态以跨 live／history 转换保留手动选择。文件卡片用真实路径决定是否可预览／分享，撤销／缺失显示不可用；复制使用 Message 的最终 block ID。Context／Records／Code／Diff 的原有详情组件继续复用。
- `FamiliarRuntimeActivityProjection.swift` — 展示专用纯值类型：非空正文、交互和交付内容形成区段，按首个调用保持卡片身份；连续检索／阅读／文件／执行／分析归类，不生成固定未来流程。来源按 Foundation URL 身份去重，notice 不增加调用数。读取失败通常为 warning，凭据／权限和不确定写入保持强提示；Shell typed result 失败不会被 envelope 的成功投递掩盖。基础成功调用只进入技术详情。它不执行工具、不决定权限、不修改持久数据。
- `FamiliarSurfaceDescriptor.swift` — 实时/历史共用的语义投影，descriptor 保存 Runtime sequence、稳定 tool identity、进度／失败信息和授权决定；实时参数只存在内存，历史不从 hash 还原。重试用事件 sequence 区分，并用可选 Call ID／既有 parentID 关联。终态／重复／过期事件不能重新打开已完成的调用。scalar、searchResults、document、contextMatches、recordCollection 等不再按固定区域堆叠，而是在所属 Assistant Turn 的调用位置渲染。`FamiliarToolPresentationName` 同时持有 name→title 与 name→SF Symbol 两张显式表；图标不放进 manifest，因为所有调用点只拿到持久化的 `activity.toolName`，历史 Run 必须在对应工具已不再注册时渲染出同一图标。
- `FamiliarComposerView.swift` — compact/expanded/fullscreen 输入器、附件/相机/相册、一次性 Slash Skill 选择与语音。
- `FamiliarSettingsHubView.swift` / `FamiliarSettingsView.swift` / `FamiliarSearchSettingsView.swift` — 设置 hub、模型服务、执行限制、Memory、Diagnostics、独立网页搜索设置和 Python 软件源设置。Diagnostics 页复用 `registry.availabilityReport()`，展示已注册工具的状态；按需加载使用相同 registry availability 检查成员并告知模型原因。它显示 Shell Runtime phase 和当前可用的已注册工具数，不声称这些 Schema 全部进入模型请求。执行限制页用 stepper 暴露步数/工具调用/时长三个预算，范围与 `FamiliarExecutionBudget.normalized` 的钳制一致，因此控件无法表达一个 Runtime 会静默拒绝的值；Memory 页提供自动记忆开关、按 scope 与来源列出每条记忆、编辑、滑动删除与二次确认的全部删除，编辑会重写派生的去重键并复用同一套敏感内容拒绝规则。模型服务页此前有 4 个 `body` 从不渲染的 section（含重复的通知开关与重复的 system prompt 编辑器），且其 `.task` 会在未授权时静默关闭通知，已一并删除；Shell 限制展示改为从 `FamiliarShellLimits.iOS` 派生而非硬编码字符串。权限页覆盖日历、提醒、联系人、位置、照片添加、照片读取、健康活动、Apple Music、蓝牙、相机、麦克风、语音识别与通知，其中健康只显示“已请求/尚未请求”并在 footer 说明 HealthKit 从不揭示读取拒绝；软件源只允许选择内置校验的官方 PyPI 或清华 TUNA HTTPS 索引，不接受任意 URL。搜索页提供 Provider 选择、独立 Key 保存/删除、最小连接验证以及隐私/费用说明。Skills 页只以右上角加号打开带默认 instructions 模板的创建表单，没有导入行，新建 Skill 的 allowedTools 为空——按现在的语义这表示「未声明限制」，不会收窄工具；页面仍没有主动收窄的编辑控件。
- `FamiliarProjectsView.swift` — Project Context Workspace：项目列表/主页/编辑（含可选的项目级模型选择）。主页展示新聊天主动作、指令、聊天、文件/网页/文本资料和输出；Environment、按需 Skills、MCP、Capability 与 Runs 集中在同一 Stack 的高级 List，保留原查询与操作。File 列表与首页摘要都按 `lineageID` 折叠为「一个交付物一行」，只展示最新版本，旧版本进入版本历史页并保持可预览、可分享；版本号只在该谱系确实有历史时显示，否则「v1」会暗示不存在的修订。
- `FamiliarSharedDestinationView.swift` — Share 收件箱目标选择（已有项目、新建项目、普通聊天草稿）。
- `FamiliarMarkdownWebView.swift` — 非持久化 WKWebView 渲染 + 高度回传 + 首帧回退文本；终态通过 `selectionChanged` bridge 回传最多 4000 字符纯文本，流式状态禁用并清空选择；长 Mermaid 通过 `previewMermaid` bridge 打开全屏，并复用同一 bundled renderer、非持久化 data store 与禁止远程连接的 CSP。
- Render state 附带原生 styleJSON（外观、对比度、动态字号与现有 token）；样式变化沿同一更新／节流／高度回传路径重新测量。代码复制、Mermaid 预览文字由原生本地化提供；对应详情复用完成按钮，结果和共享目标的 selected-model sheets 用 Identifiable 状态。
- `FamiliarCameraView.swift`、`FamiliarAttachmentQuickLookView.swift`、`FamiliarMarkdownNormalizer.swift`。

### `Familiar/Vision/` 与暂不提供的 `Familiar/LocalVision/`
- `FamiliarVisionProcessor.swift` — Apple Vision OCR、条码、图像分类，生成标记为不可信只读内容的 `FamiliarVisualEvidence`。
- `FamiliarLocalVisionModelManager.swift` / `Vendor/ml-fastvlm` — FastVLM 研究源码暂留，但该文件被 iOS target 排除，FastVLMRuntime/MLX package product 不再链接；当前产品无下载或推理入口。

### `Familiar/Skills/`、`Familiar/Memory/`
- `FamiliarSkillService.swift` — JSON instruction-only parser、安装／更新／卸载与冻结 Run snapshot；Composer 可选一个 Skill，Project 可绑定候选。skill_read 按需加载最多一个并收窄工具，不以 planning 阶段为前提，不能授予权限。
- `FamiliarSkillPackageStore.swift` — ZIPFoundation/Yams 解析 SKILL.md 包，限制文件数与大小、拒绝路径逃逸／symlink、校验资源 hash，按内容地址存不可变资源；skill_install 提案批准后保存包与 Project binding。包存在不等于脚本执行或真实 guest 已验证。
- `FamiliarMemoryService.swift` / `FamiliarMemoryTools.swift` — 三层作用域（global/project/conversation）Memory 运行时。去重键按 scope 与其所有者派生，因此跨 Project 的同一句话是不同记忆。候选检索为只读关键词匹配，按 confidence、recency 排序；Context Compiler 应用 1200 字符预算，`lastUsedAt` 仅对最终冻结选中条目与已接受用户消息一起保存，表示「进入本轮上下文」，不表示 Provider 已成功响应。敏感内容在工具边界与持久化边界双重拒绝。`memory_search` 只读本次冻结的记忆；`memory_remember` 只返回审批提案，写入请求由 Controller 注入的 persistResult(result, commitContext) 回调在成功事件前落盘，失败回滚并返回结构化工具失败，模型无法自行写入。设置页提供开关、按 scope 与来源的列表、编辑、删除与全部删除。

### `Familiar/Resources/`
- `FamiliarProjectResourceStore.swift` — 项目资源磁盘（`<Application Support>/Familiar/ProjectResources/Projects/<projectID>/Resources/<resourceID>/Versions/<version>-<versionID>/`，SHA-256 校验、symlink/回滚安全删除）。
- `Familiar/Files/FamiliarFileImportService.swift` — 导入文档、粘贴文本和明确保存的 Web capture，直接写 File/FileVersion，旧 Resource 目录仅提供字节存储。Web save 只接受已持久化的成功 fetch，离线核对 hash；同一捕获重复保存复用，同 URL 的不同捕获保持独立身份。保存内容与 provenance 保留 URL/时间/正文 hash/截断信息。

### `Familiar/Speech/`
- `FamiliarSpeechTranscriber.swift` — `@MainActor` 持有 UI／录音状态，`SFSpeechRecognizer` + `AVAudioEngine` 与远程转写共用 sessionID 失效保护。音频会话变更按 Task 顺序串行，配置／硬件调用在 @concurrent helper 中执行；iOS 27 使用异步 activate/deactivate，iOS 18–26 的 setActive 只在后台执行。准备中的停止和权限／激活返回后的旧流程不能启动录音，远程转写终态释放身份以允许再次录音。

### `Familiar/Support/`
- `FamiliarTheme.swift` — 语义 spacing / typography / radius / icon / control tokens、基础 ButtonStyle，以及 iOS 26 `glassEffect`/material 回退 modifier。`FamiliarTypography` 全部使用可缩放的语义 Font 角色。固定点数只保留给装饰容器与点击目标内的 SF Symbol；正文类固定字号已改为 `@ScaledMetric`（Composer 编辑器），且其高度计算必须从同一个缩放值派生，否则渲染缩放字体而按固定 20pt 测量会裁掉用户自己的文本。
- `FamiliarMarkdownStyle.swift` — iOS 原生语义 UIColor/Theme、UIFont Dynamic Type 与对比度解析的 CSS variable 输入；sorted JSON 保持等价输入稳定，内容不能自行提供这些样式。源码使用当前 UITraitCollection mutations API，无另一个主题或缓存权限层。
- `FamiliarMotion.swift` — 集中 motion tokens（`micro/state/spatial/drawer`）与 `FamiliarHapticPolicy`（只标记 awaitingApproval/succeeded/failed 边界）。

### `Familiar/SystemEntry/`
- `FamiliarAppIntents.swift` — `AskFamiliar`/`ProcessWithFamiliar`/`OpenFamiliar`、`FamiliarAppIntentHandoff`（排队 system entry）。
- `FamiliarNotifications.swift` — `FamiliarNotificationService`、`FamiliarAppDelegate`（UNUserNotificationCenterDelegate）。
- `FamiliarSpotlight.swift` — `actor FamiliarSpotlightIndexer.shared`，CoreSpotlight 会话标题索引。

### `Familiar/Web/` — 只读 Web
- `FamiliarSearchProvider.swift` / `FamiliarWebSearchService.swift` — 独立 Search Provider 契约、请求/响应、catalog/settings 与动态路由；默认 DuckDuckGo，选择保存在 `familiar.search.provider.v1`，所选服务失败不 fallback。
- `FamiliarSearchProviderAdapters.swift` — DuckDuckGo（复用 HTML + Lite SwiftSoup parser）、Brave normal web、Tavily basic（禁 answer/raw/images）、Exa fast + highlights-only；固定 HTTPS host，ephemeral URLSession 禁 Cookie/缓存/重定向，并限制超时与响应大小。
- `FamiliarWebContentService.swift` — `web_fetch` 页面读取与可读性抽取，输出正文、实际抓取时间和正文 hash，并保留 DuckDuckGo HTML/Lite parser 供 adapter 使用。
- `FamiliarRestrictedHTTPClient.swift` / `FamiliarPinnedConnection` / `FamiliarWebDNSResolver.swift` — 自研 Network.framework HTTP/1.1：getaddrinfo 公网校验、TLS SNI、手动请求/响应、重定向/大小/类型/超时限制。**刻意不用 URLSession**（避免 JS/Cookie 与系统级联行为）。
- `FamiliarWebURLPolicy.swift` — HTTPS-only、私网/保留地址拒绝。
- `FamiliarWebTools.swift` — `web_search`、`web_fetch`（read/sensitive）。
- `FamiliarWebModels.swift` — `FamiliarWebError`（18 cases）、含抓取元数据的 FamiliarWebFetchOutput、由它派生的 capture 和带来源头的 resourceText、`FamiliarSourceIdentifier`。Runtime Result/Event 不再另传 webCaptures；旧历史缺少完整捕获元数据时仍可阅读，但不提供离线保存动作，不回填推算值或重新抓取。

### `Shared/`（app + 扩展共享）
- `FamiliarSharedInbox.swift` — App Group 共享收件箱（manifest + 校验）。
- `FamiliarControlIntent.swift` — `OpenFamiliarControlIntent`。

### `FamiliarWidgets/`、`FamiliarShareExtension/`
- Widget bundle（launcher + control）、`SLComposeServiceViewController` 分享面板（最多 3 文件、25 MiB）。

## 4. 工具目录与按需暴露（无条件 55 个 + 资产条件 2 个 = 最多 57 个）

注册位置：FamiliarAppDependencies.init()。注册表保存 typed adapters；注册不等于模型暴露。Frozen catalog 先应用 Project 默认／显式设置和 Skill scope，首轮只带三个基础 Schema。tools_load 经 FamiliarToolLoader 检查所选成员当前 availability，再返回本轮扩展；实际调用再次检查。Diagnostics 的 availabilityReport 展示所有已注册工具状态，不声称它们已全部提供给模型。

| 分类 | 工具 |
|---|---|
| 设备原生 | `current_date_time`、`app_information`、`contacts_search`、`current_location`、`clipboard_read`、`clipboard_write`、`prepare_share`、`familiar_search` |
| Apple Framework（地点/天气/文本） | `map_search`（MapKit）、`weather_forecast`（WeatherKit 未来预报）、`weather_history`（WeatherKit 历史区间，2021-08-01 起、单次最多 10 天、`endDate` 开区间）、`natural_language_analyze`（NaturalLanguage，设备内） |
| Apple Framework（个人数据） | `health_activity_summary`（HealthKit 只读聚合）、`photos_recent_metadata`（PhotoKit 只读元数据）、`music_catalog_search`（MusicKit 目录）、`bluetooth_scan`（CoreBluetooth 前台按 UUID）、`notification_schedule`（UserNotifications，可撤销写） |
| AlarmKit | `alarm_schedule`（durable undo）、`alarm_cancel`、`alarm_list`；iOS 26.1 以下 `availability` 返回 `.unavailable`，因此不进入模型工具列表 |
| EventKit | `calendar_events`、`create_calendar_event`、`update_calendar_event`、`delete_calendar_event`、`reminders`、`create_reminder`、`update_reminder`、`delete_reminder` |
| Workspace | `workspace_list`、`workspace_read`、`workspace_search`、`workspace_write`、`workspace_image_list`、`photos_save_output`、`prepare_file_export` |
| Files | `file_list`, `file_search`, `file_read`, `file_write`, `file_edit`, `file_publish`; frozen FileVersions, typed results and explicit truncation |
| Web | `web_search`、`web_fetch` |
| Presentation/interaction | `tools_load`、`task_plan`、`present_recommendation`、`present_insight`、`ask_user`、`skill_list`、`skill_read`、`skill_install` |
| Memory | `memory_search`（只读本次运行冻结的记忆）、`memory_remember`（返回审批提案，仅 `.once` 授权，写入请求经 Controller persistResult 回调在成功事件前落盘） |
| Shell/Environment | `environment_status`（**无条件注册**：只读磁盘 receipt，不需要 guest）、`environment_prepare`、`shell_execute`（后两个仅在 bundled bridge/rootfs 存在时注册，实际执行才准备 guest） |

一个 Apple Framework 只建一个 Service，可暴露多个 Tool：`FamiliarEventKitService` 出 8 个日历/提醒工具，`FamiliarWeatherService` 出 `weather_forecast` 与 `weather_history`，`FamiliarAlarmService` 出 3 个闹钟工具，`FamiliarPhotoLibraryService` 同时实现 add-only 保存与只读元数据两个协议、出 2 个工具，二者授权分离。

工具参数统一使用 `Familiar/Agent/FamiliarToolSchema.swift` 的共享 DSL；`FamiliarJSONSchema` 支持 `items`/`minimum`/`maximum`/`minItems`/`maxItems`/`default`，数组必须声明元素类型。范围与默认值取自 `FamiliarToolDefaults`，同一常量同时供 manifest 与 `execute` 使用，避免 schema 与实际行为漂移。工具错误实现 `FamiliarStructuredToolError` 即可向模型返回稳定 `code`/`retryable`，Agent Loop 不再按具体类型硬编码分支。

App Intents 是系统入口，不作为模型可调用 Tool 注册；iOS 没有公开 API 可枚举或执行第三方 App 的 AppIntent，因此不存在“让 Agent 调用 App Intents”的路径。ToolRegistry 只按 manifest 分类和可用性注册，Agent Runtime 不包含 iSH 或 Native Tool 的类型判断。

## 5. SwiftData Schema

schema：`FamiliarReleaseSchema`（version `4.0.0`），当前 37 个实体。正式计划从冻结的当前旧 store 1.0.0 迁移；更早开发 store 不支持。历史 Artifact/Grant 实体已移出当前 schema；磁盘迁移执行尚未验收：

| 实体 | 运行时是否写入 |
|---|---|
| Conversation, Message, SourceRecord, Attachment, ModelSwitchRecord, AgentRun | 是 |
| Project, ProjectInstruction | 是 |
| Resource, ResourceVersion | 无生产新增写入；仅历史存储关系、迁移读取与显式删除 |
| FileRecord, FileVersionRecord | 是（上传、Project/Web 导入、生成结果、Shell 捕获、版本与关联） |
| ContextSnapshotRecord, ContextResourceReference | 是（冻结初始输入引用，不重复存文件正文） |
| CapabilitySnapshotRecord | 是（冻结/加载工具审计与中断识别，仍有历史生产读取用途） |
| RunResumeCursorRecord, ToolInvocationRecord | 是（工具请求/审批/完成与终态 cursor；跨进程恢复未实现） |
| AuthorizationRuleRecord, EventKitUndoRecord, VisualEvidenceRecord | 是（真实授权、跨重启 Undo、视觉证据） |
| Skill, MemoryItem, MCPServerRecord, MCPBindingRecord | Skill 安装已写入；MemoryItem 由用户确认的 `memory_remember` 与设置页写入，并由 Context Compiler 读取；HTTP MCP 已接线；STDIO 与 MCP OAuth 未接线 |
| RunSkillSnapshotRecord | 是（Run 启动时冻结 Skill ID/版本/hash/allowedTools） |
| PinnedItemRecord | 是（项目/会话统一持久置顶） |
| ActivityRecord, ToolResultRecord, ApprovalRecord, ResponseBlockRecord | 是（Assistant Turn 的活动、结构化结果、审批审计与回复块投影；ApprovalRecord 保存 allowedAuthorizationDurationsJSON，ActivityRecord 保存 failureCode/failureRetryable） |
| ClarificationRecord | 是（typed requested/resolved/cancelled/interrupted；重启后 pending 只恢复为 interrupted 展示） |
| ProjectEnvironmentRecord, ProjectSkillBindingRecord, ProjectCapabilityBindingRecord | 是（Environment receipt 与 Project-owned Skill/Capability scope） |
| AlarmUndoRecord | 是（`alarm_schedule` 的跨重启 undo；闹钟必然在未来触发，session 级 undo 会给出无法兑现的承诺） |

关系删除规则保留必要 cascade。已提交文件由 Project 所有，删除 Chat 不删除其字节。FileCatalog 统一文件删除；Project 删除暂存各后端目录，数据库提交后丢弃，失败时恢复。普通启动/迁移失败不自动清空；只有恢复界面的显式用户确认可重建 store。独立 Audit 包含逐请求编译清单、归档 Grant provenance 和运行记录；归档内容不能授权。

## 6. 数据流（消息 → Agent → 持久化）

```text
Composer
  → FamiliarChatView.onSend
  → FamiliarChatController.startSending        // Project override 后的模型／凭据／文档能力检查
      → 捕获草稿、历史、Skill；冻结 permitted native catalog + enabled MCP discovery closures（无提前网络发现）
      → 只读 Project／Memory 候选；await 后台图片编码／草稿写入，预定消息 ID 与附件最终路径，用草稿路径读取图片
      → FamiliarContextCompiler.assemble + validateSubmission
          → protected Project + 本轮用户消息／附件 + 基础 Schema 必须合计可容纳；旧历史可在 Loop 压缩
          → 文本模型图片识别后再次组装／验证；取消、草稿变化或失败均保留当前草稿
      → 复制附件、插入消息 + 最终选中 Memory usage，一次 context.save
          → 失败回滚并删除本次复制；成功后才清空草稿
  → performSend（复用同一个已验证 ContextSnapshot，不重新选上下文）
      → FamiliarAgentLoop.stream（首轮三个基础 Schema；tools_load 的成功结果替换后续扩展 Schema）
          → provider.stream（正文/reasoning summary/工具调用增量；transient/限流首字节前发 typed retry notice 后有界重试）
          → 单一 ContinuousClock deadline 同时约束 provider stream、tool execute、approval wait、retry sleep
      → registry.preflight -> policy.evaluate -> approval -> permission/target revalidation
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
          → persistResult 回调先保存 File、安装的 Skill 和 Memory；失败回传工具失败，成功后才产生 activityCompleted/toolResultProduced
          → toolResultProduced → typed result（网页捕获元数据包含在 envelope）、loaded Skill 审计；原生 durable Undo 已在 persistResult 成功边界保存；activityCompleted 只更新呈现
          → 用户在网页结果点击保存 → 从真实成功 Result 读取原捕获，校验并写 Project Resource；不重新请求网络、不更改当前冻结 Run input
      → assistantTurnCompleted 在每轮工具边界写独立 Markdown ResponseBlock；Controller 以 Runtime sequence 保持正文与工具顺序
      → reasoningSummaryCompleted 在 Controller 内存汇总，回复完成时一次写 reasoningSummary ResponseBlock
      → runFinished(outcome) 是 Controller/Recorder/Surface 唯一 Run 终态；成功后保存 markdown ResponseBlock + Sources + 可选本地通知
          → failed/cancelled Run 写 runtime notice Activity + ResponseBlock
  → 启动时：recoverInterruptedRuns 把遗留 running Run 终结为 failed
```

主要 actors：`FamiliarToolRegistry`、`FamiliarToolConfirmationCoordinator`、`FamiliarUndoStore`、`FamiliarRuntimeEventEmitter`（private）、`FamiliarEventKitService`、`FamiliarSpotlightIndexer`。
MainActor 容器：`FamiliarChatController`、`FamiliarRunPersistenceRecorder`、`FamiliarProjectService`、`FamiliarFileService`、`FamiliarFileImportService`、`FamiliarAppIntentHandoff`、`FamiliarSpeechTranscriber`。

### 验证入口

- `Scripts/run-release-test-suites.sh --check-list` 只核对当前 Suite/XCTest 清单，不启动 Simulator 或测试：42 个 Simulator suite、2 个签名设备 suite，以及完整 FamiliarUITests target。
- 默认模式接受已构建的 Simulator UDID/DerivedData，运行确定性套件与 UI target；`--device` 只运行单列的真机 guest 与签名图片取消套件，需要预构建的签名设备 host。未在本轮调用这些执行模式。
- 每个结果由本机 Xcode xcresulttool summary 反查 total/passed/failed/skipped/expectedFailures；零测试、跳过、预期失败或缺失统计不会被报告为通过。清单、编译和合成报告校验都不代替实际运行。
- `FamiliarSignedSubmissionTests` 检查签名 Keychain 与已排队图片发送的取消／草稿安全，不声称 OCR 已开始或完成，也不发 Provider 请求；缺失 entitlement 直接失败。`FamiliarDeviceRuntimeTests` 才是实际 guest 验证，Simulator skip 不算验收。

## 7. 存储位置

| 数据 | 位置 |
|---|---|
| SwiftData store | Debug：`<Application Support>/Familiar/Persistence/FamiliarDevelopment.store`；Release：`.../Familiar.store` |
| 附件 | `<Application Support>/Familiar/Attachments/{Drafts,Messages}/` |
| 项目资源 | `<Application Support>/Familiar/ProjectResources/Projects/<projectID>/...` |
| Generated File backend (legacy byte root) | `<Application Support>/Familiar/Artifacts` |
| FastVLM 残留研究资产 | `<Application Support>/Familiar/LocalModels/FastVLM/installed/`；当前无 UI/DI/自动路由入口 |
| Core AI 模型 | `<Application Support>/Familiar/Models/{Downloads,Installed,Staging}/`（当前无已配置 Qwen manifest asset） |
| Workspace | `<Application Support>/Familiar/Workspaces/{project-,conversation-}<UUID>/` |
| Project Environment | `<Application Support>/Familiar/Workspaces/project-<UUID>/Runtime/Environment/`；普通 Chat 位于 task view 并在终态删除 |
| 模型 API Key | Keychain（service `com.isaachuo.familiar.provider-api-keys.v2`） |
| Search API Key | Keychain（service `com.isaachuo.familiar.search-provider-api-keys.v1`） |
| Provider 设置/Search Provider 选择/Python 软件源选择/通知开关 | UserDefaults |
| 共享收件箱 | App Group `group.com.isaachuo.familiar` |

## 8. 已知缺口与未验证边界

- iOS 1.0 设置只保存所选供应商／模型与执行预算，不再保存 local/cloud 路由策略；显示供应商实例与模型分组。App 直接进入 Chat，缺少 API Key 时由发送动作提示并提供设置入口；所选 Provider 直接进入 Loop，本地模型无生产路由。
- 模型实例可声明图片输入能力，支持时直接发送图片；不支持时保留 Apple Vision 文本证据路径，DeepSeek 默认不发送图片 bytes。
- 当前开发机已验证为 Xcode 27.0（27A266a）/ iOS Simulator 27.0 SDK；Core AI API、Qwen3-0.6B bundle、specialization 与真机断网流式对话未在本轮接通或验收。`FamiliarCoreAIModelProvider` 目前只完成 SDK-neutral adapter contract。
- iSH fork 固定到 `54ca185b77f170e12fd353fcd7443232f6cb73fd`，Alpine 3.24.0 aarch64 fakefs、安装 identity、Project/Run Environment mount 与 headless bridge 已加入生产 target；真实 guest 冷启动、PyPI 安装、DOCX 生成和资源边界尚待 `hwf` 真机验收。
- macOS 已直接编译链接 Containerization 0.33.4，并有可构造 networkless LinuxContainer 的 session/factory；Familiar runtime kernel/init/rootfs/persistent disk 的下载校验器与真实 VM 启动尚未完成。FamiliarMac 当前是原生 Codex 式 UI shell，未接入共享 SwiftData/Agent Runtime。
- Workspace 的 Files 以 Attachment/Project Resource ContextSnapshot 虚拟投影，Outputs/Runtime 保持独立目录；不做重复物理迁移。未公开的 development store 不迁入首个 Release store，也不会被自动删除。
- ToolInvocation/cursor、授权创建/消费均已接入；字节级中断续跑仍未实现。
- Project Capability/Skill binding、指令 Skill 与 checked resource packages 均有接线。Shell 资源投影和真实安装／文档任务仍需设备验收。Memory Runtime 与 HTTP MCP 已接入；STDIO、MCP OAuth、完整 Schema 与可靠后台执行未完成。
- 后台承接（`BGContinuedProcessingTask`，iOS 26+）未实现；当前无后台 Run 保证。
- DeepSeek、Search Provider、EventKit 跨重启 Undo 与 Surface 视觉/无障碍仍缺真机验收；当前没有真实 Provider 冒烟结论。FastVLM 不进入当前验收范围。
- WeatherKit、HealthKit、PhotoKit、MusicKit、CoreBluetooth、AlarmKit 全部只完成编译与 fake-service 契约测试。真实可用性额外依赖签名 entitlement 与 provisioning（WeatherKit）、真实系统授权（Health/Photos/Music/Bluetooth）与 iOS 26.1 设备（AlarmKit），Simulator 构建无法证明其中任何一项。`weather_history` 的历史覆盖范围与 Apple Weather 配额消耗未在真实账户上验证。
- `alarm_schedule` 的 durable undo 已写入 `FamiliarAlarmUndoRecord` 并可从记录重建取消动作，但跨重启撤销未真机验证；闹钟已响铃后取消的系统行为未验证。
- AlarmKit 只使用 alert-only presentation，因此不提供 countdown/paused 状态，也不新增 widget extension；重复闹钟、贪睡与 Live Activity 不在当前范围。
- 敏感 read（health/photos/bluetooth）的仅这次/本会话授权已接入 Agent Loop 并有确定性测试，但真机上多轮任务的实际打断次数未人工验收。
- Skills 已支持一次性指令注入、工具收窄、Run 快照和 checked package resources；不能将安装包等同于赋予权限。Memory/HTTP MCP 已实现；工具组懒加载已接线；真实 Provider／服务器／guest 和设备验收仍待完成。


## H Files convergence (2026-10-06, H1/H2 implemented)

- Domain FileReference/StorageReference/FileSnapshot and persistent FileRecord/FileVersionRecord own product identity, Project scope, Chat associations, versions, provenance and explicit Project-context selection. Byte roots remain internal storage. Fresh uploads record actual hashes; old missing attachment hashes remain explicitly unknown. Version-number high-water marks survive revision Undo.
- FamiliarStoreSchemaV1 freezes all 37 original entity definitions. SchemaMigrationPlan uses additive bridge 2.0.0 to convert resource/version, generated-file lineage/version, attachments and saved scopes, then removes the old generated-file entity in current 3.0.0 (38 entities). Only explicit existing same-Project relationships share identity; names/hashes never merge files. Historical Resource/Attachment fields retain necessary relationships; new Resource production writers are removed in H5.
- Project and Chat use FamiliarFilesView; obsolete separate resource/output lists and the workspace-path Chat browser are removed. FileCatalogService provides scoped integrity reads, context selection, byte/metadata deletion compensation and cross-Project copies. Shared FileByteReader serves Tools and native preview. Deleting a Chat retains owned bytes and pruning includes File references. Moving a Chat clears its old summary and Conversation Memory now requires both Chat and Project identity.
- file_list/file_search/file_read/file_write/file_edit/file_publish form one Files tool group. Search covers filenames and already-selected text, with no full-content index claim. The catalog and approved saved-file snapshots feed the existing Run-local state; the persistence callback returns domain-only receipts. This is not the full H3 Run State.
- Shell success captures added/modified Outputs into immutable managed bytes, registers File versions before success and supports rollback/Undo of those captures; Work/Environment/checkpoints remain internal. Migration-only adoption preserves old output files with observation provenance rather than claiming an exact historical execution capture. A Files view never reimports deleted files. Project deletion and confirmed store recovery include managed byte roots.
- Current production APIs/value types use File names. Old entity definitions, stored configuration identity conversion, old artifactMutation decoding and old directory paths remain only for data/history handling. No old callable tool aliases are registered and no historical authorization is translated into new authority.
- `/tmp/familiar-architecture-files-final-20261006-build.log` confirms arm64 original-project test-target compilation. Static/localization/inventory checks pass. Disk upgrade/iOS tests and device/service acceptance are unexecuted; Compiler/Policy/persistence implementation is complete; migration execution and device/service acceptance remain H7/H8.

### H3 Compiler / Run State (2026-10-06)

Context/FamiliarContextCompiler freezes submission input and owns subsequent Agent request composition and automatic/manual compaction rules. FamiliarContextCompilation is immutable and contains input identity, schema/content hashes, scoped provenance, references, observed times and a bounded factual summary. Runtime records transcripts/results and performs compiled provider calls under its deadline; it adds no Skill/closing instructions itself. Long-term inputs are not reselected mid-Run. Project file bodies use a character budget and omitted entries remain discoverable; current submission contents are not truncated. Compaction retains the current turn and complete assistant/tool pairs.

FamiliarRunState is a factual actor: discovered versus currently exposed tools, loaded/installed Skills, result identities/hash/truncation, Memory read IDs, Web observations, attempted/committed/failed/uncertain/compensated writes and committed FileVersions. Known frozen versions reuse at most 64k characters of file-read results after policy checks, keeping the original observation time. External tools remain refreshable. Request audit uses existing ActivityRecord rows (context: identity, context_compiled summary, Codable manifest in detail), excluded from response presentation. Saving the audit precedes a model call and can fail the request. Compiler audit adds no entity; after H5 the current schema is 4.0.0 / 37 models.

Validation: static checks and arm64 generic Simulator build-for-testing; iOS regressions compiled, not executed. Disk/user-data upgrade and device/service acceptance remain separate.

### H4 / H5 Policy and persistence boundaries (2026-10-06)

Policy owns scope/availability/dynamic risk, exact authorization lookup and issuance, confirmation contents, permission/preflight rechecks and optional adapter target validation. Registry validates names, schema declarations, effect/parallelism, deadlines and output envelopes. Read concurrency requires noninteractive preflight. Commit uses the declared tool timeout, with journal, reserved write fingerprint, durable Undo, persistence-gated receipt and compensation preserved. EventKit validates content/calendar revision before committing; changed/default targets and newly prepared permissions invalidate stale previews. External APIs do not provide a distributed transaction or automatic replay.

FileImportService writes canonical File/FileVersion without Resource rows. Submission indexing is FileCatalog.stageUploads, not the migration converter. The old byte roots remain adapters. Artifact and Grant entities are excluded from current schema; Grant fields move to nonexecutable Activity audit, retaining original identity in its payload. Capability snapshots remain because interruption inspection reads their effects. Resource/Attachment stored fields remain where historical relationships require them; there is no automatic history cleanup. Pure authorization/Skill/Memory contracts are separate from SwiftData services, and Runtime/Context/Domain import no concrete UI or SwiftData.

Current schema: 4.0.0, 37 entities. Migration: frozen 1.0.0 (37) -> additive 2.0.0 (39) -> Files 3.0.0 (38) -> Grant archive/removal 4.0.0 (37). Containers keep their addresses. No disk migration, service or device acceptance is claimed from compiled regressions.

Final compilation: /tmp/familiar-architecture-verified-20261006-build.log TEST BUILD SUCCEEDED (exit 0); no warning/error. Static diff/localization/inventory/core-import checks pass. Tests compiled only; H7/H8 remain unexecuted.

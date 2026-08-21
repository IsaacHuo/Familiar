# Familiar 决策记录

本文件记录影响产品范围、数据边界和工程结构的决策。每项决策包含状态、依据、影响和复审条件。

## D-001 采用 BYOK 和设备直连

- 状态：生效
- 决策：用户提供各 Provider API Key。iPhone 直接调用 Provider。
- 依据：降低服务端数据责任，保持用户与 Provider 的直接费用关系，支持多 Provider。
- 影响：
  - 发送模型请求前需要 Provider 配置；首启允许先浏览 App 和本地内容。
  - App 需要处理不同 endpoint、认证和协议。
  - Provider 可用性和费用由用户选择决定。
  - 当前个人实验优先完成 DeepSeek 真实冒烟；其他 Provider 不作为下一阶段验收阻塞项。
- 复审条件：引入 Familiar 托管服务、账户或统一额度。

## D-002 无账户、无 Familiar 业务后端

- 状态：生效
- 决策：首发不提供登录、云同步、订阅、权益和 Familiar 业务数据库。
- 依据：产品首发范围集中在本机行动助理闭环。
- 影响：
  - 会话只保存在本机。
  - 无跨设备同步。
  - 卸载可能导致本地历史丢失。
  - 网站承担产品说明、隐私和支持功能。
- 复审条件：用户研究明确需要跨设备连续性。

## D-003 iPhone-only，最低 iOS 18

- 状态：生效
- 决策：`TARGETED_DEVICE_FAMILY = 1`，部署目标 iOS 18。
- 依据：集中优化单手聊天和输入器体验，使用 SwiftData 与 EventKit full access API，并为后续系统入口（App Intents、Widgets、Controls、Deep Link）预留系统能力。
- 影响：
  - 不维护 iPad 专用布局。
  - Simulator 和真机验证覆盖 iOS 18 与当前系统。
- 复审条件：iPad 进入正式产品范围。

## D-004 iOS 26 Liquid Glass，旧系统使用 Material

- 状态：生效
- 决策：导航、输入器和浮层在 iOS 26 使用系统 glass API；iOS 18–25 使用 Material 和边框。
- 依据：遵守系统版本能力和 Apple Materials 使用范围。
- 影响：
  - 消息正文不使用玻璃。
  - Reduce Transparency 使用实色回退。
  - UI 验收需要覆盖两个实现分支。
- 复审条件：Apple API 或设计指引变化。

## D-005 采用 ChatGPT 移动端信息结构参考

- 状态：部分被 D-036 替代
- 决策：参考其抽屉、顶栏、时间线、输入器比例和反馈节奏。
- 依据：目标用户已熟悉聊天型 AI 产品的信息结构。
- 影响：
  - Familiar 使用蓝紫品牌体系。
  - 入口只对应当前真实能力。
  - 账户和订阅入口不进入界面；Project 按 D-036 成为一级工作单元。
- 复审条件：可用性测试显示主要任务路径需要调整。

## D-006 输入器参考 Leafy 日迹页

- 状态：生效
- 决策：输入器结构、附件菜单、相机和相册选择参考 Leafy 日迹页。
- 依据：该交互已形成明确的移动端内容录入模式。
- 影响：
  - 输入器支持 compact、expanded、fullscreen。
  - 添加菜单包含文件、拍照和相册。
  - Familiar 保留聊天所需的语音和发送/停止状态。
- 复审条件：输入器真机验收发现键盘、长文本或附件操作阻塞。

## D-007 使用字符串 ID 的 Provider Catalog

- 状态：生效
- 决策：Provider 和模型使用字符串 ID 与 descriptor，避免封闭枚举。
- 依据：多 Provider、手动模型 ID 和自定义服务需要开放标识。
- 影响：
  - 会话和消息保存实际 Provider/模型 ID。
  - 未知模型可以进入 text-only 回退。
  - 模型能力由 catalog 控制。
- 复审条件：引入远程 catalog 签名或服务端能力发现。

## D-008 明确区分三类协议 adapter

- 状态：生效
- 决策：OpenAI Chat、Anthropic Messages、Gemini Generate Content 使用独立编码和事件解析。
- 依据：三类 API 的消息、工具和流事件结构不同。
- 影响：
  - OpenAI-compatible Provider 使用逐 Provider 配置。
  - adapter fixture 需要分协议维护。
  - 新 Provider 接入先确认协议和差异点。
- 复审条件：Provider 发布新的稳定统一协议。

## D-009 模型能力执行 gate

- 状态：生效
- 决策：工具、文档、图片和上下文上限由 `providerID + modelID` 决定。
- 依据：不同模型能力差异会影响请求合法性和用户预期。
- 影响：
  - 未知模型默认 text-only。
  - 工具关闭时不发送工具定义。
  - 文档不受支持时请求前阻止。
  - 图片链路关闭时请求前阻止。
- 复审条件：引入可信能力发现和缓存。

## D-010 使用有限 Tool Loop

- 状态：生效
- 决策：Agent Loop 具有轮次、工具注册、参数、结果和上下文限制。
- 依据：首发工具范围固定，需要可预测终止和错误边界。
- 影响：
  - 默认最多 6 轮。
  - 只执行注册工具。
  - 不引入工作流引擎、多 Agent 或通用自动化框架。
- 复审条件：工具数量和任务复杂度超过有限循环能力。

## D-011 EventKit 写入逐次确认

- 状态：历史方案；逐次确认政策被已实现的 D-041 精确期限授权替代
- 决策：创建事件和提醒前显示结构化确认卡。
- 依据：系统数据写入需要明确用户意图和可审查参数。
- 影响：
  - 工具 `execute` 先生成 pending write request。
  - 确认协调 actor 暂停 Agent Loop。
  - 取消结果回填模型。
  - 未确认状态下不调用 EventKit save。
- 复审条件：新增修改、删除或批量操作。新增操作仍需保持同等级确认。

## D-012 流式文本不写入 SwiftData

- 状态：生效
- 决策：逐 token 状态保存在 Controller 内存，回答终态一次保存。
- 依据：降低 SwiftData 广泛 invalidation 和写入频率。
- 影响：
  - 中途终止时不保留部分助手消息。
  - 用户消息已在请求前保存。
  - 工具终态可以独立保存。
- 复审条件：产品要求恢复部分生成内容。

## D-013 使用本地非持久化 WebKit 渲染

- 状态：生效
- 决策：Markdown、代码、KaTeX 和 Mermaid 使用 Bundle 资源与 non-persistent WebView。
- 依据：统一流式和终态排版，支持复杂内容格式。
- 影响：
  - WebView 关闭内部滚动并回传高度。
  - 渲染失败提供 SwiftUI 回退。
  - CSP 控制网络和执行边界。
  - 远程 Markdown 图片不自动加载；HTTPS 图片在插入文档前替换为来源链接，只有用户主动点击后才交由系统打开。
- 复审条件：原生文本栈完整覆盖现有格式和性能要求。

## D-014 文件统一通过 AnyDoc

- 状态：生效
- 决策：支持文档通过 `FamiliarAnyDocService` 进入统一转换链路。TXT 和 Markdown执行编码验证与文本直通。
- 依据：统一格式检测、Markdown 输出、引擎版本和错误表达。
- 影响：
  - Office、OpenDocument、RTF、EPUB、CSV、PDF 使用同一服务入口。
  - Provider 接收抽取文本。
  - 原文件保存在本机。
- 复审条件：增加 Provider 原生文件 API 或新的本地解析引擎。

## D-015 PDF 使用 AnyDoc、PDFKit 和 Vision

- 状态：生效
- 决策：AnyDoc处理文档结构，PDFKit 检查文本层，Vision 处理扫描页。
- 依据：文本 PDF 和扫描 PDF 需要不同处理路径。
- 影响：
  - 无文本层页面执行 OCR。
  - AnyDoc PDF unsupported 时执行 fallback。
  - OCR 准确率进入真机文件验收。
- 复审条件：AnyDoc 提供满足需求的完整 OCR 能力。

## D-016 图片保留输入能力，关闭发送链路

- 状态：历史过渡方案；纯文本模型阻断路径被已实现的 D-042 设备端视觉 fallback 替代
- 决策：相机和相册可以创建图片草稿。图片发送只对支持图片的模型开放，且图片字节只发往用户所选 Provider；能力不支持时阻止请求并保留草稿。
- 依据：输入器结构需要完整，模型图片编码和隐私验收尚未进入首发交付。
- 影响：
  - 拦截时保留文字和图片草稿。
  - adapter 保留第二层拒绝。
  - `supportsImages` 元数据不开放发送。
- 复审条件：完成图片编码、Provider 差异、大小处理、隐私和真实模型验证。

## D-017 语音只生成可编辑文本

- 状态：生效
- 决策：使用 Apple Speech 将语音写入输入框，不创建音频消息。
- 依据：首发目标是降低移动输入成本。
- 影响：
  - 不保存录音文件。
  - 可用时优先设备端识别。
  - 识别结果由用户编辑后发送。
- 复审条件：实时语音对话进入产品范围。

## D-018 AnyDoc 只构建 Apple Silicon slices

- 状态：生效
- 决策：XCFramework 包含 iOS arm64 和 iOS Simulator arm64。
- 依据：开发设备统一使用 Apple Silicon Mac。
- 影响：
  - 不提供 x86_64 Simulator slice。
  - CI 和本地构建使用 arm64 destination。
- 复审条件：CI 或开发环境需要 Intel Mac。

## D-019 开发 Schema 使用版本化 store

- 状态：被 D-047 替代
- 决策：当前 Schema 使用 `FamiliarAgentV2.store`。首次成功创建后清理旧开发 store；当前 store 无法创建时显示恢复界面，由用户确认重建。
- 依据：旧开发 store 缺少必填字段，SwiftData 自动迁移返回 134110；项目当前无正式用户，计划允许直接替换开发 Schema。
- 影响：
- 旧开发会话和附件被清理。
- 用户无需手动卸载以绕过旧 store。
- 恢复重建会清理当前 store 和附件，并保留 Keychain API Key。
- 公开版本仍需要正式迁移或明确的数据兼容声明。
- 复审条件：首个公开版本冻结 Schema。

## D-039 当前 7 实体冻结为 SwiftData V1

- 状态：被 D-047 替代
- 决策：当前 7 实体冻结为 `FamiliarSchemaV1` 1.0.0，所有生产和测试容器通过 `FamiliarSchemaMigrationPlan` 的 V1→V9 八个轻量 stage 打开，文件名继续使用 `FamiliarAgentV2.store`。顶层模型名由 typealias 指向当前版本模型，现有调用点不变。
- 依据：Project/Resource 引入前需要稳定的迁移起点；磁盘测试已证明旧直接 Schema store 可通过 migration plan 重开并保持全部实体数据和关系。
- 影响：后续持久化字段变更必须新增 VersionedSchema 和 migration stage。打开或迁移失败保持可观察，只有用户在恢复界面再次确认后才删除 store 与附件。
- 复审条件：设计 V2 Schema 或 SwiftData 改变 migration API/行为。

## D-020 项目正式使用 Swift 6

- 状态：生效
- 决策：Debug 和 Release 的 `SWIFT_VERSION = 6.0`。
- 依据：并发隔离问题需要在构建期作为错误处理。
- 影响：
  - DTO、actor、Main Actor 和 AVFoundation worker 边界明确。
  - 新代码需要满足 Sendable 和隔离规则。
  - Debug、Release、Simulator 和真机构建纳入验证矩阵。
- 复审条件：Swift 工具链升级引入新的语言兼容问题。

## D-021 Familiar 定位为 iPhone-native Agent Runtime

- 状态：作为执行内核继续生效，产品定位由 D-036 补充
- 决策：产品定义为 Agent Runtime：云端/可替换 LLM 负责理解、决策与编排；iOS 原生 Framework 负责感知、计算与行动；Native Workspace 提供通用内容处理能力。North Star：Familiar turns the iPhone's native capabilities into a composable runtime for AI agents。
- 依据：不以 Linux 为执行环境，不依赖 Apple Intelligence，不把用户需求硬编码成 workflow，也不从复杂多 Agent 开始。
- 影响：
  - 六层架构成为后续设计与实现基准：System Entry / Agent Runtime / Capability Registry / Execution Policy / Native Layer + State Layer。
  - 最核心资产是 Capability Registry、Agent Runtime、Execution Policy、Native Workspace。
  - Manifest v2、Resolver 和 BindingStore 完成后，新 Apple Framework、远程 MCP Server和模型主要通过 Adapter 接入。
- 复审条件：出现必须偏离 Agent Runtime 定位的明确需求。

## D-022 单 Agent First

- 状态：生效
- 决策：Familiar v1 只有一个主 Agent。Subagent、Manager Agent、Graph orchestration 暂时不做。
- 依据：工具重叠和逻辑复杂度真正成为问题之后再考虑多 Agent。
- 影响：
  - 通过清晰 Tools 扩展能力。
  - 多 Agent 相关架构不进入当前范围。
- 复审条件：单 Agent 可维护范围被复杂度超过。

## D-023 Tool 是最核心的抽象

- 状态：生效；Manifest v2 已实现，影响中“仍待实现”的表述仅保留为历史状态
- 决策：Calendar、Vision、PDF、Maps 等都只是 Capability Registry 中的 Tool。Tool 要小、正交、可组合。
- 依据：LLM 决定做什么，Swift 决定怎么做；模型只生成结构化 Tool Call。
- 影响：
  - 强类型 `FamiliarTool` 协议 + `AnyFamiliarTool` type erasure。
  - `FamiliarToolManifest` 当前包含 name、parameters、effect、risk、requirements；Manifest v2 仍待实现。
  - 不做 `summarizePDFAndCreateCalendarEvent` 这类大而全的工具。
- 复审条件：需要比 Tool 更粗粒度的编排抽象。

## D-024 Capability 可用性过滤

- 状态：生效
- 决策：启动时静态注册工具；当前设备、地区、系统版本、用户授权不可用的 Tool 不暴露给模型。运行时发现、安装和项目绑定尚未实现。
- 依据：避免模型调用不可用能力，减少错误与误操作。
- 影响：
  - Capability Registry 运行时过滤工具。
  - 工具能力关闭时不发送工具定义。
- 复审条件：引入远程能力发现。

## D-025 所有执行必须可观察（Trace）

- 状态：部分实现
- 决策：目标是一次 Agent Run 中的模型调用、Tool Call、失败、权限请求、耗时都可 Trace。当前 Runtime Event 驱动内存状态，只选择性持久化审批、模型、工具和结果摘要，不保存完整事件流。
- 依据：Agent 执行需要可调试、可重放、可审计。
- 影响：
  - Runtime Event 统一事件流。
  - Run/Step 成为正式数据模型。
  - 时间线即执行轨迹。
- 复审条件：Trace 能力与持久化边界冲突时重新评估。

## D-026 系统入口优先级

- 状态：生效
- 决策：系统入口按优先级排序：第一优先级 ① Familiar App ② Share Extension ③ 系统通知 / Deep Link；第二优先级 ④ Widgets / Controls ⑤ Spotlight 等轻量入口；兼容能力 ⑥ App Intents ⑦ Shortcuts。
- 依据：核心体验在 App 内，Share 与通知承担外部分发，轻量入口与系统表面延后，App Intents/Shortcuts 作为兼容能力打通系统生态。
- 影响：
  - App Intents 位于 Agent Core 之外，只暴露 Ask / Process / Open Familiar。
  - 不把整个 Capability Registry 复制到 App Intents。
  - Ask / Process 通过主 App 的单一 handoff 启动现有 Agent Runtime，输入限制为 20,000 字符；Open 只打开 App。
  - App Intents 不读取 Keychain 或直接调用 Provider，不授予工具权限；已有草稿时禁止覆盖，运行中请求结束后再处理。
  - iOS 18–25 使用 `openAppWhenRun`，iOS 26 起使用 `supportedModes`，保持当前最低系统版本与新 API 一致。
  - Share Extension 承接外部文本/文件进入现有执行链路。
  - 第一版 Share Extension 只写入 App Group 一次性收件箱；主 App 复用现有附件处理路径导入新草稿，不从扩展直接运行 Agent。
  - 当主 App 有未发送草稿或运行中请求时，共享项保持排队，禁止覆盖当前用户状态。
  - Deep Link 只恢复本地界面上下文或预填草稿，不自动发送、不调用工具、不携带密钥或授权。
  - 第一版 URL 为 `familiar://new?text=...`、`familiar://conversation/<UUID>` 与 `familiar://run/<UUID>`；后续通知和其他入口复用同一类型化路由。
  - 第一版本地通知只覆盖用户主动启动的 Run 完成或失败终态；用户在设置中显式开启后才请求权限，仅在 App 非活跃时安排。
  - 通知使用固定通用文案，只携带本地 Run / 会话 UUID，不包含问题、回答、附件名、工具结果、密钥或授权；点击后复用现有 handoff 与 Deep Link。
  - 不注册远程推送，不引入 Familiar 后端，不把通知描述为后台续跑保证；关闭功能时清理 Familiar 待处理与已投递通知。
  - 第一版 Spotlight 只索引已有消息或 Run 的会话标题、更新时间和本地 UUID；标题最多 80 字符，索引使用 `.complete` 文件保护等级。
  - Spotlight 不索引消息正文、附件名、工具结果、Run 详情、密钥或 Provider 配置，不启用公开 Web 索引；系统结果点击复用会话 Deep Link。
  - 索引随当前完整会话集合刷新，SwiftData 仍是唯一事实来源；索引失败不阻塞聊天、重命名或删除。
- 复审条件：系统入口需求或 Apple 系统能力变化。

## D-027 MCP 是 Adapter，不是 Kernel

- 状态：生效
- 决策：内部借鉴 MCP 的 Resources/Tools/Instructions 分离，但直接用 Swift。只支持远程 HTTPS Streamable HTTP Client，不支持本机 stdio Server；外部工具转换为 Familiar Manifest 后继续通过 Familiar Policy。
- 依据：MCP 是接入外部能力的协议，不定义 Familiar 内部架构。
- 影响：
  - 内部不引入 MCP Server。
  - OAuth/PKCE 凭据按 Server Identity 隔离在 Keychain。
  - 工具按项目/会话显式绑定，默认不全量开启；MCP annotation 不作为授权依据。
- 复审条件：需要在 iPhone 上托管 MCP Server。

## D-028 意图感知授权

- 状态：核心授权原则继续生效；决策正文中“当前按 D-011 全部逐次确认并仅提供进程内 Undo”的历史路径，分别被已实现的 D-041 与 D-045 替代
- 决策：目标授权模型允许精确匹配可审计 `AuthorizationGrant` 的可逆写入免除重复确认。当前按 D-011 对所有 EventKit 写入逐次结构化确认，成功后提供进程内一次性 Undo。
- 依据：权限由代码控制，不靠 Prompt；个人 Agent 需要比简单 Read/Write 更细的风险模型。
- 影响：
  - Execution Policy Layer 承担审批。
  - 高风险 Action 引入 human intervention。
- 复审条件：授权模型被滥用或用户无法理解。

## D-029 Agent UI 由 Runtime Event 驱动

- 状态：部分实现
- 决策：工具不自己造 UI。一次执行产生统一 `FamiliarRuntimeEventPayload`，UI 只渲染事件状态、文本、工具、审批、响应和 Run 终态。
- 依据：统一 Task Timeline、Debug 与 History，并为未来 Background resume 与 Trace 提供顺序基础。
- 影响：
  - 时间线即执行轨迹。
  - 当前只能查看摘要轨迹；严格重放需要 snapshot 与 ResumeCursor。
- 复审条件：出现必须由工具自建 UI 的交互。

## D-030 Run/Step 成为正式数据模型

- 状态：部分实现；影响中 ResumeCursor 尚未持久化的历史限制被 D-037 记录的 V6 数据契约替代，字节级恢复与严格重放仍未实现
- 决策：不只保存 Chat Message。当前 Conversation → Runs → 摘要 Steps（model / tool / approval / result）。
- 依据：复杂任务需要真正的执行状态。
- 影响：
  - Run 与 Step 终态持久化。
  - 为未来恢复、Trace 与重放提供部分基础；当前未保存完整 snapshot 与 ResumeCursor。
- 复审条件：持久化成本与收益失衡。

## D-031 Memory 三层，不做 RAG 大工程

- 状态：目标设计，未实现
- 决策：Memory 使用 global / project / conversation 作用域。第一版为结构化条目和 memory.search / write / delete，自动写入默认关闭。
- 依据：先保存明确事实，等真实数据量出现后再决定是否 embeddings。
- 影响：
  - 不做向量数据库。
  - 不自动向量化全部聊天。
- 复审条件：真实数据量出现且检索质量不足。

## D-032 Skills 不含 Python/Shell/Executable

- 状态：核心约束已实现；当前调用与创建方式见 D-047
- 决策：Familiar Skill 是 Instruction Package + Tool Scope：id、description、instructions、allowedTools、examples。
- 依据：不引入任意代码执行面。
- 影响：
  - Skill 不包含脚本执行能力。
  - 后续再扩展。
- 复审条件：真实需求要求执行脚本。

## D-033 Background 按可恢复 AgentRun 设计

- 状态：目标设计，未实现
- 决策：Agent Run 是 resumable AgentRun，不是 daemon/cron/always alive。iOS 26+ 可条件使用 `BGContinuedProcessingTask` 承接用户启动的长任务；iOS 18–25 只提供系统择机执行、合适的 background URLSession 或提醒用户继续。
- 依据：iOS 不提供可靠 cron，所有系统版本都需要可中断数据契约与明确执行保证等级。
- 影响：
  - 先补齐 snapshot、ResumeCursor 和持久化幂等状态，再接后台承接能力。
  - 不做常驻 Agent。
- 复审条件：产品要求自主后台任务。

## D-034 第一阶段用最强模型建立基准

- 状态：生效
- 决策：第一阶段用能拿到的最强模型建立 Agent benchmark，不提前做模型拆分优化。
- 依据：先建立性能基线，再通过 eval 逐步替换成更小、更便宜的模型。
- 影响：
  - ModelProvider 抽象统一（OpenAI / Anthropic / OpenAICompatible / 可选 Local）。
  - 之后才考虑简单提取用小模型、复杂 Planning 用强模型、本地分类用 Core ML。
- 复审条件：benchmark 建立且成本需要优化。

## D-035 图片预处理是 Tool，不是强制 pipeline

- 状态：被 D-042 替代
- 决策：图片进入 Agent 后，由 Agent 判断任务决定走 Vision OCR、Vision Barcode 还是 Multimodal LLM，默认不 OCR。
- 依据：图片可能是照片、截图、海报、二维码、表格、人物、风景，提前 OCR 会丢语义。
- 影响：
  - 不把每张图片都 OCR。
  - Core ML 只在明确任务（Embedding、分类、目标检测）时使用。
- 复审条件：出现必须统一预处理的场景。

## D-036 Project 是第一层工作单元

- 状态：核心决策生效（Project/Resource/Artifact/ContextSnapshot 主链路已实现）；影响中的旧侧栏布局及 Binding/Skills 路径被 D-047 替代
- 决策：Familiar 的产品定位是原生、安全、可检查的个人 AI 工作台。Project 是长期、有边界、可恢复的工作上下文；Conversation 可以属于 Project，也可以作为普通聊天独立存在。
- 依据：聊天、资料、项目指令、能力和执行记录需要稳定共同作用域，附件注入无法支撑长期 Workspace。
- 影响：
  - 先建立 Project、Resource、Artifact、ProjectInstruction、Binding 与 ContextSnapshot，再开放 Project UI。
  - 侧栏按新聊天、项目、最近对话、设置组织；运行与计划只在能力真实可用后出现。
  - Skills、MCP、Memory 和 Schedule 必须服务 Project 主链路，不作为孤立菜单扩张。
- 复审条件：真实使用证明长期工作不需要项目边界。

## D-037 当前不具备严格恢复与重放

- 状态：恢复数据契约已建（V6）；依据中“未持久化恢复游标”的表述已被本决策记录的 RunResumeCursor/ToolInvocation 实现替代，运行时重放与字节级恢复仍未实现
- 决策：现有 Run/Step 只表示摘要执行轨迹。只有保存 ContextSnapshot、CapabilitySnapshot、AuthorizationSnapshot、稳定输入输出引用、持久化幂等状态和 ResumeCursor 后，才能声明恢复或重放。V6 已持久化 RunResumeCursor 与 ToolInvocation 幂等记录（数据契约），但运行时尚未接通恢复执行。
- 依据：当前持久化不包含完整模型请求、工具参数/结果、授权证据和恢复游标。
- 影响：后台 API 接入不能先于恢复数据契约；产品文案不得把终态查看描述为恢复或重放。
- 复审条件：上述数据契约完成并通过中断恢复测试。

## D-038 冻结入口扩张，优先能力内核

- 状态：部分生效；影响中的 Skills 隐藏/Labs 限制被 D-047 的设置页与 Composer 显式一次性调用替代，Memory、MCP 与其他未接线能力的限制继续生效
- 决策：暂停新增 Provider、Widget、系统入口和近似可用的预览页，优先 benchmark/CI、迁移、Project/Context/Workspace 和可恢复 Run。
- 依据：当前系统入口和展示面扩张快于能力内核。
- 影响：Memory、Skills、MCP 维持隐藏或明确 Labs 状态；新功能以端到端任务成功率验收。
- 复审条件：Project 主链路与自动 benchmark 稳定通过。

## D-040 当前产品为个人非商业实验

- 状态：生效
- 决策：Familiar 当前只作为所有者个人使用的非商业实验产品，不进入 App Store 或其他公开市场。
- 依据：当前目标是验证原生 Agent 执行、授权、视觉 fallback 和长期工作空间，不承担公开分发、商业许可和多用户支持范围。
- 影响：FastVLM 研究权重可在其非商业研究许可证范围内用于实验；文档仍保留安全、隐私和可迁移设计标准。公开分发、商业使用或他人使用前必须重新审查模型、依赖、隐私和发布要求。
- 复审条件：计划公开分发、收费、提供给第三方使用或引入 Familiar 托管服务。

## D-041 写操作采用可选择期限的精确授权

- 状态：已实现；真机授权交互尚未验收
- 决策：首次写操作以结构化动作卡请求授权，提供“仅这次 / 本次会话 / 始终允许”，默认“本次会话”。grant 按 Project、工具、目标和规范化参数边界隔离；普通聊天使用独立作用域。有效范围内免重复询问，但每次执行仍展示动作卡并写入审计记录。
- 依据：减少高频日历和提醒写入的重复打断，同时保持用户产生授权、模型不能自授权和每次动作可检查。
- 影响：设置增加授权策略和长期授权管理；修改、删除、目标变化、参数越界、过期或撤销后的操作重新询问；破坏性和财务敏感操作始终强确认。grant 创建、匹配、消费和撤销必须进入真实 Runtime。
- 复审条件：误写率、授权理解度或作用域复杂度无法达到安全要求。

## D-042 纯文本模型使用设备端视觉 fallback

- 状态：已实现；真实图片与真机性能尚未验收
- 决策：支持图片的当前模型直接接收图片；DeepSeek 等纯文本模型由 Familiar 先生成设备端视觉证据。默认使用 Apple Vision 的 OCR、条码和基础分类；高级任务在安装 FastVLM 后自动路由。未经用户选择，不自动把图片发送到另一个 Provider。
- 依据：当前主要测试模型为 DeepSeek，用户仍需要基础图片识读；本地处理无需第二个 API Key，也不增加网络数据目的地。
- 影响：视觉结果作为带 provenance 的不可信只读证据交给主模型；基础结果不足时明确能力边界并建议切换已配置的多模态 Provider。Provider adapter 不承担 fallback。
- 复审条件：Apple Vision 覆盖不足、FastVLM 设备性能不可接受，或出现可合法分发且更可靠的本地视觉模型。

## D-043 FastVLM 作为可选高级本地视觉包

- 状态：已实现；真机下载、编译、推理与资源表现尚未验收
- 决策：个人非商业实验第一版只提供固定版本 `FastVLM-0.5B`。用户在设置中主动下载；安装检查芯片、至少约 3.5 GB 可用空间和安装后短基准。模型失败或 60 秒超时自动退回 Apple Vision。
- 依据：FastVLM 有 Apple 官方 iOS 18.2+ Demo 和移动端推理路径；0.5B 官方预转换下载约 1.23 GB。官方未公布统一设备内存门槛或中文质量，因此必须以真机基准为准。
- 影响：固定下载 URL、大小和 SHA-256，不自动跟随上游；支持断点续传、失败重试和删除；许可证与归属在设置中可见。删除模型不删除历史视觉证据。该权重不得在未重新取得许可的商业或公开分发场景使用。
- 复审条件：用途变为商业/公开分发、模型许可证变化、设备基准失败或更合适的可替换模型成熟。

## D-044 执行界面只为写动作使用卡片

- 状态：已实现；真机视觉与无障碍尚未验收
- 决策：思考、查阅、Web/Resource 读取、本地识图和整理回答使用无卡片背景的单行状态，运行结束后折叠。只有改变系统或项目数据的写操作使用动作卡，同一卡片贯穿提案、授权、执行、成功、失败和已撤销。
- 依据：信息性事件不应占据与真实系统改变相同的视觉权重；动作卡应稳定表达发生了什么、依据什么授权、结果如何以及是否可撤销。
- 影响：同一 Assistant 回合两张以上动作卡横向逐卡吸附，近全宽并露出下一张 16–24 pt；边缘只渐隐被裁切部分；页码变化触发轻触觉并尊重 Reduce Motion。每张卡独立失败、重试和撤销。
- 复审条件：真机可用性、VoiceOver、Dynamic Type 或多动作理解测试显示该分组方式不可用。

## D-045 跨重启撤销是写动作的目标保证

- 状态：已实现；真机跨重启边界尚未验收
- 决策：日历和提醒写入的撤销依据持久化，App 重启后仍可撤销。撤销后原动作卡保留并进入“已撤销”终态；撤销失败显示真实原因。
- 依据：作为行动助手，Familiar 不能把安全回退限制在当前进程生命周期。
- 影响：需要持久化系统对象标识、原动作、撤销能力、状态和有效边界；多动作分别撤销，不声明跨 EventKit 对象的原子事务。
- 复审条件：系统对象外部修改使可靠撤销不可实现，或持久化敏感度超过收益。

## D-046 Chat 是主 Surface，Project 是长期 Context Workspace

- 状态：部分被 D-047 替代；统一 Chat Surface 与 Project 长期 Context 边界继续生效，Project Skills 归属及顶栏/工作区导航以 D-047 为准
- 决策：普通 Chat 与 Project Conversation 共用同一个 Chat Surface、Composer、Runtime、授权和执行 Surface。Project 负责指令、资料、对话、Skills、Artifacts、Runs 与后续 Memory 的长期边界，但不成为执行 Dashboard。Project Home 只突出 Continue / New Chat；Resources 与 Artifacts 为主要内容，Conversations / Skills / Runs 为次级 Context 导航。Project Conversation 顶栏使用一个 Project 名称入口表达归属。
- 依据：用户完成任务应始终停留在 Chat；Project 的价值来自持续上下文，而不是同时展示全部已实现能力。独立 Ask 输入框、多个同权 Section 和重复设置入口增加了路径竞争，却没有增加执行能力。
- 影响：删除 Project Home 独立 Ask 路径；Chat 顶栏不重复设置按钮；核心 Surface 使用统一 spacing、Dynamic Type typography、radius、icon visual size 与 hit-target tokens。Glass 保持在导航、Composer 和临时 Overlay。
- 复审条件：真机可用性测试显示 Project 归属仍不清晰，或 Project Home 无法支持真实的长期工作回访。

## D-047 开发存储、聊天工作区与显式 Skills 收敛

- 日期：2026-08-21
- 状态：生效；替代 D-019、D-039 的当前存储与迁移政策、D-036 的旧侧栏与 Binding/Skills 路径、D-038 的 Skills 隐藏/Labs 限制，以及 D-046 的 Project Skills 归属与顶栏/工作区路径
- 决策：
  - 当前 SwiftData 使用单一 27 实体 `FamiliarModelSchema`，生产和测试容器均不配置 migration plan；开发持久化文件固定为 `FamiliarDevelopment.store`。开发阶段不迁移旧测试数据，schema 不兼容时允许用户确认后破坏性重建；公开发布前必须另行冻结版本化 schema 并建立迁移路径。
  - 删除 Project `SkillBinding` 实体、项目 Skill 开关和自动注入。instruction-only Skill 全局安装，由用户在普通聊天或项目聊天的 Composer 中显式选择，最多选择一个且只作用于下一次 Run；Run 启动时冻结 ID、版本、内容 hash 和 allowedTools，Skill 只能收窄工具范围，不能授权。
  - Chat 顶栏固定提供设置、工作区、模型和新对话。工作区菜单在普通聊天与活跃项目之间切换，恢复该作用域最近会话；没有历史时保持未持久化空白会话，首次发送才创建。抽屉只承担搜索、置顶、可折叠项目及普通最近会话；项目和普通最近会话按 20 条逐批展开。项目与会话共用持久化置顶记录，目标删除时同步清理置顶。
  - Skills 设置页只通过右上角加号打开带默认 instructions 模板的创建表单，新建 Skill 默认没有工具访问；当前不显示导入行。首次进入 Chat 时通过 UserDefaults gate 一次性加入一个可删除的 Clear Writing 示例，单独重建 SwiftData store 不会再次加入。
  - Project 名称在去除首尾空白并截断到 80 字符后全局唯一，创建和编辑均按不区分大小写比较，归档项目也参与冲突检查。
- 依据：当前产品仍处于个人开发实验阶段，保留未发布迁移链和 Project Skill 自动绑定增加了数据与交互复杂度；显式一次性调用能让每次 Run 的上下文和工具范围可见、可检查。统一顶栏、工作区恢复、抽屉分区和置顶可减少普通聊天与项目聊天之间的重复入口。
- 影响：
  - 首次成功创建 `FamiliarDevelopment.store` 后清理旧开发 store 及无法再对应元数据的附件、项目资源和 Artifact 目录；恢复重建清理当前 store 及这三类本地内容，但保留 Keychain。
  - 单个 Artifact 删除同时删除元数据和文件；永久删除 Project 时暂存 Resource 与 Artifact 目录，数据库提交成功后清理，失败则恢复目录。
  - 旧 Project Skill binding 不保留兼容读取或迁移。未显式选择 Skill 的 Run 不注入 Skill；发送提交后清空选择，后续 Run 不继承。
  - 置顶会话在抽屉置顶区作为顶层条目显示，不在项目或普通最近列表重复出现；置顶项目仍可在置顶区展开其未置顶会话。
- 复审条件：准备公开发布、需要保留已发布数据、真实使用证明一次性 Skill 不足，或工作区恢复与抽屉分区在真机可用性测试中产生阻塞。

## 决策维护

新增决策时使用以下字段：

```text
ID
标题
状态
决策
依据
影响
复审条件
```

影响隐私、持久化、写操作和网络目的地的决策需要在代码合并前更新本文件。

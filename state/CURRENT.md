# Current State

Last verified: 2026-09-02

## Current Focus

Product Convergence v1 已把现有能力收敛为统一产品模型：Chat 是主要交互与执行 Surface，Project 是长期 Context Workspace，单 Agent Runtime 是执行内核，原生 iPhone Capabilities 是执行能力。Chat 顶栏直接提供设置、普通/项目工作区切换、模型与新对话；工作区恢复该作用域最近更新的会话，没有历史时保持未持久化的空白会话。抽屉按置顶、可折叠项目和普通最近会话分区。Skill 可继续从 Composer 显式选择一次，也可绑定到 Project 后只常驻 metadata、由 Agent 在 planning 阶段按需加载一个；两条路径都不会自动全量注入。

当前进入 Complex Task Runtime v1 真机收口。单一 iSH/Alpine 底层新增 Project 持久 Environment 与普通 Chat 临时 Environment，Agent 可通过声明式环境方案准备依赖；Project 可绑定按需加载的 instruction-only Skill 和 Capability。首个 Golden Task 固定为真实网页检索后生成、验证、预览并分享 DOCX。生产 UI 继续固定使用 DeepSeek BYOK；当前剩余门槛是真实 `hwf` 真机上的 iSH 冷启动、PyPI 安装、DeepSeek Tool Call、AnyDoc 验证、Quick Look 与系统分享。

## Recently Completed

- **聊天有序块与 Run 审计收敛**：Assistant Turn 改为按 Runtime sequence 交错显示每轮 Markdown 与稳定工具执行块，查询结果默认摘要折叠并原地展开，Activity 不再承载重复明细。确认卡改为默认“仅这次”的单页系统蓝布局，明确展示风险、后果和撤销能力；修复 once 授权额外签发规则。Project Run 详情新增调用状态、参数 hash、结构化失败、授权决定、结果 hash 与冻结上下文审计。每轮正文在工具边界持久化，失败 Run 也可回放已产生内容。
- **2026-08-31 Complex Task Runtime v1 代码纵切**：iSH 安装改用 rootfs 版本、bundle hash、固定 iSH commit 与原子 marker 校验，并显式记录 installing/booting/ready/running/failed 生命周期；Project 持久挂载 `/workspace/env`，普通 Chat Environment 随 Run 删除。新增声明式 `environment_status`/`environment_prepare`、Project Skill/Capability binding、按需 `skill_list`/`skill_read`、动态 Shell preflight、Plan/Execute/Validate/Repair/Deliver 阶段和最多两次缺失交付修复。Artifact 扩展为 Markdown/Text/DOCX/PDF/XLSX/HTML，`artifact_publish` 只登记通过签名、AnyDoc/SwiftSoup、必需正文和 hash 校验的真实 Outputs 文件；Chat/Project 复用 Quick Look/ShareLink，HTML 使用 non-persistent WebKit + CSP。当前唯一 Release Schema 为 36 实体。独立 DerivedData 的 arm64 generic Simulator `build-for-testing` 已成功；未启动 Simulator、未执行测试、未连接真机、未调用真实 DeepSeek 或真实 iSH guest。
- **2026-08-30 DeepSeek + Native Tools + iSH 成品纵切**：EventKit 更新/完成/删除与跨重启 Undo、Photos add-only 输出、Files 导出、最小 Contacts 字段、当前单一 33 实体 Release Schema、task-scoped Shell 输入投影、Workspace 删除事务、ARM64 iSH/Alpine headless runtime、socket/资源 policy、Shell Chat Surface 和 Runtime 设置页已接入。固定 iSH commit、Alpine 3.24.0 rootfs、device/simulator XCFramework、GPLv3 源码/许可与构建脚本通过供应链校验；全新 DerivedData 的 Debug arm64 generic Simulator `build-for-testing` 与 Release generic iOS arm64 无签名 build 成功，网站构建、本地化 plist/key parity 和 `git diff --check` 通过。未启动 Simulator、未执行测试、未使用真实 DeepSeek Key；真实 iSH guest、系统权限、DeepSeek 效果、签名 Archive 与 App Review 仍由所有者验收。
- **集中 UI 反馈收口**：移除首启 Onboarding 与设置中的重看入口，首次启动直接进入 Chat；发送前在任何图片导入或 Apple Vision 处理之前检查 Keychain，缺 Key 时保留草稿并提示先填写 API Key。Composer 图片改为可点击缩略图，原生全屏预览提供关闭与删除；已发送图片从文字气泡中独立右对齐，所有 Quick Look 预览均有明确完成按钮。Thinking 只保留系统 Disclosure 箭头，Activity 内容取消额外左缩进；抽屉开合提交时触发原生 selection feedback。Skills 列表行可进入查看/编辑，保存时保持 stable ID、version、工具范围和 examples，历史 Run snapshot 不变。
- **35 Tool Release hardening**：`FamiliarActionProposal` 只保存纯预览和批准后 `commit`；EventKit 已补齐日历/提醒的查询、创建、修改、完成、删除及跨重启 Undo，删除和 Shell 只允许一次性授权。Contacts 按请求选择最小字段；Workspace 图片输出可 add-only 保存到 Photos，任意输出可进入 Quick Look、系统分享和 Files 导出。`prepare_share` 使用 schema v3 `shareDraft` top-level Surface 与真实 ShareLink。
- **DeepSeek 1.0 生产路径**：模型协议已统一为无 API Key 的 `generate/stream`，当前 catalog 只启用 DeepSeek Flash/Pro；HTTP adapter 保持通用 OpenAI-compatible 实现，Agent Runtime 不包含 DeepSeek 分支。设置固定 `.cloud`，不暴露本地路由或手填模型；App 不再提供首启引导，缺少 API Key 时从发送动作直接进入设置。模型列表只接受正式 curated ID 与实时 `/models` 的交集；替换 Key 在写入 Keychain 前验证所选模型。Provider 使用 ephemeral URLSession，错误文本会脱敏，Malformed SSE 与无 finish reason 的中断流不会伪造成功终态。
- **Workspace、Native Tools 与受控 Shell**：Project/Conversation Workspace 已具备路径穿越与 symlink 防护、配额、checkpoint/diff/restore，以及每个 Run 的只读 Resource/Attachment 输入投影。固定 commit 的 ARM64 iSH fork、Alpine 3.24.0 aarch64 fakefs、iPhoneOS/Simulator XCFramework 和 headless bridge 已纳入生产 target；bridge 准备成功时注册 `shell_execute`。Shell 只挂载当前 Run 的只读 Files、可写 Outputs 与临时 Work，默认禁网，精确审批，并执行 timeout、进程、输出、文件、Workspace 与网络资源限制。
- **原生 FamiliarMac target**：新增 SwiftUI macOS App、Codex 式 Sidebar/Chat/Inspector shell、Commands、Settings、App Sandbox/Hardened Runtime/Virtualization entitlement；固定直接依赖 `apple/containerization` 0.33.4，不调用外部 `container` CLI。Container session 支持无网络接口、Workspace-only mounts、持久 writable layer 输入、同 Workspace 串行、全局串行、进程树取消与 10 分钟 idle stop。当前 Mac shell 尚未接入共享 SwiftData/Agent Runtime，容器资产管理与实际 VM 启动未验收。
- **结构化内容 Surface 完整形态**：Surface policy 只把 scalar、Web search/fetch document 留在 Activity trace，Context Matches、RecordCollection、Diff 与 typed Code 作为正文后的 top-level accessory。Context 使用最多两条紧凑 chunk 并展示来源、字符数和真实资源版本；Records 使用纵向主次字段行、存在状态/类型字段时提供筛选 chips，超过三条进入可搜索全屏；Diff 正文只给摘要并在全屏按 before/after 纵向展示；typed Code 使用原生等宽文本、语言/文件名/复制与长内容全屏。Insight metrics 已改用 Swift Charts，无 metrics 不建图；Task Rows 显式区分四种状态且只展示真实 progress。长 Mermaid 可从本地 Markdown WebView 进入复用 bundled renderer/CSP 的全屏预览。上述详情路径均有中英本地化和无固定尺寸的 NavigationStack/List/ScrollView 布局。
- **Selection Actions、来源交互与视觉夹具**：本地 Markdown renderer 仅在终态启用文本选择，通过 `selectionChanged` bridge 向 SwiftUI 回传最多 4000 字符纯文本，取消或流式状态会清空选区。终态 Assistant 正文下方提供解释、改进、缩短、语气、语法五个本地化动作，只将带引用片段的自然语言指令填入 Composer 并聚焦，不自动发送。Sources 改为默认折叠的紧凑来源簇，展开行显示标题、域名及已读取/仅发现语义；Search trace 只显示 query、结果数和读取语义，不逐结果展示卡片。`-familiar.visual-fixture 1` 与 Light/Dark SwiftUI Preview 共用生产组件覆盖 loading/reasoning/search/approval/clarification/task/recommendation/insight/receipt/failure/sources。
- **Beautiful UI typed 能力闭环**：`FamiliarToolPresentationPayload` 新增 taskList/recommendation/insight/code 完整 Codable 契约；新增只读 `task_plan`、`present_recommendation`、`present_insight` 与 `ask_user` manifest。Task plan 以 `runID + planID` 原位替换并只持久化 latest revision，Recommendation/alternatives 只填充 Composer，Insight 仅对模型明确给出的具名 metrics 绘制紧凑 bars。独立 `FamiliarClarificationCoordinator` 通过 typed requested/resolved Runtime 事件暂停并恢复同一 Run，不复用 Approval/Authorization；取消 Run 会取消等待，重启恢复把未完成问题标记为不可重新激活的 interrupted。四类 Surface 使用现有 AI tokens，实时与历史走同一投影。
- **Runtime typed 事件与 hard deadline 重构**：旧粗粒度 state/tool/run 终态事件已删除，Runtime 只发 run phase、assistant turn、正文/reasoning、activity、tool invocation/result、approval、notice、response 与唯一 `runFinished(FamiliarRunOutcome)`。`ContinuousClock` 单一 deadline 覆盖 Provider stream、工具执行、审批等待和 retry sleep；首字节前自动重试可审计，read 失败可内部重试一次，write 不自动重放；声明 parallel 的连续独立 read 最多并发 2 个且按原 call 顺序回填。
- **Provider reasoning summary**：DeepSeek Chat Completions 只读取明确的 `reasoning_content`；Controller 只在内存流式展示，完成后一次写入 `reasoningSummary` ResponseBlock，不从正文猜测或逐 delta 持久化。
- **唯一 Assistant Turn 持久化投影**：SwiftData 只以 Activity、ToolResult、Approval、ResponseBlock 与 Context 记录 Run 展示事实；AgentStep/旧 tool snapshot/checkpoint 时间线已删除。Runtime 在 tool/approval/result 边界增量 upsert，最终助手消息一次写入 markdown block，失败/取消且无助手消息的 Run 写入可重放 runtime notice recovery，text delta 仍只保留在内存。
- **结构化 Tool Result 与 typed Approval**：所有产生结果的内置工具统一返回 `FamiliarToolResultEnvelope`，canonical model JSON 与带稳定 `schemaVersion/name` 的 typed presentation payload 同封装；Runtime/Surface 以 envelope 为瞬态 UI 主数据，现有 detail 只从 payload summary 派生。审批字段改为有序 typed `FamiliarApprovalField`，确认请求携带 manifest effect/risk、target、consequence 与 undo policy。工具失败返回 `code/retryable/message`，Web failure 保留具体稳定 code；模型工具参数不包含 trusted UI command。
- **独立 Web Search**：`web_search` 保持独立于模型 Provider。iOS 1.0 设置只显示 DuckDuckGo，无需 Key；Brave/Tavily/Exa adapter 及独立 Search Keychain contract 保留在源码和确定性测试中，但真实 Key 验收前不进入 Release UI。所有 adapter 只访问固定 HTTPS host，使用无 Cookie/缓存、禁止重定向、带超时和响应大小限制的 ephemeral URLSession；失败不静默 fallback。`web_fetch` 继续使用受限抓取链路。
- **Chat 工作区与抽屉重构**：顶栏抽屉按钮替换为设置，新增圆形文件夹工作区菜单；切换作用域恢复最近会话并延迟到首次发送才创建新会话。抽屉移除新对话和设置入口，按置顶、项目、最近分区，项目历史可折叠，项目与普通最近会话按 20 条逐批展开。`FamiliarPinnedItemRecord` 统一持久化项目/会话置顶。

- **显式与 Project 按需 Skill**：全局持久化仍严格 instruction-only。Composer 可显式选择一个 Skill 并只作用于下一次 Run；Project Context 可绑定多个候选 Skill，但只向 planning prompt 暴露 metadata，Agent 必须经 `skill_read` 加载至多一个，随后以 `FamiliarRunSkillSnapshotRecord` 冻结 ID/版本/hash/allowedTools 并收窄后续工具。Skill 不自动全量注入，也不能扩大 Project Capability。
- **导航与草稿安全**：抽屉提供项目/对话统一搜索、置顶项目、可折叠项目会话与普通最近会话；设置、工作区和新对话位于顶栏。切换对话或新建聊天时不会静默丢弃草稿，删除对话具有明确确认。
- **执行体验与授权**：Runtime 事件携带 `effect` 与显式 `assistantTurnID`；读取工具只进入可展开 typed activity trace，日期时间与 app info 等 scalar 不形成顶级 Surface。写操作使用 typed approval intervention、紧凑 tool summary、mutation/artifact receipt 与 Undo。`FamiliarAuthorizationRuntime` 已接入 Agent Loop，授权按 Project、工具版本、目标和精确参数 hash 匹配，支持仅这次/本会话/长期授权，并在设置中可撤销。
- **跨重启 Undo 与视觉证据**：`FamiliarAuthorizationRuleRecord`、`FamiliarEventKitUndoRecord`、`FamiliarVisualEvidenceRecord` 已接入；EventKit create 写入 durable undo record，重启后可重建撤销入口；Apple Vision 对纯文本模型图片生成带 provenance 的不可信只读证据，持久化到实际用户消息与 ContextSnapshot。
- **FastVLM 不进入 iOS 1.0**：`Vendor/ml-fastvlm` 研究源码仍保留，但 `FastVLMRuntime`/MLX 已从 iOS target 与 Package graph 移除，模型管理器不参与 App 编译。DeepSeek 实验视觉 ID 也已从生产 catalog 移除；图片只走 Apple Vision 基础证据，再把有限、不可信的只读文本交给当前文本模型。
- **Assistant Turn Surface（前端 P0）**：`FamiliarSurfaceDescriptor`/`FamiliarSurfaceStore` 将实时事件与历史 `FamiliarAgentRunSnapshot` 归一投影为 runStatus/activityTrace/toolSummary/approval/search/context/records/mutationReceipt/artifact/failure。时间线采用无背景正文、Loading/Thinking rail、inline source list、typed approval、write receipt 与 failure recovery；无横向 pager、卡中卡或旧 snapshot 分支。UI 只使用 `FamiliarAISurfaceColor/Radius/Metric` 与 `FamiliarMotion` tokens；真机视觉/VoiceOver/Dynamic Type 验收仍待所有者完成。

- **WP0 可验证内核**：8 场景 fake-provider Benchmark（`FamiliarBenchmarkTests`）+ `Scripts/run-agent-benchmarks.sh` + arm64 Simulator iOS CI（`.github/workflows/ios.yml`）。
- **破坏性单一 SwiftData Schema**：测试阶段不保留任何 Release migration chain。`FamiliarReleaseSchema` 直接包含当前 36 个实体，ModelContainer 不配置 `SchemaMigrationPlan`；旧测试 store 不受支持，需要时直接重建。Debug 使用 `FamiliarDevelopment.store`，Release 使用 `Familiar.store`。
- **Project 最小纵切**：Project/ProjectInstruction 已接入，对话可选归属项目，支持项目指令注入、抽屉/项目列表/编辑/归档/删除。项目名称去除首尾空白后全局唯一，创建与编辑均不区分大小写，归档项目也参与冲突检查。
- **Resource + ContextSnapshot**：Resource/ResourceVersion/ContextSnapshotRecord/ContextResourceReference 已接入；项目资源独立受保护目录；`FamiliarProjectContextAssembler` 生成确定性不可变上下文，超出输入预算明确拒绝。
- **Artifact + Web 项目闭环**：Artifact 与受控 `artifact_write` 工具已接入；`web_fetch` 正文可经 `importFetchedWebText` 落为 Project Resource（不二次 refetch，记录 URL/时间/hash/truncated/source lineage）。
- **Capability 与授权契约**：Manifest v2（`FamiliarCapabilityContract.swift`）、确定性 `FamiliarCapabilitySnapshot`、`FamiliarAuthorizationGrant`（规范化 arguments hash + source/scope/expiry 校验）已接入；旧 `FamiliarOneShotAuthorization` 来源式写授权停用。
- **可恢复 Run 数据契约**：`RunResumeCursorRecord`/`ToolInvocationRecord` 已接入；工具调用以 `run:toolCallID` 幂等键持久化状态，已 committed 拒绝重复提交。Controller 已在工具请求、审批、完成事件边界接入 invocation（requested→approved→committed/cancelled/failed）与 cursor 记录；字节级中断续跑仍未实现。
- **运行时错误分类与重试**：`FamiliarRuntimeFailure.kind(for:)` 统一分类（auth/限流/5xx/网络/上下文/参数/结果/取消）；Agent Loop 在首个字节前对 transient/限流做有界重试。
- **运行时预算**：工具调用总数与单次 Run 总时长预算，超限以明确终态失败。
- **孤儿 Run 恢复**：`FamiliarRunRecoveryService.recoverInterruptedRuns` 在启动时把遗留 running Run 终结为 failed，并取消在途 invocation。
- **Project 闭环补齐**：项目详情可浏览/预览/删除 Artifact，单项删除同步清理元数据和文件；永久删除项目时 Resource 与 Artifact 目录先暂存、数据库提交成功后再清理，失败时恢复；运行启动时持久化 CapabilitySnapshot 与 RunResumeCursor。
- **Runtime 与交付工具**：`resource_list/read/search`、`skill_list/read`、`artifact_publish` 已注册；iSH bridge 准备成功后再注册 `environment_status/prepare` 与 `shell_execute`，完整注册表最多 40 个工具。读取与 Shell 输入使用运行开始时冻结的 Resource/Attachment ContextSnapshot；Project Skill 在 planning 阶段按需加载并冻结到 Run。
- **Share 目标选择**：共享收件箱内容进入 App 后可选择已有项目、新建项目或普通聊天草稿，取消时清理准备中的附件。
- **系统入口**：Share Extension、类型化 Deep Link、App Intents/Shortcuts、Run 终态本地通知、Spotlight 会话索引、Widget/Control。
- **本地渲染**：非持久化 WKWebView + 内置 Markdown/高亮/Mermaid/KaTeX/DOMPurify，CSP 禁远程图片自动加载。

## Verification Evidence

- 2026-09-02：聊天有序块与 Run 审计收敛改动后，独立 DerivedData 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功且无警告；`FamiliarRuntimeTests`、`FamiliarSurfaceTests`、`FamiliarAssistantTurnPersistenceTests`、`FamiliarUIFeedbackTests`、`FamiliarPlanCompletionTests` 与 `FamiliarPersistenceReleaseTests` 共 45 项全部通过。中英 strings plist `plutil` lint 与 `git diff --check` 通过。按项目约束未启动 Simulator 做视觉验收；确认卡、展开动效与审计详情仍需真机人工验收。

- 2026-08-29：集中 UI 反馈改动后，独立 DerivedData 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功，App、Share Extension、Widget、`FamiliarTests` 与 `FamiliarUITests` 全部完成编译；新增 direct launch/API Key guard、图片预览/删除、Activity/Thinking、drawer haptic 与 Skill editor 静态契约测试。中英 strings plist/parity 与 `git diff --check` 通过。按项目约束未启动 Simulator；图片布局、Quick Look 关闭、抽屉触觉和 Skill 编辑仍需所有者真机验收。
- 2026-08-28：最终发布验证使用独立 DerivedData 完成 Debug arm64 generic Simulator `build-for-testing`；24 个 Swift Testing suite 按 `Scripts/run-release-test-suites.sh` 的清单逐套串行执行并全部通过，随后 UI smoke 2/2 通过。修复了测试夹具未持有 SwiftData `ModelContainer`、过时的 `.always` 授权断言与 UI fixture 子元素暴露问题。Release generic iOS arm64 build 和无签名 Archive 成功；App/Share/Widget 版本均为 1.0 (1)，三个 bundle manifest、许可资源和 arm64 架构检查通过，包内扫描未发现 FastVLM/MLX、实验 DeepSeek 模型或 DEBUG fixture。签名 Archive、Organizer Privacy Report、真实 DeepSeek Key 与真机矩阵仍由所有者完成。
- 2026-08-28：App、Share Extension、Widget/Control 分别加入 PrivacyInfo.xcprivacy；FastVLM/MLX 已确认不在 iOS target；AnyDoc Rust notices 由锁定 Cargo graph 与 crate 自带 license 文件生成，App About 同时展示主 notices 与 Rust 清单。网站与 App 内隐私说明更新为 DeepSeek、DuckDuckGo、Apple Vision、28 Tool、联系人、位置、剪贴板和 Workspace 的真实路径；Release fixture 已限制在 DEBUG。Debug arm64 Simulator `build-for-testing` 成功，产物中的三个 executable bundle 均包含各自 manifest，`FamiliarReleaseComplianceTests` 3/3 通过；Release Archive 留在最终发布验证任务执行。
- 2026-08-28：SwiftData Release V1、单 schema migration plan、Debug/Release store profile 与无自动清理启动路径接线后，Debug arm64 generic iOS Simulator `build-for-testing` 和 Release arm64 generic iOS Simulator build 成功。iOS 26.5 Simulator 单独执行 `FamiliarPersistenceReleaseTests` 4/4：31 实体/版本、文件 store 重开与关系、Release 不删除 Development store、失败打开不删除目标均通过。
- 2026-08-27：Action commit、Workspace 投影、联系人最小字段、Clipboard 边界、shareDraft 与 DuckDuckGo Release Surface 接线后，`Familiar` arm64 generic iOS Simulator `build-for-testing` 成功。iOS 26.5 Simulator 实际执行：Release tool hardening 4/4、Runtime 10/10、EventKit policy、Tool contract、Surface 与 8 场景 Benchmark suites 均通过。一次全量并发执行在 34 个用例通过后 test host 以 SIGTRAP 退出，其余 103 项被 Xcode 标为 crashed；该次不算全量通过，后续按 suite 串行补齐。未做 Simulator 视觉验收或真机验收。
- 2026-08-27：DeepSeek 1.0 catalog 收敛为 Flash/Pro，设置移除本地路由和手填模型，模型列表/Key 验证与 SSE 中断语义加固；FastVLMRuntime/MLX 从 iOS target 移除。`Familiar` Debug arm64 generic iOS Simulator build 成功，目标图从 49 个降为 App/Extensions/SwiftSoup 共 5 个；未启动 Simulator，未执行测试或真实 DeepSeek/真机验收。
- 2026-08-27：当前默认路由切为 `.cloud`；DeepSeek 继续作为唯一启用 descriptor，但网络 Provider 重命名并验证为通用 `FamiliarOpenAICompatibleModelProvider`；恢复 `deepseek-v4-flash-vision-exp` 实验图片入口；FastVLM 设置入口、DI 和 Chat 自动路由已断开。`Familiar` arm64 generic iOS Simulator `build-for-testing` 与 `FamiliarMac` macOS arm64 Debug build 成功；中英 strings plist/parity 与 `git diff --check` 通过。未启动 Simulator，未执行测试、真实 DeepSeek API、真机图片或 EventKit 验收。
- 2026-08-26：Native-First 模型/Workspace/Native Tool/Shell/Mac 纵切与 MLX 依赖升级后，`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功；原生 `FamiliarMac` scheme 的 macOS arm64 Debug build 成功并直接编译链接 Containerization 0.33.4。按项目约束未启动 Simulator；未执行测试、iSH、Core AI、真实 VM、签名/公证或真机验收。
- 2026-08-24：清理废弃的旧 Thinking rail / pixel loader、未使用 ButtonStyle、已移除 UI 的中英本地化残留与基于字符数伪估算的 token/s；视觉夹具改为直接覆盖生产 `FamiliarThinkingState`，旧 poster image gate benchmark 改为当前 Apple Vision preflight 边界，SwiftData 文档口径统一为 31 个实体。`git diff --check`、中英本地化 plist 与 key parity 检查通过；`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功，App、Share Extension、Widgets、`FamiliarTests` 与 `FamiliarUITests` 均完成编译。按项目约束未启动 Simulator，因此未执行测试或视觉验收。
- 2026-08-22：结构化内容 Surface policy、Context/Records/Diff/Code 详情、Swift Charts 与 Mermaid 本地全屏预览接线后，`git diff --check` 通过；`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功，App、扩展、`FamiliarTests`/`FamiliarUITests` 以及新增 date/app/search/document placement、Context/Records/Diff/Code projection、详情动作、Charts、Mermaid bridge/CSP 静态契约测试均完成编译。按项目约束未启动 Simulator，因此未执行测试或视觉验收。
- 2026-08-22：Selection Actions、来源 Disclosure、search semantic trace 与视觉夹具接线后，`git diff --check` 通过；`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功，App、扩展、`FamiliarTests`/`FamiliarUITests` 及新增 bridge/Selection/source 静态契约测试和 launch fixture UI 测试均完成编译。按项目约束未启动 Simulator，因此未执行测试或视觉验收。
- 2026-08-22：Beautiful UI typed Task/Recommendation/Insight/Clarification 完整接线后，`git diff --check` 通过；`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功，App、扩展、`FamiliarTests`/`FamiliarUITests` 以及 payload roundtrip、plan latest revision、recommendation 不触发授权、clarification 暂停/恢复/取消/中断恢复和实时/历史 Surface projection tests 均完成编译。按项目约束未启动 Simulator，因此未执行测试。
- 2026-08-22：Runtime typed 事件、reasoning summary、hard deadline 与并行 read 重构后，`git diff --check` 通过；`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功，App、扩展、`FamiliarTests`/`FamiliarUITests` 以及 hard deadline、retry notice、并发上限 2、原 call 顺序、reasoning summary、read 内部重试和 single runFinished deterministic tests 均完成编译。按项目约束未启动 Simulator，因此未执行测试。
- 2026-08-21：唯一 Assistant Turn 投影与 UI 破坏性清理后，`git diff --check` 通过；`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功，App、扩展、`FamiliarTests`/`FamiliarUITests` 以及日期 read 不形成顶级 Surface、历史重放、失败恢复测试均完成编译。按项目约束未启动 Simulator，因此未执行测试。
- 2026-08-21：Assistant Turn 持久化接线后，`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功；App、扩展、`FamiliarTests`/`FamiliarUITests` 以及新增 4 项 in-memory persistence tests 均完成编译。按项目约束未启动 Simulator，因此未执行测试。
- 2026-08-21：结构化 Tool Result/typed Approval 迁移后，`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功；App、扩展、`FamiliarTests`/`FamiliarUITests` 以及新增 contract tests 均完成编译。未启动 Simulator，因此未执行测试。
- 2026-08-21：独立 Search Provider 改动在 `Familiar` scheme 的 Debug arm64 generic iOS Simulator `build-for-testing` 成功；App、扩展、`FamiliarTests`/`FamiliarUITests` 产物以及 Search adapter 的 deterministic fixture tests 均完成编译。未启动 Simulator，因此未执行测试或真实 Search Provider 冒烟。
- 2026-08-21：website 隐私说明更新后 `npm run build` 成功（Vite 17 modules）。
- 2026-08-21：`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build` 成功，覆盖 App、Share Extension、Widgets 与 FastVLM/MLX 依赖。
- 2026-08-21：同一 destination 的 `build-for-testing` 成功，`FamiliarTests` 与 `FamiliarUITests` 测试产物均已编译。构建只出现 Xcode 对无 App Intents 依赖 target 跳过 metadata extraction 的警告，没有 Swift 源码诊断。

## Known Problems

- DeepSeek 尚未使用真实测试 Key 完成认证、模型列表、文本流式、取消、无效 Key、无效模型、Tool Call 与 ToolResult 回填的完整冒烟；这是当前最优先缺口。
- DeepSeek catalog 当前只包含 `deepseek-v4-flash` 与 `deepseek-v4-pro`。图片字节不发送给 DeepSeek；Apple Vision 只生成有限的本地证据文本。
- Core AI 当前只有 ModelManager、Provider adapter 和路由合同。iOS 27/Xcode 27 正式 SDK、Qwen Core AI bundle、specialization、设备适配、流式和 Tool Call 尚未实现，不阻塞当前 DeepSeek 收尾。
- iSH 源码、构建产物、rootfs 生命周期、Project/Run Environment 和 Shell Tool 已接线并完成编译；实际 ARM64 guest 冷启动、PyPI `python-docx` 安装、取消、网络边界与资源限制仍需在 `hwf` 真机验收。macOS Containerization 的 kernel/init/rootfs 资产仍未接入。
- FamiliarMac 只有可编译的 Codex 式原生 UI shell 与 Containerization adapter，尚未接入共享 SwiftData 和 Agent Runtime，不作为本轮 iOS 收尾完成项。
- Brave、Tavily、Exa Search adapter 尚未使用真实账户与 Key 冒烟，因此不在 Release UI；DuckDuckGo 仍需真实网络验收。
- 真机验收未完成：EventKit 权限、真实文档/OCR、相机、Speech、Share/Deep Link/通知/Spotlight/Intents/Widget/Control 均依赖真机。
- iOS CI 远程首次结果**尚未确认**（本地解析通过，GitHub Actions 未触发或未记录）。
- `FamiliarRunRecoveryService` 的 CapabilitySnapshot/Cursor 与 ToolInvocation 生命周期已接入；字节级中断续跑仍未实现。
- Memory 自动/显式 Runtime 工具、Remote MCP 和可靠后台承接仍未实现，按后续层次推进。
- 后台承接未实现：`BGContinuedProcessingTask` 仅适用于 iOS 26+；当前通知只报告进程内实际到达的终态。
- EventKit 写入幂等与跨重启 Undo 已实现但未真机验证；系统 save 后进程立即终止的边界仍未验证。
- FastVLMRuntime/MLX 已从 iOS target 与 Package graph 移除；`Vendor/` 研究源码不进入 App 包。
- SwiftData 真机恢复路径（磁盘不足、损坏 store、旧安装覆盖）未在真机验收。

## Next

1. 连接 `hwf`，复用设备 Keychain 中的 DeepSeek Key，先验证签名安装、iSH 冷启动、Environment prepare 与离线 Shell；不导出或记录 API Key。
2. 在 Project Chat 执行北京资料 Golden Task：真实 `web_search`/至少两次成功 `web_fetch` → `python-docx` → `artifact_publish` → AnyDoc receipt → Quick Look → Share to Files。
3. 分别验证空环境冷启动、缓存环境和强制退出后重启；任何失败必须停在真实 phase，不能产生成功 Artifact 或虚假完成回答。
4. 修复真实冒烟暴露的问题后冻结当前“唯一启用 Provider 为 DeepSeek”的 iOS 实验基线；分别记录构建、测试执行和真机结论。Search、Share、系统入口和无障碍继续按风险逐项验收，FastVLM 不进入本轮。
5. Core AI、MCP、自动 Memory 与后台执行保持在本版范围之外；不在本轮恢复本地路由 UI。iSH/Shell 只修复真机验收暴露的问题，不扩展为宿主文件系统或 Native capability bridge。

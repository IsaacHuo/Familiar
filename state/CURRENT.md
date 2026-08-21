# Current State

Last verified: 2026-08-21

## Current Focus

Product Convergence v1 已把现有能力收敛为统一产品模型：Chat 是主要交互与执行 Surface，Project 是长期 Context Workspace，单 Agent Runtime 是执行内核，原生 iPhone Capabilities 是执行能力。Chat 顶栏直接提供设置、普通/项目工作区切换、模型与新对话；工作区恢复该作用域最近更新的会话，没有历史时保持未持久化的空白会话。抽屉按置顶、可折叠项目和普通最近会话分区。Skill 从 Composer 显式选择，只作用于下一次 Run，不再由 Project binding 自动注入。

## Recently Completed

- **Chat 工作区与抽屉重构**：顶栏抽屉按钮替换为设置，新增圆形文件夹工作区菜单；切换作用域恢复最近会话并延迟到首次发送才创建新会话。抽屉移除新对话和设置入口，按置顶、项目、最近分区，项目历史可折叠，项目与普通最近会话按 20 条逐批展开。`FamiliarPinnedItemRecord` 统一持久化项目/会话置顶。

- **显式 Skill 调用**：全局持久化严格 instruction-only Skill；首次进入 Chat 时通过 UserDefaults gate 一次性加入一个可删除的 Clear Writing 示例，单独重建 SwiftData store 不会再次加入。技能页只从右上角加号打开带默认 instructions 模板的创建表单，没有导入行，新建 Skill 默认无工具访问。Composer 聚焦时提供 Slash 按钮；空白输入框点击会写入 `/` 并打开最多四行的可滚动面板，继续输入字符会按标识符、名称和说明实时筛选。最多选择一个 Skill，只注入下一次 Run，并由 `FamiliarRunSkillSnapshotRecord` 冻结 ID/版本/hash/allowedTools。Project `SkillBinding`、自动注入与项目 Skill 开关已移除。
- **导航与草稿安全**：抽屉提供项目/对话统一搜索、置顶项目、可折叠项目会话与普通最近会话；设置、工作区和新对话位于顶栏。切换对话或新建聊天时不会静默丢弃草稿，删除对话具有明确确认。
- **执行体验与授权**：Runtime 事件携带 `effect` 与 `assistantTurnID`；读取工具仅更新轻量 Agent 状态，写操作使用动作卡。同一回合的多张写卡使用水平 `viewAligned` pager、边缘渐隐、选择触觉和 Reduce Motion 降级。`FamiliarAuthorizationRuntime` 已接入 Agent Loop，授权按 Project、工具版本、目标和精确参数 hash 匹配，支持仅这次/本会话/长期授权，并在设置中可撤销。
- **跨重启 Undo 与视觉证据**：`FamiliarAuthorizationRuleRecord`、`FamiliarEventKitUndoRecord`、`FamiliarVisualEvidenceRecord` 已接入；EventKit create 写入 durable undo record，重启后可重建撤销入口；Apple Vision 对纯文本模型图片生成带 provenance 的不可信只读证据，持久化到实际用户消息与 ContextSnapshot。
- **FastVLM 0.5B**：`Vendor/ml-fastvlm` 的官方源码被封装为本地 Swift Package，锁定 MLX 0.21.2 / MLX examples 2.21.2 / Transformers 0.1.18 / ZIPFoundation 0.9.19。设置页实现 iOS 18.2+、Metal/内存/3.5 GB 存储准入、进度、暂停/恢复、SHA-256、受控解包、Core ML 编译、自动基准、删除、60 秒超时和 Apple Vision 降级。真实设备尚未验收。
- **Surface Protocol（前端 P0）**：新增 `FamiliarSurfaceDescriptor`/`FamiliarSurfaceStore` 纯 reducer，把 `FamiliarRuntimeEvent` 折叠成稳定 surface（identity `run:<runID>` / `tool:<runID>:<toolCallID>`，旧 sequence 不覆盖终态）；`FamiliarChatMessageViews` 以单一 `FamiliarToolActivityCard` 原位 morph 工具全生命周期（queued→审批→running→终态），终态内联 `FamiliarArtifactCard`（Quick Look + 分享），`FamiliarAgentStatusRow` 承载 Agent 轻状态；集中 `FamiliarMotion` tokens 与 `FamiliarHapticPolicy`；`FamiliarSurfaceTests` 当前包含 11 项单测，覆盖 identity 连续性、stale 事件、审批 resolve、run 终态、artifact 传播。测试产物已编译，真机视觉/VoiceOver/Dynamic Type 验收仍待所有者完成。

- **WP0 可验证内核**：8 场景 fake-provider Benchmark（`FamiliarBenchmarkTests`）+ `Scripts/run-agent-benchmarks.sh` + arm64 Simulator iOS CI（`.github/workflows/ios.yml`）。
- **SwiftData 开发存储**：当前 27 个实体使用单一 schema 和 `FamiliarDevelopment.store`，生产与测试容器不配置 migration plan；开发阶段不迁移旧 store。首次创建当前 store 会清理旧开发 store、附件、项目资源和 Artifact 目录；用户确认恢复重建时清理当前 store 与这三类内容，保留 Keychain。
- **Project 最小纵切**：Project/ProjectInstruction 已接入，对话可选归属项目，支持项目指令注入、抽屉/项目列表/编辑/归档/删除。项目名称去除首尾空白后全局唯一，创建与编辑均不区分大小写，归档项目也参与冲突检查。
- **Resource + ContextSnapshot**：Resource/ResourceVersion/ContextSnapshotRecord/ContextResourceReference 已接入；项目资源独立受保护目录；`FamiliarProjectContextAssembler` 生成确定性不可变上下文，超出输入预算明确拒绝。
- **Artifact + Web 项目闭环**：Artifact 与受控 `artifact_write` 工具已接入；`web_fetch` 正文可经 `importFetchedWebText` 落为 Project Resource（不二次 refetch，记录 URL/时间/hash/truncated/source lineage）。
- **Capability 与授权契约**：Manifest v2（`FamiliarCapabilityContract.swift`）、确定性 `FamiliarCapabilitySnapshot`、`FamiliarAuthorizationGrant`（规范化 arguments hash + source/scope/expiry 校验）已接入；旧 `FamiliarOneShotAuthorization` 来源式写授权停用。
- **可恢复 Run 数据契约**：`RunResumeCursorRecord`/`ToolInvocationRecord` 已接入；工具调用以 `run:toolCallID` 幂等键持久化状态，已 committed 拒绝重复提交。Controller 已在工具请求、审批、完成事件边界接入 invocation（requested→approved→committed/cancelled/failed）与 cursor 记录；字节级中断续跑仍未实现。
- **运行时错误分类与重试**：`FamiliarRuntimeFailure.kind(for:)` 统一分类（auth/限流/5xx/网络/上下文/参数/结果/取消）；Agent Loop 在首个字节前对 transient/限流做有界重试。
- **运行时预算**：工具调用总数与单次 Run 总时长预算，超限以明确终态失败。
- **孤儿 Run 恢复**：`FamiliarRunRecoveryService.recoverInterruptedRuns` 在启动时把遗留 running Run 终结为 failed，并取消在途 invocation。
- **Project 闭环补齐**：项目详情可浏览/预览/删除 Artifact，单项删除同步清理元数据和文件；永久删除项目时 Resource 与 Artifact 目录先暂存、数据库提交成功后再清理，失败时恢复；运行启动时持久化 CapabilitySnapshot 与 RunResumeCursor。
- **Resource 工具**：`resource_list/read/search` 已注册；当前启动时注册表共 13 个工具，读取工具使用运行开始时冻结的 Resource 版本快照。
- **Share 目标选择**：共享收件箱内容进入 App 后可选择已有项目、新建项目或普通聊天草稿，取消时清理准备中的附件。
- **系统入口**：Share Extension、类型化 Deep Link、App Intents/Shortcuts、Run 终态本地通知、Spotlight 会话索引、Widget/Control。
- **本地渲染**：非持久化 WKWebView + 内置 Markdown/高亮/Mermaid/KaTeX/DOMPurify，CSP 禁远程图片自动加载。

## Verification Evidence

- 2026-08-21：`Familiar` scheme 的 Debug arm64 generic iOS Simulator `build` 成功，覆盖 App、Share Extension、Widgets 与 FastVLM/MLX 依赖。
- 2026-08-21：同一 destination 的 `build-for-testing` 成功，`FamiliarTests` 与 `FamiliarUITests` 测试产物均已编译。构建只出现 Xcode 对无 App Intents 依赖 target 跳过 metadata extraction 的警告，没有 Swift 源码诊断。
- 未启动或运行 Simulator，未执行 `test` 或 `test-without-building`，因此没有测试执行结果，也不声明 Simulator 行为或视觉验收通过。

## Known Problems

- 真实 Provider 认证/流式/错误/工具闭环：**全部 12 个内置 Provider 尚未用真实 Key 冒烟**。下一阶段只把 DeepSeek 设为阻塞验收主路径，其他 Provider 延后（清单见 `docs/11`）。
- 真机验收未完成：EventKit 权限、真实文档/OCR、相机、Speech、Share/Deep Link/通知/Spotlight/Intents/Widget/Control 均依赖真机。
- iOS CI 远程首次结果**尚未确认**（本地解析通过，GitHub Actions 未触发或未记录）。
- `FamiliarRunRecoveryService` 的 CapabilitySnapshot/Cursor 与 ToolInvocation 生命周期已接入；字节级中断续跑仍未实现。
- Memory 自动/显式 Runtime 工具、Remote MCP 和可靠后台承接仍未实现，按后续层次推进。
- 后台承接未实现：`BGContinuedProcessingTask` 仅适用于 iOS 26+；当前通知只报告进程内实际到达的终态。
- EventKit 写入幂等与跨重启 Undo 已实现但未真机验证；系统 save 后进程立即终止的边界仍未验证。
- FastVLM 官方模型 archive 已在开发机验证大小与 SHA-256；真机下载恢复、Core ML 编译、推理、热/内存表现未验证。
- SwiftData 真机恢复路径（磁盘不足、损坏 store、旧安装覆盖）未在真机验收。

## Next

1. 由所有者在真机验收设置/项目/模型顶栏布局、左缘抽屉手势、置顶与长按菜单、项目折叠/展开更多、Composer Slash Skill 面板、极端 Dynamic Type、VoiceOver、Reduce Motion、Reduce Transparency 与中英文布局。
2. 由所有者继续验收 Skills、DeepSeek、EventKit、FastVLM、Share 与系统入口真机路径。

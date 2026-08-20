# Current State

Last verified: 2026-08-20

> 代码基线：`feat/familiar-product-convergence-v1`，基于 `main @ ed66605`。当前功能改动均已按 Work Package 提交。

## Current Focus

Product Convergence v1 已把现有能力收敛为统一产品模型：Chat 是主要交互与执行 Surface，Project 是长期 Context Workspace，单 Agent Runtime 是执行内核，原生 iPhone Capabilities 是执行能力。Project Home 现在优先继续工作，只保留 Continue / New Chat 两级动作；Resources 与 Artifacts 保留为主要上下文内容，Conversations / Skills / Runs 合并为次级 Project Context 导航。Project Conversation 继续复用普通 Chat Surface，并在顶栏显示唯一的 Project 归属入口。核心 Chat、Composer、Drawer、Project、Settings Hub 与 Agent Surface 已开始使用统一语义 UI tokens。

## Recently Completed

- **Product Convergence v1**：删除 Project Home 独立 Ask 输入框和重复执行路径，把项目管理操作移入导航菜单；Project Conversation 顶栏增加可返回 Project Home 的单一归属标识，普通 Chat 保持无项目提示；Chat 顶栏删除重复设置按钮；Settings 移除未接入数据的 Token Usage 占位页。`FamiliarTheme` 现包含有限 spacing、Dynamic Type typography、radius、icon visual size、hit target 和基础 ButtonStyle tokens，核心高频 Surface 已迁移。

- **Project Workspace 与 Skills v1**：项目页成为资料、对话、Artifact、Run 和 Skill 的工作台；支持项目内直接提问、公开 HTTPS 网页和粘贴文本导入，Share 选择项目后落为 Resource。全局可安装严格 instruction-only JSON Skill，项目逐项启用；Run 启动前冻结 Skill ID/版本/hash/allowedTools，以允许工具并集收窄当前可用 manifests，安全策略始终最后注入且 Skill 不能产生授权。V9 增加 `FamiliarRunSkillSnapshotRecord`，聊天轨迹和项目 Run 详情可检查实际 Resource、Skill、Provider/Model 与工具范围。
- **导航与草稿安全**：抽屉改为项目/对话统一搜索，提供新聊天、项目、最近和设置入口；顶栏移除重复设置按钮。切换对话或新建聊天时不会静默丢弃草稿，删除对话具有明确确认。
- **执行体验与授权**：Runtime 事件携带 `effect` 与 `assistantTurnID`；读取工具仅更新轻量 Agent 状态，写操作使用动作卡。同一回合的多张写卡使用水平 `viewAligned` pager、边缘渐隐、选择触觉和 Reduce Motion 降级。`FamiliarAuthorizationRuntime` 已接入 Agent Loop，授权按 Project、工具版本、目标和精确参数 hash 匹配，支持仅这次/本会话/长期授权，并在设置中可撤销。
- **跨重启 Undo 与视觉证据**：V7 增加 `FamiliarAuthorizationRuleRecord`、`FamiliarEventKitUndoRecord`、`FamiliarVisualEvidenceRecord`；EventKit create 写入 durable undo record，重启后可重建撤销入口；Apple Vision 对纯文本模型图片生成带 provenance 的不可信只读证据，持久化到实际用户消息与 ContextSnapshot。
- **FastVLM 0.5B**：`Vendor/ml-fastvlm` 的官方源码被封装为本地 Swift Package，锁定 MLX 0.21.2 / MLX examples 2.21.2 / Transformers 0.1.18 / ZIPFoundation 0.9.19。设置页实现 iOS 18.2+、Metal/内存/3.5 GB 存储准入、进度、暂停/恢复、SHA-256、受控解包、Core ML 编译、自动基准、删除、60 秒超时和 Apple Vision 降级。真实设备尚未验收。
- **Surface Protocol（前端 P0）**：新增 `FamiliarSurfaceDescriptor`/`FamiliarSurfaceStore` 纯 reducer，把 `FamiliarRuntimeEvent` 折叠成稳定 surface（identity `run:<runID>` / `tool:<runID>:<toolCallID>`，旧 sequence 不覆盖终态）；`FamiliarChatMessageViews` 以单一 `FamiliarToolActivityCard` 原位 morph 工具全生命周期（queued→审批→running→终态），终态内联 `FamiliarArtifactCard`（Quick Look + 分享），`FamiliarAgentStatusRow` 承载 Agent 轻状态；集中 `FamiliarMotion` tokens 与 `FamiliarHapticPolicy`；`FamiliarSurfaceTests` 当前包含 11 项单测，覆盖 identity 连续性、stale 事件、审批 resolve、run 终态、artifact 传播。测试产物已编译，真机视觉/VoiceOver/Dynamic Type 验收仍待所有者完成。

- **WP0 可验证内核**：8 场景 fake-provider Benchmark（`FamiliarBenchmarkTests`）+ `Scripts/run-agent-benchmarks.sh` + arm64 Simulator iOS CI（`.github/workflows/ios.yml`）。
- **WP2 SwiftData 迁移基础**：7 实体冻结为 `FamiliarSchemaV1`，正式 migration plan 接入生产与测试容器。
- **WP3 Project 最小纵切**：`FamiliarSchemaV2` 增加 Project/ProjectInstruction，对话可选归属项目，项目指令注入、抽屉/项目列表/编辑/归档/删除。
- **WP4 Resource + ContextSnapshot**：`FamiliarSchemaV3` 增加 Resource/ResourceVersion/ContextSnapshotRecord/ContextResourceReference；项目资源独立受保护目录；`FamiliarProjectContextAssembler` 生成确定性不可变上下文，超出输入预算明确拒绝。
- **WP5 Artifact + Web 项目闭环**：`FamiliarSchemaV4` 增加 Artifact；受控 `artifact_write` 工具（逐次确认）；`web_fetch` 正文可经 `importFetchedWebText` 落为 Project Resource（不二次 refetch，记录 URL/时间/hash/truncated/source lineage）。
- **WP6 Capability 与授权契约**：Manifest v2（`FamiliarCapabilityContract.swift`）、确定性 `FamiliarCapabilitySnapshot`、`FamiliarAuthorizationGrant`（规范化 arguments hash + source/scope/expiry 校验）；`FamiliarSchemaV5` 持久化快照与 grant；旧 `FamiliarOneShotAuthorization` 来源式写授权停用。
- **WP7 可恢复 Run 数据契约**：`FamiliarSchemaV6` 增加 `RunResumeCursorRecord`/`ToolInvocationRecord`；工具调用以 `run:toolCallID` 幂等键持久化状态，已 committed 拒绝重复提交。Controller 已在工具请求、审批、完成事件边界接入 invocation（requested→approved→committed/cancelled/failed）与 cursor 记录；字节级中断续跑仍未实现。
- **运行时错误分类与重试**：`FamiliarRuntimeFailure.kind(for:)` 统一分类（auth/限流/5xx/网络/上下文/参数/结果/取消）；Agent Loop 在首个字节前对 transient/限流做有界重试。
- **运行时预算**：工具调用总数与单次 Run 总时长预算，超限以明确终态失败。
- **孤儿 Run 恢复**：`FamiliarRunRecoveryService.recoverInterruptedRuns` 在启动时把遗留 running Run 终结为 failed，并取消在途 invocation。
- **Project 闭环补齐**：项目详情可浏览/预览/删除 Artifact；删除项目时 Resource 与 Artifact 目录先暂存、数据库提交成功后再清理，失败时恢复；运行启动时持久化 CapabilitySnapshot 与 RunResumeCursor。
- **Resource 工具**：`resource_list/read/search` 已注册；当前启动时注册表共 13 个工具，读取工具使用运行开始时冻结的 Resource 版本快照。
- **Share 目标选择**：共享收件箱内容进入 App 后可选择已有项目、新建项目或普通聊天草稿，取消时清理准备中的附件。
- **系统入口**：Share Extension、类型化 Deep Link、App Intents/Shortcuts、Run 终态本地通知、Spotlight 会话索引、Widget/Control。
- **本地渲染**：非持久化 WKWebView + 内置 Markdown/高亮/Mermaid/KaTeX/DOMPurify，CSP 禁远程图片自动加载。

## In Progress

Product Convergence v1 的代码与文档 Work Package 已完成静态 Swift 解析、strings plist 校验和 diff 检查。最终 arm64 iOS Simulator build 尚未执行；本轮不会启动 Simulator，也不会声明视觉验收通过。

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

1. 完成 Product Convergence v1 最终 arm64 iOS Simulator build，修复编译阻塞后推送 integration branch。
2. 由所有者在真机验收普通 Chat / Project 区分、Project 顶栏归属、Project Home 层级、极端 Dynamic Type、VoiceOver、Reduce Motion、Reduce Transparency 与中英文布局。
3. 由所有者继续验收 Skills、DeepSeek、EventKit、FastVLM、Share 与系统入口真机路径。

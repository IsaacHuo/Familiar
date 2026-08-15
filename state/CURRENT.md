# Current State

Last verified: 2026-08-15

> 代码基线：`main @ cc26ee5`，另有一批未提交的工作树改动（见 In Progress）。

## Current Focus

Project 主链路（长期工作单元）已完成数据与基础 UI 闭环：Project → 项目指令 → 版本化 Resource → 不可变 ContextSnapshot → Artifact → Web capture 落为 Resource → Capability/授权数据契约 → 可恢复 Run 数据契约。当前开发重点是：

1. 图片输入路径（未提交 WIP）：让支持图片的模型真正接收图片字节。
2. 把已建模但尚未接入运行时路径的授权/恢复契约（`FamiliarRunRecoveryService`、grant-aware policy）逐步接到真实执行。
3. 真实 Provider 冒烟与真机验收（见 `docs/11`）。

## Recently Completed

- **WP0 可验证内核**：8 场景 fake-provider Benchmark（`FamiliarBenchmarkTests`）+ `Scripts/run-agent-benchmarks.sh` + arm64 Simulator iOS CI（`.github/workflows/ios.yml`）。
- **WP2 SwiftData 迁移基础**：7 实体冻结为 `FamiliarSchemaV1`，正式 migration plan 接入生产与测试容器。
- **WP3 Project 最小纵切**：`FamiliarSchemaV2` 增加 Project/ProjectInstruction，对话可选归属项目，项目指令注入、抽屉/项目列表/编辑/归档/删除。
- **WP4 Resource + ContextSnapshot**：`FamiliarSchemaV3` 增加 Resource/ResourceVersion/ContextSnapshotRecord/ContextResourceReference；项目资源独立受保护目录；`FamiliarProjectContextAssembler` 生成确定性不可变上下文，超出输入预算明确拒绝。
- **WP5 Artifact + Web 项目闭环**：`FamiliarSchemaV4` 增加 Artifact；受控 `artifact_write` 工具（逐次确认）；`web_fetch` 正文可经 `importFetchedWebText` 落为 Project Resource（不二次 refetch，记录 URL/时间/hash/truncated/source lineage）。
- **WP6 Capability 与授权契约**：Manifest v2（`FamiliarCapabilityContract.swift`）、确定性 `FamiliarCapabilitySnapshot`、`FamiliarAuthorizationGrant`（规范化 arguments hash + source/scope/expiry 校验）；`FamiliarSchemaV5` 持久化快照与 grant；旧 `FamiliarOneShotAuthorization` 来源式写授权停用。
- **WP7 可恢复 Run 数据契约**：`FamiliarSchemaV6` 增加 `RunResumeCursorRecord`/`ToolInvocationRecord`；工具调用以 `run:toolCallID` 幂等键持久化状态，已 committed 拒绝重复提交。注意：**该契约尚未接入运行时执行**（仅数据层与测试）。
- **系统入口**：Share Extension、类型化 Deep Link、App Intents/Shortcuts、Run 终态本地通知、Spotlight 会话索引、Widget/Control。
- **本地渲染**：非持久化 WKWebView + 内置 Markdown/高亮/Mermaid/KaTeX/DOMPurify，CSP 禁远程图片自动加载。

## In Progress

工作树有一批**未提交**改动（`git status` 可见），共同方向是把图片输入从"草稿拦截"推进到"可发送"：

- `FamiliarModelProvider.swift`：`FamiliarProviderContent` 增加 `image(data:mimeType:)`，替换 `imagePlaceholder`。
- `FamiliarProviderAdapters.swift` / `OpenAICompatibleClient.swift`：Anthropic 与 Gemini adapter 增加图片 block/part 编码（base64）。
- `FamiliarProjectContextAssembler.swift`：图片附件从磁盘加载真实字节进入上下文。
- `FamiliarChatController.swift` / `FamiliarChatView.swift` / `FamiliarChatMessageViews.swift` / `FamiliarComposerView.swift`：发送 gate 与 UI 配合图片路径。
- `FamiliarSpeechTranscriber.swift`：异步化重构（`async`/`await`、sessionID 失效保护、强制 on-device）。
- `FamiliarMarkdownWebView.swift`：首帧渲染前用 SwiftUI 回退文本占位，避免布局跳动。
- `FamiliarAttachmentStore.swift`、`FamiliarBenchmarkTests.swift` 配套调整。

## Known Problems

- 真实 Provider 认证/流式/错误/工具闭环：**全部 12 个内置 Provider 尚未用真实 Key 冒烟**（清单见 `docs/11`）。
- 真机验收未完成：EventKit 权限、真实文档/OCR、相机、Speech、Share/Deep Link/通知/Spotlight/Intents/Widget/Control 均依赖真机。
- iOS CI 远程首次结果**尚未确认**（本地解析通过，GitHub Actions 未触发或未记录）。
- `FamiliarRunRecoveryService`、`FamiliarCapabilityResolver`、grant-aware `FamiliarExecutionPolicy` 已建数据契约但**未接入运行时**；运行时仍是逐次确认写入。
- `resource.list/read/search` 工具、Artifact/Binding 项目级 UI、Share 导入后的项目选择分流**未实现**。
- 后台承接未实现：`BGContinuedProcessingTask` 仅适用于 iOS 26+；当前通知只报告进程内实际到达的终态。
- EventKit 写入幂等与 Undo 状态仅限当前进程；系统 save 后进程立即终止的边界未验证。
- SwiftData 真机恢复路径（磁盘不足、损坏 store、旧安装覆盖）未在真机验收。

## Next

1. 完成图片输入路径并提交（含适配器 fixture、gate 测试、隐私确认：图片字节只发往用户所选 Provider）。
2. 把授权/恢复契约接入运行时（错误分类、有限重试、预算；`resource.*` 工具；Share → 项目选择）。
3. 按 `docs/11` 完成真实 Provider 冒烟与真机验收。
4. 确认远程 CI 首轮结果。
5. 之后才评估 Skills、Remote MCP、Memory、新原生能力与 iOS 26+ 后台承接。

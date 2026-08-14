# Familiar 实施状态记录

更新时间：2026-08-13

本文件汇总当前 `main` 已交付能力、验证边界和后续事项。详细设计与逐项验收矩阵见 [`Docs/`](Docs/README.md)。

## 已完成

- iPhone 原生 App Shell、可跳过且可恢复的 BYOK 首启流程、本地会话历史、搜索、重命名、删除、编辑重发、重试、复制与分享。
- 12 个内置 Provider 与自定义 OpenAI-compatible Provider，覆盖 OpenAI Chat、Anthropic Messages、Gemini Generate Content 三类协议；API Key 按 Provider 存入 Keychain。
- 单 Agent 有限执行循环、类型化 Tool Registry、Execution Policy、Runtime Event、Run/Step 检查点和终态持久化。
- 本机时间、App 信息、日历查询/创建、提醒事项查询/创建工具；自然语言写入需要结构化确认，并提供当前进程内单次 Undo。
- 只读 `web_search` 与 `web_fetch`，包含公共 HTTPS、DNS/重定向/大小限制和回答来源记录。
- SwiftData V1/V2/V3 保持冻结；当前 V6 通过轻量迁移链新增 Project Resource/版本、不可变 Run ContextSnapshot、Artifact、CapabilitySnapshot/AuthorizationGrant 与 RunResumeCursor/ToolInvocation；旧 store 可原位升级，打开失败时仍提供用户确认的数据恢复流程。
- Artifact 第一版仅 Markdown/纯文本，写入受项目作用域与逐次结构化确认约束；`web_fetch` 本次正文可落为 Project Resource，记录 URL/访问时间/hash/truncated/source lineage，不二次 refetch。
- Capability/授权契约：Manifest v2、确定性 CapabilitySnapshot、AuthorizationGrant（规范化 arguments hash + source/scope/expiry 校验）；Share/AppIntent/DeepLink 不能签发写 grant；写入仍逐次确认。
- 可恢复 Run 数据契约：RunResumeCursor 与 ToolInvocation 幂等记录，已 committed 的工具调用拒绝重复提交。
- Project Resource 文档使用独立受保护目录、SHA-256 校验和稳定版本 ID；项目对话确定性包含所有最新资源，超出模型输入预算时明确拒绝，不静默省略。
- 本地文档导入与 AnyDoc 转换、PDFKit 文本检查、Vision OCR、Quick Look；相机和 PhotosPicker 图片草稿保留发送 gate；Apple Speech 生成可编辑转写文本。
- 本地 WebKit Markdown、代码高亮、Mermaid 与 KaTeX 渲染；远程 Markdown 图片不会自动加载。
- Share Extension、类型化 Deep Link、App Intents / Shortcuts、Run 终态本地通知、受保护的 Spotlight 会话索引。
- Home/Lock Screen 启动 Widget 与控制中心 Control，均复用受限系统入口，不自动发送消息或授权工具。
- 简体中文和英文资源、核心无障碍语义、Reduce Motion 与 Reduce Transparency 适配。
- iOS 单元测试、8 场景 fake-provider Benchmark、UI 冷启动冒烟测试、AnyDoc Rust fixture 测试和网站构建流程。
- arm64 Simulator iOS CI 已配置，分别报告 build、unit/benchmark tests 和 UI cold-launch smoke。

## 当前验证

- `FamiliarWidgets` Debug arm64 iOS Simulator 构建通过。
- `Familiar` Debug arm64 iOS Simulator 构建及扩展嵌入校验通过。
- 2026-08-15 使用 iOS 26.5 arm64 Simulator 运行完整测试：58 项通过、0 失败；参数化 Benchmark 的 8 个场景全部通过。
- UI 冷启动 `testColdLaunchShowsOnboardingOrChatShell`：1 项通过、0 失败。
- Debug arm64 Simulator build-for-testing 与普通 Simulator build 均通过。
- WP4 focused migration/resource/context/project/runtime tests 21 项通过：真实磁盘 V1/V2→V3、旧 Attachment.resourceVersion 为空、路径/hash/symlink/删除、共享资源生命周期、确定性上下文和预算、失败/取消 snapshot 保留、项目删除脱离历史会话/Run 并清理资源。
- WP5-WP7 focused tests 覆盖 Artifact 项目作用域/hash/事务、Web capture 不二次 fetch、V3→V4 与 V4→V6 迁移、Manifest 快照确定性、Grant 参数/作用域/来源校验、工具调用幂等拒绝重复提交。
- AnyDoc Rust fixture 和网站 production build 在既有工程记录中通过。
- AnyDoc XCFramework 仅包含 iOS arm64 与 iOS Simulator arm64 slice，不支持 Intel Simulator。

## 尚未完成

- 使用真实 API Key 对所有内置 Provider 完成认证、流式回答、错误 Key、超时/取消、模型列表和真实工具调用验收。
- 在真机完成 EventKit 权限与写入/Undo、真实文档与扫描 PDF、相机、PhotosPicker、Speech、Share Extension、Deep Link、通知、Spotlight、App Intents、Widget / Control 验收。
- 补齐 SwiftData 旧安装覆盖、损坏 store、权限异常和磁盘空间不足的真机恢复验证，并在发布后 Schema 变化前制定正式迁移策略。
- Artifact、Binding、Memory、Resource 工具和 Resource 后续版本更新尚未实现；Artifact 第一版只支持项目文档首次导入、预览、删除、自动上下文注入和 Markdown/纯文本 Artifact 写入。
- 实现完整 Run 重放/恢复数据契约和后台恢复事件；`BGContinuedProcessingTask` 仅可作为 iOS 26+ 的承接方式，iOS 18–25 只能提供系统择机执行或提醒用户继续。
- Artifact、CapabilityBinding 的项目级 UI 绑定、错误分类/有限重试/预算约束和后台承接尚未接入运行时。
- iOS CI 远程首次运行结果仍待确认；V3 的真实旧安装覆盖与资源文件保护仍待真机验收。
- 扩展测试深度，包括真实 Provider 可控端到端测试、附件/OCR/清理集成测试和主要 UI/系统入口流程。
- 持久化 EventKit 写入幂等与 Undo 状态；当前保护范围仅限当前进程。

## 当前范围外

- 账户、登录、Familiar 后端、云同步、托管额度、订阅和权益。
- iPad UI、任意代码或 Shell 执行、多 Agent、复杂 RAG、MCP Server、本地 Core ML LLM 和实时语音对话。
- 修改或删除已有日历/提醒事项、自动浏览器操作和自主 Web 调研。
- 图片模型请求；当前只允许生成和编辑图片草稿，并在发送前明确拦截。

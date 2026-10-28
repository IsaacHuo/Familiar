# 功能状态索引

核对：2026-10-20。代码入口及领域规则见[架构](ARCHITECTURE.md)，当前UI状态见[CURRENT](CURRENT.md)。本表不复制工具manifest、历史suite流水或设备检查单。

| 子系统 | 生产入口／实现 | 验证边界 |
|---|---|---|
| Chat | AppShell、ChatsHome、ChatSessionCoordinator、ChatView | 源码已接；UI逐项目标在[账本](../docs/telegram-ios-ui-checklist.md)，真机待验收 |
| 历史 | ChatHistoryStore、HistoryWindow、RunHistoryQuery | 80项富数据窗口，完整业务读分离；线性身份索引SQL与性能未测 |
| 模型 | ProviderCatalog、ProviderFactory、OpenAICompatible／Structured／Group、OAuth | 用户自有Key／外部登录；真实服务按当前配置验收 |
| Agent | AgentLoop、ContextCompiler、ToolRegistry、ExecutionPolicy | 单Agent、Lazy Tools；不确定写不重放，无后台／跨重启续跑 |
| Web | WebTools、WebSearchService、WebContentService、RestrictedHTTPClient | 真实来源及引用；[S1历史证据](../docs/research/2026-10-17-search-evidence.md)不覆盖当前UI |
| Files | FileCatalogService、FileValidator、AttachmentStore、Files UI | canonical File/Version与scope；预览分享／删除／恢复待设备 |
| Shell | ISHShellExecutor、ShellPolicy、ISHPreparation、Terminal | 已捆绑Alpine与文档库；guest旧冒烟不替代真机冷热启动 |
| Memory／Skills | MemoryService、SkillsService及工具 | 三scope、选择／懒加载、provenance和工具范围；不创建授权 |
| MCP | MCPClient、TrustStore及设置 | HTTP发现／批准调用已接；信任按服务器，真实端点独立验收 |
| Apple服务 | Native／EventKit typed adapters | 系统许可、硬件、副作用和Undo不能由fixture推断 |
| 图片／语音 | VisionProcessor、SpeechTranscriber、ReplySpeechPlayer | 图片按当前模型能力；晚到回调／中断／设备识别待设备 |
| 系统入口 | ShareExtension、AppIntents、Notifications、Spotlight、Widgets | 仅输入来源；锁定、冷启动和设备权限待验收 |
| 存储与恢复 | 当前schema5.0.0／39实体、5-work-scopes、Recovery | 本轮未更改；已完成代际后的打开失败不重置 |
| 研究 | FastVLM／CoreAI／FamiliarMac相关代码 | 不把未接入iOS生产路径当产品能力 |

历史自动化证据见[2026-10-08记录](../docs/research/2026-10-08-functional-evidence.md)。当前代理只做App与测试目标编译；执行测试、真实Provider和所有者真机状态分开。

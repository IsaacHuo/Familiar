# 参考实现与使用边界

先读对应源码和调用上下文，再改 Familiar；原理、路径及阅读范围必须可追溯。不把下载文件视为全文审阅。

| 来源 | 用途 | 边界 |
|---|---|---|
| [Telegram iOS](https://github.com/TelegramMessenger/Telegram-iOS/tree/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838) | 当前 UI 唯一视觉基线，含消息、输入、导航、媒体、设置与动效 | 固定提交；公开 UIKit/SwiftUI 适配；不引入 TelegramEngine/Postbox/AsyncDisplayKit 或私有 API；上游GPL-2.0-or-later；本项目GPL-3.0适配保留notice（[官方声明](https://telegram.org/apps#source-code)） |
| [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | MCP transport、协议与类型设计 | 查对应版本许可；作为参考，不作为 Runtime 内核 |
| [OpenMinis](https://github.com/OpenMinis/OpenMinis) | iSH、原生 offload、Skills/Memory/Workspace | GPL-3.0；只迁移有当前需求的能力，保留归属 |
| [Swarm](https://github.com/christopherkarani/Swarm) | Swift Agent 循环与工程组织 | 不引入多 Agent / Graph |
| [ModLens](https://github.com/liustack/modlens) | 文本模型视觉证据、能力检测 | Node 服务不可嵌入 iOS；不把其他服务调用说成本机识图 |
| [FastVLM](https://github.com/apple/ml-fastvlm) | 历史本地视觉研究 | 不进入当前产品；模型研究许可不等于公开分发授权 |

Telegram 的精确源码与研究深度统一见 [登记](research/telegram-ios-source-map.md)，逐项实现与验收见 [账本](telegram-ios-ui-checklist.md)。其他仓库按实际需要访问上游，不维护失效的 achieve 本地路径。

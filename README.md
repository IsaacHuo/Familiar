# Familiar

Familiar 是一个独立的 iOS 聊天问答 App，最低支持 iOS 17。

## 当前功能

- 支持 DeepSeek 与 Groq Provider 的流式聊天和原生 tool calling。
- BYOK：每个 Provider 的 API Key 分开保存在当前设备 Keychain，请求由设备直接发送到所选 Provider。
- 对话历史使用 SwiftData 保存在当前设备。
- 支持本地 Markdown、代码高亮、Mermaid 与 KaTeX 回答渲染。
- 无账号、无登录、无 Supabase、无后端数据库、无订阅或额度系统。
- 不读取学业系统或其他 App 的个人数据。
- 内置只读 Native Tools：当前本地日期时间、Familiar App 版本信息。
- Tool 执行状态会实时显示，但中间态不会写入 SwiftData。
- 当前不包含联网研究、个人数据读取、外部动作、MCP、Sandbox 或 Artifact。

## 开发

打开 `familiar.xcodeproj`，选择 `Familiar` scheme。工程没有第三方运行时依赖，也不需要服务端环境变量。

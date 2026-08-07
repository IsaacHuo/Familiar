# Familiar

Familiar 是一个独立的 iOS 聊天问答 App，最低支持 iOS 17。

## 当前功能

- 使用 DeepSeek Flash 或 Pro 进行流式聊天问答。
- BYOK：API Key 只保存在当前设备 Keychain，请求由设备直接发送到 DeepSeek。
- 对话历史使用 SwiftData 保存在当前设备。
- 支持本地 Markdown、代码高亮、Mermaid 与 KaTeX 回答渲染。
- 无账号、无登录、无 Supabase、无后端数据库、无订阅或额度系统。
- 不读取学业系统或其他 App 的个人数据。
- 当前不包含联网研究、外部动作或 Artifact。

## 开发

打开 `familiar.xcodeproj`，选择 `Familiar` scheme。工程没有第三方运行时依赖，也不需要服务端环境变量。

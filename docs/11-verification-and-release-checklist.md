# Familiar 验证与发布清单

用途：在不把真实 API Key 写入自动化环境的前提下，验证认证、流式协议、错误边界、工具闭环、真机行为与发布门槛。每次执行记录 App commit、设备/iOS、Provider、模型 ID、时间和结论；**不要记录 API Key、完整问题或返回的私密内容**。

当前自动化覆盖见 `state/CURRENT.md`；本文件是手动/真机验证程序。

## 1. 真实 Provider 冒烟

### 1.1 通用前置

- 使用非生产测试 Key，并确认 Key 只保存在对应 Provider 的 Keychain 项。
- 使用公开、非私密问题；工具测试使用可删除的测试日历或提醒列表。
- 记录 Provider endpoint、协议族、模型 ID 和模型能力标记。
- 抓取 App 可见状态和必要的脱敏网络错误，不保存 Authorization header。

### 1.2 每个内置 Provider

内置 Provider：OpenAI、Anthropic、Gemini、DeepSeek、Groq、xAI、OpenRouter、Qwen、Kimi、GLM、MiniMax、SiliconFlow。

| 场景 | 操作 | 通过标准 |
|---|---|---|
| 认证成功 | 保存有效 Key，执行连接验证 | 明确成功，不泄露 Key |
| 文本流式 | 发送简短非私密问题 | 收到增量文本和正常 stop，不出现空响应 |
| 错误 Key | 替换为无效 Key | 显示认证失败，不显示虚假回答 |
| 模型列表 | 刷新模型列表，或验证 curated fallback | 有 endpoint 时解析列表；无 endpoint 时保留可编辑模型 ID |
| 超时/取消 | 发送长请求并主动停止 | 请求终止，UI 回到可发送状态，不保存虚假助手终态 |
| Provider 错误 | 使用无效模型 ID | 显示有限长度错误，草稿和历史可恢复 |

### 1.3 协议族

**OpenAI Chat**：验证 `data:` SSE、`[DONE]`、文本 delta 和 `finish_reason`；对至少一个支持工具的模型验证增量 `tool_calls` 参数、tool result 回填和最终 stop；验证兼容 Provider 的 endpoint、headers 和 stream option 差异没有被统一假设覆盖。

**Anthropic Messages**：验证 `content_block_start`、`content_block_delta`、`message_delta` 和 `message_stop`；验证 `tool_use` ID、`partial_json` 参数增量和 tool result block 回填。

**Gemini Generate Content**：验证 `streamGenerateContent?alt=sse`、candidate 文本增量和终止原因；验证 function call 缺少服务端 ID 时，本地调用 ID 在当前 Run 内保持一致。

### 1.4 工具闭环

至少选择每个协议族中的一个真实工具模型，执行：

1. "明天下午有什么安排？"验证 EventKit read Tool Call。
2. "明天下午三点提醒我测试 Familiar"验证结构化确认。
3. 在确认前取消，确认 EventKit 零写入。
4. 再次执行并确认，确认只创建一条提醒并显示 Undo。
5. 执行 Undo，确认系统对象被删除且不能重复 Undo。
6. 执行公开 Web 查询，确认 Sources 可见且失败来源不会被声称已读取。

## 2. 真机验收

### 2.1 EventKit

full access 允许 / 拒绝 / restricted；查询时间范围与文字条件；创建预览、确认写入、取消、任务中止；重复工具调用；系统保存失败。

### 2.2 文件与文档

- iCloud Drive 安全作用域文件、On My iPhone 文件、25 MiB 边界。
- DOCX、PPTX、XLSX、ODT、RTF、EPUB、CSV；文本 PDF；扫描 PDF；加密和损坏文档。
- 附件删除和重新预览。
- 项目资源从 iCloud Drive / On My iPhone 导入、Quick Look、OCR 标记和删除。
- 同一资源在两条项目对话中使用，重启后版本/hash 保持。
- 项目删除后历史聊天仍可打开且资源目录不可恢复；运行中 Run 时删除按钮禁用。

### 2.3 Project 主链路（WP1–WP4）

- 抽屉、设置、Run timeline 与工具清单在中英文、VoiceOver 和极端 Dynamic Type 下可操作。
- 保留真实旧 store 覆盖安装，确认自动迁移、重启读取和迁移失败恢复界面不静默删数据（见 `logs/swiftdata-store-migration-134110.md`）。
- 创建/编辑/归档项目，创建普通与项目聊天，确认项目指令只进入项目聊天；历史 Run 项目归属符合启动时快照。
- 导入文本 PDF、扫描 PDF 和至少一种 Office 文档，确认进度、OCR、Quick Look、文件保护、两条项目聊天共享资料及超预算提示。
- 删除单条消息不删除资源；删除资源后预览不可用；删除项目后聊天/历史 Run 保留并脱离，资源与指令删除。
- 断网/取消/模型失败后 Run ContextSnapshot 元数据和资源 hash 引用仍可读取，且记录中没有完整资源抽取文本。

### 2.4 相机与图片

相机权限、前后镜头、闪光灯、PhotosPicker 多选；图片发送在能力不支持时被拦截且文字和图片草稿保持。

### 2.5 Speech

Speech 权限、麦克风权限、中文转写、设备端识别、系统中断、App 失活停止、无录音文件。

### 2.6 系统入口

Share Extension（Notes/Safari/Files 来源、文件协调、签名环境）、Deep Link（冷启动/回前台）、通知（权限、锁屏呈现、冷启动点击、目标已删除）、Spotlight（索引延迟、中英文查询、设备锁定、冷启动、重命名/删除刷新）、App Intents（Siri/Shortcuts/Spotlight/Action Button、后台唤起、语音参数、真实请求）、Widget/Control（Gallery、主屏幕/锁屏启动、控制中心注册、未发送草稿保护）。

### 2.7 SwiftData 恢复

旧安装覆盖、损坏 store、权限异常、磁盘空间不足的启动行为；恢复重建后 Keychain 保留、重启后会话可读。

## 3. UI 验证矩阵

- iOS 18 和 iOS 26。
- Light 和 Dark。
- 简体中文和英文。
- Dynamic Type（含极端字号）。
- VoiceOver（含焦点返回、连续工具状态播报）。
- Reduce Motion 与 Reduce Transparency。
- Increase Contrast 与 Bold Text。
- 键盘交互与抽屉边缘手势。
- 长回答和滚动稳定性。
- Markdown、代码、表格、引用、KaTeX、Mermaid。
- 复制、分享、编辑、重试。

## 4. 发布前质量门槛

### 构建

- Debug generic iOS、Release generic iOS、iOS 18 arm64 Simulator 均通过。
- 当前 Xcode 稳定版 Swift 6 警告清零。

### 数据

- 当前 store 首次创建和重启通过；旧开发 store 切换通过。
- 会话、附件和工具终态重启后可读取；删除会话后附件清理通过。
- 正式 Schema 变化前提供 migration stage 与磁盘迁移测试。

### Agent

- 未确认写操作零执行；取消写操作零执行。
- 相同 run 的重复写入最多一次成功。
- 工具失败不显示成功状态。

### Provider

- 每个内置 Provider 至少一次真实文本流式冒烟。
- 标记工具能力的模型至少一次真实工具调用。
- 自定义 Base URL 行为符合设置说明。

### 隐私

- API Key 不出现在日志和普通存储。
- 图片 bytes 与原文件 bytes 只按用户所选 Provider 的路由发送，不进入无关存储。
- Speech 和 EventKit 用途说明与调用一致。
- Markdown 远程图片不自动加载，策略在 App 与官网披露。

### App Store

- 隐私政策和支持页可访问；用途说明完整。
- 无账户、订阅和无效入口。
- Provider 模型 ID 失效时界面可恢复。
- 真机主路径完成验收。

## 5. 记录模板

```text
Date:
Commit:
Device / iOS:
Provider:
Protocol:
Model ID:
Authentication: pass / fail
Text stream: pass / fail
Invalid key: pass / fail
Model list/fallback: pass / fail
Cancellation: pass / fail
Tool round trip: pass / fail / not supported
Notes (redacted):
```

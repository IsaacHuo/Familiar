# Familiar 工程状态与验证

## 1. 当前基线

- 分支：`main`
- 最低部署目标：iOS 18
- 设备族：iPhone
- Swift 语言模式：Swift 6
- 架构目标：arm64
- AnyDoc slices：iOS arm64、iOS Simulator arm64
- Intel Simulator：不支持

## 2. 已实现模块

### App Shell 与聊天

- 三步首启、无需 Key 的先浏览路径和设置内重新查看入口。
- 会话抽屉和边缘手势。
- 顶栏 Provider/模型选择。
- 用户与助手消息布局。
- 编辑、重试、复制和分享。
- 模型切换时间线记录。
- 流式富文本和滚动跟随。
- 简体中文和英文资源。

### Provider

- 12 个内置 Provider。
- 自定义 OpenAI-compatible 配置。
- OpenAI Chat adapter。
- Anthropic Messages adapter。
- Gemini Generate Content adapter。
- Keychain 分 Provider 保存。
- 模型列表与手动模型 ID。
- 模型能力 gate。

### Agent 与 EventKit

- 有限 Agent Loop 与统一 Runtime Event 流。
- 类型化 Capability Registry、Tool Router 与 Execution Policy。
- 本机时间和 App 信息工具。
- 日历查询和创建。
- 提醒事项查询和创建。
- 时间线确认卡。
- 确认协调 actor。
- Run ID + Tool Call ID 范围内的重复写入拦截。
- 可逆 EventKit 写入的单次 Undo。
- Run / Step 终态与检查点持久化。

### 文件与媒体

- 系统文件选择器。
- App 私有附件副本。
- AnyDoc 本地转换。
- PDFKit 文本层检查。
- Vision OCR。
- Quick Look 历史预览。
- 相机和 PhotosPicker 图片草稿。
- 图片发送 gate。
- Apple Speech 转写。

### 网站与文档

- Vue/Vite 官方网站。
- GitHub Pages workflow。
- 英文 README。
- 简体中文 README。
- 产品与工程 Docs。
- Agent Runtime 目标架构文档（六层架构、入口优先级、Capability Registry、Execution Policy、Native Workspace）。

### 系统入口

- 注册 `familiar://` URL Scheme。
- 类型化 Deep Link 支持新草稿、会话和 Run 三种本地入口。
- 新草稿仅预填、不自动发送；会话和 Run 仅恢复本地上下文。
- Deep Link 不能传入密钥、Provider 配置或工具授权，也不绕过 Execution Policy。
- 新增独立 Share Extension target，支持文本、网页 URL 和最多 3 个文件。
- Share Extension 与主 App 通过 App Group 一次性收件箱交接；主 App 仅在草稿为空且没有运行中请求时导入新草稿。
- 扩展不访问 Keychain、Provider、Agent Runtime 或原生写工具，共享内容不自动发送。

## 2.1 与目标架构的差距

项目按 iPhone-native Agent Runtime 方向演进。当前实现聚焦聊天与有限 EventKit 工具，尚未交付的架构部分：

- System Entry：App 内入口、Share Extension 和 Deep Link 已交付；系统通知、Widgets / Controls、Spotlight、App Intents、Shortcuts 尚未实现。
- Capability Registry：System Tools 仅 Calendar/Reminders；Workspace 仅 File/PDF/Text；Contacts、Photos、Maps、Location、Weather、Web 等未接入。
- Execution Policy：已覆盖能力可用性、权限请求、结构化写入确认和单次 Undo；App Intents 的一次性授权入口尚未实现。
- Run/Step 与 Task Timeline：已持久化运行终态和工具终态，并渲染运行、确认与工具记录；完整可恢复重放尚未实现。
- Runtime Event：已由 Agent Loop 发出统一事件流；后台恢复事件尚未实现。
- Memory 三层、Skills、Background（BGContinuedProcessingTask）与 MCP Client：未实现。
- 单 Agent First 已确立；多 Agent 明确不做。

## 3. 已执行验证

### 3.1 Swift 6 和 iPhone 构建

已执行并通过：

```text
Swift 6 Debug generic iOS signed build
Swift 6 Release generic iOS build
Swift 6 iOS 18 arm64 Simulator build
Swift 6 connected iPhone signed build
Default Xcode DerivedData clean iPhone build
```

当前 Runtime 基线额外验证：

```text
Debug iOS Simulator arm64 build
Release generic iOS arm64 unsigned build
```

Swift 6 并发修复覆盖：

- 确认请求值类型隔离。
- EventKit DTO 转换。
- EventKit reminder continuation。
- 相机 session worker。
- AttachmentStore FileManager。
- WebKit delegate callback。
- Speech isolated deinit。

### 3.2 AnyDoc

Rust/FFI fixture 已通过：

- Markdown。
- CSV。
- DOCX。
- PDF。
- 未知二进制拒绝。
- C ABI ownership/free。

### 3.3 网站

- Vite production build 通过。
- GitHub Pages workflow 通过。
- Pages deployment API 状态 success。

### 3.4 静态检查

已执行：

- `git diff --check`
- plist lint
- 本地化重复键检查

### 3.5 自动化测试

- 已建立 `FamiliarTests` 与 `FamiliarUITests` target。
- `FamiliarTests/FamiliarBaselineTests` 已在 iOS 26.5 arm64 Simulator 通过 15 项，覆盖 Provider catalog、SSE framing、Markdown CSP、Deep Link 解析与本地路由、Share Inbox 原子写入/文件副本/篡改路径拒绝及 AnyDoc 附件导入链路、附件路径边界、写入策略、Run/Step SwiftData 持久化、确认取消幂等与 V2 store 恢复删除范围。
- EventKit policy / action proposal 与 Agent Runtime 的多轮、事件顺序、最大轮次、上下文上限测试已实现；当前完整单元测试为 20 项、3 个套件通过。

## 4. SwiftData 启动问题

### 4.1 复现

真机旧安装启动时返回：

```text
NSCocoaErrorDomain 134110
Cannot migrate store in-place
FamiliarConversation.currentModelID missing mandatory destination value
```

旧地址：

```text
Application Support/default.store
```

### 4.2 处理

当前代码改用：

```text
Application Support/Familiar/Persistence/FamiliarAgentV2.store
```

流程：

1. 创建版本化 store。
2. 成功打开 `ModelContainer`。
3. 清理旧开发 store 和 sidecar。
4. 清理旧 store 对应附件。

### 4.3 验证状态

- 修改后的真机签名构建：已通过。
- 修改后的 iOS 18 arm64 Simulator 构建：已通过。
- 覆盖安装到保留旧 store 的真机：设备离线，未完成。
- iOS 26.5 Simulator 安装与冷启动 UI 冒烟：通过。

运行验收条件：

- 保留旧 `default.store` 安装新版本。
- App 启动进入首启或聊天界面。
- 无 SwiftData migration crash。
- 创建会话后生成 `FamiliarAgentV2.store`。
- 重新启动后会话可读取。

## 5. 待真实 Provider 验证

每个内置 Provider：

1. API Key 验证。
2. 一次文本流式回答。
3. 错误 Key。
4. 超时和取消。
5. 模型列表刷新或 curated fallback。

工具模型：

1. 一次真实 tool call。
2. 参数增量。
3. 工具结果回填。
4. 多轮结束。

协议 fixture：

- OpenAI-compatible SSE。
- Anthropic event stream。
- Gemini SSE。
- 工具调用增量和终止原因。

Provider fixture parser、Agent Runtime、EventKit policy 与附件路径已具备 iOS 测试覆盖。每个 Provider 的真实网络验证仍应在发布前完成。

## 6. 待真机验证

### EventKit

- full access 允许。
- 拒绝。
- restricted。
- 查询时间范围。
- 查询文字条件。
- 创建预览。
- 确认写入。
- 取消。
- 任务中止。
- 重复工具调用。
- 系统保存失败。

### 文件

- iCloud Drive 安全作用域文件。
- On My iPhone 文件。
- 25 MiB 边界。
- DOCX、PPTX、XLSX、ODT、RTF、EPUB、CSV。
- 文本 PDF。
- 扫描 PDF。
- 加密和损坏文档。
- 附件删除和重新预览。

### 相机和图片

- 相机权限。
- 前后镜头。
- 闪光灯。
- PhotosPicker 多选。
- 图片发送拦截。
- 拦截后文字和图片草稿保持。

### Speech

- Speech 权限。
- 麦克风权限。
- 中文转写。
- 设备端识别。
- 系统中断。
- App 失活停止。
- 无录音文件。

## 7. UI 验证矩阵

- iOS 18 和 iOS 26。
- Light 和 Dark。
- 简体中文和英文。
- Dynamic Type。
- VoiceOver。
- Reduce Motion。
- Reduce Transparency。
- 键盘交互。
- 抽屉边缘手势。
- 长回答和滚动稳定性。
- Markdown、代码、表格、引用、KaTeX、Mermaid。
- 复制、分享、编辑、重试。

## 8. 已知工程缺口

### 8.1 测试目标

已建立 iOS 单元测试和 UI 测试 target。关键纯逻辑已有 Provider fixture、Agent 重复调用/上下文上限、确认取消、EventKit action proposal、附件路径与 Run/Step 的基础覆盖。

仍应补充：

- 真实 Provider 端到端 smoke test 的可控测试入口。
- 附件导入、OCR 与消息附件清理的文件系统集成测试。

### 8.2 SwiftData 恢复界面

当前版本化 store 创建失败时会显示本地数据恢复界面，提供有限诊断信息。用户确认重建后，App 删除当前 V2 store、SQLite sidecar 和附件目录，保留 Keychain 中的 API Key，并提示用户重启。该删除范围已有临时目录单元测试覆盖。

仍需在真机覆盖磁盘空间不足、文件权限异常和损坏 store 的实际启动行为。

### 8.3 远程 Markdown 图片

已确定隐私优先策略。WebKit CSP 的 `img-src` 仅允许 Bundle 同源资源和 `data:`；渲染器在把清理后的 HTML 插入页面前，将 HTTPS 图片替换为来源链接。App 不会自动请求远程图片，用户主动点击后才由系统外部打开。CSP 边界已有单元测试，App 设置和官网隐私政策均已披露。

### 8.4 Share Extension

已建立独立扩展 target、App Group entitlement、严格类型/数量 activation rule 和共享收件箱。扩展接收文本、网页 URL 和最多 3 个文件，在临时目录完成复制与 manifest 写入后原子提交；主 App 校验 payload 后复用现有 AttachmentStore / AnyDoc 导入新草稿。草稿已有内容或请求运行中时不覆盖，继续排队等待安全时机。

扩展与主 App 的 Debug arm64 Simulator 编译及嵌入校验已通过，共享收件箱临时目录往返测试已通过；签名 Simulator 构建也已确认主 App 能解析 `group.com.isaachuo.familiar` 的共享容器。仍需在真实宿主 App 与实际设备签名环境验证 Notes、Safari、Files 等来源的分享、文件协调和生产 Provisioning；本轮不做人工视觉验收。

### 8.5 Deep Link 系统入口

已注册 `familiar://`，支持预填新草稿、打开本地会话和打开包含指定 Run 的本地会话。解析器拒绝非 Familiar scheme、认证信息、端口、fragment、未知路径和无效 UUID，并限制预填文本长度。入口不会自动发送消息或执行工具；当前请求执行中时会延后导航。

仍需在真机验证从 Notes、Safari、Shortcuts 等系统来源冷启动和回前台的行为。系统通知尚未实现；Run 入口当前定位到包含该 Run 的会话时间线，尚未提供精确滚动锚点。

### 8.6 孤儿附件

聊天容器出现时会根据 SwiftData 引用清理 Drafts 与 Messages 目录中的孤儿附件。仍需要在真实文件系统和大附件集合上验证清理时机与性能。

### 8.7 无障碍

代码级语义已补齐：抽屉当前会话带选中 trait；首启页码、快门和发送禁用原因有本地化描述；确认卡组合标题、目标与字段；运行中和终态工具记录读出状态与详情；新确认出现时通过 `AccessibilityFocusState` 转移 VoiceOver 焦点。

仍需真机完成 VoiceOver 全路径、焦点返回、极端 Dynamic Type、Increase Contrast 和 Bold Text 验收。

### 8.8 幂等范围

EventKit commit 幂等状态只存在于当前进程。系统 save 完成后进程立即终止的边界需要专项验证。

## 9. 发布前质量门槛

### 构建

- Debug generic iOS 通过。
- Release generic iOS 通过。
- iOS 18 arm64 Simulator 通过。
- 当前 Xcode 稳定版 Swift 6 警告清零。

### 数据

- 当前 store 首次创建和重启通过。
- 旧开发 store 切换通过。
- 会话、附件和工具终态重启后可读取。
- 删除会话后附件清理通过。

### Agent

- 未确认写操作零执行。
- 取消写操作零执行。
- 相同 run 的重复写入最多一次成功。
- 工具失败不显示成功状态。

### Provider

- 每个内置 Provider 至少一次真实文本流式冒烟。
- 标记工具能力的模型至少一次真实工具调用。
- 自定义 Base URL 行为符合设置说明。

### 隐私

- API Key 不出现在日志和普通存储。
- 图片 bytes 不进入请求。
- 原文件 bytes 不进入请求。
- Speech 和 EventKit 用途说明与调用一致。
- Markdown 远程图片不自动加载，策略在 App 与官网披露。

### App Store

- 隐私政策和支持页可访问。
- 用途说明完整。
- 无账户、订阅和无效入口。
- Provider 模型 ID 失效时界面可恢复。
- 真机主路径完成验收。

## 10. 文档更新触发条件

以下变更需要更新本文件：

- 新增构建或测试结果。
- Provider 真实冒烟结果。
- EventKit 真机结果。
- AnyDoc 真实文件结果。
- SwiftData 启动恢复结果。
- App Store 审核问题和解决方案。

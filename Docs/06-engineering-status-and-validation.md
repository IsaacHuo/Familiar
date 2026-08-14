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
- 自定义抽屉内的 Projects / Recent 层级、项目列表/详情/编辑、归档与项目内新聊天；仍复用单个长生命周期 ChatController。

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
- 类型化、启动时静态注册的 Capability Registry、Tool Router 与 Execution Policy。
- 本机时间和 App 信息工具。
- `web_search`、`web_fetch` 只读工具与回答来源记录。
- 日历查询和创建。
- 提醒事项查询和创建。
- 时间线确认卡。
- 确认协调 actor。
- Run ID + Tool Call ID 范围内的重复写入拦截。
- 可逆 EventKit 写入的单次 Undo。
- Run / Step 终态与摘要性检查点持久化；不能用于严格恢复或重放。

### 文件与媒体

- 系统文件选择器。
- App 私有附件副本。
- AnyDoc 本地转换。
- PDFKit 文本层检查。
- Vision OCR。
- Quick Look 历史预览。
- Project Resource 首版：独立受保护目录、SHA-256 文件/抽取文本 hash、版本 1 导入、Quick Look 和删除。
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
- 新增 `Ask Familiar`、`Process with Familiar`、`Open Familiar` 三项 App Intent 与双语 App Shortcut phrase；Ask / Process 只通过主 App handoff 启动现有发送链路，Open 不改变当前状态。
- App Intent 输入限制为 20,000 字符；未发送草稿不会被覆盖，工具写入仍由现有 Execution Policy 决定。
- 新增用户可选的 Run 结束本地通知；仅在 App 非活跃且 Run 完成或失败时安排，通知只显示通用状态并通过类型化路由返回本地 Run / 会话。
- 通知权限按需请求，拒绝后提供系统设置入口；关闭功能会清理 Familiar 待处理与已投递通知。未注册远程推送，也未引入后台执行保证。
- 新增受保护的 Core Spotlight 会话索引；仅索引已有内容会话的最多 80 字符标题、更新时间和本地 UUID，点击后复用现有会话 Deep Link。
- Spotlight 不索引消息正文、附件名、工具结果、密钥或 Provider 配置；重命名和删除通过当前完整会话集合刷新。
- 新增 Home/Lock Screen 启动 Widget 与控制中心 Control；Widget 复用 `familiar://new` 打开新草稿，Control 仅打开 Familiar，不执行发送或工具操作。

## 2.1 与目标架构的差距

项目按原生、安全、可检查的个人 AI 工作台方向演进。当前实现是具备 Agent Runtime 骨架的 iOS 原生原型，尚未交付的架构部分：

- System Entry：App 内入口、Share Extension、Deep Link、Run 终态本地通知、会话级 Spotlight 索引、Widget / Control、App Intents 与 App Shortcuts 已交付。
- Project / Workspace：Project、ProjectInstruction、Resource/Version、不可变 ContextSnapshot、Conversation/Run 可空项目归属和项目指令/资源注入已交付；Artifact、Binding、Memory、Resource 工具和可写 Workspace 未实现。
- Capability Registry：静态注册 8 个工具；Web Search/Fetch 已接入，Contacts、Photos、Maps、Location、Weather 未接入；运行时发现、安装、版本治理和项目绑定未实现。
- Execution Policy：已覆盖能力可用性、权限请求、结构化写入确认和进程内单次 Undo；生产路径没有 AuthorizationGrant，系统入口永不授予写权限。
- Run/Step 与 Task Timeline：已持久化运行终态、审批/模型摘要检查点、工具终态和不可变输入 ContextSnapshot 元数据/资源 hash 引用；缺少完整调用载荷、Authorization snapshot 与 ResumeCursor，完整恢复和重放尚未实现。
- Runtime Event：已由 Agent Loop 发出统一事件流；后台恢复事件尚未实现。
- Memory、Skills、MCP Client 与后台执行：未实现；`BGContinuedProcessingTask` 仅适用于 iOS 26+。
- 工程闭环：已新增 8 场景 fake-provider benchmark runner 与 arm64 Simulator iOS CI；本地基线通过，远程 GitHub Actions 首次结果待执行。
- SwiftData：V1/V2 定义保持冻结；当前 `FamiliarSchemaV3` 通过正式 V2→V3 轻量迁移新增 Resource/Version 与 ContextSnapshot/ResourceReference，旧 Attachment 的 ResourceVersion 关系迁移为空。
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
Debug iOS Simulator arm64 build-for-testing
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
- 既有记录显示 Baseline、EventKit policy/action proposal 与 Agent Runtime 测试曾在 arm64 Simulator 通过。
- 2026-08-14，`main @ f4ab809` 工作树使用 iOS 26.5 arm64 Simulator 运行 `FamiliarTests`：31 项通过、0 失败；其中 `FamiliarBenchmarkTests` 的 1 个参数化测试覆盖 8 条产品场景。
- 2026-08-14，WP2 focused migration tests 在 iOS 26.5 arm64 Simulator 通过 4 项、0 失败：旧直接 Schema 的完整 7 实体磁盘 store 通过 V1 migration plan 重开、关系与数据保持、测试内存容器版本化、可空关系轻量迁移演练、损坏 store 失败可观察且不自动删除。
- 2026-08-14，WP3 focused tests 在 iOS 26.5 arm64 Simulator 通过 10 项、0 失败；完整 `FamiliarTests` 通过 43 项、0 失败。覆盖真实磁盘 V1→V2 迁移、全部旧数据保持且旧 Conversation/Run 项目归属为空、项目字段与指令归一化、8,000 字符项目指令进入 Runtime、归档/取消归档、空项目删除、普通/项目聊天归属、Run 启动时项目固化和项目会话 Deep Link。
- 2026-08-14，WP4 focused tests 通过 21 项、0 失败；完整测试通过 51 项、0 失败。覆盖真实磁盘 V1/V2→V3、旧附件可空关系、资源路径/hash/symlink/删除、两条项目会话共享资源、消息删除不影响资源、确定性上下文/精确工具清单/预算拒绝、失败和取消 Run snapshot 保留、项目删除脱离历史会话/Run 并清理资源文件。
- 8 条 Benchmark 全部通过：Calendar read、Reminder write、图片发送 gate、PDF 问答、PDF + Calendar、Weather capability gate、Web + Reminder、Tool failure recovery。
- Benchmark 日志逐场景记录模型轮数、工具/审批序列、终态、耗时和 `usage=unavailable`；不需要真实 API Key 或真实网络。
- 同一 test products 上运行 `FamiliarColdLaunchUITests.testColdLaunchShowsOnboardingOrChatShell`：1 项通过、0 失败。

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

1. 使用 `FamiliarSchemaV1`、`FamiliarSchemaMigrationPlan` 和原文件名创建或迁移 store。
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
- 项目资源从 iCloud Drive / On My iPhone 导入、Quick Look、OCR 标记和删除。
- 同一资源在两条项目对话中使用，重启后版本/hash 保持。
- 项目删除后历史聊天仍可打开且资源目录不可恢复；运行中 Run 时删除按钮禁用。

### WP1–WP4 真机验收清单

- WP1：抽屉、设置、Run timeline 与工具清单在中英文、VoiceOver 和极端 Dynamic Type 下可操作。
- WP2：保留 V1/V2 真实旧 store 覆盖安装，确认自动迁移、重启读取和迁移失败恢复界面不静默删数据。
- WP3：创建/编辑/归档项目，创建普通与项目聊天，确认项目指令只进入项目聊天；历史 Run 项目归属符合启动时快照。
- WP4：导入文本 PDF、扫描 PDF 和至少一种 Office 文档，确认进度、OCR、Quick Look、文件保护、两条项目聊天共享资料及超预算提示。
- WP4：删除单条消息不删除资源；删除资源后预览不可用；删除项目后聊天/历史 Run 保留并脱离，资源与指令删除；运行中 Run 阻止项目删除。
- WP4：断网/取消/模型失败后 Run ContextSnapshot 元数据和资源 hash 引用仍可读取，且记录中没有完整资源抽取文本。

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
- 8 个产品场景的 fake-provider benchmark runner，记录工具序列、审批、耗时和成本。
- Web URL policy、parser、Source persistence 与受控网络 smoke 的持续覆盖。

### 8.2 iOS CI

已新增 `.github/workflows/ios.yml`，在 arm64 `macos-26` runner 上分别执行 Simulator build、`FamiliarTests`（含 Benchmark）和 UI cold-launch smoke。构建显式使用 `ARCHS=arm64`，与 AnyDoc XCFramework slice 一致。workflow YAML 已完成本地解析；远程 GitHub Actions 尚未触发，不能记录为已通过。

### 8.3 SwiftData 恢复界面

当前版本化 store 创建失败时会显示本地数据恢复界面，提供有限诊断信息。用户确认重建后，App 删除当前 V2 store、SQLite sidecar 和附件目录，保留 Keychain 中的 API Key，并提示用户重启。该删除范围已有临时目录单元测试覆盖。

仍需在真机覆盖磁盘空间不足、文件权限异常和损坏 store 的实际启动行为。

### 8.4 远程 Markdown 图片

已确定隐私优先策略。WebKit CSP 的 `img-src` 仅允许 Bundle 同源资源和 `data:`；渲染器在把清理后的 HTML 插入页面前，将 HTTPS 图片替换为来源链接。App 不会自动请求远程图片，用户主动点击后才由系统外部打开。CSP 边界已有单元测试，App 设置和官网隐私政策均已披露。

### 8.5 Share Extension

已建立独立扩展 target、App Group entitlement、严格类型/数量 activation rule 和共享收件箱。扩展接收文本、网页 URL 和最多 3 个文件，在临时目录完成复制与 manifest 写入后原子提交；主 App 校验 payload 后复用现有 AttachmentStore / AnyDoc 导入新草稿。草稿已有内容或请求运行中时不覆盖，继续排队等待安全时机。

扩展与主 App 的 Debug arm64 Simulator 编译及嵌入校验已通过，共享收件箱临时目录往返测试已通过；签名 Simulator 构建也已确认主 App 能解析 `group.com.isaachuo.familiar` 的共享容器。仍需在真实宿主 App 与实际设备签名环境验证 Notes、Safari、Files 等来源的分享、文件协调和生产 Provisioning；本轮不做人工视觉验收。

### 8.6 Deep Link 系统入口

已注册 `familiar://`，支持预填新草稿、打开本地会话和打开包含指定 Run 的本地会话。解析器拒绝非 Familiar scheme、认证信息、端口、fragment、未知路径和无效 UUID，并限制预填文本长度。入口不会自动发送消息或执行工具；当前请求执行中时会延后导航。

仍需在真机验证从 Notes、Safari、Shortcuts 等系统来源冷启动和回前台的行为。Run 入口当前定位到包含该 Run 的会话时间线，尚未提供精确滚动锚点。

### 8.7 App Intents / Shortcuts

已实现 `Ask Familiar`、`Process with Familiar`、`Open Familiar` 与 3 项 App Shortcut。Ask 接收问题，Process 支持接收上一步 Shortcut 的文本输出，两者通过 `FamiliarAppIntentHandoff` 进入主 App 并调用现有 `FamiliarChatController.startSending`；Open 只打开 App。系统提取产物已确认包含 3 项 discoverable Intent、3 项 Shortcut，以及英语和简体中文 NLU phrase。iOS 18–25 使用 `openAppWhenRun`，iOS 26+ 使用 `supportedModes = .foreground`。

App Intent handoff 与 20,000 字符边界已有单元测试。当前运行中请求会先完成；已有未发送草稿时保留草稿并拒绝本次入口。仍需在真机的 Siri、Shortcuts、Spotlight 与 Action Button 上完成冷启动、后台唤起、语音参数解析和实际 Provider 请求验收；本轮不做人工视觉检查。

### 8.8 Run 终态本地通知

已实现设置内显式开关、按需权限请求、拒绝后的系统设置恢复入口，以及完成 / 失败两类本地通知。通知只在 App 非活跃时安排，正文使用固定通用文案，不包含问题、回答、附件名或工具结果；payload 只保存本地 Run / 会话 UUID。点击通知复用现有 `FamiliarAppIntentHandoff` 与 `FamiliarDeepLink` 返回对应上下文，前台到达时不重复展示横幅。关闭开关会移除 Familiar 的待处理与已投递通知。

类型化通知路由及 `userInfo` 解析已有单元测试。仍需在真机验证权限弹窗、系统设置恢复、锁屏呈现、完成 / 失败投递、冷启动点击和目标已删除时的恢复行为。当前没有后台 Run 承接；iOS 26+ 的 `BGContinuedProcessingTask` 也未接入。因此通知只报告当前进程实际到达的终态，不保证 App 被系统挂起后 Run 仍会完成；本轮不做人工视觉检查。

### 8.9 Spotlight 会话索引

已实现 Core Spotlight 自定义索引和系统结果回流。索引指定 `.complete` 文件保护等级，只纳入已有消息或 Run 的会话；每项只含最多 80 字符标题、更新时间、Familiar 关键词和 `conversation:<UUID>`，不含消息正文、附件名、工具结果、Run 详情、密钥或 Provider 配置。聊天界面根据当前 SwiftData 集合触发整域刷新，索引 actor 串行合并连续更新；重命名和删除不会保留历史结果。用户点击系统结果后，`CSSearchableItemActionType` 复用现有 Deep Link 选择本地会话。

Spotlight item 元数据边界、严格标识解析和 `NSUserActivity` 路由已有单元测试。仍需在真机验证系统索引延迟、中英文查询、设备锁定后的数据保护、冷启动点击、重命名和删除后的结果刷新；本轮不做人工视觉检查。

### 8.10 Widgets / Controls

已建立独立 `FamiliarWidgets` extension target，并嵌入主 App。Home/Lock Screen Widget 支持主屏幕小号、中号及锁屏圆形、矩形样式，通过现有 `familiar://new` 路由打开新草稿；控制中心 Control 使用 `OpenIntent` 打开 Familiar。两者均不携带 Provider 配置、授权或自动发送行为，英语和简体中文资源已提供。

Widget target 与主 App 的 Debug arm64 Simulator 编译及嵌入校验已通过。仍需在真机验证 Widget Gallery 展示、主屏幕和锁屏启动、控制中心注册、冷启动与已有未发送草稿时的保护行为。

### 8.11 孤儿附件

聊天容器出现时会根据 SwiftData 引用清理 Drafts 与 Messages 目录中的孤儿附件。仍需要在真实文件系统和大附件集合上验证清理时机与性能。

### 8.12 无障碍

代码级语义已补齐：抽屉当前会话带选中 trait；首启页码、快门和发送禁用原因有本地化描述；确认卡组合标题、目标与字段；运行中和终态工具记录读出状态与详情；新确认出现时通过 `AccessibilityFocusState` 转移 VoiceOver 焦点。

仍需真机完成 VoiceOver 全路径、焦点返回、极端 Dynamic Type、Increase Contrast 和 Bold Text 验收。

### 8.13 幂等范围

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
- Project Schema 合入前从现有 V1 增加新 VersionedSchema 和 migration stage，并提供 Resource 文件迁移/回滚方案。

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

# Architecture

最后核对：2026-10-17（普通对话/项目分离、抽屉/顶栏、S2a 静态核对；运行验收独立）

本文只描述代码现状。设计目标见 `docs/`，切片与验收见根目录 `PLAN.md`。静态核对不代表 Simulator 或真机验收。

## 1. 技术基线

| 领域 | 现状 |
|---|---|
| UI | SwiftUI；Swift 6.0；app target `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`；iPhone only |
| 部署目标 | iOS 26.0（全部 iOS target）；`FamiliarMac` 为 macOS 26.0 |
| 数据 | SwiftData。唯一当前 `FamiliarReleaseSchema` 5.0.0，37 个实体；无历史迁移链、Artifact/Grant 迁移模型。现有 V3/V5…源文件只组织当前实体定义，不参与磁盘迁移。无 CloudKit |
| Store | `<Application Support>/Familiar/Persistence/<storeName>.store`，`.completeUntilFirstUserAuthentication`；文件名由 `FamiliarStoreProfile` 决定 |
| 模型网络 | URLSession。`.openAIChat` → `FamiliarOpenAICompatibleModelProvider`；Anthropic/Gemini/OpenAI Responses → `FamiliarStructuredModelProvider`；模型分组 → `FamiliarGroupModelProvider`；Kimi/Codex 由 OAuth Provider 包装 |
| Web | 搜索：ephemeral URLSession，DuckDuckGo/Bing/Brave/Tavily/Exa（UI 可见 DDG/Bing/Tavily）。抓取：Network.framework 自研受限 HTTP/1.1 客户端 + DNS 解析 + URL 策略 |
| 渲染 | 非持久 WKWebView：markdown-it、highlight.js、KaTeX、Mermaid、DOMPurify；终端为 xterm.js |
| Keychain | `FamiliarKeychainStore`、`FamiliarSearchKeychainStore`、`FamiliarOAuthCredentialStore` |
| 原生框架 | EventKit、Contacts、CoreLocation、MapKit、WeatherKit、HealthKit、MusicKit、Photos、CoreBluetooth、NaturalLanguage、UserNotifications、AlarmKit（26.1 门控）、CoreSpotlight、AppIntents、LocalAuthentication、Speech、AVFoundation、Vision、PDFKit、QuickLook、Charts |
| 文档转换 | AnyDoc Rust 引擎 `Vendor/AnyDocBridge.xcframework` |
| iSH guest | `Vendor/ISHRuntime/FamiliarISHRuntime.xcframework`（arm64 device + arm64 simulator）；内置 `alpine-3.24.0-aarch64-fakefs.tar.gz`（55.0 MiB，预装 python3/py3-pip/py3-lxml/py3-pillow、python-docx/openpyxl/python-pptx/fpdf2/pypdf/markdown 与 Noto Sans SC 子集）；`#if canImport(FamiliarISHRuntime)` 门控 |
| SPM | SwiftSoup 2.13.7（Familiar）、containerization 0.33.4（仅 FamiliarMac）；本地 ZIPFoundation、Yams |
| Entitlements | WeatherKit、HealthKit、App Group `group.com.isaachuo.familiar` |

## 2. Targets

- `Familiar`：iOS app，嵌入 ShareExtension 与 Widgets。
- `FamiliarMac`：macOS app，链接 Containerization。
- `FamiliarShareExtension`、`FamiliarWidgets`：appex。
- `FamiliarTests`（Swift Testing + XCTest）、`FamiliarUITests`。
- `Shared/`：`FamiliarSharedInbox`（App Group 收件箱）、`FamiliarControlIntent`。

## 3. App 入口与依赖注入

- `FamiliarApp`（`@main`）创建依赖；首次检测到业务代际非 `5-work-scopes`，清理旧 store、附件、资料、Files、Workspace、ShellRuntime、Skill 包、共享收件箱和派生索引，当前容器打开成功后写代际标记。Keychain、模型/搜索设置和外观偏好不清理。已完成代际的普通打开失败进入恢复页，不再次清空。
- `FamiliarAppDependencies`（`@MainActor`）持有 ToolRegistry、ExecutionPolicy、确认/澄清 coordinator、UndoStore、原生服务、`FamiliarWebSearchService`、`FamiliarWorkspaceStore`、Python 包源设置、`FamiliarShellRuntimeStatus`、`FamiliarVisionProcessor`。registry 在 init 中一次构建；iSH 资源存在时追加 `shell_execute`/`environment_prepare`。主界面出现后 `FamiliarRootView` 触发 `prewarmShellRuntime()`：后台低优先级、共享 flight、幂等，失败静默由下次调用或设置页 Retry 重试。
- `makeRuntime(for:...)` 把 `FamiliarProviderFactory.makeProvider` 结果与 registry、policy、coordinator、授权、persist/willCommit 回调注入唯一的 `FamiliarAgentLoop`。

## 4. 模块清单

| 目录 | 主要文件与职责 |
|---|---|
| `Agent/` | `FamiliarAgentLoop`（唯一模型/工具循环、deadline、重试、两路并行只读、串行审批与写入、tools_load、runFinished）；`FamiliarTool`/`ToolContract`/`ToolSchema`（协议、manifest、envelope、registry）；`FamiliarExecutionPolicy`；`AuthorizationContract`/`CapabilityContract`；确认与澄清 coordinator；`ToolGroups`/`ToolLoader`（工具组、默认启用、懒加载）；`RunState`/`WebEvidenceState`；`ModelProvider`/`RuntimeError`；`NativeTools`/`PresentationTools`；`Hash`/`ISO8601` |
| `Context/` | `FamiliarContextCompiler`（seed、snapshot、assemble、validateSubmission）；`FamiliarContextCompilation`（逐请求编译与压缩） |
| `Persistence/` | `FamiliarModels`（容器）、当前 schema 与业务代际重置、File 记录、`FamiliarAuthorizationRuntime`、Run 记录与恢复、`FamiliarProjectService`（能力过滤）、Pin |
| `Files/` `Workspace/` `AnyDoc/` `Attachments/` | File/FileVersion 存储与校验器、file_* 工具、导入与托管存储；Workspace 目录与 workspace_* 工具；AnyDoc 转换；附件草稿/提交、图片 JPEG、PDF OCR、共享收件箱导入 |
| `Data/` `Providers/` `Domain/` | Provider 适配、Factory 与凭据判断、实例与目录、Keychain；模型分组；OAuth（Kimi/Codex）；领域值类型 |
| `Web/` | `FamiliarWebTools`、`FamiliarWebSearchService`、`FamiliarSearchProvider(+Adapters)`、`FamiliarWebContentService`（SwiftSoup 正文）、`FamiliarRestrictedHTTPClient`、DNS、URL 策略、`FamiliarWebModels` |
| `Shell/` | `FamiliarShellTool`（shell_execute、environment_*）、`FamiliarShellPolicy`、`FamiliarShellExecutor`、`FamiliarISHShellExecutor`、`FamiliarISHPreparation`、`FamiliarContainerShellExecutor`（Mac）、Terminal 事件 |
| `Native/` `EventKit/` | Map/Weather、NaturalLanguage/Health/Music、Bluetooth、Contacts/Location/Clipboard/Share、Alarm、Photos 保存与文件导出；日历/提醒工具 |
| `MCP/` `Memory/` `Skills/` | HTTP MCP client 与服务；Memory 服务与工具；Skill 服务与包安装（Yams/ZIPFoundation） |
| `Presentation/` | `FamiliarChatController`、`Presentation/Chat/`（Timeline、Row、Turn、Runtime、Records、VisualFixture 六个文件）、`Presentation/Settings/`（Hub、Capability、Personalization、Privacy、RunHistory、RunRecord、About、ModelService 八个文件）、InputDock/Composer/Scroll、Markdown WebView 与流式节奏、ApprovalCard、活动投影与 Surface、Provider 品牌图标、Projects/Files、Terminal、Web 呈现、Debug 测试场景 |
| `Support/` | `FamiliarTheme`（颜色、字体、间距、圆角、按钮、glass）、`FamiliarMarkdownStyle`、`FamiliarMotion`（含 Haptics） |
| 其他 | `Security/FamiliarAppLock`、`SystemEntry/`（AppIntents、Notifications、Spotlight）、`Speech/`、`Vision/FamiliarVisionProcessor`、`AI/Models/`（无生产路由入口）、`Resources/` |

## 5. 关键数据流

1. 发送：`FamiliarChatController.startSending` 冻结输入，解析可选 Project 的有效设置或全局默认与凭据，生成本 Run registry、过滤能力、生成 MCP 延迟组，`ContextCompiler.assemble` + `validateSubmission`；模型不支持图片时先跑 Vision 再重编。草稿未变才写入 Conversation/Message/附件，然后 `performSend`。
2. 运行：`makeRuntime` 后遍历 `agentLoop.stream` 事件；Recorder 记录选择、用量、阶段、响应块；`FamiliarSurfaceStore.affectsPresentation` 过滤 UI 更新。
3. 工具：只执行当前请求暴露的工具。preflight → `Policy.evaluate` → 需审批则挂起 → revalidate → `willCommit` journal → 执行 → `persistResult`（失败 rollback）。
4. 懒加载：首轮基础为 `current_date_time`、`ask_user`、`tools_load`，另有经 Project/Skill/availability 过滤的 `web_search`、`web_fetch`；一次最多 2 组，替换下一轮扩展集合。默认启用 web、calendar、places、files、memory、device；`workspace_write`、`file_publish`、shell、presentation 默认关闭。
5. Web：搜索保留引擎排名并去 URL 重复；查询文本不做国家拼接，DDG 固定全球区域，Bing 不按语言设置 market，Tavily 不发送 country/language 限定；Context 提示按来源选择语言、不得从中文/时区/Provider 所在地推断地域；工具按实际结果数量请求，Run 缓存按 Provider/语言/时效/数量/规范化 query 隔离。搜索重试、DDG 形态切换与网络/5xx 降级共用 24 秒预算（工具上限 25 秒），有 Key 首选阶段最多 12 秒；认证/额度/限流/解析错误直接报告。抓取经 URL 策略、DNS、受限 HTTP、压缩/字符解码和 SwiftSoup 抽取。Run 缓存只保留成功证据；已观测请求 URL 与最终 URL 共享首份捕获。工具事件保留引用别名，最终 Message/Markdown blocks 保存时统一引用并去重来源；Sheet 只列实际引用来源。二者 read/sensitive，不自动创建长期 File。
5a. 搜索设置：feature-local `@Observable` 编辑状态以原 Provider 保存草稿；写入与重读成功后才能验证，验证绑定服务与凭据版本。编辑、切换、删除、离开均使旧验证失效；保存失败保留草稿并阻止切换。
6. Shell/iSH：`.documents` 组（shell_execute/environment_prepare/environment_status/file_publish）默认启用，取代原 shell 组；`shell_execute` manifest 为 reversibleWrite/high；`FamiliarShellPolicy` 决定 deny/确认/风险；首次使用经 `FamiliarISHPreparation` 共享准备（可被启动后预热提前完成），限定 Workspace；未就绪时工具活动行报告“正在准备运行环境”。依赖安装仅 `environment_prepare`（配置软件源、Swift 构造的声明式命令）。
7. 文件输出：file_write/edit 只写 Markdown/文本，每次新 FileVersion；复杂格式（DOCX/XLSX/PPTX/PDF）先写 Workspace `Outputs/`，经 `file_publish` 校验后登记。Shell 成功后的 Outputs 变更会被捕获登记并 best-effort 解析（已知格式经 `FamiliarFileValidator.extract` 存 extractedText；失败仍登记并在 provenance 标注 `validation.state=failed`）。
8. 呈现：工具结果只有四种呈现——活动行（点击打开 Sheet，承载 receipt、records、Shell 输出与逐活动技术详情）、行内引用 + 来源 Sheet、统一文件卡（含 prepare_file_export 与失效文件）、输入区审批/澄清。`FamiliarToolPresentationPayload` 只保留 scalar/searchResults/document/recordCollection/mutationReceipt/fileMutation/shellExecution（schemaVersion 4）；task_plan/present_recommendation/present_insight/prepare_share 工具与 diff/code/contextMatches/taskList/recommendation/insight/shareDraft 呈现已移除；写入 receipt 折入活动行并在行上提供 Undo。侧栏为原生 List（新对话/搜索/Pinned/Projects/最近普通对话/设置），省略号菜单精简，Composer 添加菜单为原生 Menu。

## 6. 授权现状

`FamiliarExecutionPolicy.evaluate` 拒绝不可用、preflight deny、缺少必要 scope、Skill 越界或 effect 不一致的调用。普通只读自动执行。第 2 级本地写入在撤销真实存在时自动执行并保留回执与撤销：内置 file_write/edit/publish、workspace_write、memory_remember（记忆开关开启时，控制器按 provenance 删除对应行）、从配置软件源发起的 environment_prepare（保留旧环境目录作为会话 Undo 目标，撤销回滚目录与 receipt 元数据）、经 Swift 命令检查与写入前 checkpoint 的离线 shell_execute。第 3 级外部影响（EventKit 创建/更新、通知、剪贴板写入、保存相册、alarm_schedule、skill_install、已信任 MCP）首次询问，卡片默认「始终允许此类」；`.always` 规则按 scopeKey + capabilityID + capabilityVersion 匹配，不绑定参数 hash 或 targetKey。删除、alarm_cancel 与未信任 MCP 每次询问且不产生持久授权。MCP 信任是按服务器的用户设置（UserDefaults，默认未信任，设置页可撤销，删除服务器清除）。执行前复核、journal、防重放、保存失败补偿和真实回执保留。撤销仅在当前聊天和其当前 scope 与原 Run scope 一致时显示/执行。

AuthorizationRuleRecord 使用完整 scopeKey，`.once` 10 分钟、`.session` 绑定会话且要求精确参数、`.always` 为能力级并 365 天有效。nil scope 不能持久授权。同 UUID 的 Project/Conversation 互不匹配；移动聊天不会携带旧授权。

`clipboard_read` 返回只读结果，只触发系统粘贴许可。`environment_prepare` 的已就绪路径返回专用 `.unchanged`，不走写审批、journal 或 Undo；普通写工具仍不得返回只读 `.result`。

## 7. 普通对话、项目与文件生命周期

- 普通对话 `project == nil`，启动和新建均不创建默认项目。草稿预分配稳定 Conversation UUID，发送校验并保存成功后才提交聊天和附件；取消/失败保留草稿。
- `FamiliarWorkScope.project(UUID)` / `.conversation(UUID)` 统一 File/FileVersion、Workspace、Environment、工具上下文、授权；scopeKey 包含类型，字节路径使用 `Scopes/<kind-id>/`。普通对话只取自己的 Files、会话记忆及显式 global Memory；项目保留共享指令、资料、设置与项目记忆。
- 普通对话删除时清理其 Files、附件目录、Workspace、环境元数据、会话记忆与授权；项目聊天删除仅解除 File 关联，项目文件保留。
- 移动聊天先复制关联文件及各版本、重新绑定附件，保留历史 FileVersion 标识到新版本的显式 provenance；清摘要，清旧普通范围授权/环境并清理原字节。删除项目先为各聊天复制关联文件，再将聊天转普通并清项目专属数据。
- 抽屉分置顶、项目、日常对话。项目重新打开默认折叠；展开只取未单独置顶的最近 5 条（updatedAt 降序、ID 稳定排序），更多打开完整列表。普通对话取最近 20 条并提供完整列表；搜索有普通/项目范围。
- 顶栏删除文件夹切换入口；独立玻璃省略号菜单仅在项目聊天包含一个项目详情入口。项目切换和所有项目来自侧栏，新对话继承当前可选 Project。

# Architecture

最后核对：2026-10-28（审核输入框初始化／天气署名；设备证据独立）

本文只描述代码现状。设计目标见 `docs/`，切片与验收见根目录 `PLAN.md`。静态核对不代表 Simulator 或真机验收。

## 1. 技术基线

| 领域 | 现状 |
|---|---|
| UI | SwiftUI；Swift 6.0；app target `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`；iPhone only |
| 部署目标 | iOS 26.0（全部 iOS target）；`FamiliarMac` 为 macOS 26.0 |
| 数据 | SwiftData。唯一当前 `FamiliarReleaseSchema` 5.0.0，39 个实体；无历史迁移链、Artifact/Grant 迁移模型。现有 V3/V5…源文件只组织当前实体定义，不参与磁盘迁移。无 CloudKit |
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

## 3. App与呈现边界

- FamiliarAppShell拥有文件／聊天／设置三个原生Tab与独立导航，默认聊天；详情隐藏Tab。FamiliarChatRoute以稳定身份表达会话、草稿、归档、项目和消息定位。旧frozenDrawerSurface仍编译但生产不挂载，不作为当前导航方案。
- ChatSessionCoordinator持有会话／草稿控制器，浏览路由与正在执行会话分开；ForegroundExecution串行占用Agent、压缩和润色。闲置额外最多两份会话保存后释放，最多128条轻量阅读书签不持有渲染器。
- ChatsHome生成轻量列表快照；ConversationList封装UICollectionView/diffable/UIHostingConfiguration。分类与分页共用选择并各自保存位置，预览只取最近三条，不创建Runtime、不改草稿或已读。首页搜索已改为本页原生searchable与结果覆盖层，取消保留分类／列表，查询观察隔离在修饰器；原生折叠手感与精确Telegram阈值的差异待设备。
- LocalSearchStore为只读ModelActor；本地标题／正文查询200ms防抖、取消／generation保护、每页50条。会话查找用稳定消息ID；原生高亮／Web非命中层保留正文和手势。
- ChatHistoryStore分轻量身份索引、按ID最多80项富数据窗口、完整业务消息和最新AI回复；完整发送／编辑前缀／压缩／分支／导出不依赖UI页。页原子发布，呈现UUID隔离几何／退场／Web补偿；索引仍线性，单Run回执完整，未测SQL／内存上限。
- FamiliarChatAppearance集中Classic/Night消息颜色、气泡掩码、16/8pt邻接圆角、原图案与静态MeshGradient背景；布局使用窄屏减36pt／宽屏85%，辅助字号保留0.98适配。用户／AI／列表预览／文件共用显式capInsets背景，1pt中心拉伸保持边角，Run不合并。ChatView原生标题显示会话／真实模型。
- ComposerTextView为UITextView薄封装，共享正文／占位测量、marked-text保护、UTF16选区、六行后内部滚动。SendPresentation仅在消息持久化成功后登记ID并播放一次有界快照，过期／离场释放；几何／帧不入数据库。
- MessageInteraction在真实UITextView/WKWebView安装菜单；菜单实例、消息／块／原文／动作资格及选择代次隔离迟到回调，选择互斥且接阅读检查。SelectedTextSink冻结消息／块／会话身份，菜单退场后追加草稿；审批／澄清占用时不回填。编辑草稿含进入前备份，取消不删历史，完整新回复保存后同事务替换旧尾部。
- 附件准备按附件ID／尝试UUID串行，真实草稿身份挡晚到回调。ThumbnailLoader共享请求／后台降采样，缓存24MiB/120项为成本提示；图片消息由有界Layout视口共同承载裁切／源锚；MessageAttachmentPresentation共享聊天／预览的排序、邻接及时间归属，FileTile无onOpen时只读且无分享，独立末尾AI文件回执内置完成时间；ImageGallery仅当前与邻页，当前图ID决定退出源；文档QuickLook保留准确版本／scope／URL/CSP。
- SettingsCatalog统一路由和搜索；ProviderEditor验证身份绑定配置／模型／凭据；Memory显示真实归属。StorageInventory后台统计可取消／标记不完整，不自动清理。Run详情使用精确responseMessageID，摘要与技术上下文按需展开。
- 本机资料为UserDefaults编码数据，不是账户。ProfileHeaderMotion在页级UIKit层隔离滚动，使用原遮罩关键帧；润色复用用户Provider、tools=[]及草稿版本保护，完整结果才应用，非Agent且不自动发送。
- 完成的普通AI段落按内容结构走原生文本（含多行／长文），Markdown／链接／来源仍用WebKit。TextAndTimeLayout以实际字号／末行测量并按文本、字号、宽度和时间尺寸缓存，同一宽度提案用于测量／放置；原生messageActions保留完整回复与blockID。预览复用生产宽度／时间但不挂载交互。
- WK原生交接时停止加载并解绑delegate，脚本／渲染回调核对原WebView身份；延迟阅读补偿不能写入新实例。Markdown资源在本地非持久WebKit，主题JSON只缓存有限外观／字号／对比度输入。SwiftUI可见性已读记录不参与布局状态；交互返回开始暂停补偿，取消后按身份恢复。卡死修正版设备复验仍开放。

## 4. 模块清单

审核修复：Composer 与原生消息 UITextView 使用显式 TextKit 1 对象图和具体子类指定初始化器。`FamiliarWeatherAttribution` 从成功 weather_forecast/weather_history 的既有 resultEnvelope.modelContent 读取法律 URL，聊天与记录详情共用原生署名视图；没有新存储实体或 Runtime 事件。健康审批与只读范围未变。

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
| `Presentation/` | `FamiliarChatController`、`Presentation/Chat/`（时间线、消息、交互、草稿、窗口与生命周期）、`Presentation/Settings/`（目录、模型、能力、资料、隐私、运行记录与设置页）、`Presentation/Files/`（Files 列表与文件详情）、InputDock/Composer/Scroll、Markdown WebView 与流式节奏、ApprovalCard、活动投影与 Surface、Provider 品牌图标、Projects/Files、Terminal、Web 呈现、Debug 测试场景 |
| `Support/` | `FamiliarTheme`（颜色、字体、间距、圆角、按钮、glass）、`FamiliarMarkdownStyle`、`FamiliarMotion`（含 Haptics） |
| 其他 | `Security/FamiliarAppLock`、`SystemEntry/`（AppIntents、Notifications、Spotlight）、`Speech/`、`Vision/FamiliarVisionProcessor`、`AI/Models/`（无生产路由入口）、`Resources/` |

## 5. 关键数据流

1. 发送：`FamiliarChatController.startSending` 冻结输入，解析可选 Project 的有效设置或全局默认与凭据，生成本 Run registry、过滤能力、生成 MCP 延迟组，`ContextCompiler.assemble` + `validateSubmission`；模型不支持图片时先跑 Vision 再重编。草稿未变才写入 Conversation/Message/附件，然后 `performSend`。
2. 运行：`makeRuntime` 后遍历 `agentLoop.stream` 事件；Recorder 记录选择、用量、阶段、响应块；`FamiliarSurfaceStore.affectsPresentation` 过滤 UI 更新。
3. 工具：只执行当前请求暴露的工具。preflight → `Policy.evaluate` → 需审批则挂起 → revalidate → `willCommit` journal → 执行 → `persistResult`（失败 rollback）。
4. 懒加载：首轮基础为 `current_date_time`、`ask_user`、`tools_load`，另有经 Project/Skill/availability 过滤的 `web_search`、`web_fetch`；一次最多 2 组，替换下一轮扩展集合。默认启用base、web、calendar、places、files、memory、device、documents及skill_list/read；workspace_write默认关闭，skill_install仍需显式启用／审批。旧shell／presentation组不在当前枚举中。
5. Web：搜索保留引擎排名并去 URL 重复；查询文本不做国家拼接，DDG 固定全球区域，Bing 不按语言设置 market，Tavily 不发送 country/language 限定；Context 提示按来源选择语言、不得从中文/时区/Provider 所在地推断地域；工具按实际结果数量请求，Run 缓存按 Provider/语言/时效/数量/规范化 query 隔离。搜索重试、DDG 形态切换与网络/5xx 降级共用 24 秒预算（工具上限 25 秒），有 Key 首选阶段最多 12 秒；认证/额度/限流/解析错误直接报告。抓取经 URL 策略、DNS、受限 HTTP、压缩/字符解码和 SwiftSoup 抽取。Run 缓存只保留成功证据；已观测请求 URL 与最终 URL 共享首份捕获。工具事件保留引用别名，最终 Message/Markdown blocks 保存时统一引用并去重来源；Sheet 只列实际引用来源。二者 read/sensitive，不自动创建长期 File。
5a. 搜索设置：feature-local `@Observable` 编辑状态以原 Provider 保存草稿；写入与重读成功后才能验证，验证绑定服务与凭据版本。编辑、切换、删除、离开均使旧验证失效；保存失败保留草稿并阻止切换。
6. Shell/iSH：`.documents` 组（shell_execute/environment_prepare/environment_status/file_publish）默认启用，取代原 shell 组；`shell_execute` manifest 为 reversibleWrite/high；`FamiliarShellPolicy` 决定 deny/确认/风险；首次使用经 `FamiliarISHPreparation` 共享准备（可被启动后预热提前完成），限定 Workspace；未就绪时工具活动行报告“正在准备运行环境”。依赖安装仅 `environment_prepare`（配置软件源、Swift 构造的声明式命令）。
7. 文件输出：file_write/edit 只写 Markdown/文本，每次新 FileVersion；复杂格式（DOCX/XLSX/PPTX/PDF）先写 Workspace `Outputs/`，经 `file_publish` 校验后登记。Shell 成功后的 Outputs 变更会被捕获登记并 best-effort 解析（已知格式经 `FamiliarFileValidator.extract` 存 extractedText；失败仍登记并在 provenance 标注 `validation.state=failed`）。
8. 呈现：工具结果只有四种呈现——活动行（点击打开 Sheet，承载 receipt、records、Shell 输出与逐活动技术详情）、行内引用 + 来源 Sheet、统一文件卡（含 prepare_file_export 与失效文件）、输入区审批/澄清。`FamiliarToolPresentationPayload` 只保留 scalar/searchResults/document/recordCollection/mutationReceipt/fileMutation/shellExecution（schemaVersion 4）；task_plan/present_recommendation/present_insight/prepare_share 工具与 diff/code/contextMatches/taskList/recommendation/insight/shareDraft 呈现已移除；写入 receipt 折入活动行并在行上提供 Undo。当前导航为三Tab与会话列表，省略号为原生Menu，Composer添加菜单复用系统能力。

## 6. 授权现状

`FamiliarExecutionPolicy.evaluate` 拒绝不可用、preflight deny、缺少必要 scope、Skill 越界或 effect 不一致的调用。普通只读自动执行。第 2 级本地写入在撤销真实存在时自动执行并保留回执与撤销：内置 file_write/edit/publish、workspace_write、memory_remember（记忆开关开启时，控制器按 provenance 删除对应行）、从配置软件源发起的 environment_prepare（保留旧环境目录作为会话 Undo 目标，撤销回滚目录与 receipt 元数据）、经 Swift 命令检查与写入前 checkpoint 的离线 shell_execute。第 3 级外部影响（EventKit 创建/更新、通知、剪贴板写入、保存相册、alarm_schedule、skill_install、已信任 MCP）首次询问，卡片默认「始终允许此类」；`.always` 规则按 scopeKey + capabilityID + capabilityVersion 匹配，不绑定参数 hash 或 targetKey。删除、alarm_cancel 与未信任 MCP 每次询问且不产生持久授权。MCP 信任是按服务器的用户设置（UserDefaults，默认未信任，设置页可撤销，删除服务器清除）。执行前复核、journal、防重放、保存失败补偿和真实回执保留。撤销仅在当前聊天和其当前 scope 与原 Run scope 一致时显示/执行。

AuthorizationRuleRecord 使用完整 scopeKey，`.once` 10 分钟、`.session` 绑定会话且要求精确参数、`.always` 为能力级并 365 天有效。nil scope 不能持久授权。同 UUID 的 Project/Conversation 互不匹配；移动聊天不会携带旧授权。

`clipboard_read` 返回只读结果，只触发系统粘贴许可。`environment_prepare` 的已就绪路径返回专用 `.unchanged`，不走写审批、journal 或 Undo；普通写工具仍不得返回只读 `.result`。

## 7. 普通对话、项目与文件生命周期

- 普通对话 `project == nil`，启动和新建均不创建默认项目。草稿预分配稳定 Conversation UUID，发送校验并保存成功后才提交聊天和附件；取消/失败保留草稿。
- `FamiliarWorkScope.project(UUID)` / `.conversation(UUID)` 统一 File/FileVersion、Workspace、Environment、工具上下文、授权；scopeKey 包含类型，字节路径使用 `Scopes/<kind-id>/`。普通对话只取自己的 Files、会话记忆及显式 global Memory；项目保留共享指令、资料、设置与项目记忆。
- 普通对话删除时清理其 Files、附件目录、Workspace、环境元数据、会话记忆与授权；项目聊天删除仅解除 File 关联，项目文件保留。
- 移动聊天先复制关联文件及各版本、重新绑定附件，保留历史 FileVersion 标识到新版本的显式 provenance；清摘要，清旧普通范围授权/环境并清理原字节。删除项目先为各聊天复制关联文件，再将聊天转普通并清项目专属数据。
- 项目分类与会话列表由首页管理，普通聊天不创建默认项目；完整列表与搜索不依赖旧抽屉。

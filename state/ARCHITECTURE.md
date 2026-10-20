# Architecture

最后核对：2026-10-19（Telegram动效/文件/选区/图库/资料头部迁移；运行与设备证据独立）

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

## 3. App 入口与依赖注入

- `FamiliarAppShell` 拥有文件/对话/设置三个原生 Tab 与独立导航路径，默认对话；会话详情隐藏 Tab bar。`FamiliarChatRoute` 按稳定身份区分会话、草稿列表、归档、项目管理/详情与消息定位。旧抽屉隔离在 `frozenDrawerSurface`，保持编译但生产不挂载；下文旧侧栏布局说明已被此入口替代。
- `FamiliarChatSessionCoordinator` 保留按会话/草稿 UUID 索引的控制器；当前查看路由和正在执行会话分开。`FamiliarForegroundExecution` 为依赖中共享的唯一执行占用，Agent、压缩和润色串行，浏览其他页不取消前台任务；无系统后台运行或跨重启执行。
- `FamiliarChatsHome` 生成轻量快照；`FamiliarConversationList` 封装 UICollectionView/diffable/UIHostingConfiguration、原生菜单和冻结的最近三条消息只读预览。预览不创建控制器、不改草稿/已读。分类点击与分页进度共享状态并保存各页位置，列表摘要在保存/运行边界更新。
- `FamiliarChatProjectPager` 将分页列表与悬浮搜索/分类分层；`FamiliarChatListChromeState` 只向浮层发布当前页偏移，各页位置另外保存。UICollectionView 显式管理内容和指示器 inset、搜索吸附、列表内特殊入口；原生 Tab 无 bottom accessory，任务入口位于首页顶栏。
- U2 将分页进度留在浮层观察状态，首页在保存边界生成按 projectID 分组的轻量快照；列表当前行按 ID 字典查找，特殊行有版本，多选同步操作选择差集。分类条使用 ScrollViewReader 保持选中项可见，取消搜索明确恢复 UIKit 偏移；预览使用 fetchLimit=3。
- `FamiliarLocalSearchStore` 是只读 ModelActor，在 detached 任务中创建执行器，按正文/标题和允许会话 ID 查询；nil 范围为全部、空集合为无结果。`FamiliarLocalSearchModel` 由各搜索视图持有，200ms 防抖、取消和 generation 检查，返回 Sendable 值快照、实际计数和每页 50 条。首页不再通过会话.messages 关系构建搜索结果；无新实体/索引/Provider 请求。
- `FamiliarConversationFindState/Bar` 管理详情查询和当前消息身份，Timeline 接收导航版本并清旧补偿锚点；查找持有阅读检查状态，退出恢复阅读。原生文本使用 attributed text 关键词背景，WebKit 在正文外的 pointer-events:none 固定范围层标记匹配，按渲染/尺寸/横滚更新并裁切，不改正文 DOM 或长按规则。公式/图示不做原始语法到显示内容的强行映射。
- U3 `FamiliarFileLibraryView` 继续按原 scope 聚合浏览，补类型、名称/日期/最新版本大小排序与时间分组、菜单和删除确认。`FamiliarFileDetailView` 明确来源及缺失历史版本；历史预览/分享捕获具体版本，不用当前最新版本替代。
- `FamiliarThumbnailLoader` 在后台用 ImageIO/QuickLookThumbnailing 按像素生成，内存 NSCache 有 24MiB/120 条成本提示，HTML 不走系统缩略图。FileLabel/消息/草稿只显示缩略图；`FamiliarDraftImage.image` 可空，完成导入和恢复的图片以托管 attachment 为字节来源，发送/检查点不重新压缩缩略图。附件变化触发即时保存检查点。
- 输入区按附件 ID/尝试 UUID 跟踪准备与失败，同一输入区串行准备大资产，可取消/重试；失败项处理后发送。控制器 `draftAttachmentIdentity` 在恢复/切换草稿时刷新，普通打字不刷新；完成回调读取真实控制器身份，避免同一会话进入编辑后附错草稿。清理只针对本次未交付结果；已交付文件继续由全部草稿引用管理。
- `FamiliarImageGalleryView` 使用UIKit分页/缩放容器和弱源视图登记；当前/邻页按需降采样，当前图ID决定退出目标，拖拽/取消/离屏收尾不回写全时间线。图片不再交QuickLook；文档QL/HTML保留原精确URL/CSP路径。草稿移除回传稳定ID，已发/Files只读；Gallery持有阅读检查。
- `FamiliarSendPresentation` 仅持有有界可见快照与一次性消息ID。Composer提交组合文字、采集源；控制器持久化成功后commit；原生目标出现才开始0.3秒横纵曲线，未命中/过期/离场释放。几何与每帧动画不进入SwiftData/Agent。
- `FamiliarSelectedTextSink` 连接原生/WK编辑菜单与原草稿保存路径；冻结消息/块/正文及会话身份，单一选区所有权，原生退场完成再追加/聚焦。审批/澄清占用输入时不回填，不发起模型请求或自动发送。
- 文件聚合页通过值快照固定File/Scope/Version，批量删除仍逐项走原服务事务并报告部分失败；分享在执行前检查实际版本/作用域/URL。分类、选择和原生底部栏均属页面状态，没有新增持久实体。
- `FamiliarProfileHeaderMotion` 的控制器在设置页而非懒加载行，行只提供弱源；滚动KVO更新UIKit子层，使用原AvatarMask关键帧和公开模糊API，导航时解除观察/效果并在返回恢复。头像解码仅随资料数据变化；这不改变本机资料或身份语义。
- U4 `FamiliarSettingsCatalog` 统一稳定 route、标题/别名/路径和图标，普通列表/本地搜索共用 destination，含既有本机资料编辑。紧凑状态行在辅助字号纵排；Hub 保存回调返回实际配置，失败保持原显示，Done 不重复保存。
- `FamiliarProviderEditor` 使用会话内验证身份（descriptor/模型/credential 哈希），变化/失败清除，成功须匹配当前身份；发现/验证/登录独立操作阶段。没有持久验证声明或自动服务请求，凭据仍在 Keychain。
- Memory 管理支持归属类型/指定 work scope 与真实所有者名称，Project 直达 project-scoped 记忆，隐藏该页全局开关；内容准入/来源/归一化检查保留，UI 保存失败回滚并分开 Sheet 错误。Project 运行与环境配置也直接进入原页面，不再经高级中转。
- `FamiliarStorageInventory` 在后台 ModelActor 计逻辑对象数量、枚举 App Support/Familiar 文件逻辑长度，按目录分类、按文件身份去重且不遍历符号链接；取消/刷新版本与不完整状态分开。统计不创建环境、不清理文件、不计算 App 包/系统缓存或 APFS 分配块。
- Run 列表显示对话/模型/实际状态，详情先摘要及 responseMessageID 精确结果；Markdown/技术上下文按需展开，回执保留。Skill 查询限当前 run，步骤用 activityID 关联已有记录；无回复 ID 不回退到其他消息，自动授权说明不再只指记住的授权。
- U0 将浮层约束在导航栏下的安全视口，只有列表单独延伸到栏后，用实际重叠量计算 inset；默认折叠不创建搜索玻璃。列表滚动偏移延后合并发布，避免 UIKit 调整 inset 时直接修改 SwiftUI 状态。
- `FamiliarComposerTextView` 是 UITextView 的薄封装，原生文本布局同时负责正文、占位、测量、焦点与选区桥接；marked text 期间禁止外部覆盖。详情移除中央模型胶囊，模型选择位于省略号菜单；菜单显式使用单层圆形玻璃并关闭系统共享背景，隐藏整条导航背景和顶部滚动边缘效果。
- U0 输入以普通 Binding 表达焦点请求，UIKit delegate 回报实际焦点，带版本取消和挂窗处理；菜单动作在退场完成后执行。外层单行高度统一，动作尾部空间固定；AI润色与回形针共用左侧纵向玻璃，展开入口不改变正文宽度。`FamiliarComposerSelection` 使用归一化 UTF-16 值；正文变化刷新 draftRevision，润色应用检查版本，操作前显式提交组合文本。
- 连续空行高度使用独立无限高 TextKit 容器和末尾不可见字形测量，编辑 UITextView 始终可内部滚动并裁切；紧凑输入最多六行，布局变化时滚动光标入可见范围。
- 会话新增可空 titleOrigin/titleRevision。新对话默认为 pending，完整回复后的可取消 Provider 后处理先请求短标题再请求后续问题；无工具、不进入 Agent。仅相同 revision 的 pending 记录接受标题，不改 updatedAt；人工重命名设为 manual。按所有者明确要求，AppShell 首次遇到旧 origin=nil 对话时走现有删除事务清理，不清空 Project/配置，新记录不再匹配清理。
- `FamiliarLocalProfileSection` 在设置顶部显示本机头像/昵称/简介，`familiar.local-profile` UserDefaults Data 原子保存编码资料，图片经 ImageIO 按 512 像素降采样；Sheet 取消不保存，不进入模型上下文或权限身份。
- `FamiliarMessageEditing` 管理编辑草稿和提交：现有 `FamiliarComposerDraftRecord` 的可空 editStateData 编码源消息身份及进入前草稿备份，附件保留集合涵盖当前/备份。进入编辑或取消不删消息；编辑请求使用原消息之前的历史且不使用含待替换尾部的旧摘要。已提交编辑在生成期间保留原历史和编辑字节，新完整回复成功持久化时同事务删除原尾部、关联旧记录并保存新回复，随后恢复之前草稿；失败/取消恢复编辑稿，已产生的尝试/真实回执继续可查。单一当前 schema 5.0.0 / 39 实体与业务代际不变，无新增迁移链。
- `FamiliarMessageInteraction` 在真实 UITextView/WKWebView 上安装 UIContextMenuInteraction；消息菜单提供现有复制/编辑/安全重试。原位选择与菜单互斥，菜单和选择接入阅读检查生命周期；WebKit 上报链接/按钮区域用于命中排除。文档与只读预览没有消息动作。终态标识独立于操作按钮，页脚只保留真实来源与后续问题。
- `FamiliarComposerDraftRecord` 保存正文、UTF-16 选区、技能、附件 manifest 与可选会话/项目；新草稿首次发送提交前不创建 Conversation。防抖及离开/后台检查点保存，发送提交同次保存删除草稿；清理检查全部持久引用，移动会话/删除项目同步草稿归属。
- `FamiliarConversationListStateRecord` 保存归档、未读回复身份、手动未读、摘要和失败状态；完整回复与未读同次保存，归档不因回复解除，正式详情末尾可见且前台无遮挡才清对应未读。列表状态不进入上下文或授权。
- `FamiliarMessageGroupLayout` 按可用宽度限制左右气泡；用户文本及无 Markdown/链接的已完成短 AI 文本使用原生文本视图，复杂正文保留 WebKit。`FamiliarTextAndTimeLayout` 测量单行文字与时间，放不下则时间独立末行；时间在气泡内。Timeline 组合日期分隔、相邻用户间距、定位高亮与返回阅读入口；Run/工具/文件顺序不变。控制器持有阅读状态；独立技能菜单维护焦点和选区。`FamiliarDraftRewriteSheet` 通过 `FamiliarDraftRewriter` 发送要求与草稿、tools 为空，不进入 Agent；复用已配置模型和用户凭据，完整结果经会话/版本检查后应用、可撤销、不直接发送。
- `FamiliarApp`（`@main`）创建依赖；首次检测到业务代际非 `5-work-scopes`，清理旧 store、附件、资料、Files、Workspace、ShellRuntime、Skill 包、共享收件箱和派生索引，当前容器打开成功后写代际标记。Keychain、模型/搜索设置和外观偏好不清理。已完成代际的普通打开失败进入恢复页，不再次清空。
- `FamiliarAppDependencies`（`@MainActor`）持有 ToolRegistry、ExecutionPolicy、确认/澄清 coordinator、UndoStore、原生服务、`FamiliarWebSearchService`、`FamiliarWorkspaceStore`、Python 包源设置、`FamiliarShellRuntimeStatus`、`FamiliarVisionProcessor`。registry 在 init 中一次构建；iSH 资源存在时追加 `shell_execute`/`environment_prepare`。主界面出现后 `FamiliarRootView` 触发 `prewarmShellRuntime()`：后台低优先级、共享 flight、幂等，失败静默由下次调用或设置页 Retry 重试。
- `makeRuntime(for:...)` 把 `FamiliarProviderFactory.makeProvider` 结果与 registry、policy、coordinator、授权、persist/willCommit 回调注入唯一的 `FamiliarAgentLoop`。

- U5 输入尾部为稳定的单一 SwiftUI Button；原图标/标签/处理器随语音/发送/停止切换，位置固定。`FamiliarEntranceRegistry` 只属于挂载时间线，播过的身份不因 Lazy 行复用或 Reduce Motion 切换补播；WebKit 初始块不动画、文本增量保持节点。
- U5 原生文本通过 `UIAccessibilityCustomAction`，Markdown 通过正文之后的具名 DOM 控件连接同一 `FamiliarMessageActions`；不合并/隐藏原文档结构。当前可阅读详情只在语义运行阶段变化时排队播报；VoiceOver 禁用自动追随，保持显式返回。自定义玻璃在降低透明度/增加对比度使用实色；无持久化/Runtime 变更，真实无障碍行为待设备验收。

- 设置首页按 Telegram 行测量分配文字高度+32pt，图标29pt/间距16pt，List 行无额外上下留白；保留本机资料和同一设置目录。聊天菜单使用系统 Toolbar 玻璃；AI 润色移除内部导航与独立底栏，三模式/统一内容卡/主操作复用原 Provider 和版本校验。
- `FamiliarChatHistoryStore` 使用 propertiesToFetch 生成全会话轻身份索引，再按 `FamiliarHistoryWindow` 的最多80项ID查询富负载。当前控制器数组是本页，完整发送/编辑前缀/压缩/分支/导出和最新回复读取独立；转换器保留原正文块/来源/附件语义，部分回复通过消息/正文块的Runtime关联补齐。`FamiliarRunHistoryQuery` 继续分批200限定Run记录，文件按scope/Run，Undo与重试沿用范围/外部影响检查。索引仍按会话全量读取轻字段，单Run数据完整；无性能测量。
- 会话协调器按导航/执行/润色/后处理/导入保护并保存后释放额外闲置会话（最多2份），128条轻量阅读书签不持有渲染器。草稿检查点返回保存成功状态；过期/失败不释放，附件导入有成对计数和完成检查点。缩略图加载器共享同版本/尺寸请求、串行准备、无读者取消排队、缓存代次隔离；内存警告请求清缓存/闲置收敛。
- 导航目的地从初始固定 Tab Bar 状态、缓存会话直接呈现；自动跟随无动画，退场冻结几何/DOM补偿和焦点。真实设备抖动与性能尚未测量；当前 schema/实体数/业务代际不变。

- 导航页切换富负载前保持读取原子性；目标跳转在呈现前准备窗口，书签先于会话选择恢复。时间线呈现UUID持有阅读几何/自动跟随，旧页和旧WebView的退场/补偿不改变新页；以索引全局最新回复判定已读。Spotlight根入口使用存储存在性谓词与标题字段投影，详情不重复遍历/发布。

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
| `Presentation/` | `FamiliarChatController`、`Presentation/Chat/`（Timeline、Row、Turn、Runtime、Records、VisualFixture 六个文件）、`Presentation/Settings/`（Hub、Capability、Personalization、Privacy、RunHistory、RunRecord、About、ModelService 八个文件）、`Presentation/Files/`（Files 列表与文件详情）、InputDock/Composer/Scroll、Markdown WebView 与流式节奏、ApprovalCard、活动投影与 Surface、Provider 品牌图标、Projects/Files、Terminal、Web 呈现、Debug 测试场景 |
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

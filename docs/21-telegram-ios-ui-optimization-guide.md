# Familiar 全应用 UI 优化总指引

研究基线：2026-10-18。参照 Telegram iOS 提交 [`f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`](https://github.com/TelegramMessenger/Telegram-iOS/tree/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838)。Familiar 对照基线为 `main @ a97e6ee` 加当日 UI 工作区改动，包含所有者最新真机反馈。

本文是后续多轮工作的方向和设计依据，覆盖首页、聊天、Files、Project、设置、Memory、AI 编辑器及运行记录。**路线与候选不自动进入实施，规划不等于交付。** 当前实现与问题状态以 [CURRENT](../state/CURRENT.md)、[ARCHITECTURE](../state/ARCHITECTURE.md) 和根 [PLAN](../PLAN.md) 为准。

本指引承接 [20：根导航与聊天重构](20-telegram-chat-ui-roadmap.md)，后者保留 R0–R6 设计和阶段边界；[功能研究](research/2026-10-18-telegram-ios-functionality.md)、[UI 研究](research/2026-10-18-telegram-ios-ui.md) 保留固定提交的专题证据。后续设计变化优先更新本文，具体任务和验收结果只在 PLAN/state 维护。

## 1. 文档定位与研究方法

### 1.1 要回答的四个问题

1. **能怎样优化**：以相同功能的布局、状态、命中、焦点、更新范围和转场规则作对照。
2. **值得增加什么**：优先补齐现有对象的 UI 操作，再列需要新产品语义的候选。
3. **缺少什么**：区分入口缺失、已有能力未接通、状态组合缺失和真正没有的功能。
4. **不足在哪里**：记录可复现问题、静态代码风险、体验差距和待验证假设，不混用这些结论。

### 1.2 来源与阅读深度

本次取得固定提交下 **32,109 个文件索引**，选取 **68 个候选源文件**建立研究副本。68 份副本逐个按 Git blob 校验，均与该提交匹配。这证明来源一致，不证明 68 个文件均已全文审阅；完整目录索引也不代表整个仓库已经审完。

附录逐文件登记完整路径、固定提交链接、已读行段、机制或待查问题、Familiar 对应组件和后续阶段。阅读深度严格区分：

| 标记 | 含义 | 可以据此作出的结论 |
|---|---|---|
| 全文审阅 | 文件全部正文已经阅读 | 文件职责与已读代码机制；仍不代表运行验证 |
| 关键函数片段 | 已沿特定入口、状态或布局函数读取列出的片段 | 只覆盖列明的调用链，不能推广到文件全部分支 |
| 仅检索 | 只检查声明、字段或搜索命中 | 只能定位后续阅读入口，不能据此宣称功能链路已理解 |
| 待审 | 尚未读取相关正文 | 不作实现结论 |

仅检索的条目继续列为待深读。大文件分阶段追入口、状态更新、测量布局、手势/转场、取消和销毁，不以文件行数或下载量充当审阅进度。README 是编译入口；UI 依据来自实际组件和调用链。

### 1.3 每项发现的记录契约

每项保留：稳定问题编号、研究日期、证据类型、Telegram 路径/函数/行段、Familiar 对应实现、差距、建议、优先级、依赖和可观察验收条件。证据类型使用：

- **真机已确认**：所有者反馈或提供截图确认了现象。
- **源码已确认**：静态控制流可以直接证明的行为。
- **静态风险**：代码存在可疑结构，但没有运行复现或性能测量。
- **体验不足**：行为存在，但可发现性、层级或使用流程不完整。
- **新增候选**：当前能力中没有完整实现，需要另行设计。

实现、编译、测试执行、真实 Provider、真实性能和真机验收分别记证据。无法确定的触发顺序继续标为待定位。

## 2. 首批必须解决的基础问题

这批问题优先于新增功能和复杂动效。下表是当日研究快照与修正方向，进展查 PLAN，不在本文重复维护完成状态。

| 编号 | 证据与不足 | 修正方向 | 验收条件 |
|---|---|---|---|
| U0-01 顶部挤压 | 真机已确认：搜索进入状态栏，分类与导航按钮重叠。`FamiliarChatProjectPager` 把浮层和列表放入忽略安全区的容器，再从内部读取 inset | 系统导航栏拥有第一行；搜索与分类明确锚定在导航栏下方。只有列表内容延伸到控件后方；统一坐标来源，避免 inset 重复计算或丢失 | 冷启动、返回首页、切分类、展开/收起搜索、大字体下，状态栏/导航/分类不重叠；默认收起的搜索不留残影 |
| U0-02 键盘不出现 | 真机已确认。`FamiliarComposerTextView.updateUIView` 异步同步焦点，焦点意图与 UIKit 实际 first responder 的竞争仍待定位 | 分开焦点请求和实际状态；只处理明确变化，取消过期请求。正文、占位及输入空白处点击都路由到实际编辑器；按钮保留各自命中 | 首次进入、返回会话、技能选择后和润色应用后能正常输入；键盘不会被旧回调立即收回 |
| U0-03 输入高度不齐 | 真机已确认。源码显示侧边控件为 44pt，输入视口至少 44pt，外面又加上下 padding | 统一外层玻璃高度，包含全部 padding。默认单行同高同中心；多行明确底部对齐规则；以同一字体和 inset 排正文/占位 | 空输入和短文输入的三块玻璃同高；占位与首行基线一致；大字体不裁切 |
| U0-04 输入布局反馈 | 静态风险：AI 按钮随行数在框内和左侧切换，位置变化又改变正文宽度 | 以稳定可用宽度测量决定布局模式，避免测量结果反过来不断改变测量条件；统一麦克风、发送、停止、AI 入口的空间规则 | 在布局阈值附近逐字输入/删除、粘贴和旋转布局时，不反复换行、抖动或挤占光标 |
| U0-05 编辑历史时机 | 源码已确认：先弹确认，但 `prepareToEdit` 在进入编辑时便保存删除原消息及后续历史 | 进入编辑只建立编辑草稿；取消不改变历史；正式提交成功后才执行替换。继续使用现有外部影响检查和回执，不把改历史当作撤销外部影响 | 打开编辑再取消、切走或提交失败，原历史与附件仍在；提交成功才改变历史 |
| U0-06 输入与选区一致性 | 静态检查项：正文、选区、语音、技能、润色与恢复经过多个入口；未证实崩溃风险不写成已复现故障 | 统一正文替换/选区更新契约，覆盖中文组合输入、Emoji、换行、撤销、恢复及晚到回调 | 不覆盖 marked text；外部替换后选区合法；旧回调不能覆盖新会话/新草稿 |

最新现象依据为所有者提供的 `截屏 2026-10-18 晚上7.23.39.png` 及聊天输入问题描述。底部原生紧凑 Tab 已在这张图中呈现，应保留；修复顶部不应重造 Tab Bar。

Telegram 明确区分实际编辑器的 `isInputFirstResponder`、获取/失去焦点，以及输入背景点击聚焦：[输入控件接口](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatInputTextNode/Sources/ChatRichTextInputNode.swift#L762)、[输入背景点击](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift#L5710)。这是 U0-02 的实现参照，不是 Familiar 键盘故障已经完成运行定位的证明。

### 2.1 U0 专项实施契约

所有者发起 U0 后采用以下边界；实现与验收证据仍在 PLAN/state 单列。

- 浮层以未忽略安全区的视口为基准，锚定在原生导航栏下方；只有列表单独延伸到栏后方。列表 inset 取实际视口重叠量，默认收起不创建空搜索玻璃；动态字体变化时同步折叠距离，不混用固定初始像素值。
- 输入焦点采用普通绑定表达请求，UIKit delegate 回报实际 first responder；只在意图变化时同步，过期请求可取消，等待菜单退场完成后再执行编辑/选择动作。玻璃只作输入区背景，文字控件拥有命中和焦点。
- 单行按同一外层高度布局，默认至少 44pt，包含全部 padding；正文多行增长，展开模式顶部对齐。AI 与发送/停止的尾部空间固定，不再按行数把 AI 按钮来回移位；展开按钮使用已有尾部空间，不挤正文。
- 选区使用归一化 UTF-16 值，不保留指向旧 String 的索引；正文替换更新草稿版本和选区。晚到润色检查版本，即使文字改回原样也不能套用旧结果。输入法组合文本不被视图重写，发送/技能/润色前提交当前组合文本；外部替换建立新的原生撤销边界。
- 消息编辑保存编辑态及进入前的草稿、技能、选区和附件引用；清理检查两份引用。取消或重启恢复不提前删历史。生成完整回复并成功保存时，在同一事务中替换旧历史、保存新回复并恢复进入编辑前的草稿；保存失败回滚，生成失败/取消恢复编辑稿，失败尝试的真实运行记录保留可查。
- 编辑请求只编译源消息之前的历史，不混入待替换尾部或包含尾部的旧摘要；提交前复核源消息身份/内容/附件及现有外部影响检查。只在当前编辑生成期间锁定该输入与附件入口，停止仍可用，其他会话草稿不受此锁定影响。
- 编辑态使用现有草稿实体的可空元数据；实体数和当前业务代际不变，不引入历史迁移链或再次重置。旧存储演进、故障恢复和真机行为须分别验收，不能由编译推定通过。

### 2.2 U0 所有者真机验收

1. 冷启动/返回首页，检查顶部三层不重叠；下拉展开搜索、上滑收起、切分类和切大字体，默认收起时无空玻璃条。
2. 首次点输入文字区域、占位及空白处均呼出键盘；编辑旧消息、选择技能、应用/撤销润色后仍可聚焦；返回会话没有旧请求误收键盘。
3. 空输入和单行时各块玻璃同高，多行/展开输入不裁切，AI/展开入口变化不改变正文测量宽度或反复换行。
4. 中文组合输入、Emoji、换行、中间插入/删除、原生撤销及润色撤销后，正文和选区一致，晚到结果不覆盖新草稿。
5. 先准备一个未发送草稿和附件，再编辑旧消息；取消及重启恢复保留原历史与原草稿。校验失败、停止、网络失败不删原历史，失败尝试保留可查。
6. 编辑生成成功后才替换旧尾部，新回复与新运行回执可查看；进入编辑前的草稿/附件恢复。测试项目会话时继续检查完整 scope 和外部影响限制。

本阶段只记录代理静态/构建证据，以上交互由所有者验收；未签字前不推进 U1。

### 2.3 U0 反馈修正与 U1 本轮边界

所有者在 20:43–20:45 的真机截图与文字反馈中确认连续空行溢出，并授权修正后进入 U1；这次授权允许先推进，不等于旧问题已经验收通过。

- 输入高度从无限高 TextKit 测量容器获取，末尾添加不可见占位字形，使连续空白段落计入高度。实际 UITextView 保持内部滚动并裁切，紧凑输入最多六行，超出后滚动到光标，仍可展开。不能以被裁切的编辑视口推算全部正文高度。
- 详情移除中央标题/模型按钮；模型、Provider 和跟随全局入口移入省略号菜单。省略号 44pt 圆形玻璃、17pt 图标，关闭系统共享背景避免双层；隐藏详情导航整条背景及顶部滚动边缘效果，保留原生返回。
- U1 首批完成范围为短纯文本自适应宽度、气泡内时间、日期分隔、相邻用户消息间距与定位反馈。只对无 Markdown/自动链接且不超过 160 字符的已完成 AI 文本使用原生文本交互；复杂正文继续生产 WebKit。同 Run 的工具、文件、正文不重新排序，不把不同 AI Run 合并。
- 单行文字与时间按实际测量宽度决定同排；放不下、多行及复杂 Markdown 使用气泡内独立末行。消息定位短暂高亮，并提供返回原阅读位置/原跟随末尾状态的入口，不改变流式阅读所有权。
- 三 Tab 显示名称为“文件｜对话｜设置”。设置顶部使用本机头像、昵称与简介；编辑 Sheet 保存才应用，照片降采样至最大 512 像素，失败或取消保留原资料。资料不进入模型上下文，也不是账号或身份授权。
- 新对话的标题在首个完整回答后，由当前实际响应模型的用户 Provider 做无工具摘要请求；生成任务沿用可取消的后处理生命周期，开始新请求/进入后台时取消。未完成时保留“新对话”，之后可重试；人工命名与晚到结果通过 origin/revision 隔离，标题更新不改变对话排序时间。
- 所有者明确选择“全部删掉所有之前的就行”，撤销旧标题批量生成方案。启动清理只匹配新增 `titleOrigin` 为空的旧对话，通过现有删除事务处理其草稿、范围文件/授权/记录。新对话构造时总有 origin，因此重复启动不删除新数据。Project 本身、凭据和配置不清空；独立未发送草稿不属于旧消息历史。此动作在所有者下次运行新版时发生，代理未启动 App 触发。
- 当前仍是 schema 5.0.0 / 39 实体 / 5-work-scopes；会话仅增加可空 titleOrigin/titleRevision，不新增历史迁移链或全量业务重置。旧存储实际演进与删除结果仍需真机确认。

Telegram 继续参照 `ChatTextInputPanelNode.calculateTextFieldMetrics` 1367–1432 行对无界高度、上限与 overflow 的分离，以及 `ChatMessageTextBubbleContentNode` 688–729 行的正文末行/状态测量。Familiar 没有导入 Telegram 渲染框架，短文本只做可证明安全的同排；复杂正文走独立时间行。

本轮所有者验收重点：连续 12 次空行后输入/回删/移动光标；菜单形状、模型入口与透明顶栏；短消息/长 Markdown/宽表格/代码/来源；跨天日期、搜索跳转高亮与返回；本机资料保存/取消/重启；新版旧历史清理后新建对话再次重启仍保留；首次真实 Provider 回复后的摘要标题与人工命名竞争。编译通过不能结清这些交互或真实服务项目。

### 2.4 U2 首页与本地搜索专项契约

所有者在 U1 交付后授权进入下一阶段。U2 包含首页分类/摘要和会话内查找（C01），其余优先候选与后续产品候选不随本次授权展开。

**对象与状态所有者**

- 首页按保存边界生成带 projectID 的轻量行快照，并一次按分类分组；分页进度由独立浮层状态持有，只更新选中区域，不按帧重算整个首页输入。分类条选中项自动滚入可见区，保留稳定 Project 身份与删除/归档回退“最近”的路径。
- 列表同时显示未读和置顶；图片/文件草稿使用已托管 manifest 生成摘要，正常消息摘要含真实附件信息。每个分类使用自己的草稿入口，不再共享当前分类的特殊行；归档页分类角标统计归档范围的未读。
- 原生列表按 ID 字典配置行，仅在内容/特殊行版本变化时做 diff；多选同步处理选择集合的差异，包括屏幕外条目。长按预览只查询最近三条消息，而不是加载整个历史再截取。
- `FamiliarLocalSearchRequest` 以查询和允许的会话 ID 集合描述范围：nil 表示全部（含归档），空集合明确匹配零条；视图中的分类筛选不改变真实会话归属。
- `FamiliarLocalSearchStore` 使用独立 ModelActor/ModelContext，在 detached 任务创建执行器，直接查询持久消息/标题；返回可发送的值快照，不把 SwiftData 对象跨隔离域传回 UI。不遍历首页所有会话的消息关系。
- `FamiliarLocalSearchModel` 由搜索视图拥有，200ms 防抖、任务取消与 generation 共同拒绝旧结果；每页最多 50 条消息/50 条标题命中，计数来自实际查询，支持显式加载后续页。空查询不执行数据库检索。此检索没有网络请求或 Runtime/授权副作用。

**展示、定位与取消**

- 空搜索显示提示；结果区分标题与消息命中，归档明确标注。摘要按第一个实际命中位置截取前后上下文，String 字符边界保留中文/Emoji，关键词着色继承原排版。
- 搜索期间保留各分类的列表偏移；取消恢复当前仍存在分类的真实列表位置与头部折叠状态，避免仅复位玻璃头部而列表停在其他位置。若当前项目被删除，回到“最近”。
- 详情省略号中的“在对话中查找”使用同一本地服务，只查当前会话。统计单位为匹配消息，非某词出现次数；初始定位最近命中，向上找更早、向下找更新，触及已加载边界时继续取下一页。计数/错误/重试均有真实状态。
- 查找跳转通过稳定消息 ID 定位和短暂气泡高亮，原生文本同时标记关键词；WebKit 根据 DOM Range 测量范围，在不接收触摸的独立层绘制标记，不改正文 DOM、链接/代码按钮或原位选择策略。公式/图示内部不强行映射原始 Markdown 语法；其消息仍可被定位。
- 原生文本选择因查询变化结束时延后回报 SwiftUI 状态，避免 updateUIView 内同步修改状态。WebKit 高亮跟随渲染、尺寸及横向滚动更新，并裁切到代码/表格的滚动容器范围。
- 查找持有阅读检查状态，搜索结果不会清未读；显式定位先清旧补偿锚点，关闭后恢复之前阅读位置或跟随末尾。离开页面对称释放检查，返回仍打开的查找页时恢复检查；查询任务随视图生命周期取消，旧回调不重定向新查询。

**来源与公开接口**

固定 Telegram 提交的 `HorizontalTabsComponent` 958–1028 行为选中分类调整可见范围；`ChatControllerUpdateSearch` 1–145 行将查询/范围作为身份，空查询取消、0.2 秒延迟，维护真实数量、当前消息和后续页。Familiar 采用这些状态机制，保持纯本地检索。

分页使用 Apple 的 [fetchOffset/fetchLimit](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/fetchoffset) 和 [ModelActor](https://developer.apple.com/documentation/swiftdata/modelactor)。WebKit 官方 [278455](https://bugs.webkit.org/show_bug.cgi?id=278455) 记录 user-select:none 下 CSS Custom Highlights 不显示，故本实现不依赖该组合，也不为高亮开启另一套长按选择行为。范围标记不参与高度、命中或复制文本。

**验收与边界**

1. 创建足够多分类后点击/分页到屏幕外分类；重排、归档或删除当前分类，核对选中区域、列表、计数和回退身份。
2. 同时置顶与未读，保留附件但删除全部草稿文字，分别检查普通/项目/归档页摘要与角标。
3. 空搜索不列全部消息；当前分类/全部范围切换、归档命中、消息末尾关键词、中文/Emoji/大小写/重音、超过 50 条结果及加载更多。
4. 连续快速输入/清空/取消/切换范围，晚到结果不覆盖；打开结果进入正确会话/消息，长按预览不改已读。
5. 会话内查找核对真实匹配消息数、上/下边界、超过一页、同词多次、普通/代码/链接高亮与原动作，退出后恢复阅读；运行增长、键盘、打开附件再返回都不抢走位置。
6. 查询/保存故障分别记录；未实现全文索引或性能采样，不能宣称数据库查询耗时、帧率或内存已达标。分页按当前数据快照展示，不将逐 token 变化接入搜索。

本阶段不新增 schema、迁移或业务重置，不修改 Provider/Agent/授权逻辑。构建、测试执行、实际搜索 SQL、WebKit 交互和所有者真机验收继续分别记证据。

### 2.5 U3 附件、Files 与系统图片浏览专项契约

所有者授权继续 U3。此阶段按 Files/缩略图、附件导入、图片浏览分层实现；只改变呈现与原生导入/预览边界，不改 canonical File/FileVersion、work scope、Provider 或 Agent 授权。没有新增 schema、业务重置或跨重启导入续传。

**Files 与版本**

- 保留原项目/对话归属筛选；类型按真实扩展名/MIME 分为图片、PDF、文档、表格、演示、文本/代码和其他。按最新版本大小、名称、更新时间升/降序排序，使用文件 ID 消除相同排序值的不确定性。
- 时间排序按本地日历日期分组；名称/大小排序保持完整排序，不再按日期打散。空结果在内容流中显示，筛选入口仍可操作。
- 列表与详情显示最新版本、来源、归属及不可用状态；历史版本缺失明确标注。上下文菜单预览/分享绑定显示时的具体 snapshot/版本 URL，详情仍用真实 File ID；删除继续走原确认和元数据/字节事务，不把聚合浏览变成作用域转移。
- File 卡先按版本 ID 限取，确需兼容已有移动后来源映射时才查询指定 scope 的版本，不再每卡加载所有版本。原有引用重绑语义保留。

**缩略图与预览生命周期**

- `FamiliarThumbnailLoader` 按 URL、版本身份和像素尺寸缓存内存缩略图，NSCache 成本提示 24MiB/120 条；这不是实测内存上限。图片使用 ImageIO 降采样，其他可预览文档复用 QuickLookThumbnailing；HTML 跳过系统缩略图，保留原 CSP/禁脚本预览约束。
- 加载与解码在后台任务完成，取消/晚到结果不回写新视图；不可生成缩略图时回退真实类型图标，不把缺图当作仍在加载。
- 消息图片使用降采样预览，草稿恢复只加载附件引用、不读取完整 UIImage；FamiliarDraftImage 的临时 bitmap 可空，托管附件才是发送/恢复字节来源。缩略图不覆盖托管原附件。
- 附件变化触发即时草稿保存检查点，文字仍防抖；保存失败继续由现有错误路径报告。失败/未完成导入不承诺跨重启恢复。
- Quick Look URL 未变化时不 reloadData；HTML URL 未变化时不重读/重载，文件读取异步执行。HTML/HTM 后缀继续强制进入受限本地 HTML 预览，避免新增快捷入口绕过既有约束。

**逐附件导入**

- 每个请求有稳定 ID、来源和尝试 UUID，呈现准备中/失败；成功后进入已托管附件列表。没有字节进度就只用不定进度，不显示百分比。
- 同一输入区串行准备 Photos 数据和文档，避免多份大资产同时加载。排队和正在准备都可取消，失败保留原位重试/移除；失败附件未处理前不发送，停止当前 Agent 不受影响。
- 数量限制含准备/失败项（4 图片、3 文档）；选择过量明确提示。Photos 选择提交后清空选择器选择状态，不把旧选择重复追加。
- 取消/重试/切换对话均检查尝试与实际草稿附件身份。`draftAttachmentIdentity` 在恢复/切换/进入或取消编辑草稿时刷新，单纯输入文字不刷新；回调通过读取控制器当前身份，不能只比较已捕获的 View 参数。
- 取消或晚到成功只清理本次新准备、尚未交给草稿的字节；已完成附件仍由全部持久草稿引用检查管理。编辑回复执行期间，附件移除/追加与图片浏览内移除均锁定，浏览保持可用。

**系统图片浏览**

- 当前草稿与单条消息的图片集共用 Quick Look；由系统提供图片缩放、分页/导航和分享，预览项目标题包含当前位置/数量。使用原生导航容器承载，保留原缩略图返回转场及 Reduce Motion 路径；不是导入 Telegram Gallery 框架。
- 当前索引来自 QLPreviewController 的真实 currentPreviewItemIndex，草稿移除操作转换为对应稳定图片 ID；删除最后一项后退出，不在退出期间向系统投递空数据源。过期索引只返回不可用项，不回退到另一张图片。
- 已发送图片只读；草稿删除只影响草稿引用。QL 编辑模式显式禁用，防止系统标注直接修改托管附件。浏览器持有并对称释放阅读检查状态，展示期间不把被遮挡的回复标记已读，也不因内容增长跳到底。
- 本次只接入有界集合，C09 的跨历史媒体库、手工相册缩略条等仍不展开。

**源码与公开接口依据**

Telegram 固定提交 `AttachmentController` 511–549 行把选择数量、准备进度与面板状态分开；`FileMediaResourceStatus` 69–142 行区分发送准备/可用及播放状态，本项目只取本地准备状态；`ZoomableContentGalleryItemNode` 70–170 行处理双击缩放和布局改变，Familiar 将基础能力交给系统；`StorageFileListPanelComponent` 844–954 行按可见区域/稳定 ID 维护显示项，Familiar 采用原生 List 和有成本限制的按需缩略图。未将这些片段记作全文审阅。

公开接口：[QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator/generatebestrepresentation(for:completion:))、[Quick Look 当前项目](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller/currentpreviewitemindex)、[ImageIO 图片内存说明](https://developer.apple.com/videos/play/wwdc2018/416/)。系统浏览的具体视觉、双击/捏合、分页和返回表现必须在所有者设备验证，编译不能证明其运行效果。

**所有者验收**

1. 同时选择图片/文件，逐项取消、失败重试、过量选择、准备期间输入文字；切对话、进入/取消历史编辑、返回后不串草稿，也不永久阻塞发送。
2. 导入结束、移除附件、后台/重启，检查完成附件及原草稿恢复；检查失败附件无虚构进度、晚到回调不删除其他草稿字节。
3. Files 组合归属/类型/搜索/四种排序，核对时间分组、大小以最新版本计，名字相同的文件仍操作正确 ID；空结果可修改筛选。
4. 最新/历史版本预览与分享对象正确；缺失/损坏/被撤销文件有合理状态；删除确认取消不改文件，实际删除不影响其他 scope。
5. 草稿/消息多图的初始项、页码、系统双击/捏合/分页、关闭与返回缩略图；删除当前项及最后一项、编辑生成时只读；长回答/流式期间阅读位置和已读不被浏览器抢走。
6. HTML 不执行脚本或访问远程资源；前后台/主题/布局更新不重复重载同一预览；大图与长文件列表的真实资源峰值另行测量，本轮没有性能通过证据。

### 2.6 U4 设置、Project 与状态真实性专项契约

所有者授权继续 U4；范围是设置本地搜索和密度、Provider 校验身份、Memory 归属、Project 入口、存储统计及运行记录分层。复用现有保存/校验/删除/授权流程，不增加账号或新的模型请求；不改运行策略、Memory 准入规则或 work scope，不新增 schema/业务重置。

**设置与搜索**

- `FamiliarSettingsCatalog` 统一条目的稳定 route、标题、分组、说明、图标、别名和路径，普通列表与搜索共用同一套元数据和 destination。目录覆盖所有路由并纳入已有本机资料编辑，资料仍只保存在本机。
- 查询在本地匹配标题/路径/说明及中英别名，空查询恢复正常分组，不联网。搜索结果直接进入既有页面，返回仍保留查询；不复制配置编辑器、验证请求或保存服务。
- 一级行保留图标/标题，模型、搜索服务、外观、预算、开关等真实短状态放行尾；空间不足或辅助字号改为纵向自然换行，不缩字。长说明在搜索结果、实际详情或 VoiceOver 提示中保留。
- 设置保存回调返回实际应用的配置，一级页与绑定以该值为准；保存失败沿原错误路径报告并恢复旧显示，不只切换本地开关。Done 只关闭，不重复保存已即时提交的配置。
- 本机资料复用现有编辑器，搜索 push 与原 sheet 分别使用所属导航容器，避免多包一层 NavigationStack/玻璃。

**Provider 状态**

- “已验证”只对应成功完成的请求：会话内身份包含完整 descriptor、模型 ID 与实际 credential 的哈希。配置、选定模型、能力/模型列表或凭据变化清除状态，晚到响应只有匹配当前身份才可显示成功。
- 验证开始先清除旧结果，失败不沿用上次成功。发现模型、验证模型、连接授权分别显示真实操作阶段；登录或取得模型列表不等于所选模型通过验证。
- 身份只在编辑器内存保存，不存凭据或哈希到业务库/日志。Provider 编辑器拆成独立文件，仍由原工厂/验证器/Keychain/外部授权入口执行，代理不触发真实连接。

**Memory 与 Project**

- Memory 文案对应当前自动保存/回执/撤销规则，不再暗示每条均逐次确认；关闭开关影响后续发送的自动写入与模型上下文使用；当前运行继续使用开始时配置，界面明确说明该边界，管理界面保留已存内容。
- 全局管理可按全局/项目/对话归属筛选；行和 scoped 页标题显示真实项目/会话名称，不把每条写成“当前项目”。项目页只管理该 Project scope 的记忆，不把全局或其他聊天记忆搬入其中，也不在该页修改全局开关。
- 当前范围清理只作用于当前可见范围，仍显式确认。编辑内容继续执行原长度/敏感信息/归一化 key 检查，保存/删除失败回滚显示，编辑错误在编辑 Sheet 内反馈。
- Project 首页把记忆与运行记录接到已有指令/会话工作入口；环境、Skills、MCP、能力配置作为直接分组，取消隐藏这些入口的高级中转页。Files/导入继续使用原业务入口与完整 scope；会话/运行数量来自真实关系。

**存储统计**

- `FamiliarStorageInventory` 是只读 ModelActor，在后台创建执行器；用 fetchCount 读取会话/消息/文件条目/版本数，不通过 @Query 将全部消息内容加载到设置页。
- 实际扫描 Application Support/Familiar，按存储目录区分附件、文件/资料、工作区、运行环境、数据库和其他。引用数量不加入字节合计；相同文件资源身份只计一次，不遍历符号链接目标。无法读取的条目/目录明确标成可能不完整，不伪装成完整的零用量。
- 口径是文件字节长度，不是 APFS 分配块/压缩后占用、整个 App 包大小或实时磁盘配额。存储目录与业务对象分别展示：例如 canonical version 引用附件目录时，字节只出现在该目录类别，不再次按 FileVersion 元数据加总。
- 查询可取消，刷新版本防止晚到结果覆盖新测量，耗时未测量。此页只有统计与刷新，不加入清理按钮或自动删除，不触发运行环境准备。

**运行记录**

- 行优先标识所属对话，补真实运行状态和模型/时间；详情先显示状态/时间摘要及实际已保存回复，再展开执行步骤、授权回执和技术上下文。
- 回复按 run.responseMessageID 精确查询；没有回复 ID 时查询为空，不用默认消息或其他会话内容填充。完整 Markdown 只在用户展开时创建，来源继续使用实际消息数据。
- Provider/模型、Run ID、结束原因、资源/Skill 哈希、工具清单仍可检查，放在折叠技术层；按当前 run 限取 Skill 快照。步骤按稳定 activityID 对应 invocation/approval/result，减少重复全量查找，状态使用已有本地化词。
- 自动授权说明覆盖应用现有自动执行规则，不再将所有自动执行误称为“曾记住的授权”；真实风险、范围、回执和技术字段不删，不增加审批或重试路径。

**研究依据与验收**

Telegram 固定提交 `SettingsSearchableItems` 70–145 行定义稳定 ID、别名、路径和展示动作；`PeerInfoSettingsItems` 32–145 行展示分组依据，账号/会员条件不适用本产品；`PeerInfoScreenDisclosureItem` 1–150 行区分标题与行尾状态；`PeerInfoScreenSettingsActions` 23–64 行明确 push/页面替换，`PeerInfoScreenItemSectionContainerNode` 87–133 行按稳定身份更新/释放节点。只记录实际已读片段，不记作完整文件审阅。

统计遵循 Apple 的 [DirectoryEnumerator](https://developer.apple.com/documentation/foundation/filemanager/directoryenumerator) 不遍历链接目标规则，以及 [fileResourceIdentifier](https://developer.apple.com/documentation/foundation/urlresourcevalues/fileresourceidentifier) 的同文件身份比较；硬链接去重、取消和实际资源用量仍需真实运行验证。

所有者真机重点：中英标题/别名/路径及资料搜索返回；大字体/长状态与原保存失败反馈；验证后切模型/Key/Endpoint/能力再返回、发现/登录/验证的区别；Memory 全局与指定项目归属、清理/编辑失败和取消；Project 入口与现有归档/删除限制；存储扫描/取消/重进/刷新、目录口径和不完整标记；完整运行/失败运行/无回复运行的结果、回执、Markdown、技术展开及正确源消息。真实 Provider、SQL、权限和性能不以编译结清。

### 2.7 U5 动效与可访问性专项契约

所有者授权继续 U5。范围限于现有输入/消息/列表的状态切换、辅助操作和系统偏好；不增加消息语义、Provider 请求、授权或数据模型。实现与构建结果见 PLAN；VoiceOver、键盘、系统手势和实际视觉均须由所有者真机验收。

**稳定身份与阅读**

- 输入尾部由同一个原生 SwiftUI Button 承载麦克风/发送/停止，固定 44pt 命中范围；只变图标/颜色和现有动作。语音转写产生文字时继续保留停止语音入口，结束后才进入发送状态；AI 入口仍预留稳定宽度，不重新测量/移动正文。
- 每个挂载的消息时间线持有 `FamiliarEntranceRegistry`，初始化时登记现有消息、Run 和活动块；后续身份首次出现才可作 2.5pt/150ms 的变换与淡入。Lazy 行回收再出现、历史恢复及流式转持久化复用同一个 ID，不重复入场。阅读旧消息或降低动效时仍消费身份，不能在恢复动效后补播。
- Markdown 保留稳定块；文字增量直接追加原文本节点，不逐 token 包裹动画 span。WebView 首次挂载的已有块不播放动画，后续新流式块保持原轻量淡入，Reduce Motion 关闭该动画及流式光标动画；不改变正文测量规则。
- VoiceOver 开启时暂停自动追随；“返回最新”仍可显式定位，定位后继续保护辅助阅读。消息菜单/文本选择继续使用现有 inspection/阅读锚点；列表在 VoiceOver 下不做差异动画。
- 消息菜单保留 UIKit 的有界可见区快照与系统预览；图片保留 Quick Look/系统关闭和已有的 Reduce Motion 无缩放路径。不另加截图浮层、页面副本或私有转场。

**辅助操作与状态**

- 原生消息文本的 `UIAccessibilityCustomAction` 提供复制、选择、已有编辑及符合安全条件的重试。Markdown 继续暴露标题、链接、代码和表格的原 DOM，同时在正文之后提供具名辅助动作；普通视觉下隐藏，硬件键盘聚焦时在正文后显示。动作更新不重建正文或相同按钮；临时动作区高度单独报告，不能覆盖正文。
- 辅助动作与原菜单使用同一个 `FamiliarMessageActions`，调用时检查当前可用操作及视图仍在窗口；不把只读预览变成可编辑消息。选择文本与 Done/两指擦除退出共用原状态，释放仍执行原清理。
- 会话行增加置顶、未读、运行/待确认/失败状态朗读及已有列表动作；运行对象仍禁止移动/删除，编辑模式只切换选择。非当前分类和搜索背后的原列表从辅助树排除；各分类提供“搜索”辅助动作，折叠时不要求用户用下拉手势找输入。
- 输入控件设置稳定的本地化名称，正文值由 UIKit 提供；不改中文组合输入、选区或 first responder 协议。附件移除和搜索清空为 44pt；分类默认改为 48pt，内含 44pt 按钮加上下 2pt 留白。
- 只在真实运行进入待确认、待回答、完成、失败、停止时排队播报短状态，不逐 token/工具结果播报，不移动焦点。播报限定前台、当前可阅读详情且未处于 inspection；锁定、其他 Tab、预览或被 Sheet 遮挡时不播报。主动复制/进入选择有简短回馈。

**系统偏好与验收**

- 自定义玻璃在 Reduce Transparency 或增加对比度时使用系统不透明背景和边框；普通模式继续公开 Liquid Glass。系统 Toolbar/Tab/菜单仍交由系统处理。分隔线在增加对比度时使用系统 separator；Markdown 继续接收原生对比度/字号/颜色，去掉页面禁止缩放标记并提供界面语言。
- 仅编译新增身份去重、动作资格、语义播报及 WebKit 文档结构/焦点保持用例，不启动 Simulator 或执行测试。编译不能证明辅助树、系统动画或焦点在设备上符合预期。
- 所有者重点验收：恢复历史/滚回活动/流式转历史不重复入场；空输入→语音转写→停止→发送/停止 Run 的按钮位置和读音；VoiceOver 从正文/链接/代码到动作、复制/选择/退出与安全重试；分类/搜索/多选的辅助范围和状态；浅/深色、辅助字号、降低动效、降低透明度、增加对比度；菜单/Quick Look 关闭后阅读位置不跳动。上述仍待验收，不报告未经测量的性能或无障碍通过结论。

**Telegram 依据**

固定提交中 `PreparedChatHistoryViewTransition.swift` 70–153 行明确区分 Initial/InteractiveChanges/Reload 和插入/更新；`ChatMessageBubbleItemNode.swift` 5770–5820 行将可访问性标签/状态与独立动作分开；`ChatTextInputActionButtonsNode.swift` 315–469 行共享动作区尺寸；`ChatMessageTransitionNode.swift` 650–728 行保持来源/目标坐标独立。这些是机制依据，不是移植整套 UI 或宣称实机动效相同。余下滚动静止区、资源释放链继续留给 U6。

### 2.8 本轮真机反馈修正与 U6 第一层

所有者反馈设置页密度、聊天菜单尺寸/文案、AI 润色面板及进出详情抖动，并授权修正后继续 U6。反馈是已确认体验问题；本节代码修正不等同于真机已验收，也不将静态风险写成已测量的根因或性能收益。

**设置、顶栏与 AI 润色**

- 设置首页取消可见分组标题，采用 Telegram 式头像/名称/简介、右上搜索/编辑和分组行；路由、搜索目录与本机资料保存不变。默认图标 29pt、图标到文字 16pt，正文上下各 16pt；这些内边距只加在文字上，不将图标高度再叠到行高。去掉 List 行默认上下留白，标准字号整行随正文自然高度约 52pt；辅助字号允许增高。行尾状态单行截断并保留完整辅助值，辅助字号纵排；分组间距 24pt，原生列表提供侧边距和分组背景。
- 聊天返回和省略号都使用系统导航栏的共享玻璃规格，省略号不再叠自己的 44pt 圆圈；主菜单只保留“当前模型”入口，具体模型仍在子菜单。此处替代旧“右侧自画玻璃圆”约定。
- “AI 编辑器”改为“AI 润色”，取消内部 NavigationStack、折叠原文和独立白色底栏。面板改为关闭/标题/模型工具、62pt 图标模式胶囊、一张含风格和原文/结果的内容卡、主操作区；默认显示真实原文。生成、停止和应用使用同一主按钮；成功后支持对照、复制及重新润色。依旧显式生成、只应用草稿、可撤销，保留用户 Provider、工具为空、版本/取消校验及串行执行占用，不引入直接发送。
- 右上模型工具只改变本次模型；辅助信息保留真实服务/模型与数据去向说明。生成未完成时不允许应用，空自定义要求/其他执行占用有禁用反馈；失败不覆盖草稿。

**导航抖动修正的静态依据**

- 原详情先渲染 ProgressView，等任务创建聊天页后才隐藏 Tab Bar，会改变安全区。现在由目的地外层从第一帧固定 Tab Bar 状态；已验证入口先准备会话，已缓存的目的地直接显示并跳过重复查询，不等下一帧切换页面容器。
- 原高度/键盘变化会反复调度带动画的滚到底部。自动跟随改为无动画事务，显式“返回最新”才保留用户触发的滚动；初始 ScrollPosition 在构造时设置。详情离开后冻结几何、DOM 补偿与调度，保留离开前偏移；不让退场的短暂尺寸覆盖阅读位置。
- 离开详情清除焦点；润色退出只有详情仍可见才恢复键盘。生产入口不再重复执行根入口已经完成的示例技能安装。
- 这些修正针对确认存在的布局路径；所有者需复验连续进入/返回、边缘返回取消、键盘开关、长 Markdown/表格/公式高度和 Sheet 进出。仍出现时需设备复现顺序/性能记录继续定位，不宣称已凭编译消除全部抖动。

**U6 第一层：有界呈现、查询和资源**

- 时间线以稳定 ID 建索引，默认展示最近 80 项历史；更早/后续按钮切换有重叠的 80 项窗口并定位旧边缘。查找/深链接直接以目标为中心打开窗口，退出查找恢复原窗口/偏移；返回最新恢复尾部窗口。不把更早消息一次拼到整条尾部，也不为翻页重播旧内容入场。
- 这是展示层分页。控制器完整消息快照继续服务现有发送、压缩、编辑和重试，不截断模型上下文。本节第一层只提供展示窗口；后续持久层按需投影由§2.9独立规定，仍需证明完整模型上下文一致性。
- 历史运行数据按当前会话 runtimeIDs 查询，SQL IN 每批最多 200 个去重 ID；文件按真实 scopeKey 查询。活动、审批、结果、澄清、调用和正文块按 Run 一次建表，替代逐 Run 扫整表/嵌套搜索；文件匹配先限当前 Run。未增加 schema 索引、全文搜索索引或历史迁移链。
- 首页已有状态集合直接跳过元数据初始化查询；项目排序和长按目标按 ID 查询，不逐项目/逐行反复线性定位。
- 会话协调器保存导航路径、Agent/压缩、润色、标题/后续问题及附件导入的所有者；另外最多留两份普通闲置会话。释放前检查草稿保存成功、代次/访问时间/执行状态仍匹配；失败或晚到检查点不释放。附件准备使用成对资源计数，完成时保存检查点，不能把尚在导入的会话当成闲置。
- 释放的会话最多保留 128 份轻量阅读书签，只有偏移/窗口锚点/阅读模式，不持有消息或 WebView。重开从持久草稿/历史恢复；删除清对应书签。书签在内存中，不承诺跨启动阅读位置恢复。
- 缩略图仍按显示尺寸降采样，缓存上限维持 24MiB/120 项提示。相同版本/尺寸请求合并，准备串行；单个读者取消不影响其他读者，无读者的排队工作取消。已开始的 Quick Look 可完成，但取消后不保留无人使用的结果。内存警告清缓存并请求闲置收敛，缓存代次阻止旧在途结果重新填充已清理的缓存；原文件不变。

**源码依据、验证与余项**

Telegram 固定提交的 `PeerInfoScreenDisclosureItem.swift` 154–217 行按文字高度+32pt计算行高、29pt图标和16pt间距；`TextProcessingScreen.swift` 775–807、1090–1125、1239–1260 行将模式、内容和动作布局分层，模式约62pt；`ChatHistoryListNode.swift` 3680–3725 行以历史边界/锚点推进窗口。`ChatMessageInteractiveFileNode.swift` 262–324 行区分资源订阅释放和当前 fetch 的取消；`ChatImageGalleryItem.swift` 341–346 行只处置 status/data/recognition，fetch 的 dispose 被注释，不能当作有效清理依据。仅登记已读片段，不记作全文阅读。

只编译窗口边界、SQL 分批范围、草稿保存后释放/恢复、执行/导入保护、退场几何隔离及缩略图合并/清缓存用例。实际 SQL、取消/内存警告和设备行为仍待验收。现有100/300条消息及大规模会话、连续开关/翻页/查找应由所有者实际采样；无启动耗时、帧率或内存下降百分比。本轮之后先收集视觉/抖动反馈，再专项处理完整历史快照的按需投影及测量证明，不盲目增加缓存或替换渲染器。

### 2.9 U6 历史按需投影与持久层窗口读取

本层将上一层显示窗口延伸到持久层负载查询。`FamiliarChatHistoryStore` 分别提供轻索引、窗口富数据、完整业务消息和最新 AI 回复；所有读取使用调用方的 MainActor ModelContext，以看到检查点的当前事务状态。没有为分页保存或修改消息，也未更换渲染器。

**索引与页负载**

- 索引查询只指定消息 ID/日期/顺序/角色、模型切换 ID/日期和 Run 的身份/状态/最终消息 ID；返回 Sendable 值，不持有 Model、正文、附件、工具结果或上下文。按既有日期/稳定 ID 排序，保留已完成回复的 Run 身份和无回复终态 Run。
- 从该索引选最多80项，再用带会话 ID 的数据库谓词读取所选消息/标记，按关联 Runtime 限定工具与上下文数据；文件继续按 scopeKey 与 Run 限定。SQL `IN` 分批规则仍为200 ID。消息检查点尚无最终 responseMessageID 时，也根据本页消息/正文块找到所属 Run，不能丢掉部分回复或回执。
- 分页只保留本页富快照及当前运行所需数据；轻索引仍覆盖整段会话。一个 Run 内的活动/回执保持完整，不将80项误写成80条工具或内存硬上限。身份索引的线性成本、单 Run 大资源以及 MainActor 查询时间需要设备测量。
- 查询失败保留上个完整页并反馈错误，不能把取数错误当成空历史；首次切换会话失败也不能展示另一个会话的旧页。空历史/查找/压缩资格以全索引表达，避免仅含标记或无回复 Run 的一页被误判为空对话。

Apple 的 [propertiesToFetch](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/propertiestofetch) 允许仅取所需字段；访问未取字段会触发补读。因此索引生成路径禁止遍历正文/附件/Run 上下文关系。本层不是把原有全量富快照包成80项数组；窗口负载由数据库按选定身份读取，完整模型输入有独立读取入口。

**完整业务历史与运行安全**

- `FamiliarChatController.messages/modelSwitches/agentRuns` 现在表达显示页，不再作为发送、压缩或分支的历史来源。发送读完整持久消息，编辑读原消息之前的完整前缀；压缩仍按现有 summaryThroughSequence 和末4条规则处理完整历史。
- 分支和导出读取全会话正文/附件/来源；导出 Sheet 只在生成文件时临时持有完整 DTO。朗读读取最新 AI 回复，不受当前查看旧页影响。完整读取采用与页面相同的正文/来源转换，不退化附件或最终回复块语义；取数失败停止相应操作，不用空上下文继续请求。
- 页内 Run 仍执行原 `requiresInspection` 检查，失败继续保守禁止重试；撤销资格以真实工作范围和当前页/当前 Run 判定。分页只改变展示数据，不授予写权限、删除回执、降低审批或改变编辑提交事务。
- 正文块先验证所属会话的 Run；不同会话的消息/Run/文件不会因调用方提供错误引用混进本页。标题/后续问题与逐 token 生命周期仍沿原检查点，UI 不重放 Runtime。

**导航和阅读归属**

- 查找/深链接先按全索引定位并准备目标窗口；直接打开旧消息不先显示最新页。普通重开先恢复轻量书签再加载数据；返回上一窗口按原锚点读取，恢复偏移。
- 时间线保留稳定的当前呈现 UUID；几何、阅读补偿和自动跟随只接受该实例。另一实例的退场不能关闭新实例或取消其滚动，旧 WebView 的高度补偿也不能修改当前阅读位置。同一会话在导航栈里重现时，重新准备对应页的数据。
- 已读判断使用全索引中的最新 AI 回复 ID，再检查当前真正可见的消息；查看旧页、预览和读取索引均不自动清最新未读。
- Spotlight 把“存在消息或运行”的判断放入存储谓词，只返回 ID/标题/更新时间；生产的索引发布由根入口负责。详情页不再为 Spotlight 遍历全应用消息关系。

**验证范围**

增加245条以上持久消息的窗口/完整读取/编辑前缀/来源附件/最终块回归、205条完整分支、模型标记和大量无回复 Run、跨会话错误引用、旧页在新回复后的稳定性、呈现交接以及 Spotlight 空/非空判断；现有助手分块/流式转历史用例继续编译。没有执行测试、Provider、SQL日志、内存测量或 Simulator。使用完整当前schema，无新实体、字段、迁移、重置或外部依赖。

后续设备重点：连续翻前后页与定位/返回、页外回复和未读、旧消息编辑/安全重试、完整分支/导出/压缩/模型上下文、失败/中断 Run、来源/文件精确版本、内存压力重开与共享会话导航。构建通过与上述实际行为分别记录；只有真实采样才能讨论延迟、掉帧或内存改善。

### 2.10 hwf 看门狗与默认折叠搜索

本轮优先收敛所有者卡死反馈，暂停新增功能。实际报告、采样及推断边界见 [hwf 调查](research/2026-10-19-hwf-hang-investigation.md)。设备三份历史报告确认退出看门狗，两份栈包含消息自定义布局；Xcode 留存控制台同时报告几何重复更新。随后附加的10秒现有进程采样没有捕获到卡死，不作为修正版验收。

所有者确认保持前台后再次采样15秒：15774条主线程样本均包含交互式返回转场，设备也生成同PID的CPU资源报告。已进一步将已读可见性移出布局状态、在UIKit转场开始时暂停阅读补偿、将文件预览导航从懒加载行移到页面、缓存有限的Markdown外观输入。原设备版本现场与修正版构建明确分开，修正版仍待安装与真机复验。

- 气泡测量/放置采用一致的未指定高度提案，包装布局不递归导出显式对齐。
- 阅读补偿与滚动几何分离：视口移动更新基线，行采样布局后合并，过期/离场任务取消；不会把普通滚动当作上方内容增长。
- 首页搜索初次默认折叠；真实拖动前不接受自适应布局回调作为用户位置。首份快照和有效尺寸后恢复，短/空列表也保留54pt（随字号缩放）的搜索滚动范围。下拉连续展开，上滑收回及半程吸附沿原入口，搜索取消恢复分类与偏移。
- 代理只构建，不启动 Simulator，不执行测试，不安装真机；实际卡死消失、输入/长回答阅读、分类切换和下拉搜索由所有者在 hwf 复验。若仍卡死，保持前台进程再采样，不能以历史报告代替新现场。

### 2.11 所有者最新入口精简

2026-10-19 晚所有者明确替代此前的下拉搜索要求：对话首页搜索移到右上角，与新建共用原生 ToolbarItemGroup；点击进入独立搜索页，首页不再展示搜索框。设置首页也取消重复搜索框，从原搜索/编辑按钮组进入搜索页。保留已有本地查询、范围、命中摘要、分页和原设置目录，命中后等待Sheet关闭再进入真实路由；取消保留首页分类与列表位置。

移除旧搜索浮层、滚动展开/吸附、额外搜索高度和编辑恢复分支。项目分类仍浮于列表上方，按分类保存位置；本次不增加第二套搜索或改变数据检索范围。

聊天空对话移除Logo、标题、说明、建议和配置引导，保留顶部及输入区。消息页菜单先列“新对话”；已选照片删除叉号从 `(8,-8)` 调整为 `(2,-2)`，向左下各移6pt，保留44pt命中区和原删除条件。只构建，不启动Simulator或执行视觉测试，所有者真机确认另列。

### 2.12 Telegram动效源码迁移

所有者授权P0–P5，实际迁移对照、代码落点、适配和未执行验收统一见 [专项22](22-telegram-ios-ui-motion-polish.md)。本版替代旧U3的图片QuickLook方案和此前只淡入的发送呈现，保留文档QuickLook及Familiar业务边界。核心对象仍是消息/Run、canonical File/Version、持久草稿；无新schema或重置。源码阅读范围以22的片段登记为准，不把取得整文件记成全文审阅。

## 3. 全应用逐模块优化方向

### 3.1 首页、分类与搜索

对应研究链路：根控制器 → Tab → 聊天列表容器 → 导航与分类 → 列表行/差异更新 → 搜索容器与结果。

- 保留系统原生紧凑 Tab，不缩放、裁切或另造一套底部导航。
- 补齐分类选中项自动进入可见范围、多分类切换、删除当前分类后的回退。搜索折叠状态与当前页共享一个偏移来源；动态高度不能混用固定初始偏移。
- 同时表达置顶和未读，避免当前行使用互斥分支而隐藏置顶。草稿只含附件时也应显示真实摘要；媒体/文件类型不用模糊省略号代替。
- 空搜索显示搜索入口或建议，不扫描全部消息。查询结果摘要围绕命中生成，避免正文后半段命中却只显示前 240 字。
- 搜索使用可取消、有范围和数量限制的本地查询，不在视图构建时遍历全部会话的消息关系。已归档命中明确标记，范围切换不改变会话归属。
- 横向分页进度只更新浮层，不按帧重算所有分类和列表输入。列表快照只随内容/状态边界更新，行配置按稳定 ID 查询。
- 长按预览保持有界、只读；取最近消息时避免为三条预览加载整个历史。多选操作命中真实 ID，运行期间限制继续保留。

Telegram 主动滚动分类条以保持选中项可见：[分类定位](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/HorizontalTabsComponent/Sources/HorizontalTabsComponent.swift#L979)。Familiar 的横向分类分页与行操作应继续避免同轴竞争。

### 3.2 消息排版与阅读

对应研究链路：历史条目 → 相邻条目关系 → 日期头 → 消息正文 → 日期/状态测量。

- 短纯文本气泡适应内容宽度；长 Markdown、代码、表格保留稳定阅读宽度。不能把最大宽度固定比例当作每条消息的实际宽度。
- 时间信息进入气泡本身的布局：短文本考虑末行剩余空间，复杂正文使用独立末行；避免漂在正文外或压住代码/表格。
- 增加日期分隔与阅读定位信息；相邻间距由角色、Run 和内容边界决定。不要把 Telegram 的同作者合并规则直接套到多个 AI Run。
- 工具、文件、正文保持真实顺序；一个 Run 保持稳定身份。审批、失败和回执不能被视觉合并隐藏。
- 消息定位提供短暂高亮及返回原位置的入口。日期跳转作为后续候选，不先增加无完整导航语义的按钮。
- 复杂内容增长、旋转、键盘切换、展开详情和媒体尺寸确定后都要保住阅读锚点。

Telegram 测量末行宽度，并分别处理 RTL 与引用块：[正文和状态测量](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift#L688)。Familiar 应采用测量机制，不照搬已读双勾、成员身份等不属于本产品的状态。

### 3.3 长按、选择与消息导航

- 明确气泡、链接、代码按钮、选择手柄和横向滚动的手势优先级。不能用透明覆盖层拦截全部内容。
- 菜单取消、选择完成、切换会话、视图释放都要对称结束阅读检查状态；关闭菜单不能误触底层操作。
- 将已有“解释／改写／精简选中文本”接入生产消息页；当前相关组件主要出现在视觉 fixture。继续只回填草稿，不自动发送。
- 增加会话内搜索、命中数量、上一个/下一个和命中高亮；搜索、引用、文件来源使用统一稳定消息定位入口。
- 文本选择必须区分显示文本和原文；中文、Emoji、链接、代码、公式附近的范围映射要列入验收，不能以简单空白分词覆盖所有文本。
- VoiceOver 可通过动作访问复制、选择、编辑/安全重试，不能只依赖发现长按手势。

Telegram 在选择层处理显示文本与原文范围转换，并共用复制、引用、翻译等动作链：[文本选择动作](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TextSelectionNode/Sources/TextSelectionNode.swift#L771)。涉及引用的新语义需另行设计，不在本轮文档落盘时加入消息模型。

### 3.4 附件、Files 与媒体浏览

- 附件分别表达导入中、可用、失败，提供移除或重试。没有实际字节进度时使用不定进度，不显示虚构百分比。
- Files 增加类型筛选、排序、日期分组和上下文菜单；保留原归属筛选，聚合浏览不扩大工具授权或文件使用范围。
- 文件行补缩略图及清晰的版本、来源和失效状态。最新版本与历史版本的打开/分享对象不能混淆。
- 图片浏览逐步补齐双击、捏合、连续翻页、页码和返回原缩略图；区分导航缩放转场与真正的图片缩放能力。
- 草稿图片和已发送图片采用一致浏览规则，仍区别可删除与只读。预览更新不应重复重载未变化的文档。
- 按显示尺寸异步生成缩略图；避免主线程加载完整图片、每个文件卡重复全量查找版本。损坏或缺失文件提供可理解的状态。

ImageIO 支持按目标尺寸降采样，适合当前原生技术栈，无须增加图片框架：[Apple 图片内存说明](https://developer.apple.com/videos/play/wwdc2018/416/?time=725)。Telegram 的远程下载状态只能借鉴状态表达方式；Familiar 应显示真实本地导入/准备/可用状态。

### 3.5 设置、Project、Memory 与运行记录

- 设置增加本地搜索：稳定路由 ID、别名、路径提示，直达现有页面；不复制第二份配置保存逻辑。
- 短状态放行尾，长说明进入详情或分组说明，减少所有设置行都占多行的情况。大字体保留自然换行，不能靠缩小文字维持密度。
- Provider“已验证”绑定实际验证过的模型和配置，切换后失效。保存、验证、发现模型和授权登录的状态区别清楚，不把旧成功结果显示为新配置已通过。
- Memory 文案与真实自动记忆规则一致；展示具体项目/会话归属，不能只写“此项目”却不指明对象。
- 存储页区分附件、canonical Files、Workspace 和运行环境；避免重复统计引用。统计和清理分开设计，不能把规范文件当作可随意清除的缓存。
- Project 详情统一指令、会话、文件、Memory 与运行记录的层级，复用已有业务入口和所有权规则，不增加同一对象的另一套编辑器。
- 运行记录按摘要 → 结果 → 技术详情渐进展开；保留实际阶段、失败、回执与可用撤销。活动、记录和错误页面使用一致的状态词汇。
- 权限状态和已有系统设置入口应保留，重点补齐说明、状态刷新和错误恢复，不为了套用 Telegram 样式重做授权语义。

Telegram 设置搜索条目包含标题、别名、路径和展示动作：[设置搜索模型](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift#L70)。这可以映射到 Familiar 的现有设置路由，不需要账号、远程搜索或新后端。

### 3.6 动效、可访问性与资源

- 控件只由一个所有者提供玻璃背景；玻璃限于导航、输入控件和浮层，正文背景保持稳定。
- 先稳定坐标与状态，再做输入到消息、菜单抬升、图片预览和模式切换。新发送只播放一次入场，恢复历史和流式增量不重复播放。
- 麦克风/发送/停止的动作区保留稳定身份与命中范围；状态变化不能挤走正文或吞掉点击。
- 提供 VoiceOver 动作、合理阅读顺序、退出手势和至少 44pt 命中区域。颜色不独自承担失败、未读或待确认语义。
- Reduce Motion、Reduce Transparency、增加对比度和大字体必须有明确路径，不复制 Telegram 私有透镜接口。
- 闲置控制器、图片和渲染器的保留应有边界；运行中会话与导航所需会话优先，草稿先保存。不能用无界会话缓存换取返回速度。
- 性能风险从代码中记录：主线程解码、全量关系遍历、按帧重算快照、线性行查找、无界控制器保留。修复前后无实测数据时不报告提升百分比。

## 4. 实施路线与功能候选

### 4.1 工作顺序

| 阶段 | 内容 | 依赖与进入下一阶段的条件 |
|---|---|---|
| U0 基础交互修复 | 顶部坐标、键盘、输入高度、布局反馈、编辑取消、选区一致性 | 代码构建通过；所有者确认关键阻塞消失。存在不能输入或控件重叠时，不以新动效替代修复 |
| U1 消息阅读 | 气泡宽度、时间、日期、间距、长内容、定位高亮 | 依赖 U0 稳定输入/坐标；所有者确认短文和复杂回答均可阅读，阅读位置不被抢走 |
| U2 首页与搜索 | 分类完整状态、列表摘要、本地搜索、会话内查找 | 依赖 U0 头部布局与 U1 定位；结果/操作命中真实对象，范围和位置能恢复 |
| U3 附件与 Files | 导入状态、缩略图、筛选排序、媒体浏览 | 依赖稳定导航/阅读；预览、分享、版本和归属清楚，失败可恢复 |
| U4 设置与 Project | 设置搜索、紧凑行、状态真实性、详情层级 | 复用现有路由和保存服务；所有者确认导航、保存反馈、文案一致 |
| U5 动效与可访问性 | 输入动作切换、消息入场、预览转场、VoiceOver | 建立在 U0–U4 稳定身份/测量上；不牺牲焦点、阅读位置和命中范围 |
| U6 规模与资源收敛 | 消息分页、列表索引、图片降采样、闲置会话释放 | 静态风险收敛；性能结果另外记录。阻塞基础交互的资源问题可提前进入对应阶段处理 |

每阶段先形成最小专项设计：明确对象、状态所有者、布局/手势契约、失败/取消、所需接口变化及验收。本文不预先承诺新 schema、历史迁移或抽象框架；引入这些内容必须有具体需求依据。

### 4.2 优先候选

| 编号 | 候选 | 最小价值与边界 | 依赖 |
|---|---|---|---|
| C01 | 会话内搜索及定位 | 本地查找、数量、上下一个、高亮、返回阅读位置；不发网络请求 | U1/U2 的稳定消息定位 |
| C02 | 生产消息页选中文本操作 | 接通现有解释/改写/精简能力；只回填草稿，不自动发送 | U0 选区契约、U1 阅读保护 |
| C03 | 文件筛选、排序、上下文菜单 | 利用已有类型/时间/大小/归属数据，不改变文件授权范围 | U3，保留 canonical File/FileVersion |
| C04 | 设置搜索 | 搜索现有设置标题/别名并直达真实页面，展示路径 | U4 的现有路由元数据 |
| C05 | AI 编辑器原文/结果对照 | 提升修改可见性、生成/取消/应用反馈；继续复用用户 Provider，不自动请求或发送 | U0 草稿版本/焦点与既有改写隔离 |

### 4.3 后续产品候选

| 编号 | 候选 | 另行设计的关键语义 |
|---|---|---|
| C06 | 引用回复、局部引用、滑动回复 | 源消息身份、显示文本与原文范围、上下文进入方式、源消息缺失、与代码横滑/返回手势的竞争 |
| C07 | 从指定消息创建分支 | 分支起点、附件/文件引用、授权隔离、历史与真实外部影响，不只画分支卡片 |
| C08 | 消息书签或置顶 | 本地对象身份、搜索/跳转、删除后的处理；不套用社交群管理员语义 |
| C09 | 多图连续浏览 | 集合身份、当前项、页面与缩略图回归、草稿删除和已发送只读边界 |
| C10 | 可保存的润色风格 | 风格归属、命名/编辑/删除、模型无关提示及草稿应用保护 |

候选默认“待评估”，不自动进入实施。引用、分支和书签涉及身份或上下文语义，必须形成专项设计；多图浏览和保存风格也不能只增加按钮而不定义状态生命周期。

## 5. 文档维护、边界与验收

### 5.1 状态与证据

统一使用“待评估 → 待实施 → 已实现并编译 → 真机待验收 → 已验收”。其中“已实现并编译”只表示代码与编译证据，不能代表测试或视觉通过。所有者报告回归后将对应项目重新打开，保留之前编译记录的历史范围，不沿用它结清新问题。

具体状态只在根 PLAN/state 维护；本文维护目标、来源、依赖和验收契约。附录结论是研究快照，不是另一份实时产品状态。研究继续时，在对应文件条目补读深度和行段，不凭“之前看过”升级状态。

### 5.2 产品与技术边界

- 继续使用 SwiftUI、UIKit、WebKit、SwiftData 和公开 Liquid Glass API；不引入 Telegram 整套 UI/存储框架或私有接口。
- 最低 iOS 26；保留现有 Reduce Transparency 路径，不增加旧系统兼容层。
- 不增加账号、云同步、多 Agent 或后台继续执行；不复制没有实际依据的在线状态、已读双勾或下载进度。
- 分类分页列表不叠加同轴会话横滑操作；消息滑动回复另行设计。旧抽屉继续按既有明确要求冻结保留，不因本指引自行删除。
- Provider/BYOK、授权范围、模型上下文、真实回执和文件所有权是约束，不能为了 UI 表面一致改变它们。

### 5.3 验证责任

所有者已明确：**代理只做静态检查及必要的指定 arm64 Simulator 构建，不启动 Simulator 做视觉检查；真机视觉与交互由所有者验收。** 文档变更只检查内容、链接、证据及 diff，无需重复构建已验证的代码基线。

代码实施时编译 App 与相关测试目标，测试执行仍单独记录；不把 build-for-testing 当作运行过测试。Simulator/测试命令若使用且无进展三分钟，按仓库规则终止并记录，不进行无意义重试；视觉检查禁令继续适用。

每阶段给所有者一份短清单：设备/系统、入口与前置状态、复现步骤、预期、实际、问题编号及可选截图。至少覆盖首次进入/返回、空/长内容、键盘与中文输入、菜单/Sheet、浅深色、大字体、降低动态效果/透明度和失败/取消。

编译、测试执行、真实性能、真实 Provider、真机验收分别记证据。没有实测就不填写帧率、内存、启动时间或性能提升比例。

## 附录 A：逐文件研究登记

下表来自固定提交的 68 个候选源文件。行段只表示已读范围；“关键函数片段”不表示整函数或整文件已经审完。“仅检索”条目只能指向后续阅读方向，结论列写明待查事项。所有链接锁定同一提交，不依赖临时研究副本继续存在。

登记字段：源文件完整路径/固定提交链接、阅读深度和范围、机制或待查项、Familiar 对应组件、路线关联。

### A.1 根导航、首页与搜索

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG01 | [submodules/TelegramUI/Sources/TelegramRootController.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/TelegramRootController.swift#L238) | 关键函数片段；238–260 | 根页面与默认选择独立于会话详情 | FamiliarAppShell；U0/U2 |
| TG02 | [submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift#L645) | 关键函数片段；645–735；859–888 | 布局尺寸、选中区域与玻璃层分工；不搬入透镜实现 | FamiliarAppShell；U0/U5 |
| TG03 | [submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListNavigationBar.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListNavigationBar.swift#L15) | 关键函数片段；15–16；308–426；443–455；621–630 | 搜索展开比例、头部可见高度、边缘效果和分类位置 | FamiliarChatProjectPager；U0/U2 |
| TG04 | [submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListHeaderComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListHeaderComponent.swift#L627) | 关键函数片段；627–631；1156–1207 | 标题测量与左右控件分别由单个玻璃容器承载 | FamiliarChatView / FamiliarChatsHome；U0/U5 |
| TG05 | [submodules/TelegramUI/Components/HorizontalTabsComponent/Sources/HorizontalTabsComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/HorizontalTabsComponent/Sources/HorizontalTabsComponent.swift#L683) | 关键函数片段；683–699；913–998 | 选中区域插值、滚动偏移换算与选中项可见性 | FamiliarChatProjectPager；U2 |
| TG06 | [submodules/ChatListUI/Sources/ChatListControllerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListControllerNode.swift#L1740) | 关键函数片段；1740–1838；2267–2339 | 列表偏移接入头部，搜索在中间位置吸附 | FamiliarChatProjectPager / FamiliarConversationList；U0/U2 |
| TG07 | [submodules/ChatListUI/Sources/Node/ChatListItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/Node/ChatListItem.swift#L1503) | 关键函数片段；1503–1597；5440–5508 | 列表摘要的可访问性文本、操作和布局更新收尾；其余行布局待续 | FamiliarConversationList；U2/U5 |
| TG08 | [submodules/ChatListUI/Sources/Node/ChatListViewTransition.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/Node/ChatListViewTransition.swift#L1) | 关键函数片段；1–175 | 稳定 ID 差异更新，区分初始、交互、重载和滚动定位 | FamiliarConversationList；U2/U6 |
| TG09 | [submodules/ChatListUI/Sources/ChatListSearchContainerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListSearchContainerNode.swift#L476) | 关键函数片段；476–484；714–733 | 查询状态入口和空查询处理；其他搜索分支待续 | FamiliarChatsHome；U2 |
| TG10 | [submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift#L1540) | 关键函数片段；1540–1614 | 查询/范围组成检索身份，管理共享查询状态；不移植远程搜索 | FamiliarChatsHome；U2/U6 |
| TG11 | [submodules/ChatListUI/Sources/ChatListSearchPaneContainerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListSearchPaneContainerNode.swift#L283) | 仅检索；283–372（命中） | 已定位分页手势和取消入口，需继续阅读完整竞争与收尾流程 | FamiliarChatProjectPager；U2 |
| TG12 | [submodules/ChatListUI/Sources/ChatListSelection.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListSelection.swift#L1) | 全文审阅；1–87 | 批量操作可用性来自选择集合和真实未读状态 | FamiliarChatsHome；U2 |

### A.2 消息、历史、选择与定位

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG13 | [submodules/TelegramUI/Components/Chat/ChatHistoryEntry/Sources/ChatHistoryEntry.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatHistoryEntry/Sources/ChatHistoryEntry.swift#L53) | 关键函数片段；53–90 | 消息、消息组、未读等条目具有独立稳定身份 | FamiliarChatTimeline；U1/U6 |
| TG14 | [submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatHistoryItemNeighbors.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatHistoryItemNeighbors.swift#L1) | 全文审阅；1–50 | 邻接条目发布日期/合并信息，供布局判断使用 | FamiliarChatTimeline；U1 |
| TG15 | [submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift#L67) | 关键函数片段；67–118；249–310（字段/初始化） | 日期头合并身份、吸附方向与高度；完整浮动转场待续 | FamiliarChatTimeline；U1 |
| TG16 | [submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift#L226) | 关键函数片段；226–305；450–479 | 正文尾部布局输入与状态参数；不据此宣称已审完整排版算法 | FamiliarChatTurn / FamiliarChatRow；U1 |
| TG17 | [submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/StringForMessageTimestampStatus.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/StringForMessageTimestampStatus.swift#L178) | 关键函数片段；178–222 | 导入时间与作者显示分支；完整时间本地化策略待续 | FamiliarChatTurn / FamiliarChatRow；U1 |
| TG18 | [submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift#L870) | 关键函数片段；870–942；1399–1440；5680–5820 | 气泡命中分发、菜单激活来源和可访问性动作 | FamiliarMessageInteraction；U1/U5 |
| TG19 | [submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift#L665) | 关键函数片段；665–735 | 正文末行、RTL/引用块与时间状态共同测量 | FamiliarChatTurn / FamiliarMarkdownWebView；U1 |
| TG20 | [submodules/TelegramUI/Components/Chat/ChatMessageReplyInfoNode/Sources/ChatMessageReplyInfoNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageReplyInfoNode/Sources/ChatMessageReplyInfoNode.swift#L188) | 关键函数片段；188–224；630–664 | 引用摘要和展开行数；源消息跳转须另行设计 | FamiliarChatRow / FamiliarChatTurn；C06 |
| TG21 | [submodules/TelegramUI/Components/Chat/ChatMessageSwipeToReplyNode/Sources/ChatMessageSwipeToReplyNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageSwipeToReplyNode/Sources/ChatMessageSwipeToReplyNode.swift#L146) | 关键函数片段；146–185 | 滑动进度、图标反馈与阈值后的动画；手势触发链待续 | FamiliarMessageInteraction；C06/U5 |
| TG22 | [submodules/TelegramUI/Components/Chat/ChatNavigationButton/Sources/ChatNavigationButton.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatNavigationButton/Sources/ChatNavigationButton.swift#L1) | 全文审阅；1–32 | 导航动作身份独立于 UIBarButtonItem 实例 | FamiliarChatView；U1/U2 |
| TG23 | [submodules/TelegramUI/Sources/ChatHistoryListNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatHistoryListNode.swift#L3680) | 关键函数片段；3680–3725；3730–3784；4051–4080（状态命中） | 历史窗口随边界推进，加载与空历史状态分开 | FamiliarChatTimeline / FamiliarChatController；U6 |
| TG28 | [submodules/TextSelectionNode/Sources/TextSelectionNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TextSelectionNode/Sources/TextSelectionNode.swift#L495) | 关键函数片段；495–560；750–806 | 原文/显示文本范围转换及复制、引用等选择动作 | FamiliarMessageInteraction / FamiliarMarkdownWebView；U0/U1/C02 |
| TG38 | [submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift#L56) | 仅检索；56–115；338（命中） | 已定位菜单上下文/限制入口；不可据此宣称全部动作权限已审 | FamiliarMessageInteraction；U1/C06 |
| TG39 | [submodules/TelegramUI/Sources/Chat/ChatControllerNavigateToMessage.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/Chat/ChatControllerNavigateToMessage.swift#L44) | 关键函数片段；44–53；97–125；228–237 | 稳定消息定位、来源位置与高亮目标，必要时加载目标窗口 | FamiliarChatTimeline；U1/U2 |
| TG40 | [submodules/TelegramUI/Sources/ChatControllerUpdateSearch.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatControllerUpdateSearch.swift#L18) | 关键函数片段；18–62；86–160 | 范围/查询变化驱动搜索，维护数量、当前命中、后续页与高亮 | FamiliarChatsHome / FamiliarChatTimeline；C01/U2 |
| TG41 | [submodules/TelegramUI/Sources/ChatControllerOpenCalendarSearch.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatControllerOpenCalendarSearch.swift) | 待审；未读正文 | 已选入候选，待核对日期跳转入口、结果定位与返回关系 | FamiliarChatTimeline；U1 后续候选 |
| TG42 | [submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageMerge.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageMerge.swift#L1) | 全文审阅；1–15 | 区分不合并、视觉合并和语义合并，避免混成一个布尔值 | FamiliarChatTimeline；U1 |
| TG43 | [submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageMergeFingerprint.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageMergeFingerprint.swift#L180) | 关键函数片段；180–263 | 合并考虑作者、时间和内容边界；Familiar 必须额外尊重 Run 边界 | FamiliarChatTimeline；U1 |
| TG47 | [submodules/TelegramUI/Sources/PreparedChatHistoryViewTransition.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/PreparedChatHistoryViewTransition.swift#L83) | 关键函数片段；70–153 | 已读初始/交互/重载、插入/更新及静止区初始化，完整静止区和滚动算法待读 | FamiliarChatTimeline；U5/U6 |
| TG58 | [submodules/TelegramUI/Sources/ChatHistoryNavigationButtons.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatHistoryNavigationButtons.swift#L58) | 关键函数片段；58–96 | 返回最新按钮角标与其他导航状态分别更新 | FamiliarChatTimeline；U1 |

### A.3 输入、草稿与面板

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG24 | [submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift#L3155) | 关键函数片段；3155–3215；5710–5758 | 正文与占位共享 inset，背景点击明确聚焦实际输入器 | FamiliarComposer / FamiliarComposerTextView；U0 |
| TG25 | [submodules/TelegramUI/Components/Chat/ChatInputTextNode/Sources/ChatRichTextInputNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatInputTextNode/Sources/ChatRichTextInputNode.swift#L127) | 关键函数片段；127–206（接口）；735–790 | 选区/光标坐标与实际 first responder 接口明确分开 | FamiliarComposerTextView；U0/U5 |
| TG26 | [submodules/TelegramUI/Components/Chat/ChatTextInputActionButtonsNode/Sources/ChatTextInputActionButtonsNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatTextInputActionButtonsNode/Sources/ChatTextInputActionButtonsNode.swift#L315) | 关键函数片段；315–376；376–469 | 动作按钮共享布局尺寸，变换期间使用 position/bounds；整体切换链待续 | FamiliarComposer；U0/U5 |
| TG27 | [submodules/ChatInterfaceState/Sources/ChatInterfaceState.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatInterfaceState/Sources/ChatInterfaceState.swift#L512) | 关键函数片段；512–589 | 草稿输入、选区、回复、编辑、历史位置分别建模；不移植同步协议 | FamiliarChatDraftPersistence / FamiliarChatController；U0/U1 |
| TG44 | [submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift#L1711) | 仅检索；1711–1716；1814–1819（命中） | 已定位控制器请求输入焦点的入口，完整加载/恢复流程待续 | FamiliarChatView / FamiliarComposerTextView；U0 |
| TG45 | [submodules/TelegramUI/Components/ChatInputPanelContainer/Sources/ChatInputPanelContainer.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/ChatInputPanelContainer/Sources/ChatInputPanelContainer.swift#L270) | 关键函数片段；270–321 | 面板展开状态、拖动收尾及启用条件；与输入模式切换需共同核对 | FamiliarComposer；U0/U5 |
| TG46 | [submodules/TelegramUI/Components/Chat/ChatInputTextNode/ChatInputTextViewImpl/Sources/ChatInputTextViewImpl.m](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatInputTextNode/ChatInputTextViewImpl/Sources/ChatInputTextViewImpl.m#L1) | 关键函数片段；1–150 | 原生文本控件动作路由、粘贴与按键；包含旧系统/私有路径，不能整段搬入 | FamiliarComposerTextView；U0/U5 |

### A.4 消息转场

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG29 | [submodules/TelegramUI/Components/Chat/ChatMessageTransitionNode/Sources/ChatMessageTransitionNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageTransitionNode/Sources/ChatMessageTransitionNode.swift#L1) | 全文审阅；1–15 | 转场装饰的窄接口；实际动画实现位于另一同名文件 | FamiliarChatTimeline；U5 |
| TG30 | [submodules/TelegramUI/Sources/ChatMessageTransitionNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatMessageTransitionNode.swift#L650) | 关键函数片段；650–728 | 输入来源坐标映射到目标气泡，横纵方向分别驱动 | FamiliarChatTimeline / FamiliarChatScrollState；U5 |

### A.5 附件、文件与媒体

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG31 | [submodules/AttachmentUI/Sources/AttachmentController.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/AttachmentUI/Sources/AttachmentController.swift#L285) | 关键函数片段；285–316（协议）；511–540 | 媒体选择数量与准备进度的观察入口；完整附件控制器生命周期待续 | FamiliarComposer；U3 |
| TG32 | [submodules/GalleryUI/Sources/ZoomableContentGalleryItemNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/ZoomableContentGalleryItemNode.swift#L70) | 关键函数片段；70–110；128–170 | 双击缩放及尺寸变化后重置内容的规则；其余缩放分支待续 | FamiliarDraftImagePreviewView / FamiliarAttachmentPreviewView；U3/C09 |
| TG33 | [submodules/GalleryUI/Sources/GalleryControllerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/GalleryControllerNode.swift#L30) | 仅检索；30–31；112–130；658（命中） | 已定位分页关闭、来源转场和可访问性退出，需追完整生命周期 | FamiliarAttachmentPreviewView；U3/U5 |
| TG34 | [submodules/GalleryUI/Sources/GalleryItemTransitionNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/GalleryItemTransitionNode.swift#L1) | 全文审阅；1–91 | 预览转场保留来源视图、来源矩形和进度回调 | FamiliarImageZoom / FamiliarAttachmentPreviewView；U3/U5 |
| TG35 | [submodules/GalleryUI/Sources/Items/ChatDocumentGalleryItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/Items/ChatDocumentGalleryItem.swift#L96) | 仅检索；96–132（字段） | 已定位文档状态/获取控制字段，完整打开与取消逻辑待读 | FamiliarAttachmentPreviewView；U3 |
| TG36 | [submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift#L133) | 关键函数片段；341–346（释放）；133–172/224–237仍仅检索 | status/data/recognition 释放；fetch dispose 注释无效，完整加载链待续 | FamiliarImageAttachmentView；U3/U6 |
| TG56 | [submodules/TelegramUI/Components/Chat/ChatMessageFileBubbleContentNode/Sources/ChatMessageFileBubbleContentNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageFileBubbleContentNode/Sources/ChatMessageFileBubbleContentNode.swift#L18) | 仅检索；18–100（命中） | 文件气泡把操作交给交互文件节点，需继续追真实状态组合 | FamiliarFileTile；U3 |
| TG57 | [submodules/FileMediaResourceStatus/Sources/FileMediaResourceStatus.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/FileMediaResourceStatus/Sources/FileMediaResourceStatus.swift#L69) | 关键函数片段；69–142 | 区分准备、可用和播放状态；Familiar 只取真实本地导入状态，其余分支待续 | FamiliarFilePresentation；U3 |
| TG62 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/Panes/PeerInfoListPaneNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/Panes/PeerInfoListPaneNode.swift#L79) | 关键函数片段；79–82；100–116（命中）；528–530 | 文件等媒体列表复用历史节点与选择状态；完整筛选/跳转待续 | FamiliarFileLibraryView；U3 |
| TG63 | [submodules/TelegramUI/Components/StorageUsageScreen/Sources/StorageFileListPanelComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/StorageUsageScreen/Sources/StorageFileListPanelComponent.swift#L743) | 关键函数片段；844–954；743/1048–1104 仍仅检索 | 已读可见区域、稳定 ID 复用、选择与文件图标映射；完整释放/缓存边界待续 | FamiliarFileLibraryView；U3/U6 |
| TG65 | [submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift#L294) | 关键函数片段；262–324；609仍仅检索 | 已读订阅释放/当前 fetch 取消，缩略图和完整状态组合待续 | FamiliarFileTile / FamiliarImageAttachmentView；U3/U6 |

### A.6 AI 文本编辑

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG37 | [submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingScreen.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingScreen.swift#L117) | 关键函数片段；117–142（模式）；200–229；775–807；1090–1125；1239–1260 | 三模式状态、统一外部状态与模式/内容/动作布局分层 | FamiliarDraftRewriteSheet；C05 |
| TG66 | [submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingTextAreaComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingTextAreaComponent.swift#L28) | 仅检索；28–90；184–194；362–367（命中） | 已定位文本结果、复制、选择和命中处理，布局/取消流程待深读 | FamiliarDraftRewriteSheet；C05 |
| TG67 | [submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingStyleSelectionComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingStyleSelectionComponent.swift#L18) | 仅检索；18–54；75–76（命中） | 已定位选中风格与创建动作；保存/删除/预览整条链路待读 | FamiliarDraftRewriteSheet；C10 |
| TG68 | [submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingLanguageSelectionComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingLanguageSelectionComponent.swift#L17) | 仅检索；17–115（命中） | 已定位语言与搜索行布局模型；检索、选择和最近项交互待读 | FamiliarDraftRewriteSheet；C05 |

### A.7 设置、Project 参照与存储

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG48 | [submodules/SettingsUI/Sources/SettingsController.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/SettingsUI/Sources/SettingsController.swift#L1) | 全文审阅；1–76 | 该文件主要是设置控制器协议/工厂，不是设置主列表；列表另见 PeerInfoSettingsItems | FamiliarSettingsView；U4 |
| TG49 | [submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift#L70) | 关键函数片段；70–108；4525–4550（搜索入口命中） | 条目含 ID、标题、别名、路径与展示动作；完整分词匹配待续 | FamiliarSettingsView / FamiliarSettingsRoute；C04 |
| TG50 | [submodules/SettingsUI/Sources/Search/SettingsSearchResultItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/SettingsUI/Sources/Search/SettingsSearchResultItem.swift#L76) | 仅检索；76–149（字段/初始化） | 已定位搜索结果标题/路径行组件，布局和可访问性待深读 | FamiliarSettingsView；C04 |
| TG51 | [submodules/SettingsUI/Sources/Search/SettingsSearchRecentQueries.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/SettingsUI/Sources/Search/SettingsSearchRecentQueries.swift#L1) | 全文审阅；1–72 | 最近设置条目按稳定 ID 记录，提供移除和清空 | FamiliarSettingsView；C04 后续扩展 |
| TG52 | [submodules/ItemListUI/Sources/ItemListControllerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ItemListUI/Sources/ItemListControllerNode.swift#L134) | 仅检索；134–178；286；464（命中） | 已定位搜索、空态、焦点目标和布局后动作，完整状态更新待读 | FamiliarSettingsView / FamiliarProjectDetailView；U4/U5 |
| TG53 | [submodules/ItemListUI/Sources/ItemListController.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ItemListUI/Sources/ItemListController.swift#L286) | 仅检索；286；344–377（命中） | 已定位原生玻璃导航与标题模式切换；不移植完整列表框架 | FamiliarSettingsView；U4 |
| TG54 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenItem.swift#L1) | 全文审阅；1–23 | 列表条目身份与节点更新职责分离；不能把注释中的焦点处理当作有效实现 | FamiliarSettingsRowIcon / FamiliarProjectContextRow；U4 |
| TG55 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ListItems/PeerInfoScreenDisclosureItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ListItems/PeerInfoScreenDisclosureItem.swift#L1) | 关键函数片段；1–150；154–217 | 模型、行高/图标/文字与行尾状态测量 | FamiliarSettingsView / FamiliarProjectContextRow；U4/U5 |
| TG59 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift#L32) | 关键函数片段；32–145 | 已读编辑/资料分组和条件状态生成；账号/会员不适用于 Familiar，其他分支待续 | FamiliarSettingsView；U4 |
| TG60 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift#L23) | 关键函数片段；23–64 | 已读 push/栈替换及资料入口，其他导航动作待续 | FamiliarSettingsRoute / FamiliarSettingsView；U4 |
| TG61 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenItemSectionContainerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenItemSectionContainerNode.swift#L39) | 关键函数片段；87–133；39–41 仍仅检索 | 已读稳定项布局/移除和背景高度，完整更新函数待续 | FamiliarSettingsView / FamiliarProjectDetailView；U4 |
| TG64 | [submodules/TelegramUI/Components/StorageUsageScreen/Sources/StorageCategoriesComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/StorageUsageScreen/Sources/StorageCategoriesComponent.swift#L18) | 关键函数片段；18–68 | 存储类别记录大小/占比和选择状态，统计数据与清理动作分开 | FamiliarStorageSettingsView；U4 |

### A.8 阅读进度与待续

当前登记：关键函数片段 46 个；仅检索 12 个；全文审阅 9 个；待审 1 个，共 68 个候选文件。关键函数片段也包含明确标注的检索入口，不能据此把未读分支视为已审。

U0–U6 第一层已按专项补读对应入口；后续继续补完整历史投影、资源生命周期和测量，已读片段以表中行段为准。重点续读 TG11、TG38、TG44、TG47、TG52、TG63、TG65，以及 AI 编辑器结果/风格/语言组件。续读时补实际已读行段和取消/销毁链路；不会自动把“仅检索”批量升级为“关键函数片段”。

## 附录 B：Familiar 对照证据与差距索引

这是 2026-10-18 的代码/真机研究快照，代码行号可能随后续修复移动。符号和行为描述用于定位；修复后实时状态仍以 PLAN/state 为准。表中的静态风险没有性能或崩溃实测结论，优化建议不等于对应机制已经完整实现。

| 编号 | 类型 | Familiar 证据 | 差距或后续检查 | 路线 / 验收重点 |
|---|---|---|---|---|
| F01 | 真机已确认 + 静态排查入口 | [FamiliarChatProjectPager.swift](../Familiar/Presentation/Chat/FamiliarChatProjectPager.swift#L36)，`body` 的安全区、浮层和忽略边缘布局 | 所有者图确认搜索/分类越界；统一系统导航栏、浮层、列表的坐标契约，不能把静态推断当作已验证根因 | U0-01；首次/返回、搜索展开、大字体不重叠 |
| F02 | 真机已确认 + 静态排查入口 | [FamiliarComposerTextView.swift](../Familiar/Presentation/FamiliarComposerTextView.swift#L32)，`updateUIView` 的异步 first responder 同步 | 键盘不出现已确认，具体竞争待定位；明确实际焦点与外部请求的关系及过期回调 | U0-02；首次点击、空白处点击和恢复焦点可输入 |
| F03 | 源码已确认 | [FamiliarComposerView.swift](../Familiar/Presentation/FamiliarComposerView.swift#L180)，`editorHeight`、控制行和玻璃外层 padding | 视口至少 44pt 外加上下 padding，不能等同于侧边 44pt 玻璃控件高度 | U0-03；比较外层总高度与单行中心 |
| F04 | 静态风险 | [FamiliarComposerView.swift](../Familiar/Presentation/FamiliarComposerView.swift#L199)，AI 按钮按 `effectiveTextHeight` 在两个位置切换 | 行数影响占位宽度，宽度又影响行数；尚未运行复现反复切换，需稳定测量基准 | U0-04；阈值附近逐字输入/删除不抖动 |
| F05 | 源码已确认 | [FamiliarChatController.swift](../Familiar/Presentation/FamiliarChatController.swift#L589)，`prepareToEdit` | 确认后进入编辑即删除并保存后续消息、Run 和相关历史；应改为正式提交后处理 | U0-05；取消/失败保留历史，不改变外部影响事实 |
| F06 | 静态检查项 | [FamiliarComposerTextView.swift](../Familiar/Presentation/FamiliarComposerTextView.swift#L43) 和 [草稿检查点](../Familiar/Presentation/Chat/FamiliarChatDraftPersistence.swift#L63) | 已有 marked text 保护及若干入口的选区清理，不能宣称完全缺失；继续统一版本、范围和正文替换契约 | U0-06；中文组合、Emoji、恢复、语音和润色 |
| F07 | 体验不足 + 静态风险 | [FamiliarChatsHome.swift](../Familiar/Presentation/Chat/FamiliarChatsHome.swift#L212)，`searchResults` | 遍历会话消息关系后才取前 100 项，摘要固定取开头 240 字；空查询和深层命中应分别处理 | U2/C01；空查询不扫全部消息，摘要显示实际命中 |
| F08 | 源码已确认 | [FamiliarConversationList.swift](../Familiar/Presentation/Chat/FamiliarConversationList.swift)，`FamiliarConversationListRow` | 未读/置顶使用互斥分支，无法同时呈现；附件草稿和媒体摘要另需补齐 | U2；状态组合可辨认，摘要来自真实数据 |
| F09 | 体验不足 | [FamiliarMessageGroupLayout.swift](../Familiar/Presentation/Chat/FamiliarMessageGroupLayout.swift#L7) 与 [消息条目](../Familiar/Presentation/Chat/FamiliarChatRow.swift#L46) | 布局按可用宽度比例提议，原生文本返回提议宽度；应区分短文本自然宽度与复杂正文最大宽度 | U1；短文本紧凑、复杂正文不挤压 |
| F10 | 体验不足 | [FamiliarChatTimeline.swift](../Familiar/Presentation/Chat/FamiliarChatTimeline.swift#L66)，`history` / `FamiliarTimelineItem` | 已有稳定 Run/消息身份与返回最新，缺日期条目、命中高亮及完整定位返回体验 | U1/U2；跨日历史与搜索跳转清楚且不串对象 |
| F11 | 已有能力未接通 | [FamiliarSelectionActions](../Familiar/Presentation/Chat/FamiliarChatTurn.swift#L687) 与 [视觉 fixture 调用](../Familiar/Presentation/Chat/FamiliarAssistantTurnVisualFixture.swift#L54) | 已有解释/改写/精简等填稿动作，但生产正文没有完整接入这组选择操作；不应重复实现另一套提示生成 | C02；选中内容准确回填，绝不自动发送 |
| F12 | 静态风险 | [消息图片读取](../Familiar/Presentation/Chat/FamiliarChatRow.swift#L106) 与 [草稿图片恢复](../Familiar/Presentation/Chat/FamiliarChatDraftPersistence.swift#L98) | 直接读取 UIImage 的路径需要按显示尺寸降采样、调度和缓存边界；没有实测内存/帧率结论 | U3/U6；保留完整文件，显示使用合适缩略图 |
| F13 | 体验不足 | [FamiliarFileLibraryView.swift](../Familiar/Presentation/Files/FamiliarFileLibraryView.swift#L11) | 已有名称搜索与归属筛选；类型、排序、分组、缩略图与完整上下文操作作为补齐方向 | U3/C03；不改变原 scope 与 FileVersion |
| F14 | 体验不足 | [FamiliarAttachmentQuickLookView.swift](../Familiar/Presentation/FamiliarAttachmentQuickLookView.swift#L69) 与 [草稿图片预览](../Familiar/Presentation/FamiliarComposerView.swift#L710) | QuickLook 数据源为一个 URL；草稿 Image 的导航缩放不等于捏合/双击/多图浏览 | U3/C09；连续浏览、页码、缩略图返回和只读边界 |
| F15 | 体验不足 | [FamiliarSettingsHubView.swift](../Familiar/Presentation/Settings/FamiliarSettingsHubView.swift#L83) | 分组与稳定路由已存在；搜索、路径提示和紧凑状态行可复用这些入口 | U4/C04；搜索结果进入同一真实设置页 |
| F16 | 源码已确认 | [FamiliarModelServiceSettingsView.swift](../Familiar/Presentation/Settings/FamiliarModelServiceSettingsView.swift#L202)，`verified` / `validate` | 验证使用所选模型，但成功标签清理主要绑定 API Key/baseURL；需和实际已验证配置一起失效 | U4；换模型/配置后不显示旧成功为新成功 |
| F17 | 文案/归属检查项 | [Memory 列表](../Familiar/Presentation/Settings/FamiliarPersonalizationSettingsViews.swift#L46) 与 `settings.memory.empty.detail` | “只记住你确认的内容”需按自动记忆实际规则核对；行中已有 scope 类型，但具体对象可发现性不足 | U4；文案与实际行为一致，具体来源可辨认 |
| F18 | 体验不足 | [FamiliarStorageSettingsView](../Familiar/Presentation/Settings/FamiliarPrivacySettingsViews.swift#L93) | 当前主要展示会话/消息数和附件大小；canonical Files、Workspace、运行环境的口径与重复引用需另定 | U4；统计说明准确，不把规范文件误标缓存 |
| F19 | 静态风险 | [FamiliarChatSessionCoordinator.swift](../Familiar/Presentation/Chat/FamiliarChatSessionCoordinator.swift#L29)，`sessions` | 已保留运行和浏览会话，闲置会话释放边界需补读；不能仅凭字典存在断言已发生内存泄漏 | U6；先保存草稿，保住运行/导航所需状态 |
| F20 | 体验不足 + 静态风险 | [FamiliarMessageInteraction.swift](../Familiar/Presentation/Chat/FamiliarMessageInteraction.swift#L43) 与 [renderer.js](../Familiar/Resources/FamiliarMarkdownRenderer/renderer.js#L29) | 已有原生菜单、原位选择、交互区域排除和退出；仍需系统核对选择范围、命中与取消，不记作真机通过 | U1/U5；中文/链接/代码、取消、释放与 VoiceOver |



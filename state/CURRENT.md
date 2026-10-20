# Current State

最后核对：2026-10-19（Telegram源码迁移P0–P5实现收口；真机仍待验收）。

## 阶段

Telegram UI与动效源码迁移P0–P5的代理实现/构建收口，当前等待所有者真机验收和反馈。主要变化为文件Tab完整操作、发送/末行/间距、正式选区动作、原生图库、设置头部和润色细节，详见docs/22与PLAN。U6的80项富数据窗口和完整业务历史分离保持。代理不启动Simulator、不执行测试；卡死修复是否有效、实际手感/SQL/内存和真实Provider结果仍须独立证据。

## 现实状态

- 最新UI迁移：文件Tab重做52/40pt行、类型条、选择/全选、精确版本分享和逐文件删除；冻结ID/Scope并保留部分失败。首页60pt头像上限、源码字号比例和分类100pt前瞻；预览为有界本地富文本。
- 消息呈现：持久化成功后才将发送快照与消息ID关联，采用Telegram 0.3秒横纵曲线；可见区域裁切、过期/离场释放，不再给用户消息叠加soft-rise。输入先提交组合文字，润色入口与回形针纵向共用玻璃；TextKit测量末行时间，RTL/复杂Markdown独立状态行。
- 正式选区动作：Native/iOS26多选区菜单和WK公开Responder菜单接解释/改写/精简/语气/语法。菜单结束后追加草稿，非空隔两换行，保留附件/技能；消息/块/会话身份保护，单一选区所有权，审批/澄清输入占用时不回填。实际WK菜单显示与焦点需真机确认。
- 图片已替换为UIKit原生缩放分页容器；迁移Telegram的50/80pt淡出、视口1/4和速度退出规则，当前图找原缩略图，离屏淡出；草稿可删，消息/Files只读。只保留当前/邻页，图库图像上限3072/512像素；文档仍QuickLook。不是已实测的内存/手势结论。
- 设置资料头部由页级UIKit控制器隔离滚动，迁移原遮罩2路径/22关键帧、缩放/模糊/标题接力，导航收尾后恢复位置；图片只在数据变化解码。AI润色有共享选择指示区域、medium/large Sheet及键盘退出恢复所选高度。所有者检查单见docs/22；未启动Simulator或执行测试。

- 当前阻塞：所有者报告频繁卡死。hwf 三份历史报告为退出看门狗，两份主线程在 `FamiliarMessageGroupLayout` 深层布局；控制台留存几何重复更新警告。已统一气泡测量/放置提案并关闭无用显式对齐递归，阅读补偿改为合并异步处理且随视口更新基线。对现有 PID 41343 附加10秒采样未捕获卡死，代理未安装或运行修正版，不能宣称卡死已消失。证据见 docs/research/2026-10-19-hwf-hang-investigation.md；卡死复验仍开放，重现时优先处理；本轮按所有者授权推进P0–P5。
- 最新所有者反馈替代下拉搜索设计：首页右上角原生搜索/新建按钮组进入独立搜索页，取消后保留原分类/位置，命中后等搜索页关闭再导航；不再挂载搜索框、54pt留位或吸附。设置首页也只保留右上角搜索/编辑组，搜索命中关闭后直达原路由。聊天空白页无引导，菜单“新对话”在首项，照片删除入口向内移6pt；实际视觉/手势待hwf。
- 补充前台证据：同PID 41343的15秒采样确认主线程持续在交互式返回转场内更新UI，CPU资源报告记录约108秒/90秒CPU。可见性已读记录不再发布布局State；UIKit转场开始即暂停阅读补偿，取消返回可恢复；文件预览导航移至页面且入口身份稳定；Markdown外观JSON按有限系统输入缓存。代理未安装或重新采样修正版，不能报告CPU改善或卡死消失。

- U6 历史：`FamiliarChatHistoryStore` 分开身份/日期索引、数据库窗口负载、完整业务消息与最新AI回复。索引仅指定必需字段；本页才加载正文/附件/来源/模型标记/Run回执及上下文，部分助手检查点也保留所属Runtime；文件和Run按会话/工作范围限制。页读取失败不发布半页，切换会话失败不泄露旧页。
- U6 业务边界：`controller.messages/modelSwitches/agentRuns` 为当前页。发送/编辑前缀/压缩/完整分支和导出不依赖此页；朗读取真正最新AI回复。撤销资格和重试检查沿用原作用域/外部影响判断，编辑提交事务不变。完整操作按需持有全历史，单个Run回执仍完整，索引仍线性覆盖该会话，未测量耗时或内存上限。
- U6 导航：定位先准备数据库窗口，书签在选择会话前恢复；页面重现重新读取该页。呈现UUID隔离几何、退场、自动跟随和WebKit补偿，旧实例不能冻结/移动新实例；已读使用全局最新回复ID。Spotlight由根入口按存储存在性谓词和标题字段更新，详情不重复发布索引。

- 本轮 UI：设置首页无可见分组标题，顶部搜索/编辑及本机资料；行按正文高度+32pt、29pt 图标/16pt 间距计算，取消额外 List 行留白。省略号改为系统 Toolbar 玻璃，主菜单仅“当前模型”；AI 润色为图标模式胶囊、统一内容卡和生成/停止/应用主操作，保留用户 Provider、对照/复制/重新润色、版本保护及撤销，不直接发送。
- 进出详情：目的地外层预先隐藏 Tab Bar，已有会话直接显示；初始阅读位置提前构造、自动跟随不动画，离开后忽略几何/DOM补偿并取消调度，清焦点，只有详情可见才恢复润色后的键盘。这些是代码修正，不是已证明所有真机抖动消失。
- U6 第一层：历史按80项展示窗口，围绕稳定目标索引切换早/后页、查找/返回恢复，Runtime 上下文仍完整。运行记录按当前会话的 runtimeIDs 分批200查询，文件按scope查询，再按 Run 建表；首页已有状态不重复初始化，项目与长按目标按 ID 找。
- U6 生命周期：导航、Agent/压缩、润色/后处理/附件导入所有者受保护；其他闲置会话额外最多2份，保存成功且身份/代次/访问仍匹配后释放。最多128份内存阅读书签不持有消息/WebView；附件完成也建立保存检查点。缩略图共享/串行准备、读者取消、24MiB/120项缓存提示、内存警告清理和代次隔离；原文件不变。实际 SQL、资源峰值/取消与设备行为待验收。

- U5：同一个 44pt 输入动作 Button 承载语音/发送/停止；转写时保留停止。时间线按稳定 ID 登记入场，初始内容/滚回复用不补播，WebView 初次恢复不动画，文字增量不再包动画 span。
- U5 辅助阅读：原生文本动作、Markdown 结构化 DOM 与具名辅助动作并存；选择支持 Done/两指擦除退出。列表状态/操作、分类搜索和非当前页/搜索背景的辅助树边界已接入；VoiceOver 暂停自动追随，语义边界只在前台详情排队播报，不移动焦点。实际辅助行为尚未验收。
- U5 系统偏好：附件/搜索目标 44pt，分类胶囊默认 48pt；输入名称补齐；自定义玻璃在降低透明度或增加对比度时实色化，Markdown 保持语义颜色/字号/语言。系统菜单/Quick Look 仍由系统处理。

- U4 设置：统一全部路由目录和本地标题/别名/路径搜索，含原资料编辑；状态行紧凑/大字体纵排，保存以实际应用值为准。Provider 校验使用会话配置/模型/凭据身份，变化/失败不保留成功；发现、验证与登录状态分开。
- U4 Memory/Project：自动记忆文案与当前规则一致，显示真实归属，可按类型/具体项目管理并确认清理；保存失败回滚、编辑错误由 Sheet 反馈。Project 直接进入原记忆/运行/环境配置页面，范围与授权未变。
- U4 存储/运行：后台读取逻辑计数和本机文件字节，目录分组/身份去重/符号链接排除、取消及不完整标记，无自动清理。运行先摘要/真实回复/状态，再展开回执和技术上下文，Skill 查询限当前 run；无新模型请求或授权逻辑。上述实际扫描、SQL、保存故障与 UI 待所有者真机。

- U3 Files：类型/归属/名称筛选、四种排序及时间分组、菜单/版本精确预览分享；缺失版本状态和原删除确认保留。缩略图后台降采样/系统生成，内存成本提示，不加载完整图到恢复草稿；图片以托管附件字节为准，附件变化即时保存检查点。
- U3 附件：逐项准备/失败/完成、取消/重试、串行准备、数量限制含排队/失败项；失败项处理后发送。实际草稿附件身份+尝试版本防止同会话进入编辑时晚到结果附错草稿；清理保留全部已保存引用，未完成导入不支持跨重启续传。
- U3图片旧QuickLook呈现已被本轮P3图库替代；文档QL/HTML的URL身份、CSP和范围规则保留，图库仍持有阅读检查。

- U2 首页：分类选中项自动进入可见范围，分页进度只驱动浮层；预分组列表快照、按 ID 配置行、版本化特殊行与屏幕外多选同步。每页草稿入口独立，取消搜索恢复列表偏移；置顶/未读并存，归档角标统计归档范围，摘要含实际附件，预览限取最近三条消息。
- U2 搜索：独立 ModelActor 读取持久消息/标题，200ms 防抖、可取消/版本检查、当前分类或全部范围，每页 50 条/真实计数/后续加载。空查询不检索，生产视图不遍历所有消息关系；命中摘要按字符边界围绕关键词，归档明确标记。会话内查找含上/下、关键词高亮、稳定 ID 定位和退出恢复阅读；统计单位为匹配消息，查找期间不清未读。WebKit 范围标记不接收触摸或改正文 DOM；实际 SQL/手势/视觉尚未运行验收。

- U0 代码现状：原生导航行与安全视口内浮层分开，只有列表延伸到栏后；空搜索玻璃收起即移除。焦点用普通 Binding 请求、UIKit delegate 回报并取消过期任务，消息菜单退场后再请求编辑焦点。输入外层高度统一，AI/动作尾部空间固定，不再按行数来回移动入口。
- 最新输入修正：独立无限高 TextKit 测量所有尾部空行；最多六行后框内滚动和裁切，光标保持可见。U1 增加短纯文本自适应气泡、气泡内时间、日期分隔、相邻用户间距，以及消息定位高亮/返回阅读位置；复杂 Markdown 与真实 Run 内容顺序保留，均待真机确认。
- 设置顶部新增本机头像、昵称与简介，照片降采样保存，资料不进入模型上下文。新会话完整回复后的无工具 Provider 请求生成摘要标题；人工命名与过期结果通过 origin/revision 保护，失败保留默认标题。不取第一句作为正式标题。
- 按所有者“全部删掉所有之前的”授权，启动只清理旧 titleOrigin=nil 对话，复用现有删除/归属事务，保留 Project 本身及配置。新增会话 origin 非空，重复启动不清理新历史；独立未发送草稿保留。会话仅增可空 titleOrigin/titleRevision，当前 schema/实体数/业务代际不变，旧存储演进和实际删除尚未运行验收。
- U0 编辑/输入：归一化 UTF-16 选区替代旧 String 索引，草稿正文版本阻止晚到润色，操作前提交 marked text。编辑保存原草稿备份；原历史在新完整回复保存成功时才同事务替换。失败/取消恢复编辑稿，已产生的失败尝试保留可查。当前编辑生成期间该输入锁定，停止和其他会话草稿仍可用。
- 草稿实体新增可空 editStateData 保存编辑态/原草稿及附件引用，清理覆盖两份引用；schema 仍 5.0.0、39 实体、业务代际 5-work-scopes，不增加历史迁移链或再次重置。存储演进和故障路径尚未运行验收。
- 全应用总指引已建立：68 个候选源文件按阅读深度登记；当前已推进 U6 历史按需投影；设备测量尚未完成。原症状和最新交互仍待所有者真机验收。
- 本轮 R0–R5 已接入：原生文件/对话/设置三 Tab，最近/项目分页、搜索、归档、独立草稿、原生列表预览和多选；旧抽屉保持编译、生产不挂载。
- 唯一当前 schema 5.0.0 增至 39 实体，新增持久草稿与会话列表状态，业务代际不变。正文、UTF-16 选区、技能、托管附件分别保存；附件清理覆盖全部草稿。完整回复与未读一起保存，正式详情末尾可见才已读。
- 根会话协调器保留控制器与唯一前台执行占用，查看路由和运行会话分离；返回列表/切 Tab 不取消前台任务，其他会话可读和编辑草稿，不启动第二个 Agent/润色。
- 聊天改为用户右/AI 左，保留生产 Markdown、工具与文件呈现；独立技能菜单取代斜线触发，附件入口为回形针。原生 AI 润色提供翻译/风格/修正，复用用户 Provider、无工具、不进 Agent；预览后应用草稿并可撤销，校验版本和晚到结果。
- 首页修正：完整移除 Tab bottom accessory，系统三 Tab 不缩放或裁切；运行入口仅在首页中央按真实任务显示，无任务留空。首页没有“聊天”标题，项目分类为完整玻璃胶囊、覆盖在列表上方；草稿与归档进入列表。搜索默认收起，真实偏移驱动展开、吸附与分类位置，列表自行处理内容/指示器 inset。
- 详情修正：中央模型胶囊已移除，模型切换归入省略号；右侧省略号为系统 Toolbar 单层玻璃，与返回按钮交由系统统一尺寸，去掉整条导航背景与顶部滚动边缘效果；技能入口固定纯图标。原生 UITextView 统一正文、占位、实际高度、焦点和 UTF-16 选区，中文 marked text 存在时不替换正文/选区。复制与重试移入原生长按菜单，原位选择期间暂停消息菜单并保护阅读位置；来源、后续问题与代码复制保留。UI 测试已改用消息终态标识，仅编译、不执行。
- 所有者负责这轮真机视觉验收，代理不再启动 Simulator 做视觉检查。下文保留此前功能及验收边界；历史测试结果不覆盖这次 UI 修改。
- 部署目标 iOS 26.0（全部 iOS target）；使用公开 Liquid Glass；降低透明度或增加对比度时自定义控件采用系统实色背景和边框。
- 复杂 Markdown 渲染保留非持久 WebKit；无 Markdown/链接的已完成短 AI 文本使用原生文本组件，原生渲染评估依赖未恢复。
- 默认模型 DeepSeek `deepseek-v4-flash`，目录中未声明图片输入，图片走 Apple Vision 证据。
- S1 历史基线证据：2026-10-17 arm64 iPhone 18 Pro Simulator `build-for-testing` 成功；S1 与 assistant-turn persistence 共 79 个用例真实通过。真实 WebKit 双引用同编号检查通过；浅/深色及大字体 3 项生产 UI 用例通过，截图已生成；真实模型与所有者验收独立见验收文档。

## 实施与待验证边界

- 搜索：上述 Key 保存/校验竞态、失败缓存与无进展混淆、引擎重排、首轮暴露、地区参数、压缩/中文解码已实施修复；请求数量和共享预算已收口。来源按已观测重定向归一，严格只列被引用来源。测试与真实服务验收见 docs/15-s1-search-acceptance.md；免 Key 搜索仍依赖服务 HTML 与 challenge 状态。已去掉中文→中国市场的自动映射和强制中文搜索词，原始搜索词中的地域仅由问题语义决定。
- 归属：普通对话无 Project，稳定草稿 ID，File/Workspace/Environment/授权按 project/conversation 完整 scope 隔离。业务代际 5-work-scopes 将在新版首次正常启动清理全部旧业务数据，保留凭据、模型/搜索配置和外观偏好；本次未启动 App，未实际触发重置。
- 生命周期：移动复制关联文件并保留历史引用映射，清摘要与旧范围授权；普通删除清独有文件与 Workspace；项目删除先转存聊天文件再转普通。
- 授权：S2a 已接入可撤销内置文件/Workspace 写入和经 Swift 检查且 checkpoint 成功的离线 Shell 自动执行。S2b 已实现：第 3 级外部影响（EventKit 创建/更新、通知、剪贴板、相册、alarm_schedule、skill_install、已信任 MCP）首次询问并默认「始终允许此类」，`.always` 按 scope + 能力版本匹配；删除类、alarm_cancel、未信任 MCP 每次询问；Memory 开关开启时自动写入并可撤销；environment_prepare 来自配置源时自动执行并保留会话撤销；MCP 信任为按服务器的用户设置。全部只编译未执行；真机行为验收清单见 docs/17-s2b-authorization-design.md §5。完整 S2 未标完成。
- 抽屉/顶栏：旧抽屉视图和手势冻结，生产不存在侧栏入口或边缘触摸区；聊天顶栏使用原生导航和模型/操作菜单，项目筛选来自首页。
- iSH：`.documents` 组（shell_execute/environment_prepare/environment_status/file_publish）默认启用，主界面出现后后台低优先级预热（幂等、失败静默）；rootfs 预装 py3-lxml/py3-pillow、python-docx/openpyxl/python-pptx/fpdf2/pypdf/markdown 与 Noto Sans SC 子集，实测 55.0 MiB（57,601,472 字节）；Shell Outputs 捕获后 best-effort 校验并标注失败；PPTX 已进入格式/校验/file_publish；内置 documents Skill 模板；终端 watchdog 不计准备时间。guest 冒烟（中文 PDF/DOCX/XLSX/PPTX）在重建镜像时通过；真机从未执行，冷热启动耗时与内存峰值待所有者记录。
- UI：设置入口被历史触摸区遮挡的问题已修复。S3 已完成呈现收敛：工具结果只保留活动行（Sheet 详情，含 receipt/records/Shell/技术详情）、行内引用+来源 Sheet、统一文件卡、输入区审批/澄清；task_plan/present_*/prepare_share 与 diff/code 等呈现整体移除；消息视图从单文件 2765 行拆为 `Presentation/Chat/` 六个文件；侧栏为原生 List（新对话/搜索/Pinned/Projects/最近/设置）；省略号移除重复 Memory 入口；Composer 添加菜单为原生 Menu（去掉 180ms sleep）。仍有约 22 种自定义 row、18 种卡片外观与两套运行记录 UI（S5/后续处理）。
- 测试执行：当前 iPhone 18 Pro 可执行定向单测；早期 UI 失败后的 xcresult 汇总曾无进展 180 秒并被 watchdog 终止；后续修复引用保存与设置触摸区，最终 3 项 UI 用例及结果包正常通过。S0 其余测试与所有者验收仍未补齐。

## 验收

本次 S1 的真实服务、截图所有者过目与真机验收分别记录在 docs/15-s1-search-acceptance.md；历史编译证据不代替本次测试。

## 本切片验证边界

U4：2026-10-18 指定 arm64 iPhone 18 Pro / iOS 27.0 的 Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`，最终日志无 warning/error），App、单元测试及 UI 测试目标均编译。日志 `/tmp/FamiliarU4-wrap-closeout-build.log`。中英各 1196 键，无重复且集合一致，22 个设置目录条目的资源键齐全；plutil、JS 语法、diff 和测试套件清单检查通过。新目录覆盖/中英别名、Provider 验证身份、存储去重/链接隔离回归只编译、不执行；未启动 Simulator 或截图。真实 Provider、SQL/存储扫描、保存失败与真机视觉仍待所有者。

U3：2026-10-18 指定 arm64 iPhone 18 Pro / iOS 27.0 的 Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`，最终日志无 warning/error），App、单元测试及 UI 测试目标均编译。日志 `/tmp/FamiliarU3-closeout-final-build.log`。中英各 1160 键，无重复且集合一致；plutil、JS 语法、diff 和测试套件清单检查通过。分类、缩略图尺寸、托管附件字节/无完整位图恢复、附件草稿身份新回归只编译、不执行；没有启动 Simulator 或截图，系统缩放/分页/分享、导入失败/取消、存储恢复及资源峰值待所有者真机。

U2：2026-10-18 指定 arm64 iPhone 18 Pro / iOS 27.0 的 Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`，最终日志无 warning/error），App、单元测试和 UI 测试目标均编译。日志 `/tmp/FamiliarU2-closeout-final-build.log`。中英各 1129 键，无重复且集合一致；plutil、JS 语法、diff 和测试套件清单检查通过。本地范围/归档/空查询/分页、Unicode 摘要、附件草稿等新回归用例只编译、不执行。没有启动 Simulator、运行 SQL/真实 WebKit、截图或性能测量；真机交互和视觉待所有者。

U0 反馈修正/U1：2026-10-18 指定 arm64 iPhone 18 Pro / iOS 27.0 的 Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`，最终日志无 warning/error），App、单元测试与 UI 测试目标全部编译。日志 `/tmp/FamiliarU1-closeout-build.log`。中英各 1118 键、集合一致且无重复；plutil、JS 语法、diff 和测试套件清单检查通过。新定向用例覆盖空白段落高度、正文分流/跨天、旧对话清理幂等与新数据保护、摘要无工具/终态；仅编译、未执行。未启动 Simulator 或 App；旧存储实际演进/清理、真实 Provider 标题与本轮视觉交互均待所有者。

U0：2026-10-18 指定 arm64 iPhone 18 Pro / iOS 27.0 的 Debug `build-for-testing` 成功（exit 0，最终日志无 warning/error），App、单测和 UI 测试目标均编译。日志 `/tmp/FamiliarU0-closeout-build.log`。中英各 1110 键、集合一致且无重复，plutil、JS 语法、diff、测试套件清单检查通过。选区、编辑取消/备份恢复、事务回滚/成功替换与草稿版本回归用例仅编译；没有本轮测试执行、Simulator 视觉或真机通过证据。

本次 UI 反馈修正：2026-10-18 指定 arm64 iPhone 18 Pro / iOS 27.0 的 Debug `build-for-testing` 成功（exit 0，最终日志无 warning/error），App、单测和 UI 测试目标均编译。日志 `/tmp/FamiliarGlass-closeout-build.log`。中英各 1105 键、集合一致且无重复，plutil、JS 语法和 diff 检查通过。按所有者最新要求只构建，不执行测试或 Simulator 视觉检查；真机验收仍待所有者确认。

2026-10-18 重构：35 个改动 Swift 文件语法解析通过；中英资源各 1103 键、无重复且集合一致；`git diff --check` 通过。App、单测及 UI 测试目标的指定 arm64 iPhone 18 Pro / iOS 27.0 `build-for-testing` 成功（exit 0，无源码 warning/error；两条构建工具 metadata 提示），日志 `/tmp/FamiliarTelegram-wrap-build.log`。本路线此前定向测试未进入执行即卡在 Simulator worker/安装启动，按无进展规则中断；安装未成功，未取得本路线运行测试、截图或性能通过证据。旧 S1 通过结果不覆盖此次改动。真实 Provider 与真机视觉待验收。

此前 S2–S6 按所有者“构建通过就行，真机视觉我验收”的要求只构建 App 与测试目标，没有执行对应 Simulator 测试、启动或截图。构建结果与未执行项目见 docs/16、17、18；前述 S1 测试结果只属于 S1 基线，不能视为后续架构变更的运行通过。

S2b 与 S4 的指定 arm64 iPhone 18 Pro `build-for-testing` 均成功（exit 0，TEST BUILD SUCCEEDED，无源码 warning/error）；S3 同样 `build-for-testing` 成功。双语 strings 1045 键、键集合一致；S4 的 rootfs 在 guest 冒烟（中文 PDF/DOCX/XLSX/PPTX）通过后重建并安装，供应链校验通过；未运行 Simulator/真机用例，真机验收清单见 docs/17 §5 与 docs/18 §5，S3 的三态截图与 VoiceOver 检查待所有者执行。


U5：2026-10-18 指定 arm64 iPhone 18 Pro / iOS 27.0 Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`，最终日志无 warning/error），App 和两类测试目标均编译。日志 `/tmp/FamiliarU5-acceptance-build.log`。中英各 1201 键，无重复、集合一致；plutil、JS 语法、diff 和套件清单静态检查通过。身份/动作/播报/WebKit 回归仅编译，不执行；未启动 Simulator、截图或真实 Provider。VoiceOver、键盘、系统偏好、预览转场与设备视觉待所有者。


本轮 UI 反馈/U6 第一层：2026-10-18 指定 arm64 iPhone 18 Pro / iOS 27.0 Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`，最终日志无 warning/error），App 和两类测试目标均编译。日志 `/tmp/FamiliarUIFeedback-U6-acceptance-build.log`。中英各1206键，无重复且集合一致，plutil/JS/diff/套件清单检查通过。全部回归仅编译，不执行测试或启动 Simulator；真机视觉/抖动、实际 SQL/内存和真实 Provider 独立待验收。


U6 历史投影：2026-10-19 指定 arm64 iPhone 18 Pro / iOS 27.0 Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`，最终日志无 warning/error），App/单元测试/UI测试目标编译。日志 `/tmp/FamiliarU6-history-final-build.log`。中英各1206键、无重复/集合一致，plutil/JS/diff/套件清单静态检查通过。新增SQL窗口/完整输入/前缀/分支/来源块/范围/呈现/Spotlight用例只编译，不运行；无 Simulator、真实 Provider 或性能证据。


Telegram动效迁移收尾：2026-10-19，指定 iPhone 18 Pro / iOS 27.0 / arm64 Debug `build-for-testing`；日志 `/tmp/Familiar-Telegram-motion-final-build.log`。App与两类测试目标编译，回归只编译未执行；中英各1213键、集合一致无重复，plutil/JS/diff/套件清单静态检查通过。无Simulator启动、截图、设备安装或新性能采样；新图库/菜单/头像和卡死消失与否均待所有者。

# Familiar 当前实施账本

目标：Telegram iOS视觉与交互的AI问答App。固定上游f1dd7a2；在main分批推进。设计只在[UI规范](docs/03-ui-ux-design.md)，逐项目标和状态只在[320项账本](docs/telegram-ios-ui-checklist.md)，源码阅读只在[登记](docs/research/telegram-ios-source-map.md)。

## 当前批次：进入富文本会话闪烁

- [x] 历史行不再播放新回复入场动画；仅实时新增回复保留原动效，异步发布历史页也直接呈现。
- [x] 富文本高度和占位交接合为一个值发布；首个有效高度前隐藏 WebKit 正文，避免原生占位与网页文字叠绘及二次布局。
- [x] 跟随最新时使用原生底部尺寸锚定，已在底部不再排队重复滚动；阅读旧内容时保留顶部与现有阅读补偿。
- [x] 会话进入页固定持有已接受的会话；后台刷新不切回加载视图，同一定位已加载时不重复读取；初始窗口匹配时不重复发起页导航。
- [x] 新增首个有效高度／占位交接／重排不重播占位回归；App／单测／UI测试目标具体 arm64 Debug build-for-testing 通过，exit 0、无 warning/error，日志 `/tmp/familiar-chat-entry-flicker-build.log`。仅编译，未执行用例或启动 Simulator。
- [ ] 所有者设备：冷启动打开含代码／表格／公式的旧对话，返回后重入、长历史翻页、阅读中流式新增、键盘与旋转；确认无闪烁、文字叠影或来回跳位。代码风险已修正，尚无运行复现和视觉通过证据。

## 已实施基线：性能与可靠性 A → G

保留下面未提交的审核修复及三个能力的注释停用；在 main 实施，不改 schema、签名、依赖或用户数据。采集方案与空基线表见 [性能验收](docs/12-performance-and-reliability.md)。

- [x] A 代码：系统 signpost、真实持久历史夹具和 App／WebContent 内存口径分离。
- [x] A 具体 arm64 Debug build-for-testing 通过（App／单测／UI测试），日志 `/tmp/familiar-performance-A-build.log`；一项 AppIntents metadata 提示；测试未执行，设备基线待采集。
- [x] B 静态复核 TextKit／返回暂停／菜单身份／iPad 分享锚点，保留已有保护；运行记录读取、审批关联与终态收尾错误传播，澄清定向查询，终态失败回滚。新增跨 Run 收尾和旧呈现不能结束新阅读的回归。
- [x] B App／单测／UI测试具体 arm64 build-for-testing 通过，`/tmp/familiar-performance-B-build.log`；测试未执行，运行卡死与设备反馈仍待采集。
- [x] C 上下文／图片／审计哈希、文档／文本复制、网页解码与字节校验后台准备；回到主线程复核草稿／scope／版本，取消或目标失效清理产物。Shell 不再启动预热，notPrepared 可配置偏好，现有终端与工具按需准备。
- [x] C App／单测／UI测试具体 arm64 build-for-testing 通过，`/tmp/familiar-performance-C-build-tests.log`；已有导入／网页保存回归已适配 async，并补取消后不创建记录或字节用例；仅编译。
- [x] D 后台只读 ModelActor 返回索引／页面 DTO，完整发送历史独立读取；保存后刷新、会话／scope／代次和导航呈现保护，终态交接等待持久页面。首页排序分组与运行小标记分离，搜索 actor 与查询计数复用。
- [x] D App／单测／UI测试具体 arm64 build-for-testing 通过，`/tmp/familiar-performance-D-build-final.log`；历史夹具走后台生产读取，旧用例等待异步边界，并补过期选择／失败保留页面／新检查点和完整历史回归；仅编译。
- [x] E 块级展示直接接收 delta，可见性 lease 防止旧 renderer 停掉新 renderer；完整 Runtime 文本与检查点不变，终态立即 flush。16KiB 以上流式 Markdown 按固定 120ms 发布节奏合并，非 debounce，保留 500ms 缓冲兜底。
- [x] E 高亮缓存每 renderer 最多32项／约1MiB字符串成本，Mermaid 复用既有内容签名并避免重复主题初始化；文档代次同时隔离 JS 消息与完成回调，WebContent 退出只重载一次，随后原生文本降级。
- [x] E App／单测／UI测试具体 arm64 build-for-testing 通过，`/tmp/familiar-performance-E-build-complete.log`；node --check 通过；新增 Unicode／长 delta、显示 lease、单次 WebContent 恢复和缓存复用／清理回归，仅编译。
- [x] F 保留缩略图单飞／取消／purge 代次、图库三页与会话淘汰边界；缩放页不再跨图片加载 await 强持有自身，离场／析构取消等待；内存警告释放每个 renderer 的可重建高亮缓存。
- [x] F App／单测／UI测试具体 arm64 build-for-testing 通过，`/tmp/familiar-performance-F-build.log`；一项异步 API 提示已在 G 改用 async。没有设备内存图，不报告泄漏数量或内存下降。
- [x] G 消息准备／网页保存／历史加载反馈与只读重载入口；跨等待归属复核、错误传播、失败保留当前页面与 Undo 状态，执行重试沿用不确定写入检查。
- [x] 消息附件正式复制、大小／SHA-256／提取文本校验也移至后台；由附件存储层构造的准备回执绑定 message／scope／附件 ID／路径。再次验证草稿与归属后一次性保存，准备失败不回滚等待期间其他界面改动。补源文件变化清理、同 UUID 不同 scope 拒绝回归。
- [x] 搜索以实际返回页终止分页，复用计数时不会因期间删除数据而持续提供空页；新增删除后翻页与重新查询回归。
- [x] 异步页发布前复核呈现 ID 与真实拖动代次，时间线按已加载页选择数据；按钮 tracking 不误取消翻页。补旧呈现请求拒绝与 tracking 点按加载回归，仅编译。
- [x] 最终 App／单测／UI测试具体 arm64 Debug build-for-testing：exit 0、TEST BUILD SUCCEEDED，无 warning/error，日志 `/tmp/familiar-performance-final-delivery.log`；包含全部上述修改。测试未执行。
- [x] 最终静态／产物检查：1205 中英有效键，集合一致且无重复；plutil、renderer.js语法、变更及新增 Markdown 本地链接、git diff --check 通过；无 schema／依赖锁／工程签名配置变更。App 与 debug dylib 无 HealthKit／WeatherKit／Speech 直接链接或相关录音 API，处理后的权限与隐私清单无停用项，原注释文件保留；state 已核对更新。
- [ ] 所有者真实性能／服务／故障与设备验收；没有采样不填改善百分比。

目的地：iPhone 18 Pro／iOS 27.0／arm64，1041DD9D-AC70-4DDD-9D34-52514C3E491F，前后均 Shutdown；DerivedData `/tmp/FamiliarPerformanceDerived`，复用既有锁定 SourcePackages，串行构建。未运行 App、执行测试、安装设备、修改签名或清理用户数据；Git 发布按所有者指令执行；推送触发现有 iOS CI 和网站自动部署，结果以工作流为准。尚未重提 App Store 审核。Release 设备归档、五组前后性能对照、20轮故障复验与内存图仍待所有者。

下一项：按性能验收文档采集当前 Release 的实际设备证据，再按确认热点定点优化；旧 R4／320项视觉与真实服务验收不因本轮编译自动关闭。

## 保留基线：App Review 1.0 (3) 功能注释停用

- [x] 按所有者最新要求将麦克风转写、HealthKit 与 WeatherKit 原实现恢复为注释，保留源码；工具注册、设置入口、权限和签名能力同步停用。
- [x] 输入框只保留发送／停止，空草稿禁用发送；系统／远程回复朗读、相机、地图与其他原生工具保留。
- [x] 注释停用过期测试／benchmark；合规套件检查当前发布声明与注册表无录音／健康／天气能力，更新中英文文案、隐私政策与审核回复草稿。
- [x] 历史重试安全检查只解码快照中的工具名和读写类型，避免停用能力使旧快照解码失败；新增读／可撤销写／破坏性写及无效 effect 回归，仅编译不执行。
- [x] 最终 Debug build-for-testing：App／单测／UI 测试目标具体 arm64 Simulator 编译通过，exit 0、TEST BUILD SUCCEEDED，无 warning/error；包含历史快照安全检查与新回归。测试未执行，Simulator 未启动。
- [x] 静态与产物检查：中英各 1198 个有效本地化键、无重复且集合一致；plutil、变更 Markdown 链接、git diff --check 通过。最终 Debug 可执行文件与 debug dylib 无 HealthKit／WeatherKit／Speech 直接链接，也无相关录音／识别 API 未解析符号；处理后的权限文件和隐私清单无停用项。原文件全部保留。
- [x] 网站 production build 通过；输出在 /tmp，未部署。停用的麦克风说明在 Vue 源码中保留为注释，生产文案不再展示。
- [ ] 最后补充历史安全检查后的 Release 测试构建未完成：Familiar arm64 优化编译连续 180 秒无日志进展，按规则 SIGINT 终止，exit 75；根因未确认，不按源码错误或测试通过记录，不重试该检查。较早的普通 Release build 已通过，只覆盖功能注释停用基线，不覆盖随后历史保护修正。
- [ ] 所有者真机：拟提交发布构建在 iPadOS 27.2 与 iPhone 复验新建／键盘／旋转／文字与附件发送／生成停止／回复朗读；确认无麦克风按钮、健康／天气工具和权限入口。
- [ ] 所有者更新 App Store Connect 隐私答案、截图及审核备注；上传高于 3 的可用 build，附真实设备验证证据。网站文案已更新，部署结果以现有 Pages 工作流为准；尚未提交 App Store 审核或发布 App。

本轮目的地：iPhone 18 Pro／iOS 27.0／arm64，1041DD9D-AC70-4DDD-9D34-52514C3E491F；前后均 Shutdown。DerivedData：`/tmp/FamiliarNativeRemovalDerived`。最终 Debug 日志：`/tmp/familiar-native-disabled-final-debug.log`；普通 Release：`/tmp/familiar-native-disabled-release.log`；被停止的 Release 测试构建：`/tmp/familiar-native-disabled-release-validation-final.log`；网站：`/tmp/familiar-native-disabled-website-build.log`。未修改项目签名或 Package.resolved；发布归档签名及真机行为仍待所有者。

旧 TextKit 1 初始化修复保留；本轮没有将旧崩溃日志作为新麦克风崩溃根因。当前仅停用问题功能，不清除用户历史、不修改版本或签名配置。完成后恢复 R4 下一片。

## 前一批次：R4 附件邻接／只读预览／菜单身份

2026-10-22继续19个原编号：BUB-029、TXT-012、MED-001/004/021/022、ACT-001/002/003/004/005/016/017/020、LST-014/015、AIR-003/008/009。先读固定TG80/TG81及TG28/TG38菜单上下文，再改Familiar；保留前轮未提交工作，业务／授权／schema不变。

- [x] 共享附件呈现值：聊天／预览同一图片后文档顺序、稳定ID、2pt间距、邻接和时间归属；预览保留最多三条／正文1200字符的有界快照，不挂载打开／分享／Runtime／WebView。
- [x] 图片：载入／失败／完成共用15/7pt边角，按收／发侧及组内邻接裁切。分立视口使用BubbleNeighbour规则；没有假装完成0pt同容器拼接、媒体尾角或相册拼格。
- [x] 文件与AI：只读预览复用文件气泡／16/13字／真实版本与缺失状态；末尾独立文件块承载唯一终态时间及message.completed，其他工具末尾使用右侧服务时间。块顺序／Run／Undo／准确scope预览保留。
- [x] 菜单：实例与冻结消息／块／原文／动作资格匹配后才复制或执行退场动作；内容变化／解绑取消，旧完成不消费新菜单动作。选区另用代次拒绝旧Task／旧选择动作。
- [x] 新增附件顺序／时间归属、四种上下文变化、解绑重挂载／有效动作单次执行三项回归；只编译未执行。既有UI测试完成标识保留。
- [x] B-R4最终App／单测／UI测试目标具体arm64 build-for-testing通过，exit0、TEST BUILD SUCCEEDED，无warning/error。前序测试桩属性／不可读provider已改为公开协议与实际菜单组装路径；连续菜单回归及scene测试窗口一并编译。
- [ ] 所有者真机：图片／文档／正文组合与无正文唯一时间；只读预览与同会话提交；AI文件末尾／撤销／缺失状态；长按选择／编辑／重试、菜单中切换或退出后的回调；浅深色／大字体。

下一片：单张图片与正文的统一容器、0pt同内容连接和媒体尾角，再推进输入／键盘／阅读联动。纵向多图与公开UIKit菜单／预览／QuickLook、AI收据语义仍保留适配。当前账本累计66项修改／148项既有机制／106项适配，320项真机均未关闭。截图气泡和hwf卡死修正版真机复验独立开放。

## 首轮基线

- [x] D0 文档：现行文档收敛；移除被取代的阶段方案／组件摘录，迁移独有证据和约束。
- [x] D0 账本：320项独立目标，240项聊天页；所有者真机全部独立待验收。
- [x] B1 气泡／主题基础：共享颜色、轮廓／尾角、邻接四角、时间／正文、默认原壁纸资源与公开背景呈现。
- [x] B1 编译：App与两类测试目标通过；未运行测试或启动Simulator。
- [x] B2 源码宽度分支与导航：窄屏减36pt／宽屏85%，17pt会话标题／13pt真实模型副标题。
- [x] B2 交互／全局收尾：本页原生搜索、系统文字行高、原生消息URL、日期／时间比例、媒体尺寸、29pt设置图标与根tint；保留Provider／scope／授权／schema。
- [x] B3 末行双向文字：改用实际末行CoreText bidi run，新增混合语言回归；仅编译。
- [x] 首轮320项静态核对：47项修改、163项现有机制、110项公开API／AI必要适配；目标真机状态全部开放。
- [x] B-FINAL 收尾编译及静态／文档链接检查。
- [x] 输入／阅读、交互／媒体／AI状态、首页／文件／设置、系统偏好首轮源码与当前机制对照。读片段不当全文，代码核对不当真机通过。
- [ ] 按所有者差距反馈重新打开原编号，继续加严必要适配的视觉与交互。
- [ ] 所有者真机视觉与卡死修正版复验。

## 验证证据

| 编号 | 范围 | 证据 | 限制 |
|---|---|---|---|
| B-REVIEW-D | 2026-10-28 当前全部代码，含输入框初始化与天气署名回归 | /tmp/FamiliarReview-debug-build-final.log；exit0，TEST BUILD SUCCEEDED；一项 AppIntents metadata 工具提示 | App／单测／UI 测试仅编译；未启动 Simulator、未执行测试或真机验收 |
| B-REVIEW-R | 2026-10-28 当前全部 App 代码与资源的 Release 配置 | /tmp/FamiliarReview-release-build.log；exit0，BUILD SUCCEEDED；一项 AppIntents metadata 工具提示 | arm64 Simulator Release 编译，不是设备 Archive、实机运行或审核重提 |
| B-R4 | 2026-10-22附件邻接／预览／菜单身份／文件终态 | /tmp/Familiar-Telegram-round4-complete-build.log；exit0，TEST BUILD SUCCEEDED；无warning/error | App／两类测试目标仅编译；新增回归未执行，无设备视觉证据 |
| B-R3 | 2026-10-21气泡错位修复／附件消息 | /tmp/Familiar-Telegram-round3-build.log；exit0，TEST BUILD SUCCEEDED；无warning/error | App／两类测试目标仅编译，无测试执行或设备视觉证据 |
| B-R2 | 2026-10-21正文／状态行／只读预览／WK交接 | /tmp/Familiar-Telegram-round2-final-build.log；exit0，TEST BUILD SUCCEEDED；无warning/error | App／两类测试目标仅编译；回归未执行，无Simulator启动／截图／设备安装 |
| B1 | 2026-10-20气泡／主题基础 | /tmp/Familiar-Telegram-alignment-B1-build.log；exit0，TEST BUILD SUCCEEDED | App／单测／UI测试仅编译；两条AppIntents metadata工具提示，无Swift错误；由B-FINAL统一覆盖后续变更 |
| B-FINAL | 2026-10-21当前全部代码／资源 | /tmp/Familiar-Telegram-alignment-final-build.log；exit0，TEST BUILD SUCCEEDED；无warning/error | App／单测／UI测试目标仅编译；包括末行方向回归，无测试执行、Simulator启动或设备安装 |
| 前序基线 | 2026-10-19 Telegram P0–P5与U6 | /tmp/Familiar-Telegram-motion-final-build.log；指定arm64 build-for-testing成功 | 不替代本轮；无新设备安装、测试执行或性能采样 |

审核修复目的地：iPhone18 Pro／iOS27.0／arm64，1041DD9D-AC70-4DDD-9D34-52514C3E491F，前后均Shutdown。DerivedData为/tmp/FamiliarReviewDerived，复用本机已有SourcePackages与锁定Package.resolved；未改依赖、签名配置或存储。中英各1217键且集合相同、无重复；plutil、变更Markdown本地链接及git diff --check通过。

R4及此前目的地相同，使用/tmp/FamiliarU0Derived；其构建证据属于各自基线，不替代本次审核修复。

## 静态检查与明确适配

48份项目Markdown本地链接零断链（排除node_modules等第三方文档）；中英各1215资源键，无重复且集合相同；plutil、renderer.js语法、git diff --check通过。320个目标编号唯一，240项聊天页，所有者真机320项仍待验收。

默认图案为固定源码原tgv的1440×2960透明PNG，保留来源／hash／上游GPL-2.0-or-later及本项目GPL-3.0声明。明确适配包括静态MeshGradient、系统原生搜索（精确54pt自定义吸附未移植）、UIKit图库／QuickLook及AI工具／审批／Provider设置；不声称完全复制Telegram实现框架或共享动画相位。

代理首轮实现与编译收口；未代为提交／推送。后续按同一编号处理真机差距，不新建重复总计划。

## 阻塞与责任

hwf看门狗和交互返回CPU问题仍待修正版设备复验；详见[调查](docs/research/2026-10-19-hwf-hang-investigation.md)。不以编译、旧版本trace或未捕获样本宣布修复。复现时优先处理。

真实Provider、SQL／内存、系统权限和最终视觉由[统一验收](docs/11-verification-and-release-checklist.md)分别记录。S1缺失真实20查询和所有旧待验收项不自动结清。

## 工作规则

每批约10–20项，先读源码和调用上下文再修改。保持单Agent、scope、文件版本、授权和Run顺序；不改变schema／重置策略。几何／动画不触发DB读取或广泛持久化。

具体arm64 build-for-testing只编译App／测试，不启动Simulator／执行测试／截图。三分钟无进度停止本次拥有进程。保留无关改动，不新建分支，不代为提交、推送、部署或发布。

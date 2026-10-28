# Familiar 当前实施账本

目标：Telegram iOS视觉与交互的AI问答App。固定上游f1dd7a2；在main分批推进。设计只在[UI规范](docs/03-ui-ux-design.md)，逐项目标和状态只在[320项账本](docs/telegram-ios-ui-checklist.md)，源码阅读只在[登记](docs/research/telegram-ios-source-map.md)。

## 当前批次：App Review 1.0 (2) 修复

- [x] 三份崩溃日志匹配发布 dSYM，应用帧定位到输入框布局；初始化与寄存器证据见 [调查](logs/2026-10-28-review-composer-crash.md)。根因判断与真机复验分开。
- [x] 输入框及消息正文显式创建 TextKit 1 并调用子类指定初始化器；统一布局文本快照、有效选区检查与重入保护。
- [x] 天气成功工具结果驱动固定  Weather／法律链接，覆盖回复、结果和完整记录；实时／历史共用投影，不依赖模型引用，不改 schema。
- [x] 保留 HealthKit／WeatherKit，健康权限页增加使用步骤；[审核回复与真机录屏清单](website/APP-STORE-CONNECT.md)已补齐。
- [x] 新增初始化／生产挂载输入／天气工具契约／持久化重读四项单测及纸笔按钮与键盘导航 UI 回归。
- [x] 指定 arm64 Simulator 的 Debug build-for-testing：App／单测／UI 测试目标编译通过；新增用例未执行。
- [x] 同一具体 arm64 destination 的 Release build：exit0，BUILD SUCCEEDED；仅编译，不能替代设备复验。
- [ ] 所有者真机：iPadOS 27.2 发布构建的新建／键盘／返回／旋转，iPhone 回归，HealthKit 权限与真实结果，WeatherKit 署名与链接及录屏。
- [ ] 所有者上传新 build、附真实录屏、更新 Review Notes 并回复审核。未自动提交 App Store 审核或发布 App。

本轮所有者另行授权将已有未提交改动与审核修复一并提交、推送 main；此授权不包含 App Store 重提审核。

审核修复完成后恢复下面 R4 的下一片；历史 UI／设备验收状态不自动关闭。

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

# Telegram iOS UI 对齐账本

参照提交 **f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838**。共 **320项**，其中前8组 **240项聊天页目标（75%）**。每一行也是所有者真机检查项，按编号回报设备、系统、步骤、截图和结论。

## 使用规则

- `待研究`：已定位相关源码登记，但本轮尚未完成该目标的分支、调用上下文与Familiar差距核对；不构成实现承诺已完成。
- `已修改`：当前对齐路线已有对应代码变更；`代码已对齐`：完成静态核对后保留已有实现；`保留适配`：明确存在AI或公开API差异，需写明原因。
- 编译列记录本轮构建编号，不能由同一次App构建推断每项目标的行为或视觉通过。真机由所有者填写，初始全部待验收。
- TG编号的固定完整路径、已读范围与研究深度见[源码登记](research/telegram-ios-source-map.md)。继承研究与本轮核对分别记录。
- AI专属功能参照消息状态／菜单／输入／Sheet的呈现规则，保留原Runtime和授权契约；不声称Telegram存在相同业务。
- 每批约10–20项；当前切片和构建证据见[PLAN](../PLAN.md)，唯一设计见[UI规范](03-ui-ux-design.md)。

## 核对边界

2026-10-20至21首轮已逐项检查当前对应实现，保留现有功能，发现的聊天主题／气泡／宽度／标题／搜索／末行方向等差距在本轮修正。`代码已对齐`仅代表该行的静态机制；`保留适配`明确保留Familiar或系统公开组件的差异。它们均不代表像素对比、真实手势、辅助功能、性能或测试执行通过。所有者发现差距后按同一编号重新打开，不增加重复任务。

明确适配包括：静态系统MeshGradient（不移植Telegram共享渐变动画相位）、系统原生搜索（不复制54pt自定义吸附）、UIKit图像图库与QuickLook、会话级未读而非社交消息计数、AI工具／来源／审批／草稿润色。未增加Telegram账户、媒体服务或第三方UI框架。

## R4 附件邻接／只读预览／菜单身份

2026-10-22继续19个原编号。聊天与预览共用附件排序、邻接及时间归属；预览沿用文件气泡但不挂载打开／分享操作。媒体按收／发侧读取15/7pt边角，分立图片／正文仍属于BubbleNeighbour适配，0pt同容器拼接、媒体尾角及相册拼格待后续。回复末尾若为真实文件回执，时间进入文件气泡并保留完成标识；其他工具末尾采用右侧服务时间。菜单延后动作核对消息／块／原文／资格和菜单实例，选区另核对选择代次；旧视图／旧菜单回调不得操作新内容。新增附件归属和两项菜单生命周期回归，只编译未执行；B-R4 App及单测／UI测试目标编译通过，无warning/error，真机全部开放。

## 分组索引

| 编号范围 | 分组 | 数量 |
|---|---|---|
| NAV-001–030 | 聊天容器与导航 | 30 |
| BUB-001–030 | 消息气泡与主题 | 30 |
| TXT-001–030 | 消息正文与状态排版 | 30 |
| INP-001–030 | 输入器与键盘 | 30 |
| SCR-001–030 | 滚动、历史与已读 | 30 |
| ACT-001–030 | 消息菜单、选区与查找 | 30 |
| MED-001–030 | 聊天附件、图库与发送 | 30 |
| AIR-001–030 | AI回复、工具与审批 | 30 |
| LST-001–020 | 聊天首页、分类与搜索 | 20 |
| FIL-001–020 | 文件与项目 | 20 |
| SET-001–020 | 设置与AI润色 | 20 |
| SYS-001–020 | 全局系统偏好与资源 | 20 |

## NAV · 聊天容器与导航

源码定位：TG01/TG04/TG18；本地主要实现：`FamiliarChatView / FamiliarAppShell`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| NAV-001 | 详情进入时隐藏Tab栏 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-002 | 完成返回时恢复原Tab | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-003 | 交互返回取消后仍留在原会话 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-004 | 会话标题单行居中 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 17pt会话标题／13pt真实模型，原生导航承载 | 已修改 | B-FINAL（仅编译） | 待验收 |
| NAV-005 | 长标题截断不挤压返回按钮 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 17pt会话标题／13pt真实模型，原生导航承载 | 已修改 | B-FINAL（仅编译） | 待验收 |
| NAV-006 | 标题下显示真实当前模型 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 17pt会话标题／13pt真实模型，原生导航承载 | 已修改 | B-FINAL（仅编译） | 待验收 |
| NAV-007 | 返回按钮采用原生导航行为 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-008 | 省略号使用单层系统玻璃 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-009 | 导航控件与正文安全区分离 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-010 | 顶部内容可延伸到导航材质后方 | TG01/TG04/TG18 | `FamiliarChatView / FamiliarRootView / AppShell` | 保留原生导航与稳定Sheet身份；不新增路由或数据对象 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-011 | 空白新对话不产生虚构历史 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-012 | 新对话菜单保留首项入口 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-013 | 新对话取消不提交空Conversation | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-014 | 模型菜单禁用运行中切换 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-015 | 模型菜单标记真实已选模型 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-016 | Project详情入口只在项目会话出现 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-017 | 普通聊天菜单不出现项目专属操作 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-018 | 菜单关闭后再执行导航 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-019 | 搜索入口使用当前会话身份 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-020 | 导出操作不改变阅读位置 | TG01/TG04/TG18 | `FamiliarChatView / FamiliarRootView / AppShell` | 保留原生导航与稳定Sheet身份；不新增路由或数据对象 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-021 | 文件详情从稳定页面导航 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-022 | 分享Sheet覆盖时暂停已读 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | Familiar本机锁定／系统入口约束，保留窗口覆盖与延后路由，不引入Telegram账户 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| NAV-023 | 锁定界面覆盖已呈现Sheet | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | Familiar本机锁定／系统入口约束，保留窗口覆盖与延后路由，不引入Telegram账户 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| NAV-024 | 系统入口先解锁再打开会话 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | Familiar本机锁定／系统入口约束，保留窗口覆盖与延后路由，不引入Telegram账户 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| NAV-025 | 目标已删除时不重建会话 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-026 | 导航恢复不重播历史入场 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-027 | 新会话不复用上个会话标题 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-028 | 导航期间不聚焦旧输入框 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-029 | 顶部菜单支持VoiceOver标签 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| NAV-030 | 导航外观切换保留当前路由 | TG01/TG04/TG18 | `FamiliarChatView / AppShell / ChatReadingLifecycle` | 原生导航／菜单与呈现身份；静态核对，手势待设备 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |

## BUB · 消息气泡与主题

源码定位：TG69/TG70/TG72/TG73/TG74；本地主要实现：`FamiliarChatAppearance / FamiliarChatTimeline / FamiliarChatRow / FamiliarChatTurn`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| BUB-001 | 浅色用户气泡使用Classic绿色 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-002 | 浅色AI气泡使用白色 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-003 | 深色用户气泡使用Night蓝色渐变 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-004 | 深色AI气泡使用Night半透明深灰 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-005 | 用户正文读取发出消息文字色 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-006 | AI正文读取接收消息文字色 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-007 | 用户时间读取发出消息状态色 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-008 | AI时间读取接收消息状态色 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-009 | 消息链接读取对应主题链接色 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-010 | 默认完整气泡圆角16pt | TG73/TG74 | `FamiliarMessageBubbleBackground / FamiliarMessageBubble` | R3固定33pt母版的边角与尾角，只拉伸1pt中心；回归覆盖双侧、四种邻接、长宽气泡，截图差距待真机复验 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-011 | 连续侧合并圆角8pt | TG73/TG74 | `FamiliarMessageBubbleBackground / FamiliarMessageBubble` | R3固定33pt母版的边角与尾角，只拉伸1pt中心；回归覆盖双侧、四种邻接、长宽气泡，截图差距待真机复验 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-012 | 用户末条气泡显示右尾角 | TG73/TG74 | `FamiliarMessageBubbleBackground / FamiliarMessageBubble` | R3固定33pt母版的边角与尾角，只拉伸1pt中心；回归覆盖双侧、四种邻接、长宽气泡，截图差距待真机复验 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-013 | AI文本气泡显示左尾角 | TG73/TG74 | `FamiliarMessageBubbleBackground / FamiliarMessageBubble` | R3固定33pt母版的边角与尾角，只拉伸1pt中心；回归覆盖双侧、四种邻接、长宽气泡，截图差距待真机复验 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-014 | 连续用户上条隐藏尾角 | TG73/TG74 | `FamiliarMessageBubbleBackground / FamiliarMessageBubble` | R3固定33pt母版的边角与尾角，只拉伸1pt中心；回归覆盖双侧、四种邻接、长宽气泡，截图差距待真机复验 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-015 | 连续用户中间条连接上下边角 | TG73/TG74 | `FamiliarMessageBubbleBackground / FamiliarMessageBubble` | R3固定33pt母版的边角与尾角，只拉伸1pt中心；回归覆盖双侧、四种邻接、长宽气泡，截图差距待真机复验 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-016 | 连续用户末条恢复下方圆角 | TG73/TG74 | `FamiliarMessageBubbleBackground / FamiliarMessageBubble` | R3固定33pt母版的边角与尾角，只拉伸1pt中心；回归覆盖双侧、四种邻接、长宽气泡，截图差距待真机复验 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-017 | 跨日期不合并用户气泡 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-018 | 跨作者不合并气泡 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-019 | 跨Run不合并AI消息身份 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | Run保留独立身份，邻接只作用于用户消息 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| BUB-020 | 两侧窄屏减36pt／超过500pt取85%宽度 | TG69/TG70/TG72/TG73/TG74 | `FamiliarReadOnlyMessage / FamiliarMessageGroupLayout / TextAndTimeLayout` | R2只读预览复用生产GroupLayout和满宽对齐容器，移除30/12pt估计Spacer | 已修改 | B-R2（仅编译） | 待验收 |
| BUB-021 | 大辅助字号放宽消息可用宽度 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 保留现有辅助字号0.98宽度适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| BUB-022 | 气泡正文水平内边距11pt | TG72/TG73 | `FamiliarMessageBubble / FamiliarMessageBubbleBackground` | R3保留11pt正文、6pt与像素上下边距、6pt尾侧；背景显式capInsets后与内容边界一致 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-023 | 气泡正文垂直内边距计入屏幕像素 | TG72/TG73 | `FamiliarMessageBubble / FamiliarMessageBubbleBackground` | R3保留11pt正文、6pt与像素上下边距、6pt尾侧；背景显式capInsets后与内容边界一致 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-024 | 气泡尾侧预留6pt空间 | TG72/TG73 | `FamiliarMessageBubble / FamiliarMessageBubbleBackground` | R3保留11pt正文、6pt与像素上下边距、6pt尾侧；背景显式capInsets后与内容边界一致 | 已修改 | B-R3（仅编译） | 待复验 |
| BUB-025 | 气泡最小尺寸40×35pt | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| BUB-026 | 时间线边缘3pt | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 保留当前时间线布局，不把几何变化写入数据库 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| BUB-027 | 普通消息间距含像素修正 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 保留当前时间线布局，不把几何变化写入数据库 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| BUB-028 | 连续消息采用紧凑间距 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 保留当前时间线布局，不把几何变化写入数据库 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| BUB-029 | 列表预览复用生产气泡背景 | TG73/TG80/TG81 | `FamiliarReadOnlyMessage / FamiliarMessageAttachmentPresentation / FamiliarFileTile` | R4预览共用生产附件顺序、邻接、文件背景和单一时间；无打开／分享／Runtime／WebView，保留正文1200字与最多三条消息限制 | 已修改 | B-R4（仅编译） | 待复验 |
| BUB-030 | 默认壁纸使用固定源码原图案 | TG69/TG70/TG72/TG73/TG74 | `FamiliarChatAppearance` | 固定原tgv图案；静态公开MeshGradient代替Telegram节点渐变动画 | 已修改 | B-FINAL（仅编译） | 待验收 |

## TXT · 消息正文与状态排版

源码定位：TG16/TG17/TG19/TG20；本地主要实现：`FamiliarChatTurn / FamiliarMessageReadingStyle / FamiliarMarkdownStyle / renderer.css`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| TXT-001 | 普通正文跟随系统body字号 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2直接传实际字号测量；不再由lineHeight反推字号，文本／字号／宽度／时间尺寸参与缓存失效 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-002 | 原生短文与Markdown共用文字主题 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2普通多行／长AI文本走原生；Markdown、链接及带来源块仍走富文本，配色契约保留 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-003 | 中英文混排不裁切字形 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2保留原生正文且测量／放置同宽度、无指定高度，避免二次压缩字形 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-004 | Emoji与组合字符保持完整 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2扩展Emoji／组合字符与多语言段落分类回归，保留整段UTF16原文 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-005 | 正文保留连续空行 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2普通正文原样保留连续空行／CRLF；Markdown继续按段落语义渲染 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-006 | 短文本气泡按实际宽度收紧 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2缓存实际正文尺寸与末行宽度，紧凑气泡仍按真实内容／时间确定宽度 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-007 | 原生文本末行容纳时间 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2按同一测量结果放置正文和时间；内联状态不额外占整行 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-008 | 末行不够宽时换独立时间行 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2末行不足时预留独立状态行；宽时间可扩展安全内容宽度，新增几何回归 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-009 | RTL正文使用独立状态区域 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2继续按实际末行CoreText方向独立状态行，并纳入布局几何回归 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-010 | 尾随换行不让时间覆盖空行 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2末尾Unicode换行均走独立状态行，包含LF／CRLF；不覆盖最后空白段落 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-011 | 复杂Markdown的时间位于正文之后 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-012 | 终态时间只出现一次 | TG16/TG56 | `FamiliarAssistantTurn / FamiliarTurnSurface / FamiliarWriteReceipt` | R4末尾真实文件回执承载唯一终态时间，保留message.completed；其他工具末尾服务时间右对齐，文字末尾不变 | 已修改 | B-R4（仅编译） | 待验收 |
| TXT-013 | 运行未结束不伪造终态时间 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-014 | 日期分隔使用服务消息样式 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 主题／末行双向文字／日期／原生链接按源码修正 | 已修改 | B-FINAL（仅编译） | 待验收 |
| TXT-015 | 跨天分隔不计入业务消息 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-016 | 模型切换标记使用真实模型名 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 主题／末行双向文字／日期／原生链接按源码修正 | 已修改 | B-FINAL（仅编译） | 待验收 |
| TXT-017 | 超长URL在气泡内可换行 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-018 | 链接命中不被消息菜单覆盖 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / FamiliarTextAndTimeLayout / FamiliarMarkdownBlock` | R2链接继续留富文本路径；原生动作完整传递，不改变链接命中排除 | 已修改 | B-R2（仅编译） | 待验收 |
| TXT-019 | 标题有正确语义层级 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-020 | 列表缩进不超出消息内容区 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-021 | 引用块保持引用边线与内容层级 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-022 | 行内代码保留等宽字体 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-023 | 代码块横向滚动 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-024 | 代码复制只复制对应块 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-025 | 长表格独立横向滚动 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-026 | 公式超宽时独立横向滚动 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-027 | Mermaid图示支持原预览入口 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-028 | 流式补全不替换已有链接身份 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 主题／末行双向文字／日期／原生链接按源码修正 | 已修改 | B-FINAL（仅编译） | 待验收 |
| TXT-029 | 网页远程图片呈现为主动打开链接 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| TXT-030 | 原生文本选择不丢失字体与搜索高亮 | TG16/TG17/TG19/TG20 | `FamiliarMessageReadingStyle / MessageInteraction / MarkdownStyle / renderer.css` | 原生TextKit／本地WebKit；Markdown结构为AI必要适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |

## INP · 输入器与键盘

源码定位：TG24/TG25/TG26/TG27/TG45/TG46；本地主要实现：`FamiliarComposerView / FamiliarComposerTextView / FamiliarChatInputDock`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| INP-001 | 单行正文与占位共享字体 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-002 | 单行正文与占位共享inset | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-003 | 单行文字在输入背景内垂直居中 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-004 | 多行输入顶部基线稳定 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-005 | 输入最大六行后内部滚动 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-006 | 末尾空白行计入输入高度 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-007 | 光标跟随输入区内部滚动 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-008 | 中文组合输入期间不重写正文 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-009 | 中文组合输入提交后再采集发送内容 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-010 | UTF16选区正确处理Emoji | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-011 | 外部追加草稿后光标位于目标位置 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-012 | 空输入显示语音动作 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-013 | 有内容时显示发送动作 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-014 | 生成中显示停止动作 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-015 | 语音转写期间保留停止语音动作 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-016 | 发送语音停止共用稳定Button身份 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-017 | 发送动作命中范围至少44pt | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-018 | 纯附件草稿允许发送 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-019 | 附件准备期间阻止提交 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-020 | 附件失败保留重试入口 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-021 | 技能选择不删除已有正文 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| INP-022 | 技能选择不删除已有附件 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| INP-023 | 技能菜单结束后恢复输入焦点 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| INP-024 | 回形针入口保留系统附件动作 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-025 | 润色入口不挤压正文测量宽度 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| INP-026 | 长输入支持展开和收起 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-027 | 键盘交互下拉不抢旧消息位置 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-028 | 退出详情清理输入焦点 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-029 | 切会话不接收旧转写回调 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| INP-030 | 键盘显示变化不重复播放发送转场 | TG24/TG25/TG26/TG27/TG45/TG46 | `FamiliarComposerTextView / ComposerView / ChatInputDock` | 公开UITextView与现有焦点／草稿身份保护；Skill和润色为AI入口 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |

## SCR · 滚动、历史与已读

源码定位：TG13/TG14/TG23/TG39/TG47/TG58；本地主要实现：`FamiliarChatTimeline / FamiliarChatScrollState / FamiliarHistoryWindow / FamiliarChatHistoryStore`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| SCR-001 | 首次打开显示正确历史窗口 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatTimeline.pageHistory / ChatController.applyHistory / ChatHistoryStore` | 已核对分页旧边缘定位、原子发布、完整业务读与UI窗口分离；未作性能结论 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-002 | 回到会话恢复阅读书签 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatTimeline.pageHistory / ChatController.applyHistory / ChatHistoryStore` | 已核对分页旧边缘定位、原子发布、完整业务读与UI窗口分离；未作性能结论 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-003 | 阅读书签使用稳定消息身份 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-004 | 未读回复末尾可见才清自动未读 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-005 | 只读预览不清未读 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-006 | 搜索期间不清未读 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-007 | 后台期间不清未读 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-008 | 锁定期间不清未读 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-009 | 流式位于底部时跟随新增内容 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-010 | 用户上滑后暂停自动追随 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-011 | 返回最新按钮在离底部时出现 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-012 | 返回最新按钮定位全局最新窗口 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-013 | 已在底部时不重复滚动 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-014 | 键盘弹起保留当前阅读意图 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-015 | 正文上方补高只补偿实际位移 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-016 | 合并同一轮行几何变化 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-017 | 滚动视口移动不误判内容增长 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-018 | 过期几何不改变当前阅读锚点 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-019 | 退场立即暂停几何补偿 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarMarkdownWebCoordinator.dismantle / userContentController / renderIfReady` | R2WebView退场停加载／解绑delegate，延迟脚本／渲染结果不得再发布高度或失败 | 已修改 | B-R2（仅编译） | 待验收 |
| SCR-020 | 取消返回恢复当前呈现实例 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-021 | 旧呈现实例不能停止新呈现 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarMarkdownWebCoordinator.dismantle / userContentController / renderIfReady` | R2脚本消息与嵌套阅读补偿均核对原WebView身份，旧实例不移动新呈现 | 已修改 | B-R2（仅编译） | 待验收 |
| SCR-022 | 历史分页不丢失定位消息 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-023 | 向前加载保留当前可见内容 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-024 | 向后加载不重播已见消息 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatTimeline.pageHistory / ChatController.applyHistory / ChatHistoryStore` | 已核对分页旧边缘定位、原子发布、完整业务读与UI窗口分离；未作性能结论 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-025 | 窗口读取失败不发布半页 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatTimeline.pageHistory / ChatController.applyHistory / ChatHistoryStore` | 已核对分页旧边缘定位、原子发布、完整业务读与UI窗口分离；未作性能结论 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-026 | 切会话失败不展示旧会话正文 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatTimeline.pageHistory / ChatController.applyHistory / ChatHistoryStore` | 已核对分页旧边缘定位、原子发布、完整业务读与UI窗口分离；未作性能结论 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-027 | 完整导出不受UI窗口限制 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatTimeline.pageHistory / ChatController.applyHistory / ChatHistoryStore` | 已核对分页旧边缘定位、原子发布、完整业务读与UI窗口分离；未作性能结论 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-028 | 完整发送上下文不受UI窗口限制 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatTimeline.pageHistory / ChatController.applyHistory / ChatHistoryStore` | 已核对分页旧边缘定位、原子发布、完整业务读与UI窗口分离；未作性能结论 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-029 | VoiceOver开启时暂停自动追随 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SCR-030 | 已读可见性不触发整条时间线重算 | TG13/TG14/TG23/TG39/TG47/TG58 | `FamiliarChatScrollState / ChatTimeline / ChatReadingLifecycle` | 保留会话阅读状态与异步补偿；SQL／资源和卡死复验独立 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |

## ACT · 消息菜单、选区与查找

源码定位：TG18/TG28/TG38/TG39/TG40；本地主要实现：`FamiliarMessageInteraction / FamiliarSelectedTextAction / FamiliarConversationFind / FamiliarMessageEditing`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| ACT-001 | 用户消息长按可复制 | TG28/TG38 | `FamiliarMessageInteraction / FamiliarMessageActions.Context` | R4复制保留冻结整条正文，触发前核对菜单实例、消息／块／原文／资格及已挂载视图；旧菜单不能复制新消息 | 已修改 | B-R4（仅编译） | 待验收 |
| ACT-002 | 用户消息长按可进入原位选择 | TG28/TG38 | `FamiliarMessageInteraction` | R4菜单选择在退场后执行，核对冻结上下文；延迟选区启动另核对选择代次，旧Task不能选择新内容 | 已修改 | B-R4（仅编译） | 待验收 |
| ACT-003 | 用户消息编辑使用现有安全入口 | TG38 | `FamiliarMessageInteraction` | R4编辑沿用安全入口，资格变化／消息切换／解绑立即使排队动作失效；同一有效菜单退场只执行一次 | 已修改 | B-R4（仅编译） | 待验收 |
| ACT-004 | AI完成消息提供复制 | TG28/TG38 | `FamiliarMessageInteraction / FamiliarMessageActions` | R4AI复制仍为完整回复，菜单实例和消息／块／原文匹配后才执行；不降为当前片段复制 | 已修改 | B-R4（仅编译） | 待验收 |
| ACT-005 | AI完成消息提供原位选择 | TG28/TG38 | `FamiliarMessageInteraction` | R4AI原位选择沿用原生／WK入口，菜单与选择代次隔离迟到动作；不新增透明手势层 | 已修改 | B-R4（仅编译） | 待验收 |
| ACT-006 | 存在外部影响时不提供不安全重试 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-007 | 消息菜单附在实际文本视图 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-008 | 选区激活时暂停消息菜单 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-009 | 开始新消息选区时结束旧选区 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-010 | Done结束当前选择 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-011 | VoiceOver两指擦除可退出选择 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-012 | Native选区菜单提供解释动作 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| ACT-013 | Native选区菜单提供改写动作 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| ACT-014 | Native选区菜单提供精简动作 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| ACT-015 | WebKit选区动作使用真实DOM文本 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| ACT-016 | 选区动作冻结消息和正文块身份 | TG28/TG38 | `FamiliarMessageActions.Context / FamiliarMessageInteraction` | R4上下文含messageID／blockID／原文／动作资格；菜单实例及选择代次独立，旧选区动作不可借新一次选择执行 | 已修改 | B-R4（仅编译） | 待验收 |
| ACT-017 | 菜单退场后才回填草稿 | TG28/TG38 | `FamiliarMessageInteraction / SelectedTextSink` | R4编辑／重试／选择仍等菜单退场；旧退场完成回调不能消费新菜单动作，选区回填保留冻结Sink及草稿约束 | 已修改 | B-R4（仅编译） | 待验收 |
| ACT-018 | 已有草稿与追加内容隔两个换行 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| ACT-019 | 选区追加保留附件和Skill | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| ACT-020 | 切会话后拒绝旧选区回填 | TG28/TG38 | `FamiliarMessageInteraction / FamiliarSelectedTextSink` | R4切消息／块／正文／资格取消待执行动作，解绑清除菜单代次；保留Sink会话身份校验，不覆盖别的草稿 | 已修改 | B-R4（仅编译） | 待验收 |
| ACT-021 | 审批占用输入区时拒绝回填 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| ACT-022 | 澄清占用输入区时拒绝回填 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| ACT-023 | 查找支持上一个匹配消息 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-024 | 查找支持下一个匹配消息 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-025 | 查找统计按匹配消息计数 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-026 | 原生查找高亮不改变原文 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-027 | Web查找高亮层不拦截触摸 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-028 | 退出查找恢复阅读状态 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-029 | 取消编辑不删除原历史 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| ACT-030 | 编辑失败保留原历史和编辑草稿 | TG18/TG28/TG38/TG39/TG40 | `FamiliarMessageInteraction / SelectedTextAction / ConversationFind / MessageEditing` | 保留真实动作资格与冻结身份；原生／WK菜单为公开API适配 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |

## MED · 聊天附件、图库与发送

源码定位：TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65；本地主要实现：`FamiliarChatRow / FamiliarAttachmentImport / FamiliarSendPresentation / FamiliarImageGallery`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| MED-001 | 图片消息采用Telegram媒体圆角 | TG72/TG80/TG81 | `FamiliarChatAppearance.mediaShape / FamiliarImageAttachmentView` | R4图片15/7pt收发邻接边角，载入／失败／完成共用裁切；分立视口使用BubbleNeighbour适配，0pt同容器拼接及媒体尾角未实现 | 已修改 | B-R4（仅编译） | 待验收 |
| MED-002 | 图片缩略图按比例显示 | TG72/TG79 | `FamiliarChatImageLayout / FamiliarImageAttachmentView` | R3实际视口300×380上限／170×74最小尺寸并受父宽约束；常规图保比例，极端比例居中裁切，原图仍由图库查看 | 已修改 | B-R3（仅编译） | 待验收 |
| MED-003 | 图片不使用完整原图恢复草稿 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-004 | 多张图片按稳定附件顺序展示 | TG80/TG81 | `FamiliarMessageAttachmentPresentation / FamiliarMessageRow / FamiliarReadOnlyMessage` | R4共享图片后文档的既有顺序与稳定ID，2pt间距，正文或最后附件拥有时间；多图仍纵向，不实现相册拼格 | 保留适配 | B-R4（仅编译） | 待验收 |
| MED-005 | 缺失原图呈现可理解状态 | TG79 | `FamiliarImageAttachmentView` | R3补图片载入／不可用的辅助功能状态，保留失败占位与打开失败提示；不恢复原图到草稿 | 已修改 | B-R3（仅编译） | 待验收 |
| MED-006 | 图片预览打开当前点击图片 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-007 | 图库左右翻页保持当前图片ID | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-008 | 图库双击按点击位置缩放 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-009 | 图库捏合缩放保持内容边界 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-010 | 放大图片移动优先于退出手势 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-011 | 图库拖拽时控件按源码距离淡出 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-012 | 图库拖拽时背景按源码距离淡出 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-013 | 图库距离达阈值可完成退出 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-014 | 图库速度达阈值可完成退出 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-015 | 图库取消拖拽恢复原位置 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-016 | 退出时寻找当前图片缩略图 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-017 | 缩略图离屏时退出淡出 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-018 | 草稿图库允许移除当前图 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 公开UIScrollView/QuickLook/Share适配，保留附件ID、取消与当前退出源 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| MED-019 | 已发送图片图库不提供删除草稿动作 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 保留有序附件／当前邻页／文档QuickLook及草稿身份；不引入Telegram媒体服务 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| MED-020 | 图库只准备当前及邻页图片 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 保留有序附件／当前邻页／文档QuickLook及草稿身份；不引入Telegram媒体服务 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| MED-021 | 文件消息显示真实文件名与类型 | TG56/TG65 | `FamiliarFileTile / FamiliarReadOnlyMessage` | R4预览复用真实文件名／类型／版本、16/13字体与缺失／撤销状态，省略交互按钮；生产准确打开／分享不变 | 已修改 | B-R4（仅编译） | 待验收 |
| MED-022 | 文件消息显示可用字节信息 | TG65/TG72 | `FamiliarFileTile / FamiliarFilePresentation` | R4生产与预览同读真实字节、类型／版本和13pt等宽数字；只读预览不生成空操作入口 | 已修改 | B-R4（仅编译） | 待验收 |
| MED-023 | 文件消息打开准确附件URL | TG56/TG65 | `FamiliarFilePresentation / FamiliarMessageFileNavigation` | R3沿用原准确附件URL与canonical版本／scope校验，视觉修改不触发DB读取；AI收据仍保留验证／Undo | 代码已对齐 | B-R3（仅编译） | 待验收 |
| MED-024 | 文档继续使用QuickLook | TG56/TG65 | `FamiliarMessageFileNavigation / FamiliarFileTile` | R3保留公开QuickLook和精确URL／版本打开，44pt分享保留在气泡中；不移植Telegram媒体服务 | 保留适配 | B-R3（仅编译） | 待验收 |
| MED-025 | 附件导入逐项显示准备和失败 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 保留有序附件／当前邻页／文档QuickLook及草稿身份；不引入Telegram媒体服务 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| MED-026 | 同一草稿导入串行准备大资产 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 保留有序附件／当前邻页／文档QuickLook及草稿身份；不引入Telegram媒体服务 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| MED-027 | 旧导入回调不能附到编辑草稿 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 保留有序附件／当前邻页／文档QuickLook及草稿身份；不引入Telegram媒体服务 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| MED-028 | 发送保存成功后才关联消息ID | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 保留有序附件／当前邻页／文档QuickLook及草稿身份；不引入Telegram媒体服务 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| MED-029 | 发送横纵坐标曲线分开 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarChatRow / ImageGallery / SendPresentation` | 15pt媒体圆角、300×380上限并适应父宽；发送保留原曲线 | 已修改 | B-FINAL（仅编译） | 待验收 |
| MED-030 | 失败过期或离场释放发送快照 | TG29/TG30/TG31/TG32/TG33/TG34/TG35/TG36/TG56/TG57/TG65 | `FamiliarImageGallery / FamiliarComposerView / FamiliarChatRow / FamiliarSendPresentation` | 保留有序附件／当前邻页／文档QuickLook及草稿身份；不引入Telegram媒体服务 | 保留适配 | B-FINAL（仅编译） | 待验收 |

## AIR · AI回复、工具与审批

源码定位：TG16/TG18/TG19/TG24/TG37；本地主要实现：`FamiliarChatTurn / FamiliarRuntimeActivityProjection / FamiliarChatInputDock / FamiliarApprovalCard`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| AIR-001 | 流式回复沿用同一消息组身份 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-002 | 流式转历史不重新播放入场 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-003 | 工具与文本按实际序列穿插 | TG16/TG56 | `FamiliarAssistantTurn / FamiliarAssistantResponseProjection` | R4只给最后独立文件块传递终态时间，不排序／删除任何内容块，Runtime活动、文本与文件仍保留sequence和Run身份 | 保留适配 | B-R4（仅编译） | 待验收 |
| AIR-004 | 工具摘要只由现有投影生成 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-005 | 工具等待不伪造完成结果 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-006 | 失败工具显示真实失败摘要 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-007 | 工具详情按需展开原回执 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-008 | 只有存在真实撤销资格才显示Undo | TG56/TG65 | `FamiliarWriteReceipt / FamiliarAssistantTurn` | R4文件时间仍沿用准确版本／scope校验与availableUndoKeys真实资格；AI授权摘要／Undo保留，不借外观授予权限 | 保留适配 | B-R4（仅编译） | 待验收 |
| AIR-009 | 撤销完成更新原活动状态 | TG56/TG65 | `FamiliarAssistantTurn.adjustedUndoPhase / FamiliarWriteReceipt` | R4撤销仍以runID+toolCallID更新原回执，撤销／缺失文件保持原状态和预览限制；终态时间不产生新回执 | 保留适配 | B-R4（仅编译） | 待验收 |
| AIR-010 | 来源页只显示实际引用来源 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-011 | 行内引用编号与来源页一致 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-012 | 重定向别名共享实际来源编号 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-013 | 后续问题只回填输入区 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-014 | 后续问题不自动发起请求 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-015 | 运行中返回首页不取消当前任务 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-016 | 浏览其他会话不创建第二个Runtime | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-017 | 全局执行占用阻止重复运行 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-018 | 审批只针对当前等待请求 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-019 | 审批显示真实操作字段 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-020 | 外部创建默认始终允许此类 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-021 | 删除审批只提供本次选择 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-022 | 取消审批不执行外部写入 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-023 | 审批选择作用域不自动提交 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-024 | 澄清卡只对应当前等待问题 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-025 | 澄清自定义答案保留输入限制 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-026 | 停止生成保留已收到的正文 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-027 | 未完整回复呈现不完整状态 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-028 | 恢复入口不自动重放不确定写入 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-029 | 运行记录定位原回复身份 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| AIR-030 | AI活动动效遵守降低动效设置 | TG16/TG18/TG19/TG24/TG37 | `FamiliarChatTurn / ChatInputDock / ApprovalCard / ChatSessionCoordinator` | AI必要适配：保留领域状态／真实回执与授权，采用消息／菜单／输入区呈现规则 | 保留适配 | B-FINAL（仅编译） | 待验收 |

## LST · 聊天首页、分类与搜索

源码定位：TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12；本地主要实现：`FamiliarChatsHome / FamiliarConversationList / FamiliarChatProjectPager / FamiliarLocalSearchResults`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| LST-001 | 首页保持文件聊天设置三Tab导航 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 保留轻量快照、diffable与稳定ID；分类／搜索及已读不改数据归属 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| LST-002 | 会话行头像上限60pt | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 保留轻量快照、diffable与稳定ID；分类／搜索及已读不改数据归属 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| LST-003 | 标题与时间共享基线 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 保留轻量快照、diffable与稳定ID；分类／搜索及已读不改数据归属 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| LST-004 | 会话摘要最多两行 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 保留轻量快照、diffable与稳定ID；分类／搜索及已读不改数据归属 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| LST-005 | 草稿摘要与正式回复区分 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-006 | 置顶和未读可同时显示 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-007 | 归档计数只统计归档范围 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-008 | 最近分类固定第一 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 保留轻量快照、diffable与稳定ID；分类／搜索及已读不改数据归属 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| LST-009 | 项目分类点击与横向分页共享选择 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-010 | 选中分类自动进入可见区域 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-011 | 各分类保留独立列表位置 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-012 | 多选模式禁止分类横向分页 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 保留轻量快照、diffable与稳定ID；分类／搜索及已读不改数据归属 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| LST-013 | 会话更新使用稳定ID差异更新 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 保留轻量快照、diffable与稳定ID；分类／搜索及已读不改数据归属 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| LST-014 | 长按预览最多三条消息 | TG38/TG80/TG81 | `FamiliarChatsHome.previewMessages / FamiliarReadOnlyMessage` | R4保留数据库最多三条、正文1200字符的本地快照；只读附件外观复用生产，图库／消息动作／Runtime不挂载；属于公开UIKit预览适配 | 保留适配 | B-R4（仅编译） | 待验收 |
| LST-015 | 预览提交打开同一会话 | TG38 | `FamiliarConversationList.Coordinator` | R4静态复核预览配置以会话UUID为identifier，提交仍在菜单收尾后打开同一ID；附件显示变化不替换导航身份 | 保留适配 | B-R4（仅编译） | 待验收 |
| LST-016 | 搜索入口与Telegram当前设计核对 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome` | 已用本页原生搜索替代独立Sheet；精确54pt自定义吸附未移植，手感待设备 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-017 | 搜索支持当前分类与全部范围 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-018 | 取消搜索恢复分类和偏移 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-019 | 消息搜索命中后定位原消息 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| LST-020 | 空查询不执行全库检索 | TG03/TG04/TG05/TG06/TG07/TG08/TG09/TG10/TG11/TG12 | `FamiliarChatsHome / ConversationList / ChatProjectPager / LocalSearchResults` | 普通／项目聊天、会话级未读与本地分页搜索，映射Telegram列表交互；不增加社交状态 | 保留适配 | B-FINAL（仅编译） | 待验收 |

## FIL · 文件与项目

源码定位：TG12/TG54/TG55/TG62/TG63/TG64；本地主要实现：`FamiliarFileLibraryView / FamiliarFileSelection / FamiliarFileDetailView / FamiliarProjectsView`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| FIL-001 | 文件列表52pt行与40pt类型图形 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-002 | 文件类型筛选显示真实格式 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-003 | 文件名称检索不改变所属范围 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-004 | 文件支持名称和日期排序 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-005 | 文件大小排序读取准确版本字节数 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | 保留recent/oldest/name/size四种排序；类型用独立筛选，不增加类型排序 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-006 | 时间分组标题与正文层级清晰 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-007 | 文件多选显示独立勾选列 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-008 | 全选只选择当前可操作集合 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-009 | 取消选择恢复原浏览位置 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-010 | 文件长按菜单提供原预览动作 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-011 | 分享冻结准确FileVersion | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-012 | 失效历史版本不替代为最新版本 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-013 | 批量删除逐文件保持原事务 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-014 | 部分删除失败保留失败项 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-015 | 删除确认取消时零写入 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-016 | 项目详情使用统一设置行 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-017 | 项目指令保存失败保留编辑内容 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-018 | 项目Memory直达所属范围 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-019 | 项目运行记录不混入其他范围 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |
| FIL-020 | 项目删除后保留聊天及转存文件 | TG12/TG54/TG55/TG62/TG63/TG64 | `FamiliarFileLibraryView / FileSelection / FileDetailView / FamiliarProjectsView` | Familiar canonical File/Version/Scope适配Telegram文件行与选择；不接缓存清理API | 保留适配 | B-FINAL（仅编译） | 待验收 |

## SET · 设置与AI润色

源码定位：TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68；本地主要实现：`FamiliarSettingsHubView / FamiliarSettingsCatalog / FamiliarProfileHeaderMotion / FamiliarDraftRewriteSheet`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| SET-001 | 设置资料显示本机真实昵称和头像 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-002 | 头像滚动折叠保持原遮罩进度 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 原头像遮罩／缩放进度由页级UIKit控制器承载，KVO隔离滚动；离场解除观察 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-003 | 二级页返回恢复资料头部位置 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 原头像遮罩／缩放进度由页级UIKit控制器承载，KVO隔离滚动；离场解除观察 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-004 | 资料编辑取消不保存 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-005 | 设置行统一图标容器和文字间距 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsRowIcon / SettingsCatalog` | 图标容器默认29pt，辅助字号继续缩放 | 已修改 | B-FINAL（仅编译） | 待验收 |
| SET-006 | 辅助字号下状态文字纵向排列 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-007 | 设置搜索与列表共用同一路由目录 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-008 | 搜索取消保留原设置位置 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-009 | Provider发现和验证状态分开 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-010 | Provider修改配置清除旧成功验证 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-011 | 外部登录不伪装Familiar账户 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-012 | Memory显示真实归属并可筛选 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-013 | 存储统计可取消并标记不完整 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-014 | 运行详情先摘要再技术信息 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-015 | 润色使用翻译风格修正三模式 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-016 | 润色只发送正文与本次要求 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-017 | 润色请求不读取Memory历史附件 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-018 | 润色完整成功后才允许应用 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-019 | 润色晚到结果不能覆盖新草稿 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |
| SET-020 | 润色应用可撤销且不自动发送 | TG37/TG48/TG49/TG50/TG51/TG52/TG53/TG55/TG59/TG60/TG61/TG66/TG67/TG68 | `FamiliarSettingsCatalog / ProviderVerificationIdentity / ProfileHeaderMotion / DraftRewriteSheet` | 本机资料／Provider／Memory／Run为AI设置适配，复用统一行、搜索目录及原保存路径 | 保留适配 | B-FINAL（仅编译） | 待验收 |

## SYS · 全局系统偏好与资源

源码定位：TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77；本地主要实现：`FamiliarTheme / FamiliarMotion / FamiliarAccessibility / FamiliarMarkdownStyle`。

| 编号 | 可观察目标 | 源码 | Familiar落点 | 差距／适配 | 实施 | 编译 | 真机 |
|---|---|---|---|---|---|---|---|
| SYS-001 | 默认浅色使用Classic主题 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarTheme` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| SYS-002 | 跟随系统深色使用Night主题 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarTheme` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| SYS-003 | 外观覆盖设置保留用户偏好 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarTheme` | 原外观覆盖／系统选择继续生效，未重置用户偏好 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-004 | 导航与消息主题同步变化 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarTheme` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| SYS-005 | 夜间强调色前景有正确反差 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarTheme` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| SYS-006 | 降低透明度使用实色控件 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-007 | 增强对比度不只依赖透明度变化 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-008 | 降低动效取消装饰性缩放 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-009 | 发送与图库在降低动效下可用 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-010 | 玻璃仅用于导航和控件 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-011 | 交互目标至少44pt | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-012 | 图标按钮具有可访问名称 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-013 | 消息结构不压平成单个辅助标签 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-014 | 隐藏页面不进入当前辅助树 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-015 | 运行播报不移动VoiceOver焦点 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-016 | 大字体不裁切操作名称 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-017 | 中文和英文资源键一致 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |
| SYS-018 | 默认壁纸从Bundle读取且不联网 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarTheme` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| SYS-019 | 第三方资源保留来源与许可证 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarTheme` | 统一气泡/主题实现；待编译与设备确认 | 已修改 | B-FINAL（仅编译） | 待验收 |
| SYS-020 | 真机视觉性能与编译分别记录 | TG02/TG04/TG07/TG24/TG55/TG69/TG70/TG74/TG76/TG77 | `FamiliarRootView / FamiliarTheme / FamiliarAccessibility / FamiliarMotion` | 已核对公开系统API、偏好、语义辅助树与资源；设备行为独立待验收 | 代码已对齐 | B-FINAL（仅编译） | 待验收 |

## 本轮编译证据

B-R2：2026-10-21，具体iPhone18 Pro／iOS27.0／arm64 Debug build-for-testing，exit0、TEST BUILD SUCCEEDED，最终日志无warning/error；日志 `/tmp/Familiar-Telegram-round2-final-build.log`。包含两项状态行几何回归、一项流式长文本终态原生交接集成回归及扩展文本分类，均未执行。未启动Simulator、未截图或安装设备。只更新本轮18个编号的编译列，不批量修改其余目标或真机状态。


B-FINAL：2026-10-21，iPhone18 Pro／iOS27.0／arm64，Debug build-for-testing，exit0、TEST BUILD SUCCEEDED；App／单元测试／UI测试目标均编译，最终日志无warning/error。日志 `/tmp/Familiar-Telegram-alignment-final-build.log`。含混合方向末行回归，只编译不执行。未启动Simulator、未截图、未安装设备。B-FINAL同时覆盖现有代码的集成编译，不证明每行行为／像素／性能已通过。

## 所有者反馈格式

```text
编号：BUB-001
构建／设备／iOS：
复现步骤与预期：
实际表现：
截图或录屏：
结果：通过／需修正
```

没有修正版设备采样前，既有hwf卡死／CPU问题继续开放。性能样本、真实Provider、权限和视觉结果相互独立。

# Telegram iOS：UI、手势与转场研究

研究日期：2026-10-18；参照提交 [f1dd7a2](https://github.com/TelegramMessenger/Telegram-iOS/tree/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838)。截图由所有者提供；源码阅读不等于运行手感验证。功能语义见 [功能研究](2026-10-18-telegram-ios-functionality.md)，Familiar 目标见 [总计划](../20-telegram-chat-ui-roadmap.md)。

## 源码观察

| 组件（相对 `submodules/`） | 机制 | Familiar 适配 |
|---|---|---|
| `ChatListUI/Sources/Node/ChatListItem.swift` | 标题、日期、草稿/消息预览、媒体与 badge 分别布局；支持辅助功能操作 | 轻量列表快照；真实状态；列表内不创建 WebView |
| `ChatListUI/Sources/Node/ChatListViewTransition.swift:53–110` | stable-ID diff 区分插入、更新、重新载入 | 原生 diffable；内容更新 reconfigure，不替换整行身份 |
| `ChatListUI/Sources/ChatListControllerNode.swift:604–805` | 分类分页有边界回弹、速度和位移判断，选中状态在切换完成时提交 | 原生横向分页与顶部分类共用状态；编辑时禁止分页 |
| `TelegramUI/Components/HorizontalTabsComponent/Sources/HorizontalTabsComponent.swift:913–939` | 按分页 fraction 插值选中区域位置和宽度 | 一份分页进度驱动选中胶囊，分类各自保存列表位置 |
| `ChatListUI/Sources/ChatListController.swift:1899–2011` | 预览内容、来源行与动作菜单分离 | 最近三条生产消息的只读快照；系统预览提交进入同一会话 |
| `TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift:1774–1960` | 菜单、附件、文本分开布局；菜单图标随展开切换 | 技能独立入口，取消斜线触发；附件回形针继续系统 Menu |
| `TelegramUI/Sources/CommandMenuChatInputContextPanelNode.swift:66–342` | 底部锚定列表、独立玻璃背景、稳定列表更新、弹簧进出 | SwiftUI 原生列表组合；面板不进入编辑框内部高度 |
| `TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift:665–774` | 文本和状态共同测量，考虑 RTL、引用和末行空间 | 双侧气泡，元信息独立末行；保留现有富文本渲染 |
| `TelegramUI/Sources/ChatMessageTransitionNode.swift:665–728` | 输入来源与目标消息坐标映射，横纵动画分开 | 新消息仅一次入场；流式更新不重复转场 |
| `TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingScreen.swift` | 原生底部编辑器与三类独立状态 | 翻译/风格/修正，模型菜单、预览、应用和撤销 |

## 技术决定

- SwiftUI TabView、独立 NavigationStack、原生 Liquid Glass；不搬入 Telegram 的 AsyncDisplayKit/SSignalKit/Postbox。
- 会话列表使用 UICollectionView 列表布局、Diffable Data Source、UIHostingConfiguration；原生 delegate 负责预览转正。
- 横向手势用于分类分页，行操作由长按和多选提供，避免同轴竞争。
- 预览复用生产消息气泡，但不创建完整聊天页、Runtime 或草稿编辑器；关闭即释放。
- 消息正文是稳定内容层；玻璃只用于导航、输入控件与浮层。
- 控件命中范围至少 44pt；遵守 Dynamic Type、VoiceOver、Reduce Motion、Reduce Transparency。
- 不复制截图中的第三方聊天内容、头像、成员数或虚构在线状态。

## 视觉验证

浅/深色、大字体、小屏、空列表、多项目、长标题、媒体/文件、复杂 Markdown、菜单键盘切换、预览进出、运行期间返回列表分别截取生产页面。所有者视觉与真机签字独立于自动测试。

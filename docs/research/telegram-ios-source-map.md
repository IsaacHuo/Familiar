# Telegram iOS 源码登记

参照提交：[f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838](https://github.com/TelegramMessenger/Telegram-iOS/tree/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838)。2026-10-20 通过 git ls-remote 核对，上游 HEAD 与此一致。本路线始终固定此提交。

以下 TG01–TG68 沿用 2026-10-18 的研究编号和已读范围。下载、检索、关键片段、全文阅读分别记录；继承的研究不能充当本轮实现或运行通过证据。新增阅读在末节登记。源码本地副本在 /tmp，不作为长期链接。



下表来自固定提交的 68 个候选源文件。行段只表示已读范围；“关键函数片段”不表示整函数或整文件已经审完。“仅检索”条目只能指向后续阅读方向，结论列写明待查事项。所有链接锁定同一提交，不依赖临时研究副本继续存在。

登记字段：源文件完整路径/固定提交链接、阅读深度和范围、机制或待查项、Familiar 对应组件、路线关联。

### A.1 根导航、首页与搜索

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG01 | [submodules/TelegramUI/Sources/TelegramRootController.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/TelegramRootController.swift#L238) | 关键函数片段；238–260 | 根页面与默认选择独立于会话详情 | FamiliarAppShell；NAV |
| TG02 | [submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift#L645) | 关键函数片段；645–735；859–888 | 布局尺寸、选中区域与玻璃层分工；不搬入透镜实现 | FamiliarAppShell；SYS |
| TG03 | [submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListNavigationBar.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListNavigationBar.swift#L15) | 关键函数片段；15–16；308–426；443–455；621–630 | 搜索展开比例、头部可见高度、边缘效果和分类位置 | FamiliarChatProjectPager；LST/NAV |
| TG04 | [submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListHeaderComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListHeaderComponent.swift#L627) | 关键函数片段；627–631；1156–1207 | 标题测量与左右控件分别由单个玻璃容器承载 | FamiliarChatView / FamiliarChatsHome；NAV/LST |
| TG05 | [submodules/TelegramUI/Components/HorizontalTabsComponent/Sources/HorizontalTabsComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/HorizontalTabsComponent/Sources/HorizontalTabsComponent.swift#L683) | 关键函数片段；683–699；913–998 | 选中区域插值、滚动偏移换算与选中项可见性 | FamiliarChatProjectPager；LST |
| TG06 | [submodules/ChatListUI/Sources/ChatListControllerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListControllerNode.swift#L1740) | 关键函数片段；1740–1838；2267–2339 | 列表偏移接入头部，搜索在中间位置吸附 | FamiliarChatProjectPager / FamiliarConversationList；LST |
| TG07 | [submodules/ChatListUI/Sources/Node/ChatListItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/Node/ChatListItem.swift#L1503) | 关键函数片段；1503–1597；5440–5508 | 列表摘要的可访问性文本、操作和布局更新收尾；其余行布局待续 | FamiliarConversationList；LST |
| TG08 | [submodules/ChatListUI/Sources/Node/ChatListViewTransition.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/Node/ChatListViewTransition.swift#L1) | 关键函数片段；1–175 | 稳定 ID 差异更新，区分初始、交互、重载和滚动定位 | FamiliarConversationList；LST |
| TG09 | [submodules/ChatListUI/Sources/ChatListSearchContainerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListSearchContainerNode.swift#L476) | 关键函数片段；476–484；714–733 | 查询状态入口和空查询处理；其他搜索分支待续 | FamiliarChatsHome；LST |
| TG10 | [submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift#L1540) | 关键函数片段；1540–1614 | 查询/范围组成检索身份，管理共享查询状态；不移植远程搜索 | FamiliarChatsHome；LST |
| TG11 | [submodules/ChatListUI/Sources/ChatListSearchPaneContainerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListSearchPaneContainerNode.swift#L283) | 关键片段；283–325（分页与手势竞争）；326–372仍仅检索 | 已定位分页手势和取消入口，需继续阅读完整竞争与收尾流程 | FamiliarChatProjectPager；LST |
| TG12 | [submodules/ChatListUI/Sources/ChatListSelection.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatListUI/Sources/ChatListSelection.swift#L1) | 全文审阅；1–87 | 批量操作可用性来自选择集合和真实未读状态 | FamiliarChatsHome；LST |

### A.2 消息、历史、选择与定位

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG13 | [submodules/TelegramUI/Components/Chat/ChatHistoryEntry/Sources/ChatHistoryEntry.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatHistoryEntry/Sources/ChatHistoryEntry.swift#L53) | 关键函数片段；53–90 | 消息、消息组、未读等条目具有独立稳定身份 | FamiliarChatTimeline；SCR |
| TG14 | [submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatHistoryItemNeighbors.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatHistoryItemNeighbors.swift#L1) | 全文审阅；1–50 | 邻接条目发布日期/合并信息，供布局判断使用 | FamiliarChatTimeline；BUB/SCR |
| TG15 | [submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift#L67) | 关键函数片段；67–118；249–310、315–369（日期文案/13pt字号/22pt背景） | 日期头合并身份、吸附方向与高度；完整浮动转场待续 | FamiliarChatTimeline；TXT |
| TG16 | [submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift#L226) |关键函数片段；226–305；450–479；610–624（11/17状态字号）；978–1038（R2无回应时状态建议宽度与最终高度） | 正文尾部布局输入与状态参数；不据此宣称已审完整排版算法 | FamiliarChatTurn / FamiliarChatRow；TXT |
| TG17 | [submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/StringForMessageTimestampStatus.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/StringForMessageTimestampStatus.swift#L178) | 关键函数片段；178–222 | 导入时间与作者显示分支；完整时间本地化策略待续 | FamiliarChatTurn / FamiliarChatRow；TXT |
| TG18 | [submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift#L870) | 关键函数片段；870–942；1399–1440；5680–5820 | 气泡命中分发、菜单激活来源和可访问性动作 | FamiliarMessageInteraction；BUB/ACT |
| TG19 | [submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift#L665) |关键函数片段；665–735；688–780（R2末行／建议宽度与最终文本框） | 正文末行、RTL/引用块与时间状态共同测量 | FamiliarChatTurn / FamiliarMarkdownWebView；TXT |
| TG20 | [submodules/TelegramUI/Components/Chat/ChatMessageReplyInfoNode/Sources/ChatMessageReplyInfoNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageReplyInfoNode/Sources/ChatMessageReplyInfoNode.swift#L188) | 关键函数片段；188–224；630–664 | 引用摘要和展开行数；源消息跳转须另行设计 | FamiliarChatRow / FamiliarChatTurn；TXT |
| TG21 | [submodules/TelegramUI/Components/Chat/ChatMessageSwipeToReplyNode/Sources/ChatMessageSwipeToReplyNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageSwipeToReplyNode/Sources/ChatMessageSwipeToReplyNode.swift#L146) | 关键函数片段；146–185 | 滑动进度、图标反馈与阈值后的动画；手势触发链待续 | FamiliarMessageInteraction；ACT研究参照 |
| TG22 | [submodules/TelegramUI/Components/Chat/ChatNavigationButton/Sources/ChatNavigationButton.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatNavigationButton/Sources/ChatNavigationButton.swift#L1) | 全文审阅；1–32 | 导航动作身份独立于 UIBarButtonItem 实例 | FamiliarChatView；SCR |
| TG23 | [submodules/TelegramUI/Sources/ChatHistoryListNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatHistoryListNode.swift#L3680) | 关键函数片段；3680–3725；3730–3784；4051–4080（状态命中） | 历史窗口随边界推进，加载与空历史状态分开 | FamiliarChatTimeline / FamiliarChatController；SCR |
| TG28 | [submodules/TextSelectionNode/Sources/TextSelectionNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TextSelectionNode/Sources/TextSelectionNode.swift#L495) | 关键函数片段；495–560；750–806 | 原文/显示文本范围转换及复制、引用等选择动作 | FamiliarMessageInteraction / FamiliarMarkdownWebView；ACT |
| TG38 | [submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift#L56) | 关键片段；56–115（菜单内容与资格）；338仍仅检索 | 已定位菜单上下文/限制入口；不可据此宣称全部动作权限已审 | FamiliarMessageInteraction；ACT |
| TG39 | [submodules/TelegramUI/Sources/Chat/ChatControllerNavigateToMessage.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/Chat/ChatControllerNavigateToMessage.swift#L44) | 关键函数片段；44–53；97–125；228–237 | 稳定消息定位、来源位置与高亮目标，必要时加载目标窗口 | FamiliarChatTimeline；ACT/SCR |
| TG40 | [submodules/TelegramUI/Sources/ChatControllerUpdateSearch.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatControllerUpdateSearch.swift#L18) | 关键函数片段；18–62；86–160 | 范围/查询变化驱动搜索，维护数量、当前命中、后续页与高亮 | FamiliarChatsHome / FamiliarChatTimeline；ACT |
| TG41 | [submodules/TelegramUI/Sources/ChatControllerOpenCalendarSearch.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatControllerOpenCalendarSearch.swift) | 待审；未读正文 | 已选入候选，待核对日期跳转入口、结果定位与返回关系 | FamiliarChatTimeline；待审候选，本轮不增加日期查找 |
| TG42 | [submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageMerge.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageMerge.swift#L1) | 全文审阅；1–15 | 区分不合并、视觉合并和语义合并，避免混成一个布尔值 | FamiliarChatTimeline；BUB |
| TG43 | [submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageMergeFingerprint.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageMergeFingerprint.swift#L180) | 关键函数片段；180–263 | 合并考虑作者、时间和内容边界；Familiar 必须额外尊重 Run 边界 | FamiliarChatTimeline；BUB |
| TG47 | [submodules/TelegramUI/Sources/PreparedChatHistoryViewTransition.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/PreparedChatHistoryViewTransition.swift#L83) | 关键函数片段；70–153 | 已读初始/交互/重载、插入/更新及静止区初始化，完整静止区和滚动算法待读 | FamiliarChatTimeline；SCR |
| TG58 | [submodules/TelegramUI/Sources/ChatHistoryNavigationButtons.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatHistoryNavigationButtons.swift#L58) | 关键函数片段；58–96 | 返回最新按钮角标与其他导航状态分别更新 | FamiliarChatTimeline；SCR |

### A.3 输入、草稿与面板

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG24 | [submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift#L3155) | 关键函数片段；3155–3215；5710–5758 | 正文与占位共享 inset，背景点击明确聚焦实际输入器 | FamiliarComposer / FamiliarComposerTextView；INP |
| TG25 | [submodules/TelegramUI/Components/Chat/ChatInputTextNode/Sources/ChatRichTextInputNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatInputTextNode/Sources/ChatRichTextInputNode.swift#L127) | 关键函数片段；127–206（接口）；735–790 | 选区/光标坐标与实际 first responder 接口明确分开 | FamiliarComposerTextView；INP |
| TG26 | [submodules/TelegramUI/Components/Chat/ChatTextInputActionButtonsNode/Sources/ChatTextInputActionButtonsNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatTextInputActionButtonsNode/Sources/ChatTextInputActionButtonsNode.swift#L315) | 关键函数片段；315–376；376–469 | 动作按钮共享布局尺寸，变换期间使用 position/bounds；整体切换链待续 | FamiliarComposer；INP |
| TG27 | [submodules/ChatInterfaceState/Sources/ChatInterfaceState.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ChatInterfaceState/Sources/ChatInterfaceState.swift#L512) | 关键函数片段；512–589 | 草稿输入、选区、回复、编辑、历史位置分别建模；不移植同步协议 | FamiliarChatDraftPersistence / FamiliarChatController；INP |
| TG44 | [submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift#L1711) | 仅检索；1711–1716；1814–1819（命中） | 已定位控制器请求输入焦点的入口，完整加载/恢复流程待续 | FamiliarChatView / FamiliarComposerTextView；INP |
| TG45 | [submodules/TelegramUI/Components/ChatInputPanelContainer/Sources/ChatInputPanelContainer.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/ChatInputPanelContainer/Sources/ChatInputPanelContainer.swift#L270) | 关键函数片段；270–321 | 面板展开状态、拖动收尾及启用条件；与输入模式切换需共同核对 | FamiliarComposer；INP |
| TG46 | [submodules/TelegramUI/Components/Chat/ChatInputTextNode/ChatInputTextViewImpl/Sources/ChatInputTextViewImpl.m](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatInputTextNode/ChatInputTextViewImpl/Sources/ChatInputTextViewImpl.m#L1) | 关键函数片段；1–150 | 原生文本控件动作路由、粘贴与按键；包含旧系统/私有路径，不能整段搬入 | FamiliarComposerTextView；INP |

### A.4 消息转场

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG29 | [submodules/TelegramUI/Components/Chat/ChatMessageTransitionNode/Sources/ChatMessageTransitionNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageTransitionNode/Sources/ChatMessageTransitionNode.swift#L1) | 全文审阅；1–15 | 转场装饰的窄接口；实际动画实现位于另一同名文件 | FamiliarChatTimeline；MED |
| TG30 | [submodules/TelegramUI/Sources/ChatMessageTransitionNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Sources/ChatMessageTransitionNode.swift#L650) | 关键函数片段；650–728 | 输入来源坐标映射到目标气泡，横纵方向分别驱动 | FamiliarChatTimeline / FamiliarChatScrollState；MED |

### A.5 附件、文件与媒体

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG31 | [submodules/AttachmentUI/Sources/AttachmentController.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/AttachmentUI/Sources/AttachmentController.swift#L285) | 关键函数片段；285–316（协议）；511–540 | 媒体选择数量与准备进度的观察入口；完整附件控制器生命周期待续 | FamiliarComposer；MED |
| TG32 | [submodules/GalleryUI/Sources/ZoomableContentGalleryItemNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/ZoomableContentGalleryItemNode.swift#L70) | 关键函数片段；70–110；128–170 | 双击缩放及尺寸变化后重置内容的规则；其余缩放分支待续 | FamiliarDraftImagePreviewView / FamiliarAttachmentPreviewView；MED |
| TG33 | [submodules/GalleryUI/Sources/GalleryControllerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/GalleryControllerNode.swift#L30) | 关键函数片段；523–616（拖拽淡出／距离和速度退出）；旧30–31、112–130、658仍仅检索 | 已定位分页关闭、来源转场和可访问性退出，需追完整生命周期 | FamiliarAttachmentPreviewView；MED |
| TG34 | [submodules/GalleryUI/Sources/GalleryItemTransitionNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/GalleryItemTransitionNode.swift#L1) | 全文审阅；1–91 | 预览转场保留来源视图、来源矩形和进度回调 | FamiliarImageZoom / FamiliarAttachmentPreviewView；MED |
| TG35 | [submodules/GalleryUI/Sources/Items/ChatDocumentGalleryItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/Items/ChatDocumentGalleryItem.swift#L96) | 仅检索；96–132（字段） | 已定位文档状态/获取控制字段，完整打开与取消逻辑待读 | FamiliarAttachmentPreviewView；MED |
| TG36 | [submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift#L133) | 关键函数片段；341–346（释放）；133–172/224–237仍仅检索 | status/data/recognition 释放；fetch dispose 注释无效，完整加载链待续 | FamiliarImageAttachmentView；MED |
| TG56 | [submodules/TelegramUI/Components/Chat/ChatMessageFileBubbleContentNode/Sources/ChatMessageFileBubbleContentNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageFileBubbleContentNode/Sources/ChatMessageFileBubbleContentNode.swift#L18) | 仅检索；18–100（命中） | 文件气泡把操作交给交互文件节点，需继续追真实状态组合 | FamiliarFileTile；MED |
| TG57 | [submodules/FileMediaResourceStatus/Sources/FileMediaResourceStatus.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/FileMediaResourceStatus/Sources/FileMediaResourceStatus.swift#L69) | 关键函数片段；69–142 | 区分准备、可用和播放状态；Familiar 只取真实本地导入状态，其余分支待续 | FamiliarFilePresentation；MED |
| TG62 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/Panes/PeerInfoListPaneNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/Panes/PeerInfoListPaneNode.swift#L79) | 关键函数片段；79–82；100–116（命中）；528–530 | 文件等媒体列表复用历史节点与选择状态；完整筛选/跳转待续 | FamiliarFileLibraryView；FIL |
| TG63 | [submodules/TelegramUI/Components/StorageUsageScreen/Sources/StorageFileListPanelComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/StorageUsageScreen/Sources/StorageFileListPanelComponent.swift#L743) | 关键函数片段；844–954；743/1048–1104 仍仅检索 | 已读可见区域、稳定 ID 复用、选择与文件图标映射；完整释放/缓存边界待续 | FamiliarFileLibraryView；FIL |
| TG65 | [submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift#L294) | 关键函数片段；262–324；609仍仅检索 | 已读订阅释放/当前 fetch 取消，缩略图和完整状态组合待续 | FamiliarFileTile / FamiliarImageAttachmentView；MED |

### A.6 AI 文本编辑

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG37 | [submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingScreen.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingScreen.swift#L117) | 关键函数片段；117–142（模式）；200–229；775–807；1090–1125；1239–1260 | 三模式状态、统一外部状态与模式/内容/动作布局分层 | FamiliarDraftRewriteSheet；SET |
| TG66 | [submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingTextAreaComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingTextAreaComponent.swift#L28) | 关键片段；160–208（文本命中与淡出）；旧28–90、362–367仍仅检索 | 已定位文本结果、复制、选择和命中处理，布局/取消流程待深读 | FamiliarDraftRewriteSheet；SET |
| TG67 | [submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingStyleSelectionComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingStyleSelectionComponent.swift#L18) | 关键片段；213–223（0.4秒弹簧／0.2秒淡出）；旧18–54、75–76仍仅检索 | 已定位选中风格与创建动作；保存/删除/预览整条链路待读 | FamiliarDraftRewriteSheet；SET |
| TG68 | [submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingLanguageSelectionComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingLanguageSelectionComponent.swift#L17) | 关键片段；75–115（语言状态身份／列表布局字段）；其余仅检索 | 已定位语言与搜索行布局模型；检索、选择和最近项交互待读 | FamiliarDraftRewriteSheet；SET |

### A.7 设置、Project 参照与存储

| 编号 | Telegram 源文件（固定提交） | 深度与范围 | 机制或待查项 | Familiar 对应 / 路线 |
|---|---|---|---|---|
| TG48 | [submodules/SettingsUI/Sources/SettingsController.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/SettingsUI/Sources/SettingsController.swift#L1) | 全文审阅；1–76 | 该文件主要是设置控制器协议/工厂，不是设置主列表；列表另见 PeerInfoSettingsItems | FamiliarSettingsView；SET |
| TG49 | [submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift#L70) | 关键函数片段；70–108；4525–4550（搜索入口命中） | 条目含 ID、标题、别名、路径与展示动作；完整分词匹配待续 | FamiliarSettingsView / FamiliarSettingsRoute；SET |
| TG50 | [submodules/SettingsUI/Sources/Search/SettingsSearchResultItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/SettingsUI/Sources/Search/SettingsSearchResultItem.swift#L76) | 仅检索；76–149（字段/初始化） | 已定位搜索结果标题/路径行组件，布局和可访问性待深读 | FamiliarSettingsView；SET |
| TG51 | [submodules/SettingsUI/Sources/Search/SettingsSearchRecentQueries.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/SettingsUI/Sources/Search/SettingsSearchRecentQueries.swift#L1) | 全文审阅；1–72 | 最近设置条目按稳定 ID 记录，提供移除和清空 | FamiliarSettingsView；SET |
| TG52 | [submodules/ItemListUI/Sources/ItemListControllerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ItemListUI/Sources/ItemListControllerNode.swift#L134) | 仅检索；134–178；286；464（命中） | 已定位搜索、空态、焦点目标和布局后动作，完整状态更新待读 | FamiliarSettingsView / FamiliarProjectDetailView；SET |
| TG53 | [submodules/ItemListUI/Sources/ItemListController.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/ItemListUI/Sources/ItemListController.swift#L286) | 仅检索；286；344–377（命中） | 已定位原生玻璃导航与标题模式切换；不移植完整列表框架 | FamiliarSettingsView；SET |
| TG54 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenItem.swift#L1) | 全文审阅；1–23 | 列表条目身份与节点更新职责分离；不能把注释中的焦点处理当作有效实现 | FamiliarSettingsRowIcon / FamiliarProjectContextRow；SET |
| TG55 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ListItems/PeerInfoScreenDisclosureItem.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ListItems/PeerInfoScreenDisclosureItem.swift#L1) | 关键函数片段；1–150；154–217 | 模型、行高/图标/文字与行尾状态测量 | FamiliarSettingsView / FamiliarProjectContextRow；SET |
| TG59 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift#L32) | 关键函数片段；32–145 | 已读编辑/资料分组和条件状态生成；账号/会员不适用于 Familiar，其他分支待续 | FamiliarSettingsView；SET |
| TG60 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift#L23) | 关键函数片段；23–64 | 已读 push/栈替换及资料入口，其他导航动作待续 | FamiliarSettingsRoute / FamiliarSettingsView；SET |
| TG61 | [submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenItemSectionContainerNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenItemSectionContainerNode.swift#L39) | 关键函数片段；87–133；39–41 仍仅检索 | 已读稳定项布局/移除和背景高度，完整更新函数待续 | FamiliarSettingsView / FamiliarProjectDetailView；SET |
| TG64 | [submodules/TelegramUI/Components/StorageUsageScreen/Sources/StorageCategoriesComponent.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/StorageUsageScreen/Sources/StorageCategoriesComponent.swift#L18) | 关键函数片段；18–68 | 存储类别记录大小/占比和选择状态，统计数据与清理动作分开 | FamiliarStorageSettingsView；FIL/SET |

### A.8 阅读进度与待续

原68项登记当前深度：{'关键片段': 52, '全文': 9, '待审': 1, '仅检索': 6}。仅反映表中实际行段，不把未读分支视为已审。

后续按真机差距补读必要分支与销毁链路；新的阅读记录写具体范围，不以取得整文件替代全文审阅。未采用的社交／日期查找／最近搜索等分支不自动进入产品范围。


## 当前核对说明

2026-10-20至21的Familiar核对覆盖账本各行对应的生产组件与调用入口，复用固定提交已有研究，并补读主题、气泡、标题、输入、选择、搜索、图库、设置行及润色关键片段。未声称重读Telegram整个仓库，未将不相关待审文件升级为全文。每行研究深度仍以实际登记范围为准。

## 本轮补充阅读

| 编号 | 固定源码 | 已读范围与用途 |
|---|---|---|
| TG69 | [DefaultDayPresentationTheme](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift) | 390–425、575–705、1000–1025、1100–1120；Classic/Day 消息色与默认背景 |
| TG70 | [DefaultDarkPresentationTheme](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramPresentationData/Sources/DefaultDarkPresentationTheme.swift) | 320–400、520–640；Night 收发颜色、状态与背景 |
| TG71 | [PresentationData](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramPresentationData/Sources/PresentationData.swift) | 67–79、400–425、860–905；字体、气泡参数及主题/壁纸分离 |
| TG72 | [ChatMessageItemCommon](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageItemCommon.swift) | 1–20、132–162；窄屏减36pt/宽屏85%、边缘、最小尺寸、文字及媒体inset |
| TG73 | [ChatMessageBubbleImages](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramPresentationData/Sources/ChatMessageBubbleImages.swift) | 1–430；路径已与固定提交的原文件核对，邻接四角、尾角两椭圆、33pt母版和拉伸点 |
| TG74 | [PresentationThemeSettings](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift) | 554–582、650–657；默认16/8pt合并圆角、Classic和跟随系统Night |
| TG75 | [MakePresentationTheme](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift) | 1–38；默认主题工厂与自定义主题分开 |
| TG76 | [WallpaperBackgroundNode](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/WallpaperBackgroundNode/Sources/WallpaperBackgroundNode.swift) | 1500–1548；正强度softLight、负强度黑底/渐变透明度 |
| TG77 | [默认壁纸资源](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Resources/fqv01SQemVIBAAAApND8LDRUhRU.tgv) | 固定资源gzip SVG解压，按原1440×2960 viewBox无损栅格化，应用不下载壁纸 |
| TG78 | [ChatTitleView](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift) | 20–30、1025–1070；17pt标题／13pt副标题、组合高度居中；Familiar副标题为真实模型 |

## R2 对照范围

本轮补读TG19 688–780与TG16 978–1038，按“正文先测量末行、状态给建议宽度、最终确定尺寸”的机制收敛原生布局。Familiar不引入回应／社交状态，保留8pt正文时间间隔及RTL／末尾空行独立状态行。UI实现位置为TextAndTimeLayout、MarkdownBlock、MessageInteraction和ReadOnlyMessage；WK退场身份保护延续现有会话／呈现隔离，不改变Runtime。

## R3 对照范围

- TG73重新核对90–246、427：33pt母版、收／发拉伸点18/24与top19。SwiftUI必须显式传入capInsets，不能依赖UIImage的拉伸元数据后再调用无参数resizable；截图长气泡椭圆据此修正。
- TG72 132–154：图片圆角15、300×380上限、170×74最小视口、时间右／下6；文件内边距15/9/15/12。Familiar图片实际Layout视口承载裁切／源锚，极端比例居中裁切；多图纵向顺序属适配，未搬入相册拼格。
- TG56 99–200：只有内容末尾承载文件状态，交互节点布局／准确文件委托保留。TG65 570–605、717–762、1015–1075、1259–1278：16/13比例字体、文件真实名／大小、状态独立参与最终高度；Familiar保留44pt分享和canonical版本／scope／撤销语义。
- TG16补读760–783：媒体状态背景上下2pt／左右7pt；Familiar采用白字与半透明Capsule，媒体颜色／背景渲染属于公开SwiftUI适配。

| 编号 | 固定源码 | 已读范围与用途 |
|---|---|---|
| TG79 | [ChatMessageInteractiveMediaNode](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift) | 1108–1223、1915–1953；状态测量、受约束图片视口／极端比例、右下角状态位置与无状态时清理；其余只下载未审阅 |

## R4 对照范围

- TG38补读320–395：上下文菜单暂停已读、dismissed恢复；后续动作使用dismiss完成回调。TG28补读750–806：显示文本转换为原始选择范围，按资格提供复制／引用／翻译并收尾选择。Familiar用公开UIKit菜单保留这些边界，增加实例／消息／块／原文／资格和选择代次保护，回归覆盖迟到完成及重挂载，未执行。
- TG56／TG65沿用R3的文件状态测量与文件气泡布局；本轮读取Familiar投影isStandalone、adjustedUndoPhase和FilePresentation上下文，终态时间只给最后独立文件块，保持Run／sequence／scope／Undo。AI收据是必要适配，无Telegram授权业务对应。
- TG80／TG81明确区分同内容Neighbour（0pt）、独立气泡BubbleNeighbour（7pt）、同作者尾侧连续（7pt）和默认15pt，末端有媒体尾角。Familiar当前是分立视口／正文，采用7pt独立气泡规则；未完成0pt同容器拼接、媒体尾角或相册拼格，不能标为对应视觉通过。
- 预览复核本地最多三条查询、1200字符正文和菜单UUID提交身份；只读文件共用生产呈现而不安装操作。没有增加历史读取或Runtime。三条数量是Familiar的有界预览适配，不声称是Telegram常量。

| 编号 | 固定源码 | 已读范围与用途 |
|---|---|---|
| TG80 | [ChatMessageMediaBubbleContentNode](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageMediaBubbleContentNode/Sources/ChatMessageMediaBubbleContentNode.swift) | 421–463；媒体实际布局把相邻位置交给统一四角函数，再测量视口及2pt外边；其余下载未审 |
| TG81 | [ChatMessageBubbleContentCalclulateImageCorners](https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode/Sources/ChatMessageBubbleContentCalclulateImageCorners.swift) | 全文1–164；linear／mosaic各角、独立气泡与同内容连接、收／发媒体尾角分支 |

## 原壁纸资源复核

固定提交原tgv：183832字节，SHA-256 `3c5ef666d033ce9effe703b80348b9d7363323f0076b2856ec041923c78b0ab8`。
Bundle PNG：1440×2960，809660字节，SHA-256 `6ec67384a30536e59418c399ce76adbee6b70260ba6e9fd1d009136b5544accb`。由原gzip SVG栅格化，无重新绘制／AI替代图案；运行时无下载。背景采用公开静态MeshGradient，未移植Telegram节点渐变动画及其共享动画相位，必须作为适配验收。

## 适配原则

- 读取完整布局分支及调用上下文后再修改对应 UI；路径、行号会以固定提交核实。
- UIKit/SwiftUI 仅承接呈现，不引入 TelegramEngine、Postbox、AsyncDisplayKit 或私有透镜。
- Familiar 的 AI 功能记录借用的 Telegram 组件与差异理由，不虚构 Telegram 存在相同业务。
- 主题、背景、消息、输入、导航共享一套规则；保留第三方 notice。

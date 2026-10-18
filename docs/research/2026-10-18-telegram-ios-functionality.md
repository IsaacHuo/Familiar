# Telegram iOS：功能与状态研究

研究日期：2026-10-18。源码固定于 [f1dd7a2](https://github.com/TelegramMessenger/Telegram-iOS/tree/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838)。以下为源码研究，不代表 Telegram 动态验收。Familiar 目标方案见 [总计划](../20-telegram-chat-ui-roadmap.md)，交付现实以 `state/` 和根 `PLAN.md` 为准。

## 证据与适配

| 源码 | 观察 | Familiar 设计 |
|---|---|---|
| `TelegramUI/Sources/TelegramRootController.swift:198–245` | 根控制器创建主要 Tab，聊天列表独立存在 | 文件、聊天、设置；默认聊天；详情成为下一层 |
| `ChatListUI/Sources/ChatListControllerNode.swift:78–150,872–923` | 分类由稳定 ID 索引，移除选中分类时回退 all | 最近和 Project ID 分开；分类选择不改变 work scope |
| `ChatInterfaceState/Sources/ChatInterfaceState.swift:512–595` | compose、媒体草稿、回复对象、阅读位置分开保存；恢复时夹紧选区 | 保存文字、UTF-16 选区、技能、已导入附件；新草稿不提前创建会话 |
| `ChatListUI/Sources/Node/ChatListItem.swift:2823–2837` | 草稿优先于上条消息展示，折叠换行 | 列表显示草稿摘要，消息历史不变 |
| `ChatListUI/Sources/ChatListController.swift:1967–1976` | 预览模式显式 `canReadHistory=false` | 预览只读取冻结快照，无运行、已读、清理、播放副作用 |
| `TelegramCore/Sources/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift` | 阅读推进与手动 unread 分开 | 已完成回复看见末尾才已读；支持手动标记 |
| `ChatListUI/Sources/ChatContextMenus.swift` | 菜单依据对象与状态组合，归档/置顶/删除为不同操作 | 会话归档独立于 Project、scope 与文件；运行中禁止移动/删除 |
| `ChatListUI/Sources/ChatListSelection.swift` | 批量操作根据选择集合推导可用性 | 多选已读、归档、删除；批量删除沿用文件归属规则 |
| `TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingScreen.swift:117–144` | 翻译、风格、修正分别维护状态 | 使用用户 Provider 的草稿编辑器；预览后应用，不自动发送 |

路径均相对于 Telegram 仓库的 `submodules/`。README 是编译指南，不能替代上述功能代码。

## 产品语义

- 一个 Conversation 是一个聊天；Project 不是 IM 文件夹，它拥有指令、Memory、文件和授权边界。
- 最近包含全部未归档会话；项目分类只过滤，移动才改变归属并执行已有文件复制与授权清理。
- 归档保持原所有权；新回复不自动取消归档。角标统计未读会话，归档独立计数。
- 前台唯一 Agent 的生命周期由根会话协调器持有；浏览其他会话不改变正在执行的会话；不新增后台执行或重启续跑。
- 持久草稿的附件必须进入清理保留集；导入中的任务不跨重启续传。
- 文件 Tab 聚合 File/FileVersion，但读取与操作仍携带完整 work scope。
- 不引入 Telegram 账户、云草稿同步、Postbox、网络协议或多 Agent。

## 验收重点

重启草稿恢复、归档与新回复、旧消息阅读时保留未读、预览不清未读、跨会话阅读不影响运行、系统入口经 App Lock 正确分发、移动/删除保留 scope 约束。真实 Provider 与真机验收分别记录。

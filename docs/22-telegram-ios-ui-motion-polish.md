# Telegram UI 与动效源码迁移

参照提交：`f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`。本文件记录实际迁移与适配；编译和所有者真机验收分开。保留 Familiar 配色、纯色聊天背景、三个原生 Tab、右上角搜索和无引导空对话。Provider、Run、草稿与文件作用域沿用现有契约。

## 源码映射

以下路径均相对 Telegram 仓库；“片段”不等于全文审阅。

| 原文件/范围 | 已读机制 | Familiar 适配/状态 |
|---|---|---|
| `StorageFileListPanelComponent.swift` 245–382、844–1048（片段） | 52pt行、40pt图形、22pt勾选、48pt选择位移、按压淡出0.25s | P1 文件列表/多选 |
| `StorageUsageScreen.swift` 1240–1311、2705–2779、2930–3008（片段） | 选择面板、选中对象、菜单关闭后操作 | P1；接File/Version，不接Telegram缓存清理 |
| `ChatMessageSelectionInputPanelNode.swift` 299–329、449–499（片段） | 分享/删除分发、动作资格、底部安全区 | P1原生底部栏，保留真实删除事务 |
| `TelegramUI/Sources/ChatMessageTransitionNode.swift` 321–334、615–749、1246–1260（片段） | 0.3秒、横纵独立曲线、发送身份关联 | P2消息ID与一次性呈现 |
| `ChatMessageBubbleItemNode.swift` 1150–1205（片段） | 输入背景/正文到气泡，剪裁收尾 | P2 UIKit可见快照与现有气泡 |
| `ChatMessageItemCommon.swift` 132–162（片段） | 3pt边距、默认两侧各2pt+像素、连续0pt、0.85紧凑宽度、11/6pt正文内边距与40x35最小尺寸 | P2布局常量迁移，AI长文保留0.92阅读宽度 |
| `ChatMessageTextBubbleContentNode.swift` 688–740（片段） | 末行状态宽度、RTL/引用分支 | P2 原生末行，复杂Markdown独立末行 |
| `ChatTextInputPanelNode.swift` 3155–3243、5710–5758（片段） | 正文/占位共用几何、背景聚焦 | P2现有UITextView |
| `TextSelectionNode.swift` 771–841（片段） | 捕获选区、动作完成后清理 | P3原生/DOM选区，追加草稿不发送 |
| `GalleryControllerNode.swift` 523–616、`ZoomableContentGalleryItemNode.swift` 78–155（片段） | 50/80pt淡出、速度/距离退出、定点双击缩放 | P3 UIKit图片浏览，文档继续QuickLook |
| `ChatListItem.swift` 2295–2300、2540–2602、4048–4077（片段） | 字号比例、头像上限、行内容测量 | P4会话行；真实状态/草稿 |
| `HorizontalTabsComponent.swift` 944–1025（片段） | 选中区域与滚动坐标统一、100pt可见前瞻 | P4分类条 |
| `PeerInfoHeaderNode.swift` 1654–1768、1858–1871、1910–2078、2154–2204（片段） | 头像/标题/遮罩同进度，导航期间停用遮罩 | P4资料头部 |
| `DynamicIslandBlurNode.swift` 1–133（全文） | fractionComplete模糊与渐变，离场停止 | P4公开UIKit效果，不接Telegram节点框架 |
| `TextProcessingStyleSelectionComponent.swift` 213–223、376–402、`TextProcessingTextAreaComponent.swift` 160–235（片段） | 0.4秒弹簧选择、0.2秒淡出、内容命中 | P4 AI润色 |

源地址前缀：<https://github.com/TelegramMessenger/Telegram-iOS/blob/f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838/>。原算法注明来源，UIKit/SwiftUI桥只接业务与呈现；不引入TelegramEngine/AsyncDisplayKit整套依赖。

## 实施账本

| 切片 | 实现与代码落点 | 编译 | 真机 |
|---|---|---|---|
| P0 | `FamiliarChatReadingLifecycle` / `FamiliarChatScrollSession`：幂等开始、交互转场取消恢复、离场关闭选择和发送快照 | 通过 `/tmp/Familiar-P0-motion-build.log` | 待验收，原卡死问题仍开放 |
| P1 | `FamiliarFileLibraryView` / `FamiliarFileSelection`：52/40pt行、类型条、上下文菜单、多选、冻结作用域/版本的分享与逐项删除 | 通过 `/tmp/Familiar-P1-files-build.log` | 单项/批量/部分失败/版本待验收 |
| P2 | `FamiliarSendPresentation`、原生TextKit末行布局、Composer：持久化后消息ID关联、0.3秒横纵曲线、中文提交、附件源、输入变化 | 通过 `/tmp/Familiar-P2-chat-build.log` | 发送/键盘/长内容/返回待验收 |
| P3 | `FamiliarSelectedTextAction` / Native和WebKit编辑菜单 / `FamiliarImageGallery`：源身份、菜单退场、单一选区、追加草稿、缩放分页/拖拽/当前缩略图回归 | 通过 `/tmp/Familiar-P3-interaction-build.log` | WK菜单可见性/手势/中断待验收 |
| P4 | 会话行、分类前瞻、`FamiliarProfileHeaderMotion` / 原头像关键帧、AI润色选择与Sheet：本机滚动状态与原请求隔离 | 通过 `/tmp/Familiar-P4-polish-build.log` | 各滚动位置/动态字号/模态层级待验收 |
| P5 | 定向回归/资源与双语/JS/套件清单静态检查，最终App及两类测试目标构建 | 通过；收尾日志 `/tmp/Familiar-Telegram-motion-final-build.log` | 所有者验收单如下 |

## 适配细节

- 源码选择面板接 canonical File，不接 Telegram 清缓存 API。每个删除目标为 File ID/Scope；每项仍使用原元数据/字节事务，成功项移除、失败项保留。分享冻结具体Version，执行前验证 File、Version、Scope 与真实URL。
- 发送采集 UIKit 可见区域，不创建第二个正文WebView；提交成功才登记消息ID，最多保留5秒，失败/过期/离场/降低动效均释放。用户发送不叠加原soft-rise，流式与恢复历史不补播。正文内边距11pt/6pt±像素、最小40x35、边缘3pt与相邻间距采用原紧凑常量，跨Run身份仍不合并。
- 输入正文先提交组合文字，再采集/发送。润色入口与回形针纵向共用玻璃，释放正文宽度；正文测量不依赖该入口的宽度变化。
- Native编辑菜单使用iOS26多选区delegate；WK通过公开Responder菜单构建与延迟元素读取实际DOM选区。动作捕获消息/块/正文身份，菜单退场后才回填；审批/澄清占用输入区时不提供该回填。离场与切换选区释放旧选择，已读记录不参与布局状态。
- 图片使用UIKit原生缩放/分页容器。Telegram的50/80pt透明度阈值、内容3屏对应视口1/4退出距离和1.0滚动速度阈值迁移；UIPan单位换算为1000pt/s。横向分页和放大图片移动优先，UIKit弹簧承担取消恢复。只准备当前页3072像素与邻页512像素，缓存仍为24MiB/120项成本提示；不是内存硬上限或实测结果。
- 图片源使用弱UIView登记和可见裁切；关闭时按当前图片ID寻找源，缺失或屏幕外淡出。图库仅显示原文件名/真实页码，不编辑已发图片；文档仍使用QuickLook/原受限HTML预览。补VoiceOver翻页、Escape退出和非当前页辅助树边界。
- 资料头部的控制器挂在设置页，第一行仅登记源位置；行被回收后仍可保持折叠标题。UIView层隔离滚动更新，头像只在数据变化时解码。`TelegramAvatarMask.json` 从原UserAvatarMask.tgs提取2条路径/22个关键帧，保留空间切线与线性时间插值；0.55头像/0.6标题末态、120pt遮罩、原模糊/淡出公式保留。应用内安全区按公开坐标换算；原设备/横屏门控作UIKit适配。
- 会话行使用源码字号比例和60pt头像上限，Project并入摘要；长按预览最多3条，每条1200字符，本地富文本投影，不加载完整消息WebView。
- AI润色用0.4秒选择指示区域迁移和系统medium/large Sheet，键盘展开后恢复此前所选高度；请求/版本/执行占用不变。Project/运行记录继续复用U4已接入的紧凑行和渐进披露，本片不重做其数据层。

## 行为约束

选区动作冻结消息/正文块与选中文本；追加到现有草稿，非空时隔两个换行，保留附件/技能，不自动发送。文件删除冻结File ID/作用域，包含全部版本；每项沿原事务执行，失败项保留并报告。发送呈现只能由已持久化用户消息触发一次。几何与动画进度不能驱动数据库查询或全时间线重建。

## 验证

只做指定arm64构建与静态检查，不启动Simulator或执行测试。记录各片日志、未执行回归与真机待确认项；持续卡死仍以真机采样定位。设备检查覆盖返回取消、中文/多行输入、流式/长内容、选区、图片翻页后退出、批量删除部分失败和润色晚到响应。


## 所有者真机检查单

1. Files：类型/归属/排序；点按精确版本；长按选择、全选/取消；分享失效文件；删除确认取消、批量部分失败、成功删除全部版本。
2. 聊天：中文/Emoji提交、单行到六行、纯附件、连续运行后的再次发送；旧消息阅读、工具展开、回到底部和半程取消返回。
3. 选择：用户短文、AI纯文/Markdown/代码；首次菜单即有动作；追加后保留原草稿/附件/技能；切会话/退出/审批期间不晚到回填。
4. 图片：从草稿/消息/Files进入；初次加载、双击定点、捏合、翻页后关闭；放大时移动不触发退出；拖拽取消；删除当前/最后一张草稿；源离屏淡出。
5. 设置与润色：头像从展开到收拢、滚回、切Tab/进二级页返回、搜索和资料Sheet不被浮层盖住；润色模式/风格切换、原文结果对照、键盘展开及恢复、取消/认证失败/晚到结果。
6. 浅/深色、大字体、降低动效/透明度、VoiceOver与键盘Escape。卡死若重现，保持前台进程采样；本次未安装修正版或报告新性能指标。


最终验证：2026-10-19，指定 iPhone 18 Pro / iOS 27.0 / arm64（`1041DD9D-AC70-4DDD-9D34-52514C3E491F`）Debug `build-for-testing`，App/单测/UI测试目标均编译。日志 `/tmp/Familiar-Telegram-motion-final-build.log`；各片后续调整由该收尾构建覆盖。中英各1213键、无重复且集合一致；plutil、JS语法、diff与套件清单静态检查通过。新回归只编译，不执行；所有者真机、真实Provider、图库/选区/头像视觉与修正版性能仍未验收。

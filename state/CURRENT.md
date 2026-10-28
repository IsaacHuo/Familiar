# 当前状态

核对：2026-10-28。当前优先 App Review 1.0 (2) 修复，随后继续Telegram iOS视觉与交互的AI问答App，保留现有Project／Files／工具／Memory／Shell／MCP与BYOK能力。

## 当前切片：审核崩溃与功能说明

- 三份审核崩溃匹配发布 dSYM，定位输入框布局字符串比较；已替换输入框／消息正文的 UIKit 工厂创建路径为显式 TextKit 1 指定初始化，并加布局重入／选区检查。初始化问题证据见 [调查](../logs/2026-10-28-review-composer-crash.md)，修正版 iPadOS 27.2 设备复验仍待所有者。
- 天气署名从持久化成功工具结果投影，回复、工具结果及完整记录显示固定  Weather 与法律链接；不依赖模型引用，不改数据库 schema。HealthKit 保留原审批与三项只读活动范围，权限页补用法。
- 审核回复草稿和真机录屏步骤见 [提交清单](../website/APP-STORE-CONNECT.md)。具体 arm64 Simulator 的 Debug build-for-testing（App／单测／UI 测试）与 Release build 均通过，证据见 PLAN；测试未执行、Simulator 未启动，真机服务、录屏与重提审核独立待办。

## UI 当前切片：R4附件邻接／只读预览／菜单身份

- 聊天与只读预览共用附件呈现值，维持图片后文档的既有顺序、稳定ID、2pt间距、邻接及唯一时间归属；预览复用生产文件气泡但不挂载打开／分享，仍仅三条与1200字符，无Runtime／WebView。
- 图片载入／失败／完成共同读取15/7pt收发邻接边角。分立视口按独立气泡规则适配；0pt同内容统一容器、媒体尾角和相册拼格尚未实现。
- 最后独立文件回执承载终态时间与message.completed；其他工具结尾使用右侧服务时间。内容块序列／Run、准确版本／scope预览和Undo资格不变。
- 菜单动作核对实例、消息／块／原文／资格，内容变化／解绑取消排队动作；选区启动／动作另有代次保护，旧退场完成不能消费新菜单动作。
- B-R4最终App／单测／UI测试目标arm64 build-for-testing通过，exit0，无warning/error；三项附件／菜单生命周期回归只编译未执行。19项原编号和证据见PLAN；320项真机均开放，原气泡截图与hwf修正版设备复验仍待做。

下一片：单张图片与正文统一容器、0pt同内容连接和媒体尾角，再推进输入／键盘／阅读联动。

## 首轮基础

- 已收敛README、产品／架构／UI／隐私／决策／验证入口，移除重复阶段计划和Beautiful UI源码摘录。独有搜索／功能执行证据及hwf调查保留在research，普通历史交给Git。
- 新[账本](../docs/telegram-ios-ui-checklist.md)包含320项，其中240项聊天目标；已完成首轮静态核对：47项修改、163项现有机制、110项必要适配；源码登记区分继承研究和本轮片段，不等于全文或真机通过。
- 共享ChatAppearance已接Classic/Night气泡／正文／时间、16/8pt邻接圆角及尾角，用户与AI共享窄屏减36pt／宽屏85%规则。默认原tgv图案从Bundle读取；公开静态MeshGradient承接四主题颜色，不接Telegram节点动画。
- 连续用户消息按原十分钟／同日邻接只改边角，不改消息或Run身份；原生导航标题显示会话／真实当前模型；首页恢复聊天标题并使用本页原生搜索，根tint统一浅深外观。列表预览复用同一气泡修饰器。
- 原生用户文本补URL检测、TextKit命中与OpenURL动作，链接不触发消息菜单；Markdown行高按系统body度量。日期／时间按13/17与11/17比例，末行CoreText双向run避免混合语言覆盖；回归只编译。
- B-FINAL：2026-10-21，指定arm64 build-for-testing通过，App／两类测试目标均编译，最终日志无warning/error。静态链接／资源／JS／diff检查通过；未启动Simulator或执行测试，全部真机视觉仍待所有者。证据见[PLAN](../PLAN.md)。

## 保留的业务事实

三原生Tab、独立草稿、会话执行与浏览解耦；唯一ForegroundExecution占用Agent／压缩／润色。普通Chat无Project，完整typed work scope隔离文件／环境／Memory／授权。

U6的80项富负载窗口和完整业务读分离、闲置会话保存后收敛、缩略图后台准备保持。轻量索引仍按会话线性覆盖；SQL、内存峰值和手势不因静态代码而视为验收。

选区动作冻结身份，退场后追加草稿且不自动发送；审批／澄清占用不回填。编辑取消／失败不删历史。图库原生缩放分页，已发／Files只读，文档QuickLook准确版本；Provider／授权／当前schema5.0.0和39实体／5-work-scopes本轮未变。

## 已知问题与待验收

- hwf历史三份退出看门狗、前台交互返回采样和CPU资源报告见[调查](../docs/research/2026-10-19-hwf-hang-investigation.md)。布局提案、已读可观察状态、返回补偿和Markdown主题JSON已有修正；未在修正版设备安装／采样，不能说卡死已消失或CPU下降。
- 首页搜索已由独立Sheet改为本页原生搜索；输入／菜单／图库／设置头部等已有实现须按账本逐项对照，不将此前编译当作本次视觉通过。
- Native/WK实际选区菜单、图库手势／回归源、头像折叠、键盘／返回取消、真实Provider和系统权限待所有者。
- 历史S1的20条DeepSeek+Tavily完整链缺凭据未执行；旧适配器请求或UI通过不覆盖当前版本。

## 验证边界

代理只执行具体arm64 Simulator的build-for-testing与静态检查，不启动Simulator、不运行测试、不截图、不安装设备或修改签名。旧通过证据只属于其原基线；所有者最终真机验收按目标编号回报。

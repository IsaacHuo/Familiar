# 消息布局看门狗与滚动几何反馈

## 症状与现场证据

所有者报告 hwf 真机 Familiar 经常卡住。2026-10-19 首次连接读取时，设备已无 Familiar 进程；没有主动停止、重启或安装 App。随后检测到新进程 PID 41343，附加采样见下文。

从设备 `systemCrashLogs` 复制了三份原始报告到 `/tmp/Familiar-hwf-20261019/`，未删除设备文件：

- `Familiar-2026-10-18-213859.ips`
- `Familiar-2026-10-18-224613.ips`
- `Familiar-2026-10-19-010354.ips`

三份均为 `FRONTBOARD / 0x8BADF00D / SIGKILL`，原因是进程退出时五秒内未响应。两份主线程包含 `FamiliarMessageGroupLayout.placeSubviews` 和默认 `Layout.explicitAlignment` 下的深层 SwiftUI 测量；另一份停在 AttributeGraph 更新。报告证明 UI 主线程在系统终止时仍阻塞于布局/图更新，不证明每次卡死都来自同一个原因。

Xcode 留存的 hwf 控制台另有：

```text
<OnScrollGeometryChange Modifier> tried to update multiple times per frame.
Geometry action is cycling between duplicate values.
```

## 代码问题与修正

`FamiliarMessageGroupLayout` 测量正文时使用无限制高度，放置时却提出已测得的固定高度，令深层 VStack 重新按另一组约束布局。默认显式对齐查询还会再次放置子树。测量与放置统一为相同宽度、未指定高度；全宽气泡包装不导出子树的显式对齐。

阅读锚点原先保存视口坐标，却没有随滚动偏移更新；普通视口移动也可能被误认为上方内容增长。几何回调还会同步改写 ScrollPosition，形成反馈。现在随视口更新锚点，丢弃跨视口的过期采样，合并本轮行变化后异步补偿；消费样本后再滚动，离场或交互立即取消。

首页列表初始化、内容自适应及 inset 变化也会产生滚动回调，不能当作用户下拉保存。初始位置等首份 Diffable 数据与有效尺寸后恢复，首次真实拖动前不发布布局偏移；短/空列表保留搜索高度的最小滚动范围，防止 UIKit 将折叠位置夹回展开位置。

## 前台现场补充

所有者明确仍卡住并保持前台后，重新对同一 PID 41343 附加15秒采样，保存为 `foreground-hang.trace` / `foreground-samples.xml`。15778条 CPU 样本中15774条来自主线程；这15774条均包含 `_UINavigationParallaxTransition._animateOrCreatePropertyAnimatorForTransition`，停留于交互式返回转场中的 `layoutBelowIfNeeded` / SwiftUI 图更新。不是沿用前一次空采样的结论。

其中4715条主线程样本包含 `FamiliarMarkdownStyle.json`，770条包含消息包装布局，54条包含 `updateReadVisibility`，19条包含阅读行补偿。数字是包含指定符号的样本数量，不是调用次数，各分类可重叠，不能把它们相加当作耗时。

设备随后生成 `Familiar.cpu_resource-2026-10-19-203602.ips`：PID一致，20:34:12–20:36:00，约108秒消耗90秒CPU、系统报告平均83%，`Action taken: none`。它是CPU资源报告，不是新增退出看门狗，也不说明系统杀死了进程。开启等待线程记录的后续10秒采样也已保留为 `foreground-waiting-name.trace` / `waiting-samples.xml`。

现场证明旧设备版本持续忙于导航转场内的UI图/布局更新；单凭采样仍不能确定哪一个状态写入是唯一触发源。对与该路径直接相关的代码作以下修正：

- 可见消息集合和最新可见回复仅供已读判断，原先用 SwiftUI State 在几何回调中写入，会使时间线重算；改为非可观察的阅读记录，不参与布局。
- UIKit `viewWillDisappear` 在返回转场开始时暂停该呈现的阅读修正，避免等到 SwiftUI `onDisappear` 才取消；手势取消后的 `viewDidAppear` 恢复同一呈现，旧呈现仍不能停止新呈现。
- 附件/文件预览的 `navigationDestination` 从懒加载消息/回执行移到稳定页面。预览使用拥有稳定身份的可比较入口，避免闭包环境值随每次更新使所有行失效；作用域和URL校验保留。
- Markdown颜色/字体JSON按外观、字号、对比度的有限组合缓存，不在每次WebView更新时重新桥接十四种颜色。这只是减少现场热点工作，不把缓存当作消除循环的证明。

## 验证边界

20:30:41–20:30:52 对设备现有 PID 41343 附加 Time Profiler，限时10秒，没有启动或替换 App。`/tmp/Familiar-hwf-20261019/current-process.trace` 的 Hangs 表为空，CPU样本仅一条后台线程；生命周期标为 Unknown。这个窗口没有捕获到活跃卡死，不能从中断言进程当时在前台、已经恢复，或修正版有效。原始 trace 和导出的 `toc.xml/samples.xml/hangs.xml/lifecycle.xml` 保留在同目录。

定向回归覆盖过期几何、视口移动、同轮合并和离场取消，只编译、不执行。指定 arm64 构建与所有者真机确认分别记录在 PLAN。未启动 Simulator，未安装修正版或对其采样；不能据静态修正宣称所有卡死消失。

后续若修正版仍卡住，保持现有进程并采集 Time Profiler/主线程栈；区分布局反馈、数据库工作和媒体加载。所有 trace 都来自原设备版本，修正版尚未安装或采样；不能报告修复后的CPU或卡死率。

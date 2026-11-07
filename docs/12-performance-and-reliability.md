# 性能与可靠性验收

本文件定义采集方法和目标，不将静态修改或编译结果当作运行证据。代码事实见 state，批次与构建结果见根 PLAN。

## 本地观测

使用系统 OSSignposter，subsystem 为 `com.isaachuo.familiar`，category 为 pointsOfInterest。按系统 signpost 是否启用生成区间，不记录正文、文件路径、凭据或逐 token 日志，不上传数据。

| 区间／事件 | 含义 |
|---|---|
| AppInitialization | 依赖和存储初始化，不代表首帧已显示 |
| OpenConversation、HistoryIndex、HistoryPage | 会话读取与投影；异步读取以其独立区间为准 |
| SendPreparation、ContextCompile | 发送准备和上下文计算，不包含后续模型运行 |
| ModelAttemptToFirstText | 每次模型尝试开始到首个文字事件；无文字或失败时在尝试结束闭合 |
| FirstReceivedModelText | 控制器首次收到文字／推理事件 |
| MarkdownRender、FirstMarkdownRenderCompleted | JavaScript 渲染请求与首次完成回调；不是屏幕实际出帧证明 |
| FileImport、AttachmentCommitPreparation、ShellPreparation | 文件准备、消息附件正式复制／校验和环境准备，与模型等待分开 |

首字展示延迟需要结合 SwiftUI／Core Animation 帧时间读取；不能仅用 JS 完成回调计算用户已经看到文字的时间。

## 场景与待采集基线

| 场景 | 数据／操作 | 基线 | 修改后 |
|---|---|---|---|
| 启动 | 冷／热；Shell 未准备／已准备 | 待设备采集 | 待设备采集 |
| 历史 | 0／100／300／3000 条；打开、翻页、搜索定位 | 待设备采集 | 待设备采集 |
| 首页 | 300／1000 会话、多 Project、运行标记 | 待设备采集 | 待设备采集 |
| 流式 | 1万／5万／10万字符；中文、组合 Emoji | 待设备采集 | 待设备采集 |
| 富文本 | 长代码、表格、公式、Mermaid、来源 | 待设备采集 | 待设备采集 |
| 媒体 | 大图、多图、接近 25MiB 文档 | 待设备采集 | 待设备采集 |
| 生命周期 | 连续20轮聊天／返回／取消返回／预览 | 待设备采集 | 待设备采集 |
| 故障 | 断网、拒绝权限、无效凭据、保存失败 | 待设备采集 | 待设备采集 |

生产历史性能夹具先在独立容器保存真实 Message，再使用生产 index/page 读取；测试容器必须活得比呈现视图久。正常发布构建不开放 UI 测试凭据或模拟服务入口。

附件提交准备在后台校验目的文件大小、SHA-256 和提取文本哈希，再返回绑定 message／scope／附件 ID／路径的不可变回执。主线程复核请求后只提交元数据；准备失败不回滚其他界面在等待期间的未提交改动，已开始的提交事务失败才回滚自身阶段。新增回归覆盖源文件变化后的清理，以及同 UUID 不同 scope 的回执拒绝。

## 所有者采集步骤

1. 保留当前有问题的进程，不先清理数据或重装。记录设备／OS、构建、数据量、操作、是否已预热。
2. 使用 Release 和匹配 UUID 的 dSYM；以 SwiftUI Instruments、Time Profiler、Hangs／Hitches 采集一个明确场景。主线程 CPU 高时分析计算热点；CPU 低时另查 I/O、锁和 IPC 等等待。
3. 内存问题补充 Allocations 和导出的内存图；分别记录 App 与 WebContent 进程。测试输出的 App RSS 不包含 WebKit，总缓存成本不是总内存上限。
4. 同设备、同配置、同数据各做至少5组前后对照，冷／热分开。报告中位数、P95、峰值与波动，模型网络等待和本地展示分开。
5. 新增复杂机制需使主要热点成本降低至少20%，或消除已确认的重复工作；其他关键指标回退超过10%需归因。缺基线时仅记录代码成本变化，不报告百分比。

代理仅编译 App／单测／UI测试目标，不启动 Simulator、不执行用例、不安装设备。编译三分钟无进展停止并记录，编译停滞不作为 App 卡死证据。旧版本 trace 不替代当前版本复验。

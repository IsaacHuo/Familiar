# Familiar 下一阶段执行计划

> 本文描述已确认的未来工作顺序。当前实现状态见 `state/CURRENT.md`；未交付能力不得从本文推断为已实现。

## 1. 阶段目标

下一阶段优先验证普通 iPhone 用户能否让 Familiar 安全、清晰地执行真实动作：

> 使用 DeepSeek 完成文本对话和基础图片识读，查询日历与提醒，按用户授权创建动作，在同一回合检查多张动作卡，并在 App 重启后撤销已执行动作。

Project 仍是长期工作单元，但不再作为唯一验收主线。普通聊天与 Project 都必须共享同一套 Runtime、视觉证据、授权和动作 Surface。

## 2. 执行原则

1. 所有方向保留在路线图中，但按可工作的层次依次交付，不并行铺开孤立菜单。
2. 当前真实 Provider 验收以 DeepSeek 为主，默认主模型为 `deepseek-chat`；其他 Provider 暂不阻塞本阶段。
3. 信息性运行事件使用轻量状态行；只有写动作使用卡片。
4. 模型不能产生自己的授权。首次授权由用户明确产生，有效 grant 范围内可以免重复询问。
5. 图片能力按当前模型路由；本地 fallback 不产生新的网络目的地。
6. 恢复和撤销的数据契约先于后台 API。
7. 每一层完成自动化验证和真机验收后再进入下一层。
8. Skills、Memory、Remote MCP 在端到端接入 Runtime、Policy、删除语义前保持隐藏或 Labs。

## 3. 已有基础

- 8 场景 fake-provider Benchmark、arm64 Simulator 构建和 iOS CI 配置。
- SwiftData V1→V9 migration plan（八个轻量 stage）。
- Project、ProjectInstruction、版本化 Resource、ContextSnapshot 和 Artifact。
- Web Search/Fetch 与 Web capture 落为 Project Resource。
- CapabilitySnapshot、AuthorizationGrant、RunResumeCursor 和 ToolInvocation 数据契约。
- Runtime Event、稳定 Surface identity、工具生命周期卡片和摘要轨迹。

具体当前边界以 `state/ARCHITECTURE.md` 为准。

## 4. 第一层：执行界面、授权、撤销与基础视觉

### 4.1 Surface 信息层级

- 将思考、查阅、Web/Resource 读取、本地识图和整理回答统一为无卡片背景的单行状态。
- Run 完成后将信息性状态折叠为“查看运行过程”。
- 只有 `reversibleWrite`、`destructive` 或其他真实写动作使用动作卡。
- 同一卡片原位呈现提案、等待授权、执行中、成功、失败和已撤销。
- 失败显示原因和重试；重试复用原结构化提案，参数变化时按新动作重新判断授权。

### 4.2 多动作卡片 pager

- 同一 Assistant 回合只有一张动作卡时使用普通全宽布局。
- 两张以上时横向排列；单卡近乎占满容器，露出下一张约 16–24 pt。
- 使用逐卡吸附，页码变化时轻触觉反馈。
- 只让视口边缘被裁切部分渐隐；滚动到头时移除对应方向渐隐。
- Reduce Motion 关闭弹簧感但保留稳定吸附；系统禁用触觉时不触发反馈。
- 每张卡独立执行、失败、重试和撤销；最终回答分别总结成功、失败和可重试项。

### 4.3 授权策略接线

- 设置增加 Agent 授权策略和长期授权管理，不与 iOS 系统权限页面混用。
- 首次授权提供“仅这次 / 本次会话 / 始终允许”，默认“本次会话”。
- grant 绑定 Project、工具、目标、规范化参数边界、期限和确认证据；普通聊天使用独立作用域。
- 将 grant 创建、查询、匹配、消费和撤销接入真实 Agent Loop，移除生产路径固定 `grant: nil`。
- 有效 grant 免重复询问，但每次写入仍显示动作卡并写入审计记录。
- 修改、删除、目标变化、参数越界和高风险动作重新确认。

### 4.4 跨重启撤销

- 持久化 EventKit 系统对象标识、动作提案、撤销状态和有效边界。
- App 重启后仍能从原动作卡发起撤销。
- 撤销成功后卡片进入“已撤销”终态；对象已被外部修改或删除时显示真实失败。
- 不声明日历和提醒跨对象事务；多动作分别撤销。

### 4.5 Apple Vision 基础 fallback

- 图片输入先根据当前模型能力建立处理计划。
- 原生多模态模型沿用当前 Provider 图片编码路径。
- DeepSeek 等纯文本模型使用 Apple Vision 提取 OCR、条码和基础分类。
- 将最终证据文本、处理方法、系统版本和原图引用持久化为 VisualEvidence；坐标级中间结果默认不持久化。
- 证据以不可信只读块进入主模型上下文，不授予工具权限，不伪装成系统或用户指令。
- 结果不足时明确说明基础能力边界，并建议切换到用户已配置的多模态 Provider；不自动上传到另一个 Provider。

### 4.6 第一层验收

- arm64 iOS Simulator 构建通过。
- 单元测试和 8 场景 Agent benchmark 通过。
- `state/CURRENT.md`、`state/ARCHITECTURE.md` 与代码一致。
- 真机由所有者使用 DeepSeek 验收：基础图片识读、日历/提醒写入、会话级免重复确认、重启后撤销和多卡滑动。
- VoiceOver、极端 Dynamic Type、Reduce Motion、Reduce Transparency 和触觉关闭状态可操作。

## 5. 第二层：FastVLM 高级本地视觉

### 5.1 模型包

- 第一版只支持固定版本 `FastVLM-0.5B`，官方预转换下载约 1.23 GB，iOS 18.2+。
- 仅用于当前个人非商业研究实验；设置展示 Apple 模型许可证、归属和用途限制。
- 固定下载 URL、文件大小与 SHA-256，不自动跟随上游版本。

### 5.2 安装与设备准入

- 用户在设置中主动下载，不随 App 默认打包，不在首次图片请求时静默下载。
- 初始准入同时检查芯片、至少约 3.5 GB 可用存储和运行时环境。
- 安装后运行短基准，记录首响应时间、内存失败和热状态；基准失败时禁用高级视觉但保留 Apple Vision。
- 下载支持进度、暂停/恢复、失败重试和删除；校验失败删除损坏文件。
- 删除模型文件和缓存时保留历史视觉证据。

### 5.3 自动路由与降级

- OCR、二维码和文字提取优先走 Apple Vision。
- 描述、比较、图表解释和开放式图片问答自动选择 FastVLM。
- 基础识别不足且 FastVLM 已安装时自动升级，不要求用户逐次选择。
- FastVLM 内存失败、模型损坏、取消或 60 秒超时时退回 Apple Vision，并明确能力受限。
- 中文图片问答质量属于真机实验指标，不能根据 Qwen2 基座预先声明支持程度。

### 5.4 第二层验收

- 下载恢复、哈希校验、空间不足、删除和重新安装路径通过。
- 目标真机基准通过，连续运行无不可接受的内存终止或热降频。
- OCR 任务不错误升级；描述和图表任务能够自动选择 FastVLM。
- 高级路径失败后基础识别和主聊天仍可继续。
- 删除模型后历史视觉证据和回答仍可检查。

## 6. 后续层次

按以下顺序继续，每项仍需真实任务驱动：

1. Web 与 Artifact：读取结果轻量化、Artifact 创建/编辑/撤销和项目呈现。
2. 语音：稳定设备端转写、权限恢复和长输入体验。
3. 系统入口：Share、通知、Deep Link、Spotlight、App Intents、Widget/Control 的真机闭环。
4. instruction-only Skills：导入、预览、安装、项目绑定、tool scope 和卸载。
5. global/project/conversation scoped Memory，自动写入默认关闭。
6. Remote HTTPS Streamable HTTP MCP Client，继续经过 Familiar Policy。
7. 新原生能力与 iOS 26+ 后台承接；iOS 18–25 明确降级，不承诺可靠 cron。

当前进度：Web/Artifact 与语音、系统入口基础已存在；Project Workspace 与 instruction-only Skills v1 已接入真实 Chat Runtime、项目设置、工具范围和 V9 Run 审计快照。Memory 仍只有 V8 基础服务，MCP 仍只有 V8 配置记录；两者必须完成 Runtime、Policy 和删除语义后再标记为完成。

## 7. 暂不进入当前层

- 多 Agent、Subagent、Agent Graph。
- Shell、任意代码执行或本机 MCP Server。
- 自动把私密图片切换发送到另一 Provider。
- Familiar 托管视觉服务或托管额度。
- FastVLM 1.5B/7B、多模型自动下载和未经验证的动态最新版。
- 公开市场分发或商业使用；用途变化时重新审查全部许可证和隐私边界。

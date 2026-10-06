# Familiar 产品收敛与 Agent Harness 长期计划

最后更新：2026-10-06。此清单跨对话持续维护。

## 目标与工作规则

Familiar 是原生、简洁、高完成度的 iPhone Personal AI Agent。Chat 是交互与执行入口；Project 保存长期上下文；单 Agent Runtime 执行任务。

Harness 收敛为 **One Agent + One Loop + Lazy Tools + Progressive Escalation**。

- 能直接回答就直接回答。普通问题允许一次模型调用完成，不强制先规划、调用工具或验证。
- 工具仅在需要外部信息、设备能力或执行动作时调用；复杂任务在同一个 Loop 中自然多轮执行。
- 不增加简单／复杂任务 Router，不让 Swift 代替模型规划任务。
- Swift 严格负责权限、审批、预算、持久化、取消、防重复写入和安全边界。
- 优先级：稳定性 > 产品逻辑 > UI/UX 一致性 > 性能 > 新功能。
- 先修核心阻塞，再完成全 App 视觉统一。停止机械追求 OpenMinis parity。
- 每个切片保持可构建；完成切片后更新本清单及必要的 state 文档。
- 直接在 main 工作，保留无关改动。不自动提交、推送、清空 store 或删除用户数据。
- 默认只做 arm64 iOS Simulator 构建，不启动／运行 Simulator。真机视觉与真实服务由所有者验收。

## 如何跨对话继续

1. 按 AGENTS.md 阅读当前事实，再阅读本清单的“当前切片”和未完成任务。
2. 检查工作树；核对相关源码，不把历史说明当作当前实现。
3. 选择一个可独立构建和验收的切片，明确它的完成条件。
4. 实现、必要的回归测试、静态检查与构建完成后，勾选对应实现任务。
5. 真机／真实服务验收单独勾选。编译成功不能代替测试执行或端到端验收。
6. 在本文件记录简短证据和遗留问题，不复制 git 活动历史，不记录密钥。

`[x]` 表示这一项规定的工作及验证已完成。`[ ]` 表示仍有工作或必要证据缺失。测试只编译时明确标为“未执行”。

## 当前切片

**H1-H5 架构收敛实现与静态/arm64 测试目标编译已完成。** 产品为 Chat / Project / Files。正式迁移链冻结原 37 实体 1.0.0，经 Files 加法桥接与旧生成元数据移除，再归档/移除 Grant，当前为 4.0.0 / 37 实体。Artifact 与 Grant 不在当前 schema；Resource/Attachment 保留必要历史关系与存储字段，新导入不再写 Resource 元数据。

Project/Chat 共用 Files；file_list/file_search/file_read/file_write/file_edit/file_publish 使用同一工具组。正式上传、资料/网页保存、生成文件、Shell Outputs 和旧工作区输出进入 Files；旧目录和旧回执仅作迁移/历史读取。删除 Chat 保留文件，移动 Chat 复制到目标 Project 并清除旧上下文摘要，Conversation Memory 同时检查 Project。Shell 成功输出先捕获不可变字节，再在 Run 保存边界登记并返回真实文件快照；失败补偿和 Undo 处理相应字节/版本。

H3 统一 Compiler 请求/压缩、冻结输入、逐请求清单、字符预算与事实型 Run State。H4 统一 Policy、授权查询/保存、审批和执行前复核，以及声明/输出契约、非交互读取并发与 commit timeout。H5 清理旧生产路径、归档历史 Grant、隔离纯领域契约与 SwiftData 服务，并同步文档。

**验收尚未完成。** 磁盘迁移执行、覆盖安装、iOS suites、真实服务与真机均未执行/验收。H7/H8 与既有 G9/F 验收独立保留，不能据编译宣称用户数据升级或端到端运行通过。

## 审查基线

以下结论来自指定状态文档和核心链路源码核对，不来自 README 的能力声明。

| 链路 | 当前真实实现 | 尚缺证据／主要问题 |
| --- | --- | --- |
| Chat | 草稿、附件、流式回复、取消、历史、重试及有序工具块已接线 | 所有 Project 强制规划，Daily Chat 也受影响；真实 Provider 连续调用未验收 |
| Project + 文件 | 固定默认 Project、指令、资源版本、冻结上下文及文件导入已接线 | 全量资源注入可能超过预算；网页抓取自动进入长期资源 |
| Agent Runtime | 一个 Loop、typed events、deadline、预算、读重试、审批、写防重 | Run-local Plan/Evidence/Delivery/Repair 编排过重；状态文档落后于代码 |
| Tools | 原生、Web、文件、Artifact 等工具已注册，具有能力及授权检查 | 每轮暴露大量 Schema；Capability 与 Skill 有不同的 core 例外表 |
| Memory | 三作用域、冻结读取、上下文预算、确认写入与设置管理已接线 | 成功回执先于 Controller 落盘；实际选中与 lastUsedAt 的语义需核对 |
| Skills | JSON 指令技能、Project binding、按需加载、包导入源码已存在 | 不能再描述成纯 instruction-only 无资源包；包导入和 Shell 尚缺真实验收 |
| MCP | HTTP 初始化、发现、分页、远程调用、逐次高风险审批已接线 | 每次聊天提前发现所有启用服务；完整 Schema、STDIO、OAuth 未实现 |
| Artifact | 文本写入、回读、真实文件校验发布、版本浏览与分享已接线 | 发布被强制 Plan 绑定；原位 edit 会覆盖版本；复杂格式依赖未验收 guest |
| Environment / Shell | iSH、rootfs、Workspace mount、资源／网络限制、依赖准备已接线 | App 启动即准备 guest；真机冷启动、取消和复杂文档未验收 |
| Settings / UI | Theme、字体、间距、圆角、玻璃回退已有基础 | 高级能力大量平级入口；语音管理重复；Markdown CSS 独立配色；fixture 仍展示非生产 ToolChips |

**目前不能将任何依赖真实 Provider、MCP、系统权限或 iSH 的完整任务标为真实端到端通过。** 历史确定性测试记录不等于当前导入后的整套测试已执行。

### 已完成的审查工作

- [x] A1 阅读 AGENTS.md、CURRENT、ARCHITECTURE、OpenMinis 对照表，并沿核心链路定向核对源码。
- [x] A2 核对工作树和当前工程依赖：开始时 main 工作树干净；Yams / ZIPFoundation 已是本地 package references。
- [x] A3 原工程 arm64 generic iOS Simulator build-for-testing 成功。没有借临时工程副本替代原工程。
- [x] A4 记录首批根因与产品决策，形成长期计划。
- [x] A5 修正 state 中过时的单 DeepSeek、Memory/MCP 未实现、技能资源包、工具数量和下一阶段描述。
- [x] A6 将旧阶段执行文档明确标为历史范围，避免与本计划并行指挥开发。

基线构建证据：`/tmp/familiar-product-audit-20260930-build-confirmation.log`，结果 `TEST BUILD SUCCEEDED`。App、扩展及测试目标编译完成；测试未执行，Simulator 未启动，真实服务／设备未验收。首次构建有语音和 OAuth 并发相关 warning，需单独排查。

## B. Harness 收敛

### B1 解除强制规划与固定流程

- [x] B1.1 删除 Project / Daily Chat 必须先 task_plan 的 gate、规划重试和正文扣留。
- [x] B1.2 删除固定 Plan/Execute/Validate/Repair/Deliver 阶段及按工具名猜阶段的逻辑。展示实际状态：请求、响应、调用、等待确认／回答、压缩和终态。
- [x] B1.3 task_plan 只作为可选展示工具；移除必须按序完成、必须工具证据、不能修改计划及自动修复两次的调度约束。
- [x] B1.4 artifact_publish 独立于计划，保留格式／签名／可解析内容／hash 和用户请求的内容校验。删除 deliverableID 与 expectedDeliverables 编排合同。
- [x] B1.5 删除 executionStateChanged 及重复 Plan 快照持久化。只保留真实工具调用／结果、审批、回复、上下文和必要防重状态。
- [x] B1.6 更新内置文档 Skill 与回归测试，不再教模型强制走固定阶段。
- [x] B1.7 静态检查与 arm64 build-for-testing 通过，更新 state；真机普通聊天仍待验收。

### B2 Lazy Tools

确定采用**模型显式加载工具组**，不引入任务分类 Router。

- [x] B2.1 建立一个明确的工具组目录，复用 Registry 和现有 manifest；避免同时维护多份工具分类／core 例外表。
- [x] B2.2 首轮仅暴露 `current_date_time`、`ask_user`、`tools_load`，并提供简短的允许工具组元信息。
- [x] B2.3 `tools_load` 选择当前需要的组；后续请求替换扩展工具集合，而不是永久累积所有 Schema。加载不会执行设备动作、授予权限或扩大 Project/Skill scope。
- [x] B2.4 组包括 Web、Calendar/Reminders、Places/Weather、Files、Artifact、Memory、Skills、Shell/Environment 和配置过的 MCP。展示类工具留高级范围。
- [x] B2.5 默认聊天可按需加载 Web、日历提醒、地图天气、文件、文本 Artifact 和已启用 Memory；非核心能力需要高级显式启用。保留已有 Project 配置，不删除历史数据。
- [x] B2.6 一次最多激活两个扩展组，基础工具始终可见；工具不可用或超出 scope 返回具体失败，不静默启用别的能力。
- [x] B2.7 MCP 首次按需访问时才发现；按服务保存本 Run 快照。大目录先返回工具元信息，再精确选择本次工具，避免整批远端 Schema 注入。
- [x] B2.8 iSH 按首次实际需要准备，合并同时准备请求，取消／失败有真实状态；普通聊天不启动 guest。
- [x] B2.9 用当前轮真实加载的参数 Schema 计算字符预算，修复只计 name/description 的漏算；输入上下文和有效 scope 仍冻结。
- [x] B2.10 动态加载后再次执行能力、Project、Skill、授权检查。未在本轮暴露的工具不能因模型猜中名字而执行。
- [x] B2.11 tool loading、权限等待、MCP 发现均受同一个 Run deadline 和取消约束，不另开执行内核。
- [x] B2.12 回归测试覆盖首次直接回答、组替换、拒绝越界、Skill 收窄、MCP 失败、预算与唯一终态；构建后更新 state。

### B3 Progressive Escalation 与状态清理

- [x] B3.1 系统策略围绕最低必要复杂度、直接回答、按需工具、真实回执与失败诚实表达，不预设任务的阶段。
- [x] B3.2 保留首字节前有界 Provider 重试、独立 read 最多并行两路、write 不自动重放、预算耗尽收尾。
- [x] B3.3 清理无生产调用的 CapabilityResolver/Catalog/Grant 路径，保留唯一实际授权路径。持久数据结构的删除必须先确认引用和数据影响。
- [x] B3.4 不新增跨重启续跑、后台执行或 Plan 调度器。启动恢复继续把未完成 Run 明确终结，并保留已取得结果。
- [x] B3.5 不增加任务 Router。现有 Provider group fallback 仅负责用户所选模型服务；本地模型的未接通路径退出生产调用图。

## C. 核心数据与输出可靠性

- [x] C1 Memory 必须落盘成功后才发成功 ToolResult；落盘失败回结构化失败，不能让 UI／模型看到“已记住”。
- [x] C2 将必要的 Artifact、Skill、Environment 结果提交纳入成功边界；核对 commit 后保存失败时的回滚与 Undo，避免重试重放已发生的外部写入。
- [x] C3 发送前检查 Project 受保护上下文预算；拒绝发送时保留草稿和附件，不先提交消息再失败。
- [x] C4 网页抓取默认只保留聊天和 Run 证据；用户明确“保存到项目”后才成为长期 Resource，不再次抓取，保留 URL／时间／hash／截断来源。
- [x] C5 默认交付 Markdown/纯文本。DOCX/PDF/XLSX 等复杂生成和 Shell 需高级显式启用，真实 guest 验收前不作为默认完整能力。
- [x] C6 Artifact 修订生成独立版本，删除原位覆盖历史的 edit 路径；预览、分享、删除与 Undo 对齐真实文件和元数据。
- [x] C7 Memory 使用时间只标记最终进入冻结上下文的条目；诚实说明关键词检索与 frozen selection 的边界。
- [x] C8 顶栏模型、Project override、Provider group 实际执行模型与用量展示一致。
- [x] C9 覆盖保存失败、取消、拒绝、权限缺失、附件清理和跨重启历史回放；当前测试与真机分别记录。

## D. 全 App 信息架构与视觉统一

本阶段是用户优先指定的 UI 交付；在核心阻塞修复后开展，按页面族逐批完成。

### D1 信息架构

- [x] D1.1 Chat 保留历史／Project 切换、有效模型、输入器、新对话和会话操作；移走 Diagnostics 等执行层快捷入口。
- [x] D1.2 Project 主页面保留指令、资料、输出和聊天；Environment、Skills、MCP、Capability、Run 审计进入 Project 的高级页。
- [x] D1.3 Settings 主层按模型与回复、外观、隐私与数据、支持组织；执行限制、工具目录、环境、软件源、MCP、技能和诊断集中高级页。
- [x] D1.4 语音配置只有一个管理入口；模型分组退出普通设置首屏。Memory 管理与授权撤销保持可发现。
- [x] D1.5 使用用户可理解的标题和错误文案；技术名、参数、hash 放入展开详情／审计，不作为普通界面的主信息。

### D2 设计系统

- [x] D2.1 复用 FamiliarTheme/Typography/Spacing/Radius/Motion，统一规则，不创建另一套主题。
- [x] D2.2 标题、正文、辅助信息、元数据、按钮使用语义字体；Dynamic Type 同时影响文本和布局测量。
- [x] D2.3 内容间距采用现有 4/8/12/16/20/24；圆角采用现有 10/14/18/24；系统组件由系统管理，图标触摸区至少 44pt。
- [x] D2.4 主／次／破坏按钮明确一致；自定义图标按钮共享按压与可访问性规则；不再逐页面发明阴影、描边和动画。
- [x] D2.5 表单与列表优先原生 Form/List/LabeledContent/Menu/NavigationStack；sheet 由有身份的展示状态持有，明确关闭／保存动作。
- [x] D2.6 Liquid Glass 用于导航与浮动控件，正文／工具结果用清晰内容层；保留 iOS 18 和降低透明度回退。
- [x] D2.7 Markdown CSS 的颜色、代码、引用、来源和正文尺度与 SwiftUI 语义一致，清理旧的独立配色。

### D3 组件与页面验收

- [x] D3.1 Chat 顶栏、抽屉、空态、Composer、附件、相机、输入预览统一。
- [x] D3.2 Message、Thinking、Tool Result、Sources、Failure、Approval、Undo、Artifact/Share 回执统一；工具结果默认紧凑展开，审批默认仅这次。
- [x] D3.3 Project 列表、编辑、资源详情、输出版本、预览分享统一。
- [x] D3.4 Settings 所有主页面及高级子页统一，包括模型／语音／Memory／权限／存储／锁定／审计／About。
- [x] D3.5 HTML、Markdown、Code、Diff、Records、Mermaid 全屏详情遵循相同导航和关闭规则。
- [x] D3.6 删除只在 fixture 出现的旧 ToolChips 展示树；fixtures 复用生产组件，不为测试维持另一套 UI。
- [x] D3.7 更新中英文文案、错误与本地化 parity。构建通过后单独列出待真机检查的页面，不声称视觉验收完成。

## E. 性能与维护面

- [x] E1 流式 delta 只影响当前回复，避免反复构建全量 timeline、历史 projection 和无关设置。
- [ ] E2 评估长会话的 eager VStack／WKWebView 数量和排序成本；按实际测量选择懒布局，不盲目添加缓存。
- [ ] E3 保留 Markdown 现有流式合并／节流；核对大表格、代码和图表的渲染、布局与内存。
- [x] E4 核对文件解析、图片缩放、Skill archive、hash 与磁盘 I/O 的 MainActor 开销；仅在证据支持时移动工作。
- [x] E5 排查现有语音未使用变量与 OAuth 并发 warning；不把源码疑点写成已经发生的性能故障。
- [x] E6 清理确认无生产引用的类型、入口和本地化；保留研究／Mac 目录，禁止为了 iOS 收敛扩展 macOS 产品。

E2/E3 当前进度与剩余门槛：

- [x] 源码核对：历史仍是 eager VStack；timeline 合并排序与每条历史的 Surface projection 不再因正文 token 重做。Run 关联改为每次历史输入更新时一次索引，保持首个匹配语义，无跨更新缓存。
- [ ] E2 对 100／300 条历史的 WKWebView 数量、主线程更新、滚动和内存进行设备采样，再决定是否改为懒布局；没有测量时不宣称需要或已经完成布局优化。
- [x] E3 保留 80ms 流式合并／终态立即渲染；修复 Mermaid 旧异步结果装饰新正文的竞态，旧版本停止继续调度图表。
- [ ] E3 大表格、长代码、多图表、Dynamic Type／外观变化下的 WebKit 真实布局、渲染与内存验收；Node 调度回归不代替这一项。

## F. 验证与完成门槛

### 实现侧

- [x] F1 当前测试清单反查所有 suite；补齐 ImportContracts、GroupBoundary、ExecutionContract 等遗漏。真机 guest suite 单列，Simulator skip 不能算 guest 通过。
- [x] F2 新增决定行为的回归用例，避免只镜像实现的字符串断言。
- [x] F3 每个切片完成 git diff --check、相关 plist／strings 检查和单次 arm64 Simulator build-for-testing。
- [x] F4 编译、测试执行、真实服务、真机视觉、签名发布证据分列；禁止“全量通过”包含未运行或跳过项。
- [x] F5 CURRENT 描述实际实现、问题与下一阶段；ARCHITECTURE 描述真实模块边界；OpenMinis 对照表仅作历史迁入记录。

### 所有者真实验收（分别勾选）

具体步骤、通过条件和采样记录集中在 [统一真机验收清单](docs/15-owner-device-acceptance.md)，页面细表继续引用 D 清单。

- [ ] F6 普通聊天：问候／解释一次请求、流式、取消、错误恢复、退出重开。
- [ ] F7 Project：文件导入、引用、模型覆盖、上下文超限保留草稿、历史回放。
- [ ] F8 Web：搜索、抓取、来源、失败／无结果、明确保存到项目。
- [ ] F9 Calendar/Reminders：查询、批准写入、拒绝零写入、跨重启 Undo。
- [ ] F10 地图／天气：真实坐标、签名与服务失败、来源；未验证时不能伪称 WeatherKit 成功。
- [ ] F11 Memory：确认落盘、失败回执、跨聊天作用域、编辑删除和开关。
- [ ] F12 文本 Artifact：写入、版本、回读、Quick Look、系统分享、删除与 Undo。
- [ ] F13 高级能力：HTTP MCP 与 iSH 冷启动／缓存、取消、权限／网络／资源限制及复杂文件交付。
- [ ] F14 UI：中英、深浅色、大字体、VoiceOver、减少动态效果、降低透明度、小屏与键盘遮挡。

## 暂不安排的新功能

跨重启自动续跑、可靠后台执行、STDIO MCP、MCP OAuth、技能商店、任意代码执行、多 Agent、云同步、备份服务、更多供应商 OAuth、Core AI Runtime 和 macOS 扩展不进入本收敛周期。只有核心验收暴露的缺陷可以提升优先级。

## 阶段证据与遗留问题

### B1：解除强制规划

- 实现：删除固定阶段、强制计划／证据／交付修复、deliverableID/expectedDeliverables 和重复 execution snapshots；保留实际审批、文件验证、预算、取消与写入防重。task_plan 只负责展示。
- 验证：git diff --check 通过；独立 DerivedData 原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED。日志 `/tmp/familiar-harness-b1-20261001-build.log`。
- 测试：新 Harness 回归和既有测试目标已编译；未执行测试、未启动 Simulator、未使用真实服务或设备。
- 此切片收尾时 Lazy Tools 仍未接线；随后 B2 已完成它。Memory 成功边界已在 C1 修复。语音／OAuth 原有 warning 仍留 E5。
- 后续状态：B2 已从 Registry/ContextSnapshot/Loop 的单一生产链路完成工具组懒加载，未增加 Router。

### C1：Memory 成功边界

- 实现：Memory 保存移入 Run 的 persistResult 成功边界；Controller 保存失败回滚并抛回 Loop，成功事件与模型结果在实际保存之后产生。取消／拒绝不会走保存。工具审计与 model-facing 结构化失败复用同一错误内容。
- 验证：新增保存失败无成功回执、数据可见先于成功事件两个回归用例；全部测试目标编译。最终增量 build-for-testing 返回 TEST BUILD SUCCEEDED，日志 `/tmp/familiar-harness-c1-final-20261001-build.log`。
- 静态：git diff --check、中英文 strings plist 检查通过；未修改本地化键集合。
- 边界：测试未执行、无真实 Provider／真机结论；Environment 等其他提交的保存边界已在 C2 修复，真实可靠性仍待验收。所有真实验收项保持未勾选。

### B2：Lazy Tools

- 实现：统一工具组、默认能力和 base 规则，删除重复分类／core 例外表。首轮只有 current_date_time/ask_user/tools_load；允许目录与实际暴露集合分开冻结。最多两组按需替换，未在本轮出现的名字（包括与 loader 同批猜出的名字）不能执行。
- 范围：默认 Web、日历提醒、地点天气／必要位置、文件读取分享、文本 Artifact 和已启用 Memory；Skill 读取只看到冻结候选与本 Run 确认安装的数据。复杂生成、Shell、其他 native 和展示工具需显式配置；既有显式选择仍有效。首个 capability 修改按当前默认值保存其余工具，避免意外开启高级能力。
- MCP：只在请求服务组时发现，每 Run 缓存；32 条描述分页、最多 16 个精确选中的 remote schemas。审批保留高风险／仅这次，并明确显示服务器、实际操作及参数；不会把远端只读声明当作授权。
- 安全／预算：加载不授权；Group/Project/Skill 范围和实际 capability 检查仍在 Swift。参数 Schema、load report、所有调用尝试计入相应预算；写入指纹在实际执行前检查，防同批重复。成功加载的 manifest snapshot 在成功事件前保存。
- iSH：启动只检查 bundled assets；真实操作共享一个准备任务。取消单个 Run 的等待不会启动它的命令，也不拆掉共享安装／启动；后台私有准备可能继续完成。真实 guest 的系统边界仍待设备验收。
- 验证：最终原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-harness-b2-verified-20261001-build.log`。App／扩展／所有测试目标编译完成，14 项 LazyTool 用例已编译；测试未执行、Simulator 未启动、未调用真实服务或 guest。
- 静态：git diff --check、release-test script 语法、两份 strings plist 与 973/973 key parity 通过。目录实际 55 无条件 + 2 bundled-asset 条件定义，最多 57；这不等于模型收到 57 个 Schema。
- 后续状态：C2 的提交边界、C3 草稿安全与 B3 的无生产调用路径清理已由下方切片完成实现／编译；D 的全 App UI 统一未完成。真实模型的组选择效果、延迟、MCP 服务和 guest 取消仍未验收。

### C2 / C6：提交成功边界与独立 Artifact 修订

- 提交：willCommit 在任何动作调用前保存 committing invocation；本 Run 同时保留“已尝试写入”的精确参数指纹，提交或保存失败后不盲目重复。中断恢复保留 committing 作为不确定结果，不再假定它已取消。
- 保存：Environment receipt、原生 durable Undo、Artifact、Skill 和 Memory 的必要保存处于成功事件之前。Skill 的文档、package hash 与 Project binding 合为一次保存；内容地址资源可以作为不可见缓存保留，不会因此成为已安装 Skill。
- 本地补偿：CommittedAction 的 rollback 只恢复本地数据，finalize 只在保存成功后清理旧目录。Environment 保留旧目录直到 receipt 保存成功；保存失败恢复旧目录。外部／原生动作不会在后台被自动撤销。
- Artifact：编辑保存新 ID／独立目录／同 lineage 的下一版本，原始文件保持不变；发布／写入保存失败只删除本次新文件。前驱必须存在且属于同一 Project；获取版本失败不能静默从 v1 重来。删除／Undo 先暂存目录，数据库失败恢复它，成功后清理。该根因修复同时完成 C6 的实现部分。
- Undo：成功的原生撤销结果缓存到元数据保存完成，保存重试不再重复操作。持久 Undo 在调用前标为 unavailable，进程中断后不自动重放；当前会话保存失败仍可凭缓存补齐记录。失败的提交保留实际可用的会话 Undo；多次点击受执行中检查保护。
- 历史：包含已提交或不确定操作的消息编辑／重新生成／失败 Run 重试被拦截，保留原记录，要求先检查结果并发送新的后续消息。纯读取仍可重新生成。
- 验证：原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-commit-c2-verified-20261001-build.log`。12 项 CommitBoundary 新用例及既有目标仅编译，未执行测试、未启动 Simulator、未进行真实系统／guest 验收。
- 仍有边界：系统动作成功后立即杀进程，可能只有提交 journal 而没有完整结果／Undo；它阻止盲目重放，不能证明动作的最终状态。中断的 Environment 本地 swap 可能保留备份；自动跨重启补偿／续跑不在本切片。真机磁盘不足、强杀窗口、权限变化和 Undo 视觉仍需所有者验证。
- 后续状态：C3 已完成下方发送前检查切片，拒绝发送保留草稿；C4 也已完成下方显式保存切片。

### C3 / C7：发送前预算与草稿安全

- 发送：先按 Project override 解析模型并检查凭据／文档能力，冻结历史、Project／Skill scope、原生目录与 MCP discovery closures。只读准备上下文，不创建 Conversation、Message 或正式附件文件。
- 预算：检查受保护 Project、系统提示、基础 Schema 与最新用户消息／附件的合计；旧历史仍可由已有 Loop 压缩。文本模型使用 Apple Vision 后再次检查证据，不把不可容纳的图片结果先提交给历史。
- 文件：发送前预定消息 ID 和最终附件路径，图片从草稿路径读；通过后复制并保存，Run 复用同一个已验证 Snapshot。缺失图片不再静默降级为空内容。
- 草稿：检查取消和准备期间的草稿变化；正式提交失败回滚 SwiftData 并清理本次复制文件。文本、原附件、原图片和 Skill 只在提交保存成功后消耗。后续网络／Provider 失败仍属于已接受消息的 Run 失败，不等同于本地拒绝提交。
- Memory：移除无生产调用、会提前保存 usage 的旧 search 入口；候选为只读关键词匹配。Compiler 的 1200 字符预算决定最终 ID，lastUsedAt 与已接受消息同一次保存；超预算候选、被拒绝的准备和回滚不会提前更新使用时间。memory_search 仍只搜索本 Run 的冻结选择，并非语义检索全库。
- 验证：原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-send-c3-verified-20261001-build.log`。9 项 SendPreflight 用例与改后的 Memory scope/usage 用例已编译，未执行测试、未启动 Simulator。覆盖合计预算、历史压缩保留、Schema、Vision 证据、暂存图片读取、最终文件路径、缺失图片以及实际 Memory usage/rollback。
- 静态：git diff --check、release script 语法、两份 strings plist 和 980/980 key parity 通过。拒绝提交保留草稿的 Controller 路径有源码／编译证据，未取得签名真机运行证据；磁盘不足、取消、图片识别及真实模型仍待验收。
- 后续状态：C4 已完成下方显式保存切片；网页默认只进入聊天／Run 证据。

### C4：网页证据与显式长期保存

- 默认：Controller 不再自动导入网页。抓取时间和正文 hash 进入 FamiliarWebFetchOutput，随原有 envelope 持久化，删除重复的 webCaptures Result/Event 通道。
- 交互：展开成功的网页工具结果后可点击“保存到项目”，复用现有按钮、字体和间距。截断页提示仅保存已读取的部分；完成后显示实际目标项目，失败在动作旁显示原因。
- 保存：从真实 Run/Call 的成功 Result 解析原始捕获并确定所属 Project，验证 hash 后离线导入，不重新抓取。资源正文及原文件携带 URL、时间、Source ID、正文 hash 和截断标记；整个资源文件另有实际内容 hash。
- 去重：同一捕获重复保存或重开历史后保存，检查现存文件完整性并复用 Resource，不增加长期上下文。损坏／缺失文件、错误工具、失败／取消结果、缺失归属或损坏捕获不产生成功回执。保存只影响下次上下文，不更改当前冻结 Run。
- 范围：保留旧 Resource；旧 Result 缺少完整捕获元数据时不提供该保存动作，不推算时间、不重抓网页。Project 新增网页与 Share 导入仍是原有用户明确导入流程。本切片未增加模型可调用工具、持久实体或执行路径。
- 验证：原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-web-c4-verified-20261003-build.log`。8 项 WebRetention 测试声明（含失败／取消参数用例）及既有目标已编译，未执行测试、未启动 Simulator、未调用真实网页。覆盖只存证据、离线保存、来源完整性、重开去重、错误结果／归属／hash、文件失败与已保存文件损坏。
- 静态：git diff --check、release script 语法、两份 strings plist 与 984/984 key parity 通过。保存动作的真机可发现性、VoiceOver 和真实网页仍待 F8/F14；旧自动导入资料不做猜测清理。
- 后续状态：B3 已完成下方清理切片，保留唯一真实权限、审批和预算路径。

### B3：单一权限与 Provider 入口

- 调用审查：Catalog/Resolver/Binding 仅有契约测试；Grant 签发／消费无生产调用。删除这些死路径和对应虚构行为测试；CanonicalJSON 提供参数 hash，实际 Project 能力收窄仍走 ProjectService，授权只走 AuthorizationRuntime/RuleRecord。
- 数据边界：历史 GrantRecord 的 12 个已存储列、schema 的 37 个实体和 Project 删除清理保持原样；移除 Grant 值类型、state 解释与签发／消费 API。它仅是历史数据，不提供授权。不为这次清理引入迁移、重置或数据回填；后续移除持久列需单独验证存储影响。
- 根因修复：实际授权不再忽略数据库读取／保存失败；签发与消费失败回滚并抛回 Loop，阻止对应敏感读取／外部动作。未知 duration 不再被当成 once 放行。精确参数、目标、能力版本、Project、session、expiry 与 revoked 条件保持。
- Provider：直接把用户所选 Factory 结果交给同一个 Loop。删除未接通的本地／云 Router、升级 Coordinator、Controller observer/state、弹窗及旧 route-policy 设置。用户配置的模型组仍只在其成员之间按首字节前规则回退，未引入任务分类或流程调度。
- 已保留：Context Compiler 的最低复杂度策略；首字节前有界 Provider 重试、独立读取最多两路／失败读取一次重试、写入不重放、预算耗尽收尾。启动恢复继续终结未完成 Run，保留 Result 与 committing 不确定记录。
- 验证：原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-harness-b3-verified-20261003-build.log`。6 组 AuthorizationBoundary 声明及参数变体已编译，覆盖精确授权、过期／撤销／损坏规则、once 消费、历史 provenance 无权、授权服务失败阻止读／写、恢复保留证据和未知提交。既有重试／并发／预算／提交／模型组边界目标同样编译，测试未执行，Simulator 未启动。
- 静态：git diff --check、脚本语法、strings plist、982/982 parity 通过；已比较历史 Grant 存储列不变。release script 补入授权与现有 ImportContracts/GroupBoundary suites，F1 全清单已在后续切片核对。真实签名存储失败、系统权限、Provider 回退和取消仍待所有者验收。
- 后续状态：C5/C8 已完成下方交付范围和模型一致性切片；真实 Provider/guest 与真机验收仍未完成。

### C5 / C8：默认文本与有效模型一致性

- 交付范围：核对真实默认 scope，仅开放文本 Artifact write/edit/read，workspace_write、artifact_publish 与 Shell/Environment prepare 需显式启用。Context Compiler 提示普通回复不创建文件，需要文件时默认 Markdown/纯文本；复杂格式在文本工具边界、审批／磁盘写入前拒绝。高级工具有代码不等于 guest 已验收，F13 保持未完成。
- 模型选择：发送与顶栏复用 effectiveSettings，显示 Project override 后的下一次请求模型。Project 覆盖下选模型修改该 Project，菜单可恢复默认；打开旧历史不再把上次请求元数据当成当前默认。修改默认设置不改变 Project 生效模型时，不插入错误的 ModelSwitch。
- 实际来源：普通适配器也发模型选择事件，模型组消除成员重复事件。Run snapshot 保存用户请求的组／模型，有序 trace 保存真正选择过的成员尝试；回复使用最后实际成员 ID，重新生成从原 Snapshot 取请求选择，避免意外退出模型组。
- 用量：Recorder 保存有序选择与仅已报告的 nullable 字段；损坏 trace 不静默重置。已核对协议适配器每次请求仅发一次最终用量，保留 cache-only 报告。自动历史压缩转发选择与用量到同一 Run；手动压缩／供应商配置请求不属于此统计，页面明确说明。跨 Run 部分缺失标为部分用量；失败尝试不被说成成功，不估算费用，也不把缺失填为零。
- 验证：原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-model-c5-c8-final-20261003-build.log`。8 组 ModelSelection 声明（含复杂格式参数用例）与既有目标编译，覆盖 Project 选择／恢复默认、历史重开、请求与成员区分、未知用量、重复成员事件、自动压缩统计、默认 scope、格式拒绝与真实 Markdown 字节。测试未执行、Simulator 未启动、真实 Provider/group/guest 与 UI 未验收。
- 静态：git diff --check、release script 语法、strings plist 与 984/984 parity 通过。没有新增工具、持久实体、模型路由或视觉体系。
- 后续状态：C9 已修复模型组无凭据预检查和取消／附件清理，F1 已核对清单。之后推进 D1 高级入口收缩和设计系统统一。手动压缩独立用量追踪、逐成员费用分摊不在本次范围。

### C9 / F1：提交与取消安全、完整测试入口

- 凭据：ProviderFactory 统一普通 key、OAuth token 与组成员可用性；组上保存的 key 不能替代成员凭据。配置显示、发送／手动压缩预检查及实际成员构造一致，正式提交前再次检查。无成员凭据时不消耗文本、附件、图片或 Skill，不创建聊天消息。
- 生命周期：Chat 重现时，活跃发送／压缩不会被恢复成中断失败，也不会扫描删除其准备文件。文档解析与交付后的取消都清理本次导入草稿，借用源文件不动。附件提交拒绝既有目标，复制碰撞失败不删已有正式字节。
- 回归：新增 5 组 SubmissionBoundary 用例；保存失败／拒绝／权限／写入提交／冻结上下文／恢复保留 Result 与未知提交由现有 SendPreflight、CommitBoundary、Runtime、AuthorizationBoundary 等用例共同覆盖。当前仅编译，不把故障注入或源码审查当成磁盘不足／系统强杀的真机证明。
- 清单：核对全部当前 Suite 与 XCTest：39 个 Simulator suite、2 个签名设备 suite、完整 UI target，无遗漏／重复／失效名称；已删除的 ExecutionContract 不再列入。`--check-list` 可重复核对，不执行测试。
- 证据门槛：脚本执行后读取实际 xcresult summary 的 total/passed/failed/skipped/expectedFailures；零测试、跳过、预期失败、缺失统计均拒绝通过。默认 Simulator 与 `--device` 签名设备套件分开选取，要求对应的预构建 host。
- 签名边界：图片 benchmark 从普通参数集移到 FamiliarSignedSubmissionTests。签名条件不满足直接失败，不再返回 assertions 未运行但 failures 为空的“unverified”绿项；仅检查排队图片准备的取消／草稿安全，不声称 OCR 或模型请求执行。真实 guest 仍在 FamiliarDeviceRuntimeTests；F13 保持未完成。
- 验证：原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-submit-c9-f1-final-20261003-build.log`。新增边界／签名用例与既有目标已编译。git diff --check、脚本语法、完整清单通过；按本机 Xcode 输出 schema 核对报告字段，并用合成报告验证全通过接受、零测试／跳过／预期失败／缺失统计拒绝。合成报告检查不是测试执行。
- 仍待验收：测试未执行，Simulator／设备／真实 Provider／guest 未启动。签名存储损坏、磁盘不足、权限变化、取消时机、强杀后的外部动作确认及真实 OCR 留所有者验收；编译不能勾选 F6–F14。
- 后续状态：D1.1–D1.4 已完成下方入口收拢；继续沿现有组件整理，不新增视觉体系或功能数量。

### D1.1–D1.4：主入口与高级配置分层

- Chat：保留历史、Project／有效模型选择、输入器、新对话与会话操作，删除 Diagnostics 快捷项及其回调，诊断只由设置高级页进入。
- Project：主页提供可见的新聊天主动作、指令、聊天、资料和输出，以及一个高级入口；新聊天不再重复放在更多菜单，归档项目先解除归档。Environment、Skills、MCP、Capability 和运行审计进入同一导航 Stack 的高级 List，原 Project ID／查询／操作保持。
- Settings：主层为模型与回复、外观、隐私与数据、支持；模型分组、搜索服务配置、工具目录、执行限制、环境、软件源、MCP、技能、运行记录和诊断集中高级页。Memory 与允许操作的撤销仍在普通设置中可见；原 leaf route 和编辑 binding 保留，没有新增 Router 或状态容器。
- 去重：模型服务页与新增供应商 chooser 删除语音管理／添加／编辑分支；语音设置页成为唯一管理入口，已有配置、选择和凭据保留。普通标题先统一为回复偏好、已允许的操作、输出；不再把技能描述为只有指令，也不暗示未准备环境已有验证锁。
- 设计与验证：复用已有 Theme/Typography/Spacing、ContextRow/settingsLink 和原生 List/NavigationLink/Menu。原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-navigation-d1-verified-20261003-build.log`。App／扩展／测试目标已编译，未执行测试／启动 Simulator／采集真机截图。未为可逆 UI 分组新增镜像实现测试；旧 key-guard 源码契约改为检查 C9 的统一凭据路径。
- 静态：git diff --check、当前 suite 清单、两份 strings plist、988/988 key parity 通过；核对原设置目的地完整保留、执行层 leaf 不在首屏、语音管理只有一个生产入口。移除旧 Agent/App section 的未使用本地化键；未删除用户数据、能力或配置。
- 后续状态：D1.5、D2、D3 实现已由下方连续切片完成；F14 真机回退导航、归档项目、大字体、VoiceOver 和深浅色仍未验收。

### D1.5 / D2 / D3：连续完成设计系统与全页面实现

- 范围：沿 Chat／抽屉／Composer／附件／相机、Message／Thinking／Tool Result／Approval／Failure／Undo／Share、Project／版本／预览、Settings 所有主页与高级子页、Voice／锁定、HTML／Markdown／Code／Diff／Records／Mermaid 详情逐族审查并整理。原生 Form/List/Menu/NavigationStack 保留，没有新增执行路径或第二套主题。
- 共用规则：正文／辅助信息／按钮统一引用 FamiliarTypography，内容间距与圆角归入既有 scale；相机快门、品牌图标、状态微型 glyph 与图表几何保留其装饰尺度，不用它们承载固定字号正文。Composer 的字体与测量继续同用 ScaledMetric。FamiliarIconButtonStyle 共享 44pt 触摸区、按压反馈与降低动态效果规则；Done 弹层控件复用 FamiliarDismissButton，原生表单按钮／破坏角色保持系统样式。
- 弹层与无障碍：文件回执预览、共享收件目标由有身份的数据驱动，移除与 optional 数据重复的 Boolean 呈现状态。文件／Markdown／Mermaid／Code／Diff／Records 详情统一原生标题与完成动作；图标行为保留可读标签，Sources、图片删除与文件回执的可访问激活路径核对。实际 VoiceOver／焦点／回退行为仍待真机，不称为已通过。
- 普通文案：文件操作统一保存／修订／读取输出与保存生成文件，审批显示文件名、格式、可读大小；不显示无意义的 Artifact ID、hash 与验证器。targetKey、参数精确授权、真实验证和持久记录仍保持原身份，技术字段保留在审计／文件详情。文件错误、保存／撤销回执及 Web 复制反馈中英文一致。
- Renderer：FamiliarMarkdownStyle 从原生语义色、外观、动态字号与高对比度生成有序 CSS variables；render state 包含样式输入，外观／字号变化会重新测量。正文、引用、代码、表格、来源、Mermaid 采用这些值，移除独立绿色／蓝色／紫色等硬编码配色和重复 dark palette。复制／图表预览有 44px 触摸区、键盘 focus-visible、原生本地化；非持久 WKWebView、安全 CSP、选择限制与既有流式合并保持。
- Glass：导航／输入与浮动控件继续使用已有 availability-gated 原生效果，TopBar 保留 GlassEffectContainer；普通回复／工具结果／审批使用清晰内容层。iOS 18 与降低透明度的原生回退保留，没有新增模糊／阴影／动画体系。
- Fixture：删除无生产调用的 FamiliarToolChips 整棵旧展示树及对应独立测试；同一 fixture 现在使用 FamiliarExecutionBlock 与其余生产卡片、审批、Thinking、Sources 等组件。示例仍只是可视检查入口，不代替真实流程。
- 回归与构建：新增 3 组 DesignSystem 用例，覆盖原生外观／辅助字号传播、相同输入稳定性、可读审批与原精确身份；仅编译，未执行。最终原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED，日志 `/tmp/familiar-design-d-verified-20261003-build.log`，本切片无编译 error／新增 deprecated warning。
- 静态：git diff --check、Renderer JavaScript 语法、suite 清单、strings plist、1005/1005 key parity 和零缺失字面量键通过；40 个 Simulator suite、2 个签名设备 suite 与完整 UI target 已列入。构建途中仅清理本任务旧 DerivedData 的可重建缓存，保留日志、源码、依赖 checkout 和用户数据。
- 完成定义：D1–D3 所有实现／静态／编译项已完成并勾选，不表示真机视觉／系统交互已验收。`docs/14-design-system-device-acceptance.md` 单列全部页面、大小字号／外观／VoiceOver／降低动态效果与透明度／小屏键盘条件，保持未勾选；Simulator、实际测试、截图、真实 Provider 和真机 guest 均未在本切片运行。
- 下一阶段：E 先依据实际源码／测量审查流式失效范围、长会话渲染、WebKit／解析 I/O 与现存 warning，不继续扩大功能数量。所有者按 F6–F14 与设计验收表验证真实任务及视觉行为。

其余未勾选项仍待实施。所有真机／真实服务验收仍未完成。


### E：流式边界、异步渲染与维护审查（2026-10-04）

- E1：Chat 父层在发送中不订阅 live 字符串，FamiliarLiveAssistantTurn 独立观察正文／推理／工具呈现；SurfaceStore 和 Controller 不为 token／usage／model 等无呈现事件作无效 mutation。历史顺序与跟随底部行为保留，没有引入缓存或另一套状态。
- E2：历史关联 Run 使用当次输入索引替代逐条扫描；eager VStack 和可变 WebKit 高度保留。源码成本已定位，懒布局、实际内存和滚动表现等待真机数据。
- E3：renderer 使用本次 renderVersion 约束 Mermaid 异步成功／失败／后续装饰，过期任务不能给新正文附上旧源码的预览；原 80ms 合并策略、原生样式、隔离 WebKit 和安全过滤不变。`node --test Scripts/test-markdown-renderer.mjs` 三项执行通过，旧 renderer 对照三项失败；这是带有限 DOM double 的调度行为验证，不是浏览器、Markdown parser、SVG 安全或真实 Mermaid／WebKit 测试。日志 `/tmp/familiar-renderer-e3-20261004-test.log`。
- E4：图片 JPEG 编码／写盘改为 @concurrent async，编码前后与写盘后检查取消，已写入草稿遇取消只清理自身；Controller 等待后仍检查草稿身份／提交边界。文档解析已有 detached 路径，Skill archive 位于非 UI tool 执行路径，资源 hash 已有流式工具。ContextAssembler 图片读取、Run recorder 附件 hash、Project 资源复制／hash、内置 Skill 首次安装及安装元数据前 manifest I/O 仍有 MainActor 工作，记录为采样点；没有推测具体耗时或跨 Actor 传递 ModelContext。
- E5：核对旧日志中的准确 warning，删除语音 rawPreview 未用变量；OAuth 回调启动闭包显式捕获 self，网络回执 completion 明确 @Sendable。编译已检查这些源文件，无相关 Swift warning；不是实际 OAuth／语音行为验收。
- E6：删除旧 ToolChips 页头／Diff／规划与完成文案、已移除固定 Runtime 阶段和旧审批翻页的 13 个无生产引用键，两语言同步。仍用的 queued/running 与动态分类／空态／分享扩展键保留；没有清理研究／Mac 或历史持久字段，没有凭候选扫描做全仓删除。
- F2–F5：补两项 StreamingObservation 回归和图片预取消用例、适配图片 preflight 用例，测试目标仅编译；41 个 Simulator suite、两个 signed-device suite 和完整 UI target 清单检查通过。实现／静态／编译与 Node 执行／iOS 未执行／真实服务／真机／签名发布证据分列，state 已同步；不表示所有运行测试完成。
- 构建：`/tmp/familiar-maintenance-e-20261004-build.log` 与资源更新后的 `/tmp/familiar-maintenance-e-verified-20261004-build.log` 均 `TEST BUILD SUCCEEDED`，原工程 Debug arm64 generic Simulator build-for-testing。前者完整重编译了相关 Swift 源，仅有 AppIntents metadata 工具提示；后者为最终增量，未启动 Simulator、未运行 iOS suites、未进行真实服务／设备／签名发布验收。
- 静态：git diff --check、shell 语法、suite 清单、JavaScript 语法、strings plist、中英 992/992 parity、零缺失生产字面量键通过。开发缓存清理仅涉及本任务旧 DerivedData 的可重建缓存，保留源码、日志与 dependency checkout。
- 下一步：所有者按 docs/15-owner-device-acceptance.md 先完成 F6–F12，再按实际启用配置检查 F10/F13 和 F14；用设备证据完成 E2/E3，并优先修正实际失败。未授权执行的 iOS 自动测试仍待独立安排，不继续新增功能。


### 真机反馈修复：语音音频会话（2026-10-04）

- 根据 FamiliarSpeechTranscriber 停止路径的主线程 setActive 运行告警，统一本地／远程录音的四个激活／停用调用。iOS 27 使用系统异步 API；部署范围内的 iOS 18–26 通过 @concurrent helper 在后台调用，category 配置也在后台。
- 会话硬件转换依次等待前一项完成，停止先清理录音 I/O 并使身份失效；权限／激活等待返回后验证 sessionID，旧流程不启动录音。准备态使用现有录音控件停止，远程转写终态清除身份，允许再次录音。无新 Agent 状态或服务。
- 验证：git diff --check 与最终 arm64 generic Simulator build-for-testing 通过，日志 `/tmp/familiar-speech-session-verified-20261004-build.log`（TEST BUILD SUCCEEDED，无新增 Swift warning）。iOS 测试未执行、Simulator 未启动，未验证实际麦克风／系统告警消失；统一真机清单增加本地／远程连续启停、准备中取消及不同 iOS API 路径的检查。


## G. 连续回复与 Runtime UI（2026-10-05）

- [x] G1 复用既有 Runtime Event／Activity／ToolResult／Approval／ResponseBlock；修复实时只读完成、重复与过期事件、重试身份、历史 Artifact 与不确定写入 journal 投影，无数据库结构变更。
- [x] G2 实时／历史共用纯值类型聚合；以非空正文、审批、提问和交付内容分段，连续搜索／读取／文件／执行／分析归类，按现有 URL 身份统计独立来源。
- [x] G3 原生折叠 Runtime Card 与二级技术详情；隐藏推理摘要、保留过程正文，基础成功信息不单独占行，局部失败低权重提示，交互／写入回执／输出保持可见。
- [x] G4 token 仅更新 live Markdown／轻量状态；活动投影仅在呈现事件或首个可见正文边界更新，完成转历史保持手动展开。首个换行不阻塞后续流式正文。
- [x] G5 取消／失败保存未完成正文；消费流提前结束时终结本地 Run／cursor。长度受限的轮次不再发出已完成正文事件；不确定写入依据现有 journal 明确提示并隐藏重试。
- [x] G6 历史文件结果重新关联真实元数据，预览／分享依赖文件存在，撤销／缺失诚实呈现；复制通过最终 block 身份取正文，过程文字仍可选择复制。
- [x] G7 更新生产 fixture、中英文文案和相关源码契约；新增 RuntimePresentation 行为回归并扩充现有 observation 边界，42 个 Simulator suites、2 个 signed-device suites 与完整 UI target 清单核对。
- [x] G8 最终静态检查与 arm64 generic Simulator build-for-testing 通过，证据单列；不启动 Simulator，不把编译称为测试执行。
- [ ] G9 所有者按 docs/15 验收普通／复杂连续会话、聚合、失败／取消／审批、文件、复制、折叠和可访问性。真实服务／真机验收仍未完成。

验证证据：数据层与区段 UI 两个切片均 TEST BUILD SUCCEEDED；最终 `/tmp/familiar-runtime-ui-final-20261005-build.log` 再次 TEST BUILD SUCCEEDED，原工程 Debug arm64 generic iOS Simulator build-for-testing，App／扩展／所有测试目标编译。15 项 RuntimePresentation 回归及调整的 StreamingObservation／UI source contracts 编译，未执行。git diff --check、strings plist、1030/1030 中英 parity、零缺失生产字面量键、42+2 suites 和完整 UI target 清单通过。最后一轮无编译 error／warning；前一轮只有 AppIntents metadata 工具提示。iOS tests、真实 Provider／Web／guest、Simulator UI 均未运行；未验证真实权限、外部写入取消窗口或物理设备视觉。保留原有语音音频会话修复；不提交或推送。下一步为 G9 与现有 F6–F14 所有者验收。


## H. 整体架构收敛（2026-10-06）

产品与生命周期决定：已提交 Files 归属 Project，删除 Chat 保留；读取去重使用事实记录与有限冻结版本复用，Web/Native/MCP 可刷新。当前 37 实体 store 为无损迁移基线，不兼容更早开发 store。当前生产命名全部使用 File；Artifact 仅允许出现在冻结迁移定义、旧存储路径与历史回执读取。

- [x] H1 冻结 37 实体基线；所有容器接入正式三阶段 schema 链；加法转换后移除旧 Artifact 实体。实现/静态/编译完成，磁盘执行独立 H7。
- [x] H2 产品 File/FileVersion、共享 Project/Chat Files、提交/导入/生成事务登记、删除/移动/版本/分享、Shell Outputs 与旧输出导入接线；读取工具统一、版本号保留高水位。实现/静态/编译完成，实际验收独立 H7/H8；Resource/Attachment 存储桥接清理归 H5。
- [x] H3 Context Compiler 统一 Agent/压缩请求、冻结长期输入/逐请求不可变编译清单、事实型 Run State、范围/字符预算/来源与观察时间；实现与 arm64 测试目标编译完成，执行验收仍为 H7/H8。
- [x] H4 统一 Tool Contract/Policy 执行决策，保留 Lazy Tools、精确授权、journal、非重放、Undo 和取消边界；回归已编译、未执行。
- [x] H5 明确 Domain/Audit/缓存职责，移除旧 Resource 生产写入，归档/移除 Grant；保留仍有历史关系与中断识别用途的记录，核对依赖并同步文档。磁盘升级执行仍为 H7。
- [x] H6 本片静态与最终 arm64 generic Simulator build-for-testing；仅编译回归，不启动 Simulator。后续切片各自重新验证。
- [ ] H7 实际执行磁盘升级/故障/重复打开回归及真实覆盖安装；用户数据升级不得仅依据编译宣称通过。
- [ ] H8 所有者真机/真实服务验收 Files、上下文隔离、多轮事实、权限/撤销和 Shell 文件行为。

每片记录实际证据；不自动提交/推送，不清空 store，不将迁移桥接阶段写成最终实体收敛。


H1/H2 验证证据：原工程 Debug arm64 generic Simulator 最终 `/tmp/familiar-architecture-files-final-20261006-build.log` 为 TEST BUILD SUCCEEDED（exit 0）。App/扩展/测试目标均编译，最终无 error/warning。静态 diff、strings plutil、1034/1034 parity、零缺失生产字面量键、42 个 Simulator suites + 2 个 signed-device suites 清单通过。增加/调整冻结存储形状、实际旧模型 store 升级、重复转换、File identity/Chat 生命周期/跨 Project 拒绝、Memory 移动隔离、旧 payload 解码与版本高水位回归；仅编译，未执行。最初 Xcode 文件协调卡住，用户保存退出/重启后恢复；早期 APFS 克隆缓存产生旧路径提示，最终增量无该提示。无 Simulator 启动、真实 Provider/MCP/guest/系统写入、真机覆盖安装、提交或推送。

H3：ContextCompiler 接管 Agent 请求、自动/手动压缩的序列化、分块、边界和摘要验收。Project 正文按预算选择，遗漏保留目录；当前消息/附件不截断，压缩显式保留当前 turn 和 assistant/tool 配对。RunState 保存工具发现/当前暴露、Skill、读取身份/结果 hash/截断/观察时间、网页证据、尝试/提交/失败/不确定/补偿撤销与生成文件引用；仅精确冻结 FileVersion 可复用读取（64k 字符缓存），保留原观察时间。逐请求清单和有限事实摘要写入现有 Activity Audit，保存失败阻止本次模型调用，不重复保存文件正文；不新增实体。增加跨 Project 候选拒绝、当前输入/工具配对、压缩后写状态、读取复用和审计回归，已编译、未执行。

H3 编译：`/tmp/familiar-architecture-context-verified-20261006-build.log` 为 TEST BUILD SUCCEEDED（exit 0），无 warning/error。初次编译暴露 extension 默认 MainActor 隔离和 summary 路径错误，已修复。未启动 Simulator、执行测试或调用真实服务。

H4/H5：Policy 返回 allow/requireApproval/deny，接管精确授权匹配/保存、审批字段和动态风险；确认后复核 preflight/权限/原生目标版本，失效决策在 journal/commit 前停止。仅无交互的独立读可并发。Registry 校验声明、effect/并发、参数载荷与输出 Envelope；commit 服从声明超时，不重放写操作。EventKit 的事件/提醒内容、目标日历和修改时间进入版本检查；首次权限准备改变目标条件时须重新确认。FileImport 直接写 File/FileVersion，stageUploads 使用当前 FileCatalog；历史 Grant 原身份/字段转成不可授权的 Activity audit 后移除实体。Runtime/Context/Domain 不导入具体 UI 或 SwiftData，授权 Persistence、Skill/Memory 纯契约分离。保留仍被恢复读取的 CapabilitySnapshot 和历史 Resource/Attachment 关系，未增加自动清理。

最终 `/tmp/familiar-architecture-verified-20261006-build.log` 为 TEST BUILD SUCCEEDED（exit 0），App/扩展/全部测试目标 arm64 generic Simulator 编译，无 error/warning。Compiler 的选择/遗漏清单、Schema 4.0.0、Grant 无损归档/重复升级、原生审批后版本变化、动态读取并发、输出契约、同 URL 刷新捕获独立身份与直接 File 导入回归均已编译、未执行。H7/H8 与既有 G/F 所有者验收仍独立保留；无 Simulator 启动、真实服务、覆盖安装、用户数据清空、提交或推送。

最终静态：git diff --check、strings plist、1034/1034 中英 key parity、零缺失生产字面量键、42 个 Simulator suites + 2 个 signed-device suites 清单通过；Core Runtime/Context/Domain 无 SwiftData/SwiftUI/EventKit import。旧的无生产调用纯 Policy gate 已删除，基线测试改用当前 evaluate 入口。

下一步是独立执行 H7 磁盘迁移/故障回归与 H8 真实服务/真机验收，按实际失败修复；不把未执行测试写成通过。

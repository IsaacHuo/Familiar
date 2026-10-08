# Familiar 产品收敛与 Agent Harness 长期计划

最后更新：2026-10-08。此清单跨对话持续维护。

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
- I 阶段例外：所有者已授权启动 Simulator 并执行测试；使用生产 Chat 与确定性 Provider／Tool，不调用真实服务或使用真实凭据。真机视觉／触感仍独立验收。

## 如何跨对话继续

1. 按 AGENTS.md 阅读当前事实，再阅读本清单的“当前切片”和未完成任务。
2. 检查工作树；核对相关源码，不把历史说明当作当前实现。
3. 选择一个可独立构建和验收的切片，明确它的完成条件。
4. 实现、必要的回归测试、静态检查与构建完成后，勾选对应实现任务。
5. 真机／真实服务验收单独勾选。编译成功不能代替测试执行或端到端验收。
6. 在本文件记录简短证据和遗留问题，不复制 git 活动历史，不记录密钥。

`[x]` 表示这一项规定的工作及验证已完成。`[ ]` 表示仍有工作或必要证据缺失。测试只编译时明确标为“未执行”。

## 当前切片

**Functional Convergence（FC0→FC9）现为当前阶段。** 用户已授权运行 Simulator、生产页面操作和真实服务验证；按下方 FC 独立账本推进。保留 I/J 的实现与历史证据，I2.4 性能对照仍单列。当前开始 FC0 代码功能矩阵与 FC1 全量测试基线；不把源码、fixture 或编译当成真实验收。设备/签名/账号条件不足的项目保持未完成。

**按用户要求在本轮收尾，I1-I8 代码实施完成；I2.4 性能对照未完成，保留为后续独立任务。** 本轮按 I1→I8 顺序推进；先建立流式呈现、稳定 Turn/Markdown identity 和统一 File 呈现契约。每阶段执行 Simulator 行为／UI 回归，失败先修复再进入下一阶段。完整规格与验收在本文 I 节；未执行的项目不得勾选。

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


## I. 连续交互与 Motion Language（2026-10-07）

### 产品契约与实施边界

目标是连续、安静、排版稳定的原生 Chat。参考成熟产品的直接正文、轻量执行过程、明确审批和可打开成果；不机械照搬截图，不制造来源、文件或进度。两个 signature motion 是新增内容 soft rise，以及执行状态收束为完成摘要。

- 维持 iOS 18、一个 Controller/Agent Runtime、现有授权/journal/非重放/Undo/保存边界。展示速度不能改变执行状态、事实时间、权限或保存内容。
- 直接在 main 实施；保留进入本轮前的文档、strings 和 staged/unstaged 测试改动。不自动提交、推送、清空用户 store、添加服务或依赖。
- 用独立测试 store、确定性 Provider/Tool 与生产 Chat 链路执行 Simulator 测试。Debug 注入不绕过生产授权，Release 不包含测试入口。
- 构建、单元测试、WebKit/UI 执行、性能测量、真实服务、真机视觉与触感分别记录。所有者明确本轮仅验证 iOS 27 Simulator；不安排 iOS 18 运行验收，部署最低版本保持原配置。
- 每阶段构建并执行相关测试，修复失败后再推进；只扩展与新变更相关的回归。既有 H7/H8/G9/F 所有者验收不随 I 阶段自动完成。

### 统一 File 呈现架构（贯穿 I1/I5/I6）

文件是可打开、可追溯版本的内容对象；卡片仅是消息流中的一种布局。File/FileVersion 是唯一生产身份，展示对象不创建新的持久化实体。

1. File presentation value 从 canonical 快照生成名称、格式、大小、版本、可用状态和可执行动作；历史 attachment/receipt 只在入口转换，不新增旧路径生产写入。历史消息固定对应版本，Files 默认最新版本。
2. 共享 File component family：Composer 的紧凑附件、用户/Assistant 消息的 File Tile、Files 的 Row 共用图标、元信息、命中区域、状态与操作规则。密度与内容可不同；图片使用缩略图，普通文档默认紧凑 Tile，多文件按统一间距纵向排列。
3. 主体操作统一打开，分享/更多独立可访问；缺失/撤销状态保留名称与原位置，关闭不能执行的动作。内容成果与授权/执行/撤销 receipt 分离、关联显示；失败和安全重要信息不能被藏掉。
4. 统一身份驱动的预览 destination；解析/完整性校验共用 FileCatalog/ByteReader，避免 View 自行拼路径。图片/Mermaid 全屏，文档 push，分享使用系统 Sheet。
5. 生成前仅显示真实 Activity。只有 typed 数据能够确定输出槽位时才预留占位；保存成功后关联真实 FileVersion，失败不能出现可打开假文件。正文、Activity、文件使用相同 soft rise。

### I1 Assistant Turn & Streaming

- [x] I1.1 新增 Presentation-only pacing，原始 delta 单独供 Runtime/Recorder 使用；按 Run/正文 block 隔离队列。首次缓冲 60ms，40ms 节拍，按完整字符和自然边界分 chunk，积压自适应追赶，额外展示延迟上限 500ms。
- [x] I1.2 完成在 120ms 内补齐；取消/错误立即补齐已接收文本并终止任务。事件边界先补齐前置正文，切换 Chat/Run/dismantle 后旧队列不得更新新视图。后台/恢复不新增执行能力。
- [x] I1.3 实时与历史放在同一稳定 Turn 节点；message/response block identity 保持，正文和 WKWebView 不因终态换分支。Footer 在补齐后出现，token 仅更新正文/轻量状态，不重算全历史和 Runtime 聚合。
- [x] I1.4 Markdown 首先去除整段 DOM 替换：稳定顶层 block 与已完成前缀复用，尾部局部 patch；source/footnote/appearance 更新只改受影响内容。新 chunk 150ms opacity + 2.5pt soft rise，已有文字不重复入场。
- [x] I1.5 定义共享 File presentation/Tile 最小契约，文件与 mutation receipt 分开；复用真实输出身份，不改 schema。
- [x] I1.6 可控时钟测试 pacing/Unicode/积压/flush/取消/旧任务；真实 WebKit 测试 block identity、终态复用、选择与复杂内容；生产 Chat 确定性短/长/突发/失败场景在 Simulator 执行。

### I2 Chat Scroll

- [x] I2.1 following/userReading/returnToLatest 显式状态；iOS 18 scroll phase/geometry/position 区分用户手势、程序滚动和内容高度变化。上滑立即取消自动跟随和待滚动任务。
- [x] I2.2 following 只在布局测量完成后合并跟随；userReading 保留可见 item/内部偏移，不因 token、Runtime 展开、Mermaid 高度、键盘或 Composer 增高重回底部。
- [x] I2.3 阅读中有新内容才显示轻量回到最新；点击时远距离先定位末屏附近，再约 200ms 短滚动。用户拖动可打断，手动回到底部恢复 following。
- [ ] I2.4 100/300 条混合历史测量 eager 基线和 LazyVStack 对照。仅当 WebView 数量明显降低、锚点漂移≤2pt、首屏/滚动耗时恶化≤10%时采用 lazy；否则保留 eager，记录原因与已完成的局部观察/增量优化，不宣称未测性能收益。
- [x] I2.5 状态机与生产 Chat UI 测试覆盖上滑/新内容/返回中断/展开/键盘/多行/终态/重新打开，记录布局和 WebView 生命周期计数。

### I3 Runtime / Tool

- [x] I3.1 沿用真实聚合与事件顺序；普通 search/read/file/process 为无背景 Activity Row，运行微 pulse，完成降低权重，失败/取消明确且无假完成摘要。
- [x] I3.2 固定图标区域与稳定 Row identity，动态执行自然收束；展开联动局部高度/opacity，保持用户展开状态，不触发全 Timeline 动画。
- [x] I3.3 Approval、clarification、File、mutation receipt、error recovery 维持操作边界；技术详情二级 push，重要失败/不确定写入/Undo 不被聚合隐藏。
- [x] I3.4 多 Tool、并发读、审批等待、局部失败、重复/过期事件、取消/不确定提交回归和 Chat UI 执行。

### I4 Composer

- [x] I4.1 输入/附件/导入/录音/发送共享连续局部 layout；复用现有草稿/异步任务隔离与发送校验。
- [x] I4.2 arrow→stop 固定中心/尺寸，symbol replacement + 微 scale/opacity；可发送/导入中/停止标签与命中区域保持。
- [x] I4.3 附件按原 identity insertion/collapse，移除自然收缩；录音轻量呼吸反馈，无真实能量数据时不伪造音量波形。
- [x] I4.4 键盘服从系统动画，Composer 高度、多行和附件变化使用局部 standard/interactiveSpring，不与滚动阅读竞争。
- [x] I4.5 UI 测试发送/停止/重复点击/导入/附件移除/长输入/语音状态/草稿切换/键盘以及大字体。

### I5 Markdown / Code / File

- [x] I5.1 完成代码/表格/引用/公式/链接/脚注的增量稳定布局。代码围栏生成时同容器纯文本，闭合后高亮/Copy；表格完整行渐进显示，横向位置保留。
- [x] I5.2 Mermaid 同尺寸最小高度源码占位，闭合后异步渲染，局部终态替换；保留版本隔离/安全过滤，缓存实际已测高度，错误可读。
- [x] I5.3 Composer、用户文件、Assistant 输出、Files Row 全面接入共享 File family；格式/大小/版本/可用性一致，主体打开与次操作分离，receipt 不占据成果主体。
- [x] I5.4 WebKit/Sources/footnote/selection/code copy/表格横滚/外观切换/文件版本/缺失/撤销测试；长 Markdown 生成与终态前后截图。

### I6 Navigation / Sheet

- [x] I6.1 Project→Chat 真正 push，返回原 Project 列表位置；共享既有 Controller/Runtime，只让当前 Chat 订阅 live presentation，保留草稿确认与忙碌限制。
- [x] I6.2 Chat→File Preview、Runtime→Detail push；Settings→Advanced 保留 push。Composer 图片原生 zoom 全屏、Mermaid 全屏；消息图片与文档交给系统 Quick Look push，无有效源节点时使用标准系统过渡。
- [x] I6.3 创建/编辑/导入/分享为 Sheet；轻量选择 Menu/Popover，身份驱动 destination；关闭与交互式返回恢复焦点/阅读位置。
- [x] I6.4 UI 验证返回路径、草稿/Run 归属、预览分享、关闭/返回手势、缺失目标和 Reduce Motion。

### I7 Haptics & Microinteraction

- [x] I7.1 FamiliarHaptics 固定 selection/send/approval/success/warning/destructive。selection=selection，send=light，approval=medium，success/warning=notification，destructive=rigid；事件去重，批量 Tool 完成合并，系统已反馈的操作不追加。
- [x] I7.2 Copy 成功 icon→check，1.2s 恢复；Save 仅保存成功后确认；Approval 点击先等待，真实执行完成后收束 receipt，失败保留上下文及安全 retry。
- [x] I7.3 Tool completion 平滑结束 pulse；Project/Model 标题 micro crossfade；Context Menu/Swipe/Long Press/自定义 dismiss 采用统一反馈归属。
- [x] I7.4 行为/UI 测试确认时机、失败不报成功、重复点击/离场任务清理。物理触感验收单独保留。

### I8 全局 Motion 收敛

| Token | 默认 | 用途 |
| --- | --- | --- |
| micro | 120ms ease-out | 按压/图标/短确认 |
| standard | 220ms smooth | 一般状态/布局 |
| emphasized | 340ms smooth | 页面内强调 |
| interactiveSpring | response .36 / damping .88 / blend .08 | 可中断布局 |
| contentAppear | 150ms ease-out / opacity 0→1 / Y 2.5→0pt | soft rise |
| collapse | 200ms smooth + opacity | 详情/操作区收起 |

- [x] I8.1 I1 先接入必要 tokens，I8 迁移全 App 旧名称和自定义曲线，删除旧别名；系统 Navigation/keyboard/symbol effect 保持系统行为，不造自定义全局转场。
- [x] I8.2 SwiftUI/CSS 共用参数，通过既有 renderer style/options bridge 下发；动画仅局部作用，无整 Timeline spring。
- [x] I8.3 Reduce Motion 关闭位移/pulse/zoom/spring，改即时状态或 micro 淡入；保留 VoiceOver、Dynamic Type、44pt hit target、降低透明度与 iOS 26+ 原生 Glass availability。
- [x] I8.4 全相关回归、UI/renderer 执行、本地化 parity/缺失键、diff 静态检查；state 只写已实现事实。未测试 OS、真实服务、真机视觉/触感和性能限制明确列出。

### 分阶段证据与下一步

I1：arm64 iOS 27 Simulator build-for-testing 通过，最终编译日志 /tmp/familiar-motion-i1-build.log 无 error/warning。相关单元/WebKit 共 25 个不同用例执行通过：/tmp/familiar-motion-i1-unit.xcresult（23/23）及 /tmp/familiar-motion-i1-native-final.xcresult（8/8，含重复及新增原生视图/首帧回退用例）；无跳过或预期失败。/tmp/familiar-motion-i1-ui-final.xcresult 生产 Chat 短回复、取消、Provider 中断三个 UI 用例 3/3 执行通过，保留截图。Node Mermaid 调度 3/3 通过。测试使用 Simulator Debug 双旗标和内存 store；未使用真实凭据/Provider/服务。
首次混合测试的 Xcode 日志收束停住，已中止并分开执行；首次 UI 的停止标签/AX WebView 层级断言失败，修正后重跑通过，不把失败尝试计作验收。截图发现首帧回退段落丢失，已修复并补原生 WebView 保持 identity/回传高度的执行用例。复杂 Markdown 的完整渐进策略、全部 File family/统一预览仍由 I5/I6 完成；本阶段仅建立生成 File Tile 与回执分离最小契约。
I2：/tmp/familiar-motion-i2-build.log arm64 iOS 27 build-for-testing 通过，无编译 error/warning。/tmp/familiar-motion-i2-lazy.xcresult 9/9（滚动状态机、100/300 原生布局及真实 WKWebView/完整 Timeline 终态复用）通过；/tmp/familiar-motion-i2-ui.xcresult 上滑后新内容锚点漂移≤2pt、键盘/多行草稿/返回最新及短回复 2/2 UI 通过，无跳过。
相同混合历史原生布局：eager 100/300 各创建 100/300 个 WKWebView，初始布局 6.032/26.026s；lazy 两档均 4 个，0.118/0.167s（/tmp/familiar-motion-i2-eager.log、i2-lazy.log）。采用 LazyVStack。频繁 geometry 留在非观察字段，历史顺序/Run 关联以输入初始化值复用，避免延迟 State 缓存造成实时→历史中间空帧；旧底部距离 PreferenceKey 已移除。
I2.4 仍保留完整滚动时延/内存/后续实例数量测量待办；以上是初始原生构建成本，不是 FPS、真实服务或真机性能验收。下一步 I3，本轮仅验证 iOS 27。

I3：Runtime 改为透明 Activity Row，固定状态图标/breathe→完成摘要，显式 44pt 展开按钮和局部高度/opacity；技术详情 push，写/审批/file/error 操作边界保留。/tmp/familiar-motion-i3-unit-retry.xcresult 31/31 通过；/tmp/familiar-motion-i3-provider.xcresult Tool Call ID 配对 1/1 通过；/tmp/familiar-motion-i3-controls-ui.xcresult 生产 Lazy Tools→三并发读→聚合/展开→详情 1/1 UI 通过。审批→真实文件/回执→Quick Look→返回的 UI 用例在 i3-ui.log 中单项通过，整次运行另一项失败，不计整包通过；后续统一复验。修复容器 AX identifier 覆盖子控件导致的不可定位，移除旧文件手势死代码，过时 UI 源码断言改为 canonical File 版本/缺失字节行为。
磁盘不足曾阻止构建，仅清理本轮失败/未收束测试临时包和重复 SourcePackages（保留日志/导出证据及成功包），复用 /tmp/familiar-architecture-dd-20261006/SourcePackages；之后构建无 error/warning。Xcode 失败时 sysdiagnose 收束停顿，后续测试使用 collect-test-diagnostics never，保留 XCTest 结果和显式截图。

I4：Composer arrow/stop 相同 frame/中心、symbol replace + micro scale，录音 breathe 并尊重 Reduce Motion，附件 insertion/collapse、测量高度 standard 和统一 mode tokens。/tmp/familiar-motion-i4-build.log 无编译 error/warning；i4-ui 中审批/file/预览、发送/停止两个用例通过，阅读用例遇到 Simulator AX query 超时，整包失败；相同构建 /tmp/familiar-motion-i4-reading-retry.xcresult 1/1 通过，未复现布局循环。附件实际导入/录音设备权限/物理触感仍为真实服务/设备验收，不从状态动画或源码验证推导通过。

I5：共享 FileLabel 用于 Composer/消息/Files，FileTile 文件打开与分享分离，生成文件通过 canonical FileVersion 解析并在预览前校验字节 hash；撤销/缺失保持不可用。代码围栏未闭合用纯文本同容器并禁用复制，闭合高亮/Copy；表格 patch 保留横向 wrapper/位置；数学/成功 Mermaid 缓存，pending Mermaid 在同源码正文增长时复用任务且保留异步归属验证。移除 16k pt 正文截断，保持有界 1M pt 测量。/tmp/familiar-motion-i5-unit.xcresult 17/17（包含原生/真实 WebKit code/table identity 与 UI/File/Theme）通过，Node 4/4；/tmp/familiar-motion-i5-ui.xcresult Markdown/code/table/Mermaid 及审批/file/预览 2/2 UI 通过。source/复杂内容内部阅读锚点、真实多格式文件/图片和物理效果仍需后续/所有者验收，不能据测试 fixture 宣称服务通过。

I6：Project 浏览器保留临时 Sheet，其 NavigationStack 内 Project→Chat 使用类型化 path push；关闭前返回同一 Project，忙碌/草稿确认沿用既有 Controller。移除旧回调构造路径，底层 Chat 在子 Chat 显示时退出订阅。文件预览由 Sheet 改为身份驱动 push，临时 Share Draft 保留 Sheet，Composer 图片使用原生 zoom 并尊重 Reduce Motion。/tmp/familiar-motion-i6-ui.xcresult 文件审批/预览/Done 单项通过，Project 测试因重复 Daily Chat 标签失败；改显式 project.open 标识后 /tmp/familiar-motion-i6-project-verified.xcresult 1/1 返回原 Project 执行通过并检查截图。误拼筛选器的 0 tests 包不算通过。完整交互式手势/真机视觉仍单独验收。

I7：六种 FamiliarHaptics 集中到一个入口，事件 key 有界去重，300ms 内并发成功合并；自定义操作负责反馈，Menu/Context Menu/Swipe 的系统反馈不叠加。Copy/Save 共用 1.2s confirmation，可重复点击保护和离场取消；审批先显示待执行，真实结果才成为 receipt。/tmp/familiar-motion-i7-unit-fixed.xcresult 32/32；/tmp/familiar-motion-i7-confirm-unit.xcresult 10/10；审批→文件→预览用例在 i7-ui 中通过，Copy 用例因 XCTest idle 等待超过确认窗口失败，改为状态测试验证即时确认、UI 验证恢复后 /tmp/familiar-motion-i7-copy-ui-fixed.xcresult 1/1 通过。未修改产品确认时长迎合测试。

I8 实现：新增 Activity/File 共用 soft rise，历史 Follow-ups 固定排版且 44pt 命中，不逐条入场改变高度。Motion 曲线及触感入口均集中；原生 Navigation/keyboard 保持系统行为，Reduce Motion 来自系统环境，Debug Simulator 双旗标可单独验收自定义动作及大字体。局部内容块几何优先于整 Turn，Mermaid/表格等 DOM 高度变化回传阅读补偿；环境几何 action 是可比较值，避免每次更新替换 closure。renderer 共用一个非持久、禁网络的 DataStore；离开正文会停止 pacing。
最终回归发现审批展示早于 coordinator 注册等待，立即回复可成为 unknownRequest 并挂起。已改为注册 continuation 后 onPending 再发事件；确认规则、作用域、重验证、取消和 idempotency 不变。/tmp/familiar-motion-i8-approval-regression.xcresult 21 个用例（29 个参数化实例）全部通过，新增立即回复/重复决策回归。
/tmp/familiar-motion-i8-anchor-verified-build.log arm64 iOS 27 build-for-testing exit 0、无 error/warning；/tmp/familiar-motion-final-unit.xcresult 102 个逻辑用例（110 个实例）通过，零跳过/预期失败。包括 native WebKit、稳定 DOM/code/table、滚动状态/内容块锚点、pacing、Runtime/授权/提交/本地化与 UI 合同。Native 100/300 初始布局均 3 个 WebViews；20 步布局工作负载最大 8/17 个，采样原生进程 resident 约 327/329 MiB，不包含独立 WebContent 进程，也不代表真实手势帧率。真实滑动及最终 UI 包仍在执行。

资源保护与中断恢复（2026-10-07）：用户要求验证前主动检查内存/磁盘并提前清理。临时 /tmp 证据目录已消失，eager 对照脚本及恢复构建未收束，不计对照通过；已明确恢复 Timeline 为 LazyVStack。此前最终 UI 目标 12/13 通过，唯一失败为 100 条历史的 XCTest AX 快照/目标失效；主线程 sample 在 XCTAutomationSupport/UIAccessibility 遍历，未显示布局补偿循环。同构建 300 条真实滑动通过：原生 App 绝对/峰值 physical memory 约 64.4/65.0 MiB，Scroll_DraggingAndDeceleration 平均 2.586s；不包含 WebContent，也不是 FPS。Project→Chat→Files 临时 Sheet→原 Project、阅读/键盘/大字体、短/取消/错误/Markdown/Tool/冷启动及生产 fixture 均单项通过。整包失败不能写成全 UI 包通过。坐标手势已替代重复的整树目标解析，等待复测。
清理时保留源代码、SourcePackages、Build Products 与测试记录，只移除可重建的 DerivedData Intermediates、ModuleCache 和 SDK 编译缓存；磁盘从约 155 MiB 恢复到约 2.8 GiB。后续采用单并发构建，先不启动 Simulator；证据移到 ~/Library/Logs/FamiliarVerification/20261007-motion，当前 DerivedData 位于仓库忽略目录 DerivedData/motion-20261007。每轮启动前和执行中检查内存压力、磁盘余量及遗留进程。
Clarification 同类注册先后时序已修复并增加立即回答回归。截图发现大字体 Composer 占位超出紧凑框，已按实际行高扩大编辑区并保持占位单行；保存成功后的 Project 名称查询失败不再误报保存失败。上述最新改动等待本次构建和针对性回归，不复用旧构建证明。

持久证据与资源恢复完成：~/Library/Logs/FamiliarVerification/20261007-motion/build.log 单并发 Debug arm64 build-for-testing exit 0，无 error/warning；final-unit.xcresult 47/47（含立即审批/立即回答、Clarification 同 Run/取消、pacing、滚动内容块、WebKit、Copy/Save 生命周期与主题）通过，零跳过；final-ui-fixes.xcresult 2/2（坐标真实滑动 100 历史、大字体 Reduce Motion）通过，已导出截图和 metrics.json。截图确认 Composer 占位已位于框内；100 历史 App physical 绝对/峰值平均约 61.1/61.5 MiB，scroll/deceleration 平均 1.897s。此前相同 iOS 27 构建已完成的其他 12 UI 单项与本次修复证据合并说明覆盖，不称为新的整包全通过。结束后关闭本轮 Simulator，可回收内存约 63%，磁盘约 2.5 GiB；无遗留测试/构建进程。有效产品、日志和结果包保留，结束构建后移除本轮编译中间产物/SDK模块缓存和 npm 下载缓存。
I1-I8 代码实施与所列 Simulator 验证完成。I2.4 的同条件 eager/lazy 全滚动 ≤10% 对照未完成：eager 对照中断且临时记录消失，不能冒充通过；保留独立性能验收项。真实 Provider/多格式导入/语音/物理触感及包含 WebContent 的真机 FPS/总内存仍在 docs/15 的所有者验收列表；iOS 18 本轮不验证。后续先做资源预检，按单并发、分组执行和及时关闭任务 Simulator 验证；不重复未改变且已通过的用例。

真机安装优先任务（2026-10-07）：hwf/iPhone 17 Pro/iOS 27.0.1 已配对，开发者模式开启。当前 Debug arm64 真机构建成功，Team G229WP43HH 与证书匹配；devicectl 覆盖安装成功、无测试参数启动，进程 PID 2849 持续存在。证据在 ~/Library/Logs/FamiliarVerification/20261007-hwf 的 build.log、install.json、launch.json。未删除旧 App 或用户数据。此前具体 Xcode 安装报错未复现；Mac 磁盘多次接近耗尽，已清理可重建缓存并保留签名产品。性能对照仍为下一任务，其隔离副本的首次创建因磁盘耗尽未启动，主代码保持 LazyVStack。

### 本轮最终收尾清单（2026-10-07）

- [x] Assistant 流式 pacing、稳定 Turn/Markdown identity、阅读状态与内容块/DOM补偿、轻量 Runtime、Composer、统一 File family/预览、Motion/Haptics 和 Copy/Save 确认已实施。
- [x] 审批/Clarification 先注册等待再展示；最新相关 47 个单元/WebKit用例及 2 项 UI 修复复测通过。此前整 UI 包 12/13 通过，失败的 100 历史用例已通过坐标手势复测；不将跨构建证据合并成新整包通过。
- [x] 当前版本已签名覆盖安装到 hwf/iOS 27.0.1 并启动；未删除原 App 或用户数据。此前 Xcode 具体失败未复现，已确认宿主机磁盘持续接近耗尽。
- [x] 本轮 DerivedData/motion-20261007、hwf-20261007 已删除；eager 隔离副本未创建。借用的 SourcePackages 缓存经 31 个仓库无本地修改检查后删除，可按 Package.resolved 重新下载。已停止本轮 Simulator，无残留构建/测试进程；手机安装保持。
- [x] 源码、Vendor、Package.resolved、现有 Git 改动保留；在 main，未提交/推送。
- [ ] 同条件 eager/lazy 全滚动 ≤10% 对照（I2.4）未完成；本轮按用户要求不再继续，下一轮由代理承担。
- [ ] 用户真机验收：真实 Provider 弱网/长回复/多 Tool/取消错误，真实附件多格式/图片/录音，导航阅读/键盘、系统大字体/Reduce Motion、物理触感；FPS与包含 WebContent 总内存独立验证，见 docs/15。

证据可用性：关闭时检查，/tmp 历史证据及 ~/Library/Logs/FamiliarVerification/20261007-motion、20261007-hwf 已不在预期路径；本次收尾清理前就已缺失，无法提供原包复查。保留上述来自已执行工具结果的验证记录，不宣称结果包/截图现仍存在；将来需要重新交付原始证据时重新生成。

## J. 设置分类、列表与聊天顶栏（2026-10-07）

本轮仅 UI/导航/文案；上一轮 I2.4 性能对照保持关闭，不恢复。全部旧功能、保存逻辑、权限/Memory/Runtime 不变；用户明确只做编译，不启动 Simulator，最后由用户真机视觉验收。

- [x] 首页按模型、个性化、能力与连接、界面与交互、隐私与数据单入口、关于与支持排列。模型分组回到模型；回复偏好/记忆独立并明确差别；高级提前且显示 Skills/MCP/工具/执行说明。
- [x] 高级依次是 Skills/MCP/搜索/工具、执行限制/Shell/Python源、运行历史/诊断；隐私汇总按访问与授权、安全、本地数据组织，原说明页改数据处理说明。
- [x] 设置行展示必要副标题、保留系统导航箭头/44pt命中；MCP/Provider/模型组/项目普通添加导入动作纯文字；项目指令、模型组、MCP编辑、记忆编辑增加进入提示，保存行为保持。
- [x] 聊天顶栏为设置、模型选择、项目、更多；项目与更多组成右侧组，新建对话移到更多首项；保留草稿/忙碌规则。图标20pt semibold、模型17pt medium、下拉11pt semibold，保留Dynamic Type/完整辅助标签和crossfade。
- [x] 静态核对23条设置路由全部可达且不重复，顶栏/菜单顺序和禁用条件正确；中英1045键相等，零缺失生产字面量；plist与diff检查通过。
- [x] 单并发 Debug arm64 iOS27 Simulator构建通过；不启动/运行Simulator，不声称真机视觉验收。

J 验证：2026-10-07 最终 generic iOS Simulator/Debug/arm64 build exit 0，final-build.log 为空（零 warning/error），产物时间晚于本轮最后的呈现源码改动。日志路径 ~/Library/Logs/FamiliarVerification/20261007-settings；23条设置路由可达且顺序核对、1045/1045文案parity/零缺失生产字面量、plist、diff静态检查通过。按用户要求没有Simulator启动/UI测试/真机视觉宣称；用户自行视觉验收。仅本轮UI文件、strings和状态文档增量修改；原有未提交工作保留，main无提交或推送。

J 真机交付（2026-10-08）：用户要求将设置分类/列表/顶栏新版本安装到 hwf。Debug arm64 真机构建完成，codesign --verify --deep --strict 通过；devicectl 覆盖安装 com.isaachuo.familiar 成功，生产参数为空启动成功，进程核对持续运行。证据在 ~/Library/Logs/FamiliarVerification/20261007-settings-hwf 的 install.json/launch.json；仅确认安装启动，不代替用户视觉验收，未删除手机数据、未运行Simulator。

## FC. Functional Convergence（2026-10-08）

### 目标、授权和最新基线

全部现有生产能力须从入口、配置、权限、执行、结果呈现到持久化/恢复贯通。单 Agent/Loop 保留；不增加 Router、后台承接、跨重启自动续跑、云同步、STDIO/MCP OAuth 或供应商数量。完整交互 Terminal 是用户明确新增的现有 Linux 能力入口。

本阶段用户已授权 Simulator 测试/生产页面操作和真实服务验证。Tavily 仅用测试凭据做少量公开查询，不内置 Key、不记录 Key；真实模型主要验收 DeepSeek，其他 Provider/OAuth 后置且不能伪称通过。hwf 需要连接、解锁及签名；硬件/账号阻断单列。直接 main，保留原改动，不自动提交/推送/清库。

当前源清单 47 Simulator suites + 2 signed-device suites + 完整 UI target。复用 I/J 的生产 Chat 测试 Provider、Streaming pacing、Scroll State、WebKit/审批注册修复。现有双旗标测试用内存 store，不证明 relaunch；补独立磁盘模式。旧 I2.4 eager/lazy 对照保持独立，不恢复大规模视觉开发。

### FC0 Feature Matrix

唯一生产清单在 [state/FEATURE_MATRIX.md](state/FEATURE_MATRIX.md)，逐入口/工具列注册、实现、默认发现、Project scope、系统权限/签名/账号、六状态、写边界、存储、测试和缺陷；源码存在、fixture、编译、执行、真实服务和真机分开。通用六状态为 success/empty/denied/failure/cancelled/relaunch；写操作额外 approve/reject/duplicate/undo/interrupted。不适用注明理由，没有 Undo 的能力明确 unavailable。

覆盖 Chat/Runtime/Provider/Streaming/Project/Context/Compaction/Attachments/Vision/Web/Memory/Files/Artifact/Workspace，Calendar/Reminder/Location/Maps/Weather/Contacts/Photos/Health/Music/Bluetooth/Notification/Alarm/Clipboard/NaturalLanguage/Spotlight，Skill/MCP/Environment/Shell/Terminal/Voice/OAuth/Share Extension/Widget/App Intents/Deep Link/锁定/Settings/存储恢复/渲染。

### 阶段任务与顺序

- [ ] FC0 完整矩阵、入口/测试清单、源码问题分级；证据与待验收分开。
- [ ] FC1 运行全部 Simulator suites/UI baseline；修 Runtime 唯一终态/保存错误/取消/工具循环/Web Evidence；生产 Chat 操作。
- [ ] FC2 Project/Context/Files：真实导入/版本/冻结/预算/隔离/磁盘重开。
- [ ] FC3 Memory/追问：质量用例、确认写入、相关建议生成/保存/历史。
- [ ] FC4 所有 Native：普通聊天按需发现、授权/权限、签名/服务、真实读写。
- [ ] FC5 Artifact/Output：write→read→edit→version→preview→share→delete→undo。
- [ ] FC6 Skill/MCP/iSH/Terminal：真实高级执行、PTY、现代入口/消息流、资源限制/隔离。
- [ ] FC7 SwiftData/文件边界、1.0→4.0升级/覆盖安装、强杀/不确定动作/Undo。
- [ ] FC8 全 UI/Settings/Voice/系统扩展入口操作，状态/返回/配置一致。
- [ ] FC9 全量回归/端到端复验/Release Gate。

任何拒绝后写入、重复副作用、跨 Project 泄漏、数据丢失、假成功即时提升 P0，优先处理。

### FC1 Runtime/Chat/Web

Runtime：实际执行所有 suites 和 UI target。助手消息/ResponseBlock/Sources/Run/cursor 成功终态在一致的保存边界提交，保存错误传播；首 token 前/中途取消、断流/空回复/异常 Tool JSON/deadline/压缩/预算耗尽均只有一个明确终态。保留已执行结果/部分正文，不重试不确定写入。发送/压缩禁止切换 Chat/Project并明确说明。测试用生产 Controller/Loop/Policy，保留 pacing/阅读机制。

Web：免 Key 搜索保留，Tavily 只作已有 API 路线/真实对照。单 Run Web Evidence 缓存 normalized query、provider/language、sourceID、canonical URL、redirect aliases、页面/失败/原观察时间；合并进行中请求，重复结果不联网。保守归一 fragment/tracking/host/默认端口，保留业务参数/路径语义。跨查询URL去重与来源多样性。独立 web_fetch 允许安全并行，最多2 reads。连续2次无新增来源阻止继续搜索、允许读取已有来源回答，不叠加多层重试。

article/main优先，内容/链接密度 fallback，清噪音/嵌套重复，保留代码/表格/标题与24K边界。按query/device语言选择语言/市场；已有adapters支持新闻/时间/来源控制。传输、反爬挑战、无结果、正文不可解析、相关性分别诊断；query改写/证据缺口仍由单Agent处理。

回归：重复查询/URL/进行中请求只执行一次；并发URL上限与调用顺序；归一URL/稳定source/跨Run隔离；失败后继续回答；预算/取消/权限优先。真实DDG/Bing/Tavily中英文/新闻/技术公开查询；429/超时/重定向/无结果/解析错误通过可控传输稳定复现。

参考：https://docs.tavily.com/documentation/api-reference/endpoint/search ，https://api-dashboard.search.brave.com/app/documentation/web-search/query ，Mozilla Readability。研究不等于采用新的云执行器或硬编码Key。

### FC2/FC3 Project/Files/Memory/追问

Daily/普通Project指令/模型/文件/Memory/Skill/输出/摘要隔离；真实 TXT/Markdown/PDF/DOCX/PPTX/XLSX/CSV/EPUB，扫描/混合PDF、损坏/加密/超限/取消；选择器/导入/文案同支持范围。Vision模型直传及Apple Vision fallback，发送失败保留草稿，冻结版本/预算。

Memory：中文分词/同义/跨语言/无关/跨域负例，先量化候选和最终入选再修简单有效检索，不先建向量系统。三作用域、remember批准/拒绝/取消、编辑删除/关闭/冲突/超预算/重启。Memory不能授权，保存前无成功回执。

追问：主回复成功保存后，同实际模型一次无工具小请求，最多3条内容相关问题，可空。输入只取该用户问题+最终正文，预算裁剪，不读取其他Project。Typed suggestion存在最终ResponseBlock payload，不加实体。JSON错误/超时/取消/保存失败不显示固定模板、不改变主Run终态。新发送/切换/退出取消旧任务，回答身份防重，重开只读保存项。点击只填Composer，模型/报告用量单独审计。参考 https://github.com/langgenius/dify/blob/main/api/core/llm_generator/llm_generator.py 。

### FC4 Native 全链路

无显式capability配置的Project/Daily默认按需发现现有原生工具，已明确关闭尊重；启动不批量权限申请。目录→Project scope→Policy/系统权限→Service→结果五层诊断。Settings与Runtime同配置；错误不得被try?吞掉。

逐工具真实验证：Calendar/Reminder 查询/增改删/目标变化/拒绝零写/重复/跨重启Undo；Location/Maps 城市/当前位置/撤权/取消/坐标；Weather 坐标直查及Maps→Weather/current/forecast/history/来源；Contacts空/limited/拒绝/撤权；Photos limited/full/add-only/重复保存；Health真实聚合/空值非零；Music授权/目录/地区/token/网络（不加播放）；Bluetooth UUID/真设备/关闭/取消；Notification/Alarm触发/重复/取消/Undo/版本门控；Clipboard/NaturalLanguage/Spotlight结果、索引/跳转与删除更新。

签名必须核对源码、最终codesign、profile、App ID服务；WeatherKit声明不证明账号的capability/app service，MusicKit使用系统授权/自动token而非要求用户音乐Key。参考 https://developer.apple.com/help/account/identifiers/enable-app-capabilities/ ，https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api 。

### FC5 Output

旧版本不可变；Markdown/TXT默认，复杂文档真实打开/内容/签名校验。磁盘缺失/元数据孤立/保存失败/分享取消/重复发布不可假成功。保存/删除/Undo故障补偿；输出与receipt分开。

### FC6 Skill/MCP/iSH/完整Terminal

Skill安装/卸载/binding/Run选择/allowedTools/hash/非法路径/损坏/超限/下一Run不继承；HTTP MCP lazy/paging/exact selection/approval/断开/取消/重复call，未实现STDIO/MCP OAuth明确不可用。iSH冷/热prepare、依赖/mount、网络/进程/磁盘/输出/timeout/cancel/失败恢复；普通聊天不启动guest。

More→Terminal归属当前Project，Project环境与Settings同状态。当地打包xterm.js+非持久WKWebView，不CDN；ANSI/光标/选择复制/中文/软键盘辅助键/resize。复用iSH现有TTY/PTY，不复制旧App；bridge start/sendInput/resize/interrupt/close，output/state/exited/failed，byte输出不走按行callback；重建arm64 device/Simulator XCFramework并更新供应链。

同guest执行所有者：Agent时terminal只读，不能抢输入/挂载/取消；手工占用Agent明确busy。手工会话显示Project/网络/资源边界，其许可不能授权模型。仅当前Project mount，验证HOME/tmp/history和guest写路径隔离，不只cd。基础环境/包准备/网络/配额保持受控。后台不保证、重启不重放。显式保存手工成果进入canonical File版本，日志不自动注入Memory/Context。

消息流沿现有Activity Row显示prepare/run/完成/失败/取消；stdout只在展开详情/同执行只读terminal，高频日志不进正文。Run/toolCallID/执行身份一致；File Tile与receipt分开，部分失败/不确定/Undo保持可见。验收交互shell/ANSI/中文/Tab/arrows/Ctrl-C/D/resize/TUI/冷启动/取消/超时/残留进程/Project切换/Agent冲突。先PTY后UI，层层真实可用。参考 https://xtermjs.org/docs/api/terminal/classes/terminal/ 。

### FC7/FC8 恢复/所有入口

检查Conversation/Message/Run/ToolResult/Approval/FileVersion/Attachment/历史Resource/Memory/Skill/Authorization/Undo及磁盘；正式1.0→4.0磁盘升级/重复打开/失败回滚/覆盖安装，身份/关系/hash/审计。提交前/外部效果后/保存前/Undo中强杀，不确定写不自动重放。恢复不自动删用户数据，升级不靠清库。独立磁盘UI store证明relaunch。

逐页 Button/Menu/Context Menu/Swipe/Sheet/NavigationLink/Toolbar/Toggle，Voice/相机/锁定/Share Extension/Widget/App Intents/DeepLink/Spotlight/通知/权限/撤销/预览分享和全部Settings routes；沿I/J，不重做已完成设计。

### 验证资源与证据

由代理执行Simulator页面操作/快照/截图/日志。47 suites同一次选择执行，UI target独立，新增suite更新清单；纯回归、production+可控依赖、真实服务、签名设备四种证据单列。0 tests/skips/expectedFailures/crash/未执行不算通过。持久证据 ~/Library/Logs/FamiliarVerification/20261008-functional-convergence。

用户要求提前资源清理：串行build/test，监测memory_pressure和磁盘；清理本任务可重建Build/Intermediates、旧失败产品/冗余临时包，保留源码、用户数据、结果摘要/截图/必要日志，不删除借用的Package源或其他项目。每切片更新实现/执行/服务/设备证据与下一任务。

### 缺陷索引（初始源码发现，尚需执行复现）

| ID | 优先级 | 问题 | 状态 |
|---|---|---|---|
| FC-R01 | P0 | Controller在assistant最终保存前finishRun；terminal save try?，可能假成功/丢正文 | 已修复，原子保存/失败回归已执行；真实Provider待验收 |
| FC-W01 | P0 | Run仅缓存File读；重复Web无证据复用/无进展限制 | 已实现并实际回归，真实搜索已验收 |
| FC-W02 | P0 | fetch禁止并行，正文max字符选body，固定中文搜索市场 | 已修复并执行，真实fetch通过 |
| FC-N01 | P1 | 其他Native默认高级关闭；capability toggle吞save错误 | 已修复，adapter回归通过，真实权限/设备待验收 |
| FC-F01 | P1 | 固定两条追问，没有内容生成/持久化 | 已实现，production UI点击仅填Composer通过，真实模型质量待验收 |
| FC-T01 | P1 | 无完整terminal入口/PTY桥接 | 待实施 |
| FC-P01 | P1 | 当前UI test内存store无法验证重启 | 独立磁盘模式已实现；新UI selector修复后复跑 |
| FC-N02 | P1 | Bluetooth新manager的unknown被判失败，取消permission waiter不释放，旧scan timer能结束下一scan | 生产Service修复及3项生命周期回归已编译，执行中 |

### Release Gate

- [ ] 所有生产能力入口/范围/权限/真实可用结论。
- [ ] 核心Runtime/Chat/Files/Memory/Native/Output/恢复通过。
- [ ] Terminal真实PTY、执行所有权/Project隔离通过。
- [ ] 内容相关追问/失败无假模板。
- [ ] 无数据丢失/重复副作用/假成功/跨Project泄漏/无限循环/残留状态。
- [ ] 拒绝/取消不越权写，不确定动作不重放。
- [ ] 升级不清库，Settings/Runtime一致。
- [ ] 缺设备/账号或后置Provider/OAuth保持未通过；不以blocked/unavailable冒充正向验收。

下一切片：FC0矩阵核对 → FC1基线实际运行/首批P0修复。所有门槛满足后才进入下一阶段UI/Motion Polish。

### FC0/FC1 当前执行记录（2026-10-08）

FC0已建立逐项矩阵：56个production tools、29个非工具/未接线入口族、24种AnyDoc声明格式。矩阵仍需随实际验收逐行补证据；不以格式声明算转换成功。

基线原工程Simulator test build成功，47 suites同一次选择实际执行：345 tests，328 passed，17 failed，0 skipped/expectedFailures。baseline-unit.xcresult/summary位于持久验证目录。失败包括过时Daily/路径/budget/model alias断言、虚构Web capture的invalid域名、未实际写字节的File版本fixture、Shell缺Project上下文、Conversation Memory缺Project归属和两个Codex instance强制解包crash；逐项核对当前真实合同，保留所有失败记录，不称基线通过。

UI基线实际启动，但100历史性能用例的app.screenshot请求AX主线程超时，300项因中止未执行完：3 tests，1 passed，2 failed/cancelled。MCP等待300s超时后xcodebuild仍运行；读取日志确认后SIGINT终止本任务PID，改屏幕级XCUIScreen截图以避免额外app AX查找。不是整UI通过，须新构建完整重跑。

FC1在实现：Run-local Web Evidence、URL/来源归一/多样性、fetch并发、语言与正文抽取；终态save错误传播与Final Message/blocks/Sources/Run/cursor单次成功保存；补Web evidence和终态原子边界回归。初次编译发现URLComponents独占访问错误，已修正，验证仍在进行。源码修复不称runtime通过。

资源：serial -jobs1/禁index，读memory_pressure/df。UI停止后内存free67%，磁盘约2.5GB；删除本任务已结束baseline prepared test products，保留xcresult、summary和logs，不删除借用Package源。未连接hwf，真实签名/系统/guest仍待验收。未提交/推送。

FC1追加证据：fc1-unit.xcresult实际353 tests/352 passed/1 failed/0 skips；唯一失败为select(nil)应保留当前Project的旧测试断言，已核对并加上显式startNewConversation(nil)切回Daily验证。fc1-ui.xcresult完整13/13通过、0 skips/expectedFailures：包含100/300历史手势、短/长/取消/错误、工具详情、文件审批/预览、Project导航、Markdown与大字/Reduce Motion。UI使用生产链路+可控Provider，不代表真实模型/系统服务。为规避MCP300s等待限制，长UI使用相同prepared products的xcodebuild test-without-building，日志和summary保留。

真实host公开搜索探针：Bing200结果实际是/ck/a?u=a1<base64>包装链接；旧解析器排除所有bing.com链接会丢掉正常来源。补按真实形态解码、HTTPS/公网校验和回归，未跟随tracking；DDG Lite也返回200非challenge。Host探针不替代Simulator生产adapter实时验收。增加单独live-service测试入口，Tavily只在0600临时配置读Key，CLI/.xctestrun仅传配置路径，结束后删除。

已有真机交付产物的codesign/profile均含WeatherKit和HealthKit；profile有效期2027-08-31。不能据此确认App ID在线服务或Weather/Music真实请求成功；hwf仍unavailable。原生live/guest签名验收等待连接。当前源码新build成功，48 suites最终回归在执行（新增Web evidence含Loop重复/失败后回答，Bing包装链接）。

FC1真实Simulator Web测试：5 tests，4 passed/1 failed，0 skips。Bing英文/中文、DDG英文+中文、Tavily英文+中文均经生产SearchService/adapters真实联网通过；0600临时测试Key配置已删除。受限Swift.org页面失败redirectLoop，追到HTTP request使用URL.path会丢末尾slash、解码reserved字符，导致/about/实际发送/about→自重定向。改percentEncodedPath/query，补slash/%2F/%0D%0A防header注入回归；须重跑真实fetch，不把这一失败算服务通过。

FC2源审查发现file_edit只找generated byte root，不能修改已canonical导入TXT/Markdown，接入context.files+统一ByteReader并做Project/hash/批准后字节复核；旧版本不改。Import保存前重新确认目标Project仍存在，避免删除Project后的孤立File成功。PDF锁定明确报encrypted；修支持格式fallback文案。生成13份真实Office/EPUB/文本/扫描/混合/加密/损坏PDF夹具，新增49th Simulator suite含格式/字节/hash/隔离/修订/磁盘重开，编译/执行进行中。

FC2/FC3 当前构建包50 Simulator suites实际执行366/366 logical tests通过，0 skips/expectedFailures（参数化实例另计）。新FunctionalFiles suite覆盖9种真实格式、扫描/混合PDF、加密/损坏、删除目标Project、导入TXT修订/旧字节/外域拒绝及磁盘重开；新FollowUp suite覆盖实质输入/实际模型/无工具/512输出预算、无效JSON无模板、去重/长度、metadata/独立usage与取消。真实模型建议质量仍需DeepSeek。新UI15项（内容追问仅填Composer、独立磁盘relaunch）待执行。

受限网页实际重跑fc1-live-fetch-fixed.xcresult：1/1通过，Swift.org抓取正文/hash/source真实验证。之前4/5Web包保留失败，修复后单项证据分开，不合称新5/5整包。Tavily live验收已通过，允许Settings显式选择这个已有adapter，免费默认DDG不变，不内置Key。

原生按需默认发现（保留已有bindings）、capability保存失败可见、当前不可用工具仍可在设置看到具体原因已进入源码；Weather错误追加原NSError domain/code利于签名/服务定位。用户设备验收仍未完成，不能称Weather/Music真实可用。

Memory质量实际复现：fc3-memory-recall-suite-before.xcresult 13 logical tests/11 passed/2 failed，零skips。同义/跨语言偏好、整句中文都被旧keyword硬过滤漏掉。改为NaturalLanguage分词做lexical ranking，所有可见且作用域正确的已确认记忆仍可作为候选，由Compiler唯一1200字符预算决定实际入选；不引入向量库/额外模型请求。这能保留少量通用偏好，不保证超预算大量记忆的跨语言语义排序；后续验证这一边界。此前函数selector执行0 tests明记未验证，未算通过。

FC3新UI首次执行2项：内容追问/点击只填Composer通过；磁盘relaunch失败为历史Button selector误查找并误折叠Daily。导出的AX树已出现持久化正文和追问；只读SQLite确认1个Chat、1个user+1个assistant及Run记录，非数据丢失。历史行增加稳定accessibility ID、改selector，并补已保存追问重开一致性断言，当前重跑。失败xcresult/AX/录屏保留。

FC4 Bluetooth生产Service生命周期和原生adapter合同实际18/18、0 skips/expected通过。覆盖已授权新manager的unknown初始化等待、permission waiter取消及随后重试、cancel-before-scan、旧scan timer不能停止下一scan和蓝牙关闭终止扫描。manager边界可控，不能替代真实硬件扫描。首次泛型Void推断编译失败已补明确continuation类型；当前稳定build-for-testing成功74.4秒，零警告/错误。清单现51 Simulator suites，3 signed-device suites；新增真实Simulator guest探针作为第二个显式live suite，尚未编译/执行。

FC5新增P0候选FC-FS01：generated/managed/attachment字节路径仅字符串前缀校验，Project父目录符号链接可能重定向到另一Project。建立真实磁盘父目录link读取/写入/删除回归，先运行旧实现复现，再修统一路径边界；不只用虚构metadata证明隔离。

FC5真实磁盘负向包3/3失败、8条断言复现跨Project字节读取/改写；修复后文件隔离/多格式/版本/正式磁盘升级相关38/38 logical tests通过（48个参数化实例）、0 skips。统一FamiliarFilePath检查内部父目录link，保留真实系统祖先alias；read/write/managed capture/delete及Attachment路径已接入。证据fc5-path-before与fc5-files-isolation-fixed均保留。

FC6真实Simulator guest冷/热准备、Python/SSL和中文输出首次1/1通过。随后增加原生字节PTY bridge、执行所有者继承/清理、readonly基础root、Project HOME/tmp、canonical原始文件投影以及底层16进程/512MiB/128MiB文件/1MiB输出约束。arm64 device与Simulator XCFramework实际重建；未开放Terminal UI，不能称完整Terminal通过。旧writable guest base保留，新scoped base不读取旧home/tmp。新增patch仍须补供应链hash记录和最终执行证明。

FC6真实负向包fc6-scoped-pty实际4 tests/1 passed/3 failed、0 skips。内存、文件、进程限制以及init保护/不存在process group用例正常运行；超长无换行输出标志/内容丢失、重挂init的sleep未及时停止导致guest明确failed并阻止后续执行，PTY因此未通过。修复Producer仅在cancelled终止时取消、反复唤醒pending KILL的host线程，以及在终止前提交有界partial line；新构建/复跑继续。失败不能用编译替代；仍先保持不开放终端入口。

FC4额外源审查发现Bluetooth UUID未验证就传CBUUID，有非法输入触发Objective-C异常的风险。新增ASCII hex/完整UUID校验，preflight与生产service在创建manager/请求权限前拒绝；新增参数化回归，尚待编译/执行。待办另记录Clipboard只保存旧文本导致非文本数据丢失/Undo覆盖后续内容，以及Files删除先移动字节再保存metadata的强杀恢复边界，均作为P0验证/修复。

当前下一切片：完成FC6受控guest/PTY真实回归 → 修Clipboard/本地文件删除恢复P0 → 接入并真实操作完整Terminal入口 → 其余Skill/MCP、全入口走查和最终全量回归。FC4签名原生服务、DeepSeek真实质量、广泛Provider/OAuth和硬件仍未验收；hwf unavailable。未提交/推送/清库。

FC3最新复验（2026-10-08）：fc3-native-discovery-unit.xcresult实际368 tests/367 passed/1 failed、0 skips/expected；唯一失败Timeline原1秒阈值实测1.035秒，未改阈值。当前稳定源码重新build-for-testing成功20.1秒，fc3-focused.xcresult实际31/31、0 skips，100/300布局峰值0.334/0.595秒；Memory质量新用例和原生adapter合同通过。原失败证据保留，不把focused复验写成新全量368/368。新增两项生产UI追问/磁盘重启正在执行。Signed Native六项真实服务探针已编译，hwf unavailable，尚未执行；Weather/Music不能判通过。提前退休本任务旧prepared products约213MB，保留xcresult/summary/log，不动其他项目或用户数据。

### 2026-10-08 阶段收尾与安装切片

用户将当前切片收尾，要求保留终端真实入口并安装 hwf；随后授权所有当前改动按模块分别 commit 并 push。仍在 main；不清空数据库或 Keychain。

- [x] FC6 sliced host nanosleep 修复 pending KILL 无法及时结束 guest sleep 的根因。真实 guest 包 `fc6-sliced-sleep.xcresult` 实际 4/4、0 failures/skip，通过资源限制/无换行输出恢复、冷热 Python/SSL、Project HOME/tmp 隔离、reparented child 清理及真实 PTY 输入/resize/中文 ANSI/Ctrl-C/Ctrl-D/Agent busy。
- [x] Clipboard 拒绝后零写入、完整非文本 checkpoint、revision 冲突/重复/Undo 保护；真实 Simulator PNG Undo 和 Bluetooth 输入/生命周期、独立 PTY 回归包 `fc4-clipboard-pty-isolated` 实际 11 logical/16 instances 全通过。不能替代蓝牙硬件或 signed 原生服务。
- [x] 原生 bridge、资源限制/隔离 patches、两片 arm64 XCFramework 实际重建，供应链 manifest 新增本地源/patch/二进制 SHA-256；verify-ish-supply-chain 实际通过。
- [x] 新增生产 `More → Terminal` 页面、本地打包 xterm 6.0.0/fit 0.11.0/unicode11 0.9.0、真实 raw-byte PTY 输入及 resize、辅助键、命令字段、Start/Stop、Project HOME、默认禁网、页面离开/后台停止。仅显式 Start 准备环境；人工许可不构成模型工具授权。
- [x] hwf 当前源码签名 build、codesign deep/strict verification 与覆盖安装成功；启动结果单列。
- [ ] 终端生产 UI/手工交互验收：自动化 worker/AX 超时，用户已停止 Simulator 验证。
- [x] 六个功能/回归提交已推送 origin/main；收尾文档提交记录最终安装结果。

本次交付不代表 Functional Convergence 完成。后续仍需 Files/Project 删除阶段移动字节后的强杀恢复、FilePresentation 缺 metadata/分享前字节一致性、完整手工 Output 显式发布回执、Agent 日志只读终端、终端广泛全屏程序/软键盘验收、全部 Native signed 服务与硬件、DeepSeek/其他 Provider/OAuth、Skill/MCP、FC7/FC8 和最终 Release Gate。正式磁盘迁移已有实际回归，不将一次真机安装等同覆盖安装/强杀完整验收。

按用户最新指示停止所有 Simulator 验证，仅进行 hwf 安装与收尾推送。`fc6-terminal-ui` 在 preparing execution worker 超时，没有执行测试体，不能算 UI 通过；普通启动已成功，但 snapshot remote automation session 也超时，未获得终端操作证据。Simulator 已关闭。保留此前真实 guest/PTY 4/4 结果，生产终端 UI/真机手工交互仍须用户验收。首轮 hwf build 失败未输出明确 error，保留日志；当前串行重跑带 xcresult，不能用首轮残留产物安装。

hwf `hwf-terminal-build-retry.xcresult` 实际 BUILD SUCCEEDED，codesign --verify --deep --strict 通过。`hwf-terminal-install.json/log` 确认 devicectl 成功覆盖安装 com.isaachuo.familiar；本次没有清空 App 数据/Keychain，也没有执行生产 Provider/原生服务工具。完整终端手工交互和其余 Release Gate 保持待验收。

hwf devicectl 启动成功，未带测试参数，生产进程 PID 6780。安装/启动均返回 success；该证据证明交付与启动，不代表已在真机执行终端命令或验证 Native 服务。

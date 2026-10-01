# Familiar 产品收敛与 Agent Harness 长期计划

最后更新：2026-10-01。此清单跨对话持续维护。

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

**B1、B2、C1、C2、C3、C6 与 C7 的实现／静态／编译验证已完成；下一个切片是 C4 网页长期保存显式化。** 运行测试与真机验收仍独立待办。写入 journal、失败补偿和不可重复撤销的机制已接线；仍不能将外部系统写入与本地保存称为跨进程原子事务。

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

- [ ] B3.1 系统策略围绕最低必要复杂度、直接回答、按需工具、真实回执与失败诚实表达，不预设任务的阶段。
- [ ] B3.2 保留首字节前有界 Provider 重试、独立 read 最多并行两路、write 不自动重放、预算耗尽收尾。
- [ ] B3.3 清理无生产调用的 CapabilityResolver/Catalog/Grant 路径，保留唯一实际授权路径。持久数据结构的删除必须先确认引用和数据影响。
- [ ] B3.4 不新增跨重启续跑、后台执行或 Plan 调度器。启动恢复继续把未完成 Run 明确终结，并保留已取得结果。
- [ ] B3.5 不增加任务 Router。现有 Provider group fallback 仅负责用户所选模型服务；本地模型的未接通路径退出生产调用图。

## C. 核心数据与输出可靠性

- [x] C1 Memory 必须落盘成功后才发成功 ToolResult；落盘失败回结构化失败，不能让 UI／模型看到“已记住”。
- [x] C2 将必要的 Artifact、Skill、Environment 结果提交纳入成功边界；核对 commit 后保存失败时的回滚与 Undo，避免重试重放已发生的外部写入。
- [x] C3 发送前检查 Project 受保护上下文预算；拒绝发送时保留草稿和附件，不先提交消息再失败。
- [ ] C4 网页抓取默认只保留聊天和 Run 证据；用户明确“保存到项目”后才成为长期 Resource，不再次抓取，保留 URL／时间／hash／截断来源。
- [ ] C5 默认交付 Markdown/纯文本。DOCX/PDF/XLSX 等复杂生成和 Shell 需高级显式启用，真实 guest 验收前不作为默认完整能力。
- [x] C6 Artifact 修订生成独立版本，删除原位覆盖历史的 edit 路径；预览、分享、删除与 Undo 对齐真实文件和元数据。
- [x] C7 Memory 使用时间只标记最终进入冻结上下文的条目；诚实说明关键词检索与 frozen selection 的边界。
- [ ] C8 顶栏模型、Project override、Provider group 实际执行模型与用量展示一致。
- [ ] C9 覆盖保存失败、取消、拒绝、权限缺失、附件清理和跨重启历史回放；当前测试与真机分别记录。

## D. 全 App 信息架构与视觉统一

本阶段是用户优先指定的 UI 交付；在核心阻塞修复后开展，按页面族逐批完成。

### D1 信息架构

- [ ] D1.1 Chat 保留历史／Project 切换、有效模型、输入器、新对话和会话操作；移走 Diagnostics 等执行层快捷入口。
- [ ] D1.2 Project 主页面保留指令、资料、输出和聊天；Environment、Skills、MCP、Capability、Run 审计进入 Project 的高级页。
- [ ] D1.3 Settings 主层按模型与回复、外观、隐私与数据、支持组织；执行限制、工具目录、环境、软件源、MCP、技能和诊断集中高级页。
- [ ] D1.4 语音配置只有一个管理入口；模型分组退出普通设置首屏。Memory 管理与授权撤销保持可发现。
- [ ] D1.5 使用用户可理解的标题和错误文案；技术名、参数、hash 放入展开详情／审计，不作为普通界面的主信息。

### D2 设计系统

- [ ] D2.1 复用 FamiliarTheme/Typography/Spacing/Radius/Motion，统一规则，不创建另一套主题。
- [ ] D2.2 标题、正文、辅助信息、元数据、按钮使用语义字体；Dynamic Type 同时影响文本和布局测量。
- [ ] D2.3 内容间距采用现有 4/8/12/16/20/24；圆角采用现有 10/14/18/24；系统组件由系统管理，图标触摸区至少 44pt。
- [ ] D2.4 主／次／破坏按钮明确一致；自定义图标按钮共享按压与可访问性规则；不再逐页面发明阴影、描边和动画。
- [ ] D2.5 表单与列表优先原生 Form/List/LabeledContent/Menu/NavigationStack；sheet 由有身份的展示状态持有，明确关闭／保存动作。
- [ ] D2.6 Liquid Glass 用于导航与浮动控件，正文／工具结果用清晰内容层；保留 iOS 18 和降低透明度回退。
- [ ] D2.7 Markdown CSS 的颜色、代码、引用、来源和正文尺度与 SwiftUI 语义一致，清理旧的独立配色。

### D3 组件与页面验收

- [ ] D3.1 Chat 顶栏、抽屉、空态、Composer、附件、相机、输入预览统一。
- [ ] D3.2 Message、Thinking、Tool Result、Sources、Failure、Approval、Undo、Artifact/Share 回执统一；工具结果默认紧凑展开，审批默认仅这次。
- [ ] D3.3 Project 列表、编辑、资源详情、输出版本、预览分享统一。
- [ ] D3.4 Settings 所有主页面及高级子页统一，包括模型／语音／Memory／权限／存储／锁定／审计／About。
- [ ] D3.5 HTML、Markdown、Code、Diff、Records、Mermaid 全屏详情遵循相同导航和关闭规则。
- [ ] D3.6 删除只在 fixture 出现的旧 ToolChips 展示树；fixtures 复用生产组件，不为测试维持另一套 UI。
- [ ] D3.7 更新中英文文案、错误与本地化 parity。构建通过后单独列出待真机检查的页面，不声称视觉验收完成。

## E. 性能与维护面

- [ ] E1 流式 delta 只影响当前回复，避免反复构建全量 timeline、历史 projection 和无关设置。
- [ ] E2 评估长会话的 eager VStack／WKWebView 数量和排序成本；按实际测量选择懒布局，不盲目添加缓存。
- [ ] E3 保留 Markdown 现有流式合并／节流；核对大表格、代码和图表的渲染、布局与内存。
- [ ] E4 核对文件解析、图片缩放、Skill archive、hash 与磁盘 I/O 的 MainActor 开销；仅在证据支持时移动工作。
- [ ] E5 排查现有语音未使用变量与 OAuth 并发 warning；不把源码疑点写成已经发生的性能故障。
- [ ] E6 清理确认无生产引用的类型、入口和本地化；保留研究／Mac 目录，禁止为了 iOS 收敛扩展 macOS 产品。

## F. 验证与完成门槛

### 实现侧

- [ ] F1 当前测试清单反查所有 suite；补齐 ImportContracts、GroupBoundary、ExecutionContract 等遗漏。真机 guest suite 单列，Simulator skip 不能算 guest 通过。
- [ ] F2 新增决定行为的回归用例，避免只镜像实现的字符串断言。
- [ ] F3 每个切片完成 git diff --check、相关 plist／strings 检查和单次 arm64 Simulator build-for-testing。
- [ ] F4 编译、测试执行、真实服务、真机视觉、签名发布证据分列；禁止“全量通过”包含未运行或跳过项。
- [ ] F5 CURRENT 描述实际实现、问题与下一阶段；ARCHITECTURE 描述真实模块边界；OpenMinis 对照表仅作历史迁入记录。

### 所有者真实验收（分别勾选）

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
- 下一项：B2 从 Registry/ContextSnapshot/Loop 的一条生产链路实现工具组懒加载，不另加 Router。

### C1：Memory 成功边界

- 实现：Memory 保存移入 Run 的 persistResult 成功边界；Controller 保存失败回滚并抛回 Loop，成功事件与模型结果在实际保存之后产生。取消／拒绝不会走保存。工具审计与 model-facing 结构化失败复用同一错误内容。
- 验证：新增保存失败无成功回执、数据可见先于成功事件两个回归用例；全部测试目标编译。最终增量 build-for-testing 返回 TEST BUILD SUCCEEDED，日志 `/tmp/familiar-harness-c1-final-20261001-build.log`。
- 静态：git diff --check、中英文 strings plist 检查通过；未修改本地化键集合。
- 边界：测试未执行、无真实 Provider／真机结论；Environment 等其他提交的可靠性仍留 C2。所有真实验收项保持未勾选。

### B2：Lazy Tools

- 实现：统一工具组、默认能力和 base 规则，删除重复分类／core 例外表。首轮只有 current_date_time/ask_user/tools_load；允许目录与实际暴露集合分开冻结。最多两组按需替换，未在本轮出现的名字（包括与 loader 同批猜出的名字）不能执行。
- 范围：默认 Web、日历提醒、地点天气／必要位置、文件读取分享、文本 Artifact 和已启用 Memory；Skill 读取只看到冻结候选与本 Run 确认安装的数据。复杂生成、Shell、其他 native 和展示工具需显式配置；既有显式选择仍有效。首个 capability 修改按当前默认值保存其余工具，避免意外开启高级能力。
- MCP：只在请求服务组时发现，每 Run 缓存；32 条描述分页、最多 16 个精确选中的 remote schemas。审批保留高风险／仅这次，并明确显示服务器、实际操作及参数；不会把远端只读声明当作授权。
- 安全／预算：加载不授权；Group/Project/Skill 范围和实际 capability 检查仍在 Swift。参数 Schema、load report、所有调用尝试计入相应预算；写入指纹在实际执行前检查，防同批重复。成功加载的 manifest snapshot 在成功事件前保存。
- iSH：启动只检查 bundled assets；真实操作共享一个准备任务。取消单个 Run 的等待不会启动它的命令，也不拆掉共享安装／启动；后台私有准备可能继续完成。真实 guest 的系统边界仍待设备验收。
- 验证：最终原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-harness-b2-verified-20261001-build.log`。App／扩展／所有测试目标编译完成，14 项 LazyTool 用例已编译；测试未执行、Simulator 未启动、未调用真实服务或 guest。
- 静态：git diff --check、release-test script 语法、两份 strings plist 与 973/973 key parity 通过。目录实际 55 无条件 + 2 bundled-asset 条件定义，最多 57；这不等于模型收到 57 个 Schema。
- 后续状态：C2 的提交边界、C3 草稿安全已由下方切片完成实现／编译；B3 的无生产调用路径审计、D 的全 App UI 统一未完成。真实模型的组选择效果、延迟、MCP 服务和 guest 取消仍未验收。

### C2 / C6：提交成功边界与独立 Artifact 修订

- 提交：willCommit 在任何动作调用前保存 committing invocation；本 Run 同时保留“已尝试写入”的精确参数指纹，提交或保存失败后不盲目重复。中断恢复保留 committing 作为不确定结果，不再假定它已取消。
- 保存：Environment receipt、原生 durable Undo、Artifact、Skill 和 Memory 的必要保存处于成功事件之前。Skill 的文档、package hash 与 Project binding 合为一次保存；内容地址资源可以作为不可见缓存保留，不会因此成为已安装 Skill。
- 本地补偿：CommittedAction 的 rollback 只恢复本地数据，finalize 只在保存成功后清理旧目录。Environment 保留旧目录直到 receipt 保存成功；保存失败恢复旧目录。外部／原生动作不会在后台被自动撤销。
- Artifact：编辑保存新 ID／独立目录／同 lineage 的下一版本，原始文件保持不变；发布／写入保存失败只删除本次新文件。前驱必须存在且属于同一 Project；获取版本失败不能静默从 v1 重来。删除／Undo 先暂存目录，数据库失败恢复它，成功后清理。该根因修复同时完成 C6 的实现部分。
- Undo：成功的原生撤销结果缓存到元数据保存完成，保存重试不再重复操作。持久 Undo 在调用前标为 unavailable，进程中断后不自动重放；当前会话保存失败仍可凭缓存补齐记录。失败的提交保留实际可用的会话 Undo；多次点击受执行中检查保护。
- 历史：包含已提交或不确定操作的消息编辑／重新生成／失败 Run 重试被拦截，保留原记录，要求先检查结果并发送新的后续消息。纯读取仍可重新生成。
- 验证：原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-commit-c2-verified-20261001-build.log`。12 项 CommitBoundary 新用例及既有目标仅编译，未执行测试、未启动 Simulator、未进行真实系统／guest 验收。
- 仍有边界：系统动作成功后立即杀进程，可能只有提交 journal 而没有完整结果／Undo；它阻止盲目重放，不能证明动作的最终状态。中断的 Environment 本地 swap 可能保留备份；自动跨重启补偿／续跑不在本切片。真机磁盘不足、强杀窗口、权限变化和 Undo 视觉仍需所有者验证。
- 后续状态：C3 已完成下方发送前检查切片，拒绝发送保留草稿；当前下一项为 C4 网页保存显式化。

### C3 / C7：发送前预算与草稿安全

- 发送：先按 Project override 解析模型并检查凭据／文档能力，冻结历史、Project／Skill scope、原生目录与 MCP discovery closures。只读准备上下文，不创建 Conversation、Message 或正式附件文件。
- 预算：检查受保护 Project、系统提示、基础 Schema 与最新用户消息／附件的合计；旧历史仍可由已有 Loop 压缩。文本模型使用 Apple Vision 后再次检查证据，不把不可容纳的图片结果先提交给历史。
- 文件：发送前预定消息 ID 和最终附件路径，图片从草稿路径读；通过后复制并保存，Run 复用同一个已验证 Snapshot。缺失图片不再静默降级为空内容。
- 草稿：检查取消和准备期间的草稿变化；正式提交失败回滚 SwiftData 并清理本次复制文件。文本、原附件、原图片和 Skill 只在提交保存成功后消耗。后续网络／Provider 失败仍属于已接受消息的 Run 失败，不等同于本地拒绝提交。
- Memory：移除无生产调用、会提前保存 usage 的旧 search 入口；候选为只读关键词匹配。Compiler 的 1200 字符预算决定最终 ID，lastUsedAt 与已接受消息同一次保存；超预算候选、被拒绝的准备和回滚不会提前更新使用时间。memory_search 仍只搜索本 Run 的冻结选择，并非语义检索全库。
- 验证：原工程 Debug arm64 generic iOS Simulator build-for-testing 返回 TEST BUILD SUCCEEDED；日志 `/tmp/familiar-send-c3-verified-20261001-build.log`。9 项 SendPreflight 用例与改后的 Memory scope/usage 用例已编译，未执行测试、未启动 Simulator。覆盖合计预算、历史压缩保留、Schema、Vision 证据、暂存图片读取、最终文件路径、缺失图片以及实际 Memory usage/rollback。
- 静态：git diff --check、release script 语法、两份 strings plist 和 980/980 key parity 通过。拒绝提交保留草稿的 Controller 路径有源码／编译证据，未取得签名真机运行证据；磁盘不足、取消、图片识别及真实模型仍待验收。
- 下一项：C4 Web 抓取默认只进入聊天／Run 证据；用户明确保存后复用已抓取内容成为 Project Resource。

未勾选的 B3–F 项仍待实施。所有真机／真实服务验收仍未完成。

# Familiar 深度产品与架构评估

评估日期：2026-08-13  
评估对象：[`IsaacHuo/Familiar`](https://github.com/IsaacHuo/Familiar)，`main` @ [`1ed7e67c`](https://github.com/IsaacHuo/Familiar/commit/1ed7e67c311854390cf35d3042338d5f121bfd42)  
对标对象：[`OpenMinis/OpenMinis`](https://github.com/OpenMinis/OpenMinis)  
结论性质：基于仓库、文档、近期提交和用户提供的 ChatGPT「项目」参考截图进行的产品、架构与工程评估；未进行 Familiar 真机交互审计。

### 后续实现补记

本报告正文的“当前”均指 `main @ 1ed7e67c` 的历史快照。报告完成后，`530e72a` 已加入只读 Web，因此 `main @ f4ab809` 有 8 个启动时静态注册工具，新增 `web_search`、`web_fetch` 与 Sources；Web 不再是“未实现”，但 Project URL Resource、独立 reader、浏览器交互和项目绑定仍未实现。`Docs/08`、`Docs/09` 也已存在。后续计划已据此消化正文中的旧快照事实，不改变“Project 优先、停止扩入口、先补可验证内核”的主结论。

## 一、结论

Familiar 已经超过普通聊天壳：多 Provider、流式协议适配、本地附件处理、EventKit 工具、审批、Run/Step、Share Extension、App Intents、Spotlight、通知和 Widgets 都有真实代码。当前最准确的阶段是：**具备 Agent Runtime 骨架的 iOS 原生原型**。

它还未达到个人 AI 工作台，也没有形成可扩展平台。核心原因在于四个被文档定义为核心资产的模块仍很浅，继续丰富界面解决不了这一点：

1. `Capability Registry` 是启动时写死的 6 个工具数组，距离可发现、可安装、可绑定、可治理的能力层很远。
2. `Agent Runtime` 是可靠的有限 Tool Loop，但还不具备上下文装配、并行工具、恢复、真正重放、预算控制和评测闭环。
3. `Execution Policy` 只有 effect/risk/availability 的初始规则，文档所说的“意图感知授权”尚未贯通生产路径。
4. `Native Workspace` 目前主要是“附件抽取文本后进入聊天上下文”，缺少项目、资源、工件、可写文件和作用域。

最重要的战略调整是：

> **把 Familiar 定义成“原生、安全、可检查的个人 AI 工作台”，项目是第一层工作单元，聊天只是入口，原生工具 + Web + 远程 MCP 是执行面。**

不要追赶 OpenMinis 的 Linux/Shell 广度。Familiar 的胜点应是更小的攻击面、更强的 iOS 语义、更清楚的授权、更稳定的项目上下文和更可理解的执行记录。

## 二、事实基线

### 已有成果

- 12 个内置 Provider、自定义 OpenAI-compatible Provider，覆盖 OpenAI Chat、Anthropic Messages、Gemini 三类适配。
- 本机时间、App 信息、日历查询/创建、提醒事项查询/创建，共 6 个静态注册工具。
- 统一 Runtime Event、最多 6 轮的 Tool Loop、重复调用保护、参数/结果长度限制。
- 可逆写入提案、确认协调器、进程内幂等与一次性 Undo。
- SwiftData 会话、消息、附件、Agent Run/Step 终态。
- AnyDoc、PDFKit、Vision OCR、文件导入、Quick Look、Speech 文本转写。
- Share Extension、Deep Link、App Intents、通知、Spotlight、Widget/Control。
- 基础单元测试与 UI 冷启动冒烟测试。

### 近期改动说明了什么

从 Agent Runtime 架构文档提交 [`0cf18a0d`](https://github.com/IsaacHuo/Familiar/commit/0cf18a0dcb1d4773f8d7b230eb642524d2d37101) 到当前 `main`，仓库在 16 个提交中修改了 85 个文件，约 `+5,834/-1,018` 行。改动同时铺开 Runtime、设置、分享、Deep Link、Intents、通知、Spotlight、Widgets、测试和文档。

这证明执行速度很快，也暴露了当前主要问题：**系统入口和展示面扩张快于能力内核**。文档开发顺序把 Web/Maps/Weather 放在系统入口之前，但实际是入口基本做完，Web、Memory、Skills、MCP Client、Background 仍未实现。

## 三、当前架构的真实成熟度

下表是启发式工程判断，不是测试分数。

| 维度 | 当前状态 | 判断 |
|---|---|---|
| 原生聊天与输入 | 中等 | 已形成可用 App 骨架，附件、语音、富文本链路较完整 |
| Provider 层 | 中等 | 适配面广，真实 Key、真实流式和真实工具调用验收仍不足 |
| Agent Loop | 初中级 | 有边界、有事件、有错误处理；缺少恢复、预算和复杂任务策略 |
| Capability Registry | 初级 | 类型化基础正确，但工具集合完全静态，能力元数据太少 |
| Execution Policy | 初级 | 有审批和风险字段，尚未形成授权凭证、来源、范围、期限模型 |
| Native Workspace | 初级 | 能导入和抽取，不能作为长期、可写、项目化工作空间 |
| 项目/长期上下文 | 未实现 | 当前根对象仍是 Conversation |
| Web / MCP / Skills / Memory | 未实现 | 设置页和文档已有预览或计划，Runtime 尚未接通 |
| Background / 已计划 | 未实现 | 当前只有终态通知，不保证离开 App 后继续执行 |
| 工程验证 | 初中级 | 有测试目标，但没有 iOS CI；大量真机与真实 Provider 路径未验收 |

综合判断：**产品骨架约完成，平台能力尚未成型。** 用户感到“差强人意”是准确感受：界面已经暗示工作台，系统现在真正能完成的仍是聊天、文档问答和有限 EventKit 闭环。

## 四、四个核心资产的问题

### 4.1 Capability Registry：名字正确，能力模型不够

[`FamiliarAppDependencies.swift`](https://github.com/IsaacHuo/Familiar/blob/main/Familiar/App/FamiliarAppDependencies.swift) 在初始化时直接注册 6 个工具。Registry 能根据 EventKit 权限隐藏不可用工具，这是有价值的第一步；但“动态”目前只代表权限可用性，不代表运行时发现、安装、启停、项目绑定和远程工具接入。

建议把 Tool Manifest 升级为稳定协议，至少包含：

- 稳定 ID、版本、来源（native / web / MCP / skill）。
- 输入/输出 Schema 与最大载荷。
- effect、risk、数据域、网络域、隐私标签。
- 是否幂等、是否可取消、是否可恢复、是否支持并行。
- 所需系统权限、用户授权、项目作用域。
- 展示元数据和审计字段。

Registry 应从“字典”升级为 `CapabilityCatalog + CapabilityResolver + CapabilityBindingStore`。

### 4.2 Agent Runtime：能循环，还不能承担工作台任务

[`FamiliarAgentLoop.swift`](https://github.com/IsaacHuo/Familiar/blob/main/Familiar/Agent/FamiliarAgentLoop.swift) 已处理流式文本、增量 Tool Call、重复调用、审批、结果回填和终止边界。这部分方向正确。

主要缺口：

- 没有项目级 Context Assembler；每次请求主要由系统提示、历史消息和附件文本拼接。
- 工具按顺序执行，没有独立的并发/依赖规划层。
- Run/Step 保存终态和摘要，缺少完整输入、输出引用、模型请求、授权凭证与恢复游标，当前不能实现严格意义的重放。
- 失败恢复主要是把 error 作为 tool result 交回模型，没有重试策略、错误分类、预算或降级计划。
- 没有 benchmark runner；文档列出的 8 个 Benchmark 还不是可执行回归测试。

建议先做可恢复的单 Agent，不要增加 Planner Agent。核心接口应是：

```text
RunRequest
  -> ContextSnapshot
  -> CapabilitySnapshot
  -> AuthorizationSnapshot
  -> ordered RuntimeEvents
  -> Artifact/Result references
  -> ResumeCursor
```

### 4.3 Execution Policy：文档领先于代码

[`FamiliarExecutionPolicy.swift`](https://github.com/IsaacHuo/Familiar/blob/main/Familiar/Agent/FamiliarExecutionPolicy.swift) 当前逻辑是：低风险读自动执行；权限可申请的读需要确认；破坏性/高风险操作确认；可逆写入只有匹配 one-shot authorization 才自动执行。

问题有三点：

1. 生产 Agent Loop 没有传入 `FamiliarOneShotAuthorization`，所以“明确可逆写入直接执行 + Undo”的设计没有落地。
2. one-shot authorization 的来源枚举包含 Share Extension、App Intent、Deep Link，但这些入口在文档中又明确“不授予工具权限”。这个类型设计容易在未来被误接。
3. “用户明确意图”不能只依赖 LLM 判断或入口来源，需要由运行时生成可审计授权。

建议用 `AuthorizationGrant` 替代当前 token：记录 user action、source、capability、arguments hash、project scope、expiry、single-use 和 confirmation evidence。系统入口只提供输入来源，默认永不提供写授权。

### 4.4 Native Workspace：现在是附件管道，还不是 Workspace

当前文档导入能力是有效成果，但 Workspace 至少还需要：

- 项目级资源目录与稳定资源 ID。
- 原文件、抽取文本、预览、派生工件之间的 lineage。
- `resource.read/search/list` 与受控 `artifact.write/export`。
- 资源版本、来源、访问范围和删除语义。
- 统一支持 Share Extension、Files、Photos、URL、扫描内容和 MCP Resource。

在没有这些对象前，“PDF 问答”仍是一次性上下文注入，无法支撑长期个人工作台。

## 五、项目应该成为 Familiar 的核心对象

用户提供的 ChatGPT 截图里，“项目”解决的是聊天、文件和工具的一站式组织。Familiar 可以采用这个目标，但数据模型要先于侧栏入口。

### 推荐定义

> **Project 是一个长期、可恢复、有边界的 Agent 工作上下文。**

项目至少包含：

| 对象 | 作用 |
|---|---|
| Project | 名称、说明、图标、状态、默认模型 |
| Conversation | 项目内的多条对话；普通聊天可不属于项目 |
| Resource | 文件、URL、图片、文本、MCP Resource |
| Artifact | Agent 生成的 Markdown、表格、摘要、导出文件 |
| ProjectInstruction | 项目持续指令，与全局系统提示分开 |
| CapabilityBinding | 项目可使用的原生工具、Web、MCP 连接 |
| SkillBinding | 项目启用的 Skills 及其 tool scope |
| MemoryItem | global / project / conversation 三种作用域 |
| Run / Step | 执行记录、审批、失败、产物与恢复游标 |
| Schedule | 用户明确创建的计划；记录系统是否能保证执行 |

建议关系：

```text
Project
├── Conversations
├── Resources -> derived Artifacts
├── Instructions
├── Capability / Skill bindings
├── Project Memory
└── Runs -> Steps -> approvals / artifacts / errors
```

每次发送消息时由 `ProjectContextAssembler` 生成不可变 `ContextSnapshot`，记录本次实际使用了哪些文件、记忆、技能、工具和授权。这样才能回答“Agent 为什么这样做”和“下次如何恢复”。

### 信息架构建议

不要直接复制截图中“库 / 项目 / 插件 / 已计划 / 远程 / 图片”六个同级入口。它清楚，但把实现类别暴露成了主导航，后续会越来越重。

Familiar 的侧栏建议只保留：

1. 新聊天与搜索。
2. 项目（置顶项目 + 全部项目）。
3. 最近对话。
4. 运行与计划（只有能力真实可用后出现）。
5. 设置。

“原生工具、Skills、MCP、Provider”合并到一个**能力中心**；“文件、图片、URL、工件”主要出现在项目内部。这样全局导航按用户任务组织，项目内部按工作材料组织。

### 截图方向简评

- 侧栏结构一眼可发现“项目”，这是值得借鉴的优点。
- 项目空态目标和主动作明确，适合 Familiar 第一版。
- “远程”含义不清；对 Familiar 应改成“连接”或放进能力中心。
- 底部独立搜索项目会与全局搜索重复；有项目数据后更适合统一搜索并提供项目筛选。
- 截图不能证明 Dynamic Type、VoiceOver、焦点顺序和可点击区域，需要真机验证。

## 六、与 OpenMinis 的差距及应对

OpenMinis 官方仓库明确提供设备内 Linux shell、浏览器自动化、Skills、持久 Memory、Workspaces、系统集成和 Native Offloads；源码还包含 MCP Store/OAuth、Skill Store、BrowserUse、Background、File Provider 和大量 Native Offload。

| 能力 | OpenMinis | Familiar 当前 | Familiar 推荐策略 |
|---|---|---|---|
| 通用执行 | Alpine/iSH、脚本和包 | 无 Shell，明确排除 | 不追；保持受控原生与远程工具 |
| iOS 系统能力 | Health、Calendar、Contacts、HomeKit、Location 等 | Calendar/Reminders | 优先补 Weather、Location、Contacts、Photos、Maps |
| Web | 浏览器自动化 | 无 | 先做 search/fetch/read，再做受限交互 |
| Skills | `SKILL.md` + scripts/references/assets | 只有文档和预览 UI | 先做 instruction-only 可导入 Skill |
| MCP | Store、OAuth、导入、会话绑定 | 只有预览 UI | 做 Remote Streamable HTTP Client，不做本机 MCP Server |
| Workspace | 文件系统和 workspace URL | 只有 Conversation + attachments | 用 Project + Resource + Artifact 建立原生 Workspace |
| Memory | 跨会话持久 Memory | 未实现 | global/project/conversation 作用域，先结构化存储 |
| Background | 大量后台与 Live Activity 机制 | 终态通知 | 采用可恢复 Run；对系统限制明确降级 |
| 安全 | 沙箱 + 权限/offload 管理 | 类型化工具、审批、BYOK、本地优先 | 把可解释授权和最小权限做成核心差异 |

关键判断：**没有 Shell，Familiar 永远无法在长尾任务覆盖率上正面对等 OpenMinis。** 这不代表路线失败。Familiar 需要用安全、可解释、项目化和 iOS 原生体验换取差异化；越来越多的占位入口只会制造“看起来什么都有”的错觉。

## 七、Web、MCP、Skills、Memory 的正确实现顺序

### 7.1 Web：先只读，后交互

第一版提供：

- `web.search(query)`
- `web.fetch(url)`
- `web.read(url, selector/readerMode)`
- URL Resource 保存到项目

统一做 SSRF 防护、重定向限制、私网地址拒绝、大小/类型上限、来源引用和远程内容不可信标记。浏览器自动点击、登录和表单提交延后，因为它会显著扩大 Cookie、凭据、注入与误操作风险。

### 7.2 Skills：先做可移植指令包

第一版 Skill：

```text
skill.json / SKILL.md
├── metadata
├── instructions
├── allowedCapabilities
├── examples
└── optional references/assets
```

支持 Files/Share Sheet 导入、预览内容、明确安装、项目绑定、禁用和删除。暂不支持脚本。Skills 只能收窄 Tool Scope，不能扩大用户授权。

### 7.3 MCP：只支持远程 HTTPS

远程 MCP 已有 Streamable HTTP 与 OAuth 标准，适合 iOS Client。第一版应实现：

- URL 校验与 Server Identity。
- Initialize、capability negotiation、tools/list、tools/call。
- OAuth/PKCE 与 Keychain credential isolation。
- 工具 Schema 转换为 Familiar Manifest。
- 连接健康、超时、取消、分页和 server change detection。
- MCP 工具继续经过 Familiar Policy，不信任 server annotations。
- project/session binding，默认不开启全部工具。

不要支持本机 stdio MCP；没有受控进程宿主时，这会把产品重新拖向 Shell Runtime。

### 7.4 Memory：从作用域和可见性开始

先用结构化条目，不做向量数据库。每条 Memory 记录 provenance、scope、confidence、createdBy、lastUsedAt 和用户可见状态。自动写入默认关闭；模型提出候选，用户确认或由明确规则写入。

## 八、Background 与“已计划”的平台现实

文档把 `BGContinuedProcessingTask` 写成 iOS 18 路线，这是需要立即修正的事实错误：该 API 是 iOS 26+，并且承接的是用户在前台启动后需要继续的工作，不是可靠 cron。

推荐兼容策略：

- iOS 26+：可用 `BGContinuedProcessingTask` 承接用户启动的长任务，但仍需保存恢复游标并处理 expiration。
- iOS 18–25：`BGProcessingTask` 是系统择机执行，不能承诺精确时间；网络传输用合适的 background `URLSession`，Agent Run 仍要可中断、可恢复。
- 精确“每天 8 点自动执行 Agent”在无后端条件下不能做可靠承诺。优先接入 Shortcuts 自动化，或把计划设计成“系统允许时执行 / 到时提醒用户继续”。
- “已计划”页面必须显示执行保证等级：精确、尽力、需用户确认。

## 九、90 天路线

### 第 0–2 周：停止扩入口，建立可验证内核

- 冻结新 Provider、新 Widget、新系统入口和预览页。
- 将 Memory/Skills/MCP 预览移到 Labs，或暂时隐藏。
- 把文档 Benchmark 变成 8 个可运行场景，记录成功、工具序列、审批、耗时和成本。
- 增加 iOS build/test CI；当前 `.github/workflows` 只有 Pages。
- 修正文档事实：BGContinuedProcessingTask 版本、意图授权状态、缺失的 Docs 08/09 链接。

验收：每次修改 Agent 行为都能自动运行 fake-provider benchmark；真实 Provider 有手工 smoke checklist。

### 第 3–5 周：Project + Context + Workspace v1

- 增加 Project、Resource、Artifact、ProjectInstruction、Binding 数据模型与迁移方案。
- Conversation 可选归属 Project。
- 完成项目列表、创建、详情、添加文件、项目内新聊天。
- 实现 ProjectContextAssembler 和 ContextSnapshot。
- 增加 resource.list/read/search 与 artifact.write/export。

验收：一个“课程项目”能长期保存课程 PDF、多个对话、项目指令和生成的复习提纲；重启后上下文仍一致。

### 第 6–8 周：只读 Web + Skills v1

- Web search/fetch/read 进入 Capability Registry。
- URL 可保存为项目 Resource，回答必须显示来源。
- Skill 导入、预览、安装、项目绑定、tool scope 和卸载。

验收：完成“URL 找活动 -> 保存到项目 -> 创建提醒”和“PDF + Web 多来源总结”。

### 第 9–12 周：Remote MCP + 可恢复 Run

- Remote Streamable HTTP MCP、OAuth/PKCE、工具发现和项目绑定。
- Capability manifest v2 与 Policy enforcement。
- Run 保存 Context/Capability/Authorization snapshot 与 ResumeCursor。
- iOS 26 continued task；iOS 18–25 明确尽力降级。

验收：连接一个只读 MCP 服务，项目只启用其中一个工具；App 中断后能安全恢复或明确终止，不重复写入。

## 十、工程与文档整改

### 立即处理

1. `Docs/README.md` 引用了不存在的 `08-reference-repositories.md` 和 `09-ui-component-reference.md`，修复链接或补文件。
2. `FamiliarSettingsHubView.swift` 已超过 38 KB，`FamiliarChatView.swift` 约 38 KB，`FamiliarChatController.swift` 约 35 KB；在加入 Projects/MCP 前按 feature 拆分，避免继续形成超大状态容器。
3. 增加 iOS CI，让文档中的本地构建记录有持续验证支撑。
4. 为 SwiftData 新增正式 migration plan；Project、Resource、Memory 会快速扩大 Schema。
5. 不再把尚未接 Runtime 的 Memory/Skills/MCP 做成近似可用的设置页面。

### 建议新增文档

- `08-project-and-context-model.md`
- `09-capability-manifest-and-adapters.md`
- `10-authorization-and-trust-model.md`
- `11-benchmark-and-evaluation.md`
- `12-background-execution-matrix.md`

## 十一、现在应该停止做什么

- 暂停新增 Provider 数量；先把现有 Provider 的真实网络验收做完。
- 暂停新的系统入口和展示页。
- 暂停多 Agent、Core ML LLM、本机 MCP Server、Shell 和复杂 RAG。
- 暂停“功能名先出现在 UI，Runtime 以后再接”的开发方式。
- 暂停用提交数量衡量 Agent 能力；改用端到端任务成功率。

## 十二、最终判断

Familiar 现在最宝贵的成果是：你已经把 BYOK、iOS 原生工具、审批、附件和系统入口做出了一个相对干净的底座。最大风险是继续横向铺功能，把“未来能力的菜单”误当成平台本身。

下一阶段只应围绕一个主命题推进：

> **让一个项目在 Familiar 中真正拥有长期上下文、资料、能力、执行记录和可恢复结果。**

当“课程项目：读 PDF + 查 Web + 记住规则 + 创建提醒 + 保存工件 + 重启恢复”这一条链路稳定跑通后，Familiar 才第一次具备个人 AI 工作台的实质。Skills、MCP、Memory 和计划任务都应服务这条链路，避免各自成为孤立菜单。

## 证据索引

- Familiar 仓库与文档：[`README`](https://github.com/IsaacHuo/Familiar/blob/main/README.md)、[`Docs/01`](https://github.com/IsaacHuo/Familiar/blob/main/Docs/01-product-definition.md)、[`Docs/02`](https://github.com/IsaacHuo/Familiar/blob/main/Docs/02-system-architecture.md)、[`Docs/04`](https://github.com/IsaacHuo/Familiar/blob/main/Docs/04-agent-provider-and-content-pipeline.md)、[`Docs/06`](https://github.com/IsaacHuo/Familiar/blob/main/Docs/06-engineering-status-and-validation.md)、[`Docs/07`](https://github.com/IsaacHuo/Familiar/blob/main/Docs/07-decision-log.md)。
- Familiar 核心实现：[`AgentLoop`](https://github.com/IsaacHuo/Familiar/blob/main/Familiar/Agent/FamiliarAgentLoop.swift)、[`Tool Registry`](https://github.com/IsaacHuo/Familiar/blob/main/Familiar/Agent/FamiliarTool.swift)、[`Execution Policy`](https://github.com/IsaacHuo/Familiar/blob/main/Familiar/Agent/FamiliarExecutionPolicy.swift)、[`App Dependencies`](https://github.com/IsaacHuo/Familiar/blob/main/Familiar/App/FamiliarAppDependencies.swift)、[`Persistence`](https://github.com/IsaacHuo/Familiar/blob/main/Familiar/Persistence/FamiliarModels.swift)、[`Chat Controller`](https://github.com/IsaacHuo/Familiar/blob/main/Familiar/Presentation/FamiliarChatController.swift)。
- OpenMinis 官方材料：[`README`](https://github.com/OpenMinis/OpenMinis/blob/main/README.md)、[`SkillStore`](https://github.com/OpenMinis/OpenMinis/blob/main/src/ios/Agent/Session/SkillStore.swift)、[`MCPStore`](https://github.com/OpenMinis/OpenMinis/blob/main/src/ios/Agent/Session/MCPStore.swift)、[`BrowserUse`](https://github.com/OpenMinis/OpenMinis/tree/main/src/ios/Agent/BrowserUse)、[`Background`](https://github.com/OpenMinis/OpenMinis/tree/main/src/ios/Agent/Background)、[`NativeOffloads`](https://github.com/OpenMinis/OpenMinis/tree/main/src/ios/NativeOffloads)。
- 平台约束：Apple [`BGContinuedProcessingTask`](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)、Apple [`BGProcessingTask`](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)、MCP [`2026-07-28 Specification`](https://modelcontextprotocol.io/specification/2026-07-28)。

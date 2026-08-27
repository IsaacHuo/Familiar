# Familiar 目标系统架构

> 本文描述**目标架构**（我们打算构建什么）。当前实现状态见 `state/ARCHITECTURE.md`；两者允许存在差异。

## 1. 系统边界

Familiar 是一个 iPhone 原生、安全、可检查的个人 AI 工作台。顶层产品模型是 Chat、Project 与单 Agent：Chat 是主要交互和执行界面，Project 是长期 Context Workspace，单 Agent Runtime 是执行内核。网络请求从 App 直接发送到用户选择的 AI Provider；只读 Web 请求直接发送到 DuckDuckGo 或用户选择的公共 HTTPS 站点。图片优先由当前 Provider 原生处理；纯文本模型使用设备端 Vision 或用户安装的本地视觉模型生成证据。项目没有 Familiar 业务后端。

它不以 Linux 为执行环境，不依赖 Apple Intelligence，不把用户需求硬编码成 workflow，也不从复杂多 Agent 开始。

## 2. 目标六层架构

```text
┌─────────────────────────────────────────┐
│             System Entry Layer          │
│ Chat / Share / Notifications / Widgets  │
│ Spotlight / App Intents / Shortcuts     │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│               Agent Runtime             │
│                                         │
│ Agent Loop / Context Assembly           │
│ Model Router / Tool Router              │
│ Run / Step State                        │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│            Capability Registry          │
│                                         │
│ System Tools          Workspace Tools   │
│ Calendar              File              │
│ Reminder              PDF               │
│ Contacts              Text              │
│ Photos                Image             │
│ Maps                  Audio             │
│ Weather               Web               │
│ Location              Structured Data   │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│           Execution Policy Layer        │
│ Availability / Permission / Approval    │
│ Validation / Timeout / Cancellation     │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│              Native Layer               │
│ EventKit / Vision / MapKit / WebKit     │
│ Photos / PDFKit / Core ML / Foundation  │
└─────────────────────────────────────────┘
            + State Layer
  Session / Workspace / Memory
  Artifacts / Trace / History
```

### 2.1 System Entry Layer

系统入口按优先级划分：

| 优先级 | 入口 |
|---|---|
| **第一优先级** | ① Familiar App 本身 · ② Share Extension · ③ 系统通知 / Deep Link |
| **第二优先级** | ④ Widgets / Controls · ⑤ Spotlight 等轻量系统入口 |
| **兼容能力** | ⑥ App Intents · ⑦ Shortcuts |

设计约束：

- System Entry 只恢复本地界面上下文或承接用户明确提供的输入，**不直接调用 Provider、不执行 Tool，也不授予写权限**。
- Share Extension 与主 App 通过 App Group 一次性收件箱交换 payload；扩展 target 不链接 Agent Runtime、Provider adapter、Keychain 或 EventKit。
- App Intents 位于 Agent Core 之外，只暴露 `Ask Familiar`、`Process with Familiar`、`Open Familiar`；不把整个 Capability Registry 复制到 App Intents。
- 本地通知只携带通用终态文案与本地类型化路由，不承载会话正文或授权信息；不注册远程推送。
- Spotlight 只索引受保护的本地会话标题与 UUID，不索引聊天正文或运行详情。
- 所有入口最终汇入同一个 Agent Runtime，不各自造一套执行逻辑。

### 2.2 Agent Runtime

Agent Runtime 是最关键的一层。它尽量不触碰 Apple Framework，完全不知道 EventKit / Vision / HealthKit / MapKit；它只知道 `ToolDefinition / ToolCall / ToolResult`。

核心数据流：

```text
User
  → AgentRun
  → Context Assembly（ProjectContextAssembler → 不可变 ContextSnapshot）
  → Model
  → Tool Call?
       ├── No ──→ Final Answer
       └── Yes
           → Tool Registry
           → Policy Engine
           → Execute Tool
           → ToolResult
           → Context
           → Model
           → continue
直到：final answer / cancelled / failed / max steps
```

目标内部组件：

- Agent Loop：有限轮次循环，支持可恢复、可取消、有预算约束。
- Context Assembly：每次 Run 生成不可变 `ContextSnapshot`（Project/Conversation、Resource 版本、ProjectInstruction、本次显式选择的 Skill、Provider/Model、暴露工具、输入预算）。
- Model Router / Tool Router：模型决策与工具分发。
- Run / Step State：一次 Run 的执行状态与恢复游标。

目标 Run 契约：

```text
RunRequest
  -> ContextSnapshot
  -> CapabilitySnapshot
  -> AuthorizationSnapshot
  -> ordered RuntimeEvents
  -> Artifact/Result references
  -> ResumeCursor
```

### 2.3 Capability Registry

目标 Registry 组织成两大能力体系：

| Native System | Native Workspace |
|---|---|
| Calendar | File |
| Reminders | PDF |
| Contacts | Text |
| Photos | Image |
| Maps | Audio |
| Location | Video |
| Weather | CSV / JSON |
| Health | Archive |
| Notifications | Document |
| Clipboard | Web |

设计约束：

- Native System 工具操作 iPhone 与用户数字环境；Native Workspace 通过 Project、Resource 和 Artifact 提供不依赖 Linux 的通用工作空间。
- 当前设备、地区、系统版本、用户授权不可用的 Tool 不暴露给模型。
- 目标实现拆分为 `CapabilityCatalog + CapabilityResolver + CapabilityBindingStore`，支持稳定 ID/版本/来源、隐私与网络域、安装状态和项目绑定。
- 工具 Manifest（v2）至少包含：稳定 ID、版本、来源（native/web/MCP/skill）、输入/输出 Schema 与最大载荷、effect/risk、数据与网络域、隐私标签、幂等/取消/恢复/并行属性、所需系统权限与项目作用域、展示元数据与审计字段。

### 2.4 Execution Policy Layer

位于 Registry 与 Native Layer 之间，承担：

- 能力可用性检查。
- 权限与授权决策。首次授权由结构化动作卡产生；用户可选择仅这次、本次会话或始终允许，默认本次会话。grant 记录 user action、source、capability、规范化 arguments hash、project scope、target scope、expiry、lifetime 和 confirmation evidence。
- 长期授权按 Project、工具和目标隔离；普通聊天使用独立作用域。有效 grant 范围内可免重复确认，但每次写入仍产生动作卡和审计记录。
- 修改、删除、目标变化或参数越界重新进入审批；破坏性和财务敏感操作始终强确认。模型不能授权自己的动作。
- 参数校验、超时与取消。
- 破坏性与财务敏感操作的强确认。

系统入口（Share Extension、App Intent、Deep Link）只提供输入来源，**永远不自行产生写授权**。

### 2.5 Native Layer

Apple Framework 只通过适配层进入相应功能，不被 Agent Runtime 直接感知。目标执行后端包括 EventKit、Vision、MapKit、WebKit、PDFKit、Core ML、Photos 等；新 Apple Framework、远程 MCP Server 和模型主要通过 Adapter 接入。

### 2.6 State Layer

- Session：Conversation、Message、Attachment、Source、Run/Step 摘要。
- Trace：运行事件、审批和工具终态的可检查轨迹。
- Project Workspace：Project、Resource、Artifact、Instruction、Binding、MemoryItem、Schedule。
- Run Workspace：不可变 Context/Capability/Authorization snapshot、工具输入输出引用、ResumeCursor、持久化幂等状态。

## 3. 目标能力设计与当前边界

### 3.1 可恢复 Run 与后台

Agent Run 的目标是可中断、可恢复，不是常驻 daemon。

```text
用户发起
  → Foreground
  → 用户退出 App
  → 必要时继续完成
```

- iOS 26+：可条件使用 `BGContinuedProcessingTask` 承接用户在前台启动的长任务，仍需保存恢复游标并处理 expiration。
- iOS 18–25：`BGProcessingTask` 由系统择机执行，不能保证精确时间；适合的网络传输可使用 background `URLSession`。
- 无后端时不承诺可靠 cron。"已计划"必须标明精确、尽力或需用户继续的保证等级。
- 数据契约先行：先完成 snapshot、ResumeCursor 与持久化幂等状态，再接后台承接能力。

### 3.2 Memory

目标使用三种作用域：

- global：跨项目个人偏好。
- project：项目事实与约定。
- conversation：单个对话的局部信息。

第一版采用结构化条目，记录 provenance、scope、confidence、createdBy、lastUsedAt 和可见性，**不做向量数据库**。自动写入默认关闭；候选条目由用户确认或明确规则写入。目标工具：`memory.search`、`memory.write`、`memory.delete`。

### 3.3 Skills

当前 Familiar Skill 不包含 Python、Shell、Executable Script，是 Instruction Package + Tool Scope：

```text
Skill
├── id
├── description
├── instructions
├── allowedTools
└── examples
```

当前已安装 Skill 由用户在普通聊天或项目聊天的 Composer 中显式选择，只作用于下一次 Run，并冻结 ID、版本、内容 hash 与 `allowedTools` 供审计。Skill 只能收窄 Tool Scope，不能扩大或创建用户授权。当前没有 Project SkillBinding，也没有 Files/Share 导入界面；文件导入、内容预览与项目绑定保留为明确标注的未来目标。

### 3.4 MCP：Adapter，不是 Kernel

内部借鉴 MCP 的 Resources/Tools/Instructions 分离，但直接用 Swift。只支持远程 HTTPS Streamable HTTP Client，不支持本机 stdio Server：

- URL 校验与 Server Identity；OAuth/PKCE 凭据按 Server Identity 隔离在 Keychain。
- Initialize、capability negotiation、tools/list、tools/call；连接健康、超时、取消、分页和 server change detection。
- 工具 Schema 转换为 Familiar Manifest，继续经过 Familiar Policy；不信任 server annotations。
- project/session binding，默认不开启全部工具。

### 3.5 图片能力路由与视觉证据

图片输入在进入主模型前形成明确的处理计划：

```text
当前模型支持图片
  -> 图片字节只发送给当前 Provider

当前模型不支持图片
  -> 文字/条码/基础识别：Apple Vision
  -> 所有结果作为只读 VisualEvidence 交给当前文本模型
```

- Apple Vision 是所有支持设备的默认本地能力，覆盖 OCR、条码和基础分类；不把分类推断写成确定事实。
- 当前 DeepSeek catalog 的 `deepseek-v4-flash-vision-exp` 是实验图片入口；只有用户当前选中该模型时才发送图片，不从文本模型自动升级。
- FastVLM 暂停提供，设置入口与自动路由关闭。研究实现暂留不等于产品能力。
- 视觉结果记录原图引用、处理方式、模型/系统版本和最终证据文本。证据按不可信只读输入处理，不授予工具权限，不伪装成用户或系统指令。
- Provider adapter 只编码准备好的 Provider 内容，不承担 Vision 或模型选择决策；DeepSeek 视觉模型与文本模型使用同一通用 adapter。

### 3.6 本地模型管理目标

- 本地模型目录独立于附件、Resource 和 Artifact，具备固定 manifest、版本、大小、SHA-256、许可证和安装状态。
- 当前不提供 FastVLM。该层面向 iOS 27 正式可用后的 Core AI/Qwen 文本模型，真实 API 与模型资产可用前保持不可执行。
- 未来下载由用户主动发起，支持进度、暂停/恢复、失败重试和删除；推理前检查内存、存储和热状态。

### 3.7 远程 Web 内容

只读 Web 先于交互：`web_search` / `web_fetch` 与公开 HTTPS 页面导入 Project Resource 已实现；`web.read`（selector/readerMode）、浏览器登录、表单提交、Cookie 会话与自动点击延后。Web/MCP 内容一律按不可信输入处理，不授予工具权限。

## 4. 架构约束

- Provider adapter 不接触 SwiftData 实体。
- Agent Runtime 不接触 Apple Framework，只认识 ToolDefinition/ToolCall/ToolResult。
- UI 不直接调用 EventKit save。
- 写工具的 `execute` 只产生待确认计划。
- 文档原文件不进入 Provider 请求；图片只进入当前多模态 Provider 请求或本地视觉处理，不进入其他网络目的地。
- 本地视觉证据必须带 provenance，不能提升为系统指令或授权。
- WebKit 不使用持久化网站数据存储。
- SwiftData 的广泛 invalidation 不承载逐 token 更新。
- App Intents 不复制 Capability Registry。
- Share Extension、App Intent 与 Deep Link 只提供输入来源，永不授予写权限。
- 远程 Web/MCP 内容与 server annotation 均按不可信输入处理。
- 每次 Project Run 使用不可变 ContextSnapshot。
- 本地通知只携带通用终态文案与本地类型化路由，不携带会话正文或授权信息。
- Spotlight 只索引受保护的本地会话标题与 UUID，不索引聊天正文或运行详情。
- 权限由代码控制，不靠 Prompt。
- Skill 只能提供指令并收窄本次 Run 的工具范围，永远不构成授权依据。

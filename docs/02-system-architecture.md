# Familiar 目标系统架构

> 本文描述**目标架构**（我们打算构建什么）。当前实现状态见 `state/ARCHITECTURE.md`；两者允许存在差异。

## 1. 系统边界

Familiar 是一个 iPhone 原生、安全、可检查的个人 AI 工作台。顶层产品模型是 Chat、Project 与单 Agent：Chat 是主要交互和执行界面，Project 是长期 Context Workspace，单 Agent Runtime 是执行内核。网络请求从 App 直接发送到用户选择的 AI Provider；只读 Web 请求直接发送到 DuckDuckGo 或用户选择的公共 HTTPS 站点。图片优先由当前 Provider 原生处理；纯文本模型使用设备端 Vision 或用户安装的本地视觉模型生成证据。项目没有 Familiar 业务后端。

它不以 Linux 为执行环境，不依赖 Apple Intelligence，不把用户需求硬编码成 workflow，也不从复杂多 Agent 开始。

## 2. Architecture boundaries

The product has three first-level objects: Chat, Project and Files. Memory is system behavior; Run is execution history. Resource, Artifact, Workspace and Capability are infrastructure or historical names, not additional product objects.

```text
Product UI -> Domain -> Context / Runtime -> Tools / Policy -> Services -> Persistence
```

- Product UI invokes use cases and renders status. Domain uses value types and minimal interfaces.
- Context Compiler freezes scoped long-term inputs at submission, then compiles an immutable snapshot before every model request. Conversation, Project Instructions, FileVersion references, selected Memory, Skill, current input, Evidence, Run facts and actual tool schemas share this entry point. No module independently adds product instructions to the Provider request.
- Single Agent Runtime performs model calls, tool calls, state transitions and results. One Agent + One Loop + Lazy Tools remains the execution model. There is no Router, Planner or multi-Agent orchestration.
- Run State records discovered and exposed tools, reads and observations, loaded Skills, write status and produced versions. It records facts rather than scheduling a plan. Known immutable FileVersions may reuse bounded read results; Web, Native and MCP observations remain refreshable.
- Tools are the only external capability boundary. Web, Files, Memory, Apple adapters, MCP and Shell share typed inputs, manifest declarations, output envelopes, structured errors, preflight, policy, approval, execution and persistence.
- Policy returns allow / requireApproval / deny. It owns scope and availability checks, exact authorization lookup/issuance and execution-time revalidation. System entries, Skills and model output never create authorization. Controlled offline Shell remains the only explicit automatic write exception; MCP remains approved on every call.
- Services implement Provider, Apple, MCP, iSH and storage adapters, injected at composition. Core Runtime does not consume SwiftData entities or concrete Views.
- Persistence keeps long-term Domain data separate in responsibility from Audit/Recovery and rebuildable caches, within one store. Project/Chat/Files/Memory are user data; Run/Invocation/Approval/Undo/Recovery are execution records.

### Files and scope

File identity is independent of name, path and hash. Each immutable FileVersion records its content hash, format/extraction, storage reference and provenance. Explicit relationships may share identity within a Project. Same names or bytes never merge Files across Projects.

Project owns committed Files. Deleting Chat removes associations and temporary data; deleting Project removes its long-term files. Moving Chat copies linked Files into the destination Project with new identities, clears the old conversation summary and preserves the original Run evidence. Global Memory is explicit; another Project's files, Memory or bound Skill cannot enter a new Run.

Uploads, Project imports, saved web captures, generated results and Shell Outputs use the same Files experience. Fetching is Evidence until a user explicitly saves its captured bytes. Work/Environment/checkpoints remain internal. Shell output capture, metadata, result receipt and compensating Undo share a success boundary.

### Context budget and audit

The budget is a character estimate, including actual tool schemas and results. Required instructions, current input and write state have priority; Project bodies, selected Memory and older history use budgets. Submitted input is never silently truncated. Omitted Project bodies leave references and reasons for lazy reads. Compaction preserves the current turn and assistant-call/result pairs; Run facts preserve write states and result references independently of transcript summarization.

Each request saves its compilation identity, references, hashes, source scope/trust, observation times and a bounded summary. It does not store repeated copies of every file body. Provider adapters translate transport format only.

### Migration and recovery

Freeze the actual 37-entity 1.0.0 definitions. Add canonical Files before removing old generated-file metadata; archive historical Grant provenance before removing its unused entity. Keep the store address and byte directories. Migration failure preserves user data and enters recovery; never automatically rebuild the store. Historical Resource/Attachment storage fields remain only where relationships/history need them; new imports write canonical Files directly. Cursor/journal records detect interruption and uncertain external writes; this phase does not resume across restarts or execute in the background.

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

- 本地模型目录独立于附件、Files，具备固定 manifest、版本、大小、SHA-256、许可证和安装状态。
- 当前不提供 FastVLM。该层面向 iOS 27 正式可用后的 Core AI/Qwen 文本模型，真实 API 与模型资产可用前保持不可执行。
- 未来下载由用户主动发起，支持进度、暂停/恢复、失败重试和删除；推理前检查内存、存储和热状态。

### 3.7 远程 Web 内容

只读 Web 先于交互：`web_search` / `web_fetch` 与公开 HTTPS 页面导入 Project File 已实现；`web.read`（selector/readerMode）、浏览器登录、表单提交、Cookie 会话与自动点击延后。Web/MCP 内容一律按不可信输入处理，不授予工具权限。

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

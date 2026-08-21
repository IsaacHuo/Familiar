<p align="center">
  <img src="website/public/assets/app-icon.png" width="112" alt="Familiar app icon">
</p>

<h1 align="center">Familiar</h1>

<p align="center">
  为 iPhone 打造的原生、安全、可检查的个人 AI 工作台。
</p>

<p align="center">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/IsaacHuo/Familiar/actions/workflows/pages.yml"><img src="https://github.com/IsaacHuo/Familiar/actions/workflows/pages.yml/badge.svg" alt="Website deployment"></a>
  <img src="https://img.shields.io/badge/iOS-18%2B-0A84FF?logo=apple" alt="iOS 18 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift and SwiftUI">
  <img src="https://img.shields.io/badge/Platform-iPhone-111111" alt="iPhone only">
  <img src="https://img.shields.io/badge/Architecture-BYOK-6D5DFB" alt="Bring your own key">
</p>

<p align="center">
  <a href="https://isaachuo.github.io/familiar/">Website</a> ·
  <a href="https://isaachuo.github.io/familiar/privacy/">Privacy</a> ·
  <a href="https://isaachuo.github.io/familiar/support/">Support</a>
</p>

---

## 项目概览

> **Familiar 是一个原生、安全、可检查的个人 AI 工作台。** Project 是长期工作单元，聊天是主要入口，本机信息、受限 Web、Project 与 EventKit 类型化工具共同组成当前执行面，单 Agent Runtime 是执行内核。

Familiar 把 iPhone 的原生能力转成一个可组合的 Runtime，不引入 Linux 执行环境、Apple Intelligence 依赖或复杂多 Agent。Project、版本化文档资源、Markdown/纯文本 Artifact、持久化工作区置顶和显式单次 Run Skill 已进入当前实现；更广泛的可写 Workspace 与字节级续跑仍是后续能力。

App 采用 BYOK 模式：用户使用自己的模型 API Key，模型请求从设备直接发送到所选 Provider；会话、附件和工具记录保存在本机。使用网页工具时，搜索词会直接发送给 DuckDuckGo，网页请求会直接发送给所选公开 HTTPS 站点。

> Familiar 目前处于持续开发阶段。AI 输出可能不准确，不应作为医疗、法律、财务或其他高风险决定的唯一依据。

## 核心特性

- **iPhone 原生 Agent Runtime** — 单一主 Agent 通过 Tool 规划，并由 iOS 原生 Framework 执行；无 Linux 环境，无 Apple Intelligence 依赖。
- **Tool 是最核心的抽象** — 17 个类型化工具覆盖本机信息、受限 Web、冻结的 Project Resource、Project Artifact、EventKit 与结构化展示；每个 Tool 小而可检查，并统一经过策略控制。
- **Native First** — 复用 EventKit、Vision、PDFKit、Photos 与 Foundation 承接原生能力和本地预处理，不重复实现系统服务。
- **统一 Chat Workspace** — 普通聊天与 Project 对话共用一个 Surface。顶栏切换工作区和模型，左侧抽屉提供搜索、持久置顶、可展开的项目历史与普通最近会话。
- **Project Workspace** — 项目指令和版本化本地资源可跨项目对话共享；资源使用受保护目录，并在 Run 中保存不可变引用。Markdown/纯文本 Artifact 支持受控新建和编辑，规范化后的项目名称全局唯一。
- **显式 Skill** — instruction-only Skill 从设置模板创建，可从普通或项目聊天的 Composer 选择，仅作用于下一次 Run。当前没有导入行或 Project binding；Skill 可以收窄工具范围，但不能授权操作。
- **代码强制授权** — 可用读取自动执行；可逆写入需要结构化审批，除非存在精确匹配且有效的仅一次/本会话/长期规则。EventKit Undo 可跨重启恢复，Artifact Undo 保留在当前会话。
- **Runtime Event 驱动的 UI** — 时间线渲染 Agent 事件（模型思考、工具进度、审批、成功与失败），而不是每个工具自造一套 UI。
- **本地优先与 BYOK** — API Key 按 Provider 分别保存在 iOS Keychain；请求不经过 Familiar 服务器。
- **完整 Provider Catalog** — OpenAI、Anthropic、Gemini、DeepSeek、Groq、xAI、OpenRouter、Qwen、Kimi、GLM、MiniMax、SiliconFlow，以及自定义 OpenAI-compatible endpoint。
- **本地文档转换** — AnyDoc 在设备上将 Office、OpenDocument、RTF、EPUB、CSV 与 PDF 转换为 Markdown；扫描 PDF 使用 Vision OCR。
- **系统入口** — Share Extension 将文本、网页链接或文档保存到 App Group 收件箱；Deep Link 与 Spotlight 恢复本地上下文；Siri/快捷指令提供 `Ask Familiar`、`Process with Familiar`、`Open Familiar`，另有本地 Run 通知、启动 Widget 与 Control。
- **富文本回答渲染** — 本地 Markdown、代码高亮、表格、引用、Mermaid、KaTeX、代码复制和安全外链。
- **语音转写** — 使用 Apple Speech 与 `AVAudioEngine` 生成可编辑文字草稿，不保存原始录音。
- **双语与无障碍基础** — 已提供简体中文与英文资源，并支持深浅色、Dynamic Type、VoiceOver、Reduce Motion 和 Reduce Transparency；真机验收仍在进行。

## 截图

<p align="center">
  <img src="screenshots/chat.png" width="180" alt="聊天页">
  <img src="screenshots/drawer.png" width="180" alt="抽屉页">
  <img src="screenshots/settings.png" width="180" alt="设置页">
  <img src="screenshots/permissions.png" width="180" alt="权限页">
  <img src="screenshots/storage.png" width="180" alt="存储页">
</p>

*截图来自较早的开发版本，当前界面可能已有变化。*

## 当前架构

当前实现是单 Agent Runtime 叠加在原生 iOS 能力之上。下图反映代码里真实存在的内容，而非下面要演进到的目标层：

```mermaid
flowchart TB
    subgraph Entry["系统入口层"]
        direction LR
        App[Familiar App]
        Share[Share Extension]
        Links[Deep Links]
        Notify[通知]
        Spotlight[Spotlight]
        Intents[App Intents / Shortcuts]
        Widget[Widget / Control]
    end

    subgraph UI["SwiftUI 展示层"]
        direction LR
        Chat[Chat Surface + Composer]
        Projects[Project Workspace]
        Settings[Settings Hub]
        Timeline[Assistant Turn Timeline]
    end

    subgraph Runtime["Agent Runtime"]
        Loop[FamiliarAgentLoop]
        Assembly[Context Assembly]
        Registry[Tool Registry · 17 个工具]
        Policy[Execution Policy]
        Auth[Authorization Runtime]
        Clarify[Clarification Coordinator]
        Undo[Undo Store]
    end

    subgraph Models["模型 Provider · BYOK"]
        direction LR
        OpenAI[OpenAI-compatible]
        Anthropic[Anthropic]
        Gemini[Gemini]
    end

    subgraph Native["原生能力适配器"]
        direction LR
        EventKit[EventKit]
        Vision[Vision / FastVLM]
        Docs[PDFKit / AnyDoc]
        Speech[Speech]
        Photos[Photos]
        Web[受限 Web]
    end

    subgraph Store["本地存储"]
        direction LR
        SwiftData[SwiftData store]
        Keychain[Keychain]
        Group[App Group]
        Files[附件 / 项目资源 / Artifact]
    end

    Entry --> UI
    UI --> Loop
    Loop --> Models
    Loop --> Registry
    Registry --> Policy
    Policy --> Auth
    Policy --> Native
    Loop --> Store
```

Agent Runtime 是内核：它只消费类型化 Tool Manifest、Provider Tool Call、Tool Outcome、策略决策和 Runtime Event，绝不直接触碰原生框架——EventKit、Vision、AnyDoc、Speech、Photos 与受限 Web 客户端都留在 Tool Adapter 与执行策略之后。持久化使用单一 SwiftData Store（`FamiliarDevelopment.store`）、iOS Keychain 保存 API Key、App Group 承接分享收件箱，附件、项目资源与 Artifact 使用受保护的设备端目录。

## 目标架构

Familiar 正在向六层架构演进。下图包含规划能力，不是当前实现清单：

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

当前普通聊天与 Project 对话共用同一个 Chat Surface 和有限 Agent Loop。启动注册表包含 17 个工具：2 个本机信息、2 个受限 Web、3 个 Project Resource、2 个 Project Artifact、4 个 EventKit 和 4 个结构化展示工具。Runtime 还支持作用域授权规则、跨重启 EventKit Undo、不可变 Context/Capability/Skill 快照、Invocation 与 Resume Cursor 记录、视觉证据、项目/会话持久置顶和显式单次 Run Skill。Memory Runtime、MCP Runtime、可靠后台承接与字节级续跑尚未实现。

本地持久化使用 `FamiliarDevelopment.store` 中单一当前 27 实体 SwiftData Schema。开发阶段遇到不兼容 Schema 变化时会使用新 Store，不迁移测试数据；公开发布前必须另行确定兼容与迁移策略。

```mermaid
flowchart TD
    Entry[System Entry Layer] --> Runtime[Agent Runtime]
    Runtime --> Registry[Capability Registry]
    Registry --> Policy[Execution Policy Layer]
    Policy --> Native[Native Layer: EventKit Vision MapKit PDFKit ...]
    Runtime --> State[State Layer: Session Memory Trace]
```

Agent Runtime 是最关键的一层：它只消费类型化 `FamiliarToolManifest`、Provider Tool Call、`FamiliarToolOutcome`、策略决策和 Runtime Event，不直接触碰 EventKit 或其他原生 Framework；这些能力都位于 Tool Adapter 与执行策略之后。

### 系统入口

系统入口按优先级划分：

| 优先级 | 入口 |
| --- | --- |
| **第一优先级** | ① Familiar App 本身 · ② Share Extension · ③ 系统通知 / Deep Link |
| **第二优先级** | ④ Widgets / Controls · ⑤ Spotlight 等轻量系统入口 |
| **兼容能力** | ⑥ App Intents · ⑦ Shortcuts |

当前 System Entry Layer 已包含 Familiar App、Share Extension、类型化 Deep Link、Run 终态本地通知、受保护的 Spotlight 会话索引、启动 Widget、控制中心 Control、三项 App Intent 和双语 App Shortcut。Widget 打开新的可编辑草稿，Control 打开 Familiar 且不替换当前上下文。共享内容只在本机暂存，Deep Link 只恢复或预填上下文；Run 通知使用通用文案，只携带本地 Run 或会话标识，不依赖远程推送，也不提供后台执行。Spotlight 只索引有限长度的会话标题、修改时间和本地标识，不索引正文或附件元数据。`Ask Familiar` 与 `Process with Familiar` 会明确启动现有 App 内发送链路，`Open Familiar` 不改变草稿或会话。所有入口都不能授权工具操作。

这些入口已在代码中实现，但仍需真机验收。

App Intents 位于 Agent Core 之外。其文本输入有长度上限，不读取 Keychain，也不直接调用 Provider；存在未发送草稿时拒绝覆盖。完整 Capability Registry 不会复制到 App Intents。

## Agent Runtime

Familiar 采用单 Agent First 设计，核心是可组合的 Tool Loop：

```text
User
  → AgentRun
  → FamiliarProjectContextAssembler
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
until: final answer / cancelled / failed / max steps
```

Agent Loop 是有限循环：有最大迭代轮数、工具结果长度上限和由模型能力决定的上下文上限。同一 run 内的重复工具调用会被拒绝；单次 Agent Run 中相同写操作只能成功提交一次。

## Tool 设计

Tool 使用强类型 Swift，Registry 存储 `AnyFamiliarTool`。当前协议使用类型化 `Input` 并返回 `FamiliarToolOutcome`：

```swift
protocol FamiliarTool {
    associatedtype Input: Decodable & Sendable

    var manifest: FamiliarToolManifest { get }
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome
}
```

当前 `FamiliarToolManifest` 包含：

```text
FamiliarToolManifest
  id / version / source
  name
  title
  description
  parameters
  effect / risk
  requirements  EventKit, Calendar permission, ...
  payload / data / network / privacy metadata
  idempotency / cancellation / recovery / parallelism
  requiredScopes
```

Familiar 内部借鉴 MCP 的思想但不把它当作内核，用原生 Swift 实现三种资源分离：

启动注册表当前恰好包含以下 17 个工具：

| 分组 | 工具名 |
| --- | --- |
| 本机信息 | `current_date_time`、`app_information` |
| 受限 Web | `web_search`、`web_fetch` |
| Project Resource | `resource_list`、`resource_read`、`resource_search` |
| Project Artifact | `artifact_write`、`artifact_edit` |
| EventKit | `calendar_events`、`create_calendar_event`、`reminders`、`create_reminder` |
| 结构化展示 | `task_plan`、`present_recommendation`、`present_insight`、`ask_user` |

- **当前 Resources** — 会话历史、消息附件抽取文本、版本化 Project Resource 和 Project Artifact（application-controlled）
- **当前 Tools** — 上表列出的 17 个注册工具（model-controlled）
- **当前 Instructions** — Base Policy、ProjectInstruction，以及最多一个显式选择的单次 Run Skill（user-controlled）
- **目标 Resources** — scoped Memory 和更广泛的受控 Workspace 数据

> **MCP 是 Adapter，不是 Kernel。** 未来远程 HTTPS Client 把 MCP Tools 转成 Familiar Manifest，并继续经过 Familiar Policy；MCP 当前尚未实现。

## Capability Registry

目标 Registry 是 Familiar 的核心资产，组织成两大能力体系：

| Native System | Native Workspace |
| --- | --- |
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

当前 Registry 是启动时提供的 17 工具字典，并按 EventKit availability 过滤；Resource 与 Artifact 工具已经按 Project 作用域运行。通用运行时发现和远程安装尚未实现，MCP 仍是未来 Adapter。

## 权限模型

当前代码授权行为：

| 操作 | 默认行为 |
| --- | --- |
| 可用读取 | 自动执行 |
| 可请求的系统访问 | 结构化审批，然后进入 iOS 权限流程 |
| 可逆写入 | 结构化审批，除非存在精确匹配的仅一次/本会话/长期授权 |
| 破坏性或高风险操作 | 始终请求审批 |
| Undo | EventKit 新建操作可跨重启恢复；Artifact 新建和编辑为会话内撤销 |

权限由代码控制，不靠 Prompt：模型无法用一句话绕过 iOS 权限、操作确认或敏感数据策略。

记忆授权由 Swift 强制执行，并精确匹配 Project、Capability ID/版本、目标、规范化参数 hash、会话和有效期；用户可在设置中撤销规则。Share Extension、App Intent 与 Deep Link 的来源信息永远不授予写权限。

## Provider 支持

| 协议 | Provider |
| --- | --- |
| OpenAI Chat | OpenAI, DeepSeek, Groq, xAI, OpenRouter, Qwen, Kimi, GLM, MiniMax, SiliconFlow, custom OpenAI-compatible |
| Anthropic Messages | Anthropic |
| Gemini generateContent | Gemini |

每个 Provider 拥有独立 Keychain 项、端点配置、Header 和模型目录策略。模型能力按 `providerID + modelID` 标记；未知自定义模型默认仅文本。

模型层使用 `FamiliarModelProvider` 抽象，当前包含 OpenAI Chat、Anthropic Messages 与 Gemini Adapter。确定性 Agent Benchmark 已存在，真实 Key Provider 冒烟仍未完成。可选本地 FastVLM 用于补充视觉预处理，不替代 BYOK 语言模型。

## 文档处理链路

系统将所选文档复制到 App 私有目录，再进行本地转换。

| 输入格式 | 本地处理方式 |
| --- | --- |
| DOC, DOCX, DOCM | AnyDoc → GitHub-Flavored Markdown |
| PPT, PPS, POT, PPTX, PPTM, PPSX, PPSM | AnyDoc → GitHub-Flavored Markdown |
| XLS, XLSX, XLSM, XLSB | AnyDoc → GitHub-Flavored Markdown |
| ODT, ODS, ODP | AnyDoc → GitHub-Flavored Markdown |
| RTF, EPUB, CSV | AnyDoc → GitHub-Flavored Markdown |
| 文本型 PDF | AnyDoc / pdf-inspector → Markdown |
| 扫描或混合型 PDF | 先由 AnyDoc 处理；无文本层页面使用 PDFKit + Vision OCR |
| TXT、MD、Markdown | 编码验证与无损文字直通 |

只有转换后的 Markdown 和文件名会进入模型请求。原始文档字节、本地路径和 security-scoped URL 不会发送给 Firecrawl 或所选模型 Provider。

支持图片的 Provider 会直接接收图片内容。对于纯文本模型，Controller 自动执行 Apple Vision OCR、条码和分类预处理，并可在路由允许时使用已安装的 FastVLM 补充；结果以带来源信息的不可信视觉证据持久化。

## 富文本渲染

流式输出使用原生回退文本；最终助手回答由内置的非持久化 `WKWebView` 渲染，并且只使用本地资源。支持的输出包括 CommonMark 风格 Markdown、语法高亮代码块与代码复制、表格、引用、列表、Mermaid 图表、KaTeX 数学表达式和安全外链。

## 隐私与安全模型

- 无 Familiar 账号或登录流程。
- 无 Familiar 自建聊天后端或云数据库。
- 无订阅、权益或托管额度系统。
- API Key 按 Provider 保存在 iOS Keychain。
- 会话历史、附件和工具记录保存在本机。
- 流式 token 和等待中的确认不会被广泛持久化。
- 文档在本机转换；只有转换后的文字会随用户主动发起的请求发送。
- 只有调用相应工具时才请求日历或提醒事项访问权限。
- 写操作使用 Action Proposal；未匹配授权的操作需要结构化审批，精确匹配的记忆授权可以免除重复审批。
- 网站代码不包含广告、分析或跟踪脚本。

## 技术栈

| 领域 | 技术 |
| --- | --- |
| UI | SwiftUI |
| 本地持久化 | SwiftData |
| 网络 | 模型流量使用 URLSession/SSE；受限 Web Fetch 使用 Network.framework HTTP/1.1 |
| 密钥 | iOS Keychain |
| 富文本 | WebKit 与内置 Markdown、Mermaid、KaTeX 资源 |
| 注册工具 | 本机信息、受限 Web、Project Resource/Artifact 与 EventKit Adapter |
| 文档 | AnyDoc Rust core、PDFKit、Vision |
| 语音输入 | Speech、AVFoundation |
| 照片 | PhotosPicker |
| 网站 | Vue 3、Vite、GitHub Pages |

## 仓库结构

```text
Familiar/
├── Agent/          Agent Runtime、工具循环与确认事件
├── AnyDoc/         内置 AnyDoc 引擎的 Swift 接口
├── App/            App 入口与模型容器
├── Artifacts/      项目 Artifact 存储与 Artifact 工具
├── Attachments/    私有存储、转换与 OCR 链路
├── Data/           Provider 适配器、Keychain 与模型目录服务
├── Domain/         Provider、消息与能力模型
├── EventKit/       日历与提醒事项服务/工具
├── LocalVision/    可选 FastVLM 安装与视觉预处理
├── Memory/         作用域 Memory 数据/服务基础（Runtime 未启用）
├── Persistence/    当前 SwiftData Schema 与本地服务
├── Presentation/   SwiftUI 页面、输入器与消息渲染
├── Resources/      Project Resource 服务、本地化与内置资产
├── Skills/         instruction-only Skill 解析、存储与 Run 快照
├── Speech/         原生语音转写
├── Support/        主题与平台兼容辅助代码
├── SystemEntry/    Deep Link、App Intents、通知与 Spotlight
├── Vision/         Apple Vision 预处理与证据
└── Web/            只读 Web 搜索/抓取与受限 HTTP 客户端

FamiliarWidgets/    主屏幕/锁屏启动 Widget 与控制中心 Control

Shared/             App Group 收件箱与控制 Intent（App 与扩展共享）
Vendor/
├── AnyDocBridge.xcframework/
├── AnyDocBridgeRust/
└── ml-fastvlm/

docs/               设计与规划（我们打算构建什么）
state/              当前实现真实状态（以代码验证）
logs/               可复用的调试与调查经验
website/            Vue/Vite 网站、隐私政策和支持页面
Scripts/            可复现的 AnyDoc XCFramework 构建脚本
```

文档按职责拆分为三个目录（模型见 [`docs/README.md`](docs/README.md)）：`docs/` 承载设计与规划，`state/` 承载以代码验证的当前实现（先读 `state/CURRENT.md`，再读 `state/ARCHITECTURE.md`），`logs/` 承载可复用的调查经验。

## 环境要求

- Apple Silicon Mac
- Xcode 26 或更高版本
- iOS 18 或更高版本
- iPhone target
- 至少一个受支持模型 Provider 的有效 API Key

正常构建 App 不需要安装 Rust，因为仓库已包含 arm64 AnyDoc XCFramework。

## 构建 iOS App

```bash
git clone https://github.com/IsaacHuo/Familiar.git
cd familiar
open familiar.xcodeproj
```

选择 `Familiar` scheme 和一个 iPhone destination。API Key 在 App 运行时配置，绝不能提交到仓库。

命令行构建示例：

```bash
xcodebuild \
  -project familiar.xcodeproj \
  -scheme Familiar \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### 重新构建 AnyDoc

```bash
./Scripts/build-anydoc-xcframework.sh
```

脚本只构建 `aarch64-apple-ios` 和 `aarch64-apple-ios-sim`。

## 构建网站

```bash
npm --prefix website ci
npm --prefix website run build
```

## 明确的产品边界

Familiar 当前不包含：

- iPad 支持
- 账号、登录、云端 Workspace 或同步系统
- 受控 Project Artifact 之外的任意可写 Workspace
- 字节级续跑或可靠后台承接；Cursor/Invocation 记录与启动时中断 Run 失败终结已实现
- Familiar 托管的模型代理
- 订阅或权益流程
- Linux / iSH 执行环境
- Shell 或任意代码执行
- 多 Agent、Subagent 或 Agent Graph
- 复杂 RAG 或向量数据库
- iPhone 上的 MCP Server（后期可能增加 MCP Client）
- Core ML LLM 或 Apple Intelligence 依赖
- 实时语音对话
- 修改或删除日历/提醒事项
- 自主浏览器操作、JavaScript 执行或递归爬取

## 第三方软件

Familiar 依据 MIT License 内置 AnyDoc 与 SwiftSoup，相关声明位于：

- `Vendor/AnyDocBridgeRust/LICENSE.anydoc`
- `Familiar/Resources/ThirdPartyNotices.txt`

FastVLM 与模型使用独立条款和致谢文件：

- `Vendor/ml-fastvlm/LICENSE`
- `Vendor/ml-fastvlm/ACKNOWLEDGEMENTS`
- `Vendor/ml-fastvlm/LICENSE_MODEL`

锁定的 MLX、Swift Transformers、ZIPFoundation 与内置渲染依赖继续遵循各自上游许可证和声明。

## 支持

- 产品支持：<https://isaachuo.github.io/familiar/support/>
- 隐私问题：<https://isaachuo.github.io/familiar/privacy/>
- Bug 反馈：<https://github.com/IsaacHuo/Familiar/issues>

反馈问题时，请勿包含 API Key、私人会话、日历数据、提醒事项、文档或其他敏感信息。

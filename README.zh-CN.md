<p align="center">
  <img src="website/public/assets/app-icon.png" width="112" alt="Familiar app icon">
</p>

<h1 align="center">Familiar</h1>

<p align="center">
  为 iPhone 打造的原生、本地优先 BYOK AI Agent Runtime。
</p>

<p align="center">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/IsaacHuo/familiar/actions/workflows/pages.yml"><img src="https://github.com/IsaacHuo/familiar/actions/workflows/pages.yml/badge.svg" alt="Website deployment"></a>
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

> **Familiar = 一个 iPhone-native Agent Runtime。** 云端/可替换 LLM 负责理解、决策与编排；iOS 原生 Framework 负责感知、计算与行动；Native Workspace 提供通用内容处理能力。

Familiar 把 iPhone 的原生能力转成一个可组合的 Agent Runtime。它不以 Linux 为执行环境，不依赖 Apple Intelligence，不把每一个用户需求硬编码成 workflow，也不从一开始做复杂多 Agent。

App 采用 BYOK 模式：用户使用自己的模型 API Key，模型请求从设备直接发送到所选 Provider；会话、附件和工具记录保存在本机。使用网页工具时，搜索词会直接发送给 DuckDuckGo，网页请求会直接发送给所选公开 HTTPS 站点。

> Familiar 目前处于持续开发阶段。AI 输出可能不准确，不应作为医疗、法律、财务或其他高风险决定的唯一依据。

## 核心特性

- **iPhone 原生 Agent Runtime** — 单一主 Agent 通过 Tool 规划，并由 iOS 原生 Framework 执行；无 Linux 环境，无 Apple Intelligence 依赖。
- **Tool 是最核心的抽象** — Calendar、Vision、PDF、Maps 都只是注册在 Capability Registry 中的 Tool；每个 Tool 小而正交、可组合。
- **Native First** — 复用 EventKit、Vision、MapKit、PDFKit、Photos 与 Foundation，而不是重新实现日历、OCR、地图或文档渲染。
- **Native Workspace** — 一个不依赖 Linux 的通用工作空间：File、PDF、Text、Image、Audio、Video、CSV/JSON、Archive 与 Document 处理。
- **意图感知授权** — 低风险读取自动执行，明确可逆写入执行并支持撤销，推断或破坏性写入要求确认。
- **Runtime Event 驱动的 UI** — 时间线渲染 Agent 事件（模型思考、工具进度、审批、成功与失败），而不是每个工具自造一套 UI。
- **本地优先与 BYOK** — API Key 按 Provider 分别保存在 iOS Keychain；请求不经过 Familiar 服务器。
- **完整 Provider Catalog** — OpenAI、Anthropic、Gemini、DeepSeek、Groq、xAI、OpenRouter、Qwen、Kimi、GLM、MiniMax、SiliconFlow，以及自定义 OpenAI-compatible endpoint。
- **本地文档转换** — AnyDoc 在设备上将 Office、OpenDocument、RTF、EPUB、CSV 与 PDF 转换为 Markdown；扫描 PDF 使用 Vision OCR。
- **系统入口** — 从其他 App 将文本、网页链接或文档保存到 App Group 收件箱；类型化 Deep Link 恢复本地上下文；Siri、快捷指令与 Spotlight 提供 `Ask Familiar`、`Process with Familiar`、`Open Familiar`。
- **富文本回答渲染** — 本地 Markdown、代码高亮、表格、引用、Mermaid、KaTeX、代码复制和安全外链。
- **语音转写** — 使用 Apple Speech 与 `AVAudioEngine` 生成可编辑文字草稿，不保存原始录音。
- **双语界面** — 完整简体中文与英文资源，支持深浅色、Dynamic Type、VoiceOver、Reduce Motion 和 Reduce Transparency。

## 架构

Familiar 整体划分为六层：

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
│ Agent Loop / Context Manager            │
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

```mermaid
flowchart TD
    Entry[System Entry Layer] --> Runtime[Agent Runtime]
    Runtime --> Registry[Capability Registry]
    Registry --> Policy[Execution Policy Layer]
    Policy --> Native[Native Layer: EventKit Vision MapKit PDFKit ...]
    Runtime --> State[State Layer: Session Memory Trace]
```

Agent Runtime 是最关键的一层：它只认识 `ToolDefinition`、`ToolCall` 与 `ToolResult`，从不直接触碰 EventKit、Vision、HealthKit 或 MapKit；这些都位于 Capability Registry 与 Execution Policy 之后。

### 系统入口

系统入口按优先级划分：

| 优先级 | 入口 |
| --- | --- |
| **第一优先级** | ① Familiar App 本身 · ② Share Extension · ③ 系统通知 / Deep Link |
| **第二优先级** | ④ Widgets / Controls · ⑤ Spotlight 等轻量系统入口 |
| **兼容能力** | ⑥ App Intents · ⑦ Shortcuts |

当前 System Entry Layer 已包含 Familiar App、Share Extension、类型化 Deep Link、Run 终态本地通知、受保护的 Spotlight 会话索引、启动 Widget、控制中心 Control、三项 App Intent 和双语 App Shortcut。Widget 打开新的可编辑草稿，Control 打开 Familiar 且不替换当前上下文。共享内容只在本机暂存，Deep Link 只恢复或预填上下文；`Ask Familiar` 与 `Process with Familiar` 会明确启动现有 App 内发送链路，`Open Familiar` 不改变草稿或会话。所有入口都不能授权工具操作。

App Intents 位于 Agent Core 之外。其文本输入有长度上限，不读取 Keychain，也不直接调用 Provider；存在未发送草稿时拒绝覆盖。完整 Capability Registry 不会复制到 App Intents。

## Agent Runtime

Familiar 采用单 Agent First 设计，核心是可组合的 Tool Loop：

```text
User
  → AgentRun
  → Context Assembler
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

Tool 使用强类型 Swift，Registry 再做 type erasure：

```swift
protocol NativeTool {
    associatedtype Input: Decodable & Sendable
    associatedtype Output: Encodable & Sendable

    static var manifest: ToolManifest { get }
    func execute(_ input: Input, context: ToolContext) async throws -> Output
}
```

`ToolManifest` 不只是名字：

```text
ToolManifest
  id
  title
  description
  effect        read / write / destructiveWrite
  risk          low / high
  requirements  EventKit, Calendar permission, ...
```

Familiar 内部借鉴 MCP 的思想但不把它当作内核，用原生 Swift 实现三种资源分离：

- **Resources** — 附件、当前位置、Workspace 文件、会话上下文、Memory（application-controlled）
- **Tools** — calendar.create、pdf.extract、maps.search、file.write（model-controlled）
- **Instructions** — Base Agent Policy、Skills（user-controlled）

> **MCP 是 Adapter，不是 Kernel。** 以后接入外部服务时通过 `MCPClient` 把 MCP Tools 转成 Familiar `AnyTool`，不需要修改基本架构。

## Capability Registry

Registry 才是 Familiar 真正的核心资产，组织成两大能力体系：

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

Native System 工具负责操作 iPhone 和用户的数字环境；Native Workspace 工具给 Agent 一个不依赖 Linux 的通用工作空间。当前设备、地区、系统版本、用户授权不可用的能力，直接不暴露给模型。

## 权限模型

Familiar 采用意图感知授权，而不是对每个写操作都弹窗：

| 操作 | 默认行为 |
| --- | --- |
| Read + 低风险 | 自动执行 |
| 明确的可逆写入 | 执行 + Undo |
| 推断出的写入 | 确认 |
| 敏感读取 | Permission / policy |
| 破坏性操作 | 确认 |
| 财务 / 外部重大影响 | 强确认 |

权限由代码控制，不靠 Prompt：模型无法用一句话绕过 HealthKit 权限、删除确认或敏感数据策略。

## Provider 支持

| 协议 | Provider |
| --- | --- |
| OpenAI Chat | OpenAI, DeepSeek, Groq, xAI, OpenRouter, Qwen, Kimi, GLM, MiniMax, SiliconFlow, custom OpenAI-compatible |
| Anthropic Messages | Anthropic |
| Gemini generateContent | Gemini |

每个 Provider 拥有独立 Keychain 项、端点配置、Header 和模型目录策略。模型能力按 `providerID + modelID` 标记；未知自定义模型默认仅文本。

模型层是简单的 `ModelProvider` 抽象，包含 OpenAI、Anthropic、OpenAI-compatible 与（可选的）本地 Provider。第一阶段先用能拿到的最强模型建立 Agent benchmark，再进行任何省 token 的模型拆分。

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

图片预处理是 Tool，不是强制 pipeline：根据 Agent 判断的任务需要，图片才走 Vision OCR、二维码检测或多模态模型，而不是默认先 OCR。

## 富文本渲染

助手回答由内置的非持久化 `WKWebView` 渲染，并且只使用本地资源。支持的输出包括 CommonMark 风格 Markdown、语法高亮代码块与代码复制、表格、引用、列表、Mermaid 图表、KaTeX 数学表达式和安全外链。

## 隐私与安全模型

- 无 Familiar 账号或登录流程。
- 无 Familiar 自建聊天后端或云数据库。
- 无订阅、权益或托管额度系统。
- API Key 按 Provider 保存在 iOS Keychain。
- 会话历史、附件和工具记录保存在本机。
- 流式 token 和等待中的确认不会被广泛持久化。
- 文档在本机转换；只有转换后的文字会随用户主动发起的请求发送。
- 只有调用相应工具时才请求日历或提醒事项访问权限。
- 写操作要求逐次确认，或提供明确的可逆撤销路径。
- 网站代码不包含广告、分析或跟踪脚本。

## 技术栈

| 领域 | 技术 |
| --- | --- |
| UI | SwiftUI |
| 本地持久化 | SwiftData |
| 网络 | URLSession、SSE streaming |
| 密钥 | iOS Keychain |
| 富文本 | WebKit 与内置 Markdown、Mermaid、KaTeX 资源 |
| 原生工具 | EventKit |
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
├── Attachments/    私有存储、转换与 OCR 链路
├── Data/           Provider 适配器、Keychain 与模型目录服务
├── Domain/         Provider、消息与能力模型
├── EventKit/       日历与提醒事项服务/工具
├── Persistence/    SwiftData Schema
├── Presentation/   SwiftUI 页面、输入器与消息渲染
├── Resources/      本地化、资产与内置渲染资源
├── Speech/         原生语音转写
└── Support/        主题与平台兼容辅助代码

FamiliarWidgets/    主屏幕/锁屏启动 Widget 与控制中心 Control

Vendor/
├── AnyDocBridge.xcframework/
└── AnyDocBridgeRust/

Docs/               产品、架构、UI、隐私和验证记录
website/            Vue/Vite 网站、隐私政策和支持页面
Scripts/            可复现的 AnyDoc XCFramework 构建脚本
```

详尽的产品与工程记录位于 [`Docs/`](Docs/README.md)。

## 环境要求

- Apple Silicon Mac
- Xcode 26 或更高版本
- iOS 18 或更高版本
- iPhone target
- 至少一个受支持模型 Provider 的有效 API Key

正常构建 App 不需要安装 Rust，因为仓库已包含 arm64 AnyDoc XCFramework。

## 构建 iOS App

```bash
git clone https://github.com/IsaacHuo/familiar.git
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
- 账号或工作区系统
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

Familiar 依据 MIT License 内置 AnyDoc，所需许可声明位于：

- `Vendor/AnyDocBridgeRust/LICENSE.anydoc`
- `Familiar/Resources/ThirdPartyNotices.txt`

其他内置渲染资源遵循各自上游项目的许可要求。

## 支持

- 产品支持：<https://isaachuo.github.io/familiar/support/>
- 隐私问题：<https://isaachuo.github.io/familiar/privacy/>
- Bug 反馈：<https://github.com/IsaacHuo/familiar/issues>

反馈问题时，请勿包含 API Key、私人会话、日历数据、提醒事项、文档或其他敏感信息。

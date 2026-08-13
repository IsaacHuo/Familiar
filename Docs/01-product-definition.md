# Familiar 产品定义

## 1. 产品标识

- 产品名称：Familiar
- 产品形态：iPhone-native Agent Runtime
- 最低系统：iOS 18
- 支持设备：iPhone
- 分发目标：公开 App Store
- 账户模式：无账户
- 计费模式：无订阅、无 Familiar 托管额度
- 模型接入：用户自备 API Key，设备直接请求 Provider
- 数据存储：会话、附件索引和工具记录保存在本机

## 2. 产品定位

> **Familiar = 一个 iPhone-native Agent Runtime。** 云端/可替换 LLM 负责理解、决策与编排；iOS 原生 Framework 负责感知、计算与行动；Native Workspace 提供通用内容处理能力。

Familiar 把 iPhone 的原生能力转成一个可组合的 Agent Runtime：

- 不以 Linux 为执行环境。
- 不依赖 Apple Intelligence。
- 不把每一个用户需求硬编码成 workflow。
- 不从复杂多 Agent 开始，坚持单 Agent First，通过清晰 Tools 扩展能力。

North Star：

> **Familiar turns the iPhone's native capabilities into a composable runtime for AI agents.**

与 OpenMinis 的稳定区别：

```text
OpenMinis  = AI + Linux Computer + Native Bridge
Familiar   = AI + Native iPhone Runtime + Native Workspace
```

最核心的技术资产最终不是支持 GPT 还是 Claude，也不是 UI，而是：

```text
Capability Registry
+ Agent Runtime
+ Execution Policy
+ Native Workspace
```

这四块做好以后，接入一个新的 Apple Framework、一个 MCP Server、一个新模型，都只是 Adapter，不再需要修改基本架构。

## 3. 产品目标

Familiar 为用户提供统一的移动问答与 Agent 执行入口。产品首发聚焦以下任务：

1. 使用用户选择的 AI Provider 完成文本问答。
2. 读取本机日历和提醒事项，回答时间安排相关问题。
3. 在意图感知授权下创建日历事件或提醒事项（明确可逆写入可执行 + Undo）。
4. 将本机文档转换为可发送的文本上下文。
5. 将语音转换为可编辑的输入草稿。
6. 在本机保存会话历史、Run/Step 执行记录和工具终态。

## 4. 核心用户任务

### 4.1 配置模型服务

用户可以在首启流程中选择 Provider、填写 API Key、选择或输入模型 ID，并执行连接验证。API Key 写入设备 Keychain，Provider 配置和偏好写入本地设置。用户也可以先跳过配置浏览聊天壳层、本地历史和设置；在真正发送模型请求前，仍必须完成 BYOK 配置。

### 4.2 连续对话

用户创建会话、发送文本或文档上下文、查看流式回答，并执行复制、分享、重试、编辑后重发等操作。会话记录实际使用的 Provider 和模型。

### 4.3 查询个人时间信息

用户可以提出日历事件和提醒事项查询。首次触发相关功能时，界面说明数据用途并请求系统权限。查询范围由工具参数限定。

### 4.4 创建日程或提醒

模型生成结构化写入请求。时间线展示目标日历或列表、标题、时间、备注、优先级等字段。低风险可逆写入可执行并支持 Undo；推断写入或破坏性写入要求确认。取消结果返回 Agent Loop，用于生成后续回答。

### 4.5 使用本机文档

用户从系统文件选择器添加文档。App 将文件复制到私有目录，通过 AnyDoc 转换为 Markdown。PDF 页面缺少文本层时使用 Vision OCR。发送给 Provider 的内容为抽取文本和文件名上下文。

### 4.6 使用语音输入

用户启动语音识别，转写结果持续写入输入框。转写文本保持可编辑状态。App 不创建音频消息，不保留原始录音文件。

## 5. 产品原则

### 5.1 LLM 决定做什么，Swift 决定怎么做

模型只生成结构化 Tool Call，不直接操纵 EventKit、文件系统、HealthKit，也不执行 arbitrary code。

### 5.2 Tool 是核心抽象

Calendar、Vision、PDF、Maps 最终都只是 Capability Registry 中的 Tool。Tool 要小、正交、可组合：做 `pdf.extractText`、`calendar.create`、`file.write`，不做 `summarizePDFAndCreateCalendarEvent`。

### 5.3 Native First

Apple 已有成熟 Framework 的能力直接调用原生 API。不重新实现 OCR、日历、地图、压缩、PDF 渲染之类的基础设施。

### 5.4 单 Agent First

Familiar v1 只有一个主 Agent。Subagent、Manager Agent、Graph orchestration 暂时不做。

### 5.5 权限由代码控制，不靠 Prompt

模型不能通过一句话绕过 HealthKit 权限、删除确认或敏感数据策略。Tool approval 和 guardrail 放在工具执行层。

### 5.6 Capability 动态注册

当前设备、地区、系统版本、用户授权不可用的 Tool，直接不暴露给模型。

### 5.7 所有执行必须可观察

一次 Agent Run 中发生的模型调用、Tool Call、失败、权限请求、耗时都必须能够 Trace。

### 5.8 先完成真实任务，再扩 Framework

判断新能力值不值得加入，只问：它能让 Familiar 完成哪个之前不能完成的真实任务？

### 5.9 复杂度必须由真实需求购买

MCP、Skills、Core ML、Background、Memory、Subagent 都是能力，不是 MVP 入场券。

## 6. 系统入口

系统入口按优先级划分：

| 优先级 | 入口 |
| --- | --- |
| **第一优先级** | ① Familiar App 本身 · ② Share Extension · ③ 系统通知 / Deep Link |
| **第二优先级** | ④ Widgets / Controls · ⑤ Spotlight 等轻量系统入口 |
| **兼容能力** | ⑥ App Intents · ⑦ Shortcuts |

当前已交付第一版 Deep Link 外壳：

- `familiar://new?text=...` 只打开新会话并预填草稿，不自动发送。
- `familiar://conversation/<UUID>` 打开本地会话。
- `familiar://run/<UUID>` 打开包含该 Run 的本地会话和现有时间线。
- Deep Link 不接受 API Key、Provider 配置或工具授权，也不能绕过 Agent Runtime 与 Execution Policy。

App Intents 不进入 Agent Core，位于外层：

```text
Siri / Shortcuts / Spotlight / Action Button / Widgets
                    │
                App Intents
                    │
            AgentRuntime.run()
```

第一批 App Intents 只需要：

- Ask Familiar
- Process with Familiar
- Open Familiar

绝不做 `CalendarCreateIntent`、`WeatherSearchIntent`、`PDFExtractIntent` 之类把整个 Capability Registry 复制到 App Intents。

## 7. 首发范围

### 7.1 包含

- 文本聊天与本地会话管理。
- 12 个内置 Provider。
- 自定义 OpenAI-compatible Provider。
- OpenAI Chat、Anthropic Messages、Gemini Generate Content 三类协议适配。
- 日历事件查询与创建。
- 提醒事项查询与创建。
- PDF、Office、OpenDocument、RTF、EPUB、CSV、TXT、Markdown 等文档导入。
- AnyDoc 本地 Markdown 转换。
- PDFKit 文本层检查与 Vision OCR。
- 图片选择、拍照、预览、移除和发送拦截。
- Apple Speech 转写。
- 简体中文和英文界面。

### 7.2 当前排除

- iPad 专用界面。
- 账户、登录、云端会话同步。
- Familiar 自建业务后端。
- 订阅、购买、权益和托管额度。
- Linux / iSH 执行环境。
- Shell 或任意代码执行。
- 多 Agent、Subagent、Agent Graph。
- 复杂 RAG、向量数据库。
- iPhone 上的 MCP Server（后期可能增加 MCP Client）。
- Core ML LLM、Apple Intelligence 依赖。
- 实时语音对话。
- 图片模型请求。
- 修改或删除现有日历事件和提醒事项。
- 读取学术系统或其他 App 的私有数据。
- 通用外部操作自动化。
- Plan / Build 模式（不照搬 Coding Agent 范式）。

## 8. MVP Benchmark

架构是否成功不看 Tool 数量，看这些任务能否端到端完成：

| Benchmark | 检验能力 |
| --- | --- |
| "明天下午有什么安排？" | Read Tool |
| "明天下午三点提醒我交作业" | Write Tool |
| 海报 → "加到日历" | Vision + LLM + Calendar |
| PDF → "考试什么时候？" | Workspace |
| PDF → 找时间 → 加 Calendar | Multi-tool |
| "看看周六安排和天气" | Parallel context |
| URL → 找活动 → 创建提醒 | Web + System |
| Tool 失败 → 自动修正/询问 | Recovery |

每一次提交影响 Agent 行为，都应该跑这些 benchmark。

## 9. 开发顺序

一个 Phase 没跑通端到端，就不进入下一个：

```text
Phase 1   Agent Loop → Tool Protocol → Dummy Tools → Trace
Phase 2   Calendar → Reminders → Policy/Approval → 完整端到端任务
Phase 3   Workspace: Files → PDF → Vision → Attachments
Phase 4   Web → Maps → Location → Weather
Phase 5   Task Timeline → Run persistence → Cancellation → Recovery
Phase 6   Share Extension → App Intents → Shortcuts
Phase 7   Memory → Background Tasks
Phase 8   Skills → MCP Client → Core ML specialized models
```

## 10. 发布门槛

1. Debug 和 Release 的 iPhone 构建通过。
2. iOS 18 arm64 Simulator 构建通过。
3. 写操作在未确认状态下零执行；可逆写入具备 Undo 路径。
4. Provider 错误、工具错误和文件错误不显示虚假成功。
5. 图片草稿被拦截时不创建消息、不上传图片、不清空草稿。
6. API Key 只进入 Keychain 和对应 Provider 请求。
7. 隐私用途说明与实际调用一致。
8. 内置模型 ID 失效时允许用户输入有效模型 ID，界面保持可恢复。
9. SwiftData 启动路径能够处理当前开发 Schema 与旧开发 store 的切换。
10. EventKit、相机、Speech 和安全作用域文件完成真机验收。

## 11. 产品成功条件

- 用户可独立完成 Provider 配置并发送首条消息。
- 会话中可稳定完成文本流式回答。
- 文档转换结果可进入模型上下文并保留原文件预览。
- 日历与提醒事项查询结果来源于 EventKit。
- 每次写入均具备确认记录和系统保存结果；Undo 路径可验证。
- 一次 Agent Run 可以被 Trace 并重放（Runtime Event 与 Run/Step 记录）。
- 关闭并重新打开 App 后，可查看已完成消息和工具终态。
- 系统拒绝权限时，App 提供明确状态和恢复入口。
- 入口调整后：Share Extension 能承接文本，Deep Link / 通知能回到对应任务上下文。

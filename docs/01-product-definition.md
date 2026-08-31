# Familiar 产品定义

> 本文描述**产品设计与目标**。当前实现状态见 `state/CURRENT.md`。

## 1. 产品标识

- 产品名称：Familiar
- 产品形态：iPhone 原生个人 AI 工作台
- 最低系统：iOS 18
- 支持设备：iPhone
- 分发目标：个人、非商业实验产品；当前不进入 App Store 或其他公开市场
- 账户模式：无账户
- 计费模式：无订阅、无 Familiar 托管额度
- 模型接入：用户自备 API Key，设备直接请求 Provider
- 数据存储：会话、附件索引和工具记录保存在本机

## 2. 产品定位

> **Familiar 是一个原生、安全、可检查的个人 AI 工作台。Chat 是主要交互和执行界面，Project 是长期 Context Workspace，单 Agent Runtime 是执行内核，原生工具与只读 Web 是执行能力。**

Familiar 把 iPhone 的原生能力转成一个可组合、可治理的执行面：

- 不以 Linux 为执行环境。
- 不依赖 Apple Intelligence。
- 不把每一个用户需求硬编码成 workflow。
- 不从复杂多 Agent 开始，坚持单 Agent First，通过清晰 Tools 扩展能力。

North Star：

> **让用户始终在 Chat 中完成事情，同时让 Project 为长期工作持续提供清晰、有边界、可检查的上下文。**

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

Project、ContextSnapshot 与这四块共同构成目标架构。Project 不是装聊天的文件夹，也不是功能 Dashboard；它统一承载 Project Instructions、Resources、Conversations、Skills、Artifacts、Runs / Trace、后续 Memory 与可用 Capability Scope，但完成任务的核心 Surface 始终是 Chat。

## 3. 产品目标

Familiar 为普通 iPhone 用户提供统一的移动问答与 Agent 执行入口。当前实验阶段聚焦以下任务：

1. 使用用户选择的 AI Provider 完成文本问答。
2. 读取本机日历和提醒事项，回答时间安排相关问题。
3. 创建日历事件或提醒事项；首次授权由用户明确产生，精确授权范围内可免重复确认，每次动作仍可检查，并保存跨重启 Undo 记录。
4. 将本机文档转换为可发送的文本上下文。
5. 将语音转换为可编辑的输入草稿。
6. 在本机保存会话历史、Run/Step 执行记录和工具终态。
7. 通过 Share Extension、Deep Link、Siri 与 Shortcuts 安全进入同一套草稿和 Agent Runtime。
8. 使用只读 Web Search/Fetch 获取公开 HTTPS 内容，并在回答中保存和展示来源。

核心目标：使多条对话、长期资料与执行记录属于同一个有边界的工作上下文（Project）。

## 4. 核心用户任务

### 4.1 配置模型服务

用户可以在首启流程中配置当前启用的 DeepSeek 服务、填写 API Key、选择或输入模型 ID，并执行连接验证。API Key 写入设备 Keychain，Provider 配置和偏好写入本地设置。底层仍使用通用 ModelProvider/OpenAI-compatible adapter，不把 Agent Runtime 绑定到 DeepSeek。

### 4.2 连续对话

用户创建会话、发送文本、文档或图片上下文、查看流式回答，并执行复制、分享、重试、编辑后重发等操作。会话记录实际使用的 Provider 和模型。DeepSeek 是当前主要真实验收 Provider，`deepseek-v4-flash` 是默认主模型；架构不应把运行时绑定到 DeepSeek 专用协议。

### 4.3 查询个人时间信息

用户可以提出日历事件和提醒事项查询。首次触发相关功能时，界面说明数据用途并请求系统权限。查询范围由工具参数限定。

### 4.4 创建日程或提醒

模型生成结构化写入请求。首次授权时，动作卡展示目标日历或列表、标题、时间、备注、优先级等字段；用户可以选择“仅这次 / 本次会话 / 始终允许”，默认“本次会话”。授权按 Project、工具和目标精确隔离，参数或作用域越界时重新确认。有效授权范围内可以直接执行，但每次动作仍展示同一张动作卡；EventKit create 保存跨重启 Undo 记录。取消、失败、成功和撤销结果都返回 Agent Loop 并保留可检查终态（见 `02-system-architecture.md` 2.4）；真机边界仍待验证。

### 4.5 使用本机文档与项目资料

用户从系统文件选择器添加文档。App 将文件复制到私有目录，通过 AnyDoc 转换为 Markdown；PDF 页面缺少文本层时使用 Vision OCR。发送给 Provider 的内容为抽取文本和文件名上下文。在 Project 中导入的文档保存为带版本和 lineage 的 Project Resource，支撑跨对话的长期上下文；Project 名称全局唯一，比较时不区分大小写。

### 4.6 使用图片

选择 `deepseek-v4-flash-vision-exp` 时，图片字节只发往当前 DeepSeek endpoint；该实验 ID 的真实可用边界必须通过账户冒烟确认。选择文本模型时，Familiar 使用 Apple Vision 提取 OCR、条码和基础分类证据，再将带来源、方法和可信度说明的只读证据交给当前模型。不会自动切换到实验视觉模型。

FastVLM 当前暂停提供，不显示安装入口，也不参与图片自动路由。Core AI/Qwen 是 iOS 27 正式可用后的本地文本模型方向。

### 4.7 使用语音输入

用户启动语音识别，转写结果持续写入输入框。转写文本保持可编辑状态。App 不创建音频消息，不保留原始录音文件。

### 4.8 显式使用 Skill

用户可以在普通聊天或项目聊天的 Composer 中显式选择一个已安装 Skill，选择只作用于下一次 Run。Project 也可绑定候选 Skill；Run 开始时仅暴露 metadata，Agent 在 planning 阶段通过 `skill_read` 按需加载至多一个。两条路径都只注入指令并收窄 Tool Scope，不能授予权限或绕过确认；当前仍没有 Skill 目录导入、scripts、references 或 assets。

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

### 5.6 Capability 可用性过滤

当前设备、地区、系统版本、用户授权不可用的 Tool 不暴露给模型。目标 Registry 具备运行时发现、安装、启停、版本治理与项目绑定。

### 5.7 所有执行必须可观察

一次 Agent Run 中发生的模型调用、Tool Call、失败、权限请求、耗时都必须能够 Trace。

### 5.8 先完成真实任务，再扩 Framework

判断新能力值不值得加入，只问：它能让 Familiar 完成哪个之前不能完成的真实任务？

### 5.9 复杂度必须由真实需求购买

MCP、Skills、Core ML、Background、Memory、Subagent 都是能力，不是 MVP 入场券。

### 5.10 能力不足时补齐输入，不伪装模型能力

Provider 原生能力、设备端预处理和可选本地模型是不同的数据处理路径。Familiar 可以为纯文本模型提供视觉证据，但必须标明证据来源，不能声称文本模型直接看见了图片，也不能未经用户选择把图片发送到另一个 Provider。

## 6. 系统入口

系统入口按优先级划分：

| 优先级 | 入口 |
| --- | --- |
| **第一优先级** | ① Familiar App 本身 · ② Share Extension · ③ 系统通知 / Deep Link |
| **第二优先级** | ④ Widgets / Controls · ⑤ Spotlight 等轻量系统入口 |
| **兼容能力** | ⑥ App Intents · ⑦ Shortcuts |

设计约束（交互细节见 `03-ui-ux-design.md`）：

- Deep Link 只接受有长度上限的草稿文本或本地会话 / Run UUID；不自动发送、不承载 API Key，也不授予工具写权限。
- Share Extension 只把用户明确共享的文本、URL 和文件复制到 App Group 收件箱；扩展不读取 Keychain、Provider 配置或 EventKit 数据。
- Run 终态通知是用户可选的本地通知，不使用远程推送，只包含通用状态与本地 Run / 会话标识。
- Spotlight 使用受保护的设备内索引，只保存会话标题、更新时间和本地 UUID。
- Widget / Control 只暴露轻量动作，不复制完整聊天界面。
- App Intents 只暴露 `Ask Familiar`、`Process with Familiar`、`Open Familiar`，不复制 Capability Registry，不能授权工具写入。
- 所有入口最终汇入同一个 Agent Runtime。

## 7. 当前实验范围

### 7.1 包含

- 文本聊天与本地会话管理。
- 当前唯一启用的 Provider descriptor 是 DeepSeek；底层 Provider/Agent 接口保持通用。
- 通用 OpenAI-compatible Chat Completions SSE adapter。
- 日历事件与提醒事项的查询与创建；精确授权、动作卡审计和跨重启 Undo 记录已接入，真机验收仍待完成。
- 只读 `web_search`、`web_fetch` 与回答来源记录。
- PDF、Office、OpenDocument、RTF、EPUB、CSV、TXT、Markdown 等文档导入；AnyDoc 本地转换、PDFKit 文本层检查与 Vision OCR。
- 图片选择、拍照和预览；DeepSeek 实验视觉模型发送，以及文本模型的 Apple Vision 基础证据 fallback。
- Apple Speech 转写。
- Project / Resource / Artifact / ContextSnapshot 主链路。
- Composer 显式选择、仅作用于下一次 Run 的 instruction-only Skill。
- 简体中文和英文界面。

### 7.2 当前排除

- FastVLM 下载、设置入口和自动推理路由。
- iOS 27 正式发布前的 Core AI/Qwen 真实 Runtime。

- iPad 专用界面。
- 账户、登录、云端会话同步。
- Familiar 自建业务后端。
- 订阅、购买、权益和托管额度。
- Linux / iSH 执行环境。
- Shell 或任意代码执行。
- 多 Agent、Subagent、Agent Graph。
- 复杂 RAG、向量数据库。
- iPhone 上的 MCP Server（后期可能增加 MCP Client）。
- Apple Intelligence 依赖；通用本地文本 LLM 不进入当前范围。
- 实时语音对话。
- 修改或删除现有日历事件和提醒事项。
- 读取学术系统或其他 App 的私有数据。
- 通用外部操作自动化。
- Plan / Build 模式（不照搬 Coding Agent 范式）。

## 8. MVP Benchmark

架构是否成功不看 Tool 数量，看这些任务能否端到端完成。以下为产品目标场景，由 `FamiliarBenchmarkTests` 的 fake-provider runner 以确定性方式运行：

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

每一次影响 Agent 行为的提交，都应通过 fake-provider runner 记录成功率、工具序列、审批结果、耗时和成本。真实 Provider 验收见 `11-verification-and-release-checklist.md`。

## 9. 长期路线图

路线图见 `10-next-phase-execution-plan.md`。可验证内核、Project/Context/Workspace、只读 Web、能力契约与一次性显式 Skill 已形成当前基础；Remote MCP、Memory Runtime 与后台承接仍是后续目标。

## 10. 实验交付门槛

1. Debug 和 Release 的 iPhone 构建通过。
2. iOS 18 arm64 Simulator 构建通过。
3. 写操作在未确认状态下零执行；可逆写入具备 Undo 路径。
4. Provider 错误、工具错误和文件错误不显示虚假成功。
5. 图片按当前模型能力路由：原生多模态模型直收图片，纯文本模型使用本地视觉证据；所有路径失败时明确说明能力边界并保留可恢复输入。
6. API Key 只进入 Keychain 和对应 Provider 请求。
7. 隐私用途说明与实际调用一致。
8. 内置模型 ID 失效时允许用户输入有效模型 ID，界面保持可恢复。
9. SwiftData 启动路径使用单一 `FamiliarReleaseSchema` 的当前 36 实体，不配置 migration plan；Debug/Release store 分离，测试阶段不支持旧 store。
10. EventKit、相机、Apple Vision、Speech 和安全作用域文件完成真机验收。
11. 通知权限只在用户明确开启时请求；关闭后不再安排 Familiar 通知，并清理待处理与已投递通知。
12. Spotlight 结果只暴露受保护的本地会话标题和 UUID，点击后能回到存在的本地会话；删除会话后对应结果被清理。

## 11. 产品成功条件

- 用户可独立完成 Provider 配置并发送首条消息。
- 会话中可稳定完成文本流式回答。
- 文档转换结果可进入模型上下文并保留原文件预览。
- 日历与提醒事项查询结果来源于 EventKit。
- 每次写入均具备授权依据和系统保存结果；跨重启 Undo 路径可验证。
- 一次 Agent Run 可以查看摘要执行轨迹；严格重放与恢复依赖 Context/Capability/Authorization snapshot 与 ResumeCursor。
- 关闭并重新打开 App 后，可查看已完成消息和工具终态。
- 系统拒绝权限时，App 提供明确状态和恢复入口。
- 入口调整后：Share Extension 能承接文本，Deep Link / 通知能回到对应任务上下文。

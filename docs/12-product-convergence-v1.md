# Familiar Product Convergence v1

> 本文记录本轮产品收敛的产品架构、信息架构与能力取舍。实现事实仍以 `state/` 和代码为准。

## 1. 产品模型

Familiar 统一为一个原生 iPhone AI Workspace：

> Chat 是主要交互和执行界面。Project 是长期 Context Workspace。Agent Runtime 是执行内核。Native iPhone Capabilities 是执行能力。

四层职责保持单一：

| 层级 | 用户理解 | 产品职责 |
| --- | --- | --- |
| Chat | 在这里提问和完成事情 | 输入、回答、执行状态、授权与结果 |
| Project | Familiar 持续了解这件事的地方 | 指令、资料、对话、Artifacts、Runs 与后续 Memory 的共同边界 |
| Agent Runtime | 不暴露为用户导航 | 组装上下文、调用模型与工具、执行 Policy、产生 Runtime Events |
| Native Capabilities | 在需要时出现的能力 | 以类型化工具连接 Web、文件和 Apple Frameworks |

普通 Chat 与 Project Conversation 共用同一个 Chat Surface、Composer、Runtime、授权和执行 Surface。两者的差别只在上下文边界：普通 Chat 适合临时问题和一次性任务；Project Conversation 会冻结并使用所属 Project 的指令、资料版本和能力范围。Skills 是全局安装项，没有 Project binding；用户可以在普通或项目聊天的 Composer 中显式选择一个 Skill，该选择只快照到下一次 Run，随后清除。

## 2. 信息架构审计

### 2.1 收敛前的问题

本轮开始时，Project Home 同时突出 Hero、Continue Chat、New Chat、Ask Familiar、Resources、Conversations、Artifacts、Skills 和 Runs。`Ask Familiar` 会新建并立即发送 Project Conversation，与 Continue/New Chat 属于同一任务链路，形成三个相互竞争的执行入口。五个内容模块又全部使用一级 List Section，导致长期上下文容器看起来更像功能 Dashboard。

当时 Project Conversation 虽然已经复用主 Chat Surface，界面却没有表达当前 Project 归属。用户离开 Project Home 后无法直接理解资料、指令和 Skill 为什么会进入当前对话。Chat 顶栏同时提供设置按钮，抽屉底部也有设置入口，进一步增加主任务之外的视觉权重。

### 2.2 当时确定的一级结构

```text
Familiar
├── New Chat
├── Projects
│   ├── Project Home
│   │   ├── Continue / New Chat
│   │   ├── Resources
│   │   ├── Artifacts
│   │   └── Project Context
│   │       ├── Conversations
│   │       ├── Skills
│   │       └── Runs
│   └── Project Conversation -> shared Chat Surface
├── Recent Conversations
├── Search
└── Settings
```

Project Home 不承担执行器职责。它帮助用户确认 Familiar 当前掌握什么，并尽快回到 Chat：

1. 主动作是继续最近一条 Project Conversation；没有历史时为新建 Project Chat。
2. 次动作是新建 Project Chat，仅在已有历史时出现。
3. 删除独立 `Ask Familiar` 输入框。提问、发送、附件和语音统一由 Composer 承担。
4. Resources 与 Artifacts 是用户可直接识别的上下文输入和输出，在主页展示最近内容并提供完整列表。
5. Conversations、Skills 与 Runs 合并为紧凑的 Project Context 导航组。它们可检查，但不与继续工作争夺视觉焦点。
6. 归档、删除与 Project 编辑留在导航栏菜单和编辑流程，不占用主内容区。

### 2.3 当时确定的 Chat 与 Project 连接

Project Conversation 的顶栏只增加一个 Project 标识，显示 Project 名称并允许返回该 Project Home。它是唯一的常驻归属表达，不再叠加 Banner、第二个 context pill 或大块说明。

顶栏控制按重要性排列：

```text
Drawer | Model | Project context when present | spacer | New Chat
```

设置只从抽屉进入。普通 Conversation 不显示 Project 标识。新建按钮继承当前 Conversation 的 Project 归属，因此在 Project 中继续创建的仍是 Project Chat。

### 2.4 实现结果

后续实现保留了“单一 Chat Surface”和“Project 是上下文边界”的核心判断，但根据移动端实际使用进一步调整了入口：

- Chat 顶栏当前从左到右为 Settings、工作区文件夹、模型菜单和新对话。工作区文件夹负责在普通聊天与项目之间切换，并提供当前项目详情和“全部项目”入口；侧栏不再重复 Settings 或 New Chat。
- 切换工作区时恢复该范围内最近更新的会话。没有历史或主动新建时，只更新临时的项目范围，不提前创建空会话；首次发送并保存用户消息时才持久化 Conversation。
- 侧栏从左边缘打开，包含置顶项目与对话、可展开的项目历史、“全部项目”、最近普通对话和统一搜索。项目展开使用轻量动画，并在 Reduce Motion 开启时直接切换。
- 抽屉项目行点击或尾部箭头用于展开历史，长按提供置顶和项目详情；“全部项目”列表中的项目行进入项目主页。项目创建与重命名统一去除首尾空白、限制长度，并执行不区分大小写的全局名称唯一性校验。
- Project Home 删除了独立 Ask 输入框；当前紧凑 Project Context 导航只展示 Conversations 与 Runs。Skills 在 Settings 中全局安装，通过右上角加号和指令模板创建，没有 JSON 导入行，也没有 Project binding；普通或项目聊天都必须从 Composer 显式选择一个 Skill，且只作用于下一次 Run。
- 助手回答下方的复制、系统分享、重试按此顺序与正文左边缘对齐。

## 3. Design System 范围

Design System 继续建立在 SwiftUI 和 `FamiliarTheme` 上，不新增第三方组件库。核心页面只使用有限的语义令牌：

- Spacing：最小间距、控件内部间距、内容间距、Section 间距和页面边距。
- Typography：大标题、屏幕标题、Section 标题、正文、次级正文、Caption、按钮和 Metadata，全部建立在 Dynamic Type Text Styles 上。
- Radius：小型控件、标准控件、卡片和浮层四档。
- Icon：紧凑、标准、强调三档视觉尺寸；触控区域独立保持至少 44 pt。
- Controls：Primary、Secondary、Icon、Circular、Toolbar、Pill、Destructive 和 Inline Action。
- Surface：Glass 只用于导航、Composer 和临时 Overlay；内容使用系统背景、List、轻量分组或必要的 Action Surface。

本轮优先替换 Chat、Composer、Drawer、Project、Settings 和 Agent Surface 的任意值，不机械清扫低频或与主流程无关的全部页面。

## 4. OpenMinis Capability Matrix

OpenMinis 当前公开产品把本机 Linux、浏览器自动化、Skills、持久 Memory、Workspaces 和深度系统集成组合为一个跨平台 Agent。Familiar 只比较能力覆盖，不复制其以 Linux computer 为中心的产品结构。来源为 [OpenMinis 主仓库 README](https://github.com/OpenMinis/OpenMinis)；平台材质边界遵循 [Apple Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)。

| Capability | OpenMinis | Familiar Current | Native Familiar Equivalent | Status | Decision |
| --- | --- | --- | --- | --- | --- |
| Workspace | 独立 Workspaces 与 URL 寻址 | Project、Instructions、Resources、Conversations、Artifacts、Runs | Project Context Workspace | Already covered | 收敛入口和层级，不新增容器 |
| Skills | `SKILL.md`，可含 scripts、references、assets | 全局安装的 instruction-only Skill；普通或项目聊天从 Composer 显式选择一次，无 Project binding | 安全的显式 instruction package | Already covered | 保持无脚本模型，不追求格式 parity |
| Memory | 跨会话持久 Memory | V8 数据与基础服务，Runtime 行为未开放 | 后续 global/project/conversation Memory tools | Valuable future capability | 只写 roadmap，本轮不实现 |
| Web | 浏览与交互自动化 | 只读 `web_search` / `web_fetch`，可保存为 Resource | 受限只读 Web + Safari 用户交互 | Native alternative | 保持只读，不加入浏览器自动化 |
| System Integration | Health、Calendar、Reminders、Contacts、HomeKit 等工具 | EventKit、Speech、Vision、系统入口与类型化 Tool Runtime | Apple Framework adapters + Swift Policy | Native alternative | 真实任务驱动逐项加入，不做 parity |
| Files | Linux 文件系统与 mounted workspaces | 私有附件、版本化 Resources、Artifacts、Quick Look | Files picker + sandboxed stores + native preview | Native alternative | 强化 Workspace 呈现，不加入通用文件系统 |
| Media | Shell/native offload 处理多媒体 | Photos、Camera、Vision、可选 FastVLM、Speech | Apple media frameworks 与受控本地模型 | Already covered | 保持当前边界 |
| Background Tasks | 可由系统入口和 Agent 工作流承接 | 只有终态通知；可靠后台执行未实现 | 可恢复 AgentRun 后再接 iOS background APIs | Valuable future capability | 不在本轮实现，不承诺可靠续跑 |
| Automation | Shell、Shortcuts 与浏览器可组成自动化 | App Intents/Shortcuts 只进入现有 Runtime；无定时自动化 | 明确系统入口 + 授权 Policy | Valuable future capability | 等 resumable runtime 与真实需求 |
| Agent Execution | 模型 + Linux shell + native tools | 单 Agent Runtime + typed tools + Policy + Runtime Events | 单 Agent Native Runtime | Already covered | 保持内核稳定 |
| Share / System Entry | Share Sheet、workspace URL 等 | Share Extension、Deep Link、通知、Spotlight、Intents、Widget/Control | 全部汇入同一 Chat Runtime | Already covered | 只收敛入口，不扩张 |
| Linux shell | 核心能力 | 无 | 无 | Intentionally excluded | 不引入 shell 或任意代码执行 |
| Browser automation | 可代表用户操作网页 | 无 | Safari 由用户直接操作 | Intentionally excluded | 不引入自动点击与表单操作 |

## 5. 决策检查

- 首次进入 App，顶栏的新对话与工作区文件夹构成两个清晰起点；抽屉负责恢复历史和搜索。
- 普通 Chat 与 Project 的差别由 Project Home 的上下文内容和 Chat 顶栏工作区文件夹的当前选择共同说明。
- 用户在 Project Home 看到资料、结果和可检查的 Context 摘要，但完成任务仍回到 Chat。
- 删除独立 Ask 输入框、侧栏中的重复设置入口和多个同权 Section 后，主路径更短。
- 视觉强调顺序固定为继续工作、创建新 Chat、管理上下文、审计细节。

## 6. 本轮非目标

本轮不实现 MCP、Durable Memory Runtime、Multi-Agent、Linux、Shell、Browser Automation、新 Provider、新模型框架、新数据库架构或 Runtime 大规模重写。Memory、后台承接和自动化只保留为已知未来能力。

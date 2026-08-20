# Familiar 参考代码仓库

## 1. 用途

当实现 Familiar 的 Agent Runtime、Tool、协议适配、MCP Adapter 和本地视觉能力时，参考以下仓库。它们不是实现终点，只是当前阶段可对照的实现参考；后续可以继续扩充参考面。

参考时遵守 AGENTS.md 与 Docs 中的原则：Native First、单 Agent First、简单优先、MCP 是 Adapter 不是 Kernel、权限由代码控制、不直接照搬第三方代码。

## 2. 参考仓库

| 仓库 | 来源 | 本地副本 | 许可证 | 核心参考点 |
|---|---|---|---|---|
| swift-sdk（MCP Swift SDK） | [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) | `achieve/swift-sdk-main` | MIT → Apache-2.0 过渡 | MCP client 协议、Tools/Resources/Prompts 建模 |
| OpenMinis | [OpenMinis/OpenMinis](https://github.com/OpenMinis/OpenMinis) | 未纳入仓库（回上游对照） | GPL-3.0 | Linux/Shell 广度、Native Offload、Skills/Memory/Workspace 对照 |
| Swarm | [christopherkarani/Swarm](https://github.com/christopherkarani/Swarm) | `achieve/Swarm-main`（当前为空目录，未拉取内容） | MIT | Swift 原生 Agent/Workflow 循环的工程组织 |
| ModLens | [liustack/modlens](https://github.com/liustack/modlens) | 未纳入仓库（回上游对照） | MIT | 纯文本模型的视觉证据、能力检测、Provider 路由与降级语义 |
| FastVLM | [apple/ml-fastvlm](https://github.com/apple/ml-fastvlm) | 未纳入仓库（回上游对照） | 代码与模型分别授权；模型仅限非商业研究 | iOS 18.2+ 本地 VLM、Core ML + MLX 推理和移动端性能基准 |

本地副本位于仓库内 `achieve/` 目录（不参与 App 构建，仅作参考）。该目录当前未完整维护，主要参考仍以各上游仓库为准。

## 3. 参考点

### 3.1 swift-sdk（MCP Swift SDK）

- MCP client 与协议类型：JSON-RPC、Transport、会话与生命周期。
- Tools / Resources / Prompts 的建模、错误处理、取消与进度跟踪。
- 为将来接入外部服务做准备：重点研究 Streamable HTTP、OAuth/PKCE、分页、server change detection、取消，并把 MCP Tools 转成 Familiar Manifest。

边界：Familiar 内部用原生 Swift，不把 MCP 当内核，也不把该 SDK 作为运行依赖。参考它用于理解 MCP 协议细节与 client 实现。

### 3.2 OpenMinis

- Native Offload 模式：重活或平台相关任务交给 native code。
- 设备能力以 Tools 暴露：日历、提醒事项、通讯录、健康、剪贴板等。
- 架构取舍对照：

```text
OpenMinis  = AI + Linux Computer(iSH/Alpine) + Native Bridge
Familiar   = AI + Native iPhone Runtime + Native Workspace
```

Familiar 不复制 Linux/Shell 路线。目标以 Project + Resource + Artifact 建立 Native Workspace；当前只有附件处理。

边界：OpenMinis 使用 GPL-3.0，仅作架构参考，不复制其代码。

### 3.3 Swarm

- Swift 原生 Agent / Workflow 循环的工程组织。
- Tool 定义与多步执行的 Swift 实现。

边界：Familiar 单 Agent First，不照搬多 Agent / Graph 编排；Swarm 的较新平台要求不作为 iOS 18 主 Runtime 依赖，仅作 workflow、checkpoint/resume 和 eval 的架构对照。

### 3.4 ModLens

- 参考按当前模型能力决定是否需要视觉 bridge。
- 参考将 OCR、版面和语义描述组织为结构化 evidence，再交给原文本模型。
- 参考明确记录视觉引擎、尝试和降级，不让 fallback 静默发生。

边界：ModLens 是 Node.js 22 / DeepSeek Harness 插件，不能直接嵌入 iOS。它本身仍依赖 Gemini、OpenAI-compatible、Anthropic 或本机 CLI 提供视觉能力，并不能只用 DeepSeek API Key 识图。Familiar 只借鉴其证据和路由设计，设备端实现使用原生 Swift、Apple Vision 和可选本地 VLM。

### 3.5 FastVLM

- 参考 Apple 官方 iOS Demo 的 Core ML 视觉编码器、MLX/MLXVLM 语言模型加载和本地生成路径。
- 当前个人实验只评估 `FastVLM-0.5B`，官方预转换下载约 1.23 GB。
- 模型安装、基准、超时、内存失败和 Apple Vision 降级由 Familiar 自己治理。

边界：FastVLM 官方模型权重仅限非商业科学研究和学术开发。当前个人非商业实验可以使用；公开分发、商业使用或提供给第三方前必须停止沿用当前权重并重新取得许可或更换模型。必须保留 `LICENSE_MODEL`、归属声明和第三方 acknowledgements。官方未承诺中文图片问答质量或统一最低设备内存。

## 4. 使用规则

- 先读对应参考实现，再写代码；结论以本项目 Docs 与 AGENTS.md 为准。
- 不直接复制代码。涉及 GPL（OpenMinis）等内容仅作架构参考；复制任何第三方代码前确认许可证并保留 notice。
- 参考面可扩充：发现新的成熟原生实现时，可以补充进本文件。
- 每一条参考都应对应一个真实设计点，避免"参考仓库越多越好"。

## 5. 维护规则

以下改动需要更新本文件：

- 新增或移除参考仓库。
- 某仓库的参考点、许可证或来源变化。
- 参考边界与项目原则出现冲突。

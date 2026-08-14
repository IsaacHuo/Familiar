# Familiar 产品与工程文档

本目录记录 Familiar 个人 AI 工作台的产品定义、项目与上下文模型、系统架构、交互设计、Agent 运行机制、本地数据边界、工程状态和关键决策。文档面向产品设计、iOS 开发、测试、隐私审核和发布审核。

## 文档目录

| 文档 | 内容 |
|---|---|
| [01-product-definition.md](01-product-definition.md) | 产品定位、Agent Runtime 原则、入口优先级、任务、范围、Benchmark、开发顺序 |
| [02-system-architecture.md](02-system-architecture.md) | 六层架构、Agent Runtime、Capability Registry、Execution Policy、Native Workspace、并发模型、平台适配 |
| [03-ui-ux-design.md](03-ui-ux-design.md) | 信息架构、聊天界面、输入器、系统入口、Runtime Event 执行界面、视觉和无障碍 |
| [04-agent-provider-and-content-pipeline.md](04-agent-provider-and-content-pipeline.md) | Provider、协议适配、Agent Runtime、Tool 设计、意图感知授权、Memory、Skills、内容链路 |
| [05-local-data-and-privacy.md](05-local-data-and-privacy.md) | SwiftData、附件、Run/Step、Memory、Keychain、权限、数据生命周期、恢复策略 |
| [06-engineering-status-and-validation.md](06-engineering-status-and-validation.md) | 当前实现状态、与目标架构的差距、验证记录、待验证项目、发布门槛 |
| [07-decision-log.md](07-decision-log.md) | 关键产品和工程决策、依据、影响、复审条件 |
| [08-reference-repositories.md](08-reference-repositories.md) | 实现代码时的参考仓库（swift-sdk、OpenMinis、Swarm）、参考点、许可证与使用规则 |
| [09-ui-component-reference.md](09-ui-component-reference.md) | 聊天页模型回复 UI 的 Beautiful UI 组件源码摘录、CSS 令牌、外部依赖与 Familiar 适配建议 |
| [10-next-phase-execution-plan.md](10-next-phase-execution-plan.md) | 基于 2026-08-13 深度评估形成的下一阶段实施顺序、工作包、验收标准和停止条件 |
| [11-real-provider-smoke-checklist.md](11-real-provider-smoke-checklist.md) | 真实 Provider 的认证、流式协议、错误、取消和工具闭环手工验收清单 |
| [阶段性分析/familiar-project-workspace-flow.md](阶段性分析/familiar-project-workspace-flow.md) | Project 与内部 Workspace 的产品流程、对象关系和端到端验收任务 |

## 状态术语

文档使用以下状态，避免将设计目标写成已交付能力。

| 状态 | 定义 |
|---|---|
| 已实现 | 对应代码已经进入 `main`，可通过路径和符号定位 |
| 部分实现 | 已有代码基础，但尚未形成目标能力的完整闭环 |
| 已构建 | 指定目标已完成 `xcodebuild`，构建结果成功 |
| 已进行本地验证 | 已在 Simulator、本地 fixture 或命令行环境运行 |
| 待真机验证 | 依赖相机、麦克风、Speech、EventKit 或真实文件环境 |
| 待真实服务验证 | 依赖有效 API Key 和 Provider 在线响应 |
| 设计约束 | 产品范围或安全要求，后续实现应持续遵守 |
| 目标架构 | 已确定方向但尚未实现，不得当作当前能力宣传 |
| 预览 UI | 只有展示或占位，未接入持久化、Runtime 或 Policy |
| 后续候选 | 未进入当前发布范围，不构成承诺 |

## 写作规范

1. 直接陈述目标、事实、约束、机制和结论。
2. 每项能力标明实现状态和事实来源。
3. 产品目标与代码现状分段记录。
4. 风险使用可复现条件、影响范围和处理策略描述。
5. 验收项使用可观察结果描述。
6. 文案避免宣传口号、拟人化表达和无依据的程度词。
7. 文案禁用预设读者误解后再反转的句式。

## 事实优先级

当前实现事实按以下顺序取证：

1. `familiar.xcodeproj/project.pbxproj` 与 App 配置。
2. `Familiar/` 下的当前实现。
3. `Vendor/AnyDocBridgeRust/`、`Vendor/AnyDocBridge.xcframework/` 与构建脚本。
4. 已执行的构建、测试和运行日志。
5. 产品计划与发布要求。

产品定位、架构方向和实施优先级以 [`阶段性分析/Familiar_deep_product_and_architecture_review_2026-08-13.md`](阶段性分析/Familiar_deep_product_and_architecture_review_2026-08-13.md) 为准。阶段性专题报告提供研究材料；具体顺序由 [10-next-phase-execution-plan.md](10-next-phase-execution-plan.md) 统一。

当代码、计划和验证结果存在差异时，文档分别记录三者，不合并为单一结论。

## 维护规则

以下改动需要同步更新本目录：

- SwiftData Schema 或本地存储地址变化。
- Project、Resource、Artifact、ProjectInstruction、Binding 或 Memory scope 变化。
- Provider、模型能力、协议适配和认证字段变化。
- 工具定义、权限范围、确认流程或写入行为变化。
- Capability Registry 的能力体系或动态注册规则变化。
- ContextSnapshot、CapabilitySnapshot、AuthorizationGrant 或 ResumeCursor 变化。
- Runtime Event 事件流、Run/Step 数据模型或执行轨迹变化。
- 系统入口（Share Extension、Deep Link、Widgets/Controls、Spotlight、App Intents、Shortcuts）变化。
- 附件格式、大小限制、OCR 或 AnyDoc 流程变化。
- 图片发送、音频处理或外部数据传输范围变化。
- 首启、抽屉、时间线、输入器和设置的信息架构变化。
- 参考仓库的新增、移除或参考点变化。
- UI 组件参考中组件的增删、源码更新或适配结论定型。
- Benchmark 场景、执行结果、CI 门槛或后台执行保证等级变化。
- App Store 隐私说明、用途说明或支持页面变化。

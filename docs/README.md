# docs/ — 设计与规划

`docs/` 回答的问题是：**我们打算构建什么，以及为什么。**

它承载产品设计、产品理念、UX/UI 设计、技术方案、Architecture Proposal、Research、RFC、长期规划，以及重要技术决策背后的 rationale。

本目录与当前实现状态的区分：

```text
docs/   → 打算构建什么、为什么（设计、目标、rationale）
state/  → 现在实际存在什么（以代码为准，见 ../state/README.md）
logs/   → 可复用的调查经验（见 ../logs/README.md）
git     → 普通代码改动历史
```

`docs/` 与 `state/` 允许存在差异。例如 `docs/` 规划未来采用 Architecture B，而 `state/` 显示当前仍运行 Architecture A，这是正常状态；不要为了让两边一致而伪造当前实现。

## 文档目录

| 文档 | 内容 |
|---|---|
| [01-product-definition.md](01-product-definition.md) | 产品定位、North Star、用户任务、产品原则、系统入口优先级、首发范围、Benchmark、发布门槛、成功条件 |
| [02-system-architecture.md](02-system-architecture.md) | 目标六层架构与各层设计、目标 Capability Registry / Execution Policy / State Layer、架构约束 |
| [03-ui-ux-design.md](03-ui-ux-design.md) | 信息架构、聊天界面、输入器、系统入口交互约束、Runtime Event 执行界面、视觉、无障碍 |
| [05-local-data-and-privacy.md](05-local-data-and-privacy.md) | 数据处理原则、数据清单、持久化时点、文件系统/Keychain 设计、权限表、威胁与控制、删除语义 |
| [07-decision-log.md](07-decision-log.md) | 关键产品和工程决策、依据、影响、复审条件 |
| [08-reference-repositories.md](08-reference-repositories.md) | 实现代码时的参考仓库、视觉能力参考、许可证与使用规则 |
| [09-ui-component-reference.md](09-ui-component-reference.md) | 聊天页模型回复 UI 的 Beautiful UI 组件源码摘录、CSS 令牌与 Familiar 适配建议 |
| [10-next-phase-execution-plan.md](10-next-phase-execution-plan.md) | 当前 DeepSeek-only enablement 的 API/视觉/Tool 闭环收尾顺序，以及 iOS 27 后恢复 Core AI 的门槛 |
| [11-verification-and-release-checklist.md](11-verification-and-release-checklist.md) | 当前静态/构建验证基线、DeepSeek 主路径、真机验收，以及开发阶段破坏性 schema 策略与未来公开发布迁移门槛 |
| [research/](research/) | 阶段性专题研究材料（2026-08-13 产品/架构评估、UI 壁垒、原生运行时后端、项目 Workspace 流程） |

> 04（Agent/Provider/内容链路）与 06（工程状态与验证）已按职责拆分：当前实现细节并入 `../state/ARCHITECTURE.md`，验证清单并入 `11-verification-and-release-checklist.md`，调试经验并入 `../logs/`。对应的旧文件已删除，不再维护。

## 状态术语

`docs/` 描述设计目标，不负责记录当前交付状态（那是 `state/` 的职责）。为避免把设计目标写成已交付能力，文档仍可使用以下标记：

| 术语 | 定义 |
|---|---|
| 设计约束 | 产品范围或安全要求，后续实现应持续遵守 |
| 目标架构 | 已确定方向但尚未实现，不得当作当前能力宣传 |
| 后续候选 | 未进入当前范围，不构成承诺 |

当前实现状态一律查 `state/CURRENT.md` 与 `state/ARCHITECTURE.md`。

## 写作规范

1. 直接陈述目标、事实、约束、机制和结论。
2. 产品目标与设计意图分段记录；不要混杂实现状态。
3. 风险使用可复现条件、影响范围和处理策略描述。
4. 验收项使用可观察结果描述。
5. 文案避免宣传口号、拟人化表达和无依据的程度词。
6. 文案禁用预设读者误解后再反转的句式。
7. 涉及"当前状态"的陈述必须指向 `state/`，不在 `docs/` 中重复维护一份状态。

## 事实优先级

当前实现事实按以下顺序取证（供写 `state/` 时使用）：

1. `familiar.xcodeproj/project.pbxproj` 与 App 配置。
2. `Familiar/` 下的当前实现。
3. `Vendor/AnyDocBridgeRust/`、`Vendor/AnyDocBridge.xcframework/` 与构建脚本。
4. 已执行的构建、测试和运行记录。
5. 产品计划与发布要求。

当代码、计划和验证结果存在差异时，分别记录三者，不合并为单一结论。

## 维护规则

`docs/` 在**意图或设计发生变化**时更新（例如：调整产品定位、改变目标架构、作出新的技术决策、更新长期规划）。实现状态的变化见 `state/README.md` 的更新规则；发现设计落后于实现时，只更新 `state/`，不反向改写设计。

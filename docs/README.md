# 项目文档

Familiar 当前目标是 Telegram iOS 视觉与交互的 AI 问答体验。产品意图、代码事实、执行证据分别维护，避免重复阶段计划。

## 阅读入口

| 文档 | 职责 |
|---|---|
| [产品定义](01-product-definition.md) | 产品对象、目标与排除项 |
| [架构约束](02-system-architecture.md) | 模块责任、scope、授权和执行边界 |
| [UI 规范](03-ui-ux-design.md) | 唯一现行视觉与交互设计 |
| [对齐账本](telegram-ios-ui-checklist.md) | 稳定编号、源码、差距、实现／编译／真机状态 |
| [本地数据与隐私](05-local-data-and-privacy.md) | 数据目的地、保护、授权、删除和系统入口 |
| [现行决策](07-decision-log.md) | 仍有效的选择与理由 |
| [参考实现](08-reference-repositories.md) | 来源和迁移边界 |
| [统一验证与发布](11-verification-and-release-checklist.md) | 编译规则、所有者验收与发布要求 |
| [源码登记](research/telegram-ios-source-map.md) | 固定Telegram提交、具体路径和已读范围 |
| [研究索引](research/README.md) | 独有调查与历史证据 |

当前代码事实在 [state](../state/README.md)，当前批次在 [PLAN](../PLAN.md)，可复用故障在 [logs](../logs/README.md)。不将设计目标、下载或编译描述为已验收。

## 本次收敛对应关系

- 旧09 Beautiful UI：现有AI内容和动作契约进入UI规范，删除React/CSS摘录。
- 旧10／12阶段路线、20–22 Telegram方案：目标进入UI规范／账本，当前批次进入PLAN，源码登记保留原研究深度。
- 旧14／15／19验收单及S1验收：统一验证清单保留当前场景，独有历史执行证据进入research。
- 旧13 OpenMinis矩阵、16工作范围、17授权、18文档生成：有效约束进入架构／隐私，代码现状在state。
- product-completion：复用调查结论进入research，普通流水删除，完整历史由Git保留。

维护时直接修改对应现行文档；不新增第二份总路线或跨文档重复状态表。

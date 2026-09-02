# End-to-End Scenarios — 验证矩阵

每个结论必须使用以下三档口径，禁止混淆：

- `verified-by-tests` — 自动化测试真实执行并通过。
- `verified-by-simulator` — 单次 Simulator smoke 中观察到。
- `device-unverified` — 只完成编译或 Fake Adapter，真实行为未验证。

当前阶段不进行真机测试。依赖真机或特殊 Entitlement 的能力，用 Fake Adapter 验证业务逻辑并标记 `device-unverified`，不因此暂停开发，也不伪造结论。

## 场景一：北京介绍 Word

输入：「帮我写一份介绍北京的 Word，包含城市历史、文化、主要景点、现代发展和旅行建议。」

| 步骤 | 实现路径 | 当前结论 |
|---|---|---|
| 1 理解目标 | `FamiliarAgentLoop` provider round | `device-unverified`（依赖真实 DeepSeek Key） |
| 2 生成计划 | `task_plan` 产出 `TaskList` payload | 部分：payload 与渲染存在，但无调度器读取，计划不驱动执行 |
| 3 判断是否检索 | 模型决策 | `device-unverified` |
| 4 获取资料 | `web_search` + `web_fetch` | `device-unverified`（adapter 有确定性 fixture 测试） |
| 5 组织结构 | 模型生成 | `device-unverified` |
| 6 生成合法 DOCX | `environment_prepare` → `shell_execute`（guest 内 python-docx） | `device-unverified`。无原生 Swift OOXML writer，生产完全依赖 iSH guest 真实启动 |
| 7 校验与入库 | `artifact_publish` → `FamiliarArtifactValidator` | `verified-by-tests`（`FamiliarProjectWorkspaceTests.swift:209-274` 真实调用 AnyDoc） |
| 8 Artifact 卡片 | `FamiliarProjectsView` / Chat receipt | 编译通过，渲染未验证 |
| 9 预览 | `QLPreviewController`（`FamiliarAttachmentQuickLookView.swift:55`） | `device-unverified` |
| 10 保存到 Files | 系统 ShareLink（`FamiliarProjectsView.swift:941`） | `device-unverified` |
| 11 分享 | 同上 | `device-unverified` |
| 12 执行步骤与证据 | `FamiliarRunPersistenceRecorder` + Run Detail | `verified-by-tests` |
| 13 继续修改生成新版本 | 无 | 缺失。无 `artifact_read`，`FamiliarArtifact` 无版本字段 |

闭环判定：未闭环。两处结构性缺口（步骤 6 依赖真机、步骤 13 回读与版本缺失）。校验、发布、审计半程已可测试验证。

失败要求：网络或工具不可用必须明确报告缺失能力。当前 `manifests()` 丢弃 `.unavailable` 的 reason，工具静默消失，模型可能改用网页猜测而不报告能力缺失，需修复。

## 场景二：资料转报告

`PDF / DOCX → AnyDoc 解析 → 摘要 → 结构化报告 → DOCX 或 PDF`

| 环节 | 状态 |
|---|---|
| 文档导入为 Project Resource | 已实现（`FamiliarProjectResourceService` 原子导入 + SHA-256 版本） |
| AnyDoc 解析为 Markdown | `verified-by-tests`（真实 Rust 桥调用） |
| Resource 只读投影给 Agent | 已实现（`resource_list/read/search`，读 Run 启动时冻结的快照） |
| 摘要 | `device-unverified` |
| 输出 DOCX 或 PDF | 与场景一步骤 6 同一约束，`device-unverified` |

## 场景三：分享内容转系统动作

`Share Sheet → 识别时间地点 → 生成日历事件 → 用户批准 → EventKit 创建`

| 环节 | 状态 |
|---|---|
| Share Extension 收件箱 | 编译通过，`device-unverified` |
| 目标选择（已有项目 / 新建 / 普通聊天） | 已实现（`FamiliarSharedDestinationView`） |
| 时间地点识别 | NaturalLanguage 设备内 + 模型，`device-unverified` |
| typed Approval 卡 | 已实现，有确定性测试 |
| EventKit 创建与跨重启 Undo | 逻辑已实现（`FamiliarEventKitUndoRecord`），真实系统授权 `device-unverified` |

## 场景四：项目连续工作

第二天重开 Project，Agent 记住目标、已做决策、已生成文件、待完成任务、用户偏好。

| 需要记住的东西 | 载体 | 状态 |
|---|---|---|
| 项目目标 | `ProjectInstruction` | 已实现并注入 |
| 已生成文件 | `FamiliarArtifact` | 已持久化，但 Agent 无法回读内容（无 `artifact_read`） |
| 已做决策 | Memory（project scope） | 缺失（service 零调用方） |
| 待完成任务 | `task_plan` payload | 仅渲染，无持久化任务队列，无跨 Run 延续 |
| 用户明确保存的偏好 | Memory（global / project） | 缺失 |

闭环判定：未闭环。项目指令与资料能延续，执行记忆与决策不能。这是 Memory 未接线的直接后果。

## 场景五：失败恢复

| 模拟情况 | 当前真实行为 | 判定 |
|---|---|---|
| iSH 尚未启动 | 工具静默消失，模型不被告知，可能改用网页猜测。UI 侧有 `failed(reason)` 与 Retry | 不合格，需修复（见 architecture-contracts §1） |
| Tool 调用超时 | `FamiliarToolExecutionTimeout`（每工具 `maximumExecutionDuration ?? 30`），read 类工具内部重试一次 | 合格，有确定性测试 |
| 用户拒绝权限 | `capabilityUnavailable(reason)` 真实透出给模型 | 合格 |
| App 被关闭 | `recoverInterruptedRuns` 把 running Run 终结为 `failed`，理由 `interrupted`，在途 invocation 置 `cancelled` | 部分合格：状态真实、不伪造成功，但无可执行恢复路径，`resumable` 无产生路径 |
| 网络中断 | 首字节前有界重试 + `retrying` notice，已产生内容后不自动重放写操作 | 合格 |
| 生成文件失败 | `artifact_publish` 校验失败即 throw 并删除已导入目录，最多 2 次交付物修复后 `missingDeliverables` | 合格。不会产出成功 Artifact 或虚假完成回答 |

## 阻塞条件汇总

| 阻塞 | 影响场景 | 性质 |
|---|---|---|
| 无真实 DeepSeek Key 冒烟 | 一、二、三、四 | 外部凭据，不阻塞开发 |
| iSH guest 真实冷启动与 `python-docx` 安装未验证 | 一（步骤 6）、二 | 真机，不阻塞开发 |
| 无 `artifact_read` | 一（步骤 13）、四 | 代码缺口，本轮可修 |
| Artifact 无版本 | 一（步骤 13） | 代码缺口，本轮可修 |
| Memory 未接线 | 四 | 代码缺口，本轮可修 |
| 不可用原因不透出给模型 | 一、五 | 代码缺口，本轮可修 |
| Run 无跨重启续跑 | 五 | 代码缺口，规模较大 |

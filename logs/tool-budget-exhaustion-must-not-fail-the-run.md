# 预算耗尽被当成错误抛出，导致「工具调用次数过多」后整轮工作作废

## Symptom

复杂任务经常以「工具调用次数过多，已停止本次任务」结束。此前若干轮已经成功执行的工具结果全部不可见，用户拿到的是一条错误而不是回答，模型也没有机会用手头已有的信息作答。

## Investigation

- `FamiliarAgentLoop` 在准备工具调用时有 `guard executedToolCalls < maximumToolCalls else { throw FamiliarAgentError.maxToolCallsExceeded }`。该 throw 会穿透整个 `run`，被 `stream` 的 catch 捕获后发 `runFinished(.failed(...))`。
- 同一处循环里还有一个同类抛出：迭代耗尽时 `throw FamiliarAgentError.maxIterationsExceeded`。
- 对比同一循环里的其它异常路径：Skill 越权与重复调用都是**软失败**，回一条带 `code` 的 tool message 让模型继续。只有两处预算是硬抛。
- 两条错误文案（`error.agent.max_tool_calls`、`error.agent.max_iterations`）当时是同一句「已停止本次任务」，也印证了这两条路径被当作同类终止错误设计。
- `FamiliarRuntimeTests` 的 `toolCallBudget` 断言 `finish?.failureKind == .maxToolCalls`，即测试把「预算耗尽 = Run 失败」固化成了预期行为，所以这个缺陷不会被现有测试发现。

## Root Cause

把「资源预算用尽」和「运行出错」当成了同一件事。预算是对**继续调用工具**的限制，不是对**这次运行**的否决：预算耗尽时手上通常已经有足够信息可以作答，把它抛成错误等于主动丢弃这些已完成的工作。同一循环里的其它限制（Skill 越权、重复调用）都已经用软失败正确处理，唯独预算走了硬抛，属于实现内部的不一致。

## Fix

预算耗尽改为「收尾信号」，不再终结 Run：

- 新增 `FamiliarRuntimeNoticeKind.budgetExhausted`。`FamiliarRuntimeNotice` 的 `attempt`/`delay` 改为有默认值，因为它们描述重试计划，对预算通知没有意义。
- 超预算的那一次调用回一条 `tool_budget_exhausted` 的结构化失败给模型，并把该次 activity 记为 failed，随后 `continue`；不再 throw。
- 引入 `withholdTools`：预算耗尽后，以及最后一轮迭代，请求里的 `tools` 传空数组，并一次性追加一条系统消息要求立即基于已有信息作答、明确说明哪些没能完成，禁止把未执行的动作说成成功。模型在没有工具可用时只能作答，这正是此时用户想要的结果。
- 迭代耗尽处不再无条件抛错：只要 `visibleResponse` 非空就交付已有正文（仍校验 `expectedDeliverables`）；只有确实什么都没产出才抛 `maxIterationsExceeded`。
- `FamiliarAgentError.maxToolCallsExceeded` 随之不可达，按「不保留过时路径」删除；`FamiliarRuntimeFailureKind.maxToolCalls` 保留，作为 notice 的 `failureKind` 供审计。
- UI：`showRuntimeNotice` 与历史回放分支改为按 kind 区分标题与详情。此前两处都无条件渲染成 “Retrying provider request”，新 kind 会显示出一个并不存在的重试延迟；历史回放还用 `activityID.contains(":retrying:")` 过滤，会把预算通知整条丢掉。
- 两条误导性文案一并更正：`error.agent.max_tool_calls` 不再说「已停止本次任务」（任务并未停止），`error.agent.max_iterations` 改为描述真实原因（持续请求工具却从未作答）。

## Verification

arm64 iOS Simulator `build-for-testing` 成功，无 Swift 诊断。中英 `Localizable.strings` 经 `plutil -lint` 通过且 key 集合一致（755/755），`git diff --check` 通过，`maxToolCallsExceeded` 无残留引用。

`FamiliarRuntimeTests.toolCallBudget` 已重写为断言正确行为：Run 终态为 `.succeeded`、恰好发出一条 `.budgetExhausted` notice、只有一次工具真的执行、超预算调用的 activity 失败码为 `tool_budget_exhausted`、并且最终交付了回答。测试夹具 `FamiliarBudgetProvider` 改为在 `request.tools` 为空时直接作答，以模拟真实模型在无工具可用时的行为。

`singleFailedFinish` 保留失败断言：其夹具 `repeatedTool` 从不发文本，因此确实无内容可交付——这现在是迭代耗尽唯一会失败的情形。

**未执行测试**（按项目约束未启动 Simulator），以上只验证了可编译。

## Remaining Issues

真机上仍需确认两点：预算耗尽后的那一轮回答是否真的诚实说明了未完成项（提示词依赖模型遵守），以及 24 次调用的默认预算对当前复杂任务是否偏紧。若真机 trace 显示大量任务都撞到预算，应先看是否有重复调用或无效工具选择，再考虑调高 `maximumToolCalls`——放宽预算会同时放宽单次 Run 的成本与时长。

更一般的教训：任何以 `throw` 表达「资源用尽」的地方都值得怀疑。要区分「无法继续」和「不该再继续」——后者应该收束能力并要求收尾，而不是让整轮工作作废。

# 审批/提问事件与等待注册的时序

现象：外部消费者收到 approvalRequested 后立即 resolve，可能得到 unknownRequest；Runtime 随后才注册 continuation，永久等候已丢失的回复。授权存储失败的参数化回归可稳定触发。

原因：approve 原先先 emitter.emit(approvalRequested)，再调用 requestConfirmation。跨 actor 的事件消费可以先于 pendingByID 注册发生。

Clarification 具有同类先发事件问题，采用同一注册后通知顺序，并验证立即回答、同 Run 恢复及取消。

修复：requestConfirmation 在 continuation 和 idempotency key 注册成功后执行 onPending 回调，由它发出审批展示事件。通知任务在请求结束时取消，取消/重复请求不发新展示。执行规则和精确授权不改变。

验证：立即回复用例确认第一次成功、重复决策返回原结果；授权存储失败、并发读/取消/Runtime 回归执行通过。证据在根 PLAN.md；不将 Simulator fixture 当成真实外部写入验收。

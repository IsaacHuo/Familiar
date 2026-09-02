# 只读但敏感的工具无法获得会话授权，且审批卡没有真实读取范围

## Symptom

`health_activity_summary`、`photos_recent_metadata`、`bluetooth_scan` 三个工具每次调用都弹一次审批，用户选“本会话允许”也无效，下一次调用照样打断。审批卡上只有一行文字，内容是 manifest 的整段 description，看不出这次到底要读多少天、多少项、哪些 UUID。多步任务（例如照片→天气→报告）因此被连续打断。

## Investigation

- 三个工具都是 `effect: .read` + `risk: .high`。`FamiliarExecutionPolicy.decide` 对 `risk == .high` 一律返回 `.requestApproval`。
- Agent Loop 里 read 与 write 走两条不同分支：write 分支（`.action`）会查询并签发 `authorizationRuntime` 的持久授权；read 分支完全不碰 `authorizationRuntime`，所以任何时长选择都不会被持久化，也永远匹配不到。
- read 分支构造审批请求时写死一个字段：`FamiliarApprovalField(id: "access_scope", value: manifest.description)`，`target: nil`，`undoPolicy: .unavailable`。工具本身知道真实范围（days、limit、serviceUUIDs），但没有通道把它交给审批卡。
- `preflight` 钩子已存在且泛化，但当时只有 `shell_execute` 用它降级 risk，`FamiliarToolAuthorizationAssessment` 不携带任何展示信息。

## Root Cause

授权与审批的实现假定「需要持久授权的一定是写操作」。敏感读取产生结果而非变更，因此走 `.result` 而不是 `.action`，于是掉出了唯一接了 `authorizationRuntime` 的那条分支。审批卡缺信息是同一个假设的副产品：read 没有 `FamiliarActionProposal`，也就没有 proposal 携带的 fields/target/consequence。

## Fix

- `FamiliarToolAuthorizationAssessment` 增加 `fields`/`consequence`/`targetKey`（均有默认值，不影响既有工具）。三个工具重写 `preflight`，给出真实读取范围：Health 报窗口天数与三个 quantity type、Photos 报项目数与“含拍摄位置、不读像素”、Bluetooth 报具体 Service UUID 与时长。
- Agent Loop 中 `preflight` 前移到 read 审批之前（四个重写 preflight 的工具都只检查入参、不触碰框架，因此安全），read 分支接入 `authorizationRuntime.matchingAuthorizationScope` / `issueAuthorization`，`allowedAuthorizationDurations` 固定为 `[.once, .session]`。
- 不开放 `.always`：健康与照片元数据长期免确认对这类数据过宽。
- read 的 `targetKey` 用常量（`argumentsHash` 已覆盖全部参数，targetKey 对 read 不增加区分度）。换参数仍需重新授权。
- 新增 `readConfirmation` 变量：只有本次真的打断了用户才记为 `.confirmed`，复用既有授权时记为自动授权，审计不会把复用伪装成新确认。
- 顺带删除 `FamiliarExecutionPolicy` 的两个死重载（`FamiliarOneShotAuthorization` 无生产调用者；`grant:` 版本生产恒传 `nil`）。注意 `FamiliarAuthorizationGrant.isValid` **不是**死代码，`FamiliarRunRecoveryService.consumeGrant` 仍在用它做外部入口的 grant 契约，必须保留。

## Verification

arm64 iOS Simulator `build-for-testing` 通过。`FamiliarAppleNativeToolTests` 断言三个工具的 preflight 给出真实范围与 targetKey，并断言超出平台上限的 days 会被 clamp 且审批卡显示 clamp 后的值。新增 `native-weather-report` benchmark 断言照片读取被审计为已确认、随后的低风险 WeatherKit 查询不再申请审批。**未执行测试**（按项目约束未启动 Simulator）。

## Remaining Issues

真机上多轮任务的实际打断次数未人工验收。若将来新增敏感 read 工具，只需重写 `preflight` 提供 fields/consequence/targetKey，不需要再改 Agent Loop。

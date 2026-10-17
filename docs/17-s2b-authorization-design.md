# S2b 授权分级设计（已确认，已实现）

2026-10-17。本文是 S2b 的设计确认页，由所有者确认后实施。级别定义以 `PLAN.md` 授权表为准；现状描述以代码为准，已逐条核对。实现结果见文末「实施纪要」。

## 1. 现状（代码事实）

- `FamiliarAuthorizationDuration` 只有 `once / session / always`（`Familiar/Agent/FamiliarAuthorizationContract.swift:3-7`）。
- 授权匹配要求 `argumentsHash` 与 `targetKey` 完全一致（`Familiar/Persistence/FamiliarAuthorizationRuntime.swift:19-26`），`.always` 也不例外。参数每次变化的工具（创建事件、提醒、通知、技能安装）事实上无法复用授权。
- `mayReuse` 排除 MCP 与全部高风险或非 reversible 工具（`Familiar/Agent/FamiliarExecutionPolicy.swift:57`）。alarm、photos、skill_install、environment_prepare、MCP 即使有记录也不可能命中。
- 审批卡选项来自 `proposal.allowedAuthorizationDurations`（`Familiar/Presentation/FamiliarApprovalCard.swift:237-247`），默认选中 `.once`（`:290-298`）；`.once` 决策不持久化（`FamiliarExecutionPolicy.swift:105`）。
- 各工具现状：
  | 工具 | effect/risk | 申请时长 | 撤销 |
  |---|---|---|---|
  | create/update_calendar_event、create/update_reminder | reversibleWrite/sensitive | 默认 `once+session+always`（精确匹配，实际不可复用） | durable |
  | delete_calendar_event、delete_reminder | destructiveWrite/sensitive | `[.once]` | durable |
  | notification_schedule | reversibleWrite/sensitive | 默认三档（精确匹配） | — |
  | clipboard_write | reversibleWrite/sensitive | 默认三档（精确匹配） | currentSession |
  | photos_save_output | destructiveWrite/sensitive | `[.once]` | — |
  | alarm_schedule / alarm_cancel | reversibleWrite / destructiveWrite | 各自 `[.once]` | — |
  | skill_install | reversibleWrite/sensitive | `[.once]` | — |
  | environment_prepare | destructiveWrite/high | `[.once]` | — |
  | memory_remember | reversibleWrite/low | `[.once]`，注释明确要求逐条确认 | unavailable |
  | MCP 远程调用 | 由远端 manifest 决定 | `[.once]`（`Familiar/MCP/FamiliarMCPClient.swift:183`） | — |
- 撤销入口已存在：设置 → Approved Actions（`FamiliarSettingsHubView.swift:781-829`），支持单个撤销与全部撤销。
- Memory 开关 `isAutomaticMemoryEnabled`（「Remember across conversations」）当前同时控制记忆工具暴露与注入；页脚文案明确“关闭时不提议也不读取”。
- MCP 没有任何信任状态；schema 里 `capabilitiesJSON/toolsHash/lastConnectedAt/lastError` 等字段从未被读取。

## 2. 设计

### 2.1 「始终允许此类」= 能力级持续授权

- 新语义：`duration == .always` 的记录按 **scopeKey + capabilityID + capabilityVersion** 匹配，忽略 `argumentsHash` 与 `targetKey`；未撤销、未过期（365 天）即命中。
- 备选：新增独立 `.capability` case。需要同时扩展 duration 枚举、decision 枚举、卡片选项、surface/run 记录 JSON 四处；重定义 `.always` 只改一处匹配逻辑，且当前 `.always` 因精确匹配基本无用，等价于新引入。推荐**重定义 `.always`**。
- `.session` 保持现状（同一会话内、精确参数）。第 3 级工具只提供 `[.once, .always]`；第 4 级只提供 `[.once]`。
- `mayReuse` 改为：工具显式允许 `.always` 时即可复用，不再受“高风险/MCP 一律排除”限制；第 4 级工具不声明 `.always`，由表驱动测试锁定。
- 卡片：第 3 级首次询问的默认选项改为「始终允许此类」（PLAN 要求）；用户仍可改选「仅这次」。第 4 级只有「仅这次」。
- Approved Actions 页补充能力级记录的展示（范围、能力、签发时间、有效期）与撤销；撤销后下一次调用重新询问。

### 2.2 工具级别归属（建议）

- 第 3 级（首次询问，默认始终允许此类）：`create/update_calendar_event`、`create/update_reminder`、`notification_schedule`、`clipboard_write`、`photos_save_output`、`alarm_schedule`、`skill_install`、**已信任 MCP 服务器**的非删除类调用。
- 第 4 级（每次询问，不持久）：`delete_calendar_event`、`delete_reminder`、`alarm_cancel`、**未信任 MCP**、对外发送类。
- 第 2 级（不询问，事后回执+撤销）：`memory_remember`（见 2.3）、`environment_prepare`（见 2.4）；`file_*`、`workspace_write`、离线 shell 已实现。

### 2.3 Memory 自动写入

PLAN 级别表把 `memory_remember` 列为第 2 级：不询问、回执 + 撤销。当前代码注释明确写着必须逐条用户确认（`FamiliarMemoryTools.swift:60-67`）。

- 按 PLAN 实施（推荐）：记忆开关开启时 `memory_remember` 自动执行，返回可撤销回执；撤销 = 删除该条记忆。需要为工具提供真实 undo 闭包（当前 `undoPolicy: .unavailable`，代码注释拒绝虚假承诺）。限制：撤销仅覆盖本会话自动写入（跨重启的删除仍从设置页完成）。
- 保留现状：继续逐条确认。与 PLAN 表格冲突，需要改 PLAN。
- 无论哪种：开关关闭时不写入、不读取；模型不能自授权；记忆不授予工具权限。

### 2.4 environment_prepare 自动执行边界

- 建议自动执行条件（全部满足）：来源 == 当前配置的软件源；包名集合是设置允许的依赖；只作用于当前 Project 的 Environment；Swift 侧检查通过。回执 + 撤销（撤销 = 回滚本次安装的环境 receipt）。
- 不满足条件的安装请求：询问（第 3 级，默认始终允许此来源）或拒绝——见决策点 4。

### 2.5 MCP 信任

- 默认未信任：每次调用询问，与现状一致。
- 信任粒度：**按服务器**（全局，用户设置）。确认稿原写「服务器 + 工作 scope」，实现时收敛为按服务器：scope 级信任在会话 scope 没有设置入口，且信任本质是对外部服务器声明的判断，不是对某次工作范围的判断；scope 级的收紧由「始终允许此类」授权记录承担（它按 scope 匹配）。
- 存储：不改 schema，信任存 UserDefaults（键 = serverID）。schema 加字段意味着无法在本机验证的迁移；本 App 未发布，但验证边界只允许编译，不做磁盘迁移验证。
- 已信任服务器调用一律第 3 级（首次询问 → 默认始终允许此类）；不读取远端 destructive hint 作为放松依据（远端字段不可信）。未信任一律每次询问（第 4 级）。

### 2.6 不变量（不变）

- 模型不能自授权；`Policy.evaluate` 保持纯 gate；执行前复核、journal、防重放保留。
- 授权按完整 work scope key 隔离；同 UUID 的 Project/Conversation 不互通。
- `.once` 仅 10 分钟有效；第 4 级永不产生持久授权。

## 3. 决策结果（所有者确认，2026-10-17）

1. 重定义 `.always` 为能力级匹配（不新增 `.capability`）。
2. 级别归属表按设计稿 2.2 执行：创建/更新日历提醒、通知、剪贴板写入、保存相册、闹钟(schedule)、skill_install、已信任 MCP → 第 3 级；删除类、alarm_cancel、未信任 MCP → 第 4 级。
3. Memory 按 PLAN 第 2 级自动写入，补真实 undo。
4. environment_prepare 满足自动条件时自动执行；不满足时询问（第 3 级，默认始终允许此类）。
5. MCP 信任按 2.5 执行；实现收敛为按服务器（见 2.5 说明）。
6. 第 3 级审批卡默认选中「始终允许此类」。
7. S2b 完成后进入 S4。

## 4. 实施纪要（2026-10-17）

- 授权匹配：`.always` 按 scopeKey + capabilityID + capabilityVersion 命中，忽略参数与目标（`FamiliarAuthorizationRuntime.swift`）。
- Policy：`mayReuse` 承认声明 `.always` 的工具（MCP 信任后同样适用）；自动执行名单加入 `memory_remember` 与 `environment_prepare`（`FamiliarExecutionPolicy.swift`）。
- 工具级别：EventKit 创建/更新、通知、剪贴板、相册、alarm_schedule、skill_install 申请 `[.once, .always]`；删除与 alarm_cancel 保持 `[.once]`；MCP 按信任返回 `[.once, .always]` 或 `[.once]`。
- Memory：`undoPolicy: .currentSession`、回执承诺可撤销、provenance 带 run 幂等键；控制器撤销时按 provenance 删除该行。
- environment_prepare：effect 改 `reversibleWrite`/风险 `sensitive`；提交后保留旧环境目录作为会话 Undo 目标（每 scope 一份确定性备份，下一次提交或删除 scope 时清理）；撤销时回滚目录并按恢复的 receipt 同步元数据，首次安装撤销则移除 receipt。
- MCP：新增 `FamiliarMCPTrustStore`（UserDefaults，按服务器）；MCP 设置页新增「信任此服务器」开关；删除服务器时清除信任。
- 审批卡：任何提供 `.always` 的卡片默认选中「始终允许此类」；Approved Actions 页按「签发时的操作标题 + 时长」展示，能力级记录不再显示过时的 targetKey。
- 文案：`authorization.always` 改为「始终允许此类 / Always Allow This Kind」；新增 `mcp.trust.title/detail`；更新 Approved Actions 页脚。双语 1076 键，键集合一致。
- 测试：新增/更新能力级匹配、EventKit 级别表、MCP 信任、Memory 二级写入、harness 失败补偿等用例；全部只编译不执行。
- 验证边界：arm64 iPhone 18 Pro Simulator `build-for-testing` 成功（exit 0，`** TEST BUILD SUCCEEDED **`，无源码 warning/error）。真机视觉与行为验收由所有者执行；清单见交付说明。

## 5. 真机验收清单（所有者）

1. MCP 设置页：默认未信任；对同一服务器开关信任后再次调用，卡片出现「始终允许此类」且默认选中。
2. 创建日历事件或提醒：首次卡片确认「始终允许此类」后，同 Project 内换时间/标题再次创建不再询问；切换到其他 Project 或普通对话重新询问；Approved Actions 可撤销后再次询问。
3. 删除事件/提醒与取消闹钟：卡片只有「仅这次」。
4. 记忆开关开启时要求记住偏好：无卡片直接写入并出现可撤销回执；撤销后该条消失；设置页可见该条记忆；关闭开关后不再写入。
5. 复杂文档任务中批准一次依赖安装：后续安装不再询问；撤销安装后设置/状态回到安装前（首次安装撤销后环境回到未准备）。
6. 复述：模型不能自授权；拒绝/取消零写入；执行中断提示与实际状态一致。

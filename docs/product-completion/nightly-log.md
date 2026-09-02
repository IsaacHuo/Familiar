# Nightly Log — 成品化持续开发

倒序记录。每条必须区分「已执行并通过」与「仅编译」，禁止声称没有实际运行过的测试已通过。

---

## 2026-09-03 · 第 4 轮：Artifact 版本历史 UI

### 已完成

- **版本按谱系折叠**（`fd66666`）：版本落地后，原先平铺的 Artifact 列表会把同一交付物的 v3、v2、v1 显示成三个互不相关的 Artifact；项目首页摘要更糟，三个「最近产物」槽位会被同一个文件的三次修订占满。两处现在都按 `lineageID` 折叠为「一个交付物一行」，只展示最新版本。
- 旧版本通过版本历史页进入，仍可预览与分享——每个版本保有自己的行与自己的字节，所以「能打开」不是新增能力，而是把已有事实暴露出来。
- 版本号只在该谱系确实有历史时显示：给只有一个版本的交付物标上「v1」会暗示存在并不存在的修订。
- 谱系分组用按 `lineageID` 的 `Identifiable` 包装类型，而不是在生产列表里对可能为空的分组做 `first!` 强解包。

### 修改文件

`Familiar/Presentation/FamiliarProjectsView.swift`、中英 `Localizable.strings`、`FamiliarTests/FamiliarUIFeedbackTests.swift`。

### 测试结果（已实际执行）

- 受影响套件：45 tests / 4 suites 全部通过。
- **全量套件再次通过**：`Scripts/run-release-test-suites.sh`，29 个 suite + `FamiliarUITests`，输出 `All release test suites passed`（退出码 0）。
- 中英 `Localizable.strings` 经 `plutil -lint` 通过且 key 完全一致（787/787），`git diff --check` 通过。
- 新增契约测试断言两处分组都存在、历史页存在，且不存在 `id: \.first!.id` 这类强解包。

### 尚未验证

版本历史页的视觉、VoiceOver、Dynamic Type 与深色模式表现需真机验收（按当前阶段策略未启动 Simulator）。

### 北京介绍 Word 闭环状态

| 半程 | 结论 |
|---|---|
| 校验、发布、审计 | `verified-by-tests` |
| 回读产物 | `verified-by-tests` |
| 生成新版本 | 数据层与 UI 均 `verified-by-tests`；视觉 `device-unverified` |
| 生产 DOCX | `device-unverified`，无原生 Swift OOXML writer，依赖 iSH guest |

**剩余唯一阻塞是 DOCX 生产半程，且它只能在真机上验证。** 其余环节已无代码缺口。

---

## 2026-09-03 · 第 3 轮：Artifact 版本

### 已完成

- **Artifact 版本**（`e24d109`）：`FamiliarArtifact` 新增 `lineageID` + `version`。每个版本是独立的行与独立目录——store 按 artifact ID 存文件，原位覆盖会销毁上一版字节，因此复用同一行做不到真正的版本。`artifact_publish` 新增可选 `supersedes`，指定后新文件成为同一交付物的下一版本；格式错误的 predecessor 直接拒绝而不是忽略，否则会静默发布一个不相关的第一版、丢掉调用方要的修订历史。
- 谱系与版本号在 `FamiliarArtifactService.persist` 解析，而不是信任 descriptor：工具是 `nonisolated`、无法查询 store，由工具提供的版本号在同一交付物发布两次修订时必然冲突。`nextVersion` 取该谱系历史最大值加一，因此删除中间版本也不会让后续修订复用号码。
- `supersedes` 声明为 `var` 而非带默认值的 `let`：带初值的 `let` 会被排除在合成 `Decodable` 之外，模型传的参数会被静默丢弃，该参数就成了死参数。

### 修改文件

`Familiar/Persistence/FamiliarSchemaV4.swift`、`Familiar/Artifacts/{FamiliarArtifactService,FamiliarArtifactTool}.swift`、`FamiliarTests/FamiliarProjectWorkspaceTests.swift`。

### 测试结果（已实际执行）

- 受影响套件：49 tests / 5 suites 全部通过（含新增的版本测试：第一版是自身谱系原点、修订为 v2 且保留旧行与旧字节、v3 延续同一谱系、删除中间版本后 `nextVersion` 仍为 4）。
- **全量套件再次通过**：`Scripts/run-release-test-suites.sh`，29 个 suite + `FamiliarUITests`，输出 `All release test suites passed`（退出码 0）。schema 有改动，因此本轮重跑了全量。
- `git diff --check` 通过。

### 一次自己造成的构建失败（值得记录）

`FamiliarArtifactService.swift:295` 报 `circular reference`：我把助手命名为 `artifact(id:in:)`，而同一作用域下一行声明了局部变量 `let artifact = ...`，Swift 把调用解析到了正在声明的变量上。改名为 `storedArtifact(id:in:)` 后消除。报错信息本身完全没有提示名字遮蔽。

### 北京介绍 Word 闭环状态

| 半程 | 结论 |
|---|---|
| 校验、发布、审计 | `verified-by-tests` |
| 回读产物 | `verified-by-tests`（`artifact_read`，经真实 AnyDoc 往返） |
| **生成新版本** | 数据层 `verified-by-tests`；**版本历史尚无 UI**，用户无法在界面浏览或预览旧版本 |
| 生产 DOCX | `device-unverified`，无原生 Swift OOXML writer，依赖 iSH guest |

剩余唯一的真机阻塞是 DOCX 生产半程。

---

## 2026-09-03 · 第 2 轮：P0 六个垂直切片

### 已完成

1. **Runtime 就绪契约**（`cdf68cd`）：`environment_status` 改为无条件注册——它只读磁盘 receipt，此前却被 iSH guest 启动门控，rootfs 缺失时永不注册。新增 `FamiliarToolRegistry.availabilityReport()` 保留 `.unavailable(reason:)` 的真实原因（`manifests()` 此前直接丢弃），并接到发送路径，渲染为 `<unavailable_capabilities>` 系统提示段落，要求模型报告缺失能力而不是静默改用其他手段猜测。
2. **Settings 死控件**（`633deb6`）：删除 `FamiliarModelServiceSettingsView` 中 4 个 `body` 从不渲染的 section（system prompt、privacy、notifications、brand header），以及随之失效的状态、hook 与 UIKit import。更严重的是该页 `.task` 仍会在未授权时静默 `setEnabled(false)`——一个没有可见通知控件的页面会关掉通知，属真实 bug，已一并移除。Shell 限制展示改为从 `FamiliarShellLimits.iOS` 派生。
3. **执行预算可配置且真实生效**（`5bbd462`）：`maximumIterations` / `maximumToolCalls` / `maximumDuration` 此前只是 `FamiliarAgentLoop` 初始化器默认值，`makeRuntime` 一个都不传，只有测试能覆写。新增 `FamiliarExecutionBudget` 并接到设置页 stepper（范围与 `normalized` 的钳制一致）。`FamiliarSettings` 改为显式宽松解码：合成初始化器遇到缺失键会 throw，而 `load()` 任何失败都回落默认值，会静默丢掉用户已存的模型与 system prompt。
4. **Memory 运行时**（`0d6f0d4`、`4cb9dd7`、`3571531`、`ac877fb`）：
   - 修三个既有缺陷：去重键改为按 scope 与其所有者派生（此前内容级全局匹配，跨 Project 同句互相覆盖）；`lastUsedAt` 在 search 实际选中的行上写入（此前从不赋值，排序永久退化为 `updatedAt`）；`confidence` 真实存储并参与排序，用户确认的记忆优先于更新的 Agent 提议。
   - Context Compiler：选中的记忆经 seed 进入冻结 ContextSnapshot，渲染为 `<remembered>` 段落并明确「不是指令、不能创建授权、与当前消息冲突时以当前消息为准」；受硬字符预算约束，超出的整条跳过而不截断（截断会让模型读到一个不同的事实）。
   - `memory_search` 只读本次冻结的记忆，避免工具与提示在运行中对「记得什么」产生分歧；`memory_remember` 返回审批提案，写入请求经 tool result 旁路由 controller 落盘，模型无法自行写入。审批只允许 `.once`，且声明 undo 不可用而非承诺一个 nonisolated 工具无法执行的 durable undo。敏感内容在工具边界与持久化边界双重拒绝。
   - Settings 新增 Memory 页：开关、按 scope 与来源列出每条记忆、编辑、滑动删除、二次确认的全部删除。编辑会重写派生的去重键，否则下一次同内容写入不会被识别为同一条记忆。
5. **`artifact_read`**（`6db2d73`）：已发布的 Artifact 此前 Agent 读不回来（无该工具，`workspace_read` 只看 Workspace 副本且拒绝非 UTF-8），发布 DOCX 后唯一证据是 publish receipt。新工具对 Markdown/文本/HTML 原样返回，DOCX/PDF/XLSX 经 AnyDoc 解析；截断会显式上报，因为以为读全了的模型会去修改一份它只看过一部分的文档。
6. **每 Project 模型覆盖**（`c6252a7`）：`FamiliarProject` 新增可选 `modelIDOverride`（`nil` 表示跟随全局，不默认具体 ID，避免把项目静默钉在用户从未为它选择的模型上）。覆盖在 `requestSettings` 固定之前应用，这要求把项目解析提前——晚于图片、文档与上下文预算校验会用一个本次运行并不使用的模型去做校验。未知 ID 在服务边界拒绝，已存的过期 ID 回落全局。
7. **测试基础设施修复**（`b440f97`）：见下文「测试结果」。

### 修改文件

生产代码：`Familiar/Agent/{FamiliarTool,FamiliarAgentLoop,FamiliarProjectContextAssembler}.swift`、`Familiar/App/FamiliarAppDependencies.swift`、`Familiar/Domain/FamiliarChatModels.swift`、`Familiar/Memory/{FamiliarMemoryService,FamiliarMemoryTools}.swift`、`Familiar/Artifacts/FamiliarArtifactTool.swift`、`Familiar/Persistence/{FamiliarSchemaV3,FamiliarProjectService}.swift`、`Familiar/Presentation/{FamiliarChatController,FamiliarSettingsView,FamiliarSettingsHubView,FamiliarProjectsView}.swift`、中英 `Localizable.strings`。

测试与脚本：`FamiliarTests/{FamiliarMemoryTests,FamiliarBaselineTests,FamiliarWP1Tests,FamiliarEventKitPolicyTests,FamiliarProjectTests,FamiliarProjectWorkspaceTests,FamiliarPersistenceReleaseTests,FamiliarBenchmarkTests,FamiliarNativeFirstArchitectureTests}.swift`、`Scripts/run-release-test-suites.sh`、`logs/swiftdata-test-fixture-must-retain-modelcontainer.md`。

新增文件：`Familiar/Memory/FamiliarMemoryTools.swift`、`FamiliarTests/FamiliarMemoryTests.swift`、`logs/swiftdata-test-fixture-must-retain-modelcontainer.md`。

### 测试结果（已实际执行）

- **全量套件通过**：`Scripts/run-release-test-suites.sh 5E9F91D1-73AE-4236-AD61-9244CE4B3A63 <dd>`，29 个 suite 串行逐个执行 + `FamiliarUITests`，最终输出 `All release test suites passed`（退出码 0）。
- 构建：独立 DerivedData、Debug、arm64 iOS Simulator（`iPhone 17 Pro Max` / OS 26.5）`build-for-testing` 成功，无 Swift 诊断、无警告。
- 中英 `Localizable.strings` 经 `plutil -lint` 通过，key 集合完全一致（786/786）。`git diff --check` 通过。
- 本轮修掉的三类测试问题：
  1. `FamiliarAppleNativeToolTests`、`FamiliarNativeOutputToolTests`、`FamiliarWorkspaceShellTests` 存在但**从未进入** `run-release-test-suites.sh` 清单，此前每次「全量」都在静默跳过它们；现已对齐到 29/29。
  2. `weather-capability-gate`：benchmark harness 把 fake EventKit service 当作整个 registry 的能力提供者且对所有 requirement 一律返回 `.available`，因此这个场景根本观察不到拒绝。fake 改为接受显式的不可用 requirement 集合。
  3. `poster-image-preflight`：`startSending` 先查 Keychain，而 harness 从不写 Key，所以该场景在 guard 处就返回、从未到达它要测的 preflight。现补写 Key；在 `CODE_SIGNING_ALLOWED=NO` 下 Keychain 返回 `errSecMissingEntitlement (-34018)` 时，记录为**显式 unverified 终态**而不是一条看起来像覆盖的绿色结果。
  4. `shellPolicy()`：断言期望「开启 Workspace 联网后出站命令自动执行」，与 `state/ARCHITECTURE.md:109` 记录的「只有离线、Workspace-only、checkpointed 命令自动执行，联网/危险命令审批」相矛盾，属过期断言，已更正为 `.requiresConfirmation`。
- 另有一处过期断言：`FamiliarPersistenceReleaseTests` 期望 36 个实体，而在途提交 `5eefbf7` 新增 `FamiliarAlarmUndoRecord` 后实为 37，已更正（切片 4a 一并提交）。
- 调试过程中记录了一条可复用日志 `logs/swiftdata-test-fixture-must-retain-modelcontainer.md`：新增的 Memory 测试全部以 `signal trap` 崩溃且无任何断言失败，根因是夹具写成 `try FamiliarTestStore.make().mainContext`，容器未被持有即释放。同类问题在 `state/CURRENT.md` 的 2026-08-28 条目已出现过一次，属复发。

### 尚未验证（`device-unverified`）

- 真实 DeepSeek Key 的认证、模型列表、流式、取消、Tool Call 与 ToolResult 回填。
- iSH guest 真实冷启动、`python-docx` 安装、取消、网络边界与资源限制；因此**DOCX 生产**半程仍未验证。
- Keychain 相关行为在验证构建中无法覆盖（`CODE_SIGNING_ALLOWED=NO` 导致 test host 缺少 `application-identifier` entitlement）。`poster-image-preflight` 已按此显式标记 unverified。
- Apple Framework 工具的真实系统授权（WeatherKit entitlement、HealthKit/PhotoKit/MusicKit/CoreBluetooth 授权、AlarmKit 需 iOS 26.1 设备）。
- 本轮新增 UI（Execution Limits、Memory 设置页、Project 模型选择器）的视觉、VoiceOver、Dynamic Type 与深色模式表现；Quick Look 能否渲染生成的 DOCX。
- 未启动 Simulator 做视觉验收，未执行 Simulator smoke（按当前阶段策略）。

### 当前阻塞

无不可逆阻塞。外部凭据与真机缺失均以 Fake Adapter + `device-unverified` 标记绕过。

### 下一步最高优先级

1. **Artifact 版本**：`FamiliarArtifact` 仍无版本字段（对比 `FamiliarResourceVersion` 确有 `version: Int`），`artifact_edit` 只保留同会话内存 undo。这是场景一步骤 13「继续修改并生成新版本」剩下的唯一代码缺口。
2. **Orchestrator 持久化执行状态**：`RunResumeCursorRecord` 与 `ToolInvocationRecord` 仍只写不读，`recoverInterruptedRuns` 做的是终结而非恢复。在实现续跑前，`paused` 与 `resumable` 不得出现在 UI 或文档中。
3. **Plan → Task → Step 真实状态机**：`FamiliarRunPhase` 目前仍是展示标签，`task_plan` 产出的 `TaskList` 无任何调度器读取，交付物靠对最后一条用户消息做关键词匹配推断。
4. **Runtime `degraded` 状态**：两个生命周期枚举仍未统一，也都没有部分能力的表示。
5. **Dynamic Type**：全仓库仍是 0 处适配。

### 北京介绍 Word 闭环状态

**仍未闭环，但缺口从 3 个减到 2 个。**

| 半程 | 结论 |
|---|---|
| 校验、发布、审计 | `verified-by-tests`（真实 AnyDoc 解析 `sample.docx`） |
| **回读产物** | 本轮新增 `artifact_read`，已 `verified-by-tests`（publish → read 经真实 Rust 桥往返） |
| 生产 DOCX | `device-unverified`，无原生 Swift OOXML writer，依赖 iSH guest |
| 生成新版本 | 仍缺失，Artifact 无版本表示 |


### 已完成

- 从 `main` 创建 `feature/familiar-product-completion`。`main` 上 47 个已修改文件与 9 个未跟踪文件（用户在途工作）全部原样带入新分支，未 reset、未覆盖、未清理、未提交。
- 完成四个 P0 子系统的代码级只读审计（Agent Orchestrator、Runtime 生命周期与 Tool Registry、Memory、Artifact/DOCX），以及 Settings 全量控件死活判定。结论一律带 `file:line`，不采信既有 Markdown 描述。
- 建立文档：`codebase-audit.md`、`architecture-contracts.md`、`e2e-scenarios.md`、本文件。

### 关键发现（与既有文档冲突处以代码为准）

1. **没有 Plan → Task → Step 状态机。** `FamiliarRunPhase`（`FamiliarAgentLoop.swift:3-17`）是展示标签，循环里没有该类型的状态变量、没有转移表。`task_plan` 产出的 `TaskList` 无任何调度器读取。
2. **Run 无跨重启恢复。** `RunResumeCursorRecord`/`ToolInvocationRecord` 只写不读；`recoverInterruptedRuns` 把 running Run 一律终结为 `failed`。统一状态词表中的 `paused`/`resumable` 没有任何真实产生路径。
3. **iSH 冷启动竞态真实存在。** `prepareRuntime()` 在游离 Task 中注册 shell 工具，`performSend`（`FamiliarChatController.swift:929`）无条件读 `manifests()` 并冻结进快照；preparing 期间发送会静默失去 Shell 能力，且模型不被告知。Registry 无任何等待就绪原语。
4. **`manifests()` 丢弃不可用原因**（`FamiliarTool.swift:1004-1013`）。工具不可用只表现为消失，模型可能因此改用网页猜测而不报告能力缺失。
5. **`environment_status` 被错误门控。** 它只读磁盘 receipt、不需要 guest，却在 `executor.prepare()` 成功后才注册；rootfs 缺失时永不注册。
6. **Memory 是活 schema + 死代码。** `FamiliarMemoryService` 零调用方，唯一写入口 `insert` 无 caller，无工具、无 UI、无 Context 注入。另有三个既有缺陷：`normalizedKey` 去重忽略 scope 且无唯一约束（跨 Project 撞名互相覆盖）、`lastUsedAt` 从不赋值却被用于排序、`confidence` 硬编码为 1 且从不被读。
7. **无原生 Swift OOXML writer。** DOCX 生产完全依赖 iSH guest 内 `python-docx`，因此场景一的生产半程在 Simulator 上不可验证。
8. **无 `artifact_read`，`FamiliarArtifact` 无版本字段。** 发布后 Agent 无法回读自己的 DOCX（`workspace_read` 限 UTF-8 且 48 KB），「继续修改并生成新版本」无法闭环。
9. **Settings 有 4 个完整构建但永不渲染的 section**（`FamiliarSettingsView.swift:143-212`）。更严重的是该页 `.task` 仍会跑 `refreshNotificationAuthorization`，在未授权时静默 `setEnabled(false)`（`:359`）—— 一个没有可见通知控件的页面关掉了通知，属真实 bug。
10. **三个 Agent 预算与 Shell 超时不可配置。** `makeRuntime`（`FamiliarAppDependencies.swift:186-194`）一个都不传，只有测试能覆写。
11. **Dynamic Type 全仓库 0 处适配**（无 `dynamicTypeSize`/`ScaledMetric`/`sizeCategory`），同时存在固定点数与固定 frame。

### 修改文件

仅新增文档，未改动任何生产代码：

- `docs/product-completion/codebase-audit.md`（新增）
- `docs/product-completion/architecture-contracts.md`（新增）
- `docs/product-completion/e2e-scenarios.md`（新增）
- `docs/product-completion/nightly-log.md`（新增）

### 运行过的命令

- `git status --porcelain=v1 -b`
- `git checkout -b feature/familiar-product-completion`
- `xcodebuild -project familiar.xcodeproj -list`
- `xcodebuild -showdestinations -project familiar.xcodeproj -scheme Familiar`
- `xcodebuild ... -destination 'platform=iOS Simulator,id=5E9F91D1-73AE-4236-AD61-9244CE4B3A63' -derivedDataPath <独立目录> -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build-for-testing`

### 测试结果

- 基线 `build-for-testing`：`** TEST BUILD SUCCEEDED **`（独立 DerivedData，Debug，arm64 iOS Simulator `iPhone 17 Pro Max` / OS 26.5）。App、Share Extension、Widget 与两个测试 target 全部完成编译。
- 必须使用具体 arm64 Simulator destination；`generic/platform=iOS Simulator` 会解析成 x86_64 并导致 iSH 静态库链接失败（见 `logs/arm64-simulator-destination-required-for-ish-linking.md`）。
- 基线测试**已实际执行并通过**：`FamiliarBaselineTests` + `FamiliarRuntimeTests`，`Test run with 35 tests in 2 suites passed after 1.473 seconds`（串行，`-parallel-testing-enabled NO`）。这是改动前的真实基线，后续回归以此对比。
- 其余 23 个 suite 与 `FamiliarUITests` 本轮未执行，将在首个代码切片完成后按 `Scripts/run-release-test-suites.sh` 补齐。

### 尚未验证

- 真实 DeepSeek Key 冒烟（认证、模型列表、流式、取消、Tool Call 回填）。
- iSH guest 真实冷启动、`python-docx` 安装、取消、网络边界、资源限制。
- 所有 Apple Framework 工具的真实系统授权行为（WeatherKit entitlement、HealthKit/PhotoKit/MusicKit/CoreBluetooth 授权、AlarmKit 需 iOS 26.1 设备）。
- Quick Look 能否渲染生成的 DOCX；系统分享与 Files 导出。
- 无障碍：VoiceOver、Dynamic Type、Reduce Motion 的实际表现。

### 当前阻塞

无不可逆阻塞。外部凭据与真机缺失均按策略以 Fake Adapter + `device-unverified` 标记绕过，不暂停开发。

### 下一步最高优先级

1. Runtime 就绪契约：Registry 支持等待就绪 / 明确报告未就绪；`manifests()` 保留并透出不可用原因；`environment_status` 解除 guest 门控；统一生命周期加入 `degraded`。
2. Settings 死控件与副作用：删除 4 个不可达 section 及其静默禁用通知的 bug；Limits 文案改为从 `FamiliarShellLimits` 派生；把三个 Agent 预算与 Shell 超时接到真实持久化设置并到达 `FamiliarAgentLoop` 初始化器。
3. Memory 三层运行时：先修 scope 去重 / `lastUsedAt` / 唯一约束三个既有缺陷，再加工具、Context Compiler 相关性选择与字符预算、Settings 管理与自动记忆开关。
4. `artifact_read` + Artifact 版本，闭合场景一步骤 13 与场景四。

### 北京介绍 Word 闭环状态

**未闭环。** 校验/发布/审计半程 `verified-by-tests`（真实 AnyDoc 解析 `sample.docx`）；生产半程 `device-unverified`（无原生 OOXML writer，依赖 iSH guest）；「继续修改并生成新版本」结构性缺失（无 `artifact_read`、Artifact 无版本）。

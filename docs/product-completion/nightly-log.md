# Nightly Log — 成品化持续开发

倒序记录。每条必须区分「已执行并通过」与「仅编译」，禁止声称没有实际运行过的测试已通过。

---

## 2026-09-02 · 第 1 轮：只读审计与基线

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

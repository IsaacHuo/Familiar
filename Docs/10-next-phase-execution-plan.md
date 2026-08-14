# Familiar 下一阶段执行计划

基线日期：2026-08-13  
代码基线：`main @ f4ab809`  
依据：[`阶段性分析/Familiar_deep_product_and_architecture_review_2026-08-13.md`](阶段性分析/Familiar_deep_product_and_architecture_review_2026-08-13.md)

## 1. 阶段目标

下一阶段只围绕一条主链路推进：

> 创建课程项目，导入 PDF，设置项目指令，在多条对话中持续引用资料，生成可保存工件，关闭并重新打开 App 后继续工作，并能查看本次 Run 实际使用的上下文和能力。

当前只读 Web 已实现，应作为 Project Resource 和引用链路的一部分继续演进，不再另起一个 Web 子项目。

## 2. 当前基线

### 已有

- 12 个内置 Provider 和自定义 OpenAI-compatible Provider。
- 8 个启动时静态注册工具：2 个本机信息、2 个只读 Web、4 个 EventKit。
- 有限、串行、最多 6 轮的单 Agent Tool Loop。
- 结构化 EventKit 写入确认和当前进程内一次性 Undo。
- Conversation、Message、Attachment、Source、Run/Step 摘要持久化。
- Share、Deep Link、Intents、通知、Spotlight、Widget/Control 等系统入口。
- 31 个 Swift Testing 测试（包含参数化的 8 场景 Benchmark）和 1 个 UI 冷启动测试。

### 核心缺口

- 没有 Project、Resource、Artifact、ProjectInstruction 或 CapabilityBinding。
- 没有不可变 Context/Capability/Authorization snapshot。
- Registry 不能发现、安装、版本化或按项目绑定能力。
- 生产路径没有可审计 AuthorizationGrant。
- Run 没有 ResumeCursor，幂等和 Undo 只在当前进程内。
- VersionedSchema/migration plan 已在 WP2 建立；iOS CI 与 benchmark runner 已在 WP0 建立，远程 CI 首次结果仍待 GitHub Actions 执行。
- Memory、Skills、MCP 和后台执行只有目标设计或预览 UI。

## 3. 执行原则

1. 每个工作包必须留下可运行 App，不并行铺开孤立菜单。
2. 数据模型和运行路径先于 Project UI；没有持久化与 ContextSnapshot 时不开放入口。
3. 迁移先于 Schema 扩张；恢复数据契约先于后台 API。
4. 系统入口只提供 provenance，永不产生写授权。
5. 只读 Web 内容与未来 MCP 内容始终按不可信输入处理。
6. 不新增 Provider、Widget、系统入口、多 Agent、Shell、复杂 RAG 或本机 MCP Server。
7. Memory、Skills、MCP 保持隐藏或明确 Labs 状态，直到端到端接入 Runtime、Policy 和删除语义。
8. 当前 EventKit 与后续 Artifact 写入保持逐次结构化确认；AuthorizationGrant 在持久化单次消费和幂等语义完成前只建模、不启用免确认执行。

## 4. 工作包

### WP0 可验证内核

状态：本地完成，远程 CI 待首次执行。

目标：让 Agent 行为变化能够自动回归。

工作项：

- 把 8 个 MVP Benchmark 变为 fake-provider 场景测试。当前支持的 6 条路径断言成功；图片海报和 Weather 场景断言明确的能力 gate，不伪装完成。
- 每个场景记录终态、工具序列、审批序列、模型轮数、耗时和可用时的 usage/cost。
- 建立真实 Provider 手工 smoke checklist，按协议族验证流式、取消、错误与一次真实工具闭环。
- 增加 arm64 Simulator iOS build/test CI；分别报告 build、unit test 和 UI cold-launch。
- CI 适配 AnyDoc XCFramework 只有 arm64 Simulator slice 的事实。

实现：

- `FamiliarTests/FamiliarBenchmarkTests.swift` 参数化运行 8 条场景并输出 `BENCHMARK` 诊断。
- `Scripts/run-agent-benchmarks.sh` 提供本地一条命令入口，可用 `FAMILIAR_SIMULATOR_ID` 指定 Simulator。
- `.github/workflows/ios.yml` 分别执行 arm64 Simulator build、unit/benchmark tests 和 UI cold-launch smoke。
- `11-real-provider-smoke-checklist.md` 记录真实 Key 的协议族与 Provider 手工验收步骤。

验收：

- 本地一条命令可运行全部 fake-provider benchmark。
- 已知失败能指出具体场景和事件序列，不只返回测试失败。
- PR 或 `main` 的 iOS build/test 有持续状态，不再只有 Pages badge。

停止条件：Benchmark 仍依赖真实 Key、随机模型行为或人工点击时，不进入 WP1。

### WP1 结构边界整理

目标：在增加 Project 前降低现有 Presentation 状态容器的耦合。

工作项：

- 按现有职责拆分全局侧栏、设置 feature screen、Run timeline 和 Run persistence recording。
- 不做纯文件大小重构；每次拆分必须保持现有行为和状态所有权清晰。
- 隐藏 Memory/MCP/Skills 预览入口，或统一移入明确标记的 Labs。
- Settings 的工具列表先读取现有 `FamiliarToolRegistry` 的只读 snapshot，消除重复静态清单；完整 CapabilityCatalog 留到 WP6。

验收：

- `FamiliarChatView` 不再同时拥有全局导航、聊天页面和未来 Project 导航职责。
- `FamiliarChatController` 不再直接承担全部 Run 记录细节。
- 现有 benchmark 和 Simulator build 通过。

### WP2 SwiftData 正式迁移基础

目标：允许 Project Schema 安全演进。

状态：2026-08-14 已完成基础层。当前 7 实体已冻结为 `FamiliarSchemaV1`，正式 migration plan 已接入生产与测试容器；磁盘重开、关系保持、可空关系演练和非破坏性失败测试通过。Project/Resource 字段未加入。

工作项：

- [x] 固化当前 7 实体 Schema 为 VersionedSchema v1。
- [x] 建立 SchemaMigrationPlan 和内存/临时 store 迁移测试。
- [x] 明确容器创建失败、迁移失败和用户确认重建三条路径。
- [x] 保留当前重建界面作为异常恢复，不作为正常升级策略。

验收：

- 当前 V2 store fixture 可升级且 Conversation、Message、Attachment、Source、Run/Step 数据保持一致。
- 迁移失败不静默丢数据，错误可观察。
- 新增一个可空关系的演练迁移测试通过。

停止条件：不能从当前 Schema 稳定迁移时，不合入 Project 实体。

### WP3 Project 最小纵切

目标：建立真实的长期工作单元，不做完整项目中心。

状态：2026-08-14 已完成。`FamiliarSchemaV2` 已通过轻量迁移接入 Project 与 ProjectInstruction；普通聊天保持无项目归属，项目聊天注入项目指令，Run 在开始时固化项目归属。抽屉、项目列表/详情/编辑、归档/取消归档、空项目永久删除与项目内新聊天均已接入现有单 ChatController。

工作项：

- [x] 新增 Project：ID、名称、说明、状态、创建/更新时间。
- [x] Conversation 增加可空 Project 关系，普通聊天继续独立存在。
- [x] 新增 ProjectInstruction，并在项目对话请求中明确注入。
- [x] 完成项目列表、空状态、创建、重命名、归档和项目内新聊天。WP3 只允许删除没有 Resource、Artifact 或运行中 Run 的空项目。
- [x] Run 记录可关联 Project。

验收：

- 创建项目和两条项目对话，重启后归属与项目指令保持一致。
- 普通聊天不受项目指令影响。
- 空项目删除和归档语义有自动测试，不留下孤立关系；完整级联/软删除在 WP4 随 Resource 生命周期定义。

### WP4 Resource 与 ContextSnapshot

目标：把附件管道升级为 Project Workspace v1。

状态：2026-08-14 已完成当前约定范围。`FamiliarSchemaV3` 通过 V2→V3 轻量迁移加入 Resource/Version 与 Run ContextSnapshot 引用；项目资源独立存储、确定性上下文、预算拒绝、项目删除脱离历史记录和双语 UI 已接入。Resource 工具、Artifact、Memory 和 Binding 未加入。

工作项：

- [x] 新增 Resource 与稳定 ID，记录 kind、版本、来源、content hash、本地路径和派生文本 lineage。
- [x] Project Resource 文件使用独立目录；Message Attachment 可选引用 ResourceVersion，但不拥有共享文件生命周期。
- [x] `ProjectContextAssembler` 生成不可变 ContextSnapshot，记录 Project/Conversation、Resource 版本、ProjectInstruction、Provider/Model、暴露工具和输入预算。
- [x] 项目详情支持资源导入、进度/错误、Quick Look、删除和项目删除确认。
- [ ] `resource.list/read/search` 工具和回答内上下文资料展示留待后续，不在 WP4 当前产品范围开放。

验收：

- 同一 PDF 可被项目内多条对话引用，编辑或删除单条消息不会删除 Project Resource。
- 重启后 ContextSnapshot 指向相同 Resource 版本。
- 明确 Project 删除时 Conversation 级联或脱离、Resource/Artifact 文件清理、运行中 Run 处理、软删除保留期和失败回滚；对应自动测试通过。

### WP5 Artifact 与 Web 项目闭环

目标：让 Agent 结果成为长期可管理对象。

工作项：

- 新增 Artifact，第一版只支持 Markdown/纯文本生成结果。
- 实现受控 `artifact.write`、查看、重命名、删除和导出；第一版写入逐次结构化确认。
- 允许把本次 Run 实际使用的 `web_fetch` 可读文本保存为 Project Resource，记录 URL、访问时间、内容 hash、截断状态和来源；不通过二次 refetch 冒充原始版本。
- Share Extension 导入后允许选择普通草稿、新项目或已有项目。

验收：

- PDF + Web 多来源总结可保存为 Artifact，并显示 Resource/Source lineage。
- Artifact 写入仍经过明确能力和项目作用域，不获得文件系统任意写权限。

### WP6 Capability 与授权契约

目标：在 Skills/MCP 前建立统一治理层。

工作项：

- Manifest v2 增加稳定 ID/版本/来源、Schema、载荷上限、effect/risk、数据与网络域、隐私标签、幂等/取消/恢复/并行属性和所需作用域。
- 拆分 CapabilityCatalog、CapabilityResolver 和 CapabilityBindingStore。
- 引入 AuthorizationGrant 数据模型：user action、source、capability、规范化 arguments hash、project scope、expiry、single-use 和 evidence；WP6 不启用免确认写入。
- 删除或替代当前来源枚举式 `FamiliarOneShotAuthorization`。

验收：

- Project 只暴露显式启用且当前可用的能力。
- Share、Intent、Deep Link 无法生成写 grant。
- grant 参数、作用域或有效期不匹配时必须确认或拒绝；即使匹配，WP7 完成前仍逐次确认。

### WP7 可恢复 Run

目标：先完成恢复数据契约，再考虑后台承接。

工作项：

- 持久化 Context/Capability/Authorization snapshot、完整工具调用或稳定引用、Artifact/Result 引用和 ResumeCursor。
- 持久化幂等状态，保证中断恢复不重复写入。
- grant 的单次消费与副作用提交使用可验证的崩溃安全状态机；只有该路径通过中断测试后，才允许匹配 grant 的可逆写入免重复确认。
- 定义可恢复、不可恢复、安全终止三类结果。
- 增加错误分类、有限重试和 token/成本/总耗时/工具调用预算；失败不能通过静默 fallback 隐藏。
- iOS 26+ 再评估 `BGContinuedProcessingTask`；iOS 18–25 明确尽力执行或提醒用户继续。

验收：

- 在模型轮次之间和工具提交前后模拟中断，恢复后不重复 EventKit 写入或 Artifact 写入。
- 无法恢复时显示明确终态，不伪装成功。
- UI 明确显示执行保证等级。

## 5. 后续工作

WP0–WP7 完成后再进入：

1. instruction-only Skills 的导入、预览、安装、项目绑定和删除。
2. Remote HTTPS Streamable HTTP MCP、OAuth/PKCE、工具发现和项目绑定。
3. global/project/conversation scoped Memory，自动写入默认关闭。
4. Contacts、Photos、Maps、Location、Weather 等新的原生能力。

## 6. 第一轮实施建议

第一轮只执行 WP0，不同时开始 Project UI。推荐顺序：

1. 建立 8 场景 fake-provider benchmark runner。
2. 为现有 Web 和 EventKit 路径补齐可确定事件序列断言。
3. 增加 arm64 Simulator iOS CI。
4. 记录首个基线结果，再进入 WP1 和 WP2。

第一轮完成定义：任何后续 Agent 或 Project 改动都能在无真实 API Key、无 Simulator 人工交互的条件下得到可重复的行为证据。

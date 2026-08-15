# Familiar 长期路线图

> 本文描述**长期规划**（未来要构建什么）。已完成工作包的状态与当前进度见 `state/CURRENT.md`；本文只保留与未来相关的规划。

## 1. 主线目标

下一阶段围绕一条主链路推进：

> 创建课程项目，导入 PDF，设置项目指令，在多条对话中持续引用资料，生成可保存工件，关闭并重新打开 App 后继续工作，并能查看本次 Run 实际使用的上下文和能力。

Project 主链路的数据层与基础 UI 已完成；剩余工作是把已建模的能力接到真实执行，并沿 Web、Skills、MCP、Memory 方向扩展。

## 2. 执行原则

1. 每个工作包必须留下可运行 App，不并行铺开孤立菜单。
2. 数据模型和运行路径先于 UI；没有持久化与 ContextSnapshot 时不开放入口。
3. 恢复数据契约先于后台 API。
4. 系统入口只提供 provenance，永不产生写授权。
5. 只读 Web 内容与未来 MCP 内容始终按不可信输入处理。
6. 不新增无谓 Provider、Widget、系统入口、多 Agent、Shell、复杂 RAG 或本机 MCP Server。
7. Memory、Skills、MCP 保持隐藏或明确 Labs 状态，直到端到端接入 Runtime、Policy 和删除语义。
8. 写入保持逐次结构化确认；`AuthorizationGrant` 在持久化单次消费和幂等语义完成前只建模、不启用免确认执行。

## 3. 已完成的基础

以下工作包已交付，本文不再重复其内容，细节以 `state/ARCHITECTURE.md` 与代码为准：

- **可验证内核**：8 场景 fake-provider Benchmark、`Scripts/run-agent-benchmarks.sh`、arm64 Simulator iOS CI。
- **SwiftData 迁移基础**：V1 冻结 + 正式 migration plan（V1→V6）。
- **Project 最小纵切**：Project/ProjectInstruction、对话归属、项目 UI。
- **Resource + ContextSnapshot**：版本化项目资源、不可变上下文快照、确定性预算。
- **Artifact + Web 项目闭环**：`artifact_write` 工具、`web_fetch` capture 落为项目资源。
- **Capability 与授权契约**：Manifest v2、确定性 CapabilitySnapshot、AuthorizationGrant 数据模型。
- **可恢复 Run 数据契约**：RunResumeCursor / ToolInvocation 幂等记录。

## 4. 下一步工作

按顺序推进（前项完成后进入后项）：

### 4.1 图片输入路径（进行中）

- 完成图片从草稿到模型的发送链路（Anthropic / Gemini 图片编码已在工作树实现）。
- 补适配器 fixture、能力 gate 测试与隐私确认（图片字节只发往用户所选 Provider）。

### 4.2 把已建模契约接入运行时

- `FamiliarRunRecoveryService`、grant-aware policy、`FamiliarCapabilityResolver` 接入真实 Agent 执行。
- 工具调用状态机（requested/approved/committing/committed/failed/cancelled）与中断恢复不重复写入。
- 错误分类、有限重试、token/成本/总耗时/工具调用预算；失败不能通过静默 fallback 隐藏。
- `resource.list/read/search` 工具与回答内上下文资料展示。
- Artifact / CapabilityBinding 的项目级 UI 绑定。

### 4.3 系统入口与 Workspace 补全

- Share Extension 导入后允许选择普通草稿、新项目或已有项目。
- Run 入口提供精确滚动锚点。

### 4.4 真实验证

- 按 `11-verification-and-release-checklist.md` 完成真实 Provider 冒烟与真机验收。
- 确认 iOS CI 远程首轮结果；SwiftData 真机恢复路径验收。

### 4.5 后续能力（每项都需真实任务驱动）

1. instruction-only Skills：导入、预览、安装、项目绑定、tool scope 和卸载；Skill 只能收窄 Tool Scope。
2. Remote HTTPS Streamable HTTP MCP Client：OAuth/PKCE、工具发现、项目绑定；MCP 工具继续经过 Familiar Policy。
3. global/project/conversation scoped Memory，自动写入默认关闭。
4. Contacts、Photos、Maps、Location、Weather 等新的原生能力。
5. iOS 26+ 后台承接（`BGContinuedProcessingTask`）与 iOS 18–25 的明确降级（见 `logs/bgcontinuedprocessingtask-is-ios26.md`）。

## 5. 验收主线

- 在模型轮次之间和工具提交前后模拟中断，恢复后不重复 EventKit 写入或 Artifact 写入。
- 无法恢复时显示明确终态，不伪装成功；UI 明确显示执行保证等级。
- "创建课程项目 → 导入 PDF → 设置指令 → 多对话引用 → 生成 Artifact → 重启继续 → 查看本次 Run 的上下文与能力"端到端跑通。

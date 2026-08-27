# Familiar 下一阶段执行计划

> 本文记录当前收尾后的工作顺序。实际实现和验证证据以 `state/CURRENT.md`、`state/ARCHITECTURE.md` 为准。

## 1. 当前阶段结论

Familiar 保留 Native-First、Local-First 的长期方向：

```text
Core AI + Qwen local model
        ↓
iOS 27 正式可用后的默认本地大脑

Native iOS Tools
        ↓
通过 Apple frameworks 访问设备能力

iSH / Containerization
        ↓
运行时资产准备完成后的受控本地计算

通用 ModelProvider
        ↓
当前唯一启用的云 Provider descriptor 是 DeepSeek
```

DeepSeek 不进入 Agent Runtime 的特殊分支。当前网络实现是通用 OpenAI-compatible adapter；DeepSeek 只是目前唯一启用的 descriptor、模型目录和 BYOK 配置。ModelRouter、Tool Call、SSE、ToolResult 和错误合同均保持供应商无关。

Core AI 当前不具备真实实施条件。开发环境仍是 Xcode 26.6/iOS 26 SDK，计划依赖的 iOS 27 Core AI API、Apple 支持的 Qwen bundle 和 specialization 资产不可用。本阶段不把完全本地对话作为交付门槛，也不使用 MLX 文本模型或其他 Runtime 冒充 Core AI。

新安装默认路由临时为 `.cloud`。`localOnly`、`preferLocal`、ModelManager、Core AI adapter 和云升级确认合同继续保留；等 iOS 27 正式工具链与模型资产可用后，再恢复 `preferLocal` 默认策略。

FastVLM 当前暂停提供。仓库内研究实现暂留，但设置入口、依赖注入和 Chat 自动路由已断开，不属于当前能力或验收范围。

## 2. 当前模型基线

当前 catalog 只属于 DeepSeek：

- `deepseek-v4-flash`：默认文本与 Agent 测试模型。
- `deepseek-v4-pro`：复杂推理补充测试。
- `deepseek-v4-flash-vision-exp`：实验图片识别入口，和文本模型使用同一通用 Provider adapter。

前两个模型 ID 已由 DeepSeek 官方的[模型与价格](https://api-docs.deepseek.com/quick_start/pricing/)和[`GET /models`](https://api-docs.deepseek.com/api/list-models/)文档确认。视觉实验 ID 是当前产品明确保留的接口，需要用真实账户单独验证 `/models`、图片请求格式、流式、Tool Call 能力和错误语义；不可用时应明确报错，不静默切换成另一个模型。

不支持图片的模型继续使用 Apple Vision 生成设备端 OCR、条码和基础分类证据。FastVLM 不参与当前路由。

## 3. 收尾目标

使用真实 DeepSeek 测试 Key 跑通一条可重复、可审计的 iOS 主路径：

```text
用户请求
  → FamiliarModelProvider
  → 当前 DeepSeek descriptor
  → stream / FamiliarToolCall
  → ToolRegistry
  → Native Tool
  → 写操作审批
  → FamiliarToolResult
  → 同一 Provider 继续同一 Run
  → 最终回答与本地持久化
```

## 4. 实施顺序

### Phase A：静态收敛

- Catalog 只启用 DeepSeek，adapter 保持通用 OpenAI-compatible 命名和实现。
- API Key 只存在于 Keychain 和 Provider 实例，Agent Runtime 不接收 Key。
- FastVLM 不显示设置入口，不参与 DI 或图片自动路由。
- Chat 保持唯一执行 Surface，Project 只提供长期 Workspace/Context。
- 执行 arm64 `build-for-testing`、macOS build、本地化检查和 `git diff --check`。

完成标准：源代码和测试产物可编译；文档不把 Core AI、FastVLM、iSH、Container VM 或 FamiliarMac shell 描述成当前已验收能力。

### Phase B：DeepSeek 文本 API 冒烟

1. 保存非生产测试 Key，执行连接验证和 `GET /models`。
2. 使用 `deepseek-v4-flash` 完成普通文本流式回答。
3. 主动取消长请求，确认网络任务终止、Composer 恢复、没有伪终态消息。
4. 使用无效 Key、无效模型 ID、断网和服务端错误，确认错误有限、可恢复且不泄露 Key。
5. 验证 reasoning delta、正常 stop、长度终止和空响应处理。
6. 对 `deepseek-v4-pro` 重复最小文本/Tool Call 冒烟。

完成标准：认证、模型列表、流式、取消和错误五类结果均有真实运行证据。

### Phase C：DeepSeek 图片 API 冒烟

1. 确认 `/models` 是否返回 `deepseek-v4-flash-vision-exp`。
2. 使用一张无隐私测试图片验证请求编码、流式回答和取消。
3. 验证多图、过大图片、不支持的 MIME、错误模型和服务端拒绝。
4. 确认视觉模型不可用时显示真实错误，不改用 FastVLM，也不把基础 Apple Vision 结果包装成视觉模型回答。
5. 如果模型支持 Tool Call，再验证图片上下文后的只读 Tool；写操作仍经过同一审批链。

完成标准：能够确认这个实验 ID在当前账户中的真实可用边界，并将结果记录到 `state/CURRENT.md`。

### Phase D：Native Tool 闭环

优先使用提醒事项场景：

1. “明天下午有什么提醒？”验证 `reminders` 读取。
2. “提醒我明天下午三点复习”验证 `create_reminder` Tool Call。
3. 在审批前取消，确认 EventKit 零写入。
4. 批准后确认只创建一条提醒，并返回 typed ToolResult。
5. Provider 接收 ToolResult 后在同一 Run 生成最终回答。
6. 重启 App 后执行 Undo，确认系统对象删除、记录进入已撤销状态。

完成标准：模型不能自授权；取消零写入；成功最多一次；重启后仍可撤销。

### Phase E：测试执行与缺陷硬化

- 实际执行 Swift Testing 和 Agent benchmark；`build-for-testing` 不等于测试通过。
- 覆盖 Router、OpenAI-compatible SSE、Tool Call 增量、ToolResult 回填、取消和错误分类。
- 在真机验证 EventKit、Apple Vision、DeepSeek 图片模型、文档、Share、Spotlight/App Intents 与 Keychain。
- 只修复真实验收暴露的问题，不在收尾阶段扩展 Provider、Shell 或本地模型矩阵。

## 5. 本轮不阻塞的工作

- Core AI/Qwen 本地文本模型。
- FastVLM 下载、基准与本地推理。
- iSH fork、Alpine rootfs 和 Familiar bridge。
- macOS kernel/init/rootfs/container runtime assets。
- FamiliarMac 与共享 SwiftData/Agent Runtime 的完整接线。
- Attachment、Resource、Artifact 的 Workspace 物理归并。
- Memory Runtime、Remote MCP、后台可靠执行和多 Agent。

这些能力不得出现在当前可用功能说明中。已有 adapter、policy、研究代码或 UI shell 只代表结构准备。

## 6. Core AI 重启条件

1. iOS 27 与 Xcode 27 正式版可用于目标设备和 CI。
2. Apple 发布或确认可用的 Qwen 小模型 Core AI 资产、版本、大小和 SHA-256。
3. `CoreAILanguageModel`、specialization 与 `LanguageModelSession` API 可在正式 SDK 编译。
4. 目标 iPhone 的内存、首 token、持续 token/s、温度、电量和 Tool Call 基准已定义。
5. 断网流式、权重复用、取消、删除和失败恢复可在真机验收。

满足后按顺序实施：ModelManifest → ModelManager 下载/校验 → prepare/specialization → runtime actor 复用权重 → 每 Run session → ModelRouter 恢复 `preferLocal` 默认值。

## 7. 阶段完成定义

- 当前唯一启用 Provider descriptor 是 DeepSeek，但底层 adapter 保持通用。
- `deepseek-v4-flash` 真实文本流式通过。
- `deepseek-v4-flash-vision-exp` 的可用或不可用边界有真实证据。
- 无效 Key、取消和至少一种网络/服务端错误通过。
- Reminder read/write/approval/ToolResult/final response/Undo 通过。
- 自动测试实际执行并记录，不只有编译证据。
- Core AI、FastVLM、iSH、Containerization 和 FamiliarMac 未完成能力保持不可执行或明确 unavailable。

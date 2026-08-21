# Familiar 验证与发布清单

用途：在不把真实 API Key 写入自动化环境的前提下，验证认证、流式协议、错误边界、工具闭环、真机行为与发布门槛。每次执行记录 App commit、设备/iOS、Provider、模型 ID、时间和结论；**不要记录 API Key、完整问题或返回的私密内容**。

当前实现边界与最新验证证据见 `state/CURRENT.md` 和 `state/ARCHITECTURE.md`。本文件只维护稳定的手动、真机与发布检查，不复制单次构建或测试结果。

## 1. 真实 Provider 冒烟

当前阶段只把 DeepSeek 作为阻塞验收 Provider，默认主路径为 `deepseek-v4-flash`；真实 Key 和真机验收由所有者执行。其他内置 Provider 保留在后续兼容性矩阵，不阻塞当前工作层交付。

### 1.1 通用前置

- 使用非生产测试 Key，并确认 Key 只保存在对应 Provider 的 Keychain 项。
- 使用公开、非私密问题；工具测试使用可删除的测试日历或提醒列表。
- 记录 Provider endpoint、协议族、模型 ID 和模型能力标记。
- 抓取 App 可见状态和必要的脱敏网络错误，不保存 Authorization header。

### 1.2 当前主路径：DeepSeek

使用 `deepseek-v4-flash` 完成认证、文本流式、错误 Key、模型列表、取消、工具调用、Apple Vision 证据注入以及日历/提醒闭环。`deepseek-v4-pro` 与 `deepseek-v4-flash-vision-exp` 保留为可选验证，不作为当前阻塞项。

### 1.3 后续 Provider 兼容矩阵

内置 Provider：OpenAI、Anthropic、Gemini、DeepSeek、Groq、xAI、OpenRouter、Qwen、Kimi、GLM、MiniMax、SiliconFlow。

| 场景 | 操作 | 通过标准 |
|---|---|---|
| 认证成功 | 保存有效 Key，执行连接验证 | 明确成功，不泄露 Key |
| 文本流式 | 发送简短非私密问题 | 收到增量文本和正常 stop，不出现空响应 |
| 错误 Key | 替换为无效 Key | 显示认证失败，不显示虚假回答 |
| 模型列表 | 刷新模型列表，或验证 curated fallback | 有 endpoint 时解析列表；无 endpoint 时保留可编辑模型 ID |
| 超时/取消 | 发送长请求并主动停止 | 请求终止，UI 回到可发送状态，不保存虚假助手终态 |
| Provider 错误 | 使用无效模型 ID | 显示有限长度错误，草稿和历史可恢复 |

### 1.4 协议族

**OpenAI Chat**：验证 `data:` SSE、`[DONE]`、文本 delta 和 `finish_reason`；对至少一个支持工具的模型验证增量 `tool_calls` 参数、tool result 回填和最终 stop；验证兼容 Provider 的 endpoint、headers 和 stream option 差异没有被统一假设覆盖。

**Anthropic Messages**：验证 `content_block_start`、`content_block_delta`、`message_delta` 和 `message_stop`；验证 `tool_use` ID、`partial_json` 参数增量和 tool result block 回填。

**Gemini Generate Content**：验证 `streamGenerateContent?alt=sse`、candidate 文本增量和终止原因；验证 function call 缺少服务端 ID 时，本地调用 ID 在当前 Run 内保持一致。

### 1.5 工具闭环

当前阶段使用 DeepSeek 执行以下主路径；后续扩展 Provider 兼容矩阵时，再为每个协议族选择至少一个真实工具模型重复执行：

1. "明天下午有什么安排？"验证 EventKit read Tool Call。
2. "明天下午三点提醒我测试 Familiar"验证首次结构化授权，默认选择“本次会话”。
3. 在授权前取消，确认 EventKit 零写入。
4. 再次执行并授权，确认只创建一条提醒并显示动作卡和 Undo。
5. 在相同 Project、工具和目标范围内再次创建，确认免重复询问但仍显示动作卡。
6. 改变目标或超出参数范围，确认重新询问。
7. 重启 App 后执行 Undo，确认系统对象被删除、卡片进入已撤销且不能重复 Undo。
8. 执行公开 Web 查询，确认 Sources 可见且失败来源不会被声称已读取。

## 2. 真机验收

### 2.1 EventKit

full access 允许 / 拒绝 / restricted；查询时间范围与文字条件；创建预览、确认写入、取消、任务中止；重复工具调用；系统保存失败。

### 2.2 文件与文档

- iCloud Drive 安全作用域文件、On My iPhone 文件、25 MiB 边界。
- DOCX、PPTX、XLSX、ODT、RTF、EPUB、CSV；文本 PDF；扫描 PDF；加密和损坏文档。
- 附件删除和重新预览。
- 项目资源从 iCloud Drive / On My iPhone 导入、Quick Look、OCR 标记和删除。
- 同一资源在两条项目对话中使用，重启后版本/hash 保持。
- 项目删除后历史聊天仍可打开且资源目录不可恢复；运行中 Run 时删除按钮禁用。

### 2.3 Project 主链路（WP1–WP4）

- 验证统一 Chat 顶栏的设置、工作区、模型和新对话入口；普通/项目工作区恢复各自最近会话，抽屉按置顶、可折叠项目和普通最近会话分区。
- 抽屉、设置、Run timeline 与工具清单在中英文、VoiceOver 和极端 Dynamic Type 下可操作。
- 当前开发存储只验证单一 27 实体 schema 的 `FamiliarDevelopment.store` 首次创建、重启读取和用户确认后的破坏性恢复；没有 active V1→V9 migration chain，也不把旧开发 store 保留作为当前门槛。
- 创建/编辑/归档项目并拒绝重复项目名称；创建普通与项目聊天，确认项目指令只进入项目聊天；历史 Run 项目归属符合启动时快照。
- 从 Composer 显式选择 Skill，确认只影响下一次 Run，工具范围按 snapshot 收窄，后续 Run 不自动继承；当前不验收 Project binding 自动注入或 Skill 导入 UI，因为两者尚未实现。
- 导入文本 PDF、扫描 PDF 和至少一种 Office 文档，确认进度、OCR、Quick Look、文件保护、两条项目聊天共享资料及超预算提示。
- 删除单条消息不删除资源；删除资源后预览不可用；删除项目后聊天/历史 Run 保留并脱离，资源与指令删除。
- 断网/取消/模型失败后 Run ContextSnapshot 元数据和资源 hash 引用仍可读取，且记录中没有完整资源抽取文本。

### 2.4 相机与图片

- 相机权限、前后镜头、闪光灯和 PhotosPicker 多选。
- 多模态模型只把图片发送到当前 Provider。
- DeepSeek 路径使用 Apple Vision 完成 OCR、条码和基础分类，并在折叠运行过程记录方法、版本和原图引用。
- 基础结果不足时说明限制；已配置多模态 Provider 时只建议切换，不自动上传。
- 所有视觉路径失败时文字和图片草稿保持。

### 2.5 FastVLM 本地模型

- 仅在满足准入条件的 iOS 18.2+ 真机测试固定版本 0.5B。
- 显示约 1.23 GB 下载大小、非商业研究许可证和设备要求。
- 验证下载暂停/恢复、断网、空间不足、SHA-256 失败、删除和重新安装。
- 验证安装后短基准、描述/比较/图表问答自动路由和 60 秒超时降级。
- 验证删除模型后历史视觉证据仍可读取。

### 2.6 Speech

Speech 权限、麦克风权限、中文转写、设备端识别、系统中断、App 失活停止、无录音文件。

### 2.7 系统入口

Share Extension（Notes/Safari/Files 来源、文件协调、签名环境）、Deep Link（冷启动/回前台）、通知（权限、锁屏呈现、冷启动点击、目标已删除）、Spotlight（索引延迟、中英文查询、设备锁定、冷启动、重命名/删除刷新）、App Intents（Siri/Shortcuts/Spotlight/Action Button、后台唤起、语音参数、真实请求）、Widget/Control（Gallery、主屏幕/锁屏启动、控制中心注册、未发送草稿保护）。

### 2.8 SwiftData 恢复

- **当前开发阶段**：验证 `FamiliarDevelopment.store` 首次创建、当前 schema 重启读取，以及损坏 store、权限异常、磁盘空间不足时的启动行为；用户确认破坏性重建后 Keychain 保留。开发 schema 变化允许清除测试数据，不要求迁移旧开发 store。
- **未来公开发布**：首次公开发布前冻结版本化 schema；之后每次不兼容 schema 变化都必须从所有受支持的已发布版本执行覆盖安装和磁盘迁移测试。迁移失败必须提供不静默删除用户数据的恢复路径。

## 3. UI 验证矩阵

- iOS 18 和 iOS 26。
- Light 和 Dark。
- 简体中文和英文。
- Dynamic Type（含极端字号）。
- VoiceOver（含焦点返回、连续工具状态播报）。
- Reduce Motion 与 Reduce Transparency。
- Increase Contrast 与 Bold Text。
- 键盘交互与抽屉边缘手势。
- 长回答和滚动稳定性。
- 信息性状态无卡片背景，完成后默认折叠。
- 单张动作卡普通布局；多张动作卡近全宽横向 pager、逐卡吸附、边缘渐隐和轻触觉。
- 多动作部分成功/失败、失败重试和已撤销终态。
- Markdown、代码、表格、引用、KaTeX、Mermaid。
- 复制、分享、编辑、重试。

## 4. 发布前质量门槛

### 构建

- Debug generic iOS、Release generic iOS、iOS 18 arm64 Simulator 均通过。
- 当前 Xcode 稳定版 Swift 6 警告清零。
- `build-for-testing` 只证明 App 与测试产物完成编译；只有实际执行 `test` 或 `test-without-building` 并记录结果，才能声明测试通过。

### 数据

- 当前单一 27 实体 schema 的 `FamiliarDevelopment.store` 首次创建和重启通过。
- 会话、附件和工具终态重启后可读取；删除会话后附件清理通过。
- 开发阶段采用破坏性 schema 策略，测试 store 可重建；这不是未来公开版本的数据迁移策略。
- 首次公开发布前建立版本化 schema 基线；公开发布后的每次 schema 变化都必须提供 migration stage、真实旧版本 store fixture、覆盖安装与磁盘迁移测试，且失败时不得静默删除用户数据。

### Agent

- 无有效授权的写操作在用户授权前零执行；取消写操作零执行。
- 有效 grant 只在 Project、工具、目标、参数和期限均匹配时生效。
- 会话级和长期授权可撤销；模型和系统入口不能产生授权。
- 相同 run 的重复写入最多一次成功。
- 工具失败不显示成功状态。
- EventKit 写入在 App 重启后仍可撤销，撤销结果保留在原动作卡。

### Provider

- 当前阶段 DeepSeek 至少完成一次真实文本流式、错误和工具闭环冒烟。
- 其他内置 Provider 的真实冒烟属于后续兼容性工作，不阻塞当前实验层。
- 自定义 Base URL 行为符合设置说明。

### 隐私

- API Key 不出现在日志和普通存储。
- 图片 bytes 只进入当前多模态 Provider 或设备端视觉处理，不进入其他 Provider 或无关存储。
- 视觉证据带 provenance，作为不可信只读输入，不能产生工具授权。
- FastVLM 模型下载固定版本、来源和哈希，许可证与归属可见。
- Speech 和 EventKit 用途说明与调用一致。
- Markdown 远程图片不自动加载，策略在 App 与官网披露。

### 个人实验交付

- 不以 App Store 审核作为当前门槛。
- 无账户、订阅、托管额度和无效入口。
- Provider 模型 ID 失效时界面可恢复。
- 所有者完成 DeepSeek 真机主路径验收。
- 任何公开分发或商业使用前重新执行许可证、隐私与发布审查。

## 5. 记录模板

```text
Date:
Commit:
Device / iOS:
Provider:
Protocol:
Model ID:
Authentication: pass / fail
Text stream: pass / fail
Invalid key: pass / fail
Model list/fallback: pass / fail
Cancellation: pass / fail
Tool round trip: pass / fail / not supported
Notes (redacted):
```

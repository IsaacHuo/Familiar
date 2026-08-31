# Familiar 验证与发布清单

用途：在不把真实 API Key 写入自动化环境的前提下，验证认证、流式协议、错误边界、工具闭环、真机行为与发布门槛。每次执行记录 App commit、设备/iOS、Provider、模型 ID、时间和结论；**不要记录 API Key、完整问题或返回的私密内容**。

当前实现边界与最新验证证据见 `state/CURRENT.md` 和 `state/ARCHITECTURE.md`。本文件只维护稳定的手动、真机与发布检查，不复制单次构建或测试结果。

## 1. 真实 Provider 冒烟

当前阶段唯一启用的 Provider descriptor 是 DeepSeek，默认主路径为 `deepseek-v4-flash`。底层仍使用通用 `FamiliarModelProvider` 与 OpenAI-compatible adapter，不把 DeepSeek 写入 Agent Runtime 分支。真实 Key 和真机验收由所有者执行。

### 1.1 通用前置

- 使用非生产测试 Key，并确认 Key 只保存在对应 Provider 的 Keychain 项。
- 使用公开、非私密问题；工具测试使用可删除的测试日历或提醒列表。
- 记录 Provider endpoint、协议族、模型 ID 和模型能力标记。
- 抓取 App 可见状态和必要的脱敏网络错误，不保存 Authorization header。

### 1.2 当前主路径：DeepSeek

使用 `deepseek-v4-flash` 完成认证、文本流式、错误 Key、模型列表、取消、工具调用、Apple Vision 证据注入以及日历/提醒闭环。对 `deepseek-v4-pro` 执行最小文本与 Tool Call 冒烟。

图片不进入 DeepSeek 请求。用户添加图片后只由 Apple Vision 在设备端生成有限、不可信的只读证据文字，再进入当前文本模型上下文。

### 1.3 通用 Provider 合同

| 场景 | 操作 | 通过标准 |
|---|---|---|
| 认证成功 | 保存有效 Key，执行连接验证 | 明确成功，不泄露 Key |
| 文本流式 | 发送简短非私密问题 | 收到增量文本和正常 stop，不出现空响应 |
| 错误 Key | 替换为无效 Key | 显示认证失败，不显示虚假回答 |
| 模型列表 | 刷新 DeepSeek `/models`，与 Flash/Pro curated catalog 对照 | 只显示实时可用的正式模型；空交集明确失败 |
| 超时/取消 | 发送长请求并主动停止 | 请求终止，UI 回到可发送状态，不保存虚假助手终态 |
| Provider 错误 | 使用无效模型 ID | 显示有限长度错误，草稿和历史可恢复 |

验证 `data:` SSE、`[DONE]`、文本/reasoning delta、`finish_reason`、增量 `tool_calls` 参数、ToolResult 回填和最终 stop。测试断言针对通用 adapter 合同，不使用 DeepSeek 类型判断；DeepSeek 专有差异只允许放在 descriptor/model capabilities 中。

### 1.5 工具闭环

当前阶段使用 DeepSeek descriptor 执行以下主路径：

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
- 验证单一 `FamiliarReleaseSchema` 的 36 实体、无 migration plan、Debug/Release store 分离、文件 store 重开，以及用户确认后的显式恢复；测试阶段不保留旧 store。
- 创建/编辑/归档项目并拒绝重复项目名称；创建普通与项目聊天，确认项目指令只进入项目聊天；历史 Run 项目归属符合启动时快照。
- 从 Composer 显式选择 Skill，确认只影响下一次 Run；为 Project 绑定候选 Skill，确认只暴露 metadata，`skill_read` 至多加载一个并冻结 snapshot/收窄工具，且不会自动注入或扩大 Capability。
- 导入文本 PDF、扫描 PDF 和至少一种 Office 文档，确认进度、OCR、Quick Look、文件保护、两条项目聊天共享资料及超预算提示。
- 删除单条消息不删除资源；删除资源后预览不可用；删除项目后聊天/历史 Run 保留并脱离，资源与指令删除。
- 断网/取消/模型失败后 Run ContextSnapshot 元数据和资源 hash 引用仍可读取，且记录中没有完整资源抽取文本。

### 2.4 相机与图片

- 相机权限、前后镜头、闪光灯和 PhotosPicker 多选。
- `deepseek-v4-flash` / `deepseek-v4-pro` 使用 Apple Vision 完成 OCR、条码和基础分类，并在折叠运行过程记录方法、版本和原图引用；原始图片不进入 Provider 请求。
- 基础结果不足时说明限制；不自动切换到实验视觉模型，不调用 FastVLM。
- 所有视觉路径失败时文字和图片草稿保持。

### 2.5 FastVLM 不进入 iOS 1.0

- 设置中不显示 FastVLM 安装、下载、基准或删除入口。
- Chat 不自动调用 FastVLM；未安装和历史残留模型均不改变当前路由。
- 当前图片路径只使用 Apple Vision 基础证据。
- Release target 和 Package graph 不包含 FastVLMRuntime/MLX；`Vendor/` 研究源码不进入 App 包。

### 2.6 Speech

Speech 权限、麦克风权限、中文转写、设备端识别、系统中断、App 失活停止、无录音文件。

### 2.7 系统入口

Share Extension（Notes/Safari/Files 来源、文件协调、签名环境）、Deep Link（冷启动/回前台）、通知（权限、锁屏呈现、冷启动点击、目标已删除）、Spotlight（索引延迟、中英文查询、设备锁定、冷启动、重命名/删除刷新）、App Intents（Siri/Shortcuts/Spotlight/Action Button、后台唤起、语音参数、真实请求）、Widget/Control（Gallery、主屏幕/锁屏启动、控制中心注册、未发送草稿保护）。

### 2.8 SwiftData 恢复

- **当前测试阶段**：Debug `FamiliarDevelopment.store` 与 Release `Familiar.store` 共享唯一 `FamiliarReleaseSchema`；旧 store 不支持迁移，schema 变化时直接重建，Keychain 保留。
- **公开发布前**：若决定开始保留用户数据，再单独冻结首个公开 schema 和后续升级策略。

### 2.9 Complex Task Golden Task

- 在 Project Chat 输入“搜索北京的公开资料，整理城市简介、三处代表性地点和实用出行提示，生成一份中文 Word 文档，并在文末列出实际读取的来源链接”。
- 至少两个来源必须经 `web_fetch` 成功读取；只出现在 search result 的页面不得写成已读取来源。
- 分别选择官方 PyPI 与清华 TUNA，确认 `environment_prepare` 审批卡、可信安装命令和 receipt 使用同一个准确索引地址；空 Project Environment 时批准 `python-docx` 依赖方案，确认依赖只进入当前 Project，其他 Project 不可见，App 重启后 lock/receipt 保持。
- 使用真实 iSH 生成 DOCX，`artifact_publish` 必须返回 AnyDoc validation receipt、字节数和 SHA-256；缺失或损坏文件不得完成 Run。
- 在真机 Quick Look 打开，通过 Share Sheet 保存到 Files 并重新打开。分别执行冷启动、缓存 Environment、强制退出后重启三条路径。

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
- 先完成 `build-for-testing`，再运行 `Scripts/run-release-test-suites.sh <simulator-udid> <derived-data-path>`；脚本逐 suite 串行执行全部 Swift Testing 与 UI smoke，并保留每个 suite 的独立 xcresult。

### 数据

- 单一 `FamiliarReleaseSchema` 的 36 实体、无 migration plan、Debug/Release store profile 和文件 store 重开测试通过。
- 会话、附件和工具终态重启后可读取；删除会话后附件清理通过。
- Development store 不迁移到 Release store；测试阶段旧 store 可直接废弃，显式恢复保留 Keychain。
- 公开发布前重新决定并记录持久化兼容策略；当前代码不携带未使用的 migration chain。

### Agent

- 无有效授权的写操作在用户授权前零执行；取消写操作零执行。
- 有效 grant 只在 Project、工具、目标、参数和期限均匹配时生效。
- 会话级和长期授权可撤销；模型和系统入口不能产生授权。
- 相同 run 的重复写入最多一次成功。
- 工具失败不显示成功状态。
- EventKit 写入在 App 重启后仍可撤销，撤销结果保留在原动作卡。

### Provider

- 当前 DeepSeek descriptor 至少完成一次真实文本流式、错误和工具闭环冒烟。
- Flash/Pro `/models`、文本流式与 Tool Call 有脱敏记录；不存在生产图片模型。
- Provider/Agent 测试确认 adapter 和 AgentLoop 没有 DeepSeek 类型判断；当前只启用 DeepSeek 不等于接口绑定 DeepSeek。

### 隐私

- API Key 不出现在日志和普通存储。
- 图片 bytes 只进入设备端 Apple Vision 与本地附件存储，不进入 DeepSeek 或无关存储。
- 视觉证据带 provenance，作为不可信只读输入，不能产生工具授权。
- FastVLMRuntime/MLX 不在 Release 二进制或数据目的地中。
- Speech 和 EventKit 用途说明与调用一致。
- Markdown 远程图片不自动加载，策略在 App 与官网披露。

### Release 交付

- 无账户、订阅、托管额度和无效入口。
- Provider 模型 ID 失效时界面可恢复。
- 所有者完成 DeepSeek 真机主路径验收。
- 所有者使用正式证书生成签名 Archive，检查 Organizer Privacy Report、entitlements、版本一致性与 App Store Connect 隐私问卷。
- 先进入 Internal TestFlight；真实 Key、真机、隐私、许可证与签名 Archive 全部通过后，才可声明 App Store 1.0 ready。

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

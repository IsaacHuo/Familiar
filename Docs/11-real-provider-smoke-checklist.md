# Familiar 真实 Provider 冒烟清单

用途：在不把真实 API Key 写入自动化环境的前提下，验证内置 Provider 的认证、流式协议、错误边界和工具闭环。每次执行记录 App commit、设备/iOS、Provider、模型 ID、时间和结论；不要记录 API Key、完整问题或返回的私密内容。

## 1. 通用前置

- 使用非生产测试 Key，并确认 Key 只保存在对应 Provider 的 Keychain 项。
- 使用公开、非私密问题；工具测试使用可删除的测试日历或提醒列表。
- 记录 Provider endpoint、协议族、模型 ID 和模型能力标记。
- 抓取 App 可见状态和必要的脱敏网络错误，不保存 Authorization header。

## 2. 每个内置 Provider

| 场景 | 操作 | 通过标准 |
|---|---|---|
| 认证成功 | 保存有效 Key，执行连接验证 | 明确成功，不泄露 Key |
| 文本流式 | 发送简短非私密问题 | 收到增量文本和正常 stop，不出现空响应 |
| 错误 Key | 替换为无效 Key | 显示认证失败，不显示虚假回答 |
| 模型列表 | 刷新模型列表，或验证 curated fallback | 有 endpoint 时解析列表；无 endpoint 时保留可编辑模型 ID |
| 超时/取消 | 发送长请求并主动停止 | 请求终止，UI 回到可发送状态，不保存虚假助手终态 |
| Provider 错误 | 使用无效模型 ID | 显示有限长度错误，草稿和历史可恢复 |

内置 Provider：OpenAI、Anthropic、Gemini、DeepSeek、Groq、xAI、OpenRouter、Qwen、Kimi、GLM、MiniMax、SiliconFlow。

## 3. 协议族

### OpenAI Chat

- 验证 `data:` SSE、`[DONE]`、文本 delta 和 `finish_reason`。
- 对至少一个支持工具的模型验证增量 `tool_calls` 参数、tool result 回填和最终 stop。
- 验证兼容 Provider 的 endpoint、headers 和 stream option 差异没有被统一假设覆盖。

### Anthropic Messages

- 验证 `content_block_start`、`content_block_delta`、`message_delta` 和 `message_stop`。
- 验证 `tool_use` ID、`partial_json` 参数增量和 tool result block 回填。

### Gemini Generate Content

- 验证 `streamGenerateContent?alt=sse`、candidate 文本增量和终止原因。
- 验证 function call 缺少服务端 ID 时，本地调用 ID 在当前 Run 内保持一致。

## 4. 工具闭环

至少选择每个协议族中的一个真实工具模型，执行：

1. “明天下午有什么安排？”验证 EventKit read Tool Call。
2. “明天下午三点提醒我测试 Familiar”验证结构化确认。
3. 在确认前取消，确认 EventKit 零写入。
4. 再次执行并确认，确认只创建一条提醒并显示 Undo。
5. 执行 Undo，确认系统对象被删除且不能重复 Undo。
6. 执行公开 Web 查询，确认 Sources 可见且失败来源不会被声称已读取。

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

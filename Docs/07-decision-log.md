# Familiar 决策记录

本文件记录影响产品范围、数据边界和工程结构的决策。每项决策包含状态、依据、影响和复审条件。

## D-001 采用 BYOK 和设备直连

- 状态：生效
- 决策：用户提供各 Provider API Key。iPhone 直接调用 Provider。
- 依据：降低服务端数据责任，保持用户与 Provider 的直接费用关系，支持多 Provider。
- 影响：
  - 首启需要 Provider 配置。
  - App 需要处理不同 endpoint、认证和协议。
  - Provider 可用性和费用由用户选择决定。
  - 公开发布前需要逐 Provider 真实冒烟。
- 复审条件：引入 Familiar 托管服务、账户或统一额度。

## D-002 无账户、无 Familiar 业务后端

- 状态：生效
- 决策：首发不提供登录、云同步、订阅、权益和 Familiar 业务数据库。
- 依据：产品首发范围集中在本机行动助理闭环。
- 影响：
  - 会话只保存在本机。
  - 无跨设备同步。
  - 卸载可能导致本地历史丢失。
  - 网站承担产品说明、隐私和支持功能。
- 复审条件：用户研究明确需要跨设备连续性。

## D-003 iPhone-only，最低 iOS 17

- 状态：生效
- 决策：`TARGETED_DEVICE_FAMILY = 1`，部署目标 iOS 17。
- 依据：集中优化单手聊天和输入器体验，使用 SwiftData 与 EventKit full access API。
- 影响：
  - 不维护 iPad 专用布局。
  - Simulator 和真机验证覆盖 iOS 17 与当前系统。
- 复审条件：iPad 进入正式产品范围。

## D-004 iOS 26 Liquid Glass，旧系统使用 Material

- 状态：生效
- 决策：导航、输入器和浮层在 iOS 26 使用系统 glass API；iOS 17–25 使用 Material 和边框。
- 依据：遵守系统版本能力和 Apple Materials 使用范围。
- 影响：
  - 消息正文不使用玻璃。
  - Reduce Transparency 使用实色回退。
  - UI 验收需要覆盖两个实现分支。
- 复审条件：Apple API 或设计指引变化。

## D-005 采用 ChatGPT 移动端信息结构参考

- 状态：生效
- 决策：参考其抽屉、顶栏、时间线、输入器比例和反馈节奏。
- 依据：目标用户已熟悉聊天型 AI 产品的信息结构。
- 影响：
  - Familiar 使用蓝紫品牌体系。
  - 入口只对应当前真实能力。
  - 账户、订阅、项目和工作区入口不进入界面。
- 复审条件：可用性测试显示主要任务路径需要调整。

## D-006 输入器参考 Leafy 日迹页

- 状态：生效
- 决策：输入器结构、附件菜单、相机和相册选择参考 Leafy 日迹页。
- 依据：该交互已形成明确的移动端内容录入模式。
- 影响：
  - 输入器支持 compact、expanded、fullscreen。
  - 添加菜单包含文件、拍照和相册。
  - Familiar 保留聊天所需的语音和发送/停止状态。
- 复审条件：输入器真机验收发现键盘、长文本或附件操作阻塞。

## D-007 使用字符串 ID 的 Provider Catalog

- 状态：生效
- 决策：Provider 和模型使用字符串 ID 与 descriptor，避免封闭枚举。
- 依据：多 Provider、手动模型 ID 和自定义服务需要开放标识。
- 影响：
  - 会话和消息保存实际 Provider/模型 ID。
  - 未知模型可以进入 text-only 回退。
  - 模型能力由 catalog 控制。
- 复审条件：引入远程 catalog 签名或服务端能力发现。

## D-008 明确区分三类协议 adapter

- 状态：生效
- 决策：OpenAI Chat、Anthropic Messages、Gemini Generate Content 使用独立编码和事件解析。
- 依据：三类 API 的消息、工具和流事件结构不同。
- 影响：
  - OpenAI-compatible Provider 使用逐 Provider 配置。
  - adapter fixture 需要分协议维护。
  - 新 Provider 接入先确认协议和差异点。
- 复审条件：Provider 发布新的稳定统一协议。

## D-009 模型能力执行 gate

- 状态：生效
- 决策：工具、文档、图片和上下文上限由 `providerID + modelID` 决定。
- 依据：不同模型能力差异会影响请求合法性和用户预期。
- 影响：
  - 未知模型默认 text-only。
  - 工具关闭时不发送工具定义。
  - 文档不受支持时请求前阻止。
  - 图片链路关闭时请求前阻止。
- 复审条件：引入可信能力发现和缓存。

## D-010 使用有限 Tool Loop

- 状态：生效
- 决策：Agent Loop 具有轮次、工具注册、参数、结果和上下文限制。
- 依据：首发工具范围固定，需要可预测终止和错误边界。
- 影响：
  - 默认最多 6 轮。
  - 只执行注册工具。
  - 不引入工作流引擎、多 Agent 或通用自动化框架。
- 复审条件：工具数量和任务复杂度超过有限循环能力。

## D-011 EventKit 写入逐次确认

- 状态：生效
- 决策：创建事件和提醒前显示结构化确认卡。
- 依据：系统数据写入需要明确用户意图和可审查参数。
- 影响：
  - 工具 `execute` 先生成 pending write request。
  - 确认协调 actor 暂停 Agent Loop。
  - 取消结果回填模型。
  - 未确认状态下不调用 EventKit save。
- 复审条件：新增修改、删除或批量操作。新增操作仍需保持同等级确认。

## D-012 流式文本不写入 SwiftData

- 状态：生效
- 决策：逐 token 状态保存在 Controller 内存，回答终态一次保存。
- 依据：降低 SwiftData 广泛 invalidation 和写入频率。
- 影响：
  - 中途终止时不保留部分助手消息。
  - 用户消息已在请求前保存。
  - 工具终态可以独立保存。
- 复审条件：产品要求恢复部分生成内容。

## D-013 使用本地非持久化 WebKit 渲染

- 状态：生效
- 决策：Markdown、代码、KaTeX 和 Mermaid 使用 Bundle 资源与 non-persistent WebView。
- 依据：统一流式和终态排版，支持复杂内容格式。
- 影响：
  - WebView 关闭内部滚动并回传高度。
  - 渲染失败提供 SwiftUI 回退。
  - CSP 控制网络和执行边界。
  - 远程 Markdown 图片策略需要发布前确认。
- 复审条件：原生文本栈完整覆盖现有格式和性能要求。

## D-014 文件统一通过 AnyDoc

- 状态：生效
- 决策：支持文档通过 `FamiliarAnyDocService` 进入统一转换链路。TXT 和 Markdown执行编码验证与文本直通。
- 依据：统一格式检测、Markdown 输出、引擎版本和错误表达。
- 影响：
  - Office、OpenDocument、RTF、EPUB、CSV、PDF 使用同一服务入口。
  - Provider 接收抽取文本。
  - 原文件保存在本机。
- 复审条件：增加 Provider 原生文件 API 或新的本地解析引擎。

## D-015 PDF 使用 AnyDoc、PDFKit 和 Vision

- 状态：生效
- 决策：AnyDoc处理文档结构，PDFKit 检查文本层，Vision 处理扫描页。
- 依据：文本 PDF 和扫描 PDF 需要不同处理路径。
- 影响：
  - 无文本层页面执行 OCR。
  - AnyDoc PDF unsupported 时执行 fallback。
  - OCR 准确率进入真机文件验收。
- 复审条件：AnyDoc 提供满足需求的完整 OCR 能力。

## D-016 图片保留输入能力，关闭发送链路

- 状态：生效
- 决策：相机和相册可以创建图片草稿，当前版本阻止图片请求。
- 依据：输入器结构需要完整，模型图片编码和隐私验收尚未进入首发交付。
- 影响：
  - 拦截时保留文字和图片草稿。
  - adapter 保留第二层拒绝。
  - `supportsImages` 元数据不开放发送。
- 复审条件：完成图片编码、Provider 差异、大小处理、隐私和真实模型验证。

## D-017 语音只生成可编辑文本

- 状态：生效
- 决策：使用 Apple Speech 将语音写入输入框，不创建音频消息。
- 依据：首发目标是降低移动输入成本。
- 影响：
  - 不保存录音文件。
  - 可用时优先设备端识别。
  - 识别结果由用户编辑后发送。
- 复审条件：实时语音对话进入产品范围。

## D-018 AnyDoc 只构建 Apple Silicon slices

- 状态：生效
- 决策：XCFramework 包含 iOS arm64 和 iOS Simulator arm64。
- 依据：开发设备统一使用 Apple Silicon Mac。
- 影响：
  - 不提供 x86_64 Simulator slice。
  - CI 和本地构建使用 arm64 destination。
- 复审条件：CI 或开发环境需要 Intel Mac。

## D-019 开发 Schema 使用版本化 store

- 状态：生效，运行迁移场景待验证
- 决策：当前 Schema 使用 `FamiliarAgentV1.store`。首次成功创建后清理旧 `default.store`。
- 依据：旧开发 store 缺少必填字段，SwiftData 自动迁移返回 134110；项目当前无正式用户，计划允许直接替换开发 Schema。
- 影响：
  - 旧开发会话和附件被清理。
  - 用户无需手动卸载以绕过旧 store。
  - 公开版本后需要正式迁移或恢复界面。
- 复审条件：首个公开版本冻结 Schema。

## D-020 项目正式使用 Swift 6

- 状态：生效
- 决策：Debug 和 Release 的 `SWIFT_VERSION = 6.0`。
- 依据：并发隔离问题需要在构建期作为错误处理。
- 影响：
  - DTO、actor、Main Actor 和 AVFoundation worker 边界明确。
  - 新代码需要满足 Sendable 和隔离规则。
  - Debug、Release、Simulator 和真机构建纳入验证矩阵。
- 复审条件：Swift 工具链升级引入新的语言兼容问题。

## 决策维护

新增决策时使用以下字段：

```text
ID
标题
状态
决策
依据
影响
复审条件
```

影响隐私、持久化、写操作和网络目的地的决策需要在代码合并前更新本文件。

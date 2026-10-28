# App Store Connect 提交清单

本文档汇总 Familiar 1.0 可复用的商店文案和网站 URL。提交前请以最终发布构建为准复核功能、权限和隐私答案。

## URL

| App Store Connect 字段 | URL |
| --- | --- |
| Marketing URL | `https://isaachuo.github.io/Familiar/` |
| Support URL | `https://isaachuo.github.io/Familiar/support/` |
| Privacy Policy URL | `https://isaachuo.github.io/Familiar/privacy/` |

这些 URL 会在 GitHub Pages 工作流首次成功部署后生效。

## 基本信息建议

- **App 名称**：`Familiar`
- **副标题**：`原生 AI 问答`
- **主要分类**：效率
- **次要分类**：工具
- **最低系统版本**：iOS 26.0
- **Bundle ID**：`com.isaachuo.familiar`
- **版本**：`1.0`
- **版权**：发布前填写真实的个人或法律主体名称，不要使用占位符提交。

## 推广文本建议

> 使用你自己的 API Key，直接从 iPhone 连接模型服务。会话历史保存在本机，Markdown、代码、Mermaid 与公式在设备上清晰呈现。

## 描述建议

> Familiar 是面向 iPhone 的原生 AI 问答 App。
>
> 自然地提问、思考与创作，获得流式呈现、层次清晰的回答。Familiar 使用你自己的模型 API Key，请求从设备直接发送到你选择的服务，不经过 Familiar 自有聊天服务器。
>
> 核心特性：
>
> • 原生、专注的聊天问答体验  
> • API Key 保存在 iOS Keychain  
> • 会话历史保存在当前设备  
> • 本地渲染 Markdown、代码、Mermaid 与 KaTeX  
> • Word、PowerPoint、Excel、OpenDocument、RTF、EPUB、CSV 与 PDF 由 AnyDoc 在本机转换，只随消息发送转换后的文字  
> • 需要系统权限时按功能请求，并可随时撤销
>
> 使用第三方模型服务可能产生费用，并适用对应服务商的条款与隐私政策。AI 生成内容可能不准确，请勿将其作为医疗、法律、财务或其他高风险决定的唯一依据。

## 关键词建议

`AI助手,聊天,问答,DeepSeek,效率,写作,Markdown,本地存储,BYOK`

提交前在 App Store Connect 中确认字符/字节限制；不同语言版本可分别优化关键词，避免重复 App 名称中的词。

## App Review 备注建议

> Familiar is a BYOK AI chat app and does not provide a Familiar account or backend. A supported provider API key or connected external provider sign-in is required to test model responses. API keys are stored in iOS Keychain, and requests go directly from the device to the selected provider.
>
> Camera, microphone, speech recognition, calendar, reminders, contacts, location, and Photos add-only permissions are requested only when the reviewer actively invokes the related feature. External creates and updates require valid scope-specific authorization, with a preview on first approval. Deletions require confirmation every time and cannot create a reusable grant.
>
> Familiar includes a headless iSH/Alpine runtime for user-approved local computation. Checked, checkpointed offline commands can execute automatically with real receipts and supported session Undo; other commands retain their policy and approval requirements. A scoped terminal is available in the app. The guest sees only task-scoped read-only inputs plus the current Workspace Outputs and temporary Work directory. It has no Photos, Contacts, Calendar, Location, Keychain, other-Workspace, or host-environment bridge. Network is disabled per Workspace by default; if the user enables it, the runtime still blocks listening sockets, loopback, local/private/link-local/multicast destinations and enforces connection and byte limits. The corresponding GPLv3 source and build scripts are available at https://github.com/IsaacHuo/Familiar.
>
> Please use the review API credential supplied in the secure App Review Information field. Do not place API credentials in public notes or screenshots.

需要为审核准备一个受限、可撤销、额度有限的测试 API Key，并仅通过 App Store Connect 的安全审核字段提供。

## 2026-10-28 审核修复与回复

对应 Submission ID `afb1bb35-e0c3-4078-9929-795e6a7d7a3b`、1.0 (2)。保留 HealthKit 与 WeatherKit。下面的回复描述修复内容；提交前必须完成新构建的真机验证并附上真实录屏，不能把编译当作设备测试完成。新构建使用高于 2 的可用 build number，App 与扩展保持一致；本次代码修复未修改版本或签名。

### 英文回复草稿

> Thank you for the detailed review feedback and crash reports.
>
> **Guideline 2.1(a)**
>
> We symbolicated all three reports using the matching release dSYM. They identify the same crash in the native chat input's layout when opening a conversation. We replaced the UIKit text-view factory path with explicit TextKit 1 construction through our Swift subclass's designated initializer, and added layout reentrancy and selection-range checks. The corresponding native message text-view creation path has also been updated.
>
> **Guideline 2.1 — HealthKit**
>
> Familiar does use HealthKit. It is available as a native conversational tool, rather than a separate health dashboard. The submitted archive links HealthKit and includes the HealthKit entitlement.
>
> 1. Open Settings → Model Service and configure a supported model using the review credential provided in the secure review information.
> 2. Open Conversations and tap the new-conversation button (the paper-and-pencil icon).
> 3. Send: “Use Health Activity to read my step count, active energy, and walking or running distance for the last seven days.”
> 4. Review the in-app approval explaining the data scope and sharing with the selected model provider. Approve it, then allow the requested access in the system Health authorization sheet when prompted.
> 5. View the response and tap the tool activity row to inspect the returned activity totals. The tool is also listed under Settings → Tools → Native Tools; Settings → Permissions → Health Activity shows whether Health access has been requested.
>
> Familiar requests read-only access to step count, active energy burned, and walking/running distance. It does not write Health records. These aggregates may be sent to the user's selected model provider after the in-app approval. HealthKit does not disclose read denials; missing data is shown as unavailable, not as zero. On a device without Health data, the tool may return unavailable values.
>
> **Guideline 5.2.5 — WeatherKit**
>
> Familiar uses WeatherKit for current conditions, forecasts, and historical daily weather. We added a persistent native “ Weather” attribution and a tappable “Weather data sources and legal information” link using the legal URL returned by WeatherKit. These are shown with the chat response and weather result details, including saved conversations, independently of model-generated citations.
>
> To locate this feature, start a conversation and send: “Use Apple Weather to show the weather in Beijing and the forecast for the next three days.” View the attribution below the response, tap the weather tool activity to inspect its results, and tap the legal information link. This example uses a named city and does not require access to the device's location.

完成真机后再在回复末尾追加实际构建号、设备、OS、测试结果，以及上传录屏的文件名／位置；不要留下未填写的占位符，也不要在验证前加入 “tested successfully” 或 “crash resolved”。

### 真机验收与录屏

- 发布配置构建：在 iPad 上冷启动，反复点击纸笔按钮、聚焦空输入框、输入中文／英文／表情／多行、返回后再次新建；测试横竖屏。重点覆盖审核的 iPadOS 27.2，另做 iPhone 回归。
- 健康：展示模型已配置（遮挡凭据）、提问、应用内审批、首次系统授权及真实结果。无数据时记录 unavailable；不得伪造健康数据或把未授权状态称为已授权。
- 天气：真机发起上述北京查询，等真实 WeatherKit 返回，录制聊天中的  Weather、工具结果署名、可用时的完整记录页及法律链接打开。切换浅／深色并重开历史确认署名；本地测试桩或 Simulator 不能替代这份录屏。
- 将天气真机录屏作为审核附件上传，并在 App Review Information 的 Notes 中写明文件名及操作入口。以下备注随未来提交保留。

### 持续使用的 App Review Notes 补充

> HealthKit is a conversational feature. After configuring the supplied review model credential in Settings → Model Service, start a chat and ask: “Read my steps, active energy, and walking or running distance for the last seven days.” Approve the in-app data access request and the system Health sheet. Only these three activity aggregates are read; no Health data is written. See Settings → Tools → Native Tools and Settings → Permissions for discovery and access-request status.
>
> WeatherKit is used by asking: “Use Apple Weather to show the weather in Beijing and the forecast for the next three days.” The chat response and weather result details show  Weather and a legal source link. Please see the attached physical-device weather demonstration recording identified in these review notes.

最后一句仅在已实际上传录屏并填写文件名后使用。审核凭据、设备验证和录屏由所有者提供；本文档更新不代表已向 App Store Connect 发送回复或重新提交。

## App Privacy 复核

不要仅因为数据保存在本机就笼统选择“完全不收集”。按 Apple 提交时的最新定义，逐项确认最终构建中的数据流：

- 消息、对话上下文与系统提示；
- 用户选择文件的提取文本；
- 相机或相册图片保存在App私有附件目录；当前模型支持图片时发送给对应Provider，文本模型使用Apple Vision本地证据。用户可批准把指定 Workspace 图片输出以 Photos add-only 方式保存到图库；
- 语音输入及 Apple Speech 处理；
- 用户主动调用工具后的日历或提醒事项数据；
- 用户明确导入并投影到 task-scoped iSH Workspace 的文件，以及 Shell command、stdout/stderr、diff 与用户开启网络后的公共网络请求；
- 诊断数据（仅当最终构建实际加入崩溃或分析服务时）；
- 数据是否仅在设备处理，或会发送给所选第三方 Provider/自定义 endpoint；
- 数据用途是否仅为 App 功能；
- 数据是否与用户身份关联，以及第三方 Provider 是否可能通过其账户关联；
- Tracking 应按 Apple 定义确认。当前网站和已核对 App 代码没有广告或跨 App 跟踪 SDK。

隐私营养标签必须与最终二进制、权限说明、App 内披露和 `privacy/` 页面保持一致。自定义 endpoint 的存在也应纳入风险说明。

## 年龄分级与内容权利

- 根据最终模型能力和可能生成的内容，如实完成 Apple 年龄分级问卷，不要直接照搬固定答案。
- 确认 App 图标、第三方开源资源和商店截图具有分发权。
- 商店截图中不得显示真实 API Key、个人聊天、日历、提醒事项或其他敏感数据。

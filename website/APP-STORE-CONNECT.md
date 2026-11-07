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
> Camera, calendar, reminders, contacts, location, and Photos add-only permissions are requested only when the reviewer actively invokes the related feature. External creates and updates require valid scope-specific authorization, with a preview on first approval. Deletions require confirmation every time and cannot create a reusable grant.
>
> Familiar includes a headless iSH/Alpine runtime for user-approved local computation. Checked, checkpointed offline commands can execute automatically with real receipts and supported session Undo; other commands retain their policy and approval requirements. A scoped terminal is available in the app. The guest sees only task-scoped read-only inputs plus the current Workspace Outputs and temporary Work directory. It has no Photos, Contacts, Calendar, Location, Keychain, other-Workspace, or host-environment bridge. Network is disabled per Workspace by default; if the user enables it, the runtime still blocks listening sockets, loopback, local/private/link-local/multicast destinations and enforces connection and byte limits. The corresponding GPLv3 source and build scripts are available at https://github.com/IsaacHuo/Familiar.
>
> Please use the review API credential supplied in the secure App Review Information field. Do not place API credentials in public notes or screenshots.

需要为审核准备一个受限、可撤销、额度有限的测试 API Key，并仅通过 App Store Connect 的安全审核字段提供。

## 2026-11-07 审核收敛与回复

对应 2026-11-06 审核、Submission ID `afb1bb35-e0c3-4078-9929-795e6a7d7a3b`、1.0 (3)。麦克风输入、HealthKit 与 WeatherKit 暂时注释停用；原实现仍在仓库，但不进入新构建。提交前完成发布包核查和真机验收，上传高于 3 的可用构建号，App 与扩展保持一致；本次未修改版本或签名配置。

### 英文回复草稿

以下草稿仅供新构建和声明核对完成后使用，不代表已经发送。

> Thank you for the review feedback.
>
> **Guideline 2.1(a) — Microphone**
>
> We have disabled voice input in this submission. The microphone button, recording and speech-recognition implementation, related settings, and microphone and speech-recognition usage-description keys are excluded from the new build. Text and attachment input remain available. Reply read-aloud remains available and does not record audio.
>
> **Guideline 2.1(a) — Weather**
>
> Weather functionality is not included in this submission. The native forecast and historical-weather tools, WeatherKit integration, related presentation, and WeatherKit entitlement are excluded from the new build.
>
> **Guideline 2.5.1 — HealthKit**
>
> The new build excludes HealthKit functionality and API calls, the HealthKit entitlement, Health usage-description keys in Info.plist and all localized InfoPlist.strings, and related tool and settings entries. The related privacy disclosures and metadata have been updated to match the submitted functionality.

### 提交前由所有者完成

- 使用拟提交发布构建在审核所用 iPadOS 27.2 与 iPhone 上检查冷启动、新建会话、键盘、旋转、文字／附件发送、生成停止及回复朗读。
- 确认空草稿无麦克风按钮，设置无语音输入／健康入口，工具列表无健康和天气工具；拒绝其他系统权限不影响文字聊天。
- 核查实际归档签名 entitlement、Info.plist、本地化权限及二进制链接，不包含停用功能。编译不替代发布归档核查或设备测试。
- 更新 App Store Connect 隐私答案及旧截图，发布对应隐私政策文案；按真实数据流逐项核对，不能宣称完全不收集数据。
- 完成后在回复中添加真实构建号、设备／系统、结果和录屏附件文件名。验证前不写 “tested successfully” 或 “crash resolved”。

审核凭据仅通过安全字段提供。文案更新不代表网站已部署、审核回复已发送或新版本已提交。

## App Privacy 复核

不要仅因为数据保存在本机就笼统选择“完全不收集”。按 Apple 提交时的最新定义，逐项确认最终构建中的数据流：

- 消息、对话上下文与系统提示；
- 用户选择文件的提取文本；
- 相机或相册图片保存在App私有附件目录；当前模型支持图片时发送给对应Provider，文本模型使用Apple Vision本地证据。用户可批准把指定 Workspace 图片输出以 Photos add-only 方式保存到图库；
- 回复朗读：系统语音合成，或用户选择远程朗读后将回复文字发送给所选服务商；
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

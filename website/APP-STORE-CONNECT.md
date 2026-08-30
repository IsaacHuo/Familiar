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
- **副标题**：`安静、原生的 AI 助手`
- **主要分类**：效率
- **次要分类**：工具
- **最低系统版本**：iOS 18.0
- **Bundle ID**：`com.isaachuo.familiar`
- **版本**：`1.0`
- **版权**：发布前填写真实的个人或法律主体名称，不要使用占位符提交。

## 推广文本建议

> 使用你自己的 API Key，直接从 iPhone 连接模型服务。会话历史保存在本机，Markdown、代码、Mermaid 与公式在设备上清晰呈现。

## 描述建议

> Familiar 是一个安静、原生、始终在你手边的 iOS AI 助手。
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

> Familiar is a BYOK AI chat app and does not provide a Familiar account or backend. A valid API key for a supported model provider is required to test model responses. API keys are stored in iOS Keychain, and requests go directly from the device to the selected provider.
>
> Camera, microphone, speech recognition, calendar, reminders, contacts, location, and Photos add-only permissions are requested only when the reviewer actively invokes the related feature. Calendar or reminder creates, updates, completion changes, and deletions always show an exact preview before system access and require confirmation. Deletions cannot be remembered as a session or always authorization.
>
> Familiar includes a headless iSH/Alpine runtime for user-approved local computation. Shell is not a terminal exposed outside the Agent flow: every command is shown in Chat and requires one-shot approval. The guest sees only task-scoped read-only inputs plus the current Workspace Outputs and temporary Work directory. It has no Photos, Contacts, Calendar, Location, Keychain, other-Workspace, or host-environment bridge. Network is disabled per Workspace by default; if the user enables it, the runtime still blocks listening sockets, loopback, local/private/link-local/multicast destinations and enforces connection and byte limits. The corresponding GPLv3 source and build scripts are available at https://github.com/IsaacHuo/Familiar.
>
> Please use the review API credential supplied in the secure App Review Information field. Do not place API credentials in public notes or screenshots.

需要为审核准备一个受限、可撤销、额度有限的测试 API Key，并仅通过 App Store Connect 的安全审核字段提供。

## App Privacy 复核

不要仅因为数据保存在本机就笼统选择“完全不收集”。按 Apple 提交时的最新定义，逐项确认最终构建中的数据流：

- 消息、对话上下文与系统提示；
- 用户选择文件的提取文本；
- 相机或相册图片保存在 App 私有附件目录并由 Apple Vision 在本机生成有限证据；原始图片不发送给 DeepSeek。用户可批准把指定 Workspace 图片输出以 Photos add-only 方式保存到图库；
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

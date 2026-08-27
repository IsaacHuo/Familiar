# Familiar 本地数据与隐私

> 本文描述**数据与隐私设计约束**（产品承诺与安全边界）。当前 SwiftData schema、store 地址与存储布局见 `state/ARCHITECTURE.md`。

## 1. 数据处理原则

- API Key 保存到设备 Keychain。
- 模型请求从 iPhone 直接发送到用户选择的 Provider。
- 会话和工具记录保存在 SwiftData 本地 store。
- Agent Run 与 Step 终态保存在 SwiftData。
- 文档原文件复制到 App 私有目录。
- 文档转换和 PDF OCR 在设备内执行。
- 流式 token 和等待用户决策的 continuation 只存在于内存；工具 invocation 的 requested / approved / terminal 检查点保存在 SwiftData。
- 图片原文件保存在 App 私有附件目录，不写入 SwiftData；图片字节只进入当前选中的 DeepSeek 实验视觉模型请求或设备端 Apple Vision 处理。
- Apple Vision 结果以有限证据文本和 provenance 持久化。
- App 不创建原始录音文件。
- App 不读取学术系统或其他 App 的私有数据。
- App 不使用 Familiar 账户、业务后端或云端数据库。
- Deep Link 只接受有长度上限的草稿文本或本地会话 / Run UUID；它不自动发送内容、不承载 API Key，也不授予工具写权限。
- Share Extension 只把用户明确共享的文本、URL 和文件复制到 App Group 收件箱；扩展不读取 Keychain、会话、Provider 配置或 EventKit 数据。
- Ask / Process App Intents 只把用户明确提供且经过长度限制的文本交给主 App；文本随后沿用普通消息的 BYOK 请求路径。Open Familiar 不创建草稿、不发送网络请求，所有 Intent 均不能授予工具写权限。
- Run 终态通知是用户可选的本地通知，不使用远程推送；通知只包含通用状态与本地 Run / 会话标识，不包含问题、回答、附件名或工具结果。
- Spotlight 使用受保护的设备内索引，只保存已有内容会话的标题、更新时间和本地 UUID；不索引消息正文、附件名、工具结果、密钥或 Provider 配置。
- Skill 只有在用户从 Composer 为下一次 Run 显式选择时才进入上下文；它只能收窄工具范围，不能创建授权或绕过确认。

## 2. 数据清单

| 数据 | 来源 | 本地位置 | 网络目的地 | 生命周期 |
|---|---|---|---|---|
| Provider API Key | 用户输入 | Keychain | 对应 Provider | 用户清除或卸载相关 Keychain 项目 |
| Provider 配置 | 用户输入 | UserDefaults | 用于构建请求 | 用户修改或重置设置 |
| Search Provider API Key | 用户输入 | 独立 Keychain service | 对应 Search Provider | 用户在搜索设置中清除 |
| Search Provider 选择 | 用户输入 | 独立 UserDefaults key | 用于路由 `web_search` | 用户修改设置 |
| 会话 | 用户行为 | SwiftData | 作为模型上下文 | 用户删除会话 |
| 用户消息 | 用户输入 | SwiftData | 对应 Provider | 用户删除或编辑路径 |
| 助手消息 | Provider 返回 | SwiftData | 后续请求上下文 | 用户删除或重试路径 |
| 模型切换记录 | 用户操作 | SwiftData | 不单独发送 | 会话删除或路径重写 |
| 工具终态 | Agent 与系统结果 | SwiftData | 可能进入后续模型上下文 | 会话删除或路径重写 |
| Run/Step 记录 | Agent Runtime | SwiftData | 不单独发送 | 会话删除或路径重写 |
| Project / Resource / Artifact | 用户导入或 Agent 生成 | SwiftData + 独立受保护目录 | 抽取文本进入上下文 | 项目删除或用户删除 |
| Skill / Run Skill 快照 | App 首次示例或用户在 App 内创建，并由用户显式选择 | SwiftData | 被选择的 Skill 指令进入对应 Provider 的下一次 Run | Skill 由用户删除；Run 快照沿用 Run 生命周期 |
| 待确认请求 | Agent | continuation 在内存；invocation requested 状态在 SwiftData | 不发送到 Familiar 服务 | 决策、取消或进程结束；检查点沿用 Run 生命周期 |
| 流式 token | Provider | 内存 | 不作二次上传 | 回答终态或任务结束 |
| 文档原文件 | 文件选择器 | App Support | 不上传 | 附件、消息或会话删除 |
| 文档抽取文本 | AnyDoc/OCR | SwiftData | 对应 Provider | 附件、消息或会话删除 |
| 图片数据 | 相机或相册 | App 私有草稿/消息附件目录；SwiftData 只保存引用和元数据 | 当前选中的 DeepSeek 实验视觉模型，或设备端 Apple Vision | 随草稿、消息、附件或会话删除 |
| 视觉证据 | Apple Vision | SwiftData；引用 App 私有图片附件 | 作为只读上下文进入当前文本模型 | 随消息/附件删除 |
| 语音转写 | Apple Speech | 输入草稿 | 发送后进入 Provider | 用户编辑或清空草稿 |
| 原始录音 | 麦克风输入 | 不落盘 | Speech framework 按系统能力处理 | audio buffer 生命周期 |
| 日历/提醒数据 | EventKit | 查询结果进入内存和工具记录摘要 | 可能作为工具结果进入 Provider | 运行结束和历史记录生命周期 |
| 网页搜索 | 用户问题经 Agent 生成的最小搜索词 | 结果正文主要在运行内存；来源标题、HTTPS URL、站点、时间和有限 snippet 随助手消息保存 | 搜索词直接发送给所选 DuckDuckGo、Brave、Tavily 或 Exa；结果可能作为工具内容进入所选模型 Provider | 临时结果随 Run 结束；来源与 snippet 随消息删除 |
| 网页读取 | 用户提供或搜索返回的公开 HTTPS URL | 原始 HTML 与完整正文默认仅在运行内存；来源元数据和最多 360 字符的有限正文 snippet 随助手消息保存；用户导入项目时抽取正文保存为 Project Resource | 请求直接发送给目标站点及允许的 HTTPS 重定向目标；抽取正文可能进入所选 Provider | 临时原始内容随 Run 结束；来源与 snippet 随消息删除；导入副本沿用 Resource 生命周期 |
| Deep Link 输入 | 其他 App 或系统入口 | 草稿文本进入内存；会话 / Run UUID 仅用于本地查询 | 不因打开链接自动发送 | 链接处理或草稿生命周期 |
| Share Extension 输入 | 用户从其他 App 明确共享 | App Group `ShareInbox`，导入后复制到 App 私有草稿附件目录 | 不因共享或导入自动发送 | 成功或终态失败处理后删除共享副本；草稿副本沿用附件生命周期 |
| App Intent 文本 | 用户在 Siri / Shortcuts / Spotlight 明确提供 | 仅作为进程内 handoff 和新草稿短暂存在，发送后进入本地消息记录 | Ask / Process 通过当前选择的 BYOK Provider 发送；Open 不发送 | 未发送草稿被拒绝覆盖；成功提交后沿用会话生命周期 |
| 本地通知状态 | Agent Run 终态 | iOS 通知中心保存通用文案和本地 Run / 会话 UUID；开关保存在 UserDefaults | 无 Familiar 服务或远程推送目的地 | 用户关闭功能时清理 Familiar 待处理与已投递通知；系统也可按自身策略清理 |
| Spotlight 会话索引 | 本地 SwiftData 会话 | Core Spotlight `.complete` 保护索引；最多 80 字符标题、更新时间和会话 UUID | 无 Familiar 服务或公开 Web 索引目的地 | 随当前会话集合重建；重命名更新，删除会话后清理对应结果 |

## 3. SwiftData 与 store 策略

当前使用 `FamiliarDevelopment.store` 中的单一 27 实体 SwiftData Schema，生产和测试容器都不配置 migration plan。完整实体模型与 store 地址见 `state/ARCHITECTURE.md` 第 5 节。数据模型设计约束：

- 关系删除规则使用 cascade；附件 / 项目资源 / Artifact 文件由控制器显式清理。
- Project 名称在本地 store 中全局唯一，比较时不区分大小写。
- Project Resource 必须独立于 Message 文件目录，具备稳定 ID、版本、来源和 lineage；删除或编辑消息不能误删项目共享资料。
- 每次 Run 保存不可变 ContextSnapshot 及其资源引用，不保存完整资源抽取文本进快照记录。
- 当前开发策略：Schema 变化可轮换到全新开发 store，不迁移测试数据；首次创建当前 store 时清理旧开发 store 及失去元数据的附件、项目资源和 Artifact 目录。
- 正式发布后的目标策略：冻结公开 Schema 后再建立版本化 migration plan、migration stage 与磁盘迁移测试，不把当前开发期的破坏性轮换当作用户数据升级方案。
- 容器打开失败不自动重置数据；只有用户在恢复界面确认后才删除当前 store、附件、项目资源和 Artifact，Keychain API Key 保留。（历史启动崩溃及当时迁移链方案见 `logs/swiftdata-store-migration-134110.md`。）

## 4. 持久化时点

### 4.1 用户消息

用户消息和已提交附件在网络请求前保存。请求失败后，用户输入仍保留在会话中。

### 4.2 助手消息

流式期间更新内存中的 `streamingText`。Provider 和 Agent Loop 进入终态后创建助手消息并保存。

### 4.3 工具记录

工具 invocation 请求时保存 requested 检查点，用户决策后保存 approved / cancelled，执行完成后保存 committed / failed；工具终态同时保存工具名、用户可见摘要、详情、确认结果、开始和结束时间。等待用户决策的 continuation 不持久化。

### 4.4 模型切换

会话内切换 Provider 或模型时保存切换记录，并更新会话当前选择。

### 4.5 Run 与 Step

一次 Agent Run 创建时保存 Run；ContextSnapshot、CapabilitySnapshot、ResumeCursor、ToolInvocation、审批、工具终态和模型响应摘要作为检查点保存。流式增量和字节级中断续跑尚未持久化；完整 Authorization snapshot 与严格恢复仍是目标（见 `02-system-architecture.md` 3.1）。

## 5. 文件系统

附件根目录：

```text
Application Support/Familiar/Attachments/
```

子目录：

```text
Drafts/
Messages/<message UUID>/
```

Project 资源、Artifact 使用独立的受保护目录（具体路径见 `state/ARCHITECTURE.md`）。

### 5.1 路径安全

`FamiliarAttachmentStore` 执行：

- 文件名清洗。
- 拒绝绝对路径、空路径段和 `..`。
- 规范化 URL 必须位于附件根目录内。
- 源文件和复制文件大小校验。
- 单文件上限 25 MiB。

### 5.2 安全作用域

文件导入期间调用 `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`。安全作用域只覆盖复制过程；后续预览使用 App 私有副本。

### 5.3 清理

设计要求：导入失败、转换失败、导入取消、多附件提交中途失败、删除会话、编辑或重试删除后续消息、丢弃草稿时均清理对应文件；页面出现时清理未被引用的 Drafts 与 Messages 孤儿文件；删除项目时清理对应 Project Resource 与 Artifact；开发 store 轮换或用户确认恢复时清理附件、项目资源和 Artifact。附件目录创建时设置 `.completeUntilFirstUserAuthentication` 文件保护。

## 6. Keychain

```text
kSecClassGenericPassword
kSecAttrService = com.isaachuo.familiar.provider-api-keys.v2
kSecAttrAccount = providerID
kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

影响：

- 设备解锁后可访问。
- 不通过 Keychain 同步迁移到其他设备。
- 每个 Provider 使用独立 account。
- 空 Key 输入触发删除。

API Key 不进入 SwiftData、UserDefaults、日志文案和工具记录。

Search Provider Key 使用独立 service `com.isaachuo.familiar.search-provider-api-keys.v1`，account 为 Search Provider ID；搜索服务选择使用独立 UserDefaults key `familiar.search.provider.v1`。搜索 Key 不与模型 Provider Key 共用。DuckDuckGo 不需要 Key；选择 Brave、Tavily 或 Exa 后缺少 Key 会明确失败，不会回退到其他搜索服务。

## 7. Provider 网络数据

发送内容可能包括：

- 系统提示词。
- 当前会话文本消息。
- 文档抽取文本。
- 工具定义。
- 工具查询结果。
- 用户确认后的工具执行结果。

网络目的地由 Provider descriptor 和用户配置决定。用户配置自定义 Base URL 时，数据会发送到该 URL 所属服务；设置界面和隐私文档需要提示该影响。

## 8. WebKit 数据

`FamiliarMarkdownWebView` 使用 `.nonPersistent()` website data store。脚本和样式来自 App Bundle。

CSP 主要限制：

- `connect-src 'none'`
- `media-src 'none'`
- `object-src 'none'`
- `frame-src 'none'`
- `form-action 'none'`

`img-src` 仅允许 Bundle 同源资源与 `data:`，不允许 HTTP 或 HTTPS 图片。渲染器先在 inert template 中清理 Markdown HTML，把 HTTPS 图片替换为带有替代文本和主机名的来源链接，再插入 WebView 文档。渲染过程不会向图片主机暴露 IP、User-Agent 或访问时间。只有用户主动点击来源链接后，系统才会在外部打开该地址。

## 9. EventKit 数据

### 9.1 读取

查询参数限定时间范围、文字条件和结果上限。工具结果可能进入 Provider 上下文，用于生成回答。

### 9.2 写入

创建操作包含以下阶段：

1. 生成待确认计划。
2. Execution Policy 查找 Project、工具、目标和参数范围均匹配的有效 grant。
3. 无有效 grant 时展示结构化动作卡，由用户选择仅这次、本次会话或始终允许；默认本次会话。
4. 有效授权产生后调用 EventKit save，并保存执行与撤销所需记录。

动作卡展示目标容器和字段。取消结果进入 Agent Loop，取消路径不调用 save。有效 grant 可以免除重复询问，但不能隐藏动作卡，也不能越过 Project、工具、目标或参数边界。修改、删除和目标变化必须重新判断授权；EventKit create 已保存跨重启 Undo 记录，真机边界仍待验证（见 `state/CURRENT.md`）。

### 9.3 权限

使用 EventKit full access API（iOS 17 引入）：

- `requestFullAccessToEvents()`
- `requestFullAccessToReminders()`

用途说明：`NSCalendarsFullAccessUsageDescription`、`NSRemindersFullAccessUsageDescription`。

## 10. 相机、照片和语音

### 相机

- 用户进入相机界面时请求权限。
- 照片进入内存草稿。

### 照片

- 使用 `PhotosPicker`，不请求完整照片库权限。
- 用户选定的图片复制到 App 私有草稿目录；选中实验视觉模型时图片字节进入当前 DeepSeek 请求，否则只由 Apple Vision 在设备端处理。
- 当前文本模型不支持图片时，原始字节不发送到模型；FastVLM 当前不参与处理。

### 语音

- 请求麦克风和 Speech 权限。
- 可用时优先设备端识别。
- 转写结果进入文本输入框；不保留音频文件。
- 系统不支持设备端识别时，Speech framework 的处理路径由 Apple 系统能力决定。

## 11. 权限表

权限由代码控制，不靠 Prompt。系统权限按功能触发；写入由精确授权和结构化动作卡控制：

| 操作 | 默认行为 |
|---|---|
| Read + 低风险 | 自动执行 |
| 可逆写入 | 首次结构化授权；有效 grant 范围内免重复确认但仍展示动作卡；EventKit create 保存跨重启 Undo 记录 |
| 推断出的写入 | 无匹配 grant 时结构化授权 |
| Web 敏感读取 | 受限公网请求自动执行；不授予后续工具权限 |
| EventKit 可申请读取 | 结构化确认后请求系统权限 |
| 破坏性操作 | 确认 |
| 财务 / 外部重大影响 | 强确认 |

| 权限 | 触发功能 | 数据用途 |
|---|---|---|
| Camera | 拍照 | 创建图片草稿 |
| Microphone | 语音输入 | 提供实时音频 buffer 给 Speech |
| Speech Recognition | 语音输入 | 生成可编辑文本 |
| Calendars Full Access | 日历工具 | 查询和确认后创建事件 |
| Reminders Full Access | 提醒工具 | 查询和确认后创建提醒 |
| PhotosPicker | 相册 | 读取用户选定图片 |
| Security-scoped file URL | 文件 | 复制用户选定文档 |

## 12. 威胁与控制

| 风险 | 控制 |
|---|---|
| API Key 泄露到普通存储 | Keychain，ThisDeviceOnly |
| 自定义服务地址收集内容 | 用户显式配置，设置中展示 Base URL |
| 模型执行未授权写入 | 精确 grant 匹配、动作卡、协调 actor、EventKit commit 分层；模型不能创建自己的授权 |
| 重复工具调用 | run 内重复检测、授权消费、持久化 invocation 与 commit 幂等 |
| 路径穿越 | 相对路径校验和根目录约束 |
| 大文件耗尽上下文 | 25 MiB 文件限制和模型字符上限 |
| 图片意外上传 | 模型能力路由、adapter gate；本地 fallback 不产生新网络目的地 |
| 本地视觉输出被当作指令 | VisualEvidence 标记为不可信只读输入，不授予工具权限 |
| 模型文件损坏或供应链变化 | 固定版本、URL、大小和 SHA-256；校验失败删除损坏文件 |
| Web 内容执行网络脚本 | Bundle 资源、CSP、non-persistent store |
| Web SSRF、DNS rebinding 与危险重定向 | 仅公共 HTTPS、DNS 公网校验、固定解析结果、逐跳重验和端口限制 |
| Web 响应炸弹或恶意类型 | 响应字节、内容类型、超时和重定向次数上限 |
| 远程 prompt injection | Web 内容标记为不可信，不授予工具权限；来源单独保存 |
| 未来 MCP server annotation 伪造风险 | annotation 不作为授权依据，凭据按 server identity 隔离并继续通过 Familiar Policy |
| 流式 token 触发广泛持久化 | 内存状态和终态保存分离 |
| 旧 Schema 启动崩溃 | 当前开发期使用独立 `FamiliarDevelopment.store` 与破坏性 store 轮换，不迁移测试数据；历史方案见 `logs/swiftdata-store-migration-134110.md` |

## 13. 删除语义

### 删除消息路径

编辑和重试会删除目标之后的：消息、模型切换记录、工具记录、对应附件文件。删除消息不删除项目共享 Resource。

### 删除会话

删除会话时：清理消息附件文件、删除会话实体、cascade 删除关联实体。

### 删除项目

删除项目时：清理 Project Resource 与 Artifact 文件、删除项目实体、历史会话与 Run 脱离项目归属；运行中 Run 时禁止删除。

### 卸载 App

App 容器中的 SwiftData、UserDefaults、附件、项目资源和 Artifact 文件由系统删除。`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain 项目的卸载行为由系统管理；产品需要提供设置内清除 Key 的操作。

## 14. 后台与通知

### 后台

后台执行不改变数据目的地：模型请求仍直接发往用户选择的 Provider。当前没有后台 Run 保证；本地通知只报告当前进程实际到达的完成或失败终态，不应被描述为后台任务保证（版本约束见 `logs/bgcontinuedprocessingtask-is-ios26.md`）。

### 本地通知

- 权限只在用户于设置中开启"Run 结束时通知我"时请求。
- 系统拒绝权限后，本地偏好保持关闭，并提供前往 iOS 设置的恢复入口。
- 通知内容使用固定的双语完成或失败文案，不从会话、消息、附件或工具记录生成预览。
- payload 只携带 `run:<UUID>` 或 `conversation:<UUID>`，点击后在本地解析；不携带 API Key、Provider 配置或工具授权。
- Familiar 不注册远程通知、不上传 device token，也不通过自有服务器发送通知。
- 用户关闭功能时清理 Familiar 的待处理与已投递通知。

### Spotlight 会话索引

- 只索引已经产生消息或 Run 的会话，空白会话不进入系统搜索。
- 每项只包含最多 80 字符的会话标题、更新时间、Familiar 标识和本地会话 UUID。
- 索引使用独立的 Core Spotlight 自定义索引，并指定 `.complete` 文件保护等级。
- 不写入消息正文、文档抽取文本、附件名、工具结果、Run 详情、API Key 或 Provider 配置。
- 点击结果只把 UUID 交给现有本地 Deep Link 路由；SwiftData 会话不存在时不恢复或重新创建内容。
- 当前会话集合变化时整域刷新；索引失败不影响本地会话操作。

## 15. 隐私验收

- 抓包确认 Provider 请求目的地。
- 检查请求体不含原文件 bytes 与未授权数据。
- 检查日志不含 API Key。
- 检查流式 token 未写入 SwiftData。
- 检查等待确认 continuation 未写入 SwiftData，且 invocation requested 检查点已写入。
- 拒绝 EventKit 权限时零读取和零写入。
- 取消写入确认时零写入。
- 授权范围越界、目标变化或 grant 过期时零写入并重新询问。
- 验证图片在纯文本模型路径中只由 Apple Vision 处理，未经选择不发送到实验视觉模型。
- 验证视觉证据记录包含方法、版本和原图引用，且不能产生工具授权。
- 验证设置和 Chat 中没有 FastVLM 用户入口或自动路由。
- 删除会话后附件目录无对应文件。
- 停止语音后无录音文件。
- 验证 Markdown CSP 不允许 HTTP/HTTPS 图片，且远程图片只呈现为用户主动打开的来源链接。
- 验证通知只在用户明确开启后安排，锁屏文案不包含会话内容，关闭后清理待处理与已投递通知。
- 验证 Spotlight 项不含聊天正文或附件信息，点击能回到本地会话，重命名与删除后结果同步更新。
- 验证 Web 私网与保留地址被拒绝、重定向逐跳重验、大小和类型上限生效、正文不持久化且恶意网页指令不能授权工具。

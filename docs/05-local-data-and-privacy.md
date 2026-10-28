# 本地数据、授权与隐私

这是稳定产品约束；代码布局见[state架构](../state/ARCHITECTURE.md)，验收见[统一清单](11-verification-and-release-checklist.md)。本轮UI对齐不改变网络目的地、授权、schema或删除事务。

## 数据与目的地

| 数据 | 存储／处理 | 网络边界 |
|---|---|---|
| Provider API Key、外部登录凭据、搜索Key | 设备Keychain，按服务身份隔离 | 仅发往所选服务，不进入日志、SwiftData或普通偏好 |
| 会话、Run、工具回执、授权、文件元数据 | 本机SwiftData | 仅当前请求经Context Compiler选择的内容进入Provider |
| 文档和附件字节 | 受保护App私有目录 | 文档在设备提取文字，原始Office/PDF不发给文本模型 |
| 图片 | 托管附件；当前模型原生处理或Apple Vision | 仅支持图片的当前Provider接收所选图片；文本模型接收有限视觉证据，不自动切Provider |
| 语音 | 实时buffer生成可编辑文本，不持久保存原录音 | 系统Speech由Apple决定处理路径；用户配置的远程服务按该配置处理 |
| 网页 | 受限HTTP读取，作为不可信Evidence | 公开HTTPS，逐跳DNS和URL复核；显式保存才进入长期Files |
| Markdown页面 | Bundle脚本／字体／样式；非持久WKWebView | connect/media/object/frame/form受CSP限制；不自动加载远程图片 |
| 本机资料 | UserDefaults编码昵称／简介／降采样头像 | 不作为账户或授权身份，不进入模型上下文 |

无Familiar账户、业务后端、数据库托管、云同步、远程推送或跨App私有数据读取。网站没有分析、广告脚本、Cookie或外部字体。API Key和隐私正文不进入诊断记录。

## 持久化与恢复

用户消息及托管附件在提交时保存；流式增量保持内存态，在明确检查点和终态保存。工具requested、approved/cancelled、committed/failed分别落盘，等待审批的continuation不持久化。Run保留上下文引用/hash/provenance和审计事实，不重复存每次完整文件正文。

仅一个当前schema。既有5-work-scopes业务代际完成标记只在创建新store成功后写入；该次授权重置保留Keychain、模型／搜索配置及外观。之后打开失败保留业务数据进入恢复，不能再次自动清空。Debug与Release store不搬迁或混用。中断Run如实终结，不自动续跑或重放不确定写入。

## Scope与删除

Project与Conversation的scopeKey包含类型，UUID相同也隔离。普通Chat的Files、Workspace、Environment、Memory属于该Chat；只有显式global Memory跨普通聊天。

- 删除普通Chat清其独有文件、附件、Workspace、环境、会话Memory和授权。
- 删除项目Chat保留项目共享Files；清理不能误删其他聊天引用的字节。
- 移动Chat先复制关联FileVersion并重绑附件，再清摘要和旧范围授权／环境。
- 删除Project先为保留Chat转存关联版本，再转普通Chat并清项目专属数据。
- 编辑先建草稿；取消／失败不删旧历史。新完整回复成功保存才同事务替换旧尾部；真实外部影响与回执不会因改历史而消失。
- 导入取消／失败只清本次拥有的未交付字节；孤儿清理计入全部草稿、编辑备份和已保存引用。
- 卸载删除App容器；Keychain卸载行为由系统管理，设置内提供显式清凭据操作。

## 文件与Keychain保护

附件路径拒绝绝对路径、空段和..，规范化后必须在App根目录内；导入复制期间才持有security-scoped访问，后续读取私有副本。单文件限制25MiB；原文件和复制后均校验。文件使用completeUntilFirstUserAuthentication保护。

Provider Keychain使用generic password，service为com.isaachuo.familiar.provider-api-keys.v2，account为providerID，accessible为WhenUnlockedThisDeviceOnly。搜索和OAuth使用独立身份与服务；空Key输入按当前设置的删除语义处理。

File身份独立于路径／名称／hash；FileVersion不可变。分享与预览必须检查File、Version、Scope和真实URL，不以最新版本替代缺失历史版本。

## 权限与写授权

系统权限按功能触发。普通只读仍受系统许可、范围与可用性检查。模型、网页、系统入口、Memory和Skill不是授权来源。

- 可逆内置本地写、启用记忆写入、配置源声明式安装、预检且有checkpoint的离线Shell自动执行，留真实回执与会话Undo。
- 外部创建／更新、通知、剪贴板、保存相册、闹钟安排、Skill安装和已信任MCP首次询问，默认始终允许此类；匹配scopeKey+capabilityID+capabilityVersion，可撤销。
- 删除、闹钟取消与未信任MCP每次询问，不产生持续授权。服务器信任由用户设置，不采信远端破坏性提示来放松。
- EventKit保存前复核权限、目标和有效授权，写前journal，失败补偿；取消审批零写入。跨重启Undo只有真实记录可用时才展示。
- 开关关闭时不读取或自动写入Memory；Skill仅提供指令并收窄工具。

## Shell与网络

内置iSH仅挂载当前Run允许的只读输入及当前Workspace的Outputs／临时Work；照片、联系人、日历、位置、Keychain、其他Workspace、Metadata和Checkpoint不挂载。默认禁网；用户开启网络或声明式安装仍受publicInternet目标、连接／字节限额、禁止监听与私网地址等宿主策略限制。

Shell写前checkpoint；资源限额、全局串行、超时、进程树取消和失败恢复沿用原规则。配置源依赖由Swift构造命令，预装库不重复下载；环境已就绪不是新写操作。终端watchdog不含准备时间。

## Web与渲染

公开HTTPS和DNS校验防止私网、保留地址、危险重定向与rebinding；响应限制类型、字节、时间和跳转。Web/MCP内容为不可信输入，不能提升为指令或授权。

Markdown在inert template清理后入DOM。远程图片转换为含alt和host的主动打开链接，不自动请求图片主机；本地img仅Bundle同源和data。预览HTML继续使用受限CSP和准确URL，不复用登录会话。

## 系统入口与通知

Share Extension只复制用户明确分享的文本、URL和文件到App Group收件箱，不读Keychain／会话／EventKit。Deep Link仅接收有长度上限的草稿或本地UUID；App Intents将用户输入交给主App，不自动授权。

Run结束通知只在用户明确启用并获系统许可后安排，文案通用，不含问题、回答、附件名、结果或凭据；payload仅本地Run／Conversation路由。关闭时清理相关通知，无device token上传。

Spotlight只索引已有内容会话的受保护标题（最多80字符）、更新时间和UUID，不索引正文、附件、Run详情或配置；点击不存在的会话不重建内容。使用独立complete保护索引。

## 验收与披露

真实网络、权限拒绝、取消、重复写、中断、不确定副作用、磁盘故障、删除与跨范围操作独立验收。隐私标签以最终二进制、实际调用和App内／官网披露核对，不能用“保存在本机”概括全部数据流。FastVLM/MLX不进入当前iOS产品路径；不以研究模型许可证推断分发权。

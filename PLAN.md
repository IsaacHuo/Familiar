# Familiar 打磨计划

跨对话任务账本。只记录：分级功能清单、切片与验收脚本、当前切片。不复制 git 历史，不记录密钥。

## 原则

- 不新增功能，现有功能按优先级逐条打磨到底。
- 默认验收标准：相关测试真实执行通过 + 所有者视觉与真机签字。当前普通对话/项目与 S2a 切片按所有者明确要求仅构建，真机视觉由所有者负责；编译与未执行项目分别记录，不宣称运行通过。
- 对标：对话/流式/工具活动/审批学 ChatGPT 与 Claude iOS；设置学 iOS 系统设置。
- iSH 是 App 内的小主机，是复杂文档交付的核心链路。
- 基底模型 DeepSeek `deepseek-v4-flash`；其他 Provider 连通性后续再测。
- 最低系统 iOS 26，不保留旧系统回退。

## 功能优先级

| 级别 | 功能 |
|---|---|
| P0 | 联网搜索与 Key、授权分级、Chat 流式与呈现、iSH 文档交付 |
| P1 | 设置、Project、Files、Memory、模型/BYOK |
| P2 | 语音、图片与相机、文档导入、日历提醒、地点天气 |
| P3 | MCP、Skills、通知、闹钟、健康、照片、音乐、蓝牙、剪贴板、终端 UI |

## 切片

执行顺序：S1 → S2 → S4 → S3 → S5/S6 → S7/S8。S2 包含必要审批交互，S4 包含文件卡与 Files 接线。

状态：`[ ]` 未开始，`[~]` 进行中，`[x]` 实现完成（验收另列）。

### S0 基线 `[x]`

- [x] 所有 target 部署目标 26.0；删除 iOS 26 以下回退分支（保留 iOS 27 语音、26.1 AlarmKit 门控）。
- [x] 去掉 `UIScreen.main`；Camera、SpeechTranscriber 改 `@Observable`；清理 iOS 26 deprecation（MapKit placemark、Text 拼接、scene coordinateSpace、测试 UIWindow）。
- [x] 移除 SwiftStreamingMarkdown/Textual/swift-markdown 及渲染评估测试与脚本。结论：保留 WebKit 渲染器。
- [x] 文档重置。
- 证据：arm64 iPhone 17 Simulator `build-for-testing` 成功，无第一方 warning。相关单测执行因 Simulator 宿主卡死未完成（见 logs/simulator-test-host-hang.md），按所有者要求暂缓。

### S1 联网搜索与 Key `[~]`

- [x] Key：规范化、类型化读取、Keychain 恢复服务选择；切换前向原服务保存，保存失败保留草稿；校验绑定已保存 Key 与服务，编辑/切换/删除/离开使旧响应失效。
- [x] 质量：保留引擎排名；Tavily 宽松解码、真实错误、时效参数、实际 `max_results`；网络/5xx 可降级到 DDG 并说明，认证/额度/限流/解析错误不降级。
- [x] DDG/Bing：UA、语言和时效参数；DDG 使用全球区域，Bing 不由语言推断市场；总搜索预算 24 秒（既有工具上限 25 秒），首选有 Key 服务最多 12 秒，重试、形态切换与降级共享剩余时间。
- [x] web_fetch：gzip/deflate、meta charset、GBK/GB18030/Big5、代理 fake-IP 网段、保留 page-wide form 正文。
- [x] Run：失败不缓存、不计无进展；成功缓存隔离 Provider/语言/时效/数量；并发重定向复用同一捕获，保留已观测别名，最终回答及 Markdown blocks 统一引用并保存唯一来源。
- [x] 主动性与呈现：Web 首轮暴露且服从 Project/Skill；时效提示与原始来源读取；按来源选择检索语言，不因中文输入、时区或 Provider 地区添加国家限定；来源 Sheet 严格只列已引用来源，并与角标编号一致。
- [x] 新增定向回归、生产页面确定性 Web 场景和 20 条中英文真实服务用例；不在源码或结果中存储 Key。
- [x] 自动验证：79 项定向单测、真实 WebKit 双引用同编号回归、3 项生产 UI 用例通过；截图已生成并由代理核对。另修复历史触摸区遮挡设置入口。
- [ ] 真实模型与所有者验收：Tavily 中英文真实请求已通过；DeepSeek + Tavily 20 条查询因 Simulator 未读到 DeepSeek Key 未执行。截图所有者过目、真机签字仍待完成。见 docs/15-s1-search-acceptance.md，S1 保持进行中。

### 普通对话/项目分离、抽屉与 S2a `[~]`

- [x] 普通聊天 project=nil，取消固定日常项目；稳定草稿 ID，全局默认和会话隔离上下文。
- [x] FamiliarWorkScope 统一 Files/Workspace/Environment/授权；同 UUID 不同类型隔离。
- [x] 唯一当前 schema 5.0.0，移除迁移链及专用模型；代际标记触发一次性业务重置，保留凭据与配置；后续失败恢复页。
- [x] 普通删除清独有文件；移动复制/重绑文件并清摘要和旧范围授权；删除项目转存聊天文件后转普通。
- [x] 抽屉置顶/项目/日常对话，项目最近 5 条、普通最近 20 条、稳定排序和置顶去重、查看更多打开完整列表。
- [x] 顶栏唯一省略号，项目详情只在项目聊天显示；切换项目从侧栏进入。
- [x] S2a：clipboard_read 只读；environment_prepare 已就绪无变更结果；可撤销 file/workspace 与 checkpoint 保护的离线 Shell 自动执行，保留回执、Undo、journal、复核、补偿、防重放。
- [x] 构建：指定 arm64 iPhone 18 Pro 的 build-for-testing 成功，App 与两类测试目标编译通过，最终日志无 warning/error；静态检查和双语文案校验通过。
- [ ] 验收：按所有者最新要求不执行测试或截图。真机视觉由所有者验收；生命周期、重置与运行授权不得记作已运行通过。详见 docs/16-work-scope-convergence.md。
- 下一步：所有者真机检查普通/项目生命周期和视觉；S2b 已实现并通过指定 arm64 构建（能力级持续授权、Memory 自动写入、依赖安装自动边界、MCP 信任），真机行为验收另列，完整 S2 不标完成。

### S2 授权按后果分级 `[~]`

| 级别 | 规则 | 工具 |
|---|---|---|
| 1 只读 | 不出 App 卡片 | 搜索、抓取、日历/提醒/联系人/位置、健康/照片/蓝牙读取、文件与记忆读取 |
| 2 可撤销本地写入 | 不询问，事后回执 + 撤销 | file_write/edit/publish、workspace_write、memory_remember、沙箱内离线 shell_execute、从已配置软件源 environment_prepare |
| 3 影响 App 外部 | 首次询问，默认“始终允许此类” | 日历/提醒创建修改、通知、剪贴板写入、保存到相册、闹钟、skill_install、已信任 MCP |
| 4 不可逆/破坏性 | 每次询问 | 删除事件/提醒、取消闹钟、未信任 MCP、对外发送 |

- 后续第 3 级规则按完整工作 scope + 能力匹配，不要求参数 hash 一致；可在隐私与数据中撤销。
- 保留：模型不能自授权、执行前复核、写入 journal、防重放。
- 修 `clipboard_read` 与 `environment_prepare` 已就绪路径的 `invalidOutcome`；修正 ContextCompiler 中与策略矛盾的 Shell 提示。
- 表驱动测试锁定“工具 → 级别”。完成后更新 AGENTS.md 的授权规则。
- [x] S2b：`.always` 重定义为能力级匹配（scopeKey + capabilityID + capabilityVersion，忽略参数与目标）；第 3 级工具（EventKit 创建/更新、通知、剪贴板、相册、alarm_schedule、skill_install、已信任 MCP）申请 `[.once, .always]` 并在卡片默认“始终允许此类”；删除类、alarm_cancel、未信任 MCP 保持每次询问。
- [x] S2b：`memory_remember` 走第 2 级自动写入（开关开启时），回执可撤销，控制器按 provenance 删除对应行；契约文档同步更新。
- [x] S2b：`environment_prepare` 改为 `reversibleWrite`，来自配置软件源时自动执行；保留旧环境目录作为会话 Undo 目标，撤销回滚目录与 receipt 元数据。
- [x] S2b：MCP 信任为按服务器的用户设置（UserDefaults，默认未信任；设置页开关，删除服务器清除），已信任按第 3 级、未信任每次询问。
- [x] S2b 构建：arm64 iPhone 18 Pro Simulator `build-for-testing` 成功（exit 0，无源码 warning/error）；新增/更新能力级匹配、EventKit 级别、MCP 信任、Memory 二级写入等用例，全部只编译不执行。见 docs/17-s2b-authorization-design.md。
- [ ] S2b 验收：所有者真机行为验收（清单见 docs/17 §5）；完整 S2 不标完成。

### S3 Chat 呈现收敛 `[~]`

- [x] 工具结果只保留 4 种呈现：活动行（点开 Sheet 承载 receipt/records/shell/技术详情）、行内引用 + 来源 Sheet、统一文件卡（含 prepare_file_export）、输入区审批/澄清。Recommendation/Insight/TaskList/ShareDraft 呈现与 `task_plan`/`present_recommendation`/`present_insight`/`prepare_share` 工具整体移除（内容改由模型写 Markdown）；payload 收敛为 scalar/searchResults/document/recordCollection/mutationReceipt/fileMutation/shellExecution（schemaVersion 4）；死代码 diff/code/contextMatches 同步删除。
- [x] 侧边栏保留推开手势，内容改为原生 List：新对话、搜索、Pinned、Projects（可展开）、最近普通对话、底部设置；顶部标题保留，搜索改为行内入口。
- [x] 顶栏省略号精简（移除与设置重复的 Memory 入口，保留 New/项目详情/分支/移动/导出/压缩/清除/终端/Files/朗读/用量）；Composer 添加菜单改原生 Menu，删除 180ms sleep 与 popover 路径。
- [x] 拆分 FamiliarChatMessageViews.swift（2765 → 0）：Chat/Timeline、Chat/Row、Chat/Turn、Chat/Runtime、Chat/Records、Chat/VisualFixture 六个文件。
- [x] hash/ID/rawValue 清理（记录行不再回退原始 record.id；上下文匹配呈现删除后 `v%lld` 一并消失）。
- [x] 构建：arm64 iPhone 18 Pro Simulator `build-for-testing` 成功（exit 0，无源码 warning/error）；测试只编译不执行；双语 strings 1045 键、键集合一致。
- [ ] 验收：假 Provider 截图（深/浅色、大字体、小屏）+ VoiceOver 标签检查 + 真机签字。

### S4 iSH 小主机与文档交付 `[~]`

- [x] Shell 与文档工具默认启用（`.documents` 组取代 `.shell`，成员 shell_execute/environment_prepare/environment_status/file_publish）；Project 绑定中未显式切换过的工具跟随默认。
- [x] 主界面出现后后台低优先级预热 rootfs（幂等共享 flight）；标记级安全重试；未就绪时活动行显示“正在准备运行环境”。
- [x] rootfs 预装 python-docx、openpyxl、python-pptx、fpdf2、pypdf、markdown、py3-lxml、py3-pillow 与 Noto Sans SC 子集（OFL-1.1）；实测 33.3 MiB → 55.0 MiB（57,601,472 字节）。
- [x] 内置 `documents` Skill 模板；Shell Outputs 自动 best-effort 校验后进入 Files（失败仍登记并标注）；补 PPTX（`FamiliarFileFormat.pptx` + validator + file_publish）；文件卡沿用产出文件路径。
- [x] boot/解包/探测错误带具体原因（含 boot 状态码）；staging 失败清理且 Retry 不需重启；终端 watchdog 不再计入准备时间；guest 默认不出站、pip 只走配置源（保持）。
- [x] 构建：arm64 iPhone 18 Pro Simulator `build-for-testing` 成功（exit 0，无源码 warning/error）；guest 冒烟（中文 PDF/DOCX/XLSX/PPTX）在重建镜像时通过；新增/更新测试只编译不执行。见 docs/18-s4-shell-documents-design.md。
- [ ] 验收：真机 `FamiliarDeviceRuntimeTests` + `log stream`；生成中文 Word/Excel/PPT/PDF；记录冷热启动耗时与内存峰值；所有者签字。

### S5 设置重组 `[ ]`

- 分组：模型、个性化、能力、外观、隐私与数据、关于，底部“开发者”。取消“高级”中转层。
- SF Symbol + 系统色；二级页编辑即生效；合并两套运行记录 UI；拆分 FamiliarSettingsHubView.swift。

### S6 Project 与 Files `[ ]`

- 文件列表原生 List + 文件详情页（版本、预览、分享、删除），预览统一 push。
- Project 详情行样式与设置统一；修 `try?` 吞掉的保存错误，清理死代码。

### S7 二级能力 `[ ]`

- 语音、图片与相机、文档导入、日历提醒、地点天气逐项过“能用、好看、错误可理解”。
- 真实请求验证 deepseek-v4-flash 图片输入；通过才标记支持图片，否则继续用 Apple Vision 证据。

### S8 三级能力 `[ ]`

- MCP、Skills、通知、闹钟、健康、照片、音乐、蓝牙、剪贴板、终端 UI 逐个打磨。

## 所有者验收

| 切片 | 截图过目 | 真机签字 |
|---|---|---|
| S1–S8 | [ ] | [ ] |

## 当前切片

普通对话/项目分离、抽屉顶栏与 S2a 已实现并通过指定 arm64 iPhone 18 Pro 构建。按所有者要求，本切片不执行测试或截图；真机视觉由所有者负责，运行生命周期和业务重置验收待记录。

S2b（能力级持续授权、Memory 自动写入、environment_prepare 自动边界、MCP 信任）已实现：arm64 iPhone 18 Pro Simulator `build-for-testing` 成功，测试只编译不执行；真机行为验收清单见 docs/17-s2b-authorization-design.md §5，验收前完整 S2 不标完成。

S4（文档工具组默认启用、后台预热、rootfs 预装文档库与中文字体、Outputs 自动校验、PPTX、documents Skill 模板、watchdog/错误恢复）已实现：`build-for-testing` 成功，guest 冒烟在重建镜像时通过；真机验收清单见 docs/18-s4-shell-documents-design.md §5，验收前 S4 不标完成。

S3（工具结果四种呈现、presentation 工具与 payload 收敛、侧栏原生 List、省略号精简、Composer 原生 Menu、消息视图拆分）已实现：`build-for-testing` 成功，测试只编译不执行；验收（假 Provider 三态截图 + VoiceOver + 真机签字）待所有者执行，验收前 S3 不标完成。

S1 的 79 项定向单测、WebKit 引用回归与 3 项生产 UI 证据仅属于之前的 S1 基线；DeepSeek + Tavily 20 条真实查询与所有者签字仍待完成。后续切片同样单列真实验收结果，不把编译等同于运行通过。

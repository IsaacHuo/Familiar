# Familiar 打磨计划

跨对话任务账本。只记录：分级功能清单、切片与验收脚本、当前切片。不复制 git 历史，不记录密钥。

## 上传隐私声明修正（2026-10-19）

- [x] 补齐 App Store Connect 报告缺失的 `NSHealthUpdateUsageDescription`，包括基础 Info.plist 及中英文用途说明。HealthKit 仍只读，`toShare` 为空，不新增写入权限。
- [x] 发布合规检查覆盖 HealthKit 读取／写入用途键；plist 格式、15 项用途说明双语完整性及 diff 静态检查通过。
- [ ] 构建与重新上传由所有者执行。按所有者最新要求停止代理 Release 构建，不记录为构建通过；未启动 Simulator 或执行测试。

## 当前切片：Telegram UI 与动效源码迁移 `[~]`

所有者授权完整P0–P5，方案及逐文件来源/适配/真机脚本见 [docs/22](docs/22-telegram-ios-ui-motion-polish.md)。本轮代理实现收口，设备验收单独开放；历史hwf卡死复验仍是阻塞优先项。

- [x] P0：重复呈现幂等、交互转场取消恢复、离场选择/发送快照清理。
- [x] P1：Telegram文件行/分类、原生长按、多选/全选、冻结File/Scope/Version分享和逐项删除、部分失败保留。
- [x] P2：0.3秒横纵发送曲线、成功持久化消息ID关联、可见快照与过期释放；组合文字、附件源、输入区与末行时间；原紧凑间距/宽度/正文内边距迁移。
- [x] P3：正式Native/WK选区菜单、单一选区、菜单退场后追加草稿，保留附件/技能；UIKit图片缩放分页、拖拽/取消和按当前图找源；文档仍QuickLook。
- [x] P4：会话字体/头像密度、分类100pt前瞻、有界预览；设置页级头像/标题/原遮罩关键帧/模糊；润色共享选择区域与键盘恢复Sheet高度。Project/运行记录复用已实现的紧凑行/渐进披露。
- [x] P5代理：各片与最终指定arm64 App/测试目标构建、双语/JS/资源/套件清单/diff静态检查；新增批量失败/Scope、草稿追加、选区所有权、图库阈值、头像进度回归，仅编译。
- [ ] 所有者真机：docs/22检查单；尤其首次WK编辑菜单、返回取消、批量删除部分失败、图库翻页回归和设置头像/Sheet层级。未确认修正版卡死消失、性能或真实Provider。

构建：`/tmp/Familiar-Telegram-motion-final-build.log`，指定arm64 Debug `build-for-testing` 成功，App/单元测试/UI测试目标编译；未启动Simulator、未执行测试、未安装真机。代码保留在main，未代为提交或发布；原39实体/schema/业务代际及授权/运行规则不变。

## hwf 卡死与首页搜索前序切片 `[~]`


2026-10-19 所有者反馈频繁卡死，并要求搜索初次隐藏、下拉自然出现。暂停新增功能，优先处理本轮阻塞。详见 docs/21 §2.10 与 [设备调查](docs/research/2026-10-19-hwf-hang-investigation.md)。

- [x] 读取 hwf 三份历史报告：均为 FRONTBOARD 退出看门狗，两份主线程包含消息布局；读取 Xcode 留存的几何重复更新警告。
- [x] 对现有 PID 41343 附加10秒 Time Profiler，不启动/替换 App；该窗口 Hangs 表为空，只有一条 CPU 样本，未捕获活跃卡死，不当作修复验收。
- [x] 所有者确认仍卡且保持前台后，重新附加15秒采样：15778条样本中15774条为主线程，均包含交互式返回转场；读取同PID CPU资源报告（约108秒消耗90秒CPU，系统未采取终止动作）。保留原始 trace/XML/报告，不将初次空采样当作恢复。
- [x] 气泡测量/放置采用相同未指定高度约束，包装不递归导出显式对齐；阅读补偿改为布局后合并，视口移动更新锚点，过期/离场采样取消。
- [x] 可见性已读记录移出布局State；UIKit转场开始即暂停阅读修正，取消返回后恢复；文件预览导航移到页面，入口具有稳定可比较身份；Markdown外观JSON按有限系统输入缓存。
- [x] 搜索默认折叠，首份数据/有效尺寸后恢复；首次真实拖动前不发布布局偏移，短/空列表保留必要滚动范围；原下拉/上滑/吸附和搜索取消恢复保留。
- [x] 指定 iPhone 18 Pro / iOS 27.0 / arm64 Debug `build-for-testing` 成功，exit 0、`TEST BUILD SUCCEEDED`，App 与测试目标编译，最终日志无 warning/error。日志 `/tmp/Familiar-hwf-hang-search-final-build.log`；`git diff --check` 通过。新增几何回归只编译，未执行。
- [x] 前台现场追加修正最终构建同一 arm64 目的地成功（exit 0、`TEST BUILD SUCCEEDED`、无 warning/error），日志 `/tmp/Familiar-hwf-foreground-final-build.log`。转场开始暂停/取消恢复的定向回归只编译；未执行测试、启动Simulator或安装设备版本。
- [x] 所有者20:51图反馈：空对话移除全部中部引导；照片删除叉号向左下各移6pt，保留44pt命中区；消息菜单“新对话”首项。
- [x] 最新要求替代上述下拉搜索：首页右上角搜索/新建为原生按钮组；独立搜索页保留本地范围/结果/分页，命中待关闭后导航。设置首页去重复搜索框，从搜索/编辑组进入搜索；命中待关闭后直达既有设置路由。移除旧54pt留位/展开/吸附代码，分类和列表位置保留。
- [x] 入口精简最终构建：同一arm64目的地 Debug `build-for-testing` 成功（exit 0、`TEST BUILD SUCCEEDED`、无warning/error），App/测试目标编译；日志 `/tmp/Familiar-ui-entry-cleanup-build.log`，diff静态检查通过。未启动Simulator或执行测试。
- [ ] 所有者 hwf 复验：进出长回答、键盘/流式/旧位置阅读；空对话无引导、照片叉号、菜单首项；首页/设置无重复搜索框，右上角按钮组、搜索命中/取消及分类/列表位置恢复。卡死若重现，保持前台现有进程再采样。

未启动 Simulator、执行测试或安装真机版本；无存储、Provider、权限或 Runtime 语义变化。本轮仍为真机待验收，不能宣称所有卡死已解决。

## 原则

- 现有功能继续打磨；2026-10-18 所有者另行授权 Telegram 参照的全局导航、持久草稿、归档/未读与 AI 编辑器路线（R0–R6）。
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

### S5 设置重组 `[~]`

- [x] 分组：模型、个性化、能力、外观、隐私与数据、关于，底部“开发者”；取消“高级”与“隐私与数据”两层中转页，全部直达二级页。
- [x] 二级页编辑即生效：执行预算、自动记忆、人格提示等绑定改为写穿到 `onSaveSettings`，不再依赖 Done。
- [x] 合并两套运行记录 UI：设置 → 运行记录与项目运行记录共用同一行与详情（共享 `FamiliarRunRecordList/Row/Detail`），删除设置内简化版详情。
- [x] 拆分 FamiliarSettingsHubView.swift（1655 行）：Settings/ 下 Hub、Capability、Personalization、Privacy、RunHistory、RunRecord、About、ModelService 八个文件。
- [ ] 验收：真机逐页过设置（编辑即生效、无重复运行记录入口、深/浅色）。

### S6 Project 与 Files `[~]`

- [x] 文件列表改为原生 List（行即导航），新增文件详情页：概览 + 预览/分享、版本列表（v 序、最新标记、逐版本预览 push）、项目资料开关、删除（确认后 pop）；预览全部 push。
- [x] Project 详情行样式与设置统一：共享 `FamiliarSettingsRowIcon`（渐变图标块），项目上下文各行按语义配色；设置 Hub 去掉重复的本地缩放属性。
- [x] 修复吞错的保存：Approved Actions 撤销/全部撤销改用显式 do/catch、失败 rollback 并弹出错误；清理死代码（`FamiliarProjectSectionHeader`、`emptyRow`）。
- [x] 构建：arm64 iPhone 18 Pro Simulator `build-for-testing` 成功（exit 0，无源码 warning/error）；双语 1050 键一致；测试只编译不执行。
- [ ] 验收：真机过 Files（行→详情→各版本预览/分享/删除、项目资料开关）与项目详情视觉；统一清单见 docs/19-owner-acceptance-checklist.md。

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

当前为 U6 历史按需投影与持久层窗口读取；此前 UI/资源层已实现并编译，设备验收仍分别记录。最新实施与证据见本文末节。只构建，不启动 Simulator 或执行测试。

普通对话/项目分离、抽屉顶栏与 S2a 已实现并通过指定 arm64 iPhone 18 Pro 构建。按所有者要求，本切片不执行测试或截图；真机视觉由所有者负责，运行生命周期和业务重置验收待记录。

S2b（能力级持续授权、Memory 自动写入、environment_prepare 自动边界、MCP 信任）已实现：arm64 iPhone 18 Pro Simulator `build-for-testing` 成功，测试只编译不执行；真机行为验收清单见 docs/17-s2b-authorization-design.md §5，验收前完整 S2 不标完成。

S4（文档工具组默认启用、后台预热、rootfs 预装文档库与中文字体、Outputs 自动校验、PPTX、documents Skill 模板、watchdog/错误恢复）已实现：`build-for-testing` 成功，guest 冒烟在重建镜像时通过；真机验收清单见 docs/18-s4-shell-documents-design.md §5，验收前 S4 不标完成。

S3（工具结果四种呈现、presentation 工具与 payload 收敛、侧栏原生 List、省略号精简、Composer 原生 Menu、消息视图拆分）已实现：`build-for-testing` 成功，测试只编译不执行；验收（假 Provider 三态截图 + VoiceOver + 真机签字）待所有者执行，验收前 S3 不标完成。

S5（设置分组扁平化、编辑即生效、运行记录 UI 合并、文件拆分；另含 Provider 品牌图标与「仍在开发中」说明）已实现：`build-for-testing` 成功，测试只编译不执行；真机逐页验收待所有者执行。统一验收入口见 docs/19-owner-acceptance-checklist.md。

S6（Files 列表原生 List + 文件详情页、Project 行样式与设置统一、撤销保存错误显式化、死代码清理）已实现：`build-for-testing` 成功，真机验收待所有者执行。

S1 的 79 项定向单测、WebKit 引用回归与 3 项生产 UI 证据仅属于之前的 S1 基线；DeepSeek + Tavily 20 条真实查询与所有者签字仍待完成。后续切片同样单列真实验收结果，不把编译等同于运行通过。

## Telegram 参照重构（2026-10-18）

所有者已授权完整计划，设计与本次真机验收顺序见 [docs/20-telegram-chat-ui-roadmap.md](docs/20-telegram-chat-ui-roadmap.md)。当前 R0–R5 实现收尾，按所有者最新要求停止扩展，等待最终构建与真机视觉反馈；之前 S1–S8 验收不自动结清。

- [x] R0：双线源码研究文档与目标方案落盘。
- [x] R1 实现：持久草稿、归档、未读、项目分类顺序与附件保护；新增两类持久记录，当前 schema 共 39 实体，业务代际不变。
- [x] R2 实现：文件/聊天/设置根导航、会话协调器与共享执行占用、系统入口；查看路由与运行会话分离，抽屉冻结并移除生产挂载。
- [x] R3 实现：UICollectionView/diffable 列表、分类分页、只读预览、多选、搜索、项目管理/详情、独立草稿列表、文件聚合。
- [x] R4 实现：双侧气泡、独立技能菜单、回形针、持有阅读状态与转场；保留 Markdown/工具/文件生产组件。
- [x] R5 实现：用户 Provider AI 编辑器，翻译/风格/修正、本次模型选择、完整结果预览应用、撤销与版本保护；无工具、不进 Agent、不能与运行并发。
- [ ] R6：定向测试、截图检查、真实性能与真实 Provider；所有者真机签字另列。

静态验证：35 个改动 Swift 文件语法解析通过；中英各 1103 个资源键，无重复、集合相同、plutil 通过；git diff --check 通过。新增草稿/未读/存储演进/串行占用、AI 改写边界单测和导航 UI 用例，套件清单同步；编译与实际执行分别记录。

最终构建：2026-10-18，`main` 当前代码以 Xcode Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`）；指定 iPhone 18 Pro / iOS 27.0 / arm64，设备 UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`。App、单测和 UI 测试目标均编译；无源码 warning/error，仅两条构建工具提示 Metadata extraction skipped / no AppIntents.framework dependency。日志 `/tmp/FamiliarTelegram-wrap-build.log`，DerivedData `/tmp/FamiliarTelegramDerived`。

运行验证：本路线定向测试卡在 Simulator worker/安装启动、未进入用例执行；安装重试也未成功，按无进展规则终止。没有本路线测试执行、生产截图或真实性能通过证据；真实 Provider 与真机签字未完成，R6 保持未完成。旧 S1 的通过结果不得套用到本次。

下一步：所有者按 docs/20 末尾顺序真机视觉验收并反馈；先修复反馈，再决定自动运行验证与后续路线。到此不再扩展功能。

## 首页与聊天详情真机反馈修正（2026-10-18）

本节的实现/构建记录不是视觉通过。所有者随后确认顶部挤压、输入高度不齐和点击输入不出键盘；这些回归已重新打开，优先级与后续工作以下方“全应用 UI 优化指引”及 U0 为准。

当前切片：只修正 UI、输入和消息交互；Provider、授权、持久化 schema、运行业务不变。具体决定与验收点见 docs/20 末节，Telegram 源码补充核对见 docs/research/2026-10-18-telegram-ios-ui.md。

- [x] 删除整个 tabViewBottomAccessory，保留原生紧凑三 Tab；首页中央去标题，任务入口移入顶栏。
- [x] 首页列表与浮层分层，完整玻璃分类胶囊；真实偏移驱动默认收起的搜索、展开和吸附，草稿/归档进入列表内容流。
- [x] 详情省略号移除内部重复玻璃，中央模型胶囊关闭系统共享背景；技能固定纯图标和命中范围。
- [x] 原生 UITextView 统一正文/占位/实际测量/焦点/UTF-16 选区；marked text 期间不覆盖中文输入法组合。
- [x] 删除常驻复制/重试及空操作行，原生长按菜单与原位选择互斥；链接/代码操作保留，菜单/选择保护阅读位置，UI 测试改用 message.completed。
- [ ] 所有者真机视觉与交互验收。

验证边界：所有者最新明确要求代理只构建、以后不启动 Simulator 做视觉检查，已写入 AGENTS.md；本轮没有执行测试或取得页面截图，要求更新后只做编译。中英各 1105 键、无重复且集合一致，plutil、JavaScript 语法及 git diff --check 通过。

最终构建：2026-10-18，指定 iPhone 18 Pro / iOS 27.0 / arm64，UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`，Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`），App、单测和 UI 测试目标均编译，最终日志无 warning/error。日志 `/tmp/FamiliarGlass-closeout-build.log`，DerivedData `/tmp/FamiliarGlassDerived`。本次没有运行、视觉或真实 Provider 通过证据。

下一步：将构建通过的代码交给所有者真机检查，按反馈修正；未执行的测试、真实 Provider 和视觉不得记作通过。

## 全应用 UI 优化指引（2026-10-18）

总指引见 [docs/21-telegram-ios-ui-optimization-guide.md](docs/21-telegram-ios-ui-optimization-guide.md)。文档落盘后所有者已发起 U0；U0 已实现，所有者最新授权先修反馈后进入 U1，另授权本机资料/AI 摘要标题及删除全部旧对话。Provider 连接、授权规则和 Agent Loop 不变。

- [x] 总指引落盘，覆盖首页、聊天、Files、Project、设置、Memory、AI 编辑器与运行记录。
- [x] 68 个候选源文件逐行登记完整固定提交链接、阅读深度/行段、结论或待查项、Familiar 对应与路线；9 个全文审阅、38 个关键函数片段、20 个仅检索、1 个待审。全部副本与固定提交 Git blob 一致，未把下载记作完整审阅。
- [x] 优先候选与后续产品候选分开；候选不自动纳入实施。目录、当前状态与本账本入口同步。
- [x] U0-01 实现：浮层固定在安全视口内，只有列表延伸到系统栏后；按实际重叠量计算 inset，收起时移除搜索玻璃，动态高度同步折叠距离。待所有者真机确认原重叠现象消失。
- [x] U0-02 实现：普通 Binding 焦点请求与 UIKit delegate 实际焦点分开，取消过期请求；菜单退场完成后执行编辑/选择，输入玻璃不拥有编辑手势。待所有者真机键盘验收。
- [x] U0-03 实现：统一外层高度，默认单行至少 44pt、包含 padding；多行增长，展开模式顶部对齐。待真机大字体/键盘布局验收。
- [x] U0-04 实现：AI 和发送/停止尾部空间固定，展开入口不挤正文；移除无效 expanded 模式反馈。待真机阈值输入/删除验收。
- [x] U0-05 实现：编辑态/原草稿和附件引用保存到可空草稿元数据，进入/取消不删历史；新完整回复成功保存时同事务替换旧尾部，失败/取消保留原历史并恢复编辑稿，已产生的失败尝试记录可查。待真机存储与失败路径验收。
- [x] U0-06 实现：归一化 UTF-16 选区、正文版本与替换边界、marked text 保护和操作前组合文本提交；同文字的旧版本润色结果也拒绝应用。待真机中文/Emoji/撤销验收。
- [ ] U0 所有者真机验收：见 docs/21 §2.2；原症状尚未由所有者确认消失，不能以编译结清。
- [~] U5 已实施并编译；真机反馈修正及 U6 第一层已实施并编译，设备与 U6 后续数据投影分别待验收/实施。

验证：2026-10-18 指定 iPhone 18 Pro / iOS 27.0 / arm64，UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`，Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`），App、单元测试和 UI 测试目标均编译，最终日志无 warning/error。日志 `/tmp/FamiliarU0-closeout-build.log`，DerivedData `/tmp/FamiliarU0Derived`。中英各 1110 键、集合一致且无重复，plutil、JS 语法、diff 和测试套件清单检查通过。

新增/更新选区字符边界、编辑取消/草稿恢复/附件保护、提交事务回滚/成功替换、同文字旧版本润色等定向用例，全部仅编译，未执行。现有草稿实体新增可空 editStateData，仍为当前 schema 5.0.0 / 39 实体 / 5-work-scopes，无历史迁移链或再次重置；旧存储演进未运行验收。

验证边界：不执行测试、不启动 Simulator 或截图；所有者真机验收独立。之前和本次编译通过均不等同于最新回归已运行通过。

### U0 反馈修正 + U1 消息阅读 `[~]`

- [x] 连续空行：无限高 TextKit 测量包含尾部空段落；输入最多六行后内部滚动、裁切并保持光标可见，展开入口保留。
- [x] 顶栏：移除中央模型/标题胶囊，模型切换移入省略号；右侧 44pt 圆形单层玻璃/17pt 图标，去掉整条导航背景和顶部滚动边缘效果，保留原生返回。
- [x] U1：用户文字与已完成短 AI 纯文本适应内容宽度，复杂 Markdown 维持稳定阅读宽度；气泡内时间单行可同排，其余独立末行；日期分隔与相邻用户间距；Run、工具、文件、正文身份/顺序保留。
- [x] U1：稳定消息定位高亮与返回阅读位置入口，接入原阅读状态；没有添加引用/分支/书签新语义。
- [x] 个性化：Tab 名称“对话”；设置本机头像/昵称/简介编辑与保存，图片降采样，取消/晚到任务不覆盖已保存资料。
- [x] AI 标题：完整回复后的用户 Provider 无工具摘要、origin/revision 竞争保护、人工命名保留、失败不伪造摘要；不取首句作为正式标题。
- [x] 所有者要求清理全部旧对话：启动时通过现有删除事务清理 titleOrigin=nil 的旧记录，保留 Project 与配置；新记录初始化 origin，不重复删除。未启动 App，实际设备清理待新版首次运行。
- [x] 定向回归用例：空白段落高度、Markdown/链接分流、跨天分隔、旧历史清理幂等/新数据保护、摘要请求无工具/完整终态。只编译，不执行。
- [ ] 所有者真机验收与真实 Provider 标题：见 docs/21 §2.3；不能由编译推定通过。

构建：2026-10-18 指定 iPhone 18 Pro / iOS 27.0 / arm64（UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`），Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`），App、单元测试、UI 测试目标全部编译，收尾日志无 warning/error。日志 `/tmp/FamiliarU1-closeout-build.log`，DerivedData 复用 `/tmp/FamiliarU0Derived`。中英各 1118 键，集合一致且无重复；plutil、JS 语法、diff 与测试套件清单检查通过。只构建，不执行测试、不启动 Simulator、不截图；真实 Provider、旧存储演进/清理和视觉交互均待所有者真机验收。

下一步：所有者验收本轮输入、顶栏、消息阅读、资料和首次启动清理；按反馈修正，再安排 U2 首页与搜索。


### U2 首页与本地搜索 `[~]`

专项契约见 docs/21 §2.4。所有者授权继续下一步，未据此推定上一阶段全部真实服务/设备项目通过。

- [x] 分类选中项自动滚入可见范围，稳定排序/删除回退；分页进度与列表输入分离，每个分类独立草稿入口与偏移，取消搜索复位实际列表与头部。
- [x] 置顶和未读同时呈现，归档分类角标范围一致；附件草稿/消息摘要携带真实文件名和照片数量。
- [x] 列表行按 ID 字典配置，特殊行版本化更新，多选同步覆盖屏幕外状态；原生预览直接限取最近三条消息。
- [x] 本地 ModelActor 查询替代生产视图关系遍历；空查询无检索，200ms 防抖、任务取消/版本检查、当前分类/全部范围、实际总数、每页 50 条和后续加载。
- [x] 结果摘要围绕命中位置，保留字符边界；标题/消息分区、关键词着色、归档标记与稳定消息定位。
- [x] 详情菜单接入会话内查找：匹配消息计数、上/下结果、自动后续页、关键词标记/定位高亮、关闭恢复阅读及检查状态收尾；搜索不自动标记已读。
- [x] WebKit 范围标记不改正文 DOM、不接收触摸，裁切到代码/表格滚动区域；保留长按/链接/复制，避开 WebKit user-select:none 的 Custom Highlight 已知限制。
- [x] 新定向回归用例覆盖空查询/空范围、分页和范围隔离、归档标记、搜索不改历史/未读、末尾 Unicode 命中与附件草稿摘要，仅编译、不执行。
- [ ] 所有者真机验收：docs/21 §2.4；真实 SQL/焦点/阅读/手势与性能不由编译结清。

构建：2026-10-18 指定 iPhone 18 Pro / iOS 27.0 / arm64（UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`），Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`），App、单元测试及 UI 测试目标均编译，最终日志无 warning/error。日志 `/tmp/FamiliarU2-closeout-final-build.log`，DerivedData 复用 `/tmp/FamiliarU0Derived`。中英各 1129 键、集合一致且无重复；plutil、JS 语法、diff 及测试套件清单检查通过。

未启动 Simulator、未执行测试或截图；实际 SQL、WebKit 高亮/手势、导航/焦点/阅读恢复、规模性能与所有者真机验收均未以编译结清。无新 schema/业务重置，Provider/授权/Agent Loop 不变。

下一步：先由所有者真机验收 U2 并修正反馈，再安排 U3 附件与 Files。


### U3 附件与 Files `[~]`

所有者授权继续 U3。范围：逐附件真实导入状态/取消/重试；Files 类型/归属筛选、排序、日期分组和菜单；版本/来源/失效信息、异步缩略图及系统多图浏览。保留 canonical File/FileVersion、原 scope、删除确认/事务和字节校验；不加入跨重启导入续传。

分层实施 Files/缩略图/预览刷新、附件状态，再接入草稿与消息的同一系统图片浏览。失败附件重试或移除后发送，晚到回调检查草稿与尝试身份；浏览限当前草稿/消息附件集，不扩展全历史媒体库。构建与真机验收分开。

- [x] Files：类型/归属/搜索、四种排序、时间分组与菜单；最新/历史版本分享和预览精确绑定，来源/失效状态；原删除确认/事务保留。
- [x] ImageIO/QuickLookThumbnailing 后台缩略图，内存缓存成本提示；恢复只加载附件引用，原始托管字节不被缩略图替代；按版本 ID 限取卡片数据。
- [x] 逐附件准备/失败/成功与取消/重试，数量限制含排队/失败项；准备串行，失败项处理后发送；停止 Agent 不阻塞。
- [x] 实际草稿附件身份及尝试版本检查，取消/晚到结果只清理本次未交付字节；附件变化即时保存检查点，保存失败由原路径报告。
- [x] 共用系统图片浏览器、当前位置/数量、原生缩放/分页与返回转场；草稿可移除、消息只读、QL 编辑关闭；阅读检查生命周期接通。
- [x] 未改变 URL 的 QL/HTML 不重复重载；HTML 后缀保持 CSP/禁脚本路径，不从缩略图生成绕过。
- [x] 新类型分类、缩略图尺寸、托管原字节/无完整位图恢复、附件身份边界回归，仅编译不执行。
- [ ] 所有者真机验收：docs/21 §2.5，实际导入/重试/分页/缩放/阅读与资源峰值未由编译结清。

构建：2026-10-18 指定 iPhone 18 Pro / iOS 27.0 / arm64（UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`），Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`），App、单元测试及 UI 测试目标均编译，最终日志无 warning/error。日志 `/tmp/FamiliarU3-closeout-final-build.log`，DerivedData 复用 `/tmp/FamiliarU0Derived`。中英各 1160 键、集合一致且无重复；plutil、JS 语法、diff 及测试套件清单检查通过。

未启动 Simulator，不执行测试或截图；系统预览/缩放/分页、实际导入/重试/取消、旧草稿恢复和资源峰值均待所有者真机。当前 schema 5.0.0/39 实体/5-work-scopes 不变，无新 Provider/授权路径。研究登记按实际新增阅读片段更新为 9 全文/40 关键片段/18 检索/1 待审，未将下载记作审阅。

下一步：所有者真机验收并修复反馈，再进入 U4 设置与 Project。


### U4 设置与 Project `[~]`

所有者授权进入 U4。先统一设置搜索元数据/路由与紧凑状态行，修复 Provider 校验身份；再明确 Memory 归属/文案、Project 工作入口、存储统计与运行记录渐进披露。复用原保存/验证/删除服务，不增加账号、模型请求或授权路径；无新 schema/重置。只构建 App 和测试目标，不启动 Simulator，由所有者真机验收。

- [x] 设置路由统一目录、本地标题/别名/路径搜索、资料编辑复用、紧凑状态行及大字体纵排；保存采用实际应用值，Done 不重复保存。
- [x] Provider 验证绑定 descriptor/模型/credential 会话哈希身份，配置变化或验证失败失效；发现/验证/登录状态分开，编辑器独立文件。
- [x] Memory 文案/归属筛选/真实名称、项目 scoped 入口与范围删除确认，编辑错误在 Sheet 反馈，保存失败回滚；不改自动记忆策略。
- [x] Project 记忆/运行/配置直达既有页面，移除高级中转；原指令/Files/会话/授权范围保留。
- [x] 后台物理文件统计、同文件身份去重/符号链接排除、逻辑记录数量、取消与版本保护；口径/不完整状态明确，不新增清理动作。
- [x] 运行结果摘要、精确回复、按需 Markdown、步骤/回执/技术渐进披露；状态本地化、当前 run Skill 查询及 activityID 对应。
- [x] 定向目录覆盖/双语别名、Provider 身份与物理文件去重/链接隔离用例，只编译、不执行。
- [ ] 真机与真实 Provider/存储扫描/SQL/保存故障验收：docs/21 §2.6，不由编译结清。

构建：2026-10-18 指定 iPhone 18 Pro / iOS 27.0 / arm64（UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`），Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`），App、单元测试及 UI 测试目标均编译，最终日志无 warning/error。日志 `/tmp/FamiliarU4-wrap-closeout-build.log`，DerivedData 复用 `/tmp/FamiliarU0Derived`。中英各 1196 键、集合一致且无重复；22 个目录条目的资源键齐全，plutil、JS 语法、diff 和测试套件清单检查通过。

新定向用例只编译、不执行；未启动 Simulator 或截图。真实 Provider/SQL/磁盘扫描/保存故障与所有者真机交互仍待验收。没有新 schema、业务重置或 Provider/授权策略，Memory 开关对后续发送生效，当前运行仍使用原冻结配置。研究登记按实际片段更新为 9 全文/43 关键片段/15 检索/1 待审。

下一步：所有者真机验收 U4、修正反馈，再进入 U5 动效与可访问性。


### U5 动效与可访问性 `[~]`

所有者授权继续下一步。专项契约见 docs/21 §2.7；不改变 Provider、授权、运行和数据规则。代理只构建，不执行测试或启动 Simulator。

- [x] 输入尾部为同一个 44pt Button，麦克风/发送/停止共用稳定身份与宽度；语音转写期间保留停止入口。
- [x] 挂载时间线的稳定 ID 入场登记、初始恢复抑制、Lazy 重建/流式终态不补播；正文增量不再生成动画 span。VoiceOver 暂停自动追随，手动返回仍可用。
- [x] 原生文本辅助动作、Markdown 独立辅助动作与原 DOM 共存；选择退出/释放沿用原状态，动作只连已有编辑/安全重试。列表动作、非当前页/搜索背后辅助树、状态朗读及折叠搜索入口补齐。
- [x] 输入名称、44pt 命中、48pt 分类胶囊、增加对比度实色路径；运行语义边界前台排队播报，不逐 token、不抢焦点。
- [x] 原生菜单有界快照与 Quick Look 系统转场保持，降低动效、透明度及字号沿原公开 API 路径。
- [x] 身份去重/动作资格/语义播报/WebKit 结构及焦点回归用例已新增；仅编译、不执行。
- [x] 收尾指定 arm64 App/测试目标构建与静态检查。
- [ ] 所有者真机/VoiceOver/系统偏好验收，见 docs/21 §2.7；不由构建结清。

构建：2026-10-18 指定 iPhone 18 Pro / iOS 27.0 / arm64（UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`），Debug `build-for-testing` 成功（exit 0，`TEST BUILD SUCCEEDED`），App、单元测试及 UI 测试目标均编译，最终日志无 warning/error。日志 `/tmp/FamiliarU5-acceptance-build.log`，DerivedData `/tmp/FamiliarU0Derived`。中英各 1201 键、无重复且集合一致；plutil、JS 语法、diff 和测试套件清单检查通过。

未启动 Simulator，不执行测试、截图、真实 Provider 或无障碍检查。新增回归只编译，系统 VoiceOver/键盘/转场/玻璃效果待所有者真机。无 schema/重置/运行策略变化；源码登记为 9 全文/44 关键片段/14 检索/1 待审，未把下载或检索当全文阅读。

下一步：所有者真机验收及修正反馈，再进入 U6 规模与资源收敛；本轮不自动启动 U6。


### 真机 UI 反馈修正与 U6 第一层 `[~]`

所有者授权：先按参考图修正设置/菜单/AI 润色及进出聊天抖动，再继续路线。具体契约与源码行段见 docs/21 §2.8；只构建，不启动 Simulator、不执行测试或截图，性能与视觉由设备证据验收。

- [x] 设置首页头像/搜索/编辑与无标题分组；正文高度+32pt、29pt 图标/16pt 间距，去重复 List 留白；标准行尾状态单行，辅助字号纵排。
- [x] 聊天省略号与返回共用系统 Toolbar 玻璃规格，主菜单只保留“当前模型”入口。
- [x] AI 润色命名、62pt 模式胶囊、风格/原文/结果统一卡及生成/停止/应用主按钮，保留对照、复制、重新润色、用户模型和版本/执行保护；无直接发送。
- [x] 外层目的地固定 Tab Bar 状态、已有会话直接呈现、初始阅读位置、自动跟随无动画、退场几何/DOM隔离、焦点收尾；抖动实际消失与否待设备复验。
- [x] 80 项展示窗口、旧/新页、目标居中与退出恢复；模型上下文仍完整；数据库按需消息投影另列。
- [x] 当前会话运行记录按批200 ID 查询，scope 文件过滤与 Run 字典，项目/列表 ID 查找及已有状态初始化收敛。
- [x] 保存成功后释放闲置会话；保护导航、Agent/压缩、润色/后处理/导入，额外闲置上限2；最多128轻量阅读书签。
- [x] 缩略图按尺寸、共享/串行准备、读者取消与内存压力清理，旧代次不回填；原文件保留。
- [x] 窗口/分批范围/释放恢复/退场几何/缩略图定向回归及新主按钮 UI 用例更新，只编译。
- [x] 最终指定 arm64 App/测试目标构建与静态检查。
- [ ] 所有者视觉、抖动、系统操作、实际 SQL 和资源采样，不能由构建结清。
- [x] U6 后续完整业务历史/显示投影拆分和数据库窗口负载读取，见下一节。
- [ ] U6 实际 SQL 与设备性能测量；不宣称整体性能验收完成。

构建：2026-10-18 指定 iPhone 18 Pro / iOS 27.0 / arm64（UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`）Debug `build-for-testing` 成功，exit 0、`TEST BUILD SUCCEEDED`，App、单元测试及 UI 测试目标均编译，最终日志无 warning/error。日志 `/tmp/FamiliarUIFeedback-U6-acceptance-build.log`，DerivedData `/tmp/FamiliarU0Derived`。中英各 1206 键、无重复且集合一致；plutil、JS 语法、diff 和套件清单静态检查通过。

代理未启动 Simulator、不执行测试、截图、真实 Provider、性能或无障碍检查。新用例只编译；抖动、完整视觉、原生玻璃尺寸、实际 SQL/取消/内存压力仍待所有者设备。当前 schema/39实体/5-work-scopes 不变；没有重置、授权或模型上下文规则变更。研究登记 9 全文/46 关键片段/12 检索/1 待审；没有将检索升级为全文审阅。

下一步：先收敛本轮真机视觉/抖动反馈，随后专项拆完整快照的按需投影；不改模型上下文、编辑/重试/压缩语义。


### U6 历史按需投影与持久层窗口读取 `[~]`

所有者于2026-10-19授权继续下一步。本层拆开聊天显示与业务历史读取，接着上一层资源边界推进；不改变模型输入、授权、编辑替换事务或单 Agent 规则。具体契约见 docs/21 §2.9。

- [x] 身份/日期轻索引与80项富数据分开；SwiftData 按窗口 ID 读取正文、来源、附件、模型标记及关联 Run，页外不常驻富快照。
- [x] 发送、编辑前缀、压缩、分支和导出单独读取完整业务历史；朗读单独读最新 AI 回复，不能误用当前页。
- [x] 保留部分助手检查点的 Runtime 关联、最终块/来源顺序、真实回执、安全重试和作用域检查；分页失败不发布半页数据。
- [x] 目标定位、返回页/偏移、书签加载顺序、全局最新回复判定与无正文运行页；空页判断使用完整索引。
- [x] 阅读位置使用当前呈现实例所有权，旧页退场/几何/DOM补偿不覆盖新页；页内重现恢复对应数据。
- [x] Spotlight 以存在性谓词+标题字段读取索引；生产由根入口更新，聊天详情不再遍历所有消息关系。
- [x] 分页/完整输入/编辑前缀/分支/最终块/跨会话隔离/运行页/新旧呈现交接/Spotlight定向回归，仅编译。
- [x] 指定 arm64 App/测试目标构建与静态检查。
- [ ] 所有者设备验证实际 SQL、导航/阅读、真实 Provider、内存与延迟；不以编译宣称已运行通过。

身份索引仍按当前会话全量读取轻字段；完整业务操作按需获取全历史，单个 Run 仍完整投影。未测量SQL耗时、帧率、内存上限或启动时间。未新增 schema、迁移、重置、FTS 或 SQL schema 索引。


构建：2026-10-19 指定 iPhone 18 Pro / iOS 27.0 / arm64（UUID `1041DD9D-AC70-4DDD-9D34-52514C3E491F`）Debug `build-for-testing` 成功，exit 0、`TEST BUILD SUCCEEDED`；App、单元测试及 UI 测试目标均编译，最终日志无 warning/error。日志 `/tmp/FamiliarU6-history-final-build.log`，DerivedData `/tmp/FamiliarU0Derived`。中英各1206键，无重复且集合一致；plutil、JS语法、diff和测试套件清单静态检查通过。

未启动 Simulator，未执行测试/截图/真实 Provider、SQL日志或性能采样。当前实现是“全会话轻身份索引+按ID读取80项富负载”，完整业务历史按动作读取；没有声称索引成本或单Run内存已达标。下一步以所有者真机行为与性能反馈收敛，不自动引入新消息功能或改变模型上下文。

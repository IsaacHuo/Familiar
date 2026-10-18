# Current State

最后核对：2026-10-18（Telegram 参照导航与聊天重构，等待所有者真机验收）。

## 阶段

本轮 Telegram 参照重构 R0–R5 实现已收尾并通过指定 arm64 Simulator 构建，等待所有者真机视觉验收；R6 运行验证仍待完成。路线与本轮验收顺序见 docs/20-telegram-chat-ui-roadmap.md，账本见 PLAN.md。此前 S1–S6 的真实服务/截图/设备待验收项仍保留，见 docs/19-owner-acceptance-checklist.md，不由本轮编译结清。

## 现实状态

- 本轮 R0–R5 已接入：原生文件/聊天/设置三 Tab，最近/项目分页、搜索、归档、独立草稿、原生列表预览和多选；旧抽屉保持编译、生产不挂载。
- 唯一当前 schema 5.0.0 增至 39 实体，新增持久草稿与会话列表状态，业务代际不变。正文、UTF-16 选区、技能、托管附件分别保存；附件清理覆盖全部草稿。完整回复与未读一起保存，正式详情末尾可见才已读。
- 根会话协调器保留控制器与唯一前台执行占用，查看路由和运行会话分离；返回列表/切 Tab 不取消前台任务，其他会话可读和编辑草稿，不启动第二个 Agent/润色。
- 聊天改为用户右/AI 左，保留生产 Markdown、工具与文件呈现；独立技能菜单取代斜线触发，附件入口为回形针。原生 AI 编辑器提供翻译/风格/修正，复用用户 Provider、无工具、不进 Agent；预览后应用草稿并可撤销，校验版本和晚到结果。
- 所有者最新要求到此收尾，构建通过后自行真机视觉验收；下一步等待反馈。下文保留此前功能及验收边界。
- 部署目标 iOS 26.0（全部 iOS target）；Liquid Glass 是唯一视觉路径，仅保留“降低透明度”回退。
- Markdown 渲染保留非持久 WebKit；原生渲染评估依赖已移除。
- 默认模型 DeepSeek `deepseek-v4-flash`，目录中未声明图片输入，图片走 Apple Vision 证据。
- S1 历史基线证据：2026-10-17 arm64 iPhone 18 Pro Simulator `build-for-testing` 成功；S1 与 assistant-turn persistence 共 79 个用例真实通过。真实 WebKit 双引用同编号检查通过；浅/深色及大字体 3 项生产 UI 用例通过，截图已生成；真实模型与所有者验收独立见验收文档。

## 实施与待验证边界

- 搜索：上述 Key 保存/校验竞态、失败缓存与无进展混淆、引擎重排、首轮暴露、地区参数、压缩/中文解码已实施修复；请求数量和共享预算已收口。来源按已观测重定向归一，严格只列被引用来源。测试与真实服务验收见 docs/15-s1-search-acceptance.md；免 Key 搜索仍依赖服务 HTML 与 challenge 状态。已去掉中文→中国市场的自动映射和强制中文搜索词，原始搜索词中的地域仅由问题语义决定。
- 归属：普通对话无 Project，稳定草稿 ID，File/Workspace/Environment/授权按 project/conversation 完整 scope 隔离。业务代际 5-work-scopes 将在新版首次正常启动清理全部旧业务数据，保留凭据、模型/搜索配置和外观偏好；本次未启动 App，未实际触发重置。
- 生命周期：移动复制关联文件并保留历史引用映射，清摘要与旧范围授权；普通删除清独有文件与 Workspace；项目删除先转存聊天文件再转普通。
- 授权：S2a 已接入可撤销内置文件/Workspace 写入和经 Swift 检查且 checkpoint 成功的离线 Shell 自动执行。S2b 已实现：第 3 级外部影响（EventKit 创建/更新、通知、剪贴板、相册、alarm_schedule、skill_install、已信任 MCP）首次询问并默认「始终允许此类」，`.always` 按 scope + 能力版本匹配；删除类、alarm_cancel、未信任 MCP 每次询问；Memory 开关开启时自动写入并可撤销；environment_prepare 来自配置源时自动执行并保留会话撤销；MCP 信任为按服务器的用户设置。全部只编译未执行；真机行为验收清单见 docs/17-s2b-authorization-design.md §5。完整 S2 未标完成。
- 抽屉/顶栏：旧抽屉视图和手势冻结，生产不存在侧栏入口或边缘触摸区；聊天顶栏使用原生导航和模型/操作菜单，项目筛选来自首页。
- iSH：`.documents` 组（shell_execute/environment_prepare/environment_status/file_publish）默认启用，主界面出现后后台低优先级预热（幂等、失败静默）；rootfs 预装 py3-lxml/py3-pillow、python-docx/openpyxl/python-pptx/fpdf2/pypdf/markdown 与 Noto Sans SC 子集，实测 55.0 MiB（57,601,472 字节）；Shell Outputs 捕获后 best-effort 校验并标注失败；PPTX 已进入格式/校验/file_publish；内置 documents Skill 模板；终端 watchdog 不计准备时间。guest 冒烟（中文 PDF/DOCX/XLSX/PPTX）在重建镜像时通过；真机从未执行，冷热启动耗时与内存峰值待所有者记录。
- UI：设置入口被历史触摸区遮挡的问题已修复。S3 已完成呈现收敛：工具结果只保留活动行（Sheet 详情，含 receipt/records/Shell/技术详情）、行内引用+来源 Sheet、统一文件卡、输入区审批/澄清；task_plan/present_*/prepare_share 与 diff/code 等呈现整体移除；消息视图从单文件 2765 行拆为 `Presentation/Chat/` 六个文件；侧栏为原生 List（新对话/搜索/Pinned/Projects/最近/设置）；省略号移除重复 Memory 入口；Composer 添加菜单为原生 Menu（去掉 180ms sleep）。仍有约 22 种自定义 row、18 种卡片外观与两套运行记录 UI（S5/后续处理）。
- 测试执行：当前 iPhone 18 Pro 可执行定向单测；早期 UI 失败后的 xcresult 汇总曾无进展 180 秒并被 watchdog 终止；后续修复引用保存与设置触摸区，最终 3 项 UI 用例及结果包正常通过。S0 其余测试与所有者验收仍未补齐。

## 验收

本次 S1 的真实服务、截图所有者过目与真机验收分别记录在 docs/15-s1-search-acceptance.md；历史编译证据不代替本次测试。

## 本切片验证边界

2026-10-18 重构：35 个改动 Swift 文件语法解析通过；中英资源各 1103 键、无重复且集合一致；`git diff --check` 通过。App、单测及 UI 测试目标的指定 arm64 iPhone 18 Pro / iOS 27.0 `build-for-testing` 成功（exit 0，无源码 warning/error；两条构建工具 metadata 提示），日志 `/tmp/FamiliarTelegram-wrap-build.log`。本路线此前定向测试未进入执行即卡在 Simulator worker/安装启动，按无进展规则中断；安装未成功，未取得本路线运行测试、截图或性能通过证据。旧 S1 通过结果不覆盖此次改动。真实 Provider 与真机视觉待验收。

此前 S2–S6 按所有者“构建通过就行，真机视觉我验收”的要求只构建 App 与测试目标，没有执行对应 Simulator 测试、启动或截图。构建结果与未执行项目见 docs/16、17、18；前述 S1 测试结果只属于 S1 基线，不能视为后续架构变更的运行通过。

S2b 与 S4 的指定 arm64 iPhone 18 Pro `build-for-testing` 均成功（exit 0，TEST BUILD SUCCEEDED，无源码 warning/error）；S3 同样 `build-for-testing` 成功。双语 strings 1045 键、键集合一致；S4 的 rootfs 在 guest 冒烟（中文 PDF/DOCX/XLSX/PPTX）通过后重建并安装，供应链校验通过；未运行 Simulator/真机用例，真机验收清单见 docs/17 §5 与 docs/18 §5，S3 的三态截图与 VoiceOver 检查待所有者执行。

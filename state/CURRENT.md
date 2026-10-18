# Current State

最后核对：2026-10-17（S5 设置重组实现）。

## 阶段

全新打磨计划（见根目录 PLAN.md）。S0 基线完成；普通对话/项目分离、抽屉顶栏与 S2a 已实现（真机验收待记录）；S2b 授权分级已实现（真机行为验收待记录）；S4 iSH 小主机与文档交付已实现（真机验收待记录）；S3 Chat 呈现收敛已实现（三态截图/VoiceOver/真机签字待记录）；S5 设置重组已实现（真机逐页验收待记录）。S1 真实模型与所有者验收仍单列待完成；所有待验收项统一见 docs/19-owner-acceptance-checklist.md。

## 现实状态

- 部署目标 iOS 26.0（全部 iOS target）；Liquid Glass 是唯一视觉路径，仅保留“降低透明度”回退。
- Markdown 渲染保留非持久 WebKit；原生渲染评估依赖已移除。
- 默认模型 DeepSeek `deepseek-v4-flash`，目录中未声明图片输入，图片走 Apple Vision 证据。
- S1 历史基线证据：2026-10-17 arm64 iPhone 18 Pro Simulator `build-for-testing` 成功；S1 与 assistant-turn persistence 共 79 个用例真实通过。真实 WebKit 双引用同编号检查通过；浅/深色及大字体 3 项生产 UI 用例通过，截图已生成；真实模型与所有者验收独立见验收文档。

## 实施与待验证边界

- 搜索：上述 Key 保存/校验竞态、失败缓存与无进展混淆、引擎重排、首轮暴露、地区参数、压缩/中文解码已实施修复；请求数量和共享预算已收口。来源按已观测重定向归一，严格只列被引用来源。测试与真实服务验收见 docs/15-s1-search-acceptance.md；免 Key 搜索仍依赖服务 HTML 与 challenge 状态。已去掉中文→中国市场的自动映射和强制中文搜索词，原始搜索词中的地域仅由问题语义决定。
- 归属：普通对话无 Project，稳定草稿 ID，File/Workspace/Environment/授权按 project/conversation 完整 scope 隔离。业务代际 5-work-scopes 将在新版首次正常启动清理全部旧业务数据，保留凭据、模型/搜索配置和外观偏好；本次未启动 App，未实际触发重置。
- 生命周期：移动复制关联文件并保留历史引用映射，清摘要与旧范围授权；普通删除清独有文件与 Workspace；项目删除先转存聊天文件再转普通。
- 授权：S2a 已接入可撤销内置文件/Workspace 写入和经 Swift 检查且 checkpoint 成功的离线 Shell 自动执行。S2b 已实现：第 3 级外部影响（EventKit 创建/更新、通知、剪贴板、相册、alarm_schedule、skill_install、已信任 MCP）首次询问并默认「始终允许此类」，`.always` 按 scope + 能力版本匹配；删除类、alarm_cancel、未信任 MCP 每次询问；Memory 开关开启时自动写入并可撤销；environment_prepare 来自配置源时自动执行并保留会话撤销；MCP 信任为按服务器的用户设置。全部只编译未执行；真机行为验收清单见 docs/17-s2b-authorization-design.md §5。完整 S2 未标完成。
- 抽屉/顶栏：项目默认折叠、最近 5 条并去除单独置顶重复，普通最近 20 条；查看更多复用完整列表；项目详情合并进唯一省略号按钮，项目切换来自侧栏。
- iSH：`.documents` 组（shell_execute/environment_prepare/environment_status/file_publish）默认启用，主界面出现后后台低优先级预热（幂等、失败静默）；rootfs 预装 py3-lxml/py3-pillow、python-docx/openpyxl/python-pptx/fpdf2/pypdf/markdown 与 Noto Sans SC 子集，实测 55.0 MiB（57,601,472 字节）；Shell Outputs 捕获后 best-effort 校验并标注失败；PPTX 已进入格式/校验/file_publish；内置 documents Skill 模板；终端 watchdog 不计准备时间。guest 冒烟（中文 PDF/DOCX/XLSX/PPTX）在重建镜像时通过；真机从未执行，冷热启动耗时与内存峰值待所有者记录。
- UI：设置入口被历史触摸区遮挡的问题已修复。S3 已完成呈现收敛：工具结果只保留活动行（Sheet 详情，含 receipt/records/Shell/技术详情）、行内引用+来源 Sheet、统一文件卡、输入区审批/澄清；task_plan/present_*/prepare_share 与 diff/code 等呈现整体移除；消息视图从单文件 2765 行拆为 `Presentation/Chat/` 六个文件；侧栏为原生 List（新对话/搜索/Pinned/Projects/最近/设置）；省略号移除重复 Memory 入口；Composer 添加菜单为原生 Menu（去掉 180ms sleep）。仍有约 22 种自定义 row、18 种卡片外观与两套运行记录 UI（S5/后续处理）。
- 测试执行：当前 iPhone 18 Pro 可执行定向单测；早期 UI 失败后的 xcresult 汇总曾无进展 180 秒并被 watchdog 终止；后续修复引用保存与设置触摸区，最终 3 项 UI 用例及结果包正常通过。S0 其余测试与所有者验收仍未补齐。

## 验收

本次 S1 的真实服务、截图所有者过目与真机验收分别记录在 docs/15-s1-search-acceptance.md；历史编译证据不代替本次测试。

## 本切片验证边界

所有者明确要求“构建通过就行，真机视觉我验收”。本切片只构建 App 与测试目标，不执行 Simulator 测试、启动或截图。构建结果与未执行项目见 docs/16、17、18；前述 S1 测试结果只属于 S1 基线，不能视为后续架构变更的运行通过。

S2b 与 S4 的指定 arm64 iPhone 18 Pro `build-for-testing` 均成功（exit 0，TEST BUILD SUCCEEDED，无源码 warning/error）；S3 同样 `build-for-testing` 成功。双语 strings 1045 键、键集合一致；S4 的 rootfs 在 guest 冒烟（中文 PDF/DOCX/XLSX/PPTX）通过后重建并安装，供应链校验通过；未运行 Simulator/真机用例，真机验收清单见 docs/17 §5 与 docs/18 §5，S3 的三态截图与 VoiceOver 检查待所有者执行。

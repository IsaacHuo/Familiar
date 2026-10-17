# Current State

最后核对：2026-10-17（普通对话/项目分离与 S2a）。

## 阶段

全新打磨计划（见根目录 PLAN.md）。S0 基线完成，当前实施切片为普通对话/项目分离、抽屉与顶栏收敛、S2a。S1 真实模型与所有者验收仍单列待完成。

## 现实状态

- 部署目标 iOS 26.0（全部 iOS target）；Liquid Glass 是唯一视觉路径，仅保留“降低透明度”回退。
- Markdown 渲染保留非持久 WebKit；原生渲染评估依赖已移除。
- 默认模型 DeepSeek `deepseek-v4-flash`，目录中未声明图片输入，图片走 Apple Vision 证据。
- S1 历史基线证据：2026-10-17 arm64 iPhone 18 Pro Simulator `build-for-testing` 成功；S1 与 assistant-turn persistence 共 79 个用例真实通过。真实 WebKit 双引用同编号检查通过；浅/深色及大字体 3 项生产 UI 用例通过，截图已生成；真实模型与所有者验收独立见验收文档。

## 实施与待验证边界

- 搜索：上述 Key 保存/校验竞态、失败缓存与无进展混淆、引擎重排、首轮暴露、地区参数、压缩/中文解码已实施修复；请求数量和共享预算已收口。来源按已观测重定向归一，严格只列被引用来源。测试与真实服务验收见 docs/15-s1-search-acceptance.md；免 Key 搜索仍依赖服务 HTML 与 challenge 状态。已去掉中文→中国市场的自动映射和强制中文搜索词，原始搜索词中的地域仅由问题语义决定。
- 归属：普通对话无 Project，稳定草稿 ID，File/Workspace/Environment/授权按 project/conversation 完整 scope 隔离。业务代际 5-work-scopes 将在新版首次正常启动清理全部旧业务数据，保留凭据、模型/搜索配置和外观偏好；本次未启动 App，未实际触发重置。
- 生命周期：移动复制关联文件并保留历史引用映射，清摘要与旧范围授权；普通删除清独有文件与 Workspace；项目删除先转存聊天文件再转普通。
- 授权：S2a 已接入可撤销内置文件/Workspace 写入和经 Swift 检查且 checkpoint 成功的离线 Shell 自动执行；clipboard_read 与已就绪 environment_prepare 结果契约已修正。外部持续授权、MCP 信任、Memory 自动写入和实际安装自动执行仍未实施，完整 S2 未完成。
- 抽屉/顶栏：项目默认折叠、最近 5 条并去除单独置顶重复，普通最近 20 条；查看更多复用完整列表；项目详情合并进唯一省略号按钮，项目切换来自侧栏。
- iSH：Shell 组默认关闭，Agent 拿不到 shell 工具，内核从未被触发；rootfs 未预装任何文档库；file_publish 不支持 PPTX；从未在真机执行。
- UI：设置入口被历史触摸区遮挡的问题已修复并通过三种外观回归。其余仍有约 22 种自定义 row、18 种卡片外观；FamiliarChatMessageViews.swift 2762 行、FamiliarSettingsHubView.swift 1726 行；两套运行记录 UI；技术字段直接给普通用户看。
- 测试执行：当前 iPhone 18 Pro 可执行定向单测；早期 UI 失败后的 xcresult 汇总曾无进展 180 秒并被 watchdog 终止；后续修复引用保存与设置触摸区，最终 3 项 UI 用例及结果包正常通过。S0 其余测试与所有者验收仍未补齐。

## 验收

本次 S1 的真实服务、截图所有者过目与真机验收分别记录在 docs/15-s1-search-acceptance.md；历史编译证据不代替本次测试。

## 本切片验证边界

所有者明确要求“构建通过就行，真机视觉我验收”。本切片只构建 App 与测试目标，不执行 Simulator 测试、启动或截图。构建结果与未执行项目见 docs/16-work-scope-convergence.md；前述 S1 测试结果只属于 S1 基线，不能视为本次架构变更的运行通过。

指定 arm64 iPhone 18 Pro 的 build-for-testing 已成功（exit 0，TEST BUILD SUCCEEDED，最终日志无 warning/error）。静态差异、双语文案语法/键一致性和测试清单检查通过；未运行用例，真机视觉待所有者验收。

# 现行产品与工程决策

只保留仍有效且需要解释的决定；代码现状见 state，普通变更交给 Git。2026-10-20 的 Telegram 对齐决定覆盖早期 ChatGPT／Beautiful UI 参考和旧主题。

| 决定 | 理由与约束 |
|---|---|
| Telegram iOS UI；AI 问答为主入口 | 使用成熟消息交互，统一布局／动效／浅深主题；保留 AI 能力和 Familiar 品牌 |
| 原生三 Tab；普通 Chat 不要求 Project | 保持快速提问入口，长期共享内容由显式 Project 承担 |
| iOS 26 与公开 Liquid Glass | 只维护当前平台，不新增 iOS 18 回退或私有透镜 |
| BYOK、设备直连、无 Familiar 账户与后端 | 密钥放 Keychain，用户选择实际 Provider 与网络目的地 |
| 单 Agent + Lazy Tools | 不增加 Router、Planner、多 Agent 或背景调度 |
| Swift 强制能力和授权 | 模型、Skill、网页、MCP annotations 和系统入口都不能自授权 |
| 按后果分级授权 | 可撤销本地写入留回执／Undo；外部操作能力级授权；删除和未信任 MCP 每次询问 |
| Chat / Project / File 是产品对象 | Workspace、Environment 为基础设施，Run 为历史，Memory 为系统行为 |
| File / FileVersion 和完整 work scope | 身份不随文件名或 hash 合并，跨范围移动复制重绑且不携带旧授权 |
| 内置 iSH/Alpine，文档库预装 | 复用成熟库生成 Office／PDF；写前 checkpoint，scope 隔离，失败如实记录 |
| 单一当前 schema、无历史链 | 业务代际重置只按既有一次授权执行，后续打开失败保留数据进入恢复 |
| 内存流式与持久检查点分离 | 避免逐 token 广泛 invalidation；历史窗口不限制业务上下文 |
| 本地非持久 WebKit | 本地资源渲染富文本，禁止自动远程图片和页面脚本出站 |
| 图片按当前模型能力处理 | 支持图片的 Provider 接收用户图片；文本模型走 Apple Vision 证据，不自动切模型；FastVLM 非产品路径 |
| Speech 只形成可编辑文本 | 不创建持久录音文件；旧回调不能覆盖其他草稿 |
| 真机视觉由所有者验收 | 代理编译不代表运行／手势／性能通过；不启动 Simulator 或截图 |

详细规则分别在 [架构](02-system-architecture.md)、[隐私](05-local-data-and-privacy.md)、[UI](03-ui-ux-design.md) 与 [验证](11-verification-and-release-checklist.md)。

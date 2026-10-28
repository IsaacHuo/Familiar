# Familiar 架构约束

本文记录设计边界与理由；代码现状、模块和数据流见 [ARCHITECTURE](../state/ARCHITECTURE.md)。

## 责任边界

Product UI → Domain → Context / Runtime → Tools / Policy → Services → Persistence。

- UI 负责原生导航、呈现及用户输入，不直接执行 EventKit 或代替审批。
- 单 Agent Loop 只理解 typed definitions、calls、results、policy 和 events；Apple、Web、MCP、iSH 留在适配器后。
- Context Compiler 是每次模型请求的统一入口：冻结当前工作范围、FileVersion 引用、Skill、Memory、Evidence、历史和工具。Provider 只编码协议，不独立追加产品指令。
- Run 记录已发生的事实、写状态和产出；不增加 Router、Planner、任务调度或多 Agent。
- 数据、审计与可重建缓存职责分开，采用一个当前 store；不新增历史兼容链。

## 工作范围与 Files

project(id) 与 conversation(id) 的 scopeKey 包含类型；即使 UUID 相同，也不能共享文件、环境或授权。普通 Chat 使用全局默认及自身 Files、Workspace、Environment、Memory，只有显式 global Memory 跨普通聊天。

File 身份独立于名称、路径和 hash。FileVersion 不可变，保留字节、格式、提取、hash 与 provenance；同名或同字节不跨范围合并。导入、保存网页、生成文档和 Shell Outputs 使用同一 Files 体系。web_fetch 仍是 Evidence，显式保存才成为 File。

删除普通 Chat 清其独有数据；删除项目 Chat 保留共享文件。移动先复制关联版本并重绑附件，清摘要与旧范围授权；删除 Project 先为保留聊天转存关联文件，再转为普通 Chat。

## 工具与授权

preflight → Policy → 必要审批 → 执行前复核 → journal → execute → persist / compensate。能力启用、系统许可、用户写授权相互独立；模型、系统入口、远程内容和 Skill 均不能创建授权。

- 普通只读自动执行，保留 scope 和系统权限检查。
- 可逆内置文件／Workspace 写入、已启用记忆写入、配置源声明式依赖安装及预检通过且已有 checkpoint 的离线 Shell，自动执行并留真实回执和会话 Undo。
- 外部创建／更新、通知、剪贴板写入、保存相册、闹钟安排、Skill 安装及已信任 MCP 首次询问，默认“始终允许此类”。持续授权匹配 scopeKey + capabilityID + capabilityVersion，不按参数 hash 匹配。
- 删除、闹钟取消、未信任 MCP 每次询问。MCP 信任为按服务器的用户设置；远端 annotations 不授予权限。
- once 有效期十分钟；session 要求会话及参数匹配；always 有效期365天且可撤销。无 scope 不可持久授权。

## 执行与恢复

documents 懒加载组承载 shell_execute、environment_prepare、environment_status、file_publish；不与旧 shell 组并存。声明式安装只来自 Swift 构造和配置源；已就绪返回 unchanged，不制造写回执。

Shell 限定当前范围，写前 checkpoint，成功捕获 Outputs 并 best-effort 校验。校验失败保留真实文件及失败标记，不能声称已验证。预装库不在设备重复下载；准备可幂等重试，不承诺字节续传。终端 watchdog 不计 prepare 时间。

超时、取消、预算耗尽与权限拒绝有真实结果；不确定写入不自动重放。检查点用于审计和中断识别，不等于跨重启续跑。后台执行和新本地模型均不在本轮范围。

## 呈现与持久化

流式文本保持内存态，只在明确检查点和终态持久化。历史富负载按窗口读取，发送／编辑／分支／导出使用完整业务历史接口。动画和几何不触发数据库读取或全时间线重建。

文本通过本地非持久 WKWebView 或原生 TextKit 呈现；代码、表格、公式与图示保留可访问结构。只使用公开 Liquid Glass API，降低透明度／增强对比度保留实色分支。

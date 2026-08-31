# Familiar 下一版执行计划：DeepSeek + Native Tools + iSH

> 实际能力与验证证据以 `state/CURRENT.md`、`state/ARCHITECTURE.md` 为准。本文只记录本版固定范围和验收边界。

## 1. 固定产品架构

```text
Chat / Project Workspace
          ↓
   Swift Agent Runtime
          ↓
ModelProvider + ToolRegistry
   ↓          ↓          ↓
DeepSeek   Native Tools   ShellTool
  BYOK     iOS Frameworks    ↓
                       ShellPolicy
                            ↓
                       iSH / Alpine
```

- DeepSeek BYOK 是唯一启用的 AI Provider；API Key 只进入 Keychain 和 Provider 实例。
- Core AI、ModelManager 与 Router 源码保留，但不接线、不显示、不验收。
- Native Tool 优先；Shell 只处理原生 Framework 不适合的通用本地计算。
- Chat 是唯一执行界面，Project 是长期 Context Workspace，单 Agent Runtime 是执行内核。
- App 整体按 GPLv3 分发；iSH 源码、补丁、构建脚本、Alpine manifest 与许可随仓库提供。

## 2. Phase 1：Native Tools 与 Workspace 底座

- EventKit 覆盖日历和提醒的查询、创建、修改、完成、删除；写入前只生成结构化预览，批准后才访问和修改系统数据。
- 删除、联网/危险 Shell 与 Environment prepare 只允许一次性授权；离线、Workspace-only、checkpointed Shell 可经动态 preflight 自动执行。EventKit 保存 mutation 前置快照，支持跨重启 Undo。
- Contacts 根据调用参数选择最小字段；Photos 只保存 Workspace 明确输出且使用 add-only 权限；文件只通过用户导入或系统导出/分享流转。
- Workspace 防止路径逃逸和最终 symlink，按 Run 投影不可变 Resource/Attachment 为 Shell 只读输入，Outputs 可写，Work 任务结束清理。
- SwiftData 直接使用当前 36 实体的单一 Release Schema；不提供旧测试 store migration，schema 变化时破坏性重建。

## 3. Phase 2：真实 iSH Runtime

- 固定 `OpenMinis/ish-arm64` commit `54ca185b77f170e12fd353fcd7443232f6cb73fd`。
- 固定 Alpine 3.24.0 aarch64，并在准备脚本中校验官方 SHA-256 与签名；rootfs 预装 Python 3、Git、jq、zip/unzip、证书和基础文本工具。
- 生成 arm64 iPhoneOS 与 arm64 iPhoneSimulator XCFramework；生产 target 使用 headless bridge，不接入 Terminal UI 或 Native Offload。
- guest 只看到 `/workspace/files`、`/workspace/outputs`、`/workspace/work`、`/workspace/env`；Keychain、Metadata、Checkpoint、其他 Workspace 和系统敏感数据不挂载。
- Shell 默认断网；联网或危险命令精确审批，依赖安装只能走声明式 `environment_prepare`。socket policy 仍阻止监听、loopback、局域网、link-local、multicast 与 Bonjour，并限制连接数和传输量。
- 执行限制包括 180 秒、16 processes、512 MiB guest memory、1 MiB output、128 MiB 单文件和 500 MiB Workspace。失败、取消、超时或超限恢复 writable checkpoint。

## 4. Phase 3：统一体验与发布收口

- DeepSeek 与最多 40 个 Native/Specialized/Environment/Shell Tools 走同一个 AgentLoop；Runtime 不判断具体 Provider 或 Tool 类型。
- Chat timeline 显示 Shell command、工作目录、网络状态、执行状态、有界 stdout/stderr、Workspace diff、输出文件和 Undo。
- Settings 的 Shell Runtime 页面显示准备状态、rootfs、当前 Workspace 网络开关、资源限制、重置和 GPL/iSH 源码入口。
- 中英文权限、工具、Shell、错误、导出与许可文案保持 key parity；README、PrivacyInfo、第三方清单和 `state/` 只描述已经接线的能力。

## 5. 实现代理验收边界

- 编译 Provider、Tool、EventKit、Workspace、ShellPolicy、bridge fixture、Runtime event 和 migration 测试。
- 校验 strings plist/parity、GPL/iSH/Alpine 供应链、rootfs hash、XCFramework 架构和 `git diff --check`。
- 使用独立 DerivedData 完成 Debug arm64 generic iOS Simulator `build-for-testing` 与 Release generic iOS arm64 build。
- 不启动 Simulator，不使用真实 DeepSeek Key，不调用线上模型；构建成功不等于 AI 效果、系统权限、真实 iSH guest 或 App Review 通过。

## 6. 所有者真机验收

1. DeepSeek Flash/Pro 的认证、模型列表、流式、取消、错误恢复与 Tool Call 质量。
2. Reminder/Calendar 的读写、审批、取消零写入、ToolResult 回填与跨重启 Undo。
3. Photos add-only、Files 导入导出、Contacts、Location、Clipboard 与 Share。
4. 导入 CSV → iSH/Python → Workspace Output → DeepSeek 最终回答。
5. Shell 网络开关、取消、资源限制、失败恢复以及照片、联系人、日历、位置、Keychain 和其他 Workspace 不可见。

真机只修复实际验收暴露的问题，不恢复 Core AI、不增加云 Provider，也不扩展 MCP、Memory、后台执行、多 Agent 或 FamiliarMac Runtime。

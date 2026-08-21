# Familiar 下一阶段执行计划

> 本文描述已确认的未来工作顺序。当前实现状态见 `state/CURRENT.md`；未交付能力不得从本文推断为已实现。

## 1. 阶段目标

下一阶段优先验证普通 iPhone 用户能否让 Familiar 安全、清晰地执行真实动作：

> 使用 DeepSeek 完成文本对话和基础图片识读，查询日历与提醒，按用户授权创建动作，在同一回合检查多张动作卡，并在 App 重启后撤销已执行动作。

Chat 是主要交互与执行 Surface，Project 是长期 Context Workspace。普通聊天与 Project Conversation 共享同一套 Chat Surface、Runtime、视觉证据、授权和动作 Surface；Project 不再以功能 Dashboard 形式扩张。

## 2. 执行原则

1. 所有方向保留在路线图中，但按可工作的层次依次交付，不并行铺开孤立菜单。
2. 当前真实 Provider 验收以 DeepSeek 为主，默认主模型为 `deepseek-v4-flash`；其他 Provider 暂不阻塞本阶段。
3. 信息性运行事件使用轻量状态行；只有写动作使用卡片。
4. 模型不能产生自己的授权。首次授权由用户明确产生，有效 grant 范围内可以免重复询问。
5. 图片能力按当前模型路由；本地 fallback 不产生新的网络目的地。
6. 后台承接不得绕过现有恢复、幂等、授权和审计边界。
7. 每一层完成自动化验证和真机验收后再进入下一层。
8. Memory、Remote MCP 和后台执行在端到端接入 Runtime、Policy、恢复与删除语义前保持隐藏或 Labs。

## 3. 执行起点

动作 Surface、持久授权、跨重启 Undo、Apple Vision fallback、FastVLM 0.5B、统一 Chat/Project Workspace 和 Composer 单次 Skill 选择均已进入当前实现。本文不再重复其实现方案；准确边界和最新验证证据以 `state/CURRENT.md` 与 `state/ARCHITECTURE.md` 为准。

下一阶段只处理尚未完成的真机验收、缺陷硬化、Runtime 能力与发布准备。

## 4. 第一层：真机验证与缺陷硬化

### 4.1 Provider、动作与恢复

- 使用 DeepSeek 真 Key 完成认证、文本流式、取消、错误处理、读工具和写工具闭环。
- 在真机验证 EventKit 权限、零授权零写入、授权范围匹配、重复调用幂等、App 重启后 Undo，以及系统对象被外部修改或删除时的失败呈现。
- 验证进程在系统保存后立即终止等边界；发现数据或授权不一致时优先修复，不扩展新动作类型。

### 4.2 Surface 与无障碍

- 在真机检查读取状态、单卡、多卡 pager、部分成功、失败重试和已撤销终态，确认长回答滚动与草稿切换稳定。
- 完成 VoiceOver、极端 Dynamic Type、Reduce Motion、Reduce Transparency、触觉关闭、中英文和明暗模式验收。

### 4.3 视觉路径

- 验证 Apple Vision OCR、条码、分类、证据 provenance、失败恢复和不跨 Provider 上传。
- 在目标真机验证 FastVLM 下载恢复、哈希、空间不足、Core ML 编译、自动路由、60 秒降级、内存与热表现；根据真实失败硬化，不扩大模型矩阵。
- 记录中文描述、比较和图表问答质量，不根据模型基座预先声明支持程度。

### 4.4 现有能力闭环

- 验证 Web/Artifact、文档/OCR、Speech、Share、Deep Link、通知、Spotlight、App Intents 和 Widget/Control 的真机主路径与失败恢复。
- 验证 Composer 选择的 Skill 只影响下一次 Run，immutable snapshot 和 tool scope 与审计记录一致。
- 只有验收暴露的缺陷进入本层；Skill 导入、分发和 Project binding 属于后续能力。

### 4.5 完成条件

- 实际执行单元测试和 8 场景 Agent benchmark；仅编译测试产物不算测试通过。
- 所有者完成 DeepSeek、EventKit、视觉、Surface 与系统入口真机验收。
- 发现的问题修复后重新执行对应的最窄验证，并把最新证据写入 `state/CURRENT.md`。

## 5. 第二层：未完成的 Runtime 能力

按以下顺序交付，每项都必须贯通 Runtime、Policy、审计、恢复与删除语义：

1. instruction-only Skill 导入、预览、安装、卸载与 Project binding；继续保持显式调用和 tool scope 收窄。
2. global/project/conversation scoped Memory；先提供显式读写与删除，自动写入默认关闭。
3. Remote HTTPS Streamable HTTP MCP Client；所有工具继续经过 Familiar Policy，不引入本机 Server 或任意代码执行。
4. iOS 26+ 后台承接；iOS 18–25 明确降级，不承诺可靠 cron，恢复与幂等验证先于扩大入口。

## 6. 第三层：Provider 与发布准备

- DeepSeek 主路径稳定后，按协议族扩展真实 Provider 兼容矩阵，不用模拟结果代替真实认证、流式和工具冒烟。
- 开发阶段继续使用可破坏性重建的 `FamiliarDevelopment.store`；首次公开发布前冻结版本化 schema，之后每次 schema 变化都提供旧版本 fixture、覆盖安装、磁盘迁移和失败恢复测试。
- 公开分发前完成许可证、隐私披露、数据删除、API Key、模型下载来源与哈希审查。
- 将 Debug、Release、Simulator、实际测试执行和真机验收分别记录，不用其中一项替代另一项。

## 7. 暂不进入当前层

- 多 Agent、Subagent、Agent Graph。
- Shell、任意代码执行或本机 MCP Server。
- 自动把私密图片切换发送到另一 Provider。
- Familiar 托管视觉服务或托管额度。
- FastVLM 1.5B/7B、多模型自动下载和未经验证的动态最新版。
- 公开市场分发或商业使用；用途变化时重新审查全部许可证和隐私边界。

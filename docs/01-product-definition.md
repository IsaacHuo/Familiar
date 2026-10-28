# Familiar 产品定义

Familiar 是面向 iPhone 的原生 AI 问答 App，采用 Telegram iOS 的视觉和交互。用户通过自己的模型凭据直接连接 Provider，聊天与文件保存在本机。

## 产品对象

- Chat 是提问、阅读、输入和执行反馈的入口，普通聊天不需要 Project。
- Project 是可选的长期工作范围，共享指令、资料与配置。
- Files 统一管理导入、显式保存和生成的版本化文件。
- Memory 是可检查、可关闭的系统行为；Run 是执行历史，不增加一级导航。

## 当前目标

先完成聊天页，再对齐聊天首页、Files、Project、设置及辅助页面。以固定 Telegram 源码逐项核对布局、排版、状态、手势、动效、配色和背景，保留 Familiar 品牌与文件／聊天／设置三个入口。

用户和 AI 都使用消息气泡。AI 回答继续支持流式、Markdown、代码、表格、公式、Mermaid、来源和后续问题；工具进度、回执、Undo、审批和澄清保持真实且可检查。长回答不另立宽屏阅读样式。

完整目标见 [UI 设计](03-ui-ux-design.md) 与 [对齐账本](telegram-ios-ui-checklist.md)，实现和验证状态只查 [当前状态](../state/CURRENT.md) 与 [PLAN](../PLAN.md)。

## 保留能力

BYOK 与已接入外部 Provider 登录、本地历史、Project、canonical File/FileVersion、单 Agent Lazy Tools、Context Compiler、Skills、Memory、Web、Apple 原生工具、MCP、内置 iSH/Alpine 文档生成、图片输入与语音转写。能力可用性与权限由 Swift 判断，模型不能自授权。

不增加 Familiar 账户、业务后端、订阅、云同步、社交关系、通话、频道、多 Agent、后台执行或跨重启续跑。最低 iOS 26；不增加旧系统回退。

## 成功条件

- 同一界面只有一套现行设计，目标能追溯固定源码及必要适配。
- 发送、阅读、输入和返回保持稳定；草稿、历史、文件归属与审批规则不因 UI 对齐改变。
- App 与测试目标编译通过；真实服务、系统权限、性能和所有者真机视觉另行验收。

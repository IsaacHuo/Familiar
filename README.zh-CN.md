# Familiar

面向 iPhone 的原生 AI 问答 App。当前重点是逐项对齐 Telegram iOS 的视觉与交互，优先聊天页；最终视觉由所有者真机验收。

[English](README.md) · [网站](https://isaachuo.github.io/Familiar/) · [隐私](https://isaachuo.github.io/Familiar/privacy/) · [支持](https://isaachuo.github.io/Familiar/support/)

## 能力与边界

- BYOK／已接入外部Provider登录；凭据保存在设备Keychain，请求直接发往所选服务。
- 本地聊天历史、流式回答、Markdown／代码／表格／公式／Mermaid、图片和语音转写。
- 可选Project共享指令与资料，统一File/FileVersion、范围隔离的Memory与Skills。
- 单Agent Lazy Tools连接Web、Apple原生能力、MCP和内置iSH/Alpine文档生成。
- Swift代码强制授权；可逆本地写有回执和Undo，外部影响需有效授权，删除每次确认。

最低iOS 26，Swift 6、SwiftUI／UIKit、SwiftData、URLSession、WebKit。保留文件／聊天／设置三个入口。没有Familiar账户、业务后端、云同步、订阅、多Agent、系统后台执行或跨重启续跑。真实服务和设备性能尚需单独验收，源码或编译不等于运行通过。

## 开发

使用支持项目SDK的Xcode打开familiar.xcodeproj，scheme Familiar。第三方AnyDoc和iSH二进制及本地Skill依赖位于Vendor；依照现有Scripts维护，不修改签名或删除数据。

默认在main开发。编译使用具体arm64 Simulator destination执行build-for-testing；generic Simulator可能选择不受iSH支持的x86_64。当前代理只编译App与测试目标，不启动Simulator或执行测试。详细规则见[AGENTS](AGENTS.md)和[验证清单](docs/11-verification-and-release-checklist.md)。

## 文档

先读[当前状态](state/CURRENT.md)和[架构](state/ARCHITECTURE.md)，再看[当前批次](PLAN.md)。[文档索引](docs/README.md)区分产品设计、代码事实与历史证据。

Telegram参照固定在f1dd7a2；[320项对齐账本](docs/telegram-ios-ui-checklist.md)按源码、实现、编译和真机状态推进。现行设计见[UI规范](docs/03-ui-ux-design.md)。

## 许可证与数据

项目使用[GPL-3.0](LICENSE)。第三方归属见Familiar/Resources/ThirdPartyNotices.txt及iSH notices。运行时不下载聊天壁纸，Markdown不自动请求远程图片。使用第三方模型服务可能产生费用，数据目的地见[隐私约束](docs/05-local-data-and-privacy.md)。

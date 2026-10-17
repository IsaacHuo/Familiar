# 终端 watchdog 不得计入 iSH 准备时间

## 症状

冷启动后第一次打开 Terminal：rootfs 正在准备（解包/启动/探测）时，终端会话在准备完成前就被 180 秒 watchdog 判定超时，显示 “Stopped: session time or storage limit reached”，用户看不到可用的终端。

## 根因

`FamiliarTerminalView` 的 `start(files:)` 在调用 `bridge.openTerminal` **之前**就创建了 180 秒 deadline 的 watchdog；而 `openTerminal` 内部先 `await prepare()`（首次为冷准备，解包 35–55 MiB rootfs、boot、Python 探测）。准备时间被计入会话时限。

## 修复

watchdog 改为在终端流的**第一个事件**（`.started`，即 guest 会话真正建立）之后才创建；准备阶段只显示 “Preparing Linux…”。见 `Familiar/Presentation/FamiliarTerminalView.swift` 中 `didStartWatchdog`。

## 备注

同类陷阱适用于任何“先连接、后计费”的超时逻辑：deadline 必须锚定在真实资源就绪之后，而不是发起准备之前。

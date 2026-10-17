# Simulator 测试宿主卡死

## 症状

`xcodebuild test-without-building` 输出停在 `Writing result bundle at path:`，3 分钟内没有任何测试用例开始。之前一次运行报 `Mach error -308 (ipc/mig) server died`。随后 `simctl spawn` / `simctl launch` 同样无响应。

## 根因（已确认部分）

问题绑定在具体的 Simulator 设备实例（iPhone 17，iOS 27 runtime）和 CoreSimulator 服务状态上，与代码无关：同一构建产物在另一台从未使用过的 iPhone 18 Pro Simulator 上可以安装并启动 App 进程。宿主侧还残留了来自第一次卡死运行的 `testmanagerd` 进程。

## 处理

1. 任何测试或 Simulator 命令都放到后台运行并写日志，3 分钟无进展即判定卡死。
2. 结束残留进程：`pkill -9 -f xcodebuild`、`pkill -9 -f simctl`、残留的宿主 `testmanagerd`。
3. `xcrun simctl shutdown all`，再 `killall -9 com.apple.CoreSimulator.CoreSimulatorService`。
4. 仍卡死时换一台未使用的 Simulator 设备，不要清除原设备数据，也不要反复重试同一台。
5. 系统没有 `timeout`，用 `perl -e 'alarm N; exec @ARGV' <cmd>` 给单条命令加上限。

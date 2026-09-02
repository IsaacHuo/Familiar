# 逐套件发布测试会因反复安装而出现启动期 flake

## Symptom

`Scripts/run-release-test-suites.sh` 跑到中途某个套件失败，退出码 65，但**没有任何断言失败**。失败信息是启动期的，形态有两种：

    Test crashed with signal abrt before establishing connection.

    Failed to create a bundle instance representing
    '.../Library/Caches/com.apple.containermanagerd/Dead/temp.XXXXXX/.../Familiar.app/PlugIns/FamiliarTests.xctest'.
    Check that the bundle exists on disk.

每次失败的套件都不同（先是 `FamiliarPersistenceReleaseTests`，后是 `FamiliarNativeOutputToolTests` 之后的那一个），与改动内容无关。

## Investigation

- 路径里的 `com.apple.containermanagerd/Dead/temp.XXXXXX` 说明测试要加载的 App 容器**已经被系统回收**，测试进程去读一个正在被删除的 bundle。这不是代码问题。
- 单独重跑失败的那个套件全部通过（例如 `FamiliarPersistenceReleaseTests` 5/5）。
- 该脚本对 29 个套件各发起一次 `xcodebuild ... test-without-building`，也就是在同一个 Simulator 上**反复安装与卸载同一个 App 29 次**。回收与下一次安装存在竞争。
- 改为单次调用跑完整个 target 后稳定通过：204 tests / 29 suites。

## Root Cause

逐套件调用带来的重复安装/回收竞争，属于 Simulator 与 `containermanagerd` 的环境行为，与被测代码无关。

## Fix

需要一次跑完全部测试时，优先用单次调用整个 target：

    xcodebuild -project familiar.xcodeproj -scheme Familiar -configuration Debug \
      -destination 'platform=iOS Simulator,id=<arm64-UDID>' \
      -derivedDataPath <已构建的目录> \
      -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
      COMPILER_INDEX_STORE_ENABLE=NO -parallel-testing-enabled NO \
      -only-testing:FamiliarTests test-without-building

逐套件脚本仍然有价值：它能在某个套件让 test host 崩溃时把影响隔离在该套件内（见 `logs/swiftdata-test-fixture-must-retain-modelcontainer.md`）。因此两种方式互补，不要删除脚本。

## Verification

单次调用整个 target 通过 204/204；同一改动下逐套件脚本在不同位置失败两次，重跑即过。

## Remaining Issues

遇到逐套件运行失败时，先看失败是否发生在 **establishing connection 之前**或路径中是否含 `containermanagerd/Dead`。若是，判定为环境 flake：单独重跑该套件确认，再用单次调用整个 target 复核，**不要据此修改代码**。只有出现真实断言失败（形如 `Expectation failed:`）才是代码问题。

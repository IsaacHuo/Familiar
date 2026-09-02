# `generic/platform=iOS Simulator` 会解析成 x86_64 并导致 iSH 链接失败

## Symptom

执行 `xcodebuild -destination 'generic/platform=iOS Simulator' ... build` 时，输出数百条同形警告并最终 `BUILD FAILED`，形如 `ld: warning: ignoring file 'libFamiliarISHRuntime.a(ISHKernel.o)': found architecture 'arm64', required architecture 'x86_64'`，最后以 `clang: error: linker command failed with exit code 1` 结束。没有任何 Swift 源码诊断，容易被误判为代码错误。

## Investigation

- 全部警告都指向 `libFamiliarISHRuntime.a` 的成员，且都是同一句「有 arm64、要 x86_64」。
- `Vendor/ish-arm64` 只提供 arm64 device / arm64 simulator 切片，本项目刻意不构建 x86_64。
- `generic/platform=iOS Simulator` 不指定架构，xcodebuild 在这台机器上把它解析成了 x86_64，于是链接器找不到可用切片。
- 追加 `arch=arm64` 不被接受：`xcodebuild: error: Unable to find a destination matching the provided destination specifier`。
- `xcodebuild -showdestinations` 显示可用的 Simulator destination 只有具体设备条目，形如 `{ platform:iOS Simulator, arch:arm64, id:<UDID>, OS:26.5, name:iPhone 17 Pro Max }`。

## Root Cause

构建命令没有固定架构，而项目的第三方静态库只有 arm64。这是构建调用方式的问题，与源码无关。

## Fix

验证构建必须使用具体的 arm64 Simulator destination：

    xcodebuild -project Familiar.xcodeproj -scheme Familiar -configuration Debug \
      -destination 'platform=iOS Simulator,id=<arm64-simulator-UDID>' \
      -derivedDataPath <独立目录> \
      -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
      COMPILER_INDEX_STORE_ENABLE=NO build-for-testing

用 `xcodebuild -showdestinations` 取当前机器上 `arch:arm64` 的 Simulator UDID，不要硬编码——UDID 随 Simulator 重建而变。`build-for-testing` 不会启动 Simulator，符合「默认不启动 Simulator」的项目约束。

## Verification

换成具体 arm64 destination 后 `** TEST BUILD SUCCEEDED **`，App、Share Extension、Widget 与两个测试 target 全部完成编译，链接警告消失。

## Remaining Issues

若某次构建出现成片的「found architecture 'arm64', required architecture 'x86_64'」，先怀疑 destination，不要去改代码。

# 测试夹具不持有 `ModelContainer` 会让 test host 以 signal trap 崩溃

## Symptom

新增的 SwiftData 单元测试全部失败，失败信息只有一句 `Test crashed with signal trap.`，**没有任何断言失败**。xcodebuild 输出里 test host 反复「Restarting after unexpected exit, crash, or test timeout」，每次重启只跑下一个用例又崩，最后一次重启后剩余用例为空，于是日志里出现极具误导性的一行：

    ✔ Suite "Familiar Memory" passed after 0.004 seconds.
    ✔ Test run with 4 tests in 2 suites passed

但退出码是 65，末尾的 `Failing tests:` 列出全部 4 个用例。**不要只看 `Test run with ... passed` 那一行**，它统计的是最后一次重启后的结果。

## Investigation

- 4 个用例的测试体互不相同（去重、作用域搜索、排序、写入边界拒绝），却全部崩溃，说明问题不在断言，而在共用的准备代码。
- 崩溃信息不含 Swift 运行时诊断，也没有 `.crash` 诊断文件，`xcresulttool` 里只有 `Test crashed with signal trap.`。
- 唯一被 4 个用例共享的一行是夹具写法：

      let context = try FamiliarTestStore.make().mainContext

- `FamiliarTestStore.make()` 返回 `ModelContainer`。上面这行没有把它绑定到任何变量，容器在语句结束后即可释放，而 `mainContext` 被继续使用。
- 仓库里既有的通过用例全部是另一种写法：先把容器绑定到局部变量，再取 `mainContext`。

## Root Cause

`ModelContext` 不持有它的 `ModelContainer`。容器被释放后底层存储随之销毁，后续对该 context 的 fetch 或 save 落在已失效的存储上，进程直接 trap，而不是抛出 Swift 错误——所以看不到任何断言失败。

## Fix

夹具必须在整个用例期间持有容器：

    let container = try FamiliarTestStore.make()
    let context = container.mainContext

不要写成 `try FamiliarTestStore.make().mainContext`。

## Verification

改成持有容器后，同 4 个用例全部通过（`Familiar Memory` 4/4），扩大到 5 个 suite 共 46 项也全部通过，且不再出现 test host 重启。

## Remaining Issues

这是复发问题：`state/CURRENT.md` 的 2026-08-28 条目已记录过一次「测试夹具未持有 SwiftData `ModelContainer`」。新增任何 SwiftData 测试时先检查这一行写法。另外，凡是 xcodebuild 退出码非 0，都不要相信 `Test run with ... passed` 摘要，直接看末尾的 `Failing tests:`。

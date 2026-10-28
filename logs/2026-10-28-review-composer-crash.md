# 新建会话时输入框布局崩溃

## 症状与证据

审核 1.0 (2)，iPad Air 11-inch (M3)、iPadOS 27.2 (24B115)，点击会话页的纸笔按钮后崩溃。三份原始 `.ips` 位于所有者 Downloads：9232CCD7-CA08-4FA1-A72C-EBE137CC05F0、FB70D1F9-F78C-43E5-8322-C92413307AC3、86DFAAE1-4D39-4F8C-A816-64C5A1119B6E。

三份均为主线程 `EXC_BAD_ACCESS / SIGSEGV`，访问地址 `0x18`；不是 watchdog、权限说明缺失或 SwiftData 异常。

已核对发布二进制与本机归档 dSYM UUID 均为 `ADCC51A5-49D3-3C51-9413-684ABE81D7E6`。归档位于 `~/Library/Developer/Xcode/Archives/2026-10-19/Familiar 2026-10-19, 23.27.xcarchive`。

关键栈及应用偏移：

```text
_StringObject.getSharedUTF8Start()
_StringObject.sharedUTF8.getter
_stringCompareInternal(_:_:expecting:)
Familiar + 6732092 → FamiliarComposerNativeTextView.layoutSubviews()
                    FamiliarComposerTextView.swift:210
Familiar + 6732556 → @objc FamiliarComposerNativeTextView.layoutSubviews()
UIKit layout → CoreAnimation commit → main run loop
```

定位命令（地址按 Mach-O 首选加载地址归一化）：

```sh
xcrun dwarfdump --uuid '<archive>/dSYMs/Familiar.app.dSYM/Contents/Resources/DWARF/Familiar'
xcrun atos -arch arm64 -o '<archive>/dSYMs/Familiar.app.dSYM/Contents/Resources/DWARF/Familiar' -l 0x100000000 0x10066b93c 0x10066bb0c
```

应用帧符号化副本保存于 `/tmp/FamiliarReviewEvidence/`，保留原始日志。系统 UIKit 27.2 的无名帧未伪造符号；本机 dSYM 只补全 Familiar 应用帧。

## 原因判断

第 210 行比较 `lastCaretLayout` 和 `text`。反汇编从实例字段读取缓存字符串后进行比较；三份寄存器证据均显示缓存一侧为 `(0, 0)`，另一侧为空字符串 `(0, 0xe000000000000000)`。全零不是有效的 Swift String 表示。子类指定初始化器的反汇编明确写入正确的空字符串标记。

生产入口 `FamiliarComposerNativeTextView(usingTextLayoutManager: false)` 被导入成 Swift convenience initializer，SDK 头文件实际声明为 Objective-C 类工厂 `+textViewUsingTextLayoutManager:`。发布版反汇编也确认为类方法调用。证据高度指向该工厂在审核系统上创建子类时没有执行 Swift 子类指定初始化；没有相同系统的运行时复现，不能把平台内部执行路径视作已直接观测。

## 修复与回归方式

输入框及原生消息正文均显式创建 `NSTextStorage → NSLayoutManager → NSTextContainer`，调用具体 Swift 子类的 `init(frame:textContainer:)`。创建期间保持 storage 存活，之后由 text view 持有 TextKit 1 对象图。输入框布局使用一次非空文本快照，检查 UTF-16 选区边界并阻止重入滚动。

回归覆盖生产 UIViewRepresentable 创建与挂载、首次聚焦、空／多行／中文组合输入、反复销毁重建、子类默认值与占位标签、TextKit 1 对象关联。编译和真机结果分别登记在根 PLAN；没有执行过的测试不得写成通过。

所有者需要使用新发布构建在 iPadOS 27.2 上复验，并做 iPhone 回归。当前编译环境只有 iOS 27.0／27.1 Simulator，不能替代原审核系统的设备证据。

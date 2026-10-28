# S1 历史执行证据

仅对应2026-10-17基线，不覆盖后续架构或UI变化。当前验收要求见[统一清单](../11-verification-and-release-checklist.md)。



- 构建：最终 arm64 `build-for-testing` 已通过，具体 arm64 iPhone 18 Pro Simulator（1041DD9D-AC70-4DDD-9D34-52514C3E491F），任务 DerivedData `/tmp/familiar-s1-20261017`。
- 定向测试：79 项 / 7 suites 真实执行通过，零失败/零跳过；结果 `/tmp/familiar-s1-final-unit.xcresult`。覆盖最终 block 的身份、正文、hash、新 ModelContext 重读与唯一来源。
- WebKit：`testRedirectAliasesRenderTwoChipsWithOneSourceNumber` 真实执行通过，DOM 中两个角标均为编号 1、相同最终 URL；日志 `/tmp/familiar-s1-render-check.log`。该组合运行后续 UI 用例失败，不能把整个组合运行标为通过。
- 生产页面：浅色、深色、大字体 3 项真实执行通过，零失败/零跳过；结果 `/tmp/familiar-s1-final-ui.xcresult`。核对 Chat 角标、唯一来源 Sheet、返回阅读位置，以及 Chat → Settings → Advanced → Web Search 路径。
- 截图：12 张已保存；回答、来源及搜索设置的 9 张核心截图已由代理检查，所有者过目独立待办。核对页 `/Users/yingwu/.codex/visualizations/2026/10/17/01a1493d-e020-75a2-9daa-10fb7e8359ca/familiar-s1/review.md`。
- 静态检查：`git diff --check` 与测试清单核对通过（最终结果收尾时更新）。


## 未完成与复用入口

FamiliarWebLiveTests/testS1DeepSeekTavilyTwentyQueries 的 s1Queries 是20条查询的唯一来源，中英各10条。该完整真实服务链当时因缺 DeepSeek Key 未执行／skip，全部相关性与引用支持度仍待审阅；不可沿用适配器两条Tavily请求通过替代。Key不写源码、CLI、日志或附件。

当时 Tavily 宿主直连三次200、Simulator中英适配器两请求通过；DDG使用全球区域，Bing不推断market，Tavily不附country/language。中文旧转载结果不能证明Agent查询质量已验收。搜索语言不等于搜索国家，详见[排障记录](../../logs/search-language-is-not-search-country.md)。

UI runner 曾在失败后的 xcresult 汇总阶段180秒无进展并被停止；缺Info.plist的结果不计成功。修正夹具和设置入口后，最终三项UI结果独立通过。没有以清空设备或修改签名解决。

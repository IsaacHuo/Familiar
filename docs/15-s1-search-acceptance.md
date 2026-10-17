# S1 搜索收口验收

日期：2026-10-17。实现、测试执行、真实服务、截图过目、真机签字分别记录。完整完成条件以根目录 PLAN.md 为准。

## 实现边界

已实施：Key 原服务保存与校验版本、实际结果数量、共享 deadline、失败可重试、严格引用列表与重定向引用归一。既有搜索排名、中文解码、压缩处理与首轮工具暴露保留。最终 checkpoint 同步更新已存在的 ResponseBlock 正文与 hash，保持原身份。没有新增依赖、数据库实体或工具种类。

## 执行证据

- 构建：最终 arm64 `build-for-testing` 已通过，具体 arm64 iPhone 18 Pro Simulator（1041DD9D-AC70-4DDD-9D34-52514C3E491F），任务 DerivedData `/tmp/familiar-s1-20261017`。
- 定向测试：79 项 / 7 suites 真实执行通过，零失败/零跳过；结果 `/tmp/familiar-s1-final-unit.xcresult`。覆盖最终 block 的身份、正文、hash、新 ModelContext 重读与唯一来源。
- WebKit：`testRedirectAliasesRenderTwoChipsWithOneSourceNumber` 真实执行通过，DOM 中两个角标均为编号 1、相同最终 URL；日志 `/tmp/familiar-s1-render-check.log`。该组合运行后续 UI 用例失败，不能把整个组合运行标为通过。
- 生产页面：浅色、深色、大字体 3 项真实执行通过，零失败/零跳过；结果 `/tmp/familiar-s1-final-ui.xcresult`。核对 Chat 角标、唯一来源 Sheet、返回阅读位置，以及 Chat → Settings → Advanced → Web Search 路径。
- 截图：12 张已保存；回答、来源及搜索设置的 9 张核心截图已由代理检查，所有者过目独立待办。核对页 `/Users/yingwu/.codex/visualizations/2026/10/17/01a1493d-e020-75a2-9daa-10fb7e8359ca/familiar-s1/review.md`。
- 静态检查：`git diff --check` 与测试清单核对通过（最终结果收尾时更新）。

## 真实 DeepSeek + Tavily

入口：`FamiliarWebLiveTests/testS1DeepSeekTavilyTwentyQueries`。固定查询以该测试内 `s1Queries` 为唯一来源，中英文各 10 条，覆盖版本/发布日期、官方技术资料、中文正文、近期公告和多来源比较。

DeepSeek Key 从当前 Simulator Keychain 读取；Tavily Key 可从 Keychain 或所有者提供的 0600 临时文件读取（测试环境只传文件路径）。缺少任一可用凭据时明确 skip。不会把 Key 写入源码、CLI、测试附件或日志。每条回执保留 query、实际模型、耗时、工具序列、搜索服务、真实错误代码、正文答案、引用 URL 与未知引用；相关性和引用正文支持度需逐条审阅，自动断言通过不代表内容审阅完成。

| 查询 | 真实运行 | 相关性审阅 | 引用内容审阅 |
|---|---|---|---|
| 01 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 02 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 03 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 04 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 05 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 06 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 07 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 08 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 09 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 10 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 11 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 12 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 13 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 14 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 15 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 16 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 17 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 18 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 19 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |
| 20 | 未执行：缺 DeepSeek Key | 待审阅 | 待审阅 |

## Simulator 执行限制

所有验证均使用所有者指定的 iPhone 18 Pro。UI runner 在失败用例结束后的 xcresult 收集阶段曾连续 180 秒没有进展，watchdog 已终止本次拥有的进程组；相关结果目录缺 Info.plist，不能解析为成功结果。没有清空 Simulator、修改签名或删除用户数据。UI 截图另存测试沙箱临时目录并复制到核对页目录，避免依赖结果包汇总。修复引用最终保存和设置触摸区之后，最终 3 项 UI 用例及结果包已正常完成；旧失败/中断结果不作为通过证据。

## 搜索语言与地域

- 发现并修复：DDG/Bing 原先按中文自动选中国市场；Context 原先强制中文问题用中文搜索词。现在 DDG 使用全球区域，Bing 不设置推断出的 market，Tavily 不附加 country/language 限定。保留合法问题中的“中国”，不以删词替代语义判断。
- 实际发出的“中国”关键词仍需要原始问题及模型 tool call 才能归因；当前 Simulator 的可读历史中未找到该调用。提示词现明确禁止从输入语言、时区或 Provider 地区推断搜索国家，并允许技术资料使用原文。
- 所有者提供的 Tavily Key 已通过宿主直连三次 200 验证；query 回传与发送一致。中文 Python 最新版查询返回旧版本转载，英文 Swift 查询出现 Apple 官方文档，支持改进检索语言策略；这不代表真实 Agent 查询生成已经验收。
- 同一 iPhone 18 Pro Simulator 的真实 Tavily 中英文适配器测试已通过（2 个搜索请求）；完整 DeepSeek + Tavily 20 条用例因未读到 DeepSeek Key 而 skip，不记作通过。对应初次结果 `/tmp/familiar-s1-final.xcresult` 中其他测试有已修正的夹具问题，该结果不能当作整套回归通过。

## 设置入口的触摸范围

生产页面测试发现，30pt 历史入口透明触摸区原先覆盖顶栏，普通字号下点设置会打开侧栏；大字体下该路径可成功。已将该触摸区的顶部让出 safe-area 和顶栏高度，并给设置按钮增加稳定标识。该修复直接解除 S1 搜索设置进入阻塞，未重做侧栏或导航结构；三种外观的完整路径均已通过。

## 所有者验收

- [ ] 浅色截图过目
- [ ] 深色截图过目
- [ ] 大字体截图过目
- [ ] 真机签字：Key 保存/替换/删除、搜索与降级、来源阅读和返回位置

下一切片为 S2 授权分级，之后 S4 文档交付；S1 缺失的验收不自动转为通过。

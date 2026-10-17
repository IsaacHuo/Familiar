# 搜索语言不能替代搜索地域

## 症状

中文提问的搜索结果偏向中国内容；技术或全球版本问题返回本地转载、旧版本信息。若活动行出现“中国”，需继续区分模型生成的 query 与 Provider 的地区权重，不能仅凭结果推断 adapter 拼接了关键词。

## 已确认原因与证据边界

`FamiliarSearchRequest` 曾将中文映射为 DDG `cn-zh`、Bing `zh-CN` market；ContextCompiler 同时要求中文问题使用中文搜索词。Tavily adapter 原样发送 query，没有追加国家。真实 Tavily 对照请求回传 query 未变；中文版本查询出现旧转载。模型为何在某一次调用中添加“中国”，必须依据该 Run 的原问题与 tool call，不能由上述对照直接证明。

## 修复与验证

DDG 使用 `wt-wt`，Bing 不按语言选择 market；Tavily 不附加 country/language。Prompt 区分回答语言、检索语言与问题地域，原文技术名保留，只有语义需要时才限制国家/城市。不要在 Swift 中删除合法 query 的“中国”。适配器回归同时覆盖全球技术问题和明确中国主题，断言 query 原样传递、无隐含国家参数。真实模型回归还应记录发出的 query，检查全球技术问题是否擅自增加国家限定。

接口依据：[Tavily Search](https://docs.tavily.com/documentation/api-reference/endpoint/search)。

# WeatherKit 的 availability 无法在运行时检查，版本门控会伪造可用性

## Symptom

用户要求查天气时，Agent 没有使用已注册的 `weather_forecast`，而是退回 `web_search` 用网页内容回答。工具明明在注册表里，权限也不需要用户授予。

## Investigation

- `FamiliarDeviceCapabilityProvider.availability(for:)` 对 `.weatherKit` 的实现只有一句 `if #available(iOS 16.0, *) { .available }`。
- App 的最低部署目标是 iOS 18，因此该判断恒为真，`availability` 永远返回 `.available`。
- WeatherKit 的真实可用性取决于三件运行时无法自省的事：`com.apple.developer.weatherkit` entitlement 是否真的随签名下发、Apple Weather 配额是否耗尽、以及网络。App 没有任何公开 API 能查询这三项。
- 结果是：`FamiliarExecutionPolicy` 认为能力就绪并直接执行，`WeatherService.weather(for:)` 在调用时才抛错，该错误经 `FamiliarRuntimeFailure.kind(for:)` 退化成通用运行时错误回灌给模型，模型把它当成“这条路不通”，于是改用网页。

## Root Cause

把「API 在这个 iOS 版本上存在」当成了「这个能力现在可用」。版本门控在最低部署目标之上恒真，等于声称了一件从未验证过的事。真实故障又缺少稳定 code，模型无法区分“WeatherKit 暂时不可用”和“不该用 WeatherKit”。

## Fix

- `.weatherKit` 直接返回 `.available`，并在注释里写明原因：运行时不可自省，不做假检查。
- 新增 typed `FamiliarWeatherError`（`weatherkit_unavailable`，`retryable = true`），`FamiliarWeatherService` 捕获 WeatherKit 抛出的错误并包装，错误文案明确要求不要用网页猜测代替天气数据。
- 错误契约从 Agent Loop 里的硬编码 `as?` 链改为 `FamiliarStructuredToolError` 协议，新增领域错误只需 conform 即可保留稳定 `code`/`retryable`，不会静默退化成通用分类。
- 系统提示补显式领域路由：天气必须走 `weather_forecast`/`weather_history`，只有原生工具明确失败或声明不支持时才用网页，且不得用网页结果伪装成原生数据。

## Verification

arm64 iOS Simulator `build-for-testing` 通过；`FamiliarAppleNativeToolTests` 覆盖了坐标校验与历史区间边界的稳定 code。**真实 WeatherKit 调用未验证**——签名 entitlement 与配额只能在真机上确认。

## Remaining Issues

“查天气退回网页”的根因仍未证实。需要在真机上带 Run trace 复现一次，确认失败是否真的来自 WeatherKit 调用；如果 trace 显示模型在工具成功的情况下仍选网页，那是提示词或工具描述问题，不是本条。

更一般的教训：任何 `availability` 实现如果只做版本判断，都应当怀疑它是否在伪造可用性。宁可返回 `.available` 并让真实故障带稳定 code 暴露，也不要假装检查过。

# `BGContinuedProcessingTask` 只在 iOS 26+ 可用（后台承接的事实修正）

## Symptom

早期文档把 `BGContinuedProcessingTask` 写成 iOS 18 路线的后台执行方案，误导了后台能力的规划与对外承诺（"离开 App 后继续执行"被表述为可保证）。

## Investigation

- 查阅 Apple 文档：`BGContinuedProcessingTask` 于 iOS 26 引入，承接的是用户在前台启动、退出 App 后需要继续的工作，不是可靠 cron。
- iOS 18–25 可用的 `BGProcessingTask` 由系统择机调度，不能承诺精确时间。
- 无后端条件下无法承诺"每天 8 点自动执行 Agent"这类精确计划。

## Root Cause

将新系统 API 的能力版本误记为 iOS 18 基线，导致文档与规划出现事实错误。

## Fix

- 后台按可恢复 Run 设计，不承诺常驻/精确执行：
  - iOS 26+：可条件使用 `BGContinuedProcessingTask`，仍需持久化恢复游标并处理 expiration。
  - iOS 18–25：`BGProcessingTask` 由系统择机执行，网络传输可用合适的 background `URLSession`；Run 必须可中断、可恢复。
- 所有"已计划/后台"表述必须标明执行保证等级：精确 / 尽力 / 需用户继续。
- 本地通知只报告当前进程实际到达的终态，不把通知描述为后台续跑保证。

## Verification

- 所有文档中涉及后台能力的表述已按 iOS 26+ / iOS 18–25 分版修正。
- 当前实现未接入任何 `BGContinuedProcessingTask`；`RunResumeCursor` 数据契约已建但运行时未接线。

## Remaining Issues

- 后续实现后台承接时，先完成恢复数据契约与中断恢复测试，再接入 iOS 26+ 的 continued task。

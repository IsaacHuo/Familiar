# 早期成品化调查结论

历史基线：2026-09-02 至 2026-10-08。本页保存已删除 product-completion 流水中仍有复用价值的结论，不作为当前代码审计或本轮通过证据。完整原始调查、修复和逐日结果由 Git 历史保留。

- Run phase 是展示标签；检查点与中断识别不能被宣传为跨进程续跑。保持不确定写入不重放。
- environment_status 读取 receipt，不应因 guest 准备失败而失去可用性；不为“部分可用”另加无行为区别的 degraded 状态。
- guest 准备共用幂等 flight，工具注册与实际 runtime readiness 分开；失败原因需如实暴露。
- 文件生成成功必须经过真实字节、格式校验、入库与精确版本预览；生成中文 DOCX/XLSX/PPTX/PDF 后仍需各自验收。
- Web 引用必须关联已观察的真实来源，不能把 search 摘要写成 fetch 结果。
- 文件版本回读、Memory 作用域、Project 连续工作和失败恢复应作为端到端验收，当前入口见统一验证清单。
- 2026-10-08 记录：确定性批次50套件366/366；后续367/368有一次时间线失败，同码定向31/31；生产 Chat 13/13，后续两项独立通过。证据目录 /Users/yingwu/Library/Logs/FamiliarVerification/20261008-functional-convergence。这些结果不覆盖后续 work-scope、U6 或 Telegram UI 改动。
- 六个签名设备服务探针当时只编译；系统权限、真实副作用与硬件不能由 fixture 或 entitlement 检查推断通过。

可复用的详细故障仍保留在 [logs](../../logs/README.md)。

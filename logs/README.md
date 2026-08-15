# logs/ — 可复用的调查与调试知识

`logs/` 不是工作流水账。这里只保存**有长期复用价值的 investigation / debugging knowledge**：一次问题调查产生了值得未来开发者复用的知识时，才创建一个 log。

## 什么是好 log

- 一个具体的问题调查，有明确症状、根因、修复和验证。
- 未来遇到同类问题时，读它可以直接避免重走弯路。

推荐单个 log 的结构：

```markdown
# Problem Name

## Symptom
## Investigation
## Root Cause
## Fix
## Verification
## Remaining Issues
```

## 不要记录

- 普通代码修改。
- 成功的 build / 测试通过。
- 每次 Agent 做了什么。
- commit history（Git 已经记录）。
- 很快就能从 Git 或代码中重新获得的信息。
- 无意义的尝试过程（例如"试了 X 不行"却没有结论）。

判断规则：

```text
Will a future developer save time by reading this?

YES → keep the log
NO  → do not write it
```

## 维护规则

- 只追加真正有复用价值的问题；宁缺毋滥。
- 根因未确认前不要写成 log。
- 修复后如果代码自身已经清晰表达（例如命名、注释、测试），且没有易被再次踩中的陷阱，也可以不写。
- 时间、commit、版本信息只作为定位辅助，不要写成流水账。

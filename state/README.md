# state/ — 当前真实状态

`state/` 是整个仓库的 Current Truth：它描述**当前代码实际上是什么样**，而不是我们以后希望它是什么样。

四类信息来源的分工：

```text
docs/   → 我们打算构建什么（设计、规划、rationale）
state/  → 现在实际存在什么（以代码为准）
logs/   → 调试与调查中可长期复用的经验
git     → 普通代码改动历史
```

## 文件

| 文件 | 职责 |
|---|---|
| [`CURRENT.md`](CURRENT.md) | 未来 Agent 进入仓库时优先阅读：阶段、重点、最近完成、进行中、已知问题、下一步 |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 基于当前代码验证的模块、数据层、数据流与依赖关系 |

## 维护原则

1. **内容必须基于当前代码验证。** 写 `state/` 前先查代码（`Familiar/`、`familiar.xcodeproj/project.pbxproj`、测试与构建记录），不要凭记忆或旧文档。
2. **不记录长期愿景。** 设计目标、未来方案和 "为什么这样设计" 属于 `docs/`。
3. **不复制 `docs/`。** 两个目录允许存在差异：`docs/` 描述目标，`state/` 描述现实。不要把两者强行改写成一致。
4. **不记录普通 commit history。** 每次代码改动的细节由 Git 提供。
5. **不记录调试过程。** 只有可复用的调查经验进入 `logs/`。

## 何时更新 state/

判断规则：

```text
Did this change alter how a future agent understands the repository?

YES → update state
NO  → do not update state
```

以下变化**必须**同步更新 `state/`：

- 架构、模块边界或模块职责发生实质变化（新增/删除/合并模块）。
- SwiftData Schema、store 地址或迁移策略变化。
- 工具集合、授权模型、执行策略或 Agent 运行时行为变化。
- 主要功能状态的开关（例如图片发送路径、Project/Resource/Artifact 能力从无到有）。
- 当前开发重点、已知问题或下一步方向变化。

以下变化**不需要**更新 `state/`：

- 普通 UI 调整、小型 bug fix、重命名、内部重构（不改变对外职责）。
- 每个 commit 的实现细节（交给 Git）。

## 读取顺序

```text
1. AGENTS.md / repository instructions
2. state/CURRENT.md
3. state/ARCHITECTURE.md
4. 与当前任务相关的 docs/
5. 与问题相关的 logs/
6. actual code
```

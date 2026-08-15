# SwiftData 旧 store 启动崩溃（NSCocoaErrorDomain 134110）

## Symptom

真机旧安装启动时 App 崩溃，SwiftData 无法打开 store：

```text
NSCocoaErrorDomain 134110
Cannot migrate store in-place
FamiliarConversation.currentModelID missing mandatory destination value
```

旧 store 位置为 SwiftData 默认地址：

```text
Application Support/default.store
```

## Investigation

- 崩溃发生在开发早期：Schema 演进时 `FamiliarConversation` 增加了必填字段 `currentModelID`，而旧 `default.store` 中没有该字段。
- SwiftData 自动轻量迁移对"新增必填字段且无默认值"的旧 store 返回 134110，无法原位迁移。
- 直接依赖 SwiftData 默认 store 文件名会让这类问题每次开发期 Schema 变化都重新出现，且没有明确的版本控制。

## Root Cause

开发阶段使用 SwiftData 默认 store（`default.store`）且未固化版本化 Schema，旧开发 store 与当前模型不兼容，自动迁移失败；App 启动路径没有处理该失败，导致无法启动。

## Fix

- 使用固定版本化 store 地址：`Application Support/Familiar/Persistence/FamiliarAgentV2.store`（`FamiliarModelContainer`）。
- 当前 7 实体固化进 `FamiliarSchemaV1`（1.0.0），之后所有生产与测试容器都通过 `FamiliarSchemaMigrationPlan` 打开，后续字段变化只能新增 VersionedSchema + migration stage。
- 新 store 首次成功创建后，清理旧开发 store（`default.store`、`FamiliarAgentV1.store`）与 SQLite sidecar、旧附件目录。
- 容器打开或迁移失败时不再终止启动：显示 `FamiliarStoreRecoveryView`，仅当用户在恢复界面再次确认后才删除当前 store 与附件（保留 Keychain API Key），并要求重启。

## Verification

- 磁盘 fixture：用旧直接 Schema 创建、含全部实体与关系的 store，可通过当前 migration plan 重新打开并保持数据一致。
- iOS 26.5 arm64 Simulator 迁移测试通过（V1/V2→V3、V4→V6 等）；模拟损坏 store 失败可观察且不自动删除。
- 覆盖安装到保留旧 store 的真机验证仍待完成。

## Remaining Issues

- 真实旧安装覆盖、磁盘空间不足、文件权限异常与损坏 store 的恢复路径尚未在真机验收。
- 首个公开版本冻结 Schema 后，需要为真正的线上用户制定正式迁移策略（当前清理旧 store 的策略只适用于无正式用户的开发阶段）。

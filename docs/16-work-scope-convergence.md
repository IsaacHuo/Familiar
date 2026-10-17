# 普通对话与项目分离、抽屉顶栏与 S2a

2026-10-17。本切片直接在 main 实施，不提交或推送，保留已有 S1 与输入区改动。

## 实现

- 普通对话 project=nil，不创建日常项目；新草稿预分配稳定 ID，提交保存成功后才消费草稿。普通对话采用全局默认，资料、会话记忆、文件与 Workspace 按对话隔离；显式全局 Memory 可跨对话。
- FamiliarWorkScope.project / .conversation 统一 Files、版本、上下文、Workspace、Environment 与授权。同 UUID 的不同 scope 类型也使用不同存储键与字节目录。
- 普通删除清独有文件、Workspace、环境元数据和授权；项目聊天删除保留项目文件。移动复制关联版本并重绑附件、清摘要和旧范围授权；删除项目先给聊天转存关联文件，再保留为普通聊天。历史文件引用通过显式版本 provenance 定位。
- 当前 schema 5.0.0，不含历史迁移链和迁移专用模型。业务代际 5-work-scopes 在下一次正常启动时触发已授权的旧业务数据重置；Keychain、模型/搜索配置、外观偏好保留。新容器成功后记完成；后续打开失败进入恢复页，不重复清空。
- 抽屉项目默认折叠，预览最近 5 条，普通对话最近 20 条；更新时间倒序、ID 稳定排序，单独置顶去重；查看更多打开完整列表。顶栏仅保留独立玻璃省略号，项目聊天内唯一项目详情入口；项目切换来自侧栏。
- S2a：clipboard_read 为只读结果；已就绪 environment_prepare 返回专用 unchanged。已启用的内置可撤销 file_write/edit/publish、workspace_write 自动执行；离线 Shell 需 Swift 检查、当前 Workspace 限制、写前 checkpoint。保留复核、journal、防重放、保存失败补偿和范围内 Undo。
- 实际依赖安装、Memory 自动写入、外部持续授权和 MCP 信任分级仍待后续切片，完整 S2 未完成；Shell 默认开启、文档环境预装属于 S4。

## 验证边界

所有者最新要求为“真机视觉验收我来，构建通过就行”。因此本切片只构建，不执行测试、启动 App 或截图，也未实际触发旧数据清理。

- 构建目标：Familiar Debug，iPhone 18 Pro Simulator，arm64，destination ID 1041DD9D-AC70-4DDD-9D34-52514C3E491F。
- 构建命令：xcodebuild build-for-testing；同时编译 App、单测与 UI 测试目标，不执行任何用例。
- 构建结果：成功，exit code 0，日志 `** TEST BUILD SUCCEEDED **`。App、单测与 UI 测试目标完成 arm64 编译；最终日志无 warning/error。
- 日志：/tmp/familiar-scope-test-build.log；DerivedData：/tmp/familiar-scope-20261017。
- 静态检查：git diff --check 通过；双语 strings 语法通过，各 1074 个键、无重复、键集合一致；测试清单检查通过（55 个 Simulator suite、3 个真机 suite、2 个显式真实服务 suite 及 UI tests）。均未执行测试。
- 新增 WorkScope 回归覆盖身份隔离、普通草稿/零项目、Compiler/Memory、代际重置、删除、移动/历史引用、授权范围和本地自动写入撤销；结果契约回归约束 environment_prepare 专用 unchanged，普通写工具不得伪装只读。已有测试更新到新契约。当前仅编译，未执行。

## 保留的验收项

- 普通对话发送/附件/生成文件/重启，跨对话与项目隔离，同 UUID 不同 scope 隔离。
- 首次业务重置保留配置与凭据，第二次启动保留新数据，打开失败进入恢复页。
- 普通/项目删除、移入移出项目、删除项目后文件仍可打开且原授权/撤销不跟随。
- 项目 0/5/6/100 条、普通 20 条以上、置顶去重、完整列表返回；浅/深色与大字体、项目详情入口、手势。
- 自动执行/撤销、checkpoint 失败、取消、保存失败补偿、越界、环境已就绪无操作。
- 真机视觉与所有者签字。S1 的 DeepSeek + Tavily 固定 20 查询仍独立待验收，见 15-s1-search-acceptance.md。

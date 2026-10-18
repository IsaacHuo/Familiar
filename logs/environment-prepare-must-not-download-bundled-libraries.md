# 设备上生成 Word 卡死：environment_prepare 的白下载

## 症状

真机要求生成 Word：确认后开始「下载」，一段时间后卡死，无法生成文件；再次尝试同样卡住。

## 根因（两段）

1. **不必要的下载**：rootfs 已内置 python-docx/openpyxl/python-pptx/fpdf2/pypdf/markdown/lxml/Pillow，但 `environment_status` 只看 Project Environment 的 receipt（恒为 notPrepared），模型据此调用 `environment_prepare` 去 pip 下载这些库。设备上 iSH 模拟 + TLS + 逐文件写挂载目录，几分钟写不完。
2. **超时必须能收尾**：shell 上限 180 秒。pip 卡在网络时，超时后 `terminateExecutionOwner` 可能杀不掉阻塞在 syscall 里的 guest 进程（`stopped == false`），执行器把 phase 置为 `.failed("...restart Familiar before retrying")` 但保留 `activeTaskID`；此后每次调用在 `prepare()` 的 `guard activeTaskID == nil` 处失败——旧版错误文案还是笼统的「尚未准备好」，看起来就像永久卡死。

## 修复

- `environment_prepare` 在创建计划前先做**内置探测**（`bundledProbe`，30 秒、禁网）：请求的包在 guest 的 Python 元数据里已存在（带版本 pin 则校验版本）就直接返回 `.unchanged` 的内置结果，不发生任何下载。
- pip 命令加 `--no-cache-dir --timeout 20 --retries 2`：真实缺包时网络卡顿快速失败而不是拖到 180 秒超时。
- 执行器：`activeTaskID` 未释放时抛出 `.failed` 里的具体原因（“重启 Familiar 前无法继续”），不再是笼统的「尚未准备好」。
- 内置 `documents`/`research-document` Skill 文案改为「依赖已内置，无需安装」。

## 复用结论

- 任何「guest 内联网安装」都必须有 30 秒级的探测前置与快速的网络超时；不要把 180 秒的 shell 上限当作 pip 的兜底。
- 超时杀不掉的 guest 进程会让整个执行器进入需要重启的状态；对该状态必须给出具体原因，否则用户感知为「卡死」。

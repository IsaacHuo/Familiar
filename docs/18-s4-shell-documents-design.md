# S4 iSH 小主机与文档交付设计（已确认，已实现）

2026-10-17。本文是 S4 的设计确认页，由所有者确认后实施。范围以 `PLAN.md` S4 为准；现状全部核对到代码。实现结果见文末「实施纪要」。

## 0. 现状

- **默认启用**（`Familiar/Agent/FamiliarToolGroups.swift`）：默认开启 base、web、calendar、places、files（除 workspace_write/file_publish）、memory、device、skill_list/skill_read；默认关闭：整个 `.shell` 组（shell_execute/environment_prepare/environment_status）、presentation 组、skill_install、workspace_write、file_publish。
- **注册与预热**：shell 工具仅在 bundled iSH 资产存在时注册（资产在，注册成功）；`prepareRuntime()` 只作为设置页重试句柄存在，**没有任何预热**；首次 shell 调用时才惰性 prepare（共享 flight，幂等）。发送路径快照不等待就绪。
- **rootfs**：`alpine-3.24.0-aarch64-fakefs.tar.gz`，34,921,546 字节（约 33.3 MiB）；包清单 ca-certificates coreutils findutils gawk git grep jq py3-pip python3 sed unzip zip；**无任何文档库**；SHA-256 侧车文件 + `Vendor/ISHRuntime/manifest.json` 对上游/Alpine/桥接产物有校验，`Scripts/prepare-ish-rootfs.sh` 可重新生成（本机 iSH builder、meson/ninja/gpg、fonttools 与网络均可用）。
- **Shell Outputs → Files**：成功的 shell 运行把 `Outputs/` 变更 `capture` 后经 `stageProducedFiles` 登记，`extractedText` 为空、**不经任何校验**。
- **格式**：`FamiliarFileFormat` 只有 markdown/plainText/docx/pdf/xlsx/html；**没有 pptx**（AnyDoc 能解析 pptx，导入路径已支持，缺的只是 validator/file_publish/QuickLook 映射）。
- **文档 Skill**：仅 bundled `research-document` 模板；安装函数硬编码该目录。
- **终端 watchdog**：180 秒 watchdog 在 `openTerminal` 之前启动，而 `openTerminal` 内部先 await prepare → **准备时间当前计入 watchdog**。
- **网络**：guest 默认不出站；`environment_prepare` 使用配置源并强制 publicInternet 策略（桥接层限制私网/监听/配额）。

## 1. 设计

### 1.1 默认启用与工具组

- `.shell` 组与 `file_publish` 默认启用（文档交付是核心链路；workspace_write、presentation 保持默认关闭）。
- 新增 `.documents` 工具组，作为“生成文档”的一站式能力包。建议组成：`shell_execute`、`environment_prepare`、`environment_status`、`file_publish`；`.shell` 组 id 由 `.documents` 取代（`group(for:)` 一个工具只归一组；保留两个高度重叠的组只会让模型困惑）。`tools_load` 一次最多两组的现有预算不变。
- Project 绑定缺省项跟随默认：当前只要有任意绑定行，未出现在绑定集合中的 manifest 一律视为关闭；新工具上线后老项目永远拿不到。改为——绑定行只表达“用户显式切换过的工具”，未出现的 id 跟随 `isDefaultEnabled`。普通对话（无绑定）不变。

### 1.2 预热与就绪呈现

- 触发：主界面出现且业务代际重置完成后，启动后台低优先级 `Task(priority: .utility)` 调 `executor.prepare()`（共享 flight 幂等；失败静默记状态，不打扰用户；下次调用自动重试）。不在 `FamiliarAppDependencies.init` 触发，避免测试/启动被拖慢。
- “可断点续做”的口径：prepare 任何时刻可安全重试；安装标记（schema/distribution/rootfsVersion/ishCommit/archiveHash）决定是否跳过重装，未完成的 staging 目录清理后重来。不做字节级续传（35–50 MiB，重来成本可接受）。
- 未就绪呈现：调用 shell/文档工具时的 progress 通道已存在，准备阶段报告“正在准备运行环境”即可；设置页已有 phase + Retry。

### 1.3 rootfs 预装

- apk 增包：`py3-lxml`、`py3-pillow`。
- pip 装入系统 site-packages（构建时，guest 内）：`python-docx openpyxl python-pptx fpdf2 pypdf markdown`。
- 中文字体子集：Noto Sans SC Regular（OFL-1.1），用 `fontTools.subset` 取 GB2312 一二级汉字 + ASCII/常用标点，放 `/usr/share/fonts/`；供 fpdf2/Pillow 渲染中文，PDF 内嵌字体授权允许。
- 脚本改动：`prepare-ish-rootfs.sh` 增加 `APK_PACKAGES`/`PIP_PACKAGES`/字体步骤，`--print-config` 展示；`generate-ish-notices.sh` 重新生成第三方清单（含字体 OFL）；`verify-ish-supply-chain.sh` 校验新 tarball 与清单。
- 体积：预计 40–48 MiB（脚本输出实测值，记入文档）。本机可直接重新生成并提交新 tarball + sha256 侧车 + manifest 更新。

### 1.4 文档交付链

- **Shell Outputs 自动校验**：capture 后对可识别格式用现有 `FamiliarFileValidator`/AnyDoc 做 best-effort 解析与文本抽取，登记 `extractedText` 与 validation receipt。校验失败**不回滚** shell 成功（字节已经产生），文件仍进入 Files 但带失败标注，模型不得声称“已验证”。Markdown/TXT/CSV 的直写路径保持 Swift 侧（file_write）。
- **PPTX**：`FamiliarFileFormat` 增加 `.pptx`；validator 走 AnyDoc（`zip-signature` + 解析非空）；`file_publish` format 枚举、QuickLook 映射与展示同步；补真实 fixture 的解析用例（编译级）。
- 统一文件卡：shell 产出已走 `producedFiles` 文件卡；实现时核对 `file.open` 可打开与历史回看。

### 1.5 内置文档 Skill 模板

- 新增 bundled skill `documents`：何时 Swift 直写（md/txt/csv）、何时走 guest + 预装库、必须 `file_publish` 且带 requiredText、PDF 中文字体路径、失败如实报告。
- `installExampleIfNeeded` 泛化为安装全部 bundled 模板（保留 research-document，新增 documents）。

### 1.6 健壮性

- boot/安装错误带真实原因：把桥接返回码映射为含阶段与 errno 文案的 `FamiliarShellExecutorError`，不改变控制流。
- 完成回调脱离主队列：保留现有 `Task.detached` trampoline；phase 发布经 MainActor 属预期。
- 失败可不重启恢复：设置页 Retry 与自动重试路径确认无残留 staging 阻塞。
- **终端 watchdog 不计准备时间**：调整终端控制流——先 await openTerminal（内部含 prepare），再启动 180 秒 watchdog 与存储检查。
- guest 出站：保持默认关闭；`environment_prepare` 的 publicInternet 仅服务于 Swift 构造的 pip 命令（见决策 6）。

### 1.7 验收（所有者执行）

- 真机 `FamiliarDeviceRuntimeTests` + `log stream`：冷/热 prepare、python + Outputs、限制与取消。
- 中文文档交付：DOCX / XLSX / PPTX / PDF 各一份，Quick Look 打开、正文含中文且非乱码；记录冷/热启动耗时与内存峰值。
- 终端：预热未完成时打开终端不被准备时间计入 watchdog；取消与重开正常。
- 构建边界同前：我只做实现 + `build-for-testing`（编译），不执行测试、不启动 Simulator、不真机。

## 2. 测试与文档影响

- 更新默认值断言：`FamiliarLazyToolTests`（shell/file_publish 默认开）、`FamiliarModelSelectionTests`（默认输出 scope）、`FamiliarBaselineTests`（工具清单）。
- 新增（编译级）：documents 组装载与默认表、绑定缺省跟随默认、预热幂等（fixture executor）、Outputs 校验登记、PPTX validator、watchdog 排除准备时间。
- 文档：`PLAN.md` S4 勾选、`state/ARCHITECTURE.md`（工具组/rootfs/预热/watchdog）、`state/CURRENT.md`、`state/FEATURE_MATRIX.md`、`docs/10` 的 iSH 供应链数值如与新 tarball 不一致需同步、`logs/` 补一条“watchdog 不得覆盖准备时间”的可复用记录。

## 3. 决策结果（所有者确认，2026-10-17）

1. `.documents` 组 = `shell_execute` + `environment_prepare` + `environment_status` + `file_publish`；`.shell` 组 id 移除。
2. Project 绑定中未显式切换过的工具跟随新默认。
3. “可断点续做” = 标记级安全重试（非字节级续传）。
4. rootfs 重新提交二进制资产与 notices，接受体积增大。
5. Outputs 校验失败的文件仍进入 Files 并标注失败。
6. environment_prepare 网络本轮不收紧到配置源主机。
7. 完成后进入 S3。

## 4. 实施纪要（2026-10-17）

- 工具组：`FamiliarToolGroup.documents` 取代 `shell`；四件套归 documents 且默认启用，`workspace_write` 与 presentation 仍默认关闭；`filterCapabilities` 对未出现在 Project 绑定中的能力跟随 `isDefaultEnabled`。
- 预热：`FamiliarRootView.onAppear` 调 `FamiliarAppDependencies.prewarmShellRuntime()`，后台低优先级执行共享 `prepare()`（幂等，失败静默，下次调用重试）；未就绪时 shell 与 environment_prepare 通过 activity progress 显示「正在准备运行环境」。
- 终端：watchdog 改为在会话首个事件后启动，准备时间不计入 180 秒。
- rootfs（实测）：`alpine-3.24.0-aarch64-fakefs.tar.gz` 33.3 MiB → **55.0 MiB（57,601,472 字节）**。新增 apk `py3-lxml`、`py3-pillow`；pip 装入 python-docx、openpyxl、python-pptx、fpdf2、pypdf、markdown、et-xmlfile、XlsxWriter、typing-extensions、defusedxml、fonttools（版本清单在 pip freeze 文件与 notices）；Noto Sans SC Regular/Bold 子集（GB2312 一二级 + ASCII/标点，OFL-1.1，含许可证文本）。guest 冒烟：fpdf2 中文 PDF（含粗体）、python-docx、openpyxl、python-pptx、markdown、pypdf 全部通过。
- 构建脚本：`prepare-ish-rootfs.sh` 支持 `FAMILIAR_GUEST_DNS`（构建期临时 resolv.conf，打包前恢复）、`FAMILIAR_ALPINE_MIRROR`、`FAMILIAR_PIP_INDEX_URL`、`FAMILIAR_NOTO_APK_URL`；因 iSH CLI builder 不传递 guest 退出码，所有联网步骤用输出标记显式校验。`generate-ish-notices.sh` 追加 pip 清单与字体许可证；`verify-ish-supply-chain.sh` 通过。
- 交付链：`FamiliarFileFormat` 增加 `.pptx`（validator 走 AnyDoc、file_publish 枚举与描述同步）；`FamiliarFileCatalogService.stageProducedFiles` 对已知格式 best-effort 解析，成功存 extractedText 与校验信息，失败仍登记并在 provenance 标注 `validation.state=failed`；`FamiliarFileValidator` 拆出 `extract` 供复用。
- 内置 Skill：bundled `documents` 模板（Swift 直写 vs guest 生成、预装库、中文字体、file_publish 校验）；`installExampleIfNeeded` 泛化为安装全部 bundled 模板。
- 错误与恢复：rootfs 缺失、解包失败、boot 状态码、Python 探测失败都有具体文案；staging 目录 defer 清理，Retry 不需重启。
- 构建：arm64 iPhone 18 Pro Simulator `build-for-testing` 成功（exit 0，`** TEST BUILD SUCCEEDED **`，无源码 warning/error）；测试只编译不执行。双语 strings 1077 键、键集合一致。

## 5. 真机验收清单（所有者）

1. 首次启动后等待片刻再发文档任务：活动行出现「正在准备运行环境」，准备完成后同一条 Run 继续；中途杀 App 重开，再次调用可直接完成准备。
2. 中文文档：要求生成 Word/Excel/PPT/PDF，Quick Look 打开，正文中文不乱码；PDF 含粗体。
3. 生成的文件在 Files 中可打开、预览、分享；`file_publish` 失败的文件不显示为成功。
4. 终端：冷准备期间打开终端，不被 180 秒 watchdog 误杀；`printf 你好`、`python3 -c 'import docx'`、Ctrl-C、Ctrl-D 正常。
5. Shell Outputs 校验：手写一个损坏的 .docx 到 Outputs 再触发捕获（或经 shell 生成），文件仍出现且不会被声称已验证。
6. 普通对话与 Project 首次使用 shell/文档：老 Project 无需手动开启 documents 组。

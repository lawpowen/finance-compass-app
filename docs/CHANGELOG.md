# 变更记录

## 2026-09-24

### Finance Compass v0.9.1 补丁版本发布准备（尚未发布）

- 行为：版本号改为 `0.9.1+43`，设置页“关于与支持”显示 `版本 0.9.1+43 · 本地优先的个人财务罗盘`（修正了 `·` 与“本地”之间缺少的空格）。本补丁包含下面两项 2026-09-24 修复：投资快照成本与取出口径，以及快照写入的余额维护与历史读取。README 与 `SELF_HOSTING.md` 的六个下载直链已指向 `v0.9.1` 资产名。**尚未创建 `v0.9.1` 标签或 GitHub Release，也未上传产物**，因此这些直链在发布前会返回 404。上一个已公开发布的版本仍是 `v0.9.0`。
- 设计：`pubspec.yaml` 仍是版本来源，Android `versionName`/`versionCode` 由 Flutter 从中读取（`0.9.1` / `43`）。自托管 Service Worker 的 `CACHE_NAME` 由 `finance-compass-shell-v0.9.0.1` 改为 `finance-compass-shell-v0.9.1`，否则缓存优先的已安装 PWA 会继续使用旧 `main.dart.js`，拿不到本次修复。两份 Compose 的本地镜像标签改为 `finance-compass-web:0.9.1`。`tool/package_selfhost.ps1` 默认 `-Version 0.9.1`，输出到 `artifacts/release/v0.9.1`。
- 兼容性：无 schema、迁移、JSON 备份格式、权限或应用 ID 变化。`0.9.0` 的备份可直接导入。Android 以更高的 versionCode `43` 和同一发布密钥覆盖升级；Windows 安装器使用固定 `AppId` 原地升级。两项行为修复会改变部分读数：未实现盈亏按剩余成本计算，以及快照后/首张快照前的历史余额。快照编辑/删除在有实际转账的账户中可能以 `SnapshotBalanceAmbiguityException` 拒绝。旧逻辑写错的 `current_balance` 不会被批量更正。回滚到 `v0.9.0` 不需要数据迁移，但会恢复旧的计算口径。
- 安全与运维：未改动签名配置、`android/key.properties`、发布密钥或任何用户数据。PWA 首次升级时，旧 Worker 可能仍会接管一次页面，关闭标签页重开即可换用新 Worker；账本存放在 Drift 浏览器存储中，不受缓存更换影响。本机已按 `RELEASE_WORKFLOW.md` 构建、验证签名并复核六项 SHA-256；GitHub 资产上传仍待执行。
- 文档：更新 README（当前版本与六个直链）、`SELF_HOSTING.md`（当前版本、直链、打包命令、Service Worker 缓存更换规则）、`RELEASE_WORKFLOW.md`（当前版本、改版本同步清单，原先硬编码为 `0.8.0`/`41` 的 APK 检查改为对照 `pubspec.yaml`，以及 `SHA256SUMS.txt` 的发布契约、产物检查与上传条目由三个二进制产物改为六个：Android、Windows 两个、自托管三个）、`docs/README.md`、`SECURITY_AND_OPERATIONS.md`、`TESTING_AND_QUALITY.md`（完成门禁加入格式检查，并记录 v0.9.1 源码检查结果）、[v0.9.1 发布 QA](public-release-qa-v0.9.1-2026-09-24.md) 与本记录。v0.9.0 的历史段落与 `public-release-qa-v0.9.0-2026-08-04.md` 保持原样。
- 验证：版本字符串全仓检索确认，剩余的 `0.9.0` 引用都属于历史描述。2026-09-24 首次复验时 `dart format --output=none --set-exit-if-changed lib test` 失败（退出码 1），141 个文件中有 6 个未按格式化规则排版：`lib/src/core/data/finance_repository.dart`、`lib/src/core/database/app_database.dart`、`lib/src/core/services/account_service.dart`、`lib/src/features/accounts/asset_snapshot_form_dialog.dart`、`lib/src/features/reports/reports_screen.dart`、`test/snapshot_balance_rebuild_test.dart`。随后只对这 6 个文件执行 `dart format`，并在格式化前留存副本比对：去除全部空白字符后，6 个文件与格式化前逐字节一致，说明只改了换行和缩进，没有改动逻辑、标记或尾随逗号。格式化后在同一工作树重跑三项检查，全部通过：`dart format --output=none --set-exit-if-changed lib test` 退出码 0（`Formatted 141 files (0 changed)`）；`flutter test` 为 131 项通过、2 项按设计跳过（`All tests passed!`，退出码 0）；`flutter analyze --no-fatal-infos --no-fatal-warnings` 退出码 0，无编译错误（0 项 error），报告 106 项问题（3 项 warning、103 项 info；warning 包括 `transactions_v2_screen.dart` 未使用的 `_referenceTransactions` 与 `ai_analysis_integration_test.dart` 未使用的局部变量 `snapshots`）。随后 Web 交付修复后全量测试为 135 项通过、2 项跳过；六项正式包已构建并逐项核对 `SHA256SUMS.txt`，详见 [v0.9.1 发布 QA](public-release-qa-v0.9.1-2026-09-24.md)。
- 限制：源码与本机发布资产检查已完成；格式、测试与静态分析三项源码检查已通过，但 106 项既有 lint info/warning 未在本补丁中清理。六项发布产物已构建，Android 发布签名与 v0.9.0 一致；GitHub 标签、Release 与资产上传仍待执行。Docker 与真机验收范围见 [发布 QA](public-release-qa-v0.9.1-2026-09-24.md)。两项修复的已知限制见下面的条目。iOS Safari 与 Android Chrome 的 HTTPS 安装和系统存储回收仍需目标设备人工验收。

### 自托管 Web 构建交付契约修复（Flutter 删除刚写入的输出、Worker 存根覆盖、界面无文字）

- 行为：
  - `tool/build_web.ps1` 在 Windows 上打印 `Built build\web` 后因缺少 `manifest.json` 失败，`build/web` 只剩 22 个文件。根因是 Flutter 构建系统按路径字符串追踪输出。`C:\Users\pwlaw\Documents\Codex` 是指向 `D:\Codex\Projects` 的 junction，经不同路径构建会得到不同配置哈希；`build/web/.last_build_id` 指向旧配置时，Flutter 在构建完成后删除旧 `outputs.json` 中列出的文件，而它们正是刚写入的同一批文件。经 junction 构建时 stamp 还会混入两种路径，清空输出目录也不足以避免。
  - 现在脚本先解析到物理路径（PowerShell 解析 junction/符号链接，shell 用 `pwd -P`），并总是清空 `build/web` 再构建。
  - Flutter 3.44 仍生成 `flutter_service_worker.js`，只是自注销存根；原 `CORE` 与两个脚本却要求它存在。更严重的是，默认 bootstrap 在已有 `service-worker.js` 注册时会把该存根注册到同一 scope，下一次访问即注销离线外壳。新增 `web/flutter_bootstrap.js`，加载时不传 Service Worker 设置；`CORE` 不再包含存根，改为补上 Chrome/Edge 实际加载的 `canvaskit/chromium/`、favicon、图标、`NOTICES`、CupertinoIcons 与字体清单。
  - 真实浏览器验证发现，v0.9.0 起自托管 Web 在 Caddy CSP 下**完全不显示文字**：CanvasKit 从 `fonts.gstatic.com` 取 Roboto/Noto Sans SC，被 `connect-src 'self'` 拒绝，且引擎持续重试。现在 `web/fonts/` 同源提供这 102 个文件（约 2.4 MB，SIL OFL 1.1），`fontFallbackBaseUrl` 指向 `fonts/`，Service Worker 按 `fonts/SHA256SUMS` 全部预缓存，离线也能显示中文。
  - 构建产物不再包含 CanvasKit `*.symbols`（约 9 MB 调试符号）和 `.last_build_id`；任何失败都会删除 `build/web`，避免 `package_selfhost.ps1 -SkipWebBuild` 打包半成品。
- 设计：
  - `deploy/selfhost/Dockerfile` 改为运行 `SKIP_PUB_GET=1 sh tool/build_web.sh`，三条构建路径使用同一份检查：必需文件、解析 `CORE` 逐项存在、`sqlite3.wasm` 锁定哈希、`drift_worker.js` 一致、字体哈希与 `main.dart.js` 回退 URL 覆盖（Roboto/Noto Sans SC 固定必需）、`useLocalCanvasKit`、bootstrap 来源、sidecar 排除。
  - 旧 gstatic 检查被替换：PowerShell 版对数组调用 `.Contains()`，从未生效；shell/Docker 版因 `flutter.js` 始终含 CanvasKit CDN 分支而必然失败。现在要求 `"useLocalCanvasKit":true`，并只允许 `main.dart.js` 含引擎默认字体回退地址。
  - 应用代码、数据库、JSON 格式与 Caddyfile 均未改变。
- 安全与运维：
  - 站点仍不向第三方发起请求。CSP 未放宽，未收录的回退字体（emoji、日/韩/繁体字体家族等）仍被拒绝，相应字符显示为方框。
  - `web/fonts/SHA256SUMS` 与 `tool/sqlite3_wasm.lock` 一样属于供应链锁；升级 Flutter 若改变字体版本，构建会失败并列出需补的路径。
  - 已安装 v0.9.0 PWA 的浏览器在新 `service-worker.js`（`CACHE_NAME` `finance-compass-shell-v0.9.1`）激活后换用新外壳。回滚到旧脚本会重新引入上述三个问题。
- 文档：更新 `SELF_HOSTING.md`（交付契约、Service Worker 存根、同源字体与更新方法、Git Bash 注意事项）、`RELEASE_WORKFLOW.md`、`TESTING_AND_QUALITY.md`（门禁与本次验证，并更正 v0.9.0 记录中“输出不含 `gstatic.com`”的说法）、`SECURITY_AND_OPERATIONS.md`、`INTERFACES.md`、`MODULE_DESIGN.md`、`ARCHITECTURE.md`、`TRACEABILITY.md` 与本记录。
- 验证：
  - 复现：junction 构建后，从物理路径运行 `flutter build web`，文件由 44 个降为 24 个。
  - 修复后，经 junction 与物理路径分别运行 `build_web.ps1`，以及在 Git Bash 运行 `build_web.sh`，均得到 142 个文件、36 项预缓存、102 个字体，`sqlite3.wasm` 哈希与锁定一致。
  - 四类负向用例（多余 `CORE` 项、缺失锁定行、缺失字体家族、构建失败）均按预期失败，且失败后删除 `build/web`。
  - Edge headless 在 Caddy CSP 下：首次加载、重载、离线重载均由 `service-worker.js` 控制，缓存 138 项，中文界面完整显示，无 CSP 错误与第三方请求。
  - 临时目录打包的 ZIP 与 `build/web` 一致，无 sidecar。
  - `web_delivery_contract_test.dart` 8 项通过；全量 135 项通过、2 项跳过；`dart format` 无变更；`flutter analyze` 无 error（106 项既有问题）。
- 限制：
  - 本机无 Docker，Dockerfile 路径未实际构建。
  - iOS Safari/Android Chrome 的 HTTPS 安装与离线重开仍需实机验收。
  - 未收录的文字系统与 emoji 在自托管 Web 中显示为方框。
  - 在 Git Bash 中运行 `build_web.sh` 需设置 `MSYS2_ARG_CONV_EXCL='*'`。

### 投资快照成本与取出口径修正

- 行为：资产卡片、详情和报表的未实现盈亏统一按总市值减剩余成本展示；取出不再使报表虚报亏损。首张快照表单按现有实际交易净投入预填成本基线，仍可手动校正。
- 设计：首张快照成本视为当日基线，只将其后的投入和取出用于后续成本变化；已包含在基线内的历史取出不再重复扣除。Repository 与 AssetService 使用相同规则，报表跨币种先换算主币种再汇总。
- 安全与运维：无 schema、备份格式、权限或部署变化；既有账本不被批量改写，历史基线错误仍须手动修正。
- 文档：更新 `SYSTEM_REQUIREMENTS.md`、`DATA_DESIGN.md`、`MODULE_DESIGN.md`、`INTERFACES.md`、`TRACEABILITY.md`、`TESTING_AND_QUALITY.md` 和根目录 `finance-app-design.md`。
- 验证：新增投入、取出、成本基线和 `planned` 排除回归；投资成本、账户详情与余额追溯相关测试共 5 项通过。定向静态分析无编译或类型错误，保留 35 项既有 lint（含 1 项未使用元素警告）。
- 限制：现有成本模型按取出金额减少剩余成本，不能区分取出本金和已实现收益。

### 资产快照写入的余额维护、快照后历史读取与首张快照前历史读取

- 行为：
  - 删除唯一快照后，余额按期初余额加实际交易重建，不再归零。
  - 原地编辑最新快照市值时保留其后的实际收入/支出：1000 的快照在其后有 100 收入时，改为 1050 后余额为 1150。
  - 新增成为最新的快照时，已存在、日期晚于它的实际转账/调整会折入其市值，余额再加其后收入/支出。
  - 回溯日期快照、非最新快照的编辑或删除，不再改动余额。
  - 在已有实际转账/调整的账户中删除最新快照（仍有较早快照），或编辑后改变了哪张是最新快照：改为明确拒绝，以中文提示建议改为编辑快照市值，数据库不变。
  - 快照之后某日的余额会加上快照后到当日的收入/支出，不再从快照值中扣减未来收入。
  - 首张快照之前的余额按此前账本计算，累计成本只算实际投入，不再泄漏未来快照。
  - “数字追溯”与显示余额同口径。
- 设计：
  - `AppDatabase` 按“是否影响最新快照”分派处理，并新增公开异常 `SnapshotBalanceAmbiguityException`。改换快照账户以 `ArgumentError` 拒绝。
  - `FinanceRepository` 新增 `_snapshotAnchoredAdjustments`，供余额与追溯共用；`AccountService` 与 `AssetService` 同步。
  - 保留 `_syncInvestmentFlowIntoSnapshot` 把转账/调整折入最新快照的既有语义。
  - 公开方法签名不变，但快照写入可能以新异常失败，新增最新快照时存储市值可能大于录入值。
- 安全与运维：无 schema、迁移、备份格式、权限或部署变化。增量路径不修复旧逻辑已写错的 `current_balance`，也不做批量重算。回滚只需还原代码文件。
- 文档：更新 `SYSTEM_REQUIREMENTS.md`、`DATA_DESIGN.md`（新增折入语义根本限制、决策表、Mermaid 流程与提案设计）、`MODULE_DESIGN.md`、`INTERFACES.md`、`TESTING_AND_QUALITY.md`、`TRACEABILITY.md`。
- 验证：
  - `snapshot_balance_rebuild_test.dart` 17 项，全部基于真实内存数据库并重新加载。
  - 与 `investment_cost_basis_test.dart`、`account_trace_test.dart`、`investment_market_value_entry_test.dart` 合计 22 项定向通过。
  - 全量 `flutter test` 131 项通过、2 项按设计跳过。
  - 定向 `flutter analyze` 仅余 1 项既有 `deprecated_member_use` info（`accounts_screen.dart:125`）。
- 限制（未修复，根因见 `DATA_DESIGN.md`“快照市值的折入语义与根本限制”）：
  - 系统未记录转账/调整折入了哪张快照，因此上述被拒绝的操作在有转账的账户中无法完成，用户只能编辑最新快照的市值。
  - 以非最新快照为锚点的历史余额，仍假设转账按时间顺序录入。
  - 旧逻辑已写错的余额不会自动更正。
  - 最新快照之前补录的收入/支出会计入 `current_balance`，但显示余额（快照锚点）不含它们。
  - 同一日期的多张快照先后次序不确定。
  - 首张快照之前的历史依赖 `initial_balance` 准确；旧账户若为 0，该区间历史余额接近 0。
  - 完整修复需要新增折入记录表（提案，未实现）。

## 2026-08-04

### 自托管 ZIP 与最小权限容器兼容修复

- 行为：Windows 生成的 Ubuntu、Windows 与 macOS 自托管 ZIP 现在统一使用 ZIP 标准的 `/` 条目分隔符，可由 Linux `unzip`、Python `zipfile` 和 macOS 归档工具正确还原目录；容器可在 `no-new-privileges` 与 `cap_drop: ALL` 下正常启动。
- 设计：打包器改用 .NET `ZipArchive` 显式生成可移植条目名，不再依赖 Windows `Compress-Archive` 的平台路径行为；Caddy 镜像在构建阶段移除监听低端口用的文件 capability，因为服务只监听 8080；`/data/caddy` 与 `/config/caddy` 使用临时内存盘，避免只读根文件系统产生运行日志错误。
- 安全与运维：继续保留只读根文件系统、临时 `/tmp`、全部 capability 丢弃、loopback 绑定和禁止权限提升；未扩大容器权限，也不影响浏览器本地账本。
- 文档：更新公开发布 QA、测试质量说明与本变更记录。
- 验证：在 Tailscale homelab 的 Ubuntu/Docker 29.6.2 环境中以发布 ZIP 原包解压、构建并启动隔离 Compose 项目，检查首页、WASM MIME、安全响应头、容器 capability 和只读根文件系统；完整测试 112 项通过、2 项按设计跳过，发布包 SHA-256 随修复重新计算。
- 限制：iOS Safari 与 Android Chrome 的 HTTPS 安装和系统存储回收仍需目标设备人工验收。

### GitHub 仓库转移链接同步

- 行为：应用内“关于与支持”、Windows 安装程序和公开文档现在打开 `lawpowen/finance-compass-app` 的源码、Release 与 Issues 页面。
- 设计：不改变 PWA、账本数据、API 或发布文件；仅将已转移仓库的公开入口由旧拥有者路径更新为当前路径。
- 安全与运维：旧 GitHub 路径可能会重定向，但安装、更新和支持入口不再依赖重定向；无需新增权限或配置。
- 文档：更新 README、`SELF_HOSTING.md`、`INTERFACES.md`、`RELEASE_WORKFLOW.md` 与本变更记录。
- 验证：确认 `lawpowen/finance-compass-app` 对当前 GitHub 身份授予 `ADMIN`，并运行 PWA 交付契约测试和 Web Release 构建。
- 限制：iOS Safari 与 Android Chrome 的 HTTPS 安装仍需在目标设备上人工验收。

### Finance Compass v0.9.0 自托管 Web / PWA

- 行为：新增可自托管 Flutter Web/PWA；iOS Safari 可添加到主屏幕，Android Chrome 可安装/添加为 PWA，桌面浏览器可访问。服务器只提供静态应用文件，账本保存在各浏览器自己的 Drift WASM SQLite 存储，不会自动跨设备同步。
- 设计：`AppDatabase` 按平台选择原生 SQLite 或 `WasmDatabase`，Web 需要同源 `sqlite3.wasm` 和编译后的 Drift Worker；自定义 Service Worker 缓存应用壳。新增 Docker/Caddy 静态服务、loopback 默认 Compose、HTTPS/Basic Auth 反向代理示例、三平台启动器和 runtime-only 打包流程。
- 安全与运维：默认不暴露公网、不写服务端账本；公开访问必须由部署者添加 HTTPS 与访问控制。浏览器清除站点数据、切换 profile/origin 可能丢失本地账本，用户需主动导出 JSON；Web 导入不伪造服务器恢复点。
- 文档：新增 `SELF_HOSTING.md`，同步 README、需求、架构、模块、接口、安全运维、测试、追踪与发布流程。
- 验证：Web Release 与 Drift Worker 构建成功；Chrome 390×844 真浏览器会话确认界面渲染、Service Worker 激活/控制页面且无控制台或资源错误。112 项测试通过、2 项按设计跳过，静态分析无编译错误并保留 105 项既有提示。三份 runtime ZIP 各含 52 个文件条目，Compose 配置、锁定 WASM、Worker sidecar 排除和 SHA-256 均已复核；Android/Windows v0.9.0 正式包同步构建并验证。
- 限制：当前不是云同步/多用户服务，没有服务器端账户、API、数据库、备份或冲突处理；Docker runtime ZIP 不是原生 `.deb`/`.msi`/`.dmg`。初版曾因误用不匹配的 sqlite3 WASM 出现 `xFileControl` 白屏，现已固定到 sqlite3 2.9.4 官方资产并完成修复后 Chrome 回归。本机 Docker Desktop 卡在 `starting`，因此容器未在本机实际启动；已完成 Compose 配置与回环 HTTP 资源验收。iOS Safari/Android Chrome 的 HTTPS 安装和系统存储回收仍需目标设备人工验收。

## 2026-08-04

### Finance Compass v0.8.0 公开发布与自愿支持

- 行为：设置页新增“关于与支持”，可查看 `0.8.0+41`、打开公开源码/最新下载/问题反馈，并显示 Touch 'n Go 自愿支持收款码与收款人 `LAW PO WEN`；README 新增 Windows 安装程序、完整便携包和 Android APK 的直接下载入口。
- 设计：Windows 正式程序统一命名为 `FinanceCompass.exe`，新增 Inno Setup 安装脚本；Android 正式构建必须从本地 `key.properties` 读取独立发布签名，缺少签名配置时直接失败，不再回退到 debug 签名。支持链接使用系统外部浏览器，收款码为随应用打包的静态资源。
- 安全与运维：仓库保持公开；发布包含安装程序、便携 ZIP、APK 与 `SHA256SUMS.txt`。签名密钥及口令文件被 Git 忽略并要求离线加密备份；支持功能不集成支付 SDK、不读取支付状态、不解锁功能。无数据库迁移、权限扩大或用户财务数据上传。
- 文档：更新 README、需求、架构、模块、接口、UI、交互、安全运维、测试质量、追踪矩阵、发布流程和设计 QA；新增 [v0.8.0 公开发布 QA](public-release-qa-v0.8.0-2026-08-04.md)。
- 验证：`flutter test` 为 108 项通过、2 项按设计跳过；静态分析无编译错误，保留 105 项既有 lint。Android APK 的包名、版本、ABI、v2 签名和内置收款码均已核对；Windows Release、Inno Setup 和 19 条目便携 ZIP 构建成功，三项二进制的 SHA-256 复核一致。
- 限制：Windows 安装程序尚无 Authenticode 商业代码签名，SmartScreen 可能提示未知发布者；Android 后续升级必须继续使用本次生成的同一发布密钥。公开发布不包含用户数据库、备份 JSON 或本机签名秘密。

## 2026-07-27

### 新建快速模板退出动画崩溃修复

- 行为：从快速模板管理页点击加号、填写交易并保存模板名称后，应用不再进入 Flutter 红屏；模板正常写入并返回列表。旧交易页的保存模板和保存周期命名框同步采用安全实现。
- 设计：移除命名对话框外部创建并在 `showDialog` 刚返回时立即销毁的 `TextEditingController`，改用 `TextFormField.initialValue` 与局部字符串接收输入。这样输入控件由对话框路由完整管理退出生命周期，避免 Android 退场动画仍订阅已销毁控制器后连锁触发 `_dependents.isEmpty`。
- 安全与运维：无 schema、JSON、权限、网络或用户账本迁移；Android Debug 构建号升至 40。回滚只需恢复命名框实现，不影响已保存模板。
- 文档：更新 README、系统需求、模块设计、UI 基线、安全运维、测试质量和变更记录。
- 验证：新增 390×844 完整创建流程 Widget 回归；修复前稳定复现 `TextEditingController was used after being disposed` 及 `_dependents.isEmpty`，修复后定向测试通过。全量 `flutter test` 为 107 项通过、2 项按设计跳过；`flutter analyze` 无编译错误，保留 105 项既有 info/warning。build 40 ARM64 Debug APK 经 `aapt` 核对为 `com.financecompass.app.debug`、versionCode `2040`、`0.8.0-debug` 与 `arm64-v8a`，大小 84,944,204 bytes，SHA-256 为 `206655AAA60878DCB1ADC9E161E267EBC73246897B2A1BBE94BEF392463FC6AA`；Drive 元数据回读大小一致。
- 限制：本修复针对应用内部命名对话框生命周期；系统键盘厂商自身的显示或语音输入问题不在应用控制范围内。

## 2026-07-22

### 月度资金需求整合进顶部口径

- 行为：交易页删除独立“N月需准备现金”大卡；顶部三张卡统一命名为“实际消费”“实际现金”“信用/贷款”。本月及未来月份由“实际现金”直接显示需准备总额，选中后以“需准备现金”为副标题，并在既有解释区显示已知流出、尚未安排及到期/覆盖说明。历史月份中间卡显示实际现金支出。
- 设计：`MonthlyFundingNeed` 计算保持不变，只调整 `TransactionsV2Screen` 的信息层级。资金总额使用橙色，继续是全月指标且不受明细筛选影响；两项解释使用弹性缩放，避免 390 像素宽度出现溢出。
- 安全与运维：无 schema、JSON、网络、权限或后台任务变化；Android Debug 构建号升至 39。
- 文档：更新 README、系统需求、架构、模块设计、UI 基线、安全运维、测试质量、设计 QA 和变更记录。
- 验证：全量 `flutter test` 为 106 项通过、2 项按设计跳过；`flutter analyze` 无编译错误，保留 105 项既有 info/warning。Windows 1266×713 Debug 实机确认三卡命名、未来月份 MYR 7,206 需准备金额、紧凑拆分说明及列表上移均正常。build 39 ARM64 Debug APK 经 `aapt` 核对为 `com.financecompass.app.debug`、versionCode `2039`、`0.8.0-debug` 与 `arm64-v8a`，大小 84,943,304 bytes，SHA-256 为 `B360335B5583729C71FC4C8D7804DDA0FE13153CE54EC68629058B3CC52CA45C`；Drive 元数据回读大小一致。
- 限制：全月资金需求有意不跟随账户、类型或类别筛选，选中卡片时会明确提示；历史月份不重建当时尚未覆盖的到期义务，只显示实际现金支出。

### 交易页月度资金需求总额

- 行为：交易页在本月及未来月份新增“N月需准备现金”卡，把已知现金流出与当月到期、尚未安排的信用卡和贷款还款合并成一个可直接备款的总额；已有实际或预计还款显示为“已包含”，不会重复相加。该全月指标不随下方账户、类型和类别筛选缩小。
- 设计：Repository 新增只读 `MonthlyFundingNeed` 派生模型与 `monthlyFundingNeedForMonth` 查询，复用现金流、信用卡账期和贷款摊销规则，并以当月还款交易抵扣到期义务的未覆盖部分；转入贷款账户的普通手工转账与结构化月供都可形成覆盖。交易页只在本月或未来月份展示，跟随“已发生/包含预计”状态。
- 安全与运维：无 schema、JSON、网络、权限或后台任务变化；计算完全基于本地账本快照且不写入交易。Android Debug 构建号升至 38。
- 文档：更新 README、系统需求、架构、模块设计、内部接口、UI 基线、测试质量、追踪矩阵和变更记录。
- 验证：月度资金需求单元与 Widget 定向回归通过；全量测试 106 项通过、2 项因外部 AI 网关未启动按设计跳过。Drive 最新 JSON 临时恢复为 18 个账户、29 个类别、12 个预算、730 笔交易和 4 个资产目标；2026-08 含预计现金流入/流出为 MYR 7,172.45 / 2,305.00，到期信用 MYR 2,275.99、到期贷款 MYR 1,316.00，贷款已由预计转账覆盖，最终需准备 MYR 4,580.99。静态分析无编译错误，保留 105 项既有 info/warning。build 38 ARM64 Debug APK 经 `aapt` 核对为 `com.financecompass.app.debug`、versionCode `2038`、`arm64-v8a`，大小 84,948,952 bytes，SHA-256 为 `F2A5C77B8BA0AF87878191648A928A866FC2A1F5D4E3B136BAFECCA9629241B0`；Drive 元数据回读大小一致。
- 限制：该卡按现有固定贷款合同与信用卡账期推导；浮动利率、临时手续费、罚息及未入账的银行侧调整仍需用户以后以真实交易或期末调整校正。

### 资产目标总资产口径与信用账户快捷还款

- 行为：资产目标改用不扣除信用卡和贷款的总资产计算，目标页文案同步显示“当前总资产”。信用账户的“记录还款”改用贷款式流程：先选择同币种现金账户，再确认或调整还款金额，保存后生成现金账户转入信用账户的实际转账。
- 设计：`totalAssetHistory` 新增 `includeCredit` 参数并默认保留净资产报表兼容性；`assetGoalSummaries` 固定传入 `false`。信用卡专用流程只接受 `ReportGroup.cash` 且币种相同的来源，不再把非现金账户带入还款候选。
- 安全与运维：无 schema、JSON、网络、权限或后台任务变化；目标仍使用既有 `app_meta`，还款仍使用既有 `transactions`。Android Debug 构建号升至 37。
- 文档：更新 README、系统需求、模块设计、数据设计、接口、UI 基线、交互审计、安全运维、测试质量、追踪矩阵、设计 QA 和变更记录。
- 验证：6 项资产目标与信用卡账单定向测试通过；样本确认总资产 MYR 1,500 不会被 MYR 800 信用负债扣成 MYR 700，并确认 MYR 300 还款同时把现金从 MYR 2,000 降至 MYR 1,700、信用欠款从 MYR 500 降至 MYR 200。全量测试 105 项通过、2 项因外部 AI 网关未配置按设计跳过；静态分析无编译错误，保留 105 项既有 info/warning。build 37 ARM64 Debug APK 经 `aapt` 核对为 `com.financecompass.app.debug`、versionCode `2037`、`arm64-v8a`，大小 84,936,860 bytes，SHA-256 为 `0E17C971DBEAC72A4048186A618EC565B630AF29F76E4EA8CD60940D930995A2`；Drive 回读大小一致。
- 限制：信用账户快捷还款当前只允许同币种现金账户；跨币种信用还款仍应通过通用转账并明确填写到账金额。

### 交易筛选、实际现金报表、资产目标与预算生效链

- 行为：交易页账户、类型和类别筛选现在同步更新列表与顶部三种口径；未来贷款还款按完整月供进入现金流出。报表统一按现金账户实际流入/流出计算。账户页恢复资产目标入口及新增、编辑、删除、趋势和进度界面。新月份预算从生效月起沿用，不再覆盖更早月份规则。
- 设计：新增 `CashFlowSummary` 与 `actualCashFlowSummaryForMonth(s)` 等现金派生查询，未来投影以现金资产为起点；预算编辑只有类别和生效月均不变才复用旧 ID；资产目标使用独立 `AssetGoalsPage` 和既有 mutation/provider。修正文档中仍描述旧版贷款本金/利息双记录的过期内容。
- 安全与运维：无 schema、JSON 格式、权限、网络或后台任务变化；所有新统计均为本地只读派生，目标和预算继续写入既有 SQLite/meta。Android Debug 构建号升至 36。
- 文档：更新 README、系统需求、架构、模块设计、数据设计、接口、安全运维、UI 基线、测试质量、追踪矩阵、设计 QA 和变更记录。
- 验证：定向回归覆盖筛选联动、RM 1,316 完整贷款月供、实际现金报表、资产目标新增和 4 月 MYR 200 / 8 月 MYR 400 预算规则链；全量测试 103 项通过、2 项因外部 AI 网关未配置按设计跳过。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译错误，保留 105 项既有 info/warning。Drive 最新 `finance_compass_2026-07-21_1457.json` 已在临时数据库成功恢复：18 个账户、29 个类别、12 个预算、730 笔交易和 4 个资产目标；2026-07 实际现金流入/流出为 MYR 7,954.70 / 7,255.54，2026-08 含预计为 MYR 7,172.45 / 2,305.00。build 36 ARM64 Debug APK 经 `aapt` 核对为 `com.financecompass.app.debug`、versionCode `2036`、`arm64-v8a`，大小 84,934,736 bytes，SHA-256 为 `D27C539671775F1E1C7236E05614B0A2A5F7B3DBD40E47449A9EC64D324DF841`；Drive 回读大小一致。
- 限制：报表现金分类中没有消费类别的还卡、还贷等转账归入“转账还款等未分类现金流出”；这不影响现金流出总额。资产目标继续存放于既有 `app_meta`，没有独立数据库表。

## 2026-07-21

### 账户历史统计截止与方向控件防回归

- 行为：账户页“统计截止”从无响应的展示文字改为真实月份选择器，连续提供最早账本月份至本月；选择历史月份后，资产、信用卡和贷款汇总按该月月末重算，普通、投资、信用卡和贷款详情继承相同截止日期并进入只读模式。类别收入/支出标题可真实折叠；输入框、禁用计划项和只读预览不再显示误导箭头。
- 设计：`AccountsV2Screen` 保存临时 `selectedCutoffMonth` 并把月末 `cutoffDate` 传给三个详情页面；历史模式只读取截止日前的实际交易和快照，不暴露写入入口。交互源码门禁从“仅检查空回调”扩展为同时检查方向性图标附近是否存在真实处理器。
- 安全与运维：不新增 schema、持久化设置、网络、后台任务或权限；历史模式是只读查询。Android Debug 构建号升至 35，仍使用独立包名与开发签名。
- 文档：更新 README、系统需求、模块设计、数据设计、接口、安全运维、UI 基线、交互审计、测试质量、追踪矩阵、设计 QA 和变更记录。
- 验证：全量测试 100 项通过、2 项按设计跳过；静态分析无编译错误，保留 105 项既有 info/warning。Windows Debug EXE 构建并实机验证月份列表与历史汇总；build 35 ARM64 Debug APK 为 `com.financecompass.app.debug`、versionCode `2035`、`arm64-v8a`，大小 84,918,420 bytes，SHA-256 为 `48B6BB0E7ADA28B0C20D1A97DE31AF57301F1BF95245120E1CB8660952B23A00`，Drive 回读大小一致。
- 限制：统计月份只保留在当前页面会话，重新启动应用会回到本月；截图和 Widget 回归不等同于屏幕阅读器、键盘遍历、超大字体和所有桌面尺寸的专项无障碍认证。Flutter 构建仍提示未来需迁移 Built-in Kotlin，当前产物不受影响。

## 2026-07-21

### 贷款整期删除与预计缺口计数

- 行为：删除第 1 期月供后，贷款详情立即恢复余额并重新显示“记录第 1 期还款”，不再错误跳到第 2 期。旧版拆分记录删除本金或利息任一项时会删除整期。预计按钮按真实缺口显示，例如 58 期中已有 19 期时显示“补齐 39 期预计交易”。
- 设计：贷款组合删除在 `TransactionMutations` 集中扩展，只匹配同来源、同状态、同日期、同期号且唯一的互补分项；数据库继续使用既有原子批量删除。页面以计划期号集合减去实际和预计集合计算缺口。
- 安全与运维：不新增 schema、权限或网络；匹配不唯一时不会扩大删除范围。Android Debug 构建号升至 34。
- 文档：更新 README、系统需求、模块设计、安全运维、UI 基线、测试质量、设计 QA 和变更记录。
- 验证：定向测试覆盖新版整期删除、旧版分项成组删除、余额恢复、期次回退和生成/补齐/已补齐文案；全量测试 94 项通过、2 项按设计跳过，静态分析无编译错误并保留 104 项 info/warning。Windows Debug EXE 构建并打开成功；build 34 ARM64 Debug APK 为 versionCode `2034`、`arm64-v8a`、84,903,732 bytes，SHA-256 为 `C2C20D8154C5537AEBABADB5C4A0AD75E45CDFAADAE071A919E5D19B5F1710B6`，Drive 回读大小一致。
- 限制：无法唯一识别互补旧记录时仅删除用户明确选择的记录，避免误删另一笔贷款。

### 贷款预计交易改为完整月供

- 行为：贷款预计和实际还款不再显示当期本金，而是每期生成一笔完整“贷款月供”；RM1,316 月供在交易列表和现金预测中就是 RM1,316。打开贷款详情时，旧版生成的预计本金转账与预计利息支出会自动合并，无需手动清理。
- 设计：结构化月供转账以 `amount` 保存完整现金付款、`toAmount` 保存本金减少额，差额为利息；因此现金账户减少完整月供，贷款余额仍只减少本金。通用交易编辑器识别 `贷款月供 #N` 并保留同币种的两个金额。实际历史记录不自动改写。
- 安全与运维：只迁移可明确识别且状态为 `planned` 的旧贷款预计组合；不新增 schema、权限、网络或后台任务。Android Debug 构建号升至 33。
- 文档：更新系统需求、架构、模块设计、数据设计、安全运维、UI 基线、测试质量、设计 QA 和变更记录。
- 验证：定向测试覆盖完整月供、现金与贷款余额、旧预计组合合并及编辑保存不丢本金金额；全量测试 93 项通过、2 项按设计跳过，静态分析无编译错误并保留 104 项 info/warning。Windows Debug EXE 构建并打开到 Loan120K 详情，确认月供显示 RM1,316。build 33 ARM64 Debug APK 为 versionCode `2033`、`arm64-v8a`、84,899,932 bytes，SHA-256 为 `AD26E365DA3E0EBE8A742BE5652B8B4B4E7CC5B29C749A18B991BF89D1E58F9F`，Drive 回读大小一致。
- 限制：既有 `actual` 本金/利息历史记录保持原样，避免未经确认改写已经影响余额的账本记录。

### 全应用交互接线与无摆设控件门禁

- 行为：周期规则编辑页的交易内容、金额与账户、类别、重复频率、发生日期、结束条件、启停、删除和未来 1–12 个月补生成全部可用；预算生效月份和下月预览、报表时间区间、货币格式、应用内提醒、总览账户/预算明细入口均执行真实行为。未实现能力改为明确禁用的“计划中”。
- 设计：共享设置行以可空回调区分交互与信息，纯信息行不再显示箭头；移除未被路由引用且含硬编码示例的 `report_reference_pages.dart`。新增源码静态门禁，禁止 `_noop` 和空交互回调。
- 安全与运维：不新增 schema、网络、后台任务或平台权限；通知偏好只控制应用内总览。Android Debug 构建号升至 32，继续使用独立包名和开发签名。
- 文档：新增全应用交互审计，并更新 README、系统需求、架构、模块设计、数据设计、接口、安全运维、测试质量、UI 基线、追踪矩阵、设计 QA 和变更记录。
- 验证：全量测试 91 项通过、2 项按设计跳过；静态分析无编译错误并保留 104 项 info/warning。Windows Debug EXE 构建并实机打开成功；build 32 ARM64 Debug APK 核对为 `com.financecompass.app.debug`、`Finance Compass Debug`、versionCode `2032`、`arm64-v8a`，大小 84,897,452 bytes，SHA-256 为 `CF474FF1416853BAE391A2D7279BE67AF648E41AB7F0AC03DB3E9CF94BF476FD`，Drive 回读大小一致。
- 限制：系统级通知调度、Google 登录、系统主题跟随和交易附件仍未实现；屏幕阅读器、完整键盘遍历和全部桌面尺寸尚未完成专项无障碍认证。

### 周期交易自动展开与贷款全期预计交易

- 行为：保存周期规则后立即生成未来 3 个完整日历月的预计交易，不再出现“规则已保存但后续记录看不到”的状态。新增贷款账户后会进入详情并询问是否生成全部剩余期次；详情页长期保留生成/补齐入口。用户选择同币种还款账户并确认后，每期生成预计本金转账和预计利息支出；记录实际还款时替换该期预计记录，避免重复计算。
- 设计：`FinanceRepository.addRecurringTransactionRule` 在规则落库后调用幂等月份生成器，跳过今天及以前并强制未来记录为 `planned`。`LoanDetailScreen` 按实时摊销计划批量写入本金与利息交易，使用期次说明去重；实际还款继续原子写入本金/利息两笔实际记录，并先清理相同到期日、还款账户和期次的预计组合。旧的周期规则和既有预计交易不自动删除。
- 安全与运维：无数据库 schema、导入导出格式、权限或网络变化；所有自动展开均写入本地 SQLite 且不改变实际余额。贷款全期生成必须经用户选择账户和确认。Android Debug 构建号升至 31，继续使用独立包名和数据目录。
- 文档：更新 README、系统需求、架构、模块设计、数据设计、接口、安全运维、UI 基线、测试质量、追踪矩阵、设计 QA 和变更记录。
- 验证：全量测试 86 项通过、2 项按设计跳过；覆盖周期规则保存后未来 3 个完整月份、贷款创建后询问、全期本金/利息预计交易及实际一期替换。静态分析无编译错误，保留 102 项既有 info/warning。Windows Debug EXE 与 build 31 ARM64 Debug APK 构建成功；APK 核对为 `com.financecompass.app.debug`、`Finance Compass Debug`、versionCode `2031`、`arm64-v8a`，大小 84,892,088 bytes，SHA-256 为 `7FC192B978A3DEB08ABC1214C2788C147E1C2F64905237C59C28C2406A38E08C`，Drive 回读大小一致。
- 限制：现有 `car loan` 周期支出规则及其已生成的预计记录不会自动迁移或删除；若改用贷款账户全期预计交易，应由用户停用旧规则并清理重复的未来预计支出。周期规则保存时默认只预生成未来 3 个完整月份，更远月份需在周期管理页继续生成。

### 贷款账户自动月供与完整还款计划

- 行为：贷款账户现在可填写合同金额、年利率、年限、开始记账日期、每月还款日、还款方式和可选开始记账余额，自动生成等额本息、等额本金或平息贷款计划；中途建账只显示之后待记录的期数，不要求补录以前已还款。等额本息和平息贷款可选用银行核定的常规月供，尾期自动补差。
- 设计：新增纯领域模型 `loan_amortization.dart`，计划按账户合同条件实时派生；`loan_principal` 保留原合同金额，`loan_start_date` 保留真实合同开始日，负数 `initial_balance` 保存开始记账余额，v9 的 `loan_tracking_start_date` 独立保存中途建账截止日。实际还款原子拆为本金转入贷款账户和利息支出，现金减少整笔月供而贷款余额只减少本金。多币种贷款汇总先换算为基准币种。
- 安全与运维：SQLite schema 从 v7 逐级升至 v9；v8 为 `accounts` 增加 7 个可空合同字段，v9 增加可空追踪开始日。打开 v1–v8 数据库前在 `pre_v9_*` 建立 SQLite、WAL/SHM 和逐表 JSON 恢复点，失败阻止升级。JSON 仍为兼容格式 v3，但 `schema_version=9` 并增加追踪日期；旧贷款缺失该字段时使用合同开始日，迁移不会猜测余额。Android Debug 构建号升至 30，继续使用独立包名与数据目录。
- 文档：更新 README、系统需求、架构、模块设计、数据设计、接口、安全运维、UI 基线、测试质量、追踪矩阵、设计 QA 和变更记录。
- 验证：新增领域、数据库与 390×844 Widget 回归；全量 `flutter test` 为 86 项通过、2 项按设计跳过。合同开始日 2022-05-23、首期合同还款日 2022-06-23 的 RM120,000、年利率 2.1%、108 期等额本息贷款，从 2026-06-30 的 RM71,097 余额中途建账时生成 57 期待记录计划，下一期为 2026-07-23，常规月供 RM1,316，预计剩余利息 RM3,654.44、剩余还款 RM74,751.44。`flutter analyze` 无编译错误，保留 103 项既有 info/warning；贷款表单和还款详情在 390 逻辑像素无 RenderFlex 溢出，Windows debug 构建成功。build 30 ARM64 Debug APK 经 `aapt` 核对为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2030` 与 `arm64-v8a`；84,888,884-byte APK 已上传至 Drive，文件大小与本地产物一致，SHA-256 为 `5E5407A3A6ED655F429E756B7F13AD6BA106D39FFA48177C42DD5C193C4E0376`。
- 限制：当前仅支持固定合同利率；浮动利率重定价、手续费、罚息、部分还款、提前还款重算及跨币种还款尚未实现。银行核定月供适用于等额本息和平息贷款，且不能低于当期利息或提前于合同期数清偿；等额本金不支持固定核定月供。

## 2026-07-20

### 新版转账双金额与自动汇率换算

- 行为：新版交易编辑器的转账类型新增“转入金额”。同币种选择目标账户后自动与转出金额相同且不可单独修改；不同币种按设置页汇率自动换算，用户可修改银行实际到账金额或点击“重新换算”。
- 设计：复用 `FinanceRepository.convertAmount` 与 `exchangeRatesToBase`，不新增网络服务。同币种继续以 `amount` 为唯一持久化金额并保存 `toAmount=NULL`；跨币种保存最终 `toAmount`/`toCurrency`，账户余额、编辑、模板、周期生成及 JSON 往返沿用既有模型。
- 安全与运维：无 schema、权限或网络变化；Debug 构建号升至 29。汇率是本地设置值，自动换算仅为建议，历史到账金额不会随汇率设置变化。
- 文档：更新系统需求、模块设计、数据设计、接口、UI 基线、测试质量和变更记录。
- 验证：定向测试覆盖同币种只读同步及 MYR→TWD 自动换算/人工覆盖；全量测试 77 项通过、2 项按设计跳过，静态分析无编译错误并保留 104 项既有 lint。可信 v3 备份已真实恢复验证为 17 个账户、29 个类别、13 个预算和 683 笔交易。build 29 ARM64 Debug APK 核对包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `2029` 与 `arm64-v8a`；84,689,324-byte APK 和 377,347-byte JSON 的 Drive 副本 SHA-256 均与工程产物一致。
- 限制：应用不会在线抓取实时银行汇率；实际手续费或银行点差需由用户在转入金额中校正。

### 同币种转账零转入金额修复

- 行为：同币种转账继续只有一个金额入口，转出和转入使用同一数值；快速模板不再把不可见的旧 `to_amount=0` 带入新记录。升级或导入后，受影响的已发生/已结算转账会自动补回目标账户余额，预计记录只归一字段。
- 设计：`FinanceTransaction.transferInAmount` 增加旧资料兼容；`TransactionComposerPage` 对同币种转账强制保存 `toAmount=NULL`；`AppDatabase` 新增幂等迁移 `zero_same_currency_transfer_amounts_v1`，并在完整导入事务内强制扫描。跨币种独立转入金额不受影响。
- 安全与运维：不覆盖用户提供的 JSON；修复与账户余额更新在数据库事务中完成，随后继续执行 SQLite 完整性检查。Debug 构建号升至 28。
- 文档：更新数据设计、模块设计、测试质量、发布恢复流程和变更记录。
- 验证：用户提供的 376,268-byte v3 JSON 已真实导入空数据库，17 个账户、29 个类别、13 个预算和 681 笔交易全部恢复；3 笔同币种异常转账成功归一。全量测试 76 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。build 28 ARM64 Debug APK 核对包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、versionCode `2028` 和 `arm64-v8a`；修复后 JSON 为 376,326 bytes，APK 与 JSON 的 Drive 副本哈希均和工程产物一致。
- 限制：当前界面尚未提供跨币种汇率/目标金额编辑器；该类交易继续沿用已有 `toAmount` 数据，不会被本次同币种迁移改写。

### 修复 Android 导出 0 KB 与恢复后黑屏

- 行为：完整备份、完整导出、AI 摘要和未来计划不再使用会吞掉 Android 写入异常的保存组件；空字节不会打开保存面板，原生写入失败不会显示成功。导入 0 KB、损坏或引用不完整的 JSON 时保留现有数据并显示错误；成功恢复后回到主页面，避免旧设置路由继续引用导入前资料。
- 设计：系统文档写入统一改为 `FilePicker.saveFile(bytes: ...)`；导入增加格式版本、字段类型、ID 唯一性和实体引用验证，并在数据库替换事务提交前执行 SQLite 完整性检查。移除未使用的 `file_saver` 与 `open_filex` 依赖。
- 安全与运维：不改变 schema；失败导入原子回滚，导入前恢复点仍保留。旧的 0 KB JSON 没有可恢复内容，应删除并用 build 27 重新导出。
- 文档：更新数据设计、接口、模块职责、安全运维、测试策略与变更记录。
- 验证：0 KB 拒绝、错误引用回滚、完整 v3 往返及恢复后六主页面渲染 5 项定向测试通过；全量测试 74 项通过、2 项按设计跳过，静态分析无编译错误。SQLite 快照完整性为 `ok`、外键错误为 0；371,284-byte 发布 JSON 已真实恢复至空数据库并核对 16 个账户、29 个类别、13 个预算、672 笔交易、34 个快照、7 个模板与 6 条周期规则。ARM64 Debug APK 为 build 27，Drive 副本哈希一致。
- 限制：系统文件提供者负责最终持久化与云端同步；应用能确认原生写入调用成功，但无法控制第三方云盘之后的同步状态。Flutter 构建提示 Android 项目及 `file_picker`、`share_plus` 未来需迁移 Built-in Kotlin，当前 build 27 不受影响。

### 快速模板前五拖动排序

- 行为：快速模板管理页的拖动手柄现已接入真实排序；全部模板可以跨越“前五/其他模板”边界重排，新的前五会立即用于闪电快捷面板，并在重新打开应用后保留。
- 设计：新增完整顺序 mutation 与 Repository 校验，拖动后一次性把全部模板写为连续唯一的 `sortOrder`，避免逐项更新出现重名次或短暂覆盖。列表使用 `ReorderableListView`，右侧手柄承担拖动，点击行仍进入编辑。
- 安全与运维：沿用既有 `transaction_templates.sort_order`，无 schema、权限、网络或用户交易数据变化；排序写入在数据库事务内整体替换。Debug 构建号升至 26，继续使用独立包名与数据目录。
- 文档：更新系统需求、模块设计、数据设计、接口、UI 基线、测试质量和变更记录。
- 验证：全量测试 71 项通过、2 项按设计跳过；静态分析无编译错误并保留 104 项既有 lint。第 6 个模板拖至首位后成为快捷面板第 1 个，Grab → UOB One 账户页实时刷新回归通过。SQLite 在线备份完整性为 `ok`、外键错误为 0；v3 JSON 验证 16 个账户、29 个分类、13 个预算、672 笔交易、34 个快照、7 个模板和 6 条周期规则。ARM64 Debug APK 核对包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `2026` 和 `arm64-v8a`；APK 与 JSON 的 Drive 副本 SHA-256 均与工程产物一致。
- 限制：手机上既有 Grab → UOB One 异常记录未存在于本地 SQLite，仍需从手机导出的最新 JSON 核对该笔记录的目标账户、状态和日期。

### 现金账户转账双边余额回归

- 行为：新增自动化回归，确认同币种、当月、已发生的现金账户转账会同时扣减转出账户并增加转入账户；本次不改变应用现有行为或用户数据。
- 设计：测试覆盖 Repository 落库与重新加载、Riverpod mutation 发布最新快照，以及新版交易表单实际选择转入账户并保存 `toAccountId` 的完整路径。
- 安全与运维：无数据库 schema、资料迁移、权限、网络或构建产物变化；未读取或改写手机端账本。
- 文档：更新测试质量说明和变更记录。
- 验证：`cash_transfer_balance_test.dart` 4 项通过；样本从现金账户 A 的 MYR 1,000 转出 MYR 250 至现金账户 B 后，两边余额分别为 MYR 750 与 MYR 350，重新加载、provider 快照及账户总览结果一致。
- 限制：标准测试路径无法复现“转入账户不变”；手机端仍需核对该笔交易是否为 `planned`、是否使用未来月份，以及安装包是否包含当前源码。

## 2026-07-19

### 外部 AI 财务分析提示词 v3

- 行为：跳转外部 AI 时分享的新提示词会要求分别分析消费发生、现金收付和信用负债；信用卡消费归入刷卡月份，信用卡还款只影响付款月份现金流，不再重复算消费。未来已确定和预计交易分列，未来 EPF/投资调整不会提前进入当前资产。
- 设计：提示词版本升级为 `finance_compass_three_lenses_v3`，兼容含派生字段的分析摘要 JSON 和用户手动上传的完整备份 JSON。新增截止时间、交易日期、转账两端、负数、币种、周期去重、预算与现金流来源优先级契约，并规定六段输出结构。
- 安全与运维：应用仍只分享提示词，不会自动上传 JSON；完整备份可能含账户、商户和备注，是否上传继续由用户在外部 AI App 内决定。无数据库 schema 或数据迁移。Debug 构建号升至 25，变更由 Git 独立提交保存。
- 文档：更新模块设计、外部接口、安全运维、测试质量、README 和变更记录。
- 验证：新增提示词单元测试，覆盖三口径、信用卡还款、投资调整、未来已确定、预计分列、完整备份兼容、MYR 货币和六个月范围。全量测试 65 项通过、2 项按设计跳过；静态分析无编译错误并保留 104 项既有 lint。SQLite 在线备份完整性为 `ok`、外键错误为 0；恢复 JSON 验证 16 个账户、29 个分类、13 个预算、672 笔交易、34 个快照、7 个模板和 6 条周期规则。ARM64 Debug APK 核对包名、Debug 标签、versionCode `2025` 和 `arm64-v8a`，APK 与 JSON 的 Drive 副本哈希一致。
- 限制：外部模型仍可能不完全遵守提示词；应用无法验证用户在第三方 AI App 中实际上传的文件或返回结果。

## 2026-07-18

### 交易页三种计算口径与方案 2 定版

- 行为：交易页新增“消费发生”“现金收付”“已承诺”三张可点击口径卡；消费发生用于监督当月消费，现金收付用于观察现金账户真实进出，已承诺用于核对当前信用卡与分期义务。账户、类型、类别快速筛选均已接入真实列表，交易明细不会因为切换口径而消失。
- 设计：按 Product Design 方案 2 重构交易页顶部为一宽两窄卡片、页点、范围分段和双指标说明。现金口径同时检查转账两端账户组；信用口径以当前 `ReportGroup.credit` 负余额为基准，并把当月信用交易拆成新增承诺与偿还抵扣。“包含预计”只叠加当月预计信用净变化，不写回真实负债。
- 安全与运维：无数据库 schema、资料迁移、权限或网络变化；Android Debug 构建号升至 24。所有代码更新在 `codex/transaction-basis-cards` 分支以独立 Git 提交保存。
- 文档：更新系统需求、模块设计、UI 基线、测试质量、视觉 QA 和变更记录。
- 验证：新增三口径 Widget 回归，样本验证消费发生 -MYR 400、现金收付 -MYR 300、已承诺 MYR 100，并验证包含预计后已承诺为 MYR 150；全量测试 63 项通过、2 项跳过，静态分析无编译错误。390×844 实现截图与方案 2 同屏检查通过。SQLite 在线备份完整性为 `ok`、外键错误为 0；恢复 JSON 验证 16 个账户、29 个分类、13 个预算、672 笔交易、34 个快照、7 个模板和 6 条周期规则。ARM64 Debug APK 核对包名、Debug 标签、versionCode `2024` 和 `arm64-v8a`，APK 与 JSON 的 Drive 副本哈希一致。
- 限制：已承诺的预计增量只使用当前选中月份，不把未来所有月份一次性提前计入；交易列表筛选不会反向改变顶部全月口径卡。

### 交易页“包含预计”统一计算口径

- 行为：交易主页面保留默认“已发生”，新增真正的“包含预计”口径；切换后列表仍显示已发生交易，并追加预计交易，顶部收入、支出和净现金流同步计入预计金额。进入未来月份时默认使用该合并口径，不再只显示预计而隐藏已确定记录。
- 设计：将 `TransactionsV2Screen` 原有“只看预计”布尔筛选改为“是否包含预计”，同一状态同时驱动列表和 `_totalForType` 汇总，避免界面筛选与顶部数字使用不同口径。
- 安全与运维：无数据库 schema、资料迁移、权限、网络或备份格式变化；只调整本地派生显示和计算。Debug 构建号升至 23，继续使用独立包名 `com.financecompass.app.debug`。
- 文档：更新系统需求、模块设计、测试质量和变更记录。
- 验证：新增 390×844 Widget 回归，验证默认 MYR 100 实际支出不显示 MYR 40 预计；切换后两笔同时可见且汇总为 MYR 140。全量测试 62 项通过、2 项按设计跳过；静态分析无编译错误并保留 104 项既有 lint。ARM64 Debug APK 构建成功，核对包名 `com.financecompass.app.debug`、版本名 `0.8.0-debug`、versionCode `2023` 和架构 `arm64-v8a`；完整 v3 JSON 导出 16 个账户、29 个分类、13 个预算、672 笔交易、34 个资产快照、7 个模板和 6 条周期规则。
- 限制：该切换只控制交易页面当前月份的展示与汇总，不改变交易状态、账户真实余额、预算或信用卡欠款口径。

### 固定 APK 与恢复 JSON 收尾作业

- 行为：每次完成任务后默认导出当前完整 v3 JSON、构建独立 Debug APK，并优先写入本机 Google Drive 同步目录；Windows EXE 默认不上传。
- 设计：新增 `tool/export_release_data_test.dart`，通过 Flutter 测试运行器和应用自身 Repository，从 SQLite 在线备份生成并校验包含账户、分类、预算、交易、投资快照、模板、周期规则与 meta 的恢复 JSON；新增发布与恢复作业文档。
- 安全与运维：默认交付目录为 `G:\我的云端硬盘\Finance Compass APK`，本地同步盘不可用时才使用 Drive 连接器；不创建公开分享，不上传临时 SQLite、银行账单或 EXE，旧 Drive 文件不覆盖、不删除。
- 文档：新增发布与恢复作业，更新文档索引、安全运维和变更记录。
- 验证：恢复 JSON 工具测试通过，导出 v3 文件 371,284 bytes，包含 16 个账户、29 个分类、13 个预算、672 笔交易、34 个投资快照、7 个模板和 6 条周期规则；SQLite 在线快照完整性为 `ok`、外键错误为 0。ARM64 Debug APK 构建成功并确认包名 `com.financecompass.app.debug`、应用名 `Finance Compass Debug`、versionName `0.8.0-debug`、versionCode `2022`。本地同步目录与 Drive 云端回读均确认 JSON 与 APK 大小分别为 371,284 和 84,956,046 bytes，均位于 `Finance Compass APK` 文件夹。
- 限制：Debug APK 使用开发签名，只供测试，不能直接提交 Google Play。

### UOB 历史银行结单快照校准

- 行为：UOB Lazada Credit Card 的 2026 年 3–6 月历史账单改为优先显示银行结单原始金额：MYR 2,364.37、1,995.35、4,352.32、5,346.29。后续还款不再把 6 月账单误显示为 MYR 5,746.30；当前欠款和额度使用继续保持 MYR 1,563.68。
- 设计：新增可选 `statementAmountOverride`，并由 `FinanceRepository.creditCardStatementAmountOverride` 从账户级、按结算日索引的 `app_meta` 读取权威账单快照。只有已核对结单存在时覆盖；缺失或格式错误时回退到交易与还款凭据推算。
- 安全与运维：写入前创建 `manual_before_uob_statement_overrides_20260718_134316.sqlite`。无 schema、权限或网络变更；快照随现有 v3 meta 备份机制迁移，不上传银行 PDF/XLS。
- 文档：更新系统需求、模块设计、数据设计、测试质量和变更记录。
- 验证：SQLite 完整性为 `ok`、外键错误为 0；当前物化欠款仍为 MYR -1,563.68。定向账期测试 14 项通过；全量测试 61 项通过、2 项按设计跳过；静态分析无编译错误并保留 101 项既有 lint。Windows x64 Release build 22 构建并启动成功，原生月份列表及 5 月历史详情均显示权威金额。
- 限制：旧账本仍缺少部分商户级历史明细；快照只校准原始账单总额和月份选择器，不伪造交易，也不改变交易明细列表。

### UOB 已使用额度与下期剩余额度对账

- 行为：UOB Lazada Credit Card 的当前欠款和额度使用已与银行 `Amount Used` MYR 1,563.68 对齐；本期账单已还清后，“下期已使用额度”会扣除确实抵扣到未出账消费的超额还款，不再显示未扣还款的毛消费。
- 设计：`calculateCreditCardBilling` 继续以下一完整账期的实际/已结算流水作为承诺上限，并用截至今天的实际欠款推导超额抵扣；只有明确转入信用卡的还款能够触发扣减，避免旧导入资料因余额不完整而把 PayLater 原始账单压低。删除银行明细不存在的 7 月 MYR 300 第 7 期 BTIPP；银行账单和交易表证明旧账本期初少记 MYR 984.49，因此校正 `initial_balance`、重建 `current_balance`，并在 `app_meta` 保存完整对账依据。
- 安全与运维：写入前创建 `manual_before_uob_amount_used_reconcile_20260718_131201.sqlite`；无 schema、权限、网络或导入导出格式变更。Windows 对照构建号升至 21；原始银行资料只用于本地核对，未上传外部服务。
- 文档：更新系统需求、模块设计、数据设计、测试质量和变更记录。
- 验证：`5,346.29 + 3,371.32 - 7,153.93 = 1,563.68`；修复后物化余额与从期初余额及全部实际流水重算的余额均为 MYR -1,563.68，SQLite 完整性为 `ok` 且外键错误为 0。`credit_card_billing_test.dart` 12 项通过；全量测试 61 项通过、2 项按设计跳过，静态分析无编译错误并保留既有 104 项 lint。
- 限制：2026 年 3–5 月旧账本仍缺少部分商户级原始明细，因此本次只用银行连续账单校正期初差额，不伪造无法从来源确认的历史商户交易；银行 PDF/XLS 仍是历史账单最终校对来源。

### Lazada PayLater 已确定分期补全

- 行为：Lazada PayLater 结算日按官方账单校正为每月 9 日、还款日维持每月 25 日。2026 年 7 月账单保留四个可核对项目：LiberNovo MYR 180.88、ARENCIA MYR 7.86、24HR SHIP MYR 7.17，以及 361 Flame MYR 38.34 与同额全额退款，净账单为 MYR 195.91。
- 设计：LiberNovo 补齐为 12 期，2026 年 6 月第 1/12 期保持原记录，7 月至 2027 年 5 月依次记录第 2/12–12/12 期；两个 6 期小额分期按每月 9 日账单结算日归期。所有 Lazada PayLater 分期均标记为 `actual`，退款以同账户负支出保留审计轨迹。
- 安全与运维：修改前创建 SQLite 完整备份；通过实际交易重算物化余额，不直接硬改欠款口径。当前欠款由 MYR 783.70 校正为 MYR 2,049.86，等于 2026 年 7 月至 2027 年 5 月已确定账单合计。无 schema、权限、网络或导入导出格式变更，未上传 Google Drive。
- 文档：更新数据设计、测试质量和变更记录。
- 验证：7–9 月账单各为 MYR 195.91，10 月为 MYR 195.97，2026 年 11 月至 2027 年 5 月各为 MYR 180.88；所有月份逐期匹配，账户不存在 `planned` Lazada 交易，SQLite 完整性为 `ok` 且外键错误为 0。
- 限制：截图展示的是商品原购买日期，而应用账单归属使用实际结算日；因此记录说明保留商品和期数，交易日期按每月 9 日结算，以确保账单月份准确。

### Shopee PayLater 原始账单与 UOB 还款对账

- 行为：账单月份现在始终显示该期原始账单额，还款后不会变成零；每月 1 日结算的账单按结算日前一天命名，因此 8 月 1 日结算显示为 7 月账单。Shopee PayLater 的 7/8/9 月已确定账单分别为 MYR 313.29、313.31、243.47，对应 8/10、9/10、10/10 还款。
- 设计：新增 `CreditCardBillingPeriod.billingMonthDate` 和 `calculateCreditCardOriginalStatementAmount`。正常资料按单一账期来源卡流水计算；旧导入资料缺少消费明细时，以结算日至还款日的明确转入还款作为原始账单额下限。下一期已使用额度不再读取累计账户余额。
- 安全与运维：每次数据校正前均建立本地 SQLite 完整备份；3–6 月四笔账单还款统一规范为 UOB Credit Card 转账到 Shopee PayLater，UOB 表中 MYR 238.38 的 6 月账单还款按银行交易日校正为 7 月 1 日。3 月缺失的 MYR 184.52 和 4 月缺失的 MYR 161.33 以明确标注的 Shopee 历史账单明细补差写入，使当前欠款由 MYR 524.22 校正为 MYR 870.07；2 月及更早记录保持不变。无 schema、权限、网络或备份格式变更；构建号升至 20，未上传 Google Drive。
- 文档：更新 README、系统需求、架构、模块设计、数据设计、内部接口、安全运维、UI 基线、测试质量、视觉 QA 和变更记录。
- 验证：领域回归覆盖已还款月份保留原始账单、每月 1 日结算的月份命名，以及 7 月三笔 MYR 69.85、161.33、82.11 合计 MYR 313.29；数据逐期核对得到 3–9 月 MYR 184.52、212.32、203.43、238.38、313.29、313.31、243.47，当前欠款与未来三期合计均为 MYR 870.07。全量测试 59 项通过、2 项按设计跳过，静态分析无编译错误，Android ARM64 Debug 与 Windows x64 Release 均构建成功。
- 限制：3 月和 4 月缺失的原始商户级明细无法从现有资料恢复，因此补差分别记在账单月份末日并明确标注为“历史明细补差”；银行和 Shopee 原始账单仍是最终校对来源。

### 未来已确定账单与结算日余额核对

- 行为：信用账户可继续向未来浏览由 `actual`/`settled` 记录形成的已确定账单；每月金额和还款日随真实账期切换，未来 `planned` 不进入。账单金额改为结算日结束时的账户待还余额，因而会正确纳入期初欠款、消费、信用卡转出、还款、退款和调整。
- 设计：`availableCreditCardBillingPeriods` 扩展为未来已确定、本期和历史三段；新增 `FinanceRepository.creditCardStatementBalance` 读取结算日余额。账期流水合计与最终待还余额明确分离，详情和账户摘要均传入下一结算日余额。
- 安全与运维：无 schema、权限、网络、备份格式或历史数据改写；仅调整本地派生读取。构建号升至 19，Debug 包继续使用 `com.financecompass.app.debug` 并与正式版数据隔离；按用户要求未上传 Google Drive。
- 文档：更新 README、系统需求、模块设计、数据设计、内部接口、安全运维、UI 基线、测试质量、视觉 QA 和变更记录。
- 验证：Shopee 回归覆盖 2026 年 7/8/9 月 `313.29`、`313.31`、`243.47` 及对应 8/10、9/10、10/10 还款日；UOB 样本核对消费 MYR 3,371.32、还款及退款 MYR 7,153.93，证明毛消费合计不能替代截止日待还余额。最终全量测试与构建结果见测试质量文档。
- 限制：银行表格未提供账单期初余额或最终 Statement Balance 时，只能核对期间流水净变动；最终待还金额仍依赖应用内导入完整期初余额及交易。

### 编辑页确认删除与有符号交易金额

- 行为：新版交易编辑页和旧高级编辑表单均新增删除入口，点击后先确认，取消时留在编辑页，确认后删除并立即刷新交易、信用卡明细和账户余额。交易金额及跨币种转入金额现在允许有限的正数、零和负数；负数在列表中按实际代数方向显示，不出现重复负号。
- 设计：`TransactionFormResult` 新增互斥的 `deletedTransactionId` 返回动作；交易主列表、高级列表和信用卡详情统一交给 `TransactionMutations.deleteTransaction` 执行现有余额逆转。表单改用带符号小数键盘，只拒绝非数字、`NaN` 与无穷；数据库 schema 与加减规则保持不变。
- 安全与运维：删除仍不可撤销且必须二次确认；无 schema、权限、网络、备份格式或历史数据迁移。构建号升至 18，Android Debug 应用 ID 继续为 `com.financecompass.app.debug`，与正式版数据隔离；按用户要求未上传 Google Drive。
- 文档：更新 README、系统需求、模块设计、数据设计、内部接口、安全运维、UI 基线、测试质量、视觉 QA 和变更记录。
- 验证：完整测试 55 项通过、2 项按设计跳过；新增编辑删除取消/确认、零与负金额保存、负支出/负转账余额方向及删除恢复测试。静态分析无编译 error，维持项目既有 104 项 lint。Android ARM64 Debug 与 Windows x64 Release 构建成功；`aapt` 核对 Debug 包名 `com.financecompass.app.debug`、版本名 `0.8.0-debug` 和 versionCode `18`。
- 限制：负金额表示对所选交易类型方向的代数冲销，不会自动改写交易类型；用户若要保留明确的退款/冲销语义，仍需在商户或说明中标注。

### 信用卡历史账单月份切换

- 行为：信用卡详情“查看账单”现在打开历史账单月份列表，显示每期账单周期、还款日和账单金额；选择后主金额、时间线和交易明细切换到对应账期，并可返回本期。实时额度使用不随历史选择改变。
- 设计：新增指定结算月份的账期重建、可回溯账期枚举和单期账单金额计算；账期列表从本期向前覆盖至最早相关实际交易，最多 120 期。历史月份仍使用完整年月日和账户级结算日，不读取旧单笔结算日期或预计交易。
- 安全与运维：无 schema、权限、网络、备份格式或历史数据改写；历史账单为本地只读派生视图。构建号升至 17，Debug 包继续与正式版隔离。
- 文档：更新 README、系统需求、架构、模块设计、数据设计、内部接口、安全运维、UI 基线、测试质量、视觉 QA 和变更记录。
- 验证：完整测试 50 项通过、2 项按设计跳过；领域测试覆盖 25 日结算/14 日还款的跨月归属，390×844 Widget 测试覆盖打开月份列表、选择往期及明细隔离。静态分析无编译 error，保留既有 104 项 lint；Android ARM64 Debug 与 Windows x64 Release 构建成功，`aapt` 核对 Debug versionCode `2017`。
- 限制：账单历史由现有交易实时推导，不保存银行原始账单快照；若历史交易已删除或修改，对应往期账单也会随之重算。

### 信用卡承诺负债与周期交易状态统一

- 行为：信用卡“当前欠款”、信用负债汇总和额度使用现在包含所有已发生/已结算记录，包括未来日期但已经锁定额度的分期；所有预计记录均不计入。信用卡本期账单、未出账和还款状态仍严格截止今天。新增交易批量生成和周期规则生成的所有月份统一继承用户选择的“已发生”或“预计”状态。
- 设计：新增 `creditCardCommittedOutstandingBalance` 专用查询，并在无显式截止日期的信用卡汇总及额度组件使用物化实际余额；带截止日期的账单和历史查询保持原接口。移除表单生成器、Repository、`TransactionService`、规则创建和规则编辑中把未来月份或预计规则强制改写状态的逻辑。
- 安全与运维：无数据库 schema、权限、网络、备份格式或历史数据改写；只调整读取和新生成记录的状态契约。构建号升至 16，Android Debug 身份保持 `com.financecompass.app.debug`，与正式版数据隔离；按用户要求未上传 Google Drive。
- 文档：更新 README、系统需求、架构、模块设计、数据设计、内部接口、安全运维、UI 基线、测试质量、视觉 QA 和变更记录。
- 验证：完整测试 48 项通过、2 项按设计跳过；静态分析无编译 error，保留项目既有 104 项 lint info/warning；Android ARM64 Debug 与 Windows x64 Release 构建成功，`aapt` 核对 Debug 包名、标签、版本名和 versionCode `2016`。
- 限制：未来“已发生”会立即占用信用额度，但不会提前进入本期账单或触发还款逾期；若用户只想表达尚未确认的未来支出，应选择“预计”。

## 2026-07-17

### 交易三点菜单与可选周期生成恢复

- 行为：新版交易行继续支持点击整行直接编辑，并在金额右侧恢复旧版三点菜单：编辑、复用新增、保存模板、保存周期和删除。新增交易及周期计划可直接选择生成未来 1–12 个月，不再固定三个月。
- 设计：菜单复用 `FinanceActionMenuButton`，五项分别接入编辑器、复制草稿、模板 mutation、周期规则 mutation 和确认删除。`TransactionComposerPage` 批量生成时首月保持表单状态，之后月份标记为预计；创建周期规则时禁用表单批量生成，避免未使用的重复草稿。
- 安全与运维：无数据库 schema、权限、网络或备份格式变化；删除仍要求二次确认。构建号升至 15，Android Debug 身份继续为 `com.financecompass.app.debug`，不会覆盖正式版。
- 文档：更新系统需求、模块设计、内部接口、UI 基线、测试质量、视觉 QA 和变更记录。
- 验证：完整测试 44 项通过、2 项按设计跳过；静态分析无编译 error，保留项目既有的 104 项 lint info/warning；390×844 菜单实现截图已与旧版截图合成同屏比较；Android ARM64 Debug 与 Windows x64 Release 构建成功，并核对 Debug 包名、标签和版本号。
- 限制：Widget 截图运行时缺少 CJK 和 Material icon 字体，测试图中文字及图标显示为方框；实体安装包使用正常系统字体和图标。

### 交易长按多选与原子删除

- 行为：交易主列表支持长按进入选择模式、点击追加或取消选择、全选当前可见结果，并在二次确认后删除一笔或多笔交易；删除成功后列表、现金流与账户余额立即刷新。
- 设计：新增数据库、Repository 和 mutation 三层批量删除契约；数据库在单一事务中先恢复所有来源/目标账户余额再删除记录，任一所选 ID 失效则整批回滚。交易页改为监听 `financeRepositoryProvider` 的最新快照。
- 安全与运维：无 schema、权限、网络或备份格式变化；删除不可撤销且只会在用户明确确认后执行。Debug 构建号升至 14，正式版应用 ID 不变。
- 文档：更新系统需求、模块设计、数据设计、内部接口、测试质量和变更记录。
- 验证：完整测试 42 项通过、2 项按设计跳过；新增长按多选实时删除 widget 回归，以及失效 ID 导致整批回滚的数据库回归。静态分析无编译 error，保留 101 项既有 lint info/warning。
- 限制：删除已由周期规则生成的交易不会删除周期规则本身；主列表支持多选删除，搜索结果仍以点击编辑为主。

### 信用卡转出纳入账单

- 行为：信用卡作为转出账户时，转账按发生日期进入该卡本期或未出账账单，并在账单明细显示目标账户；信用卡作为转入账户时仍按还款处理。信用卡 A 转至信用卡 B 不会遗漏 A 的负债，也不会在 B 重复计算消费。
- 设计：账单金额沿用既有方向计算，补齐信用卡详情对 `transfer` 来源记录的筛选、文案、图标和编辑入口；新增双信用卡方向回归。
- 安全与运维：无 schema、权限、备份格式或历史数据改写。
- 文档：更新系统需求、数据设计、模块设计、测试质量和变更记录。
- 验证：完整测试 40 项通过、2 项按设计跳过；信用卡 A→B 的转账在 A 计为账单、在 B 计为还款。静态分析无编译 error，保留 101 项既有 lint info/warning。
- 限制：银行可能对余额转移收取额外手续费；只有用户另行记录的手续费交易才会进入账单。

### 信用卡状态严谨化与投资市值入口恢复

- 行为：信用卡本期已还清后显示“本期已还清”；若仍有未出账消费，主金额改为“下期已使用额度”，不再因为还款日已过而误报逾期。待还款、今日到期、逾期未还、尚未出账、无欠款和账期待设置分别显示对应状态。投资/退休账户详情新增“录入/更新当前市值”按钮。
- 设计：新增 `CreditCardDisplayState`，状态判断优先使用本期剩余应还金额，再结合账期活动和还款日期。市值按钮打开锁定当前账户的资产快照表单，投入/取出仍由交易计算；同时修复窄屏长账户名称导致的下拉框溢出。
- 安全与运维：无数据库 schema、权限、网络或备份格式变化；新增市值仍通过现有资产快照 mutation 写入，不重写历史交易。
- 文档：更新系统需求、模块设计、测试质量和变更记录。
- 验证：完整测试 39 项通过、2 项按设计跳过；新增信用卡已还清/尚未出账/今日到期/逾期/无欠款状态测试，以及 390×844 投资市值入口与窄屏布局测试。静态分析无编译 error，保留 101 项既有 lint info/warning。
- 限制：是否“本期已还清”由当前账期存在已出账消费且剩余应还为零推导；应用尚未保存银行账单原始结清标志。

### 实际、预计与默认截止月口径统一

- 行为：无时间范围的账户、净资产、贷款和投资/退休汇总默认截止当前月；未来月份的 EPF 增值调整不会提前进入当前显示。信用卡账单截止今天。显式预测仍包含范围内的实际与预计交易。
- 设计：账户列表不再直接读取物化 `current_balance`；投资流入默认补上当前月截止；信用卡计算新增截止余额并排除今天之后的交易；现金流预测从截至今天的余额开始，避免本月未来记录重复累计。
- 安全与运维：无 schema、权限或外部接口变化；不改写用户交易状态或金额，只调整读取与计算边界。
- 文档：更新系统需求、数据设计、模块设计、内部接口、测试质量和变更记录。
- 验证：完整测试 36 项通过、2 项按设计跳过；新增 EPF 未来实际/预计、信用卡未来交易和预测单次累计回归。静态分析无编译 error，保留 102 项既有 lint info/warning。
- 限制：物化 `current_balance` 仍用于事务写入和回滚，业务展示必须继续通过带截止日期的 Repository 查询。

### 信用卡旧结算日期归一化

- 行为：信用卡消费只按实际发生日期和账户级结算日归入账期；旧版每笔交易的结算日期不再影响本期账单、未出账和月度统计。旧交易表单在涉及信用卡时不再显示单笔结算日期。
- 设计：启动时通过一次性标记 `credit_card_account_billing_dates_v1` 将涉及信用卡的旧交易 `transaction_date` 归一为 `record_date`；v1/v2 JSON 导入执行相同规则。新导出升级为 v3 并声明 `transaction_date_semantics=occurrence_date`，再次导入时保留用户后来修改的发生日期。非信用卡交易仍保留原有双日期兼容行为。
- 安全与运维：无 schema、金额、余额、账户或权限变更；迁移只修改信用卡关联交易的日期字段，重复启动不会再次处理。导入前恢复点流程保持不变。Android 构建号升至 10，以触发测试设备上的 Debug 更新安装。
- 文档：更新系统需求、数据设计、接口、测试质量和变更记录。
- 验证：完整测试 33 项通过、2 项按设计跳过；新增数据库升级与旧 JSON 导入回归，验证信用卡日期被归一、现金交易日期不变、v3 已编辑日期往返保留，信用卡账期测试继续通过。静态分析无编译 error。
- 限制：旧版单笔结算日期不会另存为历史审计字段；更新前如需保留该字段，应先导出旧版 JSON 作为档案。

### 交易编辑、信用卡账期与预测范围修复

- 行为：新版交易列表和搜索结果可点击编辑；信用卡本期/未出账明细可查看并修改原交易，记录还款统一使用新版交易编辑器。交易页允许进入未来月份并自动显示预计记录；总览预测可选择未来 7、30、60、90 天。
- 设计：新增完整年月账期模型 `CreditCardBillingPeriod`，按上期结算次日至本期结算日区分本期账单，按本期结算次日至下期结算日区分未出账；新增精确日期窗口现金流查询。编辑交易保留原 ID 和录入时间。
- 安全与运维：无数据库 schema、备份格式、权限或网络接口变更；所有查询和编辑继续使用本地 Repository/mutation 流程。Android 构建号升至 9，确保测试设备把修复包识别为更新版本。
- 文档：更新系统需求、数据设计、模块设计、内部接口、UI 基线、测试质量、视觉 QA 与变更记录。
- 验证：32 项自动测试通过，2 项按设计跳过；覆盖跨月/月末账期、精确预测窗口、未来月份交易、编辑 ID 保留和预测范围切换。静态分析无编译 error。
- 限制：总览预测只使用已经记录的未来交易和信用卡还款提醒，不会自动猜测尚未建立的收入或支出；实体 Android 的返回键、日期选择器和长列表触控仍需 Debug 包复验。

### 预算构成与主题拖动预览校准

- 行为：预算顶部恢复定版的五分类构成，不再以醒目的“其他”合并大量分类；实际与预计占用分别显示为实色和斜纹。外观页现在可左右拖动 12 款主题卡片，并可切换总览/交易预览，只有点击“设为当前主题”才实际应用。
- 设计：预算占比明确采用分类基础预算除以当月已分配预算，并保留未标名余量区段；新增 `FinanceThemeTokens`，使共享背景、卡片、图标和分段控件随预览调色板变化。
- 安全与运维：未改变数据库 schema、备份格式、导入导出或权限；主题仍仅保存为本地偏好。
- 文档：更新架构、模块设计、UI 参考、测试质量、追踪关系、视觉 QA 和变更记录。
- 验证：在 390×844 视口生成预算与外观实现截图，并与定版参考合成同屏比较；新增主题拖动、预览不自动应用和预览内容切换的 widget 测试。完整测试 26 项通过、2 项按设计跳过；ARM64 Debug APK 构建成功，并核对包名 `com.financecompass.app.debug`、应用名“Finance Compass Debug”和开发签名。
- 限制：Flutter widget 截图运行时缺少中文字体，自动截图中的中文字形显示为方框；Android 使用系统 CJK 字体，不受此测试环境限制。实体 Android 触控和系统栏间距仍需通过本次 Debug 包复验。

### 新 UI 真实功能接线与资料导入修复

- 行为：设置页现在可选择 JSON、预览数量、确认后完整导入；完整备份、AI 摘要 JSON 和未来计划 CSV 可通过系统保存面板导出。预算、快速模板、周期规则、信用卡明细、报表入口和分类管理改为读取及写入真实账本，空数据不再显示参考图示例金额。
- 设计：页面写操作统一经 repository/mutation provider 刷新状态；模板支持排序、编辑、试用和删除，周期规则支持启停、编辑、删除及主动生成未来计划；报表详情复用既有真实计算页面。
- 安全与运维：导入为事务式完整替换，执行前自动保存私有恢复点；外部 AI 只在用户主动分享摘要时离开应用。Google 登录、系统通知调度和附件保存继续明确标为计划中。
- 文档：更新接口、模块、数据、安全运维、测试、追踪和变更记录。
- 验证：新增 JSON v2 导出—预览—导入往返测试；`flutter test` 25 项通过、外部 AI 网关 1 项按设计跳过；`flutter analyze` 无编译 error。
- 限制：导入暂不支持记录级合并；Google 登录/同步、系统级通知、交易附件、贷款摊销和银行品牌图标尚未实现。

### Android Debug 版独立安装身份

- 行为：Debug 版显示为“Finance Compass Debug”，可以与正式版同时安装，不会覆盖正式版。
- 设计：Gradle `debug` build type 使用 `applicationIdSuffix = ".debug"` 和 `versionNameSuffix = "-debug"`；Manifest 通过构建变量选择应用名称。
- 安全与运维：Debug 应用 ID 为 `com.financecompass.app.debug`，正式版保持 `com.financecompass.app`；两者使用独立 Android 沙盒和本地数据库。Debug 包仍使用开发签名，仅限测试。
- 文档：更新 README、架构、安全运维、测试和变更记录。
- 验证：执行 ARM64 分包 Debug 构建，并检查 APK Manifest 的包名、版本名和应用标签。
- 限制：Debug 与正式版本地数据不会自动共享；需要通过应用内备份、导入或恢复迁移测试资料。

## 2026-07-16

### v0.8.0 全新 UI 与无损资料迁移

- 行为：六个主页面采用深海主题；交易页使用右下角同尺寸闪电和加号；新增信用卡额度、结算日、还款日、本期账单和未出账；加入基础贷款账户类型。
- 设计：新增 Compass 共享组件和 v2 页面；旧详细报表/高级设置继续保留，避免功能回退；设置主界面移除隐私与诊断入口。
- 数据：schema 由 v6 升级到 v7；分类增加样式字段；模板和周期规则迁入独立表并暂时双写旧 JSON；完整备份升级为 v2。
- 安全与运维：升级前生成 SQLite 与逐表 JSON 恢复点；升级后执行完整性和外键检查；Google 登录仍为计划中。
- 文档：建立系统需求、架构、模块、数据、接口、安全运维、测试、追踪和变更记录文档。
- 验证：`flutter test` 全部通过（24 项通过，AI 本地网关用例在服务未启动时跳过 1 项）；Windows debug build 成功；Android 发布构建仍需在 Play Store 发布阶段复验。
- 限制：Android 当前构建仍使用 Kotlin Gradle Plugin；Flutter 已提示未来版本需要迁移到 Built-in Kotlin，正式升级 Flutter 前需同步检查 `file_picker`、`file_saver` 与 `share_plus` 的兼容版本。
- 限制：Google 登录/同步、贷款摊销、系统通知调度和银行品牌图标尚未实现。

### 29 张确认截图定稿 UI 校准

- 行为：交易主页面改用月份现金流、已发生/即将发生、类型筛选与紧凑分组列表；旧完整筛选仍可从高级筛选进入。
- 设计：以 `artifacts/ui-reference/` 中 29 张截图及预算补充图作为唯一基线，重做六个主页面、信用卡、交易自动化、预算、报表详情和设置详情；账户、预算、报表与设置采用高密度列表层级。
- 安全与运维：仅修改 Flutter 展示层和导航组合，不改数据库 schema、财务计算或备份格式。
- 文档：新增 `UI_REFERENCE.md`，更新需求、模块、数据、测试、追踪与 `design-qa.md`。
- 验证：390 像素宽原生 Windows 逐页检查；修复总览、预算构成和信用卡详情的实际 RenderFlex 溢出；`flutter test` 24 项通过、AI 本地网关用例跳过 1 项；Windows debug 构建成功。`flutter analyze` 无 error，仍有项目既有的 info 与 4 个未使用声明/变量 warning。
- 兼容性：真实本地金额和账户名继续显示，参考图示例数据不会覆盖账本。旧信用卡空字段仅在编辑页显示建议默认值，保存前不写入。
- 限制：Google 登录/同步、贷款摊销、系统通知调度和银行品牌图标尚未实现；Android release 与实体设备视觉回归仍待 Play Store 发布阶段执行。

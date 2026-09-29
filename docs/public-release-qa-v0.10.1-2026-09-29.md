# Finance Compass v0.10.1 公开发布 QA

验证日期：2026-09-29。版本：`0.10.1+45`。发布标签：`v0.10.1`。

> 状态：**已公开发布**。源码经 [PR #9](https://github.com/lawpowen/finance-compass-app/pull/9) 合并到 `main`；[v0.10.1 Release](https://github.com/lawpowen/finance-compass-app/releases/tag/v0.10.1) 为非草稿、非预发布，GitHub `releases/latest` 指向该版本。README 与 [自托管指南](SELF_HOSTING.md) 中的六个 v0.10.1 直链均可无认证下载，详见下文“GitHub 公开回读”。上一版本见 [v0.10.0 公开发布 QA](public-release-qa-v0.10.0-2026-09-25.md)。
>
> 发布准备历史：本文件最初于 2026-09-29 以“发布准备 QA（待构建发布）”创建，只记录源码检查，构建、资产与 GitHub 回读各项当时均为待填。下文“源码检查”保留当时的结果；“构建与平台检查”“发布资产”“GitHub 公开回读”为之后实际构建、上传并回读后补填的事实。仍未执行的检查列在“已知限制”中，不能视为已通过。

## 发布范围

本版收录分支 `codex/credit-billing-audit` 上 2026-09-29 的两轮信用卡修复。这些修复在 v0.10.1 之前均未发布，现已随 v0.10.1 公开发布。各项行为、设计、回滚与限制见 [变更记录](CHANGELOG.md) 中 2026-09-29 的“信用卡‘当前欠款’与账期边界修复”和“信用卡复审跟进”两条：

- 当前欠款与负债总额：账户页信用卡行“当前欠款”、信用分组“负债总额”与详情额度条使用同一承诺负债口径，计入下月以后已确定的 `actual`/`settled` 分期，排除 `planned`；溢缴卡显示 0，不再计入负债。只有远期已确定分期的卡显示“尚未出账”。
- 当天账期：截至今天的账期按今天日终余额计算，当天较晚时刻的消费不再让“本期应还”被少算。
- 净资产：账户页“净资产”加回信用卡溢缴贷方余额（本月取当前余额，历史月份取月末截止余额）；负债和行金额仍不低于 0。
- 历史截止：历史统计月份的信用卡账期摘要在精确截止时刻读取余额。
- 历史原始账单：该期有来源流水时取来源流水净额，超额还款不再抬高账单；只有完全缺少来源流水的旧导入月份才以还款为凭据，结果下限为 0，并兼容同币种旧版 `toAmount=0`。
- 输入校验：信用卡账户设置的余额字段改名“信用卡余额”，常显“欠款填负数，溢缴款填正数”，按原符号读写并拒绝 `NaN`/`Infinity`；“记录还款”只接受有限正数。
- 提前还款：“本期已还清”但更远账期有已确定分期时，按钮为可点击的“提前还款”，对话框默认金额为当前欠款。

本版版本同步只改版本文字，不改应用逻辑：`pubspec.yaml`、设置页“关于与支持”版本文字（`版本 0.10.1+45 · 本地优先的个人财务罗盘`）、`web/service-worker.js` 的 `CACHE_NAME`（`finance-compass-shell-v0.10.1`）、两份 Compose 的本地镜像标签（`finance-compass-web:0.10.1`）及 `tool/package_selfhost.ps1` 默认版本与输出目录（`0.10.1`、`artifacts/release/v0.10.1`）。

无数据库 schema、迁移、JSON 备份格式、应用 ID、系统权限或依赖变化；修复只改变派生显示值与输入校验，不写入或修正任何已有余额与交易。

## 源码检查（发布准备阶段完成）

工具链：Windows PowerShell 以绝对路径调用 `C:\Users\pwlaw\tools\flutter\bin\flutter.bat` / `dart.bat`，版本为 Flutter 3.44.1、Dart 3.12.1。

- `dart format --output=none --set-exit-if-changed lib test`：检查 142 个文件，0 个需改，退出码 0。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：退出码 0，共 67 项，均为既有问题（0 error、2 warning、65 info），与 v0.10.0 基线数量相同。
- `flutter test`：176 项通过，2 项按设计跳过（`visual_qa_capture_test.dart`），0 项失败。
- `pubspec.lock`（SHA-256 `9E53C573…AED7BD7EB`）与 `analysis_options.yaml` 在检查前后哈希相同，无改动。
- 本机日志：`artifacts/qa/release-v0.10.1-{toolchain,format,analyze,test,hashes-before,hashes-after}.log`（`artifacts/` 不随仓库提交）。

## 构建与平台检查

产物从源码提交 `dbd35a568995bbd8b71f84ae4bf57a25b06f243c` 构建（其 tree 与后来的 `main` 合并提交相同，见下文）。本机构建日志：`artifacts/qa/release-v0.10.1-{apk,windows,installer,web}.log`；产物逐项核对由 `artifacts/qa/verify-v0.10.1.ps1` 完成，结果写入 `artifacts/qa/release-v0.10.1-assets.json`（均不随仓库提交）。

- [x] Android Release：`flutter build apk --release` 成功。`apksigner` v2 签名校验通过；包名 `com.financecompass.app`，versionName `0.10.1`，versionCode `45`；包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三种 ABI。签名证书 SHA-256 为 `529be690a91228ffe087c6add3a4c730b71f7cd2f6497a796ffff0913dc882a7`，与 v0.10.0 相同，因此可覆盖升级。构建日志中有既有的 Kotlin Gradle Plugin 警告（app 及 `file_picker`、`share_plus` 插件应用 KGP，未来版本 Flutter 可能因此构建失败），不影响本次构建成功，本版未处理。
- [x] Windows Release：`flutter build windows --release` 成功；`FinanceCompass.exe` 的 ProductVersion/FileVersion 为 `0.10.1+45`。Inno Setup 6.7.3 安装器编译成功，从同一 `build/windows/x64/runner/Release/` 目录打包（日志显示含 `FinanceCompass.exe`、`flutter_windows.dll`、插件 DLL、`data/flutter_assets` 与支持二维码）。便携 ZIP 共 23 个条目，已确认含 `FinanceCompass.exe`、`flutter_windows.dll`、`data/app.so` 与支持二维码资源。安装器本身**未拆包检查**。
- [x] 自托管 Web：`tool/build_web.ps1` 以 `Web build complete: build/web (142 files, 36 precache entries and 102 fallback fonts verified)` 结束，`tool/sqlite3_wasm.lock` 校验通过。三份 runtime ZIP 各 150 个条目，均含 `FinanceCompass-SelfHost/webroot/index.html` 与 `FinanceCompass-SelfHost/compose.yml`，没有使用反斜杠的条目；三份均核对 `webroot/version.json` 为 `0.10.1` / `45`、`service-worker.js` 的 `CACHE_NAME` 为 `finance-compass-shell-v0.10.1`、`compose.yml` 镜像标签为 `finance-compass-web:0.10.1`。
- [x] 私人文件：按文件名筛查 APK 与四份 ZIP 的全部条目，没有 `key.properties`、JKS/keystore、SQLite/`.db` 数据库或名称含 `backup` 的文件。安装器未拆包，只能依据其打包来源目录与便携 ZIP 相同来判断。
- [x] 支持二维码：APK 与四份 ZIP 内的 `assets/support/touch-n-go-support-qr.jpg` 各只有一份，SHA-256 均为 `2B2413CDD153BAA8A1880D28E21B07EABA32CEDE0F609D0461C43947DAD8780B`，与 v0.10.0 相同；本次发布时人工看图确认收款人为 `LAW PO WEN`。
- [ ] 实机：**未执行**。未在交互桌面打开 Windows 安装版或便携版的“关于与支持”页，未在 Android 真机覆盖升级 v0.10.0（见“已知限制”）。

## 发布资产

`SHA256SUMS.txt` 覆盖以下六个文件，重新计算六项哈希并逐项比对全部一致。

| 文件 | 大小（bytes） | SHA-256 |
|---|---:|---|
| `FinanceCompass-Android-v0.10.1.apk` | 64,766,623 | `6ff6173d9af8bdcb56abb3f7c1762f339f8b72b18cd855e6641020d8a87e689f` |
| `FinanceCompass-Windows-x64-Setup-v0.10.1.exe` | 12,503,808 | `d96b5bd16ffa394df144b43d6e8ca57ea0a17aca6ecd130ba8270e82f1b63df0` |
| `FinanceCompass-Windows-x64-Portable-v0.10.1.zip` | 14,810,643 | `dbaf362bbdb2eb889255e4e252393f00dd8d5e8e3e0b7968a857b02036df0fae` |
| `FinanceCompass-SelfHost-Ubuntu-v0.10.1.zip` | 16,581,101 | `9391f50794fda9f113825dd524dc7e40192326cff7b882d04b43adb04bfadc0c` |
| `FinanceCompass-SelfHost-Windows-v0.10.1.zip` | 16,581,101 | `ce5bad0e8e9bfd38ec7195016137fc8fff40014d5b32cf40c98db75321ccd807` |
| `FinanceCompass-SelfHost-macOS-v0.10.1.zip` | 16,581,101 | `669a985e540b4ddf4751457cb269e82913fe7fedf2cda0f1930f495e20454f41` |

第七个附件 `SHA256SUMS.txt` 为 659 bytes，SHA-256 `ee98b25388e6eb87959d599116d998fb2b389da458c023a0b451c06f7f68bafa`。

三份自托管 ZIP 大小相同但哈希不同，与 v0.10.0 的情况一致；以上数值均以 `artifacts/qa/release-v0.10.1-assets.json` 与 `release-v0.10.1-public.json` 为准。

## GitHub 公开回读

以下步骤按 [发布流程](RELEASE_WORKFLOW.md) 完成（回读结果：`artifacts/qa/release-v0.10.1-{source,public}.json`，不随仓库提交）：

- [x] [PR #9](https://github.com/lawpowen/finance-compass-app/pull/9) 已合并。`main` 合并提交为 `4c1166b6e3f69fe6bfb4fecfbdeb7d82ed152b66`，其 tree SHA `f59b26aafa0534a31e2280e36282c9d14d96f916` 与构建产物时的源码 tree 完全相同，因此上表产物来自已合并的源码。
- [x] `v0.10.1` 是 annotated tag，peel 后指向上述合并提交。
- [x] [v0.10.1 Release](https://github.com/lawpowen/finance-compass-app/releases/tag/v0.10.1) 已公开，非草稿、非预发布；GitHub `/releases/latest` 返回 `v0.10.1`。
- [x] 附件共七个：六个包和 `SHA256SUMS.txt`。GitHub 回读的每项 size 与 SHA-256 digest 都与本机 `artifacts/release/v0.10.1` 中的文件一致。
- [x] 七个附件的公开下载地址（含 README 六条直链）逐条发出无认证 HEAD 请求，均返回 200，`Content-Length` 与本机文件大小一致。
- [x] 发布后已移除 README、`SELF_HOSTING.md`、`docs/README.md`、`RELEASE_WORKFLOW.md` 与 `SECURITY_AND_OPERATIONS.md` 中“待构建发布”的临时说明，本文件状态改为已发布。

发布包内的 `SELF_HOSTING.md` 是构建时快照，仍带有“v0.10.1 待构建发布、直链上传后才可下载”的提示；GitHub 上的当前指南反映公开状态。两者的启动方法与版本（`0.10.1`）相同，以 GitHub 当前指南的发布状态为准。

## 已知限制

- 发布前后均**未执行**以下检查，不能视为已通过（发布后只做了 GitHub 元数据、附件摘要与直链回读，没有把安装包下载到目标设备运行）：
  - 在交互桌面实际启动 Windows 安装版或便携版并打开“关于与支持”页；
  - Android 真机安装或从 v0.10.0 覆盖升级并确认数据保留；
  - Docker 构建与启动（自托管包未实际运行）；
  - 浏览器对自托管 Web 的首次加载、离线重载和 CSP 回归；
  - iOS Safari、Android Chrome 的 HTTPS 安装与离线重开。
- Windows 安装器未拆包检查；其内容只能依据 Inno Setup 日志与同一 Release 目录推断。
- 发布包内的 `SELF_HOSTING.md` 仍有待发布提示（见上文），不影响启动方法。
- APK 构建有既有 Kotlin Gradle Plugin 未来兼容警告，本版未迁移。
- 信用卡修复本身的限制（见变更记录）：
  - 溢缴贷方余额在账户行只显示为 0，没有单独的“溢缴/可用贷方余额”展示；净资产加回只在账户页（`AccountsV2Screen`）实现。
  - “下期已使用额度”只计下一账期，远期分期只体现在当前欠款与额度使用中。
  - 多币种卡的“负债总额”按当前汇率折算。
  - 账户设置表单中信用额度、贷款金额等其他数字字段仍使用原有校验，未单独拒绝 `Infinity`；旧版本已写入的 `NaN`/`Infinity` 还款（若存在）不会被自动清理。
  - 两轮修复均未做原生实机或截图对照，只以 390×844 / 390×2400 Widget 回归验证。
- 静态分析仍保留 2 项既有 warning 和 65 项 info，本版未清理。
- 沿用 v0.10.0 的平台限制：Windows 安装器没有商业 Authenticode 签名，SmartScreen 可能提示未知发布者；自托管 Web 未收录 emoji、日文、韩文和繁体回退字体；Web 账本只保存在当前浏览器 profile，清除站点数据或换设备前必须先导出 JSON。

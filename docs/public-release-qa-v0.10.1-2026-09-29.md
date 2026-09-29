# Finance Compass v0.10.1 发布准备 QA（待构建发布）

记录日期：2026-09-29。版本：`0.10.1+45`。计划发布标签：`v0.10.1`。

> 状态：**待构建发布**。本文件只记录源码检查结果。版本号已同步到 `0.10.1+45`，但 Android、Windows 与自托管 Web 发布产物**尚未构建**，`SHA256SUMS.txt` 尚未生成。源码**尚未**提交或合并到 `main`，**尚未**创建 `v0.10.1` 标签或 GitHub Release。README 与 [自托管指南](SELF_HOSTING.md) 中的六个 v0.10.1 直链目前无法下载；已发布的最新版本仍是 [v0.10.0](public-release-qa-v0.10.0-2026-09-25.md)。下文“构建与平台检查”“发布资产”“GitHub 公开回读”中的待填项必须在实际构建、上传并回读后才能填写，不能提前标为通过。

## 发布范围

本版收录分支 `codex/credit-billing-audit` 上 2026-09-29 的两轮信用卡修复。发布前这些修复均未发布，现合入 v0.10.1。各项行为、设计、回滚与限制见 [变更记录](CHANGELOG.md) 中 2026-09-29 的“信用卡‘当前欠款’与账期边界修复”和“信用卡复审跟进”两条：

- 当前欠款与负债总额：账户页信用卡行“当前欠款”、信用分组“负债总额”与详情额度条使用同一承诺负债口径，计入下月以后已确定的 `actual`/`settled` 分期，排除 `planned`；溢缴卡显示 0，不再计入负债。只有远期已确定分期的卡显示“尚未出账”。
- 当天账期：截至今天的账期按今天日终余额计算，当天较晚时刻的消费不再让“本期应还”被少算。
- 净资产：账户页“净资产”加回信用卡溢缴贷方余额（本月取当前余额，历史月份取月末截止余额）；负债和行金额仍不低于 0。
- 历史截止：历史统计月份的信用卡账期摘要在精确截止时刻读取余额。
- 历史原始账单：该期有来源流水时取来源流水净额，超额还款不再抬高账单；只有完全缺少来源流水的旧导入月份才以还款为凭据，结果下限为 0，并兼容同币种旧版 `toAmount=0`。
- 输入校验：信用卡账户设置的余额字段改名“信用卡余额”，常显“欠款填负数，溢缴款填正数”，按原符号读写并拒绝 `NaN`/`Infinity`；“记录还款”只接受有限正数。
- 提前还款：“本期已还清”但更远账期有已确定分期时，按钮为可点击的“提前还款”，对话框默认金额为当前欠款。

本版版本同步只改版本文字，不改应用逻辑：`pubspec.yaml`、设置页“关于与支持”版本文字（`版本 0.10.1+45 · 本地优先的个人财务罗盘`）、`web/service-worker.js` 的 `CACHE_NAME`（`finance-compass-shell-v0.10.1`）、两份 Compose 的本地镜像标签（`finance-compass-web:0.10.1`）及 `tool/package_selfhost.ps1` 默认版本与输出目录（`0.10.1`、`artifacts/release/v0.10.1`）。

无数据库 schema、迁移、JSON 备份格式、应用 ID、系统权限或依赖变化；修复只改变派生显示值与输入校验，不写入或修正任何已有余额与交易。

## 源码检查（已完成）

工具链：Windows PowerShell 以绝对路径调用 `C:\Users\pwlaw\tools\flutter\bin\flutter.bat` / `dart.bat`，版本为 Flutter 3.44.1、Dart 3.12.1。

- `dart format --output=none --set-exit-if-changed lib test`：检查 142 个文件，0 个需改，退出码 0。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：退出码 0，共 67 项，均为既有问题（0 error、2 warning、65 info），与 v0.10.0 基线数量相同。
- `flutter test`：176 项通过，2 项按设计跳过（`visual_qa_capture_test.dart`），0 项失败。
- `pubspec.lock`（SHA-256 `9E53C573…AED7BD7EB`）与 `analysis_options.yaml` 在检查前后哈希相同，无改动。
- 本机日志：`artifacts/qa/release-v0.10.1-{toolchain,format,analyze,test,hashes-before,hashes-after}.log`（`artifacts/` 不随仓库提交）。

## 构建与平台检查（待填）

以下各项按 [发布流程](RELEASE_WORKFLOW.md) 执行后填写，目前均**未执行**：

- [ ] Android Release：versionName `0.10.1`、versionCode `45`；ABI 列表；`apksigner verify` 结果；签名证书 SHA-256 与 v0.10.0（`529be690…dc882a7`）一致，可覆盖升级。
- [ ] Windows Release：`FinanceCompass.exe` 的 ProductVersion/FileVersion 为 `0.10.1+45`；Inno Setup 安装器编译结果；便携 ZIP 条目数，且含 `FinanceCompass.exe`、`flutter_windows.dll`、插件 DLL、`data/flutter_assets` 与支持二维码资源。
- [ ] 自托管 Web：`tool/build_web.ps1` 以 `Web build complete` 结束；`tool/sqlite3_wasm.lock` 校验通过；三份 runtime ZIP 的条目数；抽查 `webroot/version.json` 为 `0.10.1` / `45`、`service-worker.js` 的 `CACHE_NAME` 为 `finance-compass-shell-v0.10.1`、`compose.yml` 镜像标签为 `finance-compass-web:0.10.1`。
- [ ] 私人文件：APK 与四份 ZIP 中不含 `key.properties`、JKS/keystore、SQLite 数据库、真实 JSON 备份或银行资料。
- [ ] 支持二维码：`assets/support/touch-n-go-support-qr.jpg` 的 SHA-256 与 v0.10.0 记录的 `2B2413CD…DAD8780B` 相同（2026-09-29 源码检查时工作区文件哈希相同，发布产物内的副本待核对），并人工确认收款人为 `LAW PO WEN`。
- [ ] 实机：Windows 安装版或便携版打开“关于与支持”页显示 `0.10.1+45`；Android 覆盖升级 v0.10.0 后保留数据。

## 发布资产（待填）

构建后填写六个产物的大小与 SHA-256，并确认 `SHA256SUMS.txt` 六项校验全部 `OK`：

| 文件 | 大小（bytes） | SHA-256 |
|---|---:|---|
| `FinanceCompass-Android-v0.10.1.apk` | 待填 | 待填 |
| `FinanceCompass-Windows-x64-Setup-v0.10.1.exe` | 待填 | 待填 |
| `FinanceCompass-Windows-x64-Portable-v0.10.1.zip` | 待填 | 待填 |
| `FinanceCompass-SelfHost-Ubuntu-v0.10.1.zip` | 待填 | 待填 |
| `FinanceCompass-SelfHost-Windows-v0.10.1.zip` | 待填 | 待填 |
| `FinanceCompass-SelfHost-macOS-v0.10.1.zip` | 待填 | 待填 |

## GitHub 公开回读（待填）

- [ ] PR 编号、`main` 合并提交与 tree SHA；tree 与构建产物时的源码 tree 相同。
- [ ] `v0.10.1` annotated tag peel 后指向合并提交。
- [ ] Release 非草稿、非预发布，`/releases/latest` 返回 `v0.10.1`。
- [ ] 七个附件（六个包与 `SHA256SUMS.txt`）的 size 与 SHA-256 digest 与本机 `artifacts/release/v0.10.1` 一致。
- [ ] README 六条直链无认证 HEAD 返回 200，`Content-Length` 与本机文件一致。
- [ ] 发布后移除 README、`SELF_HOSTING.md`、`docs/README.md`、`RELEASE_WORKFLOW.md` 与 `SECURITY_AND_OPERATIONS.md` 中“待构建发布”的临时说明，并把本文件状态改为已发布。

## 已知限制

- 本文件只覆盖源码检查。上文所有“待填”项目前均未执行，不能视为已通过。
- 信用卡修复本身的限制（见变更记录）：
  - 溢缴贷方余额在账户行只显示为 0，没有单独的“溢缴/可用贷方余额”展示；净资产加回只在账户页（`AccountsV2Screen`）实现。
  - “下期已使用额度”只计下一账期，远期分期只体现在当前欠款与额度使用中。
  - 多币种卡的“负债总额”按当前汇率折算。
  - 账户设置表单中信用额度、贷款金额等其他数字字段仍使用原有校验，未单独拒绝 `Infinity`；旧版本已写入的 `NaN`/`Infinity` 还款（若存在）不会被自动清理。
  - 两轮修复均未做原生实机或截图对照，只以 390×844 / 390×2400 Widget 回归验证。
- 静态分析仍保留 2 项既有 warning 和 65 项 info，本版未清理。
- 沿用 v0.10.0 的平台限制：Windows 安装器没有商业 Authenticode 签名；自托管 Web 未收录 emoji、日文、韩文和繁体回退字体；Web 账本只保存在当前浏览器 profile。

# Finance Compass v0.10.0 公开发布 QA

验证日期：2026-09-25。版本：`0.10.0+44`。发布标签：`v0.10.0`。

> 状态：已公开发布。源码经 [PR #7](https://github.com/lawpowen/finance-compass-app/pull/7) 合并到 `main`；[v0.10.0 Release](https://github.com/lawpowen/finance-compass-app/releases/tag/v0.10.0) 为非草稿、非预发布，GitHub `releases/latest` 指向该版本。README 与 [自托管指南](SELF_HOSTING.md) 中的六个 v0.10.0 直链均可无认证下载，详见下文“GitHub 公开回读”。上一版本见 [v0.9.1 QA](public-release-qa-v0.9.1-2026-09-24.md)。

## 发布范围

本版收录分支 `codex/report-redesign-multifilter-theme` 上的四项改动，各项行为、设计与限制见 [变更记录](CHANGELOG.md) 中 2026-09-24 至 2026-09-25 的条目：

- 外观页：点击主题卡片即可预览。
- 报表：合并为单页，按所选期间统计。
- 交易：账户、类型和类别均可多选筛选。
- 资产目标：进度只计到今天，达成日按真实首次达成日记录。

无数据库 schema、迁移、JSON 备份格式、应用 ID 或系统权限变化。

## 源码检查

- `flutter test`：156 项通过，2 项按设计跳过，0 项失败。
- `dart format --output=none --set-exit-if-changed lib test`：检查 140 个文件，0 个需改。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：0 error，2 项既有 warning，65 项 info。

## 构建与平台检查

- Android Release：versionName `0.10.0`，versionCode `44`。包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三种 ABI，v2 签名校验通过。签名证书 SHA-256 为 `529be690a91228ffe087c6add3a4c730b71f7cd2f6497a796ffff0913dc882a7`，与 v0.9.1 QA 记录的证书相同，因此可覆盖升级。
- Windows Release：主程序 ProductVersion/FileVersion 为 `0.10.0+44`。Inno Setup 6.7.3 安装器编译成功。便携 ZIP 共 23 个条目，已确认含 `FinanceCompass.exe`、`flutter_windows.dll`、`data/app.so` 与 `data/flutter_assets/assets/support/touch-n-go-support-qr.jpg`。
- 自托管 Web：构建脚本报告生成 142 个文件，并验证 36 项 Service Worker 预缓存和 102 个回退字体。三份自托管 ZIP 各有 150 个条目，其中 `webroot` 有 142 个文件；三份都含 `FinanceCompass-SelfHost/webroot/index.html` 与 `FinanceCompass-SelfHost/compose.yml`，且没有使用反斜杠的条目。以 Ubuntu 包抽查打包内容：
  - `webroot/version.json` 为 `0.10.0` / `44`；
  - `service-worker.js` 的 `CACHE_NAME` 为 `finance-compass-shell-v0.10.0`；
  - `compose.yml` 的镜像标签为 `finance-compass-web:0.10.0`。
- 私人文件：按文件名检查了 APK 与四份 ZIP 的条目，没有发现 `key.properties`、JKS/keystore、SQLite 数据库或备份文件；包中的 JSON 只有 Flutter/Web 清单与 `version.json`。
- 支持二维码：`assets/support/touch-n-go-support-qr.jpg` 的 SHA-256 为 `2B2413CDD153BAA8A1880D28E21B07EABA32CEDE0F609D0461C43947DAD8780B`，与 v0.9.1 相同，说明图片未改动（v0.9.1 已人工确认收款人为 `LAW PO WEN`）。

## 发布资产

`SHA256SUMS.txt` 覆盖六个文件，使用 CRLF 换行。去掉 CR 后运行 `sha256sum -c`，六项全部为 `OK`。

| 文件 | 大小（bytes） | SHA-256 |
|---|---:|---|
| `FinanceCompass-Android-v0.10.0.apk` | 64,766,627 | `0ed505005b268d958ad95cbd05570c05379426141780a2031bfc776598409433` |
| `FinanceCompass-Windows-x64-Setup-v0.10.0.exe` | 12,504,069 | `75397618e5e9c2b50873a90e70274ba9330494cdc7072916173799e68dd8269e` |
| `FinanceCompass-Windows-x64-Portable-v0.10.0.zip` | 14,811,797 | `87d4fec632245e72ed10f42a8c15efb517de62993b937e37f2f6006a0cfd76e1` |
| `FinanceCompass-SelfHost-Ubuntu-v0.10.0.zip` | 16,580,532 | `76820c0c64a8f9cbc574c7938288fa3204c7d4e970b816f5797e5a0cf5460432` |
| `FinanceCompass-SelfHost-Windows-v0.10.0.zip` | 16,580,532 | `f6d3337d3bb1355aeff4f4dc730124fbcb166385b233fdb179ea43fb4dfb9993` |
| `FinanceCompass-SelfHost-macOS-v0.10.0.zip` | 16,580,532 | `0e08b781cacfbeb6fd65fd74f2298a2b96c9c0b758141e91d1ccacfad1ed80cd` |

## GitHub 公开回读

以下步骤按 [发布流程](RELEASE_WORKFLOW.md) 完成：

- [PR #7](https://github.com/lawpowen/finance-compass-app/pull/7) 已合并。`main` 合并提交为 `786312cf4ebec2eb7427d932234adfd2d0f8a164`，其 tree SHA `ee4a41744dd3eb321396355771a0b41f6ed3108c` 与构建产物时的源码 tree 完全相同，因此上表产物来自已合并的源码。
- `v0.10.0` 是 annotated tag，peel 后指向上述合并提交。
- [v0.10.0 Release](https://github.com/lawpowen/finance-compass-app/releases/tag/v0.10.0) 已公开，非草稿、非预发布；GitHub `/releases/latest` 返回 `v0.10.0`。
- 附件共七个：六个包和 `SHA256SUMS.txt`。GitHub 回读的每项 size 与 SHA-256 digest 都与本机 `artifacts/release/v0.10.0` 中的文件一致。
- README 的六条直接下载链接逐条发出无认证 HEAD 请求，均返回 200，`Content-Length` 与上表的本机文件大小一致。

## 已知限制

- 发布前后均**未执行**以下检查，不能视为已通过（发布后只做了 GitHub 元数据、附件摘要与直链回读，没有下载安装包到目标设备）：
  - Docker 构建与启动（本机没有 Docker）；
  - Edge 或其他浏览器对自托管 Web 的首次加载、离线重载和 CSP 回归；
  - 在交互桌面实际打开 Windows 安装版或便携版；
  - Android 真机安装或覆盖升级；
  - iOS Safari、Android Chrome 的 HTTPS 安装与离线重开。
- Windows 安装器没有商业 Authenticode 签名，SmartScreen 可能提示未知发布者。
- 自托管 Web 未收录 emoji、日文、韩文和繁体回退字体，这些字符可能显示为方框。Web 账本只保存在当前浏览器 profile，清除站点数据或换设备前必须先导出 JSON。
- 新报表、交易多选和主题卡片的触控与读屏效果尚未在目标设备上人工验收。旧报表的自定义版块顺序（`report_section_order_v2`）不再生效。
- 资产目标达成日的限制见变更记录：回落后再次达标时不显示日期；多币种按当前汇率换算。
- 静态分析仍保留 2 项既有 warning 和 65 项 info，本版未清理。

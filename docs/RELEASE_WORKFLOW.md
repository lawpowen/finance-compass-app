# 公开发布、测试版与数据恢复作业

## 公开发布契约

Finance Compass 的公开 GitHub Release 固定提供：

| 产物 | 用途 |
|---|---|
| `FinanceCompass-Android-vX.Y.Z.apk` | 使用独立发布密钥签名的 Android 侧载包 |
| `FinanceCompass-Windows-x64-Setup-vX.Y.Z.exe` | Windows 10/11 x64 每用户安装器 |
| `FinanceCompass-Windows-x64-Portable-vX.Y.Z.zip` | 包含完整 Flutter Windows 运行目录的便携包 |
| `SHA256SUMS.txt` | 六个二进制产物（Android、Windows 两个、自托管三个）的 SHA-256 |

自托管 Web 发布还应提供三个同内容、按目标系统命名的 Docker runtime ZIP：`FinanceCompass-SelfHost-Ubuntu-vX.Y.Z.zip`、`FinanceCompass-SelfHost-Windows-vX.Y.Z.zip` 与 `FinanceCompass-SelfHost-macOS-vX.Y.Z.zip`。它们不是 `.deb`/`.msi`/`.dmg`，而是包含已构建 `webroot`、Caddy runtime Dockerfile、Compose 和对应启动脚本的可复现 Docker 服务包。不能把未实际构建的 OS 原生安装器写为已发布。

不能单独分发 `FinanceCompass.exe`，因为它依赖相邻 DLL、`data/` 和插件文件。Windows EXE 与安装器目前没有 Authenticode 商业代码签名，README 和 Release Notes 必须保留 SmartScreen/未知发布者提示。

## 版本与身份

`pubspec.yaml` 是版本来源，格式为 `X.Y.Z+N`。公开 Git 标签使用 `vX.Y.Z`，Android `versionCode` 使用 `N`。当前版本为 `0.10.0+44` / `v0.10.0`（已于 2026-09-25 公开发布，标签指向 `main` 合并提交 `786312c`，见 [v0.10.0 公开发布 QA](public-release-qa-v0.10.0-2026-09-25.md)；上一版本为 `0.9.1+43` / `v0.9.1`）；首个公开原生版本为 `0.8.0+41` / `v0.8.0`。

改版本时必须同步：`pubspec.yaml`；设置页“关于与支持”的版本文字（`lib/src/features/settings/settings_v2_screen.dart`）；`web/service-worker.js` 的 `CACHE_NAME`（缓存优先，不更换则已安装 PWA 会继续使用旧应用壳）；`deploy/selfhost/compose.yml` 与 `compose.runtime.yml` 的本地镜像标签；`tool/package_selfhost.ps1` 默认版本与输出目录；README 与 `SELF_HOSTING.md` 的当前版本和下载直链；`docs/README.md`、`SECURITY_AND_OPERATIONS.md` 的当前版本。明确描述历史版本的段落与旧版 QA 保持原样。

- Android 正式应用 ID：`com.financecompass.app`
- Android Debug 应用 ID：`com.financecompass.app.debug`
- Windows 可执行文件：`FinanceCompass.exe`
- GitHub：`lawpowen/finance-compass-app`

## 发布前提

- 可用 Flutter SDK、Visual Studio Desktop development with C++、Android SDK/Java 17。
- Windows 安装器使用 Inno Setup 6 与 `packaging/windows/FinanceCompass.iss`。
- Android 发布签名只存在本机：`android/key.properties` 与 `android/app/upload-keystore.jks`。两者均被 Git 忽略；`android/key.properties.example` 只提供字段结构。
- 必须备份 Android 发布密钥和密码文件。丢失密钥后无法使用相同应用 ID向已安装用户提供可升级 APK。
- GitHub CLI 已登录，并对公开仓库拥有 Release 权限。

## 验证与构建

从项目根目录执行：

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
flutter build windows --release
```

Web 自托管构建必须额外执行 `tool/build_web.ps1` 或 `tool/build_web.sh`（Docker 构建直接运行后者）。脚本从仓库的物理路径构建到清空后的 `build/web`，编译 Drift Worker，并校验必需文件、`service-worker.js` 的全部预缓存路径、锁定的 `sqlite3.wasm`、`web/fonts/SHA256SUMS` 与 `main.dart.js` 回退字体 URL 的覆盖，以及无 sidecar；任一失败都会删除 `build/web`。Flutter 3.44 生成的 `flutter_service_worker.js` 只是自注销存根，应用 Worker 是 `web/service-worker.js`。只有脚本以 `Web build complete` 结束后，才执行 `tool/package_selfhost.ps1 -Version X.Y.Z` 生成三份 runtime ZIP 并写入 SHA-256。升级 Flutter SDK 时，若构建报告回退字体未收录，按 [SELF_HOSTING.md](SELF_HOSTING.md) 的字体更新方法同步 `web/fonts/`。详见 [SELF_HOSTING.md](SELF_HOSTING.md)。

Web 发布前还必须验证 `tool/sqlite3_wasm.lock`：当前 `pubspec.lock` 的 `sqlite3 2.9.4`、`web/sqlite3.wasm` 的大小与 SHA-256 必须匹配该锁定文件。禁止用未经审阅的 `latest` WASM 替换；绑定与 WASM imports 版本不一致会使浏览器在启动 Drift 时失败。

缺少发布密钥时，Android Release 构建必须明确失败，不能退回 Debug 签名。Windows Release 输出目录为 `build/windows/x64/runner/Release/`。

## Windows 打包

使用 `packaging/windows/FinanceCompass.iss`，传入版本、Flutter Release 目录和产物目录。安装器使用固定 `AppId`、每用户 Local AppData 安装目录、开始菜单快捷方式和可选桌面快捷方式。

便携 ZIP 必须从同一个 Release 目录创建，保留全部 DLL、插件和 `data/flutter_assets`。安装器与便携包必须包含 `assets/support/touch-n-go-support-qr.jpg`。

## 产物检查

上传前必须：

1. 确认 APK、安装器和 ZIP 均为本次提交的新构建且非空。
2. 使用 `apksigner verify --verbose --print-certs` 验证 APK 签名；确认包名 `com.financecompass.app`、版本名与 versionCode 分别等于 `pubspec.yaml` 的 `X.Y.Z` 与 `N`（本次为 `0.10.0` / `44`），以及 ARM64/目标 ABI。
3. 确认 Windows EXE 的产品名、文件名和版本；实际启动安装版或便携版并打开关于与支持页。
4. 确认 ZIP 含 `FinanceCompass.exe`、`flutter_windows.dll`、插件 DLL、`data/flutter_assets` 和支持二维码资源。
5. 生成 `SHA256SUMS.txt`，覆盖六个二进制产物（Android APK、Windows 安装器与便携 ZIP、三个自托管 runtime ZIP），重新计算六项哈希并逐项比对。
6. 检查公开产物中不含 `key.properties`、JKS、SQLite、真实 JSON 备份、银行资料或其他私人文件。

## GitHub 公开发布

1. 提交并推送源码分支，通过 PR 合并到 `main`。
2. 在确切的 `main` 发布提交创建 `vX.Y.Z` 标签，不移动既有标签。
3. 创建非草稿、非预发布 GitHub Release，上传六个二进制产物（Android、Windows 两个、自托管三个）和 `SHA256SUMS.txt`。
4. 通过 GitHub 元数据重新读取文件名和大小，并确认 `/releases/latest` 可公开访问。
5. README 使用该版本的稳定直链；后续版本必须同步更新链接。

## 自愿支持二维码

公开二维码固定存放在 `assets/support/touch-n-go-support-qr.jpg`，显示于设置页“关于与支持”和 README。每次发布前必须人工确认收款人显示为 `LAW PO WEN`，并核对资产 SHA-256，防止二维码被意外替换。

支持完全自愿，不解锁功能、不形成服务权益。应用只打包静态图片，不接入支付 SDK、不读取付款结果，也不新增网络、相机或付款权限。二维码替换属于安全事件，应停止发布、核对 Git 历史和发布产物后再修复。

## Debug 与资料备份交付

内部设备测试继续使用 `com.financecompass.app.debug` 和 `Finance Compass Debug`，可与正式版并存。需要交付测试账本时，先用 SQLite 在线备份生成一致性快照，再通过 `tool/export_release_data_test.dart` 生成并恢复验证完整 JSON。真实 JSON 只写入用户授权的私人 Drive，不得成为 GitHub Release 资产。

## 回滚

- 已有用户下载公开二进制后，不覆盖标签或原地替换资产；以更高补丁/构建号修复。
- 如发布产物错误，先标记受影响版本，再构建、验证并发布新版本。
- 数据库 schema 变化前必须保留应用自动恢复点与用户完整 JSON；降级前先确认旧版本是否理解当前备份字段。

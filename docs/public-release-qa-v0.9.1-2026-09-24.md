# Finance Compass v0.9.1 公开发布 QA

验证日期：2026-09-24。版本：`0.9.1+43`。发布标签：`v0.9.1`。

## 源码与行为

- Claude CLI 在最终工作树运行 `dart format --output=none --set-exit-if-changed lib test`，退出码 0；`flutter test` 为 135 项通过、2 项按设计跳过；`flutter analyze --no-fatal-infos --no-fatal-warnings` 退出码 0、无 error，保留 3 项既有 warning 和 103 项 info。
- 投资未实现盈亏按当前市值减剩余成本计算；取出减少成本。快照写入与历史余额的回归测试已包含在上述全量测试中。
- 无数据库 schema、JSON 备份格式、应用 ID 或系统权限变化。旧逻辑已经写错的 `current_balance` 不会自动重算；有实际转账或调整且折入对象不明确时，部分快照删除或重排序会被拒绝。

## 构建与平台检查

- Android Release：`com.financecompass.app`、versionName `0.9.1`、versionCode `43`，含 `arm64-v8a`、`armeabi-v7a`、`x86_64`；`apksigner verify` 通过 v2 签名。签名证书 SHA-256 为 `529be690a91228ffe087c6add3a4c730b71f7cd2f6497a796ffff0913dc882a7`，与本机哈希匹配公开 v0.9.0 APK 的证书相同。
- Windows Release：主程序 ProductVersion/FileVersion 为 `0.9.1+43`；Inno Setup 6.7.3 安装器编译成功，便携 ZIP 有 22 个条目，含 `FinanceCompass.exe`、Flutter DLL、插件、`data/app.so` 和支持二维码。旧 CMake 缓存缺 Flutter 临时文件，清理仓库内 Git 忽略的 `build/windows` 后重建成功。
- 自托管 Web：Windows PowerShell 与 Git Bash 构建各生成 142 个文件；脚本验证 36 个 Service Worker 核心预缓存路径、102 个本地字体、Drift Worker 与锁定版 `sqlite3.wasm`，并排除调试 sidecar。Edge headless 在同等 CSP 下首次加载、重载、离线重载均显示完整中文，由 `service-worker.js` 控制并缓存 138 项；没有 CSP 错误或第三方请求。三份 ZIP 各含 150 个条目，其中 `webroot` 为 142 个文件，关键路径存在且无反斜杠条目。
- 支持二维码图片可见收款人 `LAW PO WEN`，资产 SHA-256 为 `2B2413CDD153BAA8A1880D28E21B07EABA32CEDE0F609D0461C43947DAD8780B`，本次未改动。

## 发布资产

`SHA256SUMS.txt` 已按六项文件重新计算并逐项匹配。

| 文件 | 大小（bytes） | SHA-256 |
|---|---:|---|
| `FinanceCompass-Android-v0.9.1.apk` | 65,258,831 | `c4f9d93d2c6fca155b41bab79435f5971dfd6d9d8f6d5bb47cc1dc4bb134a904` |
| `FinanceCompass-Windows-x64-Setup-v0.9.1.exe` | 12,548,897 | `ec42859ab5d49c3333a560a6a59c6a90475e25fa10174b8b90d5ee0e163219b3` |
| `FinanceCompass-Windows-x64-Portable-v0.9.1.zip` | 14,873,651 | `8bc950bafc72e90be7a95b6ef55a5a6bf256bf916dd6755ff6c5fc9cee6903ce` |
| `FinanceCompass-SelfHost-Ubuntu-v0.9.1.zip` | 16,604,438 | `623434edaa7e664f0bb049e3ca09083f8d9aff8fae2e09193d090d3678a5787c` |
| `FinanceCompass-SelfHost-Windows-v0.9.1.zip` | 16,604,438 | `644237d88b35df232bd2ce16eb13c1f5f93fe30ac9d61c8e33da4c57e88e19d8` |
| `FinanceCompass-SelfHost-macOS-v0.9.1.zip` | 16,604,438 | `0d471267400f463d77e6a2170337839127e6d5cfc1410d9ca4e648349abf26a1` |

## 已知限制

- 本机没有 Docker，未实际构建或启动 Docker 路径；iOS Safari 和 Android Chrome 的 HTTPS 安装、离线重开仍待真机验收。
- Windows 安装器没有商业 Authenticode 签名，SmartScreen 可能提示未知发布者；本次未在交互桌面打开安装版或便携版页面。
- Web 未收录的 emoji、日文、韩文、繁体回退字体可能显示为方框。Web 账本仍只保存在当前浏览器 profile，清除站点数据或换设备前须导出 JSON。
- GitHub 标签、Release 与资产公开回读将在上传后补记；本页记录上传前的本机验证结果。

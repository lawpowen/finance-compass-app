# Finance Compass v0.9.0 公开发布 QA

验证日期：2026-08-04

版本：`0.9.0+42`

发布标签：`v0.9.0`

## 发布结论

Finance Compass v0.9.0 已完成 Flutter Web/PWA、Android 和 Windows 正式构建。自托管 Web 使用浏览器本地 Drift WASM SQLite；服务器仅分发静态文件，不提供账户、同步、服务端数据库或备份。

## 自动化与浏览器验证

- `flutter test`：111 项通过，2 项按设计跳过。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：退出码 0，无编译错误；保留 105 项既有提示。
- Flutter Web Release 和 Drift Worker 构建成功，完全使用本地 CanvasKit，不引用 `gstatic.com`。
- Chrome 390×844 独立临时会话确认 Finance Compass 实际界面渲染、Service Worker 激活并控制页面，且无控制台错误或资源加载失败。
- 本机回环 HTTP 确认首页、manifest、Service Worker、`main.dart.js`、`sqlite3.wasm` 和 `drift_worker.js` 均返回 200；WASM MIME 为 `application/wasm`。

## Web 数据库供应链修复

初版验收捕获到 `xFileControl` WebAssembly LinkError 白屏，根因是误用与 Dart bindings 不匹配的较新 `sqlite3.wasm`。最终版本固定：

- sqlite3 Dart package：`2.9.4`
- 官方资产大小：730,989 bytes
- SHA-256：`922A76B182B6AF69B030C8E2FDD3283ECC8E827248B20E4B1F3F3DB170B52117`
- 来源：sqlite3.dart 官方 `sqlite3-2.9.4` Release

`tool/sqlite3_wasm.lock` 记录版本、URL、大小和哈希；PowerShell、shell 与 Docker 构建均会拒绝不匹配的 package/WASM 组合。

## 发布文件

| 文件 | 大小（bytes） | SHA-256 |
|---|---:|---|
| `FinanceCompass-Windows-x64-Setup-v0.9.0.exe` | 12,542,430 | `9203a467de46d6f797bc3f97d0764708da3ce01bb5b0dabd327bbfc55423a3b7` |
| `FinanceCompass-Windows-x64-Portable-v0.9.0.zip` | 14,553,926 | `20761da778babc74a080d32156a478c9ade9e3dee1c265755e0aa4378c92b356` |
| `FinanceCompass-Android-v0.9.0.apk` | 65,176,911 | `e5a686fb128c71d20bdcf8d4ba8d7e017bc44efc6ea5c6354d8da922da1715c4` |
| `FinanceCompass-SelfHost-Ubuntu-v0.9.0.zip` | 15,075,006 | `f5d00fe4b86fb35aec8c830a81540508b0ade917678268a13b871aa0ab9df9bb` |
| `FinanceCompass-SelfHost-Windows-v0.9.0.zip` | 15,075,006 | `47178074f2bd7ca84ab56ca0a425c03b7cf9cfcd3d4269671f16238ba8ff324f` |
| `FinanceCompass-SelfHost-macOS-v0.9.0.zip` | 15,075,006 | `a5d3dace2ce1576e807703758a1d90fc344a1fb450cc9d1a207e91d378b3337c` |

`SHA256SUMS.txt` 已按六项文件重新计算并逐项匹配。

## 平台验证

- Android：`com.financecompass.app`，`0.9.0`，versionCode `42`，`arm64-v8a` / `armeabi-v7a` / `x86_64`，APK Signature Scheme v2，单一 RSA-4096 签名证书。
- Windows：主程序产品/文件版本 `0.9.0+42`，安装程序由 Inno Setup 6.7.3 编译；便携包含 22 条目、运行库、插件、Cupertino 字体和支持二维码。
- 自托管：三个 ZIP 各含 55 条目、预构建 `webroot`、runtime Dockerfile、Compose、Caddy 配置和平台启动脚本；每包内 WASM 哈希正确且无 Worker 源码/map/deps sidecar。

## 安全、回滚与限制

- Compose 默认只绑定 `127.0.0.1:8080`；对外访问前必须配置 HTTPS 和认证。
- Web 账本属于当前设备、浏览器 profile 和 origin；换设备/浏览器/域名不会同步。清除站点数据前必须下载 JSON。
- Windows 安装程序仍未配置 Authenticode 商业签名，SmartScreen 可能提示未知发布者。
- 本机 Docker Desktop 在验收时持续停留 `starting`，所以未实际运行容器；Compose 配置和回环 HTTP 已验证。iOS Safari/Android Chrome 的 HTTPS 安装、离线重开与系统存储回收仍需目标设备人工验收。
- 回滚 Web 壳前先从每台设备导出 JSON，再部署旧包；服务器无法恢复浏览器账本。

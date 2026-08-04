# 自托管 Web / PWA

## 当前实现与边界

Finance Compass `0.9.0+42` 可构建为自托管的 Flutter Web 应用。自托管服务器只分发 HTML、JavaScript、静态资源、`sqlite3.wasm` 与 Drift Worker；**没有后端 API、用户账户、服务端 SQLite、服务端备份或跨设备同步**。因此它适合让 iPhone、iPad、Android 和桌面浏览器访问同一私有网址，但不是云同步服务。

公开发布包：

- [Ubuntu v0.9.0](https://github.com/lawpowen/finance-compass-app/releases/download/v0.9.0/FinanceCompass-SelfHost-Ubuntu-v0.9.0.zip)
- [Windows v0.9.0](https://github.com/lawpowen/finance-compass-app/releases/download/v0.9.0/FinanceCompass-SelfHost-Windows-v0.9.0.zip)
- [macOS v0.9.0](https://github.com/lawpowen/finance-compass-app/releases/download/v0.9.0/FinanceCompass-SelfHost-macOS-v0.9.0.zip)

账本由 Drift WASM SQLite 保存在访问该网址的浏览器 profile 内。现代浏览器优先使用 OPFS，较旧/Safari 能力受限时可回退 IndexedDB。每一个“设备 + 浏览器 + 网站 origin”是一个独立账本：换设备、换浏览器或改变域名/端口都不会带来数据；清除该网站数据、无痕模式回收或浏览器存储被系统清理时可能丢失。使用前及每次重要录入后都应从“导入与导出”下载完整 JSON。

```mermaid
flowchart LR
  U[Safari / Chrome / Desktop browser] -->|HTTPS + access control| RP[Host reverse proxy]
  RP -->|127.0.0.1:8080| C[Caddy static container]
  C --> W[Flutter Web + service worker]
  W --> D[Drift WASM SQLite]
  D --> B[This browser's OPFS / IndexedDB]
  B -. JSON export/import only .-> X[User-controlled backup]
```

## PWA 与 Apple/Android 使用方式

- **iOS/iPadOS Safari**：通过 HTTPS 打开站点，点击分享按钮，再选择“添加到主屏幕”。Safari 不提供 Chromium 式安装提示；离线缓存与本地存储受 iOS 存储回收策略影响，所以不应以它代替 JSON 备份。
- **Android Chrome**：通过 HTTPS 打开站点，在 Chrome 菜单选择“安装应用”或“添加到主屏幕”。manifest 和 standalone display 已配置；Service Worker 会缓存静态应用外壳，首次完整加载后可离线打开。它不会让服务器持有或同步账本。
- **桌面浏览器**：支持作为普通网页或浏览器安装的 PWA 使用。浏览器 WebAssembly、Worker、IndexedDB/OPFS 被禁用时，应用会无法可靠保存资料，不应继续记账。

HTTPS 是 PWA、Service Worker 及受保护浏览器存储的前提（`localhost` 仅作开发例外）。不要把 HTTP 站点当作私人账本服务。

## 默认安全部署

`deploy/selfhost/compose.yml` 默认仅发布 `127.0.0.1:8080`，不会监听公网。先在 Ubuntu、Windows 或 macOS 安装 Docker Engine/Desktop，再在仓库根目录执行：

```powershell
.\deploy\selfhost\install.ps1
```

```sh
chmod +x deploy/selfhost/install.sh deploy/selfhost/install.command
./deploy/selfhost/install.sh
```

上述脚本构建并启动静态 Caddy 容器。确认本机 `http://127.0.0.1:8080` 可打开后，才可使用你自己控制的反向代理或 VPN 将其提供给其他设备。

面向 Internet 的部署必须至少做到：

1. 使用 DNS 域名、有效 TLS 证书并强制 HTTPS；不要直接把容器 8080 端口暴露到公网。
2. 在反向代理层启用访问控制。`deploy/selfhost/Caddyfile.reverse-proxy.example` 提供 Caddy Basic Auth 模板；使用 `caddy hash-password --algorithm bcrypt --plaintext '强随机口令'` 生成哈希，把用户名/哈希以受保护环境变量提供给 Caddy。
3. 为每个家庭成员或用户使用独立访问凭据；Basic Auth 只是在 TLS 内的入口保护，不能替代端点安全。
4. 定期更新 Docker 基础镜像、Caddy、Flutter 发行版本及宿主机安全补丁，并限制服务器管理权限。
5. 不把 JSON、SQLite、密钥、反向代理环境文件或日志上传到公开 GitHub Release。服务本身不写用户数据，备份责任在每个浏览器用户。

容器设置为只读、无 Linux capabilities、禁止新增权限且只有临时 `/tmp`。Caddy 同时加入基本的 CSP、无嗅探、拒绝嵌入与关闭支付/相机/麦克风等权限；这些头不是认证的替代品。

## 构建与交付

开发机上构建 Web：

```powershell
.\tool\build_web.ps1 -Flutter C:\Users\pwlaw\tools\flutter\bin\flutter.bat -Dart C:\Users\pwlaw\tools\flutter\bin\dart.bat
```

```sh
chmod +x tool/build_web.sh
./tool/build_web.sh
```

脚本先校验 `pubspec.lock` 的 sqlite3 版本、`web/sqlite3.wasm` 与 `tool/sqlite3_wasm.lock` 三者一致，再编译 `tool/drift_worker.dart` 到发布用 `drift_worker.js`，最后以 `--no-web-resources-cdn` 运行 `flutter build web --release`，使 CanvasKit 完全随自托管站点提供。当前锁定的 WASM 是 `sqlite3 2.9.4`：来源为 [sqlite3.dart `sqlite3-2.9.4` release](https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.9.4/sqlite3.wasm)，大小 `730,989` bytes，SHA-256 为 `922A76B182B6AF69B030C8E2FDD3283ECC8E827248B20E4B1F3F3DB170B52117`。不要使用“latest”资产；它可能与锁定 Dart bindings 的 WASM imports 不兼容并导致浏览器白屏。升级 sqlite3 时，必须一并审阅 `pubspec.lock`、lock 文件、官方 release asset 和真浏览器启动测试。

脚本会拒绝把 Worker 源码、source map 或 `.deps` sidecar 送入发布目录，并拒绝仍引用 `gstatic.com` 的输出。Flutter 3.44 不再自动生成 Service Worker，因此仓库内的 `web/service-worker.js` 是受版本控制的静态缓存实现：首次成功安装会预缓存 Flutter、CanvasKit、Drift/SQLite、字体、manifest 和主静态资源；它不缓存账本资料。Flutter 生成的旧 Worker 注销器也以 no-cache 提供。`web/sqlite3.wasm` 必须随站点以 `application/wasm` 提供；`Caddyfile` 已显式处理该 MIME 类型。

创建跨平台自托管交付 ZIP：

```powershell
.\tool\package_selfhost.ps1 -Version 0.9.0
```

生成的 ZIP 内含 Dockerfile、Compose、Caddy 配置、Ubuntu/macOS shell 安装器与 Windows PowerShell 安装器。它不是 OS 原生 `.deb`、`.msi` 或 `.dmg`：三个系统均通过 Docker 提供相同、可复现的静态服务。不能从 Windows 对 macOS 签发可信 DMG，也不能声称未在目标 OS 构建的原生安装器已验证。

## 升级、回滚与恢复

- **升级 Web 壳**：先从每个设备导出 JSON，再拉取/解压新版本并运行 `docker compose up -d --build`。浏览器首次刷新可能仍使用旧 Service Worker；关闭标签页后重新打开，必要时在浏览器开发者工具清除“应用缓存”，但先导出 JSON。
- **回滚 Web 壳**：部署旧镜像/源码即可；它不改变浏览器数据库 schema 之外的既有 Drift 迁移逻辑。若曾打开更高 schema，先按应用现有恢复策略导出 JSON，并确认旧应用能理解其格式。
- **恢复账本**：打开同一受保护 origin，在“导入与导出”选择此前下载的 JSON。Web 不能悄悄在服务器创建恢复点；导入覆盖前，界面必须让用户先下载当前 JSON。
- **丢失浏览器数据**：服务器不能恢复它。使用用户自行保存的 JSON 才能恢复。

## 验收清单

1. 通过 HTTPS 且经访问控制打开域名；匿名或 HTTP 请求不得用于真实账本。
2. 首次打开后检查“关于与支持”中的 Web 存储说明，录入测试数据并下载 JSON。
3. 在 Safari 添加到主屏幕、在 Android Chrome 安装/添加 PWA；确认两端账本互不自动同步。
4. 离线重开 PWA，确认应用壳可用；恢复联网后确认导出仍可下载。
5. 在测试 profile 中清除网站数据，确认账本消失后能从 JSON 恢复，借此验证备份而非假设服务器持久化。

# Finance Compass v0.8.0 公开发布 QA

验证日期：2026-08-04

版本：`0.8.0+41`

发布标签：`v0.8.0`

## 发布结论

Finance Compass v0.8.0 已通过公开发布前的自动化测试、静态分析、Android 正式签名检查和 Windows 打包完整性检查。公开发布包含 Windows 安装程序、Windows 完整便携包、Android APK 和 SHA-256 校验文件。

## 自动化验证

- `flutter test`：108 项通过，2 项因外部 AI 网关未配置而按设计跳过。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：退出码为 0，无编译错误；保留 105 项既有 info/warning。
- 390×844 Widget 回归确认“关于与支持”页可显示版本、公开下载入口、自愿支持说明和收款码语义标签。
- 两项依赖当前日期的测试夹具改为使用执行当天，避免月初把固定月中日期误判成未来；应用业务规则未改变。

## Android 正式包

- 文件：`FinanceCompass-Android-v0.8.0.apk`
- 大小：65,060,605 bytes
- SHA-256：`729c8c6a5b6dbac6de12dd539f8e5f528f21bff31293f8480cdd6c35b8c283fe`
- 包名：`com.financecompass.app`
- `versionName` / `versionCode`：`0.8.0` / `41`
- ABI：`arm64-v8a`、`armeabi-v7a`、`x86_64`
- APK Signature Scheme v2：通过；签名者数量为 1。
- 证书 SHA-256：`52:9B:E6:90:A9:12:28:FF:E0:87:C6:AD:D3:A4:C7:30:B7:1F:7C:D2:F6:49:7A:79:6F:FF:F0:91:3D:C8:82:A7`
- 安装包包含 `assets/support/touch-n-go-support-qr.jpg`。

发布密钥和 `android/key.properties` 只保存在本地并被 Git 忽略。后续升级必须使用同一密钥签名；发布后应立即把这两个文件离线加密备份。

## Windows 正式包

### 安装程序

- 文件：`FinanceCompass-Windows-x64-Setup-v0.8.0.exe`
- 大小：12,440,755 bytes
- SHA-256：`df7ae7e9343aec1b6b7c69ef70afa46b938f205d558bfa45a71dcae22e8e424e`
- Inno Setup：6.7.3，编译验证成功。
- 产品版本：`0.8.0`；文件版本：`0.8.0.0`。
- 当前未配置 Authenticode 商业代码签名，Windows SmartScreen 可能显示未知发布者或信誉提醒。

### 便携包

- 文件：`FinanceCompass-Windows-x64-Portable-v0.8.0.zip`
- 大小：14,437,303 bytes
- SHA-256：`191aebec060e935f01d11649f8d12a265de05a3a473bf4e825fe3654fdcd0042`
- ZIP 共 19 个条目，包含 `FinanceCompass.exe`、`flutter_windows.dll`、插件 DLL、`data/` 和支持收款码。
- 主程序元数据：产品 `Finance Compass`，产品/文件版本 `0.8.0+41`，公司 `lawpowen`，原始文件名 `FinanceCompass.exe`。

Windows EXE 不是可单独复制的独立程序；便携使用时必须保留解压后的完整目录。

## 支持收款码

- 资源：`assets/support/touch-n-go-support-qr.jpg`
- SHA-256：`2B2413CDD153BAA8A1880D28E21B07EABA32CEDE0F609D0461C43947DAD8780B`
- 收款人提示：`LAW PO WEN`
- 收款码只作为静态图片显示，不集成支付 SDK、不读取支付结果、不影响功能解锁，也不构成服务承诺。

## 回滚与限制

- 回滚代码：重新发布前一已验证标签；用户数据格式没有因本次发布改变，不需要数据库迁移。
- 回滚发布页：撤回 `v0.8.0` Release，并把 README 下载入口恢复到前一公开版本。
- Android 已安装用户不能用不同密钥签名的 APK 直接覆盖升级，因此发布密钥丢失会中断升级链。
- Windows 尚无 Authenticode 签名；公开下载页必须同时提供 `SHA256SUMS.txt`，供用户核对文件完整性。

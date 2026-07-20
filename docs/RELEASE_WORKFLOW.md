# 测试版发布与数据恢复作业

## 适用范围

每次完成代码或数据修复任务后，除非用户明确取消，收尾作业固定包含：同步工程文档、完成质量检查、导出当前完整 JSON、构建独立 Debug APK，并把 JSON 与 APK 写入本机 Google Drive 同步目录 `G:\我的云端硬盘\Finance Compass APK`。Windows EXE 默认不上传；只有用户明确要求时才另行交付。

## 标准流程

1. 完成代码、数据和文档变更，确认没有覆盖无关的用户修改。
2. 执行相关定向测试、`flutter test` 和 `flutter analyze --no-fatal-infos --no-fatal-warnings`。
3. 对正在使用的 `finance_app.sqlite` 执行 SQLite 在线备份，避免直接复制 WAL 状态下的数据库。
4. 使用 `flutter test tool/export_release_data_test.dart --dart-define=SOURCE_DB=<sqlite-snapshot> --dart-define=OUTPUT_JSON=<output-json>` 从一致性快照生成完整 v3 JSON；工具通过 Flutter 运行器调用应用自身 Repository，验证账户、分类、预算、交易、投资快照、快速模板、周期规则和 meta 结构，再把产物导入空数据库并核对主要集合数量。未通过恢复验证的 JSON 不得交付。
5. 构建 ARM64 Debug APK。Debug 身份必须保持 `com.financecompass.app.debug`、应用名 `Finance Compass Debug`，数据目录与正式版及其他包名独立。
6. 用包含应用版本、构建号和日期的文件名复制 APK 与 JSON，不覆盖或删除 Drive 上的旧版本。
7. 优先把两份文件复制到本机 `G:\我的云端硬盘\Finance Compass APK`，由 Google Drive for desktop 完成同步；仅在本地同步盘不可用时才使用 Drive 连接器。默认不上传 EXE、SQLite 临时快照、银行账单或其他敏感来源文件。
8. 写入后重新读取本地同步目录中的文件元数据，并在可用时核对云端元数据；最终报告列出 APK、JSON、测试结果、备份口径和已知限制。

## 恢复原作业资料

1. 安装对应 Debug APK。Debug 包不会覆盖正式版，但不同 Debug 构建若包名相同会更新同一测试应用。
2. 打开“设置 → 导入与导出 → 导入数据文件”。
3. 选择同一发布批次的 `finance_compass_backup_*.json`。
4. 先检查预览中的账户、分类、预算、交易、投资快照、模板和周期规则数量，再确认替换当前资料。
5. 导入前应用会建立恢复点；导入完成后重新检查信用卡当前欠款、历史账单和未来已确定账单。

完整 JSON 包含敏感财务资料，只能上传到用户授权的 Drive，不创建公开分享链接，也不发送给外部 AI。若 APK 构建或 JSON 验证失败，不得上传半成品或把该任务报告为已完成。

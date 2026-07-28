# Finance Compass 项目上下文

## 目标与边界

Finance Compass 是个人财务管理产品。正式项目由 Flutter App 和 FastAPI Gateway 构成；`tooling/finance-compass-dev-kit` 只是辅助工具。

- App：离线优先，负责账户、交易、分类、预算、目标、汇率、导入导出和仪表盘。
- Gateway：只接收客户端准备好的汇总数据，用于只读 AI 分析。
- AI 不得直接新增、删除或修改财务记录。

## 技术

- Flutter / Dart / Riverpod / Drift(SQLite) / GoRouter / fl_chart。
- Gateway：Python / FastAPI / httpx / Uvicorn。
- 业务必须区分 `planned` 与 `actual/settled`。
- 跨币种显示和汇总必须通过汇率转换，不得在业务逻辑中硬编码货币符号。

## 最近验证状态

- build `0.8.0+40`。
- 107 项测试通过，2 项跳过。
- 修复模板创建对话框生命周期问题：对话框退出时不再由外部 `TextEditingController` 触发已销毁对象错误。
- 最新 APK 已交付。

以上是 2026-07-27 聊天中的验证结果；当前工作树仍有大量用户代码修改，迁移不应覆盖或混入。

## 远端状态

- App 远端目录：`/srv/hdd/projects/finance-compass-app`。
- Gateway 远端目录：`/srv/hdd/projects/finance-compass-gateway`。
- App 的 Git remote URL 棵测到嵌入式凭据；Gateway 工作树不干净。本次远端同步阻塞。

# Finance Compass 文档索引

本文档集与 `Finance Compass 0.10.1+45` 代码同时维护。代码行为为事实来源；计划能力必须明确标注为“计划中”。

当前已发布的最新版本为 `0.10.1+45` / `v0.10.1`（2026-09-29 公开发布，PR #9 合并到 `main`，合并提交 `4c1166b`，Release 为 Latest），收录 `codex/credit-billing-audit` 分支上 2026-09-29 的信用卡欠款、净资产溢缴、历史账期、原始账单与输入校验修复；其构建、附件校验、直链回读结果与未执行的平台检查见 v0.10.1 公开发布 QA。上一版本为 `0.10.0+44` / `v0.10.0`（2026-09-25 公开发布，PR #7），见 v0.10.0 公开发布 QA。

- [系统需求](SYSTEM_REQUIREMENTS.md)
- [系统架构](ARCHITECTURE.md)
- [模块设计](MODULE_DESIGN.md)
- [UI 参考基线](UI_REFERENCE.md)
- [全应用交互审计](INTERACTION_AUDIT.md)
- [数据设计与迁移](DATA_DESIGN.md)
- [接口与导入导出](INTERFACES.md)
- [安全与运维](SECURITY_AND_OPERATIONS.md)
- [公开发布、测试版与数据恢复作业](RELEASE_WORKFLOW.md)
- [自托管 Web / PWA](SELF_HOSTING.md)
- [v0.10.1 公开发布 QA（2026-09-29）](public-release-qa-v0.10.1-2026-09-29.md)
- [v0.10.0 公开发布 QA（2026-09-25）](public-release-qa-v0.10.0-2026-09-25.md)
- [v0.9.1 公开发布 QA（2026-09-24）](public-release-qa-v0.9.1-2026-09-24.md)
- [v0.9.0 公开发布 QA（2026-08-04）](public-release-qa-v0.9.0-2026-08-04.md)
- [v0.8.0 公开发布 QA（2026-08-04）](public-release-qa-v0.8.0-2026-08-04.md)
- [测试与质量](TESTING_AND_QUALITY.md)
- [代码—文档追踪](TRACEABILITY.md)
- [变更记录](CHANGELOG.md)

维护规则见项目根目录的 `AGENTS.md`。修改数据模型、页面流程、业务规则、接口或配置时，必须在同一变更中更新对应文档。

## 本地工作目录与清理

2026-10-11 整理了历史过程文件。源码、工程文档、签名配置、用户原始附件和正式发布包保留；删除旧调试包、重复解压目录、构建中间文件、未被文档引用的对比截图、旧启动日志与 PR/提示词草稿。根目录旧 `app-arm64-v8a-release.apk` 已移除，发布包按版本保存在 `artifacts/release/`。

| 路径 | 用途 | 保留与清理规则 |
| --- | --- | --- |
| `lib/`、`test/`、`tool/`、各平台目录、`assets/`、`deploy/`、`packaging/`、`docs/` | 源码、测试、构建配置、部署脚本与工程文档 | 保留在现有目录，不作为过程文件清理 |
| `artifacts/release/<version>/` | 正式安装包、自托管包、校验文件与发布说明 | 保留已有正式版本；v0.10.0 与 v0.10.1 的发布说明已集中到对应版本目录的 `RELEASE_NOTES.md` |
| `artifacts/backups/2026-07/` | 从旧 Android 包目录及 `build/release/` 移出的 11 份 JSON/SQLite 数据文件 | 按原文件名保留；迁移前后 SHA-256 一致，不因目录曾叫 build/artifacts 就删除数据 |
| `artifacts/analysis/` | 已保存的财务口径分析 Notebook | 从根目录 `analysis/` 移入，内容未改 |
| `artifacts/qa/`、`artifacts/design-qa/`、`artifacts/audit/`、`artifacts/interaction-audit/`、`artifacts/ui-reference/` | 发布与测试证据、用户确认的视觉基线 | 保留文档引用的日志、核验结果和截图；只清理已完成任务的 PR/提示词草稿 |
| `artifacts/tools/` | 本地 Inno Setup 工具 | 保留；`artifacts/` 下重复下载的安装器已清理 |
| `.codex-remote-attachments/`、`.agents/`、`.codex/`、`.dart_tool/`、Android 签名文件 | 原始输入、Agent 配置、依赖缓存与发布密钥 | 本次保留，不列入旧过程文件删除范围 |

`artifacts/` 中的本地数据不随 Git 提交；整理到一个目录不等于完成异地备份。`build/`、`outputs/`、`work/`、`tmp/` 与根目录生成的 `app-*-release.apk` 被 Git 忽略。清理构建目录前必须先检查是否混入 JSON 备份、数据库快照等用户数据。本次已清空 `build/`，下次构建将重新生成中间产物。

## Android 通知记账开发版

[Android 通知记账](ANDROID_NOTIFICATION_BOOKKEEPING.md)：授权、来源绑定、准入、待确认、撤销、隐私、后台限制与回滚。

[TNG eWallet 通知样本调查](TNG_NOTIFICATION_RESEARCH.md)：官方来源、工资示意、通知类型区别及尚未验证的 Android 字段。

[马来西亚 10 家银行通知适配调查](MALAYSIA_BANK_NOTIFICATION_RESEARCH.md)：当前 Android App 身份、包名、官方通知证据与自动模板缺口。当前开发版为 0.11.0-dev+49，公开稳定版不变。

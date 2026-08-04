# 代码—文档追踪

| 代码范围 | 必须检查的文档 |
|---|---|
| `core/database/**`、表文件 | `DATA_DESIGN.md`、`ARCHITECTURE.md`、`SECURITY_AND_OPERATIONS.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `core/models/**` | `SYSTEM_REQUIREMENTS.md`、`DATA_DESIGN.md`、`MODULE_DESIGN.md` |
| `core/models/loan_amortization.dart`、`features/accounts/loan_detail_screen.dart`、`features/accounts/account_form_dialog.dart` | `SYSTEM_REQUIREMENTS.md`、`ARCHITECTURE.md`、`MODULE_DESIGN.md`、`DATA_DESIGN.md`、`INTERFACES.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `core/data/**`、`core/services/**` | `MODULE_DESIGN.md`、`INTERFACES.md`、`TESTING_AND_QUALITY.md` |
| `features/**`、`core/theme/**` | `SYSTEM_REQUIREMENTS.md`、`MODULE_DESIGN.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、根目录 `design-qa.md` |
| 可点击控件、设置行、导航箭头和表单选择器 | `INTERACTION_AUDIT.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、根目录 `design-qa.md` |
| `features/accounts/accounts_v2_screen.dart` 及三个账户详情的 `cutoffDate` | `SYSTEM_REQUIREMENTS.md`、`MODULE_DESIGN.md`、`DATA_DESIGN.md`、`INTERFACES.md`、`UI_REFERENCE.md`、`INTERACTION_AUDIT.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `features/accounts/asset_goals_page.dart`、Repository 资产目标接口 | `SYSTEM_REQUIREMENTS.md`、`MODULE_DESIGN.md`、`DATA_DESIGN.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `features/accounts/credit_card_detail_screen.dart` 的专用还款流程 | `SYSTEM_REQUIREMENTS.md`、`MODULE_DESIGN.md`、`DATA_DESIGN.md`、`UI_REFERENCE.md`、`INTERACTION_AUDIT.md`、`SECURITY_AND_OPERATIONS.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `features/reports/**`、`actualCashFlowSummary*`、`futureCashFlowProjection` | `SYSTEM_REQUIREMENTS.md`、`ARCHITECTURE.md`、`MODULE_DESIGN.md`、`DATA_DESIGN.md`、`INTERFACES.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `features/transactions/transactions_v2_screen.dart` 的月度资金需求、`monthlyFundingNeedForMonth` | `README.md`、`SYSTEM_REQUIREMENTS.md`、`ARCHITECTURE.md`、`MODULE_DESIGN.md`、`INTERFACES.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `features/budgets/budgets_v2_screen.dart` 的生效月保存、`activeBudgetsForMonth` | `SYSTEM_REQUIREMENTS.md`、`MODULE_DESIGN.md`、`DATA_DESIGN.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `features/settings/settings_reference_pages.dart`、`core/theme/**` | `ARCHITECTURE.md`、`MODULE_DESIGN.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `features/transactions/transaction_automation_pages.dart`、`features/budgets/**` | `MODULE_DESIGN.md`、`DATA_DESIGN.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `core/data/finance_repository.dart` 的周期生成、`features/accounts/loan_detail_screen.dart` 的预计还款 | `SYSTEM_REQUIREMENTS.md`、`ARCHITECTURE.md`、`MODULE_DESIGN.md`、`DATA_DESIGN.md`、`INTERFACES.md`、`SECURITY_AND_OPERATIONS.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| 导入、导出、AI、分享 | `INTERFACES.md`、`SECURITY_AND_OPERATIONS.md` |
| `pubspec.yaml`、Android 配置 | `ARCHITECTURE.md`、`SECURITY_AND_OPERATIONS.md`、`CHANGELOG.md` |
| `assets/support/**`、`features/settings/settings_v2_screen.dart` 的关于与支持页 | `SYSTEM_REQUIREMENTS.md`、`MODULE_DESIGN.md`、`INTERFACES.md`、`SECURITY_AND_OPERATIONS.md`、`UI_REFERENCE.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md`、根目录 `README.md` |
| `packaging/**`、Windows/Android 发布配置 | `ARCHITECTURE.md`、`RELEASE_WORKFLOW.md`、`SECURITY_AND_OPERATIONS.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md`、根目录 `README.md` |
| `web/**`、`core/database/database_connection*`、`core/platform/local_file_io*` | `SELF_HOSTING.md`、`ARCHITECTURE.md`、`MODULE_DESIGN.md`、`INTERFACES.md`、`SECURITY_AND_OPERATIONS.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md` |
| `deploy/selfhost/**`、`tool/build_web.*`、`tool/package_selfhost.ps1` | `SELF_HOSTING.md`、`ARCHITECTURE.md`、`SECURITY_AND_OPERATIONS.md`、`RELEASE_WORKFLOW.md`、`TESTING_AND_QUALITY.md`、`CHANGELOG.md`、根目录 `README.md` |

任何重要变更还必须更新 `CHANGELOG.md`。未来计划不得写成当前能力。

# UI 参考基线

## 事实来源

`artifacts/ui-reference/` 中的 29 张用户确认截图是 0.8.0 界面的唯一视觉基线。实现应保持真实本地账户、交易和预算数值，因此金额和名称可以与截图示例不同；页面结构、信息层级、色彩、间距、图标语义和交互入口必须与对应截图一致。

主检查宽度为 390 逻辑像素。长页面在同一宽度下滚动检查，不通过压缩整页来适配桌面窗口。

## 页面映射

| 参考图 | 当前页面/状态 | 实现入口 |
|---|---|---|
| `01-dashboard.png` | 总览、可选 7/30/60/90 天余额预测 | `DashboardV2Screen` |
| `02-accounts.png` | 账户总览、信用分组 | `AccountsV2Screen` |
| `03-credit-card-detail.png` | 信用卡本期账单与未出账 | `CreditCardDetailScreen` |
| `04-credit-card-settings.png` | 信用卡额度、结算日、还款日 | `AccountFormDialog` |
| `05-transactions.png`、Product Design 方案 2 | 三口径月度交易列表 | `TransactionsV2Screen` |
| `06-add-transaction.png` | 新增/编辑/信用卡还款交易 | `TransactionComposerPage` |
| `07-quick-picker.png` | 闪电快速记账面板 | `TransactionsV2Screen` 快捷面板 |
| `08-recurring-plan.png` | 周期计划 | `RecurringPlanPage` |
| `09-recurring-rule-editor.png` | 周期规则编辑 | `RecurringRuleEditorPage` |
| `10-quick-templates.png` | 快速模板管理 | `QuickTemplateManagerPage` |
| `11-template-editor.png` | 模板编辑 | `TemplateEditorPage` |
| `12-budget-detail.png` | 分类预算明细 | `BudgetCategoryDetailPage` |
| `13-budget-editor.png` | 分类预算编辑 | `BudgetEditorPage` |
| `14-reports.png` | 报表总览 | `ReportsV2Screen` |
| `15-net-worth-detail.png` | 净资产详情 | `NetWorthDetailPage` |
| `16-spending-analysis.png` | 支出分析 | `SpendingAnalysisPage` |
| `17-budget-insight.png` | 预算洞察 | `BudgetInsightPage` |
| `18-cash-flow-forecast.png` | 现金流预测 | `CashFlowForecastPage` |
| `19-settings.png` | 设置总览 | `SettingsV2Screen` |
| `20-account-sync.png` | 本地账户与同步计划 | `AccountSyncPage` |
| `21-currency-rates.png` | 货币、汇率与显示 | `CurrencyDisplayPage` |
| `22-rules-center.png` | 规则中心 | `FinanceRulesCenterPage` |
| `23-category-manager.png` | 类别管理 | `CategoryManageScreen` |
| `24-category-editor.png` | 类别编辑 | `CategoryFormDialog` |
| `25-backup-restore.png` | 备份、恢复与迁移 | `BackupRestorePage` |
| `26-import-export.png` | 导入与导出 | `ImportExportPage` |
| `27-appearance.png` | 外观与主题 | `AppearancePage` |
| `28-notifications.png` | 通知与提醒 | `NotificationsPage` |
| `29-ai-gateway.png` | 外部 AI 分析与网关 | `AiGatewaySettingsPage` |
| `supplemental-budget-overview.png` | 预算主页面 | `BudgetsV2Screen` |

## 视觉与交互契约

- 背景为近黑深青渐变；主强调色为青绿色，支出、负债和主操作为橙色。
- 六个主页面使用固定底部导航：总览、账户、交易、预算、报表、设置。
- 交易页右下角保留同尺寸闪电与加号；新增消费只从交易流程进入，信用卡详情不提供新增消费按钮。
- 交易页月份下方使用一张宽选中卡加两张窄卡展示“消费发生”“现金收付”“已承诺”，点击卡片实时切换下方指标；卡片下保留页点、“已发生/包含预计”分段、两项口径解释和账户/类型/类别筛选。选中卡使用青绿色描边及深青底色，负数和支出仍用橙色。三种口径不把交易列表分成三个互相隐藏的页面。
- 交易行、搜索结果和信用卡账单明细行必须可点击进入新版交易编辑器；编辑保存保留原交易 ID。编辑页面底部提供橙色描边“删除交易”入口，点击后以确认对话框说明不可撤销和余额恢复，取消时保留编辑页面。交易行尾部保留旧版三点菜单，顺序为编辑、复用新增、保存模板、保存周期、分隔线、删除；菜单不取代整行点击。未来月份右箭头可用，进入未来月份默认展示“即将发生”。
- 新增交易和周期计划的生成入口都提供 1–12 个月直接选择，不固定为三个月；所有月份统一继承用户选择的“已发生”或“预计”状态。
- 总览“未来 30 天”是可点击范围选择器，提供 7、30、60、90 天；选择后预计余额、结束日期、横轴日期和曲线必须一起更新。
- 信用卡账单时间线显示动态年月；本期和未出账列表分别使用完整账期边界，不能展示其他月份/账期的消费。记录还款使用新版交易界面。
- 信用卡“查看账单”打开历史月份底部列表，每项展示账期、还款日和金额；选择后主金额、时间线及明细同时切换到该期，历史模式显示“返回本期”，实时额度条不随历史选择改变。
- 信用卡账户行的“当前欠款”和详情额度使用包含未来日期但状态为已发生的分期，排除所有预计记录；本期账单文案和时间线仍只反映截至今天所属账期的记录。
- 金额必须支持真实数据长度，使用弹性布局或等比缩放，不允许在 390 像素宽度出现 Flutter overflow 标记。
- 交易金额输入使用带符号数字键盘并允许显示 `0.00` 与负号；删除按钮和保存按钮均需保持至少 52 逻辑像素高的触控区域。
- 转账类型在主金额下方显示第二个“转入金额”区块及目标币种。未选目标账户时提示先选择；同币种自动同步且转入栏只读；跨币种显示参考汇率、允许编辑实际到账金额，并提供“重新换算”恢复当前设置汇率。转出/转入账户选择仍在基本信息区保留，两个入口必须驱动同一状态。
- 预算主页面顶部以“分类基础预算 ÷ 当月已分配预算”计算占比，按预算额从高到低展示最多五个分类；超过五个分类时，余量仅保留为未标名区段，不能用一个醒目的“其他”替代已确认分类。实际支出使用实色，预计支出使用斜纹，未使用额度保持底色可见。
- 外观页使用可水平拖动的主题卡片轮播，必须露出相邻卡片以提示可滑动。拖动只切换预览；只有点击“设为当前主题”才写入并应用主题。总览/交易预览切换同样不得改写用户设置。
- 快速模板管理页的右侧拖动手柄必须可用；用户可在全部模板之间调整顺序，并把“其他模板”拖入前五。排序保存后，编号 1–5 与交易页闪电快捷面板的五个模板保持一致。
- 信用卡资料缺失时，编辑界面建议额度 `MYR 10,000`、结算日 `12`、还款日 `28`；仅在用户保存后写入，迁移不会改写旧资料。
- Google 登录与跨设备同步、银行品牌图标、贷款摊销仍为计划能力；界面不得暗示已经可用。

## 未来已确定账单交互

信用卡“查看账单”月份列表在存在未来 `actual`/`settled` 记录时，先按近到远显示并标记“已确定”，随后为本期及往期；每项展示账期、还款日和可校对的原始账单额。账单月份按结算日前一天命名，例如 8 月 1 日结算显示为“7 月账单”。选择后主金额、时间线及明细同时切换到该期，非本期模式显示“返回本期”，实时额度条不随月份选择改变。已还款月份仍显示原始账单额，而不是零；顶部紧凑按钮使用“已确定”，以保持 390 像素基准宽度无溢出。

## 变更检查

修改 `features/**` 或 `core/theme/**` 时，至少对照受影响页面参考图，并在 `design-qa.md` 记录相同宽度、相同状态的配对检查结果。数据模型或日期规则变化还需同步更新 `DATA_DESIGN.md` 和 `SYSTEM_REQUIREMENTS.md`。

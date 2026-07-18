# 模块设计

## `core/database`

负责 Drift 表、schema 升级、完整性检查、余额原子更新和 v7 迁移前备份。升级失败必须保留旧文件并向启动层返回错误。

## `core/data`

`FinanceRepository` 是当前页面的聚合读模型和业务入口。它负责币种转换、账户余额、预算、报表、模板/周期规则、导入导出和 AI 摘要。`cashFlowNetBetween` 按精确起止日期汇总现金/信用账户的未来变动，供总览 7/30/60/90 天预测使用。

## `core/models`

领域对象不依赖 Flutter UI。`credit_card_billing.dart` 根据账户级日期和交易账本计算已出账、未出账、还款日及完整账期边界；不修改交易。账期包含判断使用完整日期，支持跨年、跨月和月末夹取。转账按方向解释：信用卡作为来源时增加该卡账单，作为目标时只减少目标卡负债。`AppDatabase` 在打开旧资料及完整导入时，把信用卡关联交易的旧单笔结算日期归一为 `record_date` 发生日期，保证领域计算不会继续读取已废弃语义。

## `core/providers`

`financeRepositoryProvider` 提供当前数据快照。各 mutation provider 执行写入并替换 provider 状态。页面不得绕过 mutation 修改核心账本；通知偏好等单一 meta 设置可直接写入数据库。

## 页面模块

- Dashboard：月度现金流、提醒、资金分布和快捷交易入口；预测卡可选择未来 7、30、60、90 天，并按选择范围更新结束日期、曲线采样和预计余额。预测以截至今天的实际现金为基线，显式窗口才合并未来 `actual`/`settled` 与 `planned`，不得重复加入本月未来交易。
- Accounts：账户分组、净资产、信用卡账单与账户编辑。无显式范围时，贷款负债、投资/退休汇总通过 Repository 的当前月截止余额；信用卡当前欠款、信用负债汇总和额度使用则读取承诺负债，即物化余额中的全部 `actual`/`settled`（包括未来分期），同时排除不改变物化余额的 `planned`。信用卡详情把截至今天的交易分为当前已结算账期和下一未出账账期，并通过 `CreditCardDisplayState` 区分账期待设置、无欠款、尚未出账、本期已还清、待还款、今日到期和逾期未还；承诺负债不得提前进入本期账单。右上“查看账单”打开由最早相关交易至本期的月份选择器，选择后以该期结算日重建账期、账单金额、时间线和明细，历史模式不改变实时额度使用，并提供返回本期入口。逾期状态必须同时满足当前账单仍有余额及还款日已过。账单行可进入新版交易编辑器，记录还款也使用同一新版编辑器。投资/退休账户详情直接提供锁定当前账户的市值更新入口，新增快照后由 mutation provider 刷新余额、盈亏与图表。
- Transactions：`TransactionsV2Screen` 提供月份现金流、“已发生”/“包含预计”统一计算口径、类型筛选、紧凑交易列表、模板、新增和编辑交易；默认口径排除 `planned`，切换后顶部收入、支出、净现金流与列表一起包含 `actual`/`settled` 和 `planned`。月份导航允许未来 120 个月，进入未来月份时自动启用“包含预计”，同时保留未来已确定的实际记录。交易整行点击进入编辑，尾部 `FinanceActionMenuButton` 恢复编辑、复用新增、保存模板、保存周期和删除；搜索结果复用同一菜单契约。`TransactionComposerPage` 编辑模式在页面底部提供独立删除入口，二次确认后以 `TransactionFormResult.deleted` 把 ID 交回调用页面，再由 mutation 删除并刷新；旧高级表单遵守相同契约。普通列表长按进入多选模式，点击追加选择，可选择当前可见结果并在确认后原子删除。金额字段接受有限的正数、零和负数，数据库继续使用既有代数余额规则。页面监听 `financeRepositoryProvider`，删除成功后立即使用最新账本快照重建。原 `TransactionsScreen` 作为高级筛选入口保留。
- Transactions automation：`QuickTemplateManagerPage` 和 `RecurringPlanPage` 直接读取及写入 `transaction_templates`、`recurring_transaction_rules`；模板试用只预填交易表单。普通新增交易可在 `TransactionComposerPage` 选择 1–12 个月并一次生成，所有月份统一保留表单选择的 `actual` 或 `planned`；周期计划页同样先选择 1–12 个月再主动生成，所有新月份继承规则状态，已存在月份由 Repository 去重。创建或编辑规则不得把 `planned` 强制改成 `actual`，且只保存一份规则基准交易，不误用表单的批量生成结果。
- Budgets：月度预算总览、分类预算和消费明细；新增、修改、删除和月份切换都通过真实 repository/mutation 数据完成，空月份不注入示例预算。预算构成按分类基础预算排序并展示最多五个分类，占比口径为分类基础预算除以当月已分配预算；实际、预计和未使用部分分别以实色、斜纹和底色表达。
- Reports：趋势、分类、净资产、预算洞察和未来现金流。
- Settings：本地账户、币种、规则、备份、外观、通知和外部 AI 分析。外观页以 `PageView` 提供 12 款主题的拖动预览，预览状态与持久化设置分离，用户确认后才调用设置控制器应用。导入/导出、备份、分类、模板与周期规则是当前可用能力；Google 登录、系统通知调度及交易附件明确标为计划中，不得显示虚假成功状态。

页面与 29 张确认截图的逐项映射、视觉契约和 390 像素检查规则见 [UI 参考基线](UI_REFERENCE.md)。主导航页面读取真实 `FinanceRepository` 数据；参考图中的示例金额不得覆盖用户账本。快速模板、周期计划、报表详情和设置详情使用独立页面，但共享 `CompassBackground`、`CompassSettingsRow`、`CompassSegmentedControl` 和金额格式化规则。

页面失败时显示 provider 错误；表单验证失败不得写入数据库。删除账户/类别时，如存在交易、快照、预算、模板或周期规则引用，必须拒绝删除。

## 信用卡未来账单浏览补充

`CreditCardDetailScreen` 把未来 `actual`/`settled` 记录所在账期作为“已确定”月份加入账单选择器，并允许查看对应时间线和可编辑交易；`planned` 记录不进入该列表。当前未出账只展示截至今天已发生的记录，下一期基础金额使用下一完整账期的来源卡流水合计，因此已经锁定额度的未来分期只进入各自月份，不与账户累计欠款混算。`calculateCreditCardBilling` 会根据截至今天的实际欠款推导本期是否已经还清，并只在存在明确转入还款时，把超出本期剩余应还的部分从下一期基础金额扣除；这使银行已使用额度和下期剩余承诺保持一致，同时不让旧资料中的不完整余额污染账期金额。月份选择器和历史标题使用结算日前一天作为账单月份；原始账单额由 `calculateCreditCardOriginalStatementAmount` 提供，还款后仍可校对。若本地对账已把银行结单总额写入账户级 `app_meta`，`FinanceRepository.creditCardStatementAmountOverride` 按结算日返回权威值，详情页优先展示该值；缺失或损坏的 meta 自动回退到交易推算。`FinanceRepository.creditCardStatementBalance` 只用于结算日余额审计。

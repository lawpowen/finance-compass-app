# 接口与导入导出

## JSON v3

顶层字段：`format_version=3`、`transaction_date_semantics=occurrence_date`、`app_version`、`schema_version`、`exported_at`、`meta`、`accounts`、`categories`、`budgets`、`transactions`、`asset_snapshots`、`transaction_templates`、`recurring_transaction_rules`。

导入是完整替换，不执行记录级合并。导入前展示数量摘要并要求确认，随后建立自动恢复点。空文件、缺少财务数据或枚举/日期格式错误会拒绝导入。兼容旧信用卡资料时，若 `record_date` 与 `transaction_date` 不同，以 `record_date` 作为实际发生日期写入两个字段；信用卡账期由账户级 `statement_day` 推导。

Android/桌面端通过系统文件选择器读取 `.json`，并由同一文件选择器把非空字节直接写入用户选定的文档 URI；Android 写入异常必须返回应用，不能把已创建但未写入的 0 KB 文档报告为成功。应用不会把导出路径写死到公共存储。设置页还可生成最近 6 个月的 AI 摘要 JSON，以及未来 24 个月计划表 CSV。导入完成后 mutation provider 会重新载入 `FinanceRepository`，界面退回主路由，因此账户、交易、预算、模板和周期规则立即使用新快照且不保留引用旧 repository 的详情页。

导入预览与正式导入共用相同的基础格式检查：空文件、截断 JSON、非对象顶层、未来格式版本和错误字段类型都会在改动数据库前被拒绝。正式导入还会验证实体引用与 SQLite 完整性；失败只显示错误消息，不进入空白或黑屏状态。

## AI 分析

应用支持两种当前接口：

- 生成不包含完整原始交易的 AI 摘要 JSON。
- 生成外部分析文本并通过系统分享面板交给 ChatGPT 或其他 AI App。

外部 AI 分享文本由 `AiAnalysisService.buildExternalAnalysisText` 生成，只包含分析提示词和“请上传 JSON”的说明，不自动附带文件。提示词版本 `finance_compass_three_lenses_v3` 支持带 `analysis_contract` 的分析摘要和带 `format_version/accounts/transactions` 的完整备份；接收方必须以 `generated_at` 或 `exported_at` 为截止点，按 `transaction_date` 归属月份，并分别计算消费发生、现金收付和信用负债。

可选 `ai_gateway_url` 由高级设置保存。应用不会把网关描述为隐私诊断功能。

## 外部身份

Google 登录接口尚未实现。未来接口必须将远程身份绑定到 `local_profile_id`，首次登录只能选择上传、下载或手动确认，不得静默覆盖本地数据库。

## 内部查询契约

`FinanceRepository.cashFlowNetBetween(startInclusive, endInclusive)` 按完整日历窗口返回现金及信用账户的净变动，包含已记录的未来实际交易和预计交易，不包含投资/退休等非现金分组的直接收支。结束日期包含当天 23:59:59.999。该接口只读取交易快照，不写数据库。

`FinanceRepository.accountBalanceAt(accountId, date)` 是带截止时间的实际余额接口；普通无范围账户与资产页面使用 `currentMonthCutoffDate()`。`creditCardCommittedOutstandingBalance(accountId)` 是信用卡当前欠款/额度占用专用接口，读取全部日期已影响物化余额的 `actual`/`settled`，并排除全部 `planned`；账单计算不得用它替代截至今天的 `accountBalanceAt`。`investmentFlowSummaryForAccount` 未传 `upToDate` 时同样默认当前月末。`futureCashFlowProjection` 和总览预测则以截至今天的余额为基线，只有明确预测范围时才合并未来实际与预计记录。

信用卡账单领域接口将账期归属、账期流水合计和结算日待还余额分开；完整顺序与职责见下方“信用账单余额接口补充”。选择月份只更新页面内存状态，不修改账户、交易或当前账单状态。

## 信用账单余额接口补充

信用卡账单浏览使用五个无写入接口：`availableCreditCardBillingPeriods(account, transactions, now, maximumPeriods)` 返回“未来已确定（升序）→本期→历史（倒序）”的账期列表；`calculateCreditCardBillingPeriodForStatement(statementDay, paymentDueDay, statementDate)` 重建指定结算日；`CreditCardBillingPeriod.billingMonthDate` 以结算日前一天确定用户看到的账单月份；`calculateCreditCardStatementAmount(accountId, transactions, period)` 只汇总来源卡方向的单个账期流水；`calculateCreditCardOriginalStatementAmount(accountId, transactions, period)` 返回可在还款后继续校对的原始账单额，并在旧导入消费明细不完整时使用结算日至还款日的明确转入还款作为下限凭据。`FinanceRepository.creditCardStatementBalance` 仅保留为结算日余额审计接口，不能替代月份账单金额。选择账单月份只更新页面内存状态，不修改账户、交易或当前账单状态。

## 内部交易删除契约

交易行的三点菜单是既有交易数据的操作接口：`edit` 打开原记录、`reuse` 以新 ID 打开预填草稿、`template` 调用 `addTransactionTemplate`、`recurring` 调用 `addRecurringTransactionRule`、`delete` 走与长按多选一致的确认及原子删除流程。整行点击继续直接进入 `edit`，菜单点击不得触发行点击。

`TransactionComposerPage` 的生成周期选择接受 1–12。新建交易选择大于 1 时调用 `buildRecurringTransactions` 返回多笔结果，所有记录均保持表单当前的 `actual`/`planned` 状态；编辑已有交易永远只返回原 ID 的单笔结果。`RecurringPlanPage` 把用户选择的月份数传给 `generateRecurringTransactions(ruleId, monthsAhead)`，而不是使用固定三个月；Repository 和 `TransactionService` 对每个生成月份统一使用规则保存的状态，不根据是否为未来日期改写。

`TransactionFormResult` 是新旧交易编辑器共用的页面返回契约：保存时 `transactions` 包含待新增/更新记录；编辑页确认删除时使用 `TransactionFormResult.deleted(id)`，此时 `transactions` 为空且 `deletedTransactionId` 非空。调用页面必须先处理删除动作，不能把空列表当作保存。交易金额和转入金额接受任何有限 `double`，包括 `0` 和负数；非数字、`NaN` 与无穷必须在写入前拒绝。

新版转账表单的保存契约按币种分流：来源与目标币种相同则返回 `toAmount=null`、`toCurrency=<目标币种>`，调用者以 `amount` 同时更新两端；币种不同则返回有限的 `toAmount` 与目标账户币种 `toCurrency`。自动建议值通过 `FinanceRepository.convertAmount(amount, fromCurrency, toCurrency)` 读取本地汇率设置，不调用网络；用户手动覆盖后以覆盖值为最终到账金额。

`FinanceRepository.reorderTransactionTemplates(orderedTemplateIds)` 接受包含现有全部模板且每个 ID 恰好一次的完整顺序，重新写入连续 `sortOrder=0..n-1`；缺失、重复或未知 ID 会拒绝保存。`TransactionMutations.reorderTransactionTemplates` 发布刷新后的 Repository，使快速模板管理页和闪电面板立即使用相同前五顺序。

- `TransactionMutations.deleteTransactions(ids)` 是 UI 批量删除入口；成功后把刷新后的 `FinanceRepository` 写回 `financeRepositoryProvider`。
- `FinanceRepository.deleteExistingTransactions(ids)` 调用数据库原子删除并执行现有目标同步刷新逻辑。
- `AppDatabase.deleteTransactionsByIds(ids)` 在同一数据库事务内恢复所有相关账户余额并删除记录；任一 ID 不存在时抛出 `StateError`，不产生部分变更。
- `deleteTransaction(id)` 保持兼容，内部委托给单元素批量删除。

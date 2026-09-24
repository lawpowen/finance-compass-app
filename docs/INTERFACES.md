# 接口与导入导出

投资成本读取接口：`FinanceRepository.costBasisForAccount(accountId, upToDate)` 返回首张快照基线加之后实际投入的累计成本；`remainingCostBasisForAccount(accountId, upToDate)` 再扣首张快照之后的实际取出，供资产卡片、详情与报表计算未实现盈亏。没有快照时按全部实际投入减实际取出计算。`snapshotRemainingCostBasis` 和 `snapshotUnrealizedPnl` 采用相同截止日口径；这些调用只读，不改写快照或交易。截止日早于首张快照时，`costBasisForAccount` 只返回截至当日的实际投入，`accountBalanceAt` / `accountBalanceTrace` 从 `initial_balance` 累加截止日及之前的实际交易，均不读取未来快照。

快照写入接口：`FinanceRepository.addAssetSnapshot`、`updateExistingAssetSnapshot`、`deleteExistingAssetSnapshot` 分别调用 `AppDatabase.insertAssetSnapshot`、`updateAssetSnapshot`、`deleteAssetSnapshot`，签名不变，返回刷新后的 Repository。契约变化如下：
- 新增成为最新的快照时，存储的 `marketValue` 可能大于录入值，因为已折入日期晚于它的实际转账/调整。
- `Account.currentBalance` 按 `DATA_DESIGN.md` 的决策表维护，不再等于“最新快照市值”，删除唯一快照后也不再为 0。
- 删除最新快照（仍有较早快照），或编辑时改变了“最新快照”，并且账户有实际转账/调整时，Future 以 `SnapshotBalanceAmbiguityException`（定义于 `core/database/app_database.dart`，`toString()` 为中文提示）失败，数据库不变。
- 编辑时改换 `accountId` 以 `ArgumentError` 失败。

`AssetMutations` 不捕获这些异常，由调用页面处理。账户详情页已有的 `try/catch` 会以 SnackBar 显示提示。

余额读取接口：`accountBalanceAt(accountId, date)` 在快照之后的截止日返回“快照市值 + 快照后到截止日的实际收入/支出 − 截止日后已折入的实际转账/调整”。`accountBalanceTrace` 的条目依次为：收入/支出正向加入（旧到新），然后转账/调整扣回（新到旧）；`endingBalance` 与 `accountBalanceAt` 相同。

## 自托管 Web 接口边界

Web 自托管版没有 JSON/REST/GraphQL 服务端接口。Caddy 仅提供静态 `index.html`、`flutter_bootstrap.js` 与其他 Flutter 资源、`manifest.json`、`service-worker.js`、`pwa_bootstrap.js`、`sqlite3.wasm`、`drift_worker.js` 和同源回退字体 `fonts/`（清单为 `fonts/SHA256SUMS`，Service Worker 安装时按它预缓存）；`flutter_service_worker.js` 仅作为 Flutter 生成的自注销存根存在，应用不注册它；所有账本 CRUD 仍在浏览器内通过 Drift 执行。反向代理只可把 `https://finance.example.com/` 转发到 `127.0.0.1:8080`，并应在这一层实施 TLS/认证。`sqlite3.wasm` 必须以 `application/wasm` 响应。

浏览器文件选择器可能没有本机路径，`ExportMutations.previewImportBytes` 与 `importJsonBytes` 接收 `Uint8List`，供 Web 按字节预览和导入 JSON；原生 `previewImport`/`importJson` 保留路径接口。两者使用相同的 JSON 格式验证和 Drift 事务替换规则。

## JSON v3

顶层字段：`format_version=3`、`transaction_date_semantics=occurrence_date`、`app_version`、`schema_version`、`exported_at`、`meta`、`accounts`、`categories`、`budgets`、`transactions`、`asset_snapshots`、`transaction_templates`、`recurring_transaction_rules`。

`accounts` 的贷款扩展字段为 `loan_principal`、`loan_annual_interest_rate`、`loan_term_months`、`loan_start_date`（合同开始日）、`loan_tracking_start_date`（开始记账日）、`loan_payment_day`、`loan_repayment_method` 和可空的 `loan_quoted_monthly_payment`。日期使用 ISO-8601。JSON v3 保持向后兼容：旧备份缺少追踪日期时按 `NULL` 导入并回退使用合同开始日；新备份的 `schema_version=9`，旧应用可能忽略未知字段，因此回滚前必须保留 v9 恢复点。

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

## 公开项目与下载链接

`FinanceCompassAboutPage` 通过 `url_launcher` 把源码、最新 Release 和 Issues URL 交给操作系统打开：`https://github.com/lawpowen/finance-compass-app`、`/releases/latest` 和 `/issues`。这些入口不附加账本内容、不调用付款接口；打开失败只显示本地 SnackBar。Touch 'n Go 支持二维码是随应用打包的静态资产，不是 API，也不返回付款状态。

## 内部查询契约

`FinanceRepository.cashFlowNetBetween(startInclusive, endInclusive)` 按完整日历窗口返回现金账户的实际净变动，包含已记录的未来实际交易和预计交易；信用卡消费在现金还款前不计入，现金转入贷款或信用账户按转出全额计入。不包含投资/退休等非现金分组的直接收支。结束日期包含当天 23:59:59.999。该接口只读取交易快照，不写数据库。

`FinanceRepository.totalAssetHistory({cutoffDate, includeCredit})` 默认保留包含信用负债的净资产历史，供报表使用；资产目标传入 `includeCredit: false`。`assetGoalSummaries` 固定使用不含 `ReportGroup.credit` 的总资产口径，避免调用方误把贷款或信用卡负债扣入目标进度。

`FinanceRepository.actualCashFlowSummaryForMonth(monthKey, includePlanned, accountId, type, categoryId)` 与复数月份版本 `actualCashFlowSummaryForMonths` 返回 `CashFlowSummary(inflow, outflow)`。它们只计算 `ReportGroup.cash` 的真实增减，筛选参数先选择交易集合再计算现金两端；默认排除 `planned`。`actualCashOutflowByCategoryForMonths` 将无类别的还款/转账流出放入 `uncategorizedCashOutflowKey`，`actualCashOutflowByAccountForMonth` 只返回现金来源账户。报表和历史平均使用这些接口；预算消费仍使用消费支出接口。

`FinanceRepository.monthlyFundingNeedForMonth(monthKey, includePlanned)` 返回 `MonthlyFundingNeed`：`knownCashOutflow` 是当月已知现金流出，`creditDue`/`loanDue` 是当月到期义务，`coveredDebtPayments` 是已由实际或（开启时）预计还款覆盖的部分，`uncoveredDebtDue` 为未覆盖义务，`totalCashRequired = knownCashOutflow + uncoveredDebtDue`。信用卡到期按账户结算日/还款日和各检查点的剩余账单推导；贷款到期按 `calculateLoanAmortization` 派生计划，并把当月转入对应贷款账户的结构化月供、普通手工转账或旧版本金/利息组合作为覆盖。接口只读、不写入交易，也不接受账户、类型或类别筛选。

`futureCashFlowProjection` 以当前现金资产为运行起点。未来现金还信用卡或贷款时，`expense` 使用来源完整付款金额；现金账户之间转账因净额为零不形成流入或流出。该接口包含预测窗口中的未来实际与预计记录，但不写回账户余额。

`FinanceRepository.accountBalanceAt(accountId, date)` 是带截止时间的实际余额接口；普通无范围账户与资产页面使用 `currentMonthCutoffDate()`。`creditCardCommittedOutstandingBalance(accountId)` 是信用卡当前欠款/额度占用专用接口，读取全部日期已影响物化余额的 `actual`/`settled`，并排除全部 `planned`；账单计算不得用它替代截至今天的 `accountBalanceAt`。`investmentFlowSummaryForAccount` 未传 `upToDate` 时同样默认当前月末。`futureCashFlowProjection` 和总览预测则以截至今天的余额为基线，只有明确预测范围时才合并未来实际与预计记录。

`calculateLoanAmortization(principal, annualInterestRatePercent, termMonths, startDate, paymentDay, method, quotedMonthlyPayment, openingPrincipal)` 是无数据库写入的贷款计划接口。输入合同金额必须大于零、年利率不得为负、期数为 1–1200、还款日为 1–31；可选 `openingPrincipal` 必须大于零且不超过合同金额。银行核定月供允许 `equalInstallment` 与 `flatRate`，必须覆盖当期利息，`equalPrincipal` 不接受该参数。返回 `LoanAmortizationSchedule`，包含常规月供、待付总额、待付利息和待追踪 `LoanInstallment` 列表；中途建账会在开始余额清零时结束列表，不返回历史期数。

`addRecurringTransactionRule` 保存规则后立即调用 `generateRecurringTransactions(..., monthsAhead: 3)`；生成窗口覆盖未来第 1–3 个完整日历月，仅写入今天之后且月份键尚未生成的 `planned` 交易。贷款详情的全期预计生成同样只写 `planned`，需要用户明确选择同币种现金账户并确认；预计项在实际记录对应期数前移除，避免重复进入未来现金流。

信用卡账单领域接口将账期归属、账期流水合计和结算日待还余额分开；完整顺序与职责见下方“信用账单余额接口补充”。选择月份只更新页面内存状态，不修改账户、交易或当前账单状态。

账户页通过 `AccountDetailScreen(account, cutoffDate)`、`CreditCardDetailScreen(account, cutoffDate)` 和 `LoanDetailScreen(account, cutoffDate)` 的可空参数传递历史统计范围。`cutoffDate == null` 表示本月实时模式；非空值必须是所选月份的月末，详情页只读取该日及以前的实际资料并禁用写操作。该状态仅存在于页面内存，不写入数据库、备份或 `app_meta`。

## 信用账单余额接口补充

信用卡账单浏览使用五个无写入接口：`availableCreditCardBillingPeriods(account, transactions, now, maximumPeriods)` 返回“未来已确定（升序）→本期→历史（倒序）”的账期列表；`calculateCreditCardBillingPeriodForStatement(statementDay, paymentDueDay, statementDate)` 重建指定结算日；`CreditCardBillingPeriod.billingMonthDate` 以结算日前一天确定用户看到的账单月份；`calculateCreditCardStatementAmount(accountId, transactions, period)` 只汇总来源卡方向的单个账期流水；`calculateCreditCardOriginalStatementAmount(accountId, transactions, period)` 返回可在还款后继续校对的原始账单额，并在旧导入消费明细不完整时使用结算日至还款日的明确转入还款作为下限凭据。`FinanceRepository.creditCardStatementBalance` 仅保留为结算日余额审计接口，不能替代月份账单金额。选择账单月份只更新页面内存状态，不修改账户、交易或当前账单状态。

## 内部交易删除契约

交易行的三点菜单是既有交易数据的操作接口：`edit` 打开原记录、`reuse` 以新 ID 打开预填草稿、`template` 调用 `addTransactionTemplate`、`recurring` 调用 `addRecurringTransactionRule`、`delete` 走与长按多选一致的确认及原子删除流程。整行点击继续直接进入 `edit`，菜单点击不得触发行点击。

`TransactionComposerPage` 的生成周期选择接受 1–12。新建交易选择大于 1 时调用 `buildRecurringTransactions` 返回多笔结果，所有记录均保持表单当前的 `actual`/`planned` 状态；编辑已有交易永远只返回原 ID 的单笔结果。`RecurringPlanPage` 把用户选择的月份数传给 `generateRecurringTransactions(ruleId, monthsAhead)`，而不是使用固定三个月；Repository 和 `TransactionService` 对每个生成月份统一使用规则保存的状态，不根据是否为未来日期改写。

周期规则编辑器通过现有交易编辑器更新基准交易，通过日期和选项选择器更新 `intervalMonths`、`startDate`、`endDate`，并通过 Repository 完成启停、删除和补生成。预算月份、货币格式及通知偏好均写入本地 Repository/meta；保存成功后失效并重载 `financeRepositoryProvider`。未实现的系统级能力不返回成功结果。

`TransactionFormResult` 是新旧交易编辑器共用的页面返回契约：保存时 `transactions` 包含待新增/更新记录；编辑页确认删除时使用 `TransactionFormResult.deleted(id)`，此时 `transactions` 为空且 `deletedTransactionId` 非空。调用页面必须先处理删除动作，不能把空列表当作保存。交易金额和转入金额接受任何有限 `double`，包括 `0` 和负数；非数字、`NaN` 与无穷必须在写入前拒绝。

新版转账表单的保存契约按币种分流：来源与目标币种相同则返回 `toAmount=null`、`toCurrency=<目标币种>`，调用者以 `amount` 同时更新两端；币种不同则返回有限的 `toAmount` 与目标账户币种 `toCurrency`。自动建议值通过 `FinanceRepository.convertAmount(amount, fromCurrency, toCurrency)` 读取本地汇率设置，不调用网络；用户手动覆盖后以覆盖值为最终到账金额。

`FinanceRepository.reorderTransactionTemplates(orderedTemplateIds)` 接受包含现有全部模板且每个 ID 恰好一次的完整顺序，重新写入连续 `sortOrder=0..n-1`；缺失、重复或未知 ID 会拒绝保存。`TransactionMutations.reorderTransactionTemplates` 发布刷新后的 Repository，使快速模板管理页和闪电面板立即使用相同前五顺序。

- `TransactionMutations.deleteTransactions(ids)` 是 UI 批量删除入口；成功后把刷新后的 `FinanceRepository` 写回 `financeRepositoryProvider`。
- `FinanceRepository.deleteExistingTransactions(ids)` 调用数据库原子删除并执行现有目标同步刷新逻辑。
- `AppDatabase.deleteTransactionsByIds(ids)` 在同一数据库事务内恢复所有相关账户余额并删除记录；任一 ID 不存在时抛出 `StateError`，不产生部分变更。
- `deleteTransaction(id)` 保持兼容，内部委托给单元素批量删除。

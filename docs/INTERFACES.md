# 接口与导入导出

`FinanceAmountField` 暂存键盘输入，点「完成」才写回 controller。取消不改动字段。清空后确认返回空字符串，由原表单继续区分必填和可选。`FinanceTextField(isAmount: true)` 使用同一交互。

`accountBalanceAt(accountId, cutoff)` 与余额追溯采用相同的锚点、实际交易和截止时刻。投资账户从最近观测正向回放；没有适用观测时从期初回放。同一时刻按 ID 确定快照顺序。

`costBasisForAccount` 返回累计投入成本，`remainingCostBasisForAccount` 返回可为负的净投入。详情与快照行从同一次估值取得市值、现金、净投入、资金净收益及比例。目标 JSON 的 `currency` 保存目标原币，兼容缺少此键的旧记录。

`addAssetSnapshot`、`updateExistingAssetSnapshot` 和 `deleteExistingAssetSnapshot` 在同一事务中维护观测和受影响账户的余额。可以删除或重排已有资金流水的快照，删除最后一张时从期初重建。普通交易不会改写已有观测。旧账本兼容条件见[数据设计](DATA_DESIGN.md#旧账本兼容)。

## 自托管 Web 接口边界

账号同步部署的 API 单独定义，见 [同步接口](SYNC_HOSTING.md#同步接口)。下述边界适用于原有静态自托管版。

Web 自托管版没有 JSON/REST/GraphQL 服务端接口。Caddy 仅提供静态 `index.html`、`flutter_bootstrap.js` 与其他 Flutter 资源、`manifest.json`、`service-worker.js`、`pwa_bootstrap.js`、`sqlite3.wasm`、`drift_worker.js` 和同源回退字体 `fonts/`（清单为 `fonts/SHA256SUMS`，Service Worker 安装时按它预缓存）；`flutter_service_worker.js` 仅作为 Flutter 生成的自注销存根存在，应用不注册它；所有账本 CRUD 仍在浏览器内通过 Drift 执行。反向代理只可把 `https://finance.example.com/` 转发到 `127.0.0.1:8080`，并应在这一层实施 TLS/认证。`sqlite3.wasm` 必须以 `application/wasm` 响应。

浏览器文件选择器可能没有本机路径，`ExportMutations.previewImportBytes` 与 `importJsonBytes` 接收 `Uint8List`，供 Web 按字节预览和导入 JSON；原生 `previewImport`/`importJson` 保留路径接口。两者使用相同的 JSON 格式验证和 Drift 事务替换规则。

## JSON v3

Web 26 的可选交易行字段 `card_posting_date` 用于来源信用卡账单归期；格式及验证见[数据设计](DATA_DESIGN.md)。

顶层字段：`format_version=3`、`transaction_date_semantics=occurrence_date`、`app_version`、`schema_version`、`exported_at`、`meta`、`accounts`、`categories`、`budgets`、`transactions`、`asset_snapshots`、`transaction_templates`、`recurring_transaction_rules`。

完整导出读取 `core/app_version.dart` 的应用版本，测试核对其值与 `pubspec.yaml` 一致。判断数据格式使用 `format_version` 和 `schema_version`，界面版本见设置中的版本信息。JSON 同时携带 `initial_balance`、`current_balance` 与流水。同步修订号、操作 ID 和会话在 JSON 账本之外。余额语义见[账户余额的计算与保存](DATA_DESIGN.md#账户余额的计算与保存)。

`accounts` 的贷款扩展字段为 `loan_principal`、`loan_annual_interest_rate`、`loan_term_months`、`loan_start_date`（合同开始日）、`loan_tracking_start_date`（开始记账日）、`loan_payment_day`、`loan_repayment_method` 和可空的 `loan_quoted_monthly_payment`。日期使用 ISO-8601。JSON v3 保持向后兼容：旧备份缺少追踪日期时按 `NULL` 导入并回退使用合同开始日；新备份的 `schema_version=9`，旧应用可能忽略未知字段，因此回滚前必须保留 v9 恢复点。

导入按整份账本替换。导入前展示数量摘要并要求确认。原生端在路径可用时自动建立 JSON 恢复点，Web 端可从界面下载当前账本。空文件、缺少财务数据或枚举/日期格式错误会拒绝导入。兼容 v1/v2 的旧信用卡资料时，若 `record_date` 与 `transaction_date` 不同，以 `record_date` 作为实际发生日期写入两个字段；信用卡账期由账户级 `statement_day` 推导。

Android/桌面端通过系统文件选择器读取 `.json`，并由同一文件选择器把非空字节直接写入用户选定的文档 URI；Android 写入异常必须返回应用，不能把已创建但未写入的 0 KB 文档报告为成功。应用不会把导出路径写死到公共存储。设置页还可生成最近 6 个月的 AI 摘要 JSON，以及未来 24 个月计划表 CSV。导入完成后 mutation provider 会重新载入 `FinanceRepository`，界面退回主路由，因此账户、交易、预算、模板和周期规则立即使用新快照且不保留引用旧 repository 的详情页。

导入预览与正式导入共用相同的基础格式检查：空文件、截断 JSON、非对象顶层、未来格式版本和错误字段类型都会在改动数据库前被拒绝。正式导入还会验证实体引用与 SQLite 完整性；失败只显示错误消息，不进入空白或黑屏状态。

## AI 分析

应用支持两种当前接口：

- 生成不包含完整原始交易的 AI 摘要 JSON。
- 生成外部分析文本并通过系统分享面板交给 ChatGPT 或其他 AI App。

外部 AI 分享文本由 `AiAnalysisService.buildExternalAnalysisText` 生成，只包含分析提示词和“请上传 JSON”的说明，不自动附带文件。提示词版本 `finance_compass_three_lenses_v3` 支持带 `analysis_contract` 的分析摘要和带 `format_version/accounts/transactions` 的完整备份；接收方必须以 `generated_at` 或 `exported_at` 为截止点，按 `transaction_date` 归属月份，并分别计算消费发生、现金收付和信用负债。

可选 `ai_gateway_url` 由高级设置保存。应用不会把网关描述为隐私诊断功能。

## 外部身份

同步 Web 使用同源用户名密码登录和账号绑定请求头，具体契约见[同步接口](SYNC_HOSTING.md#同步接口)。初次登录打开该账号的服务端账本，本地账本通过显式导入迁移。Google 登录尚未实现。

## 公开项目与下载链接

`FinanceCompassAboutPage` 通过 `url_launcher` 把源码、最新 Release 和 Issues URL 交给操作系统打开：`https://github.com/lawpowen/finance-compass-app`、`/releases/latest` 和 `/issues`。这些入口不附加账本内容、不调用付款接口；打开失败只显示本地 SnackBar。Touch 'n Go 支持二维码是随应用打包的静态资产，不是 API，也不返回付款状态。

## 内部查询契约

`FinanceRepository.cashFlowNetBetween(startInclusive, endInclusive)` 按完整日历窗口返回现金账户的实际净变动，包含已记录的未来实际交易和预计交易；信用卡消费在现金还款前不计入，现金转入贷款或信用账户按转出全额计入。不包含投资/退休等非现金分组的直接收支。结束日期包含当天 23:59:59.999。该接口只读取交易快照，不写数据库。

`FinanceRepository.totalAssetHistory({cutoffDate, includeCredit})` 默认保留包含信用负债的净资产历史，供报表使用；资产目标传入 `includeCredit: false`。`assetGoalSummaries` 固定使用不含 `ReportGroup.credit` 的总资产口径，避免调用方误把贷款或信用卡负债扣入目标进度。`assetGoalSummaries({cutoffDate})` 的截止日由 `FinanceRepository.assetGoalCutoffDate([requested])` 决定：缺省或未来日期一律钳制为今天 23:59:59.999，过去日期原样使用；调用方若要另行计算同口径的当前总资产或趋势，应先调用 `assetGoalCutoffDate` 再传给 `totalAssetsAt` / `totalAssetHistory`。返回的 `reachedAt` 为按日终资产重算的首次达成日（仅日期部分），无法确认时为 `null`。

`FinanceRepository.actualCashFlowSummaryForMonth(monthKey, includePlanned, accountId, type, categoryId)` 与复数月份版本 `actualCashFlowSummaryForMonths` 返回 `CashFlowSummary(inflow, outflow)`。它们只计算 `ReportGroup.cash` 的真实增减，筛选参数先选择交易集合再计算现金两端；默认排除 `planned`。`actualCashOutflowByCategoryForMonths` 将无类别的还款/转账流出放入 `uncategorizedCashOutflowKey`，`actualCashOutflowByAccountForMonth` 只返回现金来源账户。报表和历史平均使用这些接口；预算消费仍使用消费支出接口。

`monthlyFundingNeedForMonth(monthKey, includePlanned:, asOf:)` 返回当月已知现金流出、卡与贷款到期义务以及已覆盖部分。总需求等于已知现金流出加尚未安排的义务。信用卡逐卡按发生日和到期日建立预测时间线，月度指标统计选定月份到期的义务；贷款按目标、期号、本金和利息分别核销。已发生的非现金结算可降低欠款，只有现金付款计入现金支出覆盖。卡还卡同时减少目标账单并增加来源卡义务；包含预计时，两端一起进入预测，同一金额只在对应现金付款或未覆盖到期义务中计入一次。账期不全的付款卡在前瞻现金预测中，对新增卡还卡借款沿用发生日次月 25 日的估算口径。

`cashForecast(asOf:, endInclusive:)` 提供同一个预测窗口内按日期查询的现金余额、期末余额和未覆盖卡款。所有卡先按各自原币核销，再按账本汇率转换到本位币。预测以起始日日终现金为基线，叠加窗口内已知现金流水，在各账期到期时为尚未覆盖的余额计入预测现金支出。之后的同账期现金还款可替换这次预测扣款。到期后的商户退款保留在卡内，可抵后续账单，不增加银行现金。每个取样点读取同一时间线。卡已停用但仍有未付账单时，金额仍进入现金需求；提醒设置和账户启用状态单独控制通知。

`futureCashFlowProjection` 以当前现金资产为运行起点。未来现金还信用卡或贷款时，`transfers` 记录现金端的有符号全额，对应金额只出现一次；现金账户之间的转账按两端折算后的净额处理。折算金额相等时没有流入或流出，跨币转账可能留下净差额。该接口包含预测窗口中的未来实际与预计记录，但不写回账户余额。

`FinanceRepository.accountBalanceAt(accountId, date)` 是带截止时间的实际余额接口；普通无范围账户与资产页面使用 `currentMonthCutoffDate()`。`creditCardCommittedOutstandingBalance(accountId)` 是信用卡当前欠款/额度占用专用接口，读取全部日期已影响物化余额的 `actual`/`settled`，并排除全部 `planned`；账单计算不得用它替代截至今天的 `accountBalanceAt`。页面统一调用 `creditCardOutstandingBalance(accountId, {cutoffDate})` 读取“当前欠款”：未传 `cutoffDate` 时等于承诺负债；传入历史截止时返回 `-accountBalanceAt(accountId, cutoffDate)`；两者都下限为 0，溢缴不计为负债，非信用卡账户抛 `ArgumentError`。`creditCardBillingSummary(accountId, {cutoffDate, now})` 是账户页信用卡行与信用卡详情共用的账期摘要入口：实时模式（无 `cutoffDate`）读取全部交易，并以参考日 23:59:59.999 的余额作为 `calculateCreditCardBilling` 的 `balanceAtCutoff`，与按完整日期划分的账期保持同一边界；历史模式以 `cutoffDate` 为参考日，忽略其后的交易，并在同一精确时刻（而非日终）读取 `balanceAtCutoff`，因此截止时刻之后的同日交易不会进入历史欠款或账期。`creditCardCreditBalance(accountId, {cutoffDate})` 是 `creditCardOutstandingBalance` 的对称只读接口：未传 `cutoffDate` 时返回 `max(currentBalance, 0)`，传入时返回 `max(accountBalanceAt(accountId, cutoffDate), 0)`，非信用卡账户抛 `ArgumentError`；它解释单卡的承诺或指定时点贷方余额。三页净资产统一读取所选月末的资产负债表；目标、现金分组保持独立。`now` 仅供测试或调用方固定参考时间。`resolveCreditCardDisplayState` 新增可选 `committedOutstanding`：本期无应还、无本期活动且下一账期为 0，但该值大于 0.005 时返回 `unbilledOnly`；未传时行为不变。三者均只读，不写入账本。`investmentFlowSummaryForAccount` 未传 `upToDate` 时同样默认当前月末。`futureCashFlowProjection` 和总览预测则以截至今天的余额为基线，只有明确预测范围时才合并未来实际与预计记录。

`calculateLoanAmortization(principal, annualInterestRatePercent, termMonths, startDate, paymentDay, method, quotedMonthlyPayment, openingPrincipal)` 是无数据库写入的贷款计划接口。输入合同金额必须大于零、年利率不得为负、期数为 1–1200、还款日为 1–31；可选 `openingPrincipal` 必须大于零且不超过合同金额。银行核定月供允许 `equalInstallment` 与 `flatRate`，必须覆盖当期利息，`equalPrincipal` 不接受该参数。返回 `LoanAmortizationSchedule`，包含常规月供、待付总额、待付利息和待追踪 `LoanInstallment` 列表；中途建账会在开始余额清零时结束列表，不返回历史期数。

`addRecurringTransactionRule` 将规则、种子关联、预计流水和已生成月份一起提交。生成窗口从明天到第三个后续月末，仅写入该规则尚未占用的名义月份。贷款详情的全期预计生成同样只写 `planned`，需要用户明确选择同币种现金账户并确认；预计项在实际记录对应期数前移除，避免重复进入未来现金流。

信用卡账单领域接口将账期归属、账期流水合计和结算日待还余额分开；完整顺序与职责见下方“信用账单余额接口补充”。选择月份只更新页面内存状态，不修改账户、交易或当前账单状态。

账户页通过 `AccountDetailScreen(account, cutoffDate)`、`CreditCardDetailScreen(account, cutoffDate)` 和 `LoanDetailScreen(account, cutoffDate)` 的可空参数传递历史统计范围。`cutoffDate == null` 表示本月实时模式；非空值必须是所选月份的月末，详情页只读取该日及以前的实际资料并禁用写操作。该状态仅存在于页面内存，不写入数据库、备份或 `app_meta`。

## 分类报告与规划导出

分类筛选和预算投影使用同一分类树。月度预算分配结果包含所归属的原始交易、实际与预计金额，预算预览另提供上月结转和按草稿推演的下月额度。选择父类后，交易筛选使用完整子树；预算仅承担未被更近预算接管的支出。

AI 摘要的 `category_rows` 与 `category_rows_by_month` 按分类 ID 标识，同名项保留父 ID 和路径。直接归属额可加总；子树小计用于查询层级，不能再次与子类相加。未分类使用空分类 ID。预算、支出或历史结转缺汇率时，相关比率与余额标为未估值，导出保留原币及已折算小计。规划 CSV 按类别、ID、指标、币种、月份和总额导出，分别列已确定、预计及合计；未分类和净退款保留，缺汇率部分按原币另列。

## 信用账单余额接口补充

信用卡账单浏览使用五个无写入接口：`availableCreditCardBillingPeriods(account, transactions, now, maximumPeriods)` 返回“未来已确定（升序）→本期→历史（倒序）”的账期列表；`calculateCreditCardBillingPeriodForStatement(statementDay, paymentDueDay, statementDate)` 重建指定结算日；`CreditCardBillingPeriod.billingMonthDate` 以结算日前一天确定用户看到的账单月份；`calculateCreditCardStatementAmount(accountId, transactions, period)` 只汇总来源卡方向的单个账期流水；`calculateCreditCardOriginalStatementAmount(accountId, transactions, period, statementAmountOverride)` 返回可在还款后继续校对的原始账单额：覆盖值优先（下限 0）；否则该期只要有来源卡流水（含净额为 0）即返回其净额；只有完全缺少来源流水且没有显式顺延证据时才以结算日至还款日的明确转入还款（`transferInAmount`，已验证漏记的旧到账在迁移中归一化）作为凭据，负数转账按净额抵减且结果下限 0。返回值在三级中均不为负。它不再取“交易额与还款额较大值”，因此消费 100、还款 150 返回 100。`FinanceRepository.creditCardStatementBalance` 仅保留为结算日余额审计接口，不能替代月份账单金额。选择账单月份只更新页面内存状态，不修改账户、交易或当前账单状态。

## 内部交易删除契约

交易行的三点菜单是既有交易数据的操作接口：`edit` 打开原记录、`reuse` 以新 ID 打开预填草稿、`template` 调用 `addTransactionTemplate`、`recurring` 调用 `addRecurringTransactionRule`、`delete` 走与长按多选一致的确认及原子删除流程。整行点击继续直接进入 `edit`，菜单点击不得触发行点击。

`TransactionComposerPage` 的生成周期选择接受 1–12。新建交易选择大于 1 时调用 `buildRecurringTransactions` 返回多笔结果，所有记录均保持表单当前的 `actual`/`planned` 状态；编辑已有交易永远只返回原 ID 的单笔结果。`RecurringPlanPage` 把用户选择的月份数传给 `generateRecurringTransactions(ruleId, monthsAhead)`，而不是使用固定三个月；Repository 和 `TransactionService` 对每个生成月份统一使用规则保存的状态，不根据是否为未来日期改写。

周期规则编辑器通过现有交易编辑器更新基准交易，通过日期和选项选择器更新 `intervalMonths`、`startDate`、`endDate`，并通过 Repository 完成启停、删除和补生成。预算月份、货币格式及通知偏好均写入本地 Repository/meta；保存成功后失效并重载 `financeRepositoryProvider`。未实现的系统级能力不返回成功结果。

`TransactionFormResult` 是新旧交易编辑器共用的页面返回契约：保存时 `transactions` 包含待新增/更新记录；编辑页确认删除时使用 `TransactionFormResult.deleted(id)`，此时 `transactions` 为空且 `deletedTransactionId` 非空。调用页面必须先处理删除动作，不能把空列表当作保存。交易金额和转入金额接受任何有限 `double`，包括 `0` 和负数；非数字、`NaN` 与无穷必须在写入前拒绝。

结构化月供的数据契约见[贷款还款字段与旧版兼容](DATA_DESIGN.md#贷款计划派生与还款落账)。以下为普通转账的保存契约：来源与目标币种相同则返回 `toAmount=null`、`toCurrency=<目标币种>`，调用者以 `amount` 同时更新两端；币种不同则返回有限的 `toAmount` 与目标账户币种 `toCurrency`。自动建议值通过 `FinanceRepository.convertAmount(amount, fromCurrency, toCurrency)` 读取本地汇率设置，不调用网络；用户手动覆盖后以覆盖值为最终到账金额。

`FinanceRepository.reorderTransactionTemplates(orderedTemplateIds)` 接受包含现有全部模板且每个 ID 恰好一次的完整顺序，重新写入连续 `sortOrder=0..n-1`；缺失、重复或未知 ID 会拒绝保存。`TransactionMutations.reorderTransactionTemplates` 发布刷新后的 Repository，使快速模板管理页和闪电面板立即使用相同前五顺序。

- `TransactionMutations.deleteTransactions(ids)` 是 UI 批量删除入口；成功后把刷新后的 `FinanceRepository` 写回 `financeRepositoryProvider`。
- `FinanceRepository.deleteExistingTransactions(ids)` 调用数据库原子删除并执行现有目标同步刷新逻辑。
- `AppDatabase.deleteTransactionsByIds(ids)` 在同一数据库事务内恢复所有相关账户余额并删除记录；任一 ID 不存在时抛出 `StateError`，不产生部分变更。
- `deleteTransaction(id)` 保持兼容，内部委托给单元素批量删除。

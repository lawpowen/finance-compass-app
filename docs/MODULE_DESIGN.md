# 模块设计

## Web 自托管与浏览器数据库

`core/database/database_connection.dart` 是数据库执行器边界。`database_connection_native.dart` 保留 Android/桌面私有 SQLite 文件与 schema 升级恢复点；`database_connection_web.dart` 通过 `WasmDatabase.open` 打开 `finance_compass.sqlite`，并要求同源的 `sqlite3.wasm` 与 `drift_worker.js`。该选择使 Web UI、Repository 和业务规则复用同一 Drift schema，但 Web 数据只能留在访问者当前浏览器的 OPFS/IndexedDB，不能由静态 Caddy 容器读取。

`core/platform/local_file_io.dart` 对文件路径操作使用条件导入。原生目标可建立导入前 JSON 恢复点；浏览器目标不伪造隐藏服务器文件。浏览器导入依赖 `FilePicker` bytes，并在覆盖前由 UI 预览；用户必须主动下载当前 JSON 作为恢复点。

`deploy/selfhost/` 只包含构建/静态托管边界：Docker 多阶段构建会编译 Flutter Web、Drift Worker，再由 Caddy 送出文件；发行 ZIP 使用已构建的 `webroot` 与 runtime-only Dockerfile，因此解压后无需原始 Flutter 源码。访问控制和 TLS 是外层反向代理责任。

## `core/database`

负责 Drift 表、schema 升级、完整性检查、余额原子更新和 v9 迁移前备份。升级失败必须保留旧文件并向启动层返回错误。

## `core/data`

`FinanceRepository` 是当前页面的聚合读模型和业务入口。它负责币种转换、账户余额、预算、报表、模板/周期规则、导入导出和 AI 摘要。`cashFlowNetBetween` 按精确起止日期汇总现金账户的实际未来变动，供总览 7/30/60/90 天预测使用；贷款还款按现金转出全额计算。

新版现金转账表单显示转出和转入两个金额区域。普通同币种转账使用同一数值并以只读转入栏预览，保存时以 `toAmount=NULL` 维持一个权威金额；结构化贷款月供是明确例外，编辑时保留完整月供 `amount` 与本金 `toAmount`。跨币种调用 `FinanceRepository.convertAmount` 和设置页的 `exchangeRatesToBase` 自动填入 `toAmount`，用户可以覆盖为银行实际到账金额或点击“重新换算”。更改任一账户会重新按对应币种换算；快速模板和编辑记录保留已有跨币种到账金额。`FinanceTransaction.transferInAmount` 同时兼容旧资料中同币种、非零转账的显式 `toAmount=0`；数据库打开及完整导入还会事务式归一记录并补回已发生目标余额。

## `core/models`

领域对象不依赖 Flutter UI。`credit_card_billing.dart` 根据账户级日期和交易账本计算已出账、未出账、还款日及完整账期边界；不修改交易。`loan_amortization.dart` 以固定合同条件生成等额本息、等额本金和平息贷款的分币还款计划；可选 `openingPrincipal` 让中途建账只生成尚待追踪的期数，同样不写数据库。账期与贷款到期日都支持跨年、跨月和月末夹取。信用卡转账按方向解释：信用卡作为来源时增加该卡账单，作为目标时只减少目标卡负债。`AppDatabase` 在打开旧资料及完整导入时，把信用卡关联交易的旧单笔结算日期归一为 `record_date` 发生日期，保证领域计算不会继续读取已废弃语义。

## `core/providers`

`financeRepositoryProvider` 提供当前数据快照。各 mutation provider 执行写入并替换 provider 状态。页面不得绕过 mutation 修改核心账本；通知偏好等单一 meta 设置可直接写入数据库。

## 页面模块

- Dashboard：月度现金流、提醒、资金分布和快捷交易入口；预测卡可选择未来 7、30、60、90 天，并按选择范围更新结束日期、曲线采样和预计余额。预测以截至今天的实际现金为基线，显式窗口才合并未来 `actual`/`settled` 与 `planned`，不得重复加入本月未来交易。
- Accounts：账户分组、净资产、信用卡账单、贷款计划与账户编辑。无显式范围时，贷款负债、投资/退休汇总通过 Repository 的当前月截止余额；多币种贷款负债先换算为基准币种后加入总负债。`AccountFormDialog` 对贷款收集合同条件、开始记账日期和可选开始余额；开始余额默认等于合同金额，中途建账时可改为最近一期账单的剩余贷款。编辑开始余额会保留建账后本金还款形成的余额差额，不生成或删除历史交易。新建完整贷款后，Accounts 页面进入 `LoanDetailScreen` 并询问是否选择同币种现金账户生成全期待还 `planned` 月供；每期只生成一笔结构化转账，`amount` 为完整月供、`toAmount` 为本金。详情页按贷款账户和期号防重，并在打开时把旧版预计本金/利息组合安全合并为月供；实际历史记录不自动迁移。记录实际还款前先移除同一来源账户、到期日和期号的预计记录，再写入实际月供。信用卡当前欠款、信用负债汇总和额度使用则读取承诺负债，即物化余额中的全部 `actual`/`settled`（包括未来分期），同时排除不改变物化余额的 `planned`。信用卡详情把截至今天的交易分为当前已结算账期和下一未出账账期，并通过 `CreditCardDisplayState` 区分账期待设置、无欠款、尚未出账、本期已还清、待还款、今日到期和逾期未还；承诺负债不得提前进入本期账单。右上“查看账单”打开由最早相关交易至本期的月份选择器，选择后以该期结算日重建账期、账单金额、时间线和明细，历史模式不改变实时额度使用，并提供返回本期入口。逾期状态必须同时满足当前账单仍有余额及还款日已过。账单行可进入新版交易编辑器；记录还款复用贷款的同币种现金账户选择模式，在确认可编辑金额后写入现金账户到信用卡的实际转账。投资/退休账户详情直接提供锁定当前账户的市值更新入口，新增快照后由 mutation provider 刷新余额、盈亏与图表。
- Loan deletion and fill：`TransactionMutations` 将贷款旧版本金/利息视为同一期组合；删除任一分项时只在来源账户、状态、发生日和期号均相同且互补记录唯一时扩展为原子批量删除。新版单笔月供直接删除。`LoanDetailScreen` 以计划期号减去已记录和已有预计期号计算缺口，按钮显示生成/补齐的精确期数，缺口为零时禁用。
- Asset goals：`AccountsV2Screen` 的旗标和摘要卡都进入 `AssetGoalsPage`；该页通过 `accountMutationsProvider` 完成目标新增、编辑和删除，并以 Repository 派生的总资产历史、进度、剩余金额及首次达成日展示结果。总资产目标明确排除 `ReportGroup.credit`，不会因信用卡或贷款余额改变目标进度；净资产报表仍使用包含信用负债的默认历史口径。
- Transactions：`TransactionsV2Screen` 顶部以三张可切换卡片提供“实际消费”“实际现金”“信用/贷款”三种口径。实际消费只汇总收入/支出；本月及未来月份的实际现金使用 `MonthlyFundingNeed` 并以“需准备现金”为副标题，历史月份显示实际现金支出；信用/贷款以全部 `ReportGroup.credit` 当前负余额为基础，并以当月信用来源/目标交易拆分新增与偿还。三种口径共用“已发生”/“包含预计”范围，但不改变下方交易列表的可访问性。列表提供真实的账户、类型、类别快速筛选和搜索。默认排除 `planned`，切换后顶部指标与列表一起包含当月 `actual`/`settled` 和 `planned`；信用/贷款卡片仅把当月预计信用净变化叠加为预测值，不写回余额。月份导航允许未来 120 个月，进入未来月份时自动启用“包含预计”，同时保留未来已确定的实际记录。交易整行点击进入编辑，尾部 `FinanceActionMenuButton` 恢复编辑、复用新增、保存模板、保存周期和删除；搜索结果复用同一菜单契约。`TransactionComposerPage` 编辑模式在页面底部提供独立删除入口，二次确认后以 `TransactionFormResult.deleted` 把 ID 交回调用页面，再由 mutation 删除并刷新；旧高级表单遵守相同契约。普通列表长按进入多选模式，点击追加选择，可选择当前可见结果并在确认后原子删除。金额字段接受有限的正数、零和负数，数据库继续使用既有代数余额规则。页面监听 `financeRepositoryProvider`，删除成功后立即使用最新账本快照重建。原 `TransactionsScreen` 作为高级筛选入口保留。
- Transactions automation：`QuickTemplateManagerPage` 和 `RecurringPlanPage` 直接读取及写入 `transaction_templates`、`recurring_transaction_rules`；模板试用只预填交易表单。普通新增交易可在 `TransactionComposerPage` 选择 1–12 个月并一次生成，所有月份统一保留表单选择的 `actual` 或 `planned`；周期计划页同样先选择 1–12 个月再主动生成，所有新月份继承规则状态，已存在月份由 Repository 去重。创建或编辑规则不得把 `planned` 强制改成 `actual`，且只保存一份规则基准交易，不误用表单的批量生成结果。
- Interaction wiring：周期规则编辑页的交易、金额/账户、类别、间隔、开始日期和结束条件均复用真实编辑器或选择器；顶部菜单负责启停和删除，补生成入口选择 1–12 个月。预算编辑器保存所选生效月份并提供真实结转预览；报表区间选择刷新图表与分享摘要；货币显示与应用内提醒设置写入 meta 并触发 Repository 刷新。
- Transactions filtering and funding need：账户、类型和类别筛选先生成统一交易集合，再交给列表、实际消费与信用/贷款口径；“实际现金”直接读取全月 `MonthlyFundingNeed`，已知现金流出加尚未安排的到期信用卡/贷款，已有还款只作为覆盖额而不重复相加。该卡只跟随所选月份与“已发生/包含预计”，不受下方明细筛选影响。选中时以“需准备现金”为副标题，复用原两项解释区展示已知流出/尚未安排，并用一行说明到期与覆盖，不新增独立大卡。
- Budgets：月度预算总览、分类预算和消费明细；新增、修改、删除和月份切换都通过真实 repository/mutation 数据完成，空月份不注入示例预算。每条预算是从 `monthKey` 起生效的规则，`activeBudgetsForMonth` 为每个类别选择不晚于目标月的最新记录。编辑时只有类别和生效月份均不变才更新原 ID；改为新月份或新类别时创建新 ID，因此历史月份不会被新规则覆盖。预算构成按分类基础预算排序并展示最多五个分类，占比口径为分类基础预算除以当月已分配预算；实际、预计和未使用部分分别以实色、斜纹和底色表达。
- Reports：趋势、分类、净资产、预算洞察和未来现金流。报表收支统一调用 `actualCashFlowSummaryForMonth(s)`：现金收入/支出直接计入，信用消费等到现金还款时计入，现金间转账净额为零，现金还贷款按完整 `amount` 计入流出。`futureCashFlowProjection` 以现金资产为起点并使用同一现金增减函数，不能把贷款目标入账与现金付款相抵后只留下利息。
- Settings：本地账户、币种、规则、备份、外观、通知和外部 AI 分析。完整导出先构建并校验非空字节，再交给系统文档选择器写入；完整导入在替换数据库前校验格式、ID 与引用，失败保留原数据并显示错误，成功后返回主路由避免旧详情页继续持有过期 repository。外观页以 `PageView` 提供 12 款主题的拖动预览，预览状态与持久化设置分离，用户确认后才调用设置控制器应用。外部 AI 分享使用 `finance_compass_three_lenses_v3` 提示词，兼容分析摘要 JSON 与完整备份 JSON；以 `generated_at`/`exported_at` 为截止点，要求分别分析消费发生、现金收付和信用负债，未来 `actual`/`settled` 只能作为“未来已确定”，`planned` 只能作为预计。信用卡还款只进入现金口径，投资/退休转账只属于资产重配置，周期规则与已生成交易必须去重。导入/导出、备份、分类、模板与周期规则是当前可用能力；Google 登录、系统通知调度及交易附件明确标为计划中，不得显示虚假成功状态。

Settings public support：右上帮助入口打开 `FinanceCompassAboutPage`，展示版本、本地数据边界、公开源码/下载/问题链接及静态 Touch 'n Go 支持二维码；链接通过系统外部应用打开，失败显示提示。二维码支持完全自愿，不参与功能授权或付款状态。

页面与 29 张确认截图的逐项映射、视觉契约和 390 像素检查规则见 [UI 参考基线](UI_REFERENCE.md)。主导航页面读取真实 `FinanceRepository` 数据；参考图中的示例金额不得覆盖用户账本。快速模板、周期计划、报表详情和设置详情使用独立页面，但共享 `CompassBackground`、`CompassSettingsRow`、`CompassSegmentedControl` 和金额格式化规则。`QuickTemplateManagerPage` 使用单一可重排列表覆盖全部模板，允许其他模板拖入前五；`TransactionMutations.reorderTransactionTemplates` 将完整 ID 顺序交给 Repository 校验并一次性重写连续 `sortOrder`，避免逐项保存形成重复排序值。新增模板的命名对话框使用 `TextFormField.initialValue` 和局部字符串保存输入，不在 `showDialog` 返回时提前销毁仍参与退出动画的 `TextEditingController`；旧交易页的模板和周期命名入口遵循同一生命周期规则。

页面失败时显示 provider 错误；表单验证失败不得写入数据库。删除账户/类别时，如存在交易、快照、预算、模板或周期规则引用，必须拒绝删除。

## 账户统计截止与交互提示

`AccountsV2Screen` 在内存中保存所选统计月份，以月末生成统一 `cutoffDate`；可选范围从最早交易、资产快照或贷款追踪月份连续列到当前月。现金、投资、退休、信用卡和贷款汇总都按该截止日期计算，打开 `AccountDetailScreen`、`CreditCardDetailScreen` 或 `LoanDetailScreen` 时通过可空 `cutoffDate` 继续传递。历史详情显示截止提示并关闭全部写入入口，返回本月后恢复实时状态与操作。

类别分组标题由真实展开状态驱动上下箭头并支持整行点击；直接输入框、禁用计划项和只读预览不绘制导航箭头。源码门禁同时拒绝空回调和没有附近交互处理器的方向性图标，避免“看起来能点但点击无反应”再次出现。

## 信用卡未来账单浏览补充

`CreditCardDetailScreen` 把未来 `actual`/`settled` 记录所在账期作为“已确定”月份加入账单选择器，并允许查看对应时间线和可编辑交易；`planned` 记录不进入该列表。当前未出账只展示截至今天已发生的记录，下一期基础金额使用下一完整账期的来源卡流水合计，因此已经锁定额度的未来分期只进入各自月份，不与账户累计欠款混算。`calculateCreditCardBilling` 会根据截至今天的实际欠款推导本期是否已经还清，并只在存在明确转入还款时，把超出本期剩余应还的部分从下一期基础金额扣除；这使银行已使用额度和下期剩余承诺保持一致，同时不让旧资料中的不完整余额污染账期金额。月份选择器和历史标题使用结算日前一天作为账单月份；原始账单额由 `calculateCreditCardOriginalStatementAmount` 提供，还款后仍可校对。若本地对账已把银行结单总额写入账户级 `app_meta`，`FinanceRepository.creditCardStatementAmountOverride` 按结算日返回权威值，详情页优先展示该值；缺失或损坏的 meta 自动回退到交易推算。`FinanceRepository.creditCardStatementBalance` 只用于结算日余额审计。

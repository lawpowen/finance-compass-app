# 模块设计

账号同步由 `features/sync` 的入口、`core/sync` 的会话、Repository Provider 的写入边界以及 `server` 的认证和账本修订管理组成。详见[账号同步](SYNC_HOSTING.md)。

## Web 自托管与浏览器数据库

`core/database/database_connection.dart` 是数据库执行器边界。`database_connection_native.dart` 保留 Android/桌面私有 SQLite 文件与 schema 升级恢复点；`database_connection_web.dart` 通过 `WasmDatabase.open` 打开 `finance_compass.sqlite`，并要求同源的 `sqlite3.wasm` 与 `drift_worker.js`。该选择使 Web UI、Repository 和业务规则复用同一 Drift schema，但 Web 数据只能留在访问者当前浏览器的 OPFS/IndexedDB，不能由静态 Caddy 容器读取。

`core/platform/local_file_io.dart` 对文件路径操作使用条件导入。原生目标可建立导入前 JSON 恢复点；浏览器目标不伪造隐藏服务器文件。浏览器导入依赖 `FilePicker` bytes，并在覆盖前由 UI 预览；用户必须主动下载当前 JSON 作为恢复点。

`deploy/selfhost/` 只包含构建/静态托管边界：Docker 多阶段构建运行与本机相同的 `tool/build_web.sh`（编译 Drift Worker 与 Flutter Web 并校验交付契约），再由 Caddy 送出文件；`web/flutter_bootstrap.js` 决定引擎加载配置（不注册 Flutter 的 Service Worker 存根、回退字体走同源 `fonts/`），`web/service-worker.js` 是唯一应用 Worker；发行 ZIP 使用已构建的 `webroot` 与 runtime-only Dockerfile，因此解压后无需原始 Flutter 源码。访问控制和 TLS 是外层反向代理责任。

## `core/database`

负责 Drift 表、schema 升级、完整性检查、余额原子更新和 v9 迁移前备份。升级失败必须保留旧文件并向启动层返回错误。

`AppDatabase` 负责交易写入及余额差额的原子应用和反转。Repository 负责原币及本位币读模型、日期截止和导入导出。边界见[账户余额的计算与保存](DATA_DESIGN.md#账户余额的计算与保存)。

## `core/data`

`FinanceRepository` 是当前页面的聚合读模型和业务入口。它负责币种转换、账户余额、预算、报表、模板/周期规则、导入导出和 AI 摘要。`cashFlowNetBetween` 按精确起止日期汇总现金账户的实际未来变动，供总览 7/30/60/90 天预测使用；贷款还款按现金转出全额计算。

新版现金转账表单显示转出和转入两个金额区域。普通同币种转账使用同一数值并以只读转入栏预览，保存时以 `toAmount=NULL` 维持一个权威金额；结构化贷款月供是明确例外，编辑时保留完整月供 `amount` 与本金 `toAmount`。跨币种调用 `FinanceRepository.convertAmount` 和设置页的 `exchangeRatesToBase` 自动填入 `toAmount`，用户可以覆盖为银行实际到账金额或点击“重新换算”。更改任一账户会重新按对应币种换算；快速模板和编辑记录保留已有跨币种到账金额。显式零本金沿用其原值；旧普通转账只有在开账余额和流水有足够证据时才补正。

## `core/models`

领域对象不依赖 Flutter UI。`credit_card_billing.dart` 根据账户级日期和交易账本计算已出账、未出账、还款日及完整账期边界；不修改交易。`loan_amortization.dart` 以固定合同条件生成等额本息、等额本金和平息贷款的分币还款计划；可选 `openingPrincipal` 让中途建账只生成尚待追踪的期数，同样不写数据库。账期与贷款到期日都支持跨年、跨月和月末夹取。信用卡转账按方向解释：信用卡作为来源时增加该卡账单，作为目标时只减少目标卡负债。`AppDatabase` 在打开旧资料及完整导入时，把信用卡关联交易的旧单笔结算日期归一为 `record_date` 发生日期，保证领域计算不会继续读取已废弃语义。

## `core/providers`

`financeRepositoryProvider` 提供当前数据快照。各 mutation provider 执行写入并替换 provider 状态。通知偏好走同一写入路径，以便同步版把更新后的 `app_meta` 提交给服务端。浏览器订阅通过同步账号单独登记。

## `core/sync`、`features/sync` 与 `server`

- `FinanceSyncGate` 处理登录、注册、本地模式入口、后台修订检查、PWA 更新提示及同步恢复界面。
- `LedgerSyncSession` 串行化本机修改并更新待上传队列。浏览器适配层保存队列并用比较后替换处理同源标签页竞争。
- `server/sync.mjs` 提供同源 API 和会话校验。`server/snapshot.mjs` 验证快照结构和引用。`server/store.mjs` 在 SQLite 内维护账号、账本修订和操作去重。`server/reminder-events.mjs` 与 `server/push.mjs` 负责推导和发送 Web Push。

## 主题体系与多外观扩展

`core/settings/app_theme_style.dart` 定义 `selectableStyles`（`monochrome`、`dopamine`、`liquidGlass`）与 `normalize(raw)`，保留历史枚举兼容并将未知或已下线主题值统一归一至黑白极简；`AppSettingsController` 按设备保存用户选定外观。原生端写入 SQLite `app_meta['theme_style']`，Web 写入当前 origin 的 `localStorage['finance-compass.theme_style']`。持久化成功后通知界面刷新。`core/theme/finance_theme.dart` 的 `FinanceThemePalette` 通过声明式令牌（`warning`、`primaryAction`、`cardSurface`、`cardBlurSigma`、`cardShadowColor`、`dockBlurSigma`、`dockSurfaceAlpha`、`dockShadowColor`、`donutColors`、`donutSeparatorColor`、`backgroundMiddle`、`glassHighlightColor`、`selectedSurface`）统一驱动 `CompassBackground`（含三段冰蓝渐变）、`CompassCard` / `FinanceDonutPanel`（含可选零布局高光绘笔 `compassGlassHighlight` 与渐变描边）以及 `_CompassDock` 的毛玻璃胶囊与高亮选态。Web 25 的滚动卡片与环图仅在宽度至少 960 逻辑像素且使用 GPU 时采样模糊背景。窄屏 GPU 保留高光和悬浮 Dock 的模糊，CPU 模式直接绘制高光组件的子内容。

## 页面与兼容入口

生产 `HomeScreen` 挂载六个 V2 主页面。旧 `DashboardScreen`、`AccountsScreen` 和 `BudgetsScreen` 是保留的布局参考；`SettingsScreen` 仍作为高级设置页使用。新版记账入口是 `TransactionComposerPage`，旧 `TransactionFormDialog` 保留兼容测试及共享表单工具。手机端与桌面端读取相同账户名、类别名和有符号金额。

设置、通知、规则中心、账户详情和编辑器绑定当前账本的 Riverpod 作用域。子页面提交后，父页消费新修订。金额显示、通知偏好和 AI 网关地址通过 mutation 保存；主题偏好由设备设置控制器保存。正在编辑的字段保留草稿，源记录删除或发生冲突时给出重新核对入口。

`forecastSummary` 在最近 12 个已结束的日历月中选取最近有实际现金变动的月份，没有历史样本时沿用截止日净资产。AI 分析使用同一自然日边界，今日归入已发生，未来窗口从明天开始并覆盖终止月份整日。兼容交易服务的待发生支出列表和支出准备金也从明天零点起算，退款按原符号计入。未来投影区分非转账收支和现金账户端的有符号转账净额；结余为期初现金加收入、减支出、加转账。周期规则模板状态与生成的预计状态分别输出。

## 页面模块

- Dashboard：顶部 4 格 KPI 速览条、月度现金流、完整信用卡提醒＋前三排序预算告警的「需要关注」区、资金分布及近期 4 条非预计交易卡片；预测卡可选择未来 7、30、60、90 天，并按选择范围更新结束日期、带悬停提示的交互曲线、最低点警戒和预计余额。预测以今日日终实际现金为基线，各样本使用相同的窗口规则汇总已知现金流水及所有卡尚未覆盖的到期付款，均折算到账本本位币。
- Accounts：账户分组小计、外币原币折合显示、信用卡溢缴徽章与额度双层进度条、投资收益率徽章、已对账月份、精选目标进度条、历史截止一键「返回本月」，以及净资产、信用卡账单、贷款计划与账户编辑。无显式范围时，贷款负债、投资/退休汇总通过 Repository 的当前月截止余额；多币种贷款负债先换算为基准币种后加入总负债。`AccountFormDialog` 对贷款收集合同条件、开始记账日期和可选开始余额；开始余额默认等于合同金额，中途建账时可改为最近一期账单的剩余贷款。编辑开始余额会保留建账后本金还款形成的余额差额，不生成或删除历史交易。新建完整贷款后，Accounts 页面进入 `LoanDetailScreen` 并询问是否选择同币种现金账户生成全期待还 `planned` 月供；每期只生成一笔结构化转账，`amount` 为完整月供、`toAmount` 为本金。详情页按贷款账户和期号防重，并在打开时把旧版预计本金/利息组合安全合并为月供；实际历史记录不自动迁移。确认还款时按贷款和期号在一个事务内清理计划并记录剩余本金及利息。更换付款账户保留分期身份。信用卡详情的承诺欠款和额度使用读取承诺负债，即物化余额中的全部 `actual`/`settled`（包括未来分期），同时排除不改变物化余额的 `planned`。`AccountsV2Screen` 的信用卡行与“负债总额”、`CreditCardDetailScreen` 的额度使用与“当前欠款（估算）”都经 `FinanceRepository.creditCardOutstandingBalance` 取值：账户汇总为所选月末余额，实时详情另列承诺负债，结果不低于 0，溢缴卡不会被计为负债。月末资产负债表分别汇总各账户的资产、透支、欠款及溢付，每个账户对净值贡献一次。资产目标排除卡与贷款。两页的账期摘要都经 `creditCardBillingSummary` 生成：实时模式以参考日日终余额对齐按完整日期划分的账期，历史模式以精确截止时刻读取余额且只使用截止前交易；页面把同一欠款值作为 `committedOutstanding` 传给状态判定，因此只有远期已确定分期时显示“尚未出账”，详情主金额显示“当前欠款”而非 0，且“提前还款”按该欠款值启用。本期已还清（`paidThisCycle`）时，按钮文案与可点击状态都按当前欠款判断（大于 0.005 为“提前还款”，否则为“无需还款”），主金额与状态仍为本期口径；当展示金额不大于 0.005 而仍可还款时，传给还款对话框的默认金额回退为当前欠款。信用卡详情把截至今天的交易分为当前已结算账期和下一未出账账期，并通过 `CreditCardDisplayState` 区分账期待设置、无欠款、尚未出账、本期已还清、待还款、今日到期和逾期未还；承诺负债不得提前进入本期账单。右上“查看账单”打开由最早相关交易至本期的月份选择器，选择后以该期结算日重建账期、账单金额、时间线和明细，历史模式不改变实时额度使用，并提供返回本期入口。逾期状态使用最早未清账期的应付余额及原还款日。账单行可进入新版交易编辑器；记录还款复用贷款的同币种现金账户选择模式，在确认可编辑金额后写入现金账户到信用卡的实际转账；金额必须是有限正数，`NaN`/`Infinity`/不大于 0 时提示并保持对话框打开，不调用 mutation。`AccountFormDialog` 的信用卡分区以“信用卡余额”显示原币有符号金额，负数为欠款、正数为溢缴。可录入的余额须为有限数。已有流水或快照时，表单锁定余额、币种、类型及报表分组，由账本继续计算余额。所有账户详情页在桌面均居中限宽 840 逻辑像素；普通现金账户详情 `AccountDetailScreen` 提供余额主卡与一键「标记已对账至 YYYY-MM」、当月流入/流出/净变化、可扩展可点击编辑的流水明细以及余额追溯卡片。投资/退休账户详情直接提供锁定当前账户的市值更新入口，新增快照后由 mutation provider 刷新余额、盈亏与图表。
- Loan deletion and fill：`TransactionMutations` 将贷款旧版本金/利息视为同一期组合；删除任一分项时只在来源账户、状态、发生日和期号均相同且互补记录唯一时扩展为原子批量删除。新版单笔月供直接删除。`LoanDetailScreen` 以计划期号减去已记录和已有预计期号计算缺口，按钮显示生成/补齐的精确期数，缺口为零时禁用。
- Asset goals：`AccountsV2Screen` 的旗标和摘要卡都进入 `AssetGoalsPage`；该页通过 `accountMutationsProvider` 完成目标新增、编辑和删除，并以 Repository 派生的总资产历史、进度、剩余金额及首次达成日展示结果。总资产目标明确排除 `ReportGroup.credit`，不会因信用卡或贷款余额改变目标进度；净资产报表仍使用包含信用负债的默认历史口径。目标页及旧 `AccountsScreen` 的目标区块统一以 `assetGoalCutoffDate` 截止到今天日终，不计入本月剩余日期的未来实际交易；首次达成日规则见 [DATA_DESIGN.md](DATA_DESIGN.md#资产目标统计口径)。
- Transactions：`TransactionsV2Screen` 顶部以三张可切换卡片提供“实际消费”“实际现金”“信用/贷款”三种口径，工具栏支持「本月」复位、桌面「多选」与「清除筛选」药丸，移动端按日分组展示每日支出/收入小计及转账目标流向。实际消费只汇总收入/支出；本月及未来月份的实际现金使用 `MonthlyFundingNeed` 并以“需准备现金”为副标题，历史月份显示实际现金支出；信用/贷款以所选月末的各户带符号余额为基础。逐账户叠加当月已选预计变动后再计算欠款；新增与偿还分列。三种口径共用“已发生”/“包含预计”范围，但不改变下方交易列表的可访问性。列表提供真实的账户、类型、类别快速筛选和搜索。默认排除 `planned`，切换后顶部指标与列表一起包含当月 `actual`/`settled` 和 `planned`；信用/贷款卡片仅把当月预计信用净变化叠加为预测值，不写回余额。月份导航允许未来 120 个月，进入未来月份时自动启用“包含预计”，同时保留未来已确定的实际记录。交易整行点击进入编辑，尾部 `FinanceActionMenuButton` 恢复编辑、复用新增、保存模板、保存周期和删除；搜索结果复用同一菜单契约。`TransactionComposerPage` 动态区分“收款账户”“付款账户”等关系标题，提供快捷日期/分类筹码、带余额提示的选择面板、语义化类型页签，并在编辑模式页面底部提供独立删除入口，二次确认后以 `TransactionFormResult.deleted` 把 ID 交回调用页面，再由 mutation 删除并刷新；旧高级表单遵守相同契约。普通列表长按（或桌面工具栏开关）进入多选模式，点击追加选择，可选择当前可见结果并在确认后原子删除。金额字段接受有限的正数、零和负数，数据库继续使用既有代数余额规则。页面监听 `financeRepositoryProvider`，删除成功后立即使用最新账本快照重建。主交易页内置账户、类型和类别多选筛选：组内取任一、组间同时满足；转账来源或目标账户均可命中。面板取消不提交，应用后同步更新列表与可筛选指标；有明细筛选时显示所选账户端的现金流入、流出，并单列不受筛选影响的全月资金需求。按类型或类别筛选信用/贷款时，显示匹配流水的承诺净变动。旧高级筛选页已移除。
- Transactions automation：`QuickTemplateManagerPage` 和 `RecurringPlanPage` 直接读取及写入 `transaction_templates`、`recurring_transaction_rules`；模板试用只预填交易表单。普通新增交易可在 `TransactionComposerPage` 选择 1–12 个月并一次生成，所有月份统一保留表单选择的 `actual` 或 `planned`；周期计划页同样先选择 1–12 个月再主动生成，新生成月份统一写入 `planned`，已存在月份由 Repository 去重。创建或编辑规则不得把 `planned` 强制改成 `actual`，且只保存一份规则基准交易，不误用表单的批量生成结果。
- Interaction wiring：周期规则编辑页的交易、金额/账户、类别、间隔、开始日期和结束条件均复用真实编辑器或选择器；顶部菜单负责启停和删除，补生成入口选择 1–12 个月。预算编辑器保存所选生效月份并提供真实结转预览；报表区间选择刷新图表与分享摘要；货币显示与应用内提醒设置写入 meta 并触发 Repository 刷新。
- Transactions filtering and funding need：账户、类型和类别筛选先生成统一交易集合，再交给列表、实际消费与信用/贷款口径；本月及未来月份的“实际现金”读取全月 `MonthlyFundingNeed`，已知现金流出加尚未安排的到期信用卡/贷款，已有还款只作为覆盖额而不重复相加。全月资金需求只跟随所选月份与“已发生/包含预计”。历史月份显示随明细筛选变化的现金流出与流入。选中时以“需准备现金”为副标题，复用原两项解释区展示已知流出/尚未安排，并用一行说明到期与覆盖，不新增独立大卡。
- Budgets：月度预算总览、分类预算和消费明细；新增、修改、删除和月份切换（含非本月时的「本月」复位）都通过真实 repository/mutation 数据完成，空月份不注入示例预算。每条预算是从 `monthKey` 起生效的规则，`activeBudgetsForMonth` 为每个类别选择不晚于目标月的最新记录。编辑时只有类别和生效月份均不变才更新原 ID；改为新月份或新类别时创建新 ID，因此历史月份不会被新规则覆盖。预算构成按分类基础预算排序，展示前三个分类，其余合并为「其他」，占比口径为分类基础预算除以当月已分配预算；桌面总览保留实际、预计、结转及日均可用参考。手机分类列表显示占比与剩余，点进详情可查看实际、预计与结转。编辑器使用动态本位币后缀与 70%/80%/90%/100% 提醒阈值选择器。
- Reports：`ReportsV2Screen` 在一页展示所选期间的净资产变化与交互式悬停趋势、实际现金流与月均净流入交互式趋势，以及按交易发生口径统计且附带比例进度条的支出分类排行（默认展示前 5，超过 5 项时提供页内「展开全部 N 个分类 / 收起至前 5」切换，不推入新路由）；当前资产构成（含图例金额）、投资与退休账户资金净收益按当前月末计算，本月预算（含 `CompassDualProgressBar`）按当前月份计算，并明确标注不随期间变化。旧报表详情页已移除。报表收支统一调用 `actualCashFlowSummaryForMonth(s)`：现金收入/支出直接计入，信用消费等到现金还款时计入，现金间转账按两端折算后的净额统计，现金还贷款按完整 `amount` 计入流出。`futureCashFlowProjection` 以现金资产为起点并使用同一现金增减函数，不能把贷款目标入账与现金付款相抵后只留下利息。
- Settings：本地账户、币种、规则、备份、外观、通知和外部 AI 分析。完整导出先构建并校验非空字节，再交给系统文档选择器写入；完整导入在替换数据库前校验格式、ID 与引用，失败保留原数据并显示错误，成功后返回主路由避免旧详情页继续持有过期 repository。通过「个性化 -> 外观与主题」（可搜索）进入 `AppearancePage`，支持在黑白极简、多巴胺与苹果液态玻璃之间局部实时预览，点击「应用主题」并由 `AppSettingsController` 成功写入设备偏好后刷新全局界面，取消或失败保持原主题，旧样式仍自动归一到黑白极简。外部 AI 分享使用 `finance_compass_three_lenses_v3` 提示词，兼容分析摘要 JSON 与完整备份 JSON；以 `generated_at`/`exported_at` 为截止点，要求分别分析消费发生、现金收付和信用负债，未来 `actual`/`settled` 只能作为“未来已确定”，`planned` 只能作为预计。信用卡还款只进入现金口径，投资/退休转账只属于资产重配置，周期规则与已生成交易必须去重。导入/导出、备份、分类、模板与周期规则是当前可用能力；Google 登录、原生系统通知调度及交易附件明确标为计划中。同步 Web 支持 Web Push，不得显示虚假成功状态。

Settings public support：右上帮助入口打开 `FinanceCompassAboutPage`，展示版本、本地数据边界、公开源码/下载/问题链接及静态 Touch 'n Go 支持二维码；链接通过系统外部应用打开，失败显示提示。二维码支持完全自愿，不参与功能授权或付款状态。

页面与 29 张确认截图的逐项映射、视觉契约和 390 像素检查规则见 [UI 参考基线](UI_REFERENCE.md)。主导航页面读取真实 `FinanceRepository` 数据；参考图中的示例金额不得覆盖用户账本。快速模板、周期计划和设置详情使用独立页面；报表分析留在 `ReportsV2Screen` 内，但共享 `CompassBackground`、`CompassSettingsRow`、`CompassSegmentedControl` 和金额格式化规则。`QuickTemplateManagerPage` 使用单一可重排列表覆盖全部模板，允许其他模板拖入前五；`TransactionMutations.reorderTransactionTemplates` 将完整 ID 顺序交给 Repository 校验并一次性重写连续 `sortOrder`，避免逐项保存形成重复排序值。新增模板的命名对话框使用 `TextFormField.initialValue` 和局部字符串保存输入，不在 `showDialog` 返回时提前销毁仍参与退出动画的 `TextEditingController`；交易页的模板和周期命名入口遵循同一生命周期规则。

页面失败时显示 provider 错误；表单验证失败不得写入数据库。删除账户/类别时，如存在交易、快照、预算、模板或周期规则引用，必须拒绝删除。

## 账户统计截止与交互提示

投资详情和快照表单使用相同的估值结果。无市值观测时仍展示期初、实际资金流水及收益；每个历史快照行使用本次观测时刻的市值、现金和净投入。可编辑的最早观测定义资金成本基准。交易修改后由数据库更新余额缓存，观测保持原值；余额追溯按同一计算次序解释每笔变化。公式和旧库处理见[数据设计](DATA_DESIGN.md#投资快照与剩余成本)。

`AccountsV2Screen` 在内存中保存所选统计月份，以月末生成统一 `cutoffDate`；可选范围从最早交易、资产快照或贷款追踪月份连续列到当前月。现金、投资、退休、信用卡和贷款汇总都按该截止日期计算，打开 `AccountDetailScreen`、`CreditCardDetailScreen` 或 `LoanDetailScreen` 时通过可空 `cutoffDate` 继续传递。历史详情显示截止提示并关闭全部写入入口，返回本月后恢复实时状态与操作。

类别分组标题由真实展开状态驱动上下箭头并支持整行点击；直接输入框、禁用计划项和只读预览不绘制导航箭头。源码门禁同时拒绝空回调和没有附近交互处理器的方向性图标，避免“看起来能点但点击无反应”再次出现。

## 信用卡未来账单浏览补充

`CreditCardDetailScreen` 把未来 `actual`/`settled` 记录所在账期作为“已确定”月份加入账单选择器，并允许查看对应时间线和可编辑交易；`planned` 记录不进入该列表。当前未出账只展示截至今天已发生的记录，下一期基础金额使用下一完整账期的来源卡流水合计，因此已经锁定额度的未来分期只进入各自月份，不与账户累计欠款混算。`calculateCreditCardBilling` 会根据截至今天的实际欠款推导本期是否已经还清，并只在存在明确转入还款时，把超出本期剩余应还的部分从下一期基础金额扣除；这使银行已使用额度和下期剩余承诺保持一致，同时不让旧资料中的不完整余额污染账期金额。月份选择器和历史标题使用结算日前一天作为账单月份；原始账单额由 `calculateCreditCardOriginalStatementAmount` 提供，还款后仍可校对。若本地对账已把银行结单总额写入账户级 `app_meta`，`FinanceRepository.creditCardStatementAmountOverride` 按结算日返回权威值，详情页优先展示该值；缺失或损坏的 meta 自动回退到交易推算。`FinanceRepository.creditCardStatementBalance` 只用于结算日余额审计。

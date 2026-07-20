# 测试与质量

## 自动化层级

- 领域单元测试：币种、现金流、模板、周期规则、信用卡账单。
- 数据库迁移测试：构造 v6 SQLite，升级到 v7，验证余额、空信用卡字段、模板 ID、本地资料 ID，并确认旧信用卡单笔结算日期归一为发生日期而现金交易不变。
- 数据可携测试：导出包含真实账户、分类、交易、模板及周期规则的 JSON v3，预览数量后导入到空数据库，并验证模板排序与规则启停状态不丢失；旧 v1/v2 信用卡 JSON 导入后以 `record_date` 作为账期发生日期，v3 则保留已编辑的 `transaction_date`。
- Widget 测试：表单、报表比较卡和主要启动界面。
- 外观交互测试：在 390×844 逻辑像素验证主题卡片可拖动、预览不会自动应用，并可切换总览/交易预览。
- 交易与账期回归：验证跨月/月末账期边界、旧账期不混入、信用卡对信用卡转账只进入来源卡账单、未来月份导航、未来预计交易可见、交易编辑保留原 ID/录入时间、已还清账单不误报逾期，以及总览预测范围切换。
- 交易计算口径回归：默认“已发生”必须同时从顶部汇总和列表排除 `planned`；选择“包含预计”后，实际与预计记录同时可见。消费发生排除转账，现金收付只计算现金账户两端的净变化，已承诺使用当前信用负债并只叠加当月预计信用净变化。进入未来月份时使用相同合并范围，不得隐藏未来 `actual`。
- 历史账单回归：验证结算日 25、还款日 14 时，4 月 29 日交易归入 5 月 25 日结算账单并对应 6 月 14 日还款；在 390×844 视口打开账单月份列表、选择往期、切换金额/时间线/明细，并确认其他账期交易不混入。
- 原始账单与每月 1 日结算回归：验证已还款历史月份仍显示原始账单额；8 月 1 日结算显示为 7 月账单；7 月三笔 MYR 69.85、161.33、82.11 合计为 MYR 313.29，且下一期已使用额度不读取累计账户余额。旧导入消费明细缺失时，验证结算日至还款日的明确转入还款可作为原始账单额下限。
- 银行结单快照回归：验证完成对账后传入的权威账单金额覆盖交易合计与还款下限；未提供快照时保持原推算，损坏 meta 必须安全回退。历史快照不得改变当前欠款和额度使用。
- 已确定账单与银行明细回归：未来 `actual` 分期按各月结算日形成可浏览账单并显示对应还款日，未来 `planned` 完全排除；UOB 样本以账单截止余额纳入消费、还款和退款，防止使用毛消费额替代待还金额；本期已还清且存在超额还款时，下期已使用额度扣除可证明的超额部分，同时保留下一结算日前未来已确定消费。
- 投资市值入口回归：在 390×844 逻辑像素验证投资账户详情可打开市值更新表单、账户被锁定为当前账户，长账户名不产生横向溢出。
- 状态与时间口径回归：验证 EPF/退休账户默认余额与流入只到当前月、未来 `actual` 不提前进入普通账户默认现状、`planned` 不进入实际余额；信用卡账单不读取未来交易，但当前欠款和额度使用包含未来 `actual`、排除未来 `planned`；预测从今天余额起算并只累计一次未来实际/预计交易。
- 交易批量删除回归：在 390×844 视口长按第一笔、点击追加第二笔、确认删除，验证两行立即消失、成功提示出现且账户余额恢复；数据库层另以一个有效 ID 和一个失效 ID 验证整批回滚。
- 交易编辑删除与有符号金额回归：编辑页滚动至删除入口后分别验证取消与确认；确认结果只包含待删除 ID。金额用例覆盖 `0.00` 与负数保存，并在 Repository 层验证零金额无余额影响、负支出/负转账的代数方向及删除后的余额完全恢复。
- 同/跨币种转账回归：表单显示双金额；同币种自动相等、转入栏只读且保存 `toAmount=NULL`。跨币种按 Repository 当前汇率自动填值，允许覆盖后将该值写入目标余额；旧快速模板遗留的非零同币种转账 `toAmount=0` 必须按来源金额计入目标账户。应用打开与 JSON 导入会归一字段，并只为 `actual`/`settled` 补回目标余额。
- 交易菜单与周期生成回归：验证整行点击仍进入编辑，三点菜单五项均可见；复用新增使用新交易流程，保存模板和保存周期真实写入 Repository，菜单删除确认后实时刷新。新增交易选择三个月时验证生成三笔且全部继承所选状态；实际规则的未来月份全部为实际，预计规则的所有月份全部为预计。
- 集成测试：AI 网关在本地服务不可用时跳过，不影响离线测试通过。
- 外部 AI 提示词回归：验证提示词同时声明消费发生、现金收付、信用负债，明确信用卡还款不是消费、投资市值调整不是收入、未来 `actual` 是未来已确定、`planned` 单列预计，并兼容完整备份 JSON。

## 完成门禁

```powershell
flutter analyze
flutter test
flutter build windows --debug
```

发布前还需执行 Android release build、实体 Android 设备触控/返回键测试，以及导入真实 v1/v6 备份的人工回归。

本次变更已验证 Windows debug 构建及 Android ARM64 Debug APK 构建。Android Debug 变体必须验证包名为 `com.financecompass.app.debug`、桌面名称为“Finance Compass Debug”，并能与正式版并存且不共享本地数据。Android release 和实体设备完整回归仍是 Play Store 发布前门禁；升级 Flutter 工具链前，需确认应用与 `file_picker`、`file_saver`、`share_plus` 的 Kotlin 兼容性。

2026-07-17 预算/主题校准回归：`flutter test` 结果为 26 项通过、2 项按设计跳过（外部 AI 网关未启动、人工视觉截图用例默认关闭）；`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，仍保留既有 lint info 与未使用声明 warning。Android ARM64 Debug 以 `--no-track-widget-creation` 构建，保留 Debug 身份与开发签名，同时将测试包控制在 Google Drive 上传限制内。

2026-07-17 交易与账期回归：`flutter test` 结果为 32 项通过、2 项按设计跳过；新增 `credit_card_billing_test` 跨月/月末用例、`cash_flow_range_test`、`transaction_composer_edit_test`、`transactions_v2_navigation_test` 和 `dashboard_forecast_range_test`。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留项目既有 lint info 与未使用声明 warning。

2026-07-17 信用卡日期语义迁移回归：`flutter test` 结果为 33 项通过、2 项按设计跳过；数据库升级用例确认旧信用卡 `transaction_date` 改用 `record_date` 且现金交易不变，数据可携用例确认 v1/v2 归一化及 v3 编辑后发生日期往返保留。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 102 项既有 lint info/warning。

2026-07-17 交易状态与时间口径回归：`flutter test` 结果为 36 项通过、2 项按设计跳过；新增 EPF/退休账户未来实际与预计记录、信用卡未来记录隔离，以及现金流预测不重复累计的回归用例。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 102 项既有 lint info/warning。

2026-07-17 信用卡展示状态与投资市值入口回归：`flutter test` 结果为 39 项通过、2 项按设计跳过；信用卡已还清状态不会因还款日已过误报逾期，投资账户在 390×844 视口可打开锁定当前账户的市值更新表单，长账户名无溢出。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 101 项既有 lint info/warning。

2026-07-17 信用卡转账方向回归：`flutter test` 结果为 40 项通过、2 项按设计跳过；信用卡 A 转至信用卡 B 时，A 的账单增加且明细可见，B 只按还款减少负债。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 101 项既有 lint info/warning。

2026-07-17 交易批量删除回归：`flutter test` 结果为 42 项通过、2 项按设计跳过；长按可进入多选、点击追加第二笔并确认删除后列表实时刷新且账户余额恢复，包含失效 ID 的整批删除会完整回滚。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 101 项既有 lint info/warning。

2026-07-17 交易操作菜单与可选周期回归：`flutter test` 结果为 44 项通过、2 项按设计跳过；新增 `transaction_action_menu_test` 覆盖整行编辑、复用新增、模板/规则落库和单笔菜单删除，`transaction_composer_edit_test` 覆盖 1–12 个月选择中的三个月连续生成及实际/预计状态。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目现有 lint 总数为 104 项。390×844 菜单截图已与用户旧版截图同屏对照；Android ARM64 Debug 和 Windows x64 Release 均构建成功，`aapt` 确认包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `2015`。

2026-07-18 信用卡承诺负债与周期状态回归：`flutter test` 结果为 48 项通过、2 项按设计跳过；新增信用卡未来 `actual` 计入当前欠款/额度、未来 `planned` 排除、显式账单截止仍不读取未来交易，以及实际/预计周期规则在所有生成月份保持原状态的回归。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目现有 lint 总数仍为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `2016`。

2026-07-18 信用卡历史账单回归：`flutter test` 结果为 50 项通过、2 项按设计跳过；领域测试确认 25 日结算、14 日还款时，4 月 29 日消费进入 5 月账单并在 6 月 14 日还款，Widget 测试在 390×844 视口完成月份列表打开、往期选择、明细隔离和返回入口检查。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目既有 lint 总数为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `2017`。

2026-07-18 编辑删除与有符号金额回归：`flutter test` 结果为 55 项通过、2 项按设计跳过；Widget 测试覆盖编辑页取消/确认删除以及 `0.00`、`-25.50` 保存，Repository 测试覆盖零金额、负支出、负转账及删除后的双边余额恢复。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目既有 lint 总数仍为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、版本 `0.8.0-debug`、versionCode `18`。

2026-07-18 未来已确定账单与银行余额回归：`flutter test` 结果为 58 项通过、2 项按设计跳过；新增 Shopee PayLater 未来三期已发生账单、预计排除、未来月份详情，以及 UOB 消费/还款/退款后的结算日余额回归。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目既有 lint 总数仍为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、版本 `0.8.0-debug`、versionCode `19`。Android 构建继续提示 Flutter 将来会要求应用及插件迁移至 Built-in Kotlin，当前构建不受影响。

2026-07-18 Shopee PayLater 原始账单与 UOB 还款对账回归：`flutter test` 结果为 59 项通过、2 项按设计跳过；新增已还款账单保留原始金额、每月 1 日结算按前一日命名，以及单期 MYR 313.29 不受累计余额影响的领域回归。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目既有 lint 总数仍为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `20`。UOB 样本中的 MYR 238.38 Shopee 还款已按 7 月 1 日银行交易日核对；补齐 3 月 MYR 184.52 和 4 月 MYR 161.33 后，3–9 月账单逐期匹配，当前欠款与未来三期合计同为 MYR 870.07。SQLite 完整性检查为 `ok`，外键错误为 0；Android 构建仍仅提示未来 Built-in Kotlin 迁移要求。

2026-07-18 Lazada PayLater 数据对账：结算日校正为 9 日并保留 25 日还款；7 月四项含全额退款净额为 MYR 195.91。补齐 LiberNovo 1/12–12/12、重排两个 6 期分期并将全部已确定记录设为 `actual` 后，7–9 月各 MYR 195.91、10 月 MYR 195.97、11 月至 2027 年 5 月各 MYR 180.88；当前欠款与这些未还已确定账单合计均为 MYR 2,049.86。SQLite 完整性为 `ok`，外键错误为 0，Lazada 账户 `planned` 记录数为 0。

2026-07-18 UOB 已使用额度对账：银行口径由 6 月 25 日账单 MYR 5,346.29，加结算后消费 MYR 3,371.32，再减还款及退款 MYR 7,153.93，得到 MYR 1,563.68。删除银行不存在的第 7 笔 MYR 300 BTIPP 分期，以 MYR -984.49 校正不完整旧账本的期初余额，并重建物化余额后，账本重算与银行均为 MYR 1,563.68，差额为零；SQLite 完整性为 `ok`、外键错误为 0。`credit_card_billing_test.dart` 12 项通过，覆盖超额还款抵扣、下一结算日前未来已确定消费保留，以及缺少还款凭据的 PayLater 旧资料不被余额反推污染。全量测试 61 项通过、2 项按设计跳过；静态分析无编译错误，项目既有 lint 总数仍为 104 项。

2026-07-18 UOB 历史结单快照对账：银行 PDF/XLS 确认 2026 年 3 月 25 日、4 月 25 日、5 月 25 日和 6 月 25 日原始账单分别为 MYR 2,364.37、1,995.35、4,352.32、5,346.29。应用通过账户级 `app_meta` 快照优先展示这些权威值，避免后续还款 MYR 5,746.30 被误作 6 月原始账单；当前欠款仍为 MYR 1,563.68。写入前建立独立备份，SQLite 完整性为 `ok` 且外键错误为 0。定向账期测试 14 项通过；全量测试 61 项通过、2 项按设计跳过；静态分析无编译错误并保留 101 项既有 lint。Windows x64 Release build 22 构建并启动成功，原生界面已核对月份列表及 5 月历史详情金额。

2026-07-18 发布恢复包回归：`tool/export_release_data_test.dart` 从 SQLite 在线备份调用 Repository 生成完整 v3 JSON，并在写盘后重新解析校验全部必需集合；导出数量为账户 16、分类 29、预算 13、交易 672、投资快照 34、模板 7、周期规则 6。ARM64 Debug APK 的 `aapt` 结果为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2022` 和 `arm64-v8a`。本机 `G:\我的云端硬盘\Finance Compass APK` 与 Drive 云端元数据均确认 JSON 与 APK 大小分别为 371,284 和 84,956,046 bytes。

2026-07-18 交易“包含预计”口径回归：新增 390×844 Widget 测试，默认只显示 MYR 100 已发生支出，切换后保留已发生并加入 MYR 40 预计，顶部支出同步变为 MYR 140；原未来月份导航与编辑回归继续通过。全量测试 62 项通过、2 项按设计跳过；`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译错误，保留 104 项既有 lint。ARM64 Debug APK 核对包名 `com.financecompass.app.debug`、应用名 `Finance Compass Debug`、版本名 `0.8.0-debug`、versionCode `2023` 和架构 `arm64-v8a`。完整 v3 JSON 从 SQLite 在线备份导出并验证，APK 与 JSON 的 Drive 本地同步副本 SHA-256 均与工程产物一致。

2026-07-18 交易三口径与 Product Design 方案 2 回归：新增 390×844 Widget 测试，以现金支出 MYR 100、信用消费 MYR 300、还款 MYR 200、预计现金 MYR 40 和预计信用 MYR 50 分别验证消费发生 -MYR 400、现金收付 -MYR 300、当前已承诺 MYR 100，以及包含预计后 MYR 150；原“包含预计”和未来月份编辑回归继续通过。全量测试 63 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。390×844 实现截图与选定方案 2 合成同屏，筛选行经一次迭代后通过视觉门禁。SQLite 在线备份完整性为 `ok`、外键错误为 0；v3 JSON 验证为 16 个账户、29 个分类、13 个预算、672 笔交易、34 个快照、7 个模板、6 条周期规则。ARM64 Debug APK 核对包名 `com.financecompass.app.debug`、应用名 `Finance Compass Debug`、版本名 `0.8.0-debug`、versionCode `2024` 和架构 `arm64-v8a`；APK 与 JSON 的 Drive 本地同步副本 SHA-256 均与工程产物一致。

2026-07-19 外部 AI 提示词 v3 回归：新增 2 项提示词测试，验证消费发生、现金收付、信用负债三口径，信用卡还款与消费分离，投资调整不算收入，未来 `actual`/`settled` 标记为未来已确定、`planned` 单列预计，并兼容完整备份 JSON。全量测试 65 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。SQLite 在线备份完整性为 `ok`、外键错误为 0；v3 JSON 验证 16 个账户、29 个分类、13 个预算、672 笔交易、34 个快照、7 个模板和 6 条周期规则。ARM64 Debug APK 核对包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本名 `0.8.0-debug`、versionCode `2025` 和 `arm64-v8a`；APK 与 JSON 的 Drive 副本 SHA-256 均与工程产物一致。

2026-07-20 现金账户转账双边余额回归：新增 `cash_transfer_balance_test.dart` 4 项测试，分别覆盖 Repository 写入与重新加载、`TransactionMutations` 发布刷新后的 provider、新版 `TransactionComposerPage` 实际选择目标现金账户后保存并落库，以及账户总览中的 Grab → UOB One 实时刷新。MYR 250 从余额 MYR 1,000 的来源账户转至余额 MYR 100 的目标账户后，两边显示与存储余额分别为 MYR 750 和 MYR 350；定向测试全部通过。该结果说明标准“同币种、当月、已发生”路径可正确更新转入账户，尚未复现手机端报告的异常。

2026-07-20 快速模板排序与指定账户刷新回归：`quick_template_reorder_test.dart` 验证完整模板 ID 顺序会持久化为连续 `sortOrder`，重载后顺序不变；390×844 Widget 用例调用可重排列表把第 6 个模板拖到第 1 位，并确认新的前五顺序立即发布。现金转账用例同时扩展为账户总览中的 Grab → UOB One，MYR 250 转账后分别显示 MYR 750 与 MYR 350。两份定向测试共 6 项通过；全量测试 71 项通过、2 项按设计跳过，静态分析无编译错误并保留 104 项既有 lint。SQLite 在线备份完整性为 `ok`、外键错误为 0；v3 JSON 包含 16 个账户、29 个分类、13 个预算、672 笔交易、34 个快照、7 个模板和 6 条周期规则。ARM64 Debug APK 为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2026` 和 `arm64-v8a`，APK 与 JSON 的 Drive 本地同步副本哈希一致。

2026-07-20 Android 导出与恢复安全回归：移除会吞掉 Android 写入异常的 `file_saver`，所有 JSON/CSV 保存统一走 `file_picker.saveFile(bytes: ...)`。定向测试验证 0 KB 文件会被拒绝且原账户保留、缺失目标账户的转账备份会在替换前失败且原数据库不变、合法 v3 备份恢复后 `HomeScreen` 的六个主页面可共同构建而不出现黑屏；5 项定向测试通过。全量测试 74 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。正式导入在同一事务内追加 SQLite 完整性检查。发布工具把 371,284-byte v3 JSON 真实恢复到空数据库，核对 16 个账户、29 个类别、13 个预算、672 笔交易、34 个快照、7 个模板和 6 条周期规则；SQLite 快照 `quick_check=ok`、外键错误为 0。build 27 ARM64 Debug APK 核对 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2027` 与 `arm64-v8a`，APK 和 JSON 的 Drive 副本 SHA-256 与工程产物一致。

2026-07-20 同币种转账零转入金额回归：新增领域测试确认旧 `toAmount=0` 仍按唯一来源金额入账，Widget 测试确认新版表单保存 `toAmount=NULL`，数据可携测试确认导入会补回目标余额并归一交易。用户提供的 376,268-byte v3 JSON 已真实导入，17 个账户、29 个分类、13 个预算、681 笔交易全部恢复，3 笔异常转账完成修复。全量测试 76 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。build 28 ARM64 Debug APK 为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2028` 和 `arm64-v8a`；修复 JSON 为 376,326 bytes，两项 Drive 副本 SHA-256 均与工程产物一致。

2026-07-20 新版跨币种转账回归：390×844 Widget 用例确认 MYR 250 转入 MYR 时显示只读 MYR 250.00 并保存 `toAmount=NULL`；转入 TWD 时按 1 MYR = 7.1429 TWD 自动填入 TWD 1,785.71，用户覆盖为 TWD 1,800 后目标账户增加 1,800。全量测试 77 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。`validate_import_data_test.dart` 将可信 v3 备份真实恢复并重新导出，核对 17 个账户、29 个类别、13 个预算和 683 笔交易，未发现需要修复的旧式同币转账。build 29 ARM64 Debug APK 经 `aapt` 核对为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2029` 和 `arm64-v8a`；APK 为 84,689,324 bytes、JSON 为 377,347 bytes，复制到本地 Google Drive 后的 SHA-256 分别为 `90B2A37375C95FBCB1CECEB031B44230C0F451007A6A1C46C4820BDBFE62F3E0` 与 `6A7B24964E27AD48A5C3AB7824F2563F6509A8C32DD271C14A62954BCF96FAD7`，均与工程源产物一致。

## UI 质量

基准视口宽度为 390 逻辑像素；本次原生 Windows 对照使用精确 390 像素客户区宽度和 713 像素可见高度，长页面通过滚动覆盖参考图完整内容。预算与外观页另使用 390×844 widget 截图，分别与 `supplemental-budget-overview.png` 和 `27-appearance.png` 合成同屏比较图。检查六个底部入口、无横向/纵向 RenderFlex 溢出、预算占比口径、实色/斜纹状态、主题拖动预览、交易筛选、账户详情、表单主按钮、信用卡日期、闪电/加号浮动按钮及深色对比度。视觉对照记录见项目根目录 `design-qa.md`，页面映射见 [UI 参考基线](UI_REFERENCE.md)。Flutter widget 截图环境缺少中文字体时会显示方框字形；该限制只影响测试截图文字外观，不影响 Android 系统字体渲染或布局断言。

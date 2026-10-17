# Android 通知记账（0.11.0-dev+49）

本功能为开发版。APK 编译与自动化测试不等于银行实机验收；没有真实银行通知样本时，不承诺任何银行或钱包的识别率。公开稳定版仍为 v0.10.1。

## 手机安装

[下载 build 49 APK](https://github.com/lawpowen/finance-compass-app/releases/download/v0.11.0-dev.49/FinanceCompass-Android-v0.11.0-dev-build49-debug.apk)，或打开 [GitHub 预发布页](https://github.com/lawpowen/finance-compass-app/releases/tag/v0.11.0-dev.49)，选择 Assets 中的 APK；Source code 不能直接安装。安装后名称为 Finance Compass Debug，包名 com.financecompass.app.debug，与正式版并存且数据隔离。APK 使用 Android Debug 签名，不是正式版覆盖升级。

### 安装拦截排查

Google 已于 2026-04-14 公布在马来西亚推出增强防诈骗保护；浏览器、消息应用或文件管理器下载的 APK 若声明通知读取等敏感能力，可能被拦截。build 49 的实际 APK 声明了 `PaymentNotificationListener` 及 `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE`。因此，该限制适用于本测试版的分发评估；仍需根据手机完整提示确定具体原因，不能仅凭“无法安装”认定。来源：[Google Malaysia 官方公告](https://blog.google/intl/en-my/company-news/technology/google-launches-enhanced-protection-in-google/)、[Google Play Protect 开发者指南](https://developers.google.com/android/play-protect/warning-dev-guidance?hl=en)（2026-10-17 核对）。

| 手机提示 | 处理方式 |
|---|---|
| App Scan Recommended / Send App for Security Check | 按系统提示选择扫描，等待扫描结果；不承诺扫描后必然可安装。 |
| App blocked to protect your device，并提到 sensitive data / financial fraud | 核对通知读取用途、最小权限和用户同意，再按 Google 指南评估申诉；改文件名或改为 Release 签名不能作为已验证的解决方案。 |
| Harmful App Blocked | 按具体检测原因检查应用及依赖，不能直接归为普通未知应用；需要保留完整提示。 |

上述分类及处理依据为 [Google Play Protect 开发者指南](https://developers.google.com/android/play-protect/warning-dev-guidance?hl=en)。排查期间保持 Play Protect 开启，不以关闭全局防护作为标准安装步骤。APK 签名和 SHA-256 只用于核对来源与完整性，不代表 Google 的安全审核结果。删除通知服务会使自动接收功能失效，不能把删除后可安装的包称为已修复的通知记账版本。

若确认需要申诉，可使用 [Google 官方表单](https://support.google.com/googleplay/android-developer/contact/protectappeals)。build 49 包名为 `com.financecompass.app.debug`，APK SHA-256 为 `624d0b363fa67a28c50184e3ca479046bed083c966021d2fd2270cec87597d19`，下载地址见上文。表单还要求联系邮箱、说明以及 VirusTotal 已上传文件的哈希；当前未提交申诉或向 VirusTotal 上传。本项目尚未建立 Google Play 测试渠道，也未获得解除拦截的验证结果。

## 使用流程

1. 在 Android“设置 → 通知记账 → 来源设置”绑定来源应用、账本账户及通知中的独有账户片段（例如 `Card: **1234`）。没有通知样本时可选择“仅收集到待确认”，账户片段可留空；本页列出的 10 家银行及 TNG eWallet 固定使用此模式。多个账户分别绑定；不要用常见金额或“Card”等通用词作为识别片段。
2. 打开系统通知读取授权，再开启“自动接收与记账”。授权前通知不补读。关闭开关后停止接收；已经进入队列的通知转待确认。移除最后一条绑定同时关闭接收。
3. 明确的交易进入“已处理”；疑问交易进入“待确认”，显示原因与原文，可核对金额、账户、类型、日期后保存一笔实际交易，或忽略。退款可人工确认为负支出，转账/还款需人工选择两端账户。
4. “已处理”支持撤销，删除对应交易并反向恢复余额，同时保留防重记录。若交易被手动编辑，撤销作用于其当前版本；普通交易页仍可修改自动生成的交易。
5. 完整 JSON 导出包含通知正文和防重记录，请保护备份。更换设备后重新设置来源与授权。导入历史备份、清空账本或降级前，先关闭通知接收并处理队列，避免旧队列与恢复后的账本混用。

## 马来西亚 10 家银行待确认接入

首批范围如下，不是银行资产或用户量排名。当前 App 名称和精确 Android 包名来自银行官网及 Google Play 开发者页面，完整来源、授权通知区别与退役版本说明见 [银行通知适配调查](MALAYSIA_BANK_NOTIFICATION_RESEARCH.md)。**已兼容来源绑定、接收及人工确认；尚未验证银行专用自动入账模板，也未完成真机验收。**

| 银行 | 当前接入 App |
| --- | --- |
| Maybank | MAE by Maybank2u |
| CIMB | CIMB OCTO MY |
| Public Bank | MyPB by Public Bank |
| RHB | RHB Mobile Banking |
| Hong Leong Bank | HLB Connect Mobile Banking App |
| AmBank | AmOnline |
| Bank Islam | BIMB Mobile |
| Bank Rakyat | iRakyat Mobile Banking |
| BSN | myBSN |
| Affin Bank | AffinAlwaysX |

来源设置可展开“银行与钱包接入范围”查看目录；绑定选择器只列出本机已安装的应用，将目录中的应用排在前面并显示统一名称。没有安装相应 App 时，目录不会代替实际安装列表，也不会自动创建来源绑定。仍需用户选择账本账户、授予通知读取权限并打开接收。

目录中的来源固定开启“仅收集到待确认”，允许账户片段为空；填写片段后仍按原文匹配。通知只预填唯一金额和币种，不猜测收入/支出、商户、交易编号或转账两端。确认前账本与余额不变。授权请求、失败、退款、充值、还款、营销和多金额消息也不会自动入账；不需要的内容可忽略。常见 OTP/TAC 验证码继续由接收层过滤，授权请求不会触发银行操作。

新策略也作用于以前保存的这些包名绑定，无论 reviewOnly 缺省或为 false，均不能进入通用自动规则。已处理历史不改写，待确认记录不自动重解析。多个账户同时匹配时不设候选账户；确认表单仍使用既有默认账户，用户必须核对。相似名称、包名前缀、其他国家或退役包名不属于本目录；它们仍按其他来源的现有规则处理。来源身份核实不等于真实通知模板或所有设备兼容性已验证。

## TNG eWallet 待确认接入

来源精确匹配 Google Play 官方包名 `my.com.tngdigital.ewallet`。已找到官方工资入账示意，但没有足够证据证明消费者 Android 通知的完整字段、账户标识和交易编号，因此没有启用 TNG 自动入账模板。证据、官方链接与调查限制见 [TNG 通知样本调查](TNG_NOTIFICATION_RESEARCH.md)。

在已安装的来源列表选择 TNG eWallet 后，“仅收集到待确认”固定开启，账户片段可不填写。授权并开启接收后，新通知进入待确认；唯一来源绑定会预选账户，多个匹配则不设置候选账户；确认表单仍沿用既有默认账户，必须人工核对。其他应用也可主动选择仅收集模式。可选账户片段一旦填写，仍必须匹配正文；关闭仅收集模式时须填写至少 4 字符的片段。

官方 Payroll Handbook 的收款示意句式可预填 MYR 金额、收入方向及付款方，但仅是候选值；用户必须核对实际业务（例如是否自有账户转入）后确认。付款、充值、TapSecure 待授权、退款、营销或多金额内容均不自动改余额；营销通知也可能进入列表，可忽略。即使旧配置没有 reviewOnly 或正文碰巧匹配通用成功句式，TNG 来源仍待确认。未知格式只尝试提取唯一币种金额，不从正文推测账户或类型。

开启前的通知不补读，不会因为加入来源就生成历史交易。样本原文留在本机且进入完整 JSON 备份；没有新增上传或联网解析。

## 自动入账契约

目录外的其他来源当前支持下列严格英文句式；上述 10 家银行及 TNG eWallet 不进入这组自动规则。示例是合成测试数据，不代表已适配任何银行：

```text
Payment of MYR 12.34 to SHOP was successful. Ref: ABC12345 Card: **1234
Paid RM 12.34 to SHOP successfully. Reference: ABC12345 Card: **1234
Received MYR 12.34 from COMPANY successfully. Transaction ID: ABC12345 Account: **1234
```

支持 MYR/RM、USD、CNY、TWD；金额为正数且含两位小数，允许千位逗号。标题出现失败/待处理等状态时不会自动入账。正文必须完整匹配句式，包含唯一金额、明确成功状态、6–64 字符交易编号。账户片段按原文区分大小写匹配，必须只命中一条绑定，且账户有效、币种一致。自动入账限现金、储蓄、电子钱包与信用卡账户。类别不猜测，保存为空，可在交易页补充。

通知送达时间暂用作发生时间，不推断正文日期；延迟超过一天的通知待确认。超过 4096 字符的正文标记截断并待确认。失败、待处理、退款、转账、还款、预授权、奖励等不能自动入账。验证码在 Android 接收层过滤，不存入队列。未知语言/模板、金额不唯一、币种不一致、无账户匹配、多个匹配、配置变化均待确认。不调用大模型，不联网解析。

防重分三层：完全相同事件 ID 幂等返回；已有同一通知的交易但凭据缺失时待确认；相同通知 key 更新或相同来源交易编号待确认；已有实际交易在通知时间前后 10 分钟内同金额同币种，也待确认。后两类不静默删除，可能只是同金额的不同消费。跨来源没有可靠统一交易 ID，依赖疑似重复提示与人工核对。

## 模块与运行流程

```mermaid
flowchart TD
  N[Android 通知监听] --> F[来源白名单与验证码过滤]
  F --> Q[Android 私有 SQLite 队列]
  Q --> E[共享 FlutterEngine / MethodChannel]
  E --> P[本地解析与账户匹配]
  P --> T[Drift 单一事务]
  T --> A[明确: 交易与余额]
  T --> R[不确定: 待确认记录]
  A --> K[提交后 ACK 队列]
  R --> K
  K --> U[刷新 Repository 与页面]
```

- `android/app/src/main/kotlin/com/financecompass/app/NotificationCapture.kt`：`PaymentNotificationListener`、`NotificationQueue`、`FinanceEngine`。Activity 与服务复用同一 FlutterEngine，避免两个 Dart 引擎持有独立账本连接。后台收到通知可启动引擎执行相同主入口，不自动打开 Activity。
- `lib/src/core/notifications/notification_sources.dart`：集中维护 NotificationSourceProfile、malaysiaBankNotificationSources（10 家银行）、reviewOnlyNotificationSources（银行 + TNG）及 notificationSourceFor 精确查询。纯静态目录，无存储或联网依赖；未知包名返回 null，不按显示名称或前缀推断身份。
- `lib/src/core/notifications/notification_parser.dart`：纯解析器，接收可选 sourcePackage，返回候选字段与人工确认原因。目录中的包名强制待确认，TNG 官方工资示意句式仅用于候选字段预填；目录外继续使用既有严格通用句式。
- `notification_bookkeeper.dart`：接收、防重、确认、忽略、撤销；复用 AppDatabase 入账和反向余额操作，不另算一套余额。
- `notification_bridge.dart`：串行消费、提交后 ACK、失败后 30 秒及恢复前台重试、刷新 Riverpod。每个事件重新读取当前配置与系统授权，并在该事件内使用独立快照，页面并发刷新不会替换正在处理事件的账户；已开始处理的事件按该次快照完成，设置变更影响后续读取。接收后配置版本变化或授权被撤销则待确认。连接握手失败也进入重试；消费与刷新期间收到 available 会补做一次队列读取。
- `lib/src/features/settings/notification_bookkeeping_page.dart`：来源设置、待确认、已处理。确认复用 TransactionFormDialog 的 `notificationDraft` 模式，保留通知日期并禁止生成多个月记录。

## 数据、接口与失败行为

账本 schema 仍为 9，不新增财务表，不改写已有交易。每条通知存在 `app_meta` 的 `notification_record_v1_<eventId>` 中，JSON 包含 id、key、package、postedAt（Unix 毫秒）、title、text、configVersion、configurationChanged、state、reason、候选金额/币种/类型/商户/编号/账户与 transactionId。

状态：接收 → posted 或 pending；pending → confirmed 或 ignored；posted/confirmed → undone。已处理状态不自动回到 pending。交易 ID 固定为 `notification_<eventId>`。通知记录与交易/余额同事务提交，ACK 失败重试不会再次扣款，撤销保留 tombstone。人工确认再次验证有效账户、币种、非零有限金额、实际状态、转账目标及金额；重复确认报错，不重复写入。

Android 队列 `notification_capture.sqlite` 的 events 表为 `id TEXT PRIMARY KEY, payload TEXT NOT NULL`。SHA-256 ID 基于通知 key、postTime、标题与完整正文。每批最多 50 条，成功后逐条 ACK；原生队列不包含在 JSON 备份。配置保存在私有 SharedPreferences `notification_capture/config`，包括 enabled、bindings、递增 version；每条绑定包含 package、label、accountId、accountName、marker 和可选布尔 reviewOnly（缺省 false），不进入账本 JSON，跨设备不自动启用。捕获保存失败尝试保存 captureFailed 标记，在页面提示核对账单；日志不输出通知正文。

连接握手、消费队列、Repository 刷新、记录列表读取均纳入同一恢复流程：失败显示状态并在 30 秒后重试，也可手动刷新或恢复前台触发。未提交/未 ACK 的事件保留在原生队列；已 ACK 但 Repository 刷新失败时，保留本进程待刷新标记，下次重试只需重载账本，不重复入账。桥接对象销毁后不再通知页面或继续消费，已提交但未 ACK 的事件由下一次连接幂等恢复。

MethodChannel：`finance_compass/notification_bookkeeping`。Dart 调用 ready、config、configure(JSON 字符串)、permission、captureFailed、openPermission、apps、pending、ack(eventId)；Android 发 available 唤醒消费。apps 只查询可启动应用，不请求 QUERY_ALL_PACKAGES。服务要求 BIND_NOTIFICATION_LISTENER_SERVICE 系统绑定权限；用户必须单独开启通知读取，普通发送通知权限不能替代它。

记录默认持续保留，暂无自动保留期或批量清除正文入口。完整 JSON 备份包含记录；AI 摘要不含通知原文，已记账交易仍参与现有财务分析。清除应用数据/卸载会丢失私有队列与设置。旧版不会显示新记录；回滚前关闭通知权限，优先用升级前 JSON 恢复。Debug 使用 `.debug` ID，与正式版数据隔离，不需要卸载正式版。

## 验证与限制

自动化覆盖严格句式、拒绝不确定内容、原子余额、防重/更新、忽略、撤销、回滚、ACK 重试、连接握手与 30 秒自动重试、逐条撤权检查、刷新失败恢复、刷新期间通知唤醒、销毁时队列保留、并发设置刷新下账户隔离、人工确认、隐私导出、暂停，以及 375px 小屏、横屏、平板和两倍字号。最终构建与测试结果见[变更记录](CHANGELOG.md)。

真机验收尚未完成：授权/撤权、进程回收后新通知、锁屏隐藏正文、银行模板、厂商省电策略、后台到前台引擎复用、重启恢复和屏幕阅读器。系统强制停止、后台限制或来源不发通知都可能漏记，不保证与账单完整一致。新增银行专用自动模板必须先取得脱敏成功、失败、重复、退款、多账户样本，与真实交易核对并添加回归测试；仅确认官方包名时只能接入待确认。

## GitHub 回滚基线

修改前快照分支 `codex/backup-before-notification-2026-10-17`，提交 `857bc56ba132fd8341af67d2cedd7ee62ec7a7ba`；稳定标签 v0.10.1 保留。快照含修改前源码与既有目录清理记录，不含被忽略的财务备份和签名密钥。

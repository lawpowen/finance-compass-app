# 马来西亚 10 家银行 Android 通知适配调查

检索日期：**2026-10-17**（Asia/Kuala_Lumpur）。范围：Maybank、CIMB、Public Bank、RHB、Hong Leong、AmBank、Bank Islam、Bank Rakyat、BSN、Affin 的马来西亚个人银行 App。此名单是本次产品适配范围，**不是按资产、用户数或市场份额编制的十大银行排名**；不含企业银行 App、其他国家版本或证券交易 App。

## 结论

**10 家当前 Android 应用身份均已核实，但没有取得足以直接启用自动入账的完整已完成交易通知模板。** 以下银行官网能证明交易提醒、授权通知或应用内消息的存在，Google Play 开发者页面能核实名称与包名；两类证据都不能代替真实 Android 通知字段和交易状态验证。建议先按精确包名接收、绑定账户并进入待确认。本文记录证据与建议，当前实际功能以 [Android 通知记账说明](ANDROID_NOTIFICATION_BOOKKEEPING.md) 为准。

## 已知客观事实

### 当前 App 身份

包名取自下表 Google Play 官方开发者应用页面的 `id` 参数。检索采用银行网站及 Google Play 开发者介绍，不采用商店用户评论、论坛、个人博客或社交媒体内容。

| 银行 | 当前个人银行 App | 已核实 Android 包名 | 银行官方入口 | Google Play |
| --- | --- | --- | --- | --- |
| Maybank | MAE by Maybank2u | `com.maybank2u.life` | [MAE](https://www.maybank2u.com.my/maybank2u/malaysia/en/personal/services/digital_banking/mae_by_maybank2u.page) | [Maybank 开发者应用](https://play.google.com/store/apps/details?id=com.maybank2u.life) |
| CIMB | CIMB OCTO MY | `com.cimb.cimbocto` | [CIMB OCTO App](https://www.cimb.com.my/en/personal/digital-services/cimb-octo-app.html) | [CIMB 开发者应用](https://play.google.com/store/apps/details?id=com.cimb.cimbocto) |
| Public Bank | MyPB by Public Bank | `com.pbb.mypb` | [MyPB App](https://www.pbebank.com/en/digital-banking/mobile-banking/mypb-app/) | [Public Bank 开发者应用](https://play.google.com/store/apps/details?id=com.pbb.mypb) |
| RHB | RHB Mobile Banking | `com.rhbgroup.rhbmobilebanking` | [RHB Mobile Banking](https://www.rhbgroup.com/new-RHB-mobile-banking/) | [RHB 开发者应用](https://play.google.com/store/apps/details?id=com.rhbgroup.rhbmobilebanking) |
| Hong Leong Bank | HLB Connect Mobile Banking App | `my.com.hongleongconnect.mobileconnect` | [HLB Connect](https://www.hlb.com.my/en/personal-banking/hlb-connect.html) | [Hong Leong Bank 开发者应用](https://play.google.com/store/apps/details?id=my.com.hongleongconnect.mobileconnect) |
| AmBank | AmOnline | `com.ambank.ambankonline` | [About AmOnline](https://www.ambank.com.my/online-banking/faq/general) | [AmBank 开发者应用](https://play.google.com/store/apps/details?id=com.ambank.ambankonline) |
| Bank Islam | BIMB Mobile | `com.bankislam.bimbmobile` | [BIMB Mobile](https://www.bimb.com/bimb-mobile/) | [Bank Islam 开发者应用](https://play.google.com/store/apps/details?id=com.bankislam.bimbmobile) |
| Bank Rakyat | iRakyat Mobile Banking | `com.irakyatmob.bkrm` | [Bank Rakyat Apps](https://www.bankrakyat.com.my/portal-main/article/about-app) | [Bank Kerjasama Rakyat Malaysia 开发者应用](https://play.google.com/store/apps/details?id=com.irakyatmob.bkrm) |
| Bank Simpanan Nasional（BSN） | myBSN | `com.bsn.mybsn` | [myBSN Mobile App](https://www.bsn.com.my/page/myBSNMobileApp) | [BSN 开发者应用](https://play.google.com/store/apps/details?id=com.bsn.mybsn) |
| Affin Bank | AffinAlwaysX | `com.affin.mobilebanking` | [AffinAlwaysX](https://www.affinalways.com/en/AffinAlwaysX) | [Affin Bank 开发者应用](https://play.google.com/store/apps/details?id=com.affin.mobilebanking) |

### 通知证据与适配边界

**证据等级**：A＝已核实应用身份；B＝官方说明通知类别或投递渠道；C＝完整 Android 已完成交易载荷，足以核实金额、币种、方向、账户与唯一交易编号。本次全部达到 A，已有 B 类证据，**没有任何一家达到 C**。下表中的“未取得”只描述本次调查，不表示银行不发送该类通知。

| 银行 | 已核实的官方通知行为与来源 | 自动记账所缺证据 |
| --- | --- | --- |
| Maybank | [MAE 产品页](https://www.maybank2u.com.my/maybank2u/malaysia/en/personal/services/digital_banking/mae_by_maybank2u.page)说明启用推送可接收入账和出账提醒；[Secure2u FAQ](https://www.maybank2u.com.my/maybank2u/malaysia/en/personal/frequent_queries/secure2u_tac/secure-differences.page)区分待批准 Secure Verification、Secure TAC、Push Notification TAC。 | 未取得完成交易的 Android 标题、正文和编号格式；授权请求或 TAC 推送不能当作扣款。 |
| CIMB | [入账通知公告](https://www.cimb.com.my/en/personal/important-notices/2026/notice-inward-credit-notification.html)与 [FAQ](https://www.cimb.com.my/content/dam/cimb/personal/documents/important-notices/2026/casa-inward-notification/faq-casa-inward-notification.pdf)确认 OCTO 入账通知；[SecureTAC 公告](https://www.cimb.com.my/en/personal/important-notices/2026/important-securetac-approval-required-for-selected-online-transactions.html)说明授权推送后仍需批准或拒绝。 | 未取得完整入账/出账载荷；不能把 SecureTAC 交易请求或应用内交易历史当作完成通知。 |
| Public Bank | [MyPB Google Play 开发者说明](https://play.google.com/store/apps/details?id=com.pbb.mypb)说明推送用于接收通知及交易批准；[PB SecureSign FAQ](https://www.pbebank.com/en/digital-banking/mobile-banking/pb-securesign/)明确批准时限与 SecurePAC 用途；[官方用卡提示](https://www.pbebank.com/online-security-en/announcement/keep-your-card-safe-while-travelling/)提及交易的 in-app notification / SMS alert。 | 未取得完整 MyPB Android 完成交易文本，不能把 in-app 内容或 SMS 格式直接当作系统推送。 |
| RHB | [DuitNow Request FAQ](https://www.rhbgroup.com/others/faq/payments-and-transfer/duitnow-request/index.html)说明收款请求及已付款都会通过 push/inbox 提醒；[TCOP FAQ](https://www.rhbgroup.com/others/faq/payments-and-transfer/tcop/index.html)区分待批准、成功与拒绝；[Secure Plus FAQ](https://www.rhbgroup.com/others/faq/registration-and-login/secure-plus/index.html)说明授权请求。 | 同一来源含请求、失败、成功和安全通知，未取得各状态完整载荷及关联编号，不能按金额直接入账。 |
| Hong Leong Bank | [HLB Connect FAQ](https://www.hlb.com.my/en/connect/faq-en.html/)说明 Mobile Alerts、交易通知收件箱、通知语言设置及 AppAuthorise；[信用卡提醒页](https://www.hlb.com.my/en/personal-banking/credit-cards/credit-card-services/consumer-services/sms-transaction-alert.html)说明 App/SMS 通知及门槛。 | 未取得英语、马来语、中文的完整系统通知模板；收件箱和 PDF 收据不是 Android 通知载荷。 |
| AmBank | [Notifications & Inbox FAQ](https://www.ambank.com.my/online-banking/faq/general/manage-settings/notifications---inbox)明确交易完成后发成功通知，并区分促销与 AmSecure 请求；[AmSecure FAQ](https://www.ambank.com.my/online-banking/faq/general/security/amsecure)定义交易授权。 | 未取得成功推送标题、正文、账户片段和交易编号；“Authorise”请求不能表示款项已发生。 |
| Bank Islam | [BIMB Mobile Lite FAQ](https://www.bimb.com/lite/)说明成功交易的确认推送及 Inbox/交易历史；[BIMB Secure](https://www.bimb.com/bimb-secure/)说明授权后还需检查完成状态。 | 未取得完整 Android 载荷，也未证明 Lite、一般账户和各交易类型共享同一格式。 |
| Bank Rakyat | [iRakyat 条款](https://www.irakyat.com.my/portal-main/article/terms-conditions)把推送类别分为交易认证、事后交易提醒、安全提醒、维护、促销等，并说明 iSecure 批准/拒绝。 | 未取得完整事后交易推送模板；同一包名不代表每条消息都是交易。 |
| BSN | [myBSN 产品页](https://www.bsn.com.my/page/myBSNMobileApp)确认 DuitNow 入账和出账推送；[BSNSecure](https://www.bsn.com.my/page/BSNSecure)说明批准/拒绝；[myBSN FAQ](https://www.bsn.com.my/cms/upload/pdf/customer_care/mobileapp/faq_en.pdf)明确未批准时不处理交易、不扣款。 | 未取得成功推送原文；BSNSecure 请求与已付款提醒必须分开，不能根据“Complete your transaction”等操作说明造模板。 |
| Affin Bank | [AffinAlwaysX 产品页](https://www.affinalways.com/en/AffinAlwaysX)说明交易及账户活动推送；[AffinSecure](https://www.affinalways.com/en/affin-secure)明确推送用于打开授权并批准/拒绝，最终状态在银行端查询。 | 未取得 AffinAlwaysX 完成交易载荷；AffinSecure 授权教学截图不构成已完成交易样本。 |

### 迁移及旧资料限制

| 项目 | 可核实变更与处理 |
| --- | --- |
| Maybank2u MY → MAE | 官方公告宣布 Maybank2u MY 于 **2024-08-28** 停用。本次采用 MAE；不因旧资料把 Maybank2u MY 加入当前支持名单。[Maybank 官方公告](https://www.maybank2u.com.my/maybank2u/malaysia/en/personal/announcements/2024/august/m2u-my-app-discontinued-soon-bm.page) |
| CIMB Clicks App → OCTO | 官方 FAQ 记录旧 Clicks App 于 **2024-06-11** 从官方商店移除；当前官方入口使用 OCTO。该证据只说明商店移除，不据此推断全部旧安装的最终停服日；Clicks Web 与旧 App 需区分。[CIMB 官方 FAQ](https://www.cimb.com.my/en/personal/help-support/faq/mobile-banking/the-new-cimb-clicks-app/removal-of-cimb-clicks-app-from-the-official-app-store/when-will-the-cimb-clicks-app-be-removed.html) |
| PB engage MY → MyPB | 官方公告说明旧 App 于 **2025 年 6 月**退役，并引导迁移 MyPB。[Public Bank 官方公告](https://www.pbebank.com/en/announcements/pb-engage-my-is-sunsetting/) |
| GO by Bank Islam → BIMB Mobile | 官方公告确认旧 App 于 **2025-06-28**退役。[Bank Islam 官方公告](https://www.bimb.com/decommissioning-of-go-by-bank-islam-and-www-bankislam-biz/) |
| BSNSecure 独立 App → myBSN | 官方公告说明独立 App 于 **2024-06-07**停止访问，安全功能迁入 myBSN。本次绑定 `com.bsn.mybsn`。[BSN 官方公告](https://www.bsn.com.my/page/download-mybsn-mobile-app) |
| HLB 与 Affin 的旧名称 | HLB 历史资料中的 `com.konylabs.HongLeongConnect` 不属于本次核实的当前包名；以本表当前 Google Play 为准。Affin 当前商店名称为 **AffinAlwaysX**，保留 `com.affin.mobilebanking`；不要把独立 AffinSecure 当作当前零售银行来源。[HLB 历史官方资料](https://www.hlisb.com.my/content/dam/hlb/my/images/Promotions/connect-mobile-prepaid-reload-campaign/hlb-connect-mobile-prepaid-reload-tnc.pdf)、[Affin 当前商店页](https://play.google.com/store/apps/details?id=com.affin.mobilebanking) |
| CIMB 入账通知日期存在资料差异 | [早期公告 PDF](https://www.cimb.com.my/content/dam/cimb/personal/documents/important-notices/2026/casa-inward-notification/notice-of-casa-inward-notification.pdf)曾写 **2026-05-23**；[当前网页](https://www.cimb.com.my/en/personal/important-notices/2026/notice-inward-credit-notification.html)及当前 FAQ 首页写 **2026-06-06**，部分搜索摘要仍保留旧文字。只用这些资料确认通知功能存在，不用日期决定解析行为。 |

## 基于事实的适配建议

1. **先实现来源兼容和人工确认。** 精确匹配上述包名，允许用户选择已有账户；缺少账户识别样本时可留空。不得用名称包含 bank、包名前缀或相似包名扩大来源。多账户绑定或多金额继续保留歧义。
2. **10 家均保持待确认策略。** 可将唯一、合理的金额与币种用于草稿，但未验证交易方向、资金两端、唯一编号和完成状态前不改变账户余额。入账可能是自有账户转账，不能一概记收入；银行卡还款、充值、退款、冲正也不能按普通消费处理。
3. **明确排除授权和非交易语义。** Secure2u、SecureTAC、PB SecureSign、SecurePAC、Secure Plus、AppAuthorise、AmSecure、BIMB Secure、iSecure、BSNSecure、AffinSecure 均与授权有关；必须结合语句和状态处理。验证码遵循接收层过滤，禁止从通知触发银行授权。
4. **以真实样本升级模板。** 后续需脱敏保留 App 版本、语言、包名、通知标题、正文/扩展正文、通知 key、投递/更新时间，并与银行交易历史核对；覆盖成功、失败、授权、重复、合并、退款、转账和多币种。不得把应用内收据、网页示例或测试合成文本标记为真实 Android 样本。
5. **把验证能力与限制写进验收结果。** 包名与待确认路由可用合成事件测试；这种测试只验证防误入账、账户绑定、解析边界和幂等性，不能证明银行实际投递格式、监听可见性或真机兼容。未接设备时明确标注未完成真机验收。

## 维护与下一轮证据

本轮未登录任何银行账户、未执行付款、未采集用户真实通知，也未验证银行的每种语言/版本、Android 隐私隐藏、合并与重复更新行为。官方功能描述只支持类别判断；**自动入账模板仍待验证**。研究检索包含 app、push notification、transaction alert、inward credit、SecureTAC、SecureSign、AppAuthorise 和迁移公告；未把搜索不到解释为功能不存在。

后续维护者新增银行或改变自动规则时，须重新核实官方 App 身份、记录脱敏模板来源，并同步 [通知模块设计](ANDROID_NOTIFICATION_BOOKKEEPING.md)、[测试说明](TESTING_AND_QUALITY.md)与 [变更记录](CHANGELOG.md)。TNG 的独立证据见 [TNG 通知调查](TNG_NOTIFICATION_RESEARCH.md)。

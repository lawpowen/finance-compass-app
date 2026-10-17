# TNG eWallet 通知样本调查

检索日期：**2026-10-17**（Asia/Kuala_Lumpur）。范围：消费者 Android 付款、收款通知；仅采用 TNG 官方网站、帮助中心、官方 PDF 与 Google Play 开发者页面。本文记录证据与适配建议，不代表任何规则已实现或通过真机验收；当前实现参见 [Android 通知记账](ANDROID_NOTIFICATION_BOOKKEEPING.md)。

## 结论

**未找到足以直接启用消费者 Android 付款自动入账的可靠完整通知模板。** 官方资料能确认部分交易会发送通知，也能找到一条工资收款示意文字，但没有同时验证 Android 的通知标题、正文、账户标识、交易唯一编号及重复更新行为。缺少模板不等于 TNG 不发送付款通知。

**可以确认 Android 应用包名为 `my.com.tngdigital.ewallet`。** Google Play 页面显示应用为 Touch 'n Go eWallet，开发者为 TNG Digital Sdn Bhd；包名来自该官方应用页面的 `id` 参数。来源：[Google Play：Touch 'n Go eWallet](https://play.google.com/store/apps/details?id=my.com.tngdigital.ewallet)。

## 已知客观事实

### 最接近消费者收款原文的官方示例

官方 **TNG eWallet Payroll Handbook（2025 年 6 月版）PDF 第 11 页**，章节为 How to Pay Salary via Single Transfer，步骤 6 的示例文字为：

> You have received payment from XYZ Sdn Bhd : RM1,700.00

手册说明，工资成功入账后员工会收到 TNG eWallet 通知。这是官方教学示意，可用于人工核对收款文字和带千位分隔符的 RM 金额。资料没有声明这是 Android `NotificationListenerService` 返回的 `EXTRA_TITLE` / `EXTRA_TEXT` / `EXTRA_BIG_TEXT`，示例也没有交易编号或账户片段。因此**不能把此示例升级为已验证的 Android 自动入账模板**。来源：[TNG 官方 Payroll Handbook，第 11 页](https://www.touchngo.com.my/assets/pdf/payroll-handbook/TNG_eWallet_Payroll_Handbook.pdf#page=11)。

较新的官方外籍员工工资指南（文件标题为 Payroll Handbook Nov2025）的检索结果同样展示 TNG 首页收款横幅；该 PDF 直接打开时超过检索工具的文件大小限制，未完成逐页复核，故不作为新增模板证据。来源：[TNG 官方外籍员工工资指南](https://www.touchngo.com.my/assets/pdf/guideline/foreign-worker-salary-account-guide.pdf?v=1)。

### 通知类别必须分开处理

| 类别 | 官方可验证证据 | 证据不支持的推断 |
| --- | --- | --- |
| 消费者停车付款推送 | LPR Parking 帮助页明确表示离开停车场后会收到含付款金额的 push notification。[官方 LPR FAQ](https://support.tngdigital.com.my/hc/en-my/articles/42849464985113-How-do-I-check-my-LPR-Parking-transactions-on-TNG-eWallet) | 页面未提供完整正文、标题、交易号、车辆标识或 Android 字段，不能凭功能说明编写付款模板。 |
| 消费者工资收款示意 | 上述手册第 11 页提供一条收款文字和金额。[官方 Payroll Handbook](https://www.touchngo.com.my/assets/pdf/payroll-handbook/TNG_eWallet_Payroll_Handbook.pdf#page=11) | 教学示意不证明系统通知载荷相同，也不证明所有收款都是收入；自有账户转入仍需区分。 |
| 待授权交易通知 | TapSecure 帮助页说明线上交易通知用于打开批准页面，用户随后选择 Yes 或 No。[官方 TapSecure FAQ](https://support.tngdigital.com.my/hc/en-my/articles/15977704908953-How-do-I-approve-transactions-with-TapSecure-on-TNG-eWallet) | 收到授权通知不等于交易完成；金额和商户也不构成已扣款证据。 |
| 商户收款推送、语音播报 | Merchant Help Center 把 Voice Notification 定义为收到客户扫码付款时的提醒，并明确描述商户、经理与员工 Dashboard 的推送设置。[官方商户通知 FAQ](https://merchantsupport.tngdigital.com.my/hc/en-us/articles/11239511531801-What-is-Voice-Notification-and-how-do-I-set-it) | 商户角色的收款提醒不能当作消费者付款模板；同一生态中的收款也可能属于不同主体。 |
| 自动充值 | 官方说明提供自动充值成功或失败的 in-app notification。[官方自动充值 FAQ](https://support.tngdigital.com.my/hc/en-my/articles/360035649514-How-do-I-know-if-my-TNG-eWallet-has-been-auto-reloaded) | 应用内通知不保证存在 Android 系统推送；充值不是普通消费，也不能直接记作收入。 |
| SOS Balance 资格与欠款 | 官方说明资格开通会发推送；待付款提示在 eWallet 首页出现。偿还会从可用余额扣除。[官方功能页](https://www.touchngo.com.my/consumer/ewallet-features/sos-balance/)、[官方欠款 FAQ](https://support.tngdigital.com.my/hc/en-my/articles/42589658693273-How-do-I-check-if-I-have-an-outstanding-TNG-eWallet-SOS-Balance) | 资格通知、过路费垫付、欠款提醒及偿还不是同一笔普通付款状态；不能仅看到 RM 金额就记支出。 |
| 营销、优惠券 | 官方历史 RM0.80 Cashback Voucher 条款说明优惠可以通过应用横幅、推送或邮件通知。[官方优惠活动条款](https://www.touchngo.com.my/terms-conditions/rm0-80-exclusive-cashback-voucher) | 此历史资料证明营销也可使用通知渠道，不证明该活动现仍有效；优惠金额与最低消费额不是已完成交易金额。 |
| 成功转账与冲正 | 官方 DuitNow 条款第 2.4 节说明成功及冲正的交易状态可通过推送通知。[官方 DuitNow 条款 PDF，第 6 页](https://www.touchngo.com.my/assets/documents/pages/consumers/terms-and-conditions-duitnow-eng-v20082021.pdf#page=6) | 该历史条款没有完整通知模板，也不能把冲正当收入或普通付款；它不覆盖所有退款通知。 |
| 应用内收据、交易历史 | LPR 帮助页分别描述推送与交易历史入口，说明二者是不同证据载体。[官方 LPR FAQ](https://support.tngdigital.com.my/hc/en-my/articles/42849464985113-How-do-I-check-my-LPR-Parking-transactions-on-TNG-eWallet) | 带交易号、时间和成功状态的收据不能直接当作 Android 通知正文。需要独立采集通知字段。 |

### 未验证的边界

本次没有确认消费者一般扫码付款、网上付款、Visa 卡付款、普通 P2P 收款、退款的 Android 完整通知原文。也没有确认通知语言切换、不同 App 版本、通知合并或更新时的字段变化、点击通知前后的正文变化，以及系统隐私设置导致的正文隐藏行为。

官方 2025 Sustainability Impact Report 在搜索索引中可查到 SOS Balance 相关内容，但完整 PDF 约 30.6 MB，检索工具未成功打开。**未据此认定任何锁屏截图或具体通知正文已经验证。** 来源：[TNG 官方 2025 Sustainability Impact Report](https://www.touchngo.com.my/sustainability/TNG-Group-2025-Sustainability-Impact-Report.pdf)。

## 基于事实的适配建议（尚非已验证模板）

1. **先支持来源绑定与待确认。** 用官方包名精确识别来源；缺少真实通知样本时允许绑定已存在的钱包账户，收到的交易候选先进入待确认。包名只说明来源，不说明交易已经完成。
2. **不启用 TNG 专用自动入账正则。** 不把通用合成句式、工资示意、商户推送或收据文本标记为 TNG 付款支持；已识别金额只能用于待确认表单预填。
3. **把非普通交易隔离。** 充值、转账、退款、冲正、TapSecure 授权、SOS Balance、营销或奖励存在不同业务含义；在没有完整状态与资金两端信息时不得自动改变余额。验证码按现有接收层过滤规则处理。
4. **用真机通知补齐验收证据。** 后续需脱敏保留应用版本、通知语言、系统来源包名、标题、完整正文及其字段来源、通知 key 和时间、相应收据核对结果；为成功、失败、授权、重复、退款分别留样，再决定哪些模板可以自动入账。
5. **说明收集范围与隐私。** 接收来源中的消息可能含营销或敏感交易信息；待确认记录与原文的保留、导出及删除行为应跟随通知模块契约，不把原始通知发送到外部解析服务。

## 检索与维护记录

本次检索围绕 TNG 官方域名下的 payment notification、received payment、push notification、auto-reload、TapSecure、LPR Parking、SOS Balance 与官方 PDF 展开。排除了论坛、个人社交媒体、个人博客及应用商店用户评论；Google Play 只采用开发者应用身份信息。搜索摘要仅作线索，正文已访问的来源与未能打开的 PDF 已分别说明。

后续新增自动入账规则时，应在本文补充可追溯的模板证据，并在 [通知模块说明](ANDROID_NOTIFICATION_BOOKKEEPING.md) 与相应测试中明确实际支持范围。没有新的可靠样本前，本调查结论保持为**可接收并人工确认，自动模板待验证**。

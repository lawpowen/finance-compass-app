# Design QA

## 2026-08-04 关于、公开下载与自愿支持

- 设置页右上帮助入口改为可滚动关于页面，提供版本、本地数据边界、GitHub 源码/下载/问题入口及 Touch 'n Go 静态二维码。
- 390×844 必须能通过滚动访问二维码和完整免责声明；二维码保持原比例并提供收款人语义标签。
- 支持文案明确为自愿、不解锁功能、不形成服务权益；页面不得出现付款状态、支付 SDK 或自动上传财务资料的暗示。

## 2026-07-21 账户统计截止交互

1. 修复前健康度：失败。Windows Debug 账户页显示“统计截止 · 2026年7月”及向下箭头，但点击后没有菜单或状态变化。证据：`artifacts/interaction-audit/2026-07-21-cutoff/01-before-account-cutoff.png` 与 `02-before-cutoff-no-response.png`。
2. 月份选择器健康度：通过。build 35 的整行点击会打开居中底部面板，当前月有选中标记，历史月份有明确导航箭头，并提供“返回本月”和关闭入口。证据：`03-after-cutoff-picker.png`。
3. 历史汇总健康度：通过。选择 2026 年 6 月后净资产、资产、负债和资产分布同步变化，控件显示所选月份，并出现橙色“历史统计：截至 2026年6月末”提示。证据：`04-after-historical-cutoff.png`。
4. 详情与防回归健康度：通过。Widget 回归确认普通、投资、信用卡和贷款详情继承截止日期、隐藏写入操作并可返回本月；类别分组整行折叠；输入框、禁用项和只读预览不再带误导箭头。

视觉验收使用 1266×713 Windows 客户区和 390×844 Widget 回归。当前证据不能替代屏幕阅读器、完整键盘遍历、超大字体和所有桌面尺寸的专项无障碍认证。

## 2026-07-21 loan account flow

- Checked `AccountFormDialog` and `LoanDetailScreen` at a 390×844 logical-pixel viewport with the production Abyss theme.
- The loan form exposes contract principal, annual rate, term, tracking start date, payment day, repayment method, optional bank installment, optional opening outstanding balance and a compact remaining-payment preview without horizontal overflow.
- The detail summary keeps three monetary metrics width-safe, while the primary action uses the compact “记录第 N 期还款” label; the amount and principal/interest split remain visible in the confirmation dialog.
- The full installment list scrolls vertically and shows date, state, principal, interest, payment and remaining principal. Recording the first period changes its state to “已记录” and advances the action to the next period.
- A newly created loan opens its detail page and asks whether to generate the remaining plan. The persistent secondary action can generate or complete all planned principal-transfer and interest-expense pairs after a repayment account is chosen; recording an installment removes that period's planned pair.
- Automated Widget rendering detected an initial 3.2-pixel overflow in the long action label; shortening the label removed the issue. Final 390×844 regression completed without RenderFlex exceptions.
- Known follow-up: physical-device review is still required for very large font scaling and long localized institution/account names.

## Evidence

- Visual sources of truth for this correction: `artifacts/ui-reference/supplemental-budget-overview.png` and `artifacts/ui-reference/27-appearance.png`.
- Implementation captures: `artifacts/design-qa/budget-overview-390.png` and `artifacts/design-qa/appearance-carousel-390.png` at a 390×844 logical-pixel viewport.
- Combined comparison inputs: `artifacts/design-qa/budget-comparison.png` and `artifacts/design-qa/appearance-comparison.png`. Each places the reference and implementation in the same image before judging visible differences.
- State: dark mode with deterministic test data. Amounts and category names can differ from the illustrative reference, while information hierarchy, percentage semantics, color roles and interactions must match.

## Findings

- No actionable P0, P1 or P2 mismatch remains in the checked budget and appearance states.
- Budget composition now shows up to five actual categories rather than four categories plus a visually dominant “其他”. Each percentage is the category base budget divided by the month’s total allocated budget.
- Budget usage separates solid actual spend, diagonal-striped planned spend and unused capacity, matching the reference’s status grammar. Category cells use the reference’s teal-tinted grouping and remain width-safe at 390 px.
- Appearance exposes partial neighboring cards, page dots and a selected-card outline, so horizontal dragging is discoverable. Dragging changes only the local preview; the app theme changes only after the user presses the confirmation button.
- Total/transaction preview switching is functional and does not persist a theme by itself.
- Flutter’s widget-test renderer on this workstation has no CJK fallback font, so Chinese glyphs appear as squares in captures. Geometry, colors, hierarchy and interaction assertions remain inspectable; Android uses the device system font.

## Comparison history

1. The previous budget implementation combined all categories after the largest four into “其他” and used a nearly full orange strip, causing the result to diverge from the approved five-category composition.
2. The previous appearance page listed theme controls but did not expose the approved draggable carousel preview.
3. The corrected build was recaptured at 390×844 and combined with both references. The budget hierarchy, five-category composition, usage-state treatment and theme carousel now align with the approved direction.

## Primary interactions checked

- Horizontal drag between themes.
- Previewing a different theme without applying it.
- Switching the preview between dashboard and transaction content.
- Rendering the budget composition and allocation rows at 390 px without overflow.
- Opening an existing transaction from the v2 list and preserving its identity when saving.
- Navigating into a future month and automatically revealing planned transactions.
- Switching the dashboard forecast between 30 and 60 days at 390×844.
- Opening credit-card billed and unbilled rows in the same v2 transaction editor used for repayments.

## Known follow-up

- Verify Android system-font rendering, physical swipe feel, status/navigation-bar insets and native back behavior using the new Debug APK.
- Bank-specific logos and Google sign-in remain future enhancements.

## 2026-07-17 transaction and billing-cycle follow-up

- The approved screen hierarchy was retained; this correction adds missing tap targets and replaces the old repayment dialog with `TransactionComposerPage`.
- Billing labels now render actual month/day values from `CreditCardBillingPeriod` instead of hard-coded June/July/August samples.
- Widget checks at 390×844 confirm the future-month route reaches its planned transaction and the dashboard range menu updates without layout overflow.
- No P0, P1 or P2 interaction blocker remains in these paths.

## 2026-07-17 transaction action menu follow-up

- Visual source: the user-provided pre-redesign menu crop at `C:/Users/pwlaw/AppData/Local/Packages/MicrosoftWindows.Client.Core_cw5n1h2txyewy/TempState/ScreenClip/{C59239E0-A78D-4B67-A25A-654A053BC28D}.png`.
- Implementation capture: `artifacts/design-qa/transaction-menu-390.png` at 390×844 with the popup open.
- Combined comparison: `artifacts/design-qa/transaction-menu-comparison.png` places the source and implementation menu side by side before judging it.
- The implementation preserves the five-row order, leading icons, destructive divider and destructive color. Row height, menu density and corner treatment remain consistent with the old interaction while using the selected app theme.
- The menu is anchored at the transaction amount edge without replacing the full-row edit target. Automated interaction checks confirm every item is functional.
- The widget renderer lacks CJK and Material icon fonts on this workstation, so glyphs appear as squares in the implementation capture; the Android/Windows packaged app uses its normal fonts and icon assets.
- No actionable P0, P1 or P2 visual mismatch remains for this component.

final result: passed

## 2026-07-18 transaction calculation basis cards

- Visual source of truth: `C:/Users/pwlaw/.codex/generated_images/019f5ba9-2b1f-7cf3-bf9a-2da8a4633995/exec-f4136a98-86fe-402b-a555-7098de94f50d.png`, the user-selected Product Design option 2.
- Implementation capture: `artifacts/design-qa/transaction-basis-cards-390.png` at a 390×844 logical-pixel viewport with deterministic cash, credit, income, expense, transfer and planned data.
- Combined comparison: `artifacts/design-qa/transaction-basis-comparison.png`; the reference and implementation were judged in one image at the same width.
- Full-page evidence confirms the retained month navigation, grouped transaction list, equal-size lightning/add actions and bottom navigation. Focused evidence confirms the selected wide card, two compact cards, page indicator, actual/planned segment, dual metric legend and three quick-filter pills plus search.
- The implementation preserves the approved deep-navy surface, teal selection border and orange negative-value grammar. Amounts differ because the implementation capture uses test ledger data rather than the concept image's illustrative values.
- All three cards are real controls. Switching cards changes the summary and metric labels; the actual/planned segment changes the underlying status scope; account, type and category pills open real selectors. Transaction rows remain available under every calculation basis.
- No actionable P0, P1 or P2 mismatch remains. The implementation card row is slightly more compact vertically to preserve more transaction content at 390×844, without changing hierarchy or touch-target clarity.
- The Flutter widget renderer on this workstation lacks CJK and Material icon fallback fonts, so glyphs appear as boxes in automated captures. Layout, color, spacing and control state remain inspectable; packaged Android uses system glyphs.

### Iteration history

1. First capture implemented the three basis cards and status switch but retained four legacy transaction-type chips.
2. The filter row was revised to the approved account/type/category pills with a compact search control, and all pills were connected to real filters.
3. The corrected state was recaptured and recombined with the selected reference; geometry and interaction hierarchy now align at the 390 px baseline.

final result: passed

## 2026-07-18 Shopee PayLater original-statement follow-up

- The approved credit-card detail hierarchy is unchanged. The correction only changes bill-month naming and amount semantics: the month is derived from the day before statement close, and a paid historical bill keeps its original amount for reconciliation.
- The unbilled/confirmed statement amount now uses one billing period rather than the cumulative account balance. The visible July rows MYR 69.85, MYR 161.33 and MYR 82.11 therefore reconcile to MYR 313.29 instead of MYR 151.96.
- No new visual primitive, spacing rule, navigation pattern or 390 px responsive constraint was introduced. Existing historical and future-statement interaction baselines remain applicable.

final result: passed

## 2026-07-18 future confirmed credit-card statements follow-up

- The approved credit-card detail composition is retained. The existing statement picker now extends forward only when future transactions are explicitly `actual`/`settled`; those rows are labeled “已确定”, while planned rows remain excluded.
- Selecting a future statement reuses the same amount hierarchy, timeline, transaction list and return-to-current interaction. The compact top action uses “已确定” to remain width-safe at the 390 px baseline.
- Future confirmed statements display the original amount for that individual billing period rather than the cumulative account balance. Repayments affect the remaining debt state without erasing the historical amount used for reconciliation.
- A 390×844 widget test covers the future picker, confirmed transaction visibility and absence of narrow-screen overflow.

final result: passed

## 2026-07-18 transaction edit delete and signed amount follow-up

- The approved full-screen transaction editor keeps its existing hierarchy and orange primary save action. Edit mode now adds a 52 px orange-outline “删除交易” action immediately above save, so destructive intent remains separated from the primary action.
- Tapping delete opens a native confirmation dialog that states both irreversibility and account-balance restoration. Cancelling leaves the user in the same scrolled edit view; confirming returns to the originating transaction or credit-card list and refreshes it through the existing mutation provider.
- The amount field now requests a signed decimal keyboard and preserves `0.00` and negative draft values instead of displaying an empty field. No new component width, navigation pattern or 390 px overflow risk was introduced.
- Widget and repository tests cover cancel/confirm behavior, zero and negative edit saves, negative expense/transfer balance direction, and exact balance restoration after deletion.

final result: passed

## 2026-07-18 historical credit-card statement follow-up

- The existing “查看账单” control now opens a bottom-sheet month list with billing range, due date and amount; selecting a row switches the approved detail composition rather than navigating to a visually unrelated page.
- Historical mode reuses the amount hierarchy, timeline and transaction rows, replaces the current/unbilled segment with a clear historical-month label and “返回本期”, and keeps the live credit-usage bar unchanged.
- A 390×844 widget interaction test opens the picker, selects a previous cycle and confirms that only transactions from that exact period remain visible. The compact header button retains its original text-only layout to avoid narrow-screen overflow.

final result: passed

## 2026-07-18 credit commitment and recurring-status follow-up

- The approved account and credit-card layouts are unchanged; the existing amount slot now labels the account-row value as “当前欠款”, while statement-state chips and the detail header continue to describe the current billing cycle.
- Credit-limit usage reuses the approved progress component and changes only its data source: future actual installments are included, planned records are excluded.
- Recurring-generation helper copy now states that every generated month preserves the selected actual/planned state. No component dimensions, navigation, color tokens or 390 px responsive constraints changed.
- Functional and repository tests cover these semantic changes; no new visual primitive or overflow risk was introduced, so the existing 390×844 visual baseline remains applicable without a new capture.

final result: passed
# 2026-07-21 全应用交互接线审计

- 已在 Windows Debug 应用逐页检查总览、账户、交易、预算、报表、设置、规则中心、周期计划和周期规则编辑。
- 修复了周期规则编辑行、预算月份/预览、报表区间、货币格式、应用内提醒、总览明细等装饰性入口；直接输入框与纯信息行不再显示误导箭头。
- 未实现的系统通知、Google 登录、系统主题跟随和附件保持明确“计划中”并禁用。
- 新增 feature 源码静态门禁及 390×844 Widget 回归。截图证据不等同于完整无障碍认证，后续仍需专项验证屏幕阅读器和键盘遍历。
# 2026-07-21 贷款月供金额修正

- 交易列表与预计现金流以完整月供为主金额，不再把本金分项冒充月供。
- 贷款详情仍展示本金和利息拆分；实际入账时现金减少完整月供，贷款余额只减少本金。
- 旧预计本金/利息组合自动合并，实际历史记录不自动改写。
# 2026-07-21 贷款删除与补齐计数

- 删除已记录月供后，主操作必须回退到被删除的最早期次。
- 预计按钮显示精确缺口，不再写“补齐全部”。
- 缺口为零时按钮禁用并显示“预计交易已补齐”。
# 2026-07-22 build 36 现金口径与资产目标 QA

- 账户页新增旗标与资产目标摘要卡，两处均进入同一真实管理页；390×844 Widget 回归完成空状态、新增对话框、保存后目标卡和 provider 刷新，未出现布局异常。
- 预算编辑标题改为弹性居中并限制单行省略；生效月说明在 390 像素宽度换行，避免英文长类别名导致横向溢出。
- 交易快速筛选以稳定 key 覆盖账户、类型和类别，筛选后顶部金额与双指标同步变化；未来月份 RM 1,316 贷款月供在现金卡显示完整流出。
- 报表文案改为现金流入、现金流出和现金结余率；现金流出分类为无类别还款保留明确的“转账还款等未分类现金流出”，不隐藏与总额的差异。
- 本轮以 390×844 Widget 交互和最新真实 JSON 数据验证为视觉/数据 QA；未新增截图参考图，既有 0.8.0 深海主题、间距、卡片和触控尺寸基线保持不变。

# 2026-07-22 build 37 总资产目标与信用还款 QA

- 资产目标页标题下方明确写“按总资产变化”，摘要写“当前总资产”；目标算法与 UI 使用同一排除信用负债的历史序列，避免标签与数值口径不一致。
- 信用账户还款保留原顶部主按钮位置，点击后先展示同币种现金账户底部列表，再显示金额确认框；390×844 Widget 回归覆盖选择、改额、确认及双方余额刷新。
- 历史截止状态继续禁用还款；无同币种现金账户时显示明确提示，不展示无法完成的空确认框。

# 2026-07-22 build 38 月度资金需求 QA

- 修改前的交易页把消费、现金和承诺拆成三张口径卡，用户浏览未来月份时没有一个可直接备款的全月总额；证据保存于 `artifacts/audit/transaction-funding-needs/01-before.jpg`。
- 修改后在“已发生/包含预计”下方新增高优先级“月需准备现金”卡，橙色主金额与四项拆分保持既有深海主题、字号、圆角和颜色语义；Windows 1266×713 实机没有横向溢出，证据保存于 `artifacts/audit/transaction-funding-needs/02-after-august.jpg`。
- 卡片明确说明全月汇总不受下方筛选影响、已包含还款不重复计算。语义标签朗读总额、已记录现金流出和尚未安排还款；截图不能替代屏幕阅读器、键盘焦点和触控目标专项认证。

# 2026-07-22 build 39 资金需求卡片整合 QA

- 独立资金需求大卡已移除，避免重复展示同一金额并把交易列表继续向下推；顶部三卡改名为“实际消费”“实际现金”“信用/贷款”，中间卡以“需准备现金”为选中副标题，沿用既有宽窄切换、深海配色和橙色现金流出语义。
- 选中中间卡时，原两项解释位显示“已知流出/尚未安排”，下方仅增加一行到期信用、到期贷款、已包含和筛选边界说明；未选中时不显示额外说明。
- 390×844 Widget 回归覆盖未来月份、MYR 1,556 总额、独立大卡不存在及解释指标；长金额解释使用弹性缩放，不产生 RenderFlex 溢出。
- Windows 1266×713 Debug 实机复核 2026 年 8 月：选中“实际现金”后显示 MYR 7,206、“已知流出 MYR 3,621”“尚未安排 MYR 3,585”及单行到期拆分，交易列表不再被第二张大卡下推。
